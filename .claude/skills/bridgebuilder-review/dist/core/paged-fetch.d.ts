import type { IGitProvider, PullRequestFile, PullRequestRef } from "../ports/git-provider.js";
import { truncateFiles } from "./truncation.js";
import { type DegradedReason } from "./degraded-reason.js";
import type { BridgebuilderConfig, CoverageRecord, OmissionReason, ReviewItem, TruncationResult } from "./types.js";
/** GitHub's `pulls/N/files` lists at most this many files (30 pages of 100). */
export declare const FILES_ENDPOINT_CAP = 3000;
export type PagedGit = Required<Pick<IGitProvider, "getPR" | "getPRFilesPage">>;
export type SelectionConfig = Pick<BridgebuilderConfig, "excludePatterns" | "maxDiffBytes" | "maxFilesPerPr" | "loaAware" | "repoRoot" | "selfReview">;
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
 * Degradation from the coverage: a fetch-side reason is reported as itself; otherwise any omitted reviewable file or
 * any unknown (unlisted) file is `incomplete_coverage`. Either way the merge is blocked as incomplete_coverage.
 */
export declare function evaluateCoverage(input: {
    omitted: CoverageRecord["omitted"];
    unknown_omitted: number;
    fetchReasons: DegradedReason[];
}): Pick<CoverageRecord, "degraded" | "degraded_reasons" | "mergeBlockedReason">;
/** The two-pass fetch with one restart on a base/head move (sdd.md C-1). */
export declare function fetchPRFilesTwoPass(git: PagedGit, owner: string, repo: string, prNumber: number, config: SelectionConfig): Promise<TwoPassResult>;
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