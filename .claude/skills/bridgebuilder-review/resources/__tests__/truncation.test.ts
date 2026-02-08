import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { truncateFiles } from "../core/truncation.js";
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
});
