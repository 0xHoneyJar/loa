/**
 * Comprehensive Audit Logger
 *
 * Implements HIGH-007: Comprehensive Logging and Audit Trail
 *
 * Security event logging for:
 * - Authentication (success, failure, unauthorized)
 * - Authorization (permission checks, access grants/denials)
 * - Command execution (all Discord commands with parameters)
 * - Translation generation (documents included, format, approval)
 * - Secret detection (secrets found in documents/commits)
 * - Configuration changes (who changed what, when)
 * - Error events (exceptions, API failures, rate limits)
 *
 * Log retention: 1 year for compliance (SOC2, GDPR)
 * SIEM integration: Ready for Datadog, Splunk, ELK Stack
 */

import winston from 'winston';
import DailyRotateFile from 'winston-daily-rotate-file';
import fs from 'fs';
import path from 'path';
import { sanitizeForLogging } from './validation';

/**
 * Security Event Types (HIGH-007 requirement)
 */
export enum SecurityEventType {
  // Authentication & Authorization
  AUTH_SUCCESS = 'AUTH_SUCCESS',
  AUTH_FAILURE = 'AUTH_FAILURE',
  AUTH_UNAUTHORIZED = 'AUTH_UNAUTHORIZED',
  PERMISSION_GRANTED = 'PERMISSION_GRANTED',
  PERMISSION_DENIED = 'PERMISSION_DENIED',

  // Command Execution
  COMMAND_INVOKED = 'COMMAND_INVOKED',
  COMMAND_BLOCKED = 'COMMAND_BLOCKED',
  COMMAND_FAILED = 'COMMAND_FAILED',

  // Translation & Document Access
  TRANSLATION_REQUESTED = 'TRANSLATION_REQUESTED',
  TRANSLATION_GENERATED = 'TRANSLATION_GENERATED',
  TRANSLATION_FAILED = 'TRANSLATION_FAILED',
  TRANSLATION_APPROVED = 'TRANSLATION_APPROVED',
  TRANSLATION_REJECTED = 'TRANSLATION_REJECTED',
  DOCUMENT_ACCESSED = 'DOCUMENT_ACCESSED',
  DOCUMENT_REJECTED_SIZE = 'DOCUMENT_REJECTED_SIZE',
  CONTEXT_ASSEMBLED = 'CONTEXT_ASSEMBLED',

  // Secret Detection & Security
  SECRET_DETECTED = 'SECRET_DETECTED',
  SECRET_REDACTED = 'SECRET_REDACTED',
  SECRET_ROTATION_DUE = 'SECRET_ROTATION_DUE',
  SECRET_ROTATION_OVERDUE = 'SECRET_ROTATION_OVERDUE',
  SECRETS_LEAK_DETECTED = 'SECRETS_LEAK_DETECTED',
  SERVICE_PAUSED_LEAK = 'SERVICE_PAUSED_LEAK',

  // Configuration & Admin
  CONFIG_READ = 'CONFIG_READ',
  CONFIG_MODIFIED = 'CONFIG_MODIFIED',
  CONFIG_VALIDATION_FAILED = 'CONFIG_VALIDATION_FAILED',
  USER_ACCESS_GRANTED = 'USER_ACCESS_GRANTED',
  USER_ACCESS_REVOKED = 'USER_ACCESS_REVOKED',

  // Rate Limiting & Abuse
  RATE_LIMIT_EXCEEDED = 'RATE_LIMIT_EXCEEDED',
  API_QUOTA_EXCEEDED = 'API_QUOTA_EXCEEDED',
  SUSPICIOUS_ACTIVITY = 'SUSPICIOUS_ACTIVITY',

  // System & Errors
  SYSTEM_STARTUP = 'SYSTEM_STARTUP',
  SYSTEM_SHUTDOWN = 'SYSTEM_SHUTDOWN',
  SECURITY_EXCEPTION = 'SECURITY_EXCEPTION',
  ERROR_HIGH_RATE = 'ERROR_HIGH_RATE',
  SERVICE_DEGRADED = 'SERVICE_DEGRADED',
  SERVICE_RECOVERED = 'SERVICE_RECOVERED',
}

/**
 * Severity levels (aligned with security standards)
 */
export enum Severity {
  INFO = 'INFO',
  LOW = 'LOW',
  MEDIUM = 'MEDIUM',
  HIGH = 'HIGH',
  CRITICAL = 'CRITICAL',
}

/**
 * Comprehensive audit event structure
 */
export interface SecurityEvent {
  timestamp: string;
  eventType: SecurityEventType;
  severity: Severity;
  userId?: string;
  username?: string;
  action: string;
  resource?: string;
  outcome: 'SUCCESS' | 'FAILURE' | 'BLOCKED' | 'PENDING';
  details: Record<string, any>;
  ipAddress?: string;
  userAgent?: string;
  sessionId?: string;
  requestId?: string;
}

/**
 * Log directory with secure permissions
 */
const logDir = path.join(__dirname, '../../logs');

if (!fs.existsSync(logDir)) {
  fs.mkdirSync(logDir, { recursive: true, mode: 0o700 });
} else {
  try {
    fs.chmodSync(logDir, 0o700);
  } catch (error) {
    console.error('Warning: Could not set log directory permissions:', error);
  }
}

/**
 * Security audit logger (separate from general logs)
 *
 * HIGH-007: 1-year retention for compliance
 */
const securityAuditLogger = winston.createLogger({
  level: 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.json()
  ),
  transports: [
    new DailyRotateFile({
      filename: path.join(logDir, 'security-audit-%DATE%.log'),
      datePattern: 'YYYY-MM-DD',
      maxFiles: '365d', // HIGH-007: 1 year retention
      zippedArchive: true,
      maxSize: '50m',
    }),
  ],
});

/**
 * Critical security events logger (immediate alerting)
 */
const criticalSecurityLogger = winston.createLogger({
  level: 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.json()
  ),
  transports: [
    new DailyRotateFile({
      filename: path.join(logDir, 'critical-security-%DATE%.log'),
      datePattern: 'YYYY-MM-DD',
      maxFiles: '365d', // 1 year retention
      zippedArchive: true,
    }),
    // Also log to console for immediate visibility
    new winston.transports.Console({
      format: winston.format.combine(
        winston.format.colorize(),
        winston.format.timestamp(),
        winston.format.printf(({ timestamp, eventType, severity, action, details }) => {
          return `[${timestamp}] 🚨 ${severity} - ${eventType}: ${action}\n${JSON.stringify(details, null, 2)}`;
        })
      ),
    }),
  ],
});

/**
 * Main audit logger class
 */
export class AuditLogger {
  /**
   * Log a security event
   */
  logEvent(event: SecurityEvent): void {
    // Sanitize event data to remove secrets/PII
    const sanitizedEvent = sanitizeForLogging(event);

    // Add correlation ID if not present
    if (!sanitizedEvent.requestId) {
      sanitizedEvent.requestId = this.generateRequestId();
    }

    // Log to security audit log
    securityAuditLogger.info(sanitizedEvent);

    // If CRITICAL severity, also log to critical channel
    if (event.severity === Severity.CRITICAL) {
      criticalSecurityLogger.info(sanitizedEvent);

      // TODO: Send to alerting systems
      // - Discord webhook to #security-alerts
      // - PagerDuty for on-call rotation
      // - Email to security team
      // - SIEM integration (Datadog, Splunk, ELK)
    }
  }

  /**
   * Generate unique request ID for correlation
   */
  private generateRequestId(): string {
    return `req_${Date.now()}_${Math.random().toString(36).substring(2, 11)}`;
  }

  /**
   * Helper methods for common security events
   */

  // Authentication events
  authSuccess(userId: string, username: string, details?: Record<string, any>): void {
    this.logEvent({
      timestamp: new Date().toISOString(),
      eventType: SecurityEventType.AUTH_SUCCESS,
      severity: Severity.INFO,
      userId,
      username,
      action: 'User authenticated successfully',
      outcome: 'SUCCESS',
      details: details || {},
    });
  }

  authFailure(userId: string, reason: string, details?: Record<string, any>): void {
    this.logEvent({
      timestamp: new Date().toISOString(),
      eventType: SecurityEventType.AUTH_FAILURE,
      severity: Severity.MEDIUM,
      userId,
      action: 'Authentication failed',
      outcome: 'FAILURE',
      details: { reason, ...details },
    });
  }

  authUnauthorized(userId: string, resource: string, details?: Record<string, any>): void {
    this.logEvent({
      timestamp: new Date().toISOString(),
      eventType: SecurityEventType.AUTH_UNAUTHORIZED,
      severity: Severity.MEDIUM,
      userId,
      resource,
      action: 'Unauthorized access attempt',
      outcome: 'BLOCKED',
      details: details || {},
    });
  }

  // Permission events
  permissionGranted(userId: string, username: string, permission: string, resource?: string): void {
    this.logEvent({
      timestamp: new Date().toISOString(),
      eventType: SecurityEventType.PERMISSION_GRANTED,
      severity: Severity.INFO,
      userId,
      username,
      resource,
      action: 'Permission granted',
      outcome: 'SUCCESS',
      details: { permission },
    });
  }

  permissionDenied(userId: string, username: string, permission: string, resource?: string): void {
    this.logEvent({
      timestamp: new Date().toISOString(),
      eventType: SecurityEventType.PERMISSION_DENIED,
      severity: Severity.MEDIUM,
      userId,
      username,
      resource,
      action: 'Permission denied',
      outcome: 'BLOCKED',
      details: { permission },
    });
  }

  // Command events
  commandInvoked(userId: string, username: string, command: string, args: string[] = []): void {
    this.logEvent({
      timestamp: new Date().toISOString(),
      eventType: SecurityEventType.COMMAND_INVOKED,
      severity: Severity.INFO,
      userId,
      username,
      action: 'Command executed',
      outcome: 'SUCCESS',
      details: { command, args: args.slice(0, 5) }, // Limit args to prevent huge logs
    });
  }

  commandBlocked(userId: string, username: string, command: string, reason: string): void {
    this.logEvent({
      timestamp: new Date().toISOString(),
      eventType: SecurityEventType.COMMAND_BLOCKED,
      severity: Severity.MEDIUM,
      userId,
      username,
      action: 'Command blocked',
      outcome: 'BLOCKED',
      details: { command, reason },
    });
  }

  commandFailed(userId: string, username: string, command: string, error: string): void {
    this.logEvent({
      timestamp: new Date().toISOString(),
      eventType: SecurityEventType.COMMAND_FAILED,
      severity: Severity.LOW,
      userId,
      username,
      action: 'Command failed',
      outcome: 'FAILURE',
      details: { command, error },
    });
  }

  // Translation events
  translationRequested(userId: string, username: string, documents: string[], format: string, audience: string): void {
    this.logEvent({
      timestamp: new Date().toISOString(),
      eventType: SecurityEventType.TRANSLATION_REQUESTED,
      severity: Severity.INFO,
      userId,
      username,
      action: 'Translation requested',
      outcome: 'PENDING',
      details: { documents, format, audience },
    });
  }

  translationGenerated(userId: string, username: string, documents: string[], format: string): void {
    this.logEvent({
      timestamp: new Date().toISOString(),
      eventType: SecurityEventType.TRANSLATION_GENERATED,
      severity: Severity.INFO,
      userId,
      username,
      action: 'Translation generated successfully',
      outcome: 'SUCCESS',
      details: { documents, format },
    });
  }

  translationApproved(userId: string, username: string, translationId: string): void {
    this.logEvent({
      timestamp: new Date().toISOString(),
      eventType: SecurityEventType.TRANSLATION_APPROVED,
      severity: Severity.INFO,
      userId,
      username,
      action: 'Translation approved for distribution',
      outcome: 'SUCCESS',
      details: { translationId },
    });
  }

  // Secret detection events
  secretDetected(location: string, secretType: string, severity: Severity): void {
    this.logEvent({
      timestamp: new Date().toISOString(),
      eventType: SecurityEventType.SECRET_DETECTED,
      severity: severity === Severity.CRITICAL ? Severity.CRITICAL : Severity.HIGH,
      action: 'Secret detected in document/commit',
      outcome: 'BLOCKED',
      details: { location, secretType },
    });
  }

  secretsLeakDetected(location: string, secretCount: number, criticalCount: number): void {
    this.logEvent({
      timestamp: new Date().toISOString(),
      eventType: SecurityEventType.SECRETS_LEAK_DETECTED,
      severity: Severity.CRITICAL,
      action: 'Secrets leak detected in public repository',
      outcome: 'BLOCKED',
      details: { location, secretCount, criticalCount },
    });
  }

  servicePausedLeak(reason: string): void {
    this.logEvent({
      timestamp: new Date().toISOString(),
      eventType: SecurityEventType.SERVICE_PAUSED_LEAK,
      severity: Severity.CRITICAL,
      action: 'Service paused due to secrets leak',
      outcome: 'BLOCKED',
      details: { reason },
    });
  }

  // Document access events
  documentAccessed(userId: string, username: string, documentPath: string): void {
    this.logEvent({
      timestamp: new Date().toISOString(),
      eventType: SecurityEventType.DOCUMENT_ACCESSED,
      severity: Severity.INFO,
      userId,
      username,
      resource: documentPath,
      action: 'Document accessed',
      outcome: 'SUCCESS',
      details: { documentPath },
    });
  }

  documentRejectedSize(userId: string, username: string, documentPath: string, size: number, maxSize: number): void {
    this.logEvent({
      timestamp: new Date().toISOString(),
      eventType: SecurityEventType.DOCUMENT_REJECTED_SIZE,
      severity: Severity.MEDIUM,
      userId,
      username,
      resource: documentPath,
      action: 'Document rejected due to size limits',
      outcome: 'BLOCKED',
      details: { documentPath, size, maxSize },
    });
  }

  // Configuration events
  configRead(userId: string, username: string, configKey: string): void {
    this.logEvent({
      timestamp: new Date().toISOString(),
      eventType: SecurityEventType.CONFIG_READ,
      severity: Severity.INFO,
      userId,
      username,
      action: 'Configuration read',
      outcome: 'SUCCESS',
      details: { configKey },
    });
  }

  configModified(userId: string, username: string, configKey: string, oldValue?: any, newValue?: any): void {
    this.logEvent({
      timestamp: new Date().toISOString(),
      eventType: SecurityEventType.CONFIG_MODIFIED,
      severity: Severity.HIGH,
      userId,
      username,
      action: 'Configuration modified',
      outcome: 'SUCCESS',
      details: {
        configKey,
        oldValue: sanitizeForLogging(oldValue),
        newValue: sanitizeForLogging(newValue),
      },
    });
  }

  // Rate limiting events
  rateLimitExceeded(userId: string, username: string, limitType: string): void {
    this.logEvent({
      timestamp: new Date().toISOString(),
      eventType: SecurityEventType.RATE_LIMIT_EXCEEDED,
      severity: Severity.MEDIUM,
      userId,
      username,
      action: 'Rate limit exceeded',
      outcome: 'BLOCKED',
      details: { limitType },
    });
  }

  // System events
  systemStartup(): void {
    this.logEvent({
      timestamp: new Date().toISOString(),
      eventType: SecurityEventType.SYSTEM_STARTUP,
      severity: Severity.INFO,
      action: 'System started',
      outcome: 'SUCCESS',
      details: {
        nodeVersion: process.version,
        platform: process.platform,
        environment: process.env['NODE_ENV'] || 'development',
      },
    });
  }

  systemShutdown(): void {
    this.logEvent({
      timestamp: new Date().toISOString(),
      eventType: SecurityEventType.SYSTEM_SHUTDOWN,
      severity: Severity.INFO,
      action: 'System shutdown',
      outcome: 'SUCCESS',
      details: {},
    });
  }

  // Context assembly events (HIGH-011)
  contextAssembly(userId: string, primaryDoc: string, details: Record<string, any>): void {
    this.logEvent({
      timestamp: new Date().toISOString(),
      eventType: SecurityEventType.CONTEXT_ASSEMBLED,
      severity: Severity.INFO,
      userId,
      resource: primaryDoc,
      action: 'Context assembled for document',
      outcome: 'SUCCESS',
      details: {
        primaryDoc,
        ...details,
      },
    });
  }

  // Security exceptions
  securityException(userId: string | undefined, action: string, error: Error): void {
    this.logEvent({
      timestamp: new Date().toISOString(),
      eventType: SecurityEventType.SECURITY_EXCEPTION,
      severity: Severity.HIGH,
      userId,
      action: 'Security exception occurred',
      outcome: 'FAILURE',
      details: {
        action,
        error: error.message,
        stack: error.stack,
      },
    });
  }
}

/**
 * Singleton instance
 */
export const auditLogger = new AuditLogger();

/**
 * Export for testing
 */
export default auditLogger;
