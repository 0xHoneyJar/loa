import { describe, it } from "node:test";
import assert from "node:assert/strict";

import { ReviewPipeline } from "../core/reviewer.js";
import { PRReviewTemplate } from "../core/template.js";
import { BridgebuilderContext } from "../core/context.js";
import type { BridgebuilderConfig } from "../core/types.js";
import type {
  IGitProvider,
  PullRequest,
  PullRequestFile,
  PreflightResult,
  RepoPreflightResult,
  PRReview,
} from "../ports/git-provider.js";
import type { ILLMProvider, ReviewRequest } from "../ports/llm-provider.js";
import type {
  IReviewPoster,
  PostReviewInput,
} from "../ports/review-poster.js";
import type { IOutputSanitizer } from "../ports/output-sanitizer.js";
import type { IHasher } from "../ports/hasher.js";
import type { ILogger } from "../ports/logger.js";
import type { IContextStore } from "../ports/context-store.js";
import type { ReviewResult } from "../core/types.js";

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const VALID_REVIEW =
  "## Summary\n\nThis PR adds user authentication with JWT tokens. Overall good quality.\n\n" +
  "## Findings\n\n" +
  "[Security] **high** — `auth.ts:42` Hardcoded secret in JWT signing. Use env var.\n" +
  "[Quality] **medium** — `login.ts:15` Missing error handling for token refresh.\n" +
  "[Test Coverage] **medium** — No tests for expired token path.\n" +
  "[Operational] **low** — No structured logging for auth failures.\n\n" +
  "## Callouts\n\n" +
  "[Security] Good use of bcrypt for password hashing.\n" +
  "[Quality] Clean separation of auth middleware from route handlers.";

const CRITICAL_REVIEW =
  "## Summary\n\nThis PR has a critical SQL injection vulnerability in the search endpoint.\n\n" +
  "## Findings\n\n" +
  "[Security] **critical** — SQL injection via unescaped user input. Must fix immediately.\n\n" +
  "## Callouts\n\n" +
  "[Quality] Good test structure overall.";

const fakePR: PullRequest = {
  number: 42,
  title: "Add auth module",
  headSha: "abc123def456",
  baseBranch: "main",
  labels: ["feature"],
  author: "dev-user",
};

const fakeFiles: PullRequestFile[] = [
  {
    filename: "src/auth.ts",
    status: "added",
    additions: 50,
    deletions: 0,
    patch: "+export function login() { return true; }",
  },
];

function makeConfig(overrides?: Partial<BridgebuilderConfig>): BridgebuilderConfig {
  return {
    repos: [{ owner: "test-org", repo: "test-repo" }],
    model: "claude-sonnet-4-5-20250929",
    maxPrs: 10,
    maxFilesPerPr: 50,
    maxDiffBytes: 100_000,
    maxInputTokens: 8000,
    maxOutputTokens: 4000,
    dimensions: ["security", "quality", "test-coverage"],
    reviewMarker: "bridgebuilder-review",
    repoOverridePath: "grimoires/bridgebuilder/BEAUVOIR.md",
    dryRun: false,
    excludePatterns: [],
    sanitizerMode: "default",
    maxRuntimeMinutes: 30,
    ...overrides,
  };
}

// ---------------------------------------------------------------------------
// Mock factories
// ---------------------------------------------------------------------------

function createMockGit(
  prs: PullRequest[] = [fakePR],
  files: PullRequestFile[] = fakeFiles,
): IGitProvider & { listOpenPRsCalled: number; getPRFilesCalled: number } {
  const mock = {
    listOpenPRsCalled: 0,
    getPRFilesCalled: 0,
    async listOpenPRs(_owner: string, _repo: string): Promise<PullRequest[]> {
      mock.listOpenPRsCalled++;
      return prs;
    },
    async getPRFiles(
      _owner: string,
      _repo: string,
      _prNumber: number,
    ): Promise<PullRequestFile[]> {
      mock.getPRFilesCalled++;
      return files;
    },
    async getPRReviews(
      _owner: string,
      _repo: string,
      _prNumber: number,
    ): Promise<PRReview[]> {
      return [];
    },
    async preflight(): Promise<PreflightResult> {
      return { remaining: 5000, scopes: ["repo"] };
    },
    async preflightRepo(
      owner: string,
      repo: string,
    ): Promise<RepoPreflightResult> {
      return { owner, repo, accessible: true };
    },
    async getCommitDiff() {
      return { filesChanged: [], totalCommits: 0 };
    },
  };
  return mock;
}

function createMockLLM(
  responseContent: string = VALID_REVIEW,
): ILLMProvider & { calls: ReviewRequest[] } {
  const mock = {
    calls: [] as ReviewRequest[],
    async generateReview(request: ReviewRequest) {
      mock.calls.push(request);
      return {
        content: responseContent,
        inputTokens: 500,
        outputTokens: 200,
        model: "claude-sonnet-4-5-20250929",
      };
    },
  };
  return mock;
}

function createMockPoster(): IReviewPoster & {
  postCalls: PostReviewInput[];
  hasExistingCalls: number;
} {
  const mock = {
    postCalls: [] as PostReviewInput[],
    hasExistingCalls: 0,
    async postReview(input: PostReviewInput): Promise<boolean> {
      mock.postCalls.push(input);
      return true;
    },
    async hasExistingReview(
      _owner: string,
      _repo: string,
      _prNumber: number,
      _headSha: string,
    ): Promise<boolean> {
      mock.hasExistingCalls++;
      return false;
    },
  };
  return mock;
}

function createMockSanitizer(safe: boolean = true): IOutputSanitizer & {
  calls: string[];
} {
  const mock = {
    calls: [] as string[],
    sanitize(content: string) {
      mock.calls.push(content);
      return { safe, sanitizedContent: content, redactedPatterns: [] };
    },
  };
  return mock;
}

function createMockHasher(): IHasher {
  return {
    async sha256(input: string): Promise<string> {
      // Simple deterministic hash for testing
      let h = 0;
      for (let i = 0; i < input.length; i++) {
        h = ((h << 5) - h + input.charCodeAt(i)) | 0;
      }
      return `mock-${Math.abs(h).toString(16)}`;
    },
  };
}

function createMockLogger(): ILogger {
  return {
    info: () => {},
    warn: () => {},
    error: () => {},
    debug: () => {},
  };
}

function createMockContextStore(): IContextStore {
  return {
    async load(): Promise<void> {},
    async getLastHash(): Promise<string | null> {
      return null; // Always treat as new
    },
    async setLastHash(): Promise<void> {},
    async claimReview(): Promise<boolean> {
      return true;
    },
    async finalizeReview(): Promise<void> {},
    async getLastReviewedSha(): Promise<string | null> {
      return null;
    },
    async setLastReviewedSha(): Promise<void> {},
  };
}

// ---------------------------------------------------------------------------
// Build pipeline helper
// ---------------------------------------------------------------------------

function buildPipeline(opts: {
  config?: Partial<BridgebuilderConfig>;
  git?: IGitProvider;
  llm?: ILLMProvider;
  poster?: IReviewPoster;
  sanitizer?: IOutputSanitizer;
  hasher?: IHasher;
  logger?: ILogger;
  contextStore?: IContextStore;
  persona?: string;
}) {
  const config = makeConfig(opts.config);
  const git = opts.git ?? createMockGit();
  const hasher = opts.hasher ?? createMockHasher();
  const template = new PRReviewTemplate(git, hasher, config);
  const context = new BridgebuilderContext(
    opts.contextStore ?? createMockContextStore(),
  );
  const poster = opts.poster ?? createMockPoster();
  const llm = opts.llm ?? createMockLLM();
  const sanitizer = opts.sanitizer ?? createMockSanitizer();
  const logger = opts.logger ?? createMockLogger();
  const persona = opts.persona ?? "Test persona";

  const pipeline = new ReviewPipeline(
    template,
    context,
    git,
    poster,
    llm,
    sanitizer,
    logger,
    persona,
    config,
  );

  return { pipeline, config, git, llm, poster, sanitizer, logger };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("integration: full pipeline", () => {
  it("reviews a single PR end-to-end and returns correct summary", async () => {
    const poster = createMockPoster();
    const sanitizer = createMockSanitizer();
    const llm = createMockLLM();

    const { pipeline } = buildPipeline({ poster, sanitizer, llm });
    const summary = await pipeline.run("test-run-1");

    assert.equal(summary.runId, "test-run-1");
    assert.equal(summary.reviewed, 1);
    assert.equal(summary.skipped, 0);
    assert.equal(summary.errors, 0);
    assert.equal(summary.results.length, 1);

    // Verify poster was called
    assert.equal(poster.postCalls.length, 1);
    const posted = poster.postCalls[0];
    assert.equal(posted.owner, "test-org");
    assert.equal(posted.repo, "test-repo");
    assert.equal(posted.prNumber, 42);
    assert.equal(posted.event, "COMMENT");

    // Verify sanitizer was called before posting
    assert.equal(sanitizer.calls.length, 1);

    // Verify LLM was called with persona
    assert.equal(llm.calls.length, 1);
  });

  it("dry-run does NOT call postReview", async () => {
    const poster = createMockPoster();

    const { pipeline } = buildPipeline({
      config: { dryRun: true },
      poster,
    });
    const summary = await pipeline.run("test-dry-run");

    // Pipeline processes the item but doesn't post
    assert.equal(summary.reviewed, 1);
    assert.equal(poster.postCalls.length, 0);

    // Result should show posted=false
    const result = summary.results[0];
    assert.equal(result.posted, false);
    assert.equal(result.skipped, false);
  });

  it("poster receives headSha for marker append", async () => {
    const poster = createMockPoster();

    const { pipeline } = buildPipeline({ poster });
    await pipeline.run("test-marker");

    // Marker append is the adapter's responsibility (github-cli.ts:300).
    // Core pipeline passes headSha so the adapter can build the marker.
    const posted = poster.postCalls[0];
    assert.equal(posted.headSha, "abc123def456");
    assert.equal(posted.prNumber, 42);
  });

  it("classifies critical findings as REQUEST_CHANGES", async () => {
    const poster = createMockPoster();
    const llm = createMockLLM(CRITICAL_REVIEW);

    const { pipeline } = buildPipeline({ poster, llm });
    await pipeline.run("test-critical");

    assert.equal(poster.postCalls[0].event, "REQUEST_CHANGES");
  });

  it("rejects invalid LLM response (refusal pattern)", async () => {
    const llm = createMockLLM(
      "I apologize, but I cannot review this code as an AI assistant.",
    );
    const poster = createMockPoster();

    const { pipeline } = buildPipeline({ llm, poster });
    const summary = await pipeline.run("test-refusal");

    // Should skip due to invalid response
    assert.equal(summary.skipped, 1);
    assert.equal(poster.postCalls.length, 0);
    assert.equal(summary.results[0].skipReason, "invalid_llm_response");
  });

  it("rejects LLM response missing required sections", async () => {
    const llm = createMockLLM("This looks fine to me. No issues found.");
    const poster = createMockPoster();

    const { pipeline } = buildPipeline({ llm, poster });
    const summary = await pipeline.run("test-no-sections");

    assert.equal(summary.skipped, 1);
    assert.equal(summary.results[0].skipReason, "invalid_llm_response");
  });

  it("sanitizer is called before posting", async () => {
    const sanitizer = createMockSanitizer();
    const poster = createMockPoster();
    const llm = createMockLLM();

    const { pipeline } = buildPipeline({ sanitizer, poster, llm });
    await pipeline.run("test-sanitizer-order");

    // Sanitizer received the LLM output
    assert.equal(sanitizer.calls.length, 1);
    assert.equal(sanitizer.calls[0], VALID_REVIEW);

    // Poster received the sanitized content (+ marker)
    assert.equal(poster.postCalls.length, 1);
  });

  it("skips already-reviewed PRs", async () => {
    const poster = createMockPoster();
    // Override hasExistingReview to return true
    poster.hasExistingReview = async () => true;

    const { pipeline } = buildPipeline({ poster });
    const summary = await pipeline.run("test-skip-existing");

    assert.equal(summary.skipped, 1);
    assert.equal(summary.results[0].skipReason, "already_reviewed");
    assert.equal(poster.postCalls.length, 0);
  });

  it("handles empty PR list gracefully", async () => {
    const git = createMockGit([]); // No open PRs

    const { pipeline } = buildPipeline({ git });
    const summary = await pipeline.run("test-empty");

    assert.equal(summary.reviewed, 0);
    assert.equal(summary.skipped, 0);
    assert.equal(summary.errors, 0);
    assert.equal(summary.results.length, 0);
  });

  it("skips run when GitHub quota is too low", async () => {
    const git = createMockGit();
    git.preflight = async () => ({ remaining: 50, scopes: ["repo"] });

    const { pipeline } = buildPipeline({ git });
    const summary = await pipeline.run("test-low-quota");

    assert.equal(summary.reviewed, 0);
    assert.equal(summary.results.length, 0);
  });

  it("handles LLM error gracefully", async () => {
    const llm = createMockLLM();
    llm.generateReview = async () => {
      throw new Error("anthropic API timeout");
    };
    const poster = createMockPoster();

    const { pipeline } = buildPipeline({ llm, poster });
    const summary = await pipeline.run("test-llm-error");

    assert.equal(summary.errors, 1);
    assert.equal(poster.postCalls.length, 0);
    assert.ok(summary.results[0].error);
    assert.equal(summary.results[0].error!.source, "llm");
    assert.equal(summary.results[0].error!.retryable, true);
  });

  it("processes multiple PRs in sequence", async () => {
    const pr2: PullRequest = {
      number: 43,
      title: "Fix bug",
      headSha: "def789",
      baseBranch: "main",
      labels: [],
      author: "another-user",
    };
    const git = createMockGit([fakePR, pr2]);
    const poster = createMockPoster();
    const llm = createMockLLM();

    const { pipeline } = buildPipeline({ git, poster, llm });
    const summary = await pipeline.run("test-multi");

    assert.equal(summary.reviewed, 2);
    assert.equal(poster.postCalls.length, 2);
    assert.equal(llm.calls.length, 2);
  });

  it("multi-repo: repo A inaccessible does not block repo B review", async () => {
    const repoBPR: PullRequest = {
      number: 99,
      title: "Repo B feature",
      headSha: "bbb999",
      baseBranch: "main",
      labels: [],
      author: "dev-b",
    };
    const repoBFiles: PullRequestFile[] = [
      {
        filename: "src/feature.ts",
        status: "added",
        additions: 10,
        deletions: 0,
        patch: "+export const feature = true;",
      },
    ];

    // Git mock that serves different data per repo
    const git: IGitProvider = {
      async listOpenPRs(_owner: string, repo: string) {
        if (repo === "repo-b") return [repoBPR];
        return [fakePR]; // repo-a
      },
      async getPRFiles(_owner: string, repo: string, _prNumber: number) {
        if (repo === "repo-b") return repoBFiles;
        return fakeFiles;
      },
      async getPRReviews() { return []; },
      async preflight() { return { remaining: 5000, scopes: ["repo"] }; },
      async preflightRepo(_owner: string, repo: string) {
        // Repo A fails, Repo B succeeds
        return { owner: _owner, repo, accessible: repo === "repo-b" };
      },
      async getCommitDiff() { return { filesChanged: [], totalCommits: 0 }; },
    };

    const poster = createMockPoster();
    const llm = createMockLLM();

    const { pipeline } = buildPipeline({
      config: {
        repos: [
          { owner: "test-org", repo: "repo-a" },
          { owner: "test-org", repo: "repo-b" },
        ],
      },
      git,
      poster,
      llm,
    });

    const summary = await pipeline.run("test-multi-repo-isolation");

    // Repo B's PR should be reviewed despite Repo A being inaccessible
    assert.equal(summary.reviewed, 1);
    assert.equal(poster.postCalls.length, 1);
    // Repo A's PR should be skipped as inaccessible
    const skipped = summary.results.filter((r) => r.skipped);
    assert.equal(skipped.length, 1);
    assert.equal(skipped[0].skipReason, "repo_inaccessible");
    assert.equal(skipped[0].item.repo, "repo-a");
    // The reviewed PR should be Repo B's
    const reviewed = summary.results.filter((r) => r.posted);
    assert.equal(reviewed.length, 1);
    assert.equal(reviewed[0].item.repo, "repo-b");
    assert.equal(reviewed[0].item.pr.number, 99);
  });

  it("RunSummary has valid timestamps", async () => {
    const { pipeline } = buildPipeline({});
    const before = new Date().toISOString();
    const summary = await pipeline.run("test-timestamps");
    const after = new Date().toISOString();

    assert.ok(summary.startTime >= before);
    assert.ok(summary.endTime <= after);
    assert.ok(summary.startTime <= summary.endTime);
  });
});
