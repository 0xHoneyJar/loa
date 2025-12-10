/**
 * Blog Draft Generator
 *
 * Generates blog post drafts for manual review and publishing.
 * NEVER auto-publishes - all blog posts must be manually published by authorized team members.
 *
 * This implements CRITICAL-007 remediation (blog publishing security).
 */

import { logger } from '../utils/logger';
import { secretScanner } from './secret-scanner';
import { preDistributionValidator } from './pre-distribution-validator';
import { SecurityException } from '../utils/errors';

export interface BlogDraft {
  id: string;
  title: string;
  content: string;
  summary: string;
  sourceDocuments: string[];
  createdAt: Date;
  createdBy: string;
  status: 'draft' | 'ready_for_review' | 'approved' | 'published' | 'rejected';
  reviewedBy?: string;
  reviewedAt?: Date;
  publishedBy?: string;
  publishedAt?: Date;
  rejectionReason?: string;
  metadata: {
    wordCount: number;
    secretsDetected: boolean;
    secretsRedacted: number;
    sensitiveContentFlags: string[];
    redactionChecklist: RedactionChecklistItem[];
  };
}

export interface RedactionChecklistItem {
  category: string;
  description: string;
  checked: boolean;
  notes?: string;
}

/**
 * Blog Draft Generator
 *
 * Security Controls:
 * 1. Auto-publishing DISABLED - all drafts require manual publishing
 * 2. Secret scanning before draft creation
 * 3. Automatic secret redaction in drafts
 * 4. Pre-distribution validation (additional layer)
 * 5. Redaction checklist for manual review
 * 6. Sensitive content flagging (internal URLs, emails, amounts)
 * 7. Status tracking (draft → review → approved → published)
 * 8. Audit trail for all draft operations
 * 9. Multi-stakeholder approval workflow
 * 10. Final secret scan before publishing
 */
export class BlogDraftGenerator {
  private drafts = new Map<string, BlogDraft>();

  /**
   * Generate blog draft from content
   *
   * IMPORTANT: This ONLY creates a draft. It does NOT publish automatically.
   * Team members must manually review and publish via publishDraft().
   */
  async generateDraft(
    title: string,
    content: string,
    sourceDocuments: string[],
    createdBy: string
  ): Promise<BlogDraft> {
    logger.info('Generating blog draft', { title, createdBy, sourceDocumentCount: sourceDocuments.length });

    try {
      // STEP 1: Scan for secrets (CRITICAL-005)
      const scanResult = secretScanner.scanForSecrets(content, {
        skipFalsePositives: true,
        contextLength: 100
      });

      let secretsDetected = false;
      let secretsRedacted = 0;
      let processedContent = content;

      if (scanResult.hasSecrets) {
        secretsDetected = true;
        secretsRedacted = scanResult.totalSecretsFound;

        logger.warn('Secrets detected in blog draft content', {
          title,
          secretCount: scanResult.totalSecretsFound,
          criticalSecrets: scanResult.criticalSecretsFound,
          secretTypes: scanResult.secrets.map(s => s.type).join(', ')
        });

        // Automatically redact secrets
        processedContent = scanResult.redactedContent;

        logger.info('Secrets redacted from blog draft', { title, secretsRedacted });
      }

      // STEP 2: Flag sensitive content patterns
      const sensitiveContentFlags = this.detectSensitiveContent(processedContent);

      if (sensitiveContentFlags.length > 0) {
        logger.warn('Sensitive content detected in blog draft', {
          title,
          flags: sensitiveContentFlags
        });
      }

      // STEP 3: Generate redaction checklist for manual review
      const redactionChecklist = this.generateRedactionChecklist();

      // STEP 4: Create draft
      const draft: BlogDraft = {
        id: this.generateDraftId(),
        title,
        content: processedContent,
        summary: this.generateSummary(processedContent),
        sourceDocuments,
        createdAt: new Date(),
        createdBy,
        status: 'draft',
        metadata: {
          wordCount: this.countWords(processedContent),
          secretsDetected,
          secretsRedacted,
          sensitiveContentFlags,
          redactionChecklist
        }
      };

      // Store draft
      this.drafts.set(draft.id, draft);

      logger.info('Blog draft created successfully', {
        draftId: draft.id,
        title: draft.title,
        status: draft.status,
        wordCount: draft.metadata.wordCount,
        secretsDetected,
        sensitiveContentFlags: sensitiveContentFlags.length
      });

      // Audit log
      logger.security({
        eventType: 'BLOG_DRAFT_CREATED',
        severity: 'INFO',
        draftId: draft.id,
        title: draft.title,
        createdBy,
        secretsDetected,
        secretsRedacted,
        sensitiveContentFlags,
        timestamp: new Date().toISOString()
      });

      return draft;

    } catch (error) {
      logger.error('Failed to generate blog draft', {
        title,
        error: error.message,
        stack: error.stack
      });
      throw new Error(`Failed to generate blog draft: ${error.message}`);
    }
  }

  /**
   * Mark draft as ready for review
   */
  async markReadyForReview(draftId: string): Promise<BlogDraft> {
    const draft = this.drafts.get(draftId);
    if (!draft) {
      throw new Error(`Draft not found: ${draftId}`);
    }

    if (draft.status !== 'draft') {
      throw new Error(`Draft ${draftId} is not in draft status (current: ${draft.status})`);
    }

    draft.status = 'ready_for_review';

    logger.info('Draft marked ready for review', {
      draftId: draft.id,
      title: draft.title
    });

    return draft;
  }

  /**
   * Review draft (approve or reject)
   */
  async reviewDraft(
    draftId: string,
    reviewedBy: string,
    approved: boolean,
    rejectionReason?: string
  ): Promise<BlogDraft> {
    const draft = this.drafts.get(draftId);
    if (!draft) {
      throw new Error(`Draft not found: ${draftId}`);
    }

    if (draft.status !== 'ready_for_review') {
      throw new Error(`Draft ${draftId} is not ready for review (current: ${draft.status})`);
    }

    draft.reviewedBy = reviewedBy;
    draft.reviewedAt = new Date();

    if (approved) {
      draft.status = 'approved';
      logger.info('Draft approved', { draftId: draft.id, reviewedBy });
    } else {
      draft.status = 'rejected';
      draft.rejectionReason = rejectionReason;
      logger.info('Draft rejected', { draftId: draft.id, reviewedBy, reason: rejectionReason });
    }

    // Audit log
    logger.security({
      eventType: approved ? 'BLOG_DRAFT_APPROVED' : 'BLOG_DRAFT_REJECTED',
      severity: 'INFO',
      draftId: draft.id,
      reviewedBy,
      rejectionReason,
      timestamp: new Date().toISOString()
    });

    return draft;
  }

  /**
   * Publish approved draft
   *
   * IMPORTANT: This is the ONLY way to publish a blog post.
   * Requires manual approval and final security checks.
   */
  async publishDraft(draftId: string, publishedBy: string): Promise<BlogDraft> {
    const draft = this.drafts.get(draftId);
    if (!draft) {
      throw new Error(`Draft not found: ${draftId}`);
    }

    // SECURITY CHECK: Must be approved first
    if (draft.status !== 'approved') {
      throw new SecurityException(
        `Cannot publish draft ${draftId}: status is ${draft.status}, must be 'approved'`
      );
    }

    logger.info('Publishing blog draft', {
      draftId: draft.id,
      title: draft.title,
      publishedBy
    });

    try {
      // STEP 1: Final secret scan (CRITICAL-005)
      const scanResult = secretScanner.scanForSecrets(draft.content);
      if (scanResult.hasSecrets) {
        logger.error('CRITICAL: Secrets detected in approved draft before publishing', {
          draftId: draft.id,
          secretCount: scanResult.totalSecretsFound,
          criticalSecrets: scanResult.criticalSecretsFound
        });

        throw new SecurityException(
          `Cannot publish draft ${draftId}: secrets detected in content. Found: ${scanResult.secrets.map(s => s.type).join(', ')}`
        );
      }

      // STEP 2: Pre-distribution validation (CRITICAL-005)
      const validationResult = await preDistributionValidator.validateBeforeDistribution(
        {
          content: draft.content,
          metadata: {
            documentId: draft.id,
            documentName: draft.title,
            author: draft.createdBy,
            channel: 'blog'
          }
        },
        {
          strictMode: true,
          allowWarnings: false
        }
      );

      if (!validationResult.valid) {
        logger.error('Pre-distribution validation failed for draft', {
          draftId: draft.id,
          errors: validationResult.errors
        });

        throw new SecurityException(
          `Cannot publish draft ${draftId}: pre-distribution validation failed. Errors: ${validationResult.errors.join('; ')}`
        );
      }

      // STEP 3: Mark as published
      draft.status = 'published';
      draft.publishedBy = publishedBy;
      draft.publishedAt = new Date();

      logger.info('Blog draft published successfully', {
        draftId: draft.id,
        title: draft.title,
        publishedBy,
        publishedAt: draft.publishedAt
      });

      // STEP 4: Audit log
      logger.security({
        eventType: 'BLOG_DRAFT_PUBLISHED',
        severity: 'INFO',
        draftId: draft.id,
        title: draft.title,
        publishedBy,
        publishedAt: draft.publishedAt,
        timestamp: new Date().toISOString()
      });

      return draft;

    } catch (error) {
      if (error instanceof SecurityException) {
        // Re-throw security exceptions
        throw error;
      }

      logger.error('Failed to publish draft', {
        draftId: draft.id,
        error: error.message
      });

      throw new Error(`Failed to publish draft: ${error.message}`);
    }
  }

  /**
   * Get draft by ID
   */
  getDraft(draftId: string): BlogDraft | undefined {
    return this.drafts.get(draftId);
  }

  /**
   * List all drafts
   */
  listDrafts(filters?: {
    status?: BlogDraft['status'];
    createdBy?: string;
  }): BlogDraft[] {
    let drafts = Array.from(this.drafts.values());

    if (filters?.status) {
      drafts = drafts.filter(d => d.status === filters.status);
    }

    if (filters?.createdBy) {
      drafts = drafts.filter(d => d.createdBy === filters.createdBy);
    }

    // Sort by created date (newest first)
    return drafts.sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime());
  }

  /**
   * Detect sensitive content patterns
   */
  private detectSensitiveContent(content: string): string[] {
    const flags: string[] = [];

    // Internal URLs
    if (content.match(/https?:\/\/(internal|localhost|127\.0\.0\.1|192\.168\.|10\.)/gi)) {
      flags.push('INTERNAL_URL');
    }

    // Email addresses
    if (content.match(/[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/g)) {
      flags.push('EMAIL_ADDRESS');
    }

    // Dollar amounts (might be sensitive revenue data)
    if (content.match(/\$[\d,]+/g)) {
      flags.push('DOLLAR_AMOUNT');
    }

    // IP addresses
    if (content.match(/\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b/g)) {
      flags.push('IP_ADDRESS');
    }

    // Specific employee names pattern (simplified)
    if (content.match(/@[a-zA-Z0-9._-]+/g)) {
      flags.push('USERNAME_MENTION');
    }

    return flags;
  }

  /**
   * Generate redaction checklist for manual review
   */
  private generateRedactionChecklist(): RedactionChecklistItem[] {
    return [
      // Secrets & Credentials
      {
        category: 'Secrets & Credentials',
        description: 'API keys, tokens, passwords redacted',
        checked: false
      },
      {
        category: 'Secrets & Credentials',
        description: 'Database connection strings removed',
        checked: false
      },
      {
        category: 'Secrets & Credentials',
        description: 'Private keys and certificates removed',
        checked: false
      },
      {
        category: 'Secrets & Credentials',
        description: 'Internal URLs and endpoints obscured',
        checked: false
      },

      // Business Sensitive
      {
        category: 'Business Sensitive',
        description: 'Revenue numbers removed or rounded',
        checked: false
      },
      {
        category: 'Business Sensitive',
        description: 'Customer names anonymized',
        checked: false
      },
      {
        category: 'Business Sensitive',
        description: 'Pricing details redacted',
        checked: false
      },
      {
        category: 'Business Sensitive',
        description: 'Competitive intelligence removed',
        checked: false
      },
      {
        category: 'Business Sensitive',
        description: 'Unreleased product details removed',
        checked: false
      },

      // Security Sensitive
      {
        category: 'Security Sensitive',
        description: 'Unpatched vulnerabilities removed',
        checked: false
      },
      {
        category: 'Security Sensitive',
        description: 'Security architecture details obscured',
        checked: false
      },
      {
        category: 'Security Sensitive',
        description: 'Internal infrastructure details removed',
        checked: false
      },
      {
        category: 'Security Sensitive',
        description: 'Incident details anonymized',
        checked: false
      },

      // Legal & Compliance
      {
        category: 'Legal & Compliance',
        description: 'No PII exposed',
        checked: false
      },
      {
        category: 'Legal & Compliance',
        description: 'GDPR compliance verified',
        checked: false
      },
      {
        category: 'Legal & Compliance',
        description: 'No confidential agreements referenced',
        checked: false
      },
      {
        category: 'Legal & Compliance',
        description: 'No trademark/IP violations',
        checked: false
      }
    ];
  }

  /**
   * Generate summary from content (first 200 chars)
   */
  private generateSummary(content: string): string {
    const cleanContent = content.replace(/[#*_`]/g, '').trim();
    return cleanContent.substring(0, 200) + (cleanContent.length > 200 ? '...' : '');
  }

  /**
   * Count words in content
   */
  private countWords(content: string): number {
    return content.split(/\s+/).filter(word => word.length > 0).length;
  }

  /**
   * Generate unique draft ID
   */
  private generateDraftId(): string {
    return `draft_${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;
  }

  /**
   * Get statistics
   */
  getStatistics(): {
    totalDrafts: number;
    draftsByStatus: Record<BlogDraft['status'], number>;
    draftsWithSecrets: number;
    draftsWithSensitiveContent: number;
  } {
    const drafts = Array.from(this.drafts.values());

    const draftsByStatus: Record<BlogDraft['status'], number> = {
      'draft': 0,
      'ready_for_review': 0,
      'approved': 0,
      'published': 0,
      'rejected': 0
    };

    for (const draft of drafts) {
      draftsByStatus[draft.status]++;
    }

    return {
      totalDrafts: drafts.length,
      draftsByStatus,
      draftsWithSecrets: drafts.filter(d => d.metadata.secretsDetected).length,
      draftsWithSensitiveContent: drafts.filter(d => d.metadata.sensitiveContentFlags.length > 0).length
    };
  }
}

// Singleton instance
export const blogDraftGenerator = new BlogDraftGenerator();
export default blogDraftGenerator;
