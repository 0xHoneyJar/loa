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
  /**
   * cycle-133 C-1: UTF-8 byte length of GitHub's patch, recorded by the metadata pass of the two-pass fetch, which
   * keeps the size and drops the text. `truncateFiles` uses it for the byte budget when `patch` is absent; undefined
   * means GitHub sent no patch (binary, generated, or GitHub-truncated).
   */
  patchBytes?: number;
}

/** cycle-133 C-1: the immutable pair a review is pinned to, read from `pulls/N` before and after every page. */
export interface PullRequestRef {
  base_sha: string;
  head_sha: string;
  /** GitHub's `changed_files` count; the files endpoint lists at most 3,000 of them. */
  changed_files: number;
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
export type GitProviderErrorCode = "RATE_LIMITED" | "NOT_FOUND" | "FORBIDDEN" | "NETWORK" | "PAYLOAD_OVERSIZE";

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

/**
 * cycle-135 C-3 (sdd.md § 5.3, bd-w5pd9): the content of one file at a pinned commit, read for an added file GitHub
 * listed without a patch. `bytes` is the decoded byte length; `binary` = a NUL in the first 8 KiB or invalid UTF-8;
 * `too_large` = over the caller's bound (or GitHub's > 1 MiB `encoding: "none"` answer). Failures throw.
 */
export type FileContentResult =
  | { kind: "text"; content: string; bytes: number }
  | { kind: "binary" }
  | { kind: "too_large" };

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
  /** cycle-133 C-1: `pulls/N` → base/head sha and changed_files (the two-pass fetch pins and re-checks this pair). */
  getPR?(owner: string, repo: string, prNumber: number): Promise<PullRequestRef>;
  /**
   * cycle-133 C-1: one page of `pulls/N/files?per_page=100&page=K` (never `--paginate`), patch text included —
   * the endpoint has no patch-less mode. Throws GitProviderError PAYLOAD_OVERSIZE when the page exceeds the per-call
   * buffer, RATE_LIMITED on a rate limit.
   */
  getPRFilesPage?(owner: string, repo: string, prNumber: number, page: number): Promise<PullRequestFile[]>;
  /**
   * cycle-135 C-3: `contents/<path>?ref=<40-hex>` with at most `maxBytes` decoded bytes. Optional — a provider or test
   * double without it means no content fetch (today's `no_patch`). Throws GitProviderError on a failed or malformed read.
   */
  getFileContent?(owner: string, repo: string, path: string, ref: string, maxBytes: number): Promise<FileContentResult>;
}
