import { describe, it, expect, vi } from "vitest";
import type { IRecoverySource } from "../recovery/recovery-source.js";
import {
  ManifestSigner,
  generateKeyPair,
  createManifestSigner,
} from "../recovery/manifest-signer.js";
import { RecoveryEngine, type RecoveryState } from "../recovery/recovery-engine.js";
import { TemplateRecoverySource } from "../recovery/sources/template-source.js";

function makeSource(
  name: string,
  available: boolean,
  files: Map<string, Buffer> | null,
): IRecoverySource {
  return {
    name,
    isAvailable: vi.fn().mockResolvedValue(available),
    restore: vi.fn().mockResolvedValue(files),
  };
}

describe("RecoveryEngine", () => {
  // ── 1. Full Cascade ────────────────────────────────────

  it("cascades through sources until one succeeds", async () => {
    const s1 = makeSource("mount", true, null); // fails
    const s2 = makeSource("git", true, new Map([["a.txt", Buffer.from("ok")]]));
    const s3 = makeSource("template", true, new Map([["t.txt", Buffer.from("fallback")]]));

    const engine = new RecoveryEngine({ sources: [s1, s2, s3] });
    const result = await engine.run();

    expect(result.state).toBe("RUNNING");
    expect(result.source).toBe("git");
    expect(result.files?.size).toBe(1);

    // Template source should not have been called
    expect(s3.restore).not.toHaveBeenCalled();
  });

  // ── 2. Source Failure Fallthrough ──────────────────────

  it("falls through unavailable sources to template", async () => {
    const s1 = makeSource("mount", false, null); // unavailable
    const s2 = makeSource("git", false, null); // unavailable
    const templates = new Map([["default.json", Buffer.from("{}")]]);
    const s3 = new TemplateRecoverySource(templates);

    const engine = new RecoveryEngine({ sources: [s1, s2, s3] });
    const result = await engine.run();

    expect(result.state).toBe("RUNNING");
    expect(result.source).toBe("template");
    expect(result.files?.get("default.json")?.toString()).toBe("{}");
  });

  // ── 3. Loop Detection ─────────────────────────────────

  it("detects recovery loop after N failures in window", async () => {
    let clock = 0;
    const failSource = makeSource("fail", true, null);

    const transitions: [RecoveryState, RecoveryState][] = [];
    const engine = new RecoveryEngine(
      {
        sources: [failSource],
        loopMaxFailures: 3,
        loopWindowMs: 1000,
        onStateChange: (from, to) => transitions.push([from, to]),
      },
      { now: () => clock },
    );

    // Three failures within window
    await engine.run(); // fail 1
    clock += 100;
    await engine.run(); // fail 2
    clock += 100;
    await engine.run(); // fail 3

    // Next attempt should detect loop
    clock += 100;
    const result = await engine.run();
    expect(result.state).toBe("LOOP_DETECTED");
    expect(result.files).toBeNull();
  });

  // ── 4. Degraded Mode ──────────────────────────────────

  it("enters DEGRADED when all sources fail", async () => {
    const s1 = makeSource("mount", true, null);
    const s2 = makeSource("git", true, null);

    const events: string[] = [];
    const engine = new RecoveryEngine({
      sources: [s1, s2],
      onEvent: (e) => events.push(e),
    });

    const result = await engine.run();
    expect(result.state).toBe("DEGRADED");
    expect(events).toContain("all_sources_failed");
  });

  // ── 5. Signature Verification ─────────────────────────

  it("ManifestSigner signs and verifies with Ed25519", () => {
    const { publicKey, privateKey } = generateKeyPair();
    const signer = createManifestSigner(publicKey, privateKey);

    const payload = {
      version: 1,
      createdAt: "2026-02-06T00:00:00Z",
      files: [{ path: "a.txt", checksum: "abc123", size: 100 }],
    };

    const signature = signer.sign(payload);
    expect(signature).toBeTruthy();

    const manifest = { ...payload, signature };
    expect(signer.verify(manifest)).toBe(true);

    // Tampered manifest should fail
    const tampered = { ...manifest, version: 999 };
    expect(signer.verify(tampered)).toBe(false);
  });

  // ── 6. Key Pair Generation ─────────────────────────────

  it("generates valid Ed25519 key pairs", () => {
    const pair = generateKeyPair();

    expect(pair.publicKey).toContain("BEGIN PUBLIC KEY");
    expect(pair.privateKey).toContain("BEGIN PRIVATE KEY");

    // Verify the keys work together
    const signer = createManifestSigner(pair.publicKey, pair.privateKey);
    const payload = {
      version: 1,
      createdAt: new Date().toISOString(),
      files: [],
    };

    const signature = signer.sign(payload);
    expect(signer.verify({ ...payload, signature })).toBe(true);

    // Verify-only signer (no private key)
    const verifier = createManifestSigner(pair.publicKey);
    expect(verifier.verify({ ...payload, signature })).toBe(true);
    expect(() => verifier.sign(payload)).toThrow("Private key required");
  });
});
