import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import { describe, it, expect, vi } from "vitest";
import type { IRecoverySource } from "../recovery/recovery-source.js";
import { CircuitBreaker } from "../circuit-breaker.js";
import { RecoveryEngine, type RecoveryState } from "../recovery/recovery-engine.js";
import { TemplateRecoverySource } from "../recovery/sources/template-source.js";
import { WALManager } from "../wal/wal-manager.js";

describe("Integration: Checkpoint failure → Recovery cascade", () => {
  it("falls through to template fallback when mount source fails", async () => {
    // Simulate: mount source unavailable, git source fails, template succeeds
    const failingMount: IRecoverySource = {
      name: "mount",
      isAvailable: vi.fn().mockResolvedValue(false),
      restore: vi.fn(),
    };

    const failingGit: IRecoverySource = {
      name: "git",
      isAvailable: vi.fn().mockResolvedValue(true),
      restore: vi.fn().mockResolvedValue(null), // Returns null = failure
    };

    const templates = new Map([
      ["BEAUVOIR.md", Buffer.from("# BEAUVOIR\n\nDefault identity.")],
      ["NOTES.md", Buffer.from("# NOTES\n")],
    ]);
    const templateSource = new TemplateRecoverySource(templates);

    const events: string[] = [];
    const engine = new RecoveryEngine({
      sources: [failingMount, failingGit, templateSource],
      onEvent: (e) => events.push(e),
    });

    const result = await engine.run();

    // Template fallback should succeed
    expect(result.state).toBe("RUNNING");
    expect(result.source).toBe("template");
    expect(result.files?.get("BEAUVOIR.md")?.toString()).toContain("BEAUVOIR");

    // Mount was unavailable, so its restore() should not have been called
    expect(failingMount.restore).not.toHaveBeenCalled();
    // Git was tried and failed
    expect(failingGit.restore).toHaveBeenCalled();

    // Events should show the cascade
    expect(events).toContain("source_unavailable");
    expect(events).toContain("restored");
  });

  it("enters DEGRADED when ALL sources fail, then recovers on next try", async () => {
    let gitAvailable = false;

    const failingMount: IRecoverySource = {
      name: "mount",
      isAvailable: vi.fn().mockResolvedValue(false),
      restore: vi.fn(),
    };

    const gitSource: IRecoverySource = {
      name: "git",
      isAvailable: vi.fn().mockImplementation(async () => gitAvailable),
      restore: vi.fn().mockResolvedValue(new Map([["BEAUVOIR.md", Buffer.from("# BEAUVOIR")]])),
    };

    const engine = new RecoveryEngine({
      sources: [failingMount, gitSource],
    });

    // First attempt: all fail
    const first = await engine.run();
    expect(first.state).toBe("DEGRADED");

    // Git becomes available
    gitAvailable = true;

    // Second attempt: git succeeds
    const second = await engine.run();
    expect(second.state).toBe("RUNNING");
    expect(second.source).toBe("git");
  });
});

describe("Integration: WAL with high-volume replay", () => {
  let tmpDir: string;

  it("handles 1000 entries with replay pagination", async () => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "wal-integration-"));
    const walDir = path.join(tmpDir, "wal");

    const wal = new WALManager({
      walDir,
      maxSegmentSize: 10 * 1024 * 1024,
      maxSegmentAge: 60 * 60 * 1000,
      maxSegments: 10,
    });

    await wal.initialize();

    // Append 1000 entries sequentially
    for (let i = 0; i < 1000; i++) {
      await wal.append(
        "write",
        `data/file-${i}.json`,
        Buffer.from(JSON.stringify({ index: i, value: `data-${i}` })),
      );
    }

    // Replay all
    const entries: number[] = [];
    await wal.replay(async (entry) => {
      if (entry.data) {
        const parsed = JSON.parse(Buffer.from(entry.data, "base64").toString());
        entries.push(parsed.index);
      }
    });

    expect(entries).toHaveLength(1000);
    // Verify ordering (first should be 0, last 999)
    expect(entries[0]).toBe(0);
    expect(entries[entries.length - 1]).toBe(999);

    // Verify sinceSeq pagination
    const laterEntries = await wal.getEntriesSince(990);
    expect(laterEntries.length).toBe(10);

    // Cleanup
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });
});

describe("Integration: CircuitBreaker + RecoveryEngine coordination", () => {
  it("circuit breaker state feeds into recovery decisions", async () => {
    let clock = 0;
    const cb = new CircuitBreaker(
      { maxFailures: 2, resetTimeMs: 1000, halfOpenRetries: 1 },
      { onStateChange: () => {}, now: () => clock },
    );

    // Open circuit breaker
    cb.recordFailure();
    cb.recordFailure();
    expect(cb.getState()).toBe("OPEN");

    // Recovery engine with circuit-breaker-aware source
    const cbAwareSource: IRecoverySource = {
      name: "cb-aware",
      isAvailable: vi.fn().mockImplementation(async () => cb.getState() !== "OPEN"),
      restore: vi.fn().mockResolvedValue(new Map([["data.json", Buffer.from("{}")]])),
    };

    const templates = new Map([["fallback.txt", Buffer.from("fallback")]]);
    const templateSource = new TemplateRecoverySource(templates);

    const engine = new RecoveryEngine({
      sources: [cbAwareSource, templateSource],
    });

    // While circuit is OPEN, cb-aware source is unavailable → template fallback
    const result1 = await engine.run();
    expect(result1.source).toBe("template");

    // Wait for reset → HALF_OPEN
    clock += 1001;
    expect(cb.getState()).toBe("HALF_OPEN");

    // Now cb-aware source is available
    const result2 = await engine.run();
    expect(result2.source).toBe("cb-aware");
  });
});
