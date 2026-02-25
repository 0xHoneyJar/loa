import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, existsSync, readFileSync, writeFileSync, mkdirSync, chmodSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { rmSync } from "node:fs";
import { Pass1Cache, computeCacheKey, type CacheEntry } from "../core/cache.js";
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
import { createHash } from "node:crypto";

// ─── Test Helpers ─────────────────────────────────────────────

function realHasher(): IHasher {
  return {
    sha256: async (input: string) =>
      createHash("sha256").update(input).digest("hex"),
  };
}

function makeCacheEntry(overrides?: Partial<CacheEntry>): CacheEntry {
  return {
    findings: {
      raw: JSON.stringify({
        schema_version: 1,
        findings: [
          { id: "F001", title: "Issue", severity: "HIGH", category: "security", file: "f:1", description: "d", suggestion: "s" },
        ],
      }),
      parsed: {
        schema_version: 1,
        findings: [
          { id: "F001", title: "Issue", severity: "HIGH", category: "security", file: "f:1", description: "d", suggestion: "s" },
        ],
      },
    },
    tokens: { input: 500, output: 200, duration: 1000 },
    timestamp: "2026-02-25T12:00:00Z",
    hitCount: 0,
    ...overrides,
  };
}

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
    reviewMode: "two-pass" as const,
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

function mockSanitizer(): IOutputSanitizer {
  return {
    sanitize: (content: string) => ({
      safe: true,
      sanitizedContent: content,
      redactedPatterns: [],
    }),
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
  hasher?: IHasher;
}) {
  const config = mockConfig(opts?.config);
  const git = mockGit(opts?.git);
  const hasher = opts?.hasher ?? mockHasher();
  const template = new PRReviewTemplate(git, hasher, config);
  const context = new BridgebuilderContext(mockStore(opts?.store));

  return new ReviewPipeline(
    template,
    context,
    git,
    mockPoster(opts?.poster),
    mockLLM(opts?.llm),
    opts?.sanitizer ? mockSanitizer() : mockSanitizer(),
    opts?.logger ?? mockLogger(),
    "You are a code reviewer.",
    config,
    opts?.now ?? Date.now,
    hasher,
  );
}

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


// ─── Tests ─────────────────────────────────────────────

describe("Pass1Cache", () => {
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = mkdtempSync(join(tmpdir(), "bb-cache-"));
  });

  afterEach(() => {
    try {
      rmSync(tmpDir, { recursive: true, force: true });
    } catch {
      // cleanup best-effort
    }
  });

  describe("core operations", () => {
    it("Test 1: get() returns null on cache miss", async () => {
      const cache = new Pass1Cache(join(tmpDir, "cache"));
      const result = await cache.get("nonexistent-key");
      assert.equal(result, null);
    });

    it("Test 2: set() then get() returns the stored entry", async () => {
      const cacheDir = join(tmpDir, "cache");
      const cache = new Pass1Cache(cacheDir);
      const entry = makeCacheEntry();

      await cache.set("test-key", entry);
      const result = await cache.get("test-key");

      assert.ok(result, "Should return cached entry");
      assert.equal(result!.findings.raw, entry.findings.raw);
      assert.equal(result!.tokens.input, 500);
      assert.equal(result!.tokens.output, 200);
      assert.equal(result!.timestamp, "2026-02-25T12:00:00Z");
      assert.equal(result!.hitCount, 1, "hitCount should increment on read");
    });

    it("Test 11: clear() removes all cache entries", async () => {
      const cacheDir = join(tmpDir, "cache");
      const cache = new Pass1Cache(cacheDir);

      await cache.set("key-a", makeCacheEntry());
      await cache.set("key-b", makeCacheEntry());

      // Verify entries exist
      assert.ok(await cache.get("key-a"));
      assert.ok(await cache.get("key-b"));

      await cache.clear();

      // After clear, entries should be gone
      assert.equal(await cache.get("key-a"), null);
      assert.equal(await cache.get("key-b"), null);
    });
  });

  describe("cache key computation", () => {
    it("Test 3: different headSha → different cache key → miss", async () => {
      const hasher = realHasher();
      const key1 = await computeCacheKey(hasher, "sha-aaa", 0, "prompthash1");
      const key2 = await computeCacheKey(hasher, "sha-bbb", 0, "prompthash1");
      assert.notEqual(key1, key2, "Different headSha should produce different keys");
    });

    it("Test 4: different truncation level → different cache key → miss", async () => {
      const hasher = realHasher();
      const key1 = await computeCacheKey(hasher, "sha-aaa", 0, "prompthash1");
      const key2 = await computeCacheKey(hasher, "sha-aaa", 1, "prompthash1");
      assert.notEqual(key1, key2, "Different truncation level should produce different keys");
    });

    it("Test 5: different prompt hash → different cache key → miss", async () => {
      const hasher = realHasher();
      const key1 = await computeCacheKey(hasher, "sha-aaa", 0, "prompthash1");
      const key2 = await computeCacheKey(hasher, "sha-aaa", 0, "prompthash2");
      assert.notEqual(key1, key2, "Different prompt hash should produce different keys");
    });

    it("Test 6: same inputs → same cache key → hit", async () => {
      const hasher = realHasher();
      const key1 = await computeCacheKey(hasher, "sha-aaa", 0, "prompthash1");
      const key2 = await computeCacheKey(hasher, "sha-aaa", 0, "prompthash1");
      assert.equal(key1, key2, "Same inputs should produce same key");
    });
  });

  describe("graceful degradation", () => {
    it("Test 8: I/O error on get() → returns null gracefully", async () => {
      // Point to a non-existent deeply nested path
      const cache = new Pass1Cache("/nonexistent/deep/path/cache");
      const result = await cache.get("some-key");
      assert.equal(result, null, "Should return null on I/O error");
    });

    it("set() to unwritable directory → swallows error", async () => {
      // Create a read-only directory, then try to write inside it
      const readonlyDir = join(tmpDir, "readonly");
      mkdirSync(readonlyDir, { mode: 0o555 });
      const cache = new Pass1Cache(join(readonlyDir, "nested", "cache"));
      // Should not throw
      await cache.set("some-key", makeCacheEntry());
      // And get should return null
      const result = await cache.get("some-key");
      assert.equal(result, null);
      // Clean up — restore permissions so rmSync works
      chmodSync(readonlyDir, 0o755);
    });
  });

  describe("lazy directory creation", () => {
    it("creates cache directory on first set() (AC-9)", async () => {
      const cacheDir = join(tmpDir, "lazy-cache");
      assert.ok(!existsSync(cacheDir), "Cache dir should not exist initially");

      const cache = new Pass1Cache(cacheDir);
      await cache.set("first-key", makeCacheEntry());

      assert.ok(existsSync(cacheDir), "Cache dir should be created after first set()");
    });
  });
});

describe("Pass1Cache integration with ReviewPipeline", () => {
  // Clean up the shared cache directory between tests to prevent cross-test contamination
  beforeEach(() => {
    try {
      rmSync(".run/bridge-cache", { recursive: true, force: true });
    } catch {
      // ignore if doesn't exist
    }
  });

  afterEach(() => {
    try {
      rmSync(".run/bridge-cache", { recursive: true, force: true });
    } catch {
      // ignore
    }
  });

  it("Test 7: cache disabled in config → LLM always called (no cache check)", async () => {
    let llmCallCount = 0;
    const pipeline = buildPipeline({
      config: { reviewMode: "two-pass" }, // no pass1Cache config → disabled by default
      llm: {
        generateReview: async () => {
          llmCallCount++;
          if (llmCallCount === 1) {
            return { content: VALID_PASS1_CONTENT, inputTokens: 500, outputTokens: 200, model: "test" };
          }
          return { content: VALID_PASS2_CONTENT, inputTokens: 100, outputTokens: 300, model: "test" };
        },
      },
    });

    const summary = await pipeline.run("run-no-cache");
    assert.equal(summary.reviewed, 1);
    assert.equal(llmCallCount, 2, "LLM should be called twice (no caching)");
    // When cache is disabled, pass1CacheHit is not set (remains false since it's the two-pass default)
    assert.equal(summary.results[0].pass1CacheHit, false, "pass1CacheHit should be false when cache disabled");
  });

  it("Test 9: two-pass with cache hit → Pass 1 LLM NOT called, Pass 2 receives cached findings", async () => {
    // First run: populate cache (cache miss)
    let llmCallCount = 0;
    const pipeline1 = buildPipeline({
      config: { reviewMode: "two-pass", pass1Cache: { enabled: true } },
      hasher: realHasher(),
      llm: {
        generateReview: async () => {
          llmCallCount++;
          if (llmCallCount === 1) {
            return { content: VALID_PASS1_CONTENT, inputTokens: 500, outputTokens: 200, model: "test" };
          }
          return { content: VALID_PASS2_CONTENT, inputTokens: 100, outputTokens: 300, model: "test" };
        },
      },
    });

    const summary1 = await pipeline1.run("run-cache-miss");
    assert.equal(summary1.reviewed, 1);
    assert.equal(llmCallCount, 2, "First run: 2 LLM calls (cache miss)");
    assert.equal(summary1.results[0].pass1CacheHit, false, "First run: cache miss");

    // Second run: same headSha → cache hit, only 1 LLM call (Pass 2)
    llmCallCount = 0;
    const pipeline2 = buildPipeline({
      config: { reviewMode: "two-pass", pass1Cache: { enabled: true } },
      hasher: realHasher(),
      llm: {
        generateReview: async () => {
          llmCallCount++;
          // This should only be called once — for Pass 2
          return { content: VALID_PASS2_CONTENT, inputTokens: 100, outputTokens: 300, model: "test" };
        },
      },
    });

    const summary2 = await pipeline2.run("run-cache-hit");
    assert.equal(summary2.reviewed, 1);
    assert.equal(llmCallCount, 1, "Second run: only 1 LLM call (Pass 2 — Pass 1 from cache)");
    assert.equal(summary2.results[0].pass1CacheHit, true, "Second run: cache hit");
  });

  it("Test 10: two-pass with cache miss → Pass 1 LLM called, result cached", async () => {
    let llmCallCount = 0;
    const pipeline = buildPipeline({
      config: { reviewMode: "two-pass", pass1Cache: { enabled: true } },
      hasher: realHasher(),
      llm: {
        generateReview: async () => {
          llmCallCount++;
          if (llmCallCount === 1) {
            return { content: VALID_PASS1_CONTENT, inputTokens: 500, outputTokens: 200, model: "test" };
          }
          return { content: VALID_PASS2_CONTENT, inputTokens: 100, outputTokens: 300, model: "test" };
        },
      },
    });

    const summary = await pipeline.run("run-cache-store");
    assert.equal(summary.reviewed, 1);
    assert.equal(llmCallCount, 2, "Should make 2 LLM calls on cache miss");
    assert.equal(summary.results[0].pass1CacheHit, false, "Should report cache miss");

    // Verify the cache file was written
    const cacheDir = ".run/bridge-cache";
    assert.ok(existsSync(cacheDir), "Cache directory should exist after cache miss + store");

    // Clean up
    rmSync(cacheDir, { recursive: true, force: true });
  });

  it("cache hit provides correct findings to Pass 2 enrichment", async () => {
    // First run: populate cache
    let llmCallCount = 0;
    const pipeline1 = buildPipeline({
      config: { reviewMode: "two-pass", pass1Cache: { enabled: true } },
      hasher: realHasher(),
      llm: {
        generateReview: async () => {
          llmCallCount++;
          if (llmCallCount === 1) {
            return { content: VALID_PASS1_CONTENT, inputTokens: 500, outputTokens: 200, model: "test" };
          }
          return { content: VALID_PASS2_CONTENT, inputTokens: 100, outputTokens: 300, model: "test" };
        },
      },
    });
    await pipeline1.run("run-pop-cache");

    // Second run: cache hit path
    llmCallCount = 0;
    let pass2UserPrompt = "";
    const pipeline2 = buildPipeline({
      config: { reviewMode: "two-pass", pass1Cache: { enabled: true } },
      hasher: realHasher(),
      llm: {
        generateReview: async (req) => {
          llmCallCount++;
          pass2UserPrompt = req.userPrompt;
          return { content: VALID_PASS2_CONTENT, inputTokens: 100, outputTokens: 300, model: "test" };
        },
      },
    });
    const summary = await pipeline2.run("run-verify-findings");
    assert.equal(summary.reviewed, 1);
    assert.equal(llmCallCount, 1, "Only Pass 2 LLM call on cache hit");
    // The Pass 2 user prompt should contain the findings JSON from cache
    assert.ok(pass2UserPrompt.includes("F001"), "Pass 2 should receive F001 from cached findings");
    assert.ok(pass2UserPrompt.includes("F002"), "Pass 2 should receive F002 from cached findings");
  });
});
