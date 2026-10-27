import type { PullRequest, PullRequestFile } from "../ports/git-provider.js";
import type { DegradedReason } from "./degraded-reason.js";
/**
 * cycle-133 C-1: why a listed file's diff was not (fully) reviewed. `excluded_*` and `renamed` never degrade; the
 * others degrade (and block the merge as incomplete_coverage) when the file is a reviewable code file.
 */
export type OmissionReason = "excluded_loa" | "excluded_pattern" | "excluded_fail_closed" | "file_cap" | "byte_budget" | "no_patch" | "patch_truncated" | "renamed" | "page_incomplete";
/** cycle-133 C-1: the coverage record (summary JSON in full; the posted comment shows counts + the first 20 paths). */
export interface CoverageRecord {
    base_sha: string;
    head_sha: string;
    /** GitHub's changed_files count for the pinned head. */
    changed_files: number;
    /** Distinct files the paged listing returned (≤ 3,000). */
    listed: number;
    reviewed: Array<{
        file: string;
        bytes: number;
        hunks: number;
        /** cycle-135 C-3: the patch was synthesized from the file's content (an added file GitHub returned without a patch). */
        source?: "contents";
    }>;
    /** Named omissions; a patch_truncated file is also in `reviewed` (its retained bytes). */
    omitted: Array<{
        file: string;
        reason: OmissionReason;
        reviewable: boolean;
        /** cycle-135 C-2: the default or user pattern that excluded the file (excluded_loa / excluded_pattern). */
        pattern?: string;
        /**
         * cycle-135 C-3: the outcome of an attempted content fetch for a patch-less added file. `budget`: the read (or the
         * file's size) did not fit the diff budget left after the patches selected ahead of it; `aborted`: not attempted
         * after a RATE_LIMITED / FORBIDDEN answer stopped the loop (review round 1).
         */
        fetch?: "binary" | "too_large" | "error" | "skipped_cap" | "deadline" | "budget" | "aborted";
    }>;
    /** Files GitHub counted but the listing never named (changed_files − listed). */
    unknown_omitted: number;
    degraded: boolean;
    degraded_reasons: DegradedReason[];
    mergeBlockedReason?: "incomplete_coverage";
    /** Head/base moves that restarted the fetch (at most 1; a second move degrades as pr_head_moved). */
    restarts: number;
    /** cycle-135 C-2: protected files a wildcard user exclusion would have removed; the first matching wildcard pattern. */
    protected_kept?: Array<{
        file: string;
        pattern: string;
    }>;
    /**
     * cycle-135 C-2: where the `.reviewignore` patterns came from — the PR base sha, the checkout (no base known), the
     * checkout because the base read failed (`base_unavailable`: the review degrades as `reviewignore_unavailable`,
     * review round 1), or nowhere.
     */
    reviewignore_source?: ReviewignoreSource;
    /** cycle-135 C-2: the PR's file list contains `.reviewignore` (the file itself is protected and reviewed). */
    reviewignore_changed_in_pr?: boolean;
}
export interface BridgebuilderConfig {
    repos: Array<{
        owner: string;
        repo: string;
    }>;
    model: string;
    maxPrs: number;
    maxFilesPerPr: number;
    maxDiffBytes: number;
    maxInputTokens: number;
    maxOutputTokens: number;
    dimensions: string[];
    reviewMarker: string;
    repoOverridePath: string;
    dryRun: boolean;
    excludePatterns: string[];
    /**
     * cycle-135 C-2 (`bridgebuilder.protected_paths`): paths a wildcard user exclusion cannot remove from the review
     * set. `undefined` = DEFAULT_PROTECTED_PATHS; `[]` disables protection; a set list replaces the default.
     */
    protectedPaths?: string[];
    /** cycle-135 C-3 (`bridgebuilder.fetch_missing_patches`): fetch the content of added files GitHub returned without a patch. `undefined` = true. */
    fetchMissingPatches?: boolean;
    /** cycle-135 C-3 (`bridgebuilder.max_content_fetches`): at most this many content fetches per review. `undefined` = 20. */
    maxContentFetches?: number;
    sanitizerMode: "default" | "strict";
    maxRuntimeMinutes: number;
    /** When set (via --pr flag), filters fetchPRItems() to this single PR number. */
    targetPr?: number;
    /** Explicit Loa-aware mode override. true=force on, false=force off, undefined=auto-detect. */
    loaAware?: boolean;
    /**
     * Per-PR self-review opt-in. When true, the Loa-aware filter (Step 0 of
     * truncateFiles) is skipped — framework files under `.claude/`, `grimoires/`,
     * `.beads/`, etc. are admitted into the review payload.
     *
     * Set per-call by reviewer.ts when the PR carries the `bridgebuilder:self-review`
     * label. This is the per-PR opt-in vision-013 names — reviews of bridgebuilder
     * itself, of cycle-planning artifacts, or of other framework changes need to
     * see the substrate, not be blinded by the filter that protects code-PR review
     * from grimoire noise. Closes #796.
     *
     * NOTE: this is intentionally a per-call override, not a config-wide knob.
     * `loaAware: false` already exists for global disable; `selfReview: true` is
     * the per-PR signal that flows from PR labels to the truncate call.
     */
    selfReview?: boolean;
    /** Git repo root for path resolution (defaults to cwd). */
    repoRoot?: string;
    /** Persona pack name (e.g. "security", "dx"). */
    persona?: string;
    /** Custom persona file path. */
    personaFilePath?: string;
    /** Force full review even when incremental context is available (V3-1). */
    forceFullReview?: boolean;
    /** Review mode: two-pass (convergence + enrichment) or single-pass (legacy). */
    reviewMode: "two-pass" | "single-pass";
    /**
     * cycle-133 C-1 (`bridgebuilder.gh_max_buffer_bytes`): per-call `gh` stdout buffer in bytes (default 64 MiB). One call
     * receives one page of the files list, so this bounds received bytes per page.
     */
    ghMaxBufferBytes?: number;
    /** Path to ecosystem context JSON file for cross-repo pattern hints (Pass 0 prototype). */
    ecosystemContextPath?: string;
    /** Pass 1 convergence cache configuration (Sprint 70). */
    pass1Cache?: {
        enabled: boolean;
    };
    /** Multi-model review configuration. When enabled, multiple models review in parallel. */
    multiModel?: MultiModelConfig;
    /**
     * cycle-129 D-7.5 (DEC-0170): the provider declarations, locality and exit key read from TRUSTED configuration only
     * (the base branch's config or repository settings on a pull request, the working tree locally). Set by main.ts.
     */
    trusted?: TrustedConfig;
}
/** One `hounfour.providers.<name>` declaration as Bridgebuilder reads it (cycle-129 D-7.5, D-8.0 canonical keys). */
export interface ProviderDecl {
    /** `keyless: true`, or a literal `auth` value (normalised to keyless, D-8.0): no credential env var is required. */
    keyless: boolean;
    /** `allow_insecure_endpoint` is set (any non-null, non-false value). */
    insecure: boolean;
    /** The env var named by an `auth: "{env:VAR}"` template, when the declaration has one. */
    authEnv?: string;
    /** Provider-level `dispatch_group`, when declared. */
    dispatchGroup?: string;
    /** `models.<model_id>.dispatch_group` per declared model. */
    modelGroups: Record<string, string | undefined>;
    /** The declared `endpoint` (a string), when there is one — the local-hop rule reads its host (D-8.1, r257-1). */
    endpoint?: string;
    /** A CLI provider (`type: *-headless`, or every model `kind: cli`): never local (D-8.1, r257-1). */
    cli?: boolean;
    /**
     * `models.<model_id>.fallback_chain` per declared model that has one (audit a257-1 MEDIUM-A1 (c)): cheval walks it
     * inside one call, so a local voice is local only when every entry is. A non-string entry is kept as "" (unresolvable).
     */
    modelFallbacks?: Record<string, string[]>;
}
/** Where the trusted provider configuration was read from. */
export type TrustedConfigSource = "working-tree" | "base-ref" | "repository-settings" | "none";
/** The trusted configuration view (cycle-129 D-7.5, D-7.7, D-8.1). */
export interface TrustedConfig {
    /** `pull-request` when run on a PR (`--pr`, `GITHUB_EVENT_NAME`, `GITHUB_BASE_REF`); `local` otherwise. */
    mode: "local" | "pull-request";
    source: TrustedConfigSource;
    /** The git ref the base config was read from (`source: base-ref`). */
    ref?: string;
    /** `hounfour.providers` from the trusted source only. */
    providers: Record<string, ProviderDecl>;
    /** Providers the head checkout declares keyless or insecure that the trusted source does not: refused by name. */
    headOnlyRefused: string[];
    /** `hounfour.locality` (default `hosted`). */
    locality: "hosted" | "local_voices";
    /** `bridgebuilder.exit_on_degraded` (default 3; 0 restores the pre-cycle-129 exit). */
    exitOnDegraded: number;
    /**
     * cycle-133 C-2: `bridgebuilder.writer_role_allowlist` from the trusted source only (a PR head cannot widen who
     * writes the commentary). Undefined = the default; the effective list is always ∩ the proven no-tool routes.
     */
    writerRoleAllowlist?: string[];
    /** Lines to log once at startup (read failures, refusals, invalid values). */
    warnings: string[];
    /** `hounfour.aliases` from the trusted source (string targets only) — resolves `fallback_chain` aliases (MEDIUM-A1 (c)). */
    aliases?: Record<string, string>;
    /**
     * Pull-request mode only (audit a257-1 MEDIUM-A2): the dotted keys among `hounfour.providers.<name>`,
     * `hounfour.aliases.<alias>`, `hounfour.locality` and the secret allowlists that differ between the PR head and the
     * trusted source. cheval reads the checkout's configuration for the dispatch, so a non-empty list refuses the
     * multi-model run (main.ts, exit 5). Always `[]` in local mode.
     */
    headDrift?: string[];
}
/** Multi-model provider configuration entry. */
export interface MultiModelProviderEntry {
    provider: string;
    model_id: string;
    role: "primary" | "reviewer";
}
/** Multi-model Bridgebuilder configuration. */
export interface MultiModelConfig {
    enabled: boolean;
    models: MultiModelProviderEntry[];
    iteration_strategy: "every" | "final" | number[];
    api_key_mode: "graceful" | "strict";
    consensus: {
        enabled: boolean;
        scoring_thresholds: {
            high_consensus: number;
            disputed_delta: number;
            low_value: number;
            blocker: number;
        };
    };
    token_budget: {
        per_model: number | null;
        total: number | null;
    };
    depth: {
        structural_checklist: boolean;
        checklist_min_elements: number;
        permission_to_question: boolean;
        lore_active_weaving: boolean;
        /**
         * Path to the lore patterns YAML file. Used only when
         * `lore_active_weaving === true`. Defaults to
         * `grimoires/loa/lore/patterns.yaml` (DEFAULT_LORE_PATH in lore-loader.ts).
         */
        lore_path?: string;
    };
    cross_repo: {
        auto_detect: boolean;
        manual_refs: string[];
        /** #1014: extra owners whose auto-detected refs may be fetched (org-only by default). */
        allowed_owners: string[];
    };
    rating: {
        enabled: boolean;
        timeout_seconds: number;
        retrospective_command: boolean;
    };
    progress: {
        verbose: boolean;
    };
    max_concurrency?: number;
    cost_rates?: Record<string, {
        input: number;
        output: number;
    }>;
}
export interface ReviewItem {
    owner: string;
    repo: string;
    pr: PullRequest;
    files: PullRequestFile[];
    hash: string;
    /** cycle-133 C-1: the two-pass fetch's coverage record (absent for providers without the paged contract). */
    coverage?: CoverageRecord;
    /** cycle-133 C-1: the global selection the fetch made (`included` === `files`); callers reuse it, never re-select. */
    selection?: TruncationResult;
}
export type ErrorCategory = "transient" | "permanent" | "unknown";
export interface ReviewError {
    code: string;
    message: string;
    category: ErrorCategory;
    retryable: boolean;
    source: "github" | "llm" | "sanitizer" | "pipeline";
}
/** Token metrics for a single LLM pass. */
export interface PassTokenMetrics {
    input: number;
    output: number;
    duration: number;
}
export interface ReviewResult {
    item: ReviewItem;
    posted: boolean;
    skipped: boolean;
    skipReason?: string;
    inputTokens?: number;
    outputTokens?: number;
    error?: ReviewError;
    /** Raw Pass 1 response content (for observability — FR-5.2). */
    pass1Output?: string;
    /** Token metrics for convergence pass (two-pass mode only). */
    pass1Tokens?: PassTokenMetrics;
    /** Token metrics for enrichment pass (two-pass mode only). */
    pass2Tokens?: PassTokenMetrics;
    /** Confidence statistics from Pass 1 findings (two-pass mode only). */
    pass1ConfidenceStats?: {
        min: number;
        max: number;
        mean: number;
        count: number;
    };
    /** Persona identity for provenance tracking (two-pass mode only). */
    personaId?: string;
    /** SHA-256 hash of persona content for integrity verification. */
    personaHash?: string;
    /** Whether Pass 1 findings were served from cache (Sprint 70). */
    pass1CacheHit?: boolean;
    /** Explicit review-body decision; absence is never merge clearance. */
    verdict?: "REQUEST_CHANGES" | "APPROVE" | "COMMENT" | "UNKNOWN";
    highestSeverity?: string | null;
    mergeBlocked?: boolean;
    /** cycle-133 C-1/C-2: why the merge is blocked when a degradation, not the verdict, blocks it. */
    mergeBlockedReason?: string;
    /** cycle-133 C-1/C-2: the review completed degraded (exit `bridgebuilder.exit_on_degraded`, default 3). */
    degraded?: boolean;
    /** cycle-133: the primary degraded reason (first in enumeration order). */
    degradedReason?: DegradedReason;
    degradedReasons?: DegradedReason[];
}
export interface RunSummary {
    reviewed: number;
    skipped: number;
    errors: number;
    startTime: string;
    endTime: string;
    runId: string;
    results: ReviewResult[];
}
/** cycle-135 C-2 (DEC-1027) / cycle-136 Task 1.0: where the applied `.reviewignore` was read from. */
export type ReviewignoreSource = "base" | "checkout" | "base_unavailable" | "none";
/**
 * cycle-136 Task 1.0 (DEC-1069, DEC-1070): the selection's configuration — the `BridgebuilderConfig` keys `truncateFiles`
 * reads plus the `.reviewignore` provenance inputs (moved here from paged-fetch.ts so the two modules share one type).
 */
export type SelectionConfig = Pick<BridgebuilderConfig, "excludePatterns" | "maxDiffBytes" | "maxFilesPerPr" | "loaAware" | "repoRoot" | "selfReview" | "protectedPaths" | "fetchMissingPatches" | "maxContentFetches"> & {
    /** cycle-135 C-2 (DEC-1027): read `.reviewignore` at this PR base sha (undefined: the checkout copy). */
    reviewignoreBaseSha?: string;
    /** cycle-136 C-2 (DEC-1069, D-2.5): the base `.reviewignore` already resolved by paged-fetch (contents API); wins over the sha read. */
    reviewignoreBase?: {
        patterns: string[];
        source: "base" | "none";
    };
};
export interface TruncationResult {
    included: PullRequestFile[];
    /** cycle-135 C-2 (review round 1): `pattern` is the default or user pattern that excluded the file, when one did. */
    excluded: Array<{
        filename: string;
        stats: string;
        pattern?: string;
    }>;
    totalBytes: number;
    /** cycle-135 C-2: protected files kept although a wildcard user exclusion matched them (the first matching wildcard). */
    protectedKept?: Array<{
        file: string;
        pattern: string;
    }>;
    /** cycle-135 C-2 / cycle-136 Task 1.0 (DEC-1070): where the applied `.reviewignore` came from; undefined when it was not consulted. */
    reviewignoreSource?: ReviewignoreSource;
    /** True when all files were excluded by Loa filtering (no app files remain). */
    allExcluded?: boolean;
    /** Banner string when Loa files were excluded. */
    loaBanner?: string;
    /** Loa exclusion statistics. */
    loaStats?: {
        filesExcluded: number;
        bytesSaved: number;
    };
    /**
     * True when the self-review opt-in (#796 / vision-013) was active AND
     * succeeded for this truncation pass — framework files were admitted.
     *
     * BB-797-001 (iter-3): typed; never substring-match the banner prose.
     * BB-797-004-typing (iter-4): required, not optional.
     *
     * BB-797-002 (iter-5): kept as a convenience mirror of `selfReviewState ===
     * "active"`. Downstream consumers needing to distinguish "rejected" from
     * "inactive" (cache keys, audit) MUST read `selfReviewState` instead — the
     * boolean lossy-encodes the tri-state and produces cache collisions.
     */
    selfReviewActive: boolean;
    /**
     * Tri-state self-review outcome (#797 iter-5 BB-797-002):
     *   - "inactive": no self-review label on PR (default-filter path ran)
     *   - "active":   label present + .reviewignore readable + framework files admitted
     *   - "rejected": label present BUT .reviewignore unreadable → fail-closed
     *                 to default filter (BB-797-001-security iter-4)
     *
     * Cache keys MUST dimension on this field, not the boolean: "inactive" and
     * "rejected" both yield selfReviewActive=false but produce different prompts.
     */
    selfReviewState: "inactive" | "active" | "rejected";
    /** Truncation level applied (undefined = no progressive truncation). */
    truncationLevel?: 1 | 2 | 3;
    /** Disclaimer text for the current truncation level. */
    truncationDisclaimer?: string;
}
export interface LoaDetectionResult {
    isLoa: boolean;
    version?: string;
    source: "file" | "config_override";
}
/** Security pattern entry with category and rationale for auditability. */
export interface SecurityPatternEntry {
    pattern: RegExp;
    category: string;
    rationale: string;
}
/** Per-model token budget constants. */
export interface TokenBudget {
    maxInput: number;
    maxOutput: number;
    coefficient: number;
}
/** Progressive truncation result from the retry loop. */
export interface ProgressiveTruncationResult {
    success: boolean;
    level?: 1 | 2 | 3;
    files: PullRequestFile[];
    excluded: Array<{
        filename: string;
        stats: string;
    }>;
    totalBytes: number;
    disclaimer?: string;
    tokenEstimate?: TokenEstimateBreakdown;
}
/** Persona identity and version for provenance tracking. */
export interface PersonaMetadata {
    id: string;
    version: string;
    hash: string;
}
/** Cross-repository pattern hints for enrichment context (Pass 0 prototype). */
export interface EcosystemContext {
    patterns: Array<{
        repo: string;
        pr?: number;
        pattern: string;
        connection: string;
    }>;
    lastUpdated: string;
}
/** Truncation context passed from Pass 1 to Pass 2 for enrichment awareness. */
export interface TruncationContext {
    filesExcluded: number;
    totalFiles: number;
}
/** Consolidated options for the enrichment prompt builder (Sprint 69 — params object pattern). */
export interface EnrichmentOptions {
    findingsJSON: string;
    item: ReviewItem;
    persona: string;
    truncationContext?: TruncationContext;
    personaMetadata?: PersonaMetadata;
    ecosystemContext?: EcosystemContext;
    /**
     * Lore entries passed through to `buildEnrichedSystemPrompt`. Only emitted
     * in the prompt when `multiModelConfig.depth.lore_active_weaving === true`.
     * Closes #464 A5 — multi-model enrichment now actually weaves lore.
     */
    loreEntries?: LoreEntryRef[];
    /**
     * Multi-model config. Required to read the `depth.lore_active_weaving`
     * flag that gates lore inclusion. Optional for backwards compatibility.
     */
    multiModelConfig?: MultiModelConfig;
}
/**
 * Local minimal LoreEntry shape (mirrors `LoreEntry` exported by template.ts).
 * Avoids a circular type import — types.ts is imported by template.ts.
 */
export interface LoreEntryRef {
    id: string;
    term: string;
    short: string;
    context: string;
    source?: string;
    tags?: string[];
}
/** Token estimate broken down by component for calibration logging. */
export interface TokenEstimateBreakdown {
    persona: number;
    template: number;
    metadata: number;
    diffs: number;
    total: number;
}
/**
 * Ecosystem pattern extracted from bridge findings (Sprint 71 — dynamic ecosystem context).
 * Extends the static pattern shape with provenance fields for traceability.
 */
export interface EcosystemPattern {
    repo: string;
    pr: number;
    pattern: string;
    connection: string;
    extractedFrom: string;
    confidence: number | undefined;
}
/**
 * Persona registry entry for the persona marketplace (Sprint 71 — schema primitives).
 * Defines the identity and metadata for a review persona.
 * The full persona marketplace is future work; these types formalize the slot architecture.
 */
export interface PersonaRegistryEntry {
    name: string;
    version: string;
    hash: string;
    description: string;
    dimensions: string[];
    voiceSamples?: string[];
}
//# sourceMappingURL=types.d.ts.map