/**
 * Audit Logger Tests
 *
 * Tests for HIGH-007: Comprehensive Logging and Audit Trail
 */

import { AuditLogger, SecurityEventType, Severity, type SecurityEvent } from '../audit-logger';

// Mock validation module to avoid ES module issues
jest.mock('../validation', () => ({
  sanitizeForLogging: (data: any) => data,
}));

describe('AuditLogger', () => {
  let logger: AuditLogger;
  let loggedEvents: SecurityEvent[];

  beforeEach(() => {
    logger = new AuditLogger();
    loggedEvents = [];

    // Mock logEvent to capture events instead of writing to file
    jest.spyOn(logger, 'logEvent').mockImplementation((event: SecurityEvent) => {
      loggedEvents.push(event);
    });
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  describe('Authentication Events', () => {
    test('should log successful authentication', () => {
      logger.authSuccess('user-123', 'john.doe', { method: 'Discord OAuth' });

      expect(loggedEvents).toHaveLength(1);
      expect(loggedEvents[0]).toMatchObject({
        eventType: SecurityEventType.AUTH_SUCCESS,
        severity: Severity.INFO,
        userId: 'user-123',
        username: 'john.doe',
        action: 'User authenticated successfully',
        outcome: 'SUCCESS',
      });
    });

    test('should log failed authentication', () => {
      logger.authFailure('user-123', 'Invalid credentials');

      expect(loggedEvents).toHaveLength(1);
      expect(loggedEvents[0]).toMatchObject({
        eventType: SecurityEventType.AUTH_FAILURE,
        severity: Severity.MEDIUM,
        userId: 'user-123',
        action: 'Authentication failed',
        outcome: 'FAILURE',
      });
      expect(loggedEvents[0]!.details['reason']).toBe('Invalid credentials');
    });

    test('should log unauthorized access attempts', () => {
      logger.authUnauthorized('user-123', 'docs/confidential.md');

      expect(loggedEvents).toHaveLength(1);
      expect(loggedEvents[0]).toMatchObject({
        eventType: SecurityEventType.AUTH_UNAUTHORIZED,
        severity: Severity.MEDIUM,
        userId: 'user-123',
        resource: 'docs/confidential.md',
        action: 'Unauthorized access attempt',
        outcome: 'BLOCKED',
      });
    });
  });

  describe('Permission Events', () => {
    test('should log permission granted', () => {
      logger.permissionGranted('user-123', 'john.doe', 'translate', 'docs/prd.md');

      expect(loggedEvents).toHaveLength(1);
      expect(loggedEvents[0]).toMatchObject({
        eventType: SecurityEventType.PERMISSION_GRANTED,
        severity: Severity.INFO,
        userId: 'user-123',
        username: 'john.doe',
        resource: 'docs/prd.md',
        action: 'Permission granted',
        outcome: 'SUCCESS',
      });
      expect(loggedEvents[0]!.details['permission']).toBe('translate');
    });

    test('should log permission denied', () => {
      logger.permissionDenied('user-123', 'john.doe', 'admin', 'config.yaml');

      expect(loggedEvents).toHaveLength(1);
      expect(loggedEvents[0]).toMatchObject({
        eventType: SecurityEventType.PERMISSION_DENIED,
        severity: Severity.MEDIUM,
        userId: 'user-123',
        username: 'john.doe',
        resource: 'config.yaml',
        action: 'Permission denied',
        outcome: 'BLOCKED',
      });
    });
  });

  describe('Command Events', () => {
    test('should log command invocation', () => {
      logger.commandInvoked('user-123', 'john.doe', 'translate', ['docs/prd.md', 'executive']);

      expect(loggedEvents).toHaveLength(1);
      expect(loggedEvents[0]).toMatchObject({
        eventType: SecurityEventType.COMMAND_INVOKED,
        severity: Severity.INFO,
        userId: 'user-123',
        username: 'john.doe',
        action: 'Command executed',
        outcome: 'SUCCESS',
      });
      expect(loggedEvents[0]!.details['command']).toBe('translate');
      expect(loggedEvents[0]!.details['args']).toEqual(['docs/prd.md', 'executive']);
    });

    test('should limit args to 5 to prevent huge logs', () => {
      const manyArgs = Array.from({ length: 10 }, (_, i) => `arg${i}`);
      logger.commandInvoked('user-123', 'john.doe', 'test', manyArgs);

      expect(loggedEvents[0]!.details['args']).toHaveLength(5);
    });

    test('should log blocked command', () => {
      logger.commandBlocked('user-123', 'john.doe', 'admin-reset', 'Insufficient permissions');

      expect(loggedEvents).toHaveLength(1);
      expect(loggedEvents[0]).toMatchObject({
        eventType: SecurityEventType.COMMAND_BLOCKED,
        severity: Severity.MEDIUM,
        userId: 'user-123',
        username: 'john.doe',
        action: 'Command blocked',
        outcome: 'BLOCKED',
      });
      expect(loggedEvents[0]!.details['reason']).toBe('Insufficient permissions');
    });

    test('should log failed command', () => {
      logger.commandFailed('user-123', 'john.doe', 'fetch-data', 'API timeout');

      expect(loggedEvents).toHaveLength(1);
      expect(loggedEvents[0]).toMatchObject({
        eventType: SecurityEventType.COMMAND_FAILED,
        severity: Severity.LOW,
        userId: 'user-123',
        username: 'john.doe',
        action: 'Command failed',
        outcome: 'FAILURE',
      });
      expect(loggedEvents[0]!.details['error']).toBe('API timeout');
    });
  });

  describe('Translation Events', () => {
    test('should log translation request', () => {
      logger.translationRequested(
        'user-123',
        'john.doe',
        ['docs/prd.md', 'docs/sdd.md'],
        'executive',
        'Board of Directors'
      );

      expect(loggedEvents).toHaveLength(1);
      expect(loggedEvents[0]).toMatchObject({
        eventType: SecurityEventType.TRANSLATION_REQUESTED,
        severity: Severity.INFO,
        userId: 'user-123',
        username: 'john.doe',
        action: 'Translation requested',
        outcome: 'PENDING',
      });
      expect(loggedEvents[0]!.details['documents']).toEqual(['docs/prd.md', 'docs/sdd.md']);
      expect(loggedEvents[0]!.details['format']).toBe('executive');
      expect(loggedEvents[0]!.details['audience']).toBe('Board of Directors');
    });

    test('should log translation generation', () => {
      logger.translationGenerated('user-123', 'john.doe', ['docs/prd.md'], 'executive');

      expect(loggedEvents).toHaveLength(1);
      expect(loggedEvents[0]).toMatchObject({
        eventType: SecurityEventType.TRANSLATION_GENERATED,
        severity: Severity.INFO,
        userId: 'user-123',
        username: 'john.doe',
        action: 'Translation generated successfully',
        outcome: 'SUCCESS',
      });
    });

    test('should log translation approval', () => {
      logger.translationApproved('user-123', 'john.doe', 'trans_abc123');

      expect(loggedEvents).toHaveLength(1);
      expect(loggedEvents[0]).toMatchObject({
        eventType: SecurityEventType.TRANSLATION_APPROVED,
        severity: Severity.INFO,
        userId: 'user-123',
        username: 'john.doe',
        action: 'Translation approved for distribution',
        outcome: 'SUCCESS',
      });
      expect(loggedEvents[0]!.details['translationId']).toBe('trans_abc123');
    });
  });

  describe('Secret Detection Events', () => {
    test('should log secret detection', () => {
      logger.secretDetected('docs/config.md', 'STRIPE_SECRET_KEY_LIVE', Severity.CRITICAL);

      expect(loggedEvents).toHaveLength(1);
      expect(loggedEvents[0]).toMatchObject({
        eventType: SecurityEventType.SECRET_DETECTED,
        severity: Severity.CRITICAL,
        action: 'Secret detected in document/commit',
        outcome: 'BLOCKED',
      });
      expect(loggedEvents[0]!.details['location']).toBe('docs/config.md');
      expect(loggedEvents[0]!.details['secretType']).toBe('STRIPE_SECRET_KEY_LIVE');
    });

    test('should log secrets leak detection', () => {
      logger.secretsLeakDetected('https://github.com/test/repo/commit/abc123', 3, 2);

      expect(loggedEvents).toHaveLength(1);
      expect(loggedEvents[0]).toMatchObject({
        eventType: SecurityEventType.SECRETS_LEAK_DETECTED,
        severity: Severity.CRITICAL,
        action: 'Secrets leak detected in public repository',
        outcome: 'BLOCKED',
      });
      expect(loggedEvents[0]!.details['secretCount']).toBe(3);
      expect(loggedEvents[0]!.details['criticalCount']).toBe(2);
    });

    test('should log service pause due to leak', () => {
      logger.servicePausedLeak('Discord bot token leaked in public commit');

      expect(loggedEvents).toHaveLength(1);
      expect(loggedEvents[0]).toMatchObject({
        eventType: SecurityEventType.SERVICE_PAUSED_LEAK,
        severity: Severity.CRITICAL,
        action: 'Service paused due to secrets leak',
        outcome: 'BLOCKED',
      });
    });
  });

  describe('Document Access Events', () => {
    test('should log document access', () => {
      logger.documentAccessed('user-123', 'john.doe', 'docs/prd.md');

      expect(loggedEvents).toHaveLength(1);
      expect(loggedEvents[0]).toMatchObject({
        eventType: SecurityEventType.DOCUMENT_ACCESSED,
        severity: Severity.INFO,
        userId: 'user-123',
        username: 'john.doe',
        resource: 'docs/prd.md',
        action: 'Document accessed',
        outcome: 'SUCCESS',
      });
    });

    test('should log document rejection due to size', () => {
      logger.documentRejectedSize('user-123', 'john.doe', 'docs/huge.pdf', 150000, 100000);

      expect(loggedEvents).toHaveLength(1);
      expect(loggedEvents[0]).toMatchObject({
        eventType: SecurityEventType.DOCUMENT_REJECTED_SIZE,
        severity: Severity.MEDIUM,
        userId: 'user-123',
        username: 'john.doe',
        resource: 'docs/huge.pdf',
        action: 'Document rejected due to size limits',
        outcome: 'BLOCKED',
      });
      expect(loggedEvents[0]!.details['size']).toBe(150000);
      expect(loggedEvents[0]!.details['maxSize']).toBe(100000);
    });
  });

  describe('Configuration Events', () => {
    test('should log configuration read', () => {
      logger.configRead('user-123', 'admin@example.com', 'monitored_folders');

      expect(loggedEvents).toHaveLength(1);
      expect(loggedEvents[0]).toMatchObject({
        eventType: SecurityEventType.CONFIG_READ,
        severity: Severity.INFO,
        userId: 'user-123',
        username: 'admin@example.com',
        action: 'Configuration read',
        outcome: 'SUCCESS',
      });
      expect(loggedEvents[0]!.details['configKey']).toBe('monitored_folders');
    });

    test('should log configuration modification', () => {
      logger.configModified(
        'user-123',
        'admin@example.com',
        'max_documents',
        10,
        20
      );

      expect(loggedEvents).toHaveLength(1);
      expect(loggedEvents[0]).toMatchObject({
        eventType: SecurityEventType.CONFIG_MODIFIED,
        severity: Severity.HIGH,
        userId: 'user-123',
        username: 'admin@example.com',
        action: 'Configuration modified',
        outcome: 'SUCCESS',
      });
      expect(loggedEvents[0]!.details['configKey']).toBe('max_documents');
      expect(loggedEvents[0]!.details['oldValue']).toBe(10);
      expect(loggedEvents[0]!.details['newValue']).toBe(20);
    });
  });

  describe('Rate Limiting Events', () => {
    test('should log rate limit exceeded', () => {
      logger.rateLimitExceeded('user-123', 'john.doe', 'command_rate_limit');

      expect(loggedEvents).toHaveLength(1);
      expect(loggedEvents[0]).toMatchObject({
        eventType: SecurityEventType.RATE_LIMIT_EXCEEDED,
        severity: Severity.MEDIUM,
        userId: 'user-123',
        username: 'john.doe',
        action: 'Rate limit exceeded',
        outcome: 'BLOCKED',
      });
      expect(loggedEvents[0]!.details['limitType']).toBe('command_rate_limit');
    });
  });

  describe('System Events', () => {
    test('should log system startup', () => {
      logger.systemStartup();

      expect(loggedEvents).toHaveLength(1);
      expect(loggedEvents[0]).toMatchObject({
        eventType: SecurityEventType.SYSTEM_STARTUP,
        severity: Severity.INFO,
        action: 'System started',
        outcome: 'SUCCESS',
      });
      expect(loggedEvents[0]!.details['nodeVersion']).toBeDefined();
      expect(loggedEvents[0]!.details['platform']).toBeDefined();
    });

    test('should log system shutdown', () => {
      logger.systemShutdown();

      expect(loggedEvents).toHaveLength(1);
      expect(loggedEvents[0]).toMatchObject({
        eventType: SecurityEventType.SYSTEM_SHUTDOWN,
        severity: Severity.INFO,
        action: 'System shutdown',
        outcome: 'SUCCESS',
      });
    });

    test('should log security exceptions', () => {
      const error = new Error('Path traversal detected');
      error.stack = 'Error: Path traversal detected\n  at ...';

      logger.securityException('user-123', 'file_access', error);

      expect(loggedEvents).toHaveLength(1);
      expect(loggedEvents[0]).toMatchObject({
        eventType: SecurityEventType.SECURITY_EXCEPTION,
        severity: Severity.HIGH,
        userId: 'user-123',
        action: 'Security exception occurred',
        outcome: 'FAILURE',
      });
      expect(loggedEvents[0]!.details['action']).toBe('file_access');
      expect(loggedEvents[0]!.details['error']).toBe('Path traversal detected');
      expect(loggedEvents[0]!.details['stack']).toBeDefined();
    });
  });

  describe('Event Structure', () => {
    test('should include timestamp in ISO format', () => {
      logger.authSuccess('user-123', 'john.doe');

      expect(loggedEvents[0]!.timestamp).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/);
    });

    test('should include all required fields', () => {
      logger.authSuccess('user-123', 'john.doe');

      const event = loggedEvents[0]!;
      expect(event.timestamp).toBeDefined();
      expect(event.eventType).toBeDefined();
      expect(event.severity).toBeDefined();
      expect(event.action).toBeDefined();
      expect(event.outcome).toBeDefined();
      expect(event.details).toBeDefined();
    });

    test('should sanitize sensitive data in details', () => {
      // Note: Actual sanitization is tested in validation.test.ts
      // This test just verifies the structure
      logger.configModified('user-123', 'admin', 'api_key', 'old_key', 'new_key');

      expect(loggedEvents[0]!.details).toBeDefined();
      expect(typeof loggedEvents[0]!.details).toBe('object');
    });
  });

  describe('Attack Scenario Prevention', () => {
    test('should log HIGH-007 scenario: unauthorized document access attempt', () => {
      // Scenario: User attempts to access confidential document without permission
      // Before fix: Access granted, no audit trail
      // After fix: Access denied, event logged for investigation

      logger.authUnauthorized('contractor-456', 'docs/financials-q4.md');

      expect(loggedEvents).toHaveLength(1);
      expect(loggedEvents[0]).toMatchObject({
        eventType: SecurityEventType.AUTH_UNAUTHORIZED,
        severity: Severity.MEDIUM,
        userId: 'contractor-456',
        resource: 'docs/financials-q4.md',
        outcome: 'BLOCKED',
      });

      // Security team can now:
      // 1. Review unauthorized access attempts
      // 2. Identify patterns of suspicious behavior
      // 3. Investigate if account is compromised
      // 4. Audit who has access to sensitive documents
    });

    test('should log HIGH-007 scenario: secrets leak in public commit', () => {
      // Scenario: Discord bot token leaked in public GitHub commit
      // Before fix: Leak undetected for months
      // After fix: Immediate CRITICAL alert, service paused

      logger.secretsLeakDetected('https://github.com/company/repo/commit/abc123', 1, 1);

      expect(loggedEvents).toHaveLength(1);
      expect(loggedEvents[0]).toMatchObject({
        eventType: SecurityEventType.SECRETS_LEAK_DETECTED,
        severity: Severity.CRITICAL,
        outcome: 'BLOCKED',
      });

      // Follow-up actions logged:
      logger.servicePausedLeak('Discord bot token exposed in commit abc123');

      expect(loggedEvents).toHaveLength(2);
      expect(loggedEvents[1]).toMatchObject({
        eventType: SecurityEventType.SERVICE_PAUSED_LEAK,
        severity: Severity.CRITICAL,
        outcome: 'BLOCKED',
      });

      // Timeline reconstruction possible:
      // - When leak was detected
      // - What secret was leaked
      // - When service was paused
      // - Who rotated the secret (subsequent log entry)
      // - When service was resumed
    });

    test('should log HIGH-007 scenario: configuration tampering', () => {
      // Scenario: Attacker modifies monitored_folders to exclude sensitive folder
      // Before fix: Change undetected, sensitive docs no longer monitored
      // After fix: Change logged with user ID, old/new values, HIGH severity

      logger.configModified(
        'contractor-789',
        'contractor@external.com',
        'monitored_folders',
        ['company/confidential', 'company/public'],
        ['company/public'] // Removed confidential folder!
      );

      expect(loggedEvents).toHaveLength(1);
      expect(loggedEvents[0]).toMatchObject({
        eventType: SecurityEventType.CONFIG_MODIFIED,
        severity: Severity.HIGH,
        userId: 'contractor-789',
        username: 'contractor@external.com',
      });

      // Security team alerted to:
      // 1. Unauthorized config change
      // 2. Who made the change (contractor, not employee)
      // 3. What was changed (removed confidential folder)
      // 4. When it happened (timestamp)
      //
      // Can immediately:
      // - Revert change
      // - Revoke contractor's config access
      // - Investigate if data was exfiltrated
    });
  });
});
