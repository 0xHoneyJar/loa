import { describe, it } from "node:test";
import assert from "node:assert/strict";
import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import { initState } from "./state";

function tmpStatePath(): string {
  return path.join(os.tmpdir(), `archivist-state-test-${Date.now()}-${Math.random().toString(36).slice(2)}.json`);
}

describe("initState", () => {
  it("creates bootstrapped file when absent", () => {
    const p = tmpStatePath();
    try {
      const state = initState(p);
      assert.ok(fs.existsSync(p));
      assert.equal(state.version, 1);
      assert.equal(state.mode, "bootstrapped");
      assert.deepEqual(state.active_digests, []);
      assert.equal(state.last_ingest_cursor, null);
      assert.ok(typeof state.initialized_at === "string");
    } finally {
      if (fs.existsSync(p)) fs.unlinkSync(p);
    }
  });

  it("returns existing valid state without overwriting", () => {
    const p = tmpStatePath();
    const existing = {
      version: 1,
      mode: "incremental",
      active_digests: ["abc"],
      last_ingest_cursor: "2026-01-01T00:00:00.000Z",
      initialized_at: "2026-01-01T00:00:00.000Z",
    };
    fs.writeFileSync(p, JSON.stringify(existing), "utf8");
    try {
      const state = initState(p);
      assert.equal(state.mode, "incremental");
      assert.deepEqual(state.active_digests, ["abc"]);
      const raw = fs.readFileSync(p, "utf8");
      assert.equal(JSON.parse(raw).mode, "incremental");
    } finally {
      fs.unlinkSync(p);
    }
  });

  it("reinitializes when file contains invalid JSON", () => {
    const p = tmpStatePath();
    fs.writeFileSync(p, "{ this is not valid json }", "utf8");
    try {
      const state = initState(p);
      assert.equal(state.version, 1);
      assert.equal(state.mode, "bootstrapped");
    } finally {
      if (fs.existsSync(p)) fs.unlinkSync(p);
    }
  });

  it("initialized_at is a valid ISO-8601 string", () => {
    const p = tmpStatePath();
    try {
      const state = initState(p);
      const d = new Date(state.initialized_at);
      assert.ok(!isNaN(d.getTime()));
    } finally {
      if (fs.existsSync(p)) fs.unlinkSync(p);
    }
  });
});
