// cycle-109 Sprint 2 T2.6 — ChevalDelegateAdapter verdict_quality sidecar
// + PR-comment header rendering.
//
// CONSUMER #4 per SDD §3.2.3 IMP-004. The adapter spawns cheval which
// produces a verdict_quality envelope via the LOA_VERDICT_QUALITY_SIDECAR
// transport (T2.4). The adapter reads the sidecar after cheval returns
// and attaches the envelope to ReviewResponse.verdictQuality so the
// multi-model pipeline can render it in the PR-comment header (FR-2.8).

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import { PassThrough } from "node:stream";
import { writeFileSync, mkdtempSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import type { ChildProcess } from "node:child_process";

import { ChevalDelegateAdapter } from "../adapters/cheval-delegate.js";

interface FakeProcessScript {
  stdout?: string;
  stderr?: string;
  exitCode?: number | null;
  /**
   * If set, the fake spawn writes this JSON envelope to the path read from
   * env.LOA_VERDICT_QUALITY_SIDECAR (mirrors cheval's T2.3 finally-block
   * behavior). When null, the sidecar is NOT written (simulates legacy
   * cheval or build-error path).
   */
  sidecarEnvelope?: object | null;
}

interface SpawnCall {
  command: string;
  args: string[];
  env: NodeJS.ProcessEnv | undefined;
}

function makeFakeSpawn(script: FakeProcessScript, calls: SpawnCall[]) {
  return ((command: string, args: readonly string[], opts: { env?: NodeJS.ProcessEnv } = {}) => {
    calls.push({ command, args: [...args], env: opts.env });

    // cycle-109 T2.6: emulate cheval's sidecar write at finally time. The
    // adapter MUST export LOA_VERDICT_QUALITY_SIDECAR in the env it passes
    // to spawn; the fake honors that by writing the fixture envelope to
    // the path BEFORE emitting `close`. This pins the contract that the
    // adapter reads the sidecar AFTER cheval returns.
    const sidecarPath = opts.env?.LOA_VERDICT_QUALITY_SIDECAR;
    if (sidecarPath && script.sidecarEnvelope !== null && script.sidecarEnvelope !== undefined) {
      try {
        writeFileSync(sidecarPath, JSON.stringify(script.sidecarEnvelope));
      } catch {
        // Ignore — tests intentionally exercise the no-sidecar case
      }
    }

    const proc = new EventEmitter() as ChildProcess & EventEmitter & {
      exitCode: number | null;
      signalCode: NodeJS.Signals | null;
      kill: (sig?: NodeJS.Signals) => boolean;
    };
    const stdout = new PassThrough();
    const stderr = new PassThrough();
    proc.stdout = stdout as unknown as ChildProcess["stdout"];
    proc.stderr = stderr as unknown as ChildProcess["stderr"];
    proc.exitCode = null;
    proc.signalCode = null;
    proc.kill = () => true;

    setImmediate(() => {
      if (script.stdout) stdout.write(script.stdout);
      if (script.stderr) stderr.write(script.stderr);
      stdout.end();
      stderr.end();
      proc.exitCode = script.exitCode ?? 0;
      proc.emit("close", script.exitCode ?? 0, null);
    });

    return proc;
  }) as unknown as typeof import("node:child_process").spawn;
}

function makeAdapter(script: FakeProcessScript, calls: SpawnCall[]) {
  return new ChevalDelegateAdapter({
    model: "anthropic:claude-opus-4-7",
    timeoutMs: 5_000,
    chevalScript: "/tmp/fake-cheval.py",
    pythonBin: "/tmp/fake-python3",
    spawnFn: makeFakeSpawn(script, calls),
  });
}

const baseRequest = {
  systemPrompt: "You are a code reviewer.",
  userPrompt: "Review this PR diff: ...",
  maxOutputTokens: 4_000,
};

const successStdout = JSON.stringify({
  content: "## Summary\nLooks good.",
  model: "claude-opus-4-7",
  provider: "anthropic",
  usage: { input_tokens: 1500, output_tokens: 200 },
  latency_ms: 8421,
});

const approvedEnvelope = {
  status: "APPROVED",
  consensus_outcome: "consensus",
  truncation_waiver_applied: false,
  voices_planned: 1,
  voices_succeeded: 1,
  voices_succeeded_ids: ["claude-opus-4-7"],
  voices_dropped: [],
  chain_health: "ok",
  confidence_floor: "low",
  rationale: "single-voice cheval invoke (voice=claude-opus-4-7)",
  single_voice_call: true,
};

const degradedEnvelope = {
  status: "DEGRADED",
  consensus_outcome: "consensus",
  truncation_waiver_applied: false,
  voices_planned: 1,
  voices_succeeded: 1,
  voices_succeeded_ids: ["claude-opus-4-6"],
  voices_dropped: [],
  chain_health: "degraded",
  confidence_floor: "low",
  rationale: "chain walked to fallback (claude-opus-4-6)",
  single_voice_call: true,
};

describe("ChevalDelegateAdapter — verdict_quality sidecar (T2.6)", () => {
  it("exports LOA_VERDICT_QUALITY_SIDECAR in spawn env", async () => {
    const calls: SpawnCall[] = [];
    const adapter = makeAdapter(
      { stdout: successStdout, exitCode: 0, sidecarEnvelope: approvedEnvelope },
      calls,
    );
    await adapter.generateReview(baseRequest);
    assert.equal(calls.length, 1);
    const env = calls[0]!.env;
    assert.ok(env, "spawn env must be set");
    const sidecar = env!["LOA_VERDICT_QUALITY_SIDECAR"];
    assert.ok(
      typeof sidecar === "string" && sidecar.length > 0,
      `LOA_VERDICT_QUALITY_SIDECAR must be set in spawn env; got ${sidecar}`,
    );
  });

  it("sidecar path is unique per spawn (parallel-safe)", async () => {
    const calls1: SpawnCall[] = [];
    const adapter1 = makeAdapter(
      { stdout: successStdout, exitCode: 0, sidecarEnvelope: approvedEnvelope },
      calls1,
    );
    await adapter1.generateReview(baseRequest);

    const calls2: SpawnCall[] = [];
    const adapter2 = makeAdapter(
      { stdout: successStdout, exitCode: 0, sidecarEnvelope: approvedEnvelope },
      calls2,
    );
    await adapter2.generateReview(baseRequest);

    const path1 = calls1[0]!.env?.["LOA_VERDICT_QUALITY_SIDECAR"];
    const path2 = calls2[0]!.env?.["LOA_VERDICT_QUALITY_SIDECAR"];
    assert.notEqual(path1, path2, "sidecar paths MUST be unique per call");
  });

  it("attaches verdict_quality envelope to ReviewResponse", async () => {
    const adapter = makeAdapter(
      { stdout: successStdout, exitCode: 0, sidecarEnvelope: approvedEnvelope },
      [],
    );
    const result = await adapter.generateReview(baseRequest);
    assert.ok(result.verdictQuality, "ReviewResponse.verdictQuality must be set");
    assert.equal(result.verdictQuality!.status, "APPROVED");
    assert.equal(result.verdictQuality!.chain_health, "ok");
    assert.equal(result.verdictQuality!.voices_succeeded, 1);
  });

  it("attaches DEGRADED envelope when chain walked", async () => {
    const adapter = makeAdapter(
      { stdout: successStdout, exitCode: 0, sidecarEnvelope: degradedEnvelope },
      [],
    );
    const result = await adapter.generateReview(baseRequest);
    assert.ok(result.verdictQuality);
    assert.equal(result.verdictQuality!.status, "DEGRADED");
    assert.equal(result.verdictQuality!.chain_health, "degraded");
  });

  it("ReviewResponse.verdictQuality is undefined when sidecar not written (legacy cheval)", async () => {
    const adapter = makeAdapter(
      // sidecarEnvelope: null → fake does NOT write the sidecar file,
      // simulating a pre-T2.3 cheval that doesn't honor the env var.
      { stdout: successStdout, exitCode: 0, sidecarEnvelope: null },
      [],
    );
    const result = await adapter.generateReview(baseRequest);
    assert.equal(
      result.verdictQuality,
      undefined,
      "verdictQuality must be undefined when sidecar is absent",
    );
  });

  it("does not throw when sidecar file contains malformed JSON", async () => {
    // Simulate a partially-written sidecar (e.g., cheval crashed mid-write).
    const calls: SpawnCall[] = [];
    const customSpawn = ((command: string, args: readonly string[], opts: { env?: NodeJS.ProcessEnv } = {}) => {
      calls.push({ command, args: [...args], env: opts.env });
      const sidecarPath = opts.env?.LOA_VERDICT_QUALITY_SIDECAR;
      if (sidecarPath) {
        writeFileSync(sidecarPath, "not-json {");
      }
      const proc = new EventEmitter() as ChildProcess & EventEmitter & {
        exitCode: number | null; signalCode: NodeJS.Signals | null;
        kill: (sig?: NodeJS.Signals) => boolean;
      };
      const stdout = new PassThrough();
      const stderr = new PassThrough();
      proc.stdout = stdout as unknown as ChildProcess["stdout"];
      proc.stderr = stderr as unknown as ChildProcess["stderr"];
      proc.exitCode = null;
      proc.signalCode = null;
      proc.kill = () => true;
      setImmediate(() => {
        stdout.write(successStdout);
        stdout.end();
        stderr.end();
        proc.exitCode = 0;
        proc.emit("close", 0, null);
      });
      return proc;
    }) as unknown as typeof import("node:child_process").spawn;

    const adapter = new ChevalDelegateAdapter({
      model: "anthropic:claude-opus-4-7",
      timeoutMs: 5_000,
      chevalScript: "/tmp/fake-cheval.py",
      pythonBin: "/tmp/fake-python3",
      spawnFn: customSpawn,
    });
    // Must NOT throw on malformed sidecar — fail-soft is the contract.
    const result = await adapter.generateReview(baseRequest);
    assert.equal(result.verdictQuality, undefined,
      "malformed sidecar JSON must result in undefined verdictQuality, not a throw");
  });
});

describe("formatVerdictQualityHeader — PR-comment surface (T2.6)", () => {
  // The renderer is imported lazily here so the test file doesn't fail to
  // LOAD when the export is missing (commit-1 RED state). Subsequent runs
  // resolve the import after commit-2 lands the helper.
  async function renderer() {
    const mod = await import("../core/multi-model-pipeline.js") as {
      formatVerdictQualityHeader?: (verdicts: Array<{ provider: string; modelId: string; verdictQuality?: object }>) => string;
    };
    return mod.formatVerdictQualityHeader;
  }

  it("renders APPROVED header when all voices succeeded with ok chain", async () => {
    const r = await renderer();
    assert.ok(r, "formatVerdictQualityHeader must be exported from multi-model-pipeline");
    const out = r!([
      { provider: "anthropic", modelId: "claude-opus-4-7", verdictQuality: approvedEnvelope },
      { provider: "openai", modelId: "gpt-5.5-pro", verdictQuality: approvedEnvelope },
      { provider: "google", modelId: "gemini-3.1-pro", verdictQuality: approvedEnvelope },
    ]);
    assert.match(out, /APPROVED/);
    assert.match(out, /3\/3/);
  });

  it("renders DEGRADED header when at least one voice walked / failed", async () => {
    const r = await renderer();
    assert.ok(r);
    const out = r!([
      { provider: "anthropic", modelId: "claude-opus-4-7", verdictQuality: approvedEnvelope },
      { provider: "openai", modelId: "gpt-5.5-pro", verdictQuality: degradedEnvelope },
      { provider: "google", modelId: "gemini-3.1-pro", verdictQuality: approvedEnvelope },
    ]);
    assert.match(out, /DEGRADED/);
  });

  it("renders FAILED header when any voice carries FAILED status", async () => {
    const r = await renderer();
    assert.ok(r);
    const failedEnvelope = {
      ...approvedEnvelope,
      status: "FAILED",
      voices_succeeded: 0,
      voices_succeeded_ids: [],
      voices_dropped: [
        { voice: "gpt-5.5-pro", reason: "ChainExhausted", exit_code: 12,
          blocker_risk: "high", chain_walk: [] },
      ],
      chain_health: "exhausted",
    };
    const out = r!([
      { provider: "anthropic", modelId: "claude-opus-4-7", verdictQuality: approvedEnvelope },
      { provider: "openai", modelId: "gpt-5.5-pro", verdictQuality: failedEnvelope },
    ]);
    assert.match(out, /FAILED/);
  });

  it("returns empty string when no verdictQuality envelopes available", async () => {
    const r = await renderer();
    assert.ok(r);
    const out = r!([
      { provider: "anthropic", modelId: "claude-opus-4-7" },  // no verdictQuality
      { provider: "openai", modelId: "gpt-5.5-pro" },
    ]);
    assert.equal(out, "", "header must be empty when no envelopes available");
  });

  it("returns empty string for empty input list", async () => {
    const r = await renderer();
    assert.ok(r);
    assert.equal(r!([]), "");
  });
});
