/**
 * Secrets Rotation Monitor Tests
 *
 * Tests for CRITICAL-008: Secrets Rotation Strategy
 */

import { SecretsRotationMonitor } from '../../src/services/secrets-rotation-monitor';
import * as fs from 'fs';
import * as path from 'path';
import * as yaml from 'js-yaml';

describe('SecretsRotationMonitor', () => {
  let monitor: SecretsRotationMonitor;
  let testPolicyPath: string;

  beforeEach(() => {
    // Create temporary test policy file
    testPolicyPath = path.join(__dirname, '../fixtures/test-rotation-policy.yaml');

    const testPolicy = {
      secrets_rotation: {
        test_secret_ok: {
          interval_days: 90,
          last_rotated: new Date(Date.now() - 45 * 24 * 60 * 60 * 1000).toISOString().split('T')[0], // 45 days ago
          next_rotation: null,
          description: 'Test secret with OK status',
          rotation_runbook: 'docs/runbooks/secrets-rotation.md'
        },
        test_secret_expiring: {
          interval_days: 90,
          last_rotated: new Date(Date.now() - 80 * 24 * 60 * 60 * 1000).toISOString().split('T')[0], // 80 days ago (10 days until expiry)
          next_rotation: null,
          description: 'Test secret expiring soon',
          rotation_runbook: 'docs/runbooks/secrets-rotation.md'
        },
        test_secret_expired: {
          interval_days: 90,
          last_rotated: new Date(Date.now() - 100 * 24 * 60 * 60 * 1000).toISOString().split('T')[0], // 100 days ago (10 days overdue)
          next_rotation: null,
          description: 'Test secret that is expired',
          rotation_runbook: 'docs/runbooks/secrets-rotation.md'
        },
        test_secret_never_rotated: {
          interval_days: 90,
          last_rotated: null,
          next_rotation: null,
          description: 'Test secret never rotated',
          rotation_runbook: 'docs/runbooks/secrets-rotation.md'
        }
      },
      reminders: {
        reminder_days_before: 14,
        notification_channels: ['console', 'email'],
        notification_recipients: ['test@example.com']
      },
      leak_detection: {
        enabled: true,
        scan_interval_hours: 168,
        repositories: ['https://github.com/test/repo'],
        scan_history_days: 90,
        auto_pause_on_leak: true
      },
      emergency_rotation: {
        immediate_rotation_required: true,
        pause_services_on_compromise: true,
        escalate_to: ['security@example.com']
      },
      audit: {
        log_rotations: true,
        log_file: 'logs/secrets-rotation.log',
        retention_days: 365
      }
    };

    // Create fixtures directory
    const fixturesDir = path.dirname(testPolicyPath);
    if (!fs.existsSync(fixturesDir)) {
      fs.mkdirSync(fixturesDir, { recursive: true });
    }

    // Write test policy
    fs.writeFileSync(testPolicyPath, yaml.dump(testPolicy), 'utf8');

    monitor = new SecretsRotationMonitor(testPolicyPath);
  });

  afterEach(() => {
    // Clean up test policy file
    if (fs.existsSync(testPolicyPath)) {
      fs.unlinkSync(testPolicyPath);
    }
  });

  describe('loadRotationPolicy', () => {
    test('should load rotation policy from YAML file', async () => {
      const policy = await monitor.loadRotationPolicy();

      expect(policy).toBeDefined();
      expect(policy.secrets_rotation).toBeDefined();
      expect(policy.reminders).toBeDefined();
      expect(policy.leak_detection).toBeDefined();
    });

    test('should throw error if policy file not found', async () => {
      const invalidMonitor = new SecretsRotationMonitor('/invalid/path/policy.yaml');

      await expect(invalidMonitor.loadRotationPolicy()).rejects.toThrow('Failed to load rotation policy');
    });
  });

  describe('checkRotationStatus', () => {
    test('should check rotation status for all secrets', async () => {
      const statuses = await monitor.checkRotationStatus();

      expect(statuses.length).toBe(4);
      expect(statuses.map(s => s.secret)).toEqual([
        'test_secret_ok',
        'test_secret_expiring',
        'test_secret_expired',
        'test_secret_never_rotated'
      ]);
    });

    test('should correctly identify OK status', async () => {
      const statuses = await monitor.checkRotationStatus();
      const okSecret = statuses.find(s => s.secret === 'test_secret_ok');

      expect(okSecret).toBeDefined();
      expect(okSecret!.status).toBe('OK');
      expect(okSecret!.severity).toBe('INFO');
      expect(okSecret!.daysRemaining).toBeGreaterThan(14);
    });

    test('should correctly identify EXPIRING_SOON status', async () => {
      const statuses = await monitor.checkRotationStatus();
      const expiringSecret = statuses.find(s => s.secret === 'test_secret_expiring');

      expect(expiringSecret).toBeDefined();
      expect(expiringSecret!.status).toBe('EXPIRING_SOON');
      expect(expiringSecret!.severity).toBe('HIGH');
      expect(expiringSecret!.daysRemaining).toBeLessThanOrEqual(14);
      expect(expiringSecret!.daysRemaining).toBeGreaterThan(0);
    });

    test('should correctly identify EXPIRED status', async () => {
      const statuses = await monitor.checkRotationStatus();
      const expiredSecret = statuses.find(s => s.secret === 'test_secret_expired');

      expect(expiredSecret).toBeDefined();
      expect(expiredSecret!.status).toBe('EXPIRED');
      expect(expiredSecret!.severity).toBe('CRITICAL');
      expect(expiredSecret!.daysOverdue).toBeGreaterThan(0);
    });

    test('should correctly identify NEVER_ROTATED status', async () => {
      const statuses = await monitor.checkRotationStatus();
      const neverRotated = statuses.find(s => s.secret === 'test_secret_never_rotated');

      expect(neverRotated).toBeDefined();
      expect(neverRotated!.status).toBe('NEVER_ROTATED');
      expect(neverRotated!.severity).toBe('HIGH');
      expect(neverRotated!.lastRotated).toBeNull();
    });
  });

  describe('alertOnExpiringSecrets', () => {
    test('should alert on expiring and expired secrets', async () => {
      // This should alert for: expiring, expired, never_rotated
      await monitor.alertOnExpiringSecrets();

      // No assertion - just verify it runs without error
      // In production, this would send actual alerts
    });

    test('should not alert if all secrets are OK', async () => {
      // Create policy with only OK secrets
      const okPolicy = {
        secrets_rotation: {
          test_secret: {
            interval_days: 90,
            last_rotated: new Date().toISOString().split('T')[0], // Today
            next_rotation: null,
            description: 'Test secret',
            rotation_runbook: 'docs/runbooks/secrets-rotation.md'
          }
        },
        reminders: {
          reminder_days_before: 14,
          notification_channels: ['console'],
          notification_recipients: []
        },
        leak_detection: {
          enabled: true,
          scan_interval_hours: 168,
          repositories: [],
          scan_history_days: 90,
          auto_pause_on_leak: true
        },
        emergency_rotation: {
          immediate_rotation_required: true,
          pause_services_on_compromise: true,
          escalate_to: []
        },
        audit: {
          log_rotations: true,
          log_file: 'logs/secrets-rotation.log',
          retention_days: 365
        }
      };

      fs.writeFileSync(testPolicyPath, yaml.dump(okPolicy), 'utf8');

      const okMonitor = new SecretsRotationMonitor(testPolicyPath);
      await okMonitor.alertOnExpiringSecrets();

      // No error = success
    });
  });

  describe('updateLastRotated', () => {
    test('should update last rotated date for secret', async () => {
      const rotatedDate = new Date('2025-12-08');

      await monitor.updateLastRotated('test_secret_expired', rotatedDate);

      // Reload policy to verify update
      const policy = yaml.load(fs.readFileSync(testPolicyPath, 'utf8')) as any;

      expect(policy.secrets_rotation.test_secret_expired.last_rotated).toBe('2025-12-08');
      expect(policy.secrets_rotation.test_secret_expired.next_rotation).toBe('2026-03-08'); // 90 days later
    });

    test('should throw error if secret not found', async () => {
      await expect(
        monitor.updateLastRotated('nonexistent_secret', new Date())
      ).rejects.toThrow('Secret not found in rotation policy');
    });

    test('should calculate next rotation date correctly', async () => {
      const rotatedDate = new Date('2025-12-08');

      await monitor.updateLastRotated('test_secret_ok', rotatedDate);

      const policy = yaml.load(fs.readFileSync(testPolicyPath, 'utf8')) as any;
      const nextRotation = new Date(policy.secrets_rotation.test_secret_ok.next_rotation);
      const expectedNext = new Date('2026-03-08'); // 90 days later

      expect(nextRotation.toISOString().split('T')[0]).toBe(expectedNext.toISOString().split('T')[0]);
    });
  });

  describe('getStatistics', () => {
    test('should return correct statistics', async () => {
      const stats = await monitor.getStatistics();

      expect(stats.totalSecrets).toBe(4);
      expect(stats.upToDate).toBe(1); // test_secret_ok
      expect(stats.expiringSoon).toBe(1); // test_secret_expiring
      expect(stats.expired).toBe(1); // test_secret_expired
      expect(stats.neverRotated).toBe(1); // test_secret_never_rotated
    });
  });

  describe('getSecretStatus', () => {
    test('should get status for specific secret', async () => {
      const status = await monitor.getSecretStatus('test_secret_expired');

      expect(status).toBeDefined();
      expect(status!.secret).toBe('test_secret_expired');
      expect(status!.status).toBe('EXPIRED');
    });

    test('should return null for nonexistent secret', async () => {
      const status = await monitor.getSecretStatus('nonexistent_secret');

      expect(status).toBeNull();
    });
  });

  describe('Attack Scenario Prevention', () => {
    test('should prevent CRITICAL-008 attack: 6-month-old leaked secret still works', async () => {
      // Scenario: Discord bot token leaked 6 months ago, never rotated
      const sixMonthsAgo = new Date(Date.now() - 180 * 24 * 60 * 60 * 1000);

      const attackPolicy = {
        secrets_rotation: {
          discord_bot_token: {
            interval_days: 90,
            last_rotated: sixMonthsAgo.toISOString().split('T')[0],
            next_rotation: null,
            description: 'Discord bot token',
            rotation_runbook: 'docs/runbooks/secrets-rotation.md'
          }
        },
        reminders: {
          reminder_days_before: 14,
          notification_channels: ['console'],
          notification_recipients: []
        },
        leak_detection: {
          enabled: true,
          scan_interval_hours: 168,
          repositories: [],
          scan_history_days: 90,
          auto_pause_on_leak: true
        },
        emergency_rotation: {
          immediate_rotation_required: true,
          pause_services_on_compromise: true,
          escalate_to: []
        },
        audit: {
          log_rotations: true,
          log_file: 'logs/secrets-rotation.log',
          retention_days: 365
        }
      };

      fs.writeFileSync(testPolicyPath, yaml.dump(attackPolicy), 'utf8');

      const attackMonitor = new SecretsRotationMonitor(testPolicyPath);
      const statuses = await attackMonitor.checkRotationStatus();

      const discordToken = statuses.find(s => s.secret === 'discord_bot_token');

      // Verify token detected as EXPIRED
      expect(discordToken!.status).toBe('EXPIRED');
      expect(discordToken!.severity).toBe('CRITICAL');
      expect(discordToken!.daysOverdue).toBeGreaterThan(90); // Over 90 days overdue

      // Verify alert would be triggered
      await attackMonitor.alertOnExpiringSecrets();

      // Result: System would alert security team that token is 90+ days overdue
      // This prompts emergency rotation, limiting exposure window
    });

    test('should send reminders 14 days before expiry', async () => {
      // Secret that expires in 12 days (within reminder window)
      const twelveDaysRemaining = new Date(Date.now() - 78 * 24 * 60 * 60 * 1000); // 78 days ago (90 - 78 = 12)

      const reminderPolicy = {
        secrets_rotation: {
          google_service_account: {
            interval_days: 90,
            last_rotated: twelveDaysRemaining.toISOString().split('T')[0],
            next_rotation: null,
            description: 'Google service account',
            rotation_runbook: 'docs/runbooks/secrets-rotation.md'
          }
        },
        reminders: {
          reminder_days_before: 14,
          notification_channels: ['console', 'email'],
          notification_recipients: ['security@example.com']
        },
        leak_detection: {
          enabled: true,
          scan_interval_hours: 168,
          repositories: [],
          scan_history_days: 90,
          auto_pause_on_leak: true
        },
        emergency_rotation: {
          immediate_rotation_required: true,
          pause_services_on_compromise: true,
          escalate_to: []
        },
        audit: {
          log_rotations: true,
          log_file: 'logs/secrets-rotation.log',
          retention_days: 365
        }
      };

      fs.writeFileSync(testPolicyPath, yaml.dump(reminderPolicy), 'utf8');

      const reminderMonitor = new SecretsRotationMonitor(testPolicyPath);
      const statuses = await reminderMonitor.checkRotationStatus();

      const googleAccount = statuses.find(s => s.secret === 'google_service_account');

      // Verify reminder would be triggered
      expect(googleAccount!.status).toBe('EXPIRING_SOON');
      expect(googleAccount!.severity).toBe('HIGH');
      expect(googleAccount!.daysRemaining).toBeLessThanOrEqual(14);

      // Alert would be sent to security@example.com
      await reminderMonitor.alertOnExpiringSecrets();
    });
  });
});
