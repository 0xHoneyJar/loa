import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, existsSync, readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { rmSync } from "node:fs";
import {
  extractEcosystemPatterns,
  updateEcosystemContext,
  firstSentence,
} from "../core/ecosystem.js";
import { ReviewPipeline } from "../core/reviewer.js";
import type { ValidatedFinding } from "../core/schemas.js";
import type { EcosystemPattern, EcosystemContext } from "../core/types.js";
import type { ILogger } from "../ports/logger.js";

// ─── Test Helpers ─────────────────────────────────────────────

function mockLogger(): ILogger & { warnings: Array<Record<string, unknown>> } {
  const warnings: Array<Record<string, unknown>>[] = [];
  return {
    warnings: warnings as unknown as Array<Record<string, unknown>>,
    info: () => {},
    warn: (_msg: string, meta?: Record<string, unknown>) => {
      (warnings as unknown as Array<Record<string, unknown>>).push(meta ?? {});
    },
    error: () => {},
    debug: () => {},
  };
}

function makeFinding(overrides: Partial<ValidatedFinding> & { title?: string; description?: string }): ValidatedFinding {
  return {
    id: "F001",
    severity: "HIGH",
    category: "quality",
    ...overrides,
  } as ValidatedFinding;
}

// ─── extractEcosystemPatterns ─────────────────────────────────

describe("extractEcosystemPatterns", () => {
  it("extracts PRAISE with confidence > 0.8 and all SPECULATION findings (Test 1)", () => {
    const findings: ValidatedFinding[] = [
      makeFinding({ id: "P001", severity: "PRAISE", confidence: 0.95, title: "Great architecture", description: "Well-structured code. Clear separation of concerns." }),
      makeFinding({ id: "P002", severity: "PRAISE", confidence: 0.5, title: "Decent naming", description: "Names are okay." }),
      makeFinding({ id: "S001", severity: "SPECULATION", confidence: 0.3, title: "Future caching", description: "Could add caching here." }),
      makeFinding({ id: "H001", severity: "HIGH", confidence: 0.9, title: "Security issue", description: "SQL injection risk." }),
      makeFinding({ id: "M001", severity: "MEDIUM", confidence: 0.7, title: "Minor issue", description: "Should refactor." }),
      makeFinding({ id: "S002", severity: "SPECULATION", title: "Pattern matching", description: "Pattern matching would simplify this." }),
    ];

    const patterns = extractEcosystemPatterns(findings, "test-repo", 42);

    assert.equal(patterns.length, 3, "Should extract 3 patterns: 1 PRAISE (high confidence) + 2 SPECULATION");
    assert.equal(patterns[0].extractedFrom, "P001");
    assert.equal(patterns[0].pattern, "Great architecture");
    assert.equal(patterns[0].confidence, 0.95);
    assert.equal(patterns[1].extractedFrom, "S001");
    assert.equal(patterns[1].pattern, "Future caching");
    assert.equal(patterns[2].extractedFrom, "S002");
    assert.equal(patterns[2].pattern, "Pattern matching");

    // Verify all patterns have required fields
    for (const p of patterns) {
      assert.equal(p.repo, "test-repo");
      assert.equal(p.pr, 42);
      assert.ok(p.pattern.length > 0);
      assert.ok(typeof p.connection === "string");
      assert.ok(typeof p.extractedFrom === "string");
    }
  });

  it("returns empty array when no qualifying findings exist (Test 2)", () => {
    const findings: ValidatedFinding[] = [
      makeFinding({ id: "H001", severity: "HIGH", confidence: 0.9, title: "Bug", description: "Real bug." }),
      makeFinding({ id: "L001", severity: "LOW", confidence: 0.4, title: "Minor", description: "Nitpick." }),
      makeFinding({ id: "P001", severity: "PRAISE", confidence: 0.7, title: "Good", description: "Nice." }),
      makeFinding({ id: "P002", severity: "PRAISE", title: "OK", description: "Fine." }),
    ];

    const patterns = extractEcosystemPatterns(findings, "test-repo", 10);
    assert.equal(patterns.length, 0, "No PRAISE with confidence > 0.8 or SPECULATION findings");
  });

  it("extracts connection as first sentence of description (Test 2b)", () => {
    const findings: ValidatedFinding[] = [
      makeFinding({
        id: "S001",
        severity: "SPECULATION",
        title: "Event sourcing",
        description: "Event sourcing could improve auditability. It would also simplify replay. Consider CQRS as a complement.",
      }),
    ];

    const patterns = extractEcosystemPatterns(findings, "repo", 1);
    assert.equal(patterns.length, 1);
    assert.equal(patterns[0].connection, "Event sourcing could improve auditability.");
  });
});

// ─── firstSentence ─────────────────────────────────────────────

describe("firstSentence", () => {
  it("extracts first sentence up to period (Test 8a)", () => {
    const text = "This is the first sentence. This is the second. And a third.";
    assert.equal(firstSentence(text), "This is the first sentence.");
  });

  it("returns full text when no period exists", () => {
    const text = "No period here";
    assert.equal(firstSentence(text), "No period here");
  });

  it("bounds at 200 characters (Test 8)", () => {
    // Create a string with no period that's > 200 chars
    const longText = "A".repeat(250);
    assert.equal(firstSentence(longText).length, 200);
  });

  it("bounds first sentence at 200 characters when sentence is very long", () => {
    // First sentence is > 200 chars before the period
    const longSentence = "A".repeat(220) + ". Short second.";
    const result = firstSentence(longSentence);
    assert.equal(result.length, 200);
  });

  it("returns empty string for empty input", () => {
    assert.equal(firstSentence(""), "");
  });
});

// ─── updateEcosystemContext ─────────────────────────────────────

describe("updateEcosystemContext", () => {
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = mkdtempSync(join(tmpdir(), "ecosystem-test-"));
  });

  afterEach(() => {
    rmSync(tmpDir, { recursive: true, force: true });
  });

  it("appends new patterns to existing context (Test 3)", async () => {
    const contextPath = join(tmpDir, "context.json");
    const existing: EcosystemContext = {
      patterns: [
        { repo: "repo-a", pr: 1, pattern: "Existing pattern", connection: "Already here." },
      ],
      lastUpdated: "2026-01-01T00:00:00Z",
    };
    writeFileSync(contextPath, JSON.stringify(existing));

    const newPatterns: EcosystemPattern[] = [
      { repo: "repo-b", pr: 5, pattern: "New pattern", connection: "Fresh insight.", extractedFrom: "F001", confidence: 0.9 },
    ];

    await updateEcosystemContext(contextPath, newPatterns);

    const result = JSON.parse(readFileSync(contextPath, "utf-8")) as EcosystemContext;
    assert.equal(result.patterns.length, 2);
    assert.equal(result.patterns[0].pattern, "Existing pattern");
    assert.equal(result.patterns[1].pattern, "New pattern");
    assert.notEqual(result.lastUpdated, "2026-01-01T00:00:00Z", "lastUpdated should be updated");
  });

  it("deduplicates by repo + pattern (Test 4)", async () => {
    const contextPath = join(tmpDir, "context.json");
    const existing: EcosystemContext = {
      patterns: [
        { repo: "repo-a", pr: 1, pattern: "Pattern Alpha", connection: "Original." },
      ],
      lastUpdated: "2026-01-01T00:00:00Z",
    };
    writeFileSync(contextPath, JSON.stringify(existing));

    const newPatterns: EcosystemPattern[] = [
      { repo: "repo-a", pr: 2, pattern: "Pattern Alpha", connection: "Duplicate.", extractedFrom: "F001", confidence: 0.9 },
      { repo: "repo-a", pr: 3, pattern: "Pattern Beta", connection: "New.", extractedFrom: "F002", confidence: 0.8 },
    ];

    await updateEcosystemContext(contextPath, newPatterns);

    const result = JSON.parse(readFileSync(contextPath, "utf-8")) as EcosystemContext;
    assert.equal(result.patterns.length, 2, "Duplicate should be skipped, new one added");
    assert.equal(result.patterns[0].pattern, "Pattern Alpha");
    assert.equal(result.patterns[1].pattern, "Pattern Beta");
  });

  it("evicts oldest patterns when per-repo cap exceeded (Test 5)", async () => {
    const contextPath = join(tmpDir, "context.json");

    // Create 19 existing patterns for repo-x
    const existingPatterns = Array.from({ length: 19 }, (_, i) => ({
      repo: "repo-x",
      pr: i,
      pattern: `Pattern ${i}`,
      connection: `Connection ${i}.`,
    }));
    const existing: EcosystemContext = {
      patterns: existingPatterns,
      lastUpdated: "2026-01-01T00:00:00Z",
    };
    writeFileSync(contextPath, JSON.stringify(existing));

    // Add 3 new patterns → total 22 for repo-x → should cap at 20
    const newPatterns: EcosystemPattern[] = [
      { repo: "repo-x", pr: 100, pattern: "New A", connection: "A.", extractedFrom: "F001", confidence: 0.9 },
      { repo: "repo-x", pr: 101, pattern: "New B", connection: "B.", extractedFrom: "F002", confidence: 0.8 },
      { repo: "repo-x", pr: 102, pattern: "New C", connection: "C.", extractedFrom: "F003", confidence: 0.7 },
    ];

    await updateEcosystemContext(contextPath, newPatterns);

    const result = JSON.parse(readFileSync(contextPath, "utf-8")) as EcosystemContext;
    assert.equal(result.patterns.filter((p) => p.repo === "repo-x").length, 20, "Should cap at 20 per repo");
    // The oldest 2 (Pattern 0 and Pattern 1) should be evicted
    const patternNames = result.patterns.map((p) => p.pattern);
    assert.ok(!patternNames.includes("Pattern 0"), "Pattern 0 (oldest) should be evicted");
    assert.ok(!patternNames.includes("Pattern 1"), "Pattern 1 (second oldest) should be evicted");
    assert.ok(patternNames.includes("New C"), "Newest pattern should remain");
  });

  it("creates file when context file is missing (Test 6)", async () => {
    const contextPath = join(tmpDir, "new-context.json");
    assert.ok(!existsSync(contextPath), "File should not exist yet");

    const newPatterns: EcosystemPattern[] = [
      { repo: "repo-a", pr: 1, pattern: "Fresh pattern", connection: "Brand new.", extractedFrom: "F001", confidence: 0.9 },
    ];

    await updateEcosystemContext(contextPath, newPatterns);

    assert.ok(existsSync(contextPath), "File should be created");
    const result = JSON.parse(readFileSync(contextPath, "utf-8")) as EcosystemContext;
    assert.equal(result.patterns.length, 1);
    assert.equal(result.patterns[0].pattern, "Fresh pattern");
    assert.ok(result.lastUpdated.length > 0, "lastUpdated should be set");
  });

  it("writes atomically via temp file then rename (Test 7)", async () => {
    const contextPath = join(tmpDir, "atomic-context.json");
    const tmpPath = `${contextPath}.tmp`;

    const newPatterns: EcosystemPattern[] = [
      { repo: "repo-a", pr: 1, pattern: "Atomic test", connection: "Should be atomic.", extractedFrom: "F001", confidence: 0.9 },
    ];

    await updateEcosystemContext(contextPath, newPatterns);

    // After successful write, temp file should NOT exist (renamed)
    assert.ok(!existsSync(tmpPath), "Temp file should be renamed away");
    // Final file should exist and be valid
    assert.ok(existsSync(contextPath), "Final file should exist");
    const result = JSON.parse(readFileSync(contextPath, "utf-8"));
    assert.equal(result.patterns.length, 1);
  });

  it("handles gracefully when directory does not exist", async () => {
    const contextPath = join(tmpDir, "nonexistent", "deep", "context.json");
    const logger = mockLogger();

    const newPatterns: EcosystemPattern[] = [
      { repo: "repo-a", pr: 1, pattern: "Test", connection: "Test.", extractedFrom: "F001", confidence: 0.9 },
    ];

    // Should not throw
    await updateEcosystemContext(contextPath, newPatterns, logger);
    assert.ok(logger.warnings.length > 0, "Should log a warning");
  });
});

// ─── Full Pipeline: extract + update (end-to-end) ─────────────

describe("Ecosystem full pipeline", () => {
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = mkdtempSync(join(tmpdir(), "ecosystem-pipeline-"));
  });

  afterEach(() => {
    rmSync(tmpDir, { recursive: true, force: true });
  });

  it("extract + update end-to-end (Test 9)", async () => {
    const contextPath = join(tmpDir, "eco.json");
    const logger = mockLogger();

    // Seed with one existing pattern
    const seed: EcosystemContext = {
      patterns: [
        { repo: "other-repo", pr: 1, pattern: "Existing", connection: "Already here." },
      ],
      lastUpdated: "2026-01-01T00:00:00Z",
    };
    writeFileSync(contextPath, JSON.stringify(seed));

    // Simulate findings from a bridge run
    const findings: ValidatedFinding[] = [
      makeFinding({ id: "P001", severity: "PRAISE", confidence: 0.95, title: "Excellent error handling", description: "Comprehensive error recovery with circuit breakers. Falls back gracefully." }),
      makeFinding({ id: "S001", severity: "SPECULATION", confidence: 0.4, title: "Consider event sourcing", description: "Event sourcing could improve auditability here." }),
      makeFinding({ id: "H001", severity: "HIGH", confidence: 0.9, title: "Missing validation", description: "Input not validated." }),
    ];

    // Use the ReviewPipeline static method (AC-7)
    await ReviewPipeline.updateEcosystemFromFindings(
      findings,
      "my-repo",
      42,
      contextPath,
      logger,
    );

    const result = JSON.parse(readFileSync(contextPath, "utf-8")) as EcosystemContext;
    assert.equal(result.patterns.length, 3, "1 existing + 2 extracted (PRAISE + SPECULATION)");
    assert.equal(result.patterns[0].pattern, "Existing");
    assert.equal(result.patterns[1].pattern, "Excellent error handling");
    assert.equal(result.patterns[1].connection, "Comprehensive error recovery with circuit breakers.");
    assert.equal(result.patterns[2].pattern, "Consider event sourcing");
    assert.notEqual(result.lastUpdated, "2026-01-01T00:00:00Z");
  });

  it("skips update when no qualifying findings (pipeline integration)", async () => {
    const contextPath = join(tmpDir, "eco2.json");
    const logger = mockLogger();

    const seed: EcosystemContext = {
      patterns: [],
      lastUpdated: "2026-01-01T00:00:00Z",
    };
    writeFileSync(contextPath, JSON.stringify(seed));

    const findings: ValidatedFinding[] = [
      makeFinding({ id: "H001", severity: "HIGH", confidence: 0.9, title: "Bug", description: "Bug found." }),
    ];

    await ReviewPipeline.updateEcosystemFromFindings(
      findings,
      "my-repo",
      10,
      contextPath,
      logger,
    );

    // File should not have been modified (no patterns extracted)
    const result = JSON.parse(readFileSync(contextPath, "utf-8")) as EcosystemContext;
    assert.equal(result.patterns.length, 0);
    assert.equal(result.lastUpdated, "2026-01-01T00:00:00Z", "Timestamp unchanged");
  });
});
