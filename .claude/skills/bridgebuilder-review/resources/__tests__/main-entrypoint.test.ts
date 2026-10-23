// cycle-133 Sprint 1 follow-up a2: importing main.ts must never start a review (persona.test.ts imports it for its
// helpers and, before this guard, ran a live review with read-only `gh` calls against the real repository).
// Every case runs in a subprocess with a fake `gh` on PATH that logs each call, from an empty temporary cwd, so a
// review that starts is observed (a gh call or "[bridgebuilder]" output) without any network.
import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, existsSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

import { isEntrypoint } from "../main.js";

const RESOURCES = join(import.meta.dirname, "..");
const TSX = join(RESOURCES, "..", "node_modules", ".bin", "tsx");

function sandbox() {
  const dir = mkdtempSync(join(tmpdir(), "bb-entry-"));
  const bin = join(dir, "bin");
  const log = join(dir, "gh-calls.log");
  spawnSync("mkdir", ["-p", bin]);
  writeFileSync(join(bin, "gh"), `#!/usr/bin/env bash\necho "$*" >> ${JSON.stringify(log)}\nexit 1\n`);
  chmodSync(join(bin, "gh"), 0o755);
  const env = {
    PATH: `${bin}:${process.env.PATH ?? ""}`, HOME: dir, ANTHROPIC_API_KEY: "fixture-not-a-key",
    BRIDGEBUILDER_REPOS: "fixture-owner/fixture-repo",
  };
  return { dir, log, env, cleanup: () => rmSync(dir, { recursive: true, force: true }) };
}

function run(args: string[], s: ReturnType<typeof sandbox>) {
  return spawnSync(TSX, args, { cwd: s.dir, env: s.env, encoding: "utf8", timeout: 60_000 });
}

describe("main.ts entrypoint guard", () => {
  it("importing main.ts starts no review: no gh call, no output, exit 0", () => {
    const s = sandbox();
    try {
      const probe = join(s.dir, "probe.mts");
      writeFileSync(probe, `await import(${JSON.stringify(pathToFileURL(join(RESOURCES, "main.ts")).href)});\n`);
      const r = run([probe], s);
      assert.equal(existsSync(s.log), false, `gh was spawned: ${existsSync(s.log) ? readFileSync(s.log, "utf8") : ""}`);
      assert.doesNotMatch(r.stderr, /\[bridgebuilder\]/, r.stderr);
      assert.equal(r.status, 0, r.stderr);
    } finally {
      s.cleanup();
    }
  });

  it("run as the entrypoint, main.ts still runs (directly and through a symlink)", () => {
    const s = sandbox();
    try {
      const direct = run([join(RESOURCES, "main.ts"), "--help"], s);
      assert.equal(direct.status, 0, direct.stderr);
      assert.match(direct.stdout, /Usage: bridgebuilder/);
      const link = join(s.dir, "bb-main.ts");
      symlinkSync(join(RESOURCES, "main.ts"), link);
      const viaLink = run([link, "--help"], s);
      assert.match(viaLink.stdout, /Usage: bridgebuilder/, viaLink.stderr);
      // a real run (no --help) reaches the pipeline: it starts, and fails on the fake gh
      const real = run([join(RESOURCES, "main.ts"), "--dry-run"], s);
      assert.match(real.stderr, /\[bridgebuilder\]/);
    } finally {
      s.cleanup();
    }
  });

  it("isEntrypoint compares real paths and refuses a missing argv[1]", () => {
    const url = pathToFileURL(join(RESOURCES, "main.ts")).href;
    assert.equal(isEntrypoint(url, join(RESOURCES, "main.ts")), true);
    assert.equal(isEntrypoint(url, join(RESOURCES, "config.ts")), false);
    assert.equal(isEntrypoint(url, undefined), false);
    assert.equal(isEntrypoint(url, join(RESOURCES, "no-such-file.ts")), false);
  });
});
