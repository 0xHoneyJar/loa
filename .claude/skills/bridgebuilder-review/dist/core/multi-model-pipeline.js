/**
 * MultiModelPipeline — orchestrates parallel multi-model reviews with consensus scoring.
 *
 * Executes N model reviews in parallel via Promise.allSettled(), scores findings
 * using dual-track consensus (convergence + diversity), and posts per-model
 * comments followed by a consensus summary.
 */
import { appendFile, mkdir } from "node:fs/promises";
import path from "node:path";
import { summarizeReviewVerdict, combineReviewVerdicts, hasApprovedReviewQuality } from "./review-verdict.js";
import { scoreFindings } from "./scoring.js";
import { createAdapter } from "../adapters/adapter-factory.js";
import { PROVIDER_API_KEY_ENV, validateApiKeys } from "../config.js";
/**
 * Per-model timeout derivation — reasoning-class predicate (multi-provider).
 *
 * History:
 *   - cycle-100 sprint-bug-143 (#789a) introduced the 1_800_000ms (30-min)
 *     budget for OpenAI `gpt-*-pro` after gpt-5.5-pro hung past 900s on a
 *     95k-token diff (most of the budget is spent on internal reasoning
 *     before any visible tokens emit).
 *   - cycle-111 sprint-bug-165 (#921) extended the predicate to the rest
 *     of the BB triad. Claude Opus + Gemini Pro are reasoning-class too —
 *     they were silently SIGTERMing at the 300_000ms ceiling on realistic
 *     BB prompts (KF-010, recurrence ≥20× by 2026-05-16). Direct provider
 *     API health was fine; the predicate scope was the bug.
 *
 * Detection by model_id pattern is intentionally narrow — we want the longer
 * budget ONLY where it's needed, not as a blanket increase. To add a new
 * reasoning-class model: extend the relevant provider's branch. Non-reasoning
 * variants on the same provider (e.g. claude-sonnet-4-6, gemini-3.1-flash,
 * gpt-5.3-codex) MUST remain on the tier-based ladder.
 *
 * 1_800_000ms = 30min, comfortably above observed 900-1100s end-to-end on
 * large reviews while keeping operator-visible latency bounded.
 */
function isReasoningClass(provider, modelId) {
    if (/-headless$/i.test(modelId))
        return true;
    if (provider === "openai" && /^gpt-\d+(\.\d+)?-pro$/i.test(modelId))
        return true;
    if (provider === "anthropic" && /opus/i.test(modelId))
        return true;
    if (provider === "google" && /^gemini-\d+(\.\d+)?-pro/i.test(modelId))
        return true;
    return false;
}
export function deriveTimeoutMs(provider, modelId, config) {
    if (isReasoningClass(provider, modelId)) {
        return 1_800_000; // 30 minutes
    }
    // Existing tiered ladder for non-reasoning paths.
    return config.maxInputTokens > 100_000 ? 300_000 :
        config.maxInputTokens > 50_000 ? 180_000 :
            120_000;
}
/**
 * Guard helper: returns true when a PR comment should be posted, and logs
 * a warning if postComment is missing in non-dry-run mode.
 *
 * Addresses bug-20260413-i464-9d4f51 / Issue #464 A2: HITL could not
 * distinguish "comment posting unsupported" from "comment posting failed".
 */
export function shouldPostComment(poster, config, logger, context) {
    if (config.dryRun)
        return false;
    if (!poster.postComment) {
        logger.warn(`[multi-model] Poster does not implement postComment; ${context} skipped`);
        return false;
    }
    return true;
}
/**
 * Execute a multi-model review for a single PR item.
 *
 * @param item - The PR review item
 * @param systemPrompt - The system prompt (same for all models)
 * @param userPrompt - The user prompt (same for all models)
 * @param config - Full bridgebuilder config (includes multiModel)
 * @param adapters - Shared adapters (poster, sanitizer, logger)
 * @returns Multi-model review result with per-model responses and consensus
 */
export async function executeMultiModelReview(item, systemPrompt, userPrompt, config, adapters, enrichment) {
    const multiConfig = config.multiModel;
    const { poster, sanitizer, logger } = adapters;
    // Validate API keys
    const keyStatus = validateApiKeys(multiConfig);
    if (multiConfig.api_key_mode === "strict" && keyStatus.missing.length > 0) {
        throw new Error(`Strict mode: missing API keys for providers: ${keyStatus.missing.map((m) => m.provider).join(", ")}`);
    }
    // Create adapters for available providers
    const modelAdapters = [];
    for (const entry of keyStatus.valid) {
        const envVar = PROVIDER_API_KEY_ENV[entry.provider];
        const apiKey = envVar ? process.env[envVar] : undefined;
        if (!apiKey)
            continue;
        const costRates = multiConfig.cost_rates?.[entry.provider];
        const adapter = createAdapter({
            provider: entry.provider,
            modelId: entry.modelId,
            apiKey,
            timeoutMs: deriveTimeoutMs(entry.provider, entry.modelId, config),
            costRates,
        });
        modelAdapters.push({
            provider: entry.provider,
            modelId: entry.modelId,
            adapter,
        });
    }
    if (modelAdapters.length === 0) {
        throw new Error("No models available for multi-model review (all API keys missing)");
    }
    // Limit concurrency
    const concurrency = Math.min(modelAdapters.length, multiConfig.max_concurrency ?? 3);
    logger.info("[multi-model] Starting parallel review", {
        models: modelAdapters.map((m) => `${m.provider}/${m.modelId}`),
        concurrency,
    });
    // Execute reviews in parallel with concurrency limit
    const request = {
        systemPrompt,
        userPrompt,
        maxOutputTokens: config.maxOutputTokens,
    };
    const results = await executeWithConcurrency(modelAdapters, async (ma) => {
        logger.info(`[multi-model:${ma.provider}] Starting review...`);
        const startMs = Date.now();
        const response = await ma.adapter.generateReview(request);
        const latencyMs = Date.now() - startMs;
        logger.info(`[multi-model:${ma.provider}] Complete`, {
            latencyMs,
            inputTokens: response.inputTokens,
            outputTokens: response.outputTokens,
        });
        return response;
    }, concurrency);
    // Process results
    const modelResults = [];
    const findingsPerModel = [];
    for (let i = 0; i < modelAdapters.length; i++) {
        const ma = modelAdapters[i];
        const result = results[i];
        if (result.status === "fulfilled") {
            const response = result.value;
            const reviewVerdict = summarizeReviewVerdict(response.content);
            if (!hasApprovedReviewQuality(response))
                reviewVerdict.mergeBlocked = true;
            // Sanitize
            const sanitized = sanitizer.sanitize(response.content);
            const cleanContent = sanitized.safe ? response.content : sanitized.sanitizedContent;
            // Extract findings from content
            const findings = extractFindingsFromContent(cleanContent);
            findingsPerModel.push({
                provider: ma.provider,
                model: ma.modelId,
                findings,
            });
            // Post per-model comment
            let posted = false;
            if (shouldPostComment(poster, config, logger, "per-model comment") && poster.postComment) {
                try {
                    const commentBody = formatModelComment(ma.provider, ma.modelId, cleanContent, i + 1, modelAdapters.length);
                    posted = await poster.postComment({
                        owner: item.owner,
                        repo: item.repo,
                        prNumber: item.pr.number,
                        body: commentBody,
                    });
                }
                catch (err) {
                    logger.warn(`[multi-model:${ma.provider}] Failed to post comment`, {
                        error: err.message,
                    });
                }
            }
            modelResults.push({
                provider: ma.provider,
                model: ma.modelId,
                response,
                reviewVerdict,
                posted,
            });
        }
        else {
            const error = {
                code: "PROVIDER_ERROR",
                message: result.reason instanceof Error ? result.reason.message : String(result.reason),
                category: "transient",
                retryable: true,
                source: "llm",
            };
            logger.warn(`[multi-model:${ma.provider}] Review failed`, {
                error: error.message,
            });
            modelResults.push({
                provider: ma.provider,
                model: ma.modelId,
                error,
                posted: false,
            });
        }
    }
    // Score findings across models
    const consensus = scoreFindings(findingsPerModel, multiConfig.consensus.scoring_thresholds);
    logger.info("[multi-model] Consensus scoring complete", {
        high_consensus: consensus.stats.high_consensus,
        disputed: consensus.stats.disputed,
        blocker: consensus.stats.blocker,
        unique: consensus.stats.unique,
    });
    // One qualification drives clearance, the posted quality/counts and telemetry.
    const cohort = qualifyReviewCohort(multiConfig.models, modelResults);
    let consensusBody = formatConsensusSummary(consensus, modelAdapters);
    if (enrichment && findingsPerModel.length > 0 && modelAdapters.length > 0) {
        try {
            logger.info("[multi-model] Generating enriched consensus review...");
            const enrichedContent = await generateEnrichedConsensusReview(item, consensus, modelAdapters, config, enrichment, adapters.sanitizer, adapters.logger);
            if (enrichedContent) {
                // Prepend stats to enriched prose for quick-scan visibility
                consensusBody = formatEnrichedConsensusSummary(consensus, modelAdapters, enrichedContent);
                logger.info("[multi-model] Enrichment complete", {
                    enrichedBytes: enrichedContent.length,
                });
            }
        }
        catch (err) {
            logger.warn("[multi-model] Enrichment failed, using stats-only summary", {
                error: err.message,
            });
        }
    }
    // Enrichment can add a blocker but cannot supply approval for missing reviews.
    const enrichedVerdict = summarizeReviewVerdict(consensusBody);
    if (enrichedVerdict.verdict === "REQUEST_CHANGES") {
        cohort.reviewVerdict = combineReviewVerdicts([cohort.reviewVerdict, enrichedVerdict]);
    }
    consensusBody = formatVerdictQualityHeader(cohort) + consensusBody;
    await emitDegradedVerdictTrajectory(item, cohort, { repoRoot: config.repoRoot });
    // Post even a partial cohort's summary: its configured denominator matters.
    let overallPosted = false;
    if (shouldPostComment(poster, config, logger, "consensus summary") &&
        poster.postComment &&
        multiConfig.models.length > 1) {
        try {
            overallPosted = await poster.postComment({
                owner: item.owner,
                repo: item.repo,
                prNumber: item.pr.number,
                body: consensusBody,
            });
        }
        catch (err) {
            logger.warn("[multi-model] Failed to post consensus summary", {
                error: err.message,
            });
        }
    }
    const combinedContent = modelResults
        .filter((r) => r.response)
        .map((r) => r.response.content)
        .join("\n\n---\n\n");
    return {
        modelResults,
        consensus,
        posted: overallPosted || modelResults.some((r) => r.posted),
        combinedContent,
        reviewVerdict: cohort.reviewVerdict,
    };
}
/**
 * Execute async tasks with a concurrency limit.
 */
async function executeWithConcurrency(items, fn, concurrency) {
    if (items.length <= concurrency) {
        return Promise.allSettled(items.map(fn));
    }
    const results = new Array(items.length);
    let nextIndex = 0;
    async function worker() {
        while (nextIndex < items.length) {
            const index = nextIndex++;
            try {
                results[index] = { status: "fulfilled", value: await fn(items[index]) };
            }
            catch (reason) {
                results[index] = { status: "rejected", reason };
            }
        }
    }
    const workers = Array.from({ length: Math.min(concurrency, items.length) }, () => worker());
    await Promise.all(workers);
    return results;
}
/**
 * Extract findings from review content by parsing the bridge-findings JSON block.
 * Exported for testing — see bug-20260413-9f9b39.
 */
export function extractFindingsFromContent(content) {
    const match = content.match(/<!--\s*bridge-findings-start\s*-->\s*```json\s*([\s\S]*?)```\s*<!--\s*bridge-findings-end\s*-->/);
    if (!match)
        return [];
    try {
        const parsed = JSON.parse(match[1]);
        if (parsed.findings && Array.isArray(parsed.findings)) {
            return parsed.findings;
        }
    }
    catch {
        // Malformed findings — return empty
    }
    return [];
}
/**
 * Format a per-model comment with continuation numbering.
 */
/**
 * cycle-109 Sprint 2 T2.6 — render an operator-facing verdict_quality
 * header for the BB PR comment (FR-2.8 surface).
 *
 * Takes the ReviewCohortQualification shared with the handoff and trajectory.
 * Always renders the quality band, qualified/expected voice count, and final
 * review verdict with an explicit blocked marker when applicable.
 *
 * Missing or legacy quality evidence remains visible as DEGRADED or FAILED.
 * An APPROVED quality band describes evidence health; a COMMENT or
 * REQUEST_CHANGES review verdict still blocks merge clearance.
 */
/**
 * cycle-109 Sprint 4 T4.8 — operator-facing chunked-review annotation
 * for the BB PR comment. Per FR-2.8 + SDD §5.4 IMP-006: when the
 * substrate dispatched through the chunking package, the PR comment
 * header surfaces the chunk count + per-chunk degradation distinctly
 * from the overall verdict_quality status banner.
 *
 * Rendered above formatVerdictQualityHeader so operators see the
 * "chunked: 5 chunks reviewed" annotation BEFORE the verdict banner.
 * Returns empty string when no chunked review occurred.
 */
export function formatChunkedReviewAnnotation(perModelResults) {
    const chunked = perModelResults.filter((r) => r.chunkedReview?.chunked === true);
    if (chunked.length === 0)
        return "";
    // Aggregate counts across the per-model results
    const totalChunks = chunked.reduce((acc, r) => acc + (r.chunkedReview?.chunks_reviewed ?? 0), 0);
    const totalDropped = chunked.reduce((acc, r) => acc + (r.chunkedReview?.chunks_dropped ?? 0), 0);
    const totalWithFindings = chunked.reduce((acc, r) => acc + (r.chunkedReview?.chunks_with_findings ?? 0), 0);
    const anyCrossChunkPass = chunked.some((r) => r.chunkedReview?.cross_chunk_pass === true);
    const lines = [
        `**Chunked review**: ${chunked.length} model${chunked.length > 1 ? "s" : ""} dispatched through chunking package (KF-002 layer-1 closure)`,
        `- Total chunks reviewed: ${totalChunks}` +
            (totalDropped > 0 ? ` (⚠ ${totalDropped} dropped)` : "") +
            ` — ${totalWithFindings} produced findings`,
    ];
    if (anyCrossChunkPass) {
        lines.push("- Cross-chunk pass invoked (boundary-spanning findings)");
    }
    return lines.join("\n") + "\n\n";
}
/** Qualify the configured cohort once, including missing and duplicated voices. */
export function qualifyReviewCohort(expected, results) {
    const requestedIds = expected.map((r) => `${r.provider}:${r.model_id}`);
    const resultIds = results.map((r) => `${r.provider}:${r.model}`);
    const resolvedIds = results.map((r) => `${r.response?.provider ?? r.provider}:${r.response?.model ?? ""}`);
    const approved = results.map((r) => hasApprovedReviewQuality(r.response));
    const voices = results.map((r, i) => approved[i]
        ? r.response.verdictQuality.voices_succeeded_ids.map((id) => `${r.response?.provider ?? r.provider}:${id}`) : []);
    const allVoices = voices.flat();
    const decisions = results.map((r) => r.reviewVerdict ?? summarizeReviewVerdict(r.response?.content ?? ""));
    const count = (ids, id) => ids.filter((value) => value === id).length;
    const reasons = [];
    const degradedLegs = new Set();
    const reject = (reason, id) => {
        reasons.push(reason);
        degradedLegs.add(id);
    };
    let qualified = 0;
    for (const id of requestedIds) {
        if (!resultIds.includes(id))
            reject("missing_response", id);
    }
    for (let i = 0; i < results.length; i++) {
        const result = results[i];
        const id = resultIds[i];
        const reason = result.error || result.response?.errorState ? "review_failed"
            : !result.response ? "missing_response"
                : !approved[i] ? "unqualified_quality"
                    : decisions[i].verdict === "UNKNOWN" ? "unknown_verdict"
                        : !result.response.model?.trim() ? "missing_model_identity"
                            : count(requestedIds, id) !== 1 || count(resultIds, id) !== 1 ? "invalid_requested_identity"
                                : count(resolvedIds, resolvedIds[i]) !== 1 ? "duplicate_resolved_identity"
                                    : voices[i].some((voice) => count(allVoices, voice) !== 1) ? "duplicate_voice_identity"
                                        : undefined;
        if (reason)
            reject(reason, id);
        else
            qualified++;
    }
    if (expected.length === 0)
        reasons.push("empty_cohort");
    const failed = results.length === 0 || results.some((r) => r.error || r.response?.errorState || r.response?.verdictQuality?.status === "FAILED");
    const band = failed ? "FAILED" : reasons.length > 0 ? "DEGRADED" : "APPROVED";
    const reviewVerdict = combineReviewVerdicts(decisions);
    if (band !== "APPROVED")
        reviewVerdict.mergeBlocked = true;
    // Unqualified metadata is not trusted as a structure. Retain only well-typed
    // drop diagnostics for the existing trajectory schema.
    const drops = results.flatMap((r) => {
        const dropped = r.response?.verdictQuality?.voices_dropped;
        return Array.isArray(dropped) ? dropped.filter((d) => d && typeof d.voice === "string" && typeof d.reason === "string" && Number.isInteger(d.exit_code)) : [];
    });
    return {
        band, expected: expected.length, qualified, reviewVerdict,
        degradationReason: drops[0]?.reason ?? reasons[0] ?? "",
        degradedLegs: drops.length ? drops.map((d) => d.voice) : [...degradedLegs],
        modelExitCode: drops[0]?.exit_code ?? null,
    };
}
export function formatVerdictQualityHeader(cohort) {
    const { band, qualified, expected, reviewVerdict } = cohort;
    let banner;
    if (band === "FAILED") {
        banner = `❌ FAILED — ${qualified}/${expected} voices qualified; verdict unsafe`;
    }
    else if (band === "DEGRADED") {
        banner = `⚠ DEGRADED — ${qualified}/${expected} voices qualified`;
    }
    else {
        banner = `✓ APPROVED — ${qualified}/${expected} voices, chain ok`;
    }
    // A healthy review may legitimately request changes. Make that semantic
    // decision explicit beside the cohort's evidence quality.
    return `**Verdict Quality**: ${banner}\n` +
        `**Merge Clearance**: ${reviewVerdict.verdict}${reviewVerdict.mergeBlocked ? " — blocked" : ""}\n\n`;
}
/**
 * Append a degraded-verdict trajectory record when BB's aggregate multi-model
 * verdict band is DEGRADED or FAILED. Missing evidence is unqualified; only
 * an APPROVED cohort skips this record.
 *
 * The record is the SAME shape the 3 bash gate writers emit (adversarial-
 * review.sh, red-team-code-vs-design.sh, flatline-orchestrator.sh via
 * degraded-verdict-lib.sh) into the SAME date-sharded trajectory file, so a
 * downstream reader sees one homogeneous channel regardless of runtime.
 *
 * Scope (per bd-bb-degraded-verdict-ts-b5bu): trajectory-record emit only.
 * Paging is deferred — the bash writers page via push-notify-lib.sh, but BB
 * already surfaces degradation directly in the PR comment via
 * formatVerdictQualityHeader, a stronger operator-visible signal than a page.
 *
 * Fire-and-forget: never throws. A write failure is swallowed (mirrors the
 * bash lib's "every function ALWAYS returns 0" contract and the appendFile
 * try/catch precedent in depth-checker.ts). Unlike the bash lib this uses a
 * single appendFile (no flock): a single-line JSON append is one write()
 * syscall, atomic on POSIX under the OS write limit — adequate given BB runs
 * one PR per invocation, not concurrent Node writers on one host.
 */
export async function emitDegradedVerdictTrajectory(item, cohort, opts) {
    const { band } = cohort;
    if (band !== "DEGRADED" && band !== "FAILED")
        return;
    const gate = opts?.gate ?? "bridgebuilder:multi-model";
    const sprintId = `${item.owner}/${item.repo}#${item.pr.number}`;
    const record = {
        gate,
        verdict_band: band,
        degradation_reason: cohort.degradationReason,
        ...(cohort.degradedLegs.length ? { degraded_legs: cohort.degradedLegs } : {}),
        model_exit_code: cohort.modelExitCode,
        sprint_id: sprintId,
        ts: new Date().toISOString(),
    };
    const dir = process.env.LOA_DEGRADED_VERDICT_DIR ??
        path.join(opts?.repoRoot ?? process.cwd(), "grimoires/loa/a2a/trajectory");
    const dateShard = new Date().toISOString().slice(0, 10);
    const file = path.join(dir, `degraded-verdict-${dateShard}.jsonl`);
    try {
        await mkdir(dir, { recursive: true });
        await appendFile(file, JSON.stringify(record) + "\n");
    }
    catch {
        // Side-channel: never change the caller's control flow on a write failure.
    }
}
function formatModelComment(provider, modelId, content, index, total) {
    const header = total > 1
        ? `**[${index}/${total + 1}] Review by ${provider} (${modelId})**\n\n`
        : `**Review by ${provider} (${modelId})**\n\n`;
    return header + content;
}
/**
 * Format the consensus summary comment.
 */
function formatConsensusSummary(result, models) {
    const lines = [];
    const total = models.length + 1; // models + this summary
    lines.push(`**[${total}/${total}] Multi-Model Consensus Summary**`);
    lines.push("");
    lines.push(`Models: ${models.map((m) => `${m.provider}/${m.modelId}`).join(", ")}`);
    lines.push("");
    // Stats table
    lines.push("| Classification | Count |");
    lines.push("|---|---|");
    lines.push(`| HIGH_CONSENSUS | ${result.stats.high_consensus} |`);
    lines.push(`| DISPUTED | ${result.stats.disputed} |`);
    lines.push(`| BLOCKER | ${result.stats.blocker} |`);
    lines.push(`| LOW_VALUE | ${result.stats.low_value} |`);
    lines.push(`| Unique perspectives | ${result.stats.unique} |`);
    lines.push("");
    // BLOCKER findings
    const blockers = result.convergence.filter((f) => f.classification === "BLOCKER");
    if (blockers.length > 0) {
        lines.push("### Blockers");
        for (const b of blockers) {
            lines.push(`- **${b.finding.title}** (${b.finding.file ?? "general"}) — agreed by ${b.agreeing_models.join(", ")}`);
        }
        lines.push("");
    }
    // HIGH_CONSENSUS findings
    const highConsensus = result.convergence.filter((f) => f.classification === "HIGH_CONSENSUS");
    if (highConsensus.length > 0) {
        lines.push("### High Consensus");
        for (const h of highConsensus) {
            const models = h.agreeing_models.length > 1 ? ` (${h.agreeing_models.join(", ")})` : "";
            lines.push(`- **${h.finding.severity}**: ${h.finding.title}${models}`);
        }
        lines.push("");
    }
    // DISPUTED findings
    const disputed = result.convergence.filter((f) => f.classification === "DISPUTED");
    if (disputed.length > 0) {
        lines.push("### Disputed");
        for (const d of disputed) {
            lines.push(`- **${d.finding.title}** — score delta: ${d.score_delta} (${d.agreeing_models.join(" vs ")})`);
        }
        lines.push("");
    }
    return lines.join("\n");
}
/**
 * Generate a human-readable enriched review from consensus findings (Option C).
 *
 * Takes the scored consensus findings and invokes ONE designated "writer" model
 * (the first primary model in config.multiModel.models, or first available) to
 * produce a Pass-2 enriched review with metaphors, FAANG parallels, and teachable
 * moments. This closes the HITL readability gap — multi-model reviews now
 * include the educational prose that single-model reviews already have.
 */
async function generateEnrichedConsensusReview(item, consensus, modelAdapters, config, enrichment, sanitizer, logger) {
    // Pick writer: first model with role=primary in config, else first available
    const multiConfig = config.multiModel;
    const primaryEntry = multiConfig.models.find((m) => m.role === "primary");
    const writerTarget = primaryEntry ?? multiConfig.models[0];
    const writer = modelAdapters.find((m) => m.provider === writerTarget.provider && m.modelId === writerTarget.model_id) ?? modelAdapters[0];
    if (!writer) {
        logger.warn("[multi-model] No writer model available for enrichment");
        return null;
    }
    // Build findings JSON from consensus (convergence track)
    // Preserve only the canonical finding from each group
    const findingsForEnrichment = consensus.convergence.map((scored) => ({
        ...scored.finding,
        // Add consensus metadata as non-enriched fields
        agreeing_models: scored.agreeing_models,
        consensus_classification: scored.classification,
    }));
    const findingsJSON = JSON.stringify({ schema_version: 1, findings: findingsForEnrichment }, null, 2);
    const { systemPrompt, userPrompt } = enrichment.template.buildEnrichmentPrompt({
        findingsJSON,
        item,
        persona: enrichment.persona,
        // A5 (#464): pass lore entries through; template uses them only when
        // depth_5.lore_active_weaving is enabled in multiModelConfig.
        loreEntries: enrichment.loreEntries,
        multiModelConfig: multiConfig,
    });
    logger.info(`[multi-model:enrichment] Writer: ${writer.provider}/${writer.modelId}`);
    const response = await writer.adapter.generateReview({
        systemPrompt,
        userPrompt,
        maxOutputTokens: config.maxOutputTokens,
    });
    // Sanitize writer output
    const sanitized = sanitizer.sanitize(response.content);
    return sanitized.safe ? response.content : sanitized.sanitizedContent;
}
/**
 * Format enriched consensus summary: stats banner + writer-generated prose.
 */
function formatEnrichedConsensusSummary(result, models, enrichedContent) {
    const lines = [];
    const total = models.length + 1;
    lines.push(`**[${total}/${total}] Multi-Model Consensus Review**`);
    lines.push("");
    lines.push(`Models: ${models.map((m) => `${m.provider}/${m.modelId}`).join(", ")}`);
    lines.push("");
    // Quick-scan stats (collapsible)
    lines.push("<details>");
    lines.push("<summary>Consensus Statistics</summary>");
    lines.push("");
    lines.push("| Classification | Count |");
    lines.push("|---|---|");
    lines.push(`| HIGH_CONSENSUS | ${result.stats.high_consensus} |`);
    lines.push(`| DISPUTED | ${result.stats.disputed} |`);
    lines.push(`| BLOCKER | ${result.stats.blocker} |`);
    lines.push(`| LOW_VALUE | ${result.stats.low_value} |`);
    lines.push(`| Unique perspectives | ${result.stats.unique} |`);
    lines.push("");
    lines.push("</details>");
    lines.push("");
    lines.push("---");
    lines.push("");
    lines.push(enrichedContent);
    return lines.join("\n");
}
//# sourceMappingURL=multi-model-pipeline.js.map