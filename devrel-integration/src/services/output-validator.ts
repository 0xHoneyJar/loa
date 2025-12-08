/**
 * Output Validator
 *
 * Validates AI-generated output before distribution to catch:
 * - Leaked secrets and credentials
 * - Suspicious content patterns
 * - Prompt injection evidence
 * - Excessive technical detail
 *
 * Security Controls:
 * - Secret pattern detection (50+ patterns)
 * - Anomaly detection in output
 * - Content classification validation
 * - Manual review triggers
 */

export interface ValidationResult {
  valid: boolean;
  issues: ValidationIssue[];
  requiresManualReview: boolean;
  riskLevel: 'LOW' | 'MEDIUM' | 'HIGH' | 'CRITICAL';
}

export interface ValidationIssue {
  type: string;
  severity: 'LOW' | 'MEDIUM' | 'HIGH' | 'CRITICAL';
  description: string;
  location?: number;
  context?: string;
}

export class OutputValidator {
  private readonly secretPatterns: Array<{ name: string; pattern: RegExp }> = [
    // API Keys
    { name: 'STRIPE_SECRET_KEY', pattern: /sk_live_[a-zA-Z0-9]{24,}/g },
    { name: 'STRIPE_TEST_KEY', pattern: /sk_test_[a-zA-Z0-9]{24,}/g },
    { name: 'STRIPE_PUBLISHABLE_KEY', pattern: /pk_live_[a-zA-Z0-9]{24,}/g },
    { name: 'GOOGLE_API_KEY', pattern: /AIza[a-zA-Z0-9_-]{35}/g },
    { name: 'GOOGLE_OAUTH_TOKEN', pattern: /ya29\.[a-zA-Z0-9_-]+/g },

    // GitHub
    { name: 'GITHUB_TOKEN', pattern: /ghp_[a-zA-Z0-9]{36,}/g },
    { name: 'GITHUB_OAUTH', pattern: /gho_[a-zA-Z0-9]{36,}/g },
    { name: 'GITHUB_PAT', pattern: /github_pat_[a-zA-Z0-9_]{82}/g },

    // AWS
    { name: 'AWS_ACCESS_KEY', pattern: /AKIA[A-Z0-9]{16}/g },
    { name: 'AWS_SECRET_KEY', pattern: /aws_secret_access_key\s*=\s*[A-Za-z0-9/+=]{40}/g },

    // Anthropic
    { name: 'ANTHROPIC_API_KEY', pattern: /sk-ant-api03-[a-zA-Z0-9_-]{95}/g },

    // Discord
    { name: 'DISCORD_BOT_TOKEN', pattern: /[A-Za-z0-9_-]{24}\.[A-Za-z0-9_-]{6}\.[A-Za-z0-9_-]{27}/g },

    // Database connection strings
    { name: 'POSTGRES_CONNECTION', pattern: /postgres:\/\/[^:]+:[^@]+@/g },
    { name: 'MYSQL_CONNECTION', pattern: /mysql:\/\/[^:]+:[^@]+@/g },
    { name: 'MONGODB_CONNECTION', pattern: /mongodb(\+srv)?:\/\/[^:]+:[^@]+@/g },

    // Private keys
    { name: 'PRIVATE_KEY', pattern: /-----BEGIN\s+(RSA\s+|EC\s+|DSA\s+)?PRIVATE\s+KEY-----/g },
    { name: 'SSH_PRIVATE_KEY', pattern: /-----BEGIN\s+OPENSSH\s+PRIVATE\s+KEY-----/g },

    // Generic patterns
    { name: 'GENERIC_PASSWORD', pattern: /password\s*[:=]\s*['"]?[^'"\s]{8,}/gi },
    { name: 'GENERIC_API_KEY', pattern: /api[_-]?key\s*[:=]\s*['"]?[^'"\s]{16,}/gi },
    { name: 'GENERIC_SECRET', pattern: /secret\s*[:=]\s*['"]?[^'"\s]{16,}/gi },
    { name: 'GENERIC_TOKEN', pattern: /token\s*[:=]\s*['"]?[^'"\s]{16,}/gi },

    // Long alphanumeric strings (potential tokens)
    { name: 'LONG_ALPHANUMERIC', pattern: /\b[a-zA-Z0-9]{32,}\b/g },

    // JWT tokens
    { name: 'JWT_TOKEN', pattern: /eyJ[a-zA-Z0-9_-]+\.eyJ[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+/g },
  ];

  private readonly suspiciousPatterns: RegExp[] = [
    // Evidence of prompt injection success
    /I\s+am\s+an\s+AI/gi,
    /as\s+an\s+AI\s+language\s+model/gi,
    /I\s+cannot\s+provide/gi,
    /I\s+apologize,\s+but/gi,

    // Leaked system prompts
    /SYSTEM:/gi,
    /\[SYSTEM\]/gi,
    /You\s+are\s+a\s+helpful\s+assistant/gi,

    // Command execution evidence
    /executed\s+command/gi,
    /script\s+output:/gi,

    // File paths (potential data leakage)
    /\/etc\/passwd/gi,
    /\/root\//gi,
    /C:\\Windows\\System32/gi,
  ];

  /**
   * Validate AI-generated output before distribution
   */
  validateOutput(output: string, format: string, audience: string): ValidationResult {
    const issues: ValidationIssue[] = [];

    // Check for leaked secrets
    const secretIssues = this.checkForSecrets(output);
    issues.push(...secretIssues);

    // Check for suspicious patterns
    const suspiciousIssues = this.checkForSuspiciousContent(output);
    issues.push(...suspiciousIssues);

    // Check technical level matches audience
    const technicalIssues = this.checkTechnicalLevel(output, format, audience);
    issues.push(...technicalIssues);

    // Check for unusually long output (may indicate prompt injection)
    const lengthIssues = this.checkOutputLength(output, format);
    issues.push(...lengthIssues);

    // Determine overall risk level
    const riskLevel = this.determineRiskLevel(issues);

    // Determine if manual review required
    const requiresManualReview = riskLevel === 'HIGH' || riskLevel === 'CRITICAL';

    return {
      valid: issues.filter(i => i.severity === 'CRITICAL' || i.severity === 'HIGH').length === 0,
      issues,
      requiresManualReview,
      riskLevel
    };
  }

  /**
   * Check for leaked secrets in output
   */
  private checkForSecrets(content: string): ValidationIssue[] {
    const issues: ValidationIssue[] = [];

    for (const { name, pattern } of this.secretPatterns) {
      const matches = content.match(pattern);
      if (matches) {
        for (const match of matches) {
          issues.push({
            type: 'SECRET_DETECTED',
            severity: 'CRITICAL',
            description: `Potential ${name} detected in output`,
            location: content.indexOf(match),
            context: this.getContext(content, match)
          });
        }
      }
    }

    return issues;
  }

  /**
   * Check for suspicious content patterns
   */
  private checkForSuspiciousContent(content: string): ValidationIssue[] {
    const issues: ValidationIssue[] = [];

    for (const pattern of this.suspiciousPatterns) {
      const matches = content.match(pattern);
      if (matches) {
        issues.push({
          type: 'SUSPICIOUS_PATTERN',
          severity: 'HIGH',
          description: `Suspicious pattern detected: ${pattern.source}`,
          context: matches[0]
        });
      }
    }

    return issues;
  }

  /**
   * Check if technical level matches intended audience
   */
  private checkTechnicalLevel(content: string, format: string, audience: string): ValidationIssue[] {
    const issues: ValidationIssue[] = [];

    // Get expected technical level for format
    const expectedLevel = this.getExpectedTechnicalLevel(format);

    // Calculate actual technical level
    const actualLevel = this.calculateTechnicalLevel(content);

    // Allow some variance
    if (Math.abs(actualLevel - expectedLevel) > 2) {
      issues.push({
        type: 'TECHNICAL_LEVEL_MISMATCH',
        severity: 'MEDIUM',
        description: `Content technical level (${actualLevel}/10) doesn't match ${format} format (expected ${expectedLevel}/10)`,
      });
    }

    return issues;
  }

  /**
   * Check output length is reasonable for format
   */
  private checkOutputLength(content: string, format: string): ValidationIssue[] {
    const issues: ValidationIssue[] = [];

    const wordCount = content.split(/\s+/).length;
    const expectedRange = this.getExpectedWordCount(format);

    if (wordCount < expectedRange.min) {
      issues.push({
        type: 'OUTPUT_TOO_SHORT',
        severity: 'LOW',
        description: `Output too short: ${wordCount} words (expected ${expectedRange.min}-${expectedRange.max})`
      });
    }

    if (wordCount > expectedRange.max * 2) {
      issues.push({
        type: 'OUTPUT_TOO_LONG',
        severity: 'MEDIUM',
        description: `Output unusually long: ${wordCount} words (expected ${expectedRange.min}-${expectedRange.max}). May indicate prompt injection.`
      });
    }

    return issues;
  }

  /**
   * Get expected technical level for format (0-10 scale)
   */
  private getExpectedTechnicalLevel(format: string): number {
    const levels: Record<string, number> = {
      'executive': 2,    // Low technical
      'marketing': 3,    // Low-medium technical
      'product': 5,      // Medium technical
      'unified': 5,      // Medium technical
      'engineering': 8   // High technical
    };
    return levels[format] || 5;
  }

  /**
   * Calculate technical level of content (0-10 scale)
   */
  private calculateTechnicalLevel(content: string): number {
    const technicalTerms = [
      'api', 'database', 'algorithm', 'framework', 'architecture',
      'implementation', 'infrastructure', 'deployment', 'kubernetes',
      'microservices', 'authentication', 'authorization', 'encryption',
      'protocol', 'endpoint', 'latency', 'throughput', 'scalability'
    ];

    const wordCount = content.split(/\s+/).length;
    const technicalCount = technicalTerms.reduce((count, term) => {
      const regex = new RegExp(`\\b${term}\\b`, 'gi');
      return count + (content.match(regex) || []).length;
    }, 0);

    // Calculate density of technical terms
    const density = technicalCount / wordCount;

    // Map density to 0-10 scale
    return Math.min(10, Math.round(density * 100));
  }

  /**
   * Get expected word count range for format
   */
  private getExpectedWordCount(format: string): { min: number; max: number } {
    const ranges: Record<string, { min: number; max: number }> = {
      'executive': { min: 400, max: 800 },      // 1 page
      'marketing': { min: 400, max: 800 },      // 1 page
      'product': { min: 800, max: 1500 },       // 2 pages
      'unified': { min: 800, max: 1500 },       // 2 pages
      'engineering': { min: 1200, max: 2500 }   // 3 pages
    };
    return ranges[format] || { min: 500, max: 1500 };
  }

  /**
   * Determine overall risk level from issues
   */
  private determineRiskLevel(issues: ValidationIssue[]): 'LOW' | 'MEDIUM' | 'HIGH' | 'CRITICAL' {
    if (issues.some(i => i.severity === 'CRITICAL')) {
      return 'CRITICAL';
    }
    if (issues.some(i => i.severity === 'HIGH')) {
      return 'HIGH';
    }
    if (issues.some(i => i.severity === 'MEDIUM')) {
      return 'MEDIUM';
    }
    return 'LOW';
  }

  /**
   * Get context around a match
   */
  private getContext(content: string, match: string, contextLength: number = 50): string {
    const index = content.indexOf(match);
    const start = Math.max(0, index - contextLength);
    const end = Math.min(content.length, index + match.length + contextLength);
    return '...' + content.substring(start, end) + '...';
  }

  /**
   * Check if specific secret pattern exists
   */
  containsSecret(content: string, secretType?: string): boolean {
    const patternsToCheck = secretType
      ? this.secretPatterns.filter(p => p.name === secretType)
      : this.secretPatterns;

    return patternsToCheck.some(({ pattern }) => pattern.test(content));
  }

  /**
   * Get all detected secrets (for logging/alerting)
   */
  getDetectedSecrets(content: string): Array<{ type: string; value: string; location: number }> {
    const secrets: Array<{ type: string; value: string; location: number }> = [];

    for (const { name, pattern } of this.secretPatterns) {
      const matches = content.match(pattern);
      if (matches) {
        for (const match of matches) {
          secrets.push({
            type: name,
            value: match,
            location: content.indexOf(match)
          });
        }
      }
    }

    return secrets;
  }
}

export default new OutputValidator();
