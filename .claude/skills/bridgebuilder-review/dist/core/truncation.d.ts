import type { PullRequestFile } from "../ports/git-provider.js";
import type { BridgebuilderConfig, TruncationResult, LoaDetectionResult, SecurityPatternEntry, TokenBudget, ProgressiveTruncationResult } from "./types.js";
export declare const SECURITY_PATTERNS: SecurityPatternEntry[];
export declare function isHighRisk(filename: string): boolean;
export declare function getSecurityCategory(filename: string): string | undefined;
export declare function matchesExcludePattern(filename: string, patterns: string[]): boolean;
/** Default Loa framework exclude patterns.
 * Use ** for recursive directory matching (BB-F4). */
export declare const LOA_EXCLUDE_PATTERNS: string[];
/**
 * Load .reviewignore patterns from repo root and merge with LOA_EXCLUDE_PATTERNS.
 * Returns combined patterns array. Graceful when file missing (returns LOA patterns only).
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
export declare function truncateFiles(files: PullRequestFile[], config: Pick<BridgebuilderConfig, "excludePatterns" | "maxDiffBytes" | "maxFilesPerPr" | "loaAware" | "repoRoot">): TruncationResult;
//# sourceMappingURL=truncation.d.ts.map