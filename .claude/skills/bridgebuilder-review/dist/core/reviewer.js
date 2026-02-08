const CRITICAL_PATTERN = /\b(critical|security vulnerability|sql injection|xss|secret leak|must fix)\b/i;
const REFUSAL_PATTERN = /\b(I cannot|I'm unable|I can't|as an AI|I apologize)\b/i;
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
            // Step 4: Build prompt
            const { systemPrompt, userPrompt } = this.template.buildPrompt(item, this.persona);
            // Step 5: Token estimation guard (chars / 4).
            // Decision: chars/4 is a deliberate over-estimate for English+code text.
            // Real tokenizers average ~3.5-4.2 chars/token. Over-estimating is safe —
            // worst case we skip a PR that would have fit. Under-estimating risks
            // truncated LLM output or API errors. A proper tokenizer (tiktoken) would
            // add ~2MB dependency for marginal accuracy gain on a guard rail.
            const estimatedTokens = (systemPrompt.length + userPrompt.length) / 4;
            if (estimatedTokens > this.config.maxInputTokens) {
                return this.skipResult(item, "prompt_too_large");
            }
            // Step 6: Generate review via LLM
            const response = await this.llm.generateReview({
                systemPrompt,
                userPrompt,
                maxOutputTokens: this.config.maxOutputTokens,
            });
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
    classifyError(_err, message) {
        // Never persist raw adapter messages — may contain sensitive details.
        // Classify using anchored prefixes that match actual adapter error strings,
        // not generic substrings that could false-positive on unrelated messages.
        const m = (message || "").toLowerCase();
        if (m.includes("429") || m.includes("rate limit")) {
            return makeError("E_RATE_LIMIT", "Rate limited", "github", "transient", true);
        }
        // Match actual adapter error prefixes: "gh command failed", "gh api"
        if (m.startsWith("gh ") || m.includes("gh command failed") || m.includes("github cli")) {
            return makeError("E_GITHUB", "GitHub operation failed", "github", "transient", true);
        }
        // Match actual adapter error prefixes: "anthropic api ..."
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
    buildSummary(runId, startTime, results) {
        return {
            runId,
            startTime,
            endTime: new Date().toISOString(),
            reviewed: results.filter((r) => r.posted).length,
            skipped: results.filter((r) => r.skipped).length,
            errors: results.filter((r) => r.error).length,
            results,
        };
    }
}
//# sourceMappingURL=reviewer.js.map