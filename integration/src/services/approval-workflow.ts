/**
 * Approval Workflow Service
 *
 * Manages approval state for DevRel translations:
 * - State machine (pending → approved → published)
 * - Multi-approval tracking
 * - Audit trail for all approvals
 * - Security alerts for blog publishing
 *
 * This implements CRITICAL-003 remediation.
 */

import { logger, auditLog } from '../utils/logger';
import fs from 'fs';
import path from 'path';

export enum ApprovalState {
  PENDING_REVIEW = 'pending_review',
  APPROVED = 'approved',
  REJECTED = 'rejected',
  PUBLISHED = 'published'
}

export interface Approval {
  summaryId: string;
  state: ApprovalState;
  approvedBy: string;  // Discord user ID
  approvedByUsername?: string;  // Discord username for display
  approvedAt: Date;
  notes?: string;
  metadata?: {
    ipAddress?: string;
    guildId?: string;
    channelId?: string;
    messageId?: string;
  };
}

export interface SummaryApprovalRecord {
  summaryId: string;
  currentState: ApprovalState;
  approvals: Approval[];
  createdAt: Date;
  updatedAt: Date;
  content?: string;  // Store summary content for review
  format?: string;
  audience?: string;
}

export class ApprovalWorkflow {
  private storageFile: string;
  private approvals: Map<string, SummaryApprovalRecord>;

  constructor() {
    this.storageFile = path.join(__dirname, '../../data/approvals.json');
    this.approvals = new Map();
    this.loadApprovals();
  }

  /**
   * Load approvals from disk
   */
  private loadApprovals(): void {
    try {
      if (fs.existsSync(this.storageFile)) {
        const data = fs.readFileSync(this.storageFile, 'utf8');
        const parsed = JSON.parse(data);

        for (const [id, record] of Object.entries(parsed)) {
          const typedRecord = record as SummaryApprovalRecord;
          // Convert date strings back to Date objects
          typedRecord.createdAt = new Date(typedRecord.createdAt);
          typedRecord.updatedAt = new Date(typedRecord.updatedAt);
          typedRecord.approvals = typedRecord.approvals.map(a => ({
            ...a,
            approvedAt: new Date(a.approvedAt)
          }));
          this.approvals.set(id, typedRecord);
        }

        logger.info('Approval records loaded', { count: this.approvals.size });
      }
    } catch (error) {
      logger.error('Failed to load approval records', { error: error.message });
    }
  }

  /**
   * Save approvals to disk
   */
  private async saveApprovals(): Promise<void> {
    try {
      // Ensure directory exists
      const dir = path.dirname(this.storageFile);
      if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir, { recursive: true });
      }

      const data = JSON.stringify(Object.fromEntries(this.approvals), null, 2);
      fs.writeFileSync(this.storageFile, data, 'utf8');
    } catch (error) {
      logger.error('Failed to save approval records', { error: error.message });
      throw error;
    }
  }

  /**
   * Create new approval record for a summary
   */
  async createApprovalRecord(
    summaryId: string,
    content: string,
    format: string,
    audience: string
  ): Promise<void> {
    const record: SummaryApprovalRecord = {
      summaryId,
      currentState: ApprovalState.PENDING_REVIEW,
      approvals: [],
      createdAt: new Date(),
      updatedAt: new Date(),
      content,
      format,
      audience
    };

    this.approvals.set(summaryId, record);
    await this.saveApprovals();

    logger.info('Approval record created', { summaryId, format, audience });
  }

  /**
   * Track approval for a summary
   */
  async trackApproval(
    summaryId: string,
    state: ApprovalState,
    userId: string,
    username?: string,
    notes?: string,
    metadata?: Approval['metadata']
  ): Promise<void> {
    const approval: Approval = {
      summaryId,
      state,
      approvedBy: userId,
      approvedByUsername: username,
      approvedAt: new Date(),
      notes,
      metadata
    };

    // Get or create record
    let record = this.approvals.get(summaryId);
    if (!record) {
      record = {
        summaryId,
        currentState: ApprovalState.PENDING_REVIEW,
        approvals: [],
        createdAt: new Date(),
        updatedAt: new Date()
      };
      this.approvals.set(summaryId, record);
    }

    // Add approval to list
    record.approvals.push(approval);
    record.currentState = state;
    record.updatedAt = new Date();

    await this.saveApprovals();

    // Log to audit trail
    auditLog.command(userId, username || 'unknown', 'approve_summary', {
      summaryId,
      state,
      notes
    });

    logger.info('Approval tracked', {
      summaryId,
      state,
      userId,
      username,
      totalApprovals: record.approvals.length
    });

    // Alert security team for blog publish approvals
    if (state === ApprovalState.PUBLISHED) {
      await this.alertSecurityTeam(approval);
    }
  }

  /**
   * Get current approval state for a summary
   */
  getState(summaryId: string): ApprovalState | null {
    const record = this.approvals.get(summaryId);
    return record?.currentState || null;
  }

  /**
   * Get approval record for a summary
   */
  getRecord(summaryId: string): SummaryApprovalRecord | null {
    return this.approvals.get(summaryId) || null;
  }

  /**
   * Get all approvals for a summary
   */
  getApprovals(summaryId: string): Approval[] {
    const record = this.approvals.get(summaryId);
    return record?.approvals || [];
  }

  /**
   * Check if summary has minimum required approvals
   */
  async hasMinimumApprovals(summaryId: string, minimumCount: number): Promise<boolean> {
    const approvals = this.getApprovals(summaryId);

    // Filter to only APPROVED state
    const approvedApprovals = approvals.filter(a => a.state === ApprovalState.APPROVED);

    // Get unique approvers (prevent same user approving multiple times)
    const uniqueApprovers = new Set(approvedApprovals.map(a => a.approvedBy));

    const hasMinimum = uniqueApprovers.size >= minimumCount;

    logger.info('Checking minimum approvals', {
      summaryId,
      required: minimumCount,
      current: uniqueApprovers.size,
      hasMinimum
    });

    return hasMinimum;
  }

  /**
   * Check if user has already approved this summary
   */
  hasUserApproved(summaryId: string, userId: string): boolean {
    const approvals = this.getApprovals(summaryId);
    return approvals.some(a =>
      a.approvedBy === userId &&
      a.state === ApprovalState.APPROVED
    );
  }

  /**
   * Get approval statistics
   */
  getStatistics(): {
    total: number;
    byState: Record<ApprovalState, number>;
    pendingReview: number;
    approved: number;
    rejected: number;
    published: number;
  } {
    const stats = {
      total: this.approvals.size,
      byState: {
        [ApprovalState.PENDING_REVIEW]: 0,
        [ApprovalState.APPROVED]: 0,
        [ApprovalState.REJECTED]: 0,
        [ApprovalState.PUBLISHED]: 0
      },
      pendingReview: 0,
      approved: 0,
      rejected: 0,
      published: 0
    };

    for (const record of this.approvals.values()) {
      stats.byState[record.currentState]++;

      switch (record.currentState) {
        case ApprovalState.PENDING_REVIEW:
          stats.pendingReview++;
          break;
        case ApprovalState.APPROVED:
          stats.approved++;
          break;
        case ApprovalState.REJECTED:
          stats.rejected++;
          break;
        case ApprovalState.PUBLISHED:
          stats.published++;
          break;
      }
    }

    return stats;
  }

  /**
   * Get pending approvals (for review queue UI)
   */
  getPendingApprovals(): SummaryApprovalRecord[] {
    const pending: SummaryApprovalRecord[] = [];

    for (const record of this.approvals.values()) {
      if (record.currentState === ApprovalState.PENDING_REVIEW) {
        pending.push(record);
      }
    }

    // Sort by creation date (oldest first)
    pending.sort((a, b) => a.createdAt.getTime() - b.createdAt.getTime());

    return pending;
  }

  /**
   * Cleanup old records (older than 90 days)
   */
  async cleanup(daysToKeep: number = 90): Promise<number> {
    const cutoffDate = new Date();
    cutoffDate.setDate(cutoffDate.getDate() - daysToKeep);

    let removedCount = 0;

    for (const [id, record] of this.approvals.entries()) {
      if (record.updatedAt < cutoffDate) {
        this.approvals.delete(id);
        removedCount++;
      }
    }

    if (removedCount > 0) {
      await this.saveApprovals();
      logger.info('Cleaned up old approval records', {
        removed: removedCount,
        cutoffDate: cutoffDate.toISOString()
      });
    }

    return removedCount;
  }

  /**
   * Alert security team about blog publishing
   */
  private async alertSecurityTeam(approval: Approval): Promise<void> {
    logger.warn('SECURITY ALERT: Blog publishing approval', {
      summaryId: approval.summaryId,
      approvedBy: approval.approvedBy,
      approvedByUsername: approval.approvedByUsername,
      approvedAt: approval.approvedAt,
      metadata: approval.metadata
    });

    // TODO: Integrate with alerting system (Discord DM, Slack, email, etc.)
    // For now, log to security events file
    const securityLogPath = path.join(__dirname, '../../logs/security-events.log');
    const logEntry = `[${new Date().toISOString()}] BLOG_PUBLISH_APPROVAL: Summary ${approval.summaryId} approved for publishing by ${approval.approvedByUsername} (${approval.approvedBy})\n`;

    try {
      fs.appendFileSync(securityLogPath, logEntry, 'utf8');
    } catch (error) {
      logger.error('Failed to write security alert', { error: error.message });
    }
  }
}

export default new ApprovalWorkflow();
