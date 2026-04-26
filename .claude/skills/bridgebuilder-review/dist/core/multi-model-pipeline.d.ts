/**
 * MultiModelPipeline — orchestrates parallel multi-model reviews with consensus scoring.
 *
 * Executes N model reviews in parallel via Promise.allSettled(), scores findings
 * using dual-track consensus (convergence + diversity), and posts per-model
 * comments followed by a consensus summary.
 */
import type { ReviewResponse } from "../ports/llm-provider.js";
import type { IReviewPoster } from "../ports/review-poster.js";
import type { IOutputSanitizer } from "../ports/output-sanitizer.js";
import type { ILogger } from "../ports/logger.js";
import type { BridgebuilderConfig, ReviewItem, ReviewError } from "./types.js";
import type { ScoringResult } from "./scoring.js";
import type { LoreEntry, PRReviewTemplate } from "./template.js";
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
export declare function shouldPostComment(poster: IReviewPoster, config: {
    dryRun: boolean;
}, logger: ILogger, context: string): boolean;
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
export declare function executeMultiModelReview(item: ReviewItem, systemPrompt: string, userPrompt: string, config: BridgebuilderConfig, adapters: PipelineAdapters, enrichment?: EnrichmentContext): Promise<MultiModelReviewResult>;
/**
 * Extract findings from review content by parsing the bridge-findings JSON block.
 * Exported for testing — see bug-20260413-9f9b39.
 */
export declare function extractFindingsFromContent(content: string): Array<{
    id: string;
    title: string;
    severity: string;
    category: string;
    file?: string;
    description: string;
    suggestion?: string;
    confidence?: number;
    [key: string]: unknown;
}>;
//# sourceMappingURL=multi-model-pipeline.d.ts.map