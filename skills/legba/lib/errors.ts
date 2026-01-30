/**
 * Legba Error Handling
 *
 * User-friendly error messages and error codes per SDD Appendix C.
 */

/**
 * Error codes with user-friendly messages
 */
export const ErrorCodes = {
  E001: {
    code: 'E001',
    message: 'Project not found',
    hint: 'Check the project name with `legba projects`',
  },
  E002: {
    code: 'E002',
    message: 'Project disabled',
    hint: 'The project is currently disabled for autonomous execution',
  },
  E003: {
    code: 'E003',
    message: 'Session already active',
    hint: 'Use `legba status` to check the current session, or `legba abort` to cancel it',
  },
  E004: {
    code: 'E004',
    message: 'Queue full',
    hint: 'The queue has reached maximum capacity. Try again later.',
  },
  E005: {
    code: 'E005',
    message: 'GitHub App not installed',
    hint: 'Install the GitHub App on the target repository',
  },
  E006: {
    code: 'E006',
    message: 'Clone failed',
    hint: 'Check repository access and network connectivity',
  },
  E007: {
    code: 'E007',
    message: 'Circuit breaker tripped',
    hint: 'Review the issue with `legba logs {session-id}` and `legba resume` when ready',
  },
  E008: {
    code: 'E008',
    message: 'Session timeout',
    hint: 'The session exceeded the maximum execution time (8 hours)',
  },
  E009: {
    code: 'E009',
    message: 'Session not found',
    hint: 'Check the session ID is correct',
  },
  E010: {
    code: 'E010',
    message: 'Invalid session state',
    hint: 'The operation cannot be performed in the current session state',
  },
  E011: {
    code: 'E011',
    message: 'Storage error',
    hint: 'An error occurred accessing storage. Try again.',
  },
  E012: {
    code: 'E012',
    message: 'GitHub API error',
    hint: 'An error occurred communicating with GitHub. Try again.',
  },
} as const;

export type ErrorCode = keyof typeof ErrorCodes;

/**
 * Legba-specific error class
 */
export class LegbaError extends Error {
  public readonly code: ErrorCode;
  public readonly hint: string;
  public readonly details?: string;

  constructor(code: ErrorCode, details?: string) {
    const errorInfo = ErrorCodes[code];
    super(errorInfo.message);
    this.name = 'LegbaError';
    this.code = code;
    this.hint = errorInfo.hint;
    this.details = details;
  }

  /**
   * Format error for user display
   */
  toUserMessage(): string {
    let msg = `**Error ${this.code}**: ${this.message}`;
    if (this.details) {
      msg += `\n\n${this.details}`;
    }
    msg += `\n\n*Hint*: ${this.hint}`;
    return msg;
  }
}

/**
 * Check if an error is a LegbaError
 */
export function isLegbaError(error: unknown): error is LegbaError {
  return error instanceof LegbaError;
}

/**
 * M-001 FIX: Patterns that may indicate sensitive information in error messages
 */
const SENSITIVE_PATTERNS = [
  // File paths that might reveal system structure
  /\/home\/[^/\s]+/gi,
  /\/Users\/[^/\s]+/gi,
  /C:\\Users\\[^\\]+/gi,
  // Internal error messages
  /at\s+\S+\s+\(\S+:\d+:\d+\)/g, // Stack trace lines
  // SQL fragments
  /SELECT\s+.+\s+FROM/gi,
  /INSERT\s+INTO/gi,
  /UPDATE\s+.+\s+SET/gi,
  // API endpoints that might be internal
  /https?:\/\/[^/]*internal[^/\s]*/gi,
  /https?:\/\/localhost[:\d]*/gi,
  // Secret-like patterns (API keys, tokens)
  /sk-[a-zA-Z0-9_-]+/g,
  /Bearer\s+[a-zA-Z0-9._-]+/gi,
];

/**
 * M-001 FIX: Sanitize error message for safe user display
 * Removes potentially sensitive information from error messages
 */
function sanitizeErrorMessage(message: string): string {
  let sanitized = message;

  for (const pattern of SENSITIVE_PATTERNS) {
    sanitized = sanitized.replace(pattern, '[redacted]');
  }

  // Truncate if too long (might contain stack traces)
  if (sanitized.length > 200) {
    sanitized = sanitized.substring(0, 200) + '...';
  }

  return sanitized;
}

/**
 * Wrap an unknown error in a user-friendly message
 *
 * M-001 FIX: Sanitizes error messages to prevent information disclosure
 */
export function wrapError(error: unknown): LegbaError {
  if (isLegbaError(error)) {
    return error;
  }

  const rawMessage = error instanceof Error ? error.message : String(error);

  // Log the full error for debugging (server-side only)
  console.error('Legba error:', rawMessage);

  // M-001 FIX: Sanitize the message before including in user-facing error
  const sanitizedMessage = sanitizeErrorMessage(rawMessage);

  // Try to map common errors to codes
  // Use original message for classification but sanitized for display
  if (rawMessage.includes('not found') || rawMessage.includes('404')) {
    return new LegbaError('E009'); // Don't include details for not found
  }
  if (rawMessage.includes('timeout')) {
    return new LegbaError('E008'); // Don't include details for timeout
  }
  if (rawMessage.includes('GitHub') || rawMessage.includes('Octokit')) {
    return new LegbaError('E012'); // Don't expose GitHub error details
  }
  if (rawMessage.includes('R2') || rawMessage.includes('storage')) {
    return new LegbaError('E011'); // Don't expose storage error details
  }

  // Generic error - use sanitized message only if it doesn't look sensitive
  if (sanitizedMessage.includes('[redacted]')) {
    return new LegbaError('E011'); // Something looked sensitive, use generic message
  }

  return new LegbaError('E011', sanitizedMessage);
}

/**
 * Retry logic for transient failures
 */
export async function withRetry<T>(
  operation: () => Promise<T>,
  maxAttempts = 3,
  delayMs = 1000
): Promise<T> {
  let lastError: Error | undefined;

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await operation();
    } catch (error) {
      lastError = error instanceof Error ? error : new Error(String(error));

      // Don't retry for certain error types
      if (isLegbaError(error)) {
        const nonRetryable: ErrorCode[] = ['E001', 'E002', 'E009', 'E010'];
        if (nonRetryable.includes(error.code)) {
          throw error;
        }
      }

      // Wait before next attempt (exponential backoff)
      if (attempt < maxAttempts) {
        await new Promise((resolve) => setTimeout(resolve, delayMs * attempt));
      }
    }
  }

  throw lastError;
}
