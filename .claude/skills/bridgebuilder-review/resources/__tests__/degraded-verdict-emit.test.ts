// cycle-118 bd-bb-degraded-verdict-ts — emitDegradedVerdictTrajectory +
// computeVerdictBand coverage.
//
// BB's TS multi-model pipeline must write the SAME degraded-verdict-<date>.jsonl
// record shape the 3 bash gate writers (adversarial-review.sh / red-team /
// flatline via degraded-verdict-lib.sh) emit, into the SAME date-sharded
// trajectory channel, when its aggregate verdict band is DEGRADED/FAILED.
// A clean (all-APPROVED / no-envelope) run writes nothing.
//
// Case matrix ported from tests/unit/degraded-verdict-lib.bats (DVL1-9),
// envelope fixtures modeled on cheval-delegate-verdict-quality.test.ts.
// No ajv is installed in this skill, so shape is asserted field-by-field
// (schema-library validation is degraded-verdict-schema.bats's separate job).

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync, existsSync, readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";

import {
  computeVerdictBand,
  emitDegradedVerdictTrajectory,
  type DegradedVerdictRecord,
} from "../core/multi-model-pipeline.js";

// The 7 fields degraded-verdict.schema.json allows (additionalProperties:false).
const SCHEMA_FIELDS = new Set([
  "gate",
  "verdict_band",
  "degradation_reason",
  "degraded_legs",
  "model_exit_code",
  "sprint_id",
  "ts",
]);

const ITEM = { owner: "0xHoneyJar", repo: "loa", pr: { number: 1234 } };

function approvedEnvelope() {
  return {
    status: "APPROVED" as const,
    consensus_outcome: "consensus" as const,
    truncation_waiver_applied: false,
    voices_planned: 1,
    voices_succeeded: 1,
    voices_succeeded_ids: ["claude-opus-4-8"],
    voices_dropped: [],
    chain_health: "ok" as const,
    confidence_floor: "low" as const,
    rationale: "single-voice cheval invoke",
    single_voice_call: true,
  };
}

// DEGRADED with an EMPTY voices_dropped — the chain-walked-to-fallback case
// (chain_health degraded, no formal drop). Real, already-tested code path.
function degradedNoDropEnvelope() {
  return {
    ...approvedEnvelope(),
    status: "DEGRADED" as const,
    voices_succeeded_ids: ["claude-opus-4-7"],
    chain_health: "degraded" as const,
    rationale: "chain walked to fallback (claude-opus-4-7)",
  };
}

function degradedWithDropEnvelope() {
  return {
    ...approvedEnvelope(),
    status: "DEGRADED" as const,
    voices_succeeded: 0,
    voices_succeeded_ids: [],
    voices_dropped: [
      {
        voice: "gpt-5.5-pro",
        reason: "EmptyContent",
        exit_code: 7,
        blocker_risk: "med" as const,
      },
    ],
    chain_health: "degraded" as const,
  };
}

function failedEnvelope() {
  return {
    ...approvedEnvelope(),
    status: "FAILED" as const,
    voices_succeeded: 0,
    voices_succeeded_ids: [],
    voices_dropped: [
      {
        voice: "gemini-3.1-pro",
        reason: "ChainExhausted",
        exit_code: 12,
        blocker_risk: "high" as const,
        chain_walk: [],
      },
    ],
    chain_health: "exhausted" as const,
  };
}

// Run body with a fresh temp trajectory dir wired via LOA_DEGRADED_VERDICT_DIR,
// returning the parsed records written (if any). Mirrors the bats suite's
// per-test isolation discipline.
async function withTempDir<T>(
  fn: (dir: string) => Promise<T>,
): Promise<{ result: T; dir: string }> {
  const dir = mkdtempSync(join(tmpdir(), "bb-degraded-verdict-"));
  const prev = process.env.LOA_DEGRADED_VERDICT_DIR;
  process.env.LOA_DEGRADED_VERDICT_DIR = dir;
  try {
    const result = await fn(dir);
    return { result, dir };
  } finally {
    if (prev === undefined) delete process.env.LOA_DEGRADED_VERDICT_DIR;
    else process.env.LOA_DEGRADED_VERDICT_DIR = prev;
    rmSync(dir, { recursive: true, force: true });
  }
}

function readRecords(dir: string): DegradedVerdictRecord[] {
  const files = readdirSync(dir).filter((f) => f.startsWith("degraded-verdict-") && f.endsWith(".jsonl"));
  const out: DegradedVerdictRecord[] = [];
  for (const f of files) {
    const body = readFileSync(join(dir, f), "utf8").trim();
    if (!body) continue;
    for (const line of body.split("\n")) out.push(JSON.parse(line) as DegradedVerdictRecord);
  }
  return out;
}

function assertSchemaShape(rec: DegradedVerdictRecord): void {
  // additionalProperties:false — every key must be one of the 7 allowed.
  for (const k of Object.keys(rec)) {
    assert.ok(SCHEMA_FIELDS.has(k), `unexpected field "${k}" (schema is additionalProperties:false)`);
  }
  // required: [gate, verdict_band, sprint_id, ts]
  assert.equal(typeof rec.gate, "string");
  assert.ok(rec.gate.length > 0);
  assert.ok(rec.verdict_band === "DEGRADED" || rec.verdict_band === "FAILED");
  assert.equal(typeof rec.sprint_id, "string");
  assert.ok(rec.sprint_id.length > 0);
  assert.equal(typeof rec.ts, "string");
  assert.match(rec.ts, /^\d{4}-\d{2}-\d{2}T/);
  assert.equal(typeof rec.degradation_reason, "string");
  // model_exit_code: integer | null
  assert.ok(rec.model_exit_code === null || Number.isInteger(rec.model_exit_code));
  // degraded_legs: when present, non-empty array of strings (minItems:1)
  if (rec.degraded_legs !== undefined) {
    assert.ok(Array.isArray(rec.degraded_legs) && rec.degraded_legs.length >= 1);
    for (const leg of rec.degraded_legs) assert.equal(typeof leg, "string");
  }
}

describe("computeVerdictBand", () => {
  it("returns null for empty input", () => {
    assert.equal(computeVerdictBand([]), null);
  });

  it("returns null when no envelopes carry verdictQuality", () => {
    assert.equal(computeVerdictBand([{}, {}]), null);
  });

  it("returns APPROVED when every voice is APPROVED with ok chain", () => {
    assert.equal(
      computeVerdictBand([{ verdictQuality: approvedEnvelope() }, { verdictQuality: approvedEnvelope() }]),
      "APPROVED",
    );
  });

  it("returns DEGRADED when one voice degraded", () => {
    assert.equal(
      computeVerdictBand([{ verdictQuality: approvedEnvelope() }, { verdictQuality: degradedNoDropEnvelope() }]),
      "DEGRADED",
    );
  });

  it("returns FAILED when any voice failed", () => {
    assert.equal(
      computeVerdictBand([{ verdictQuality: approvedEnvelope() }, { verdictQuality: failedEnvelope() }]),
      "FAILED",
    );
  });

  it("returns DEGRADED when some voices are missing envelopes (partial cohort)", () => {
    assert.equal(
      computeVerdictBand([{ verdictQuality: approvedEnvelope() }, {}]),
      "DEGRADED",
    );
  });
});

describe("emitDegradedVerdictTrajectory", () => {
  it("writes NO record for an all-APPROVED run", async () => {
    const { dir } = await withTempDir(async () => {
      await emitDegradedVerdictTrajectory(ITEM, [
        { verdictQuality: approvedEnvelope() },
        { verdictQuality: approvedEnvelope() },
      ]);
      return null;
    });
    assert.equal(existsSync(dir) ? readRecords(dir).length : 0, 0, "APPROVED must emit nothing");
  });

  it("writes NO record when no verdictQuality envelopes present", async () => {
    const { result } = await withTempDir(async (dir) => {
      await emitDegradedVerdictTrajectory(ITEM, [{}, {}]);
      return readRecords(dir).length;
    });
    assert.equal(result, 0);
  });

  it("writes a schema-valid FAILED record with degraded_legs from the dropped voice", async () => {
    const { result } = await withTempDir(async (dir) => {
      await emitDegradedVerdictTrajectory(ITEM, [
        { verdictQuality: approvedEnvelope() },
        { verdictQuality: failedEnvelope() },
      ]);
      return readRecords(dir);
    });
    assert.equal(result.length, 1);
    const rec = result[0];
    assertSchemaShape(rec);
    assert.equal(rec.verdict_band, "FAILED");
    assert.equal(rec.gate, "bridgebuilder:multi-model");
    assert.equal(rec.sprint_id, "0xHoneyJar/loa#1234");
    assert.equal(rec.degradation_reason, "ChainExhausted");
    assert.equal(rec.model_exit_code, 12);
    assert.deepEqual(rec.degraded_legs, ["gemini-3.1-pro"]);
  });

  it("writes a schema-valid DEGRADED record and uses the first dropped voice's reason/exit_code", async () => {
    const { result } = await withTempDir(async (dir) => {
      await emitDegradedVerdictTrajectory(ITEM, [{ verdictQuality: degradedWithDropEnvelope() }]);
      return readRecords(dir);
    });
    assert.equal(result.length, 1);
    const rec = result[0];
    assertSchemaShape(rec);
    assert.equal(rec.verdict_band, "DEGRADED");
    assert.equal(rec.degradation_reason, "EmptyContent");
    assert.equal(rec.model_exit_code, 7);
    assert.deepEqual(rec.degraded_legs, ["gpt-5.5-pro"]);
  });

  it("omits degraded_legs and falls back to unknown/null on DEGRADED with empty voices_dropped", async () => {
    const { result } = await withTempDir(async (dir) => {
      await emitDegradedVerdictTrajectory(ITEM, [{ verdictQuality: degradedNoDropEnvelope() }]);
      return readRecords(dir);
    });
    assert.equal(result.length, 1);
    const rec = result[0];
    assertSchemaShape(rec);
    assert.equal(rec.verdict_band, "DEGRADED");
    assert.equal(rec.degradation_reason, "unknown");
    assert.equal(rec.model_exit_code, null);
    assert.equal(rec.degraded_legs, undefined, "degraded_legs must be omitted, not []");
    assert.ok(!("degraded_legs" in rec), "empty-drop record must not carry a degraded_legs key");
  });

  it("flattens degraded_legs across multiple per-model results", async () => {
    const { result } = await withTempDir(async (dir) => {
      await emitDegradedVerdictTrajectory(ITEM, [
        { verdictQuality: degradedWithDropEnvelope() },
        { verdictQuality: failedEnvelope() },
      ]);
      return readRecords(dir);
    });
    assert.equal(result.length, 1);
    const rec = result[0];
    assertSchemaShape(rec);
    // Band is FAILED (failedEnvelope present); legs collected from BOTH.
    assert.equal(rec.verdict_band, "FAILED");
    assert.deepEqual(rec.degraded_legs, ["gpt-5.5-pro", "gemini-3.1-pro"]);
    // First dropped voice across the flattened list drives reason/exit_code.
    assert.equal(rec.degradation_reason, "EmptyContent");
    assert.equal(rec.model_exit_code, 7);
  });

  it("honors an explicit gate override", async () => {
    const { result } = await withTempDir(async (dir) => {
      await emitDegradedVerdictTrajectory(
        ITEM,
        [{ verdictQuality: failedEnvelope() }],
        { gate: "bridgebuilder:custom-mode" },
      );
      return readRecords(dir);
    });
    assert.equal(result[0].gate, "bridgebuilder:custom-mode");
  });

  it("writes to the date-sharded filename", async () => {
    const { dir } = await withTempDir(async (d) => {
      await emitDegradedVerdictTrajectory(ITEM, [{ verdictQuality: failedEnvelope() }]);
      const shard = new Date().toISOString().slice(0, 10);
      assert.ok(
        existsSync(join(d, `degraded-verdict-${shard}.jsonl`)),
        `expected degraded-verdict-${shard}.jsonl`,
      );
      return null;
    });
    void dir;
  });

  it("never throws when the target directory is unwritable", async () => {
    const prev = process.env.LOA_DEGRADED_VERDICT_DIR;
    // A path under an existing regular file cannot be mkdir'd — write fails,
    // emitter must swallow it.
    process.env.LOA_DEGRADED_VERDICT_DIR = "/dev/null/nope";
    try {
      await emitDegradedVerdictTrajectory(ITEM, [{ verdictQuality: failedEnvelope() }]);
    } finally {
      if (prev === undefined) delete process.env.LOA_DEGRADED_VERDICT_DIR;
      else process.env.LOA_DEGRADED_VERDICT_DIR = prev;
    }
    // Reaching here without a throw is the assertion.
    assert.ok(true);
  });
});
