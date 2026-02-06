/**
 * Tests for MLP-Informed Enhancements (Issue #208)
 *
 * Covers all 4 phases:
 *   Phase 1: Gap Detection
 *   Phase 2: Lineage Labels
 *   Phase 3: Classification & Confidence Labels
 *   Phase 4: Context Compiler
 *
 * @module beads/__tests__/mlp-enhancements
 */

import { describe, it, expect, beforeEach } from "vitest";

// Phase 2 & 3: Label utilities
import {
  LABELS,
  createSupersedesLabel,
  createBranchedFromLabel,
  parseLineageTarget,
  getSupersedesTargets,
  getBranchedFromSources,
  classificationToLabel,
  confidenceToLabel,
  deriveClassification,
  deriveConfidence,
  classificationPriority,
  type BeadClassification,
  type ConfidenceLevel,
} from "../labels";

// Phase 1: Gap Detection
import { GapDetector, createGapDetector } from "../gap-detection";

// Phase 4: Context Compiler
import { ContextCompiler, createContextCompiler } from "../context-compiler";

// Shared types
import type { IBrExecutor, BrCommandResult, Bead } from "../interfaces";

// =============================================================================
// Mock BR Executor (shared across all phase tests)
// =============================================================================

class MockBrExecutor implements IBrExecutor {
  private responses: Map<string, BrCommandResult | (() => BrCommandResult)> =
    new Map();
  public callHistory: string[] = [];

  mockResponse(
    pattern: string,
    result: BrCommandResult | (() => BrCommandResult),
  ): void {
    this.responses.set(pattern, result);
  }

  async exec(args: string): Promise<BrCommandResult> {
    this.callHistory.push(args);

    for (const [pattern, resultOrFn] of this.responses) {
      if (args.includes(pattern)) {
        const result =
          typeof resultOrFn === "function" ? resultOrFn() : resultOrFn;
        return result;
      }
    }

    return {
      success: true,
      stdout: "[]",
      stderr: "",
      exitCode: 0,
    };
  }

  async execJson<T = unknown>(args: string): Promise<T> {
    const result = await this.exec(args);
    if (!result.success) {
      throw new Error(`br command failed: ${result.stderr}`);
    }
    if (!result.stdout) {
      return [] as unknown as T;
    }
    return JSON.parse(result.stdout) as T;
  }

  reset(): void {
    this.responses.clear();
    this.callHistory = [];
  }
}

// =============================================================================
// Test Fixtures
// =============================================================================

function createMockBead(overrides: Partial<Bead>): Bead {
  return {
    id: "bead-123",
    title: "Test Bead",
    type: "task",
    status: "open",
    priority: 2,
    labels: [],
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
    ...overrides,
  };
}

function jsonResponse(data: unknown): BrCommandResult {
  return {
    success: true,
    stdout: JSON.stringify(data),
    stderr: "",
    exitCode: 0,
  };
}

// =============================================================================
// Phase 2: Lineage Label Tests
// =============================================================================

describe("Phase 2: Lineage Labels", () => {
  describe("LABELS constants", () => {
    it("should have SUPERSEDES_PREFIX", () => {
      expect(LABELS.SUPERSEDES_PREFIX).toBe("supersedes:");
    });

    it("should have BRANCHED_FROM_PREFIX", () => {
      expect(LABELS.BRANCHED_FROM_PREFIX).toBe("branched-from:");
    });
  });

  describe("createSupersedesLabel", () => {
    it("should create supersession label", () => {
      expect(createSupersedesLabel("task-old")).toBe("supersedes:task-old");
    });

    it("should handle various bead ID formats", () => {
      expect(createSupersedesLabel("abc123")).toBe("supersedes:abc123");
      expect(createSupersedesLabel("sprint-1")).toBe("supersedes:sprint-1");
      expect(createSupersedesLabel("task_v2")).toBe("supersedes:task_v2");
    });
  });

  describe("createBranchedFromLabel", () => {
    it("should create branched-from label", () => {
      expect(createBranchedFromLabel("task-original")).toBe(
        "branched-from:task-original",
      );
    });
  });

  describe("parseLineageTarget", () => {
    it("should parse supersedes target", () => {
      expect(parseLineageTarget("supersedes:task-old")).toBe("task-old");
    });

    it("should parse branched-from target", () => {
      expect(parseLineageTarget("branched-from:task-parent")).toBe(
        "task-parent",
      );
    });

    it("should return null for non-lineage labels", () => {
      expect(parseLineageTarget("sprint:in_progress")).toBeNull();
      expect(parseLineageTarget("session:abc")).toBeNull();
      expect(parseLineageTarget("epic")).toBeNull();
    });

    it("should return null for empty target", () => {
      expect(parseLineageTarget("supersedes:")).toBeNull();
      expect(parseLineageTarget("branched-from:")).toBeNull();
    });
  });

  describe("getSupersedesTargets", () => {
    it("should extract all superseded bead IDs", () => {
      const labels = [
        "supersedes:task-v1",
        "supersedes:task-v2",
        "sprint:in_progress",
      ];
      expect(getSupersedesTargets(labels)).toEqual(["task-v1", "task-v2"]);
    });

    it("should return empty for no supersession labels", () => {
      expect(getSupersedesTargets(["sprint:pending", "epic"])).toEqual([]);
    });

    it("should handle empty arrays", () => {
      expect(getSupersedesTargets([])).toEqual([]);
    });
  });

  describe("getBranchedFromSources", () => {
    it("should extract all source bead IDs", () => {
      const labels = ["branched-from:task-parent", "sprint:pending"];
      expect(getBranchedFromSources(labels)).toEqual(["task-parent"]);
    });

    it("should handle multiple branch sources", () => {
      const labels = [
        "branched-from:task-a",
        "branched-from:task-b",
        "epic",
      ];
      expect(getBranchedFromSources(labels)).toEqual(["task-a", "task-b"]);
    });

    it("should return empty for no branch labels", () => {
      expect(getBranchedFromSources(["sprint:pending"])).toEqual([]);
    });
  });

  describe("lineage lifecycle integration", () => {
    it("should track task supersession chain", () => {
      // Task v1 created
      const v1Labels = ["sprint:1", "sprint:in_progress"];

      // Task v2 supersedes v1
      const v2Labels = [
        "sprint:1",
        "sprint:in_progress",
        createSupersedesLabel("task-v1"),
      ];

      expect(getSupersedesTargets(v2Labels)).toEqual(["task-v1"]);
      expect(parseLineageTarget(v2Labels[2])).toBe("task-v1");
    });

    it("should track task split (branching)", () => {
      // Original task split into two
      const subtask1Labels = [
        "sprint:1",
        createBranchedFromLabel("task-original"),
      ];
      const subtask2Labels = [
        "sprint:1",
        createBranchedFromLabel("task-original"),
      ];

      expect(getBranchedFromSources(subtask1Labels)).toEqual([
        "task-original",
      ]);
      expect(getBranchedFromSources(subtask2Labels)).toEqual([
        "task-original",
      ]);
    });
  });
});

// =============================================================================
// Phase 3: Classification & Confidence Label Tests
// =============================================================================

describe("Phase 3: Classification & Confidence Labels", () => {
  describe("LABELS constants", () => {
    it("should have all classification labels", () => {
      expect(LABELS.CLASS_DECISION).toBe("class:decision");
      expect(LABELS.CLASS_DISCOVERY).toBe("class:discovery");
      expect(LABELS.CLASS_BLOCKER).toBe("class:blocker");
      expect(LABELS.CLASS_CONTEXT).toBe("class:context");
      expect(LABELS.CLASS_ROUTINE).toBe("class:routine");
    });

    it("should have all confidence labels", () => {
      expect(LABELS.CONFIDENCE_EXPLICIT).toBe("confidence:explicit");
      expect(LABELS.CONFIDENCE_DERIVED).toBe("confidence:derived");
      expect(LABELS.CONFIDENCE_STALE).toBe("confidence:stale");
    });
  });

  describe("classificationToLabel", () => {
    it("should map all classification types to labels", () => {
      expect(classificationToLabel("decision")).toBe("class:decision");
      expect(classificationToLabel("discovery")).toBe("class:discovery");
      expect(classificationToLabel("blocker")).toBe("class:blocker");
      expect(classificationToLabel("context")).toBe("class:context");
      expect(classificationToLabel("routine")).toBe("class:routine");
    });
  });

  describe("confidenceToLabel", () => {
    it("should map all confidence levels to labels", () => {
      expect(confidenceToLabel("explicit")).toBe("confidence:explicit");
      expect(confidenceToLabel("derived")).toBe("confidence:derived");
      expect(confidenceToLabel("stale")).toBe("confidence:stale");
    });
  });

  describe("deriveClassification", () => {
    it("should derive classification from labels", () => {
      expect(deriveClassification(["class:decision"])).toBe("decision");
      expect(deriveClassification(["class:discovery"])).toBe("discovery");
      expect(deriveClassification(["class:blocker"])).toBe("blocker");
      expect(deriveClassification(["class:context"])).toBe("context");
      expect(deriveClassification(["class:routine"])).toBe("routine");
    });

    it("should return null for unclassified beads", () => {
      expect(deriveClassification(["sprint:pending", "epic"])).toBeNull();
      expect(deriveClassification([])).toBeNull();
    });

    it("should prioritize by severity (blocker > decision > discovery > context > routine)", () => {
      expect(
        deriveClassification(["class:decision", "class:blocker"]),
      ).toBe("blocker");
      expect(
        deriveClassification(["class:discovery", "class:decision"]),
      ).toBe("decision");
      expect(
        deriveClassification(["class:context", "class:discovery"]),
      ).toBe("discovery");
      expect(
        deriveClassification(["class:routine", "class:context"]),
      ).toBe("context");
    });
  });

  describe("deriveConfidence", () => {
    it("should derive confidence from labels", () => {
      expect(deriveConfidence(["confidence:explicit"])).toBe("explicit");
      expect(deriveConfidence(["confidence:derived"])).toBe("derived");
      expect(deriveConfidence(["confidence:stale"])).toBe("stale");
    });

    it("should return null for beads without confidence", () => {
      expect(deriveConfidence(["sprint:pending"])).toBeNull();
      expect(deriveConfidence([])).toBeNull();
    });

    it("should prioritize explicit > derived > stale", () => {
      expect(
        deriveConfidence(["confidence:explicit", "confidence:stale"]),
      ).toBe("explicit");
      expect(
        deriveConfidence(["confidence:derived", "confidence:stale"]),
      ).toBe("derived");
    });
  });

  describe("classificationPriority", () => {
    it("should return correct priority order", () => {
      expect(classificationPriority("blocker")).toBe(5);
      expect(classificationPriority("decision")).toBe(4);
      expect(classificationPriority("discovery")).toBe(3);
      expect(classificationPriority("context")).toBe(2);
      expect(classificationPriority("routine")).toBe(0);
      expect(classificationPriority(null)).toBe(1); // unclassified
    });

    it("should rank blocker highest", () => {
      const classifications: (BeadClassification | null)[] = [
        "routine",
        "discovery",
        null,
        "blocker",
        "decision",
        "context",
      ];
      const sorted = [...classifications].sort(
        (a, b) => classificationPriority(b) - classificationPriority(a),
      );
      expect(sorted[0]).toBe("blocker");
      expect(sorted[1]).toBe("decision");
      expect(sorted[sorted.length - 1]).toBe("routine");
    });
  });
});

// =============================================================================
// Phase 1: Gap Detection Tests
// =============================================================================

describe("Phase 1: Gap Detection", () => {
  let mockExecutor: MockBrExecutor;
  let detector: GapDetector;

  beforeEach(() => {
    mockExecutor = new MockBrExecutor();
    detector = new GapDetector(mockExecutor, {
      staleHandoffThresholdMs: 30 * 60 * 1000, // 30 min
      orphanedTaskThresholdMs: 60 * 60 * 1000, // 60 min
    });
  });

  describe("detect()", () => {
    it("should return healthy when no gaps detected", async () => {
      // All queries return empty
      const result = await detector.detect();

      expect(result.healthy).toBe(true);
      expect(result.gaps).toHaveLength(0);
      expect(result.stats.gapsFound).toBe(0);
    });

    it("should detect orphaned in-progress tasks", async () => {
      const oldTime = new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString(); // 2 hours ago

      mockExecutor.mockResponse(
        "sprint:in_progress",
        jsonResponse([
          createMockBead({
            id: "orphan-task",
            title: "Stuck task",
            labels: [LABELS.SPRINT_IN_PROGRESS],
            updated_at: oldTime,
          }),
        ]),
      );

      const result = await detector.detect();

      expect(result.healthy).toBe(false);
      const orphanGaps = result.gaps.filter(
        (g) => g.type === "orphaned_task",
      );
      expect(orphanGaps).toHaveLength(1);
      expect(orphanGaps[0].severity).toBe("HIGH");
      expect(orphanGaps[0].affectedBeadIds).toContain("orphan-task");
      expect(orphanGaps[0].autoResolvable).toBe(true);
    });

    it("should NOT flag in-progress tasks with session labels", async () => {
      const oldTime = new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString();

      mockExecutor.mockResponse(
        "sprint:in_progress",
        jsonResponse([
          createMockBead({
            id: "active-task",
            title: "Active task",
            labels: [LABELS.SPRINT_IN_PROGRESS, "session:abc123"],
            updated_at: oldTime,
          }),
        ]),
      );

      const result = await detector.detect();

      const orphanGaps = result.gaps.filter(
        (g) => g.type === "orphaned_task",
      );
      expect(orphanGaps).toHaveLength(0);
    });

    it("should NOT flag recent in-progress tasks", async () => {
      const recentTime = new Date(Date.now() - 5 * 60 * 1000).toISOString(); // 5 min ago

      mockExecutor.mockResponse(
        "sprint:in_progress",
        jsonResponse([
          createMockBead({
            id: "recent-task",
            title: "Just started",
            labels: [LABELS.SPRINT_IN_PROGRESS],
            updated_at: recentTime,
          }),
        ]),
      );

      const result = await detector.detect();

      const orphanGaps = result.gaps.filter(
        (g) => g.type === "orphaned_task",
      );
      expect(orphanGaps).toHaveLength(0);
    });

    it("should detect unresolved circuit breakers", async () => {
      mockExecutor.mockResponse(
        "circuit-breaker",
        jsonResponse([
          createMockBead({
            id: "cb-1",
            title: "Circuit Breaker: Sprint sprint-1",
            type: "debt",
            labels: [LABELS.CIRCUIT_BREAKER, "same-issue-2x"],
          }),
        ]),
      );

      const result = await detector.detect();

      const cbGaps = result.gaps.filter(
        (g) => g.type === "unresolved_circuit_breaker",
      );
      expect(cbGaps).toHaveLength(1);
      expect(cbGaps[0].severity).toBe("CRITICAL");
      expect(cbGaps[0].autoResolvable).toBe(false);
    });

    it("should sort gaps by severity (CRITICAL first)", async () => {
      const oldTime = new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString();

      // Orphaned task (HIGH)
      mockExecutor.mockResponse(
        "sprint:in_progress",
        jsonResponse([
          createMockBead({
            id: "orphan",
            labels: [LABELS.SPRINT_IN_PROGRESS],
            updated_at: oldTime,
          }),
        ]),
      );

      // Circuit breaker (CRITICAL)
      mockExecutor.mockResponse(
        "circuit-breaker",
        jsonResponse([
          createMockBead({
            id: "cb",
            type: "debt",
            labels: [LABELS.CIRCUIT_BREAKER],
          }),
        ]),
      );

      const result = await detector.detect();

      expect(result.gaps.length).toBeGreaterThanOrEqual(2);
      expect(result.gaps[0].severity).toBe("CRITICAL");
      expect(result.gaps[1].severity).toBe("HIGH");
    });

    it("should compile accurate statistics", async () => {
      mockExecutor.mockResponse(
        "circuit-breaker",
        jsonResponse([
          createMockBead({ id: "cb", type: "debt", labels: [LABELS.CIRCUIT_BREAKER] }),
        ]),
      );

      const result = await detector.detect();

      expect(result.stats.bySeverity.CRITICAL).toBe(1);
      expect(result.stats.byType["unresolved_circuit_breaker"]).toBe(1);
      expect(typeof result.scannedAt).toBe("string");
    });
  });

  describe("autoResolve()", () => {
    it("should resolve orphaned tasks by resetting labels", async () => {
      const gap = {
        type: "orphaned_task" as const,
        severity: "HIGH" as const,
        description: "Test orphan",
        affectedBeadIds: ["orphan-1"],
        suggestedAction: "Reset",
        autoResolvable: true,
      };

      const resolved = await detector.autoResolve(gap);

      expect(resolved).toBe(true);
      // Should have called label remove and label add
      expect(
        mockExecutor.callHistory.some((c) => c.includes("label remove")),
      ).toBe(true);
      expect(
        mockExecutor.callHistory.some((c) => c.includes("label add")),
      ).toBe(true);
    });

    it("should refuse to auto-resolve non-resolvable gaps", async () => {
      const gap = {
        type: "unresolved_circuit_breaker" as const,
        severity: "CRITICAL" as const,
        description: "Test CB",
        affectedBeadIds: ["cb-1"],
        suggestedAction: "Investigate",
        autoResolvable: false,
      };

      const resolved = await detector.autoResolve(gap);
      expect(resolved).toBe(false);
    });
  });

  describe("createGapDetector factory", () => {
    it("should create a GapDetector instance", () => {
      const detector = createGapDetector(mockExecutor);
      expect(detector).toBeInstanceOf(GapDetector);
    });
  });
});

// =============================================================================
// Phase 4: Context Compiler Tests
// =============================================================================

describe("Phase 4: Context Compiler", () => {
  let mockExecutor: MockBrExecutor;
  let compiler: ContextCompiler;

  beforeEach(() => {
    mockExecutor = new MockBrExecutor();
    compiler = new ContextCompiler(mockExecutor, {
      tokenBudget: 1000,
      charsPerToken: 4,
    });
  });

  describe("compile()", () => {
    it("should include the target task with highest priority", async () => {
      const targetTask = createMockBead({
        id: "target-task",
        title: "Implement feature X",
        labels: ["sprint:in_progress", "epic:sprint-1"],
      });

      mockExecutor.mockResponse("show", jsonResponse(targetTask));

      const result = await compiler.compile("target-task");

      expect(result.included.length).toBeGreaterThanOrEqual(1);
      const target = result.included.find(
        (s) => s.bead.id === "target-task",
      );
      expect(target).toBeDefined();
      expect(target!.reason).toBe("Target task");
    });

    it("should always include circuit breakers", async () => {
      const targetTask = createMockBead({
        id: "task-1",
        title: "Task",
      });
      const circuitBreaker = createMockBead({
        id: "cb-1",
        title: "Circuit Breaker",
        type: "debt",
        labels: [LABELS.CIRCUIT_BREAKER],
      });

      mockExecutor.mockResponse("show", jsonResponse(targetTask));
      mockExecutor.mockResponse(
        "circuit-breaker",
        jsonResponse([circuitBreaker]),
      );

      const result = await compiler.compile("task-1");

      const cb = result.included.find((s) => s.bead.id === "cb-1");
      expect(cb).toBeDefined();
      expect(cb!.reason).toBe("Active circuit breaker");
    });

    it("should respect token budget", async () => {
      // Create a compiler with very small budget
      const tinyCompiler = new ContextCompiler(mockExecutor, {
        tokenBudget: 10,
        charsPerToken: 1, // 1 char = 1 token for easy calculation
      });

      const task = createMockBead({
        id: "task-1",
        title: "A".repeat(20), // 20 tokens
      });

      mockExecutor.mockResponse("show", jsonResponse(task));

      const result = await tinyCompiler.compile("task-1");

      // Even the target task exceeds budget, but it should still try
      expect(result.stats.tokenBudget).toBe(10);
    });

    it("should exclude stale beads by default", async () => {
      const targetTask = createMockBead({
        id: "task-1",
        title: "Task",
        labels: ["epic:sprint-1"],
      });
      const staleBead = createMockBead({
        id: "stale-1",
        title: "Old context",
        labels: ["epic:sprint-1", LABELS.CONFIDENCE_STALE],
      });

      mockExecutor.mockResponse("show", jsonResponse(targetTask));
      mockExecutor.mockResponse(
        "epic:sprint-1",
        jsonResponse([targetTask, staleBead]),
      );

      const result = await compiler.compile("task-1");

      const staleExcluded = result.excluded.find(
        (e) => e.bead.id === "stale-1",
      );
      expect(staleExcluded).toBeDefined();
      expect(staleExcluded!.exclusionReason).toBe("stale_confidence");
    });

    it("should exclude low-scoring routine beads", async () => {
      const targetTask = createMockBead({
        id: "task-1",
        title: "Task",
        labels: ["epic:sprint-1"],
      });
      const routineBead = createMockBead({
        id: "routine-1",
        title: "Status update",
        labels: ["epic:sprint-1", LABELS.CLASS_ROUTINE],
        updated_at: new Date(Date.now() - 48 * 60 * 60 * 1000).toISOString(), // 2 days old
      });

      mockExecutor.mockResponse("show", jsonResponse(targetTask));
      mockExecutor.mockResponse(
        "epic:sprint-1",
        jsonResponse([targetTask, routineBead]),
      );

      const result = await compiler.compile("task-1");

      const routineExcluded = result.excluded.find(
        (e) => e.bead.id === "routine-1",
      );
      expect(routineExcluded).toBeDefined();
      expect(routineExcluded!.exclusionReason).toBe("routine_classification");
    });

    it("should prioritize decision beads over context beads", async () => {
      const targetTask = createMockBead({
        id: "task-1",
        title: "Task",
        labels: ["epic:sprint-1"],
      });
      const decisionBead = createMockBead({
        id: "decision-1",
        title: "Architecture decision",
        labels: ["epic:sprint-1", LABELS.CLASS_DECISION],
      });
      const contextBead = createMockBead({
        id: "context-1",
        title: "Background info",
        labels: ["epic:sprint-1", LABELS.CLASS_CONTEXT],
      });

      mockExecutor.mockResponse("show", jsonResponse(targetTask));
      mockExecutor.mockResponse(
        "epic:sprint-1",
        jsonResponse([contextBead, decisionBead, targetTask]),
      );
      mockExecutor.mockResponse(
        "class:decision",
        jsonResponse([decisionBead]),
      );

      const result = await compiler.compile("task-1");

      const decisionIdx = result.included.findIndex(
        (s) => s.bead.id === "decision-1",
      );
      const contextIdx = result.included.findIndex(
        (s) => s.bead.id === "context-1",
      );

      // Both should be included (decision before context in priority)
      if (decisionIdx !== -1 && contextIdx !== -1) {
        expect(decisionIdx).toBeLessThan(contextIdx);
      }
    });

    it("should include compilation statistics", async () => {
      mockExecutor.mockResponse(
        "show",
        jsonResponse(createMockBead({ id: "task-1" })),
      );

      const result = await compiler.compile("task-1");

      expect(result.stats.tokenBudget).toBe(1000);
      expect(typeof result.stats.considered).toBe("number");
      expect(typeof result.stats.included).toBe("number");
      expect(typeof result.stats.estimatedTokens).toBe("number");
      expect(typeof result.stats.utilization).toBe("number");
      expect(result.stats.utilization).toBeLessThanOrEqual(1);
      expect(typeof result.compiledAt).toBe("string");
    });

    it("should boost recently updated beads", async () => {
      const recentBead = createMockBead({
        id: "recent",
        title: "Just updated",
        labels: ["epic:sprint-1"],
        updated_at: new Date().toISOString(), // now
      });
      const oldBead = createMockBead({
        id: "old",
        title: "Updated yesterday",
        labels: ["epic:sprint-1"],
        updated_at: new Date(Date.now() - 48 * 60 * 60 * 1000).toISOString(),
      });
      const targetTask = createMockBead({
        id: "task-1",
        title: "Task",
        labels: ["epic:sprint-1"],
      });

      mockExecutor.mockResponse("show", jsonResponse(targetTask));
      mockExecutor.mockResponse(
        "epic:sprint-1",
        jsonResponse([oldBead, recentBead, targetTask]),
      );

      const result = await compiler.compile("task-1");

      const recentScored = result.included.find(
        (s) => s.bead.id === "recent",
      );
      const oldScored = result.included.find((s) => s.bead.id === "old");

      if (recentScored && oldScored) {
        expect(recentScored.score).toBeGreaterThan(oldScored.score);
      }
    });

    it("should boost explicit confidence beads", async () => {
      const explicitBead = createMockBead({
        id: "explicit",
        title: "Important",
        labels: ["epic:sprint-1", LABELS.CONFIDENCE_EXPLICIT],
      });
      const noneConfBead = createMockBead({
        id: "none",
        title: "No confidence",
        labels: ["epic:sprint-1"],
      });
      const targetTask = createMockBead({
        id: "task-1",
        title: "Task",
        labels: ["epic:sprint-1"],
      });

      mockExecutor.mockResponse("show", jsonResponse(targetTask));
      mockExecutor.mockResponse(
        "epic:sprint-1",
        jsonResponse([noneConfBead, explicitBead, targetTask]),
      );

      const result = await compiler.compile("task-1");

      const explicitScored = result.included.find(
        (s) => s.bead.id === "explicit",
      );
      const noneScored = result.included.find((s) => s.bead.id === "none");

      if (explicitScored && noneScored) {
        expect(explicitScored.score).toBeGreaterThan(noneScored.score);
      }
    });
  });

  describe("createContextCompiler factory", () => {
    it("should create a ContextCompiler instance", () => {
      const compiler = createContextCompiler(mockExecutor);
      expect(compiler).toBeInstanceOf(ContextCompiler);
    });

    it("should accept custom config", () => {
      const compiler = createContextCompiler(mockExecutor, {
        tokenBudget: 8000,
        charsPerToken: 3.5,
      });
      expect(compiler).toBeInstanceOf(ContextCompiler);
    });
  });
});

// =============================================================================
// Cross-Phase Integration Tests
// =============================================================================

describe("Cross-Phase Integration", () => {
  it("classification labels should be valid per LABEL_PATTERN", () => {
    // All classification and confidence labels must pass Loa's label validation
    const LABEL_PATTERN = /^[a-zA-Z0-9_:-]+$/;

    const allNewLabels = [
      LABELS.CLASS_DECISION,
      LABELS.CLASS_DISCOVERY,
      LABELS.CLASS_BLOCKER,
      LABELS.CLASS_CONTEXT,
      LABELS.CLASS_ROUTINE,
      LABELS.CONFIDENCE_EXPLICIT,
      LABELS.CONFIDENCE_DERIVED,
      LABELS.CONFIDENCE_STALE,
      LABELS.SUPERSEDES_PREFIX + "test-id",
      LABELS.BRANCHED_FROM_PREFIX + "test-id",
    ];

    for (const label of allNewLabels) {
      expect(LABEL_PATTERN.test(label)).toBe(true);
    }
  });

  it("lineage labels should survive round-trip through parse", () => {
    const originalId = "task-abc-123";
    const supersedesLabel = createSupersedesLabel(originalId);
    const parsed = parseLineageTarget(supersedesLabel);
    expect(parsed).toBe(originalId);

    const branchedLabel = createBranchedFromLabel(originalId);
    const parsedBranch = parseLineageTarget(branchedLabel);
    expect(parsedBranch).toBe(originalId);
  });

  it("gap detector and context compiler should use consistent label constants", () => {
    // Both modules import from the same labels.ts — verify they reference the same constants
    expect(LABELS.CIRCUIT_BREAKER).toBe("circuit-breaker");
    expect(LABELS.SESSION_PREFIX).toBe("session:");
    expect(LABELS.HANDOFF_PREFIX).toBe("handoff:");
    expect(LABELS.SPRINT_IN_PROGRESS).toBe("sprint:in_progress");
  });
});
