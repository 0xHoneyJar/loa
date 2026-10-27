import type { IGitProvider, PullRequestFile, PullRequestRef } from "../ports/git-provider.js";
import { truncateFiles, type BaseRead } from "./truncation.js";
import { type DegradedReason } from "./degraded-reason.js";
import type { BridgebuilderConfig, CoverageRecord, OmissionReason, ReviewignoreSource, ReviewItem, SelectionConfig, TruncationResult } from "./types.js";
/** GitHub's `pulls/N/files` lists at most this many files (30 pages of 100). */
export declare const FILES_ENDPOINT_CAP = 3000;
export type PagedGit = Required<Pick<IGitProvider, "getPR" | "getPRFilesPage">>;
/** cycle-135 C-3: the paged contract plus the optional content read (absent → no content fetch). */
export type PagedContentGit = PagedGit & Pick<IGitProvider, "getFileContent">;
export type { SelectionConfig } from "./types.js";
/** cycle-135 C-3: default `max_content_fetches` and the total deadline for the content reads of one attempt. */
export declare const DEFAULT_MAX_CONTENT_FETCHES = 20;
export declare const CONTENT_FETCH_DEADLINE_MS = 120000;
/** Test seams of the two-pass fetch (production passes none). */
export interface TwoPassDeps {
    /** cycle-135 C-3: the clock for the content-fetch deadline (default `Date.now`). */
    now?: () => number;
    /** cycle-135 C-2: the selection (default `truncateFiles`); tests substitute the producer of `protectedKept`. */
    truncate?: (files: PullRequestFile[], config: SelectionConfig) => TruncationResult;
    /** cycle-135 C-2: where `.reviewignore` is read from for this PR (default `defaultReviewignoreSource`). */
    reviewignoreSource?: (repoRoot: string | undefined, opts: {
        baseSha?: string;
    }) => ReviewignoreSource | undefined;
    /** cycle-136 C-2: the local base `.reviewignore` read of `resolveBaseReviewignore` (default `readBaseReviewignore`). */
    readBaseReviewignore?: (repoRoot: string, baseSha: string) => BaseRead;
}
/** cycle-136 C-2 (D-2.5): the base `.reviewignore` resolved for the selection (`none` always carries no patterns). */
export type BaseReviewignore = NonNullable<SelectionConfig["reviewignoreBase"]>;
/**
 * cycle-136 C-2 (sdd.md § 5.2, FR-2, bd-9tt4b, DEC-1082/DEC-1083): the base branch's `.reviewignore` for one base sha.
 * The local read answers when the clone holds the base commit (`ok` → base, `absent` → none); only `unknown_commit` (a
 * shallow checkout) reads it through the contents API against the run's target `owner/repo` at the base sha, bounded
 * at 1 MiB — a `text` answer is complete by construction (the adapter answers `too_large` above the bound and rejects
 * a `size` that disagrees with the decoded bytes). A 404 is not proof of absence (an authorization gap answers 404
 * too): one probe of a listed file that exists at the base (modified or removed; the listing keeps no
 * `previous_filename`, so a rename is no probe target) with `maxBytes` 1 must answer before it counts as `none`. Any
 * other outcome is `undefined` — the selection's own read then reports `base_unavailable` and the review degrades
 * (DEC-1043). The outcome, failures included, is cached per base sha for the run; the read is outside
 * `max_content_fetches` and `fetch_missing_patches` (they govern listed files). Never throws.
 */
export declare function resolveBaseReviewignore(git: PagedContentGit, owner: string, repo: string, baseSha: string, repoRoot: string | undefined, files: readonly PullRequestFile[], cache: Map<string, BaseReviewignore | undefined>, readLocal?: (repoRoot: string, baseSha: string) => BaseRead): Promise<BaseReviewignore | undefined>;
export interface TwoPassResult {
    /** Selected files with their retained (possibly cut) patch text, in selection order. */
    files: PullRequestFile[];
    /** The global selection, `included` === `files`. */
    selection: TruncationResult;
    coverage: CoverageRecord;
}
/** Omission reasons that count against coverage when the file is a reviewable code file. */
export declare const REVIEWABLE_OMISSION_REASONS: ReadonlySet<OmissionReason>;
/** A file in the review set by name (dotfiles such as `.gitattributes` are config). */
export declare function isReviewableCodeFile(filename: string): boolean;
/** A base or head change between the pin and a later read. */
export declare class PrHeadMoved extends Error {
    readonly latest: PullRequestRef;
    constructor(latest: PullRequestRef);
}
/** Cut a patch to at most `maxBytes` UTF-8 bytes, at the last line boundary when one exists (always a prefix). */
export declare function cutPatch(patch: string, maxBytes: number): string;
/**
 * cycle-135 C-3: the patch for a whole added file — `@@ -0,0 +1,N @@` then every line with a `+` prefix (bytes
 * verbatim, so CRLF keeps its `\r`), and git's `\ No newline at end of file` marker when the content lacks one.
 */
export declare function synthesizeAddedPatch(content: string): string;
/**
 * Degradation from the coverage: a fetch-side reason is reported as itself; otherwise any omitted reviewable file or
 * any unknown (unlisted) file is `incomplete_coverage`. Either way the merge is blocked as incomplete_coverage.
 */
export declare function evaluateCoverage(input: {
    omitted: CoverageRecord["omitted"];
    unknown_omitted: number;
    fetchReasons: DegradedReason[];
}): Pick<CoverageRecord, "degraded" | "degraded_reasons" | "mergeBlockedReason">;
/** The two-pass fetch with one restart on a base/head move (sdd.md C-1). */
export declare function fetchPRFilesTwoPass(git: PagedContentGit, owner: string, repo: string, prNumber: number, config: SelectionConfig, deps?: TwoPassDeps): Promise<TwoPassResult>;
/** Whether a provider implements the paged contract. */
export declare function hasPagedContract(git: IGitProvider): git is IGitProvider & PagedGit;
/**
 * The truncation for a (possibly incremental) item: the fetch's global selection when the item still carries the
 * fetched file list, else `truncateFiles` over the given files (deriveCallConfig stays the single chokepoint).
 */
export declare function truncationFor(item: ReviewItem, config: Parameters<typeof truncateFiles>[1] & Pick<BridgebuilderConfig, "selfReview">): TruncationResult;
/**
 * The coverage marker: the full record when it fits the comment budget, else a compact form carrying both SHAs,
 * the counts and the sha256 of the full record (which is in the summary JSON in full).
 */
export declare function coverageMarker(coverage: CoverageRecord): string;
/** The posted coverage section: pinned pair, counts per reason, the first 20 omitted paths, and the marker. */
export declare function formatCoverageSection(coverage: CoverageRecord): string;
//# sourceMappingURL=paged-fetch.d.ts.map