import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { ReviewPipeline } from "../core/reviewer.js";
import { PRReviewTemplate } from "../core/template.js";
import { BridgebuilderContext } from "../core/context.js";
import { GitProviderError } from "../ports/git-provider.js";
import type { IGitProvider } from "../ports/git-provider.js";
import { LLMProviderError } from "../ports/llm-provider.js";
import type { ILLMProvider } from "../ports/llm-provider.js";
import type { IReviewPoster } from "../ports/review-poster.js";
import type { IOutputSanitizer } from "../ports/output-sanitizer.js";
import type { ILogger } from "../ports/logger.js";
import type { IContextStore } from "../ports/context-store.js";
import type { IHasher } from "../ports/hasher.js";
import type { BridgebuilderConfig } from "../core/types.js";

function mockConfig(overrides?: Partial<BridgebuilderConfig>): BridgebuilderConfig {
  return {
    repos: [{ owner: "test", repo: "repo" }],
    model: "claude-sonnet-4-5-20250929",
    maxPrs: 10,
    maxFilesPerPr: 50,
    maxDiffBytes: 100_000,
    maxInputTokens: 100_000,
    maxOutputTokens: 4096,
    dimensions: ["correctness"],
    reviewMarker: "bridgebuilder-review",
    repoOverridePath: "BEAUVOIR.md",
    dryRun: false,
    excludePatterns: [],
    sanitizerMode: "default" as const,
    maxRuntimeMinutes: 30,
    ...overrides,
  };
}

function mockGit(overrides?: Partial<IGitProvider>): IGitProvider {
  return {
    listOpenPRs: async () => [
      { number: 1, title: "PR", headSha: "sha1", baseBranch: "main", labels: [], author: "dev" },
    ],
    getPRFiles: async () => [
      { filename: "src/app.ts", status: "modified" as const, additions: 5, deletions: 3, patch: "+code" },
    ],
    getPRReviews: async () => [],
    preflight: async () => ({ remaining: 5000, scopes: ["repo"] }),
    preflightRepo: async () => ({ owner: "test", repo: "repo", accessible: true }),
    getCommitDiff: async () => ({ filesChanged: [], totalCommits: 0 }),
    ...overrides,
  };
}

function mockHasher(): IHasher {
  return { sha256: async (input: string) => `hash-${input.slice(0, 10)}` };
}

function mockStore(overrides?: Partial<IContextStore>): IContextStore {
  return {
    load: async () => {},
    getLastHash: async () => null,
    setLastHash: async () => {},
    claimReview: async () => true,
    finalizeReview: async () => {},
    getLastReviewedSha: async () => null,
    setLastReviewedSha: async () => {},
    ...overrides,
  };
}

function mockLLM(overrides?: Partial<ILLMProvider>): ILLMProvider {
  return {
    generateReview: async () => ({
      content: "## Summary\nGood PR.\n\n## Findings\n- No issues found.\n\n## Callouts\n- Clean code.",
      inputTokens: 100,
      outputTokens: 50,
      model: "test-model",
    }),
    ...overrides,
  };
}

function mockPoster(overrides?: Partial<IReviewPoster>): IReviewPoster {
  return {
    postReview: async () => true,
    hasExistingReview: async () => false,
    ...overrides,
  };
}

function mockSanitizer(overrides?: Partial<IOutputSanitizer>): IOutputSanitizer {
  return {
    sanitize: (content: string) => ({
      safe: true,
      sanitizedContent: content,
      redactedPatterns: [],
    }),
    ...overrides,
  };
}

function mockLogger(): ILogger {
  return {
    info: () => {},
    warn: () => {},
    error: () => {},
    debug: () => {},
  };
}

function buildPipeline(opts?: {
  config?: Partial<BridgebuilderConfig>;
  git?: Partial<IGitProvider>;
  llm?: Partial<ILLMProvider>;
  poster?: Partial<IReviewPoster>;
  sanitizer?: Partial<IOutputSanitizer>;
  store?: Partial<IContextStore>;
  logger?: ILogger;
  now?: () => number;
}) {
  const config = mockConfig(opts?.config);
  const git = mockGit(opts?.git);
  const hasher = mockHasher();
  const template = new PRReviewTemplate(git, hasher, config);
  const context = new BridgebuilderContext(mockStore(opts?.store));

  return new ReviewPipeline(
    template,
    context,
    git,
    mockPoster(opts?.poster),
    mockLLM(opts?.llm),
    mockSanitizer(opts?.sanitizer),
    opts?.logger ?? mockLogger(),
    "You are a code reviewer.",
    config,
    opts?.now ?? Date.now,
  );
}

describe("ReviewPipeline", () => {
  describe("skip on existing review", () => {
    it("skips when poster reports existing review", async () => {
      const pipeline = buildPipeline({
        poster: { hasExistingReview: async () => true },
      });
      const summary = await pipeline.run("run-1");

      assert.equal(summary.skipped, 1);
      assert.equal(summary.reviewed, 0);
      assert.equal(summary.results[0].skipReason, "already_reviewed");
    });
  });

  describe("dryRun behavior", () => {
    it("does not post review when dryRun is true", async () => {
      let postCalled = false;
      const pipeline = buildPipeline({
        config: { dryRun: true },
        poster: {
          postReview: async () => { postCalled = true; return true; },
        },
      });
      const summary = await pipeline.run("run-1");

      assert.ok(!postCalled);
      assert.equal(summary.results[0].posted, false);
    });
  });

  describe("structured output validation", () => {
    it("rejects empty LLM response", async () => {
      const pipeline = buildPipeline({
        llm: {
          generateReview: async () => ({
            content: "",
            inputTokens: 10,
            outputTokens: 0,
            model: "test",
          }),
        },
      });
      const summary = await pipeline.run("run-1");

      assert.equal(summary.skipped, 1);
      assert.equal(summary.results[0].skipReason, "invalid_llm_response");
    });

    it("rejects LLM refusal response", async () => {
      const pipeline = buildPipeline({
        llm: {
          generateReview: async () => ({
            content: "I cannot review this code as an AI assistant. I apologize for the inconvenience.",
            inputTokens: 10,
            outputTokens: 20,
            model: "test",
          }),
        },
      });
      const summary = await pipeline.run("run-1");

      assert.equal(summary.results[0].skipReason, "invalid_llm_response");
    });

    it("rejects response missing required headings", async () => {
      const pipeline = buildPipeline({
        llm: {
          generateReview: async () => ({
            content: "This is a review without proper headings. It has enough characters to pass length check but lacks structure.",
            inputTokens: 10,
            outputTokens: 30,
            model: "test",
          }),
        },
      });
      const summary = await pipeline.run("run-1");

      assert.equal(summary.results[0].skipReason, "invalid_llm_response");
    });
  });

  describe("marker data passed to poster", () => {
    it("passes headSha to poster for marker append", async () => {
      let postedHeadSha = "";
      let postedBody = "";
      const pipeline = buildPipeline({
        poster: {
          postReview: async (input) => { postedHeadSha = input.headSha; postedBody = input.body; return true; },
        },
      });
      await pipeline.run("run-1");

      // Marker is appended by the adapter (github-cli.ts), not the core reviewer.
      // Core passes headSha so the adapter can build: <!-- reviewMarker: headSha -->
      assert.equal(postedHeadSha, "sha1");
      assert.ok(postedBody.length > 0, "Body should contain sanitized review content");
    });
  });

  describe("re-check guard", () => {
    it("skips posting if review appeared between generate and post", async () => {
      let callCount = 0;
      const pipeline = buildPipeline({
        poster: {
          hasExistingReview: async () => {
            callCount++;
            // First call: no review. Second call (re-check): review exists
            return callCount > 1;
          },
          postReview: async () => true,
        },
      });
      const summary = await pipeline.run("run-1");

      assert.equal(summary.skipped, 1);
      assert.equal(summary.results[0].skipReason, "already_reviewed_recheck");
    });
  });

  describe("error categorization", () => {
    it("categorizes rate limit errors as transient", async () => {
      const pipeline = buildPipeline({
        llm: {
          generateReview: async () => { throw new Error("429 Too Many Requests"); },
        },
      });
      const summary = await pipeline.run("run-1");

      assert.equal(summary.errors, 1);
      assert.equal(summary.results[0].error?.category, "transient");
      assert.equal(summary.results[0].error?.retryable, true);
    });

    it("categorizes unknown errors correctly", async () => {
      const pipeline = buildPipeline({
        llm: {
          generateReview: async () => { throw new Error("Something unexpected"); },
        },
      });
      const summary = await pipeline.run("run-1");

      assert.equal(summary.results[0].error?.category, "unknown");
      assert.equal(summary.results[0].error?.retryable, false);
    });

    it("classifies typed GitProviderError RATE_LIMITED as transient", async () => {
      // Throw during hasExistingReview (inside processItem's try/catch)
      const pipeline = buildPipeline({
        poster: {
          hasExistingReview: async () => { throw new GitProviderError("RATE_LIMITED", "rate limited"); },
        },
      });
      const summary = await pipeline.run("run-1");

      assert.equal(summary.errors, 1);
      assert.equal(summary.results[0].error?.code, "E_RATE_LIMIT");
      assert.equal(summary.results[0].error?.source, "github");
      assert.equal(summary.results[0].error?.category, "transient");
      assert.equal(summary.results[0].error?.retryable, true);
    });

    it("classifies typed GitProviderError FORBIDDEN as permanent", async () => {
      const pipeline = buildPipeline({
        poster: {
          hasExistingReview: async () => { throw new GitProviderError("FORBIDDEN", "forbidden"); },
        },
      });
      const summary = await pipeline.run("run-1");

      assert.equal(summary.errors, 1);
      assert.equal(summary.results[0].error?.code, "E_GITHUB");
      assert.equal(summary.results[0].error?.source, "github");
      assert.equal(summary.results[0].error?.category, "permanent");
      assert.equal(summary.results[0].error?.retryable, false);
    });

    it("classifies typed LLMProviderError RATE_LIMITED as transient", async () => {
      const pipeline = buildPipeline({
        llm: {
          generateReview: async () => { throw new LLMProviderError("RATE_LIMITED", "rate limited"); },
        },
      });
      const summary = await pipeline.run("run-1");

      assert.equal(summary.errors, 1);
      assert.equal(summary.results[0].error?.code, "E_RATE_LIMIT");
      assert.equal(summary.results[0].error?.source, "llm");
      assert.equal(summary.results[0].error?.category, "transient");
      assert.equal(summary.results[0].error?.retryable, true);
    });

    it("classifies typed LLMProviderError INVALID_REQUEST as permanent", async () => {
      const pipeline = buildPipeline({
        llm: {
          generateReview: async () => { throw new LLMProviderError("INVALID_REQUEST", "bad request"); },
        },
      });
      const summary = await pipeline.run("run-1");

      assert.equal(summary.errors, 1);
      assert.equal(summary.results[0].error?.code, "E_LLM");
      assert.equal(summary.results[0].error?.source, "llm");
      assert.equal(summary.results[0].error?.category, "permanent");
      assert.equal(summary.results[0].error?.retryable, false);
    });

    it("classifies typed LLMProviderError NETWORK as transient", async () => {
      const pipeline = buildPipeline({
        llm: {
          generateReview: async () => { throw new LLMProviderError("NETWORK", "network error"); },
        },
      });
      const summary = await pipeline.run("run-1");

      assert.equal(summary.errors, 1);
      assert.equal(summary.results[0].error?.code, "E_LLM");
      assert.equal(summary.results[0].error?.source, "llm");
      assert.equal(summary.results[0].error?.category, "transient");
      assert.equal(summary.results[0].error?.retryable, true);
    });

    it("falls back to string matching for untyped errors", async () => {
      const pipeline = buildPipeline({
        llm: {
          generateReview: async () => { throw new Error("Anthropic API 500"); },
        },
      });
      const summary = await pipeline.run("run-1");

      assert.equal(summary.results[0].error?.code, "E_LLM");
      assert.equal(summary.results[0].error?.category, "transient");
    });
  });

  describe("sanitizer modes", () => {
    it("blocks posting in strict mode when content unsafe", async () => {
      const pipeline = buildPipeline({
        config: { sanitizerMode: "strict" },
        sanitizer: {
          sanitize: () => ({
            safe: false,
            sanitizedContent: "redacted",
            redactedPatterns: ["api_key"],
          }),
        },
      });
      const summary = await pipeline.run("run-1");

      assert.equal(summary.errors, 1);
      assert.equal(summary.results[0].error?.code, "E_SANITIZER_BLOCKED");
    });

    it("redacts and posts in default mode when content unsafe", async () => {
      let posted = false;
      const pipeline = buildPipeline({
        config: { sanitizerMode: "default" },
        sanitizer: {
          sanitize: () => ({
            safe: false,
            sanitizedContent: "## Summary\nRedacted.\n\n## Findings\n- Secret redacted.\n\n## Callouts\n- Good.",
            redactedPatterns: ["api_key"],
          }),
        },
        poster: {
          postReview: async () => { posted = true; return true; },
        },
      });
      await pipeline.run("run-1");

      assert.ok(posted);
    });
  });

  describe("preflight", () => {
    it("skips run when API quota too low", async () => {
      const pipeline = buildPipeline({
        git: { preflight: async () => ({ remaining: 50, scopes: ["repo"] }) },
      });
      const summary = await pipeline.run("run-1");

      assert.equal(summary.results.length, 0);
    });
  });

  describe("runtime enforcement", () => {
    it("skips remaining items when runtime limit exceeded", async () => {
      let tick = 0;
      const pipeline = buildPipeline({
        config: { maxRuntimeMinutes: 1 },
        git: {
          listOpenPRs: async () => [
            { number: 1, title: "PR1", headSha: "a", baseBranch: "main", labels: [], author: "u" },
            { number: 2, title: "PR2", headSha: "b", baseBranch: "main", labels: [], author: "u" },
          ],
          getPRFiles: async () => [
            { filename: "f.ts", status: "modified" as const, additions: 1, deletions: 0, patch: "+x" },
          ],
          getPRReviews: async () => [],
          preflight: async () => ({ remaining: 5000, scopes: ["repo"] }),
          preflightRepo: async () => ({ owner: "o", repo: "r", accessible: true }),
        },
        // First call: 0ms, subsequent: 2 minutes past limit
        now: () => { tick++; return tick === 1 ? 0 : 120_001; },
      });
      const summary = await pipeline.run("run-1");

      const runtimeSkipped = summary.results.filter(
        (r) => r.skipReason === "runtime_limit",
      );
      assert.ok(runtimeSkipped.length > 0);
    });
  });

  describe("RunSummary counts", () => {
    it("returns accurate reviewed/skipped/errors counts", async () => {
      const pipeline = buildPipeline();
      const summary = await pipeline.run("run-1");

      assert.equal(summary.runId, "run-1");
      assert.ok(summary.startTime);
      assert.ok(summary.endTime);
      assert.equal(typeof summary.reviewed, "number");
      assert.equal(typeof summary.skipped, "number");
      assert.equal(typeof summary.errors, "number");
      assert.equal(
        summary.reviewed + summary.skipped + summary.errors,
        summary.results.length,
      );
    });
  });

  describe("token calibration logging (BB-F1)", () => {
    it("emits calibration log with ratio when inputTokens available", async () => {
      const infoCalls: Array<{ msg: string; data: Record<string, unknown> }> = [];
      const logger: ILogger = {
        info: (msg: string, data?: Record<string, unknown>) => { infoCalls.push({ msg, data: data ?? {} }); },
        warn: () => {},
        error: () => {},
        debug: () => {},
      };
      const pipeline = buildPipeline({
        llm: {
          generateReview: async () => ({
            content: "## Summary\nGood PR.\n\n## Findings\n- No issues found.\n\n## Callouts\n- Clean code.",
            inputTokens: 500,
            outputTokens: 50,
            model: "test-model",
          }),
        },
        logger,
      });
      await pipeline.run("run-1");

      const calibrationLog = infoCalls.find((c) => c.msg === "calibration");
      assert.ok(calibrationLog, "Expected calibration log to be emitted");
      assert.equal(calibrationLog.data.phase, "calibration");
      assert.equal(calibrationLog.data.actualInputTokens, 500);
      assert.equal(typeof calibrationLog.data.estimatedTokens, "number");
      assert.equal(typeof calibrationLog.data.ratio, "number");
      assert.ok((calibrationLog.data.ratio as number) > 0, "Ratio should be positive");
      assert.equal(typeof calibrationLog.data.model, "string");
    });

    it("does not emit calibration log when inputTokens is 0", async () => {
      const infoCalls: Array<{ msg: string; data: Record<string, unknown> }> = [];
      const logger: ILogger = {
        info: (msg: string, data?: Record<string, unknown>) => { infoCalls.push({ msg, data: data ?? {} }); },
        warn: () => {},
        error: () => {},
        debug: () => {},
      };
      const pipeline = buildPipeline({
        llm: {
          generateReview: async () => ({
            content: "## Summary\nGood PR.\n\n## Findings\n- No issues found.\n\n## Callouts\n- Clean code.",
            inputTokens: 0,
            outputTokens: 50,
            model: "test-model",
          }),
        },
        logger,
      });
      await pipeline.run("run-1");

      const calibrationLog = infoCalls.find((c) => c.msg === "calibration");
      assert.equal(calibrationLog, undefined, "Should not emit calibration when inputTokens=0");
    });
  });

  describe("incremental review (V3-1)", () => {
    it("reviews only delta files when lastReviewedSha exists", async () => {
      let postedBody = "";
      const pipeline = buildPipeline({
        git: {
          listOpenPRs: async () => [
            { number: 1, title: "PR", headSha: "newsha", baseBranch: "main", labels: [], author: "dev" },
          ],
          getPRFiles: async () => [
            { filename: "src/app.ts", status: "modified" as const, additions: 5, deletions: 3, patch: "+code" },
            { filename: "src/old.ts", status: "modified" as const, additions: 1, deletions: 1, patch: "+old" },
          ],
          getCommitDiff: async () => ({
            filesChanged: ["src/app.ts"],
            totalCommits: 1,
          }),
        },
        store: {
          getLastReviewedSha: async () => "oldsha",
        },
        poster: {
          postReview: async (input) => { postedBody = input.body; return true; },
          hasExistingReview: async () => false,
        },
      });
      const summary = await pipeline.run("run-inc");
      assert.equal(summary.reviewed, 1);
      // The incremental banner should be in the review (it gets sent to LLM, not directly in posted body)
    });

    it("falls back to full review when getCommitDiff fails", async () => {
      const pipeline = buildPipeline({
        git: {
          listOpenPRs: async () => [
            { number: 1, title: "PR", headSha: "newsha", baseBranch: "main", labels: [], author: "dev" },
          ],
          getPRFiles: async () => [
            { filename: "src/app.ts", status: "modified" as const, additions: 5, deletions: 3, patch: "+code" },
          ],
          getCommitDiff: async () => { throw new Error("force push — SHA gone"); },
        },
        store: {
          getLastReviewedSha: async () => "oldsha",
        },
      });
      const summary = await pipeline.run("run-fallback");
      assert.equal(summary.reviewed, 1, "Should still review with full diff after fallback");
    });

    it("does full review when forceFullReview is set", async () => {
      const infoCalls: Array<{ msg: string }> = [];
      const pipeline = buildPipeline({
        config: { forceFullReview: true },
        git: {
          listOpenPRs: async () => [
            { number: 1, title: "PR", headSha: "newsha", baseBranch: "main", labels: [], author: "dev" },
          ],
          getPRFiles: async () => [
            { filename: "src/app.ts", status: "modified" as const, additions: 5, deletions: 3, patch: "+code" },
            { filename: "src/old.ts", status: "modified" as const, additions: 1, deletions: 1, patch: "+old" },
          ],
          getCommitDiff: async () => ({
            filesChanged: ["src/app.ts"],
            totalCommits: 1,
          }),
        },
        store: {
          getLastReviewedSha: async () => "oldsha",
        },
        logger: {
          info: (msg: string) => { infoCalls.push({ msg }); },
          warn: () => {},
          error: () => {},
          debug: () => {},
        },
      });
      const summary = await pipeline.run("run-force");
      assert.equal(summary.reviewed, 1);
      // Should NOT have "Incremental review mode" log since forceFullReview skips it
      const incrementalLog = infoCalls.find((c) => c.msg === "Incremental review mode");
      assert.equal(incrementalLog, undefined, "Should not use incremental mode when forceFullReview=true");
    });

    it("does full review when lastReviewedSha is null", async () => {
      const pipeline = buildPipeline({
        store: {
          getLastReviewedSha: async () => null,
        },
      });
      const summary = await pipeline.run("run-first");
      assert.equal(summary.reviewed, 1);
    });
  });
});
