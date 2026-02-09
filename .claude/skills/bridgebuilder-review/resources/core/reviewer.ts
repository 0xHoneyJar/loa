import { GitProviderError } from "../ports/git-provider.js";
import type { IGitProvider } from "../ports/git-provider.js";
import { LLMProviderError } from "../ports/llm-provider.js";
import type { ILLMProvider } from "../ports/llm-provider.js";
import type { IReviewPoster, ReviewEvent } from "../ports/review-poster.js";
import type { IOutputSanitizer } from "../ports/output-sanitizer.js";
import type { ILogger } from "../ports/logger.js";
import type { PRReviewTemplate } from "./template.js";
import type { BridgebuilderContext } from "./context.js";
import type {
  BridgebuilderConfig,
  ReviewItem,
  ReviewResult,
  ReviewError,
  RunSummary,
} from "./types.js";
import {
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
  ) {}

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

      // Step 8: Sanitize output
      const sanitized = this.sanitizer.sanitize(response.content);

      if (!sanitized.safe && this.config.sanitizerMode === "strict") {
        this.logger.error("Sanitizer blocked review in strict mode", {
          owner,
          repo,
          pr: pr.number,
          redactions: sanitized.redactedPatterns?.length ?? 0,
        });
        return this.errorResult(
          item,
          makeError(
            "E_SANITIZER_BLOCKED",
            "Review blocked by sanitizer in strict mode",
            "sanitizer",
            "permanent",
            false,
          ),
        );
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
      } catch {
        // Retry once — this is the last gate before posting
        try {
          recheck = await this.poster.hasExistingReview(owner, repo, pr.number, pr.headSha);
        } catch {
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
      } else {
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
      const result: ReviewResult = {
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
