import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { GitProviderError } from "../ports/git-provider.js";
import type { IGitProvider } from "../ports/git-provider.js";
import { LLMProviderError } from "../ports/llm-provider.js";
import type { ILLMProvider } from "../ports/llm-provider.js";
import type { IReviewPoster, ReviewEvent } from "../ports/review-poster.js";
import type { IOutputSanitizer } from "../ports/output-sanitizer.js";
import type { ILogger } from "../ports/logger.js";
import type { IHasher } from "../ports/hasher.js";
import type { PRReviewTemplate } from "./template.js";
import type { BridgebuilderContext } from "./context.js";
import type {
  BridgebuilderConfig,
  ReviewItem,
  ReviewResult,
  ReviewError,
  RunSummary,
  PersonaMetadata,
  EcosystemContext,
  EnrichmentOptions,
} from "./types.js";
import { FindingsBlockSchema } from "./schemas.js";
import type { ValidatedFinding } from "./schemas.js";
import { Pass1Cache, computeCacheKey } from "./cache.js";
import { extractEcosystemPatterns, updateEcosystemContext } from "./ecosystem.js";
import {
  truncateFiles,
  progressiveTruncate,
  estimateTokens,
  getTokenBudget,
} from "./truncation.js";

const CRITICAL_PATTERN =
  /\b(critical|security vulnerability|sql injection|xss|secret leak|must fix)\b/i;

const REFUSAL_PATTERN =
  /\b(I cannot|I'm unable|I can't|as an AI|I apologize)\b/i;

/** Patterns that indicate an LLM token rejection (Task 1.8). */
const TOKEN_REJECTION_PATTERNS = [
  "prompt_too_large",
  "maximum context length",
  "context_length_exceeded",
  "token limit",
];

function classifyEvent(content: string): ReviewEvent {
  return CRITICAL_PATTERN.test(content) ? "REQUEST_CHANGES" : "COMMENT";
}

function isValidResponse(content: string): boolean {
  if (!content || content.length < 50) return false;
  if (REFUSAL_PATTERN.test(content)) return false;
  if (!content.includes("## Summary") || !content.includes("## Findings"))
    return false;
  // Reject code-only responses (no prose)
  const nonCodeContent = content.replace(/```[\s\S]*?```/g, "").trim();
  if (nonCodeContent.length < 30) return false;
  return true;
}

function makeError(
  code: string,
  message: string,
  source: ReviewError["source"],
  category: ReviewError["category"],
  retryable: boolean,
): ReviewError {
  return { code, message, category, retryable, source };
}

function isTokenRejection(err: unknown): boolean {
  // Primary: typed error code from LLM adapter (BB-F3)
  if (err instanceof LLMProviderError && err.code === "TOKEN_LIMIT") {
    return true;
  }
  // Fallback: string matching for unknown/untyped errors
  const message =
    err instanceof Error ? err.message.toLowerCase() : String(err).toLowerCase();
  return TOKEN_REJECTION_PATTERNS.some((p) => message.includes(p));
}

export class ReviewPipeline {
  private readonly personaMetadata: PersonaMetadata;
  private ecosystemContext: EcosystemContext | undefined;
  private readonly pass1Cache: Pass1Cache | null;
  private readonly hasher: IHasher | null;

  constructor(
    private readonly template: PRReviewTemplate,
    private readonly context: BridgebuilderContext,
    private readonly git: IGitProvider,
    private readonly poster: IReviewPoster,
    private readonly llm: ILLMProvider,
    private readonly sanitizer: IOutputSanitizer,
    private readonly logger: ILogger,
    private readonly persona: string,
    private readonly config: BridgebuilderConfig,
    private readonly now: () => number = Date.now,
    hasher?: IHasher,
  ) {
    this.personaMetadata = ReviewPipeline.parsePersonaMetadata(persona);
    // Initialize Pass 1 cache when config enables it (AC-8: opt-in, default false)
    if (config.pass1Cache?.enabled && hasher) {
      this.pass1Cache = new Pass1Cache(".run/bridge-cache");
      this.hasher = hasher;
    } else {
      this.pass1Cache = null;
      this.hasher = null;
    }
  }

  /**
   * Load ecosystem context from the configured JSON file path.
   * Validates structure; silently ignores missing/malformed files.
   */
  static loadEcosystemContext(
    filePath: string | undefined,
    logger: ILogger,
  ): EcosystemContext | undefined {
    if (!filePath) return undefined;

    try {
      const raw = readFileSync(filePath, "utf-8");
      const parsed = JSON.parse(raw);

      if (
        !parsed.patterns ||
        !Array.isArray(parsed.patterns) ||
        typeof parsed.lastUpdated !== "string"
      ) {
        logger.warn("Ecosystem context file has invalid structure", { filePath });
        return undefined;
      }

      // Validate each pattern entry has required fields
      const validPatterns = parsed.patterns.filter(
        (p: unknown): p is { repo: string; pattern: string; connection: string; pr?: number } =>
          p != null &&
          typeof p === "object" &&
          typeof (p as Record<string, unknown>).repo === "string" &&
          typeof (p as Record<string, unknown>).pattern === "string" &&
          typeof (p as Record<string, unknown>).connection === "string",
      );

      if (validPatterns.length === 0) {
        logger.warn("Ecosystem context file has no valid patterns", { filePath });
        return undefined;
      }

      logger.info("Loaded ecosystem context", {
        filePath,
        patternCount: validPatterns.length,
        lastUpdated: parsed.lastUpdated,
      });

      return { patterns: validPatterns, lastUpdated: parsed.lastUpdated };
    } catch {
      // File missing or unreadable — not an error, just no context
      return undefined;
    }
  }

  /**
   * Parse persona frontmatter to extract identity metadata.
   * Expected format: <!-- persona-version: X | agent: Y -->
   * Fallback: { id: "unknown", version: "0.0.0", hash: sha256(content) }
   */
  static parsePersonaMetadata(content: string): PersonaMetadata {
    const hash = createHash("sha256").update(content.trim()).digest("hex");
    const match = content.match(
      /<!--\s*persona-version:\s*([^\s|]+)\s*\|\s*agent:\s*([^\s>]+)/,
    );
    if (match) {
      return { id: match[2], version: match[1], hash };
    }
    return { id: "unknown", version: "0.0.0", hash };
  }

  /**
   * Post-bridge hook: extract high-quality patterns from findings and update ecosystem context (AC-7).
   * Orchestrates extractEcosystemPatterns() + updateEcosystemContext().
   * Called by run-bridge finalization after each bridge iteration.
   */
  static async updateEcosystemFromFindings(
    findings: ValidatedFinding[],
    repo: string,
    pr: number,
    contextPath: string,
    logger: ILogger,
  ): Promise<void> {
    const patterns = extractEcosystemPatterns(findings, repo, pr);
    if (patterns.length === 0) {
      logger.info("No ecosystem-worthy patterns found in findings", { repo, pr });
      return;
    }

    logger.info("Extracted ecosystem patterns from findings", {
      repo,
      pr,
      patternCount: patterns.length,
    });

    await updateEcosystemContext(contextPath, patterns, logger);
  }

  async run(runId: string): Promise<RunSummary> {
    const startTime = new Date().toISOString();
    const startMs = this.now();
    const results: ReviewResult[] = [];

    // Preflight: check GitHub API connectivity and quota
    const preflight = await this.git.preflight();
    if (preflight.remaining < 100) {
      this.logger.warn("GitHub API quota too low, skipping run", {
        remaining: preflight.remaining,
      });
      return this.buildSummary(runId, startTime, results);
    }

    // Preflight: check each repo is accessible, track results
    const accessibleRepos = new Set<string>();
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

    // Load ecosystem context for enrichment (Pass 0 prototype — Task 6.4)
    this.ecosystemContext = ReviewPipeline.loadEcosystemContext(
      this.config.ecosystemContextPath,
      this.logger,
    );

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

  private async processItem(item: ReviewItem): Promise<ReviewResult> {
    const { owner, repo, pr } = item;

    try {
      // Step 1: Check if changed
      const changed = await this.context.hasChanged(item);
      if (!changed) {
        return this.skipResult(item, "unchanged");
      }

      // Step 2: Check for existing review
      const existing = await this.poster.hasExistingReview(
        owner,
        repo,
        pr.number,
        pr.headSha,
      );
      if (existing) {
        return this.skipResult(item, "already_reviewed");
      }

      // Step 3: Claim review slot
      const claimed = await this.context.claimReview(item);
      if (!claimed) {
        return this.skipResult(item, "claim_failed");
      }

      // Step 3.5: Incremental review detection (V3-1)
      let incrementalBanner: string | undefined;
      let effectiveItem = item;
      if (!this.config.forceFullReview) {
        const lastSha = await this.context.getLastReviewedSha(item);
        if (lastSha && lastSha !== pr.headSha) {
          try {
            const compare = await this.git.getCommitDiff(owner, repo, lastSha, pr.headSha);
            if (compare.filesChanged.length > 0) {
              const deltaFiles = item.files.filter((f) =>
                compare.filesChanged.includes(f.filename),
              );
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
          } catch {
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
      const { systemPrompt, userPrompt, allExcluded, loaBanner } =
        this.template.buildPromptWithMeta(effectiveItem, this.persona);

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
      let truncationLevel: number | undefined;

      if (estimatedTokens > this.config.maxInputTokens) {
        // Progressive truncation (replaces hard skip)
        this.logger.info("Token budget exceeded, attempting progressive truncation", {
          owner,
          repo,
          pr: pr.number,
          estimatedTokens,
          budget: this.config.maxInputTokens,
        });

        const truncResult = progressiveTruncate(
          effectiveItem.files,
          this.config.maxInputTokens,
          this.config.model,
          systemPrompt.length,
          // Metadata estimate: PR header, format instructions (~2000 chars)
          2000,
        );

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
        const truncatedPrompt = this.template.buildPromptFromTruncation(
          item,
          this.persona,
          truncResult,
          loaBanner,
        );
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
      } catch (llmErr: unknown) {
        if (isTokenRejection(llmErr)) {
          // Adaptive retry: drop to next level with 85% budget (SKP-004)
          this.logger.warn("LLM rejected prompt (token limit), attempting adaptive retry", {
            owner,
            repo,
            pr: pr.number,
          });

          const retryBudget = Math.floor(this.config.maxInputTokens * 0.85);
          const retryResult = progressiveTruncate(
            effectiveItem.files,
            retryBudget,
            this.config.model,
            finalSystemPrompt.length,
            2000,
          );

          if (!retryResult.success) {
            return this.skipResult(item, "prompt_too_large_after_truncation");
          }

          const retryPrompt = this.template.buildPromptFromTruncation(
            item,
            this.persona,
            retryResult,
            loaBanner,
          );

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
        } else {
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

      // Steps 8-9: Shared post-processing (sanitize → recheck → post → finalize)
      return this.postAndFinalize(item, response.content, {
        inputTokens: response.inputTokens,
        outputTokens: response.outputTokens,
      });
    } catch (err: unknown) {
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

  private classifyError(err: unknown, message: string): ReviewError {
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

  private skipResult(item: ReviewItem, skipReason: string): ReviewResult {
    return { item, posted: false, skipped: true, skipReason };
  }

  private errorResult(item: ReviewItem, error: ReviewError): ReviewResult {
    return { item, posted: false, skipped: false, error };
  }

  /**
   * Shared post-processing: sanitize → recheck guard (with retry) → dry-run gate → post → finalize.
   * All review completion paths delegate here to avoid duplication (medium-1).
   *
   * resultFields may include pass1Output, pass1Tokens, and pass2Tokens — these are
   * populated by two-pass callers only. Single-pass callers pass inputTokens/outputTokens only.
   */
  private async postAndFinalize(
    item: ReviewItem,
    body: string,
    resultFields: Omit<ReviewResult, "item" | "posted" | "skipped">,
  ): Promise<ReviewResult> {
    const { owner, repo, pr } = item;

    const sanitized = this.sanitizer.sanitize(body);

    if (!sanitized.safe && this.config.sanitizerMode === "strict") {
      return this.errorResult(
        item,
        makeError("E_SANITIZER_BLOCKED", "Review blocked by sanitizer in strict mode", "sanitizer", "permanent", false),
      );
    }

    if (!sanitized.safe) {
      this.logger.warn("Sanitizer redacted content", {
        owner, repo, pr: pr.number,
        redactions: sanitized.redactedPatterns?.length ?? 0,
      });
    }

    const sanitizedBody = sanitized.sanitizedContent;
    const event = classifyEvent(sanitizedBody);

    // Re-check guard (race condition mitigation) with retry
    let recheck = false;
    try {
      recheck = await this.poster.hasExistingReview(owner, repo, pr.number, pr.headSha);
    } catch {
      try {
        recheck = await this.poster.hasExistingReview(owner, repo, pr.number, pr.headSha);
      } catch {
        return this.skipResult(item, "recheck_failed");
      }
    }
    if (recheck) {
      return this.skipResult(item, "already_reviewed_recheck");
    }

    if (this.config.dryRun) {
      this.logger.info("Dry run — review not posted", {
        owner, repo, pr: pr.number, event, bodyLength: sanitizedBody.length,
      });
    } else {
      await this.poster.postReview({
        owner, repo, prNumber: pr.number, headSha: pr.headSha,
        body: sanitizedBody, event,
      });
    }

    const result: ReviewResult = {
      item,
      posted: !this.config.dryRun,
      skipped: false,
      ...resultFields,
    };

    await this.context.finalizeReview(item, result);
    return result;
  }

  /**
   * Extract findings JSON from content enclosed in bridge-findings markers (SDD 3.5).
   * Uses zod FindingsBlockSchema for runtime validation (Sprint 69 — schema-first).
   * Returns { raw, parsed } or null if markers/JSON are missing or malformed.
   */
  private extractFindingsJSON(content: string): { raw: string; parsed: { findings: Array<{ id: string; severity: string; category: string; confidence?: number; [key: string]: unknown }> } } | null {
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
      const raw = JSON.parse(jsonStr);

      // Zod validation: validates schema_version, findings array, and each finding's
      // required fields (id, severity, category) + optional confidence [0,1].
      // .passthrough() preserves enrichment fields (faang_parallel, metaphor, etc.)
      const result = FindingsBlockSchema.safeParse(raw);

      if (!result.success) {
        return null;
      }

      const validated = result.data.findings;
      if (validated.length === 0) {
        return null;
      }

      // Strip confidence from findings where zod validation passed but confidence
      // was not provided (undefined) — preserve the existing behavior of stripping
      // invalid confidence values that fall outside [0,1] bounds.
      // Zod already handles min/max validation, so we only need to handle the case
      // where confidence was present in raw but stripped by zod's optional() handling.
      const findings = validated.map((f) => {
        // If the raw finding had a confidence field that zod dropped (outside bounds),
        // the validated finding won't have it — this is correct behavior.
        // Passthrough fields are preserved as-is.
        return f as { id: string; severity: string; category: string; confidence?: number; [key: string]: unknown };
      });

      return { raw: jsonStr, parsed: { ...result.data, findings } };
    } catch {
      return null;
    }
  }

  /**
   * Validate that Pass 2 preserved all findings from Pass 1 (SDD 3.6, FR-2.4).
   * Checks: same count, same IDs, same severities, same categories.
   */
  private validateFindingPreservation(
    pass1Findings: { findings: Array<{ id: string; severity: string; category: string; [key: string]: unknown }> },
    pass2Findings: { findings: Array<{ id: string; severity: string; category: string; [key: string]: unknown }> },
  ): boolean {
    try {
      if (pass1Findings.findings.length !== pass2Findings.findings.length) {
        return false;
      }

      const pass1Ids = new Set(pass1Findings.findings.map((f) => f.id));
      const pass2Ids = new Set(pass2Findings.findings.map((f) => f.id));
      if (pass1Ids.size !== pass2Ids.size) return false;
      for (const id of pass1Ids) {
        if (!pass2Ids.has(id)) return false;
      }

      for (const f1 of pass1Findings.findings) {
        const f2 = pass2Findings.findings.find((f) => f.id === f1.id);
        if (!f2 || f2.severity !== f1.severity) return false;
        if (f2.category !== f1.category) return false;
      }

      return true;
    } catch {
      return false;
    }
  }

  /**
   * Fallback: wrap Pass 1 findings in minimal valid review format (SDD 3.7, FR-2.7).
   * Used when Pass 2 fails or modifies findings.
   */
  private async finishWithUnenrichedOutput(
    item: ReviewItem,
    pass1InputTokens: number,
    pass1OutputTokens: number,
    pass1Duration: number,
    findingsJSON: string,
    pass1Content: string,
    pass1CacheHit?: boolean,
  ): Promise<ReviewResult> {
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

    return this.postAndFinalize(item, body, {
      inputTokens: pass1InputTokens,
      outputTokens: pass1OutputTokens,
      pass1Output: pass1Content,
      pass1Tokens: { input: pass1InputTokens, output: pass1OutputTokens, duration: pass1Duration },
      ...(pass1CacheHit != null ? { pass1CacheHit } : {}),
    });
  }

  /**
   * Two-pass review flow: convergence (analytical) then enrichment (persona) (SDD 3.4).
   * Pass 1 produces findings JSON; Pass 2 enriches with educational depth.
   * Pass 2 failure is always safe — falls back to Pass 1 unenriched output.
   */
  private async processItemTwoPass(
    item: ReviewItem,
    effectiveItem: ReviewItem,
    incrementalBanner: string | undefined,
  ): Promise<ReviewResult> {
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
    let truncationContext: { filesExcluded: number; totalFiles: number } | undefined;

    if (estimatedTokens > this.config.maxInputTokens) {
      this.logger.info("Pass 1: Token budget exceeded, attempting progressive truncation", {
        owner, repo, pr: pr.number, estimatedTokens, budget: this.config.maxInputTokens,
      });

      const truncResult = progressiveTruncate(
        effectiveItem.files,
        this.config.maxInputTokens,
        this.config.model,
        convergenceSystem.length,
        2000,
      );

      if (!truncResult.success) {
        return this.skipResult(item, "prompt_too_large_after_truncation");
      }

      truncationContext = {
        filesExcluded: truncResult.excluded.length,
        totalFiles: effectiveItem.files.length,
      };

      finalConvergenceUser = this.template.buildConvergenceUserPromptFromTruncation(
        effectiveItem, truncResult, truncated.loaBanner,
      );
    }

    // ═══════════════════════════════════════════════
    // Pass 1 Cache Check (Sprint 70 — AC-4)
    // ═══════════════════════════════════════════════
    const truncationLevel = truncationContext
      ? 1 // simplified: truncation occurred
      : 0; // no truncation

    let pass1CacheHit = false;
    let findingsJSON: string | undefined;
    let pass1Parsed: { findings: Array<{ id: string; severity: string; category: string; confidence?: number; [key: string]: unknown }> } | undefined;
    let pass1InputTokens = 0;
    let pass1OutputTokens = 0;
    let pass1Content = "";

    if (this.pass1Cache && this.hasher) {
      const convergencePromptHash = await this.hasher.sha256(finalConvergenceSystem);
      const cacheKey = await computeCacheKey(
        this.hasher, pr.headSha, truncationLevel, convergencePromptHash,
      );

      const cached = await this.pass1Cache.get(cacheKey);
      if (cached) {
        this.logger.info("Pass 1: Cache HIT — skipping LLM call", {
          owner, repo, pr: pr.number, cacheKey,
          hitCount: cached.hitCount,
        });
        pass1CacheHit = true;
        findingsJSON = cached.findings.raw;
        pass1Parsed = cached.findings.parsed as typeof pass1Parsed;
        pass1InputTokens = cached.tokens.input;
        pass1OutputTokens = cached.tokens.output;
        // Synthesize pass1Content from cached findings for fallback path
        pass1Content = [
          "<!-- bridge-findings-start -->",
          "```json",
          cached.findings.raw,
          "```",
          "<!-- bridge-findings-end -->",
        ].join("\n");
      }
    }

    // LLM Call 1: Convergence (skipped on cache hit)
    if (!pass1CacheHit) {
      this.logger.info("Pass 1: Convergence review", { owner, repo, pr: pr.number });

      let pass1Response;
      try {
        pass1Response = await this.llm.generateReview({
          systemPrompt: finalConvergenceSystem,
          userPrompt: finalConvergenceUser,
          maxOutputTokens: this.config.maxOutputTokens,
        });
      } catch (llmErr: unknown) {
        if (isTokenRejection(llmErr)) {
          const retryBudget = Math.floor(this.config.maxInputTokens * 0.85);
          const retryResult = progressiveTruncate(
            effectiveItem.files, retryBudget, this.config.model,
            finalConvergenceSystem.length, 2000,
          );

          if (!retryResult.success) {
            return this.skipResult(item, "prompt_too_large_after_truncation");
          }

          truncationContext = {
            filesExcluded: retryResult.excluded.length,
            totalFiles: effectiveItem.files.length,
          };

          const retryUser = this.template.buildConvergenceUserPromptFromTruncation(
            effectiveItem, retryResult, truncated.loaBanner,
          );

          pass1Response = await this.llm.generateReview({
            systemPrompt: finalConvergenceSystem,
            userPrompt: retryUser,
            maxOutputTokens: this.config.maxOutputTokens,
          });
        } else {
          throw llmErr;
        }
      }

      pass1InputTokens = pass1Response.inputTokens;
      pass1OutputTokens = pass1Response.outputTokens;
      pass1Content = pass1Response.content;

      // Extract findings JSON from Pass 1
      const pass1Extracted = this.extractFindingsJSON(pass1Response.content);
      if (!pass1Extracted) {
        this.logger.warn("Pass 1 produced no parseable findings, falling back to single-pass validation", {
          owner, repo, pr: pr.number,
        });
        // If Pass 1 content is still a valid review format, use it directly
        if (isValidResponse(pass1Response.content)) {
          return this.finishWithPass1AsReview(item, pass1Response, this.now() - pass1Start);
        }
        return this.skipResult(item, "invalid_llm_response");
      }

      findingsJSON = pass1Extracted.raw;
      pass1Parsed = pass1Extracted.parsed;

      // Store in cache on miss (AC-5)
      if (this.pass1Cache && this.hasher) {
        const convergencePromptHash = await this.hasher.sha256(finalConvergenceSystem);
        const cacheKey = await computeCacheKey(
          this.hasher, pr.headSha, truncationLevel, convergencePromptHash,
        );
        await this.pass1Cache.set(cacheKey, {
          findings: { raw: findingsJSON, parsed: pass1Parsed },
          tokens: { input: pass1InputTokens, output: pass1OutputTokens, duration: 0 },
          timestamp: new Date().toISOString(),
          hitCount: 0,
        });
      }
    }

    const pass1Duration = this.now() - pass1Start;

    // At this point findingsJSON and pass1Parsed are guaranteed set (cache hit or LLM extraction)
    if (!findingsJSON || !pass1Parsed) {
      return this.skipResult(item, "invalid_llm_response");
    }

    // Compute confidence statistics from Pass 1 findings (Task 4.4)
    const confidenceValues = pass1Parsed.findings
      .filter((f): f is typeof f & { confidence: number } => typeof f.confidence === "number")
      .map((f) => f.confidence);
    const pass1ConfidenceStats = confidenceValues.length > 0
      ? {
          min: Math.min(...confidenceValues),
          max: Math.max(...confidenceValues),
          mean: +(confidenceValues.reduce((a, b) => a + b, 0) / confidenceValues.length).toFixed(3),
          count: confidenceValues.length,
        }
      : undefined;

    this.logger.info("Pass 1 complete", {
      owner, repo, pr: pr.number,
      duration: pass1Duration,
      inputTokens: pass1InputTokens,
      outputTokens: pass1OutputTokens,
      confidenceStats: pass1ConfidenceStats ?? null,
      cacheHit: pass1CacheHit,
    });

    // ═══════════════════════════════════════════════
    // PASS 2: Enrichment (persona loaded, no full diff)
    // ═══════════════════════════════════════════════

    const pass2Start = this.now();

    const enrichmentOptions: EnrichmentOptions = {
      findingsJSON,
      item,
      persona: this.persona,
      truncationContext,
      personaMetadata: this.personaMetadata,
      ecosystemContext: this.ecosystemContext,
    };
    const { systemPrompt: enrichmentSystem, userPrompt: enrichmentUser } =
      this.template.buildEnrichmentPrompt(enrichmentOptions);

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
    } catch (enrichErr: unknown) {
      this.logger.warn("Pass 2 failed, using Pass 1 unenriched output", {
        owner, repo, pr: pr.number,
        error: enrichErr instanceof Error ? enrichErr.message : String(enrichErr),
      });
      return this.finishWithUnenrichedOutput(
        item, pass1InputTokens, pass1OutputTokens,
        pass1Duration, findingsJSON, pass1Content, pass1CacheHit,
      );
    }

    const pass2Duration = this.now() - pass2Start;

    // FR-2.4: Validate finding preservation
    const pass2Extracted = this.extractFindingsJSON(pass2Response.content);
    if (pass2Extracted) {
      const preserved = this.validateFindingPreservation(pass1Parsed, pass2Extracted.parsed);
      if (!preserved) {
        this.logger.warn("Pass 2 modified findings, using Pass 1 output", {
          owner, repo, pr: pr.number,
        });
        return this.finishWithUnenrichedOutput(
          item, pass1InputTokens, pass1OutputTokens,
          pass1Duration, findingsJSON, pass1Content, pass1CacheHit,
        );
      }
    } else {
      // Pass 2 lost the structured findings markers — fall back to preserve them
      this.logger.warn("Pass 2 missing findings markers, using Pass 1 output", {
        owner, repo, pr: pr.number,
      });
      return this.finishWithUnenrichedOutput(
        item, pass1InputTokens, pass1OutputTokens,
        pass1Duration, findingsJSON, pass1Content, pass1CacheHit,
      );
    }

    // Validate combined output
    if (!isValidResponse(pass2Response.content)) {
      this.logger.warn("Pass 2 invalid response, using Pass 1 output", {
        owner, repo, pr: pr.number,
      });
      return this.finishWithUnenrichedOutput(
        item, pass1InputTokens, pass1OutputTokens,
        pass1Duration, findingsJSON, pass1Content, pass1CacheHit,
      );
    }

    this.logger.info("Pass 2 complete", {
      owner, repo, pr: pr.number,
      duration: pass2Duration,
      inputTokens: pass2Response.inputTokens,
      outputTokens: pass2Response.outputTokens,
      totalDuration: pass1Duration + pass2Duration,
    });

    // Steps 7-9: Shared post-processing (sanitize → recheck → post → finalize)
    return this.postAndFinalize(item, pass2Response.content, {
      inputTokens: pass1InputTokens + pass2Response.inputTokens,
      outputTokens: pass1OutputTokens + pass2Response.outputTokens,
      pass1Output: pass1Content,
      pass1Tokens: { input: pass1InputTokens, output: pass1OutputTokens, duration: pass1Duration },
      pass2Tokens: { input: pass2Response.inputTokens, output: pass2Response.outputTokens, duration: pass2Duration },
      pass1ConfidenceStats,
      pass1CacheHit,
      personaId: this.personaMetadata.id,
      personaHash: this.personaMetadata.hash,
    });
  }

  /**
   * Handle case where Pass 1 content is a valid review (has Summary+Findings)
   * but findings couldn't be extracted as JSON. Use it directly as the review.
   */
  private async finishWithPass1AsReview(
    item: ReviewItem,
    pass1Response: { content: string; inputTokens: number; outputTokens: number },
    pass1Duration: number,
  ): Promise<ReviewResult> {
    return this.postAndFinalize(item, pass1Response.content, {
      inputTokens: pass1Response.inputTokens,
      outputTokens: pass1Response.outputTokens,
      pass1Output: pass1Response.content,
      pass1Tokens: { input: pass1Response.inputTokens, output: pass1Response.outputTokens, duration: pass1Duration },
    });
  }

  private buildSummary(
    runId: string,
    startTime: string,
    results: ReviewResult[],
  ): RunSummary {
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
