/**
 * Beads Label Constants
 *
 * Semantic label constants for beads_rust integration.
 * These labels enable run-mode state tracking and circuit breaker management.
 *
 * @module beads/labels
 * @version 1.30.0
 * @origin Extracted from loa-beauvoir production implementation
 */

// =============================================================================
// Run Mode Labels
// =============================================================================

/**
 * Labels used for run-mode state tracking.
 *
 * The run-mode system uses beads labels instead of `.run/*.json` files
 * to track state, enabling persistence across context windows and
 * crash recovery.
 *
 * @example
 * ```typescript
 * // Mark a bead as the current run epic
 * await execBr(`label add ${beadId} ${LABELS.RUN_CURRENT}`);
 *
 * // Query current run
 * const result = await execBr(`list --label ${LABELS.RUN_CURRENT} --json`);
 * ```
 */
export const LABELS = {
  // -------------------------------------------------------------------------
  // Run Lifecycle Labels
  // -------------------------------------------------------------------------

  /**
   * Marks the epic bead representing the current active run.
   * Only one bead should have this label at a time.
   */
  RUN_CURRENT: "run:current",

  /**
   * Marks a bead as a run epic (may be historical).
   */
  RUN_EPIC: "run:epic",

  // -------------------------------------------------------------------------
  // Sprint State Labels
  // -------------------------------------------------------------------------

  /**
   * Sprint is currently being implemented.
   * Applied when /implement starts working on a sprint.
   */
  SPRINT_IN_PROGRESS: "sprint:in_progress",

  /**
   * Sprint is queued for implementation.
   * Applied to sprints in a run that haven't started yet.
   */
  SPRINT_PENDING: "sprint:pending",

  /**
   * Sprint has been completed successfully.
   * Applied when audit passes and COMPLETED marker is created.
   */
  SPRINT_COMPLETE: "sprint:complete",

  // -------------------------------------------------------------------------
  // Circuit Breaker Labels
  // -------------------------------------------------------------------------

  /**
   * Marks a bead as a circuit breaker record.
   * Circuit breakers are created when runs halt due to failures.
   */
  CIRCUIT_BREAKER: "circuit-breaker",

  /**
   * Prefix for same-issue tracking.
   * Format: same-issue-{count}x (e.g., 'same-issue-3x')
   */
  SAME_ISSUE_PREFIX: "same-issue-",

  // -------------------------------------------------------------------------
  // Session Labels
  // -------------------------------------------------------------------------

  /**
   * Prefix for session tracking.
   * Format: session:{session-id}
   */
  SESSION_PREFIX: "session:",

  /**
   * Prefix for handoff tracking.
   * Format: handoff:{from-session}
   */
  HANDOFF_PREFIX: "handoff:",

  // -------------------------------------------------------------------------
  // Type Labels
  // -------------------------------------------------------------------------

  /**
   * Marks a bead as an epic (container for sprints/tasks).
   */
  TYPE_EPIC: "epic",

  /**
   * Marks a bead as a sprint.
   */
  TYPE_SPRINT: "sprint",

  /**
   * Marks a bead as a task.
   */
  TYPE_TASK: "task",

  // -------------------------------------------------------------------------
  // Status Labels (for filtering)
  // -------------------------------------------------------------------------

  /**
   * Bead is blocked by dependencies.
   */
  STATUS_BLOCKED: "blocked",

  /**
   * Bead is ready for work (no blockers).
   */
  STATUS_READY: "ready",

  /**
   * Bead requires security review.
   */
  SECURITY: "security",
} as const;

// =============================================================================
// Type Exports
// =============================================================================

/**
 * Type for all valid label values
 */
export type BeadLabel = (typeof LABELS)[keyof typeof LABELS];

/**
 * Run state derived from labels
 */
export type RunState = "READY" | "RUNNING" | "HALTED" | "COMPLETE";

/**
 * Sprint state derived from labels
 */
export type SprintState = "pending" | "in_progress" | "complete";

// =============================================================================
// Label Utilities
// =============================================================================

/**
 * Create a same-issue label with count
 *
 * @param count - Number of times the same issue occurred
 * @returns Label string like 'same-issue-3x'
 */
export function createSameIssueLabel(count: number): string {
  return `${LABELS.SAME_ISSUE_PREFIX}${count}x`;
}

/**
 * Parse count from same-issue label
 *
 * @param label - Label to parse
 * @returns Count, or null if not a same-issue label
 */
export function parseSameIssueCount(label: string): number | null {
  if (!label.startsWith(LABELS.SAME_ISSUE_PREFIX)) {
    return null;
  }
  const match = label.match(/same-issue-(\d+)x/);
  return match ? parseInt(match[1], 10) : null;
}

/**
 * Create a session label
 *
 * @param sessionId - Session identifier
 * @returns Label string like 'session:abc123'
 */
export function createSessionLabel(sessionId: string): string {
  return `${LABELS.SESSION_PREFIX}${sessionId}`;
}

/**
 * Create a handoff label
 *
 * @param fromSession - Source session identifier
 * @returns Label string like 'handoff:abc123'
 */
export function createHandoffLabel(fromSession: string): string {
  return `${LABELS.HANDOFF_PREFIX}${fromSession}`;
}

/**
 * Check if a bead has a specific label
 *
 * @param beadLabels - Array of labels on the bead
 * @param targetLabel - Label to check for
 * @returns true if bead has the label
 */
export function hasLabel(beadLabels: string[], targetLabel: string): boolean {
  return beadLabels.includes(targetLabel);
}

/**
 * Check if a bead has any label with a prefix
 *
 * @param beadLabels - Array of labels on the bead
 * @param prefix - Prefix to check for
 * @returns true if bead has any label starting with prefix
 */
export function hasLabelWithPrefix(beadLabels: string[], prefix: string): boolean {
  return beadLabels.some((l) => l.startsWith(prefix));
}

/**
 * Get labels matching a prefix
 *
 * @param beadLabels - Array of labels on the bead
 * @param prefix - Prefix to filter by
 * @returns Array of matching labels
 */
export function getLabelsWithPrefix(beadLabels: string[], prefix: string): string[] {
  return beadLabels.filter((l) => l.startsWith(prefix));
}

/**
 * Derive run state from labels
 *
 * @param labels - Labels on the run epic bead
 * @returns Derived run state
 */
export function deriveRunState(labels: string[]): RunState {
  if (hasLabel(labels, LABELS.CIRCUIT_BREAKER)) {
    return "HALTED";
  }
  if (hasLabel(labels, LABELS.SPRINT_COMPLETE)) {
    return "COMPLETE";
  }
  if (hasLabel(labels, LABELS.RUN_CURRENT)) {
    return "RUNNING";
  }
  return "READY";
}

/**
 * Derive sprint state from labels
 *
 * @param labels - Labels on the sprint bead
 * @returns Derived sprint state
 */
export function deriveSprintState(labels: string[]): SprintState {
  if (hasLabel(labels, LABELS.SPRINT_COMPLETE)) {
    return "complete";
  }
  if (hasLabel(labels, LABELS.SPRINT_IN_PROGRESS)) {
    return "in_progress";
  }
  return "pending";
}
