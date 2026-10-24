// cycle-129 Sprint 3 Task 3.4 (SDD D-7.7, DEC-0150): the completion banner counts the voices whose result completed, and a
// DEGRADED consensus exits bridgebuilder.exit_on_degraded (default 3; 0 restores the old exit) after the JSON is written.
import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { decideExitCode, degradedWarnLine, summarizeVoices, totalVoices } from "../core/run-outcome.js";
import type { MultiModelReviewResult } from "../core/multi-model-pipeline.js";

type MR = MultiModelReviewResult["modelResults"][number];

function ok(provider: string, model: string, status?: string): MR {
  return {
    provider, model, posted: false,
    response: {
      content: "", inputTokens: 1, outputTokens: 1, model,
      ...(status ? { verdictQuality: { status, voices_planned: 1, voices_succeeded: 1, chain_health: "ok" } } : {}),
    } as MR["response"],
  };
}
function failed(provider: string, model: string): MR {
  return {
    provider, model, posted: false,
    error: { code: "PROVIDER_ERROR", message: "boom", category: "transient", retryable: true, source: "llm" } as MR["error"],
  };
}

describe("voice outcome and exit code (D-7.7)", () => {
  it("all planned voices completed and approved: not degraded, exit 0", () => {
    const o = summarizeVoices({
      modelResults: [ok("anthropic", "opus", "APPROVED"), ok("openai", "gpt-5.5", "APPROVED")],
      voicesPlanned: ["anthropic/opus", "openai/gpt-5.5"],
    });
    assert.deepEqual(o, { planned: 2, completed: 2, band: "APPROVED", incomplete: [], degraded: false });
    assert.equal(decideExitCode(o.degraded, 3), 0);
  });

  it("a failed voice: completed < planned, the voice named, DEGRADED exits 3 (and 0 under the rollback key)", () => {
    const o = summarizeVoices({
      modelResults: [ok("anthropic", "opus", "APPROVED"), failed("openai", "gpt-5.5")],
      voicesPlanned: ["anthropic/opus", "openai/gpt-5.5"],
    });
    assert.equal(o.completed, 1);
    assert.equal(o.planned, 2);
    assert.deepEqual(o.incomplete, ["openai/gpt-5.5"]);
    assert.equal(o.degraded, true);
    assert.equal(decideExitCode(o.degraded, 3), 3);
    assert.equal(decideExitCode(o.degraded, 0), 0);
  });

  it("a planned voice that never ran (missing key, graceful mode) counts as incomplete", () => {
    const o = summarizeVoices({
      modelResults: [ok("anthropic", "opus")],
      voicesPlanned: ["anthropic/opus", "google/gemini-3-pro"],
    });
    assert.equal(o.completed, 1);
    assert.equal(o.planned, 2);
    assert.deepEqual(o.incomplete, ["google/gemini-3-pro"]);
    assert.equal(o.degraded, true);
  });

  it("every voice completed but the verdict-quality band is DEGRADED: still degraded", () => {
    const o = summarizeVoices({
      modelResults: [ok("anthropic", "opus", "APPROVED"), ok("openai", "gpt-5.5", "DEGRADED")],
      voicesPlanned: ["anthropic/opus", "openai/gpt-5.5"],
    });
    assert.equal(o.completed, 2);
    assert.equal(o.band, "DEGRADED");
    assert.equal(o.degraded, true);
    assert.equal(decideExitCode(o.degraded, 3), 3);
  });

  it("legacy envelopes (no verdictQuality) with every voice complete are not degraded", () => {
    const o = summarizeVoices({ modelResults: [ok("anthropic", "opus"), ok("openai", "gpt-5.5")] });
    assert.equal(o.band, null);
    assert.equal(o.degraded, false);
    assert.equal(o.planned, 2);
  });

  it("totals sum across items; the WARN line names the voices and the exit", () => {
    const a = summarizeVoices({ modelResults: [ok("anthropic", "opus", "APPROVED")], voicesPlanned: ["anthropic/opus"] });
    const b = summarizeVoices({ modelResults: [ok("anthropic", "opus", "APPROVED"), failed("openai", "gpt-5.5")], voicesPlanned: ["anthropic/opus", "openai/gpt-5.5"] });
    const t = totalVoices([a, b]);
    assert.deepEqual(t, { completed: 2, planned: 3, degraded: true, incomplete: ["openai/gpt-5.5"] });
    const line = degradedWarnLine(t, [a.band, b.band], 3);
    // (b's band is DEGRADED: one of its voices carried no envelope)
    assert.equal(line, "[bridgebuilder] WARN: DEGRADED — 2/3 voices completed; incomplete voices: openai/gpt-5.5; verdict quality: DEGRADED (exit 3; bridgebuilder.exit_on_degraded)");
    assert.equal(totalVoices([]).degraded, false);
  });
});

describe("main.ts wiring (D-7.7)", () => {
  const here = dirname(fileURLToPath(import.meta.url));
  const src = readFileSync(join(here, "..", "main.ts"), "utf8");

  it("passes the completed count, not the configured count, to reportComplete", () => {
    assert.ok(!/reportComplete\([^)]*config\.multiModel\.models\.length/.test(src), "the configured count is gone");
    assert.match(src, /progress\.reportComplete\(Date\.now\(\) - now\.getTime\(\), totals\.completed, totals\.planned\)/);
  });

  it("sets the exit code from exit_on_degraded only after the JSON is printed", () => {
    const json = src.indexOf('mode: "multi-model"');
    const exit = src.indexOf("process.exitCode = exitCode");
    assert.ok(json > 0 && exit > json, "the JSON precedes the exit code");
    assert.match(src, /decideExitCode\(totals\.degraded, trusted\.exitOnDegraded\)/);
  });
});

describe("main.ts wiring (cycle-133 C-1/C-2: a named degradation exits exit_on_degraded)", () => {
  const here = dirname(fileURLToPath(import.meta.url));
  const src = readFileSync(join(here, "..", "main.ts"), "utf8");

  it("multi-model: named degradations make the run DEGRADED before the exit code is decided", () => {
    const merge = src.indexOf("if (degradedReasons.length > 0) totals.degraded = true;");
    const decide = src.indexOf("decideExitCode(totals.degraded, trusted.exitOnDegraded)");
    assert.ok(merge > 0 && decide > merge, "the merge precedes the decision");
    assert.match(src, /degraded_reason: mmResult\.reviewVerdict\.degradedReason/);
    assert.match(src, /coverage: item\.coverage/);
  });

  it("single-model: printSummary sets exit_on_degraded for a named degradation and prints the reasons", () => {
    assert.match(src, /printSummary\(summary, trusted\.exitOnDegraded\)/);
    assert.match(src, /if \(degradedReasons\.length > 0 && summary\.errors === 0\) process\.exitCode = decideExitCode\(true, exitOnDegraded\);/);
    assert.match(src, /degraded_reasons: degradedReasons/);
  });
});
