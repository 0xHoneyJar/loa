import type { IGitProvider } from "../ports/git-provider.js";
import type { ILLMProvider } from "../ports/llm-provider.js";
import type { IReviewPoster } from "../ports/review-poster.js";
import type { IOutputSanitizer } from "../ports/output-sanitizer.js";
import type { ILogger } from "../ports/logger.js";
import type { IHasher } from "../ports/hasher.js";
import type { PRReviewTemplate } from "./template.js";
import type { BridgebuilderContext } from "./context.js";
import type { BridgebuilderConfig, RunSummary, PersonaMetadata, EcosystemContext } from "./types.js";
import type { ValidatedFinding } from "./schemas.js";
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
    private readonly personaMetadata;
    private ecosystemContext;
    private readonly pass1Cache;
    private readonly hasher;
    constructor(template: PRReviewTemplate, context: BridgebuilderContext, git: IGitProvider, poster: IReviewPoster, llm: ILLMProvider, sanitizer: IOutputSanitizer, logger: ILogger, persona: string, config: BridgebuilderConfig, now?: () => number, hasher?: IHasher);
    /**
     * Load ecosystem context from the configured JSON file path.
     * Validates structure; silently ignores missing/malformed files.
     */
    static loadEcosystemContext(filePath: string | undefined, logger: ILogger): EcosystemContext | undefined;
    /**
     * Parse persona frontmatter to extract identity metadata.
     * Expected format: <!-- persona-version: X | agent: Y -->
     * Fallback: { id: "unknown", version: "0.0.0", hash: sha256(content) }
     */
    static parsePersonaMetadata(content: string): PersonaMetadata;
    /**
     * Post-bridge hook: extract high-quality patterns from findings and update ecosystem context (AC-7).
     * Orchestrates extractEcosystemPatterns() + updateEcosystemContext().
     * Called by run-bridge finalization after each bridge iteration.
     */
    static updateEcosystemFromFindings(findings: ValidatedFinding[], repo: string, pr: number, contextPath: string, logger: ILogger): Promise<void>;
    run(runId: string): Promise<RunSummary>;
    private processItem;
    private classifyError;
    /** cycle-133 C-1: nothing could be fetched for review; post the coverage notice and report the degradation. */
    private degradedFetchResult;
    private skipResult;
    private errorResult;
    /**
     * Shared post-processing: sanitize → recheck guard (with retry) → dry-run gate → post → finalize.
     * All review completion paths delegate here to avoid duplication (medium-1).
     *
     * resultFields may include pass1Output, pass1Tokens, and pass2Tokens — these are
     * populated by two-pass callers only. Single-pass callers pass inputTokens/outputTokens only.
     */
    private postAndFinalize;
    /**
     * Extract findings JSON from content enclosed in bridge-findings markers (SDD 3.5).
     * Uses zod FindingsBlockSchema for runtime validation (Sprint 69 — schema-first).
     * Returns { raw, parsed } or null if markers/JSON are missing or malformed.
     */
    private extractFindingsJSON;
    /**
     * Validate that Pass 2 preserved all findings from Pass 1 (SDD 3.6, FR-2.4).
     * Checks: same count, same IDs, same severities, same categories.
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