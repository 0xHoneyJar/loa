import { execFile } from "node:child_process";
import { promisify } from "node:util";
import {
  GitProviderError,
} from "../ports/git-provider.js";
import type {
  IGitProvider,
  PullRequest,
  PullRequestFile,
  PRReview,
  PreflightResult,
  RepoPreflightResult,
  CommitCompareResult,
} from "../ports/git-provider.js";
import type {
  IReviewPoster,
  PostReviewInput,
} from "../ports/review-poster.js";

const execFileAsync = promisify(execFile);

// Decision: execFile+gh CLI over Octokit SDK.
// gh handles token refresh, SSO, credential helpers, and proxy config automatically.
// execFile avoids shell injection (no shell: true). Tradeoff: shelling out is slower
// than HTTP-direct, but review volume is low (<50 PRs/run) so latency is acceptable.
// If throughput becomes a bottleneck, swap to Octokit behind IGitProvider port.
const GH_TIMEOUT_MS = 30_000;

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
  /^\/repos\/[^/]+\/[^/]+\/pulls\/\d+\/reviews\?per_page=100$/,
  /^\/repos\/[^/]+\/[^/]+\/pulls\/\d+\/reviews$/,
  // V3-1: compare commits for incremental review
  /^\/repos\/[^/]+\/[^/]+\/compare\/[a-f0-9]{7,40}\.\.\.[a-f0-9]{7,40}$/,
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
}

async function gh(
  args: string[],
  timeoutMs: number = GH_TIMEOUT_MS,
): Promise<string> {
  assertAllowedArgs(args);
  try {
    const { stdout } = await execFileAsync("gh", args, {
      timeout: timeoutMs,
      maxBuffer: 10 * 1024 * 1024,
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
    // Do not include stderr/message — may contain tokens or sensitive repo info
    const code = typeof e.code === "string" || typeof e.code === "number" ? String(e.code) : "unknown";
    // Classify by exit code: 1 = general failure, 4 = auth/forbidden in gh
    const errorCode = code === "4" ? "FORBIDDEN" : "NETWORK";
    // Extract HTTP status from gh stderr: "gh: ... (HTTP NNN)"
    const httpMatch = e.stderr?.match(/\(HTTP (\d{3})\)/);
    const httpStatus = httpMatch ? parseInt(httpMatch[1], 10) : undefined;
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

export class GitHubCLIAdapter implements IGitProvider, IReviewPoster {
  private readonly marker: string;

  constructor(config: GitHubCLIAdapterConfig) {
    this.marker = config.reviewMarker;
  }

  async listOpenPRs(owner: string, repo: string): Promise<PullRequest[]> {
    const raw = await gh([
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
    const raw = await gh([
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
    const raw = await gh([
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
    const raw = await gh(["api", "/rate_limit"]);
    const data = parseJson<Record<string, unknown>>(raw, "preflight");
    const resources = data.resources as Record<string, unknown> | undefined;
    const core = resources?.core as Record<string, unknown> | undefined;

    let scopes: string[] = [];
    try {
      const authRaw = await gh(["auth", "status"], 10_000);
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
      await gh(["api", `/repos/${owner}/${repo}`]);
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
    const raw = await gh([
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
  ): Promise<boolean> {
    const reviews = await this.getPRReviews(owner, repo, prNumber);
    const exact = `<!-- ${this.marker}: ${headSha} -->`;
    return reviews.some((r) => r.body.includes(exact));
  }

  async postReview(input: PostReviewInput): Promise<boolean> {
    const marker = `\n\n<!-- ${this.marker}: ${input.headSha} -->`;
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
      await gh(makeArgs(input.event));
    } catch (err) {
      // GitHub returns 422 when REQUEST_CHANGES targets own PR.
      // Fall back to COMMENT so the review content is still posted.
      if (
        input.event === "REQUEST_CHANGES" &&
        err instanceof GhApiError &&
        err.httpStatus === 422
      ) {
        await gh(makeArgs("COMMENT"));
        return true;
      }
      throw err;
    }

    return true;
  }
}
