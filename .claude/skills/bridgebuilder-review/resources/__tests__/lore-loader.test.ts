/**
 * lore-loader.test.ts — coverage for #464 A5 (lore active weaving wiring).
 *
 * Verifies the loader handles all the degraded-input scenarios that previously
 * would have caused either a no-op (silent miss) or a hard crash, and produces
 * valid LoreEntry[] for well-formed input.
 */
import { describe, it, beforeEach, afterEach, before } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { execFileSync } from "node:child_process";
import { loadLoreEntries, DEFAULT_LORE_PATH } from "../core/lore-loader.js";
import type { ILogger } from "../ports/logger.js";

/**
 * Bridgebuilder pass-1 FIND-007: lore-loader uses `yq` to convert YAML→JSON.
 * Skip the suite (with a clear message) when yq is not installed instead of
 * failing with an opaque execFile error. yq is a hard prerequisite of the
 * Loa framework, but CI containers / fresh dev machines may not have it.
 */
let yqAvailable = false;
before(() => {
  try {
    execFileSync("yq", ["--version"], { stdio: "ignore" });
    yqAvailable = true;
  } catch {
    yqAvailable = false;
  }
});

class CapturingLogger implements ILogger {
  warns: Array<{ msg: string; ctx?: unknown }> = [];
  infos: Array<string> = [];
  errors: Array<{ msg: string; ctx?: unknown }> = [];
  info(msg: string) { this.infos.push(msg); }
  warn(msg: string, ctx?: unknown) { this.warns.push({ msg, ctx }); }
  error(msg: string, ctx?: unknown) { this.errors.push({ msg, ctx }); }
  debug() {}
}

describe("lore-loader", () => {
  let tmpDir: string;
  let logger: CapturingLogger;

  beforeEach((t) => {
    if (!yqAvailable) {
      t.skip("yq not installed — install with `brew install yq` (macOS) or `apt install yq` (Debian/Ubuntu)");
      return;
    }
    tmpDir = mkdtempSync(join(tmpdir(), "lore-loader-test-"));
    logger = new CapturingLogger();
  });

  afterEach(() => {
    rmSync(tmpDir, { recursive: true, force: true });
  });

  it("DEFAULT_LORE_PATH points at grimoires/loa/lore/patterns.yaml", () => {
    assert.equal(DEFAULT_LORE_PATH, "grimoires/loa/lore/patterns.yaml");
  });

  it("returns [] with a warning when the file is missing", async () => {
    const entries = await loadLoreEntries(join(tmpDir, "no-such-file.yaml"), logger);
    assert.deepEqual(entries, []);
    assert.ok(logger.warns.some((w) => w.msg.includes("not found")));
  });

  it("returns [] with a warning when the file is empty", async () => {
    const path = join(tmpDir, "empty.yaml");
    writeFileSync(path, "");
    const entries = await loadLoreEntries(path, logger);
    assert.deepEqual(entries, []);
    assert.ok(logger.warns.some((w) => w.msg.includes("empty")));
  });

  it("parses a well-formed lore YAML with multiple entries", async () => {
    const path = join(tmpDir, "patterns.yaml");
    writeFileSync(path, `
- id: governance-isomorphism
  term: Governance Isomorphism
  short: |
    Multi-perspective evaluation with fail-closed semantics.
  context: |
    The same pattern appears in Flatline, Red Team, and HoneyJar vault governance.
  source:
    cycle: cycle-046
    bridge_iteration: "PR #429"
    date: "2026-02-28"
  tags:
    - governance
    - flatline
    - red-team

- id: kaironic-termination
  term: Kaironic Termination
  short: |
    Iterate until convergence, not until a counter expires.
  context: |
    Loop terminates when actionable_high == 0 AND blocker_count == 0.
  tags:
    - convergence
    - bridgebuilder
`);
    const entries = await loadLoreEntries(path, logger);
    assert.equal(entries.length, 2);
    assert.equal(entries[0].id, "governance-isomorphism");
    assert.equal(entries[0].term, "Governance Isomorphism");
    assert.equal(entries[0].source, "cycle-046, PR #429, 2026-02-28");
    assert.deepEqual(entries[0].tags, ["governance", "flatline", "red-team"]);
    assert.equal(entries[1].id, "kaironic-termination");
    assert.equal(entries[1].source, undefined);
    assert.deepEqual(entries[1].tags, ["convergence", "bridgebuilder"]);
  });

  it("skips entries missing required fields and warns per skip", async () => {
    const path = join(tmpDir, "mixed.yaml");
    writeFileSync(path, `
- id: valid-one
  term: Valid Entry
  short: short text
  context: long context

- id: missing-context
  term: Missing Context
  short: short text
  # context: ABSENT

- id: just-id
  # missing term, short, context
`);
    const entries = await loadLoreEntries(path, logger);
    assert.equal(entries.length, 1);
    assert.equal(entries[0].id, "valid-one");
    // Two skips logged
    assert.equal(logger.warns.filter((w) => w.msg.includes("missing required field")).length, 2);
  });

  it("returns [] when YAML top-level is not an array", async () => {
    const path = join(tmpDir, "scalar.yaml");
    writeFileSync(path, "just a string");
    const entries = await loadLoreEntries(path, logger);
    assert.deepEqual(entries, []);
    assert.ok(logger.warns.some((w) => w.msg.includes("Expected top-level YAML array")));
  });

  it("throws with an actionable message on malformed YAML", async () => {
    const path = join(tmpDir, "broken.yaml");
    // YAML with a hard syntax error: unclosed quote and tab indentation
    writeFileSync(path, "- id: 'unclosed\n\ttab_indent: true");
    await assert.rejects(
      () => loadLoreEntries(path, logger),
      /Failed to convert YAML/,
    );
  });

  it("accepts string-form source field unchanged", async () => {
    const path = join(tmpDir, "str-source.yaml");
    writeFileSync(path, `
- id: x
  term: X
  short: s
  context: c
  source: "Inline source string"
`);
    const entries = await loadLoreEntries(path, logger);
    assert.equal(entries.length, 1);
    assert.equal(entries[0].source, "Inline source string");
  });
});
