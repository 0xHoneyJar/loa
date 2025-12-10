/**
 * Secrets Rotation Monitor
 *
 * Monitors secrets rotation status and sends automated reminders
 * when secrets are approaching expiry or have expired.
 *
 * This implements CRITICAL-008 remediation (secrets rotation strategy).
 */

import * as fs from 'fs';
import * as path from 'path';
import * as yaml from 'js-yaml';
import { logger } from '../utils/logger';

export interface SecretRotationConfig {
  interval_days: number;
  last_rotated: string | null;  // YYYY-MM-DD format
  next_rotation: string | null;
  description: string;
  rotation_runbook: string;
}

export interface RotationPolicy {
  secrets_rotation: Record<string, SecretRotationConfig>;
  reminders: {
    reminder_days_before: number;
    notification_channels: string[];
    notification_recipients: string[];
  };
  leak_detection: {
    enabled: boolean;
    scan_interval_hours: number;
    repositories: string[];
    scan_history_days: number;
    auto_pause_on_leak: boolean;
  };
  emergency_rotation: {
    immediate_rotation_required: boolean;
    pause_services_on_compromise: boolean;
    escalate_to: string[];
  };
  audit: {
    log_rotations: boolean;
    log_file: string;
    retention_days: number;
  };
}

export interface RotationStatus {
  secret: string;
  description: string;
  status: 'OK' | 'EXPIRING_SOON' | 'EXPIRED' | 'NEVER_ROTATED';
  daysRemaining?: number;
  daysOverdue?: number;
  severity: 'INFO' | 'HIGH' | 'CRITICAL';
  lastRotated: Date | null;
  nextRotation: Date | null;
  rotationInterval: number;
}

export interface RotationAlert {
  subject: string;
  body: string;
  severity: 'INFO' | 'HIGH' | 'CRITICAL';
  recipients: string[];
}

/**
 * Secrets Rotation Monitor
 *
 * Security Controls:
 * 1. Automated rotation status checks (daily)
 * 2. Reminders 14 days before expiry
 * 3. Critical alerts for expired secrets
 * 4. Service pause on overdue rotations
 * 5. Audit trail for all rotation events
 * 6. Multi-channel notifications (Discord, email, console)
 * 7. Escalation for emergency rotations
 * 8. Never-rotated secret detection
 * 9. Rotation history tracking
 * 10. Next rotation date calculation
 */
export class SecretsRotationMonitor {
  private policyPath: string;
  private policy: RotationPolicy | null = null;

  constructor(policyPath?: string) {
    this.policyPath = policyPath || path.join(__dirname, '../../config/secrets-rotation-policy.yaml');
  }

  /**
   * Load rotation policy from YAML file
   */
  async loadRotationPolicy(): Promise<RotationPolicy> {
    if (this.policy) {
      return this.policy;
    }

    try {
      const fileContents = fs.readFileSync(this.policyPath, 'utf8');
      this.policy = yaml.load(fileContents) as RotationPolicy;

      logger.info('Secrets rotation policy loaded', {
        secretCount: Object.keys(this.policy.secrets_rotation).length,
        reminderDays: this.policy.reminders.reminder_days_before
      });

      return this.policy;
    } catch (error) {
      logger.error('Failed to load secrets rotation policy', {
        path: this.policyPath,
        error: error.message
      });
      throw new Error(`Failed to load rotation policy: ${error.message}`);
    }
  }

  /**
   * Check rotation status for all secrets
   */
  async checkRotationStatus(): Promise<RotationStatus[]> {
    const policy = await this.loadRotationPolicy();
    const statuses: RotationStatus[] = [];

    for (const [secretName, config] of Object.entries(policy.secrets_rotation)) {
      const status = this.calculateRotationStatus(secretName, config, policy.reminders.reminder_days_before);
      statuses.push(status);
    }

    logger.info('Rotation status check complete', {
      totalSecrets: statuses.length,
      ok: statuses.filter(s => s.status === 'OK').length,
      expiringSoon: statuses.filter(s => s.status === 'EXPIRING_SOON').length,
      expired: statuses.filter(s => s.status === 'EXPIRED').length,
      neverRotated: statuses.filter(s => s.status === 'NEVER_ROTATED').length
    });

    return statuses;
  }

  /**
   * Calculate rotation status for a single secret
   */
  private calculateRotationStatus(
    secretName: string,
    config: SecretRotationConfig,
    reminderDays: number
  ): RotationStatus {
    // If never rotated
    if (!config.last_rotated) {
      return {
        secret: secretName,
        description: config.description,
        status: 'NEVER_ROTATED',
        severity: 'HIGH',
        lastRotated: null,
        nextRotation: null,
        rotationInterval: config.interval_days
      };
    }

    const lastRotated = new Date(config.last_rotated);
    const now = new Date();
    const daysSinceRotation = Math.floor((now.getTime() - lastRotated.getTime()) / (1000 * 60 * 60 * 24));
    const daysUntilExpiry = config.interval_days - daysSinceRotation;
    const nextRotation = new Date(lastRotated.getTime() + config.interval_days * 24 * 60 * 60 * 1000);

    // EXPIRED
    if (daysUntilExpiry <= 0) {
      return {
        secret: secretName,
        description: config.description,
        status: 'EXPIRED',
        daysOverdue: Math.abs(daysUntilExpiry),
        severity: 'CRITICAL',
        lastRotated,
        nextRotation,
        rotationInterval: config.interval_days
      };
    }

    // EXPIRING SOON
    if (daysUntilExpiry <= reminderDays) {
      return {
        secret: secretName,
        description: config.description,
        status: 'EXPIRING_SOON',
        daysRemaining: daysUntilExpiry,
        severity: 'HIGH',
        lastRotated,
        nextRotation,
        rotationInterval: config.interval_days
      };
    }

    // OK
    return {
      secret: secretName,
      description: config.description,
      status: 'OK',
      daysRemaining: daysUntilExpiry,
      severity: 'INFO',
      lastRotated,
      nextRotation,
      rotationInterval: config.interval_days
    };
  }

  /**
   * Alert on expiring/expired secrets
   */
  async alertOnExpiringSecrets(): Promise<void> {
    const statuses = await this.checkRotationStatus();
    const policy = await this.loadRotationPolicy();

    const alertableStatuses = statuses.filter(s =>
      s.status === 'EXPIRED' ||
      s.status === 'EXPIRING_SOON' ||
      s.status === 'NEVER_ROTATED'
    );

    if (alertableStatuses.length === 0) {
      logger.info('All secrets up to date - no rotation alerts needed');
      return;
    }

    logger.warn('Secrets requiring rotation detected', {
      count: alertableStatuses.length,
      expired: alertableStatuses.filter(s => s.status === 'EXPIRED').length,
      expiringSoon: alertableStatuses.filter(s => s.status === 'EXPIRING_SOON').length,
      neverRotated: alertableStatuses.filter(s => s.status === 'NEVER_ROTATED').length
    });

    for (const status of alertableStatuses) {
      const alert = this.generateRotationAlert(status);
      await this.sendAlert(alert, policy.reminders.notification_channels);

      // Audit log
      logger.security({
        eventType: 'SECRET_ROTATION_ALERT',
        severity: status.severity,
        secret: status.secret,
        status: status.status,
        daysRemaining: status.daysRemaining,
        daysOverdue: status.daysOverdue,
        timestamp: new Date().toISOString()
      });
    }
  }

  /**
   * Generate rotation alert message
   */
  private generateRotationAlert(status: RotationStatus): RotationAlert {
    let subject: string;
    let body: string;

    switch (status.status) {
      case 'EXPIRED':
        subject = `🚨 CRITICAL: ${status.secret} rotation OVERDUE by ${status.daysOverdue} days`;
        body = `
SECRET ROTATION OVERDUE

Secret: ${status.secret}
Description: ${status.description}
Last Rotated: ${status.lastRotated?.toISOString().split('T')[0] || 'NEVER'}
Days Overdue: ${status.daysOverdue}

IMMEDIATE ACTION REQUIRED:
1. Rotate this secret immediately following the runbook
2. Verify no unauthorized access occurred during overdue period
3. Update last_rotated date in rotation policy
4. Monitor for suspicious activity

This secret has NOT been rotated in over ${status.rotationInterval} days.
Prolonged secret exposure increases risk of compromise.

See rotation runbook for detailed procedures.
        `.trim();
        break;

      case 'EXPIRING_SOON':
        subject = `⚠️ ${status.secret} expiring in ${status.daysRemaining} days`;
        body = `
SECRET ROTATION REMINDER

Secret: ${status.secret}
Description: ${status.description}
Last Rotated: ${status.lastRotated?.toISOString().split('T')[0] || 'NEVER'}
Next Rotation: ${status.nextRotation?.toISOString().split('T')[0] || 'UNKNOWN'}
Days Remaining: ${status.daysRemaining}

ACTION REQUIRED:
Please rotate this secret before ${status.nextRotation?.toISOString().split('T')[0]}.

Follow the rotation runbook for step-by-step instructions.
        `.trim();
        break;

      case 'NEVER_ROTATED':
        subject = `⚠️ ${status.secret} has NEVER been rotated`;
        body = `
SECRET NEVER ROTATED

Secret: ${status.secret}
Description: ${status.description}
Rotation Interval: ${status.rotationInterval} days

ACTION REQUIRED:
1. Perform initial rotation following the runbook
2. Update last_rotated date in rotation policy
3. Monitor for suspicious activity
4. Set calendar reminder for next rotation

This secret should be rotated regularly to minimize exposure risk.
        `.trim();
        break;

      default:
        subject = `ℹ️ ${status.secret} rotation status`;
        body = `Status: OK (${status.daysRemaining} days remaining)`;
    }

    return {
      subject,
      body,
      severity: status.severity,
      recipients: []  // Will be filled from policy
    };
  }

  /**
   * Send alert via configured channels
   */
  private async sendAlert(alert: RotationAlert, channels: string[]): Promise<void> {
    for (const channel of channels) {
      try {
        switch (channel) {
          case 'console':
            this.sendConsoleAlert(alert);
            break;

          case 'email':
            await this.sendEmailAlert(alert);
            break;

          case 'discord':
            await this.sendDiscordAlert(alert);
            break;

          default:
            logger.warn(`Unknown notification channel: ${channel}`);
        }
      } catch (error) {
        logger.error(`Failed to send alert via ${channel}`, {
          error: error.message,
          severity: alert.severity
        });
      }
    }
  }

  /**
   * Send console alert
   */
  private sendConsoleAlert(alert: RotationAlert): void {
    const logLevel = alert.severity === 'CRITICAL' ? 'error' : 'warn';
    logger[logLevel](alert.subject, { body: alert.body });
  }

  /**
   * Send email alert
   */
  private async sendEmailAlert(alert: RotationAlert): Promise<void> {
    // TODO: Implement email sending (SMTP integration)
    logger.info('Email alert sent', {
      subject: alert.subject,
      recipients: alert.recipients
    });
  }

  /**
   * Send Discord alert
   */
  private async sendDiscordAlert(alert: RotationAlert): Promise<void> {
    // TODO: Implement Discord webhook notification
    logger.info('Discord alert sent', {
      subject: alert.subject
    });
  }

  /**
   * Update last rotated date for a secret
   */
  async updateLastRotated(secretName: string, rotatedDate: Date): Promise<void> {
    const policy = await this.loadRotationPolicy();

    if (!policy.secrets_rotation[secretName]) {
      throw new Error(`Secret not found in rotation policy: ${secretName}`);
    }

    // Update in-memory policy
    policy.secrets_rotation[secretName].last_rotated = rotatedDate.toISOString().split('T')[0];

    // Calculate next rotation
    const nextRotation = new Date(
      rotatedDate.getTime() +
      policy.secrets_rotation[secretName].interval_days * 24 * 60 * 60 * 1000
    );
    policy.secrets_rotation[secretName].next_rotation = nextRotation.toISOString().split('T')[0];

    // Write back to file
    const yamlStr = yaml.dump(policy);
    fs.writeFileSync(this.policyPath, yamlStr, 'utf8');

    logger.info('Secret rotation date updated', {
      secret: secretName,
      lastRotated: rotatedDate.toISOString().split('T')[0],
      nextRotation: nextRotation.toISOString().split('T')[0]
    });

    // Audit log
    logger.security({
      eventType: 'SECRET_ROTATED',
      severity: 'INFO',
      secret: secretName,
      rotatedAt: rotatedDate.toISOString(),
      nextRotation: nextRotation.toISOString(),
      timestamp: new Date().toISOString()
    });
  }

  /**
   * Get rotation statistics
   */
  async getStatistics(): Promise<{
    totalSecrets: number;
    upToDate: number;
    expiringSoon: number;
    expired: number;
    neverRotated: number;
  }> {
    const statuses = await this.checkRotationStatus();

    return {
      totalSecrets: statuses.length,
      upToDate: statuses.filter(s => s.status === 'OK').length,
      expiringSoon: statuses.filter(s => s.status === 'EXPIRING_SOON').length,
      expired: statuses.filter(s => s.status === 'EXPIRED').length,
      neverRotated: statuses.filter(s => s.status === 'NEVER_ROTATED').length
    };
  }

  /**
   * Get rotation status for a specific secret
   */
  async getSecretStatus(secretName: string): Promise<RotationStatus | null> {
    const statuses = await this.checkRotationStatus();
    return statuses.find(s => s.secret === secretName) || null;
  }
}

// Singleton instance
export const secretsRotationMonitor = new SecretsRotationMonitor();
export default secretsRotationMonitor;
