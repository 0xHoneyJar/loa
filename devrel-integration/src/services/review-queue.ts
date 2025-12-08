/**
 * Review Queue
 *
 * Manages manual review workflow for flagged translations.
 * Flags suspicious outputs for manual review before distribution.
 *
 * Security Controls:
 * - Block distribution of flagged content
 * - Alert reviewers immediately
 * - Track review status and approvals
 * - Audit log all review actions
 */

import * as fs from 'fs';
import * as path from 'path';

export interface ReviewItem {
  id: string;
  translation: any;
  reason: string;
  flaggedAt: Date;
  flaggedBy: string;
  reviewedBy: string | null;
  reviewedAt: Date | null;
  approved: boolean;
  status: 'PENDING' | 'APPROVED' | 'REJECTED';
  securityIssues: string[];
  notes: string;
}

export class SecurityException extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'SecurityException';
  }
}

export class ReviewQueue {
  private queuePath: string;
  private queue: Map<string, ReviewItem>;

  constructor() {
    this.queuePath = path.join(__dirname, '../../data/review-queue.json');
    this.queue = new Map();
    this.loadQueue();
  }

  /**
   * Flag translation for manual review
   */
  async flagForReview(
    translation: any,
    reason: string,
    securityIssues: string[] = []
  ): Promise<void> {
    const reviewItem: ReviewItem = {
      id: this.generateId(),
      translation,
      reason,
      flaggedAt: new Date(),
      flaggedBy: 'system',
      reviewedBy: null,
      reviewedAt: null,
      approved: false,
      status: 'PENDING',
      securityIssues,
      notes: ''
    };

    // Add to queue
    this.queue.set(reviewItem.id, reviewItem);
    await this.saveQueue();

    // Alert reviewers immediately
    await this.notifyReviewers(reviewItem);

    // Log security event
    this.logSecurityEvent('FLAGGED_FOR_REVIEW', reviewItem);

    // BLOCK distribution - throw exception
    throw new SecurityException(
      `Translation flagged for review: ${reason}\n` +
      `Review ID: ${reviewItem.id}\n` +
      `Security issues: ${securityIssues.join(', ')}`
    );
  }

  /**
   * Notify reviewers about flagged content
   */
  private async notifyReviewers(reviewItem: ReviewItem): Promise<void> {
    const message = this.formatReviewAlert(reviewItem);

    // In production, this would send to Discord/Slack/Email
    console.error('\n========================================');
    console.error('🚨 SECURITY ALERT: CONTENT FLAGGED FOR REVIEW');
    console.error('========================================');
    console.error(message);
    console.error('========================================\n');

    // TODO: Implement actual notification (Discord webhook, email, etc.)
    // await discordWebhook.send({
    //   content: '🚨 **SECURITY ALERT: Translation Flagged for Review**',
    //   embeds: [{
    //     title: 'Review Required',
    //     description: message,
    //     color: 0xFF0000, // Red
    //     timestamp: new Date().toISOString()
    //   }]
    // });
  }

  /**
   * Format review alert message
   */
  private formatReviewAlert(reviewItem: ReviewItem): string {
    return [
      `Review ID: ${reviewItem.id}`,
      `Reason: ${reviewItem.reason}`,
      `Flagged At: ${reviewItem.flaggedAt.toISOString()}`,
      `Security Issues: ${reviewItem.securityIssues.join(', ') || 'None'}`,
      '',
      'ACTION REQUIRED:',
      '1. Review translation content in review queue',
      '2. Check for secrets, sensitive data, prompt injection',
      '3. Approve or reject translation',
      '',
      `Command: npm run review ${reviewItem.id}`
    ].join('\n');
  }

  /**
   * Get pending review items
   */
  getPendingReviews(): ReviewItem[] {
    return Array.from(this.queue.values()).filter(
      item => item.status === 'PENDING'
    );
  }

  /**
   * Get review item by ID
   */
  getReviewItem(id: string): ReviewItem | undefined {
    return this.queue.get(id);
  }

  /**
   * Approve review item
   */
  async approve(id: string, reviewedBy: string, notes: string = ''): Promise<void> {
    const item = this.queue.get(id);
    if (!item) {
      throw new Error(`Review item not found: ${id}`);
    }

    if (item.status !== 'PENDING') {
      throw new Error(`Review item already processed: ${item.status}`);
    }

    item.reviewedBy = reviewedBy;
    item.reviewedAt = new Date();
    item.approved = true;
    item.status = 'APPROVED';
    item.notes = notes;

    await this.saveQueue();
    this.logSecurityEvent('REVIEW_APPROVED', item);

    console.log(`✅ Review ${id} approved by ${reviewedBy}`);
  }

  /**
   * Reject review item
   */
  async reject(id: string, reviewedBy: string, notes: string): Promise<void> {
    const item = this.queue.get(id);
    if (!item) {
      throw new Error(`Review item not found: ${id}`);
    }

    if (item.status !== 'PENDING') {
      throw new Error(`Review item already processed: ${item.status}`);
    }

    item.reviewedBy = reviewedBy;
    item.reviewedAt = new Date();
    item.approved = false;
    item.status = 'REJECTED';
    item.notes = notes;

    await this.saveQueue();
    this.logSecurityEvent('REVIEW_REJECTED', item);

    console.log(`❌ Review ${id} rejected by ${reviewedBy}: ${notes}`);
  }

  /**
   * Get review statistics
   */
  getStatistics(): {
    total: number;
    pending: number;
    approved: number;
    rejected: number;
  } {
    const items = Array.from(this.queue.values());
    return {
      total: items.length,
      pending: items.filter(i => i.status === 'PENDING').length,
      approved: items.filter(i => i.status === 'APPROVED').length,
      rejected: items.filter(i => i.status === 'REJECTED').length
    };
  }

  /**
   * Clear old review items (keep last 100)
   */
  async cleanupOldReviews(): Promise<void> {
    const items = Array.from(this.queue.values())
      .sort((a, b) => b.flaggedAt.getTime() - a.flaggedAt.getTime());

    // Keep only last 100 items
    const toKeep = items.slice(0, 100);
    const toRemove = items.slice(100);

    this.queue.clear();
    for (const item of toKeep) {
      this.queue.set(item.id, item);
    }

    await this.saveQueue();

    if (toRemove.length > 0) {
      console.log(`🗑️  Cleaned up ${toRemove.length} old review items`);
    }
  }

  /**
   * Generate unique ID for review item
   */
  private generateId(): string {
    return `review-${Date.now()}-${Math.random().toString(36).substring(7)}`;
  }

  /**
   * Load queue from disk
   */
  private loadQueue(): void {
    try {
      if (fs.existsSync(this.queuePath)) {
        const data = fs.readFileSync(this.queuePath, 'utf8');
        const items = JSON.parse(data);

        this.queue.clear();
        for (const item of items) {
          // Convert date strings back to Date objects
          item.flaggedAt = new Date(item.flaggedAt);
          if (item.reviewedAt) {
            item.reviewedAt = new Date(item.reviewedAt);
          }
          this.queue.set(item.id, item);
        }
      }
    } catch (error) {
      console.error('Failed to load review queue:', error);
    }
  }

  /**
   * Save queue to disk
   */
  private async saveQueue(): Promise<void> {
    try {
      const dir = path.dirname(this.queuePath);
      if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir, { recursive: true });
      }

      const items = Array.from(this.queue.values());
      fs.writeFileSync(
        this.queuePath,
        JSON.stringify(items, null, 2),
        'utf8'
      );
    } catch (error) {
      console.error('Failed to save review queue:', error);
    }
  }

  /**
   * Log security event
   */
  private logSecurityEvent(eventType: string, reviewItem: ReviewItem): void {
    const logEntry = {
      timestamp: new Date().toISOString(),
      eventType,
      reviewId: reviewItem.id,
      reason: reviewItem.reason,
      securityIssues: reviewItem.securityIssues,
      status: reviewItem.status,
      reviewedBy: reviewItem.reviewedBy
    };

    // In production, send to proper logging system (Datadog, Splunk, etc.)
    const logPath = path.join(__dirname, '../../logs/security-events.log');
    const logDir = path.dirname(logPath);

    if (!fs.existsSync(logDir)) {
      fs.mkdirSync(logDir, { recursive: true });
    }

    fs.appendFileSync(
      logPath,
      JSON.stringify(logEntry) + '\n',
      'utf8'
    );
  }
}

export default new ReviewQueue();
