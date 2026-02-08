import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { ReviewPipeline } from "../core/reviewer.js";
import { PRReviewTemplate } from "../core/template.js";
import { BridgebuilderContext } from "../core/context.js";
import type { IGitProvider } from "../ports/git-provider.js";
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
    personaPath: "BEAUVOIR.md",
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
    mockLogger(),
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

  describe("marker appended", () => {
    it("appends review marker to posted body", async () => {
      let postedBody = "";
      const pipeline = buildPipeline({
        poster: {
          postReview: async (input) => { postedBody = input.body; return true; },
        },
      });
      await pipeline.run("run-1");

      assert.ok(postedBody.includes("<!-- bridgebuilder-review:"));
      assert.ok(postedBody.includes("sha1"));
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
});
