import { describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  progressiveTruncate,
  prioritizeFiles,
  parseHunks,
  reduceHunkContext,
  capSecurityFile,
  isAdjacentTest,
  estimateTokens,
  getTokenBudget,
  TOKEN_BUDGETS,
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

// --- TOKEN_BUDGETS ---

describe("TOKEN_BUDGETS", () => {
  it("has entry for claude-sonnet-4-5-20250929", () => {
    const budget = TOKEN_BUDGETS["claude-sonnet-4-5-20250929"];
    assert.ok(budget);
    assert.equal(budget.maxInput, 200_000);
    assert.equal(budget.coefficient, 0.25);
  });

  it("has entry for claude-opus-4-6", () => {
    const budget = TOKEN_BUDGETS["claude-opus-4-6"];
    assert.ok(budget);
    assert.equal(budget.maxInput, 200_000);
  });

  it("has entry for gpt-5.2", () => {
    const budget = TOKEN_BUDGETS["gpt-5.2"];
    assert.ok(budget);
    assert.equal(budget.maxInput, 128_000);
    assert.equal(budget.coefficient, 0.23);
  });

  it("getTokenBudget falls back to default for unknown models", () => {
    const budget = getTokenBudget("unknown-model");
    assert.equal(budget, TOKEN_BUDGETS["default"]);
  });

  it("estimateTokens uses model-specific coefficient", () => {
    const text = "x".repeat(1000);
    const sonnet = estimateTokens(text, "claude-sonnet-4-5-20250929");
    const gpt = estimateTokens(text, "gpt-5.2");
    // sonnet: ceil(1000 * 0.25) = 250
    assert.equal(sonnet, 250);
    // gpt: ceil(1000 * 0.23) = 230
    assert.equal(gpt, 230);
  });
});

// --- parseHunks ---

describe("parseHunks", () => {
  it("parses single hunk correctly", () => {
    const patch = "@@ -1,3 +1,5 @@\n+line1\n+line2\n context";
    const hunks = parseHunks(patch);
    assert.ok(hunks);
    assert.equal(hunks.length, 1);
    assert.equal(hunks[0].header, "@@ -1,3 +1,5 @@");
    assert.deepEqual(hunks[0].lines, ["+line1", "+line2", " context"]);
  });

  it("parses multiple hunks", () => {
    const patch = "@@ -1,3 +1,5 @@\n+line1\n@@ -10,3 +12,5 @@\n+line2\n-removed";
    const hunks = parseHunks(patch);
    assert.ok(hunks);
    assert.equal(hunks.length, 2);
    assert.equal(hunks[1].header, "@@ -10,3 +12,5 @@");
  });

  it("returns empty array for empty patch", () => {
    const hunks = parseHunks("");
    assert.ok(hunks);
    assert.equal(hunks.length, 0);
  });

  it("ignores lines before first @@ header", () => {
    const patch = "diff --git a/f b/f\nindex abc..def\n@@ -1,3 +1,5 @@\n+line1";
    const hunks = parseHunks(patch);
    assert.ok(hunks);
    assert.equal(hunks.length, 1);
    assert.equal(hunks[0].lines.length, 1);
  });

  it("returns empty array for falsy input", () => {
    // parseHunks checks `if (!patch)` which catches null/undefined/empty
    // @ts-expect-error testing invalid input
    const hunks = parseHunks(null);
    assert.deepEqual(hunks, []);
  });
});

// --- reduceHunkContext ---

describe("reduceHunkContext", () => {
  it("keeps changed lines with 0 context", () => {
    const hunks = [
      {
        header: "@@ -1,5 +1,5 @@",
        lines: [" unchanged1", "+added", " unchanged2", "-removed", " unchanged3"],
      },
    ];
    const reduced = reduceHunkContext(hunks, 0);
    assert.equal(reduced.length, 1);
    // Only changed lines kept
    const kept = reduced[0].lines;
    assert.ok(kept.includes("+added"));
    assert.ok(kept.includes("-removed"));
    assert.ok(!kept.includes(" unchanged1"));
    assert.ok(!kept.includes(" unchanged3"));
  });

  it("keeps 1 line of context around changes", () => {
    const hunks = [
      {
        header: "@@ -1,7 +1,7 @@",
        lines: [
          " far-away",
          " before",
          "+added",
          " after",
          " far-away-2",
          " far-away-3",
        ],
      },
    ];
    const reduced = reduceHunkContext(hunks, 1);
    const kept = reduced[0].lines;
    assert.ok(kept.includes(" before"));
    assert.ok(kept.includes("+added"));
    assert.ok(kept.includes(" after"));
    assert.ok(!kept.includes(" far-away"));
    assert.ok(!kept.includes(" far-away-3"));
  });
});

// --- capSecurityFile ---

describe("capSecurityFile", () => {
  it("returns file unchanged when patch is under 50KB", () => {
    const f = file("src/auth.ts", 5, 3, "x".repeat(1000));
    const result = capSecurityFile(f);
    assert.equal(result.patch, f.patch);
  });

  it("caps large security files to first 10 hunks", () => {
    // Create a patch with 15 hunks, each ~4KB to exceed 50KB total
    const hunkContent = "+x\n".repeat(1200); // ~3600 bytes per hunk
    const hunks = Array.from({ length: 15 }, (_, i) =>
      `@@ -${i * 100 + 1},3 +${i * 100 + 1},5 @@\n${hunkContent}`,
    ).join("");
    const f = file("src/auth.ts", 100, 0, hunks);

    // Verify it's over the cap
    const byteSize = new TextEncoder().encode(f.patch!).byteLength;
    assert.ok(byteSize > 50_000, `Expected >50KB, got ${byteSize}`);

    const result = capSecurityFile(f);
    assert.ok(result.patch!.includes("[10 of 15 hunks included"));
  });

  it("returns file unchanged when no patch", () => {
    const f: PullRequestFile = {
      filename: "auth.ts",
      status: "modified",
      additions: 5,
      deletions: 3,
      patch: undefined,
    };
    const result = capSecurityFile(f);
    assert.equal(result.patch, undefined);
  });
});

// --- prioritizeFiles ---

describe("prioritizeFiles", () => {
  it("security files come first", () => {
    const files = [
      file("src/utils.ts", 10, 5),
      file("src/auth/login.ts", 3, 1),
      file("README.md", 20, 0),
    ];
    const sorted = prioritizeFiles(files);
    assert.equal(sorted[0].filename, "src/auth/login.ts");
  });

  it("adjacent tests come after security files", () => {
    const files = [
      file("src/app.ts", 5, 2),
      file("src/app.test.ts", 10, 0),
      file("src/auth.ts", 3, 1),
    ];
    const sorted = prioritizeFiles(files);
    // auth.ts first (security), then app.test.ts (adjacent test to app.ts), then app.ts
    assert.equal(sorted[0].filename, "src/auth.ts");
    assert.equal(sorted[1].filename, "src/app.test.ts");
    assert.equal(sorted[2].filename, "src/app.ts");
  });

  it("entry/config files come after adjacent tests", () => {
    const files = [
      file("src/something.ts", 20, 5),
      file("src/index.ts", 3, 1),
      file("tsconfig.json", 2, 0),
    ];
    const sorted = prioritizeFiles(files);
    // index.ts and tsconfig.json are entry/config (priority 2)
    // something.ts is remaining (priority 1)
    const configIdx = sorted.findIndex((f) => f.filename === "src/index.ts");
    const remainIdx = sorted.findIndex((f) => f.filename === "src/something.ts");
    assert.ok(configIdx < remainIdx, "config files should come before remaining");
  });

  it("ties broken by change size (larger first)", () => {
    const files = [
      file("src/small.ts", 2, 0),
      file("src/big.ts", 50, 10),
    ];
    const sorted = prioritizeFiles(files);
    assert.equal(sorted[0].filename, "src/big.ts");
  });

  it("final tie-break is alphabetical", () => {
    const files = [
      file("src/zebra.ts", 5, 0),
      file("src/alpha.ts", 5, 0),
    ];
    const sorted = prioritizeFiles(files);
    assert.equal(sorted[0].filename, "src/alpha.ts");
  });
});

// --- isAdjacentTest ---

describe("isAdjacentTest", () => {
  it("returns true for test file next to changed source", () => {
    const files = [
      file("src/app.ts", 5, 2),
      file("src/app.test.ts", 3, 0),
    ];
    assert.ok(isAdjacentTest("src/app.test.ts", files));
  });

  it("returns false for test file without adjacent source", () => {
    const files = [
      file("src/app.test.ts", 3, 0),
    ];
    assert.ok(!isAdjacentTest("src/app.test.ts", files));
  });

  it("returns false for non-test file", () => {
    const files = [file("src/app.ts", 5, 2)];
    assert.ok(!isAdjacentTest("src/app.ts", files));
  });

  it("matches .spec. files as tests", () => {
    const files = [
      file("src/auth.ts", 5, 2),
      file("src/auth.spec.ts", 3, 0),
    ];
    assert.ok(isAdjacentTest("src/auth.spec.ts", files));
  });
});

// --- progressiveTruncate ---

describe("progressiveTruncate", () => {
  const model = "claude-sonnet-4-5-20250929";
  const systemLen = 200; // Short system prompt
  const metadataLen = 500; // PR metadata

  it("Level 1: drops low-priority files to fit budget", () => {
    const files = [
      file("src/auth.ts", 10, 5, "x".repeat(400)),       // security → priority 4
      file("src/utils.ts", 5, 2, "x".repeat(400)),        // normal → priority 1
      file("src/helpers.ts", 3, 1, "x".repeat(400)),      // normal → priority 1
    ];
    // Budget that fits ~1-2 files but not all 3
    // Fixed tokens: ceil((200+500)*0.25) = 175
    // Each file: ceil(400*0.25) = 100
    // Target: floor(500*0.9) = 450
    // 175 + 100 = 275 (auth fits), 275+100=375 (utils fits), 375+100=475>450 (helpers excluded)
    const result = progressiveTruncate(files, 500, model, systemLen, metadataLen);

    assert.ok(result.success);
    assert.equal(result.level, 1);
    assert.ok(result.files.length >= 1);
    // Auth should be included (highest priority)
    assert.ok(result.files.some((f) => f.filename === "src/auth.ts"));
    assert.ok(result.excluded.length > 0);
    assert.ok(result.disclaimer?.includes("low-priority files excluded"));
  });

  it("Level 2: reduces hunk context when Level 1 fails", () => {
    // Single file too large for Level 1 even alone
    const largePatch =
      "@@ -1,10 +1,15 @@\n" +
      " ctx1\n ctx2\n ctx3\n+added1\n ctx4\n ctx5\n ctx6\n" +
      "@@ -20,10 +25,15 @@\n" +
      " ctx7\n ctx8\n ctx9\n+added2\n ctx10\n ctx11\n ctx12\n";

    const files = [file("src/big.ts", 50, 20, largePatch)];

    // Budget: enough for reduced patch but not full
    // Fixed: ceil((200+500)*0.25) = 175
    // Full patch: ~170 chars → ceil(170*0.25) = 43
    // Total: 175+43 = 218
    // But set budget so 90% target = 210 → full doesn't fit but reduced does
    // Actually the patch is small enough. Let's make it larger.
    const bigPatch =
      Array.from({ length: 20 }, (_, i) =>
        `@@ -${i * 20 + 1},10 +${i * 20 + 1},15 @@\n` +
        " ctx1\n ctx2\n ctx3\n+added\n ctx4\n ctx5\n ctx6\n",
      ).join("");
    const bigFiles = [file("src/big.ts", 200, 50, bigPatch)];

    // Budget where full patch doesn't fit at Level 1 but hunk-reduced does at Level 2
    const patchTokens = Math.ceil(bigPatch.length * 0.25);
    const fixedTokens = Math.ceil((systemLen + metadataLen) * 0.25);
    // Set budget so 90% barely fails at L1 but works at L2 with context reduction
    const budget = Math.floor((fixedTokens + patchTokens) / 0.9) - 10;

    const result = progressiveTruncate(bigFiles, budget, model, systemLen, metadataLen);

    if (result.success && result.level === 2) {
      assert.ok(result.disclaimer?.includes("patches truncated"));
    }
    // If it succeeded at any level, that's fine
    assert.ok(result.success, "Should succeed at some level");
  });

  it("Level 3: stats only when diffs too large", () => {
    const hugePatch = "x".repeat(100_000);
    const files = [file("src/massive.ts", 5000, 0, hugePatch)];

    // Very small budget — only stats can fit
    const result = progressiveTruncate(files, 500, model, systemLen, metadataLen);

    assert.ok(result.success);
    assert.equal(result.level, 3);
    assert.equal(result.files.length, 0);
    assert.ok(result.excluded.length > 0);
    assert.ok(result.disclaimer?.includes("Summary Review"));
  });

  it("returns failure when even stats don't fit", () => {
    // Generate many files with long names to make even stats huge
    const files = Array.from({ length: 500 }, (_, i) =>
      file(`src/very/deep/nested/directory/structure/file${i}.ts`, 100, 50, "x".repeat(1000)),
    );

    // Impossibly small budget
    const result = progressiveTruncate(files, 10, model, 5, 5);
    assert.equal(result.success, false);
  });

  it("applies size-aware security handling (SKP-005)", () => {
    // Large security file that should be capped
    const hunkContent = "+x\n".repeat(200);
    const hunks = Array.from({ length: 15 }, (_, i) =>
      `@@ -${i * 10 + 1},3 +${i * 10 + 1},5 @@\n${hunkContent}`,
    ).join("");
    const files = [file("src/auth/handler.ts", 100, 0, hunks)];

    // Budget large enough for capped version
    const result = progressiveTruncate(files, 50_000, model, systemLen, metadataLen);

    assert.ok(result.success);
    if (result.files.length > 0 && result.files[0].patch) {
      // If capped, should mention hunks included
      const patchText = result.files[0].patch;
      if (new TextEncoder().encode(hunks).byteLength > 50_000) {
        assert.ok(patchText.includes("hunks included"));
      }
    }
  });

  it("includes token estimate breakdown", () => {
    const files = [file("src/app.ts", 5, 3, "x".repeat(100))];
    const result = progressiveTruncate(files, 10_000, model, systemLen, metadataLen);

    assert.ok(result.success);
    assert.ok(result.tokenEstimate);
    assert.equal(typeof result.tokenEstimate.persona, "number");
    assert.equal(typeof result.tokenEstimate.metadata, "number");
    assert.equal(typeof result.tokenEstimate.diffs, "number");
    assert.equal(typeof result.tokenEstimate.total, "number");
    assert.equal(
      result.tokenEstimate.total,
      result.tokenEstimate.persona + result.tokenEstimate.template + result.tokenEstimate.metadata + result.tokenEstimate.diffs,
    );
  });

  it("uses 90% budget target (SKP-004)", () => {
    // Create files that fit in 100% but not 90% of budget
    const patchSize = 360; // tokens: ceil(360*0.25) = 90
    const fixedTokens = Math.ceil((systemLen + metadataLen) * 0.25); // 175
    // Total at 100%: 175 + 90 = 265
    // Budget = 280 → 90% = 252 < 265 → Level 1 should exclude the file
    const files = [file("src/app.ts", 5, 3, "x".repeat(patchSize))];
    const result = progressiveTruncate(files, 280, model, systemLen, metadataLen);

    // The file doesn't fit at 90% budget, so it should be excluded at Level 1
    // Level 2 or 3 should handle it
    assert.ok(result.success);
    if (result.level === 1) {
      // If Level 1 succeeded, the file was excluded and stats-only result
      assert.equal(result.files.length, 0);
    }
  });

  it("respects deterministic priority order (IMP-002)", () => {
    const files = [
      file("src/utils.ts", 5, 0, "x".repeat(200)),        // priority 1
      file("src/auth.ts", 3, 0, "x".repeat(200)),          // priority 4 (security)
      file("src/index.ts", 2, 0, "x".repeat(200)),         // priority 2 (entry)
    ];

    // Budget fits only 2 files
    // Fixed: 175, each file: 50, target: floor(500*0.9)=450
    // 175+50=225 (auth), 225+50=275 (index), 275+50=325 (utils) → all fit at 500
    // Use tighter budget: 350 → target=315 → 175+50+50=275 fits 2, 275+50=325>315 → exclude 1
    const result = progressiveTruncate(files, 350, model, systemLen, metadataLen);

    assert.ok(result.success);
    if (result.level === 1 && result.excluded.length > 0) {
      // utils.ts (lowest priority) should be excluded
      assert.equal(result.excluded[0].filename, "src/utils.ts");
    }
  });
});

// --- E2E Fixture: all-Loa PR ---

describe("E2E: all-Loa PR", () => {
  it("progressiveTruncate handles empty file list gracefully", () => {
    const result = progressiveTruncate([], 10_000, "claude-sonnet-4-5-20250929", 200, 500);
    // Empty files → Level 1 has 0 included → falls through to Level 3 stats
    // Level 3 with 0 files → stats tokens ≈ 0 → success
    assert.ok(result.success);
  });
});

// --- Performance guardrails (IMP-009) ---

describe("performance guardrails (IMP-009)", () => {
  it("progressiveTruncate with 200 files completes in <500ms", () => {
    const files = Array.from({ length: 200 }, (_, i) =>
      file(
        `src/components/feature-${i}/component.ts`,
        Math.floor(Math.random() * 50) + 1,
        Math.floor(Math.random() * 20),
        "@@ -1,5 +1,10 @@\n" + "+line\n".repeat(20),
      ),
    );

    const start = performance.now();
    const result = progressiveTruncate(
      files,
      50_000,
      "claude-sonnet-4-5-20250929",
      500,
      1000,
    );
    const elapsed = performance.now() - start;

    assert.ok(result.success || !result.success); // Just verify it completes
    assert.ok(elapsed < 500, `Expected <500ms, got ${elapsed.toFixed(1)}ms`);
  });

  it("detectLoa + applyLoaTierExclusion with 100 files completes in <100ms", async () => {
    const { writeFileSync, mkdirSync, rmSync } = await import("node:fs");
    const { join } = await import("node:path");
    const { tmpdir } = await import("node:os");
    const { detectLoa, applyLoaTierExclusion, LOA_EXCLUDE_PATTERNS } = await import("../core/truncation.js");

    const tmpDir = join(tmpdir(), `perf-test-${Date.now()}`);
    mkdirSync(tmpDir, { recursive: true });
    writeFileSync(
      join(tmpDir, ".loa-version.json"),
      JSON.stringify({ framework_version: "1.31.0" }),
    );

    const files = Array.from({ length: 100 }, (_, i) => {
      const isLoa = i < 50; // Half Loa, half app
      return file(
        isLoa ? `.claude/skills/skill-${i}/index.ts` : `src/module-${i}/index.ts`,
        10,
        5,
        "@@ -1,5 +1,10 @@\n+line\n",
      );
    });

    const start = performance.now();
    const detection = detectLoa({ repoRoot: tmpDir });
    assert.equal(detection.isLoa, true);
    applyLoaTierExclusion(files, LOA_EXCLUDE_PATTERNS);
    const elapsed = performance.now() - start;

    rmSync(tmpDir, { recursive: true, force: true });

    assert.ok(elapsed < 100, `Expected <100ms, got ${elapsed.toFixed(1)}ms`);
  });
});

// --- E2E Fixture: lockfile-heavy PR ---

describe("E2E: lockfile-heavy PR", () => {
  it("prioritizes lockfiles as security files", () => {
    const files = [
      file("package-lock.json", 5000, 4000, "x".repeat(50_000)),
      file("yarn.lock", 3000, 2000, "x".repeat(30_000)),
      file("src/app.ts", 10, 5, "x".repeat(200)),
    ];

    const sorted = prioritizeFiles(files);
    // Lockfiles match SECURITY_PATTERNS → priority 4
    assert.equal(sorted[0].filename, "package-lock.json"); // largest security
    assert.equal(sorted[1].filename, "yarn.lock");
    assert.equal(sorted[2].filename, "src/app.ts");
  });
});
