/**
 * MultiModelPipeline — orchestrates parallel multi-model reviews with consensus scoring.
 *
 * Executes N model reviews in parallel via Promise.allSettled(), scores findings
 * using dual-track consensus (convergence + diversity), and posts per-model
 * comments followed by a consensus summary.
 */
import type { ILLMProvider, ReviewRequest, ReviewResponse } from "../ports/llm-provider.js";
import type { IReviewPoster, PostCommentInput } from "../ports/review-poster.js";
import type { IOutputSanitizer } from "../ports/output-sanitizer.js";
import type { ILogger } from "../ports/logger.js";
import type {
  BridgebuilderConfig,
  MultiModelConfig,
  ReviewItem,
  ReviewResult,
  ReviewError,
} from "./types.js";
import { scoreFindings } from "./scoring.js";
import type { ModelFindings, ScoringResult } from "./scoring.js";
import { createAdapter } from "../adapters/adapter-factory.js";
import { PROVIDER_API_KEY_ENV, validateApiKeys } from "../config.js";

export interface MultiModelReviewResult {
  /** Per-model review results. */
  modelResults: Array<{
    provider: string;
    model: string;
    response?: ReviewResponse;
    error?: ReviewError;
    posted: boolean;
  }>;
  /** Consensus scoring result across all models. */
  consensus: ScoringResult;
  /** Whether the overall review was posted. */
  posted: boolean;
  /** Combined content from all models. */
  combinedContent: string;
}

export interface PipelineAdapters {
  poster: IReviewPoster;
  sanitizer: IOutputSanitizer;
  logger: ILogger;
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
export async function executeMultiModelReview(
  item: ReviewItem,
  systemPrompt: string,
  userPrompt: string,
  config: BridgebuilderConfig,
  adapters: PipelineAdapters,
): Promise<MultiModelReviewResult> {
  const multiConfig = config.multiModel!;
  const { poster, sanitizer, logger } = adapters;

  // Validate API keys
  const keyStatus = validateApiKeys(multiConfig);
  if (multiConfig.api_key_mode === "strict" && keyStatus.missing.length > 0) {
    throw new Error(
      `Strict mode: missing API keys for providers: ${keyStatus.missing.map((m) => m.provider).join(", ")}`,
    );
  }

  // Create adapters for available providers
  const modelAdapters: Array<{
    provider: string;
    modelId: string;
    adapter: ILLMProvider;
  }> = [];

  for (const entry of keyStatus.valid) {
    const envVar = PROVIDER_API_KEY_ENV[entry.provider];
    const apiKey = envVar ? process.env[envVar] : undefined;
    if (!apiKey) continue;

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
  const concurrency = Math.min(
    modelAdapters.length,
    multiConfig.max_concurrency ?? 3,
  );

  logger.info("[multi-model] Starting parallel review", {
    models: modelAdapters.map((m) => `${m.provider}/${m.modelId}`),
    concurrency,
  });

  // Execute reviews in parallel with concurrency limit
  const request: ReviewRequest = {
    systemPrompt,
    userPrompt,
    maxOutputTokens: config.maxOutputTokens,
  };

  const results = await executeWithConcurrency(
    modelAdapters,
    async (ma) => {
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
    },
    concurrency,
  );

  // Process results
  const modelResults: MultiModelReviewResult["modelResults"] = [];
  const findingsPerModel: ModelFindings[] = [];

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
      if (!config.dryRun && poster.postComment) {
        try {
          const commentBody = formatModelComment(
            ma.provider,
            ma.modelId,
            cleanContent,
            i + 1,
            modelAdapters.length,
          );
          posted = await poster.postComment({
            owner: item.owner,
            repo: item.repo,
            prNumber: item.pr.number,
            body: commentBody,
          });
        } catch (err) {
          logger.warn(`[multi-model:${ma.provider}] Failed to post comment`, {
            error: (err as Error).message,
          });
        }
      }

      modelResults.push({
        provider: ma.provider,
        model: ma.modelId,
        response,
        posted,
      });
    } else {
      const error: ReviewError = {
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
  const consensus = scoreFindings(
    findingsPerModel,
    multiConfig.consensus.scoring_thresholds,
  );

  logger.info("[multi-model] Consensus scoring complete", {
    high_consensus: consensus.stats.high_consensus,
    disputed: consensus.stats.disputed,
    blocker: consensus.stats.blocker,
    unique: consensus.stats.unique,
  });

  // Post consensus summary comment
  let overallPosted = false;
  if (!config.dryRun && poster.postComment && findingsPerModel.length > 1) {
    try {
      const summaryBody = formatConsensusSummary(consensus, modelAdapters);
      overallPosted = await poster.postComment({
        owner: item.owner,
        repo: item.repo,
        prNumber: item.pr.number,
        body: summaryBody,
      });
    } catch (err) {
      logger.warn("[multi-model] Failed to post consensus summary", {
        error: (err as Error).message,
      });
    }
  }

  const combinedContent = modelResults
    .filter((r) => r.response)
    .map((r) => r.response!.content)
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
async function executeWithConcurrency<T, R>(
  items: T[],
  fn: (item: T) => Promise<R>,
  concurrency: number,
): Promise<PromiseSettledResult<R>[]> {
  if (items.length <= concurrency) {
    return Promise.allSettled(items.map(fn));
  }

  const results: PromiseSettledResult<R>[] = new Array(items.length);
  let nextIndex = 0;

  async function worker(): Promise<void> {
    while (nextIndex < items.length) {
      const index = nextIndex++;
      try {
        results[index] = { status: "fulfilled", value: await fn(items[index]) };
      } catch (reason) {
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
 */
function extractFindingsFromContent(content: string): Array<{
  id: string;
  title: string;
  severity: string;
  category: string;
  file?: string;
  description: string;
  suggestion?: string;
  confidence?: number;
  [key: string]: unknown;
}> {
  const match = content.match(
    /<!--\s*bridge-findings-start\s*-->\s*```json\s*([\s\S]*?)```\s*<!--\s*bridge-findings-end\s*-->/,
  );
  if (!match) return [];

  try {
    const parsed = JSON.parse(match[1]);
    if (parsed.findings && Array.isArray(parsed.findings)) {
      return parsed.findings;
    }
  } catch {
    // Malformed findings — return empty
  }

  return [];
}

/**
 * Format a per-model comment with continuation numbering.
 */
function formatModelComment(
  provider: string,
  modelId: string,
  content: string,
  index: number,
  total: number,
): string {
  const header = total > 1
    ? `**[${index}/${total + 1}] Review by ${provider} (${modelId})**\n\n`
    : `**Review by ${provider} (${modelId})**\n\n`;

  return header + content;
}

/**
 * Format the consensus summary comment.
 */
function formatConsensusSummary(
  result: ScoringResult,
  models: Array<{ provider: string; modelId: string }>,
): string {
  const lines: string[] = [];
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
