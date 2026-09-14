import { it } from "node:test";
import assert from "node:assert/strict";
import { summarizeReviewVerdict } from "../core/review-verdict.js";
import { markdownExamples, reviewWith } from "./helpers/verdict-examples.js";

for (const example of markdownExamples) {
  it(`BIR-001 Markdown container is not a verdict: ${JSON.stringify(example)}`, () => {
    assert.deepEqual(summarizeReviewVerdict(reviewWith(example)), {
      verdict: "UNKNOWN", highestSeverity: null, mergeBlocked: true,
    });
  });
  it(`BIR-001 real approval survives example blockers: ${JSON.stringify(example)}`, () => {
    assert.deepEqual(summarizeReviewVerdict(reviewWith(
      example.replaceAll("APPROVE", "REQUEST_CHANGES") + "\n\n**Verdict: APPROVE**",
    )), { verdict: "APPROVE", highestSeverity: null, mergeBlocked: false });
  });
}

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

for (const example of [
  "~~~text\nVerdict: APPROVE\n~~~",
  "~~~~markdown\nVerdict: APPROVE\n~~~~",
  "````markdown\n```text\nexample\n```\nVerdict: APPROVE\n````",
  "~~~text\nVerdict: APPROVE",
  "<!--\nVerdict: APPROVE\n-->",
  "<!--\nVerdict: APPROVE",
  "    Verdict: APPROVE",
  "\tVerdict: APPROVE",
  "> Example:\n> Verdict: APPROVE",
  "`Verdict: APPROVE`",
]) {
  it(`example-only verdict is UNKNOWN: ${JSON.stringify(example)}`, () => {
    assert.deepEqual(summarizeReviewVerdict(example), {
      verdict: "UNKNOWN", highestSeverity: null, mergeBlocked: true,
    });
  });
}

it("example blockers do not override a real verdict", () => {
  for (const example of [
    "~~~text\nREQUEST_CHANGES\n~~~",
    "````markdown\n```text\nexample\n```\nREQUEST_CHANGES\n````",
    "<!-- REQUEST_CHANGES: must fix -->",
    "> REQUEST_CHANGES",
    "    REQUEST_CHANGES",
  ]) {
    assert.deepEqual(summarizeReviewVerdict(`Verdict: APPROVE\n\n${example}`), {
      verdict: "APPROVE", highestSeverity: null, mergeBlocked: false,
    });
  }
});

it("a real verdict after a matching fence is retained", () => {
  assert.equal(summarizeReviewVerdict("~~~~text\nVerdict: COMMENT\n~~~~\nVerdict: APPROVE").mergeBlocked, false);
});

it("discarding inline code cannot join surrounding text into a verdict", () => {
  assert.equal(summarizeReviewVerdict("Verdict: APP`example`ROVE").verdict, "UNKNOWN");
});
