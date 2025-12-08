/**
 * Permission Audit Scheduler
 *
 * Runs weekly audits of Google Drive permissions to detect:
 * - Unexpected folder access (security breach indicator)
 * - Missing expected folder access (misconfiguration)
 * - Permission creep over time
 *
 * This implements CRITICAL-004 remediation (periodic audits).
 */

import * as cron from 'node-cron';
import { logger } from '../utils/logger';
import { drivePermissionValidator } from '../services/drive-permission-validator';
import { google } from 'googleapis';
import path from 'path';
import fs from 'fs';

export interface AuditResult {
  timestamp: Date;
  status: 'PASSED' | 'FAILED';
  validation: any;
  alertSent: boolean;
}

export interface AuditHistory {
  audits: AuditResult[];
  lastAudit?: AuditResult;
  consecutiveFailures: number;
}

/**
 * Permission Audit Scheduler
 *
 * Security Controls:
 * 1. Weekly automated permission audits
 * 2. Immediate alerting on permission violations
 * 3. Tracks audit history for compliance reporting
 * 4. Escalates repeated failures
 * 5. Generates audit reports for security team
 */
export class PermissionAuditScheduler {
  private auditHistory: AuditHistory = {
    audits: [],
    consecutiveFailures: 0
  };
  private cronJob: cron.ScheduledTask | null = null;

  /**
   * Start scheduled permission audits
   *
   * Default: Every Monday at 9am
   */
  start(schedule: string = '0 9 * * MON'): void {
    if (this.cronJob) {
      logger.warn('Permission audit scheduler already running');
      return;
    }

    logger.info(`Starting permission audit scheduler: ${schedule}`);

    this.cronJob = cron.schedule(schedule, async () => {
      await this.runAudit();
    });

    logger.info('✅ Permission audit scheduler started');
  }

  /**
   * Stop scheduled audits
   */
  stop(): void {
    if (this.cronJob) {
      this.cronJob.stop();
      this.cronJob = null;
      logger.info('Permission audit scheduler stopped');
    }
  }

  /**
   * Run permission audit manually
   */
  async runAudit(): Promise<AuditResult> {
    logger.info('━'.repeat(80));
    logger.info('Running weekly Google Drive permission audit...');
    logger.info('━'.repeat(80));

    const timestamp = new Date();

    try {
      // Initialize Google Auth
      const auth = await this.getAuth();

      if (!auth) {
        logger.error('Failed to initialize Google Auth for audit');
        return this.recordFailedAudit(timestamp, 'Failed to initialize Google Auth');
      }

      // Initialize validator
      await drivePermissionValidator.initialize(auth);

      // Run validation
      const validation = await drivePermissionValidator.validatePermissions();

      if (!validation.valid) {
        logger.error('🚨 PERMISSION AUDIT FAILED');
        logger.error('Validation errors:', validation.errors);

        // Alert security team
        await this.alertSecurityTeam({
          subject: '🚨 SECURITY ALERT: Google Drive Permission Violation Detected',
          body: this.formatAlertBody(validation),
          severity: 'CRITICAL',
          validation
        });

        const result: AuditResult = {
          timestamp,
          status: 'FAILED',
          validation,
          alertSent: true
        };

        this.recordAuditResult(result);

        return result;

      } else {
        logger.info('✅ Permission audit PASSED');

        if (validation.warnings && validation.warnings.length > 0) {
          logger.warn('Audit warnings:', validation.warnings);
        }

        const result: AuditResult = {
          timestamp,
          status: 'PASSED',
          validation,
          alertSent: false
        };

        this.recordAuditResult(result);

        // Reset consecutive failures
        this.auditHistory.consecutiveFailures = 0;

        return result;
      }

    } catch (error) {
      logger.error('Permission audit failed with error', {
        error: error.message,
        stack: error.stack
      });

      return this.recordFailedAudit(timestamp, error.message);
    }
  }

  /**
   * Record failed audit
   */
  private recordFailedAudit(timestamp: Date, errorMessage: string): AuditResult {
    const result: AuditResult = {
      timestamp,
      status: 'FAILED',
      validation: {
        valid: false,
        errors: [errorMessage]
      },
      alertSent: false
    };

    this.recordAuditResult(result);

    return result;
  }

  /**
   * Record audit result in history
   */
  private recordAuditResult(result: AuditResult): void {
    this.auditHistory.audits.push(result);
    this.auditHistory.lastAudit = result;

    if (result.status === 'FAILED') {
      this.auditHistory.consecutiveFailures++;

      // Escalate if multiple consecutive failures
      if (this.auditHistory.consecutiveFailures >= 3) {
        logger.error(`🚨 ESCALATION: ${this.auditHistory.consecutiveFailures} consecutive audit failures`);
        this.escalateToExecutives();
      }
    } else {
      this.auditHistory.consecutiveFailures = 0;
    }

    // Keep only last 52 audits (1 year of weekly audits)
    if (this.auditHistory.audits.length > 52) {
      this.auditHistory.audits = this.auditHistory.audits.slice(-52);
    }

    // Save to disk for persistence
    this.saveAuditHistory();
  }

  /**
   * Format alert body for security team
   */
  private formatAlertBody(validation: any): string {
    let body = '🚨 WEEKLY PERMISSION AUDIT FAILED\n\n';
    body += `Timestamp: ${new Date().toISOString()}\n`;
    body += `Status: FAILED\n\n`;

    body += '━'.repeat(80) + '\n';
    body += 'VALIDATION ERRORS\n';
    body += '━'.repeat(80) + '\n\n';

    for (const error of validation.errors) {
      body += `  ✗ ${error}\n`;
    }

    if (validation.unexpectedFolders && validation.unexpectedFolders.length > 0) {
      body += '\n' + '━'.repeat(80) + '\n';
      body += 'UNEXPECTED FOLDER ACCESS DETECTED\n';
      body += '━'.repeat(80) + '\n\n';

      for (const folder of validation.unexpectedFolders) {
        body += `  ⚠️  ${folder.path}\n`;
        body += `     ID: ${folder.id}\n`;
        body += `     Link: ${folder.webViewLink}\n\n`;
      }

      body += 'IMMEDIATE ACTIONS REQUIRED:\n';
      body += '  1. Review each unexpected folder above\n';
      body += '  2. Determine why service account has access\n';
      body += '  3. Revoke access if unintended\n';
      body += '  4. Investigate potential security breach\n';
      body += '  5. Update monitored_folders whitelist if intended\n\n';
    }

    if (validation.warnings && validation.warnings.length > 0) {
      body += '━'.repeat(80) + '\n';
      body += 'WARNINGS\n';
      body += '━'.repeat(80) + '\n\n';

      for (const warning of validation.warnings) {
        body += `  ⚠️  ${warning}\n`;
      }
      body += '\n';
    }

    body += '━'.repeat(80) + '\n';
    body += 'NEXT STEPS\n';
    body += '━'.repeat(80) + '\n\n';
    body += '  1. Review validation errors above\n';
    body += '  2. Check Google Drive sharing settings\n';
    body += '  3. Revoke unexpected folder access\n';
    body += '  4. Re-run validation: npm run validate-drive-permissions\n';
    body += '  5. Document all changes in security incident log\n\n';

    body += `Audit History: ${this.auditHistory.consecutiveFailures} consecutive failures\n`;

    return body;
  }

  /**
   * Alert security team
   */
  private async alertSecurityTeam(alert: {
    subject: string;
    body: string;
    severity: string;
    validation: any;
  }): Promise<void> {
    logger.error('SECURITY ALERT', {
      subject: alert.subject,
      severity: alert.severity
    });

    // Console alert
    console.error('\n' + '='.repeat(80));
    console.error(`🚨 ${alert.subject}`);
    console.error('='.repeat(80));
    console.error(alert.body);
    console.error('='.repeat(80) + '\n');

    // Write to security events log
    logger.security({
      eventType: 'AUDIT_FAILED',
      severity: alert.severity,
      details: alert.body,
      validation: alert.validation,
      timestamp: new Date().toISOString()
    });

    // TODO: Integrate with alerting systems
    // - Discord webhook
    // - Slack webhook
    // - Email (SendGrid, AWS SES)
    // - PagerDuty
    // - OpsGenie
  }

  /**
   * Escalate to executives on repeated failures
   */
  private escalateToExecutives(): void {
    logger.error('🚨 EXECUTIVE ESCALATION: Multiple consecutive audit failures');

    const message = `
🚨 EXECUTIVE ESCALATION: Google Drive Permission Audit

${this.auditHistory.consecutiveFailures} CONSECUTIVE AUDIT FAILURES

This indicates a serious security issue that requires immediate executive attention.

RISK: Service account may have unauthorized access to sensitive folders, potentially
exposing confidential data (board presentations, HR files, financial data, etc.).

IMMEDIATE ACTION REQUIRED:
  1. Review audit logs: logs/security-events.log
  2. Check Google Drive sharing permissions
  3. Contact security team immediately
  4. Consider temporarily disabling DevRel integration until resolved

Last ${this.auditHistory.consecutiveFailures} Audit Results:
${this.auditHistory.audits.slice(-this.auditHistory.consecutiveFailures).map((a, i) =>
  `  ${i + 1}. ${a.timestamp.toISOString()} - ${a.status}`
).join('\n')}

Contact: security@example.com
    `;

    console.error(message);
    logger.security({
      eventType: 'EXECUTIVE_ESCALATION',
      severity: 'CRITICAL',
      consecutiveFailures: this.auditHistory.consecutiveFailures,
      details: message,
      timestamp: new Date().toISOString()
    });

    // TODO: Send to executive team
    // - Email to CTO, CEO, Head of Security
    // - Page on-call security engineer
    // - Create high-priority incident ticket
  }

  /**
   * Get Google Auth
   */
  private async getAuth(): Promise<any> {
    try {
      const credentialsPath = path.join(__dirname, '../../config/google-service-account.json');

      if (!fs.existsSync(credentialsPath)) {
        logger.error('Service account credentials not found', { path: credentialsPath });
        return null;
      }

      const auth = new google.auth.GoogleAuth({
        keyFile: credentialsPath,
        scopes: [
          'https://www.googleapis.com/auth/drive.readonly',
          'https://www.googleapis.com/auth/documents.readonly'
        ]
      });

      return await auth.getClient();

    } catch (error) {
      logger.error('Failed to initialize Google Auth', { error: error.message });
      return null;
    }
  }

  /**
   * Save audit history to disk
   */
  private saveAuditHistory(): void {
    try {
      const historyPath = path.join(__dirname, '../../data/audit-history.json');
      const dir = path.dirname(historyPath);

      if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir, { recursive: true });
      }

      fs.writeFileSync(historyPath, JSON.stringify(this.auditHistory, null, 2));

    } catch (error) {
      logger.error('Failed to save audit history', { error: error.message });
    }
  }

  /**
   * Load audit history from disk
   */
  private loadAuditHistory(): void {
    try {
      const historyPath = path.join(__dirname, '../../data/audit-history.json');

      if (fs.existsSync(historyPath)) {
        const data = fs.readFileSync(historyPath, 'utf8');
        this.auditHistory = JSON.parse(data);
        logger.info(`Loaded ${this.auditHistory.audits.length} historical audits`);
      }

    } catch (error) {
      logger.error('Failed to load audit history', { error: error.message });
    }
  }

  /**
   * Get audit statistics
   */
  getStatistics(): {
    totalAudits: number;
    passedAudits: number;
    failedAudits: number;
    consecutiveFailures: number;
    lastAudit?: AuditResult;
  } {
    return {
      totalAudits: this.auditHistory.audits.length,
      passedAudits: this.auditHistory.audits.filter(a => a.status === 'PASSED').length,
      failedAudits: this.auditHistory.audits.filter(a => a.status === 'FAILED').length,
      consecutiveFailures: this.auditHistory.consecutiveFailures,
      lastAudit: this.auditHistory.lastAudit
    };
  }

  /**
   * Generate compliance report
   */
  generateComplianceReport(): string {
    const stats = this.getStatistics();
    const passRate = stats.totalAudits > 0
      ? ((stats.passedAudits / stats.totalAudits) * 100).toFixed(1)
      : '0.0';

    let report = '━'.repeat(80) + '\n';
    report += 'GOOGLE DRIVE PERMISSION AUDIT - COMPLIANCE REPORT\n';
    report += '━'.repeat(80) + '\n\n';

    report += 'AUDIT STATISTICS\n';
    report += `  Total Audits: ${stats.totalAudits}\n`;
    report += `  Passed: ${stats.passedAudits}\n`;
    report += `  Failed: ${stats.failedAudits}\n`;
    report += `  Pass Rate: ${passRate}%\n`;
    report += `  Consecutive Failures: ${stats.consecutiveFailures}\n\n`;

    if (stats.lastAudit) {
      report += 'LAST AUDIT\n';
      report += `  Date: ${stats.lastAudit.timestamp.toISOString()}\n`;
      report += `  Status: ${stats.lastAudit.status}\n`;
      report += `  Alert Sent: ${stats.lastAudit.alertSent ? 'Yes' : 'No'}\n\n`;
    }

    report += 'RECENT AUDIT HISTORY\n';
    const recentAudits = this.auditHistory.audits.slice(-10).reverse();
    for (const audit of recentAudits) {
      const icon = audit.status === 'PASSED' ? '✅' : '❌';
      report += `  ${icon} ${audit.timestamp.toISOString()} - ${audit.status}\n`;
    }

    report += '\n' + '━'.repeat(80) + '\n';

    return report;
  }
}

// Singleton instance
export const permissionAuditScheduler = new PermissionAuditScheduler();
export default permissionAuditScheduler;

/**
 * Start permission audits (called from main app)
 */
export function schedulePermissionAudit(schedule?: string): void {
  permissionAuditScheduler.start(schedule);
}
