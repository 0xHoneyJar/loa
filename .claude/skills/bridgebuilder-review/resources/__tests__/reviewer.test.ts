import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, writeFileSync, unlinkSync, mkdtempSync } from "node:fs";
import { join, dirname } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
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
    reviewMode: "single-pass" as const,
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

  describe("two-pass review mode", () => {
    const VALID_PASS1_CONTENT = [
      "<!-- bridge-findings-start -->",
      "```json",
      JSON.stringify({
        schema_version: 1,
        findings: [
          { id: "F001", title: "Issue", severity: "HIGH", category: "security", file: "src/app.ts:1", description: "d", suggestion: "s" },
          { id: "F002", title: "Good", severity: "PRAISE", category: "quality", file: "src/app.ts:5", description: "d", suggestion: "s" },
        ],
      }),
      "```",
      "<!-- bridge-findings-end -->",
    ].join("\n");

    const VALID_PASS2_CONTENT = [
      "## Summary",
      "",
      "Two-pass enriched review.",
      "",
      "## Findings",
      "",
      "<!-- bridge-findings-start -->",
      "```json",
      JSON.stringify({
        schema_version: 1,
        findings: [
          { id: "F001", title: "Issue", severity: "HIGH", category: "security", file: "src/app.ts:1", description: "d", suggestion: "s", faang_parallel: "Google SRE" },
          { id: "F002", title: "Good", severity: "PRAISE", category: "quality", file: "src/app.ts:5", description: "d", suggestion: "s", metaphor: "Like a well-oiled machine" },
        ],
      }),
      "```",
      "<!-- bridge-findings-end -->",
      "",
      "## Callouts",
      "",
      "- Good architecture.",
    ].join("\n");

    it("routes to two-pass when reviewMode is 'two-pass'", async () => {
      let callCount = 0;
      const pipeline = buildPipeline({
        config: { reviewMode: "two-pass" },
        llm: {
          generateReview: async () => {
            callCount++;
            if (callCount === 1) {
              return { content: VALID_PASS1_CONTENT, inputTokens: 500, outputTokens: 200, model: "test" };
            }
            return { content: VALID_PASS2_CONTENT, inputTokens: 100, outputTokens: 300, model: "test" };
          },
        },
      });
      const summary = await pipeline.run("run-2p");
      assert.equal(summary.reviewed, 1);
      assert.equal(callCount, 2, "Should make exactly 2 LLM calls");
    });

    it("returns pass1Tokens and pass2Tokens in two-pass mode", async () => {
      let callCount = 0;
      const pipeline = buildPipeline({
        config: { reviewMode: "two-pass" },
        llm: {
          generateReview: async () => {
            callCount++;
            if (callCount === 1) {
              return { content: VALID_PASS1_CONTENT, inputTokens: 500, outputTokens: 200, model: "test" };
            }
            return { content: VALID_PASS2_CONTENT, inputTokens: 100, outputTokens: 300, model: "test" };
          },
        },
      });
      const summary = await pipeline.run("run-tokens");
      const result = summary.results[0];
      assert.ok(result.pass1Tokens, "Should have pass1Tokens");
      assert.equal(result.pass1Tokens!.input, 500);
      assert.equal(result.pass1Tokens!.output, 200);
      assert.ok(result.pass2Tokens, "Should have pass2Tokens");
      assert.equal(result.pass2Tokens!.input, 100);
      assert.equal(result.pass2Tokens!.output, 300);
      assert.equal(result.inputTokens, 600, "Total inputTokens = pass1 + pass2");
      assert.equal(result.outputTokens, 500, "Total outputTokens = pass1 + pass2");
    });

    it("saves pass1Output for observability", async () => {
      let callCount = 0;
      const pipeline = buildPipeline({
        config: { reviewMode: "two-pass" },
        llm: {
          generateReview: async () => {
            callCount++;
            if (callCount === 1) {
              return { content: VALID_PASS1_CONTENT, inputTokens: 500, outputTokens: 200, model: "test" };
            }
            return { content: VALID_PASS2_CONTENT, inputTokens: 100, outputTokens: 300, model: "test" };
          },
        },
      });
      const summary = await pipeline.run("run-obs");
      assert.ok(summary.results[0].pass1Output, "Should save pass1Output");
      assert.ok(summary.results[0].pass1Output!.includes("bridge-findings-start"));
    });

    it("falls back to unenriched output when Pass 2 fails", async () => {
      let callCount = 0;
      let postedBody = "";
      const pipeline = buildPipeline({
        config: { reviewMode: "two-pass" },
        llm: {
          generateReview: async () => {
            callCount++;
            if (callCount === 1) {
              return { content: VALID_PASS1_CONTENT, inputTokens: 500, outputTokens: 200, model: "test" };
            }
            throw new Error("Pass 2 LLM failure");
          },
        },
        poster: {
          postReview: async (input) => { postedBody = input.body; return true; },
        },
      });
      const summary = await pipeline.run("run-fallback");
      assert.equal(summary.reviewed, 1);
      assert.ok(postedBody.includes("## Summary"), "Fallback should have Summary");
      assert.ok(postedBody.includes("## Findings"), "Fallback should have Findings");
      assert.ok(postedBody.includes("bridge-findings-start"), "Fallback should preserve findings");
      assert.ok(postedBody.includes("Enrichment unavailable"), "Fallback should note enrichment was unavailable");
    });

    it("falls back when Pass 2 adds findings (preservation check)", async () => {
      let callCount = 0;
      const addedFindingsContent = [
        "## Summary", "", "Review.", "",
        "## Findings", "",
        "<!-- bridge-findings-start -->",
        "```json",
        JSON.stringify({
          schema_version: 1,
          findings: [
            { id: "F001", title: "Issue", severity: "HIGH", category: "security", file: "src/app.ts:1", description: "d", suggestion: "s" },
            { id: "F002", title: "Good", severity: "PRAISE", category: "quality", file: "src/app.ts:5", description: "d", suggestion: "s" },
            { id: "F003", title: "Hallucinated", severity: "LOW", category: "quality", file: "src/x.ts:1", description: "d", suggestion: "s" },
          ],
        }),
        "```",
        "<!-- bridge-findings-end -->",
        "", "## Callouts", "", "- Ok.",
      ].join("\n");

      let postedBody = "";
      const pipeline = buildPipeline({
        config: { reviewMode: "two-pass" },
        llm: {
          generateReview: async () => {
            callCount++;
            if (callCount === 1) {
              return { content: VALID_PASS1_CONTENT, inputTokens: 500, outputTokens: 200, model: "test" };
            }
            return { content: addedFindingsContent, inputTokens: 100, outputTokens: 300, model: "test" };
          },
        },
        poster: {
          postReview: async (input) => { postedBody = input.body; return true; },
        },
      });
      const summary = await pipeline.run("run-added");
      assert.equal(summary.reviewed, 1);
      assert.ok(postedBody.includes("Enrichment unavailable"), "Should fall back to unenriched output");
    });

    it("falls back when Pass 2 reclassifies severity", async () => {
      let callCount = 0;
      const reclassifiedContent = [
        "## Summary", "", "Review.", "",
        "## Findings", "",
        "<!-- bridge-findings-start -->",
        "```json",
        JSON.stringify({
          schema_version: 1,
          findings: [
            { id: "F001", title: "Issue", severity: "CRITICAL", category: "security", file: "src/app.ts:1", description: "d", suggestion: "s" },
            { id: "F002", title: "Good", severity: "PRAISE", category: "quality", file: "src/app.ts:5", description: "d", suggestion: "s" },
          ],
        }),
        "```",
        "<!-- bridge-findings-end -->",
        "", "## Callouts", "", "- Ok.",
      ].join("\n");

      let postedBody = "";
      const pipeline = buildPipeline({
        config: { reviewMode: "two-pass" },
        llm: {
          generateReview: async () => {
            callCount++;
            if (callCount === 1) {
              return { content: VALID_PASS1_CONTENT, inputTokens: 500, outputTokens: 200, model: "test" };
            }
            return { content: reclassifiedContent, inputTokens: 100, outputTokens: 300, model: "test" };
          },
        },
        poster: {
          postReview: async (input) => { postedBody = input.body; return true; },
        },
      });
      const summary = await pipeline.run("run-reclass");
      assert.equal(summary.reviewed, 1);
      assert.ok(postedBody.includes("Enrichment unavailable"), "Should fall back when severity reclassified");
    });

    it("falls back when Pass 2 response is invalid (no Summary heading)", async () => {
      let callCount = 0;
      let postedBody = "";
      const pipeline = buildPipeline({
        config: { reviewMode: "two-pass" },
        llm: {
          generateReview: async () => {
            callCount++;
            if (callCount === 1) {
              return { content: VALID_PASS1_CONTENT, inputTokens: 500, outputTokens: 200, model: "test" };
            }
            return { content: "Just some random text without proper headings or structure for the review output format.", inputTokens: 100, outputTokens: 50, model: "test" };
          },
        },
        poster: {
          postReview: async (input) => { postedBody = input.body; return true; },
        },
      });
      const summary = await pipeline.run("run-invalid");
      assert.equal(summary.reviewed, 1);
      assert.ok(postedBody.includes("Enrichment unavailable"), "Should fall back to unenriched output");
    });

    it("skips when Pass 1 produces no findings and no valid response", async () => {
      const pipeline = buildPipeline({
        config: { reviewMode: "two-pass" },
        llm: {
          generateReview: async () => ({
            content: "No structured findings here.",
            inputTokens: 100,
            outputTokens: 50,
            model: "test",
          }),
        },
      });
      const summary = await pipeline.run("run-nofind");
      assert.equal(summary.skipped, 1);
      assert.equal(summary.results[0].skipReason, "invalid_llm_response");
    });

    it("single-pass mode is unchanged (default path)", async () => {
      let callCount = 0;
      const pipeline = buildPipeline({
        config: { reviewMode: "single-pass" },
        llm: {
          generateReview: async () => {
            callCount++;
            return {
              content: "## Summary\nGood PR.\n\n## Findings\n- No issues found.\n\n## Callouts\n- Clean code.",
              inputTokens: 100, outputTokens: 50, model: "test",
            };
          },
        },
      });
      const summary = await pipeline.run("run-sp");
      assert.equal(summary.reviewed, 1);
      assert.equal(callCount, 1, "Single-pass should make exactly 1 LLM call");
    });

    it("two-pass respects dryRun flag", async () => {
      let callCount = 0;
      let postCalled = false;
      const pipeline = buildPipeline({
        config: { reviewMode: "two-pass", dryRun: true },
        llm: {
          generateReview: async () => {
            callCount++;
            if (callCount === 1) {
              return { content: VALID_PASS1_CONTENT, inputTokens: 500, outputTokens: 200, model: "test" };
            }
            return { content: VALID_PASS2_CONTENT, inputTokens: 100, outputTokens: 300, model: "test" };
          },
        },
        poster: {
          postReview: async () => { postCalled = true; return true; },
        },
      });
      const summary = await pipeline.run("run-dry");
      assert.ok(!postCalled, "Should not post in dry run");
      assert.equal(summary.results[0].posted, false);
    });

    it("two-pass handles all-files-excluded by Loa filtering", async () => {
      let postBody = "";
      const pipeline = buildPipeline({
        config: { reviewMode: "two-pass", loaAware: true },
        git: {
          listOpenPRs: async () => [
            { number: 1, title: "PR", headSha: "sha1", baseBranch: "main", labels: [], author: "dev" },
          ],
          getPRFiles: async () => [
            { filename: ".claude/loa/something.md", status: "modified" as const, additions: 5, deletions: 3, patch: "+code" },
          ],
          getPRReviews: async () => [],
          preflight: async () => ({ remaining: 5000, scopes: ["repo"] }),
          preflightRepo: async () => ({ owner: "test", repo: "repo", accessible: true }),
        },
        poster: {
          postReview: async (input) => { postBody = input.body; return true; },
        },
      });
      const summary = await pipeline.run("run-loa");
      assert.equal(summary.skipped, 1);
      assert.equal(summary.results[0].skipReason, "all_files_excluded");
    });

    it("two-pass falls back to unenriched when enrichment-only fields preserved but pass2 valid", async () => {
      let callCount = 0;
      let postedBody = "";
      const pipeline = buildPipeline({
        config: { reviewMode: "two-pass" },
        llm: {
          generateReview: async () => {
            callCount++;
            if (callCount === 1) {
              return { content: VALID_PASS1_CONTENT, inputTokens: 500, outputTokens: 200, model: "test" };
            }
            return { content: VALID_PASS2_CONTENT, inputTokens: 100, outputTokens: 300, model: "test" };
          },
        },
        poster: {
          postReview: async (input) => { postedBody = input.body; return true; },
        },
      });
      const summary = await pipeline.run("run-enrich-ok");
      assert.equal(summary.reviewed, 1);
      assert.ok(postedBody.includes("## Summary"), "Enriched output should have Summary");
      assert.ok(postedBody.includes("## Findings"), "Enriched output should have Findings");
      assert.ok(!postedBody.includes("Enrichment unavailable"), "Should NOT be the fallback");
    });

    it("falls back when Pass 2 reclassifies category", async () => {
      let callCount = 0;
      const categoryChangedContent = [
        "## Summary", "", "Review.", "",
        "## Findings", "",
        "<!-- bridge-findings-start -->",
        "```json",
        JSON.stringify({
          schema_version: 1,
          findings: [
            { id: "F001", title: "Issue", severity: "HIGH", category: "correctness", file: "src/app.ts:1", description: "d", suggestion: "s" },
            { id: "F002", title: "Good", severity: "PRAISE", category: "quality", file: "src/app.ts:5", description: "d", suggestion: "s" },
          ],
        }),
        "```",
        "<!-- bridge-findings-end -->",
        "", "## Callouts", "", "- Ok.",
      ].join("\n");

      let postedBody = "";
      const pipeline = buildPipeline({
        config: { reviewMode: "two-pass" },
        llm: {
          generateReview: async () => {
            callCount++;
            if (callCount === 1) {
              return { content: VALID_PASS1_CONTENT, inputTokens: 500, outputTokens: 200, model: "test" };
            }
            return { content: categoryChangedContent, inputTokens: 100, outputTokens: 300, model: "test" };
          },
        },
        poster: {
          postReview: async (input) => { postedBody = input.body; return true; },
        },
      });
      const summary = await pipeline.run("run-cat-change");
      assert.equal(summary.reviewed, 1);
      assert.ok(postedBody.includes("Enrichment unavailable"), "Should fall back when category reclassified");
    });

    it("falls back when Pass 2 has valid prose but no findings markers", async () => {
      let callCount = 0;
      const noMarkersContent = [
        "## Summary",
        "",
        "This is a valid-looking review with proper headings.",
        "",
        "## Findings",
        "",
        "Here are the findings in prose form without any JSON markers.",
        "- F001: Some issue was found",
        "- F002: Some good thing was found",
        "",
        "## Callouts",
        "",
        "- Good architecture overall.",
      ].join("\n");

      let postedBody = "";
      const pipeline = buildPipeline({
        config: { reviewMode: "two-pass" },
        llm: {
          generateReview: async () => {
            callCount++;
            if (callCount === 1) {
              return { content: VALID_PASS1_CONTENT, inputTokens: 500, outputTokens: 200, model: "test" };
            }
            return { content: noMarkersContent, inputTokens: 100, outputTokens: 300, model: "test" };
          },
        },
        poster: {
          postReview: async (input) => { postedBody = input.body; return true; },
        },
      });
      const summary = await pipeline.run("run-no-markers");
      assert.equal(summary.reviewed, 1);
      assert.ok(postedBody.includes("Enrichment unavailable"), "Should fall back when findings markers missing from Pass 2");
      assert.ok(postedBody.includes("bridge-findings-start"), "Fallback should preserve structured findings from Pass 1");
    });

    it("two-pass sanitizer warn-and-continue posts redacted review in default mode", async () => {
      let callCount = 0;
      let posted = false;
      const pipeline = buildPipeline({
        config: { reviewMode: "two-pass", sanitizerMode: "default" },
        llm: {
          generateReview: async () => {
            callCount++;
            if (callCount === 1) {
              return { content: VALID_PASS1_CONTENT, inputTokens: 500, outputTokens: 200, model: "test" };
            }
            return { content: VALID_PASS2_CONTENT, inputTokens: 100, outputTokens: 300, model: "test" };
          },
        },
        sanitizer: {
          sanitize: () => ({
            safe: false,
            sanitizedContent: VALID_PASS2_CONTENT,
            redactedPatterns: ["api_key"],
          }),
        },
        poster: {
          postReview: async () => { posted = true; return true; },
        },
      });
      const summary = await pipeline.run("run-2p-sanitizer-warn");
      assert.equal(summary.reviewed, 1);
      assert.ok(posted, "Should still post when sanitizer warns in default mode");
    });

    it("two-pass recheck-fail returns skip when hasExistingReview throws twice", async () => {
      let llmCallCount = 0;
      let recheckCallCount = 0;
      const pipeline = buildPipeline({
        config: { reviewMode: "two-pass" },
        llm: {
          generateReview: async () => {
            llmCallCount++;
            if (llmCallCount === 1) {
              return { content: VALID_PASS1_CONTENT, inputTokens: 500, outputTokens: 200, model: "test" };
            }
            return { content: VALID_PASS2_CONTENT, inputTokens: 100, outputTokens: 300, model: "test" };
          },
        },
        poster: {
          hasExistingReview: async () => {
            recheckCallCount++;
            // First call is the initial check (step 2) — return false (no existing review)
            if (recheckCallCount === 1) return false;
            // Subsequent calls are the recheck in postAndFinalize — throw
            throw new Error("GitHub API unavailable");
          },
          postReview: async () => true,
        },
      });
      const summary = await pipeline.run("run-2p-recheck-fail");
      assert.equal(summary.skipped, 1);
      assert.equal(summary.results[0].skipReason, "recheck_failed");
    });
  });

  describe("confidence pipeline (Sprint 66)", () => {
    const FINDINGS_WITH_CONFIDENCE = [
      "<!-- bridge-findings-start -->",
      "```json",
      JSON.stringify({
        schema_version: 1,
        findings: [
          { id: "F001", title: "Issue", severity: "HIGH", category: "security", file: "src/app.ts:1", description: "d", suggestion: "s", confidence: 0.9 },
          { id: "F002", title: "Good", severity: "PRAISE", category: "quality", file: "src/app.ts:5", description: "d", suggestion: "s", confidence: 0.7 },
          { id: "F003", title: "Maybe", severity: "LOW", category: "style", file: "src/app.ts:10", description: "d", suggestion: "s", confidence: 0.3 },
        ],
      }),
      "```",
      "<!-- bridge-findings-end -->",
    ].join("\n");

    function makePass2WithConfidence(findings: Array<Record<string, unknown>>): string {
      return [
        "## Summary", "", "Review.", "",
        "## Findings", "",
        "<!-- bridge-findings-start -->",
        "```json",
        JSON.stringify({ schema_version: 1, findings }),
        "```",
        "<!-- bridge-findings-end -->",
        "", "## Callouts", "", "- Ok.",
      ].join("\n");
    }

    it("parses confidence values from Pass 1 and includes stats in result", async () => {
      let callCount = 0;
      const pass2Findings = [
        { id: "F001", title: "Issue", severity: "HIGH", category: "security", file: "src/app.ts:1", description: "d", suggestion: "s", confidence: 0.9, faang_parallel: "Google" },
        { id: "F002", title: "Good", severity: "PRAISE", category: "quality", file: "src/app.ts:5", description: "d", suggestion: "s", confidence: 0.7, metaphor: "Well-oiled" },
        { id: "F003", title: "Maybe", severity: "LOW", category: "style", file: "src/app.ts:10", description: "d", suggestion: "s", confidence: 0.3 },
      ];
      const pipeline = buildPipeline({
        config: { reviewMode: "two-pass" },
        llm: {
          generateReview: async () => {
            callCount++;
            if (callCount === 1) {
              return { content: FINDINGS_WITH_CONFIDENCE, inputTokens: 500, outputTokens: 200, model: "test" };
            }
            return { content: makePass2WithConfidence(pass2Findings), inputTokens: 100, outputTokens: 300, model: "test" };
          },
        },
      });
      const summary = await pipeline.run("run-conf-stats");
      const result = summary.results[0];
      assert.equal(summary.reviewed, 1);
      assert.ok(result.pass1ConfidenceStats, "Should have pass1ConfidenceStats");
      assert.equal(result.pass1ConfidenceStats!.min, 0.3);
      assert.equal(result.pass1ConfidenceStats!.max, 0.9);
      assert.equal(result.pass1ConfidenceStats!.count, 3);
      assert.ok(result.pass1ConfidenceStats!.mean > 0.6 && result.pass1ConfidenceStats!.mean < 0.7);
    });

    it("silently drops invalid confidence values (negative, >1, string)", async () => {
      let callCount = 0;
      const invalidConfidenceFindings = [
        "<!-- bridge-findings-start -->",
        "```json",
        JSON.stringify({
          schema_version: 1,
          findings: [
            { id: "F001", title: "Issue", severity: "HIGH", category: "security", file: "f:1", description: "d", suggestion: "s", confidence: -0.5 },
            { id: "F002", title: "Good", severity: "PRAISE", category: "quality", file: "f:2", description: "d", suggestion: "s", confidence: 1.5 },
            { id: "F003", title: "Low", severity: "LOW", category: "style", file: "f:3", description: "d", suggestion: "s", confidence: "high" },
            { id: "F004", title: "Ok", severity: "MEDIUM", category: "perf", file: "f:4", description: "d", suggestion: "s", confidence: 0.8 },
          ],
        }),
        "```",
        "<!-- bridge-findings-end -->",
      ].join("\n");

      const pass2 = makePass2WithConfidence([
        { id: "F001", title: "Issue", severity: "HIGH", category: "security", file: "f:1", description: "d", suggestion: "s" },
        { id: "F002", title: "Good", severity: "PRAISE", category: "quality", file: "f:2", description: "d", suggestion: "s" },
        { id: "F003", title: "Low", severity: "LOW", category: "style", file: "f:3", description: "d", suggestion: "s" },
        { id: "F004", title: "Ok", severity: "MEDIUM", category: "perf", file: "f:4", description: "d", suggestion: "s", confidence: 0.8 },
      ]);

      const pipeline = buildPipeline({
        config: { reviewMode: "two-pass" },
        llm: {
          generateReview: async () => {
            callCount++;
            if (callCount === 1) {
              return { content: invalidConfidenceFindings, inputTokens: 500, outputTokens: 200, model: "test" };
            }
            return { content: pass2, inputTokens: 100, outputTokens: 300, model: "test" };
          },
        },
      });
      const summary = await pipeline.run("run-conf-invalid");
      const result = summary.results[0];
      assert.equal(summary.reviewed, 1);
      // Only F004 has valid confidence (0.8)
      assert.ok(result.pass1ConfidenceStats, "Should have stats from valid confidence values");
      assert.equal(result.pass1ConfidenceStats!.count, 1);
      assert.equal(result.pass1ConfidenceStats!.min, 0.8);
      assert.equal(result.pass1ConfidenceStats!.max, 0.8);
    });

    it("omits confidence stats when no findings have confidence", async () => {
      let callCount = 0;
      const noConfFindings = [
        "<!-- bridge-findings-start -->",
        "```json",
        JSON.stringify({
          schema_version: 1,
          findings: [
            { id: "F001", title: "Issue", severity: "HIGH", category: "security", file: "f:1", description: "d", suggestion: "s" },
            { id: "F002", title: "Good", severity: "PRAISE", category: "quality", file: "f:2", description: "d", suggestion: "s" },
          ],
        }),
        "```",
        "<!-- bridge-findings-end -->",
      ].join("\n");

      const pass2 = makePass2WithConfidence([
        { id: "F001", title: "Issue", severity: "HIGH", category: "security", file: "f:1", description: "d", suggestion: "s" },
        { id: "F002", title: "Good", severity: "PRAISE", category: "quality", file: "f:2", description: "d", suggestion: "s" },
      ]);

      const pipeline = buildPipeline({
        config: { reviewMode: "two-pass" },
        llm: {
          generateReview: async () => {
            callCount++;
            if (callCount === 1) {
              return { content: noConfFindings, inputTokens: 500, outputTokens: 200, model: "test" };
            }
            return { content: pass2, inputTokens: 100, outputTokens: 300, model: "test" };
          },
        },
      });
      const summary = await pipeline.run("run-conf-none");
      const result = summary.results[0];
      assert.equal(summary.reviewed, 1);
      assert.equal(result.pass1ConfidenceStats, undefined, "Should not have stats when no findings have confidence");
    });

    it("mixed findings: stats computed from available confidence values only", async () => {
      let callCount = 0;
      const mixedFindings = [
        "<!-- bridge-findings-start -->",
        "```json",
        JSON.stringify({
          schema_version: 1,
          findings: [
            { id: "F001", title: "Issue", severity: "HIGH", category: "security", file: "f:1", description: "d", suggestion: "s", confidence: 0.9 },
            { id: "F002", title: "Good", severity: "PRAISE", category: "quality", file: "f:2", description: "d", suggestion: "s" },
            { id: "F003", title: "Maybe", severity: "LOW", category: "style", file: "f:3", description: "d", suggestion: "s", confidence: 0.5 },
          ],
        }),
        "```",
        "<!-- bridge-findings-end -->",
      ].join("\n");

      const pass2 = makePass2WithConfidence([
        { id: "F001", title: "Issue", severity: "HIGH", category: "security", file: "f:1", description: "d", suggestion: "s", confidence: 0.9 },
        { id: "F002", title: "Good", severity: "PRAISE", category: "quality", file: "f:2", description: "d", suggestion: "s" },
        { id: "F003", title: "Maybe", severity: "LOW", category: "style", file: "f:3", description: "d", suggestion: "s", confidence: 0.5 },
      ]);

      const pipeline = buildPipeline({
        config: { reviewMode: "two-pass" },
        llm: {
          generateReview: async () => {
            callCount++;
            if (callCount === 1) {
              return { content: mixedFindings, inputTokens: 500, outputTokens: 200, model: "test" };
            }
            return { content: pass2, inputTokens: 100, outputTokens: 300, model: "test" };
          },
        },
      });
      const summary = await pipeline.run("run-conf-mixed");
      const result = summary.results[0];
      assert.equal(summary.reviewed, 1);
      assert.ok(result.pass1ConfidenceStats);
      assert.equal(result.pass1ConfidenceStats!.count, 2, "Only 2 findings have confidence");
      assert.equal(result.pass1ConfidenceStats!.min, 0.5);
      assert.equal(result.pass1ConfidenceStats!.max, 0.9);
    });

    it("preservation guard passes when confidence differs between Pass 1 and Pass 2", async () => {
      let callCount = 0;
      // Pass 2 changes confidence values but preserves id/severity/category
      const pass2 = makePass2WithConfidence([
        { id: "F001", title: "Issue", severity: "HIGH", category: "security", file: "src/app.ts:1", description: "d", suggestion: "s", confidence: 0.95 },
        { id: "F002", title: "Good", severity: "PRAISE", category: "quality", file: "src/app.ts:5", description: "d", suggestion: "s", confidence: 0.6 },
        { id: "F003", title: "Maybe", severity: "LOW", category: "style", file: "src/app.ts:10", description: "d", suggestion: "s" },
      ]);

      let postedBody = "";
      const pipeline = buildPipeline({
        config: { reviewMode: "two-pass" },
        llm: {
          generateReview: async () => {
            callCount++;
            if (callCount === 1) {
              return { content: FINDINGS_WITH_CONFIDENCE, inputTokens: 500, outputTokens: 200, model: "test" };
            }
            return { content: pass2, inputTokens: 100, outputTokens: 300, model: "test" };
          },
        },
        poster: {
          postReview: async (input) => { postedBody = input.body; return true; },
        },
      });
      const summary = await pipeline.run("run-conf-preserve");
      assert.equal(summary.reviewed, 1);
      assert.ok(!postedBody.includes("Enrichment unavailable"), "Should NOT fall back — confidence is not a preserved attribute");
    });
  });

  describe("persona provenance (Sprint 67)", () => {
    it("parses persona with valid frontmatter", () => {
      const metadata = ReviewPipeline.parsePersonaMetadata(
        "<!-- persona-version: 1.0.0 | agent: bridgebuilder -->\n# Bridgebuilder\nContent here.",
      );
      assert.equal(metadata.id, "bridgebuilder");
      assert.equal(metadata.version, "1.0.0");
      assert.ok(metadata.hash.length === 64, "Should be a SHA-256 hex digest");
    });

    it("defaults to unknown/0.0.0 when no frontmatter", () => {
      const metadata = ReviewPipeline.parsePersonaMetadata(
        "# Just a persona\nNo frontmatter here.",
      );
      assert.equal(metadata.id, "unknown");
      assert.equal(metadata.version, "0.0.0");
      assert.ok(metadata.hash.length === 64, "Should still compute hash");
    });

    it("two-pass ReviewResult includes personaId and personaHash", async () => {
      let callCount = 0;
      const pass1 = [
        "<!-- bridge-findings-start -->",
        "```json",
        JSON.stringify({
          schema_version: 1,
          findings: [
            { id: "F001", title: "Issue", severity: "HIGH", category: "security", file: "f:1", description: "d", suggestion: "s" },
          ],
        }),
        "```",
        "<!-- bridge-findings-end -->",
      ].join("\n");

      const pass2 = [
        "## Summary", "", "Review.", "",
        "## Findings", "",
        "<!-- bridge-findings-start -->",
        "```json",
        JSON.stringify({
          schema_version: 1,
          findings: [
            { id: "F001", title: "Issue", severity: "HIGH", category: "security", file: "f:1", description: "d", suggestion: "s", faang_parallel: "Google" },
          ],
        }),
        "```",
        "<!-- bridge-findings-end -->",
        "", "## Callouts", "", "- Good.",
      ].join("\n");

      const pipeline = buildPipeline({
        config: { reviewMode: "two-pass" },
        llm: {
          generateReview: async () => {
            callCount++;
            if (callCount === 1) {
              return { content: pass1, inputTokens: 500, outputTokens: 200, model: "test" };
            }
            return { content: pass2, inputTokens: 100, outputTokens: 300, model: "test" };
          },
        },
      });
      const summary = await pipeline.run("run-persona");
      const result = summary.results[0];
      assert.equal(summary.reviewed, 1);
      // The default persona is "You are a code reviewer." — no frontmatter
      assert.equal(result.personaId, "unknown");
      assert.ok(result.personaHash, "Should have personaHash");
      assert.ok(result.personaHash!.length === 64, "Hash should be SHA-256");
    });

    it("single-pass ReviewResult does NOT include personaId", async () => {
      const pipeline = buildPipeline({
        config: { reviewMode: "single-pass" },
      });
      const summary = await pipeline.run("run-sp-persona");
      const result = summary.results[0];
      assert.equal(summary.reviewed, 1);
      assert.equal(result.personaId, undefined, "Single-pass should not include personaId");
      assert.equal(result.personaHash, undefined, "Single-pass should not include personaHash");
    });
  });

  describe("ecosystem context (Sprint 68)", () => {
    it("loadEcosystemContext returns undefined for missing file", () => {
      const result = ReviewPipeline.loadEcosystemContext(
        "/nonexistent/path/ecosystem.json",
        mockLogger(),
      );
      assert.equal(result, undefined);
    });

    it("loadEcosystemContext returns undefined for undefined path", () => {
      const result = ReviewPipeline.loadEcosystemContext(undefined, mockLogger());
      assert.equal(result, undefined);
    });

    it("loadEcosystemContext validates structure and filters invalid patterns", () => {
      const dir = mkdtempSync(join(tmpdir(), "bb-eco-"));
      const filePath = join(dir, "ecosystem.json");

      writeFileSync(filePath, JSON.stringify({
        patterns: [
          { repo: "valid/repo", pattern: "Pattern A", connection: "Connection A" },
          { repo: "valid/repo2", pr: 42, pattern: "Pattern B", connection: "Connection B" },
          { missing: "fields" },
          { repo: "no-connection", pattern: "P" },
        ],
        lastUpdated: "2026-02-25T12:00:00Z",
      }));

      try {
        const result = ReviewPipeline.loadEcosystemContext(filePath, mockLogger());
        assert.ok(result, "Should return context for valid file");
        assert.equal(result!.patterns.length, 2, "Should filter to only valid patterns");
        assert.equal(result!.patterns[0].repo, "valid/repo");
        assert.equal(result!.patterns[1].pr, 42);
        assert.equal(result!.lastUpdated, "2026-02-25T12:00:00Z");
      } finally {
        unlinkSync(filePath);
      }
    });

    it("loadEcosystemContext returns undefined for invalid JSON", () => {
      const dir = mkdtempSync(join(tmpdir(), "bb-eco-"));
      const filePath = join(dir, "bad.json");

      writeFileSync(filePath, "not valid json {{{");

      try {
        const result = ReviewPipeline.loadEcosystemContext(filePath, mockLogger());
        assert.equal(result, undefined, "Should return undefined for invalid JSON");
      } finally {
        unlinkSync(filePath);
      }
    });

    it("loadEcosystemContext warns on missing lastUpdated", () => {
      const dir = mkdtempSync(join(tmpdir(), "bb-eco-"));
      const filePath = join(dir, "no-date.json");

      writeFileSync(filePath, JSON.stringify({
        patterns: [{ repo: "r", pattern: "p", connection: "c" }],
      }));

      const warns: string[] = [];
      const logger: ILogger = {
        ...mockLogger(),
        warn: (msg: string) => { warns.push(msg); },
      };

      try {
        const result = ReviewPipeline.loadEcosystemContext(filePath, logger);
        assert.equal(result, undefined, "Should return undefined when lastUpdated missing");
        assert.ok(warns.some((w) => w.includes("invalid structure")), "Should warn about invalid structure");
      } finally {
        unlinkSync(filePath);
      }
    });
  });

  describe("fixture-based tests", () => {
    const __filename = fileURLToPath(import.meta.url);
    const __dirname = dirname(__filename);
    const fixturesDir = join(__dirname, "fixtures");

    it("extractFindingsJSON parses pass1-valid-findings.json fixture", async () => {
      const fixtureContent = readFileSync(join(fixturesDir, "pass1-valid-findings.json"), "utf-8");
      // Use a two-pass pipeline to exercise extractFindingsJSON via the public flow
      let callCount = 0;
      const pipeline = buildPipeline({
        config: { reviewMode: "two-pass" },
        llm: {
          generateReview: async () => {
            callCount++;
            if (callCount === 1) {
              return { content: fixtureContent, inputTokens: 500, outputTokens: 200, model: "test" };
            }
            // Return valid enriched version of the fixture
            const enriched = [
              "## Summary", "", "Enriched review.", "",
              "## Findings", "", fixtureContent, "",
              "## Callouts", "", "- Good.",
            ].join("\n");
            return { content: enriched, inputTokens: 100, outputTokens: 300, model: "test" };
          },
        },
      });
      const summary = await pipeline.run("run-fixture-p1");
      // Should successfully extract and process — not skip
      assert.equal(summary.reviewed, 1);
    });

    it("extractFindingsJSON returns null for pass1-malformed.txt fixture", async () => {
      const fixtureContent = readFileSync(join(fixturesDir, "pass1-malformed.txt"), "utf-8");
      const pipeline = buildPipeline({
        config: { reviewMode: "two-pass" },
        llm: {
          generateReview: async () => ({
            content: fixtureContent,
            inputTokens: 100,
            outputTokens: 50,
            model: "test",
          }),
        },
      });
      const summary = await pipeline.run("run-fixture-malformed");
      // Malformed content should result in skip (no valid findings and no valid response)
      assert.equal(summary.skipped, 1);
    });

    it("validateFindingPreservation rejects pass2-findings-added.md fixture", async () => {
      const pass1Content = readFileSync(join(fixturesDir, "pass1-valid-findings.json"), "utf-8");
      const pass2Content = readFileSync(join(fixturesDir, "pass2-findings-added.md"), "utf-8");
      let callCount = 0;
      let postedBody = "";
      const pipeline = buildPipeline({
        config: { reviewMode: "two-pass" },
        llm: {
          generateReview: async () => {
            callCount++;
            if (callCount === 1) {
              return { content: pass1Content, inputTokens: 500, outputTokens: 200, model: "test" };
            }
            return { content: pass2Content, inputTokens: 100, outputTokens: 300, model: "test" };
          },
        },
        poster: {
          postReview: async (input) => { postedBody = input.body; return true; },
        },
      });
      const summary = await pipeline.run("run-fixture-added");
      assert.equal(summary.reviewed, 1);
      assert.ok(postedBody.includes("Enrichment unavailable"), "Should fall back when Pass 2 adds findings");
    });

    it("validateFindingPreservation rejects pass2-severity-changed.md fixture", async () => {
      const pass1Content = readFileSync(join(fixturesDir, "pass1-valid-findings.json"), "utf-8");
      const pass2Content = readFileSync(join(fixturesDir, "pass2-severity-changed.md"), "utf-8");
      let callCount = 0;
      let postedBody = "";
      const pipeline = buildPipeline({
        config: { reviewMode: "two-pass" },
        llm: {
          generateReview: async () => {
            callCount++;
            if (callCount === 1) {
              return { content: pass1Content, inputTokens: 500, outputTokens: 200, model: "test" };
            }
            return { content: pass2Content, inputTokens: 100, outputTokens: 300, model: "test" };
          },
        },
        poster: {
          postReview: async (input) => { postedBody = input.body; return true; },
        },
      });
      const summary = await pipeline.run("run-fixture-severity");
      assert.equal(summary.reviewed, 1);
      assert.ok(postedBody.includes("Enrichment unavailable"), "Should fall back when Pass 2 changes severity");
    });

    it("validateFindingPreservation rejects pass2-category-changed.md fixture", async () => {
      const pass1Content = readFileSync(join(fixturesDir, "pass1-valid-findings.json"), "utf-8");
      const pass2Content = readFileSync(join(fixturesDir, "pass2-category-changed.md"), "utf-8");
      let callCount = 0;
      let postedBody = "";
      const pipeline = buildPipeline({
        config: { reviewMode: "two-pass" },
        llm: {
          generateReview: async () => {
            callCount++;
            if (callCount === 1) {
              return { content: pass1Content, inputTokens: 500, outputTokens: 200, model: "test" };
            }
            return { content: pass2Content, inputTokens: 100, outputTokens: 300, model: "test" };
          },
        },
        poster: {
          postReview: async (input) => { postedBody = input.body; return true; },
        },
      });
      const summary = await pipeline.run("run-fixture-category");
      assert.equal(summary.reviewed, 1);
      assert.ok(postedBody.includes("Enrichment unavailable"), "Should fall back when Pass 2 changes category");
    });
  });
});
