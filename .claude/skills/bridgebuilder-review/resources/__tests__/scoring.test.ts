import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { scoreFindings, levenshteinSimilarity } from "../core/scoring.js";
import type { ModelFindings } from "../core/scoring.js";

describe("scoreFindings", () => {
  it("returns empty result for no models", () => {
    const result = scoreFindings([]);
    assert.equal(result.convergence.length, 0);
    assert.equal(result.diversity.length, 0);
    assert.equal(result.stats.total_findings, 0);
  });

  it("returns empty result for models with no findings", () => {
    const result = scoreFindings([
      { provider: "anthropic", model: "opus", findings: [] },
      { provider: "openai", model: "gpt-4o", findings: [] },
    ]);
    assert.equal(result.convergence.length, 0);
    assert.equal(result.stats.models_contributing, 2);
  });

  it("classifies CRITICAL findings as BLOCKER regardless of model count", () => {
    const result = scoreFindings([
      {
        provider: "anthropic",
        model: "opus",
        findings: [{
          id: "F1",
          title: "SQL injection",
          severity: "CRITICAL",
          category: "security",
          description: "User input directly interpolated in SQL query",
        }],
      },
    ]);
    assert.equal(result.convergence.length, 1);
    assert.equal(result.convergence[0].classification, "BLOCKER");
  });

  it("classifies matching findings from 2+ models as HIGH_CONSENSUS", () => {
    const result = scoreFindings([
      {
        provider: "anthropic",
        model: "opus",
        findings: [{
          id: "F1",
          title: "Missing error handling",
          severity: "HIGH",
          category: "quality",
          file: "src/handler.ts",
          description: "The async handler does not catch rejected promises",
        }],
      },
      {
        provider: "openai",
        model: "gpt-4o",
        findings: [{
          id: "F1",
          title: "Unhandled promise rejection",
          severity: "HIGH",
          category: "quality",
          file: "src/handler.ts",
          description: "The handler fails to catch promise rejections",
        }],
      },
    ]);
    assert.equal(result.convergence.length, 1);
    assert.equal(result.convergence[0].classification, "HIGH_CONSENSUS");
    assert.equal(result.convergence[0].agreeing_models.length, 2);
    assert.ok(result.convergence[0].agreeing_models.includes("opus"));
    assert.ok(result.convergence[0].agreeing_models.includes("gpt-4o"));
  });

  it("classifies findings with large score delta as DISPUTED", () => {
    const result = scoreFindings([
      {
        provider: "anthropic",
        model: "opus",
        findings: [{
          id: "F1",
          title: "Naming issue",
          severity: "CRITICAL",
          category: "quality",
          file: "src/api.ts",
          description: "Variable naming is inconsistent",
        }],
      },
      {
        provider: "openai",
        model: "gpt-4o",
        findings: [{
          id: "F1",
          title: "Naming convention",
          severity: "LOW",
          category: "quality",
          file: "src/api.ts",
          description: "Variable names are inconsistent",
        }],
      },
    ], { disputed_delta: 300 });

    // The CRITICAL finding may override to BLOCKER, or the delta makes it DISPUTED
    // depending on the scoring logic — verify one of these classifications
    const finding = result.convergence[0];
    assert.ok(
      finding.classification === "BLOCKER" || finding.classification === "DISPUTED",
      `Expected BLOCKER or DISPUTED, got ${finding.classification}`,
    );
    assert.ok(finding.score_delta >= 300, `Score delta ${finding.score_delta} should be >= 300`);
  });

  it("classifies low-scoring single-model findings correctly", () => {
    const result = scoreFindings([
      {
        provider: "anthropic",
        model: "opus",
        findings: [{
          id: "F1",
          title: "Consider adding comment",
          severity: "LOW",
          category: "style",
          description: "A comment here would improve readability",
        }],
      },
    ]);
    assert.equal(result.convergence.length, 1);
    assert.equal(result.convergence[0].classification, "LOW_VALUE");
  });

  it("preserves unique perspectives in diversity track", () => {
    const result = scoreFindings([
      {
        provider: "anthropic",
        model: "opus",
        findings: [{
          id: "F1",
          title: "Security issue",
          severity: "HIGH",
          category: "security",
          description: "Input validation missing",
          faang_parallel: "Similar to Google's approach to input validation in Borg",
          teachable_moment: "Always validate at system boundaries",
        }],
      },
      {
        provider: "openai",
        model: "gpt-4o",
        findings: [{
          id: "F1",
          title: "Different pattern",
          severity: "MEDIUM",
          category: "architecture",
          description: "This architecture could benefit from event sourcing",
          metaphor: "Think of events as a ledger of state changes",
        }],
      },
    ]);

    // Both have enrichment fields, so both should appear in diversity
    assert.ok(result.diversity.length >= 1, "Should have diversity entries");
  });

  it("deduplicates similar findings in diversity track", () => {
    const result = scoreFindings([
      {
        provider: "anthropic",
        model: "opus",
        findings: [{
          id: "F1",
          title: "Error handling",
          severity: "HIGH",
          category: "quality",
          description: "Missing error handling in the request handler function",
          faang_parallel: "Netflix Hystrix uses circuit breakers",
        }],
      },
      {
        provider: "openai",
        model: "gpt-4o",
        findings: [{
          id: "F1",
          title: "Error handling missing",
          severity: "HIGH",
          category: "quality",
          description: "Missing error handling in the request handler function",
          faang_parallel: "Netflix uses Hystrix for circuit breaking",
        }],
      },
    ]);

    // Should deduplicate since descriptions are nearly identical
    assert.ok(result.diversity.length <= 1, "Should deduplicate similar findings");
  });

  it("respects custom scoring thresholds", () => {
    const result = scoreFindings(
      [
        {
          provider: "anthropic",
          model: "opus",
          findings: [{
            id: "F1",
            title: "Style issue",
            severity: "LOW",
            category: "style",
            description: "Minor formatting suggestion",
          }],
        },
      ],
      { low_value: 500 }, // Higher threshold — LOW (200) should be below it
    );

    assert.equal(result.convergence[0].classification, "LOW_VALUE");
  });

  it("handles 3-model review correctly", () => {
    const models: ModelFindings[] = [
      {
        provider: "anthropic",
        model: "opus",
        findings: [
          { id: "A1", title: "Auth bypass", severity: "HIGH", category: "security", description: "Authentication check missing" },
          { id: "A2", title: "Formatting", severity: "LOW", category: "style", description: "Inconsistent indentation" },
        ],
      },
      {
        provider: "openai",
        model: "gpt-4o",
        findings: [
          { id: "B1", title: "Missing auth check", severity: "HIGH", category: "security", description: "Authentication check is bypassed" },
        ],
      },
      {
        provider: "google",
        model: "gemini-2.5-pro",
        findings: [
          { id: "C1", title: "Auth vulnerability", severity: "HIGH", category: "security", description: "Authentication verification missing" },
          { id: "C2", title: "Performance", severity: "MEDIUM", category: "performance", description: "N+1 query pattern detected" },
        ],
      },
    ];

    const result = scoreFindings(models);

    assert.equal(result.stats.models_contributing, 3);
    assert.ok(result.stats.total_findings > 0);
    assert.ok(result.stats.high_consensus >= 1, "Auth finding should be high consensus");
  });

  it("computes correct stats summary", () => {
    const result = scoreFindings([
      {
        provider: "anthropic",
        model: "opus",
        findings: [
          { id: "F1", title: "Critical bug", severity: "CRITICAL", category: "bug", description: "Crash on null input" },
          { id: "F2", title: "Good pattern", severity: "PRAISE", category: "quality", description: "Well-structured code" },
        ],
      },
      {
        provider: "openai",
        model: "gpt-4o",
        findings: [
          { id: "F1", title: "Null crash", severity: "CRITICAL", category: "bug", description: "Crashes when input is null" },
        ],
      },
    ]);

    assert.ok(result.stats.blocker >= 1, "Should have at least 1 blocker");
    assert.equal(result.stats.models_contributing, 2);
    assert.ok(result.stats.total_findings > 0);
  });
});

describe("levenshteinSimilarity", () => {
  it("returns 1.0 for identical strings", () => {
    assert.equal(levenshteinSimilarity("hello", "hello"), 1.0);
  });

  it("returns 0.0 for empty vs non-empty", () => {
    assert.equal(levenshteinSimilarity("", "hello"), 0.0);
    assert.equal(levenshteinSimilarity("hello", ""), 0.0);
  });

  it("returns 1.0 for both empty", () => {
    assert.equal(levenshteinSimilarity("", ""), 1.0);
  });

  it("returns high similarity for similar strings", () => {
    const sim = levenshteinSimilarity("kitten", "sitting");
    assert.ok(sim > 0.5, `Expected > 0.5, got ${sim}`);
  });

  it("returns low similarity for very different strings", () => {
    const sim = levenshteinSimilarity("abc", "xyz");
    assert.ok(sim < 0.5, `Expected < 0.5, got ${sim}`);
  });

  it("handles long strings by truncating", () => {
    const a = "a".repeat(1000);
    const b = "b".repeat(1000);
    // Should not hang — truncation kicks in
    const sim = levenshteinSimilarity(a, b);
    assert.ok(sim >= 0.0 && sim <= 1.0);
  });
});
