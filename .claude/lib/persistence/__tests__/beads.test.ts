import { describe, it, expect, vi, beforeEach } from "vitest";
import { BeadsRecoveryHandler, type IShellExecutor } from "../beads/beads-recovery.js";
import {
  BeadsWALAdapter,
  type IBeadsWAL,
  type IBeadsWALEntry,
  type BeadWALEntry,
} from "../beads/beads-wal-adapter.js";

// ── Mock WAL ───────────────────────────────────────────────

function createMockWAL(): IBeadsWAL & {
  entries: { operation: string; path: string; data?: Buffer }[];
  seq: number;
} {
  const entries: { operation: string; path: string; data?: Buffer }[] = [];
  let seq = 0;

  return {
    entries,
    seq,
    async append(operation: string, path: string, data?: Buffer) {
      seq++;
      entries.push({ operation, path, data });
      return seq;
    },
    async replay(visitor: (entry: IBeadsWALEntry) => void | Promise<void>) {
      for (const e of entries) {
        await visitor({
          operation: e.operation,
          path: e.path,
          data: e.data?.toString("base64"),
        });
      }
    },
    getStatus() {
      return { seq };
    },
  };
}

// ── Mock Shell ─────────────────────────────────────────────

function createMockShell(): IShellExecutor & { commands: string[] } {
  const commands: string[] = [];
  return {
    commands,
    async exec(cmd: string) {
      commands.push(cmd);
      return { stdout: "", stderr: "" };
    },
  };
}

describe("BeadsWALAdapter", () => {
  let wal: ReturnType<typeof createMockWAL>;
  let adapter: BeadsWALAdapter;

  beforeEach(() => {
    wal = createMockWAL();
    adapter = new BeadsWALAdapter(wal, { pathPrefix: ".beads/wal" });
  });

  it("records a transition and returns sequence number", async () => {
    const seq = await adapter.recordTransition({
      operation: "create",
      beadId: "bead-123",
      payload: { title: "Test bead", type: "task" },
    });

    expect(seq).toBe(1);
    expect(wal.entries).toHaveLength(1);
    expect(wal.entries[0].path).toContain(".beads/wal/bead-123/");
    expect(wal.entries[0].operation).toBe("write");
  });

  it("replays entries with checksum verification", async () => {
    await adapter.recordTransition({
      operation: "create",
      beadId: "bead-1",
      payload: { title: "First" },
    });
    await adapter.recordTransition({
      operation: "update",
      beadId: "bead-1",
      payload: { status: "done" },
    });

    const entries = await adapter.replay();

    expect(entries).toHaveLength(2);
    expect(entries[0].operation).toBe("create");
    expect(entries[1].operation).toBe("update");
  });

  it("rejects invalid beadId with path traversal chars", async () => {
    await expect(
      adapter.recordTransition({
        operation: "create",
        beadId: "../etc/passwd",
        payload: { title: "malicious" },
      }),
    ).rejects.toThrow("Invalid beadId");
  });

  it("rejects invalid operation type", async () => {
    await expect(
      adapter.recordTransition({
        operation: "rm -rf" as any,
        beadId: "bead-1",
        payload: {},
      }),
    ).rejects.toThrow("Invalid operation");
  });
});

describe("BeadsRecoveryHandler", () => {
  let wal: ReturnType<typeof createMockWAL>;
  let adapter: BeadsWALAdapter;
  let shell: ReturnType<typeof createMockShell>;

  beforeEach(() => {
    wal = createMockWAL();
    adapter = new BeadsWALAdapter(wal);
    shell = createMockShell();
  });

  it("recovers by replaying WAL entries through br CLI", async () => {
    // Record transitions
    await adapter.recordTransition({
      operation: "create",
      beadId: "bead-1",
      payload: { title: "Test task", type: "task", priority: 2 },
    });
    await adapter.recordTransition({
      operation: "label",
      beadId: "bead-1",
      payload: { action: "add", labels: ["ready"] },
    });

    const handler = new BeadsRecoveryHandler(adapter, { skipSync: true }, shell);
    const result = await handler.recover();

    expect(result.success).toBe(true);
    expect(result.entriesReplayed).toBe(2);
    expect(result.beadsAffected).toContain("bead-1");
    expect(shell.commands).toHaveLength(2);
    expect(shell.commands[0]).toContain("create");
    expect(shell.commands[1]).toContain("label add");
  });

  it("shell-escapes all user values", async () => {
    await adapter.recordTransition({
      operation: "create",
      beadId: "bead-1",
      payload: { title: "O'Reilly book's test; rm -rf /", type: "task", priority: 2 },
    });

    const handler = new BeadsRecoveryHandler(adapter, { skipSync: true }, shell);
    await handler.recover();

    // The title should be shell-escaped with single-quote wrapping
    const cmd = shell.commands[0];
    // Verify single quotes are escaped with '\'' idiom
    expect(cmd).toContain("'\\''");
    // Verify the command uses br create with properly quoted argument
    expect(cmd).toMatch(/^br create '/);
  });

  it("enforces operation and update key whitelists", async () => {
    await adapter.recordTransition({
      operation: "update",
      beadId: "bead-1",
      payload: { title: "New title", malicious_key: "dropped" },
    });

    const handler = new BeadsRecoveryHandler(adapter, { skipSync: true }, shell);
    await handler.recover();

    // Only whitelisted keys should appear in command
    const cmd = shell.commands[0];
    expect(cmd).toContain("--title");
    expect(cmd).not.toContain("malicious_key");
  });

  it("returns empty result when no WAL entries", async () => {
    const handler = new BeadsRecoveryHandler(adapter, { skipSync: true }, shell);
    const result = await handler.recover();

    expect(result.success).toBe(true);
    expect(result.entriesReplayed).toBe(0);
    expect(result.beadsAffected).toEqual([]);
    expect(shell.commands).toHaveLength(0);
  });
});
