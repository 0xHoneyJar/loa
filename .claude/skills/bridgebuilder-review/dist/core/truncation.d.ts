import type { PullRequestFile } from "../ports/git-provider.js";
import type { ReviewignoreSource, SelectionConfig, BridgebuilderConfig, TruncationResult, LoaDetectionResult, SecurityPatternEntry, TokenBudget, ProgressiveTruncationResult } from "./types.js";
export declare const SECURITY_PATTERNS: SecurityPatternEntry[];
export declare function isHighRisk(filename: string): boolean;
export declare function getSecurityCategory(filename: string): string | undefined;
/** cycle-135 C-1: a pattern with any of `*`, `?`, `{`, `[` is a glob; anything else names whole segments. */
export declare function isWildcardPattern(pattern: string): boolean;
/** Why `pattern` is outside the grammar, or null when it is inside (cycle-135 C-1). */
export declare function excludePatternGrammarError(pattern: string): string | null;
/**
 * cycle-135 C-1 (bd-ow72o): the one loader every pattern source goes through. Trims; drops blank entries; strips one
 * leading `./` (patterns are repository-relative) and keeps a leading `/` as the root anchor; keeps a trailing `/` (the matcher ignores one); rejects a
 * pattern outside the grammar with one WARN naming it (a rejected pattern is dropped and so matches nothing).
 */
export declare function normalizeExcludePatterns(raw: readonly string[], source: string): string[];
/**
 * True when `filename` matches any of `patterns` under the grammar above (cycle-135 C-1, bd-ow72o): non-wildcard →
 * whole segments, wildcard → the segment-aware glob. Pure; no exceptions at match time.
 */
export declare function matchesExcludePattern(filename: string, patterns: readonly string[]): boolean;
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
 * Use ** for recursive directory matching (BB-F4). Non-wildcard entries name whole segments (cycle-135 C-1:
 * `PROCESS.md` excludes `docs/PROCESS.md`, never `MYPROCESS.md`); the list goes through the one loader. */
export declare const LOA_EXCLUDE_PATTERNS: string[];
/**
 * cycle-135 C-2 (bd-i4fyw, DEC-1014): paths a wildcard user exclusion (`--exclude`, `exclude_patterns`,
 * `.reviewignore`) cannot remove from the review. An explicit (non-wildcard) user pattern still excludes them; the
 * Loa tier is not subject to this list. `bridgebuilder.protected_paths` replaces it; `[]` disables it.
 */
export declare const DEFAULT_PROTECTED_PATHS: readonly string[];
/**
 * cycle-135 C-2 (bd-i4fyw, SDD § 5.2): split `files` by the user patterns, order-independently. Every matching user
 * pattern is resolved first. An explicit match — a non-wildcard pattern that is root-anchored (a `/` after one
 * trailing `/` is ignored) or equals the file's full path — excludes (that pattern recorded: an explicit name wins
 * over protection). Otherwise a file matching a protected pattern (same matcher) is kept with the first matching
 * pattern recorded: wildcards and floating segment names (`ci.yml`, `.github`, `settings.json`) do not defeat
 * protection (sprint-279 review round 1, HIGH 2). Otherwise the file is excluded (an explicit or non-wildcard match
 * recorded first, else the first match). Files no pattern matches appear in neither list.
 */
export declare function partitionUserExclusions(files: readonly PullRequestFile[], userPatterns: readonly string[], protectedPatterns: readonly string[]): {
    excluded: Array<{
        file: string;
        pattern: string;
    }>;
    protectedKept: Array<{
        file: string;
        pattern: string;
    }>;
};
/** cycle-135 C-2 (DEC-1027): where the applied `.reviewignore` patterns came from (`base_unavailable`: round 1). */
export type { ReviewignoreSource } from "./types.js";
/**
 * Parse a `.reviewignore` file's user-curated patterns from disk.
 *
 * BB-797-003-duplication (iter-4): one grammar deserves one parser.
 *
 * BB-797-001-security (iter-4): ONLY ENOENT means "file absent" → []. ANY
 * OTHER error throws — caller decides fail-open vs fail-closed. cycle-098 L2
 * fail-closed: uncertain signals halt, never permit.
 *
 * BB-797-SEC-002 (iter-6): use readFileSync directly; classify ONLY
 * `code === "ENOENT"` as "absent". Earlier `existsSync` gate collapsed four
 * distinct states (absent, present-readable, present-unreadable, broken-link)
 * into one boolean — broken symlinks, EACCES, and ENOTDIR all returned `false`,
 * silently coercing unreadable to "no rules". Errno-explicit handling closes
 * the TOCTOU/ambiguous-stat class (Go's golang/go#41112 lesson applied here).
 *
 * cycle-135 C-2 (bd-i4fyw, DEC-1027): with `opts.baseSha` the base version is read (`git show <sha>:.reviewignore`,
 * the same line validation) so a PR cannot change the exclusions its own review applies. A failed base read fails
 * CLOSED (sprint-279 review round 1, HIGH 1): the checkout copy governs and the source is `base_unavailable` (the
 * review degrades as reviewignore_unavailable), with one WARN naming why. A readable base that LACKS the file is a
 * definitive answer (Bridgebuilder round 1, PR #1302): no patterns apply and the source is `none` — a copy the PR adds
 * is reported in a WARN, never applied (its patterns take effect after merge). Without a base sha the checkout file is
 * read as before.
 *
 * @throws Error when the checkout `.reviewignore` exists but cannot be read or parsed, or repoRoot is invalid.
 */
export declare function parseReviewignoreFile(repoRoot: string, opts?: {
    baseSha?: string;
}): {
    patterns: string[];
    source: ReviewignoreSource;
};
/** The `.reviewignore` line grammar, shared by the checkout and the base read. */
export declare function parseReviewignoreLines(content: string): string[];
export declare const REVIEWIGNORE_MAX_BYTES: number;
/**
 * cycle-135 C-2 (bd-i4fyw, DEC-1027): `.reviewignore` as of the PR base. The sha must be 40-hex (never an option);
 * the entry must be a regular blob (a symlink is refused, as for the checkout read); bounded by a 10 s timeout and
 * 1 MiB. Never throws: a failure (absent at the base, unknown commit, git error, oversize, a symlink) is returned
 * with its reason and the caller falls back to the checkout copy.
 */
export type BaseRead = {
    ok: true;
    patterns: string[];
} | {
    ok: false;
    absent: boolean;
    why: string;
};
export declare function readBaseReviewignore(repoRoot: string, baseSha: string): BaseRead;
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
export declare function loadReviewIgnoreUserPatterns(repoRoot?: string, opts?: {
    baseSha?: string;
}): string[];
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
    /** Tier 1 excluded files: name + stats only (cycle-135: `pattern` = the matching default). */
    tier1Excluded: Array<{
        filename: string;
        stats: string;
        pattern?: string;
    }>;
    /** Tier 2 summary files: first hunk + stats. */
    tier2Summary: Array<{
        filename: string;
        stats: string;
        summary: string;
        pattern?: string;
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
/**
 * The input budget a caller may actually prepare for `model`: the operator
 * budget clamped to the model's dispatchable input when the id is KNOWN to
 * the generated twin or the hand table; an unknown id (and the literal
 * "default" row, which is not a model) keeps the operator budget. Used by
 * progressiveTruncate and by the reviewer's adaptive retry, so a retry never
 * re-sends the same clamped payload (Sprint 1 audit, slice D).
 */
export declare function effectiveInputBudget(budgetTokens: number, model: string): number;
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
export declare function truncateFiles(files: PullRequestFile[], config: SelectionConfig): TruncationResult;
//# sourceMappingURL=truncation.d.ts.map