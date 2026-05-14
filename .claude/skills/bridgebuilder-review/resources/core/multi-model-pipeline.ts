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
import type { ModelFindings, ScoredFinding, ScoringResult } from "./scoring.js";
import { createAdapter } from "../adapters/adapter-factory.js";
import { PROVIDER_API_KEY_ENV, validateApiKeys } from "../config.js";
import type { LoreEntry, PRReviewTemplate } from "./template.js";

/**
 * Sprint-bug-143 #789a fix: per-model timeout derivation.
 *
 * Reasoning-class OpenAI models (gpt-5.5-pro and similar) need substantially
 * more time than the prior 300_000ms cap allowed — observed cycle-100
 * sprint-2 BB iter-1: gpt-5.5-pro hung past 900s on a 95k-token diff because
 * the model spends most of its budget on internal reasoning before emitting
 * visible tokens. The previous 300s ceiling forced a silent timeout and
 * BB degraded to single-model.
 *
 * Detection by model_id substring is intentionally narrow — we want to grant
 * the longer budget ONLY where it's needed, not as a blanket increase. New
 * reasoning-class models added to the BB triad must extend this regex.
 *
 * 1_800_000ms = 30min, comfortably above gpt-5.5-pro's observed 900-1100s
 * end-to-end on large reviews while keeping operator-visible latency bounded.
 */
function isReasoningClassOpenAI(provider: string, modelId: string): boolean {
  if (provider !== "openai") return false;
  // gpt-5.5-pro, gpt-5.6-pro, etc. — `pro` suffix on /v1/responses path.
  // Codex variants (gpt-5.3-codex) are non-reasoning despite using
  // /v1/responses; exclude them via the `-pro` anchor.
  return /^gpt-\d+(\.\d+)?-pro$/i.test(modelId);
}

export function deriveTimeoutMs(
  provider: string,
  modelId: string,
  config: BridgebuilderConfig,
): number {
  if (isReasoningClassOpenAI(provider, modelId)) {
    return 1_800_000; // 30 minutes
  }
  // Existing tiered ladder for non-reasoning paths.
  return config.maxInputTokens > 100_000 ? 300_000 :
         config.maxInputTokens > 50_000 ? 180_000 :
         120_000;
}

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
 * Guard helper: returns true when a PR comment should be posted, and logs
 * a warning if postComment is missing in non-dry-run mode.
 *
 * Addresses bug-20260413-i464-9d4f51 / Issue #464 A2: HITL could not
 * distinguish "comment posting unsupported" from "comment posting failed".
 */
export function shouldPostComment(
  poster: IReviewPoster,
  config: { dryRun: boolean },
  logger: ILogger,
  context: string,
): boolean {
  if (config.dryRun) return false;
  if (!poster.postComment) {
    logger.warn(`[multi-model] Poster does not implement postComment; ${context} skipped`);
    return false;
  }
  return true;
}

/**
 * Optional Pass-2 enrichment context. When provided, executeMultiModelReview()
 * invokes ONE designated "writer" model to produce a human-readable consensus
 * review with metaphors, FAANG parallels, and teachable moments.
 *
 * See bug-20260413-enrich: multi-model posts were unreadable raw JSON.
 */
export interface EnrichmentContext {
  /** Template used to build enrichment prompt. */
  template: PRReviewTemplate;
  /** Persona string for enrichment voice. */
  persona: string;
  /**
   * Optional lore entries. When provided AND `depth_5.lore_active_weaving`
   * is true, the enrichment system prompt includes a Lore Context section.
   * Closes #464 A5 — load via `core/lore-loader.ts` in main.ts.
   */
  loreEntries?: LoreEntry[];
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
  enrichment?: EnrichmentContext,
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
      if (shouldPostComment(poster, config, logger, "per-model comment") && poster.postComment) {
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

  // Pass-2 enrichment: generate human-readable consensus review (Option C).
  // When enrichment context provided, the first primary model writes a prose
  // review over the consensus findings. Falls back to stats-only if enrichment
  // fails or is disabled.
  // cycle-109 Sprint 2 T2.6 — prepend the verdict_quality header
  // (FR-2.8) before the consensus stats table. Returns empty string when
  // no per-model envelopes carry verdictQuality (legacy / pre-T2.3
  // cheval), so legacy review surfaces are unchanged.
  const verdictHeader = formatVerdictQualityHeader(
    modelResults.map((r) => ({
      provider: r.provider,
      modelId: r.model,
      verdictQuality: r.response?.verdictQuality,
    })),
  );
  let consensusBody = verdictHeader + formatConsensusSummary(consensus, modelAdapters);

  if (enrichment && findingsPerModel.length > 0 && modelAdapters.length > 0) {
    try {
      logger.info("[multi-model] Generating enriched consensus review...");
      const enrichedContent = await generateEnrichedConsensusReview(
        item,
        consensus,
        modelAdapters,
        config,
        enrichment,
        adapters.sanitizer,
        adapters.logger,
      );
      if (enrichedContent) {
        // Prepend stats to enriched prose for quick-scan visibility
        consensusBody = formatEnrichedConsensusSummary(consensus, modelAdapters, enrichedContent);
        logger.info("[multi-model] Enrichment complete", {
          enrichedBytes: enrichedContent.length,
        });
      }
    } catch (err) {
      logger.warn("[multi-model] Enrichment failed, using stats-only summary", {
        error: (err as Error).message,
      });
    }
  }

  // Post consensus summary comment
  let overallPosted = false;
  if (
    shouldPostComment(poster, config, logger, "consensus summary") &&
    poster.postComment &&
    findingsPerModel.length > 1
  ) {
    try {
      overallPosted = await poster.postComment({
        owner: item.owner,
        repo: item.repo,
        prNumber: item.pr.number,
        body: consensusBody,
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
 * Exported for testing — see bug-20260413-9f9b39.
 */
export function extractFindingsFromContent(content: string): Array<{
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
/**
 * cycle-109 Sprint 2 T2.6 — render an operator-facing verdict_quality
 * header for the BB PR comment (FR-2.8 surface).
 *
 * Takes per-model results carrying their `verdictQuality` envelopes
 * (populated by ChevalDelegateAdapter from the LOA_VERDICT_QUALITY_SIDECAR
 * transport) and produces a short markdown header line:
 *
 *   ✓ APPROVED — 3/3 voices, chain ok
 *   ⚠ DEGRADED — 2/3 voices succeeded
 *   ❌ FAILED — chain exhausted; verdict unsafe
 *
 * Returns an empty string when:
 *   - The input list is empty.
 *   - No per-model result carries a `verdictQuality` envelope (legacy /
 *     pre-T2.3 cheval emits, or the sidecar mechanism is unavailable).
 *
 * Note: this is a presentation-layer summary, not the canonical aggregate.
 * Persistence of the full multi-voice envelope happens at the FL orchestrator
 * level (T2.4) via the Python aggregator. BB's PR comment surfaces the
 * status banner derived from per-model envelopes for operator-visibility.
 */
export function formatVerdictQualityHeader(
  perModelResults: Array<{
    provider: string;
    modelId: string;
    verdictQuality?: {
      status?: string;
      voices_succeeded?: number;
      voices_planned?: number;
      chain_health?: string;
    };
  }>,
): string {
  if (perModelResults.length === 0) return "";

  const withEnvelope = perModelResults.filter((r) => r.verdictQuality);
  if (withEnvelope.length === 0) return "";

  // Aggregate stats from per-voice envelopes. Each cheval cmd_invoke
  // produces a SINGLE-voice envelope (voices_planned=1). For the BB
  // multi-voice cohort we count the number of envelopes that ended in
  // each status.
  const total = perModelResults.length;
  const succeeded = withEnvelope.filter(
    (r) => r.verdictQuality?.status === "APPROVED" || r.verdictQuality?.status === "DEGRADED",
  ).length;
  const anyFailed = withEnvelope.some((r) => r.verdictQuality?.status === "FAILED");
  const anyDegraded = withEnvelope.some(
    (r) => r.verdictQuality?.status === "DEGRADED" || r.verdictQuality?.chain_health === "degraded",
  );
  const allApproved = withEnvelope.every((r) => r.verdictQuality?.status === "APPROVED");

  // Promote to FAILED if any voice failed OR if not all voices ran (we
  // never received envelopes for the missing ones, suggesting they
  // didn't reach cheval) AND the responding voices are degraded.
  const missingVoices = total - withEnvelope.length;

  let banner: string;
  if (anyFailed || (missingVoices === total)) {
    banner = `❌ FAILED — ${succeeded}/${total} voices succeeded; verdict unsafe`;
  } else if (anyDegraded || missingVoices > 0 || !allApproved) {
    banner = `⚠ DEGRADED — ${succeeded}/${total} voices succeeded`;
  } else {
    banner = `✓ APPROVED — ${succeeded}/${total} voices, chain ok`;
  }

  return `**Verdict Quality**: ${banner}\n\n`;
}

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

/**
 * Generate a human-readable enriched review from consensus findings (Option C).
 *
 * Takes the scored consensus findings and invokes ONE designated "writer" model
 * (the first primary model in config.multiModel.models, or first available) to
 * produce a Pass-2 enriched review with metaphors, FAANG parallels, and teachable
 * moments. This closes the HITL readability gap — multi-model reviews now
 * include the educational prose that single-model reviews already have.
 */
async function generateEnrichedConsensusReview(
  item: ReviewItem,
  consensus: ScoringResult,
  modelAdapters: Array<{ provider: string; modelId: string; adapter: ILLMProvider }>,
  config: BridgebuilderConfig,
  enrichment: EnrichmentContext,
  sanitizer: IOutputSanitizer,
  logger: ILogger,
): Promise<string | null> {
  // Pick writer: first model with role=primary in config, else first available
  const multiConfig = config.multiModel!;
  const primaryEntry = multiConfig.models.find((m) => m.role === "primary");
  const writerTarget = primaryEntry ?? multiConfig.models[0];
  const writer = modelAdapters.find(
    (m) => m.provider === writerTarget.provider && m.modelId === writerTarget.model_id,
  ) ?? modelAdapters[0];

  if (!writer) {
    logger.warn("[multi-model] No writer model available for enrichment");
    return null;
  }

  // Build findings JSON from consensus (convergence track)
  // Preserve only the canonical finding from each group
  const findingsForEnrichment = consensus.convergence.map((scored: ScoredFinding) => ({
    ...scored.finding,
    // Add consensus metadata as non-enriched fields
    agreeing_models: scored.agreeing_models,
    consensus_classification: scored.classification,
  }));

  const findingsJSON = JSON.stringify(
    { schema_version: 1, findings: findingsForEnrichment },
    null,
    2,
  );

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
function formatEnrichedConsensusSummary(
  result: ScoringResult,
  models: Array<{ provider: string; modelId: string }>,
  enrichedContent: string,
): string {
  const lines: string[] = [];
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
