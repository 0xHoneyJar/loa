/**
 * Beads Label Constants
 *
 * Semantic label constants for beads_rust integration.
 * These labels enable run-mode state tracking, circuit breaker management,
 * lineage tracking, and memory classification.
 *
 * LINEAGE (Issue #208, Phase 2): Tracks bead relationships beyond parent/child.
 * Informed by MLP v0.2's lineage model (supersedes/branches), adapted for
 * Loa's development-focused use case. Like git's `replace` mechanism —
 * the history stays intact, consumers follow the chain.
 *
 * CLASSIFICATION (Issue #208, Phase 3): Enables ranked context assembly.
 * Informed by MLP v0.2's Continuity Framework classification and Kafka's
 * schema registry pattern — knowing the type determines the aggregation
 * strategy for downstream consumers (agents, handoffs, br prime).
 *
 * @module beads/labels
 * @version 1.31.0
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

  // -------------------------------------------------------------------------
  // Lineage Labels (Issue #208, Phase 2)
  //
  // Tracks bead relationships beyond parent/child.
  // Like HTTP's 301 (Moved Permanently) — the old resource still exists
  // but consumers should follow the redirect to the new one.
  // -------------------------------------------------------------------------

  /**
   * Prefix for supersession tracking.
   * Format: supersedes:{old-bead-id}
   *
   * Used when a task is replaced or re-scoped. The new task supersedes
   * the old one, forming a replacement chain.
   */
  SUPERSEDES_PREFIX: "supersedes:",

  /**
   * Prefix for branch tracking.
   * Format: branched-from:{source-bead-id}
   *
   * Used when a task is split into multiple tasks. Each child task
   * branches from the source, indicating a fork in the work graph.
   */
  BRANCHED_FROM_PREFIX: "branched-from:",

  // -------------------------------------------------------------------------
  // Classification Labels (Issue #208, Phase 3)
  //
  // Enables ranked context assembly. Like Prometheus metric types
  // (counter, gauge, histogram, summary) — knowing the classification
  // determines how downstream consumers (agents, handoffs, br prime)
  // prioritize the bead during context compilation.
  // -------------------------------------------------------------------------

  /**
   * Marks a bead as containing an architectural or design decision.
   * Always included in context compilation (highest priority).
   */
  CLASS_DECISION: "class:decision",

  /**
   * Marks a bead as containing an unexpected discovery during implementation.
   * Included in context compilation when task-relevant.
   */
  CLASS_DISCOVERY: "class:discovery",

  /**
   * Marks a bead as a blocker record.
   * Always included in context compilation (safety-critical).
   */
  CLASS_BLOCKER: "class:blocker",

  /**
   * Marks a bead as containing background context information.
   * Included in context compilation within token budget.
   */
  CLASS_CONTEXT: "class:context",

  /**
   * Marks a bead as a routine status update or task completion note.
   * Lowest priority — summarized or skipped during context compilation.
   */
  CLASS_ROUTINE: "class:routine",

  /**
   * Confidence: explicitly marked as important by agent or user.
   * Score range: 0.95-1.0
   */
  CONFIDENCE_EXPLICIT: "confidence:explicit",

  /**
   * Confidence: automatically derived from patterns.
   * Score range: 0.70-0.94
   */
  CONFIDENCE_DERIVED: "confidence:derived",

  /**
   * Confidence: older than N sessions, may be outdated.
   * Score range: <0.40
   */
  CONFIDENCE_STALE: "confidence:stale",
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

/**
 * Bead classification type for context ranking.
 *
 * Like Kafka consumer groups, classification determines how a bead
 * is processed by downstream consumers during context assembly.
 */
export type BeadClassification =
  | "decision"
  | "discovery"
  | "blocker"
  | "context"
  | "routine";

/**
 * Confidence level for memory relevance scoring.
 */
export type ConfidenceLevel = "explicit" | "derived" | "stale";

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
  if (!sessionId || /[^a-zA-Z0-9_\-.:@]/.test(sessionId)) {
    throw new Error(`Invalid session ID: ${sessionId}`);
  }
  return `${LABELS.SESSION_PREFIX}${sessionId}`;
}

/**
 * Create a handoff label
 *
 * @param fromSession - Source session identifier
 * @returns Label string like 'handoff:abc123'
 */
export function createHandoffLabel(fromSession: string): string {
  if (!fromSession || /[^a-zA-Z0-9_\-.:@]/.test(fromSession)) {
    throw new Error(`Invalid session ID: ${fromSession}`);
  }
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

// =============================================================================
// Lineage Utilities (Issue #208, Phase 2)
// =============================================================================

/**
 * Create a supersession label linking a new bead to the one it replaces.
 *
 * @param oldBeadId - ID of the bead being superseded
 * @returns Label string like 'supersedes:task-123'
 *
 * @example
 * ```typescript
 * // Task was re-scoped, new task replaces old one
 * const label = createSupersedesLabel("task-old");
 * await br.exec(`label add ${newTaskId} ${label}`);
 * ```
 */
export function createSupersedesLabel(oldBeadId: string): string {
  if (!oldBeadId || /[^a-zA-Z0-9_\-.:@]/.test(oldBeadId)) {
    throw new Error(`Invalid bead ID: ${oldBeadId}`);
  }
  return `${LABELS.SUPERSEDES_PREFIX}${oldBeadId}`;
}

/**
 * Create a branched-from label linking a child bead to its source.
 *
 * @param sourceBeadId - ID of the bead this was split from
 * @returns Label string like 'branched-from:task-123'
 *
 * @example
 * ```typescript
 * // Task was split into two subtasks
 * const label = createBranchedFromLabel("task-original");
 * await br.exec(`label add ${subtask1Id} ${label}`);
 * await br.exec(`label add ${subtask2Id} ${label}`);
 * ```
 */
export function createBranchedFromLabel(sourceBeadId: string): string {
  if (!sourceBeadId || /[^a-zA-Z0-9_\-.:@]/.test(sourceBeadId)) {
    throw new Error(`Invalid bead ID: ${sourceBeadId}`);
  }
  return `${LABELS.BRANCHED_FROM_PREFIX}${sourceBeadId}`;
}

/**
 * Parse target bead ID from a lineage label.
 *
 * @param label - A supersedes: or branched-from: label
 * @returns The target bead ID, or null if not a lineage label
 */
export function parseLineageTarget(label: string): string | null {
  if (label.startsWith(LABELS.SUPERSEDES_PREFIX)) {
    return label.slice(LABELS.SUPERSEDES_PREFIX.length) || null;
  }
  if (label.startsWith(LABELS.BRANCHED_FROM_PREFIX)) {
    return label.slice(LABELS.BRANCHED_FROM_PREFIX.length) || null;
  }
  return null;
}

/**
 * Get all supersession targets from a bead's labels.
 *
 * @param beadLabels - Labels on the bead
 * @returns Array of superseded bead IDs
 */
export function getSupersedesTargets(beadLabels: string[]): string[] {
  return getLabelsWithPrefix(beadLabels, LABELS.SUPERSEDES_PREFIX)
    .map((l) => l.slice(LABELS.SUPERSEDES_PREFIX.length))
    .filter((id) => id.length > 0);
}

/**
 * Get all branched-from sources from a bead's labels.
 *
 * @param beadLabels - Labels on the bead
 * @returns Array of source bead IDs
 */
export function getBranchedFromSources(beadLabels: string[]): string[] {
  return getLabelsWithPrefix(beadLabels, LABELS.BRANCHED_FROM_PREFIX)
    .map((l) => l.slice(LABELS.BRANCHED_FROM_PREFIX.length))
    .filter((id) => id.length > 0);
}

// =============================================================================
// Classification Utilities (Issue #208, Phase 3)
// =============================================================================

/** Map from classification type to label */
const CLASSIFICATION_LABEL_MAP: Record<BeadClassification, string> = {
  decision: LABELS.CLASS_DECISION,
  discovery: LABELS.CLASS_DISCOVERY,
  blocker: LABELS.CLASS_BLOCKER,
  context: LABELS.CLASS_CONTEXT,
  routine: LABELS.CLASS_ROUTINE,
};

/** Map from confidence level to label */
const CONFIDENCE_LABEL_MAP: Record<ConfidenceLevel, string> = {
  explicit: LABELS.CONFIDENCE_EXPLICIT,
  derived: LABELS.CONFIDENCE_DERIVED,
  stale: LABELS.CONFIDENCE_STALE,
};

/**
 * Get the classification label for a given type.
 *
 * @param classification - The classification type
 * @returns The corresponding label string
 */
export function classificationToLabel(
  classification: BeadClassification,
): string {
  return CLASSIFICATION_LABEL_MAP[classification];
}

/**
 * Get the confidence label for a given level.
 *
 * @param confidence - The confidence level
 * @returns The corresponding label string
 */
export function confidenceToLabel(confidence: ConfidenceLevel): string {
  return CONFIDENCE_LABEL_MAP[confidence];
}

/**
 * Derive classification from a bead's labels.
 *
 * Returns the first matching classification, or null if unclassified.
 * Priority order: blocker > decision > discovery > context > routine
 * (matches context compilation priority).
 *
 * @param beadLabels - Labels on the bead
 * @returns Derived classification, or null
 */
export function deriveClassification(
  beadLabels: string[],
): BeadClassification | null {
  if (hasLabel(beadLabels, LABELS.CLASS_BLOCKER)) return "blocker";
  if (hasLabel(beadLabels, LABELS.CLASS_DECISION)) return "decision";
  if (hasLabel(beadLabels, LABELS.CLASS_DISCOVERY)) return "discovery";
  if (hasLabel(beadLabels, LABELS.CLASS_CONTEXT)) return "context";
  if (hasLabel(beadLabels, LABELS.CLASS_ROUTINE)) return "routine";
  return null;
}

/**
 * Derive confidence level from a bead's labels.
 *
 * @param beadLabels - Labels on the bead
 * @returns Derived confidence, or null if no confidence label
 */
export function deriveConfidence(
  beadLabels: string[],
): ConfidenceLevel | null {
  if (hasLabel(beadLabels, LABELS.CONFIDENCE_EXPLICIT)) return "explicit";
  if (hasLabel(beadLabels, LABELS.CONFIDENCE_DERIVED)) return "derived";
  if (hasLabel(beadLabels, LABELS.CONFIDENCE_STALE)) return "stale";
  return null;
}

/**
 * Get the context compilation priority for a classification.
 *
 * Higher numbers = higher priority (included first in context window).
 * Unclassified beads get a default priority of 1.
 *
 * This is the core ranking function used by the context compiler.
 */
export function classificationPriority(
  classification: BeadClassification | null,
): number {
  switch (classification) {
    case "blocker":
      return 5; // Always include — safety critical
    case "decision":
      return 4; // Always include — architectural context
    case "discovery":
      return 3; // Include if task-relevant
    case "context":
      return 2; // Include within token budget
    case "routine":
      return 0; // Summarize or skip
    default:
      return 1; // Unclassified — low priority
  }
}
