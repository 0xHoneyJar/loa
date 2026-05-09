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
});
