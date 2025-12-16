/**
 * Role Verifier
 *
 * Implements HIGH-005: Database-first role verification for command execution.
 * Replaces Discord-only role checks with immutable database-backed authorization.
 *
 * Security Features:
 * - Database-first role verification (not just Discord roles)
 * - Complete audit logging of all authorization checks
 * - MFA requirement detection for sensitive operations
 * - Permission caching to reduce database load
 */

import { authDb } from '../database/db';
import { logger, auditLog } from '../utils/logger';
import userMappingService from './user-mapping-service';
import type { Permission } from '../middleware/auth';

export interface AuthorizationContext {
  command?: string;
  resource?: string;
  channelId?: string;
  guildId?: string;
  ipAddress?: string;
  userAgent?: string;
}

export interface AuthorizationResult {
  granted: boolean;
  denialReason?: string;
  requiredRole?: string;
  requiredPermission?: string;
  mfaRequired: boolean;
}

/**
 * Permission-to-role mapping
 */
const PERMISSION_ROLE_MAP: Record<Permission, string[]> = {
  // Public commands (everyone)
  'show-sprint': ['guest', 'researcher', 'developer', 'admin'],
  'preview': ['guest', 'researcher', 'developer', 'admin'],
  'doc': ['guest', 'researcher', 'developer', 'admin'],
  'task': ['guest', 'researcher', 'developer', 'admin'],
  'my-notifications': ['guest', 'researcher', 'developer', 'admin'],

  // Developer commands
  'implement': ['developer', 'admin'],
  'review-sprint': ['developer', 'admin'],
  'my-tasks': ['developer', 'admin'],
  'implement-status': ['developer', 'admin'],
  'feedback': ['researcher', 'developer', 'admin'],
  'feedback-capture': ['researcher', 'developer', 'admin'],

  // Linear issue commands
  'tag-issue': ['developer', 'admin'],
  'show-issue': ['guest', 'researcher', 'developer', 'admin'],
  'list-issues': ['guest', 'researcher', 'developer', 'admin'],

  // Admin commands
  'config': ['admin'],
  'manage-users': ['admin'],
  'manage-roles': ['admin'],
  '*': ['admin'],
};

/**
 * Operations requiring MFA
 */
const MFA_REQUIRED_OPERATIONS = new Set([
  'manage-roles',
  'config',
  'manage-users',
]);

/**
 * Permission cache (5 minute TTL)
 */
interface CacheEntry {
  permissions: Permission[];
  roles: string[];
  expiresAt: number;
}

const permissionCache = new Map<string, CacheEntry>();
const CACHE_TTL_MS = 5 * 60 * 1000; // 5 minutes

export class RoleVerifier {
  /**
   * Check if user has permission to perform action
   */
  async hasPermission(
    discordUserId: string,
    permission: Permission,
    context: AuthorizationContext = {}
  ): Promise<AuthorizationResult> {
    try {
      // Get user roles from database
      const roles = await this.getUserRoles(discordUserId);

      // Check if permission is granted by any of user's roles
      const requiredRoles = PERMISSION_ROLE_MAP[permission];
      if (!requiredRoles) {
        return this.denyWithAudit(
          discordUserId,
          permission,
          context,
          `Unknown permission: ${permission}`,
          undefined
        );
      }

      const hasRequiredRole = roles.some(role => requiredRoles.includes(role));

      if (!hasRequiredRole) {
        return this.denyWithAudit(
          discordUserId,
          permission,
          context,
          `User has roles [${roles.join(', ')}], requires one of [${requiredRoles.join(', ')}]`,
          requiredRoles[0]
        );
      }

      // Check if MFA is required
      const mfaRequired = MFA_REQUIRED_OPERATIONS.has(permission);

      // Log successful authorization
      await this.logAuthorization(
        discordUserId,
        permission,
        context,
        true,
        undefined,
        requiredRoles[0],
        mfaRequired
      );

      return {
        granted: true,
        requiredPermission: permission,
        mfaRequired
      };
    } catch (error) {
      logger.error('Error checking permission', {
        discordUserId,
        permission,
        error: error instanceof Error ? error.message : String(error)
      });

      return this.denyWithAudit(
        discordUserId,
        permission,
        context,
        `Internal error: ${error instanceof Error ? error.message : String(error)}`,
        undefined
      );
    }
  }

  /**
   * Check if user has any of the specified roles
   */
  async hasAnyRole(
    discordUserId: string,
    requiredRoles: string[],
    context: AuthorizationContext = {}
  ): Promise<AuthorizationResult> {
    try {
      const userRoles = await this.getUserRoles(discordUserId);
      const hasRole = userRoles.some(role => requiredRoles.includes(role));

      if (!hasRole) {
        return this.denyWithAudit(
          discordUserId,
          undefined,
          context,
          `User has roles [${userRoles.join(', ')}], requires one of [${requiredRoles.join(', ')}]`,
          requiredRoles[0]
        );
      }

      await this.logAuthorization(
        discordUserId,
        undefined,
        context,
        true,
        undefined,
        requiredRoles[0],
        false
      );

      return {
        granted: true,
        requiredRole: requiredRoles[0],
        mfaRequired: false
      };
    } catch (error) {
      logger.error('Error checking roles', {
        discordUserId,
        requiredRoles,
        error: error instanceof Error ? error.message : String(error)
      });

      return this.denyWithAudit(
        discordUserId,
        undefined,
        context,
        `Internal error: ${error instanceof Error ? error.message : String(error)}`,
        requiredRoles[0]
      );
    }
  }

  /**
   * Get user's roles from database (with caching)
   */
  private async getUserRoles(discordUserId: string): Promise<string[]> {
    const now = Date.now();

    // Check cache
    const cached = permissionCache.get(discordUserId);
    if (cached && cached.expiresAt > now) {
      return cached.roles;
    }

    // Fetch from database
    const roles = await userMappingService.getUserRoles(discordUserId);

    // Cache result
    permissionCache.set(discordUserId, {
      permissions: [], // Will be populated if needed
      roles,
      expiresAt: now + CACHE_TTL_MS
    });

    return roles;
  }

  /**
   * Get all permissions for user (with caching)
   */
  async getUserPermissions(discordUserId: string): Promise<Permission[]> {
    const now = Date.now();

    // Check cache
    const cached = permissionCache.get(discordUserId);
    if (cached && cached.expiresAt > now && cached.permissions.length > 0) {
      return cached.permissions;
    }

    // Fetch roles
    const roles = await this.getUserRoles(discordUserId);

    // Compute permissions from roles
    const permissions = new Set<Permission>();

    for (const [permission, requiredRoles] of Object.entries(PERMISSION_ROLE_MAP)) {
      if (roles.some(role => requiredRoles.includes(role))) {
        permissions.add(permission as Permission);
      }
    }

    const permissionArray = Array.from(permissions);

    // Update cache
    permissionCache.set(discordUserId, {
      permissions: permissionArray,
      roles,
      expiresAt: now + CACHE_TTL_MS
    });

    return permissionArray;
  }

  /**
   * Clear permission cache for user (call after role changes)
   */
  clearCache(discordUserId?: string): void {
    if (discordUserId) {
      permissionCache.delete(discordUserId);
      logger.debug('Permission cache cleared for user', { discordUserId });
    } else {
      permissionCache.clear();
      logger.debug('Permission cache cleared for all users');
    }
  }

  /**
   * Deny authorization and log to audit trail
   */
  private async denyWithAudit(
    discordUserId: string,
    permission: Permission | undefined,
    context: AuthorizationContext,
    reason: string,
    requiredRole: string | undefined
  ): Promise<AuthorizationResult> {
    await this.logAuthorization(
      discordUserId,
      permission,
      context,
      false,
      reason,
      requiredRole,
      false
    );

    return {
      granted: false,
      denialReason: reason,
      requiredRole,
      requiredPermission: permission,
      mfaRequired: false
    };
  }

  /**
   * Log authorization check to audit trail
   */
  private async logAuthorization(
    discordUserId: string,
    permission: Permission | undefined,
    context: AuthorizationContext,
    granted: boolean,
    denialReason: string | undefined,
    requiredRole: string | undefined,
    mfaRequired: boolean
  ): Promise<void> {
    try {
      const db = authDb.getConnection();
      const now = new Date().toISOString();

      // Get user
      const user = await userMappingService.getUserByDiscordId(discordUserId);

      await db.run(
        `INSERT INTO auth_audit_log (
          user_id, discord_user_id, discord_username, operation, resource,
          required_role, required_permission, granted, denial_reason,
          ip_address, user_agent, channel_id, guild_id, mfa_required, timestamp
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        user?.id || null,
        discordUserId,
        user?.discordUsername || 'unknown',
        context.command || 'unknown',
        context.resource || null,
        requiredRole || null,
        permission || null,
        granted ? 1 : 0,
        denialReason || null,
        context.ipAddress || null,
        context.userAgent || null,
        context.channelId || null,
        context.guildId || null,
        mfaRequired ? 1 : 0,
        now
      );

      // Also log to application audit log
      if (!granted) {
        auditLog.permissionDenied(
          discordUserId,
          user?.discordUsername || 'unknown',
          denialReason || 'Access denied'
        );
      }
    } catch (error) {
      logger.error('Failed to log authorization check', {
        discordUserId,
        permission,
        error: error instanceof Error ? error.message : String(error)
      });
    }
  }

  /**
   * Get authorization audit trail for user
   */
  async getAuditTrail(
    discordUserId: string,
    limit: number = 100
  ): Promise<Array<{
    timestamp: string;
    operation: string;
    granted: boolean;
    denialReason?: string;
  }>> {
    try {
      const db = authDb.getConnection();

      const rows = await db.all(
        `SELECT timestamp, operation, granted, denial_reason as denialReason
         FROM auth_audit_log
         WHERE discord_user_id = ?
         ORDER BY timestamp DESC
         LIMIT ?`,
        discordUserId,
        limit
      );

      return rows;
    } catch (error) {
      logger.error('Failed to fetch audit trail', {
        discordUserId,
        error: error instanceof Error ? error.message : String(error)
      });
      return [];
    }
  }

  /**
   * Get recent authorization denials (for security monitoring)
   */
  async getRecentDenials(limit: number = 50): Promise<Array<{
    timestamp: string;
    discordUserId: string;
    discordUsername: string;
    operation: string;
    denialReason: string;
  }>> {
    try {
      const db = authDb.getConnection();

      const rows = await db.all(
        `SELECT timestamp, discord_user_id as discordUserId,
                discord_username as discordUsername, operation, denial_reason as denialReason
         FROM auth_audit_log
         WHERE granted = 0 AND denial_reason IS NOT NULL
         ORDER BY timestamp DESC
         LIMIT ?`,
        limit
      );

      return rows;
    } catch (error) {
      logger.error('Failed to fetch recent denials', {
        error: error instanceof Error ? error.message : String(error)
      });
      return [];
    }
  }

  /**
   * Check if MFA is required for operation
   */
  isMfaRequired(permission: Permission): boolean {
    return MFA_REQUIRED_OPERATIONS.has(permission);
  }
}

export default new RoleVerifier();
