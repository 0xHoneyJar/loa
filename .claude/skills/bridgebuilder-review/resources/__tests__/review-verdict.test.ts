import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { summarizeReviewVerdict } from "../core/review-verdict.js";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { scoreFindings } from "../core/scoring.js";
import { composeConsensusReview } from "../core/consensus-findings.js";
import { toolStanceFor } from "../adapters/tool-stance.js";
import { DEFAULT_WRITER_ROLE_ALLOWLIST } from "../core/writer-role.js";
import { decideExitCode } from "../core/run-outcome.js";
import { DEFAULT_EXIT_ON_DEGRADED } from "../config.js";

it("HIGH findings override an APPROVE body", () => {
  const body = 'Verdict: APPROVE\n<!-- bridge-findings-start -->\n```json\n' +
    JSON.stringify({ schema_version: 1, findings: [{ id: "F1", severity: "HIGH", category: "correctness" }] }) +
    '\n```\n<!-- bridge-findings-end -->';
  assert.deepEqual(summarizeReviewVerdict(body), {
    verdict: "REQUEST_CHANGES", highestSeverity: "HIGH", mergeBlocked: true,
  });
});
it("COMMENT, ambiguous and conflicting verdicts do not clear a merge", () => {
  for (const body of ["Verdict: COMMENT", "No errors", "Verdict: APPROVE\nVerdict: COMMENT", "REQUEST_CHANGES"]) {
    assert.equal(summarizeReviewVerdict(body).mergeBlocked, true);
  }
});
it("an explicit APPROVE without blockers can be reported as approval", () => {
  assert.deepEqual(summarizeReviewVerdict("## Verdict\nAPPROVE"), {
    verdict: "APPROVE", highestSeverity: null, mergeBlocked: false,
  });
});
it("malformed structured findings cannot be cleared by an APPROVE label", () => {
  assert.equal(summarizeReviewVerdict("Verdict: APPROVE\n<!-- bridge-findings-start -->invalid").mergeBlocked, true);
});
it("quoted or fenced examples are not explicit approval", () => {
  for (const content of ["```\nVerdict: APPROVE\n```", "> Verdict: APPROVE"]) {
    assert.equal(summarizeReviewVerdict(content).mergeBlocked, true);
  }
});
it("unknown finding severities are ambiguous, not approval", () => {
  const content = 'Verdict: APPROVE\n<!-- bridge-findings-start -->' +
    JSON.stringify({schema_version:1, findings:[{id:"F", severity:"UNRECOGNIZED", category:"bug"}]}) +
    '<!-- bridge-findings-end -->';
  assert.equal(summarizeReviewVerdict(content).mergeBlocked, true);
});

// ── cycle-133 Sprint 1 Task 1.2 (sdd.md C-2, FR-2 AC 3-4, KF-055): the decision table and the PR #1289 replays ──────

const blockOf = (obj: unknown) => "<!-- bridge-findings-start -->\n```json\n" + JSON.stringify(obj) + "\n```\n<!-- bridge-findings-end -->";
const f = (severity: string, extra: Record<string, unknown> = {}) => ({ id: `F-${severity}`, severity, category: "c", file: "a.ts:1", description: "d", ...extra });

describe("verdict decision table (C-2)", () => {
  it("(3) a single valid block with verdict COMMENT and no HIGH-or-above finding → COMMENT, merge not blocked", () => {
    assert.deepEqual(summarizeReviewVerdict(blockOf({ schema_version: 1, verdict: "COMMENT", findings: [f("MEDIUM"), f("LOW")] })), {
      verdict: "COMMENT", highestSeverity: "MEDIUM", mergeBlocked: false,
    });
  });
  it("(1) a block saying COMMENT beside a HIGH finding → REQUEST_CHANGES (the contradiction is recorded as verdict_conflict)", () => {
    const v = summarizeReviewVerdict(blockOf({ schema_version: 1, verdict: "COMMENT", findings: [f("HIGH")] }));
    assert.equal(v.verdict, "REQUEST_CHANGES");
    assert.equal(v.mergeBlocked, true);
    assert.equal(v.degradedReason, "verdict_conflict");
  });
  it("(1) a finding marked blocking: true blocks whatever its severity", () => {
    const v = summarizeReviewVerdict(blockOf({ schema_version: 1, verdict: "REQUEST_CHANGES", findings: [f("LOW", { blocking: true })] }));
    assert.deepEqual([v.verdict, v.mergeBlocked, v.degraded], ["REQUEST_CHANGES", true, undefined]);
  });
  it("(5) two blocks → verdict_conflict, UNKNOWN, merge blocked with the reason", () => {
    const one = blockOf({ schema_version: 1, verdict: "COMMENT", findings: [f("LOW")] });
    const v = summarizeReviewVerdict(one + "\n" + one);
    assert.deepEqual([v.verdict, v.mergeBlocked, v.mergeBlockedReason, v.degradedReason], ["UNKNOWN", true, "verdict_conflict", "verdict_conflict"]);
  });
  it("(5) a malformed block or an unknown block verdict → verdict_conflict", () => {
    for (const body of [blockOf({ schema_version: 1, findings: "nope" }), blockOf({ schema_version: 1, verdict: "LGTM", findings: [] })]) {
      const v = summarizeReviewVerdict(body);
      assert.deepEqual([v.verdict, v.mergeBlockedReason], ["UNKNOWN", "verdict_conflict"]);
    }
  });
  it("(4) no block → the prose rule", () => {
    assert.equal(summarizeReviewVerdict("## Verdict\nAPPROVE").verdict, "APPROVE");
    assert.equal(summarizeReviewVerdict("Verdict: COMMENT").mergeBlocked, true);
  });
  it("INFO, PRAISE, SPECULATION and REFRAME never block", () => {
    const v = summarizeReviewVerdict(blockOf({ schema_version: 1, verdict: "COMMENT", findings: ["INFO", "PRAISE", "SPECULATION", "REFRAME"].map((s) => f(s)) }));
    assert.deepEqual([v.verdict, v.mergeBlocked, v.highestSeverity], ["COMMENT", false, null]);
  });
  it("(2) a guard rejection or incomplete coverage → UNKNOWN, degraded, merge blocked with the reason", () => {
    const body = blockOf({ schema_version: 1, verdict: "COMMENT", findings: [f("MEDIUM")] });
    for (const reason of ["enrichment_guard_rejected", "incomplete_coverage"] as const) {
      const v = summarizeReviewVerdict(body, [], { degradedReasons: [reason] });
      assert.deepEqual([v.verdict, v.mergeBlocked, v.mergeBlockedReason, v.degraded], ["UNKNOWN", true, reason, true]);
    }
  });
});

const FIXTURES = join(import.meta.dirname, "fixtures");
const THRESHOLDS = { high_consensus: 700, disputed_delta: 300, low_value: 400, blocker: 700 };

/** The two voices' blocks and the writer's output, as posted on PR #1289 (record branch, sprint-271 bridgebuilder rounds). */
function round(n: 1 | 2) {
  const body = readFileSync(join(FIXTURES, `pr1289-r${n}-comments.md`), "utf8");
  const voice = (header: string) => {
    const at = body.indexOf(header);
    const m = /<!-- bridge-findings-start -->\s*```json\s*([\s\S]*?)```\s*<!-- bridge-findings-end -->/.exec(body.slice(at));
    return JSON.parse(m![1]).findings;
  };
  const consensusComment = body.slice(body.indexOf("**[3/3] Multi-Model Consensus Review**"));
  const sep = "</details>\n\n---\n\n";
  return {
    body,
    consensus: scoreFindings([
      { provider: "anthropic", model: "claude-headless", findings: voice("**[1/3] Review by anthropic (claude-headless)**") },
      { provider: "openai", model: "gpt-5.5-pro", findings: voice("**[2/3] Review by openai (gpt-5.5-pro)**") },
    ], THRESHOLDS),
    writer: consensusComment.slice(consensusComment.indexOf(sep) + sep.length),
  };
}

describe("PR #1289 round replays (FR-2 AC 4)", () => {
  it("round 1: one valid block, verdict COMMENT, highest MEDIUM → COMMENT, merge not blocked", () => {
    const r = round(1);
    // KF-055: the pre-cycle-133 verdict read the whole posted thread (three blocks) and reported UNKNOWN
    assert.equal(summarizeReviewVerdict(r.body).verdict, "UNKNOWN");
    assert.equal(r.consensus.stats.disputed, 3, "the recomputed consensus matches the posted statistics");
    assert.equal(r.consensus.stats.low_value, 12);
    const out = composeConsensusReview({
      header: "**[3/3] Multi-Model Consensus Review**", consensus: r.consensus,
      writer: { output: r.writer, stance: toolStanceFor("claude-headless"), allowlist: DEFAULT_WRITER_ROLE_ALLOWLIST, label: "anthropic/claude-headless" },
    });
    assert.deepEqual(out.degradedReasons, [], `guard: ${JSON.stringify(out.guard)}`);
    assert.equal(out.guard?.accepted, true);
    assert.deepEqual({ verdict: out.verdict.verdict, mergeBlocked: out.verdict.mergeBlocked, highestSeverity: out.verdict.highestSeverity },
      { verdict: "COMMENT", mergeBlocked: false, highestSeverity: "MEDIUM" });
    assert.equal((out.body.match(/bridge-findings-start/g) ?? []).length, 1, "one block: the one rendered from the consensus");
    assert.match(out.body, /The substrate ate itself again/, "the writer's prose is posted as commentary");
  });

  it("round 2: the writer transcript carries tool-call grammar → the guard rejects, the un-enriched consensus is posted, exit 3", () => {
    const r = round(2);
    const out = composeConsensusReview({
      header: "**[3/3] Multi-Model Consensus Review**", consensus: r.consensus,
      writer: { output: r.writer, stance: toolStanceFor("claude-headless"), allowlist: DEFAULT_WRITER_ROLE_ALLOWLIST, label: "anthropic/claude-headless" },
    });
    assert.equal(out.guard?.accepted, false);
    assert.deepEqual(out.degradedReasons, ["enrichment_guard_rejected"]);
    assert.deepEqual([out.verdict.verdict, out.verdict.mergeBlocked, out.verdict.mergeBlockedReason, out.verdict.highestSeverity],
      ["UNKNOWN", true, "enrichment_guard_rejected", "MEDIUM"]);
    assert.ok(!out.body.includes("<invoke"), "no writer text reaches the posted body");
    assert.equal((out.body.match(/bridge-findings-start/g) ?? []).length, 1);
    assert.equal(decideExitCode(out.verdict.degraded === true, DEFAULT_EXIT_ON_DEGRADED), 3);
  });
});
