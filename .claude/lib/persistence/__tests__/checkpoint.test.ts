import { mkdtempSync, rmSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { verifyManifest } from "../checkpoint/checkpoint-manifest.js";
import { CheckpointProtocol } from "../checkpoint/checkpoint-protocol.js";
import { MountCheckpointStorage } from "../checkpoint/storage-mount.js";

describe("CheckpointProtocol", () => {
  let mountDir: string;
  let storage: MountCheckpointStorage;
  let protocol: CheckpointProtocol;

  beforeEach(() => {
    mountDir = mkdtempSync(join(tmpdir(), "checkpoint-test-"));
    storage = new MountCheckpointStorage(mountDir, "data");
    protocol = new CheckpointProtocol({ storage, staleIntentTimeoutMs: 100 });
  });

  afterEach(() => {
    rmSync(mountDir, { recursive: true, force: true });
  });

  // ── 1. Happy Path ──────────────────────────────────────

  it("completes two-phase checkpoint: begin → finalize → manifest", async () => {
    const files = [
      { relativePath: "state/a.json", content: Buffer.from('{"a":1}') },
      { relativePath: "state/b.json", content: Buffer.from('{"b":2}') },
    ];

    const intentId = await protocol.beginCheckpoint(files);
    expect(intentId).toMatch(/^intent-/);

    const manifest = await protocol.finalizeCheckpoint(intentId, files);
    expect(manifest.version).toBe(1);
    expect(manifest.files).toHaveLength(2);
    expect(manifest.totalSize).toBe(14);
    expect(verifyManifest(manifest)).toBe(true);

    // Second checkpoint increments version
    const manifest2 = await protocol.finalizeCheckpoint(
      await protocol.beginCheckpoint(files),
      files,
    );
    expect(manifest2.version).toBe(2);
  });

  // ── 2. Stale Intent Cleanup ────────────────────────────

  it("cleans stale intents older than timeout", async () => {
    const files = [{ relativePath: "x.txt", content: Buffer.from("data") }];

    // Create an intent but don't finalize
    await protocol.beginCheckpoint(files);

    // Intents should exist
    const intentsBefore = await storage.listFiles("_intents");
    expect(intentsBefore.length).toBe(1);

    // Wait for timeout
    await new Promise((r) => setTimeout(r, 150));

    const cleaned = await protocol.cleanStaleIntents();
    expect(cleaned).toBe(1);

    const intentsAfter = await storage.listFiles("_intents");
    expect(intentsAfter.length).toBe(0);
  });

  // ── 3. Verify Failure ──────────────────────────────────

  it("throws on verification failure when file content changes", async () => {
    const files = [{ relativePath: "critical.json", content: Buffer.from("original") }];

    const intentId = await protocol.beginCheckpoint(files);

    // Tamper with the uploaded file
    await storage.writeFile("critical.json", Buffer.from("tampered"));

    await expect(protocol.finalizeCheckpoint(intentId, files)).rejects.toThrow(
      /Verification failed/,
    );
  });

  // ── 4. Concurrent Intent ───────────────────────────────

  it("handles multiple concurrent intents independently", async () => {
    const files1 = [{ relativePath: "a.txt", content: Buffer.from("a") }];
    const files2 = [{ relativePath: "b.txt", content: Buffer.from("b") }];

    const [intent1, intent2] = await Promise.all([
      protocol.beginCheckpoint(files1),
      protocol.beginCheckpoint(files2),
    ]);

    expect(intent1).not.toBe(intent2);

    // Finalize both
    const m1 = await protocol.finalizeCheckpoint(intent1, files1);
    const m2 = await protocol.finalizeCheckpoint(intent2, files2);

    // Second finalize should have higher version
    expect(m2.version).toBe(m1.version + 1);
  });

  // ── 5. Manifest Versioning ─────────────────────────────

  it("manifest version increments monotonically", async () => {
    const files = [{ relativePath: "v.txt", content: Buffer.from("v1") }];

    for (let i = 1; i <= 5; i++) {
      const intent = await protocol.beginCheckpoint(files);
      const manifest = await protocol.finalizeCheckpoint(intent, files);
      expect(manifest.version).toBe(i);
    }

    const latest = await protocol.getManifest();
    expect(latest?.version).toBe(5);
  });
});
