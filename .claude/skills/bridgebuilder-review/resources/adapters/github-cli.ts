import { execFile } from "node:child_process";
import { promisify } from "node:util";
import type {
  IGitProvider,
  PullRequest,
  PullRequestFile,
  PRReview,
  PreflightResult,
  RepoPreflightResult,
} from "../ports/git-provider.js";
import type {
  IReviewPoster,
  PostReviewInput,
} from "../ports/review-poster.js";

const execFileAsync = promisify(execFile);

const GH_TIMEOUT_MS = 30_000;

/** Allowlisted gh API endpoints — adapter cannot call anything else. */
const ALLOWED_API_ENDPOINTS: RegExp[] = [
  /^\/rate_limit$/,
  /^\/repos\/[^/]+\/[^/]+$/,
  /^\/repos\/[^/]+\/[^/]+\/pulls\?state=open&per_page=100$/,
  /^\/repos\/[^/]+\/[^/]+\/pulls\/\d+\/files\?per_page=100$/,
  /^\/repos\/[^/]+\/[^/]+\/pulls\/\d+\/reviews\?per_page=100$/,
  /^\/repos\/[^/]+\/[^/]+\/pulls\/\d+\/reviews$/,
];

/** Flags that can redirect requests or alter target host/protocol. */
const FORBIDDEN_FLAGS = new Set([
  "--hostname",
  "-H",
  "--header",
  "--method",
  "-F",
  "--field",
  "--input",
]);

function assertAllowedArgs(args: string[]): void {
  const cmd = args[0];

  if (cmd === "api") {
    // Enforce endpoint at args[1] position (not arbitrary arg)
    const endpoint = args[1];
    if (!endpoint || !endpoint.startsWith("/")) {
      throw new Error("gh api endpoint missing or invalid");
    }

    // Block flags that can redirect or change target host/protocol
    for (let i = 2; i < args.length; i++) {
      const a = args[i];
      if (FORBIDDEN_FLAGS.has(a)) {
        throw new Error(`gh api flag not allowlisted: ${a}`);
      }
      for (const f of FORBIDDEN_FLAGS) {
        if (a.startsWith(f + "=")) {
          throw new Error(`gh api flag not allowlisted: ${a}`);
        }
      }
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
      throw new Error(
        "GitHub CLI (gh) required. Install: https://cli.github.com/ and run 'gh auth login'.",
      );
    }
    // Do not include stderr/message — may contain tokens or sensitive repo info
    const code = typeof e.code === "string" || typeof e.code === "number" ? String(e.code) : "unknown";
    throw new Error(`gh command failed (code=${code})`);
  }
}

function parseJson<T>(raw: string, context: string): T {
  try {
    return JSON.parse(raw) as T;
  } catch {
    // Do not include raw response — may contain sensitive data
    throw new Error(`Failed to parse gh JSON for ${context}`);
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

    await gh([
      "api",
      `/repos/${input.owner}/${input.repo}/pulls/${input.prNumber}/reviews`,
      "-X",
      "POST",
      "--raw-field",
      `body=${body}`,
      "-f",
      `event=${input.event}`,
      "-f",
      `commit_id=${input.headSha}`,
    ]);

    return true;
  }
}
