/**
 * Tests for Beads Label Constants and Utilities
 *
 * @module beads/__tests__/labels
 */

import { describe, it, expect } from "vitest";
import {
  LABELS,
  type BeadLabel,
  type RunState,
  type SprintState,
  createSameIssueLabel,
  parseSameIssueCount,
  createSessionLabel,
  createHandoffLabel,
  hasLabel,
  hasLabelWithPrefix,
  getLabelsWithPrefix,
  deriveRunState,
  deriveSprintState,
} from "../labels";

// =============================================================================
// LABELS Constant Tests
// =============================================================================

describe("LABELS", () => {
  describe("Run Lifecycle Labels", () => {
    it("should have RUN_CURRENT label", () => {
      expect(LABELS.RUN_CURRENT).toBe("run:current");
    });

    it("should have RUN_EPIC label", () => {
      expect(LABELS.RUN_EPIC).toBe("run:epic");
    });
  });

  describe("Sprint State Labels", () => {
    it("should have SPRINT_IN_PROGRESS label", () => {
      expect(LABELS.SPRINT_IN_PROGRESS).toBe("sprint:in_progress");
    });

    it("should have SPRINT_PENDING label", () => {
      expect(LABELS.SPRINT_PENDING).toBe("sprint:pending");
    });

    it("should have SPRINT_COMPLETE label", () => {
      expect(LABELS.SPRINT_COMPLETE).toBe("sprint:complete");
    });
  });

  describe("Circuit Breaker Labels", () => {
    it("should have CIRCUIT_BREAKER label", () => {
      expect(LABELS.CIRCUIT_BREAKER).toBe("circuit-breaker");
    });

    it("should have SAME_ISSUE_PREFIX", () => {
      expect(LABELS.SAME_ISSUE_PREFIX).toBe("same-issue-");
    });
  });

  describe("Session Labels", () => {
    it("should have SESSION_PREFIX", () => {
      expect(LABELS.SESSION_PREFIX).toBe("session:");
    });

    it("should have HANDOFF_PREFIX", () => {
      expect(LABELS.HANDOFF_PREFIX).toBe("handoff:");
    });
  });

  describe("Type Labels", () => {
    it("should have TYPE_EPIC label", () => {
      expect(LABELS.TYPE_EPIC).toBe("epic");
    });

    it("should have TYPE_SPRINT label", () => {
      expect(LABELS.TYPE_SPRINT).toBe("sprint");
    });

    it("should have TYPE_TASK label", () => {
      expect(LABELS.TYPE_TASK).toBe("task");
    });
  });

  describe("Status Labels", () => {
    it("should have STATUS_BLOCKED label", () => {
      expect(LABELS.STATUS_BLOCKED).toBe("blocked");
    });

    it("should have STATUS_READY label", () => {
      expect(LABELS.STATUS_READY).toBe("ready");
    });

    it("should have SECURITY label", () => {
      expect(LABELS.SECURITY).toBe("security");
    });
  });

  it("should be immutable (as const)", () => {
    // TypeScript const assertion makes the object readonly
    // This test verifies the values exist and are strings
    const labelKeys = Object.keys(LABELS);
    expect(labelKeys.length).toBeGreaterThan(0);

    for (const key of labelKeys) {
      const value = LABELS[key as keyof typeof LABELS];
      expect(typeof value).toBe("string");
    }
  });
});

// =============================================================================
// Label Utility Function Tests
// =============================================================================

describe("createSameIssueLabel", () => {
  it("should create label with count", () => {
    expect(createSameIssueLabel(1)).toBe("same-issue-1x");
    expect(createSameIssueLabel(2)).toBe("same-issue-2x");
    expect(createSameIssueLabel(3)).toBe("same-issue-3x");
    expect(createSameIssueLabel(10)).toBe("same-issue-10x");
  });

  it("should handle zero", () => {
    expect(createSameIssueLabel(0)).toBe("same-issue-0x");
  });
});

describe("parseSameIssueCount", () => {
  it("should extract count from valid label", () => {
    expect(parseSameIssueCount("same-issue-1x")).toBe(1);
    expect(parseSameIssueCount("same-issue-3x")).toBe(3);
    expect(parseSameIssueCount("same-issue-10x")).toBe(10);
    expect(parseSameIssueCount("same-issue-99x")).toBe(99);
  });

  it("should return null for non-same-issue labels", () => {
    expect(parseSameIssueCount("sprint:in_progress")).toBeNull();
    expect(parseSameIssueCount("run:current")).toBeNull();
    expect(parseSameIssueCount("epic")).toBeNull();
  });

  it("should return null for malformed same-issue labels", () => {
    expect(parseSameIssueCount("same-issue-")).toBeNull();
    expect(parseSameIssueCount("same-issue-abc")).toBeNull();
    expect(parseSameIssueCount("same-issue")).toBeNull();
  });

  it("should handle edge cases", () => {
    expect(parseSameIssueCount("same-issue-0x")).toBe(0);
  });
});

describe("createSessionLabel", () => {
  it("should create session label with ID", () => {
    expect(createSessionLabel("abc123")).toBe("session:abc123");
    expect(createSessionLabel("session-1")).toBe("session:session-1");
  });

  it("should handle UUIDs", () => {
    expect(createSessionLabel("550e8400-e29b-41d4-a716-446655440000")).toBe(
      "session:550e8400-e29b-41d4-a716-446655440000",
    );
  });
});

describe("createHandoffLabel", () => {
  it("should create handoff label with source session", () => {
    expect(createHandoffLabel("abc123")).toBe("handoff:abc123");
    expect(createHandoffLabel("prev-session")).toBe("handoff:prev-session");
  });
});

// =============================================================================
// Label Query Function Tests
// =============================================================================

describe("hasLabel", () => {
  const testLabels = ["sprint:in_progress", "run:current", "epic", "security"];

  it("should return true when label exists", () => {
    expect(hasLabel(testLabels, "sprint:in_progress")).toBe(true);
    expect(hasLabel(testLabels, "epic")).toBe(true);
    expect(hasLabel(testLabels, "security")).toBe(true);
  });

  it("should return false when label does not exist", () => {
    expect(hasLabel(testLabels, "sprint:complete")).toBe(false);
    expect(hasLabel(testLabels, "blocked")).toBe(false);
    expect(hasLabel(testLabels, "nonexistent")).toBe(false);
  });

  it("should handle empty arrays", () => {
    expect(hasLabel([], "sprint:in_progress")).toBe(false);
  });

  it("should be case-sensitive", () => {
    expect(hasLabel(testLabels, "EPIC")).toBe(false);
    expect(hasLabel(testLabels, "Sprint:in_progress")).toBe(false);
  });
});

describe("hasLabelWithPrefix", () => {
  const testLabels = ["sprint:in_progress", "session:abc123", "epic"];

  it("should return true when any label has prefix", () => {
    expect(hasLabelWithPrefix(testLabels, "sprint:")).toBe(true);
    expect(hasLabelWithPrefix(testLabels, "session:")).toBe(true);
  });

  it("should return false when no label has prefix", () => {
    expect(hasLabelWithPrefix(testLabels, "run:")).toBe(false);
    expect(hasLabelWithPrefix(testLabels, "handoff:")).toBe(false);
  });

  it("should handle empty arrays", () => {
    expect(hasLabelWithPrefix([], "sprint:")).toBe(false);
  });

  it("should match exact starts", () => {
    expect(hasLabelWithPrefix(testLabels, "epi")).toBe(true); // epic starts with epi
    expect(hasLabelWithPrefix(testLabels, "pic")).toBe(false); // nothing starts with pic
  });
});

describe("getLabelsWithPrefix", () => {
  const testLabels = [
    "sprint:in_progress",
    "sprint:pending",
    "session:abc123",
    "epic",
  ];

  it("should return all labels matching prefix", () => {
    expect(getLabelsWithPrefix(testLabels, "sprint:")).toEqual([
      "sprint:in_progress",
      "sprint:pending",
    ]);
  });

  it("should return single matching label", () => {
    expect(getLabelsWithPrefix(testLabels, "session:")).toEqual([
      "session:abc123",
    ]);
  });

  it("should return empty array when no matches", () => {
    expect(getLabelsWithPrefix(testLabels, "run:")).toEqual([]);
    expect(getLabelsWithPrefix(testLabels, "handoff:")).toEqual([]);
  });

  it("should handle empty arrays", () => {
    expect(getLabelsWithPrefix([], "sprint:")).toEqual([]);
  });
});

// =============================================================================
// State Derivation Tests
// =============================================================================

describe("deriveRunState", () => {
  it("should return HALTED when circuit-breaker present", () => {
    const labels = [LABELS.RUN_CURRENT, LABELS.CIRCUIT_BREAKER];
    expect(deriveRunState(labels)).toBe("HALTED");
  });

  it("should return HALTED even with other labels", () => {
    const labels = [
      LABELS.RUN_CURRENT,
      LABELS.SPRINT_IN_PROGRESS,
      LABELS.CIRCUIT_BREAKER,
    ];
    expect(deriveRunState(labels)).toBe("HALTED");
  });

  it("should return COMPLETE when sprint:complete present (no circuit-breaker)", () => {
    const labels = [LABELS.RUN_EPIC, LABELS.SPRINT_COMPLETE];
    expect(deriveRunState(labels)).toBe("COMPLETE");
  });

  it("should return RUNNING when run:current present (no circuit-breaker, no complete)", () => {
    const labels = [LABELS.RUN_CURRENT, LABELS.SPRINT_IN_PROGRESS];
    expect(deriveRunState(labels)).toBe("RUNNING");
  });

  it("should return READY when no state labels present", () => {
    const labels = [LABELS.TYPE_EPIC];
    expect(deriveRunState(labels)).toBe("READY");
  });

  it("should return READY for empty labels", () => {
    expect(deriveRunState([])).toBe("READY");
  });

  describe("priority order", () => {
    it("should prioritize HALTED over COMPLETE", () => {
      const labels = [LABELS.CIRCUIT_BREAKER, LABELS.SPRINT_COMPLETE];
      expect(deriveRunState(labels)).toBe("HALTED");
    });

    it("should prioritize COMPLETE over RUNNING", () => {
      const labels = [LABELS.SPRINT_COMPLETE, LABELS.RUN_CURRENT];
      expect(deriveRunState(labels)).toBe("COMPLETE");
    });

    it("should prioritize RUNNING over READY", () => {
      const labels = [LABELS.RUN_CURRENT];
      expect(deriveRunState(labels)).toBe("RUNNING");
    });
  });
});

describe("deriveSprintState", () => {
  it("should return complete when sprint:complete present", () => {
    const labels = [LABELS.SPRINT_COMPLETE, LABELS.TYPE_SPRINT];
    expect(deriveSprintState(labels)).toBe("complete");
  });

  it("should return in_progress when sprint:in_progress present (no complete)", () => {
    const labels = [LABELS.SPRINT_IN_PROGRESS, LABELS.TYPE_SPRINT];
    expect(deriveSprintState(labels)).toBe("in_progress");
  });

  it("should return pending when no sprint state labels", () => {
    const labels = [LABELS.TYPE_SPRINT, LABELS.STATUS_READY];
    expect(deriveSprintState(labels)).toBe("pending");
  });

  it("should return pending for empty labels", () => {
    expect(deriveSprintState([])).toBe("pending");
  });

  describe("priority order", () => {
    it("should prioritize complete over in_progress", () => {
      const labels = [LABELS.SPRINT_COMPLETE, LABELS.SPRINT_IN_PROGRESS];
      expect(deriveSprintState(labels)).toBe("complete");
    });

    it("should prioritize in_progress over pending", () => {
      const labels = [LABELS.SPRINT_IN_PROGRESS, LABELS.SPRINT_PENDING];
      expect(deriveSprintState(labels)).toBe("in_progress");
    });
  });
});

// =============================================================================
// Type Tests
// =============================================================================

describe("Types", () => {
  it("BeadLabel type should be assignable from LABELS values", () => {
    // TypeScript compilation test - these should not error
    const label1: BeadLabel = LABELS.RUN_CURRENT;
    const label2: BeadLabel = LABELS.SPRINT_IN_PROGRESS;
    const label3: BeadLabel = LABELS.CIRCUIT_BREAKER;

    expect(label1).toBe("run:current");
    expect(label2).toBe("sprint:in_progress");
    expect(label3).toBe("circuit-breaker");
  });

  it("RunState type should cover all states", () => {
    const states: RunState[] = ["READY", "RUNNING", "HALTED", "COMPLETE"];
    expect(states).toHaveLength(4);
  });

  it("SprintState type should cover all states", () => {
    const states: SprintState[] = ["pending", "in_progress", "complete"];
    expect(states).toHaveLength(3);
  });
});

// =============================================================================
// Integration Tests
// =============================================================================

describe("Integration", () => {
  it("should correctly track run lifecycle", () => {
    // Initial state - no run
    let labels: string[] = [];
    expect(deriveRunState(labels)).toBe("READY");

    // Start run
    labels = [LABELS.RUN_CURRENT, LABELS.RUN_EPIC];
    expect(deriveRunState(labels)).toBe("RUNNING");

    // Halt with circuit breaker
    labels = [...labels, LABELS.CIRCUIT_BREAKER];
    expect(deriveRunState(labels)).toBe("HALTED");

    // Resume (remove circuit breaker)
    labels = labels.filter((l) => l !== LABELS.CIRCUIT_BREAKER);
    expect(deriveRunState(labels)).toBe("RUNNING");

    // Complete
    labels = [...labels, LABELS.SPRINT_COMPLETE];
    expect(deriveRunState(labels)).toBe("COMPLETE");
  });

  it("should correctly track sprint lifecycle", () => {
    // Initial - pending
    let labels = [LABELS.TYPE_SPRINT, LABELS.SPRINT_PENDING];
    expect(deriveSprintState(labels)).toBe("pending");

    // Start implementation
    labels = [LABELS.TYPE_SPRINT, LABELS.SPRINT_IN_PROGRESS];
    expect(deriveSprintState(labels)).toBe("in_progress");

    // Complete
    labels = [LABELS.TYPE_SPRINT, LABELS.SPRINT_COMPLETE];
    expect(deriveSprintState(labels)).toBe("complete");
  });

  it("should track same-issue count progression", () => {
    // First occurrence
    expect(createSameIssueLabel(1)).toBe("same-issue-1x");
    expect(parseSameIssueCount("same-issue-1x")).toBe(1);

    // Increment
    const label = "same-issue-2x";
    const count = parseSameIssueCount(label);
    expect(count).toBe(2);

    const nextLabel = createSameIssueLabel((count ?? 0) + 1);
    expect(nextLabel).toBe("same-issue-3x");
  });

  it("should track session handoffs", () => {
    const session1 = "session-abc";
    const session2 = "session-def";

    const session1Label = createSessionLabel(session1);
    const handoffLabel = createHandoffLabel(session1);
    const session2Label = createSessionLabel(session2);

    expect(session1Label).toBe("session:session-abc");
    expect(handoffLabel).toBe("handoff:session-abc");
    expect(session2Label).toBe("session:session-def");

    // Verify we can query by prefix
    const allLabels = [session1Label, handoffLabel, session2Label, LABELS.RUN_CURRENT];

    expect(getLabelsWithPrefix(allLabels, LABELS.SESSION_PREFIX)).toEqual([
      "session:session-abc",
      "session:session-def",
    ]);
    expect(getLabelsWithPrefix(allLabels, LABELS.HANDOFF_PREFIX)).toEqual([
      "handoff:session-abc",
    ]);
  });
});
