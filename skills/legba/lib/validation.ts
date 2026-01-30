/**
 * Legba Input Validation
 *
 * Centralized validation for all user inputs to prevent injection attacks.
 */

/**
 * Maximum input length to prevent DoS via regex backtracking
 */
export const MAX_INPUT_LENGTH = 500;

/**
 * Sprint number bounds
 */
export const MIN_SPRINT = 1;
export const MAX_SPRINT = 1000;

/**
 * Validation patterns
 */
export const PATTERNS = {
  /**
   * Project ID: lowercase alphanumeric with hyphens
   * - Must start and end with alphanumeric
   * - 2-64 characters
   * - Only lowercase letters, numbers, and hyphens
   */
  projectId: /^[a-z0-9][a-z0-9-]{0,62}[a-z0-9]$/,

  /**
   * Session ID: UUID v4 format
   */
  sessionId: /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i,

  /**
   * Branch name: Git-safe pattern
   * - Alphanumeric, dots, underscores, hyphens, slashes
   * - Cannot start with dot or hyphen
   * - Cannot end with .lock
   * - No consecutive dots
   */
  branchName: /^[a-zA-Z0-9_][a-zA-Z0-9._/-]*$/,

  /**
   * Shell-safe string: no metacharacters
   */
  shellSafe: /^[a-zA-Z0-9._-]+$/,
};

/**
 * Validation result
 */
export interface ValidationResult {
  valid: boolean;
  error?: string;
}

/**
 * Validate input length
 */
export function validateLength(input: string, maxLength = MAX_INPUT_LENGTH): ValidationResult {
  if (input.length > maxLength) {
    return {
      valid: false,
      error: `Input exceeds maximum length of ${maxLength} characters`,
    };
  }
  return { valid: true };
}

/**
 * Validate project ID
 */
export function validateProjectId(projectId: string): ValidationResult {
  const lengthResult = validateLength(projectId, 64);
  if (!lengthResult.valid) {
    return lengthResult;
  }

  if (projectId.length < 2) {
    return {
      valid: false,
      error: 'Project ID must be at least 2 characters',
    };
  }

  if (!PATTERNS.projectId.test(projectId)) {
    return {
      valid: false,
      error: 'Project ID must contain only lowercase letters, numbers, and hyphens, and must start and end with alphanumeric',
    };
  }

  // Check for path traversal attempts
  if (projectId.includes('..') || projectId.includes('/') || projectId.includes('\\')) {
    return {
      valid: false,
      error: 'Project ID contains invalid characters',
    };
  }

  return { valid: true };
}

/**
 * Validate session ID (UUID v4)
 */
export function validateSessionId(sessionId: string): ValidationResult {
  const lengthResult = validateLength(sessionId, 36);
  if (!lengthResult.valid) {
    return lengthResult;
  }

  if (!PATTERNS.sessionId.test(sessionId)) {
    return {
      valid: false,
      error: 'Session ID must be a valid UUID',
    };
  }

  return { valid: true };
}

/**
 * Validate branch name
 */
export function validateBranchName(branch: string): ValidationResult {
  const lengthResult = validateLength(branch, 255);
  if (!lengthResult.valid) {
    return lengthResult;
  }

  if (!PATTERNS.branchName.test(branch)) {
    return {
      valid: false,
      error: 'Branch name contains invalid characters',
    };
  }

  // Check for dangerous patterns
  if (branch.includes('..') || branch.endsWith('.lock')) {
    return {
      valid: false,
      error: 'Branch name contains invalid pattern',
    };
  }

  return { valid: true };
}

/**
 * Validate sprint number
 */
export function validateSprintNumber(sprint: number): ValidationResult {
  if (!Number.isInteger(sprint)) {
    return {
      valid: false,
      error: 'Sprint must be an integer',
    };
  }

  if (sprint < MIN_SPRINT || sprint > MAX_SPRINT) {
    return {
      valid: false,
      error: `Sprint must be between ${MIN_SPRINT} and ${MAX_SPRINT}`,
    };
  }

  return { valid: true };
}

/**
 * Sanitize string for shell environment variable
 * Removes any characters that could be dangerous in shell context
 */
export function sanitizeForShell(input: string): string {
  // Remove any non-safe characters
  return input.replace(/[^a-zA-Z0-9._-]/g, '_');
}

/**
 * Sanitize string for environment variable value
 * Escapes potentially dangerous characters
 */
export function sanitizeEnvValue(input: string): string {
  // Replace newlines, quotes, and backslashes
  return input
    .replace(/\\/g, '\\\\')
    .replace(/"/g, '\\"')
    .replace(/'/g, "\\'")
    .replace(/\n/g, '\\n')
    .replace(/\r/g, '\\r')
    .replace(/`/g, '\\`')
    .replace(/\$/g, '\\$');
}

/**
 * Escape string for shell command argument
 * Uses single quotes with proper escaping
 */
export function escapeShellArg(arg: string): string {
  // Replace single quotes with escaped version
  const escaped = arg.replace(/'/g, "'\\''");
  return `'${escaped}'`;
}

/**
 * Validate and sanitize a command from user input
 */
export function validateCommand(input: string): ValidationResult {
  const lengthResult = validateLength(input);
  if (!lengthResult.valid) {
    return lengthResult;
  }

  // Check for null bytes
  if (input.includes('\0')) {
    return {
      valid: false,
      error: 'Input contains null bytes',
    };
  }

  return { valid: true };
}

/**
 * Secret redaction patterns for log sanitization
 */
export const SECRET_PATTERNS: Array<{ name: string; pattern: RegExp }> = [
  // API Keys
  { name: 'anthropic_key', pattern: /sk-ant-[a-zA-Z0-9_-]+/g },
  { name: 'openai_key', pattern: /sk-[a-zA-Z0-9]{20,}/g },
  { name: 'aws_key', pattern: /AKIA[0-9A-Z]{16}/g },
  { name: 'aws_secret', pattern: /[a-zA-Z0-9/+=]{40}/g },
  { name: 'github_token', pattern: /gh[pousr]_[a-zA-Z0-9]{36,}/g },
  { name: 'stripe_key', pattern: /[sp]k_(live|test)_[a-zA-Z0-9]{24,}/g },
  { name: 'slack_token', pattern: /xox[baprs]-[a-zA-Z0-9-]+/g },

  // Generic secrets
  { name: 'bearer_token', pattern: /Bearer\s+[a-zA-Z0-9._-]+/gi },
  { name: 'basic_auth', pattern: /Basic\s+[a-zA-Z0-9+/=]+/gi },
  { name: 'password', pattern: /password['":\s]*[=:]["']?[^\s"']+/gi },
  { name: 'secret', pattern: /secret['":\s]*[=:]["']?[^\s"']+/gi },
  { name: 'api_key', pattern: /api[_-]?key['":\s]*[=:]["']?[^\s"']+/gi },

  // Private keys
  { name: 'private_key', pattern: /-----BEGIN[A-Z ]+PRIVATE KEY-----[\s\S]*?-----END[A-Z ]+PRIVATE KEY-----/g },

  // Database URIs
  { name: 'db_uri', pattern: /(postgres|mysql|mongodb|redis):\/\/[^\s"']+/gi },

  // JWT tokens
  { name: 'jwt', pattern: /eyJ[a-zA-Z0-9_-]*\.eyJ[a-zA-Z0-9_-]*\.[a-zA-Z0-9_-]*/g },
];

/**
 * Redact secrets from log output
 */
export function redactSecrets(logs: string): string {
  let redacted = logs;

  for (const { name, pattern } of SECRET_PATTERNS) {
    redacted = redacted.replace(pattern, `[REDACTED:${name}]`);
  }

  return redacted;
}

/**
 * Validate required credentials are present
 */
export interface CredentialValidation {
  name: string;
  value: string | undefined;
  required: boolean;
}

export function validateCredentials(credentials: CredentialValidation[]): ValidationResult {
  const missing: string[] = [];

  for (const cred of credentials) {
    if (cred.required && (!cred.value || cred.value.trim() === '')) {
      missing.push(cred.name);
    }
  }

  if (missing.length > 0) {
    return {
      valid: false,
      error: `Missing required credentials: ${missing.join(', ')}`,
    };
  }

  return { valid: true };
}
