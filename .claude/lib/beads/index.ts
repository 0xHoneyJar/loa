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
  type SprintState,
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
