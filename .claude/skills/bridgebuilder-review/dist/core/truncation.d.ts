import type { PullRequestFile } from "../ports/git-provider.js";
import type { BridgebuilderConfig, TruncationResult, LoaDetectionResult, SecurityPatternEntry, TokenBudget, ProgressiveTruncationResult } from "./types.js";
export declare const SECURITY_PATTERNS: SecurityPatternEntry[];
export declare function isHighRisk(filename: string): boolean;
export declare function getSecurityCategory(filename: string): string | undefined;
export declare function matchesExcludePattern(filename: string, patterns: string[]): boolean;
/**
 * The PR label that operators apply to opt into bridgebuilder self-review —
 * BB will admit framework files (`.claude/`, `grimoires/`, etc.) into the
 * review payload instead of stripping them via the Loa-aware filter.
 *
 * The label name is intentionally a single source of truth; truncation logic,
 * caller-side label detection in reviewer.ts/template.ts, and operator-facing
 * docs all reference this constant.
 */
export declare const SELF_REVIEW_LABEL = "bridgebuilder:self-review";
/**
 * Derive the per-call `selfReview` flag from a PR's labels.
 * Returns true iff the PR carries SELF_REVIEW_LABEL.
 *
 * Centralized so the label string lives in one place and call sites
 * (reviewer.ts processItemTwoPass; template.ts buildPrompt + buildPromptWithMeta;
 * main.ts multi-model entry) cannot drift from each other.
 */
export declare function isSelfReviewOptedIn(prLabels: readonly string[] | undefined): boolean;
/**
 * Build a per-call truncate config from a base config and a PR's labels.
 *
 * BB-004 (PR #797 iter-2): four call sites (template.ts × 2, reviewer.ts,
 * main.ts) duplicated `{ ...config, selfReview: isSelfReviewOptedIn(pr.labels) }`.
 * BB iter-1 caught a missed call site that silently nullified the feature for
 * the multi-model pipeline — a duplication-as-correctness-hazard pattern. This
 * helper is the single chokepoint, so adding new call sites OR new per-PR
 * configuration knobs requires touching ONE function, and tests can pin the
 * derivation here.
 */
export declare function deriveCallConfig<C extends Pick<BridgebuilderConfig, "selfReview">>(config: C, pr: {
    labels: readonly string[] | undefined;
}): C & {
    selfReview: boolean;
};
/** Default Loa framework exclude patterns.
 * Use ** for recursive directory matching (BB-F4). */
export declare const LOA_EXCLUDE_PATTERNS: string[];
/**
 * Load `.reviewignore` operator-curated patterns from repo root.
 * Returns ONLY the user patterns — does NOT merge with LOA_EXCLUDE_PATTERNS.
 *
 * `.reviewignore` carries operator-curated exclusions (secrets/, vendor blobs,
 * private internal docs) that are distinct from the framework's built-in
 * exclusion list. The self-review opt-in (#796 / vision-013) bypasses the
 * framework patterns but MUST continue to honor `.reviewignore` — BB-001-security
 * surfaced this as a MEDIUM finding on PR #797 iter-2.
 *
 * BB-797-001-security (PR #797 iter-4): fail-CLOSED on read errors. Caller
 * (truncateFiles self-review branch) propagates the error to halt the review
 * rather than silently admitting files that may have been excluded by an
 * unreadable `.reviewignore`. ENOENT (no file) is "no rules" and returns [];
 * any other error throws.
 *
 * @throws Error when `.reviewignore` exists but cannot be read or parsed —
 *         caller MUST handle and decide whether to halt or fall back.
 */
export declare function loadReviewIgnoreUserPatterns(repoRoot?: string): string[];
/**
 * Load .reviewignore patterns from repo root and merge with LOA_EXCLUDE_PATTERNS.
 * Returns combined patterns array. Graceful when file missing (returns LOA
 * patterns only); also fail-soft on read errors (returns LOA defaults) — the
 * default-mode path can never fail-closed because the LOA patterns are themselves
 * the safety floor. Self-review path uses parseReviewignoreFile directly so it
 * can fail-closed (BB-797-001-security).
 *
 * BB-797-003-duplication (PR #797 iter-4): single source of truth for parsing.
 */
export declare function loadReviewIgnore(repoRoot?: string): string[];
/**
 * Detect if repo is Loa-mounted by reading .loa-version.json.
 * Resolves paths against repoRoot (git root), NOT cwd (SKP-001, IMP-004).
 *
 * Decision: sync I/O (existsSync/readFileSync) is intentional here.
 * truncateFiles() — the only caller — is synchronous (SDD §3.1), so async
 * would require a cascading refactor for zero runtime benefit.
 */
export declare function detectLoa(config: Pick<BridgebuilderConfig, "loaAware" | "repoRoot">): LoaDetectionResult;
export declare function isLoaSystemZone(filename: string): boolean;
export type LoaTier = "tier1" | "tier2" | "exception";
export declare function classifyLoaFile(filename: string): LoaTier;
/** Extract the first hunk from a unified diff patch. */
export declare function extractFirstHunk(patch: string): string;
export interface LoaTierResult {
    /** Files that passed through (not under Loa paths, or exception). */
    passthrough: PullRequestFile[];
    /** Tier 1 excluded files: name + stats only. */
    tier1Excluded: Array<{
        filename: string;
        stats: string;
    }>;
    /** Tier 2 summary files: first hunk + stats. */
    tier2Summary: Array<{
        filename: string;
        stats: string;
        summary: string;
    }>;
    /** Total bytes saved by exclusion. */
    bytesSaved: number;
}
/**
 * Apply two-tier Loa exclusion to files under Loa paths.
 * Security check runs BEFORE tier classification (SDD 3.6).
 */
export declare function applyLoaTierExclusion(files: PullRequestFile[], loaPatterns: string[]): LoaTierResult;
export declare const TOKEN_BUDGETS: Record<string, TokenBudget>;
export declare function getTokenBudget(model: string): TokenBudget;
/** Estimate tokens from string using model-specific coefficient. */
export declare function estimateTokens(text: string, model: string): number;
/** Check if a test file is adjacent to a changed non-test file (IMP-002). */
export declare function isAdjacentTest(filename: string, allFiles: PullRequestFile[]): boolean;
/** Parse unified diff into hunks. Returns null on parse failure (SKP-003 fallback). */
export declare function parseHunks(patch: string): Array<{
    header: string;
    lines: string[];
}> | null;
/** Reduce context lines around changed hunks (3→1→0). */
export declare function reduceHunkContext(hunks: Array<{
    header: string;
    lines: string[];
}>, contextLines: number): Array<{
    header: string;
    lines: string[];
}>;
/**
 * Apply size-aware handling for large security files (SKP-005).
 * Files >50KB get hunk summary instead of full diff.
 */
export declare function capSecurityFile(file: PullRequestFile): PullRequestFile;
/**
 * Deterministic file priority for Level 1 truncation (IMP-002).
 * Returns files sorted by retention priority (highest first).
 */
export declare function prioritizeFiles(files: PullRequestFile[]): PullRequestFile[];
/**
 * Progressive truncation engine (Task 1.7 — SDD Section 3.3).
 * Attempts 3 levels of truncation to fit within token budget.
 * Budget target: 90% of maxInputTokens (SKP-004).
 */
export declare function progressiveTruncate(files: PullRequestFile[], budgetTokens: number, model: string, systemPromptLen: number, metadataLen: number): ProgressiveTruncationResult;
export declare function truncateFiles(files: PullRequestFile[], config: Pick<BridgebuilderConfig, "excludePatterns" | "maxDiffBytes" | "maxFilesPerPr" | "loaAware" | "repoRoot" | "selfReview">): TruncationResult;
//# sourceMappingURL=truncation.d.ts.map