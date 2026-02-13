import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import { writeFileSync, mkdirSync, rmSync, existsSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import {
  detectLoa,
  classifyLoaFile,
  applyLoaTierExclusion,
  extractFirstHunk,
  LOA_EXCLUDE_PATTERNS,
  isHighRisk,
  getSecurityCategory,
  matchesExcludePattern,
  SECURITY_PATTERNS,
  isLoaSystemZone,
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

// --- detectLoa ---

describe("detectLoa", () => {
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = join(tmpdir(), `loa-test-${Date.now()}-${Math.random().toString(36).slice(2)}`);
    mkdirSync(tmpDir, { recursive: true });
  });

  afterEach(() => {
    if (existsSync(tmpDir)) {
      rmSync(tmpDir, { recursive: true, force: true });
    }
  });

  it("returns isLoa: true when config.loaAware is true (override)", () => {
    const result = detectLoa({ loaAware: true, repoRoot: tmpDir });
    assert.equal(result.isLoa, true);
    assert.equal(result.source, "config_override");
  });

  it("returns isLoa: false when config.loaAware is false (override)", () => {
    // Even if .loa-version.json exists, override wins
    writeFileSync(
      join(tmpDir, ".loa-version.json"),
      JSON.stringify({ framework_version: "1.0.0" }),
    );
    const result = detectLoa({ loaAware: false, repoRoot: tmpDir });
    assert.equal(result.isLoa, false);
    assert.equal(result.source, "config_override");
  });

  it("auto-detects Loa from .loa-version.json with valid semver", () => {
    writeFileSync(
      join(tmpDir, ".loa-version.json"),
      JSON.stringify({ framework_version: "1.31.0" }),
    );
    const result = detectLoa({ repoRoot: tmpDir });
    assert.equal(result.isLoa, true);
    assert.equal(result.version, "1.31.0");
    assert.equal(result.source, "file");
  });

  it("returns isLoa: false when .loa-version.json missing", () => {
    const result = detectLoa({ repoRoot: tmpDir });
    assert.equal(result.isLoa, false);
    assert.equal(result.source, "file");
  });

  it("returns isLoa: false when .loa-version.json has invalid framework_version", () => {
    writeFileSync(
      join(tmpDir, ".loa-version.json"),
      JSON.stringify({ framework_version: "not-a-version" }),
    );
    const result = detectLoa({ repoRoot: tmpDir });
    assert.equal(result.isLoa, false);
  });

  it("returns isLoa: false when .loa-version.json is malformed JSON", () => {
    writeFileSync(join(tmpDir, ".loa-version.json"), "not json at all");
    const result = detectLoa({ repoRoot: tmpDir });
    assert.equal(result.isLoa, false);
  });

  it("returns isLoa: false when framework_version is missing", () => {
    writeFileSync(
      join(tmpDir, ".loa-version.json"),
      JSON.stringify({ other_field: "value" }),
    );
    const result = detectLoa({ repoRoot: tmpDir });
    assert.equal(result.isLoa, false);
  });

  it("accepts semver with pre-release suffix", () => {
    writeFileSync(
      join(tmpDir, ".loa-version.json"),
      JSON.stringify({ framework_version: "2.0.0-beta.1" }),
    );
    const result = detectLoa({ repoRoot: tmpDir });
    assert.equal(result.isLoa, true);
    assert.equal(result.version, "2.0.0-beta.1");
  });
});

// --- classifyLoaFile ---

describe("classifyLoaFile", () => {
  it("classifies security files in system zones as tier2 (Bug 2 fix)", () => {
    assert.equal(classifyLoaFile(".claude/scripts/auth/login.sh"), "tier2");
    assert.equal(classifyLoaFile("grimoires/loa/crypto/keys.ts"), "tier2");
  });

  it("classifies security files outside system zones as exception", () => {
    assert.equal(classifyLoaFile("src/auth/login.ts"), "exception");
    assert.equal(classifyLoaFile("lib/crypto/keys.ts"), "exception");
    assert.equal(classifyLoaFile("SECURITY.md"), "exception");
    assert.equal(classifyLoaFile("CODEOWNERS"), "exception");
  });

  it("classifies .md files under Loa paths as tier1", () => {
    assert.equal(classifyLoaFile("grimoires/loa/prd.md"), "tier1");
    assert.equal(classifyLoaFile(".claude/loa/CLAUDE.loa.md"), "tier1");
  });

  it("classifies .sh files as tier2", () => {
    assert.equal(classifyLoaFile(".claude/scripts/setup.sh"), "tier2");
  });

  it("classifies .ts files as tier2", () => {
    assert.equal(classifyLoaFile(".claude/skills/review/resources/core/types.ts"), "tier2");
  });

  it("classifies .json files as tier2", () => {
    assert.equal(classifyLoaFile(".claude/data/constraints.json"), "tier2");
  });

  it("classifies SECURITY.md as exception (security pattern takes precedence)", () => {
    // SECURITY.md matches the /security/ pattern → exception (never excluded)
    assert.equal(classifyLoaFile("SECURITY.md"), "exception");
  });

  it("classifies CODEOWNERS as exception (security pattern takes precedence over filename)", () => {
    // CODEOWNERS matches SECURITY_PATTERNS policy → exception
    assert.equal(classifyLoaFile("CODEOWNERS"), "exception");
  });

  it("classifies .github/ paths as exception when matching security patterns", () => {
    // .github/workflows/ matches SECURITY_PATTERNS (cicd) → exception takes precedence
    assert.equal(classifyLoaFile(".github/workflows/ci.yml"), "exception");
  });

  it("classifies .github/ non-workflow paths as tier2 (SKP-002 path heuristic)", () => {
    // .github/ISSUE_TEMPLATE/ doesn't match security patterns but matches TIER2_MIN_PATHS
    assert.equal(classifyLoaFile(".github/ISSUE_TEMPLATE/bug.md"), "tier2");
  });

  it("classifies infra/ paths as tier2 minimum (SKP-002)", () => {
    assert.equal(classifyLoaFile("infra/deploy/config.md"), "tier2");
  });

  it("classifies unknown extensions as tier1 (conservative)", () => {
    assert.equal(classifyLoaFile("grimoires/loa/data.xyz"), "tier1");
  });

  it("classifies image files as tier1", () => {
    assert.equal(classifyLoaFile("grimoires/loa/diagrams/arch.png"), "tier1");
    assert.equal(classifyLoaFile(".claude/assets/icon.svg"), "tier1");
  });
});

// --- extractFirstHunk ---

describe("extractFirstHunk", () => {
  it("returns full patch for single hunk", () => {
    const patch = "@@ -1,3 +1,5 @@\n+line1\n+line2\n context";
    assert.equal(extractFirstHunk(patch), patch);
  });

  it("returns only first hunk for multi-hunk patch", () => {
    const patch = "@@ -1,3 +1,5 @@\n+line1\n@@ -10,3 +12,5 @@\n+line2";
    const result = extractFirstHunk(patch);
    assert.ok(result.includes("+line1"));
    assert.ok(!result.includes("@@ -10,3"));
    assert.ok(!result.includes("+line2"));
  });

  it("returns empty string for empty input", () => {
    assert.equal(extractFirstHunk(""), "");
  });

  it("returns patch as-is when no @@ headers found", () => {
    const patch = "+line1\n-line2";
    assert.equal(extractFirstHunk(patch), patch);
  });
});

// --- applyLoaTierExclusion ---

describe("applyLoaTierExclusion", () => {
  it("passes through non-Loa files unchanged", () => {
    const files = [file("src/app.ts", 5, 3), file("lib/utils.ts", 2, 1)];
    const result = applyLoaTierExclusion(files, LOA_EXCLUDE_PATTERNS);

    assert.equal(result.passthrough.length, 2);
    assert.equal(result.tier1Excluded.length, 0);
    assert.equal(result.tier2Summary.length, 0);
  });

  it("excludes .claude/ files to tier1 (.md) and tier2 (.ts)", () => {
    const files = [
      file(".claude/loa/CLAUDE.loa.md", 10, 0),
      file(".claude/skills/review/resources/core/types.ts", 5, 2),
    ];
    const result = applyLoaTierExclusion(files, LOA_EXCLUDE_PATTERNS);

    assert.equal(result.passthrough.length, 0);
    assert.equal(result.tier1Excluded.length, 1);
    assert.equal(result.tier1Excluded[0].filename, ".claude/loa/CLAUDE.loa.md");
    assert.equal(result.tier2Summary.length, 1);
    assert.equal(result.tier2Summary[0].filename, ".claude/skills/review/resources/core/types.ts");
  });

  it("excludes grimoires/ files", () => {
    const files = [file("grimoires/loa/prd.md", 100, 0)];
    const result = applyLoaTierExclusion(files, LOA_EXCLUDE_PATTERNS);

    assert.equal(result.passthrough.length, 0);
    assert.equal(result.tier1Excluded.length, 1);
  });

  it("excludes .beads/ files", () => {
    const files = [file(".beads/state.json", 5, 0)];
    const result = applyLoaTierExclusion(files, LOA_EXCLUDE_PATTERNS);

    assert.equal(result.passthrough.length, 0);
    // .json is tier2
    assert.equal(result.tier2Summary.length, 1);
  });

  it("demotes security files under Loa system zones to tier2 (Bug 2 fix)", () => {
    const files = [file(".claude/scripts/auth/login.sh", 10, 0)];
    const result = applyLoaTierExclusion(files, LOA_EXCLUDE_PATTERNS);

    // auth/ matches SECURITY_PATTERNS, but .claude/ is a system zone → tier2 (not exception/passthrough)
    assert.equal(result.passthrough.length, 0);
    assert.equal(result.tier2Summary.length, 1);
    assert.equal(result.tier2Summary[0].filename, ".claude/scripts/auth/login.sh");
  });

  it("passes through security files outside Loa system zones", () => {
    // src/auth/ is NOT in LOA_EXCLUDE_PATTERNS, so it passes through normally
    const files = [file("src/auth/login.ts", 10, 0)];
    const result = applyLoaTierExclusion(files, LOA_EXCLUDE_PATTERNS);

    assert.equal(result.passthrough.length, 1);
  });

  it("tracks bytesSaved from excluded files", () => {
    const patch = "x".repeat(500);
    const files = [file("grimoires/loa/notes.md", 10, 0, patch)];
    const result = applyLoaTierExclusion(files, LOA_EXCLUDE_PATTERNS);

    assert.ok(result.bytesSaved > 0);
  });

  it("includes first hunk summary for tier2 files", () => {
    const patch = "@@ -1,3 +1,5 @@\n+first\n@@ -10,3 +12,5 @@\n+second";
    const files = [file(".claude/scripts/setup.sh", 5, 0, patch)];
    const result = applyLoaTierExclusion(files, LOA_EXCLUDE_PATTERNS);

    assert.equal(result.tier2Summary.length, 1);
    assert.ok(result.tier2Summary[0].summary.includes("+first"));
    assert.ok(!result.tier2Summary[0].summary.includes("+second"));
  });

  it("handles mixed Loa and non-Loa files", () => {
    const files = [
      file("src/app.ts", 10, 5),
      file(".claude/loa/CLAUDE.loa.md", 20, 0),
      file("grimoires/loa/prd.md", 50, 0),
      file("lib/auth/login.ts", 3, 1),
    ];
    const result = applyLoaTierExclusion(files, LOA_EXCLUDE_PATTERNS);

    assert.equal(result.passthrough.length, 2); // src/app.ts + lib/auth/login.ts
    assert.equal(result.tier1Excluded.length, 2); // both .md files
  });
});

// --- SECURITY_PATTERNS coverage ---

describe("SECURITY_PATTERNS", () => {
  it("has at least 39 patterns", () => {
    assert.ok(SECURITY_PATTERNS.length >= 39, `Expected >=39, got ${SECURITY_PATTERNS.length}`);
  });

  it("each pattern has category and rationale", () => {
    for (const entry of SECURITY_PATTERNS) {
      assert.ok(entry.pattern instanceof RegExp, `Pattern ${entry.rationale} is not a RegExp`);
      assert.ok(entry.category.length > 0, `Missing category for ${entry.rationale}`);
      assert.ok(entry.rationale.length > 0, `Missing rationale`);
    }
  });

  it("covers all required categories", () => {
    const categories = new Set(SECURITY_PATTERNS.map((p) => p.category));
    for (const required of ["auth", "crypto", "cicd", "iac", "lockfile", "policy"]) {
      assert.ok(categories.has(required), `Missing category: ${required}`);
    }
  });

  it("isHighRisk matches auth files", () => {
    assert.ok(isHighRisk("src/auth/login.ts"));
    assert.ok(isHighRisk("middleware/auth.ts"));
    assert.ok(isHighRisk("lib/oauth/provider.ts"));
  });

  it("isHighRisk matches crypto files", () => {
    assert.ok(isHighRisk("src/crypto/hash.ts"));
    assert.ok(isHighRisk("config/security.yml"));
    assert.ok(isHighRisk("keys/server.pem"));
  });

  it("isHighRisk matches CI/CD files", () => {
    assert.ok(isHighRisk(".github/workflows/deploy.yml"));
    assert.ok(isHighRisk("Dockerfile"));
    assert.ok(isHighRisk("Jenkinsfile"));
  });

  it("isHighRisk matches lockfiles", () => {
    assert.ok(isHighRisk("package-lock.json"));
    assert.ok(isHighRisk("yarn.lock"));
    assert.ok(isHighRisk("Cargo.lock"));
  });

  it("getSecurityCategory returns correct category", () => {
    assert.equal(getSecurityCategory("src/auth/login.ts"), "auth");
    assert.equal(getSecurityCategory("src/crypto/keys.ts"), "crypto");
    assert.equal(getSecurityCategory(".github/workflows/ci.yml"), "cicd");
    assert.equal(getSecurityCategory("deploy.tf"), "iac");
    assert.equal(getSecurityCategory("package-lock.json"), "lockfile");
    assert.equal(getSecurityCategory(".github/CODEOWNERS"), "policy");
  });

  it("getSecurityCategory returns undefined for non-security files", () => {
    assert.equal(getSecurityCategory("src/utils.ts"), undefined);
    assert.equal(getSecurityCategory("README.md"), undefined);
  });
});

// --- LOA_EXCLUDE_PATTERNS ---

describe("LOA_EXCLUDE_PATTERNS", () => {
  it("matches .claude/ paths", () => {
    assert.ok(matchesExcludePattern(".claude/loa/CLAUDE.loa.md", LOA_EXCLUDE_PATTERNS));
    assert.ok(matchesExcludePattern(".claude/scripts/setup.sh", LOA_EXCLUDE_PATTERNS));
  });

  it("matches grimoires/ paths", () => {
    assert.ok(matchesExcludePattern("grimoires/loa/prd.md", LOA_EXCLUDE_PATTERNS));
  });

  it("matches .beads/ paths", () => {
    assert.ok(matchesExcludePattern(".beads/state.json", LOA_EXCLUDE_PATTERNS));
  });

  it("matches .loa-version.json exactly", () => {
    assert.ok(matchesExcludePattern(".loa-version.json", LOA_EXCLUDE_PATTERNS));
  });

  it("does not match application files", () => {
    assert.ok(!matchesExcludePattern("src/app.ts", LOA_EXCLUDE_PATTERNS));
    assert.ok(!matchesExcludePattern("lib/utils.ts", LOA_EXCLUDE_PATTERNS));
    assert.ok(!matchesExcludePattern("package.json", LOA_EXCLUDE_PATTERNS));
  });
});

// --- isLoaSystemZone (Bug 2 fix — issue #309) ---

describe("isLoaSystemZone", () => {
  it("returns true for .claude/ paths", () => {
    assert.ok(isLoaSystemZone(".claude/scripts/setup.sh"));
    assert.ok(isLoaSystemZone(".claude/protocols/security-hardening.md"));
  });

  it("returns true for grimoires/ paths", () => {
    assert.ok(isLoaSystemZone("grimoires/loa/prd.md"));
    assert.ok(isLoaSystemZone("grimoires/loa/security-notes.md"));
  });

  it("returns true for other system zones", () => {
    assert.ok(isLoaSystemZone(".beads/state.json"));
    assert.ok(isLoaSystemZone("evals/suites/basic.ts"));
    assert.ok(isLoaSystemZone(".run/sprint-plan-state.json"));
    assert.ok(isLoaSystemZone(".flatline/runs/abc.json"));
  });

  it("returns false for application paths", () => {
    assert.ok(!isLoaSystemZone("src/auth/login.ts"));
    assert.ok(!isLoaSystemZone("lib/crypto/keys.ts"));
    assert.ok(!isLoaSystemZone("app/page.tsx"));
  });

  it("returns false for root-level files", () => {
    assert.ok(!isLoaSystemZone("SECURITY.md"));
    assert.ok(!isLoaSystemZone("CODEOWNERS"));
    assert.ok(!isLoaSystemZone("package.json"));
  });
});

// --- Dual-list sync assertion (medium-1 fix — bridge iter-1) ---

describe("LOA_SYSTEM_ZONE_PREFIXES / LOA_EXCLUDE_PATTERNS sync", () => {
  it("every system zone prefix has a corresponding exclude pattern", () => {
    // isLoaSystemZone prefixes: .claude/, grimoires/, .beads/, evals/, .run/, .flatline/
    // Each should have a glob entry in LOA_EXCLUDE_PATTERNS (e.g., ".claude/**")
    const systemZonePaths = [
      ".claude/test",
      "grimoires/test",
      ".beads/test",
      "evals/test",
      ".run/test",
      ".flatline/test",
    ];
    for (const path of systemZonePaths) {
      assert.ok(
        isLoaSystemZone(path),
        `${path} should be detected as system zone`,
      );
      assert.ok(
        matchesExcludePattern(path, LOA_EXCLUDE_PATTERNS),
        `${path} should also match LOA_EXCLUDE_PATTERNS — lists are out of sync`,
      );
    }
  });
});

// --- LOA_EXCLUDE_PATTERNS: new patterns (Bug 1 fix — issue #309) ---

describe("LOA_EXCLUDE_PATTERNS — expanded patterns", () => {
  it("matches evals/ paths", () => {
    assert.ok(matchesExcludePattern("evals/suites/basic.ts", LOA_EXCLUDE_PATTERNS));
    assert.ok(matchesExcludePattern("evals/fixtures/repo/src/index.ts", LOA_EXCLUDE_PATTERNS));
  });

  it("matches .run/ paths", () => {
    assert.ok(matchesExcludePattern(".run/sprint-plan-state.json", LOA_EXCLUDE_PATTERNS));
    assert.ok(matchesExcludePattern(".run/bridge-state.json", LOA_EXCLUDE_PATTERNS));
  });

  it("matches .flatline/ paths", () => {
    assert.ok(matchesExcludePattern(".flatline/runs/abc.json", LOA_EXCLUDE_PATTERNS));
    assert.ok(matchesExcludePattern(".flatline/snapshots/snap.json", LOA_EXCLUDE_PATTERNS));
  });

  it("matches Loa doc files", () => {
    assert.ok(matchesExcludePattern("PROCESS.md", LOA_EXCLUDE_PATTERNS));
    assert.ok(matchesExcludePattern("BUTTERFREEZONE.md", LOA_EXCLUDE_PATTERNS));
    assert.ok(matchesExcludePattern("INSTALLATION.md", LOA_EXCLUDE_PATTERNS));
    assert.ok(matchesExcludePattern("grimoires/loa/NOTES.md", LOA_EXCLUDE_PATTERNS));
  });

  it("does NOT match root-level NOTES.md (low-1 fix — bridge iter-1)", () => {
    // NOTES.md is now qualified to grimoires/**/NOTES.md to avoid false-positives
    assert.ok(!matchesExcludePattern("NOTES.md", LOA_EXCLUDE_PATTERNS));
  });

  it("does NOT match application paths", () => {
    assert.ok(!matchesExcludePattern("src/index.ts", LOA_EXCLUDE_PATTERNS));
    assert.ok(!matchesExcludePattern("tests/unit/foo.test.ts", LOA_EXCLUDE_PATTERNS));
    assert.ok(!matchesExcludePattern("app/page.tsx", LOA_EXCLUDE_PATTERNS));
  });
});

// --- classifyLoaFile: system zone demotion (Bug 2 fix — issue #309) ---

describe("classifyLoaFile — system zone demotion", () => {
  it("demotes .claude/protocols/security-hardening.md to tier2", () => {
    assert.equal(classifyLoaFile(".claude/protocols/security-hardening.md"), "tier2");
  });

  it("demotes .claude/scripts/detect-secrets.sh to tier2", () => {
    assert.equal(classifyLoaFile(".claude/scripts/detect-secrets.sh"), "tier2");
  });

  it("demotes .claude/adapters/crypto-utils.ts to tier2", () => {
    assert.equal(classifyLoaFile(".claude/adapters/crypto-utils.ts"), "tier2");
  });

  it("demotes grimoires/loa/security-notes.md to tier2", () => {
    assert.equal(classifyLoaFile("grimoires/loa/security-notes.md"), "tier2");
  });

  it("keeps src/security/middleware.ts as exception", () => {
    assert.equal(classifyLoaFile("src/security/middleware.ts"), "exception");
  });

  it("keeps lib/auth/oauth.ts as exception", () => {
    assert.equal(classifyLoaFile("lib/auth/oauth.ts"), "exception");
  });

  it("keeps root SECURITY.md as exception", () => {
    assert.equal(classifyLoaFile("SECURITY.md"), "exception");
  });
});

// --- matchesExcludePattern: enhanced glob matching (BB-F4) ---

describe("matchesExcludePattern — enhanced glob patterns", () => {
  it("supports ** recursive matching: src/**/*.ts", () => {
    assert.ok(matchesExcludePattern("src/core/utils.ts", ["src/**/*.ts"]));
    assert.ok(matchesExcludePattern("src/deep/nested/file.ts", ["src/**/*.ts"]));
    assert.ok(!matchesExcludePattern("src/core/utils.js", ["src/**/*.ts"]));
    assert.ok(!matchesExcludePattern("lib/core/utils.ts", ["src/**/*.ts"]));
  });

  it("supports ** at end: logs/**", () => {
    assert.ok(matchesExcludePattern("logs/app.log", ["logs/**"]));
    assert.ok(matchesExcludePattern("logs/2024/01/debug.log", ["logs/**"]));
  });

  it("supports ** at start: **/*.test.ts", () => {
    assert.ok(matchesExcludePattern("src/core/utils.test.ts", ["**/*.test.ts"]));
    assert.ok(matchesExcludePattern("utils.test.ts", ["**/*.test.ts"]));
    assert.ok(!matchesExcludePattern("src/core/utils.ts", ["**/*.test.ts"]));
  });

  it("supports ? single character wildcard", () => {
    assert.ok(matchesExcludePattern("file1.ts", ["file?.ts"]));
    assert.ok(matchesExcludePattern("fileA.ts", ["file?.ts"]));
    assert.ok(!matchesExcludePattern("file10.ts", ["file?.ts"]));
    assert.ok(!matchesExcludePattern("file.ts", ["file?.ts"]));
  });

  it("? does not match path separator", () => {
    assert.ok(!matchesExcludePattern("file/.ts", ["file?.ts"]));
  });

  it("existing basic patterns still work", () => {
    // suffix pattern: *.md
    assert.ok(matchesExcludePattern("README.md", ["*.md"]));
    assert.ok(!matchesExcludePattern("README.txt", ["*.md"]));

    // prefix pattern: src/*
    assert.ok(matchesExcludePattern("src/app.ts", ["src/*"]));

    // exact match
    assert.ok(matchesExcludePattern(".loa-version.json", [".loa-version.json"]));

    // substring match
    assert.ok(matchesExcludePattern("path/to/grimoires/loa/file.md", ["grimoires/"]));
  });

  it("handles empty patterns array", () => {
    assert.ok(!matchesExcludePattern("anything.ts", []));
  });

  it("handles special regex characters in patterns", () => {
    assert.ok(matchesExcludePattern("src/file.test.ts", ["src/**/*.test.ts"]));
    assert.ok(matchesExcludePattern("pkg(1).ts", ["pkg(1).ts"]));
  });
});
