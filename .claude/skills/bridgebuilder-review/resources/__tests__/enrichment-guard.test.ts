// cycle-133 Sprint 1 Task 1.2 (sdd.md C-2, FR-2, KF-055): the enrichment writer's output is commentary; the findings
// are rendered from the consensus. The guard rejects writer output that carries a findings block of its own, alters or
// omits a canonical field of an echoed finding, duplicates an id, or carries provider tool-call grammar (structurally:
// outside fenced code spans and outside quoted string values).
import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";

import { guardEnrichment, findToolGrammar } from "../core/enrichment-guard.js";
import { buildConsensusBlock, renderFindingsBlock, canonicalize, CANONICAL_FIELDS } from "../core/consensus-findings.js";
import { scoreFindings } from "../core/scoring.js";

const THRESHOLDS = { high_consensus: 700, disputed_delta: 300, low_value: 400, blocker: 700 };

function consensusFixture() {
  return buildConsensusBlock(scoreFindings([
    { provider: "anthropic", model: "claude-headless", findings: [
      { id: "F-1", title: "Unchecked jq error", severity: "MEDIUM", category: "correctness", file: "lib/cap.sh:24-30",
        description: "When jq fails on a malformed ledger then the spend reads as zero and the watchdog never trips.",
        suggestion: "Fail closed on a jq error.", confidence: 0.8 },
      { id: "F-2", title: "Good env handling", severity: "PRAISE", category: "security", file: "lib/exec.sh:20",
        description: "Secrets travel by environment.", suggestion: "Keep it.", confidence: 0.9 },
    ] },
    { provider: "openai", model: "gpt-5.5-pro", findings: [
      { id: "G-1", title: "Descriptor range", severity: "LOW", category: "security", file: "lib/exec.sh:24",
        description: "os.closerange stops at 65536.", suggestion: "Close every descriptor.", confidence: 0.99, blocking: false },
    ] },
  ], THRESHOLDS));
}

/** The writer echoing the consensus block faithfully, with enrichment fields added (round-1 shape). */
function faithfulEcho(block = consensusFixture()): string {
  const echoed = { ...block, findings: block.findings.map((f) => ({ ...f, metaphor: "a lighthouse", teachable_moment: "fail closed" })) };
  return "## Summary\n\nThe shape is right.\n\n## Findings\n\n" + renderFindingsBlock(echoed) + "\n\n## Callouts\n\n- **[Quality]** Tests have homes.\n";
}

function withEdited(edit: (findings: Array<Record<string, unknown>>) => void, block = consensusFixture()): string {
  const copy = JSON.parse(JSON.stringify(block)) as typeof block;
  edit(copy.findings);
  return "prose\n\n" + renderFindingsBlock(copy) + "\n";
}

describe("guardEnrichment (C-2)", () => {
  it("accepts a faithful echo, keeps the prose as commentary and strips the echoed block", () => {
    const block = consensusFixture();
    const r = guardEnrichment(faithfulEcho(block), block);
    assert.equal(r.accepted, true, JSON.stringify(r));
    if (!r.accepted) return;
    assert.equal(r.echoed, true);
    assert.ok(!r.commentary.includes("bridge-findings-start"), "the echoed block never reaches the posted commentary");
    assert.match(r.commentary, /The shape is right/);
    assert.match(r.commentary, /Tests have homes/);
  });

  it("accepts prose without any findings block", () => {
    const r = guardEnrichment("## Summary\n\nAll good prose.\n", consensusFixture());
    assert.deepEqual(r, { accepted: true, echoed: false, commentary: "## Summary\n\nAll good prose.\n" });
  });

  it("rejects a findings block of its own (an added finding)", () => {
    const r = guardEnrichment(withEdited((f) => f.push({ ...f[0], id: "F-9" })), consensusFixture());
    assert.deepEqual([r.accepted, !r.accepted && r.reason], [false, "own_findings_block"]);
  });

  it("rejects an echo that omits a consensus finding", () => {
    const r = guardEnrichment(withEdited((f) => f.pop()), consensusFixture());
    assert.deepEqual([r.accepted, !r.accepted && r.reason], [false, "own_findings_block"]);
  });

  it("rejects a duplicated id", () => {
    const r = guardEnrichment(withEdited((f) => f.push({ ...f[0] })), consensusFixture());
    assert.deepEqual([r.accepted, !r.accepted && r.reason], [false, "duplicate_id"]);
  });

  const edits: Record<string, (f: Record<string, unknown>) => void> = {
    file: (f) => { f.file = "lib/other.sh:24-30"; },
    anchor_line: (f) => { f.file = "lib/cap.sh:25-30"; },
    anchor_line_end: (f) => { f.file = "lib/cap.sh:24-31"; },
    severity: (f) => { f.severity = "LOW"; },
    confidence: (f) => { f.confidence = 0.5; },
    failure_scenario: (f) => { f.description = "Something else entirely happens here when it runs."; },
    suggestion: (f) => { f.suggestion = "Ignore it."; },
    blocking: (f) => { f.blocking = true; },
  };
  for (const field of CANONICAL_FIELDS.filter((x) => x !== "id")) {
    it(`rejects an echo that alters canonical field ${field}`, () => {
      const r = guardEnrichment(withEdited((f) => edits[field](f.find((x) => x.id === "F-1")!)), consensusFixture());
      assert.equal(r.accepted, false);
      if (r.accepted) return;
      assert.equal(r.reason, "altered_field");
      assert.match(r.detail, new RegExp(`F-1\\.${field}`));
    });
  }

  it("rejects an echo that omits a canonical field", () => {
    const r = guardEnrichment(withEdited((f) => { delete f.find((x) => x.id === "F-1")!.suggestion; }), consensusFixture());
    assert.equal(r.accepted, false);
    if (!r.accepted) assert.match(r.detail, /F-1\.suggestion/);
  });

  it("rejects an echo whose verdict differs from the consensus verdict", () => {
    const block = consensusFixture();
    const r = guardEnrichment("x\n" + renderFindingsBlock({ ...block, verdict: "APPROVE" as never }), block);
    assert.deepEqual([r.accepted, !r.accepted && r.reason], [false, "altered_verdict"]);
  });

  it("rejects two findings blocks, a malformed block and an unmarked findings JSON", () => {
    const block = consensusFixture();
    const two = guardEnrichment(renderFindingsBlock(block) + "\n" + renderFindingsBlock(block), block);
    assert.equal(!two.accepted && two.reason, "multiple_findings_blocks");
    const bad = guardEnrichment("<!-- bridge-findings-start -->\n```json\n{oops\n```\n<!-- bridge-findings-end -->", block);
    assert.equal(!bad.accepted && bad.reason, "malformed_findings_block");
    const unmarked = guardEnrichment("```json\n" + JSON.stringify({ findings: [{ id: "X", severity: "HIGH" }] }) + "\n```", block);
    assert.equal(!unmarked.accepted && unmarked.reason, "own_findings_block");
  });

  it("canonicalize derives anchors from a file:line[-end] reference and failure_scenario by alias precedence", () => {
    assert.deepEqual(canonicalize({ id: "A", file: "a/b.ts:3-9", severity: "high", description: "d" }), {
      id: "A", file: "a/b.ts", anchor_line: 3, anchor_line_end: 9, severity: "HIGH", confidence: null,
      failure_scenario: "d", suggestion: null, blocking: false,
    });
    assert.equal(canonicalize({ id: "A", failure_scenario: "s", failure_mode: "m", description: "d", severity: "LOW" }).failure_scenario, "s");
    assert.equal(canonicalize({ id: "A", failure_mode: "m", description: "d", severity: "LOW" }).failure_scenario, "m");
  });
});

describe("tool-call grammar is matched structurally (C-2)", () => {
  const hits: Record<string, string> = {
    "anthropic XML invoke": 'Let me check.\n<invoke name="Bash">\n<parameter name="command">ls</parameter>\n</invoke>\n',
    "anthropic function_calls": "<function_calls>\n<invoke name=\"Read\"></invoke>\n</function_calls>",
    "namespaced invoke": '  <x:invoke name="Bash">',
    "anthropic tool_use JSON": 'Calling:\n{"type": "tool_use", "id": "toolu_01", "name": "Bash", "input": {"command": "ls"}}',
    "anthropic tool_use key": '{"tool_use": {"name": "Bash", "input": {}}}',
    "openai tool_calls": '{"role": "assistant", "tool_calls": [{"id": "call_1", "type": "function", "function": {"name": "sh", "arguments": "{}"}}]}',
    "openai function_call": 'reply {"function_call": {"name": "sh", "arguments": "{\\"cmd\\": \\"ls\\"}"}} end',
    "openai nested in choices": '{"choices": [{"message": {"tool_calls": [{"id": "c"}]}}]}',
    "bedrock converse toolUse": '{"toolUse": {"toolUseId": "t1", "name": "sh", "input": {}}}',
    "gemini functionCall": '[{"functionCall": {"name": "sh", "args": {}}}]',
  };
  for (const [name, text] of Object.entries(hits)) {
    it(`hit: ${name}`, () => {
      assert.ok(findToolGrammar(text) !== null, `expected a hit in ${JSON.stringify(text)}`);
      const r = guardEnrichment(text, consensusFixture());
      assert.deepEqual([r.accepted, !r.accepted && r.reason], [false, "tool_grammar"]);
    });
  }

  const misses: Record<string, string> = {
    "inside a backtick fence": '```xml\n<invoke name="Bash">\n</invoke>\n```\n',
    "inside a tilde fence": '~~~\n{"tool_use": {"name": "x"}}\n~~~\n',
    "inside a json fence": '```json\n{"tool_calls": [{"id": "c"}]}\n```',
    "inside inline code": 'The guard refuses `<invoke name="x">` and `{"tool_use": 1}` spans.',
    "inside a quoted string value": '{"note": "<invoke name=x> and the \\"tool_use\\" key", "tool": "named in a value"}',
    "prose mention, not at line start": "A writer must never emit <invoke tags or a tool_use key.",
    "an unrelated JSON key": '{"tools": "none", "usage": {"tool_use_count": 0}}',
  };
  for (const [name, text] of Object.entries(misses)) {
    it(`not a hit: ${name}`, () => {
      assert.equal(findToolGrammar(text), null, `unexpected hit in ${JSON.stringify(text)}`);
    });
  }

  it("the PR #1289 round-2 writer transcript is a hit", () => {
    const body = readFileSync(join(import.meta.dirname, "fixtures", "pr1289-r2-comments.md"), "utf8");
    const consensusComment = body.slice(body.indexOf("**[3/3] Multi-Model Consensus Review**"));
    const writer = consensusComment.slice(consensusComment.indexOf("</details>\n\n---\n\n") + "</details>\n\n---\n\n".length);
    assert.match(findToolGrammar(writer) ?? "", /invoke/);
  });
});

describe("single-model two-pass: a Pass 2 output with tool-call grammar is never posted (C-2)", () => {
  it("posts the Pass 1 findings un-enriched and reports enrichment_guard_rejected", async () => {
    const { ReviewPipeline } = await import("../core/reviewer.js");
    const { PRReviewTemplate } = await import("../core/template.js");
    const { BridgebuilderContext } = await import("../core/context.js");
    const pr = { number: 3, title: "t", headSha: "h".repeat(40), baseBranch: "main", labels: [], author: "a" };
    const git = {
      listOpenPRs: async () => [pr],
      getPRFiles: async () => [{ filename: "src/a.ts", status: "modified" as const, additions: 1, deletions: 0, patch: "@@ -1 +1 @@\n+x" }],
      getPRReviews: async () => [], preflight: async () => ({ remaining: 5000, scopes: [] }),
      preflightRepo: async (owner: string, repo: string) => ({ owner, repo, accessible: true }),
      getCommitDiff: async () => ({ filesChanged: [], totalCommits: 0 }),
    };
    const config = {
      repos: [{ owner: "o", repo: "r" }], model: "fixture", maxPrs: 1, maxFilesPerPr: 10, maxDiffBytes: 100_000,
      maxInputTokens: 100_000, maxOutputTokens: 1000, dimensions: [], reviewMarker: "m", repoOverridePath: "",
      dryRun: false, excludePatterns: [], sanitizerMode: "default" as const, maxRuntimeMinutes: 5, reviewMode: "two-pass" as const,
      loaAware: false,
    };
    const pass1 = "<!-- bridge-findings-start -->\n```json\n" + JSON.stringify({ schema_version: 1, findings: [
      { id: "F-1", title: "t", severity: "MEDIUM", category: "quality", file: "src/a.ts:1", description: "d" }] }) + "\n```\n<!-- bridge-findings-end -->";
    let call = 0;
    const llm = { generateReview: async () => ({ content: ++call === 1 ? pass1 : '## Summary\nChecking.\n<invoke name="Bash">\n</invoke>\n## Findings\n' + pass1 + "\n## Callouts\n- x", inputTokens: 1, outputTokens: 1, model: "m" }) };
    const posted: string[] = [];
    const store = { load: async () => {}, getLastHash: async () => null, setLastHash: async () => {}, claimReview: async () => true,
      finalizeReview: async () => {}, getLastReviewedSha: async () => null, setLastReviewedSha: async () => {} };
    const pipeline = new ReviewPipeline(
      new PRReviewTemplate(git, { sha256: async (x: string) => x }, config), new BridgebuilderContext(store), git,
      { postReview: async ({ body }: { body: string }) => { posted.push(body); return true; }, hasExistingReview: async () => false },
      llm, { sanitize: (c: string) => ({ safe: true, sanitizedContent: c, redactedPatterns: [] }) },
      { info() {}, warn() {}, error() {}, debug() {} }, "persona", config,
    );
    const summary = await pipeline.run("r");
    assert.equal(call, 2);
    const r = summary.results[0];
    assert.equal(r.degradedReason, "enrichment_guard_rejected");
    assert.equal(r.verdict, "UNKNOWN");
    assert.equal(r.mergeBlocked, true);
    assert.equal(posted.length, 1);
    assert.ok(!posted[0].includes("<invoke"), "the tool-call transcript is not posted");
    assert.match(posted[0], /findings are unenriched/);
  });
});
