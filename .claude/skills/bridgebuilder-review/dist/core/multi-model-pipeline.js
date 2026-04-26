import { scoreFindings } from "./scoring.js";
import { createAdapter } from "../adapters/adapter-factory.js";
import { PROVIDER_API_KEY_ENV, validateApiKeys } from "../config.js";
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
            timeoutMs: config.maxInputTokens > 100_000 ? 300_000 : 120_000,
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
    // Pass-2 enrichment: generate human-readable consensus review (Option C).
    // When enrichment context provided, the first primary model writes a prose
    // review over the consensus findings. Falls back to stats-only if enrichment
    // fails or is disabled.
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
    // Post consensus summary comment
    let overallPosted = false;
    if (shouldPostComment(poster, config, logger, "consensus summary") &&
        poster.postComment &&
        findingsPerModel.length > 1) {
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