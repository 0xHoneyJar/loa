import type { IGitProvider } from "../ports/git-provider.js";
import type { ILLMProvider } from "../ports/llm-provider.js";
import type { IReviewPoster } from "../ports/review-poster.js";
import type { IOutputSanitizer } from "../ports/output-sanitizer.js";
import type { ILogger } from "../ports/logger.js";
import type { PRReviewTemplate } from "./template.js";
import type { BridgebuilderContext } from "./context.js";
import type { BridgebuilderConfig, RunSummary } from "./types.js";
export declare class ReviewPipeline {
    private readonly template;
    private readonly context;
    private readonly git;
    private readonly poster;
    private readonly llm;
    private readonly sanitizer;
    private readonly logger;
    private readonly persona;
    private readonly config;
    private readonly now;
    constructor(template: PRReviewTemplate, context: BridgebuilderContext, git: IGitProvider, poster: IReviewPoster, llm: ILLMProvider, sanitizer: IOutputSanitizer, logger: ILogger, persona: string, config: BridgebuilderConfig, now?: () => number);
    run(runId: string): Promise<RunSummary>;
    private processItem;
    private classifyError;
    private skipResult;
    private errorResult;
    /**
     * Extract findings JSON from content enclosed in bridge-findings markers (SDD 3.5).
     * Returns the raw JSON string or null if markers/JSON are missing or malformed.
     */
    private extractFindingsJSON;
    /**
     * Validate that Pass 2 preserved all findings from Pass 1 (SDD 3.6, FR-2.4).
     * Checks: same count, same IDs, same severities.
     */
    private validateFindingPreservation;
    /**
     * Fallback: wrap Pass 1 findings in minimal valid review format (SDD 3.7, FR-2.7).
     * Used when Pass 2 fails or modifies findings.
     */
    private finishWithUnenrichedOutput;
    /**
     * Two-pass review flow: convergence (analytical) then enrichment (persona) (SDD 3.4).
     * Pass 1 produces findings JSON; Pass 2 enriches with educational depth.
     * Pass 2 failure is always safe — falls back to Pass 1 unenriched output.
     */
    private processItemTwoPass;
    /**
     * Handle case where Pass 1 content is a valid review (has Summary+Findings)
     * but findings couldn't be extracted as JSON. Use it directly as the review.
     */
    private finishWithPass1AsReview;
    private buildSummary;
}
//# sourceMappingURL=reviewer.d.ts.map