import type { IGitProvider, PullRequest, PullRequestFile, PRReview, PreflightResult, RepoPreflightResult } from "../ports/git-provider.js";
import type { IReviewPoster, PostReviewInput } from "../ports/review-poster.js";
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
    hasExistingReview(owner: string, repo: string, prNumber: number, headSha: string): Promise<boolean>;
    postReview(input: PostReviewInput): Promise<boolean>;
}
//# sourceMappingURL=github-cli.d.ts.map