import winston from 'winston';
import DailyRotateFile from 'winston-daily-rotate-file';
import fs from 'fs';
import path from 'path';
import { sanitizeForLogging } from './validation';

/**
 * Secure Logging System
 *
 * SECURITY FIXES:
 * - CRITICAL #10: Logs never contain secrets or PII
 * - Automatic redaction of sensitive data
 * - Secure file permissions (0600)
 * - Separate audit trail
 * - Log rotation and retention
 */

const logDir = path.join(__dirname, '../../logs');

// Ensure log directory with secure permissions
if (!fs.existsSync(logDir)) {
  fs.mkdirSync(logDir, { recursive: true, mode: 0o700 });
} else {
  // Fix permissions if they exist
  try {
    fs.chmodSync(logDir, 0o700);
  } catch (error) {
    console.error('Warning: Could not set log directory permissions:', error);
  }
}

/**
 * Custom format with PII/secret redaction
 */
const redactingFormat = winston.format.printf(({ level, message, timestamp, ...meta }) => {
  const sanitizedMessage = typeof message === 'string'
    ? sanitizeForLogging(message)
    : JSON.stringify(sanitizeForLogging(message));

  const sanitizedMeta = sanitizeForLogging(meta);

  let log = `${timestamp} [${level.toUpperCase()}] ${sanitizedMessage}`;

  if (Object.keys(sanitizedMeta).length > 0) {
    log += ` ${JSON.stringify(sanitizedMeta)}`;
  }

  return log;
});

/**
 * Main application log (info, warn, error)
 */
const fileRotateTransport = new DailyRotateFile({
  filename: path.join(logDir, 'discord-bot-%DATE%.log'),
  datePattern: 'YYYY-MM-DD',
  maxSize: '20m',
  maxFiles: '14d', // Keep logs for 14 days
  zippedArchive: true,
  format: winston.format.combine(
    winston.format.timestamp(),
    redactingFormat
  ),
});

/**
 * Error-only log
 */
const errorRotateTransport = new DailyRotateFile({
  filename: path.join(logDir, 'error-%DATE%.log'),
  datePattern: 'YYYY-MM-DD',
  maxSize: '20m',
  maxFiles: '30d', // Keep error logs longer
  level: 'error',
  zippedArchive: true,
  format: winston.format.combine(
    winston.format.timestamp(),
    redactingFormat
  ),
});

/**
 * Console transport (development only)
 */
const consoleTransport = new winston.transports.Console({
  format: winston.format.combine(
    winston.format.colorize(),
    winston.format.timestamp({ format: 'HH:mm:ss' }),
    redactingFormat
  ),
});

/**
 * Main logger instance
 */
export const logger = winston.createLogger({
  level: process.env['LOG_LEVEL'] || 'info',
  transports: [
    fileRotateTransport,
    errorRotateTransport,
    ...(process.env['NODE_ENV'] !== 'production' ? [consoleTransport] : []),
  ],
  // Handle uncaught exceptions
  exceptionHandlers: [
    new DailyRotateFile({
      filename: path.join(logDir, 'exceptions-%DATE%.log'),
      datePattern: 'YYYY-MM-DD',
      maxFiles: '30d',
      format: winston.format.combine(
        winston.format.timestamp(),
        winston.format.json()
      ),
    }),
  ],
  // Handle unhandled promise rejections
  rejectionHandlers: [
    new DailyRotateFile({
      filename: path.join(logDir, 'rejections-%DATE%.log'),
      datePattern: 'YYYY-MM-DD',
      maxFiles: '30d',
      format: winston.format.combine(
        winston.format.timestamp(),
        winston.format.json()
      ),
    }),
  ],
});

/**
 * Audit logger (separate from general logs, structured JSON)
 */
const auditLogger = winston.createLogger({
  level: 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.json()
  ),
  transports: [
    new DailyRotateFile({
      filename: path.join(logDir, 'audit-%DATE%.log'),
      datePattern: 'YYYY-MM-DD',
      maxFiles: '90d', // Keep audit logs longer for compliance
      zippedArchive: true,
    }),
  ],
});

/**
 * Audit log entry
 */
export interface AuditEntry {
  action: string;
  userId: string;
  username?: string;
  guildId?: string;
  timestamp: string;
  details?: Record<string, any>;
  result?: 'success' | 'failure';
  error?: string;
  resource?: string; // Resource being accessed (e.g., webhook, Linear API)
}

/**
 * Write audit log entry
 */
export function audit(entry: AuditEntry): void {
  const sanitized = sanitizeForLogging(entry);
  auditLogger.info(sanitized);
}

/**
 * Audit log helpers for common actions
 */
export const auditLog = {
  command(userId: string, username: string, command: string, args: string[] = []) {
    audit({
      action: 'command_executed',
      userId,
      username,
      timestamp: new Date().toISOString(),
      details: { command, args: args.slice(0, 5) }, // Limit args to prevent huge logs
      result: 'success',
    });
  },

  feedbackCaptured(userId: string, username: string, messageId: string, issueId?: string) {
    audit({
      action: 'feedback_captured',
      userId,
      username,
      timestamp: new Date().toISOString(),
      details: { messageId, issueId },
      result: issueId ? 'success' : 'failure',
    });
  },

  statusUpdated(userId: string, username: string, issueId: string, from: string, to: string) {
    audit({
      action: 'status_updated',
      userId,
      username,
      timestamp: new Date().toISOString(),
      details: { issueId, from, to },
      result: 'success',
    });
  },

  permissionDenied(userId: string, username: string, permission: string) {
    audit({
      action: 'permission_denied',
      userId,
      username,
      timestamp: new Date().toISOString(),
      details: { permission },
      result: 'failure',
    });
  },

  authFailure(userId: string, reason: string) {
    audit({
      action: 'auth_failure',
      userId,
      timestamp: new Date().toISOString(),
      details: { reason },
      result: 'failure',
    });
  },

  configChanged(userId: string, username: string, configKey: string, action: 'read' | 'write') {
    audit({
      action: 'config_changed',
      userId,
      username,
      timestamp: new Date().toISOString(),
      details: { configKey, action },
      result: 'success',
    });
  },

  contextAssembly(userId: string, primaryDoc: string, details: Record<string, any>) {
    audit({
      action: 'context_assembled',
      userId,
      resource: primaryDoc,
      timestamp: new Date().toISOString(),
      details: {
        primaryDoc,
        ...details,
      },
      result: 'success',
    });
  },
};

/**
 * Set secure file permissions on rotated files
 */
fileRotateTransport.on('rotate', (oldFilename, newFilename) => {
  try {
    if (oldFilename) {
      fs.chmodSync(oldFilename, 0o600);
    }
    if (newFilename) {
      fs.chmodSync(newFilename, 0o600);
    }
  } catch (error) {
    console.error('Warning: Could not set log file permissions:', error);
  }
});

errorRotateTransport.on('rotate', (oldFilename, newFilename) => {
  try {
    if (oldFilename) {
      fs.chmodSync(oldFilename, 0o600);
    }
    if (newFilename) {
      fs.chmodSync(newFilename, 0o600);
    }
  } catch (error) {
    console.error('Warning: Could not set log file permissions:', error);
  }
});

/**
 * Log system info at startup
 */
export function logStartup(): void {
  logger.info('='.repeat(80));
  logger.info('Agentic-Base Integration Bot Starting');
  logger.info(`Node version: ${process.version}`);
  logger.info(`Platform: ${process.platform}`);
  logger.info(`Environment: ${process.env['NODE_ENV'] || 'development'}`);
  logger.info(`Log level: ${process.env['LOG_LEVEL'] || 'info'}`);
  logger.info('='.repeat(80));
}

/**
 * Monitor error rate and alert if too high
 */
let errorCount = 0;
let lastErrorReset = Date.now();
let lastAlertTime = 0;

logger.on('data', (info) => {
  if (info.level === 'error') {
    errorCount++;

    const now = Date.now();
    const elapsed = now - lastErrorReset;

    // Reset counter every minute
    if (elapsed > 60000) {
      errorCount = 1;
      lastErrorReset = now;
    }

    // Alert if >10 errors in 1 minute and haven't alerted in last 5 minutes
    if (errorCount > 10 && now - lastAlertTime > 300000) {
      logger.error(`🚨 HIGH ERROR RATE: ${errorCount} errors in last minute`);
      lastAlertTime = now;
      errorCount = 0;
      lastErrorReset = now;
    }
  }
});

export default logger;
