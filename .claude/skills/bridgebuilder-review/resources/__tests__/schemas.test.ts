import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { FindingSchema, FindingsBlockSchema } from "../core/schemas.js";
import { PRReviewTemplate } from "../core/template.js";
import type { IGitProvider } from "../ports/git-provider.js";
import type { IHasher } from "../ports/hasher.js";
import type { BridgebuilderConfig, EnrichmentOptions } from "../core/types.js";

function mockGitProvider(): IGitProvider {
  return {
    listOpenPRs: async () => [],
    getPRFiles: async () => [],
    getPRReviews: async () => [],
    preflight: async () => ({ remaining: 5000, scopes: ["repo"] }),
    preflightRepo: async () => ({ owner: "o", repo: "r", accessible: true }),
    getCommitDiff: async () => ({ filesChanged: [], totalCommits: 0 }),
  };
}

function mockHasher(): IHasher {
  return { sha256: async (input: string) => `hash-of-${input.slice(0, 20)}` };
}

function mockConfig(overrides?: Partial<BridgebuilderConfig>): BridgebuilderConfig {
  return {
    repos: [{ owner: "test", repo: "repo" }],
    model: "claude-sonnet-4-5-20250929",
    maxPrs: 10,
    maxFilesPerPr: 50,
    maxDiffBytes: 100_000,
    maxInputTokens: 100_000,
    maxOutputTokens: 4096,
    dimensions: ["correctness"],
    reviewMarker: "bridgebuilder-review",
    repoOverridePath: "BEAUVOIR.md",
    dryRun: false,
    excludePatterns: [],
    sanitizerMode: "default" as const,
    maxRuntimeMinutes: 30,
    reviewMode: "single-pass" as const,
    ...overrides,
  };
}

describe("FindingSchema", () => {
  it("accepts valid finding with all required fields", () => {
    const input = {
      id: "F001",
      severity: "HIGH",
      category: "security",
      title: "Test",
      file: "src/app.ts:42",
      description: "A real issue",
      suggestion: "Fix it",
    };

    const result = FindingSchema.safeParse(input);
    assert.ok(result.success, "Valid finding should pass schema");
    assert.equal(result.data.id, "F001");
    assert.equal(result.data.severity, "HIGH");
    assert.equal(result.data.category, "security");
  });

  it("rejects finding missing id", () => {
    const input = {
      severity: "HIGH",
      category: "security",
    };

    const result = FindingSchema.safeParse(input);
    assert.ok(!result.success, "Finding without id should be rejected");
  });

  it("rejects finding with id as number (not string)", () => {
    const input = {
      id: 42,
      severity: "HIGH",
      category: "security",
    };

    const result = FindingSchema.safeParse(input);
    assert.ok(!result.success, "Finding with numeric id should be rejected");
  });

  it("strips confidence above 1.0", () => {
    const input = {
      id: "F001",
      severity: "HIGH",
      category: "security",
      confidence: 1.5,
    };

    const result = FindingSchema.safeParse(input);
    assert.ok(result.success, "Finding with out-of-bounds confidence should still pass");
    assert.equal(result.data.confidence, undefined, "Confidence > 1.0 should be stripped to undefined");
  });

  it("strips negative confidence", () => {
    const input = {
      id: "F001",
      severity: "HIGH",
      category: "security",
      confidence: -0.1,
    };

    const result = FindingSchema.safeParse(input);
    assert.ok(result.success, "Finding with negative confidence should still pass");
    assert.equal(result.data.confidence, undefined, "Negative confidence should be stripped to undefined");
  });

  it("preserves valid confidence 0.85", () => {
    const input = {
      id: "F001",
      severity: "HIGH",
      category: "security",
      confidence: 0.85,
    };

    const result = FindingSchema.safeParse(input);
    assert.ok(result.success, "Finding with valid confidence should pass");
    assert.equal(result.data.confidence, 0.85, "Valid confidence should be preserved");
  });

  it("preserves enrichment fields via passthrough (faang_parallel, metaphor)", () => {
    const input = {
      id: "F001",
      severity: "PRAISE",
      category: "architecture",
      faang_parallel: "Google's Zanzibar authorization system uses similar hierarchical patterns",
      metaphor: "Like a symphony conductor coordinating independent instruments",
      teachable_moment: "Dependency inversion enables testing without mocks",
      connection: "Same pattern as the service mesh in Sprint 45",
    };

    const result = FindingSchema.safeParse(input);
    assert.ok(result.success, "Finding with enrichment fields should pass");
    const data = result.data as Record<string, unknown>;
    assert.equal(data.faang_parallel, input.faang_parallel, "faang_parallel should be preserved");
    assert.equal(data.metaphor, input.metaphor, "metaphor should be preserved");
    assert.equal(data.teachable_moment, input.teachable_moment, "teachable_moment should be preserved");
    assert.equal(data.connection, input.connection, "connection should be preserved");
  });

  it("strips string confidence (wrong type)", () => {
    const input = {
      id: "F001",
      severity: "LOW",
      category: "style",
      confidence: "high",
    };

    const result = FindingSchema.safeParse(input);
    assert.ok(result.success, "Finding with string confidence should still pass");
    assert.equal(result.data.confidence, undefined, "String confidence should be stripped");
  });

  it("preserves boundary confidence values 0.0 and 1.0", () => {
    const inputZero = { id: "F001", severity: "LOW", category: "style", confidence: 0.0 };
    const inputOne = { id: "F002", severity: "LOW", category: "style", confidence: 1.0 };

    const resultZero = FindingSchema.safeParse(inputZero);
    const resultOne = FindingSchema.safeParse(inputOne);

    assert.ok(resultZero.success);
    assert.equal(resultZero.data.confidence, 0.0, "Confidence 0.0 should be preserved");
    assert.ok(resultOne.success);
    assert.equal(resultOne.data.confidence, 1.0, "Confidence 1.0 should be preserved");
  });
});

describe("FindingsBlockSchema", () => {
  it("validates complete findings block", () => {
    const input = {
      schema_version: 1,
      findings: [
        { id: "F001", severity: "HIGH", category: "security", confidence: 0.9 },
        { id: "F002", severity: "PRAISE", category: "quality" },
      ],
    };

    const result = FindingsBlockSchema.safeParse(input);
    assert.ok(result.success, "Valid findings block should pass");
    assert.equal(result.data.schema_version, 1);
    assert.equal(result.data.findings.length, 2);
  });

  it("rejects block without schema_version", () => {
    const input = {
      findings: [
        { id: "F001", severity: "HIGH", category: "security" },
      ],
    };

    const result = FindingsBlockSchema.safeParse(input);
    assert.ok(!result.success, "Block without schema_version should be rejected");
  });

  it("rejects block with non-array findings", () => {
    const input = {
      schema_version: 1,
      findings: "not an array",
    };

    const result = FindingsBlockSchema.safeParse(input);
    assert.ok(!result.success, "Block with non-array findings should be rejected");
  });

  it("rejects block with invalid finding inside array", () => {
    const input = {
      schema_version: 1,
      findings: [
        { severity: "HIGH", category: "security" }, // missing id
      ],
    };

    const result = FindingsBlockSchema.safeParse(input);
    assert.ok(!result.success, "Block containing invalid finding should be rejected");
  });
});

describe("EnrichmentOptions equivalence", () => {
  const sampleFindings = JSON.stringify({
    schema_version: 1,
    findings: [
      { id: "F001", title: "Test", severity: "HIGH", category: "security", file: "src/x.ts:1", description: "d", suggestion: "s" },
    ],
  });

  const makeItem = () => ({
    owner: "myorg",
    repo: "myrepo",
    pr: { number: 42, title: "Add feature", headSha: "abc", baseBranch: "main", labels: [] as string[], author: "dev" },
    files: [
      { filename: "src/a.ts", status: "modified" as const, additions: 5, deletions: 3, patch: "+code" },
    ],
    hash: "h",
  });

  it("options object produces identical output to positional params", () => {
    const template = new PRReviewTemplate(mockGitProvider(), mockHasher(), mockConfig());
    const item = makeItem();
    const persona = "You are a code reviewer.";
    const truncationContext = { filesExcluded: 3, totalFiles: 10 };
    const personaMetadata = { id: "bridgebuilder", version: "1.0.0", hash: "abc123" };
    const ecosystemContext = {
      patterns: [{ repo: "core/auth", pr: 99, pattern: "JWT rotation", connection: "Same pattern" }],
      lastUpdated: "2026-02-25T12:00:00Z",
    };

    // Old-style: positional params (deprecated wrapper)
    const oldResult = template.buildEnrichmentPrompt(
      sampleFindings, item, persona, truncationContext, personaMetadata, ecosystemContext,
    );

    // New-style: options object
    const options: EnrichmentOptions = {
      findingsJSON: sampleFindings,
      item,
      persona,
      truncationContext,
      personaMetadata,
      ecosystemContext,
    };
    const newResult = template.buildEnrichmentPrompt(options);

    assert.equal(oldResult.systemPrompt, newResult.systemPrompt, "System prompts should be identical");
    assert.equal(oldResult.userPrompt, newResult.userPrompt, "User prompts should be identical");
  });

  it("deprecated wrapper delegates correctly with minimal params", () => {
    const template = new PRReviewTemplate(mockGitProvider(), mockHasher(), mockConfig());
    const item = makeItem();
    const persona = "reviewer";

    // Old-style: minimal params (no optional args)
    const oldResult = template.buildEnrichmentPrompt(sampleFindings, item, persona);

    // New-style: options object with only required fields
    const options: EnrichmentOptions = {
      findingsJSON: sampleFindings,
      item,
      persona,
    };
    const newResult = template.buildEnrichmentPrompt(options);

    assert.equal(oldResult.systemPrompt, newResult.systemPrompt, "System prompts should match");
    assert.equal(oldResult.userPrompt, newResult.userPrompt, "User prompts should match");
  });
});
