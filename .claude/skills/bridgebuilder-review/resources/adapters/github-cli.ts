import { execFile } from "node:child_process";
import { promisify } from "node:util";
import {
  GitProviderError,
} from "../ports/git-provider.js";
import type {
  IGitProvider,
  PullRequest,
  PullRequestFile,
  PullRequestRef,
  PRReview,
  PreflightResult,
  RepoPreflightResult,
  CommitCompareResult,
} from "../ports/git-provider.js";
import type {
  IReviewPoster,
  PostReviewInput,
  PostCommentInput,
} from "../ports/review-poster.js";

const execFileAsync = promisify(execFile);

// Decision: execFile+gh CLI over Octokit SDK.
// gh handles token refresh, SSO, credential helpers, and proxy config automatically.
// execFile avoids shell injection (no shell: true). Tradeoff: shelling out is slower
// than HTTP-direct, but review volume is low (<50 PRs/run) so latency is acceptable.
// If throughput becomes a bottleneck, swap to Octokit behind IGitProvider port.
const GH_TIMEOUT_MS = 30_000;

/**
 * cycle-133 C-1 (`bridgebuilder.gh_max_buffer_bytes`): the per-call stdout buffer for `gh`. 64 MiB by default — the
 * paged fetch bounds what one call receives to one page of 100 files, so this only has to hold the largest page.
 * The pre-cycle-133 value was a fixed 10 MiB that a single `--paginate` call over a 2,000-file PR overflowed (KF-054).
 */
export const DEFAULT_GH_MAX_BUFFER_BYTES = 64 * 1024 * 1024;

/** The child-process seam (tests pass a mocked `gh`; production is `execFile`). */
export type GhExec = (
  file: string,
  args: string[],
  options: { timeout: number; maxBuffer: number },
) => Promise<{ stdout: string }>;

/** Error from gh CLI that carries the HTTP status code when available. */
class GhApiError extends GitProviderError {
  readonly httpStatus: number | undefined;
  constructor(code: GitProviderError["code"], message: string, httpStatus?: number) {
    super(code, message);
    this.httpStatus = httpStatus;
  }
}

// SECURITY: Adding endpoints here requires review — each is an attack surface expansion.
// Every regex must anchor start (^) and end ($), use [^/]+ (not .*) for path segments,
// and escape query parameters literally. New entries should get their own PR with justification.
const ALLOWED_API_ENDPOINTS: ReadonlyArray<RegExp> = [
  /^\/rate_limit$/,
  /^\/repos\/[^/]+\/[^/]+$/,
  /^\/repos\/[^/]+\/[^/]+\/pulls\?state=open&per_page=100$/,
  /^\/repos\/[^/]+\/[^/]+\/pulls\/\d+\/files\?per_page=100$/,
  // cycle-133 C-1: the immutable pair (base/head sha, changed_files) and the paged file list (one page per call)
  /^\/repos\/[^/]+\/[^/]+\/pulls\/\d+$/,
  /^\/repos\/[^/]+\/[^/]+\/pulls\/\d+\/files\?per_page=100&page=\d{1,2}$/,
  /^\/repos\/[^/]+\/[^/]+\/pulls\/\d+\/reviews\?per_page=100$/,
  /^\/repos\/[^/]+\/[^/]+\/pulls\/\d+\/reviews$/,
  // V3-1: compare commits for incremental review
  /^\/repos\/[^/]+\/[^/]+\/compare\/[a-f0-9]{7,40}\.\.\.[a-f0-9]{7,40}$/,
  // Multi-model: post issue comments (per-model reviews + consensus summary)
  /^\/repos\/[^/]+\/[^/]+\/issues\/\d+\/comments$/,
];

/**
 * Strict allowlist for gh api flags.
 * Any flag not explicitly listed here is rejected (default-deny).
 */
const ALLOWED_API_FLAGS = new Set([
  "--paginate",
  "-X",
  "-f",
  "--raw-field",
]);

/** Flags that can redirect requests, alter host/protocol, or inject headers. */
const FORBIDDEN_FLAGS = new Set([
  "--hostname",
  "-H",
  "--header",
  "--method",
  "-F",
  "--field",
  "--input",
  "--jq",
  "--template",
  "--repo",
]);

function assertAllowedArgs(args: string[]): void {
  const cmd = args[0];

  if (cmd === "api") {
    // Enforce endpoint at args[1] position (not arbitrary arg)
    // Length bound prevents oversized path segments from reaching execFile
    const endpoint = args[1];
    if (!endpoint || endpoint.length > 200 || !endpoint.startsWith("/")) {
      throw new Error("gh api endpoint missing or invalid");
    }

    if (!ALLOWED_API_ENDPOINTS.some((re) => re.test(endpoint))) {
      throw new Error(`gh api endpoint not allowlisted: ${endpoint}`);
    }

    // Only allow POST via -X POST (for review posting); default is GET
    const xIndex = args.indexOf("-X");
    if (xIndex !== -1) {
      const method = args[xIndex + 1];
      if (method !== "POST") {
        throw new Error(`gh api method not allowlisted: ${method ?? "(missing)"}`);
      }
    }

    // Strict flag validation: reject anything not explicitly allowed
    for (let i = 2; i < args.length; i++) {
      const a = args[i];

      // Skip non-flag arguments (values for preceding flags)
      if (!a.startsWith("-")) continue;

      // Check combined flag forms (--flag=value)
      const flagName = a.includes("=") ? a.slice(0, a.indexOf("=")) : a;

      // Reject explicitly forbidden flags (belt-and-suspenders)
      if (FORBIDDEN_FLAGS.has(flagName)) {
        throw new Error(`gh api flag not allowlisted: ${a}`);
      }

      // Reject any flag not in the strict allowlist
      if (!ALLOWED_API_FLAGS.has(flagName)) {
        throw new Error(`gh api flag not allowlisted: ${a}`);
      }

      // Validate -f/--raw-field values are key=value format
      if (flagName === "-f" || flagName === "--raw-field") {
        const value = a.includes("=") ? a.slice(a.indexOf("=") + 1) : args[i + 1];
        if (!value || !value.includes("=")) {
          throw new Error(`gh api ${flagName} value must be key=value format`);
        }
        if (!a.includes("=")) i++; // skip the value arg
        continue;
      }

      // Skip value for -X (already validated above)
      if (flagName === "-X") {
        i++; // skip the method value
        continue;
      }
    }

    return;
  }

  if (cmd === "auth" && args[1] === "status" && args.length === 2) {
    return;
  }

  throw new Error(`gh command not allowlisted: ${cmd}`);
}

export interface GitHubCLIAdapterConfig {
  reviewMarker: string;
  /** cycle-133 C-1: per-call stdout buffer (`bridgebuilder.gh_max_buffer_bytes`); default DEFAULT_GH_MAX_BUFFER_BYTES. */
  ghMaxBufferBytes?: number;
  /** Test seam: the `gh` executor. Defaults to execFile. */
  exec?: GhExec;
}

const defaultExec: GhExec = (file, args, options) => execFileAsync(file, args, options);

async function gh(
  args: string[],
  timeoutMs: number = GH_TIMEOUT_MS,
  exec: GhExec = defaultExec,
  maxBuffer: number = DEFAULT_GH_MAX_BUFFER_BYTES,
): Promise<string> {
  assertAllowedArgs(args);
  try {
    const { stdout } = await exec("gh", args, {
      timeout: timeoutMs,
      maxBuffer,
    });
    return stdout;
  } catch (err: unknown) {
    const e = err as NodeJS.ErrnoException & {
      stderr?: string;
      code?: string | number;
    };
    if (e.code === "ENOENT") {
      throw new GitProviderError(
        "NETWORK",
        "GitHub CLI (gh) required. Install: https://cli.github.com/ and run 'gh auth login'.",
      );
    }
    // cycle-133 C-1 (KF-054): a payload larger than the per-call buffer is a typed, recoverable condition — the paged
    // fetch records it as files_payload_oversize — never a Fatal.
    if (e.code === "ERR_CHILD_PROCESS_STDIO_MAXBUFFER") {
      throw new GhApiError("PAYLOAD_OVERSIZE", `gh output exceeded the ${maxBuffer}-byte buffer (bridgebuilder.gh_max_buffer_bytes)`);
    }
    // Do not include stderr/message — may contain tokens or sensitive repo info
    const code = typeof e.code === "string" || typeof e.code === "number" ? String(e.code) : "unknown";
    // Extract HTTP status from gh stderr: "gh: ... (HTTP NNN)"
    const httpMatch = e.stderr?.match(/\(HTTP (\d{3})\)/);
    const httpStatus = httpMatch ? parseInt(httpMatch[1], 10) : undefined;
    // Classify by exit code: 1 = general failure, 4 = auth/forbidden in gh; a rate limit (HTTP 429, or GitHub's
    // 403 "rate limit exceeded") is RATE_LIMITED (cycle-133 C-1: patch_fetch_rate_limited).
    const rateLimited = httpStatus === 429 || /rate limit/i.test(e.stderr ?? "");
    const errorCode = rateLimited ? "RATE_LIMITED" : code === "4" ? "FORBIDDEN" : "NETWORK";
    throw new GhApiError(errorCode, `gh command failed (code=${code})`, httpStatus);
  }
}

function parseJson<T>(raw: string, context: string): T {
  try {
    return JSON.parse(raw) as T;
  } catch {
    // Do not include raw response — may contain sensitive data
    throw new GitProviderError("NETWORK", `Failed to parse gh JSON for ${context}`);
  }
}

/**
 * Split a long comment into chunks at natural boundaries (paragraph breaks).
 * Each chunk stays under maxChars. Falls back to hard split if no boundary found.
 */
function splitComment(body: string, maxChars: number): string[] {
  const chunks: string[] = [];
  let remaining = body;

  while (remaining.length > maxChars) {
    // Try to split at a paragraph break (double newline)
    let splitIdx = remaining.lastIndexOf("\n\n", maxChars);
    if (splitIdx < maxChars * 0.5) {
      // No good paragraph break — try single newline
      splitIdx = remaining.lastIndexOf("\n", maxChars);
    }
    if (splitIdx < maxChars * 0.5) {
      // Hard split at limit
      splitIdx = maxChars;
    }

    chunks.push(remaining.slice(0, splitIdx));
    remaining = remaining.slice(splitIdx).trimStart();
  }

  if (remaining.length > 0) {
    chunks.push(remaining);
  }

  return chunks;
}

export class GitHubCLIAdapter implements IGitProvider, IReviewPoster {
  private readonly marker: string;
  private readonly exec: GhExec;
  private readonly maxBuffer: number;

  constructor(config: GitHubCLIAdapterConfig) {
    this.marker = config.reviewMarker;
    this.exec = config.exec ?? defaultExec;
    this.maxBuffer = config.ghMaxBufferBytes ?? DEFAULT_GH_MAX_BUFFER_BYTES;
  }

  private gh(args: string[], timeoutMs: number = GH_TIMEOUT_MS): Promise<string> {
    return gh(args, timeoutMs, this.exec, this.maxBuffer);
  }

  /** cycle-133 C-1: the pair the review is pinned to (`pulls/N`). */
  async getPR(owner: string, repo: string, prNumber: number): Promise<PullRequestRef> {
    const raw = await this.gh(["api", `/repos/${owner}/${repo}/pulls/${prNumber}`]);
    const data = parseJson<Record<string, unknown>>(raw, `getPR(${owner}/${repo}#${prNumber})`);
    const base = (data.base as Record<string, unknown> | undefined)?.sha;
    const head = (data.head as Record<string, unknown> | undefined)?.sha;
    const changed = data.changed_files;
    if (typeof base !== "string" || typeof head !== "string" || typeof changed !== "number" || !Number.isInteger(changed) || changed < 0) {
      throw new GitProviderError("NETWORK", `getPR(${owner}/${repo}#${prNumber}): response lacks base.sha, head.sha or changed_files`);
    }
    return { base_sha: base, head_sha: head, changed_files: changed };
  }

  /** cycle-133 C-1: one page of the files list (≤ 100 entries, patch text included — the endpoint has no other mode). */
  async getPRFilesPage(owner: string, repo: string, prNumber: number, page: number): Promise<PullRequestFile[]> {
    if (!Number.isInteger(page) || page < 1 || page > 30) {
      throw new GitProviderError("NETWORK", `getPRFilesPage: page ${page} outside 1..30 (the endpoint lists at most 3,000 files)`);
    }
    const raw = await this.gh(["api", `/repos/${owner}/${repo}/pulls/${prNumber}/files?per_page=100&page=${page}`]);
    const data = parseJson<unknown>(raw, `getPRFilesPage(${owner}/${repo}#${prNumber}, page ${page})`);
    if (!Array.isArray(data)) {
      throw new GitProviderError("NETWORK", `getPRFilesPage(${owner}/${repo}#${prNumber}, page ${page}): not a JSON array`);
    }
    return (data as Array<Record<string, unknown>>).map((f) => ({
      filename: f.filename as string,
      status: f.status as PullRequestFile["status"],
      additions: f.additions as number,
      deletions: f.deletions as number,
      patch: typeof f.patch === "string" ? f.patch : undefined,
    }));
  }

  async listOpenPRs(owner: string, repo: string): Promise<PullRequest[]> {
    const raw = await this.gh([
      "api",
      `/repos/${owner}/${repo}/pulls?state=open&per_page=100`,
      "--paginate",
    ]);
    const data = parseJson<Array<Record<string, unknown>>>(
      raw,
      `listOpenPRs(${owner}/${repo})`,
    );
    return data.map((pr) => ({
      number: pr.number as number,
      title: pr.title as string,
      headSha: (pr.head as Record<string, unknown>).sha as string,
      baseBranch: (pr.base as Record<string, unknown>).ref as string,
      labels: ((pr.labels as Array<Record<string, unknown>>) ?? []).map(
        (l) => l.name as string,
      ),
      author: (pr.user as Record<string, unknown>).login as string,
    }));
  }

  async getPRFiles(
    owner: string,
    repo: string,
    prNumber: number,
  ): Promise<PullRequestFile[]> {
    const raw = await this.gh([
      "api",
      `/repos/${owner}/${repo}/pulls/${prNumber}/files?per_page=100`,
      "--paginate",
    ]);
    const data = parseJson<Array<Record<string, unknown>>>(
      raw,
      `getPRFiles(${owner}/${repo}#${prNumber})`,
    );
    return data.map((f) => ({
      filename: f.filename as string,
      status: f.status as PullRequestFile["status"],
      additions: f.additions as number,
      deletions: f.deletions as number,
      patch: f.patch as string | undefined,
    }));
  }

  async getPRReviews(
    owner: string,
    repo: string,
    prNumber: number,
  ): Promise<PRReview[]> {
    const raw = await this.gh([
      "api",
      `/repos/${owner}/${repo}/pulls/${prNumber}/reviews?per_page=100`,
      "--paginate",
    ]);
    const data = parseJson<Array<Record<string, unknown>>>(
      raw,
      `getPRReviews(${owner}/${repo}#${prNumber})`,
    );
    return data.map((r) => ({
      id: r.id as number,
      body: (r.body as string) ?? "",
      user: ((r.user as Record<string, unknown>)?.login as string) ?? "",
      state: r.state as PRReview["state"],
      submittedAt: (r.submitted_at as string) ?? "",
    }));
  }

  async preflight(): Promise<PreflightResult> {
    const raw = await this.gh(["api", "/rate_limit"]);
    const data = parseJson<Record<string, unknown>>(raw, "preflight");
    const resources = data.resources as Record<string, unknown> | undefined;
    const core = resources?.core as Record<string, unknown> | undefined;

    let scopes: string[] = [];
    try {
      const authRaw = await this.gh(["auth", "status"], 10_000);
      const scopeMatch = authRaw.match(/Token scopes: (.+)/);
      if (scopeMatch) {
        scopes = scopeMatch[1].split(",").map((s) => s.trim());
      }
    } catch {
      // auth status may fail — scopes optional
    }

    return {
      remaining: (core?.remaining as number) ?? 0,
      scopes,
    };
  }

  async preflightRepo(
    owner: string,
    repo: string,
  ): Promise<RepoPreflightResult> {
    try {
      await this.gh(["api", `/repos/${owner}/${repo}`]);
      return { owner, repo, accessible: true };
    } catch (err: unknown) {
      return {
        owner,
        repo,
        accessible: false,
        error: (err as Error).message,
      };
    }
  }

  async getCommitDiff(
    owner: string,
    repo: string,
    base: string,
    head: string,
  ): Promise<CommitCompareResult> {
    const raw = await this.gh([
      "api",
      `/repos/${owner}/${repo}/compare/${base}...${head}`,
    ]);
    const data = parseJson<Record<string, unknown>>(
      raw,
      `getCommitDiff(${owner}/${repo}, ${base.slice(0, 7)}...${head.slice(0, 7)})`,
    );
    const files = (data.files as Array<Record<string, unknown>> | undefined) ?? [];
    return {
      filesChanged: files.map((f) => f.filename as string),
      totalCommits: (data.total_commits as number) ?? 0,
    };
  }

  async hasExistingReview(
    owner: string,
    repo: string,
    prNumber: number,
    headSha: string,
    markerKind: "review" | "skip" = "review",
  ): Promise<boolean> {
    const reviews = await this.getPRReviews(owner, repo, prNumber);
    // bug-1004: skip notices carry a distinct `-skip` marker — the genuine
    // matcher must never treat a skip-stamped sha as reviewed (that made
    // bridgebuilder:self-review unreachable without API surgery).
    const name = markerKind === "skip" ? `${this.marker}-skip` : this.marker;
    const exact = `<!-- ${name}: ${headSha} -->`;
    return reviews.some((r) => r.body.includes(exact));
  }

  async postReview(input: PostReviewInput): Promise<boolean> {
    const name = input.markerKind === "skip" ? `${this.marker}-skip` : this.marker;
    const marker = `\n\n<!-- ${name}: ${input.headSha} -->`;
    const body = input.body + marker;

    const makeArgs = (event: string): string[] => [
      "api",
      `/repos/${input.owner}/${input.repo}/pulls/${input.prNumber}/reviews`,
      "-X",
      "POST",
      "--raw-field",
      `body=${body}`,
      "-f",
      `event=${event}`,
      "-f",
      `commit_id=${input.headSha}`,
    ];

    try {
      await this.gh(makeArgs(input.event));
    } catch (err) {
      // GitHub returns 422 when REQUEST_CHANGES targets own PR.
      // Fall back to COMMENT so the review content is still posted.
      if (
        input.event === "REQUEST_CHANGES" &&
        err instanceof GhApiError &&
        err.httpStatus === 422
      ) {
        await this.gh(makeArgs("COMMENT"));
        return true;
      }
      throw err;
    }

    return true;
  }

  /**
   * Post an issue comment (not a review). Used for multi-model per-model comments
   * and consensus summary. Splits long comments at 65K chars with continuation headers.
   */
  async postComment(input: PostCommentInput): Promise<boolean> {
    const MAX_COMMENT_CHARS = 65_000;
    const body = input.body;

    if (body.length <= MAX_COMMENT_CHARS) {
      await this.postSingleComment(input.owner, input.repo, input.prNumber, body);
      return true;
    }

    // Split into chunks with continuation headers
    const chunks = splitComment(body, MAX_COMMENT_CHARS);
    for (let i = 0; i < chunks.length; i++) {
      const header = `**[${i + 1}/${chunks.length}]** _(continued)_\n\n`;
      const chunkBody = i === 0 ? chunks[i] : header + chunks[i];
      await this.postSingleComment(input.owner, input.repo, input.prNumber, chunkBody);
    }

    return true;
  }

  private async postSingleComment(
    owner: string,
    repo: string,
    prNumber: number,
    body: string,
  ): Promise<void> {
    // GitHub PR comments use the issues endpoint (PRs are issues in GitHub's model)
    await this.gh([
      "api",
      `/repos/${owner}/${repo}/issues/${prNumber}/comments`,
      "-X",
      "POST",
      "--raw-field",
      `body=${body}`,
    ]);
  }
}
