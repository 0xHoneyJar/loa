/**
 * Pre-Distribution Validator
 *
 * Final validation layer before posting summaries to Discord or blog.
 * Blocks distribution if secrets or sensitive patterns detected.
 *
 * This implements CRITICAL-005 remediation (pre-distribution validation).
 */

import { logger } from '../utils/logger';
import { secretScanner, ScanResult } from './secret-scanner';
import { SecurityException } from '../utils/errors';

export interface ValidationResult {
  valid: boolean;
  errors: string[];
  warnings: string[];
  scanResult?: ScanResult;
  blockedReasons?: string[];
}

export interface Translation {
  content: string;
  metadata?: {
    documentId?: string;
    documentName?: string;
    author?: string;
    channel?: string;
  };
}

/**
 * Pre-Distribution Validator
 *
 * Security Controls:
 * 1. Scans for secrets before distribution
 * 2. Blocks distribution if secrets found
 * 3. Scans for sensitive keywords (password, credential, etc.)
 * 4. Flags for manual review if suspicious patterns detected
 * 5. Generates audit trail for all distribution attempts
 */
export class PreDistributionValidator {
  private sensitivePatterns: Array<{
    pattern: RegExp;
    keyword: string;
    severity: 'BLOCK' | 'WARN';
    description: string;
  }> = [
    // BLOCK patterns - prevent distribution
    {
      pattern: /password\s*[:=]/gi,
      keyword: 'password',
      severity: 'BLOCK',
      description: 'Password assignment detected'
    },
    {
      pattern: /private\s+key/gi,
      keyword: 'private key',
      severity: 'BLOCK',
      description: 'Private key reference'
    },
    {
      pattern: /secret\s*[:=]/gi,
      keyword: 'secret',
      severity: 'BLOCK',
      description: 'Secret assignment detected'
    },
    {
      pattern: /api[_-]?key\s*[:=]/gi,
      keyword: 'api_key',
      severity: 'BLOCK',
      description: 'API key assignment detected'
    },
    {
      pattern: /token\s*[:=]/gi,
      keyword: 'token',
      severity: 'BLOCK',
      description: 'Token assignment detected'
    },
    {
      pattern: /credential/gi,
      keyword: 'credential',
      severity: 'BLOCK',
      description: 'Credential reference'
    },

    // WARN patterns - flag for review but don't block
    {
      pattern: /confidential/gi,
      keyword: 'confidential',
      severity: 'WARN',
      description: 'Confidential information reference'
    },
    {
      pattern: /internal\s+only/gi,
      keyword: 'internal only',
      severity: 'WARN',
      description: 'Internal only designation'
    },
    {
      pattern: /do\s+not\s+share/gi,
      keyword: 'do not share',
      severity: 'WARN',
      description: 'Explicit no-share instruction'
    },
    {
      pattern: /proprietary/gi,
      keyword: 'proprietary',
      severity: 'WARN',
      description: 'Proprietary information reference'
    }
  ];

  /**
   * Validate content before distribution
   *
   * This is the final security gate before posting to Discord or blog.
   */
  async validateBeforeDistribution(
    translation: Translation,
    options: {
      strictMode?: boolean;
      allowWarnings?: boolean;
    } = {}
  ): Promise<ValidationResult> {
    const { strictMode = true, allowWarnings = false } = options;

    logger.info('Running pre-distribution validation...', {
      contentLength: translation.content.length,
      documentId: translation.metadata?.documentId,
      strictMode,
      allowWarnings
    });

    const errors: string[] = [];
    const warnings: string[] = [];
    const blockedReasons: string[] = [];

    try {
      // STEP 1: Scan for secrets (highest priority)
      const scanResult = secretScanner.scanForSecrets(translation.content, {
        skipFalsePositives: true,
        contextLength: 100
      });

      if (scanResult.hasSecrets) {
        const secretTypes = scanResult.secrets.map(s => s.type).join(', ');

        logger.error('🚨 SECRETS DETECTED IN DISTRIBUTION CONTENT', {
          documentId: translation.metadata?.documentId,
          documentName: translation.metadata?.documentName,
          secretCount: scanResult.totalSecretsFound,
          criticalSecrets: scanResult.criticalSecretsFound,
          secretTypes
        });

        errors.push(`Secrets detected in content: ${secretTypes}`);
        blockedReasons.push(`Found ${scanResult.totalSecretsFound} secrets (${scanResult.criticalSecretsFound} critical)`);

        // Alert security team immediately
        await this.alertSecurityTeam({
          subject: '🚨 CRITICAL: Secrets Detected in Distribution Content',
          body: this.formatSecretAlertBody(translation, scanResult),
          severity: 'CRITICAL',
          scanResult,
          metadata: translation.metadata
        });

        // BLOCK DISTRIBUTION
        throw new SecurityException(
          `Cannot distribute content containing secrets. Found: ${secretTypes}`
        );
      }

      logger.info('✅ No secrets detected');

      // STEP 2: Scan for sensitive patterns
      for (const { pattern, keyword, severity, description } of this.sensitivePatterns) {
        pattern.lastIndex = 0; // Reset regex state

        if (pattern.test(translation.content)) {
          const message = `Sensitive keyword detected: "${keyword}" - ${description}`;

          if (severity === 'BLOCK') {
            errors.push(message);
            blockedReasons.push(message);

            logger.error('🚨 BLOCKING PATTERN DETECTED', {
              keyword,
              description,
              documentId: translation.metadata?.documentId
            });
          } else {
            warnings.push(message);

            logger.warn('⚠️  Suspicious pattern detected', {
              keyword,
              description,
              documentId: translation.metadata?.documentId
            });
          }
        }
      }

      // STEP 3: Determine if distribution is allowed
      if (errors.length > 0) {
        logger.error('❌ Pre-distribution validation FAILED', {
          errorCount: errors.length,
          blockedReasons
        });

        // Flag for manual review
        await this.flagForManualReview(translation, errors.join('; '), scanResult);

        throw new SecurityException(
          `Pre-distribution validation failed: ${blockedReasons.join('; ')}`
        );
      }

      if (warnings.length > 0) {
        logger.warn('⚠️  Pre-distribution validation passed with warnings', {
          warningCount: warnings.length,
          warnings
        });

        if (strictMode && !allowWarnings) {
          logger.warn('Strict mode: flagging for manual review due to warnings');

          // Flag for manual review in strict mode
          await this.flagForManualReview(translation, warnings.join('; '), scanResult);

          return {
            valid: false,
            errors: ['Strict mode: Manual review required due to warnings'],
            warnings,
            scanResult,
            blockedReasons: ['Manual review required']
          };
        }
      }

      logger.info('✅ Pre-distribution validation PASSED');

      return {
        valid: true,
        errors: [],
        warnings,
        scanResult
      };

    } catch (error) {
      if (error instanceof SecurityException) {
        // Re-throw security exceptions
        throw error;
      }

      logger.error('Pre-distribution validation failed with error', {
        error: error.message,
        stack: error.stack
      });

      throw new Error(`Pre-distribution validation error: ${error.message}`);
    }
  }

  /**
   * Format alert body for security team
   */
  private formatSecretAlertBody(translation: Translation, scanResult: ScanResult): string {
    let body = '🚨 CRITICAL SECURITY ALERT\n\n';
    body += 'Secrets detected in content scheduled for distribution.\n';
    body += 'Distribution has been BLOCKED automatically.\n\n';

    body += '━'.repeat(80) + '\n';
    body += 'DOCUMENT INFORMATION\n';
    body += '━'.repeat(80) + '\n\n';

    if (translation.metadata) {
      body += `  Document ID: ${translation.metadata.documentId || 'N/A'}\n`;
      body += `  Document Name: ${translation.metadata.documentName || 'N/A'}\n`;
      body += `  Author: ${translation.metadata.author || 'N/A'}\n`;
      body += `  Target Channel: ${translation.metadata.channel || 'N/A'}\n`;
    }

    body += `  Content Length: ${translation.content.length} characters\n\n`;

    body += '━'.repeat(80) + '\n';
    body += 'SECRETS DETECTED\n';
    body += '━'.repeat(80) + '\n\n';

    body += `  Total Secrets: ${scanResult.totalSecretsFound}\n`;
    body += `  Critical Secrets: ${scanResult.criticalSecretsFound}\n\n`;

    body += 'Secret Details:\n';
    for (const secret of scanResult.secrets) {
      body += `  • ${secret.type} (${secret.severity})\n`;
      body += `    Location: Character ${secret.location}\n`;
      body += `    Context: ${secret.context.substring(0, 100)}...\n\n`;
    }

    body += '━'.repeat(80) + '\n';
    body += 'IMMEDIATE ACTIONS REQUIRED\n';
    body += '━'.repeat(80) + '\n\n';

    body += '  1. Review the source document immediately\n';
    body += '  2. Identify why secrets were included in the document\n';
    body += '  3. Rotate any exposed credentials as a precaution\n';
    body += '  4. Educate document author on secret management\n';
    body += '  5. Review other recent documents from same author\n\n';

    body += 'Distribution Status: ❌ BLOCKED\n';
    body += `Timestamp: ${new Date().toISOString()}\n`;

    return body;
  }

  /**
   * Alert security team
   */
  private async alertSecurityTeam(alert: {
    subject: string;
    body: string;
    severity: string;
    scanResult: ScanResult;
    metadata?: any;
  }): Promise<void> {
    logger.error('SECURITY ALERT', {
      subject: alert.subject,
      severity: alert.severity,
      metadata: alert.metadata
    });

    // Console alert
    console.error('\n' + '='.repeat(80));
    console.error(`🚨 ${alert.subject}`);
    console.error('='.repeat(80));
    console.error(alert.body);
    console.error('='.repeat(80) + '\n');

    // Write to security events log
    logger.security({
      eventType: 'SECRET_DETECTION_BLOCKED',
      severity: alert.severity,
      details: alert.body,
      scanResult: {
        totalSecrets: alert.scanResult.totalSecretsFound,
        criticalSecrets: alert.scanResult.criticalSecretsFound,
        secretTypes: alert.scanResult.secrets.map(s => s.type)
      },
      metadata: alert.metadata,
      timestamp: new Date().toISOString()
    });

    // TODO: Integrate with alerting systems
    // - Discord webhook to #security-alerts
    // - Slack webhook
    // - Email (SendGrid, AWS SES)
    // - PagerDuty for on-call engineer
  }

  /**
   * Flag content for manual security review
   */
  private async flagForManualReview(
    translation: Translation,
    reason: string,
    scanResult?: ScanResult
  ): Promise<void> {
    logger.warn('Flagging content for manual security review', {
      reason,
      documentId: translation.metadata?.documentId,
      documentName: translation.metadata?.documentName,
      hasSecrets: scanResult?.hasSecrets || false
    });

    // TODO: Implement review queue
    // - Add to review queue database
    // - Notify security team via email/Discord
    // - Create Linear ticket for review
    // - Block distribution until manually approved
  }

  /**
   * Get validation statistics
   */
  getStatistics(): {
    totalSensitivePatterns: number;
    blockingPatterns: number;
    warningPatterns: number;
  } {
    return {
      totalSensitivePatterns: this.sensitivePatterns.length,
      blockingPatterns: this.sensitivePatterns.filter(p => p.severity === 'BLOCK').length,
      warningPatterns: this.sensitivePatterns.filter(p => p.severity === 'WARN').length
    };
  }
}

// Singleton instance
export const preDistributionValidator = new PreDistributionValidator();
export default preDistributionValidator;
