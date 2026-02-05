/**
 * Beads TypeScript Runtime Patterns
 *
 * Production-hardened utilities for beads_rust integration.
 *
 * @module beads
 * @version 1.0.0
 * @origin Extracted from loa-beauvoir production implementation
 */

// =============================================================================
// Security Validation
// =============================================================================

export {
  // Constants
  BEAD_ID_PATTERN,
  MAX_BEAD_ID_LENGTH,
  MAX_STRING_LENGTH,
  LABEL_PATTERN,
  MAX_LABEL_LENGTH,
  ALLOWED_TYPES,
  ALLOWED_OPERATIONS,
  // Validation Functions
  validateBeadId,
  validateLabel,
  validateType,
  validateOperation,
  validatePriority,
  validatePath,
  shellEscape,
  validateBrCommand,
  // Utility Functions
  safeType,
  safePriority,
  filterValidLabels,
} from "./validation";

// =============================================================================
// Label Constants & Utilities
// =============================================================================

export {
  // Constants
  LABELS,
  // Types
  type BeadLabel,
  type RunState,
  /**
   * Sprint state derived from labels (string union: 'pending' | 'in_progress' | 'complete').
   *
   * Renamed from `SprintState` to `LabelSprintState` to avoid conflict with
   * `interfaces.SprintState` which is a full interface with id, status, tasksTotal, etc.
   *
   * Use `LabelSprintState` when working with label-based state derivation.
   * Use `SprintState` (from interfaces) when working with full sprint objects.
   */
  type SprintState as LabelSprintState,
  // Utility Functions
  createSameIssueLabel,
  parseSameIssueCount,
  createSessionLabel,
  createHandoffLabel,
  hasLabel,
  hasLabelWithPrefix,
  getLabelsWithPrefix,
  deriveRunState,
  deriveSprintState,
} from "./labels";

// =============================================================================
// Abstract Interfaces
// =============================================================================

export {
  // Bead Types
  type Bead,
  type BeadCreateOptions,
  type BeadQueryOptions,
  // WAL Interface
  type WALEntry,
  type IWALAdapter,
  // Scheduler Interface
  type SchedulerTask,
  type IScheduler,
  // State Store Interface
  type IStateStore,
  // BR Executor Interface
  type BrCommandResult,
  type IBrExecutor,
  // Run State Manager Interface
  type SprintState,
  type CircuitBreakerRecord,
  type MigrationResult,
  type BeadsRunStateConfig,
  type IBeadsRunStateManager,
} from "./interfaces";

// =============================================================================
// Run State Manager
// =============================================================================

export {
  BeadsRunStateManager,
  createBeadsRunStateManager,
} from "./run-state";
