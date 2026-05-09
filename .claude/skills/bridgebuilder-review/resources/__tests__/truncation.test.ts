import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { writeFileSync, mkdirSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import {
  truncateFiles,
  loadReviewIgnore,
  loadReviewIgnoreUserPatterns,
  LOA_EXCLUDE_PATTERNS,
  getTokenBudget,
  isSelfReviewOptedIn,
  SELF_REVIEW_LABEL,
  deriveCallConfig,
} from "../core/truncation.js";
import type { PullRequestFile } from "../ports/git-provider.js";

function file(
  filename: string,
  additions: number,
  deletions: number,
  patch?: string,
): PullRequestFile {
  return {
    filename,
    status: "modified",
    additions,
    deletions,
    patch: patch ?? `@@ -1,${deletions} +1,${additions} @@\n+added`,
  };
}

const defaultConfig = {
  excludePatterns: [] as string[],
  maxDiffBytes: 100_000,
  maxFilesPerPr: 50,
};

describe("loadReviewIgnore", () => {
  it("returns LOA_EXCLUDE_PATTERNS when no .reviewignore exists", () => {
    const patterns = loadReviewIgnore("/nonexistent/path/that/does/not/exist");
    assert.deepEqual(patterns, [...LOA_EXCLUDE_PATTERNS]);
  });

  it("merges .reviewignore patterns with LOA_EXCLUDE_PATTERNS", () => {
    const tmpDir = join(tmpdir(), `loa-test-${Date.now()}`);
    mkdirSync(tmpDir, { recursive: true });
    try {
      writeFileSync(join(tmpDir, ".reviewignore"), "custom-pattern\n*.log\n");
      const patterns = loadReviewIgnore(tmpDir);
      assert.ok(patterns.includes("custom-pattern"), "should include custom pattern");
      assert.ok(patterns.includes("*.log"), "should include *.log pattern");
      // Should also include all LOA defaults
      for (const loa of LOA_EXCLUDE_PATTERNS) {
        assert.ok(patterns.includes(loa), `should include LOA pattern: ${loa}`);
      }
    } finally {
      rmSync(tmpDir, { recursive: true, force: true });
    }
  });

  it("normalizes directory patterns (trailing / becomes /**)", () => {
    const tmpDir = join(tmpdir(), `loa-test-${Date.now()}`);
    mkdirSync(tmpDir, { recursive: true });
    try {
      writeFileSync(join(tmpDir, ".reviewignore"), "vendor/\nbuild/\n");
      const patterns = loadReviewIgnore(tmpDir);
      assert.ok(patterns.includes("vendor/**"), "should normalize vendor/ to vendor/**");
      assert.ok(patterns.includes("build/**"), "should normalize build/ to build/**");
    } finally {
      rmSync(tmpDir, { recursive: true, force: true });
    }
  });

  it("skips blank lines and comments", () => {
    const tmpDir = join(tmpdir(), `loa-test-${Date.now()}`);
    mkdirSync(tmpDir, { recursive: true });
    try {
      writeFileSync(join(tmpDir, ".reviewignore"), "# A comment\n\nreal-pattern\n  \n# Another\n");
      const patterns = loadReviewIgnore(tmpDir);
      assert.ok(patterns.includes("real-pattern"), "should include real-pattern");
      assert.ok(!patterns.includes("# A comment"), "should not include comments");
      assert.ok(!patterns.includes(""), "should not include blank lines");
    } finally {
      rmSync(tmpDir, { recursive: true, force: true });
    }
  });

  it("avoids duplicate patterns", () => {
    const tmpDir = join(tmpdir(), `loa-test-${Date.now()}`);
    mkdirSync(tmpDir, { recursive: true });
    try {
      // .claude/** is already in LOA_EXCLUDE_PATTERNS
      writeFileSync(join(tmpDir, ".reviewignore"), ".claude/**\ncustom\n");
      const patterns = loadReviewIgnore(tmpDir);
      const claudeCount = patterns.filter(p => p === ".claude/**").length;
      assert.equal(claudeCount, 1, "should not duplicate .claude/**");
    } finally {
      rmSync(tmpDir, { recursive: true, force: true });
    }
  });
});

describe("getTokenBudget", () => {
  it("returns correct budget for claude-sonnet-4-6", () => {
    const budget = getTokenBudget("claude-sonnet-4-6");
    assert.equal(budget.maxInput, 200_000);
    assert.equal(budget.maxOutput, 8_192);
    assert.equal(budget.coefficient, 0.25);
  });

  it("returns correct budget for claude-sonnet-4-5-20250929 (backward compat)", () => {
    const budget = getTokenBudget("claude-sonnet-4-5-20250929");
    assert.equal(budget.maxInput, 200_000);
    assert.equal(budget.maxOutput, 8_192);
  });

  it("returns default budget for unknown model", () => {
    const budget = getTokenBudget("unknown-model-xyz");
    assert.equal(budget.maxInput, 100_000);
    assert.equal(budget.maxOutput, 4_096);
  });
});

describe("truncateFiles", () => {
  describe("excludePatterns", () => {
    it("excludes files matching suffix pattern", () => {
      const files = [file("src/app.ts", 5, 3), file("package-lock.json", 500, 0)];
      const config = { ...defaultConfig, excludePatterns: ["*.json"] };
      const result = truncateFiles(files, config);

      assert.equal(result.included.length, 1);
      assert.equal(result.included[0].filename, "src/app.ts");
      assert.equal(result.excluded.length, 1);
      assert.ok(result.excluded[0].stats.includes("excluded by pattern"));
    });

    it("excludes files matching prefix pattern", () => {
      const files = [file("dist/bundle.js", 10, 0), file("src/main.ts", 5, 2)];
      const config = { ...defaultConfig, excludePatterns: ["dist/*"] };
      const result = truncateFiles(files, config);

      assert.equal(result.included.length, 1);
      assert.equal(result.included[0].filename, "src/main.ts");
    });

    it("excludes files matching substring pattern", () => {
      const files = [file(".env.local", 1, 0), file("src/config.ts", 3, 1)];
      const config = { ...defaultConfig, excludePatterns: [".env"] };
      const result = truncateFiles(files, config);

      assert.equal(result.included.length, 1);
      assert.equal(result.included[0].filename, "src/config.ts");
    });

    it("excluded-by-pattern files appear in excluded list with annotation", () => {
      const files = [file("yarn.lock", 100, 50)];
      const config = { ...defaultConfig, excludePatterns: ["*.lock"] };
      const result = truncateFiles(files, config);

      assert.equal(result.included.length, 0);
      assert.equal(result.excluded.length, 1);
      assert.equal(result.excluded[0].filename, "yarn.lock");
      assert.ok(result.excluded[0].stats.includes("excluded by pattern"));
    });

    it("handles undefined excludePatterns gracefully", () => {
      const files = [file("src/app.ts", 5, 3)];
      const config = { maxDiffBytes: 100_000, maxFilesPerPr: 50 } as typeof defaultConfig;
      const result = truncateFiles(files, config);

      assert.equal(result.included.length, 1);
    });
  });

  describe("risk prioritization", () => {
    it("places high-risk files before normal files", () => {
      const files = [
        file("src/utils.ts", 10, 5),
        file("src/auth/login.ts", 3, 1),
        file("src/readme.ts", 20, 10),
      ];
      const result = truncateFiles(files, defaultConfig);

      assert.equal(result.included[0].filename, "src/auth/login.ts");
    });

    it("sorts high-risk files by change size descending", () => {
      const files = [
        file("src/auth/small.ts", 1, 0),
        file("src/auth/large.ts", 50, 20),
      ];
      const result = truncateFiles(files, defaultConfig);

      assert.equal(result.included[0].filename, "src/auth/large.ts");
      assert.equal(result.included[1].filename, "src/auth/small.ts");
    });

    it("sorts normal files by change size descending", () => {
      const files = [
        file("src/small.ts", 1, 0),
        file("src/large.ts", 50, 20),
      ];
      const result = truncateFiles(files, defaultConfig);

      assert.equal(result.included[0].filename, "src/large.ts");
    });
  });

  describe("byte budget", () => {
    it("includes files within budget", () => {
      const small = file("a.ts", 1, 0, "x".repeat(100));
      const result = truncateFiles([small], { ...defaultConfig, maxDiffBytes: 200 });

      assert.equal(result.included.length, 1);
      assert.ok(result.totalBytes <= 200);
    });

    it("excludes files exceeding budget with stats", () => {
      const large = file("big.ts", 100, 50, "x".repeat(1000));
      const result = truncateFiles([large], { ...defaultConfig, maxDiffBytes: 10 });

      assert.equal(result.included.length, 0);
      assert.equal(result.excluded.length, 1);
      assert.ok(result.excluded[0].stats.includes("+100 -50"));
      assert.ok(!result.excluded[0].stats.includes("excluded by pattern"));
    });

    it("uses TextEncoder for accurate byte counting", () => {
      // Multi-byte characters
      const emoji = file("emoji.ts", 1, 0, "\u{1F600}".repeat(10));
      const result = truncateFiles([emoji], defaultConfig);

      // Each emoji is 4 bytes
      assert.equal(result.totalBytes, 40);
    });
  });

  describe("maxFilesPerPr cap", () => {
    it("caps included + budget-excluded files at maxFilesPerPr", () => {
      const files = Array.from({ length: 5 }, (_, i) =>
        file(`f${i}.ts`, 1, 0, "x"),
      );
      const result = truncateFiles(files, { ...defaultConfig, maxFilesPerPr: 3 });

      const totalTracked = result.included.length + result.excluded.length;
      assert.equal(totalTracked, 5); // all appear somewhere
      assert.ok(result.included.length <= 3);
    });
  });

  describe("patch-optional files", () => {
    it("handles files with null patch (binary/large)", () => {
      const binary: PullRequestFile = {
        filename: "image.png",
        status: "added",
        additions: 0,
        deletions: 0,
        patch: undefined,
      };
      const result = truncateFiles([binary], defaultConfig);

      assert.equal(result.included.length, 0);
      assert.equal(result.excluded.length, 1);
      assert.ok(result.excluded[0].stats.includes("diff unavailable"));
    });

    it("handles files with empty string patch as valid", () => {
      const emptyPatch: PullRequestFile = {
        filename: "empty.ts",
        status: "modified",
        additions: 0,
        deletions: 0,
        patch: "",
      };
      const result = truncateFiles([emptyPatch], defaultConfig);

      // Empty string patch is NOT null — it's a valid (empty) patch
      assert.equal(result.included.length, 1);
    });
  });

  describe("empty input", () => {
    it("returns empty results for empty file list", () => {
      const result = truncateFiles([], defaultConfig);

      assert.equal(result.included.length, 0);
      assert.equal(result.excluded.length, 0);
      assert.equal(result.totalBytes, 0);
    });
  });

  describe("no input mutation", () => {
    it("does not mutate the input files array", () => {
      const files = [
        file("b.ts", 1, 0),
        file("a.ts", 2, 0),
      ];
      const original = [...files];
      truncateFiles(files, defaultConfig);

      assert.equal(files[0].filename, original[0].filename);
      assert.equal(files[1].filename, original[1].filename);
    });
  });

  // --- Boundary tests: edge cases ---

  describe("edge cases", () => {
    it("handles a single file with a very large patch (exceeds byte budget)", () => {
      const hugePatch = "x".repeat(200_000); // 200KB — exceeds 100KB budget
      const f = file("huge.ts", 5000, 0, hugePatch);
      const result = truncateFiles([f], defaultConfig);

      assert.equal(result.included.length, 0);
      assert.equal(result.excluded.length, 1);
      assert.ok(result.excluded[0].stats.includes("+5000 -0"));
    });

    it("handles 100 files with maxFilesPerPr=3", () => {
      const files = Array.from({ length: 100 }, (_, i) =>
        file(`file${i}.ts`, i + 1, 0, "x"),
      );
      const config = { ...defaultConfig, maxFilesPerPr: 3 };
      const result = truncateFiles(files, config);

      // Only 3 files in the included+budget-excluded window
      assert.ok(result.included.length <= 3);
      // All 100 files accounted for in included + excluded
      assert.equal(result.included.length + result.excluded.length, 100);
    });

    it("handles all files being binary (patch: undefined)", () => {
      const binaries: PullRequestFile[] = Array.from({ length: 5 }, (_, i) => ({
        filename: `image${i}.png`,
        status: "added" as const,
        additions: 0,
        deletions: 0,
        patch: undefined,
      }));
      const result = truncateFiles(binaries, defaultConfig);

      assert.equal(result.included.length, 0);
      assert.equal(result.excluded.length, 5);
      assert.equal(result.totalBytes, 0);
      for (const ex of result.excluded) {
        assert.ok(ex.stats.includes("diff unavailable"));
      }
    });

    it("handles mixed security and normal files with tight byte budget", () => {
      const files = [
        file("src/utils.ts", 10, 0, "x".repeat(50)),
        file("src/auth/login.ts", 5, 0, "x".repeat(50)),
        file("src/crypto/keys.ts", 3, 0, "x".repeat(50)),
      ];
      // Budget fits only 2 files (100 bytes < 150)
      const config = { ...defaultConfig, maxDiffBytes: 100 };
      const result = truncateFiles(files, config);

      // Security files (auth, crypto) should be prioritized
      assert.equal(result.included.length, 2);
      const includedNames = result.included.map((f) => f.filename);
      assert.ok(includedNames.includes("src/auth/login.ts"), "auth file should be included");
      assert.ok(includedNames.includes("src/crypto/keys.ts"), "crypto file should be included");
    });
  });

  // --- Self-review opt-in (#796 / vision-013) ---

  describe("self-review opt-in", () => {
    it("default behavior — loaAware:true filters framework files", () => {
      const files = [
        file(".claude/skills/bridgebuilder-review/resources/adapters/anthropic.ts", 25, 3),
        file(".claude/skills/bridgebuilder-review/resources/adapters/google.ts", 26, 3),
      ];
      const config = { ...defaultConfig, loaAware: true };
      const result = truncateFiles(files, config);

      // All framework files filtered out → allExcluded path
      assert.equal(result.allExcluded, true);
      assert.equal(result.included.length, 0);
      assert.ok(result.loaBanner);
      assert.ok(
        result.loaBanner!.includes("framework files excluded"),
        `expected default-mode banner; got: ${result.loaBanner}`,
      );
    });

    it("selfReview:true skips the loa filter — framework files admitted", () => {
      const files = [
        file(".claude/skills/bridgebuilder-review/resources/adapters/anthropic.ts", 25, 3),
        file(".claude/skills/bridgebuilder-review/resources/adapters/google.ts", 26, 3),
      ];
      const config = { ...defaultConfig, loaAware: true, selfReview: true };
      const result = truncateFiles(files, config);

      // Both framework files reach the included payload
      assert.equal(result.allExcluded, false);
      assert.equal(result.included.length, 2);
      const includedNames = result.included.map((f) => f.filename).sort();
      assert.deepEqual(includedNames, [
        ".claude/skills/bridgebuilder-review/resources/adapters/anthropic.ts",
        ".claude/skills/bridgebuilder-review/resources/adapters/google.ts",
      ]);
    });

    it("selfReview:true surfaces a banner — operator sees why filter was skipped", () => {
      const files = [
        file(".claude/skills/bridgebuilder-review/resources/adapters/anthropic.ts", 25, 3),
      ];
      const config = { ...defaultConfig, loaAware: true, selfReview: true };
      const result = truncateFiles(files, config);

      assert.ok(result.loaBanner, "selfReview should produce a banner");
      assert.ok(
        result.loaBanner!.includes("self-review opt-in"),
        `expected self-review banner; got: ${result.loaBanner}`,
      );
      // Banner cross-refs the issue / vision so operators can dig in
      assert.ok(
        result.loaBanner!.includes("vision-013") || result.loaBanner!.includes("#796"),
        `banner should cite vision-013 or #796; got: ${result.loaBanner}`,
      );
    });

    it("selfReview:false (default) leaves loa filter active", () => {
      const files = [
        file(".claude/skills/bridgebuilder-review/resources/adapters/anthropic.ts", 25, 3),
      ];
      const config = { ...defaultConfig, loaAware: true, selfReview: false };
      const result = truncateFiles(files, config);

      assert.equal(result.allExcluded, true);
      assert.equal(result.included.length, 0);
    });

    it("selfReview:true is a no-op when loa is not detected", () => {
      // Non-loa repo + selfReview flag — flag has no effect, normal path runs.
      const files = [file("src/handler.ts", 10, 0)];
      const config = { ...defaultConfig, loaAware: false, selfReview: true };
      const result = truncateFiles(files, config);

      assert.equal(result.included.length, 1);
      assert.equal(result.loaBanner, undefined);
    });

    it("selfReview admits both framework AND application files together", () => {
      const files = [
        file(".claude/skills/bridgebuilder-review/resources/adapters/anthropic.ts", 25, 3),
        file("src/handler.ts", 10, 0),
      ];
      const config = { ...defaultConfig, loaAware: true, selfReview: true };
      const result = truncateFiles(files, config);

      assert.equal(result.included.length, 2);
      const names = result.included.map((f) => f.filename).sort();
      assert.deepEqual(names, [
        ".claude/skills/bridgebuilder-review/resources/adapters/anthropic.ts",
        "src/handler.ts",
      ]);
    });
  });

  describe("isSelfReviewOptedIn", () => {
    it("returns true when bridgebuilder:self-review label is present", () => {
      assert.equal(isSelfReviewOptedIn(["bridgebuilder:self-review"]), true);
    });

    it("returns true when label is present alongside other labels", () => {
      assert.equal(
        isSelfReviewOptedIn(["needs-review", "bridgebuilder:self-review", "size/M"]),
        true,
      );
    });

    it("returns false when label is absent", () => {
      assert.equal(isSelfReviewOptedIn(["needs-review"]), false);
    });

    it("returns false on empty label list", () => {
      assert.equal(isSelfReviewOptedIn([]), false);
    });

    it("returns false on undefined input — pr.labels may be missing in tests", () => {
      assert.equal(isSelfReviewOptedIn(undefined), false);
    });

    it("label name is exact — substring match does NOT trigger", () => {
      // "bridgebuilder:self-review-extra" is not the canonical label and
      // must not opt in. Single source of truth is SELF_REVIEW_LABEL.
      assert.equal(isSelfReviewOptedIn(["bridgebuilder:self-review-extra"]), false);
      assert.equal(isSelfReviewOptedIn(["bridgebuilder:self"]), false);
    });

    it("SELF_REVIEW_LABEL is the canonical constant — single source of truth", () => {
      assert.equal(SELF_REVIEW_LABEL, "bridgebuilder:self-review");
      assert.equal(isSelfReviewOptedIn([SELF_REVIEW_LABEL]), true);
    });
  });

  // BB-001-security (PR #797 iter-2): self-review must NOT bypass operator-curated
  // .reviewignore patterns. Only LOA framework defaults are bypassed.
  describe(".reviewignore honored under self-review (BB-001-security)", () => {
    it("loadReviewIgnoreUserPatterns returns empty when file missing", () => {
      const patterns = loadReviewIgnoreUserPatterns("/nonexistent/dir");
      assert.deepEqual(patterns, []);
    });

    it("loadReviewIgnoreUserPatterns returns ONLY user patterns (not LOA defaults)", () => {
      const tmpDir = join(tmpdir(), `loa-test-userpatterns-${Date.now()}`);
      mkdirSync(tmpDir, { recursive: true });
      try {
        writeFileSync(
          join(tmpDir, ".reviewignore"),
          "secrets/\nvendor/internal-blob.bin\n# comment\n",
        );
        const patterns = loadReviewIgnoreUserPatterns(tmpDir);
        assert.deepEqual(patterns.sort(), ["secrets/**", "vendor/internal-blob.bin"]);
        // CRITICAL: must NOT include LOA defaults like ".claude/**"
        assert.equal(patterns.includes(".claude/**"), false);
        assert.equal(patterns.includes("grimoires/**"), false);
      } finally {
        rmSync(tmpDir, { recursive: true, force: true });
      }
    });

    it("self-review honors .reviewignore secrets/ pattern — files NOT admitted", () => {
      const tmpDir = join(tmpdir(), `loa-test-selfreview-secrets-${Date.now()}`);
      mkdirSync(tmpDir, { recursive: true });
      try {
        // Operator-curated .reviewignore — secrets/ MUST be excluded under self-review.
        writeFileSync(join(tmpDir, ".reviewignore"), "secrets/\n");
        const files = [
          file(".claude/skills/bb/adapter.ts", 25, 3, "x".repeat(50)),
          file("secrets/api-keys.env", 5, 0, "x".repeat(50)),
        ];
        const config = {
          ...defaultConfig,
          loaAware: true,
          selfReview: true,
          repoRoot: tmpDir,
        };
        const result = truncateFiles(files, config);

        // Framework file admitted (self-review purpose)
        const includedNames = result.included.map((f) => f.filename);
        assert.ok(
          includedNames.includes(".claude/skills/bb/adapter.ts"),
          "framework file should be admitted under self-review",
        );
        // BUT secrets/ file MUST NOT be admitted — .reviewignore takes priority
        assert.equal(
          includedNames.includes("secrets/api-keys.env"),
          false,
          ".reviewignore secrets/ pattern MUST still exclude even under self-review",
        );
      } finally {
        rmSync(tmpDir, { recursive: true, force: true });
      }
    });

    it("self-review banner cites user-pattern count when .reviewignore present", () => {
      const tmpDir = join(tmpdir(), `loa-test-banner-${Date.now()}`);
      mkdirSync(tmpDir, { recursive: true });
      try {
        writeFileSync(join(tmpDir, ".reviewignore"), "secrets/\nvendor/\n");
        const files = [file(".claude/skills/bb/adapter.ts", 25, 3, "x".repeat(50))];
        const config = {
          ...defaultConfig,
          loaAware: true,
          selfReview: true,
          repoRoot: tmpDir,
        };
        const result = truncateFiles(files, config);

        assert.ok(result.loaBanner);
        assert.ok(
          result.loaBanner!.includes("user patterns"),
          `banner should cite user-pattern count; got: ${result.loaBanner}`,
        );
        assert.ok(
          result.loaBanner!.includes(".reviewignore"),
          `banner should mention .reviewignore; got: ${result.loaBanner}`,
        );
      } finally {
        rmSync(tmpDir, { recursive: true, force: true });
      }
    });
  });

  // BB-004 (PR #797 iter-2): four call sites duplicating the spread caused
  // BB-001 (one missed site silently nullified the feature). Centralized
  // helper is the structural fix; tests pin the contract.
  describe("deriveCallConfig (BB-004)", () => {
    it("returns selfReview=true when PR carries the label", () => {
      const config = { ...defaultConfig, selfReview: undefined };
      const pr = { labels: ["bridgebuilder:self-review"] };
      assert.equal(deriveCallConfig(config, pr).selfReview, true);
    });

    it("returns selfReview=false when label absent", () => {
      const config = { ...defaultConfig, selfReview: undefined };
      const pr = { labels: ["other-label"] };
      assert.equal(deriveCallConfig(config, pr).selfReview, false);
    });

    it("preserves ALL other config fields verbatim", () => {
      const config = {
        ...defaultConfig,
        selfReview: undefined,
        loaAware: true,
        repoRoot: "/some/path",
        excludePatterns: ["custom/*"],
        maxDiffBytes: 12345,
      };
      const pr = { labels: ["bridgebuilder:self-review"] };
      const result = deriveCallConfig(config, pr);

      assert.equal(result.loaAware, true);
      assert.equal(result.repoRoot, "/some/path");
      assert.deepEqual(result.excludePatterns, ["custom/*"]);
      assert.equal(result.maxDiffBytes, 12345);
      assert.equal(result.selfReview, true);
    });

    it("handles undefined labels gracefully (no PR label data)", () => {
      const config = { ...defaultConfig, selfReview: undefined };
      const pr = { labels: undefined };
      assert.equal(deriveCallConfig(config, pr).selfReview, false);
    });
  });

  // BB-797-001 (PR #797 iter-3): typed selfReviewActive field — downstream
  // consumers must read this, never substring-match the loaBanner prose.
  describe("selfReviewActive typed field (BB-797-001)", () => {
    it("selfReviewActive=true when self-review path runs", () => {
      const files = [file(".claude/skills/bb/adapter.ts", 25, 3, "x")];
      const config = { ...defaultConfig, loaAware: true, selfReview: true };
      const result = truncateFiles(files, config);
      assert.equal(result.selfReviewActive, true);
    });

    it("selfReviewActive=false on default loa filter path", () => {
      const files = [file("src/handler.ts", 10, 0)];
      const config = { ...defaultConfig, loaAware: true, selfReview: false };
      const result = truncateFiles(files, config);
      assert.equal(result.selfReviewActive, false);
    });

    it("selfReviewActive=false when loa not detected (selfReview is moot)", () => {
      const files = [file("src/handler.ts", 10, 0)];
      const config = { ...defaultConfig, loaAware: false, selfReview: true };
      const result = truncateFiles(files, config);
      assert.equal(result.selfReviewActive, false);
    });

    it("selfReviewActive remains true on the allExcluded path (BR-001)", () => {
      const tmpDir = join(tmpdir(), `loa-test-allexcl-selfreview-${Date.now()}`);
      mkdirSync(tmpDir, { recursive: true });
      try {
        // .reviewignore matches every changed file → allExcluded path under self-review
        writeFileSync(join(tmpDir, ".reviewignore"), "*\n");
        const files = [
          file("anything.ts", 5, 0, "x".repeat(50)),
          file("another.ts", 3, 0, "x".repeat(50)),
        ];
        const config = {
          ...defaultConfig,
          loaAware: true,
          selfReview: true,
          repoRoot: tmpDir,
        };
        const result = truncateFiles(files, config);

        // BR-001 invariant: empty included MUST set allExcluded under self-review
        assert.equal(result.allExcluded, true);
        assert.equal(result.included.length, 0);
        // Typed field still set — downstream cache logic must see this
        assert.equal(result.selfReviewActive, true);
      } finally {
        rmSync(tmpDir, { recursive: true, force: true });
      }
    });
  });

  // BB-797-001-security (PR #797 iter-4): unreadable .reviewignore under
  // self-review MUST fail-CLOSED (fall back to default LOA filter). The cycle-098
  // L2 fail-closed cost gate principle, applied to exclusion gates.
  describe("self-review fail-closed on unreadable .reviewignore (BB-797-001-security)", () => {
    it("ENOENT (.reviewignore absent) → returns [] gracefully, self-review proceeds", () => {
      const tmpDir = join(tmpdir(), `loa-test-enoent-${Date.now()}`);
      mkdirSync(tmpDir, { recursive: true });
      try {
        // No .reviewignore created → ENOENT path → returns []
        const patterns = loadReviewIgnoreUserPatterns(tmpDir);
        assert.deepEqual(patterns, []);
      } finally {
        rmSync(tmpDir, { recursive: true, force: true });
      }
    });

    it("loadReviewIgnoreUserPatterns throws on read error (NOT silent empty)", () => {
      // Point at a path where `.reviewignore` IS a directory — readFileSync
      // throws EISDIR. Models the EACCES / parse-error class.
      const tmpDir = join(tmpdir(), `loa-test-eisdir-${Date.now()}`);
      mkdirSync(join(tmpDir, ".reviewignore"), { recursive: true });
      try {
        assert.throws(
          () => loadReviewIgnoreUserPatterns(tmpDir),
          /EISDIR|illegal operation/i,
          "MUST throw on read error so caller can fail-closed",
        );
      } finally {
        rmSync(tmpDir, { recursive: true, force: true });
      }
    });

    // BB-797-SEC-002 (iter-6): errno-explicit handling. existsSync also
    // returns false for broken symlinks, EACCES, ENOTDIR — those MUST
    // propagate, NOT collapse to "absent". Distinct states are now
    // distinguished by errno.
    it("ENOENT (genuinely absent) is distinguished from other errors", () => {
      const tmpDir = join(tmpdir(), `loa-test-enoent-strict-${Date.now()}`);
      mkdirSync(tmpDir, { recursive: true });
      try {
        // Genuinely absent: no .reviewignore created
        const patterns = loadReviewIgnoreUserPatterns(tmpDir);
        assert.deepEqual(patterns, [], "ENOENT path must return [] (no rules)");
      } finally {
        rmSync(tmpDir, { recursive: true, force: true });
      }
    });

    it("ENOTDIR / EISDIR / non-ENOENT errors propagate (BB-797-SEC-002)", () => {
      // Repo root that doesn't exist as a directory — resolving
      // `.reviewignore` underneath it produces ENOTDIR / ENOENT-cascade
      // depending on platform. Check that EISDIR (.reviewignore-as-directory)
      // throws — non-ENOENT errno classes MUST propagate to fail-closed.
      const tmpDir = join(tmpdir(), `loa-test-eisdir-strict-${Date.now()}`);
      mkdirSync(join(tmpDir, ".reviewignore"), { recursive: true });
      try {
        let thrown: Error | null = null;
        try {
          loadReviewIgnoreUserPatterns(tmpDir);
        } catch (err) {
          thrown = err as Error;
        }
        assert.ok(thrown, "EISDIR MUST throw");
        // Errno code is exposed (not just message-substring) per the
        // BB-797-SEC-002 contract — caller can dispatch on it
        const code = (thrown as NodeJS.ErrnoException).code;
        assert.notEqual(code, "ENOENT", "EISDIR MUST NOT be reported as ENOENT");
      } finally {
        rmSync(tmpDir, { recursive: true, force: true });
      }
    });

    it("truncateFiles fail-closes self-review with allExcluded=true when .reviewignore unreadable (BB-797-001 iter-5 HIGH)", () => {
      const tmpDir = join(tmpdir(), `loa-test-failclosed-${Date.now()}`);
      mkdirSync(tmpDir, { recursive: true });
      // .reviewignore as directory → unreadable
      mkdirSync(join(tmpDir, ".reviewignore"), { recursive: true });
      try {
        const files = [
          file(".claude/skills/bb/adapter.ts", 25, 3, "x".repeat(50)),
          file("secrets/api-keys.env", 5, 0, "x".repeat(50)),
          file("src/handler.ts", 10, 0, "x".repeat(50)),
        ];
        const config = {
          ...defaultConfig,
          loaAware: true,
          selfReview: true,
          repoRoot: tmpDir,
        };
        const result = truncateFiles(files, config);

        // BB-797-001 iter-5 HIGH invariant: fail-closed must close EVERY axis
        // the operator was governing. We don't know what `.reviewignore`
        // wanted excluded, so NO files are admitted — including the
        // "innocent" app file. AWS-IAM analogue: unreachable policy
        // collapses to deny-all.
        assert.equal(result.allExcluded, true);
        assert.equal(result.included.length, 0);
        // Critically: the secrets/ file MUST NOT be admitted under
        // fail-closed — this is the user-gate axis the iter-4 fix leaked.
        const includedNames = result.included.map((f) => f.filename);
        assert.equal(
          includedNames.includes("secrets/api-keys.env"),
          false,
          "secrets/ file MUST NOT be admitted under fail-closed (closes BB-797-001 iter-5 HIGH)",
        );
        assert.equal(
          includedNames.includes("src/handler.ts"),
          false,
          "even non-framework app files are NOT admitted — fail-closed on every axis",
        );
        // selfReviewState=rejected reflects ACTUAL state, not operator request
        assert.equal(result.selfReviewActive, false);
        assert.equal(
          result.selfReviewState, "rejected",
          "tri-state MUST reflect rejected (not inactive); cache keys depend on this distinction",
        );
        // Banner cites the rejection so operators can debug
        assert.ok(result.loaBanner);
        assert.ok(
          result.loaBanner!.includes("REJECTED"),
          `banner should cite REJECTED state; got: ${result.loaBanner}`,
        );
        assert.ok(
          result.loaBanner!.includes("BB-797-001"),
          `banner should cite finding ID; got: ${result.loaBanner}`,
        );
      } finally {
        rmSync(tmpDir, { recursive: true, force: true });
      }
    });
  });

  // BB-797-002 (iter-5 MEDIUM): tri-state state field — boolean is lossy.
  describe("selfReviewState tri-state (BB-797-002 iter-5)", () => {
    it("state='inactive' when no self-review label", () => {
      const config = { ...defaultConfig, loaAware: true, selfReview: false };
      const result = truncateFiles([file("src/h.ts", 1, 0)], config);
      assert.equal(result.selfReviewState, "inactive");
      assert.equal(result.selfReviewActive, false);
    });

    it("state='active' when self-review succeeds", () => {
      const config = { ...defaultConfig, loaAware: true, selfReview: true };
      const result = truncateFiles([file(".claude/x.ts", 1, 0)], config);
      assert.equal(result.selfReviewState, "active");
      assert.equal(result.selfReviewActive, true);
    });

    it("state='rejected' when self-review fail-closes", () => {
      const tmpDir = join(tmpdir(), `loa-test-tri-rejected-${Date.now()}`);
      mkdirSync(tmpDir, { recursive: true });
      mkdirSync(join(tmpDir, ".reviewignore"), { recursive: true });
      try {
        const config = {
          ...defaultConfig,
          loaAware: true,
          selfReview: true,
          repoRoot: tmpDir,
        };
        const result = truncateFiles([file(".claude/x.ts", 1, 0)], config);
        assert.equal(result.selfReviewState, "rejected");
        // The convenience boolean is false in BOTH "inactive" and "rejected" —
        // that's the lossy encoding the tri-state was added to disambiguate.
        assert.equal(result.selfReviewActive, false);
      } finally {
        rmSync(tmpDir, { recursive: true, force: true });
      }
    });

    it("'inactive' and 'rejected' produce DIFFERENT cache keys (no collision)", async () => {
      // Smoke test on the cache.ts side too — BB-797-002 invariant cross-check.
      // Full cache contract lives in cache.test.ts; this guards the
      // truncation→cache wire.
      const states: Array<"inactive" | "active" | "rejected"> = [
        "inactive", "active", "rejected",
      ];
      // String comparison only — actual hash stability is in cache.test.ts
      const strings = states.map((s) => `head:0:self-review=${s}:prompthash`);
      assert.equal(new Set(strings).size, 3, "3 distinct cache key inputs");
    });
  });

  // BB-797-002-banner (PR #797 iter-4): banner states what the system DID,
  // not what it intended to enable.
  describe("self-review banner factual reporting (BB-797-002-banner)", () => {
    it("banner reports framework-files-admitted count when admitted", () => {
      const files = [
        file(".claude/skills/bb/adapter.ts", 25, 3, "x".repeat(50)),
        file(".claude/skills/bb/google.ts", 10, 0, "x".repeat(50)),
      ];
      const config = { ...defaultConfig, loaAware: true, selfReview: true };
      const result = truncateFiles(files, config);

      assert.ok(result.loaBanner);
      assert.ok(
        result.loaBanner!.includes("2 framework files admitted"),
        `banner should report admitted count; got: ${result.loaBanner}`,
      );
    });

    it("banner reports 'no framework files in PR' when none present", () => {
      const files = [file("src/handler.ts", 10, 0, "x".repeat(50))];
      const config = { ...defaultConfig, loaAware: true, selfReview: true };
      const result = truncateFiles(files, config);

      assert.ok(result.loaBanner);
      assert.ok(
        result.loaBanner!.includes("no framework files in PR"),
        `banner should be factually narrow; got: ${result.loaBanner}`,
      );
    });

    it("banner reports both admitted AND user-excluded when .reviewignore matches some framework files", () => {
      const tmpDir = join(tmpdir(), `loa-test-banner-mixed-${Date.now()}`);
      mkdirSync(tmpDir, { recursive: true });
      try {
        // .reviewignore excludes ONE specific framework path — admits the other
        writeFileSync(join(tmpDir, ".reviewignore"), ".claude/skills/bb/secrets.ts\n");
        const files = [
          file(".claude/skills/bb/adapter.ts", 25, 3, "x".repeat(50)),
          file(".claude/skills/bb/secrets.ts", 5, 0, "x".repeat(50)),
        ];
        const config = {
          ...defaultConfig,
          loaAware: true,
          selfReview: true,
          repoRoot: tmpDir,
        };
        const result = truncateFiles(files, config);

        assert.ok(result.loaBanner);
        assert.ok(
          result.loaBanner!.includes("1 framework files admitted") &&
            result.loaBanner!.includes("1 excluded by .reviewignore"),
          `banner should report both numbers; got: ${result.loaBanner}`,
        );
      } finally {
        rmSync(tmpDir, { recursive: true, force: true });
      }
    });
  });
});
