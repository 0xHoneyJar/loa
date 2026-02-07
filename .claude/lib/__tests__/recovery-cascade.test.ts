import { describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  RecoveryCascade,
  createRecoveryCascade,
  type IRecoverySource,
} from "../sync/recovery-cascade.js";
import { LoaLibError } from "../errors.js";

// ── Helpers ──────────────────────────────────────────

function makeSource(
  name: string,
  priority: number,
  opts: {
    available?: boolean;
    data?: unknown;
    valid?: boolean;
    restoreDelay?: number;
    throwOnRestore?: boolean;
  } = {},
): IRecoverySource {
  const {
    available = true,
    data = { restored: true },
    valid,
    restoreDelay = 0,
    throwOnRestore = false,
  } = opts;

  return {
    name,
    priority,
    async isAvailable() { return available; },
    async restore() {
      if (restoreDelay > 0) {
        await new Promise((r) => setTimeout(r, restoreDelay));
      }
      if (throwOnRestore) throw new Error(`${name} restore failed`);
      return data;
    },
    ...(valid !== undefined
      ? { validate: async () => valid }
      : {}),
  };
}

describe("RecoveryCascade (T3.3)", () => {
  it("createRecoveryCascade returns a RecoveryCascade", () => {
    const cascade = createRecoveryCascade([]);
    assert.ok(cascade instanceof RecoveryCascade);
  });

  it("selects highest-priority available source", async () => {
    const sources = [
      makeSource("low", 10, { data: "low-data" }),
      makeSource("high", 1, { data: "high-data" }),
      makeSource("mid", 5, { data: "mid-data" }),
    ];
    const result = await createRecoveryCascade(sources).run();
    assert.equal(result.sourceUsed, "high");
    assert.equal(result.data, "high-data");
  });

  it("skips unavailable sources", async () => {
    const sources = [
      makeSource("unavail", 1, { available: false }),
      makeSource("avail", 2, { data: "good" }),
    ];
    const result = await createRecoveryCascade(sources).run();
    assert.equal(result.sourceUsed, "avail");
    assert.equal(result.attempts.length, 2);
    assert.equal(result.attempts[0].success, false);
  });

  it("skips source that fails validation", async () => {
    const sources = [
      makeSource("invalid", 1, { valid: false }),
      makeSource("valid", 2, { data: "ok" }),
    ];
    const result = await createRecoveryCascade(sources).run();
    assert.equal(result.sourceUsed, "valid");
    assert.equal(result.attempts[0].error, "validation failed");
  });

  it("passes validation when validate returns true", async () => {
    const sources = [
      makeSource("checked", 1, { data: "verified", valid: true }),
    ];
    const result = await createRecoveryCascade(sources).run();
    assert.equal(result.sourceUsed, "checked");
    assert.equal(result.data, "verified");
  });

  it("skips source that throws on restore", async () => {
    const sources = [
      makeSource("broken", 1, { throwOnRestore: true }),
      makeSource("fallback", 2, { data: "ok" }),
    ];
    const result = await createRecoveryCascade(sources).run();
    assert.equal(result.sourceUsed, "fallback");
    assert.ok(result.attempts[0].error?.includes("restore failed"));
  });

  it("throws SYN_001 when all sources fail", async () => {
    const sources = [
      makeSource("a", 1, { available: false }),
      makeSource("b", 2, { throwOnRestore: true }),
    ];
    await assert.rejects(
      () => createRecoveryCascade(sources).run(),
      (err: LoaLibError) => err.code === "SYN_001",
    );
  });

  it("throws SYN_001 on empty sources", async () => {
    await assert.rejects(
      () => createRecoveryCascade([]).run(),
      (err: LoaLibError) => err.code === "SYN_001",
    );
  });

  it("per-source timeout enforced", async () => {
    const sources = [
      makeSource("slow", 1, { restoreDelay: 200, data: "late" }),
      makeSource("fast", 2, { data: "quick" }),
    ];
    const result = await createRecoveryCascade(sources, {
      perSourceTimeoutMs: 50,
    }).run();
    assert.equal(result.sourceUsed, "fast");
    assert.ok(result.attempts[0].error?.includes("timed out"));
  });

  it("total budget enforced", async () => {
    let clock = 0;
    const sources = [
      makeSource("s1", 1, { restoreDelay: 10 }),
      makeSource("s2", 2, { data: "never" }),
    ];
    // Override s1 to consume budget via clock
    sources[0].restore = async () => {
      clock += 100;
      throw new Error("fail");
    };
    const result = await assert.rejects(
      () => createRecoveryCascade(sources, {
        totalBudgetMs: 50,
        now: () => clock,
      }).run(),
      (err: LoaLibError) => err.code === "SYN_001",
    );
  });

  it("FR-5.1: WAL corrupt, R2 available → R2 selected", async () => {
    const sources = [
      makeSource("wal", 1, { throwOnRestore: true }),
      makeSource("r2", 2, { data: { from: "r2" } }),
    ];
    const result = await createRecoveryCascade(sources).run();
    assert.equal(result.sourceUsed, "r2");
    assert.deepEqual(result.data, { from: "r2" });
  });

  it("records attempt durations", async () => {
    const sources = [makeSource("src", 1, { data: "ok" })];
    const result = await createRecoveryCascade(sources).run();
    assert.equal(result.attempts.length, 1);
    assert.equal(typeof result.attempts[0].durationMs, "number");
    assert.equal(typeof result.totalDurationMs, "number");
  });
});
