/**
 * Tests for Beads Run State Manager
 *
 * @module beads/__tests__/run-state
 */

import { describe, it, expect, beforeEach, vi } from "vitest";
import {
  BeadsRunStateManager,
  createBeadsRunStateManager,
} from "../run-state";
import { LABELS } from "../labels";
import type {
  IBrExecutor,
  BrCommandResult,
  Bead,
} from "../interfaces";

// =============================================================================
// Mock BR Executor
// =============================================================================

/**
 * Mock BR executor for testing
 */
class MockBrExecutor implements IBrExecutor {
  private responses: Map<string, BrCommandResult | (() => BrCommandResult)> = new Map();
  public callHistory: string[] = [];

  mockResponse(pattern: string, result: BrCommandResult | (() => BrCommandResult)): void {
    this.responses.set(pattern, result);
  }

  async exec(args: string): Promise<BrCommandResult> {
    this.callHistory.push(args);

    for (const [pattern, resultOrFn] of this.responses) {
      if (args.includes(pattern)) {
        const result = typeof resultOrFn === "function" ? resultOrFn() : resultOrFn;
        return result;
      }
    }

    // Default: success with empty output
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
    created_at: "2026-01-15T10:00:00Z",
    updated_at: "2026-01-15T10:00:00Z",
    ...overrides,
  };
}

function createMockRunEpic(labels: string[] = []): Bead {
  return createMockBead({
    id: "run-001",
    title: "Run: 2026-01-15",
    type: "epic",
    labels: [LABELS.RUN_CURRENT, LABELS.RUN_EPIC, ...labels],
  });
}

function createMockSprint(
  id: string,
  sprintNum: number,
  status: "pending" | "in_progress" | "complete",
): Bead {
  const labels = [`sprint:${sprintNum}`];
  if (status === "pending") labels.push(LABELS.SPRINT_PENDING);
  else if (status === "in_progress") labels.push(LABELS.SPRINT_IN_PROGRESS);
  else labels.push(LABELS.SPRINT_COMPLETE);

  return createMockBead({
    id,
    title: `Sprint ${sprintNum}`,
    type: "epic",
    labels,
  });
}

// =============================================================================
// Tests: getRunState
// =============================================================================

describe("BeadsRunStateManager", () => {
  let mockExecutor: MockBrExecutor;
  let manager: BeadsRunStateManager;

  beforeEach(() => {
    mockExecutor = new MockBrExecutor();
    manager = new BeadsRunStateManager({ executor: mockExecutor });
  });

  describe("getRunState", () => {
    it("should return READY when no runs exist", async () => {
      mockExecutor.mockResponse(`--label '${LABELS.RUN_CURRENT}'`, {
        success: true,
        stdout: "[]",
        stderr: "",
        exitCode: 0,
      });

      const state = await manager.getRunState();
      expect(state).toBe("READY");
    });

    it("should return HALTED when run has circuit-breaker label", async () => {
      const run = createMockRunEpic([LABELS.CIRCUIT_BREAKER]);
      mockExecutor.mockResponse(`--label '${LABELS.RUN_CURRENT}'`, {
        success: true,
        stdout: JSON.stringify([run]),
        stderr: "",
        exitCode: 0,
      });

      const state = await manager.getRunState();
      expect(state).toBe("HALTED");
    });

    it("should return COMPLETE when run has sprint:complete and no pending", async () => {
      const run = createMockRunEpic([LABELS.SPRINT_COMPLETE]);
      mockExecutor.mockResponse(`--label '${LABELS.RUN_CURRENT}'`, {
        success: true,
        stdout: JSON.stringify([run]),
        stderr: "",
        exitCode: 0,
      });
      mockExecutor.mockResponse(`--label '${LABELS.SPRINT_IN_PROGRESS}'`, {
        success: true,
        stdout: "[]",
        stderr: "",
        exitCode: 0,
      });
      mockExecutor.mockResponse(`--label '${LABELS.SPRINT_PENDING}'`, {
        success: true,
        stdout: "[]",
        stderr: "",
        exitCode: 0,
      });

      const state = await manager.getRunState();
      expect(state).toBe("COMPLETE");
    });

    it("should return RUNNING when run:current exists with in_progress sprint", async () => {
      const run = createMockRunEpic();
      const sprint = createMockSprint("sprint-1", 1, "in_progress");

      mockExecutor.mockResponse(`--label '${LABELS.RUN_CURRENT}'`, {
        success: true,
        stdout: JSON.stringify([run]),
        stderr: "",
        exitCode: 0,
      });
      mockExecutor.mockResponse(`--label '${LABELS.SPRINT_IN_PROGRESS}'`, {
        success: true,
        stdout: JSON.stringify([sprint]),
        stderr: "",
        exitCode: 0,
      });

      const state = await manager.getRunState();
      expect(state).toBe("RUNNING");
    });

    it("should return RUNNING when run has pending sprints (ready for next)", async () => {
      const run = createMockRunEpic();
      const sprint = createMockSprint("sprint-1", 1, "pending");

      mockExecutor.mockResponse(`--label '${LABELS.RUN_CURRENT}'`, {
        success: true,
        stdout: JSON.stringify([run]),
        stderr: "",
        exitCode: 0,
      });
      mockExecutor.mockResponse(`--label '${LABELS.SPRINT_IN_PROGRESS}'`, {
        success: true,
        stdout: "[]",
        stderr: "",
        exitCode: 0,
      });
      mockExecutor.mockResponse(`--label '${LABELS.SPRINT_PENDING}'`, {
        success: true,
        stdout: JSON.stringify([sprint]),
        stderr: "",
        exitCode: 0,
      });

      const state = await manager.getRunState();
      expect(state).toBe("RUNNING");
    });

    it("should return READY on error (graceful degradation)", async () => {
      mockExecutor.mockResponse(`--label '${LABELS.RUN_CURRENT}'`, {
        success: false,
        stdout: "",
        stderr: "connection failed",
        exitCode: 1,
      });

      const state = await manager.getRunState();
      expect(state).toBe("READY");
    });
  });

  // ===========================================================================
  // Tests: Sprint Operations
  // ===========================================================================

  describe("getCurrentSprint", () => {
    it("should return null when no sprint in progress", async () => {
      mockExecutor.mockResponse(`--label '${LABELS.SPRINT_IN_PROGRESS}'`, {
        success: true,
        stdout: "[]",
        stderr: "",
        exitCode: 0,
      });

      const sprint = await manager.getCurrentSprint();
      expect(sprint).toBeNull();
    });

    it("should return sprint state when in progress", async () => {
      const sprint = createMockSprint("sprint-1", 1, "in_progress");
      mockExecutor.mockResponse(`--label '${LABELS.SPRINT_IN_PROGRESS}'`, {
        success: true,
        stdout: JSON.stringify([sprint]),
        stderr: "",
        exitCode: 0,
      });
      mockExecutor.mockResponse(`--label 'epic:sprint-1'`, {
        success: true,
        stdout: JSON.stringify([
          createMockBead({ id: "task-1", status: "closed" }),
          createMockBead({ id: "task-2", status: "open" }),
        ]),
        stderr: "",
        exitCode: 0,
      });

      const result = await manager.getCurrentSprint();

      expect(result).not.toBeNull();
      expect(result?.id).toBe("sprint-1");
      expect(result?.sprintNumber).toBe(1);
      expect(result?.status).toBe("in_progress");
      expect(result?.tasksTotal).toBe(2);
      expect(result?.tasksCompleted).toBe(1);
    });
  });

  describe("startSprint", () => {
    it("should remove pending and add in_progress labels", async () => {
      await manager.startSprint("sprint-1");

      expect(mockExecutor.callHistory).toContainEqual(
        expect.stringContaining(`label remove 'sprint-1' '${LABELS.SPRINT_PENDING}'`),
      );
      expect(mockExecutor.callHistory).toContainEqual(
        expect.stringContaining(`label add 'sprint-1' '${LABELS.SPRINT_IN_PROGRESS}'`),
      );
    });

    it("should reject invalid sprint IDs", async () => {
      await expect(manager.startSprint("../bad-path")).rejects.toThrow();
      await expect(manager.startSprint("sprint;rm")).rejects.toThrow();
    });
  });

  describe("completeSprint", () => {
    it("should remove in_progress, add complete, and close bead", async () => {
      await manager.completeSprint("sprint-1");

      expect(mockExecutor.callHistory).toContainEqual(
        expect.stringContaining(`label remove 'sprint-1' '${LABELS.SPRINT_IN_PROGRESS}'`),
      );
      expect(mockExecutor.callHistory).toContainEqual(
        expect.stringContaining(`label add 'sprint-1' '${LABELS.SPRINT_COMPLETE}'`),
      );
      expect(mockExecutor.callHistory).toContainEqual(
        expect.stringContaining(`close 'sprint-1'`),
      );
    });
  });

  // ===========================================================================
  // Tests: Run Operations
  // ===========================================================================

  describe("startRun", () => {
    it("should create run epic and label sprints", async () => {
      let createCallCount = 0;
      mockExecutor.mockResponse("create", () => {
        createCallCount++;
        return {
          success: true,
          stdout: JSON.stringify({ id: `created-${createCallCount}` }),
          stderr: "",
          exitCode: 0,
        };
      });

      const runId = await manager.startRun(["sprint-1", "sprint-2"]);

      expect(runId).toBe("created-1");

      // Should label each sprint
      expect(mockExecutor.callHistory).toContainEqual(
        expect.stringContaining(`label add 'sprint-1' 'sprint:1'`),
      );
      expect(mockExecutor.callHistory).toContainEqual(
        expect.stringContaining(`label add 'sprint-2' 'sprint:2'`),
      );
      expect(mockExecutor.callHistory).toContainEqual(
        expect.stringContaining(`label add 'sprint-1' '${LABELS.SPRINT_PENDING}'`),
      );
    });

    it("should validate all sprint IDs before starting", async () => {
      await expect(manager.startRun(["valid", "../invalid"])).rejects.toThrow();
    });
  });

  // ===========================================================================
  // Tests: Circuit Breaker
  // ===========================================================================

  describe("haltRun", () => {
    it("should create circuit breaker bead", async () => {
      // Mock getCurrentSprint
      mockExecutor.mockResponse(`--label '${LABELS.SPRINT_IN_PROGRESS}'`, {
        success: true,
        stdout: JSON.stringify([createMockSprint("sprint-1", 1, "in_progress")]),
        stderr: "",
        exitCode: 0,
      });

      // Mock create
      mockExecutor.mockResponse("create", {
        success: true,
        stdout: JSON.stringify({ id: "cb-001" }),
        stderr: "",
        exitCode: 0,
      });

      // Mock run query for labeling
      mockExecutor.mockResponse(`--label '${LABELS.RUN_CURRENT}' --json`, {
        success: true,
        stdout: JSON.stringify([createMockRunEpic()]),
        stderr: "",
        exitCode: 0,
      });

      const result = await manager.haltRun("Test failure");

      expect(result.beadId).toBe("cb-001");
      expect(result.sprintId).toBe("sprint-1");
      expect(result.reason).toBe("Test failure");
      expect(result.failureCount).toBe(1);
    });
  });

  describe("createCircuitBreaker", () => {
    it("should create bead with correct labels", async () => {
      mockExecutor.mockResponse("create", {
        success: true,
        stdout: JSON.stringify({ id: "cb-002" }),
        stderr: "",
        exitCode: 0,
      });
      mockExecutor.mockResponse(`--label '${LABELS.RUN_CURRENT}'`, {
        success: true,
        stdout: JSON.stringify([createMockRunEpic()]),
        stderr: "",
        exitCode: 0,
      });

      await manager.createCircuitBreaker("sprint-1", "Audit failed", 3);

      // Should create with circuit-breaker and same-issue-3x labels
      const createCall = mockExecutor.callHistory.find((c) => c.includes("create"));
      expect(createCall).toContain(LABELS.CIRCUIT_BREAKER);
      expect(createCall).toContain("same-issue-3x");
    });

    it("should add circuit-breaker label to current run", async () => {
      mockExecutor.mockResponse("create", {
        success: true,
        stdout: JSON.stringify({ id: "cb-003" }),
        stderr: "",
        exitCode: 0,
      });
      mockExecutor.mockResponse(`--label '${LABELS.RUN_CURRENT}' --json`, {
        success: true,
        stdout: JSON.stringify([createMockRunEpic()]),
        stderr: "",
        exitCode: 0,
      });

      await manager.createCircuitBreaker("sprint-1", "Error", 1);

      expect(mockExecutor.callHistory).toContainEqual(
        expect.stringContaining(`label add 'run-001' '${LABELS.CIRCUIT_BREAKER}'`),
      );
    });
  });

  describe("resumeRun", () => {
    it("should resolve all active circuit breakers", async () => {
      // Mock getActiveCircuitBreakers
      mockExecutor.mockResponse(`--label '${LABELS.CIRCUIT_BREAKER}' --status open`, {
        success: true,
        stdout: JSON.stringify([
          createMockBead({
            id: "cb-001",
            type: "debt",
            labels: [LABELS.CIRCUIT_BREAKER, "same-issue-2x"],
          }),
        ]),
        stderr: "",
        exitCode: 0,
      });

      // Mock run query
      mockExecutor.mockResponse(`--label '${LABELS.RUN_CURRENT}' --json`, {
        success: true,
        stdout: JSON.stringify([createMockRunEpic([LABELS.CIRCUIT_BREAKER])]),
        stderr: "",
        exitCode: 0,
      });

      await manager.resumeRun();

      // Should close circuit breaker and remove label from run
      expect(mockExecutor.callHistory).toContainEqual(
        expect.stringContaining(`close 'cb-001'`),
      );
      expect(mockExecutor.callHistory).toContainEqual(
        expect.stringContaining(`label remove 'run-001' '${LABELS.CIRCUIT_BREAKER}'`),
      );
    });
  });

  describe("getActiveCircuitBreakers", () => {
    it("should return empty array when no circuit breakers", async () => {
      mockExecutor.mockResponse(`--label '${LABELS.CIRCUIT_BREAKER}'`, {
        success: true,
        stdout: "[]",
        stderr: "",
        exitCode: 0,
      });

      const cbs = await manager.getActiveCircuitBreakers();
      expect(cbs).toEqual([]);
    });

    it("should parse failure count from labels", async () => {
      mockExecutor.mockResponse(`--label '${LABELS.CIRCUIT_BREAKER}'`, {
        success: true,
        stdout: JSON.stringify([
          createMockBead({
            id: "cb-001",
            type: "debt",
            labels: [LABELS.CIRCUIT_BREAKER, "same-issue-5x", "sprint:2"],
            description: "Repeated failure",
          }),
        ]),
        stderr: "",
        exitCode: 0,
      });

      const cbs = await manager.getActiveCircuitBreakers();

      expect(cbs).toHaveLength(1);
      expect(cbs[0].beadId).toBe("cb-001");
      expect(cbs[0].failureCount).toBe(5);
      expect(cbs[0].reason).toBe("Repeated failure");
    });
  });

  // ===========================================================================
  // Tests: Migration
  // ===========================================================================

  describe("migrateFromDotRun", () => {
    it("should reject paths with traversal", async () => {
      await expect(manager.migrateFromDotRun("../etc")).rejects.toThrow("traversal");
    });

    it("should return success with warning when no state.json", async () => {
      // existsSync will return false for non-existent paths
      const result = await manager.migrateFromDotRun("/nonexistent/.run");

      expect(result.success).toBe(true);
      expect(result.warnings).toContain("No .run/state.json found - nothing to migrate");
    });
  });

  // ===========================================================================
  // Tests: Factory Function
  // ===========================================================================

  describe("createBeadsRunStateManager", () => {
    it("should create manager with default config", () => {
      const manager = createBeadsRunStateManager();
      expect(manager).toBeInstanceOf(BeadsRunStateManager);
    });

    it("should accept custom config", () => {
      const manager = createBeadsRunStateManager({
        brCommand: "/custom/br",
        verbose: true,
      });
      expect(manager).toBeInstanceOf(BeadsRunStateManager);
    });
  });

  // ===========================================================================
  // Tests: Batch Query Optimization (RFC #198)
  // ===========================================================================

  describe("getSprintPlan (batch query optimization)", () => {
    it("should return sprints with correct task counts using batch query", async () => {
      const sprint1 = createMockSprint("sprint-1", 1, "complete");
      const sprint2 = createMockSprint("sprint-2", 2, "in_progress");

      // Mock epic list (single query)
      mockExecutor.mockResponse("--type epic --json", {
        success: true,
        stdout: JSON.stringify([sprint1, sprint2]),
        stderr: "",
        exitCode: 0,
      });

      // Mock batch task query (single query for ALL tasks)
      mockExecutor.mockResponse("--type task --json", {
        success: true,
        stdout: JSON.stringify([
          createMockBead({ id: "task-1", type: "task", status: "closed", labels: ["epic:sprint-1"] }),
          createMockBead({ id: "task-2", type: "task", status: "closed", labels: ["epic:sprint-1"] }),
          createMockBead({ id: "task-3", type: "task", status: "open", labels: ["epic:sprint-2"] }),
          createMockBead({ id: "task-4", type: "task", status: "closed", labels: ["epic:sprint-2"] }),
          createMockBead({ id: "task-5", type: "task", status: "open", labels: ["epic:sprint-2"] }),
        ]),
        stderr: "",
        exitCode: 0,
      });

      const plan = await manager.getSprintPlan();

      expect(plan).toHaveLength(2);

      // Sprint 1: 2 tasks, both completed
      expect(plan[0].id).toBe("sprint-1");
      expect(plan[0].sprintNumber).toBe(1);
      expect(plan[0].status).toBe("completed");
      expect(plan[0].tasksTotal).toBe(2);
      expect(plan[0].tasksCompleted).toBe(2);

      // Sprint 2: 3 tasks, 1 completed
      expect(plan[1].id).toBe("sprint-2");
      expect(plan[1].sprintNumber).toBe(2);
      expect(plan[1].status).toBe("in_progress");
      expect(plan[1].tasksTotal).toBe(3);
      expect(plan[1].tasksCompleted).toBe(1);
    });

    it("should only make 2 br subprocess calls (batch optimization)", async () => {
      const sprint1 = createMockSprint("sprint-1", 1, "pending");
      const sprint2 = createMockSprint("sprint-2", 2, "pending");
      const sprint3 = createMockSprint("sprint-3", 3, "pending");

      mockExecutor.mockResponse("--type epic --json", {
        success: true,
        stdout: JSON.stringify([sprint1, sprint2, sprint3]),
        stderr: "",
        exitCode: 0,
      });

      mockExecutor.mockResponse("--type task --json", {
        success: true,
        stdout: "[]",
        stderr: "",
        exitCode: 0,
      });

      await manager.getSprintPlan();

      // Should be exactly 2 calls: one for epics, one for tasks
      // Previously would be 1 + N (4 calls for 3 sprints)
      expect(mockExecutor.callHistory).toHaveLength(2);
      expect(mockExecutor.callHistory[0]).toContain("--type epic");
      expect(mockExecutor.callHistory[1]).toContain("--type task");
    });

    it("should filter out non-sprint epics", async () => {
      const sprintEpic = createMockSprint("sprint-1", 1, "pending");
      const nonSprintEpic = createMockBead({
        id: "run-001",
        type: "epic",
        labels: [LABELS.RUN_CURRENT, LABELS.RUN_EPIC],
      });

      mockExecutor.mockResponse("--type epic --json", {
        success: true,
        stdout: JSON.stringify([sprintEpic, nonSprintEpic]),
        stderr: "",
        exitCode: 0,
      });

      mockExecutor.mockResponse("--type task --json", {
        success: true,
        stdout: "[]",
        stderr: "",
        exitCode: 0,
      });

      const plan = await manager.getSprintPlan();

      expect(plan).toHaveLength(1);
      expect(plan[0].id).toBe("sprint-1");
    });

    it("should handle empty epic list", async () => {
      mockExecutor.mockResponse("--type epic --json", {
        success: true,
        stdout: "[]",
        stderr: "",
        exitCode: 0,
      });

      const plan = await manager.getSprintPlan();
      expect(plan).toEqual([]);

      // Should only call once (no task query needed)
      expect(mockExecutor.callHistory).toHaveLength(1);
    });
  });

  // ===========================================================================
  // Tests: Circuit Breaker Optimization (RFC #198)
  // ===========================================================================

  describe("getSameIssueCount (targeted query optimization)", () => {
    it("should use targeted query when issueHash provided", async () => {
      // Mock targeted query returning a match
      mockExecutor.mockResponse(
        `--label '${LABELS.CIRCUIT_BREAKER}' --label 'issue:abc123'`,
        {
          success: true,
          stdout: JSON.stringify([
            createMockBead({
              id: "cb-001",
              type: "debt",
              labels: [LABELS.CIRCUIT_BREAKER, "same-issue-3x", "issue:abc123"],
            }),
          ]),
          stderr: "",
          exitCode: 0,
        },
      );

      const count = await manager.getSameIssueCount("abc123");

      expect(count).toBe(3);
      // Should only make the targeted query
      expect(mockExecutor.callHistory).toHaveLength(1);
      expect(mockExecutor.callHistory[0]).toContain("issue:abc123");
    });

    it("should fallback to full scan when targeted query returns empty", async () => {
      // Mock targeted query returning empty
      mockExecutor.mockResponse(
        `--label '${LABELS.CIRCUIT_BREAKER}' --label 'issue:xyz789'`,
        {
          success: true,
          stdout: "[]",
          stderr: "",
          exitCode: 0,
        },
      );

      // Mock fallback full scan
      mockExecutor.mockResponse(
        `--label '${LABELS.CIRCUIT_BREAKER}' --json`,
        {
          success: true,
          stdout: JSON.stringify([
            createMockBead({
              id: "cb-old",
              type: "debt",
              labels: [LABELS.CIRCUIT_BREAKER, "same-issue-2x"],
            }),
          ]),
          stderr: "",
          exitCode: 0,
        },
      );

      const count = await manager.getSameIssueCount("xyz789");

      expect(count).toBe(2);
      // Should make both targeted + fallback queries
      expect(mockExecutor.callHistory).toHaveLength(2);
    });

    it("should return 0 when no circuit breakers exist", async () => {
      mockExecutor.mockResponse(`--label '${LABELS.CIRCUIT_BREAKER}'`, {
        success: true,
        stdout: "[]",
        stderr: "",
        exitCode: 0,
      });

      const count = await manager.getSameIssueCount("nonexistent");
      expect(count).toBe(0);
    });

    it("should return 0 on error (graceful degradation)", async () => {
      mockExecutor.mockResponse(`--label '${LABELS.CIRCUIT_BREAKER}'`, {
        success: false,
        stdout: "",
        stderr: "database error",
        exitCode: 1,
      });

      const count = await manager.getSameIssueCount("abc");
      expect(count).toBe(0);
    });

    it("should prevent malicious issueHash from reaching shell (injection prevention)", async () => {
      // These payloads contain shell metacharacters that must not reach exec()
      const injectionPayloads = [
        "abc'; rm -rf /; echo '",
        "abc$(whoami)",
        "abc`id`",
        "abc & cat /etc/passwd",
        "abc\"; malicious",
      ];

      for (const payload of injectionPayloads) {
        mockExecutor.callHistory = [];

        // validateLabel() throws inside the try/catch, so getSameIssueCount
        // gracefully returns 0 without the payload reaching the shell
        const count = await manager.getSameIssueCount(payload);
        expect(count).toBe(0);

        // CRITICAL: verify the malicious payload never reached the executor
        const targetedCalls = mockExecutor.callHistory.filter(
          (c) => c.includes("issue:"),
        );
        expect(targetedCalls).toHaveLength(0);
      }
    });
  });

  // ===========================================================================
  // Tests: Security
  // ===========================================================================

  describe("Security", () => {
    it("should validate beadId in all operations", async () => {
      const maliciousIds = [
        "../etc/passwd",
        "sprint;rm -rf /",
        "sprint`whoami`",
        "sprint$(cat /etc/shadow)",
      ];

      for (const id of maliciousIds) {
        await expect(manager.startSprint(id)).rejects.toThrow();
        await expect(manager.completeSprint(id)).rejects.toThrow();
        await expect(manager.createCircuitBreaker(id, "test", 1)).rejects.toThrow();
        await expect(manager.resolveCircuitBreaker(id)).rejects.toThrow();
      }
    });

    it("should not execute shell commands with unvalidated input", async () => {
      // Attempt injection through startRun
      await expect(manager.startRun(["valid", "$(whoami)"])).rejects.toThrow();

      // Check that no shell commands were executed with the malicious input
      const hasInjection = mockExecutor.callHistory.some(
        (cmd) => cmd.includes("$(") || cmd.includes("`"),
      );
      expect(hasInjection).toBe(false);
    });
  });
});
