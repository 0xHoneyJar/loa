import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { crossScore } from "../core/cross-scorer.js";
import { detectRefs, parseManualRefs } from "../core/cross-repo.js";
import { extractFindingsFromContent } from "../core/multi-model-pipeline.js";

describe("crossScore", () => {
  it("returns empty result for single model", () => {
    const result = crossScore([
      {
        provider: "anthropic",
        model: "opus",
        findings: [{ id: "F1", title: "Bug", severity: "HIGH", category: "quality", description: "A bug" }],
      },
    ]);
    assert.equal(result.comparisons.length, 0);
    assert.equal(result.total_pairs, 0);
  });

  it("identifies agreements between two models", () => {
    const result = crossScore([
      {
        provider: "anthropic",
        model: "opus",
        findings: [
          { id: "A1", title: "Missing validation", severity: "HIGH", category: "security", file: "src/api.ts", description: "Input validation is missing in the handler" },
        ],
      },
      {
        provider: "openai",
        model: "gpt-4o",
        findings: [
          { id: "B1", title: "No input validation", severity: "HIGH", category: "security", file: "src/api.ts", description: "Handler lacks input validation" },
        ],
      },
    ]);

    assert.equal(result.comparisons.length, 1);
    assert.equal(result.comparisons[0].model_a, "opus");
    assert.equal(result.comparisons[0].model_b, "gpt-4o");
    assert.ok(result.comparisons[0].agreements.length >= 1, "Should have at least 1 agreement");
  });

  it("identifies disagreements between models", () => {
    const result = crossScore([
      {
        provider: "anthropic",
        model: "opus",
        findings: [
          { id: "A1", title: "Security bug", severity: "HIGH", category: "security", description: "SQL injection vulnerability" },
        ],
      },
      {
        provider: "openai",
        model: "gpt-4o",
        findings: [
          { id: "B1", title: "Performance issue", severity: "MEDIUM", category: "performance", description: "N+1 query pattern in the loop" },
        ],
      },
    ]);

    assert.equal(result.comparisons.length, 1);
    assert.ok(result.comparisons[0].disagreements.length >= 1, "Should have disagreements");
  });

  it("handles 3-model pairwise comparison (3 pairs)", () => {
    const result = crossScore([
      { provider: "anthropic", model: "opus", findings: [{ id: "A1", title: "Bug", severity: "HIGH", category: "bug", description: "A bug" }] },
      { provider: "openai", model: "gpt-4o", findings: [{ id: "B1", title: "Bug", severity: "HIGH", category: "bug", description: "A bug" }] },
      { provider: "google", model: "gemini", findings: [{ id: "C1", title: "Bug", severity: "HIGH", category: "bug", description: "A bug" }] },
    ]);

    // N*(N-1)/2 = 3 pairs
    assert.equal(result.total_pairs, 3);
    assert.equal(result.comparisons.length, 3);
  });

  it("computes agreement rate", () => {
    const result = crossScore([
      {
        provider: "anthropic",
        model: "opus",
        findings: [
          { id: "A1", title: "Issue", severity: "HIGH", category: "quality", file: "src/a.ts", description: "Same issue found by both" },
        ],
      },
      {
        provider: "openai",
        model: "gpt-4o",
        findings: [
          { id: "B1", title: "Issue", severity: "HIGH", category: "quality", file: "src/a.ts", description: "Same issue found by both models" },
        ],
      },
    ]);

    assert.ok(result.agreement_rate >= 0, "Agreement rate should be >= 0");
    assert.ok(result.agreement_rate <= 1, "Agreement rate should be <= 1");
  });
});

describe("detectRefs", () => {
  it("detects owner/repo#123 references", () => {
    const refs = detectRefs("Related to some-org/other-repo#42");
    assert.equal(refs.length, 1);
    assert.equal(refs[0].owner, "some-org");
    assert.equal(refs[0].repo, "other-repo");
    assert.equal(refs[0].number, 42);
    assert.equal(refs[0].source, "auto");
  });

  it("detects GitHub URLs", () => {
    const refs = detectRefs("See https://github.com/org/repo/pull/99 for context");
    assert.equal(refs.length, 1);
    assert.equal(refs[0].owner, "org");
    assert.equal(refs[0].repo, "repo");
    assert.equal(refs[0].number, 99);
  });

  it("detects issue URLs", () => {
    const refs = detectRefs("Fixes https://github.com/org/repo/issues/123");
    assert.equal(refs.length, 1);
    assert.equal(refs[0].number, 123);
  });

  it("skips self-references", () => {
    const refs = detectRefs("See my-org/my-repo#1", "my-org/my-repo");
    assert.equal(refs.length, 0);
  });

  it("deduplicates multiple mentions of same ref", () => {
    const refs = detectRefs("See org/repo#42 and also org/repo#42 again");
    assert.equal(refs.length, 1);
  });

  it("detects multiple different refs", () => {
    const refs = detectRefs("Related to org/repo-a#1 and org/repo-b#2");
    assert.equal(refs.length, 2);
  });

  it("returns empty for no refs", () => {
    const refs = detectRefs("Just a normal PR description");
    assert.equal(refs.length, 0);
  });
});

describe("parseManualRefs", () => {
  it("parses owner/repo#123 format", () => {
    const refs = parseManualRefs(["org/repo#42"]);
    assert.equal(refs.length, 1);
    assert.equal(refs[0].owner, "org");
    assert.equal(refs[0].repo, "repo");
    assert.equal(refs[0].number, 42);
    assert.equal(refs[0].source, "manual");
  });

  it("parses owner/repo format (no number)", () => {
    const refs = parseManualRefs(["org/repo"]);
    assert.equal(refs.length, 1);
    assert.equal(refs[0].owner, "org");
    assert.equal(refs[0].repo, "repo");
    assert.equal(refs[0].number, undefined);
  });

  it("skips invalid formats", () => {
    const refs = parseManualRefs(["invalid", "also-invalid", "org/repo#42"]);
    assert.equal(refs.length, 1);
  });

  it("handles empty array", () => {
    const refs = parseManualRefs([]);
    assert.equal(refs.length, 0);
  });
});

/**
 * Regression tests for bug-20260413-9f9b39:
 * Multi-model pipeline extracts 0 findings because main.ts uses buildPrompt()
 * (standard review prose) but extractFindingsFromContent() expects convergence
 * format with <!-- bridge-findings-start --> JSON markers.
 *
 * These tests document the format contract: the extractor ONLY parses
 * convergence-format output. main.ts MUST use buildConvergenceUserPromptFromTruncation()
 * (or equivalent) to produce parseable reviews.
 */
describe("extractFindingsFromContent (bug-20260413-9f9b39)", () => {
  it("extracts findings from convergence-format review output", () => {
    const content = `## Summary
Review content.

<!-- bridge-findings-start -->
\`\`\`json
{
  "schema_version": 1,
  "findings": [
    {
      "id": "F1",
      "title": "SQL Injection",
      "severity": "HIGH",
      "category": "security",
      "file": "src/db.ts",
      "description": "User input interpolated into SQL",
      "suggestion": "Use parameterized queries"
    },
    {
      "id": "F2",
      "title": "Missing error handler",
      "severity": "MEDIUM",
      "category": "quality",
      "description": "Promise rejection uncaught"
    }
  ]
}
\`\`\`
<!-- bridge-findings-end -->`;

    const findings = extractFindingsFromContent(content);
    assert.equal(findings.length, 2, "Should extract both findings from convergence format");
    assert.equal(findings[0].id, "F1");
    assert.equal(findings[0].severity, "HIGH");
    assert.equal(findings[1].id, "F2");
  });

  it("returns empty array for standard prose review (documents the bug)", () => {
    // This is what template.buildPrompt() asks models to produce:
    // "Your review MUST contain these sections:
    //   - ## Summary (2-3 sentences)
    //   - ## Findings (5-8 items, grouped by dimension, severity-tagged)
    //   - ## Callouts (positive observations, ~30% of content)"
    // Models return markdown prose — NOT findings JSON.
    const standardProseReview = `## Summary
This PR has several issues worth addressing.

## Findings

### Security
- **HIGH**: SQL injection vulnerability in src/db.ts:42 — user input is directly interpolated into SQL
- **MEDIUM**: Missing input validation on the userId parameter

### Quality
- **LOW**: Inconsistent variable naming

## Callouts
- Good test coverage across all new modules
- Clean separation of concerns`;

    const findings = extractFindingsFromContent(standardProseReview);
    // Bug documented: extractor cannot parse prose format.
    // main.ts must use convergence prompt builder to produce parseable output.
    assert.equal(findings.length, 0);
  });

  it("handles malformed JSON in findings block gracefully", () => {
    const content = `<!-- bridge-findings-start -->
\`\`\`json
{ "schema_version": 1, "findings": [ {broken json
\`\`\`
<!-- bridge-findings-end -->`;

    const findings = extractFindingsFromContent(content);
    assert.equal(findings.length, 0);
  });

  it("handles missing findings array gracefully", () => {
    const content = `<!-- bridge-findings-start -->
\`\`\`json
{ "schema_version": 1 }
\`\`\`
<!-- bridge-findings-end -->`;

    const findings = extractFindingsFromContent(content);
    assert.equal(findings.length, 0);
  });
});
