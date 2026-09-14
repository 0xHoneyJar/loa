import { it } from "node:test";
import assert from "node:assert/strict";
import { summarizeReviewVerdict } from "../core/review-verdict.js";

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
