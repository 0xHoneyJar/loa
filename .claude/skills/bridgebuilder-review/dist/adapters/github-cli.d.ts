import type { IGitProvider, PullRequest, PullRequestFile, PRReview, PreflightResult, RepoPreflightResult, CommitCompareResult } from "../ports/git-provider.js";
import type { IReviewPoster, PostReviewInput, PostCommentInput } from "../ports/review-poster.js";
export interface GitHubCLIAdapterConfig {
    reviewMarker: string;
}
export declare class GitHubCLIAdapter implements IGitProvider, IReviewPoster {
    private readonly marker;
    constructor(config: GitHubCLIAdapterConfig);
    listOpenPRs(owner: string, repo: string): Promise<PullRequest[]>;
    getPRFiles(owner: string, repo: string, prNumber: number): Promise<PullRequestFile[]>;
    getPRReviews(owner: string, repo: string, prNumber: number): Promise<PRReview[]>;
    preflight(): Promise<PreflightResult>;
    preflightRepo(owner: string, repo: string): Promise<RepoPreflightResult>;
    getCommitDiff(owner: string, repo: string, base: string, head: string): Promise<CommitCompareResult>;
    hasExistingReview(owner: string, repo: string, prNumber: number, headSha: string): Promise<boolean>;
    postReview(input: PostReviewInput): Promise<boolean>;
    /**
     * Post an issue comment (not a review). Used for multi-model per-model comments
     * and consensus summary. Splits long comments at 65K chars with continuation headers.
     */
    postComment(input: PostCommentInput): Promise<boolean>;
    private postSingleComment;
}
//# sourceMappingURL=github-cli.d.ts.map