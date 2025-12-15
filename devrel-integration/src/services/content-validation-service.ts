/**
 * Content Validation Service
 *
 * Sprint 6 - Task 6.2: Content Validation Service
 *
 * Provides AI-powered technical accuracy validation for marketing content.
 * Uses Claude to verify technical claims against documentation.
 *
 * Features:
 * - Validate technical claims against PRD/SDD
 * - Flag outdated information
 * - Identify missing disclaimers
 * - Highlight misleading language
 * - Confidence scoring for findings
 * - Tenant isolation for multi-tenancy
 */

import { logger } from '../utils/logger';
import { getCurrentTenant } from './tenant-context';
import { TieredCache } from './tiered-cache';

// =============================================================================
// Types
// =============================================================================

export type ValidationVerdict = 'accurate' | 'minor_issues' | 'major_issues';

export interface ValidationReport {
  verdict: ValidationVerdict;
  overallScore: number;
  findings: ValidationFinding[];
  suggestions: string[];
  validatedAt: Date;
  contentLength: number;
  documentationSourcesChecked: string[];
}

export interface ValidationFinding {
  type: ValidationFindingType;
  severity: 'critical' | 'warning' | 'info';
  message: string;
  excerpt: string;
  confidence: number;
  suggestion?: string;
  sourceReference?: string;
}

export type ValidationFindingType =
  | 'inaccurate_claim'
  | 'outdated_info'
  | 'missing_disclaimer'
  | 'misleading_language'
  | 'unverifiable_claim'
  | 'technical_error'
  | 'style_issue';

export interface ContentValidationOptions {
  /** Product context for validation */
  product?: string;
  /** Strictness level */
  strictness?: 'relaxed' | 'standard' | 'strict';
  /** Categories to check */
  categories?: ValidationCategory[];
  /** Use cached result if available */
  useCache?: boolean;
  /** Custom documentation to validate against */
  customDocumentation?: DocumentationSource[];
}

export type ValidationCategory =
  | 'technical_accuracy'
  | 'date_currency'
  | 'disclaimers'
  | 'language_clarity'
  | 'brand_consistency';

export interface DocumentationSource {
  name: string;
  type: 'prd' | 'sdd' | 'readme' | 'api_docs' | 'custom';
  content: string;
}

export interface ClaudeClientInterface {
  complete(prompt: string): Promise<string>;
}

export interface GoogleDocsClientInterface {
  fetchDocument(documentId: string): Promise<string>;
}

// =============================================================================
// Content Validation Service
// =============================================================================

export class ContentValidationService {
  private static instance: ContentValidationService;
  private cache: TieredCache;
  private claudeClient: ClaudeClientInterface | null = null;
  private googleDocsClient: GoogleDocsClientInterface | null = null;
  private documentationCache = new Map<string, DocumentationSource>();

  constructor() {
    this.cache = TieredCache.getInstance();
  }

  /**
   * Get singleton instance
   */
  static getInstance(): ContentValidationService {
    if (!ContentValidationService.instance) {
      ContentValidationService.instance = new ContentValidationService();
    }
    return ContentValidationService.instance;
  }

  /**
   * Inject Claude client for AI validation
   */
  setClaudeClient(client: ClaudeClientInterface): void {
    this.claudeClient = client;
  }

  /**
   * Inject Google Docs client
   */
  setGoogleDocsClient(client: GoogleDocsClientInterface): void {
    this.googleDocsClient = client;
  }

  /**
   * Register documentation source for validation
   */
  registerDocumentation(source: DocumentationSource): void {
    this.documentationCache.set(source.name, source);
    logger.debug('Documentation registered', { name: source.name, type: source.type });
  }

  /**
   * Clear documentation cache
   */
  clearDocumentationCache(): void {
    this.documentationCache.clear();
    logger.debug('Documentation cache cleared');
  }

  // ===========================================================================
  // Main Validation Methods
  // ===========================================================================

  /**
   * Validate content for technical accuracy
   */
  async validateContent(
    content: string,
    product: string,
    options: ContentValidationOptions = {}
  ): Promise<ValidationReport> {
    const tenant = getCurrentTenant();
    const contentHash = this.hashContent(content);
    const cacheKey = `validation:${product}:${contentHash}`;

    logger.info('Validating content', {
      tenantId: tenant.tenantId,
      product,
      contentLength: content.length,
      strictness: options.strictness ?? 'standard',
    });

    // Check cache if enabled
    if (options.useCache !== false) {
      try {
        const cached = await this.cache.get<ValidationReport>(tenant.tenantId, cacheKey);
        if (cached) {
          logger.debug('Validation report retrieved from cache', { product });
          return cached;
        }
      } catch (error) {
        logger.warn('Cache lookup failed for validation', {
          error: error instanceof Error ? error.message : String(error),
        });
      }
    }

    try {
      // Perform validation
      const report = await this.performValidation(content, product, options);

      // Cache the result (10 min TTL)
      try {
        await this.cache.set(tenant.tenantId, cacheKey, report, 600);
      } catch (error) {
        logger.warn('Failed to cache validation report', {
          error: error instanceof Error ? error.message : String(error),
        });
      }

      return report;
    } catch (error) {
      logger.error('Content validation failed', {
        error: error instanceof Error ? error.message : String(error),
        product,
      });
      throw error;
    }
  }

  /**
   * Validate content from Google Docs link
   */
  async validateGoogleDoc(
    documentLink: string,
    product: string,
    options: ContentValidationOptions = {}
  ): Promise<ValidationReport> {
    const tenant = getCurrentTenant();

    logger.info('Validating Google Doc', {
      tenantId: tenant.tenantId,
      documentLink,
      product,
    });

    if (!this.googleDocsClient) {
      throw new Error('Google Docs client not configured');
    }

    // Extract document ID from link
    const documentId = this.extractDocumentId(documentLink);
    if (!documentId) {
      throw new Error('Invalid Google Docs link');
    }

    // Fetch document content
    const content = await this.googleDocsClient.fetchDocument(documentId);

    // Validate the content
    return this.validateContent(content, product, options);
  }

  // ===========================================================================
  // Validation Implementation
  // ===========================================================================

  /**
   * Perform validation using AI
   */
  private async performValidation(
    content: string,
    product: string,
    options: ContentValidationOptions
  ): Promise<ValidationReport> {
    const tenant = getCurrentTenant();
    const strictness = options.strictness ?? 'standard';
    const categories = options.categories ?? [
      'technical_accuracy',
      'date_currency',
      'disclaimers',
      'language_clarity',
    ];

    // Gather documentation sources
    const sources = await this.gatherDocumentation(product, options);

    // If no Claude client, perform rule-based validation
    if (!this.claudeClient) {
      logger.warn('Claude client not configured, using rule-based validation');
      return this.performRuleBasedValidation(content, sources, strictness);
    }

    // Build validation prompt
    const prompt = this.buildValidationPrompt(content, sources, categories, strictness);

    // Call Claude for validation
    const aiResponse = await this.claudeClient.complete(prompt);

    // Parse AI response
    const findings = this.parseAIResponse(aiResponse);

    // Calculate verdict and score
    const { verdict, score } = this.calculateVerdict(findings, strictness);

    // Generate suggestions
    const suggestions = this.generateSuggestions(findings);

    logger.info('Content validation completed', {
      tenantId: tenant.tenantId,
      product,
      verdict,
      findingsCount: findings.length,
    });

    return {
      verdict,
      overallScore: score,
      findings,
      suggestions,
      validatedAt: new Date(),
      contentLength: content.length,
      documentationSourcesChecked: sources.map((s) => s.name),
    };
  }

  /**
   * Gather documentation sources for validation
   */
  private async gatherDocumentation(
    product: string,
    options: ContentValidationOptions
  ): Promise<DocumentationSource[]> {
    const sources: DocumentationSource[] = [];

    // Add custom documentation if provided
    if (options.customDocumentation) {
      sources.push(...options.customDocumentation);
    }

    // Add cached documentation
    for (const source of this.documentationCache.values()) {
      sources.push(source);
    }

    return sources;
  }

  /**
   * Build validation prompt for Claude
   */
  private buildValidationPrompt(
    content: string,
    sources: DocumentationSource[],
    categories: ValidationCategory[],
    strictness: 'relaxed' | 'standard' | 'strict'
  ): string {
    const strictnessGuide = {
      relaxed: 'Focus only on clearly incorrect technical claims. Allow marketing hyperbole.',
      standard: 'Flag incorrect claims, outdated info, and missing disclaimers. Allow reasonable marketing language.',
      strict: 'Flag any claim that cannot be verified. Require precise language. Check all disclaimers.',
    };

    const categoryDescriptions: Record<ValidationCategory, string> = {
      technical_accuracy: 'Verify technical claims match documentation',
      date_currency: 'Check dates, versions, and timeframes are current',
      disclaimers: 'Ensure required disclaimers are present',
      language_clarity: 'Flag misleading or ambiguous language',
      brand_consistency: 'Check brand voice and messaging consistency',
    };

    const categoriesText = categories
      .map((c) => `- ${c}: ${categoryDescriptions[c]}`)
      .join('\n');

    const sourcesText = sources.length > 0
      ? sources.map((s) => `### ${s.name} (${s.type})\n${s.content.slice(0, 2000)}...`).join('\n\n')
      : 'No documentation sources provided.';

    return `You are a technical content validator. Your task is to review marketing content for technical accuracy.

## Validation Guidelines
${strictnessGuide[strictness]}

## Categories to Check
${categoriesText}

## Documentation Sources
${sourcesText}

## Content to Validate
${content}

## Response Format
Provide your findings as a JSON array with this structure:
[
  {
    "type": "inaccurate_claim|outdated_info|missing_disclaimer|misleading_language|unverifiable_claim|technical_error|style_issue",
    "severity": "critical|warning|info",
    "message": "Description of the issue",
    "excerpt": "The specific text with the issue",
    "confidence": 0.0-1.0,
    "suggestion": "How to fix it",
    "sourceReference": "Which documentation source contradicts this (if any)"
  }
]

If the content is accurate, return an empty array: []

IMPORTANT: Return ONLY the JSON array, no other text.`;
  }

  /**
   * Parse AI response into findings
   */
  private parseAIResponse(response: string): ValidationFinding[] {
    try {
      // Extract JSON from response
      const jsonMatch = response.match(/\[[\s\S]*\]/);
      if (!jsonMatch) {
        logger.warn('Could not extract JSON from AI response');
        return [];
      }

      const parsed = JSON.parse(jsonMatch[0]);

      if (!Array.isArray(parsed)) {
        logger.warn('AI response is not an array');
        return [];
      }

      // Validate and normalize findings
      return parsed
        .filter((f: unknown) => this.isValidFinding(f))
        .map((f: unknown) => this.normalizeFinding(f as Partial<ValidationFinding>));
    } catch (error) {
      logger.error('Failed to parse AI response', {
        error: error instanceof Error ? error.message : String(error),
      });
      return [];
    }
  }

  /**
   * Check if finding object is valid
   */
  private isValidFinding(finding: unknown): boolean {
    if (typeof finding !== 'object' || finding === null) return false;
    const f = finding as Record<string, unknown>;
    return (
      typeof f.type === 'string' &&
      typeof f.severity === 'string' &&
      typeof f.message === 'string'
    );
  }

  /**
   * Normalize finding object
   */
  private normalizeFinding(f: Partial<ValidationFinding>): ValidationFinding {
    return {
      type: this.normalizeType(f.type ?? 'technical_error'),
      severity: this.normalizeSeverity(f.severity ?? 'warning'),
      message: f.message ?? 'Unknown issue',
      excerpt: f.excerpt ?? '',
      confidence: Math.max(0, Math.min(1, f.confidence ?? 0.5)),
      suggestion: f.suggestion,
      sourceReference: f.sourceReference,
    };
  }

  /**
   * Normalize finding type
   */
  private normalizeType(type: string): ValidationFindingType {
    const validTypes: ValidationFindingType[] = [
      'inaccurate_claim',
      'outdated_info',
      'missing_disclaimer',
      'misleading_language',
      'unverifiable_claim',
      'technical_error',
      'style_issue',
    ];
    return validTypes.includes(type as ValidationFindingType)
      ? (type as ValidationFindingType)
      : 'technical_error';
  }

  /**
   * Normalize severity
   */
  private normalizeSeverity(severity: string): 'critical' | 'warning' | 'info' {
    const normalized = severity.toLowerCase();
    if (normalized === 'critical') return 'critical';
    if (normalized === 'info') return 'info';
    return 'warning';
  }

  /**
   * Perform rule-based validation (fallback when no AI)
   */
  private performRuleBasedValidation(
    content: string,
    sources: DocumentationSource[],
    strictness: 'relaxed' | 'standard' | 'strict'
  ): ValidationReport {
    const findings: ValidationFinding[] = [];
    const lowerContent = content.toLowerCase();

    // Check for common issues

    // 1. Check for absolute claims without qualifiers
    const absolutePatterns = [
      { pattern: /\b100%\b/gi, message: 'Absolute percentage claim' },
      { pattern: /\bguaranteed?\b/gi, message: 'Guarantee claim without disclaimer' },
      { pattern: /\bnever\b/gi, message: 'Absolute "never" claim' },
      { pattern: /\balways\b/gi, message: 'Absolute "always" claim' },
    ];

    if (strictness !== 'relaxed') {
      for (const { pattern, message } of absolutePatterns) {
        const matches = content.match(pattern);
        if (matches) {
          for (const match of matches) {
            findings.push({
              type: 'misleading_language',
              severity: strictness === 'strict' ? 'warning' : 'info',
              message,
              excerpt: match,
              confidence: 0.7,
              suggestion: 'Consider adding qualifiers or removing absolute language',
            });
          }
        }
      }
    }

    // 2. Check for outdated year references
    const currentYear = new Date().getFullYear();
    const yearPattern = /\b20\d{2}\b/g;
    const yearMatches = content.match(yearPattern);
    if (yearMatches) {
      for (const year of yearMatches) {
        const yearNum = parseInt(year, 10);
        if (yearNum < currentYear - 1) {
          findings.push({
            type: 'outdated_info',
            severity: 'warning',
            message: `Reference to ${year} may be outdated`,
            excerpt: year,
            confidence: 0.6,
            suggestion: 'Verify this date/year reference is still current',
          });
        }
      }
    }

    // 3. Check for crypto-related disclaimers
    const cryptoTerms = ['token', 'crypto', 'blockchain', 'defi', 'nft', 'web3'];
    const hasCryptoContent = cryptoTerms.some((term) => lowerContent.includes(term));
    const hasDisclaimer = lowerContent.includes('not financial advice') ||
      lowerContent.includes('disclaimer') ||
      lowerContent.includes('dyor');

    if (hasCryptoContent && !hasDisclaimer && strictness !== 'relaxed') {
      findings.push({
        type: 'missing_disclaimer',
        severity: 'warning',
        message: 'Crypto-related content may require financial disclaimer',
        excerpt: '',
        confidence: 0.8,
        suggestion: 'Add "Not financial advice" or similar disclaimer',
      });
    }

    // 4. Check for unverifiable performance claims
    const performancePatterns = [
      { pattern: /\d+x\s*(faster|better|more)/gi, message: 'Performance multiplier claim' },
      { pattern: /\d+%\s*(faster|better|more|improvement)/gi, message: 'Percentage improvement claim' },
    ];

    for (const { pattern, message } of performancePatterns) {
      const matches = content.match(pattern);
      if (matches) {
        for (const match of matches) {
          findings.push({
            type: 'unverifiable_claim',
            severity: 'info',
            message,
            excerpt: match,
            confidence: 0.6,
            suggestion: 'Consider adding source or benchmark reference',
          });
        }
      }
    }

    // Calculate verdict
    const { verdict, score } = this.calculateVerdict(findings, strictness);

    return {
      verdict,
      overallScore: score,
      findings,
      suggestions: this.generateSuggestions(findings),
      validatedAt: new Date(),
      contentLength: content.length,
      documentationSourcesChecked: sources.map((s) => s.name),
    };
  }

  /**
   * Calculate verdict based on findings
   */
  private calculateVerdict(
    findings: ValidationFinding[],
    strictness: 'relaxed' | 'standard' | 'strict'
  ): { verdict: ValidationVerdict; score: number } {
    const criticalCount = findings.filter((f) => f.severity === 'critical').length;
    const warningCount = findings.filter((f) => f.severity === 'warning').length;
    const infoCount = findings.filter((f) => f.severity === 'info').length;

    // Calculate score (100 = perfect)
    let score = 100;
    score -= criticalCount * 25;
    score -= warningCount * 10;
    score -= infoCount * 2;
    score = Math.max(0, score);

    // Determine verdict
    let verdict: ValidationVerdict;

    if (strictness === 'strict') {
      if (criticalCount > 0 || warningCount >= 2) {
        verdict = 'major_issues';
      } else if (warningCount > 0 || infoCount >= 3) {
        verdict = 'minor_issues';
      } else {
        verdict = 'accurate';
      }
    } else if (strictness === 'relaxed') {
      if (criticalCount >= 2) {
        verdict = 'major_issues';
      } else if (criticalCount > 0 || warningCount >= 3) {
        verdict = 'minor_issues';
      } else {
        verdict = 'accurate';
      }
    } else {
      // standard
      if (criticalCount > 0 || warningCount >= 3) {
        verdict = 'major_issues';
      } else if (warningCount > 0 || infoCount >= 3) {
        verdict = 'minor_issues';
      } else {
        verdict = 'accurate';
      }
    }

    return { verdict, score };
  }

  /**
   * Generate suggestions from findings
   */
  private generateSuggestions(findings: ValidationFinding[]): string[] {
    const suggestions: string[] = [];
    const seen = new Set<string>();

    for (const finding of findings) {
      if (finding.suggestion && !seen.has(finding.suggestion)) {
        suggestions.push(finding.suggestion);
        seen.add(finding.suggestion);
      }
    }

    // Add general suggestions based on finding types
    const types = new Set(findings.map((f) => f.type));

    if (types.has('missing_disclaimer')) {
      const s = 'Review and add appropriate disclaimers for all claims';
      if (!seen.has(s)) suggestions.push(s);
    }

    if (types.has('outdated_info')) {
      const s = 'Update all date references to current information';
      if (!seen.has(s)) suggestions.push(s);
    }

    if (types.has('misleading_language')) {
      const s = 'Review marketing language for clarity and accuracy';
      if (!seen.has(s)) suggestions.push(s);
    }

    return suggestions;
  }

  // ===========================================================================
  // Utility Methods
  // ===========================================================================

  /**
   * Extract document ID from Google Docs link
   */
  private extractDocumentId(link: string): string | null {
    // Pattern: https://docs.google.com/document/d/DOCUMENT_ID/...
    const pattern = /\/document\/d\/([a-zA-Z0-9_-]+)/;
    const match = link.match(pattern);
    return match ? match[1] : null;
  }

  /**
   * Generate content hash for caching
   */
  private hashContent(content: string): string {
    // Simple hash for cache key
    let hash = 0;
    for (let i = 0; i < content.length; i++) {
      const char = content.charCodeAt(i);
      hash = ((hash << 5) - hash) + char;
      hash = hash & hash; // Convert to 32bit integer
    }
    return Math.abs(hash).toString(36);
  }

  // ===========================================================================
  // Formatting Helpers
  // ===========================================================================

  /**
   * Format validation report as Discord embed
   */
  formatReportForDiscord(report: ValidationReport): object {
    const verdictEmoji =
      report.verdict === 'accurate' ? '✅' :
      report.verdict === 'minor_issues' ? '⚠️' : '❌';

    const severityEmoji = {
      critical: '🔴',
      warning: '🟡',
      info: '🔵',
    };

    const findingsText = report.findings.length > 0
      ? report.findings
          .slice(0, 10)
          .map((f) => `${severityEmoji[f.severity]} **${f.type}**: ${f.message}`)
          .join('\n')
      : 'No issues found';

    return {
      title: `Content Validation Report`,
      description: `${verdictEmoji} **Verdict: ${report.verdict.replace('_', ' ').toUpperCase()}**`,
      fields: [
        { name: 'Score', value: `${report.overallScore}/100`, inline: true },
        { name: 'Content Length', value: `${report.contentLength} chars`, inline: true },
        { name: 'Sources Checked', value: report.documentationSourcesChecked.length.toString(), inline: true },
        {
          name: 'Findings',
          value: findingsText,
          inline: false,
        },
        {
          name: 'Suggestions',
          value: report.suggestions.length > 0
            ? report.suggestions.slice(0, 5).map((s) => `• ${s}`).join('\n')
            : 'No suggestions',
          inline: false,
        },
      ],
      footer: { text: `Validated at ${report.validatedAt.toISOString()}` },
    };
  }
}

// =============================================================================
// Export Singleton Instance
// =============================================================================

export const contentValidationService = ContentValidationService.getInstance();
export default contentValidationService;
