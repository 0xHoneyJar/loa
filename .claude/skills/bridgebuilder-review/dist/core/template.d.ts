import type { IGitProvider } from "../ports/git-provider.js";
import type { IHasher } from "../ports/hasher.js";
import type { BridgebuilderConfig, ReviewItem, TruncationResult, ProgressiveTruncationResult, PersonaMetadata, EcosystemContext, EnrichmentOptions, TruncationContext, MultiModelConfig } from "./types.js";
export interface PromptPair {
    systemPrompt: string;
    userPrompt: string;
}
export interface PromptPairWithMeta extends PromptPair {
    allExcluded: boolean;
    loaBanner?: string;
}
/** Lore entry structure matching grimoires/loa/lore/patterns.yaml schema. */
export interface LoreEntry {
    id: string;
    term: string;
    short: string;
    context: string;
    source?: string;
    tags?: string[];
}
/** Truncation priority order for context window heterogeneity. */
export declare const TRUNCATION_PRIORITY: readonly ["persona", "lore", "crossRepo", "diff"];
export type TruncationLayer = typeof TRUNCATION_PRIORITY[number];
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
     * For single-model or basic mode — no depth enhancements.
     */
    buildSystemPrompt(persona: string): string;
    /**
     * Build enriched system prompt with Permission to Question, depth expectations,
     * and optionally woven lore entries (T2.3, T2.4, T2.6).
     *
     * Used for Pass 2 (enrichment) in multi-model and enhanced single-model modes.
     * Respects truncation priority: persona > lore > cross-repo > diff.
     *
     * @param persona - The persona content
     * @param options - Optional lore entries and multi-model config
     * @param tokenBudget - Optional per-provider token budget for context window management
     */
    buildEnrichedSystemPrompt(persona: string, options?: {
        loreEntries?: LoreEntry[];
        multiModelConfig?: MultiModelConfig;
        provider?: string;
    }, tokenBudget?: number): string;
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
     * Render PR metadata header lines (shared between convergence prompt variants).
     */
    private renderPRMetadata;
    /**
     * Render excluded files with stats (shared between prompt variants).
     */
    private renderExcludedFiles;
    /**
     * Render convergence-specific "Expected Response Format" section.
     */
    private renderConvergenceFormat;
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
     *
     * Overload 1 (options object — preferred, Sprint 69):
     *   buildEnrichmentPrompt(options: EnrichmentOptions): PromptPair
     *
     * Overload 2 (positional params — deprecated, backward compat):
     *   buildEnrichmentPrompt(findingsJSON, item, persona, truncationContext?, personaMetadata?, ecosystemContext?): PromptPair
     */
    buildEnrichmentPrompt(options: EnrichmentOptions): PromptPair;
    /** @deprecated Use options object overload instead. */
    buildEnrichmentPrompt(findingsJSON: string, item: ReviewItem, persona: string, truncationContext?: TruncationContext, personaMetadata?: PersonaMetadata, ecosystemContext?: EcosystemContext): PromptPair;
    private buildEnrichmentPromptFromOptions;
    /**
     * Check if findings JSON contains at least one finding with a confidence value.
     */
    private findingsHaveConfidence;
    private buildUserPrompt;
    private formatIncludedFile;
}
//# sourceMappingURL=template.d.ts.map