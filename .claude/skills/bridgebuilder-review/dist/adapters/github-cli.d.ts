import type { FileContentResult, IGitProvider, PullRequest, PullRequestFile, PullRequestRef, PRReview, PreflightResult, RepoPreflightResult, CommitCompareResult } from "../ports/git-provider.js";
import type { IReviewPoster, PostReviewInput, PostCommentInput } from "../ports/review-poster.js";
/**
 * cycle-133 C-1 (`bridgebuilder.gh_max_buffer_bytes`): the per-call stdout buffer for `gh`. 64 MiB by default — the
 * paged fetch bounds what one call receives to one page of 100 files, so this only has to hold the largest page.
 * The pre-cycle-133 value was a fixed 10 MiB that a single `--paginate` call over a 2,000-file PR overflowed (KF-054).
 */
export declare const DEFAULT_GH_MAX_BUFFER_BYTES: number;
/** The child-process seam (tests pass a mocked `gh`; production is `execFile`). */
export type GhExec = (file: string, args: string[], options: {
    timeout: number;
    maxBuffer: number;
}) => Promise<{
    stdout: string;
}>;
/**
 * cycle-135 C-3 (sdd.md § 5.3, bd-w5pd9): a repository path for the contents endpoint, checked before encoding and
 * again on the decoded request — non-empty segments, never `.` or `..`, no leading `/`, no `?`, `#` or control
 * character. Returns the reason it is refused, or undefined.
 */
export declare function contentsPathProblem(path: string): string | undefined;
/** The canonical request: each path segment encoded with encodeURIComponent (so `/` inside a name is `%2F`). */
export declare function contentsEndpoint(owner: string, repo: string, path: string, ref: string): string;
/** Exported for the allowlist tests (cycle-135 C-3); the adapter is the only caller. */
export declare function assertAllowedArgs(args: string[]): void;
export interface GitHubCLIAdapterConfig {
    reviewMarker: string;
    /** cycle-133 C-1: per-call stdout buffer (`bridgebuilder.gh_max_buffer_bytes`); default DEFAULT_GH_MAX_BUFFER_BYTES. */
    ghMaxBufferBytes?: number;
    /** Test seam: the `gh` executor. Defaults to execFile. */
    exec?: GhExec;
}
export declare class GitHubCLIAdapter implements IGitProvider, IReviewPoster {
    private readonly marker;
    private readonly exec;
    private readonly maxBuffer;
    constructor(config: GitHubCLIAdapterConfig);
    private gh;
    /** cycle-133 C-1: the pair the review is pinned to (`pulls/N`). */
    getPR(owner: string, repo: string, prNumber: number): Promise<PullRequestRef>;
    /** cycle-133 C-1: one page of the files list (≤ 100 entries, patch text included — the endpoint has no other mode). */
    getPRFilesPage(owner: string, repo: string, prNumber: number, page: number): Promise<PullRequestFile[]>;
    /**
     * cycle-135 C-3 (sdd.md § 5.3, bd-w5pd9): one file's content at a pinned commit, for an added file the files list
     * returned without a patch. Default JSON media type (Q-1: `type`, `encoding: base64`, `size` = decoded bytes,
     * `content` wrapped every 60 characters); the buffer is sized for the envelope of `maxBytes`, so an overflow is
     * `too_large`; the envelope is validated strictly and the bytes are tested for binary before any string is made.
     */
    getFileContent(owner: string, repo: string, path: string, ref: string, maxBytes: number): Promise<FileContentResult>;
    listOpenPRs(owner: string, repo: string): Promise<PullRequest[]>;
    getPRFiles(owner: string, repo: string, prNumber: number): Promise<PullRequestFile[]>;
    getPRReviews(owner: string, repo: string, prNumber: number): Promise<PRReview[]>;
    preflight(): Promise<PreflightResult>;
    preflightRepo(owner: string, repo: string): Promise<RepoPreflightResult>;
    getCommitDiff(owner: string, repo: string, base: string, head: string): Promise<CommitCompareResult>;
    hasExistingReview(owner: string, repo: string, prNumber: number, headSha: string, markerKind?: "review" | "skip"): Promise<boolean>;
    postReview(input: PostReviewInput): Promise<boolean>;
    /**
     * Post an issue comment (not a review). Used for multi-model per-model comments
     * and consensus summary. Splits long comments at 65K chars with continuation headers.
     */
    postComment(input: PostCommentInput): Promise<boolean>;
    private postSingleComment;
}
//# sourceMappingURL=github-cli.d.ts.map