/**
 * Beads Security Validation
 *
 * Input validation patterns for beads_rust integration.
 * Prevents command injection, path traversal, and other attacks.
 *
 * SECURITY: All user-controllable values MUST be validated before use
 * in shell commands or file paths.
 *
 * @module beads/validation
 * @version 1.30.0
 * @origin Extracted from loa-beauvoir production implementation
 */

// =============================================================================
// Constants
// =============================================================================

/**
 * SECURITY: Pattern for valid bead IDs (alphanumeric, underscore, hyphen only)
 * Prevents path traversal and injection via beadId
 */
export const BEAD_ID_PATTERN = /^[a-zA-Z0-9_-]+$/;

/**
 * SECURITY: Maximum beadId length to prevent DoS via extremely long IDs
 */
export const MAX_BEAD_ID_LENGTH = 128;

/**
 * SECURITY: Maximum string length for shell arguments
 * Prevents memory exhaustion and command line overflow
 */
export const MAX_STRING_LENGTH = 1024;

/**
 * SECURITY: Pattern for valid labels (alphanumeric, underscore, hyphen, colon)
 * Colons are allowed for namespaced labels (e.g., 'sprint:in_progress')
 */
export const LABEL_PATTERN = /^[a-zA-Z0-9_:-]+$/;

/**
 * SECURITY: Maximum label length
 */
export const MAX_LABEL_LENGTH = 64;

/**
 * SECURITY: Allowed bead types (whitelist)
 */
export const ALLOWED_TYPES = new Set([
  "task",
  "bug",
  "feature",
  "epic",
  "story",
  "debt",
  "spike",
]);

/**
 * SECURITY: Allowed operation types (whitelist)
 */
export const ALLOWED_OPERATIONS = new Set([
  "create",
  "update",
  "close",
  "reopen",
  "label",
  "comment",
  "dep",
]);

// =============================================================================
// Validation Functions
// =============================================================================

/**
 * Validate bead ID against safe pattern
 *
 * SECURITY: Must be called before using beadId in:
 * - Shell commands
 * - File paths
 * - Database queries
 *
 * @throws Error if beadId contains unsafe characters or is invalid
 *
 * @example
 * ```typescript
 * validateBeadId('task-123');     // OK
 * validateBeadId('../etc');       // throws Error
 * validateBeadId('task;rm -rf'); // throws Error
 * ```
 */
export function validateBeadId(beadId: unknown): asserts beadId is string {
  if (!beadId || typeof beadId !== "string") {
    throw new Error("Invalid beadId: must be a non-empty string");
  }
  if (!BEAD_ID_PATTERN.test(beadId)) {
    throw new Error(
      `Invalid beadId: must match pattern ${BEAD_ID_PATTERN} (alphanumeric, underscore, hyphen only)`,
    );
  }
  if (beadId.length > MAX_BEAD_ID_LENGTH) {
    throw new Error(
      `Invalid beadId: exceeds maximum length of ${MAX_BEAD_ID_LENGTH} characters`,
    );
  }
}

/**
 * Validate label against safe pattern
 *
 * SECURITY: Must be called before using label in shell commands
 *
 * @throws Error if label contains unsafe characters
 *
 * @example
 * ```typescript
 * validateLabel('sprint:in_progress'); // OK
 * validateLabel('label with spaces');  // throws Error
 * ```
 */
export function validateLabel(label: unknown): asserts label is string {
  if (!label || typeof label !== "string") {
    throw new Error("Invalid label: must be a non-empty string");
  }
  if (!LABEL_PATTERN.test(label)) {
    throw new Error(
      `Invalid label: must match pattern ${LABEL_PATTERN} (alphanumeric, underscore, hyphen, colon)`,
    );
  }
  if (label.length > MAX_LABEL_LENGTH) {
    throw new Error(
      `Invalid label: exceeds maximum length of ${MAX_LABEL_LENGTH} characters`,
    );
  }
}

/**
 * Validate bead type against whitelist
 *
 * @throws Error if type is not in allowed list
 */
export function validateType(type: unknown): asserts type is string {
  if (!type || typeof type !== "string") {
    throw new Error("Invalid type: must be a non-empty string");
  }
  if (!ALLOWED_TYPES.has(type)) {
    throw new Error(
      `Invalid type: must be one of ${Array.from(ALLOWED_TYPES).join(", ")}`,
    );
  }
}

/**
 * Validate operation type against whitelist
 *
 * @throws Error if operation is not in allowed list
 */
export function validateOperation(operation: unknown): asserts operation is string {
  if (!operation || typeof operation !== "string") {
    throw new Error("Invalid operation: must be a non-empty string");
  }
  if (!ALLOWED_OPERATIONS.has(operation)) {
    throw new Error(
      `Invalid operation: must be one of ${Array.from(ALLOWED_OPERATIONS).join(", ")}`,
    );
  }
}

/**
 * Validate priority is a safe integer in valid range
 *
 * @param priority - Priority value to validate
 * @param min - Minimum allowed value (default: 0)
 * @param max - Maximum allowed value (default: 10)
 * @throws Error if priority is invalid
 */
export function validatePriority(
  priority: unknown,
  min = 0,
  max = 10,
): asserts priority is number {
  if (typeof priority !== "number" || !Number.isInteger(priority)) {
    throw new Error("Invalid priority: must be an integer");
  }
  if (priority < min || priority > max) {
    throw new Error(`Invalid priority: must be between ${min} and ${max}`);
  }
}

/**
 * Validate path does not contain traversal sequences
 *
 * SECURITY: Must be called before using user-provided paths
 *
 * Checks for:
 * - Direct traversal (..)
 * - URL-encoded traversal (%2e%2e)
 * - Null byte injection (\x00)
 *
 * @throws Error if path contains traversal or unsafe characters
 */
export function validatePath(path: unknown): asserts path is string {
  if (!path || typeof path !== "string") {
    throw new Error("Invalid path: must be a non-empty string");
  }

  // SECURITY: Check for null bytes (can truncate paths in some systems)
  if (path.includes("\x00") || path.includes("%00")) {
    throw new Error("Invalid path: null bytes not allowed");
  }

  // SECURITY: Check for direct traversal
  if (path.includes("..")) {
    throw new Error("Invalid path: traversal not allowed");
  }

  // SECURITY: Check for URL-encoded traversal (double dot = %2e%2e)
  // Also handle mixed case (%2E%2e, %2e%2E, etc.)
  if (/%2e%2e/i.test(path)) {
    throw new Error("Invalid path: encoded traversal not allowed");
  }
}

// =============================================================================
// Shell Escaping
// =============================================================================

/**
 * Escape string for safe shell execution
 *
 * SECURITY: Uses single-quote escaping which is safe for all content.
 * This is the ONLY safe way to include user input in shell commands.
 *
 * @param str - String to escape
 * @returns Escaped string wrapped in single quotes
 * @throws Error if input is not a string or exceeds max length
 *
 * @example
 * ```typescript
 * shellEscape("hello");           // "'hello'"
 * shellEscape("it's");            // "'it'\\''s'"
 * shellEscape("$(rm -rf /)");     // "'$(rm -rf /)'"  (safe - not executed)
 * ```
 */
export function shellEscape(str: string): string {
  if (typeof str !== "string") {
    throw new Error("shellEscape requires a string input");
  }
  if (str.length > MAX_STRING_LENGTH) {
    throw new Error(`Input exceeds maximum length of ${MAX_STRING_LENGTH}`);
  }
  // Escape single quotes by ending the string, adding escaped quote, starting new string
  // 'foo'bar' becomes 'foo'\''bar'
  return `'${str.replace(/'/g, "'\\''")}'`;
}

/**
 * Validate br command path is safe
 *
 * SECURITY: Only allows 'br' or absolute paths without shell metacharacters
 *
 * @throws Error if brCommand contains unsafe characters
 */
export function validateBrCommand(cmd: unknown): asserts cmd is string {
  if (!cmd || typeof cmd !== "string") {
    throw new Error("Invalid brCommand: must be a non-empty string");
  }
  if (cmd === "br") return;
  // Allow absolute paths without spaces, semicolons, or other shell metacharacters
  if (cmd.startsWith("/") && /^[a-zA-Z0-9/_.-]+$/.test(cmd)) return;
  throw new Error(
    "Invalid brCommand: must be 'br' or an absolute path without shell metacharacters",
  );
}

// =============================================================================
// Utility Functions
// =============================================================================

/**
 * Safely coerce value to valid bead type, with fallback
 *
 * @param value - Value to coerce
 * @param fallback - Fallback type if invalid (default: 'task')
 * @returns Valid bead type
 */
export function safeType(value: unknown, fallback = "task"): string {
  if (typeof value === "string" && ALLOWED_TYPES.has(value)) {
    return value;
  }
  return fallback;
}

/**
 * Safely coerce value to valid priority, with fallback
 *
 * @param value - Value to coerce
 * @param fallback - Fallback priority if invalid (default: 2)
 * @returns Valid priority number
 */
export function safePriority(value: unknown, fallback = 2): number {
  if (typeof value === "number" && Number.isInteger(value) && value >= 0 && value <= 10) {
    return value;
  }
  return fallback;
}

/**
 * Filter array of labels to only valid ones
 *
 * @param labels - Array of potential labels
 * @returns Array of valid labels only
 */
export function filterValidLabels(labels: unknown[]): string[] {
  return labels
    .filter((l): l is string => typeof l === "string")
    .filter((l) => LABEL_PATTERN.test(l) && l.length <= MAX_LABEL_LENGTH);
}
