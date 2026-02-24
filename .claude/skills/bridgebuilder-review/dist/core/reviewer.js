import { GitProviderError } from "../ports/git-provider.js";
import { LLMProviderError } from "../ports/llm-provider.js";
import { truncateFiles, progressiveTruncate, getTokenBudget, } from "./truncation.js";
const CRITICAL_PATTERN = /\b(critical|security vulnerability|sql injection|xss|secret leak|must fix)\b/i;
const REFUSAL_PATTERN = /\b(I cannot|I'm unable|I can't|as an AI|I apologize)\b/i;
/** Patterns that indicate an LLM token rejection (Task 1.8). */
const TOKEN_REJECTION_PATTERNS = [
    "prompt_too_large",
    "maximum context length",
    "context_length_exceeded",
    "token limit",
];
function classifyEvent(content) {
    return CRITICAL_PATTERN.test(content) ? "REQUEST_CHANGES" : "COMMENT";
}
function isValidResponse(content) {
    if (!content || content.length < 50)
        return false;
    if (REFUSAL_PATTERN.test(content))
        return false;
    if (!content.includes("## Summary") || !content.includes("## Findings"))
        return false;
    // Reject code-only responses (no prose)
    const nonCodeContent = content.replace(/```[\s\S]*?```/g, "").trim();
    if (nonCodeContent.length < 30)
        return false;
    return true;
}
function makeError(code, message, source, category, retryable) {
    return { code, message, category, retryable, source };
}
function isTokenRejection(err) {
    // Primary: typed error code from LLM adapter (BB-F3)
    if (err instanceof LLMProviderError && err.code === "TOKEN_LIMIT") {
        return true;
    }
    // Fallback: string matching for unknown/untyped errors
    const message = err instanceof Error ? err.message.toLowerCase() : String(err).toLowerCase();
    return TOKEN_REJECTION_PATTERNS.some((p) => message.includes(p));
}
export class ReviewPipeline {
    template;
    context;
    git;
    poster;
    llm;
    sanitizer;
    logger;
    persona;
    config;
    now;
    constructor(template, context, git, poster, llm, sanitizer, logger, persona, config, now = Date.now) {
        this.template = template;
        this.context = context;
        this.git = git;
        this.poster = poster;
        this.llm = llm;
        this.sanitizer = sanitizer;
        this.logger = logger;
        this.persona = persona;
        this.config = config;
        this.now = now;
    }
    async run(runId) {
        const startTime = new Date().toISOString();
        const startMs = this.now();
        const results = [];
        // Preflight: check GitHub API connectivity and quota
        const preflight = await this.git.preflight();
        if (preflight.remaining < 100) {
            this.logger.warn("GitHub API quota too low, skipping run", {
                remaining: preflight.remaining,
            });
            return this.buildSummary(runId, startTime, results);
        }
        // Preflight: check each repo is accessible, track results
        const accessibleRepos = new Set();
        for (const { owner, repo } of this.config.repos) {
            const repoPreflight = await this.git.preflightRepo(owner, repo);
            if (!repoPreflight.accessible) {
                this.logger.error("Repository not accessible, skipping", {
                    owner,
                    repo,
                });
                continue;
            }
            accessibleRepos.add(`${owner}/${repo}`);
        }
        if (accessibleRepos.size === 0) {
            this.logger.warn("No accessible repositories; ending run");
            return this.buildSummary(runId, startTime, results);
        }
        // Load persisted context
        await this.context.load();
        // Resolve review items
        const items = await this.template.resolveItems();
        // Process each item sequentially
        for (const item of items) {
            // Runtime limit check
            if (this.now() - startMs > this.config.maxRuntimeMinutes * 60_000) {
                results.push(this.skipResult(item, "runtime_limit"));
                continue;
            }
            // Skip items for inaccessible repos
            const repoKey = `${item.owner}/${item.repo}`;
            if (!accessibleRepos.has(repoKey)) {
                results.push(this.skipResult(item, "repo_inaccessible"));
                continue;
            }
            const result = await this.processItem(item);
            results.push(result);
        }
        return this.buildSummary(runId, startTime, results);
    }
    async processItem(item) {
        const { owner, repo, pr } = item;
        try {
            // Step 1: Check if changed
            const changed = await this.context.hasChanged(item);
            if (!changed) {
                return this.skipResult(item, "unchanged");
            }
            // Step 2: Check for existing review
            const existing = await this.poster.hasExistingReview(owner, repo, pr.number, pr.headSha);
            if (existing) {
                return this.skipResult(item, "already_reviewed");
            }
            // Step 3: Claim review slot
            const claimed = await this.context.claimReview(item);
            if (!claimed) {
                return this.skipResult(item, "claim_failed");
            }
            // Step 3.5: Incremental review detection (V3-1)
            let incrementalBanner;
            let effectiveItem = item;
            if (!this.config.forceFullReview) {
                const lastSha = await this.context.getLastReviewedSha(item);
                if (lastSha && lastSha !== pr.headSha) {
                    try {
                        const compare = await this.git.getCommitDiff(owner, repo, lastSha, pr.headSha);
                        if (compare.filesChanged.length > 0) {
                            const deltaFiles = item.files.filter((f) => compare.filesChanged.includes(f.filename));
                            if (deltaFiles.length > 0 && deltaFiles.length < item.files.length) {
                                effectiveItem = { ...item, files: deltaFiles };
                                incrementalBanner = `[Incremental: reviewing ${deltaFiles.length} files changed since ${lastSha.slice(0, 7)}]`;
                                this.logger.info("Incremental review mode", {
                                    owner,
                                    repo,
                                    pr: pr.number,
                                    lastSha: lastSha.slice(0, 7),
                                    totalFiles: item.files.length,
                                    deltaFiles: deltaFiles.length,
                                });
                            }
                        }
                    }
                    catch {
                        // Force push or deleted SHA — fall back to full review
                        this.logger.warn("Incremental diff failed (force push?), falling back to full review", {
                            owner,
                            repo,
                            pr: pr.number,
                            lastSha: lastSha.slice(0, 7),
                        });
                    }
                }
            }
            // Two-pass gate: route to processItemTwoPass() when configured (SDD 3.4)
            if (this.config.reviewMode === "two-pass") {
                return this.processItemTwoPass(item, effectiveItem, incrementalBanner);
            }
            // Step 4: Build prompt (includes truncation + Loa filtering)
            const { systemPrompt, userPrompt, allExcluded, loaBanner } = this.template.buildPromptWithMeta(effectiveItem, this.persona);
            // Step 4a: Handle all-files-excluded by Loa filtering (IMP-004)
            if (allExcluded) {
                this.logger.info("All files excluded by Loa filtering", {
                    owner,
                    repo,
                    pr: pr.number,
                });
                if (!this.config.dryRun) {
                    await this.poster.postReview({
                        owner,
                        repo,
                        prNumber: pr.number,
                        headSha: pr.headSha,
                        body: "All changes in this PR are Loa framework files. No application code changes to review. Override with `loa_aware: false` to review framework changes.",
                        event: "COMMENT",
                    });
                }
                return this.skipResult(item, "all_files_excluded");
            }
            // Step 4.5: Inject incremental review banner if applicable (V3-1)
            const finalUserPrompt0 = incrementalBanner
                ? `${incrementalBanner}\n\n${userPrompt}`
                : userPrompt;
            // Step 5: Token estimation guard with progressive truncation.
            const { coefficient } = getTokenBudget(this.config.model);
            const systemTokens = Math.ceil(systemPrompt.length * coefficient);
            const userTokens = Math.ceil(finalUserPrompt0.length * coefficient);
            const estimatedTokens = systemTokens + userTokens;
            // Pre-flight prompt size report (SKP-004: component breakdown)
            this.logger.info("Prompt estimate", {
                owner,
                repo,
                pr: pr.number,
                estimatedTokens,
                systemTokens,
                userTokens,
                budget: this.config.maxInputTokens,
                model: this.config.model,
            });
            let finalSystemPrompt = systemPrompt;
            let finalUserPrompt = finalUserPrompt0;
            let finalEstimatedTokens = estimatedTokens;
            let truncationLevel;
            if (estimatedTokens > this.config.maxInputTokens) {
                // Progressive truncation (replaces hard skip)
                this.logger.info("Token budget exceeded, attempting progressive truncation", {
                    owner,
                    repo,
                    pr: pr.number,
                    estimatedTokens,
                    budget: this.config.maxInputTokens,
                });
                const truncResult = progressiveTruncate(effectiveItem.files, this.config.maxInputTokens, this.config.model, systemPrompt.length, 
                // Metadata estimate: PR header, format instructions (~2000 chars)
                2000);
                if (!truncResult.success) {
                    this.logger.warn("Progressive truncation failed (all 3 levels exceeded budget)", {
                        owner,
                        repo,
                        pr: pr.number,
                        estimatedTokens,
                        budget: this.config.maxInputTokens,
                    });
                    return this.skipResult(item, "prompt_too_large_after_truncation");
                }
                // Rebuild prompt with truncated files
                const truncatedPrompt = this.template.buildPromptFromTruncation(item, this.persona, truncResult, loaBanner);
                finalSystemPrompt = truncatedPrompt.systemPrompt;
                finalUserPrompt = truncatedPrompt.userPrompt;
                finalEstimatedTokens = truncResult.tokenEstimate?.total ?? estimatedTokens;
                truncationLevel = truncResult.level;
                this.logger.info("Progressive truncation succeeded", {
                    owner,
                    repo,
                    pr: pr.number,
                    level: truncResult.level,
                    filesIncluded: truncResult.files.length,
                    filesExcluded: truncResult.excluded.length,
                    tokenEstimate: truncResult.tokenEstimate,
                });
            }
            // Step 6: Generate review via LLM (with adaptive retry — Task 1.8)
            let response;
            try {
                response = await this.llm.generateReview({
                    systemPrompt: finalSystemPrompt,
                    userPrompt: finalUserPrompt,
                    maxOutputTokens: this.config.maxOutputTokens,
                });
            }
            catch (llmErr) {
                if (isTokenRejection(llmErr)) {
                    // Adaptive retry: drop to next level with 85% budget (SKP-004)
                    this.logger.warn("LLM rejected prompt (token limit), attempting adaptive retry", {
                        owner,
                        repo,
                        pr: pr.number,
                    });
                    const retryBudget = Math.floor(this.config.maxInputTokens * 0.85);
                    const retryResult = progressiveTruncate(effectiveItem.files, retryBudget, this.config.model, finalSystemPrompt.length, 2000);
                    if (!retryResult.success) {
                        return this.skipResult(item, "prompt_too_large_after_truncation");
                    }
                    const retryPrompt = this.template.buildPromptFromTruncation(item, this.persona, retryResult, loaBanner);
                    this.logger.info("Adaptive retry with reduced budget", {
                        owner,
                        repo,
                        pr: pr.number,
                        retryBudget,
                        level: retryResult.level,
                    });
                    response = await this.llm.generateReview({
                        systemPrompt: retryPrompt.systemPrompt,
                        userPrompt: retryPrompt.userPrompt,
                        maxOutputTokens: this.config.maxOutputTokens,
                    });
                }
                else {
                    throw llmErr; // Re-throw non-token errors
                }
            }
            // Step 6b: Token calibration logging (BB-F1)
            // Log estimated vs actual tokens for coefficient tuning over time.
            if (response.inputTokens > 0) {
                const ratio = +(response.inputTokens / finalEstimatedTokens).toFixed(3);
                this.logger.info("calibration", {
                    phase: "calibration",
                    estimatedTokens: finalEstimatedTokens,
                    actualInputTokens: response.inputTokens,
                    ratio,
                    model: this.config.model,
                    truncationLevel: truncationLevel ?? null,
                });
            }
            // Step 7: Validate structured output
            if (!isValidResponse(response.content)) {
                return this.skipResult(item, "invalid_llm_response");
            }
            // Step 8: Sanitize output
            const sanitized = this.sanitizer.sanitize(response.content);
            if (!sanitized.safe && this.config.sanitizerMode === "strict") {
                this.logger.error("Sanitizer blocked review in strict mode", {
                    owner,
                    repo,
                    pr: pr.number,
                    redactions: sanitized.redactedPatterns?.length ?? 0,
                });
                return this.errorResult(item, makeError("E_SANITIZER_BLOCKED", "Review blocked by sanitizer in strict mode", "sanitizer", "permanent", false));
            }
            if (!sanitized.safe) {
                this.logger.warn("Sanitizer redacted content", {
                    owner,
                    repo,
                    pr: pr.number,
                    redactions: sanitized.redactedPatterns?.length ?? 0,
                });
            }
            // Marker is appended by the poster adapter — do not duplicate here
            const body = sanitized.sanitizedContent;
            const event = classifyEvent(sanitized.sanitizedContent);
            // Step 9a: Re-check guard (race condition mitigation) with retry
            let recheck = false;
            try {
                recheck = await this.poster.hasExistingReview(owner, repo, pr.number, pr.headSha);
            }
            catch {
                // Retry once — this is the last gate before posting
                try {
                    recheck = await this.poster.hasExistingReview(owner, repo, pr.number, pr.headSha);
                }
                catch {
                    // Both attempts failed — conservative: skip to avoid duplicate
                    return this.skipResult(item, "recheck_failed");
                }
            }
            if (recheck) {
                return this.skipResult(item, "already_reviewed_recheck");
            }
            // Step 9b: Post review (or dry-run)
            if (this.config.dryRun) {
                this.logger.info("Dry run — review not posted", {
                    owner,
                    repo,
                    pr: pr.number,
                    event,
                    bodyLength: body.length,
                });
            }
            else {
                await this.poster.postReview({
                    owner,
                    repo,
                    prNumber: pr.number,
                    headSha: pr.headSha,
                    body,
                    event,
                });
            }
            // Finalize context
            const result = {
                item,
                posted: !this.config.dryRun,
                skipped: false,
                inputTokens: response.inputTokens,
                outputTokens: response.outputTokens,
            };
            await this.context.finalizeReview(item, result);
            this.logger.info("Review complete", {
                owner,
                repo,
                pr: pr.number,
                event,
                posted: result.posted,
                inputTokens: response.inputTokens,
                outputTokens: response.outputTokens,
            });
            return result;
        }
        catch (err) {
            const message = err instanceof Error ? err.message : String(err);
            const reviewError = this.classifyError(err, message);
            // Log error code/category only — raw message may contain secrets from adapters
            this.logger.error("Review failed", {
                owner,
                repo,
                pr: pr.number,
                code: reviewError.code,
                category: reviewError.category,
                source: reviewError.source,
            });
            return this.errorResult(item, reviewError);
        }
    }
    classifyError(err, message) {
        // Primary: typed port errors from adapters (BB-F3)
        if (err instanceof GitProviderError) {
            const retryable = err.code === "RATE_LIMITED" || err.code === "NETWORK";
            const code = err.code === "RATE_LIMITED" ? "E_RATE_LIMIT" : "E_GITHUB";
            return makeError(code, "GitHub operation failed", "github", retryable ? "transient" : "permanent", retryable);
        }
        if (err instanceof LLMProviderError) {
            const retryable = err.code === "RATE_LIMITED" || err.code === "NETWORK";
            const code = err.code === "RATE_LIMITED" ? "E_RATE_LIMIT" : "E_LLM";
            return makeError(code, "LLM operation failed", "llm", retryable ? "transient" : "permanent", retryable);
        }
        // Fallback: string matching for unknown/untyped errors (backward compat)
        const m = (message || "").toLowerCase();
        if (m.includes("429") || m.includes("rate limit")) {
            return makeError("E_RATE_LIMIT", "Rate limited", "github", "transient", true);
        }
        if (m.startsWith("gh ") || m.includes("gh command failed") || m.includes("github cli")) {
            return makeError("E_GITHUB", "GitHub operation failed", "github", "transient", true);
        }
        if (m.startsWith("anthropic api")) {
            return makeError("E_LLM", "LLM operation failed", "llm", "transient", true);
        }
        return makeError("E_UNKNOWN", "Unknown failure", "pipeline", "unknown", false);
    }
    skipResult(item, skipReason) {
        return { item, posted: false, skipped: true, skipReason };
    }
    errorResult(item, error) {
        return { item, posted: false, skipped: false, error };
    }
    /**
     * Extract findings JSON from content enclosed in bridge-findings markers (SDD 3.5).
     * Returns the raw JSON string or null if markers/JSON are missing or malformed.
     */
    extractFindingsJSON(content) {
        const startMarker = "<!-- bridge-findings-start -->";
        const endMarker = "<!-- bridge-findings-end -->";
        const startIdx = content.indexOf(startMarker);
        const endIdx = content.indexOf(endMarker);
        if (startIdx === -1 || endIdx === -1 || endIdx <= startIdx) {
            return null;
        }
        const block = content.slice(startIdx + startMarker.length, endIdx).trim();
        // Strip markdown code fences if present
        const jsonStr = block.replace(/^```json?\s*\n?/, "").replace(/\n?```\s*$/, "");
        try {
            const parsed = JSON.parse(jsonStr);
            if (!parsed.findings || !Array.isArray(parsed.findings)) {
                return null;
            }
            return jsonStr;
        }
        catch {
            return null;
        }
    }
    /**
     * Validate that Pass 2 preserved all findings from Pass 1 (SDD 3.6, FR-2.4).
     * Checks: same count, same IDs, same severities.
     */
    validateFindingPreservation(pass1JSON, pass2JSON) {
        try {
            const pass1 = JSON.parse(pass1JSON);
            const pass2 = JSON.parse(pass2JSON);
            if (pass1.findings.length !== pass2.findings.length) {
                return false;
            }
            const pass1Ids = new Set(pass1.findings.map((f) => f.id));
            const pass2Ids = new Set(pass2.findings.map((f) => f.id));
            if (pass1Ids.size !== pass2Ids.size)
                return false;
            for (const id of pass1Ids) {
                if (!pass2Ids.has(id))
                    return false;
            }
            for (const f1 of pass1.findings) {
                const f2 = pass2.findings.find((f) => f.id === f1.id);
                if (!f2 || f2.severity !== f1.severity)
                    return false;
            }
            return true;
        }
        catch {
            return false;
        }
    }
    /**
     * Fallback: wrap Pass 1 findings in minimal valid review format (SDD 3.7, FR-2.7).
     * Used when Pass 2 fails or modifies findings.
     */
    async finishWithUnenrichedOutput(item, pass1InputTokens, pass1OutputTokens, pass1Duration, findingsJSON, pass1Content) {
        const { owner, repo, pr } = item;
        const body = [
            "## Summary",
            "",
            `Analytical review of ${owner}/${repo}#${pr.number}. Enrichment pass was unavailable; findings are unenriched.`,
            "",
            "## Findings",
            "",
            "<!-- bridge-findings-start -->",
            "```json",
            findingsJSON,
            "```",
            "<!-- bridge-findings-end -->",
            "",
            "## Callouts",
            "",
            "_Enrichment unavailable for this review._",
        ].join("\n");
        const sanitized = this.sanitizer.sanitize(body);
        const event = classifyEvent(sanitized.sanitizedContent);
        if (!sanitized.safe && this.config.sanitizerMode === "strict") {
            return this.errorResult(item, makeError("E_SANITIZER_BLOCKED", "Review blocked by sanitizer in strict mode", "sanitizer", "permanent", false));
        }
        // Re-check guard
        let recheck = false;
        try {
            recheck = await this.poster.hasExistingReview(owner, repo, pr.number, pr.headSha);
        }
        catch {
            try {
                recheck = await this.poster.hasExistingReview(owner, repo, pr.number, pr.headSha);
            }
            catch {
                return this.skipResult(item, "recheck_failed");
            }
        }
        if (recheck) {
            return this.skipResult(item, "already_reviewed_recheck");
        }
        if (this.config.dryRun) {
            this.logger.info("Dry run — unenriched review not posted", {
                owner, repo, pr: pr.number, event, bodyLength: body.length,
            });
        }
        else {
            await this.poster.postReview({
                owner, repo, prNumber: pr.number, headSha: pr.headSha,
                body: sanitized.sanitizedContent, event,
            });
        }
        const result = {
            item,
            posted: !this.config.dryRun,
            skipped: false,
            inputTokens: pass1InputTokens,
            outputTokens: pass1OutputTokens,
            pass1Output: pass1Content,
            pass1Tokens: { input: pass1InputTokens, output: pass1OutputTokens, duration: pass1Duration },
        };
        await this.context.finalizeReview(item, result);
        return result;
    }
    /**
     * Two-pass review flow: convergence (analytical) then enrichment (persona) (SDD 3.4).
     * Pass 1 produces findings JSON; Pass 2 enriches with educational depth.
     * Pass 2 failure is always safe — falls back to Pass 1 unenriched output.
     */
    async processItemTwoPass(item, effectiveItem, incrementalBanner) {
        const { owner, repo, pr } = item;
        // ═══════════════════════════════════════════════
        // PASS 1: Convergence (no persona, analytical only)
        // ═══════════════════════════════════════════════
        const pass1Start = this.now();
        const convergenceSystem = this.template.buildConvergenceSystemPrompt();
        const truncated = truncateFiles(effectiveItem.files, this.config);
        // Handle all-files-excluded by Loa filtering
        if (truncated.allExcluded) {
            this.logger.info("All files excluded by Loa filtering", {
                owner, repo, pr: pr.number,
            });
            if (!this.config.dryRun) {
                await this.poster.postReview({
                    owner, repo, prNumber: pr.number, headSha: pr.headSha,
                    body: "All changes in this PR are Loa framework files. No application code changes to review. Override with `loa_aware: false` to review framework changes.",
                    event: "COMMENT",
                });
            }
            return this.skipResult(item, "all_files_excluded");
        }
        // Build convergence user prompt using TruncationResult
        let convergenceUser = this.template.buildConvergenceUserPrompt(effectiveItem, truncated);
        if (incrementalBanner) {
            convergenceUser = `${incrementalBanner}\n\n${convergenceUser}`;
        }
        // Token estimation + progressive truncation
        const { coefficient } = getTokenBudget(this.config.model);
        const systemTokens = Math.ceil(convergenceSystem.length * coefficient);
        const userTokens = Math.ceil(convergenceUser.length * coefficient);
        const estimatedTokens = systemTokens + userTokens;
        this.logger.info("Pass 1: Prompt estimate", {
            owner, repo, pr: pr.number,
            estimatedTokens, systemTokens, userTokens,
            budget: this.config.maxInputTokens, model: this.config.model,
        });
        let finalConvergenceSystem = convergenceSystem;
        let finalConvergenceUser = convergenceUser;
        if (estimatedTokens > this.config.maxInputTokens) {
            this.logger.info("Pass 1: Token budget exceeded, attempting progressive truncation", {
                owner, repo, pr: pr.number, estimatedTokens, budget: this.config.maxInputTokens,
            });
            const truncResult = progressiveTruncate(effectiveItem.files, this.config.maxInputTokens, this.config.model, convergenceSystem.length, 2000);
            if (!truncResult.success) {
                return this.skipResult(item, "prompt_too_large_after_truncation");
            }
            finalConvergenceUser = this.template.buildConvergenceUserPromptFromTruncation(effectiveItem, truncResult, truncated.loaBanner);
        }
        // LLM Call 1: Convergence
        this.logger.info("Pass 1: Convergence review", { owner, repo, pr: pr.number });
        let pass1Response;
        try {
            pass1Response = await this.llm.generateReview({
                systemPrompt: finalConvergenceSystem,
                userPrompt: finalConvergenceUser,
                maxOutputTokens: this.config.maxOutputTokens,
            });
        }
        catch (llmErr) {
            if (isTokenRejection(llmErr)) {
                const retryBudget = Math.floor(this.config.maxInputTokens * 0.85);
                const retryResult = progressiveTruncate(effectiveItem.files, retryBudget, this.config.model, finalConvergenceSystem.length, 2000);
                if (!retryResult.success) {
                    return this.skipResult(item, "prompt_too_large_after_truncation");
                }
                const retryUser = this.template.buildConvergenceUserPromptFromTruncation(effectiveItem, retryResult, truncated.loaBanner);
                pass1Response = await this.llm.generateReview({
                    systemPrompt: finalConvergenceSystem,
                    userPrompt: retryUser,
                    maxOutputTokens: this.config.maxOutputTokens,
                });
            }
            else {
                throw llmErr;
            }
        }
        const pass1Duration = this.now() - pass1Start;
        // Extract findings JSON from Pass 1
        const findingsJSON = this.extractFindingsJSON(pass1Response.content);
        if (!findingsJSON) {
            this.logger.warn("Pass 1 produced no parseable findings, falling back to single-pass validation", {
                owner, repo, pr: pr.number,
            });
            // If Pass 1 content is still a valid review format, use it directly
            if (isValidResponse(pass1Response.content)) {
                return this.finishWithPass1AsReview(item, pass1Response, pass1Duration);
            }
            return this.skipResult(item, "invalid_llm_response");
        }
        this.logger.info("Pass 1 complete", {
            owner, repo, pr: pr.number,
            duration: pass1Duration,
            inputTokens: pass1Response.inputTokens,
            outputTokens: pass1Response.outputTokens,
        });
        // ═══════════════════════════════════════════════
        // PASS 2: Enrichment (persona loaded, no full diff)
        // ═══════════════════════════════════════════════
        const pass2Start = this.now();
        const { systemPrompt: enrichmentSystem, userPrompt: enrichmentUser } = this.template.buildEnrichmentPrompt(findingsJSON, item, this.persona);
        this.logger.info("Pass 2: Enrichment review", {
            owner, repo, pr: pr.number,
            enrichmentInputChars: enrichmentUser.length,
        });
        let pass2Response;
        try {
            pass2Response = await this.llm.generateReview({
                systemPrompt: enrichmentSystem,
                userPrompt: enrichmentUser,
                maxOutputTokens: this.config.maxOutputTokens,
            });
        }
        catch (enrichErr) {
            this.logger.warn("Pass 2 failed, using Pass 1 unenriched output", {
                owner, repo, pr: pr.number,
                error: enrichErr instanceof Error ? enrichErr.message : String(enrichErr),
            });
            return this.finishWithUnenrichedOutput(item, pass1Response.inputTokens, pass1Response.outputTokens, pass1Duration, findingsJSON, pass1Response.content);
        }
        const pass2Duration = this.now() - pass2Start;
        // FR-2.4: Validate finding preservation
        const pass2FindingsJSON = this.extractFindingsJSON(pass2Response.content);
        if (pass2FindingsJSON) {
            const preserved = this.validateFindingPreservation(findingsJSON, pass2FindingsJSON);
            if (!preserved) {
                this.logger.warn("Pass 2 modified findings, using Pass 1 output", {
                    owner, repo, pr: pr.number,
                });
                return this.finishWithUnenrichedOutput(item, pass1Response.inputTokens, pass1Response.outputTokens, pass1Duration, findingsJSON, pass1Response.content);
            }
        }
        // Validate combined output
        if (!isValidResponse(pass2Response.content)) {
            this.logger.warn("Pass 2 invalid response, using Pass 1 output", {
                owner, repo, pr: pr.number,
            });
            return this.finishWithUnenrichedOutput(item, pass1Response.inputTokens, pass1Response.outputTokens, pass1Duration, findingsJSON, pass1Response.content);
        }
        this.logger.info("Pass 2 complete", {
            owner, repo, pr: pr.number,
            duration: pass2Duration,
            inputTokens: pass2Response.inputTokens,
            outputTokens: pass2Response.outputTokens,
            totalDuration: pass1Duration + pass2Duration,
        });
        // Steps 7-9: Standard post-processing using Pass 2 enriched output
        const sanitized = this.sanitizer.sanitize(pass2Response.content);
        if (!sanitized.safe && this.config.sanitizerMode === "strict") {
            return this.errorResult(item, makeError("E_SANITIZER_BLOCKED", "Review blocked by sanitizer in strict mode", "sanitizer", "permanent", false));
        }
        if (!sanitized.safe) {
            this.logger.warn("Sanitizer redacted content", {
                owner, repo, pr: pr.number,
                redactions: sanitized.redactedPatterns?.length ?? 0,
            });
        }
        const body = sanitized.sanitizedContent;
        const event = classifyEvent(sanitized.sanitizedContent);
        // Re-check guard
        let recheck = false;
        try {
            recheck = await this.poster.hasExistingReview(owner, repo, pr.number, pr.headSha);
        }
        catch {
            try {
                recheck = await this.poster.hasExistingReview(owner, repo, pr.number, pr.headSha);
            }
            catch {
                return this.skipResult(item, "recheck_failed");
            }
        }
        if (recheck) {
            return this.skipResult(item, "already_reviewed_recheck");
        }
        if (this.config.dryRun) {
            this.logger.info("Dry run — two-pass review not posted", {
                owner, repo, pr: pr.number, event, bodyLength: body.length,
            });
        }
        else {
            await this.poster.postReview({
                owner, repo, prNumber: pr.number, headSha: pr.headSha, body, event,
            });
        }
        const result = {
            item,
            posted: !this.config.dryRun,
            skipped: false,
            inputTokens: pass1Response.inputTokens + pass2Response.inputTokens,
            outputTokens: pass1Response.outputTokens + pass2Response.outputTokens,
            pass1Output: pass1Response.content,
            pass1Tokens: { input: pass1Response.inputTokens, output: pass1Response.outputTokens, duration: pass1Duration },
            pass2Tokens: { input: pass2Response.inputTokens, output: pass2Response.outputTokens, duration: pass2Duration },
        };
        await this.context.finalizeReview(item, result);
        this.logger.info("Two-pass review complete", {
            owner, repo, pr: pr.number, event,
            posted: result.posted,
            pass1Tokens: result.pass1Tokens,
            pass2Tokens: result.pass2Tokens,
        });
        return result;
    }
    /**
     * Handle case where Pass 1 content is a valid review (has Summary+Findings)
     * but findings couldn't be extracted as JSON. Use it directly as the review.
     */
    async finishWithPass1AsReview(item, pass1Response, pass1Duration) {
        const { owner, repo, pr } = item;
        const sanitized = this.sanitizer.sanitize(pass1Response.content);
        if (!sanitized.safe && this.config.sanitizerMode === "strict") {
            return this.errorResult(item, makeError("E_SANITIZER_BLOCKED", "Review blocked by sanitizer in strict mode", "sanitizer", "permanent", false));
        }
        const body = sanitized.sanitizedContent;
        const event = classifyEvent(body);
        let recheck = false;
        try {
            recheck = await this.poster.hasExistingReview(owner, repo, pr.number, pr.headSha);
        }
        catch {
            try {
                recheck = await this.poster.hasExistingReview(owner, repo, pr.number, pr.headSha);
            }
            catch {
                return this.skipResult(item, "recheck_failed");
            }
        }
        if (recheck) {
            return this.skipResult(item, "already_reviewed_recheck");
        }
        if (this.config.dryRun) {
            this.logger.info("Dry run — pass1-as-review not posted", {
                owner, repo, pr: pr.number, event, bodyLength: body.length,
            });
        }
        else {
            await this.poster.postReview({
                owner, repo, prNumber: pr.number, headSha: pr.headSha, body, event,
            });
        }
        const result = {
            item,
            posted: !this.config.dryRun,
            skipped: false,
            inputTokens: pass1Response.inputTokens,
            outputTokens: pass1Response.outputTokens,
            pass1Output: pass1Response.content,
            pass1Tokens: { input: pass1Response.inputTokens, output: pass1Response.outputTokens, duration: pass1Duration },
        };
        await this.context.finalizeReview(item, result);
        return result;
    }
    buildSummary(runId, startTime, results) {
        return {
            runId,
            startTime,
            endTime: new Date().toISOString(),
            reviewed: results.filter((r) => !r.skipped && !r.error).length,
            skipped: results.filter((r) => r.skipped).length,
            errors: results.filter((r) => r.error).length,
            results,
        };
    }
}
//# sourceMappingURL=reviewer.js.map