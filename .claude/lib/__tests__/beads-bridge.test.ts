import { describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  BeadsBridge,
  createBeadsBridge,
  type BrExecutor,
  type Bead,
} from "../bridge/beads-bridge.js";

// ── Mock Executor ────────────────────────────────────

function mockExecutor(
  responses: Map<string, { stdout: string; stderr: string; exitCode: number }>,
): BrExecutor {
  return {
    async exec(args, _opts) {
      const key = args.join(" ");
      for (const [pattern, result] of responses) {
        if (key.includes(pattern)) return result;
      }
      return { stdout: "", stderr: `Unknown command: ${key}`, exitCode: 1 };
    },
  };
}

const SAMPLE_BEAD: Bead = {
  id: "task-123",
  title: "Test task",
  type: "task",
  status: "open",
  priority: 2,
  labels: ["sprint:1"],
  created_at: "2026-01-15T10:00:00Z",
  updated_at: "2026-01-15T12:00:00Z",
};

describe("BeadsBridge (T3.1)", () => {
  // ── Factory ─────────────────────────────────────────

  it("createBeadsBridge returns a BeadsBridge", () => {
    const exec = mockExecutor(new Map());
    const bridge = createBeadsBridge({}, exec);
    assert.ok(bridge instanceof BeadsBridge);
  });

  // ── Health Check ────────────────────────────────────

  it("healthCheck returns healthy with version", async () => {
    const exec = mockExecutor(new Map([
      ["--version", { stdout: "beads_rust 0.5.0\n", stderr: "", exitCode: 0 }],
    ]));
    const bridge = createBeadsBridge({}, exec);
    const result = await bridge.healthCheck();
    assert.equal(result.healthy, true);
    assert.equal(result.version, "beads_rust 0.5.0");
  });

  it("FR-4.2: healthCheck returns unhealthy when binary not found", async () => {
    const exec = mockExecutor(new Map([
      ["--version", { stdout: "", stderr: "", exitCode: 127 }],
    ]));
    const bridge = createBeadsBridge({}, exec);
    const result = await bridge.healthCheck();
    assert.equal(result.healthy, false);
    assert.equal(result.reason, "binary_not_found");
  });

  it("healthCheck returns unhealthy on non-zero exit", async () => {
    const exec = mockExecutor(new Map([
      ["--version", { stdout: "", stderr: "error", exitCode: 1 }],
    ]));
    const bridge = createBeadsBridge({}, exec);
    const result = await bridge.healthCheck();
    assert.equal(result.healthy, false);
    assert.ok(result.reason?.includes("exit_code"));
  });

  // ── List ────────────────────────────────────────────

  it("FR-4.1: list returns typed Bead[]", async () => {
    const exec = mockExecutor(new Map([
      ["list --json", { stdout: JSON.stringify([SAMPLE_BEAD]), stderr: "", exitCode: 0 }],
    ]));
    const bridge = createBeadsBridge({}, exec);
    const beads = await bridge.list();
    assert.equal(beads.length, 1);
    assert.equal(beads[0].id, "task-123");
    assert.equal(beads[0].status, "open");
  });

  // ── Ready ───────────────────────────────────────────

  it("ready returns unblocked beads", async () => {
    const exec = mockExecutor(new Map([
      ["ready --json", { stdout: JSON.stringify([SAMPLE_BEAD]), stderr: "", exitCode: 0 }],
    ]));
    const bridge = createBeadsBridge({}, exec);
    const beads = await bridge.ready();
    assert.equal(beads.length, 1);
  });

  // ── Get ─────────────────────────────────────────────

  it("get returns a single bead", async () => {
    const exec = mockExecutor(new Map([
      ["show task-123 --json", { stdout: JSON.stringify(SAMPLE_BEAD), stderr: "", exitCode: 0 }],
    ]));
    const bridge = createBeadsBridge({}, exec);
    const bead = await bridge.get("task-123");
    assert.equal(bead.id, "task-123");
  });

  // ── Update ──────────────────────────────────────────

  it("update sends correct arguments", async () => {
    let capturedArgs: string[] = [];
    const exec: BrExecutor = {
      async exec(args) {
        capturedArgs = args;
        return { stdout: "", stderr: "", exitCode: 0 };
      },
    };
    const bridge = createBeadsBridge({}, exec);
    await bridge.update("task-123", { status: "in_progress", priority: 1 });
    assert.ok(capturedArgs.includes("update"));
    assert.ok(capturedArgs.includes("task-123"));
    assert.ok(capturedArgs.includes("--status"));
    assert.ok(capturedArgs.includes("in_progress"));
    assert.ok(capturedArgs.includes("--priority"));
    assert.ok(capturedArgs.includes("1"));
  });

  // ── Close ───────────────────────────────────────────

  it("close sends correct arguments", async () => {
    let capturedArgs: string[] = [];
    const exec: BrExecutor = {
      async exec(args) {
        capturedArgs = args;
        return { stdout: "", stderr: "", exitCode: 0 };
      },
    };
    const bridge = createBeadsBridge({}, exec);
    await bridge.close("task-123", "Done");
    assert.ok(capturedArgs.includes("close"));
    assert.ok(capturedArgs.includes("task-123"));
    assert.ok(capturedArgs.includes("--reason"));
    assert.ok(capturedArgs.includes("Done"));
  });

  // ── Sync ────────────────────────────────────────────

  it("sync calls br sync", async () => {
    let called = false;
    const exec: BrExecutor = {
      async exec(args) {
        if (args.includes("sync")) called = true;
        return { stdout: "", stderr: "", exitCode: 0 };
      },
    };
    const bridge = createBeadsBridge({}, exec);
    await bridge.sync();
    assert.equal(called, true);
  });

  // ── Input Validation (BRG_005) ──────────────────────

  it("rejects invalid ID", async () => {
    const exec = mockExecutor(new Map());
    const bridge = createBeadsBridge({}, exec);
    await assert.rejects(
      () => bridge.get("../../../etc/passwd"),
      (err: Error) => err.message.includes("Invalid bead ID"),
    );
  });

  it("rejects invalid status", async () => {
    const exec = mockExecutor(new Map());
    const bridge = createBeadsBridge({}, exec);
    await assert.rejects(
      () => bridge.update("task-1", { status: "invalid" }),
      (err: Error) => err.message.includes("Invalid status"),
    );
  });

  it("rejects out-of-range priority", async () => {
    const exec = mockExecutor(new Map());
    const bridge = createBeadsBridge({}, exec);
    await assert.rejects(
      () => bridge.update("task-1", { priority: 99 }),
      (err: Error) => err.message.includes("Invalid priority"),
    );
  });

  it("rejects too-long reason", async () => {
    const exec = mockExecutor(new Map());
    const bridge = createBeadsBridge({}, exec);
    await assert.rejects(
      () => bridge.close("task-1", "x".repeat(1025)),
      (err: Error) => err.message.includes("Reason too long"),
    );
  });

  // ── Error Mapping ───────────────────────────────────

  it("maps exit code 127 to BRG_001", async () => {
    const exec = mockExecutor(new Map([
      ["list --json", { stdout: "", stderr: "", exitCode: 127 }],
    ]));
    const bridge = createBeadsBridge({}, exec);
    await assert.rejects(
      () => bridge.list(),
      (err: Error) => err.message.includes("not found"),
    );
  });

  it("maps timeout to BRG_002", async () => {
    const exec = mockExecutor(new Map([
      ["list --json", { stdout: "", stderr: "", exitCode: -1 }],
    ]));
    const bridge = createBeadsBridge({}, exec);
    await assert.rejects(
      () => bridge.list(),
      (err: Error) => err.message.includes("timed out"),
    );
  });

  it("maps parse error to BRG_003", async () => {
    const exec = mockExecutor(new Map([
      ["list --json", { stdout: "not json{", stderr: "", exitCode: 0 }],
    ]));
    const bridge = createBeadsBridge({}, exec);
    await assert.rejects(
      () => bridge.list(),
      (err: Error) => err.message.includes("parse"),
    );
  });

  it("maps other exit codes to BRG_004", async () => {
    const exec = mockExecutor(new Map([
      ["list --json", { stdout: "", stderr: "some error", exitCode: 2 }],
    ]));
    const bridge = createBeadsBridge({}, exec);
    await assert.rejects(
      () => bridge.list(),
      (err: Error) => err.message.includes("exit 2"),
    );
  });

  // ── Write Serialization ─────────────────────────────

  it("write operations are serialized (not concurrent)", async () => {
    const order: string[] = [];
    let resolveFirst!: () => void;
    const firstPromise = new Promise<void>((r) => { resolveFirst = r; });

    const exec: BrExecutor = {
      async exec(args) {
        const cmd = args[0];
        order.push(`${cmd}-start`);
        if (cmd === "close") {
          await firstPromise;
        }
        order.push(`${cmd}-end`);
        return { stdout: "", stderr: "", exitCode: 0 };
      },
    };

    const bridge = createBeadsBridge({}, exec);

    // Fire two writes concurrently
    const p1 = bridge.close("task-1");
    const p2 = bridge.sync();

    // Let first write complete after a delay
    await new Promise((r) => setTimeout(r, 20));
    resolveFirst();

    await p1;
    await p2;

    // close should fully complete before sync starts
    assert.equal(order[0], "close-start");
    assert.equal(order[1], "close-end");
    assert.equal(order[2], "sync-start");
    assert.equal(order[3], "sync-end");
  });
});
