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
  state:
    | "APPROVED"
    | "CHANGES_REQUESTED"
    | "COMMENTED"
    | "DISMISSED"
    | "PENDING";
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

/** Typed error codes for git provider operations. */
export type GitProviderErrorCode = "RATE_LIMITED" | "NOT_FOUND" | "FORBIDDEN" | "NETWORK";

/** Typed error thrown by git provider adapters for structured classification. */
export class GitProviderError extends Error {
  readonly code: GitProviderErrorCode;

  constructor(code: GitProviderErrorCode, message: string) {
    super(message);
    this.name = "GitProviderError";
    this.code = code;
  }
}

/** Result of comparing two commits (V3-1 incremental review). */
export interface CommitCompareResult {
  filesChanged: string[];
  totalCommits: number;
}

export interface IGitProvider {
  listOpenPRs(owner: string, repo: string): Promise<PullRequest[]>;
  getPRFiles(
    owner: string,
    repo: string,
    prNumber: number,
  ): Promise<PullRequestFile[]>;
  getPRReviews(
    owner: string,
    repo: string,
    prNumber: number,
  ): Promise<PRReview[]>;
  preflight(): Promise<PreflightResult>;
  preflightRepo(
    owner: string,
    repo: string,
  ): Promise<RepoPreflightResult>;
  /** Compare two commits and return changed filenames (V3-1 incremental). */
  getCommitDiff(
    owner: string,
    repo: string,
    base: string,
    head: string,
  ): Promise<CommitCompareResult>;
}
