import { describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  parseCLIArgs,
  resolveConfig,
  resolveRepos,
  formatEffectiveConfig,
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

  it("returns empty args for no input", () => {
    const args = parseCLIArgs([]);
    assert.equal(args.dryRun, undefined);
    assert.equal(args.repos, undefined);
    assert.equal(args.pr, undefined);
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
    assert.equal(config.model, "claude-sonnet-4-5-20250929");
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
    } as any;
    const provenance = { repos: "cli" as const, model: "env" as const, dryRun: "default" as const };
    const output = formatEffectiveConfig(config, provenance);

    assert.ok(output.includes("(cli)"), "Should include repos provenance");
    assert.ok(output.includes("(env)"), "Should include model provenance");
    assert.ok(output.includes("(default)"), "Should include dryRun provenance");
  });

  it("omits provenance annotations when not provided", () => {
    const config = {
      repos: [{ owner: "test", repo: "repo" }],
      model: "claude-sonnet-4-5-20250929",
      maxPrs: 10,
      dryRun: false,
      sanitizerMode: "default" as const,
    } as any;
    const output = formatEffectiveConfig(config);

    assert.ok(!output.includes("(cli)"));
    assert.ok(!output.includes("(env)"));
    assert.ok(!output.includes("(default)"));
  });
});
