/**
 * Role-Based Access Control (RBAC) Service
 *
 * Implements authorization checks for DevRel integration:
 * - Approval permissions (who can approve summaries)
 * - Publishing permissions (who can publish to public blog)
 * - Role-based checks via Discord roles
 * - Explicit user ID whitelist
 *
 * This implements CRITICAL-003 remediation.
 */

import { Client, GuildMember } from 'discord.js';
import { logger, auditLog } from '../utils/logger';
import fs from 'fs';
import path from 'path';
import yaml from 'js-yaml';

export interface RBACConfig {
  review_workflow: {
    require_approval: boolean;
    reviewers: string[];  // Discord user IDs
    approval_roles: string[];  // Discord role names
    require_multi_approval_for: string[];
    minimum_approvals: number;
  };
  distribution: {
    blog: {
      enabled: boolean;
      auto_publish: boolean;
      authorized_publishers: string[];  // Discord user IDs
      require_security_review: boolean;
      require_legal_review: boolean;
    };
  };
}

export class RBAC {
  private config: RBACConfig | null = null;
  private configPath: string;
  private discordClient: Client | null = null;

  constructor() {
    this.configPath = path.join(__dirname, '../../config/rbac-config.yaml');
  }

  /**
   * Initialize RBAC with Discord client
   */
  initialize(client: Client): void {
    this.discordClient = client;
    this.loadConfig();
    logger.info('RBAC service initialized');
  }

  /**
   * Load RBAC configuration from YAML file
   */
  private loadConfig(): void {
    try {
      if (fs.existsSync(this.configPath)) {
        const fileContents = fs.readFileSync(this.configPath, 'utf8');
        this.config = yaml.load(fileContents) as RBACConfig;
        logger.info('RBAC configuration loaded', {
          reviewers: this.config.review_workflow.reviewers.length,
          approvalRoles: this.config.review_workflow.approval_roles.length,
          publishers: this.config.distribution.blog.authorized_publishers.length
        });
      } else {
        logger.warn('RBAC config file not found, using defaults');
        this.config = this.getDefaultConfig();
      }
    } catch (error) {
      logger.error('Failed to load RBAC config', { error: error instanceof Error ? error.message : String(error) });
      this.config = this.getDefaultConfig();
    }
  }

  /**
   * Get default RBAC configuration
   */
  private getDefaultConfig(): RBACConfig {
    return {
      review_workflow: {
        require_approval: true,
        reviewers: [],  // No default reviewers - must be configured
        approval_roles: ['product_manager', 'tech_lead', 'cto'],
        require_multi_approval_for: ['blog_publishing'],
        minimum_approvals: 2
      },
      distribution: {
        blog: {
          enabled: false,  // Disabled by default for security
          auto_publish: false,  // NEVER auto-publish
          authorized_publishers: [],  // Must be explicitly configured
          require_security_review: true,
          require_legal_review: true
        }
      }
    };
  }

  /**
   * Check if user has permission to approve summaries
   */
  async canApprove(userId: string, guildId?: string): Promise<boolean> {
    if (!this.config) {
      logger.error('RBAC config not loaded');
      return false;
    }

    // Check explicit reviewer list
    if (this.config.review_workflow.reviewers.includes(userId)) {
      logger.info('User authorized by explicit reviewer list', { userId });
      return true;
    }

    // Check Discord roles
    if (guildId && this.discordClient) {
      try {
        const guild = await this.discordClient.guilds.fetch(guildId);
        const member = await guild.members.fetch(userId);

        if (member) {
          const hasApprovalRole = this.hasApprovalRole(member);
          if (hasApprovalRole) {
            logger.info('User authorized by Discord role', {
              userId,
              roles: member.roles.cache.map(r => r.name)
            });
            return true;
          }
        }
      } catch (error) {
        logger.error('Failed to check Discord roles', {
          userId,
          guildId,
          error: error instanceof Error ? error.message : String(error)
        });
      }
    }

    logger.warn('User not authorized to approve', { userId, guildId });
    auditLog.permissionDenied(userId, 'unknown', 'approve_summary');
    return false;
  }

  /**
   * Check if guild member has approval role
   */
  private hasApprovalRole(member: GuildMember): boolean {
    if (!this.config) return false;

    const approvalRoles = this.config.review_workflow.approval_roles;

    return member.roles.cache.some(role => {
      const normalizedRoleName = role.name.toLowerCase().replace(/\s+/g, '_');
      return approvalRoles.includes(normalizedRoleName);
    });
  }

  /**
   * Check if user has permission to publish to public blog
   */
  async canPublishBlog(userId: string): Promise<boolean> {
    if (!this.config) {
      logger.error('RBAC config not loaded');
      return false;
    }

    // Blog publishing disabled by default
    if (!this.config.distribution.blog.enabled) {
      logger.warn('Blog publishing is disabled in config');
      return false;
    }

    // Check authorized publishers list
    const authorized = this.config.distribution.blog.authorized_publishers.includes(userId);

    if (!authorized) {
      logger.warn('User not authorized to publish blog', { userId });
      auditLog.permissionDenied(userId, 'unknown', 'publish_blog');
    } else {
      logger.info('User authorized to publish blog', { userId });
    }

    return authorized;
  }

  /**
   * Check if action requires multi-approval
   */
  requiresMultiApproval(action: string): boolean {
    if (!this.config) return false;

    return this.config.review_workflow.require_multi_approval_for.includes(action);
  }

  /**
   * Get minimum number of approvals required
   */
  getMinimumApprovals(): number {
    return this.config?.review_workflow.minimum_approvals || 2;
  }

  /**
   * Check if approval workflow is enabled
   */
  isApprovalRequired(): boolean {
    return this.config?.review_workflow.require_approval ?? true;
  }

  /**
   * Get list of authorized reviewers (for display/debugging)
   */
  getAuthorizedReviewers(): string[] {
    return this.config?.review_workflow.reviewers || [];
  }

  /**
   * Get list of approval roles (for display/debugging)
   */
  getApprovalRoles(): string[] {
    return this.config?.review_workflow.approval_roles || [];
  }

  /**
   * Get list of authorized publishers (for display/debugging)
   */
  getAuthorizedPublishers(): string[] {
    return this.config?.distribution.blog.authorized_publishers || [];
  }

  /**
   * Reload configuration from disk
   */
  reloadConfig(): void {
    logger.info('Reloading RBAC configuration');
    this.loadConfig();
  }

  /**
   * Validate configuration (for startup checks)
   */
  validateConfig(): { valid: boolean; errors: string[] } {
    const errors: string[] = [];

    if (!this.config) {
      errors.push('Configuration not loaded');
      return { valid: false, errors };
    }

    // Warn if no reviewers configured
    if (this.config.review_workflow.reviewers.length === 0 &&
        this.config.review_workflow.approval_roles.length === 0) {
      errors.push('No reviewers or approval roles configured - approval workflow will not work');
    }

    // Warn if blog enabled but no publishers
    if (this.config.distribution.blog.enabled &&
        this.config.distribution.blog.authorized_publishers.length === 0) {
      errors.push('Blog publishing enabled but no authorized publishers configured');
    }

    // Warn if auto-publish enabled (dangerous)
    if (this.config.distribution.blog.auto_publish) {
      errors.push('WARNING: Blog auto-publish is enabled - this is a security risk');
    }

    return {
      valid: errors.length === 0,
      errors
    };
  }
}

export default new RBAC();
