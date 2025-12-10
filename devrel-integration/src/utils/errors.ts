import crypto from 'crypto';
import { logger } from './logger';

/**
 * Safe Error Handling
 *
 * SECURITY FIXES:
 * - CRITICAL #8: No information disclosure in error messages
 * - Generic user messages with error IDs
 * - Detailed internal logging
 * - Error classification and tracking
 */

export enum ErrorCode {
  // User errors (safe to show details)
  INVALID_INPUT = 'INVALID_INPUT',
  PERMISSION_DENIED = 'PERMISSION_DENIED',
  NOT_FOUND = 'NOT_FOUND',
  RATE_LIMITED = 'RATE_LIMITED',
  VALIDATION_FAILED = 'VALIDATION_FAILED',
  PII_DETECTED = 'PII_DETECTED',

  // Internal errors (hide details)
  INTERNAL_ERROR = 'INTERNAL_ERROR',
  SERVICE_UNAVAILABLE = 'SERVICE_UNAVAILABLE',
  DATABASE_ERROR = 'DATABASE_ERROR',
  API_ERROR = 'API_ERROR',
  AUTH_ERROR = 'AUTH_ERROR',
  CONFIG_ERROR = 'CONFIG_ERROR',
  CONFIGURATION_ERROR = 'CONFIGURATION_ERROR',
}

/**
 * Security-specific exception class
 */
export class SecurityException extends Error {
  constructor(message: string, public readonly metadata?: Record<string, any>) {
    super(message);
    this.name = 'SecurityException';
    Error.captureStackTrace(this, this.constructor);
  }
}

/**
 * Application error with safe user messaging
 */
export class AppError extends Error {
  public readonly errorId: string;
  public readonly timestamp: Date;

  constructor(
    public readonly code: ErrorCode,
    public readonly userMessage: string,
    public readonly internalMessage: string,
    public readonly statusCode: number = 500,
    public readonly metadata?: Record<string, any>
  ) {
    super(internalMessage);
    this.name = 'AppError';
    this.errorId = crypto.randomBytes(8).toString('hex');
    this.timestamp = new Date();

    // Capture stack trace
    Error.captureStackTrace(this, this.constructor);
  }

  /**
   * Get safe message for user (never exposes internals)
   */
  getUserMessage(): string {
    return `❌ ${this.userMessage}\n\n` +
           `Error ID: \`${this.errorId}\` (share with support if needed)`;
  }

  /**
   * Get detailed message for logging
   */
  getLogMessage(): string {
    return `[${this.errorId}] ${this.code}: ${this.internalMessage}`;
  }

  /**
   * Convert to JSON for logging
   */
  toJSON(): Record<string, any> {
    return {
      errorId: this.errorId,
      code: this.code,
      userMessage: this.userMessage,
      internalMessage: this.internalMessage,
      statusCode: this.statusCode,
      timestamp: this.timestamp.toISOString(),
      metadata: this.metadata,
      stack: this.stack,
    };
  }
}

/**
 * Error handler that logs internally and returns safe message
 */
export function handleError(error: unknown, userId?: string, context?: string): string {
  // Generate error ID for tracking
  const errorId = crypto.randomBytes(8).toString('hex');

  // Log full error internally
  const logContext: Record<string, any> = {
    errorId,
    timestamp: new Date().toISOString(),
  };

  if (userId) {
    logContext['userId'] = userId;
  }

  if (context) {
    logContext['context'] = context;
  }

  if (error instanceof AppError) {
    // Log with error details
    logger.error(error.getLogMessage(), {
      ...logContext,
      ...error.toJSON(),
    });

    // Return safe user message
    return error.getUserMessage();
  }

  if (error instanceof Error) {
    // Unknown error - log full details
    logger.error(`[${errorId}] Unexpected error: ${error.message}`, {
      ...logContext,
      error: {
        name: error.name,
        message: error.message,
        stack: error.stack,
      },
    });
  } else {
    // Non-Error object
    logger.error(`[${errorId}] Unexpected error:`, {
      ...logContext,
      error: String(error),
    });
  }

  // Return generic error message
  return `❌ An unexpected error occurred. Please try again later.\n\n` +
         `Error ID: \`${errorId}\` (share with support if needed)`;
}

/**
 * Specific error constructors for common cases
 */
export const Errors = {
  /**
   * Invalid user input
   */
  invalidInput(userMessage: string, details?: string): AppError {
    return new AppError(
      ErrorCode.INVALID_INPUT,
      userMessage,
      details || userMessage,
      400
    );
  },

  /**
   * Permission denied
   */
  permissionDenied(permission: string, userId: string): AppError {
    return new AppError(
      ErrorCode.PERMISSION_DENIED,
      `You don't have permission to perform this action.`,
      `Permission denied: ${permission} for user ${userId}`,
      403,
      { permission, userId }
    );
  },

  /**
   * Resource not found
   */
  notFound(resource: string, id: string): AppError {
    return new AppError(
      ErrorCode.NOT_FOUND,
      `${resource} not found: ${id}`,
      `${resource} not found: ${id}`,
      404,
      { resource, id }
    );
  },

  /**
   * Rate limit exceeded
   */
  rateLimited(retryAfter: number): AppError {
    const seconds = Math.ceil(retryAfter / 1000);
    return new AppError(
      ErrorCode.RATE_LIMITED,
      `Rate limit exceeded. Please try again in ${seconds} seconds.`,
      `Rate limit exceeded (retry after ${retryAfter}ms)`,
      429,
      { retryAfter }
    );
  },

  /**
   * Validation failed
   */
  validationFailed(errors: string[]): AppError {
    return new AppError(
      ErrorCode.VALIDATION_FAILED,
      `Validation failed:\n${errors.map(e => `• ${e}`).join('\n')}`,
      `Validation failed: ${errors.join(', ')}`,
      400,
      { errors }
    );
  },

  /**
   * PII detected in input
   */
  piiDetected(piiTypes: string[]): AppError {
    return new AppError(
      ErrorCode.PII_DETECTED,
      'This message appears to contain sensitive information (email, phone, etc.). ' +
      'Please remove sensitive data and try again.',
      `PII detected: ${piiTypes.join(', ')}`,
      400,
      { piiTypes }
    );
  },

  /**
   * Service unavailable (API down, etc.)
   */
  serviceUnavailable(service: string, reason?: string): AppError {
    return new AppError(
      ErrorCode.SERVICE_UNAVAILABLE,
      `The ${service} service is temporarily unavailable. Please try again later.`,
      reason || `${service} service unavailable`,
      503,
      { service }
    );
  },

  /**
   * API error
   */
  apiError(service: string, statusCode: number, message: string): AppError {
    return new AppError(
      ErrorCode.API_ERROR,
      `Unable to communicate with ${service}. Please try again.`,
      `${service} API error (${statusCode}): ${message}`,
      502,
      { service, apiStatusCode: statusCode }
    );
  },

  /**
   * Authentication error
   */
  authError(reason: string): AppError {
    return new AppError(
      ErrorCode.AUTH_ERROR,
      'Authentication failed. Please try again or contact support.',
      `Auth error: ${reason}`,
      401,
      { reason }
    );
  },

  /**
   * Internal server error
   */
  internal(message: string, metadata?: Record<string, any>): AppError {
    return new AppError(
      ErrorCode.INTERNAL_ERROR,
      'An internal error occurred. Please try again later.',
      message,
      500,
      metadata
    );
  },
};

/**
 * Wrap async function with error handling
 */
export function withErrorHandling<T extends (...args: any[]) => Promise<any>>(
  fn: T,
  context?: string
): T {
  return (async (...args: any[]) => {
    try {
      return await fn(...args);
    } catch (error) {
      const errorMessage = handleError(error, undefined, context);
      throw new Error(errorMessage);
    }
  }) as T;
}

/**
 * Try/catch wrapper that returns result or error
 */
export async function tryCatch<T>(
  fn: () => Promise<T>
): Promise<{ success: true; data: T } | { success: false; error: AppError }> {
  try {
    const data = await fn();
    return { success: true, data };
  } catch (error) {
    if (error instanceof AppError) {
      return { success: false, error };
    }

    return {
      success: false,
      error: Errors.internal(
        error instanceof Error ? error.message : String(error)
      ),
    };
  }
}

/**
 * Assert condition or throw error
 */
export function assert(
  condition: boolean,
  error: AppError | string
): asserts condition {
  if (!condition) {
    throw typeof error === 'string' ? Errors.internal(error) : error;
  }
}

/**
 * Global error handlers
 */
export function setupGlobalErrorHandlers(): void {
  // Uncaught exceptions
  process.on('uncaughtException', (error) => {
    logger.error('FATAL: Uncaught exception', {
      error: {
        name: error.name,
        message: error.message,
        stack: error.stack,
      },
    });

    // In production, consider graceful shutdown
    if (process.env['NODE_ENV'] === 'production') {
      logger.error('Shutting down due to uncaught exception');
      process.exit(1);
    }
  });

  // Unhandled promise rejections
  process.on('unhandledRejection', (reason, promise) => {
    logger.error('FATAL: Unhandled promise rejection', {
      reason: reason instanceof Error ? {
        name: reason.name,
        message: reason.message,
        stack: reason.stack,
      } : reason,
      promise: String(promise),
    });

    // In production, consider graceful shutdown
    if (process.env['NODE_ENV'] === 'production') {
      logger.error('Shutting down due to unhandled rejection');
      process.exit(1);
    }
  });

  // Graceful shutdown on SIGTERM
  process.on('SIGTERM', () => {
    logger.info('SIGTERM received, shutting down gracefully');
    process.exit(0);
  });

  // Graceful shutdown on SIGINT (Ctrl+C)
  process.on('SIGINT', () => {
    logger.info('SIGINT received, shutting down gracefully');
    process.exit(0);
  });
}

/**
 * Error statistics for monitoring
 */
class ErrorStats {
  private stats = new Map<ErrorCode, number>();

  increment(code: ErrorCode): void {
    this.stats.set(code, (this.stats.get(code) || 0) + 1);
  }

  getStats(): Record<ErrorCode, number> {
    return Object.fromEntries(this.stats.entries()) as Record<ErrorCode, number>;
  }

  reset(): void {
    this.stats.clear();
  }
}

export const errorStats = new ErrorStats();

// Track errors in stats
const originalHandleError = handleError;
export function handleErrorWithStats(error: unknown, userId?: string, context?: string): string {
  if (error instanceof AppError) {
    errorStats.increment(error.code);
  }
  return originalHandleError(error, userId, context);
}
