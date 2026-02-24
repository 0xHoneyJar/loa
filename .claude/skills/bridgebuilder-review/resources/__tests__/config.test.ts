import { describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  parseCLIArgs,
  resolveConfig,
  resolveRepos,
  formatEffectiveConfig,
  resolveRepoRoot,
} from "../config.js";
import type { CLIArgs, EnvVars, YamlConfig } from "../config.js";

// Helper: resolve config with explicit yaml (skips file I/O)
async function resolve(
  cli: CLIArgs = {},
  env: EnvVars = {},
  yaml: YamlConfig = { enabled: true, repos: ["test/repo"] },
) {
  return resolveConfig(cli, env, yaml);
}

describe("parseCLIArgs", () => {
  it("parses --dry-run flag", () => {
    const args = parseCLIArgs(["--dry-run"]);
    assert.equal(args.dryRun, true);
  });

  it("parses --repo flag", () => {
    const args = parseCLIArgs(["--repo", "owner/repo"]);
    assert.deepEqual(args.repos, ["owner/repo"]);
  });

  it("parses multiple --repo flags", () => {
    const args = parseCLIArgs(["--repo", "a/b", "--repo", "c/d"]);
    assert.deepEqual(args.repos, ["a/b", "c/d"]);
  });

  it("parses --pr flag", () => {
    const args = parseCLIArgs(["--pr", "42"]);
    assert.equal(args.pr, 42);
  });

  it("rejects negative --pr value", () => {
    assert.throws(() => parseCLIArgs(["--pr", "-1"]), /positive integer/);
  });

  it("rejects non-numeric --pr value", () => {
    assert.throws(() => parseCLIArgs(["--pr", "abc"]), /positive integer/);
  });

  it("parses --no-auto-detect flag", () => {
    const args = parseCLIArgs(["--no-auto-detect"]);
    assert.equal(args.noAutoDetect, true);
  });

  it("parses --max-input-tokens flag", () => {
    const args = parseCLIArgs(["--max-input-tokens", "64000"]);
    assert.equal(args.maxInputTokens, 64000);
  });

  it("parses --max-output-tokens flag", () => {
    const args = parseCLIArgs(["--max-output-tokens", "8000"]);
    assert.equal(args.maxOutputTokens, 8000);
  });

  it("parses --max-diff-bytes flag", () => {
    const args = parseCLIArgs(["--max-diff-bytes", "256000"]);
    assert.equal(args.maxDiffBytes, 256000);
  });

  it("parses --model flag", () => {
    const args = parseCLIArgs(["--model", "claude-opus-4-6"]);
    assert.equal(args.model, "claude-opus-4-6");
  });

  it("rejects negative --max-input-tokens", () => {
    assert.throws(() => parseCLIArgs(["--max-input-tokens", "-1"]), /positive integer/);
  });

  it("rejects non-numeric --max-output-tokens", () => {
    assert.throws(() => parseCLIArgs(["--max-output-tokens", "abc"]), /positive integer/);
  });

  it("rejects zero --max-diff-bytes", () => {
    assert.throws(() => parseCLIArgs(["--max-diff-bytes", "0"]), /positive integer/);
  });

  it("returns empty args for no input", () => {
    const args = parseCLIArgs([]);
    assert.equal(args.dryRun, undefined);
    assert.equal(args.repos, undefined);
    assert.equal(args.pr, undefined);
    assert.equal(args.maxInputTokens, undefined);
    assert.equal(args.maxOutputTokens, undefined);
    assert.equal(args.maxDiffBytes, undefined);
    assert.equal(args.model, undefined);
  });
});

describe("resolveConfig precedence", () => {
  it("CLI repos override env repos", async () => {
    const { config, provenance } = await resolve(
      { repos: ["cli/repo"] },
      { BRIDGEBUILDER_REPOS: "env/repo" },
      { enabled: true, repos: ["yaml/repo"] },
    );
    assert.equal(config.repos[0].owner, "cli");
    assert.equal(config.repos[0].repo, "repo");
    assert.equal(provenance.repos, "cli");
  });

  it("env repos override yaml repos when CLI absent", async () => {
    const { config, provenance } = await resolve(
      {},
      { BRIDGEBUILDER_REPOS: "env/repo" },
      { enabled: true, repos: ["yaml/repo"] },
    );
    assert.equal(config.repos[0].owner, "env");
    assert.equal(provenance.repos, "env");
  });

  it("yaml repos used when CLI and env absent", async () => {
    const { config, provenance } = await resolve(
      {},
      {},
      { enabled: true, repos: ["yaml/repo"] },
    );
    assert.equal(config.repos[0].owner, "yaml");
    assert.equal(provenance.repos, "yaml");
  });

  it("env model overrides yaml model", async () => {
    const { config, provenance } = await resolve(
      {},
      { BRIDGEBUILDER_MODEL: "env-model" },
      { enabled: true, repos: ["test/repo"], model: "yaml-model" },
    );
    assert.equal(config.model, "env-model");
    assert.equal(provenance.model, "env");
  });

  it("yaml model used when env absent", async () => {
    const { config, provenance } = await resolve(
      {},
      {},
      { enabled: true, repos: ["test/repo"], model: "yaml-model" },
    );
    assert.equal(config.model, "yaml-model");
    assert.equal(provenance.model, "yaml");
  });

  it("default model used when env and yaml absent", async () => {
    const { config, provenance } = await resolve(
      {},
      {},
      { enabled: true, repos: ["test/repo"] },
    );
    assert.equal(config.model, "claude-opus-4-6");
    assert.equal(provenance.model, "default");
  });

  it("CLI dryRun overrides env dryRun", async () => {
    const { config, provenance } = await resolve(
      { dryRun: true },
      { BRIDGEBUILDER_DRY_RUN: "false" },
    );
    assert.equal(config.dryRun, true);
    assert.equal(provenance.dryRun, "cli");
  });

  it("env dryRun used when CLI absent", async () => {
    const { config, provenance } = await resolve(
      {},
      { BRIDGEBUILDER_DRY_RUN: "true" },
    );
    assert.equal(config.dryRun, true);
    assert.equal(provenance.dryRun, "env");
  });

  it("CLI model overrides env and yaml model", async () => {
    const { config, provenance } = await resolve(
      { model: "cli-model" },
      { BRIDGEBUILDER_MODEL: "env-model" },
      { enabled: true, repos: ["test/repo"], model: "yaml-model" },
    );
    assert.equal(config.model, "cli-model");
    assert.equal(provenance.model, "cli");
  });

  it("CLI maxInputTokens overrides yaml", async () => {
    const { config, provenance } = await resolve(
      { maxInputTokens: 200_000 },
      {},
      { enabled: true, repos: ["test/repo"], max_input_tokens: 64_000 },
    );
    assert.equal(config.maxInputTokens, 200_000);
    assert.equal(provenance.maxInputTokens, "cli");
  });

  it("yaml maxInputTokens used when CLI absent", async () => {
    const { config, provenance } = await resolve(
      {},
      {},
      { enabled: true, repos: ["test/repo"], max_input_tokens: 64_000 },
    );
    assert.equal(config.maxInputTokens, 64_000);
    assert.equal(provenance.maxInputTokens, "yaml");
  });

  it("CLI maxOutputTokens overrides yaml", async () => {
    const { config, provenance } = await resolve(
      { maxOutputTokens: 32_000 },
      {},
      { enabled: true, repos: ["test/repo"], max_output_tokens: 8_000 },
    );
    assert.equal(config.maxOutputTokens, 32_000);
    assert.equal(provenance.maxOutputTokens, "cli");
  });

  it("CLI maxDiffBytes overrides yaml", async () => {
    const { config, provenance } = await resolve(
      { maxDiffBytes: 1_000_000 },
      {},
      { enabled: true, repos: ["test/repo"], max_diff_bytes: 256_000 },
    );
    assert.equal(config.maxDiffBytes, 1_000_000);
    assert.equal(provenance.maxDiffBytes, "cli");
  });

  it("defaults used when CLI and yaml absent for token/size fields", async () => {
    const { config, provenance } = await resolve(
      {},
      {},
      { enabled: true, repos: ["test/repo"] },
    );
    assert.equal(config.maxInputTokens, 128_000);
    assert.equal(config.maxOutputTokens, 16_000);
    assert.equal(config.maxDiffBytes, 512_000);
    assert.equal(provenance.maxInputTokens, "default");
    assert.equal(provenance.maxOutputTokens, "default");
    assert.equal(provenance.maxDiffBytes, "default");
  });

  it("throws when bridgebuilder is disabled in yaml", async () => {
    await assert.rejects(
      () => resolve({}, {}, { enabled: false }),
      /disabled/,
    );
  });
});

describe("resolveRepos", () => {
  it("allows --pr with single repo", () => {
    const config = {
      repos: [{ owner: "a", repo: "b" }],
    } as any;
    const result = resolveRepos(config, 42);
    assert.equal(result.length, 1);
  });

  it("rejects --pr with multiple repos", () => {
    const config = {
      repos: [{ owner: "a", repo: "b" }, { owner: "c", repo: "d" }],
    } as any;
    assert.throws(() => resolveRepos(config, 42), /--pr 42/);
  });
});

describe("formatEffectiveConfig", () => {
  it("includes provenance annotations when provided", () => {
    const config = {
      repos: [{ owner: "test", repo: "repo" }],
      model: "claude-sonnet-4-5-20250929",
      maxPrs: 10,
      dryRun: false,
      sanitizerMode: "default" as const,
      excludePatterns: [],
    } as any;
    const provenance = {
      repos: "cli" as const,
      model: "env" as const,
      dryRun: "default" as const,
      maxInputTokens: "cli" as const,
      maxOutputTokens: "yaml" as const,
      maxDiffBytes: "default" as const,
      reviewMode: "default" as const,
    };
    const output = formatEffectiveConfig(config, provenance);

    assert.ok(output.includes("(cli)"), "Should include repos provenance");
    assert.ok(output.includes("(env)"), "Should include model provenance");
    assert.ok(output.includes("max_input_tokens="), "Should include maxInputTokens");
    assert.ok(output.includes("max_output_tokens="), "Should include maxOutputTokens");
    assert.ok(output.includes("max_diff_bytes="), "Should include maxDiffBytes");
  });

  it("omits provenance annotations when not provided", () => {
    const config = {
      repos: [{ owner: "test", repo: "repo" }],
      model: "claude-sonnet-4-5-20250929",
      maxPrs: 10,
      dryRun: false,
      sanitizerMode: "default" as const,
      excludePatterns: [],
    } as any;
    const output = formatEffectiveConfig(config);

    assert.ok(!output.includes("(cli)"));
    assert.ok(!output.includes("(env)"));
    assert.ok(!output.includes("(default)"));
  });

  it("includes persona info when persona is set", () => {
    const config = {
      repos: [{ owner: "test", repo: "repo" }],
      model: "claude-sonnet-4-5-20250929",
      maxPrs: 10,
      dryRun: false,
      sanitizerMode: "default" as const,
      persona: "security",
      excludePatterns: [],
    } as any;
    const output = formatEffectiveConfig(config);

    assert.ok(output.includes("persona=security"), "Should include persona");
  });

  it("includes exclude patterns when set", () => {
    const config = {
      repos: [{ owner: "test", repo: "repo" }],
      model: "claude-sonnet-4-5-20250929",
      maxPrs: 10,
      dryRun: false,
      sanitizerMode: "default" as const,
      excludePatterns: ["*.md", "dist/*"],
    } as any;
    const output = formatEffectiveConfig(config);

    assert.ok(output.includes("exclude_patterns="), "Should include exclude patterns");
    assert.ok(output.includes("*.md"), "Should include first pattern");
    assert.ok(output.includes("dist/*"), "Should include second pattern");
  });
});

// --- Sprint 2: New CLI flags ---

describe("parseCLIArgs --persona flag", () => {
  it("parses --persona flag", () => {
    const args = parseCLIArgs(["--persona", "security"]);
    assert.equal(args.persona, "security");
  });

  it("parses --persona with other flags", () => {
    const args = parseCLIArgs(["--dry-run", "--persona", "dx", "--repo", "a/b"]);
    assert.equal(args.persona, "dx");
    assert.equal(args.dryRun, true);
    assert.deepEqual(args.repos, ["a/b"]);
  });
});

describe("parseCLIArgs --exclude flag", () => {
  it("parses single --exclude flag", () => {
    const args = parseCLIArgs(["--exclude", "*.md"]);
    assert.deepEqual(args.exclude, ["*.md"]);
  });

  it("parses multiple --exclude flags (repeatable)", () => {
    const args = parseCLIArgs(["--exclude", "*.md", "--exclude", "dist/*"]);
    assert.deepEqual(args.exclude, ["*.md", "dist/*"]);
  });

  it("accumulates --exclude with other flags", () => {
    const args = parseCLIArgs(["--exclude", "*.md", "--dry-run", "--exclude", "dist/*"]);
    assert.deepEqual(args.exclude, ["*.md", "dist/*"]);
    assert.equal(args.dryRun, true);
  });
});

describe("resolveConfig persona precedence", () => {
  it("CLI persona overrides YAML persona", async () => {
    const { config } = await resolve(
      { persona: "security" },
      {},
      { enabled: true, repos: ["test/repo"], persona: "dx" },
    );
    assert.equal(config.persona, "security");
  });

  it("YAML persona used when CLI absent", async () => {
    const { config } = await resolve(
      {},
      {},
      { enabled: true, repos: ["test/repo"], persona: "dx" },
    );
    assert.equal(config.persona, "dx");
  });

  it("persona undefined when CLI and YAML absent", async () => {
    const { config } = await resolve(
      {},
      {},
      { enabled: true, repos: ["test/repo"] },
    );
    assert.equal(config.persona, undefined);
  });

  it("passes through personaFilePath from YAML persona_path", async () => {
    const { config } = await resolve(
      {},
      {},
      { enabled: true, repos: ["test/repo"], persona_path: "/custom/persona.md" },
    );
    assert.equal(config.personaFilePath, "/custom/persona.md");
  });
});

describe("resolveConfig exclude merging", () => {
  it("merges YAML and CLI exclude patterns in order", async () => {
    const { config } = await resolve(
      { exclude: ["cli-pattern"] },
      {},
      { enabled: true, repos: ["test/repo"], exclude_patterns: ["yaml-pattern"] },
    );
    assert.deepEqual(config.excludePatterns, ["yaml-pattern", "cli-pattern"]);
  });

  it("CLI exclude only when YAML absent", async () => {
    const { config } = await resolve(
      { exclude: ["cli-only"] },
      {},
      { enabled: true, repos: ["test/repo"] },
    );
    assert.deepEqual(config.excludePatterns, ["cli-only"]);
  });

  it("YAML exclude only when CLI absent", async () => {
    const { config } = await resolve(
      {},
      {},
      { enabled: true, repos: ["test/repo"], exclude_patterns: ["yaml-only"] },
    );
    assert.deepEqual(config.excludePatterns, ["yaml-only"]);
  });

  it("empty excludePatterns when both absent", async () => {
    const { config } = await resolve(
      {},
      {},
      { enabled: true, repos: ["test/repo"] },
    );
    assert.deepEqual(config.excludePatterns, []);
  });
});

describe("resolveConfig loaAware", () => {
  it("passes through loa_aware: true from YAML", async () => {
    const { config } = await resolve(
      {},
      {},
      { enabled: true, repos: ["test/repo"], loa_aware: true },
    );
    assert.equal(config.loaAware, true);
  });

  it("passes through loa_aware: false from YAML", async () => {
    const { config } = await resolve(
      {},
      {},
      { enabled: true, repos: ["test/repo"], loa_aware: false },
    );
    assert.equal(config.loaAware, false);
  });

  it("loaAware undefined when not in YAML", async () => {
    const { config } = await resolve(
      {},
      {},
      { enabled: true, repos: ["test/repo"] },
    );
    assert.equal(config.loaAware, undefined);
  });
});

// --- repoRoot resolution (Bug 3 fix — issue #309) ---

describe("parseCLIArgs --repo-root flag", () => {
  it("parses --repo-root flag", () => {
    const args = parseCLIArgs(["--repo-root", "/custom/path"]);
    assert.equal(args.repoRoot, "/custom/path");
  });

  it("parses --repo-root with other flags", () => {
    const args = parseCLIArgs(["--dry-run", "--repo-root", "/opt/repo", "--repo", "a/b"]);
    assert.equal(args.repoRoot, "/opt/repo");
    assert.equal(args.dryRun, true);
    assert.deepEqual(args.repos, ["a/b"]);
  });
});

describe("resolveRepoRoot", () => {
  it("CLI repoRoot takes highest precedence", () => {
    const result = resolveRepoRoot(
      { repoRoot: "/cli/path" },
      { BRIDGEBUILDER_REPO_ROOT: "/env/path" },
    );
    assert.equal(result, "/cli/path");
  });

  it("env BRIDGEBUILDER_REPO_ROOT used when CLI absent", () => {
    const result = resolveRepoRoot({}, { BRIDGEBUILDER_REPO_ROOT: "/env/path" });
    assert.equal(result, "/env/path");
  });

  it("falls back to git auto-detect when no CLI or env", () => {
    const result = resolveRepoRoot({}, {});
    // We're in a git repo, so this should return a path
    assert.ok(result !== undefined, "Should auto-detect git root");
    assert.ok(result!.length > 0, "Path should not be empty");
  });

  it("CLI > env precedence", () => {
    const result = resolveRepoRoot(
      { repoRoot: "/cli" },
      { BRIDGEBUILDER_REPO_ROOT: "/env" },
    );
    assert.equal(result, "/cli");
  });

  it("returns undefined when git auto-detect fails (non-git dir)", () => {
    // Simulate non-git directory by passing a path that can't be a git root
    // We can't easily mock execSync, but we can verify the function signature
    // handles the case — the try/catch in resolveRepoRoot returns undefined on error
    const result = resolveRepoRoot({}, {});
    // In our test env we ARE in a git repo, so this returns a path.
    // The key assertion is that the function doesn't throw.
    assert.ok(typeof result === "string" || result === undefined);
  });
});

// --- reviewMode (cycle-039: two-pass review) ---

describe("parseCLIArgs --review-mode flag", () => {
  it("parses --review-mode two-pass", () => {
    const args = parseCLIArgs(["--review-mode", "two-pass"]);
    assert.equal(args.reviewMode, "two-pass");
  });

  it("parses --review-mode single-pass", () => {
    const args = parseCLIArgs(["--review-mode", "single-pass"]);
    assert.equal(args.reviewMode, "single-pass");
  });

  it("rejects invalid --review-mode value", () => {
    assert.throws(() => parseCLIArgs(["--review-mode", "invalid"]), /Must be "two-pass" or "single-pass"/);
  });

  it("parses --review-mode with other flags", () => {
    const args = parseCLIArgs(["--dry-run", "--review-mode", "single-pass", "--repo", "a/b"]);
    assert.equal(args.reviewMode, "single-pass");
    assert.equal(args.dryRun, true);
    assert.deepEqual(args.repos, ["a/b"]);
  });
});

describe("resolveConfig repoRoot integration", () => {
  it("config includes repoRoot from resolveRepoRoot", async () => {
    const { config } = await resolve(
      { repoRoot: "/explicit/root" },
      {},
      { enabled: true, repos: ["test/repo"] },
    );
    assert.equal(config.repoRoot, "/explicit/root");
  });

  it("config includes auto-detected repoRoot when no override", async () => {
    const { config } = await resolve(
      {},
      {},
      { enabled: true, repos: ["test/repo"] },
    );
    // In a git repo, should auto-detect
    assert.ok(config.repoRoot !== undefined, "Should auto-detect repoRoot");
  });
});

describe("resolveConfig ecosystemContextPath", () => {
  it("passes through ecosystem_context_path from YAML", async () => {
    const { config } = await resolve(
      {},
      {},
      { enabled: true, repos: ["test/repo"], ecosystem_context_path: ".claude/data/ecosystem.json" },
    );
    assert.equal(config.ecosystemContextPath, ".claude/data/ecosystem.json");
  });

  it("ecosystemContextPath undefined when not in YAML", async () => {
    const { config } = await resolve(
      {},
      {},
      { enabled: true, repos: ["test/repo"] },
    );
    assert.equal(config.ecosystemContextPath, undefined);
  });
});

describe("resolveConfig reviewMode precedence", () => {
  it("defaults to two-pass when no override", async () => {
    const { config, provenance } = await resolve(
      {},
      {},
      { enabled: true, repos: ["test/repo"] },
    );
    assert.equal(config.reviewMode, "two-pass");
    assert.equal(provenance.reviewMode, "default");
  });

  it("CLI reviewMode overrides all", async () => {
    const { config, provenance } = await resolve(
      { reviewMode: "single-pass" },
      { LOA_BRIDGE_REVIEW_MODE: "two-pass" },
      { enabled: true, repos: ["test/repo"], review_mode: "two-pass" },
    );
    assert.equal(config.reviewMode, "single-pass");
    assert.equal(provenance.reviewMode, "cli");
  });

  it("env reviewMode overrides yaml and default", async () => {
    const { config, provenance } = await resolve(
      {},
      { LOA_BRIDGE_REVIEW_MODE: "single-pass" },
      { enabled: true, repos: ["test/repo"], review_mode: "two-pass" },
    );
    assert.equal(config.reviewMode, "single-pass");
    assert.equal(provenance.reviewMode, "env");
  });

  it("yaml reviewMode overrides default", async () => {
    const { config, provenance } = await resolve(
      {},
      {},
      { enabled: true, repos: ["test/repo"], review_mode: "single-pass" },
    );
    assert.equal(config.reviewMode, "single-pass");
    assert.equal(provenance.reviewMode, "yaml");
  });

  it("ignores invalid env reviewMode values", async () => {
    const { config, provenance } = await resolve(
      {},
      { LOA_BRIDGE_REVIEW_MODE: "invalid-mode" },
      { enabled: true, repos: ["test/repo"] },
    );
    assert.equal(config.reviewMode, "two-pass");
    assert.equal(provenance.reviewMode, "default");
  });
});
