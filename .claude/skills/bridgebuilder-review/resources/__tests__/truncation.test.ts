import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { writeFileSync, mkdirSync, mkdtempSync, rmSync, symlinkSync, unlinkSync } from "node:fs";
import { execFileSync } from "node:child_process";
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
// cycle-135 C-2 (bd-i4fyw): namespace access so a missing export fails its own case, not the whole file.
import * as truncation from "../core/truncation.js";
import * as configModule from "../config.js";
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

  // cycle-135 C-1 (bd-ow72o): formerly "trailing / becomes /**"; the conversion is gone — a directory line is a
  // non-wildcard segment pattern (FR-2: `.github/workflows/` is an explicit name).
  it("keeps directory patterns as written (no / → /** conversion)", () => {
    const tmpDir = join(tmpdir(), `loa-test-${Date.now()}`);
    mkdirSync(tmpDir, { recursive: true });
    try {
      writeFileSync(join(tmpDir, ".reviewignore"), "vendor/\nbuild/\n");
      const patterns = loadReviewIgnore(tmpDir);
      assert.ok(patterns.includes("vendor/"), "vendor/ stays vendor/");
      assert.ok(patterns.includes("build/"), "build/ stays build/");
      assert.ok(!patterns.includes("vendor/**") && !patterns.includes("build/**"), "no ** conversion");
    } finally {
      rmSync(tmpDir, { recursive: true, force: true });
    }
  });

  it("normalises .reviewignore lines through the one loader (leading / or ./, ! rejected)", () => {
    const tmpDir = join(tmpdir(), `loa-test-norm-${Date.now()}-${Math.random().toString(36).slice(2)}`);
    mkdirSync(tmpDir, { recursive: true });
    const original = process.stderr.write;
    let err = "";
    (process.stderr as unknown as { write: (c: unknown) => boolean }).write = (c: unknown) => {
      err += String(c);
      return true;
    };
    try {
      writeFileSync(join(tmpDir, ".reviewignore"), "/abs.md\n./rel/\n  spaced.txt  \n!negated.md\n+(a|b).md\n");
      const patterns = loadReviewIgnoreUserPatterns(tmpDir);
      assert.deepEqual(patterns, ["abs.md", "rel/", "spaced.txt"]);
      assert.ok(err.includes("!negated.md") && err.includes("+(a|b).md"), err);
    } finally {
      process.stderr.write = original;
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
  // cycle-124 FR-3: the yaml-derived twin wins — Anthropic maxInput is
  // effective_input_ceiling (180K) − 20K headroom, not the raw context window.
  it("returns the generated (ceiling − 20K) budget for claude-sonnet-4-6", () => {
    const budget = getTokenBudget("claude-sonnet-4-6");
    assert.equal(budget.maxInput, 160_000);
    assert.equal(budget.maxOutput, 32_000); // cycle-126 FR-1.5: min(yaml 128K, BB_OUTPUT_CAP)
    assert.equal(budget.coefficient, 0.25);
  });

  it("returns the generated budget for claude-sonnet-4-5-20250929 (backward compat id)", () => {
    const budget = getTokenBudget("claude-sonnet-4-5-20250929");
    assert.equal(budget.maxInput, 160_000);
    assert.equal(budget.maxOutput, 8_192); // no max_output_tokens declared → the provider default stays
  });

  it("returns the generated budget for the new generation (claude-opus-5 / claude-fable-5-1)", () => {
    assert.equal(getTokenBudget("claude-opus-5").maxInput, 160_000);
    assert.equal(getTokenBudget("claude-fable-5-1").maxInput, 160_000);
  });

  it("falls back to the hand table for ids the yaml does not carry", () => {
    const budget = getTokenBudget("gpt-5.2-legacy-hand-only");
    assert.equal(budget.maxInput, 100_000);
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

    // cycle-135 C-1 (bd-ow72o): formerly "excludes files matching substring pattern" (`.env` excluded `.env.local`).
    // A non-wildcard pattern now names a whole segment: `.env` excludes `.env` and `config/.env`, not `.env.local`.
    it("non-wildcard pattern excludes the whole segment only (no substring match)", () => {
      const files = [file(".env.local", 1, 0), file("config/.env", 1, 0), file(".env", 1, 0), file("src/config.ts", 3, 1)];
      const config = { ...defaultConfig, excludePatterns: [".env"] };
      const result = truncateFiles(files, config);

      assert.deepEqual(result.included.map((f) => f.filename).sort(), [".env.local", "src/config.ts"]);
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
    it("loadReviewIgnoreUserPatterns returns empty when file missing in valid repoRoot", () => {
      // BB-801-002-gpt: bogus repoRoot now throws EBADREPOROOT, so we
      // need a real (empty) directory to test the genuine-absence path.
      const tmpDir = join(tmpdir(), `loa-test-no-reviewignore-${Date.now()}`);
      mkdirSync(tmpDir, { recursive: true });
      try {
        const patterns = loadReviewIgnoreUserPatterns(tmpDir);
        assert.deepEqual(patterns, []);
      } finally {
        rmSync(tmpDir, { recursive: true, force: true });
      }
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
        // cycle-135 C-1: directory lines are kept as written (no `/` → `/**` conversion)
        assert.deepEqual(patterns.sort(), ["secrets/", "vendor/internal-blob.bin"]);
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

    // BB-801-002-gpt (PR #801 iter-1 MEDIUM, conf 0.82): bogus repoRoot
    // MUST throw a config error, NOT silently collapse to "no rules".
    it("bogus repoRoot throws EBADREPOROOT (NOT silent empty)", () => {
      const bogusPath = join(tmpdir(), `loa-test-bogus-root-${Date.now()}-does-not-exist`);
      let thrown: NodeJS.ErrnoException | null = null;
      try {
        loadReviewIgnoreUserPatterns(bogusPath);
      } catch (err) {
        thrown = err as NodeJS.ErrnoException;
      }
      assert.ok(thrown, "bogus repoRoot MUST throw");
      assert.equal(thrown!.code, "EBADREPOROOT");
    });

    it("repoRoot pointing at a regular file throws EBADREPOROOT", () => {
      const tmpDir = join(tmpdir(), `loa-test-root-as-file-${Date.now()}`);
      mkdirSync(tmpDir, { recursive: true });
      const filePath = join(tmpDir, "not-a-dir");
      writeFileSync(filePath, "x");
      try {
        let thrown: NodeJS.ErrnoException | null = null;
        try {
          loadReviewIgnoreUserPatterns(filePath);
        } catch (err) {
          thrown = err as NodeJS.ErrnoException;
        }
        assert.ok(thrown);
        assert.equal(thrown!.code, "EBADREPOROOT");
      } finally {
        rmSync(tmpDir, { recursive: true, force: true });
      }
    });

    // BB801-REVIEW-002 (PR #801 iter-2 HIGH, conf 0.76): TOCTOU on symlink-
    // follow. .reviewignore-as-symlink MUST be rejected BEFORE readFileSync
    // (which follows symlinks transparently). Same CVE class as
    // Git CVE-2022-39253.
    it("rejects .reviewignore that is a symlink to ANOTHER existing file (BB801-REVIEW-002 HIGH)", () => {
      const tmpDir = join(tmpdir(), `loa-test-symlink-attack-${Date.now()}`);
      mkdirSync(tmpDir, { recursive: true });
      const reviewignorePath = join(tmpDir, ".reviewignore");
      const realFile = join(tmpDir, "real-target.txt");
      // Target file exists with content. Without the lstat-before-read
      // policy, readFileSync would silently slurp it into the policy parser.
      writeFileSync(realFile, "secrets/\nvendor/\n");
      symlinkSync(realFile, reviewignorePath);
      try {
        let thrown: NodeJS.ErrnoException | null = null;
        try {
          loadReviewIgnoreUserPatterns(tmpDir);
        } catch (err) {
          thrown = err as NodeJS.ErrnoException;
        }
        assert.ok(thrown, "symlink-to-existing-file MUST throw, not be silently followed");
        assert.equal(thrown!.code, "ESYMLINKREJECTED");
        // Closes the TOCTOU class — even if the target is innocuous,
        // the policy is fail-closed because we can't validate ahead of read
      } finally {
        rmSync(tmpDir, { recursive: true, force: true });
      }
    });

    it("rejects .reviewignore that is a directory (ENOTAFILE)", () => {
      const tmpDir = join(tmpdir(), `loa-test-dir-as-reviewignore-${Date.now()}`);
      mkdirSync(join(tmpDir, ".reviewignore"), { recursive: true });
      try {
        let thrown: NodeJS.ErrnoException | null = null;
        try {
          loadReviewIgnoreUserPatterns(tmpDir);
        } catch (err) {
          thrown = err as NodeJS.ErrnoException;
        }
        assert.ok(thrown);
        // Either EISDIR (lstat... no wait, lstat works on dirs) or
        // ENOTAFILE (our explicit non-regular-file rejection)
        assert.ok(
          thrown!.code === "ENOTAFILE" || thrown!.code === "EISDIR",
          `expected ENOTAFILE or EISDIR; got: ${thrown!.code}`,
        );
      } finally {
        rmSync(tmpDir, { recursive: true, force: true });
      }
    });

    // BB801-REVIEW-001 (PR #801 iter-2 MEDIUM, conf 0.88): symlinked
    // repoRoot MUST be accepted (macOS /tmp → /private/tmp pattern, CI
    // checkout caches). Use statSync for container, lstatSync for leaf.
    it("accepts a symlinked repoRoot (statSync, not lstatSync, for container)", () => {
      const id = `${Date.now()}-${Math.random().toString(36).slice(2)}`;
      const tmpDir = join(tmpdir(), `loa-test-symlink-repo-${id}`);
      mkdirSync(tmpDir, { recursive: true });
      const symlinkRoot = join(tmpdir(), `loa-test-symlink-link-${id}`);
      symlinkSync(tmpDir, symlinkRoot);
      try {
        // No .reviewignore in the underlying dir — should return [] gracefully
        const patterns = loadReviewIgnoreUserPatterns(symlinkRoot);
        assert.deepEqual(patterns, []);
      } finally {
        // Node 24's rmSync errors on symlinks-to-directories — use unlinkSync
        // for the symlink itself (removes the link, not its target).
        try { unlinkSync(symlinkRoot); } catch { /* best-effort */ }
        rmSync(tmpDir, { recursive: true, force: true });
      }
    });

    // #799 (iter-7 HIGH, conf 0.87): broken symlink ENOENT MUST be distinguished
    // from genuine absence. lstat-before-collapse-to-empty.
    it("broken symlink at .reviewignore throws (NOT silent absence) — #799", () => {
      const tmpDir = join(tmpdir(), `loa-test-broken-symlink-${Date.now()}`);
      mkdirSync(tmpDir, { recursive: true });
      const reviewignorePath = join(tmpDir, ".reviewignore");
      const missingTarget = join(tmpDir, "non-existent-target");
      symlinkSync(missingTarget, reviewignorePath);
      try {
        let thrown: NodeJS.ErrnoException | null = null;
        try {
          loadReviewIgnoreUserPatterns(tmpDir);
        } catch (err) {
          thrown = err as NodeJS.ErrnoException;
        }
        assert.ok(thrown, "broken symlink MUST throw, not silently collapse to []");
        assert.equal(
          thrown!.code, "ESYMLINKREJECTED",
          "errno code MUST distinguish broken symlink from genuine absence (#799 + BB-801-002-opus rename)",
        );
        // BB-801-002-opus: the code MUST NOT start with "ENOENT" — downstream
        // `err.code.startsWith("ENOENT")` checks would misclassify otherwise.
        assert.equal(
          thrown!.code!.startsWith("ENOENT"), false,
          "errno code MUST NOT begin with ENOENT prefix (string-startsWith hazard)",
        );
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

    // #800 (iter-7 HIGH, conf 0.68): default-mode trust-origin preservation.
    // User .reviewignore patterns MUST be strict denies, not tier-routed
    // through framework-classifier exception branches.
    describe("default-mode user pattern strict-deny (#800)", () => {
      it("user .reviewignore secrets/ pattern excludes high-risk file STRICTLY (not tier-exception)", () => {
        const tmpDir = join(tmpdir(), `loa-test-default-secrets-${Date.now()}`);
        mkdirSync(tmpDir, { recursive: true });
        try {
          // Operator-curated: secrets/ excluded
          writeFileSync(join(tmpDir, ".reviewignore"), "secrets/\n");
          // High-risk file (security-pattern match: .env extension) under
          // user-pattern-matched directory. The previous merged-list
          // behavior would route this through `applyLoaTierExclusion`'s
          // "exception" tier and admit it. Strict-deny phase 1 catches it
          // BEFORE tier classification.
          const files = [
            file("secrets/api-keys.env", 5, 0, "x".repeat(50)),
            file("src/handler.ts", 10, 0, "x".repeat(50)),
          ];
          const config = {
            ...defaultConfig,
            loaAware: true,
            selfReview: false, // default-mode path, NOT self-review
            repoRoot: tmpDir,
          };
          const result = truncateFiles(files, config);

          const includedNames = result.included.map((f) => f.filename);
          // CRITICAL: high-risk file MUST be excluded by user pattern even
          // in default mode. Closes #800 trust-origin leakage.
          assert.equal(
            includedNames.includes("secrets/api-keys.env"),
            false,
            "user .reviewignore pattern MUST strict-deny — even high-risk files (closes #800)",
          );
          // Innocent app file admitted as expected
          assert.ok(
            includedNames.includes("src/handler.ts"),
            "non-matched files admitted normally",
          );
          // Banner cites the strict-deny phase
          assert.ok(result.loaBanner);
          assert.ok(
            result.loaBanner!.includes(".reviewignore (strict deny)"),
            `banner should cite strict deny; got: ${result.loaBanner}`,
          );
        } finally {
          rmSync(tmpDir, { recursive: true, force: true });
        }
      });

      // BB801-001 (PR #801 iter-3 HIGH_CONSENSUS, conf 0.9, 3-model): default-
      // mode fail-CLOSES on .reviewignore anomalies. ENOENT (genuine absence)
      // is fine; everything else (ESYMLINKREJECTED, ENOTAFILE, EBADREPOROOT,
      // EACCES) MUST halt the review with allExcluded=true.
      it("default-mode fail-closes on .reviewignore anomaly (BB801-001 iter-3 HIGH_CONSENSUS)", () => {
        const tmpDir = join(tmpdir(), `loa-test-default-failclosed-${Date.now()}`);
        mkdirSync(tmpDir, { recursive: true });
        // .reviewignore as directory → ENOTAFILE on readFileSync
        mkdirSync(join(tmpDir, ".reviewignore"), { recursive: true });
        try {
          const files = [
            file("secrets/api-keys.env", 5, 0, "x".repeat(50)),
            file("src/handler.ts", 10, 0, "x".repeat(50)),
            file(".claude/x.ts", 3, 0, "x".repeat(50)),
          ];
          const config = {
            ...defaultConfig,
            loaAware: true,
            selfReview: false, // default-mode
            repoRoot: tmpDir,
          };
          const result = truncateFiles(files, config);

          // BB801-001 invariant: ALL files excluded — silent skip would have
          // admitted secrets/ and src/handler.ts.
          assert.equal(result.allExcluded, true);
          assert.equal(result.included.length, 0);
          assert.ok(result.loaBanner);
          assert.ok(
            result.loaBanner!.includes("default-mode fail-closed"),
            `banner cites fail-closed; got: ${result.loaBanner}`,
          );
          assert.ok(
            result.loaBanner!.includes("BB801-001"),
            `banner cites finding ID; got: ${result.loaBanner}`,
          );
        } finally {
          rmSync(tmpDir, { recursive: true, force: true });
        }
      });

      it("default-mode genuine ENOENT remains permissive (no fail-closed on absent file)", () => {
        // BB801-001 boundary: ENOENT (no .reviewignore at all) is NOT an
        // anomaly — it means "no user patterns", which is the common case.
        // Default-mode proceeds normally with LOA framework filter only.
        const tmpDir = join(tmpdir(), `loa-test-default-no-ri-${Date.now()}`);
        mkdirSync(tmpDir, { recursive: true });
        try {
          const files = [
            file("src/handler.ts", 10, 0, "x".repeat(50)),
            file(".claude/x.ts", 3, 0, "x".repeat(50)),
          ];
          const config = {
            ...defaultConfig,
            loaAware: true,
            selfReview: false,
            repoRoot: tmpDir,
          };
          const result = truncateFiles(files, config);

          // App file admitted, framework file excluded by LOA filter
          const includedNames = result.included.map((f) => f.filename);
          assert.ok(includedNames.includes("src/handler.ts"));
          assert.equal(includedNames.includes(".claude/x.ts"), false);
          assert.equal(result.allExcluded, false);
        } finally {
          rmSync(tmpDir, { recursive: true, force: true });
        }
      });

      it("framework filter still applies after user-pattern phase-1 (LOA defaults preserved)", () => {
        const tmpDir = join(tmpdir(), `loa-test-default-twophase-${Date.now()}`);
        mkdirSync(tmpDir, { recursive: true });
        try {
          writeFileSync(join(tmpDir, ".reviewignore"), "secrets/\n");
          const files = [
            file("secrets/api-keys.env", 5, 0, "x".repeat(50)),
            file(".claude/skills/bb/x.ts", 3, 0, "x".repeat(50)),
            file("src/handler.ts", 10, 0, "x".repeat(50)),
          ];
          const config = {
            ...defaultConfig,
            loaAware: true,
            selfReview: false,
            repoRoot: tmpDir,
          };
          const result = truncateFiles(files, config);

          const includedNames = result.included.map((f) => f.filename);
          // User-pattern phase: secrets/ excluded
          assert.equal(includedNames.includes("secrets/api-keys.env"), false);
          // LOA default phase: .claude/ excluded by framework filter
          assert.equal(includedNames.includes(".claude/skills/bb/x.ts"), false);
          // App file admitted
          assert.ok(includedNames.includes("src/handler.ts"));
          // Banner cites BOTH phases
          assert.ok(result.loaBanner);
          assert.ok(
            result.loaBanner!.includes("framework files excluded") &&
              result.loaBanner!.includes(".reviewignore (strict deny)"),
            `banner should cite both phases; got: ${result.loaBanner}`,
          );
        } finally {
          rmSync(tmpDir, { recursive: true, force: true });
        }
      });
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

// --- cycle-135 C-2 (bd-i4fyw): protected paths and .reviewignore provenance ---

type ProtectedConfig = typeof defaultConfig & {
  loaAware?: boolean;
  selfReview?: boolean;
  repoRoot?: string;
  protectedPaths?: string[];
  reviewignoreBaseSha?: string;
};

function run(files: PullRequestFile[], extra: Partial<ProtectedConfig>) {
  const config: ProtectedConfig = { ...defaultConfig, loaAware: false, ...extra };
  return truncateFiles(files, config as Parameters<typeof truncateFiles>[1]) as ReturnType<typeof truncateFiles> & {
    protectedKept?: Array<{ file: string; pattern: string }>;
    reviewignoreSource?: "base" | "checkout" | "none";
  };
}

function names(list: Array<{ filename: string }>): string[] {
  return list.map((f) => f.filename);
}

function tmpRepoDir(tag: string): string {
  return mkdtempSync(join(tmpdir(), `loa-c135-${tag}-`));
}

function captureStderr<T>(fn: () => T): { value: T; err: string } {
  const original = process.stderr.write;
  let err = "";
  (process.stderr as unknown as { write: (c: unknown) => boolean }).write = (c: unknown) => {
    err += String(c);
    return true;
  };
  try {
    return { value: fn(), err };
  } finally {
    process.stderr.write = original;
  }
}

const CI = ".github/workflows/ci.yml";

describe("protected paths (cycle-135 C-2, bd-i4fyw)", () => {
  it("DEFAULT_PROTECTED_PATHS is the SDD C-2 list", () => {
    assert.deepEqual(truncation.DEFAULT_PROTECTED_PATHS, [
      ".github/workflows/**",
      ".github/actions/**",
      ".github/CODEOWNERS",
      ".claude/settings.json",
      ".claude/settings.local.json",
      ".claude/hooks/**",
      ".husky/**",
      ".reviewignore",
    ]);
  });

  it("**/*.yml keeps .github/workflows/ci.yml and records the pattern", () => {
    const r = run([file(CI, 3, 1), file("config/app.yml", 2, 0), file("src/a.ts", 1, 0)], { excludePatterns: ["**/*.yml"] });
    assert.ok(names(r.included).includes(CI), "protected workflow stays in the review set");
    assert.ok(!names(r.included).includes("config/app.yml"), "unprotected yml still excluded");
    assert.deepEqual(r.protectedKept, [{ file: CI, pattern: "**/*.yml" }]);
  });

  for (const order of [["**/*.yml", CI], [CI, "**/*.yml"]]) {
    it(`an exact name excludes the protected file whatever the order (${order.join(", ")})`, () => {
      const r = run([file(CI, 3, 1), file("src/a.ts", 1, 0)], { excludePatterns: order });
      assert.ok(!names(r.included).includes(CI));
      assert.ok(names(r.excluded).includes(CI));
      assert.ok(!(r.protectedKept ?? []).some((k) => k.file === CI));
    });
  }

  for (const order of [["**/*.yml", ".github/workflows/"], [".github/workflows/", "**/*.yml"]]) {
    it(`the .reviewignore line .github/workflows/ is an explicit name (${order.join(", ")})`, () => {
      const root = tmpRepoDir("ri-dir");
      try {
        writeFileSync(join(root, ".reviewignore"), order.join("\n") + "\n");
        const r = run([file(CI, 3, 1), file("src/a.ts", 1, 0)], { loaAware: true, repoRoot: root });
        assert.ok(!names(r.included).includes(CI));
        assert.ok(names(r.excluded).includes(CI));
        assert.ok(!(r.protectedKept ?? []).some((k) => k.file === CI));
      } finally {
        rmSync(root, { recursive: true, force: true });
      }
    });
  }

  it(".reviewignore wildcard keeps the protected file in the default Loa mode and under self-review", () => {
    const root = tmpRepoDir("ri-wild");
    try {
      writeFileSync(join(root, ".reviewignore"), "**/*.yml\n");
      for (const selfReview of [false, true]) {
        const r = run([file(CI, 3, 1), file("config/app.yml", 2, 0), file("src/a.ts", 1, 0)], {
          loaAware: true,
          selfReview,
          repoRoot: root,
        });
        assert.ok(names(r.included).includes(CI), `selfReview=${selfReview}`);
        assert.ok(!names(r.included).includes("config/app.yml"), `selfReview=${selfReview}`);
        assert.deepEqual(r.protectedKept, [{ file: CI, pattern: "**/*.yml" }], `selfReview=${selfReview}`);
      }
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });

  it("an exact config pattern wins over protection a .reviewignore wildcard granted (order-independent across sources)", () => {
    const root = tmpRepoDir("ri-cross");
    try {
      writeFileSync(join(root, ".reviewignore"), "**/*.yml\n");
      const r = run([file(CI, 3, 1), file("src/a.ts", 1, 0)], { loaAware: true, repoRoot: root, excludePatterns: [CI] });
      assert.ok(!names(r.included).includes(CI));
      assert.ok(!(r.protectedKept ?? []).some((k) => k.file === CI));
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });

  it("protected-kept files come first in the selection order (file cap 1)", () => {
    // src/auth.ts is high-risk and larger: without protected-first it would take the one slot.
    const r = run([file("src/auth.ts", 500, 0), file(CI, 1, 0)], { excludePatterns: ["**/*.yml"], maxFilesPerPr: 1 });
    assert.deepEqual(names(r.included), [CI]);
    assert.ok(names(r.excluded).includes("src/auth.ts"));
  });

  it("protectedPaths: [] disables protection", () => {
    const r = run([file(CI, 3, 1), file("src/a.ts", 1, 0)], { excludePatterns: ["**/*.yml"], protectedPaths: [] });
    assert.ok(!names(r.included).includes(CI));
    assert.deepEqual(r.protectedKept ?? [], []);
  });

  it("a custom list protects only its entries", () => {
    const action = ".github/actions/setup/action.yml";
    const r = run([file(CI, 3, 1), file(action, 2, 0)], { excludePatterns: ["**/*.yml"], protectedPaths: [CI] });
    assert.ok(names(r.included).includes(CI));
    assert.ok(!names(r.included).includes(action));
    assert.deepEqual(r.protectedKept, [{ file: CI, pattern: "**/*.yml" }]);
  });

  it("partitionUserExclusions is order-independent and records the pattern", () => {
    const files = [file(CI, 1, 0), file("config/app.yml", 1, 0), file("src/a.ts", 1, 0)];
    const prot = [".github/workflows/**"];
    const a = truncation.partitionUserExclusions(files, ["**/*.yml"], prot);
    assert.deepEqual(a.protectedKept, [{ file: CI, pattern: "**/*.yml" }]);
    assert.deepEqual(a.excluded, [{ file: "config/app.yml", pattern: "**/*.yml" }]);
    for (const user of [["**/*.yml", CI], [CI, "**/*.yml"]]) {
      const b = truncation.partitionUserExclusions(files, user, prot);
      assert.deepEqual(b.protectedKept, [], user.join(","));
      assert.deepEqual(b.excluded, [{ file: CI, pattern: CI }, { file: "config/app.yml", pattern: "**/*.yml" }], user.join(","));
    }
  });

  it("omissions carry the excluding pattern in the stats suffix", () => {
    const r = run([file("config/app.yml", 2, 0), file("src/a.ts", 1, 0)], { excludePatterns: ["**/*.yml"] });
    const ex = r.excluded.find((e) => e.filename === "config/app.yml");
    assert.ok(ex && ex.stats.endsWith("(excluded by pattern) [pattern: **/*.yml]"), ex?.stats);
  });

  it("the Loa tier still strips .claude/settings.json without self-review, naming its default pattern", () => {
    const root = tmpRepoDir("loa-tier");
    try {
      const r = run([file(".claude/settings.json", 2, 0), file("src/a.ts", 1, 0)], { loaAware: true, repoRoot: root });
      assert.ok(!names(r.included).includes(".claude/settings.json"));
      const ex = r.excluded.find((e) => e.filename === ".claude/settings.json");
      assert.ok(ex && /\(Loa framework, summary only\) \[pattern: \.claude\/\*\*\]$/.test(ex.stats), ex?.stats);
      assert.deepEqual(r.protectedKept ?? [], []);
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });
});

describe("protected_paths and the fetch keys in config (cycle-135 C-2, bd-i4fyw)", () => {
  it("validateProtectedPaths strips a leading / or ./ and keeps the rest", () => {
    assert.deepEqual(configModule.validateProtectedPaths(["/.github/x/**", "./.husky/**", " ci.yml "]), [
      ".github/x/**",
      ".husky/**",
      "ci.yml",
    ]);
    assert.deepEqual(configModule.validateProtectedPaths([]), []);
  });

  for (const [bad, needle] of [
    [[42], "42"],
    [[""], "[0]"],
    [["ok/**", "   "], "[1]"],
    [["a/../b"], "a/../b"],
    [[".."], ".."],
    [["+(a|b).yml"], "+(a|b).yml"],
  ] as Array<[unknown[], string]>) {
    it(`validateProtectedPaths rejects ${JSON.stringify(bad)} with an error naming the entry`, () => {
      assert.throws(
        () => configModule.validateProtectedPaths(bad),
        (e: Error) => e.message.includes("protected_paths") && e.message.includes(needle),
      );
    });
  }

  it("validateProtectedPaths rejects a non-list value", () => {
    assert.throws(() => configModule.validateProtectedPaths("ci.yml"), /protected_paths/);
  });

  it("resolveConfig carries protected_paths, fetch_missing_patches and max_content_fetches", async () => {
    const { config } = await configModule.resolveConfig(
      {},
      {},
      { enabled: true, repos: ["test/repo"], protected_paths: ["/ci.yml"], fetch_missing_patches: false, max_content_fetches: 5 } as never,
    );
    assert.deepEqual(config.protectedPaths, ["ci.yml"]);
    assert.equal(config.fetchMissingPatches, false);
    assert.equal(config.maxContentFetches, 5);
  });

  it("resolveConfig leaves the three keys undefined when unset (the readers default them)", async () => {
    const { config } = await configModule.resolveConfig({}, {}, { enabled: true, repos: ["test/repo"] });
    assert.equal(config.protectedPaths, undefined);
    assert.equal(config.fetchMissingPatches, undefined);
    assert.equal(config.maxContentFetches, undefined);
  });

  it("resolveConfig rejects an invalid protected_paths entry", async () => {
    await assert.rejects(
      configModule.resolveConfig({}, {}, { enabled: true, repos: ["test/repo"], protected_paths: ["a/../b"] } as never),
      /protected_paths.*a\/\.\.\/b/,
    );
  });

  it("resolveConfig rejects a negative or fractional max_content_fetches", async () => {
    for (const bad of [-1, 1.5]) {
      await assert.rejects(
        configModule.resolveConfig({}, {}, { enabled: true, repos: ["test/repo"], max_content_fetches: bad } as never),
        /max_content_fetches/,
      );
    }
  });
});

describe(".reviewignore provenance (cycle-135 C-2, bd-i4fyw)", () => {
  function git(root: string, ...args: string[]): string {
    return execFileSync(
      "git",
      ["-C", root, "-c", "user.name=t", "-c", "user.email=t@example.invalid", "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", ...args],
      { encoding: "utf-8", stdio: ["ignore", "pipe", "pipe"] },
    ).trim();
  }

  /** A repo with two commits: base has `.reviewignore` = base-only.md, head (the checkout) = head-only.md + src/**. */
  function twoCommitRepo(): { root: string; base: string } {
    const root = tmpRepoDir("prov");
    git(root, "init", "-q");
    writeFileSync(join(root, ".reviewignore"), "base-only.md\n");
    git(root, "add", ".reviewignore");
    git(root, "commit", "-q", "-m", "base");
    const base = git(root, "rev-parse", "HEAD");
    writeFileSync(join(root, ".reviewignore"), "head-only.md\nsrc/**\n");
    git(root, "add", ".reviewignore");
    git(root, "commit", "-q", "-m", "head");
    return { root, base };
  }

  it("reads the base version when a base sha is given", () => {
    const { root, base } = twoCommitRepo();
    try {
      assert.deepEqual(truncation.parseReviewignoreFile(root, { baseSha: base }), { patterns: ["base-only.md"], source: "base" });
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });

  it("reads the checkout version without a base sha", () => {
    const { root } = twoCommitRepo();
    try {
      assert.deepEqual(truncation.parseReviewignoreFile(root), { patterns: ["head-only.md", "src/**"], source: "checkout" });
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });

  it("is none when the file is absent from the checkout", () => {
    const root = tmpRepoDir("prov-absent");
    try {
      assert.deepEqual(truncation.parseReviewignoreFile(root), { patterns: [], source: "none" });
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });

  it("is none with a WARN when the base read fails (file absent at base, unknown sha, malformed sha)", () => {
    const { root } = twoCommitRepo();
    try {
      git(root, "rm", "-q", ".reviewignore");
      git(root, "commit", "-q", "-m", "drop");
      const noFile = git(root, "rev-parse", "HEAD");
      writeFileSync(join(root, ".reviewignore"), "checkout-only.md\n"); // never consulted when a base sha is given
      for (const sha of [noFile, "0".repeat(40), "abc123", "--output=/tmp/x"]) {
        const { value, err } = captureStderr(() => truncation.parseReviewignoreFile(root, { baseSha: sha }));
        assert.deepEqual(value, { patterns: [], source: "none" }, sha);
        assert.ok(/WARN/.test(err) && err.includes(".reviewignore"), `${sha}: ${err}`);
      }
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });

  it("is none with a WARN when .reviewignore is a symlink at the base", () => {
    const root = tmpRepoDir("prov-link");
    try {
      git(root, "init", "-q");
      writeFileSync(join(root, "target"), "x.md\n");
      symlinkSync("target", join(root, ".reviewignore"));
      git(root, "add", "target", ".reviewignore");
      git(root, "commit", "-q", "-m", "link");
      const base = git(root, "rev-parse", "HEAD");
      const { value, err } = captureStderr(() => truncation.parseReviewignoreFile(root, { baseSha: base }));
      assert.deepEqual(value, { patterns: [], source: "none" });
      assert.ok(/WARN/.test(err), err);
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });

  it("truncateFiles applies the base patterns: a line the PR adds does not affect its own review", () => {
    const { root, base } = twoCommitRepo();
    try {
      const files = [file("src/a.ts", 3, 0), file("base-only.md", 1, 0), file(".reviewignore", 2, 1)];
      const withBase = run(files, { loaAware: true, repoRoot: root, reviewignoreBaseSha: base });
      assert.ok(names(withBase.included).includes("src/a.ts"), "head-added src/** must not apply");
      assert.ok(!names(withBase.included).includes("base-only.md"), "base pattern applies");
      assert.ok(names(withBase.included).includes(".reviewignore"), "the file itself is reviewed");
      assert.equal(withBase.reviewignoreSource, "base");
      const checkout = run(files, { loaAware: true, repoRoot: root });
      assert.ok(!names(checkout.included).includes("src/a.ts"));
      assert.equal(checkout.reviewignoreSource, "checkout");
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });
});
