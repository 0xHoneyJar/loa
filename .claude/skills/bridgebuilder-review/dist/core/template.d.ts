import type { IGitProvider } from "../ports/git-provider.js";
import type { IHasher } from "../ports/hasher.js";
import type { BridgebuilderConfig, ReviewItem, TruncationResult, ProgressiveTruncationResult } from "./types.js";
export interface PromptPair {
    systemPrompt: string;
    userPrompt: string;
}
export interface PromptPairWithMeta extends PromptPair {
    allExcluded: boolean;
    loaBanner?: string;
}
export declare class PRReviewTemplate {
    private readonly git;
    private readonly hasher;
    private readonly config;
    constructor(git: IGitProvider, hasher: IHasher, config: BridgebuilderConfig);
    /**
     * Resolve all configured repos into ReviewItem[] by fetching open PRs,
     * their files, and computing a state hash for change detection.
     */
    resolveItems(): Promise<ReviewItem[]>;
    /**
     * Build system prompt: persona with injection hardening prefix.
     */
    buildSystemPrompt(persona: string): string;
    /**
     * Build user prompt: PR metadata + truncated diffs.
     * Returns the PromptPair ready for LLM submission.
     */
    buildPrompt(item: ReviewItem, persona: string): PromptPair;
    /**
     * Build prompt with metadata about Loa filtering (Task 1.5).
     * Returns allExcluded and loaBanner alongside the prompts.
     */
    buildPromptWithMeta(item: ReviewItem, persona: string): PromptPairWithMeta;
    /**
     * Build prompt from progressive truncation result (TruncationPromptBinding — SDD 3.7).
     * Deterministic mapping from truncation output to prompt variables.
     */
    buildPromptFromTruncation(item: ReviewItem, persona: string, truncResult: ProgressiveTruncationResult, loaBanner?: string): PromptPair;
    /**
     * Build convergence system prompt: injection hardening + analytical instructions only.
     * No persona — Pass 1 focuses entirely on finding quality (SDD 3.1).
     */
    buildConvergenceSystemPrompt(): string;
    /**
     * Build convergence user prompt: PR metadata + diffs + findings-only format instructions.
     * Reuses the existing PR metadata/diff rendering but replaces the output format section (SDD 3.2).
     */
    buildConvergenceUserPrompt(item: ReviewItem, truncated: TruncationResult): string;
    /**
     * Build convergence user prompt from progressive truncation result (SDD 3.2 + 3.7 binding).
     */
    buildConvergenceUserPromptFromTruncation(item: ReviewItem, truncResult: ProgressiveTruncationResult, loaBanner?: string): string;
    /**
     * Build enrichment prompt: persona + condensed PR metadata + Pass 1 findings (SDD 3.3).
     * No full diff — Pass 2 enriches findings with educational depth.
     */
    buildEnrichmentPrompt(findingsJSON: string, item: ReviewItem, persona: string): PromptPair;
    private buildUserPrompt;
    private formatIncludedFile;
}
//# sourceMappingURL=template.d.ts.map