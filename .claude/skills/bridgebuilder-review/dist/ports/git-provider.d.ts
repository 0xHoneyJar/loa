export interface PullRequest {
    number: number;
    title: string;
    headSha: string;
    baseBranch: string;
    labels: string[];
    author: string;
}
export interface PullRequestFile {
    filename: string;
    status: "added" | "modified" | "removed" | "renamed";
    additions: number;
    deletions: number;
    patch?: string;
}
export interface PRReview {
    id: number;
    body: string;
    user: string;
    state: "APPROVED" | "CHANGES_REQUESTED" | "COMMENTED" | "DISMISSED" | "PENDING";
    submittedAt: string;
}
export interface PreflightResult {
    remaining: number;
    scopes: string[];
}
export interface RepoPreflightResult {
    owner: string;
    repo: string;
    accessible: boolean;
    error?: string;
}
export interface IGitProvider {
    listOpenPRs(owner: string, repo: string): Promise<PullRequest[]>;
    getPRFiles(owner: string, repo: string, prNumber: number): Promise<PullRequestFile[]>;
    getPRReviews(owner: string, repo: string, prNumber: number): Promise<PRReview[]>;
    preflight(): Promise<PreflightResult>;
    preflightRepo(owner: string, repo: string): Promise<RepoPreflightResult>;
}
//# sourceMappingURL=git-provider.d.ts.map