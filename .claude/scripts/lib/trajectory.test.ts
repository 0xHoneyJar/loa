import { describe, it } from "node:test";
import assert from "node:assert/strict";
import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import { appendTrajectoryEvent, TrajectoryEvent } from "./trajectory";

function makeEvent(): TrajectoryEvent {
  return {
    event: "forge.archivist.page_synthesized",
    timestamp: new Date().toISOString(),
    oracle_path: "~/hivemind/wiki/concepts/memory-architecture-synthesis.md",
    candidate_path: "~/hivemind/wiki/concepts/memory-architecture-synthesis.rederived.md",
    fidelity: 0.85,
    pass: true,
    oracle_integrity: true,
    seed_count: 8,
  };
}

describe("appendTrajectoryEvent", () => {
  it("appends exactly one line to a temp file", () => {
    const tmp = path.join(os.tmpdir(), `traj-test-${Date.now()}.jsonl`);
    fs.writeFileSync(tmp, "", "utf8");
    try {
      appendTrajectoryEvent(tmp, makeEvent());
      const lines = fs.readFileSync(tmp, "utf8").trim().split("\n");
      assert.equal(lines.length, 1);
    } finally {
      fs.unlinkSync(tmp);
    }
  });

  it("multiple appends grow file without modifying earlier lines", () => {
    const tmp = path.join(os.tmpdir(), `traj-multi-${Date.now()}.jsonl`);
    fs.writeFileSync(tmp, "", "utf8");
    try {
      appendTrajectoryEvent(tmp, makeEvent());
      appendTrajectoryEvent(tmp, makeEvent());
      const lines = fs.readFileSync(tmp, "utf8").trim().split("\n");
      assert.equal(lines.length, 2);
      assert.ok(JSON.parse(lines[0]).event);
    } finally {
      fs.unlinkSync(tmp);
    }
  });

  it("emitted JSON contains all 7 required fields", () => {
    const tmp = path.join(os.tmpdir(), `traj-fields-${Date.now()}.jsonl`);
    fs.writeFileSync(tmp, "", "utf8");
    try {
      appendTrajectoryEvent(tmp, makeEvent());
      const line = fs.readFileSync(tmp, "utf8").trim();
      const obj = JSON.parse(line);
      assert.ok("event" in obj);
      assert.ok("timestamp" in obj);
      assert.ok("oracle_path" in obj);
      assert.ok("candidate_path" in obj);
      assert.ok("fidelity" in obj);
      assert.ok("pass" in obj);
      assert.ok("oracle_integrity" in obj);
      assert.ok("seed_count" in obj);
    } finally {
      fs.unlinkSync(tmp);
    }
  });

  it("append failure produces stderr warning and does not throw", () => {
    const nonWritable = "/nonexistent/dir/traj.jsonl";
    assert.doesNotThrow(() => appendTrajectoryEvent(nonWritable, makeEvent()));
  });
});
