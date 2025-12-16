import { User, Guild, GuildMember, Client } from 'discord.js';
import { logger } from '../utils/logger';
import userMappingService from '../services/user-mapping-service';
import roleVerifier from '../services/role-verifier';

/**
 * Role-Based Access Control (RBAC)
 *
 * SECURITY FIXES:
 * - CRITICAL #4: Comprehensive RBAC implementation
 * - HIGH-005: Database-backed immutable user-role mappings
 * - Enforces permissions for all commands and actions
 * - Audits all privileged operations
 * - Prevents privilege escalation
 * - MFA verification for sensitive operations
 * - LOW-002: Extracted magic numbers to named constants
 */

/**
 * Rate limiting configuration constants
 * LOW-002: Extracted from inline magic numbers for better maintainability
 */
export const RATE_LIMITS = {
  COMMAND: { maxRequests: 5, windowMs: 60000 },
  FEEDBACK_CAPTURE: { maxRequests: 3, windowMs: 60000 },
  DOC_REQUEST: { maxRequests: 10, windowMs: 60000 },
  MY_TASKS: { maxRequests: 10, windowMs: 60000 },
  IMPLEMENT_STATUS: { maxRequests: 10, windowMs: 60000 },
} as const;

export enum UserRole {
  RESEARCHER = 'researcher',
  DEVELOPER = 'developer',
  ADMIN = 'admin',
  GUEST = 'guest',
}

export interface RoleConfig {
  discordRoleId: string;
  permissions: Permission[];
  description: string;
}

export type Permission =
  // Public commands (everyone)
  | 'show-sprint'
  | 'preview'
  | 'doc'
  | 'task'
  | 'my-notifications'
  // Developer commands
  | 'implement'
  | 'review-sprint'
  | 'my-tasks'
  | 'implement-status'
  | 'feedback'
  | 'feedback-capture' // 📌 reaction
  // Linear issue commands
  | 'tag-issue'
  | 'show-issue'
  | 'list-issues'
  // Admin commands
  | 'config'
  | 'manage-users'
  | 'manage-roles'
  | '*'; // All permissions

/**
 * Default role configuration
 * Override by setting environment variables or config file
 */
function getDefaultRoleConfig(): Record<UserRole, RoleConfig> {
  return {
    [UserRole.GUEST]: {
      discordRoleId: '@everyone', // Special: matches all users
      permissions: ['show-sprint', 'doc', 'task'],
      description: 'Basic read-only access',
    },
    [UserRole.RESEARCHER]: {
      discordRoleId: process.env['RESEARCHER_ROLE_ID'] || '',
      permissions: [
        'show-sprint',
        'preview',
        'doc',
        'task',
        'my-notifications',
      ],
      description: 'Can view and provide feedback',
    },
    [UserRole.DEVELOPER]: {
      discordRoleId: process.env['DEVELOPER_ROLE_ID'] || '',
      permissions: [
        'show-sprint',
        'preview',
        'doc',
        'task',
        'my-notifications',
        'implement',
        'review-sprint',
        'my-tasks',
        'implement-status',
        'feedback',
        'feedback-capture',
      ],
      description: 'Full development access',
    },
    [UserRole.ADMIN]: {
      discordRoleId: process.env['ADMIN_ROLE_ID'] || '',
      permissions: ['*'],
      description: 'Full administrative access',
    },
  };
}

/**
 * Get user roles from Discord guild member (DATABASE-FIRST with Discord fallback)
 *
 * HIGH-005 IMPLEMENTATION:
 * 1. Try to get roles from database (immutable audit trail)
 * 2. If user not in database, fetch from Discord and create user record
 * 3. Return roles as UserRole enum for backward compatibility
 */
export async function getUserRoles(user: User, guild: Guild): Promise<UserRole[]> {
  try {
    // Try database first
    const dbRoles = await userMappingService.getUserRoles(user.id);

    // If user has database roles (other than just guest), use them
    if (dbRoles.length > 1 || !dbRoles.includes('guest')) {
      return dbRoles.map(role => role as UserRole);
    }

    // User not in database or only has guest role - check Discord and create user
    const member = await guild.members.fetch(user.id);
    const discordRoles = getUserRolesFromMember(member);

    // Create user in database (auto-grants guest role)
    await userMappingService.getOrCreateUser(user.id, user.tag);

    logger.info('User auto-created from Discord interaction', {
      userId: user.id,
      username: user.tag,
      discordRoles
    });

    // Return Discord roles for this session
    // User must request role grants through approval workflow for database roles
    return discordRoles;
  } catch (error) {
    logger.error(`Error fetching roles for user ${user.id}:`, error);
    return [UserRole.GUEST]; // Default to guest on error
  }
}

/**
 * Get user roles from guild member
 */
export function getUserRolesFromMember(member: GuildMember): UserRole[] {
  const roleConfig = getDefaultRoleConfig();
  const userRoles: UserRole[] = [];

  // Check each role
  for (const [role, config] of Object.entries(roleConfig)) {
    if (!config.discordRoleId) {
      continue;
    }

    // Special case: @everyone
    if (config.discordRoleId === '@everyone') {
      if (role === UserRole.GUEST) {
        // Guest role is implicit for all users
        continue;
      }
    }

    // Check if user has this Discord role
    if (member.roles.cache.has(config.discordRoleId)) {
      userRoles.push(role as UserRole);
    }
  }

  // If no roles assigned, user is a guest
  if (userRoles.length === 0) {
    userRoles.push(UserRole.GUEST);
  }

  return userRoles;
}

/**
 * Check if user has specific permission
 */
export async function hasPermission(
  user: User,
  guild: Guild,
  permission: Permission
): Promise<boolean> {
  const userRoles = await getUserRoles(user, guild);
  return hasPermissionForRoles(userRoles, permission);
}

/**
 * Check if member has specific permission
 */
export function hasPermissionForMember(
  member: GuildMember,
  permission: Permission
): boolean {
  const userRoles = getUserRolesFromMember(member);
  return hasPermissionForRoles(userRoles, permission);
}

/**
 * Check if roles grant permission
 */
function hasPermissionForRoles(roles: UserRole[], permission: Permission): boolean {
  const roleConfig = getDefaultRoleConfig();

  for (const role of roles) {
    const config = roleConfig[role];
    if (!config) continue;

    // Admin has all permissions
    if (config.permissions.includes('*')) {
      return true;
    }

    // Check specific permission
    if (config.permissions.includes(permission)) {
      return true;
    }
  }

  return false;
}

/**
 * Get all permissions for user
 */
export async function getUserPermissions(user: User, guild: Guild): Promise<Permission[]> {
  const userRoles = await getUserRoles(user, guild);
  const roleConfig = getDefaultRoleConfig();
  const permissions = new Set<Permission>();

  for (const role of userRoles) {
    const config = roleConfig[role];
    if (!config) continue;

    if (config.permissions.includes('*')) {
      // Admin has all permissions
      return ['*'];
    }

    for (const permission of config.permissions) {
      permissions.add(permission);
    }
  }

  return Array.from(permissions);
}

/**
 * Audit log for permission checks
 */
export interface PermissionAudit {
  userId: string;
  username: string;
  permission: Permission;
  granted: boolean;
  roles: UserRole[];
  timestamp: Date;
  guildId: string;
}

/**
 * Check permission with audit logging (DATABASE-FIRST with MFA awareness)
 *
 * HIGH-005 IMPLEMENTATION:
 * Uses roleVerifier service for database-backed permission checks
 * with complete audit logging and MFA requirement detection
 */
export async function checkPermissionWithAudit(
  user: User,
  guild: Guild,
  permission: Permission
): Promise<{ granted: boolean; audit: PermissionAudit; mfaRequired: boolean }> {
  // Use roleVerifier service for database-backed permission check
  const result = await roleVerifier.hasPermission(user.id, permission, {
    command: permission,
    guildId: guild.id,
  });

  // Get user roles for audit record (for backward compatibility)
  const userRoles = await getUserRoles(user, guild);

  const audit: PermissionAudit = {
    userId: user.id,
    username: user.tag,
    permission,
    granted: result.granted,
    roles: userRoles,
    timestamp: new Date(),
    guildId: guild.id,
  };

  // Additional logging (roleVerifier already logs to database)
  if (!result.granted) {
    logger.warn('Permission denied', {
      userId: user.id,
      username: user.tag,
      permission,
      roles: userRoles,
      denialReason: result.denialReason,
    });
  }

  return { granted: result.granted, audit, mfaRequired: result.mfaRequired };
}

/**
 * Require permission (throws if denied or MFA needed)
 *
 * HIGH-005 IMPLEMENTATION:
 * Throws MfaRequiredError if operation requires MFA verification
 */
export async function requirePermission(
  user: User,
  guild: Guild | null,
  permission: Permission
): Promise<void> {
  if (!guild) {
    throw new PermissionError('Commands must be used in a server channel', permission);
  }

  const { granted, mfaRequired } = await checkPermissionWithAudit(user, guild, permission);

  if (!granted) {
    throw new PermissionError(
      `You don't have permission to use this feature. Required: ${permission}`,
      permission
    );
  }

  if (mfaRequired) {
    throw new MfaRequiredError(
      `This operation requires MFA verification. Please verify with /mfa-verify <code>`,
      permission
    );
  }
}

/**
 * Permission error
 */
export class PermissionError extends Error {
  constructor(message: string, public permission: Permission) {
    super(message);
    this.name = 'PermissionError';
  }
}

/**
 * MFA Required error (HIGH-005)
 */
export class MfaRequiredError extends Error {
  constructor(message: string, public permission: Permission) {
    super(message);
    this.name = 'MfaRequiredError';
  }
}

/**
 * Setup roles check (validates configuration)
 *
 * SECURITY FIX (HIGH-004): Validate actual Discord roles and fail startup if missing
 */
export async function validateRoleConfiguration(client: Client): Promise<void> {
  const roleConfig = getDefaultRoleConfig();
  const errors: string[] = [];

  // Get guild
  const guildId = process.env['DISCORD_GUILD_ID'];
  if (!guildId) {
    throw new Error('DISCORD_GUILD_ID not configured');
  }

  const guild = client.guilds.cache.get(guildId);
  if (!guild) {
    throw new Error(`Guild ${guildId} not found in bot cache`);
  }

  // Check that essential roles exist in Discord
  const essentialRoles = [UserRole.DEVELOPER, UserRole.ADMIN];

  for (const role of essentialRoles) {
    const config = roleConfig[role];

    // Check if env var is set
    if (!config.discordRoleId || config.discordRoleId === '') {
      errors.push(`${role} role ID not configured (set ${role.toUpperCase()}_ROLE_ID env var)`);
      continue;
    }

    // Check if role exists in guild
    const discordRole = guild.roles.cache.get(config.discordRoleId);
    if (!discordRole) {
      errors.push(`${role} role with ID '${config.discordRoleId}' not found in guild ${guild.name}`);
    }
  }

  // Warn about optional roles
  if (!roleConfig[UserRole.RESEARCHER].discordRoleId) {
    logger.warn('Researcher role not configured - all users will need developer role');
  } else {
    // Check if optional researcher role exists
    const researcherRole = guild.roles.cache.get(roleConfig[UserRole.RESEARCHER].discordRoleId);
    if (!researcherRole) {
      logger.warn(`Researcher role with ID '${roleConfig[UserRole.RESEARCHER].discordRoleId}' not found in guild`);
    }
  }

  // CRITICAL: Throw on any errors (fail startup)
  if (errors.length > 0) {
    logger.error('❌ Role configuration validation failed:');
    errors.forEach(err => logger.error(`  - ${err}`));
    throw new Error(`Role validation failed: ${errors.length} error(s). Bot cannot start without required roles.`);
  }

  logger.info('✅ Role configuration validated successfully');
}

/**
 * Get user's highest role (for display purposes)
 */
export async function getPrimaryRole(user: User, guild: Guild): Promise<UserRole> {
  const roles = await getUserRoles(user, guild);

  // Priority order: admin > developer > researcher > guest
  if (roles.includes(UserRole.ADMIN)) return UserRole.ADMIN;
  if (roles.includes(UserRole.DEVELOPER)) return UserRole.DEVELOPER;
  if (roles.includes(UserRole.RESEARCHER)) return UserRole.RESEARCHER;
  return UserRole.GUEST;
}

/**
 * Check if user can modify another user's data
 */
export async function canModifyUser(
  actor: User,
  guild: Guild,
  targetUserId: string
): Promise<boolean> {
  // Users can always modify their own data
  if (actor.id === targetUserId) {
    return true;
  }

  // Admins can modify anyone's data
  const actorRoles = await getUserRoles(actor, guild);
  return actorRoles.includes(UserRole.ADMIN);
}

/**
 * Rate limit check per user
 */
interface RateLimitConfig {
  maxRequests: number;
  windowMs: number;
}

const rateLimitCache = new Map<string, { count: number; resetAt: number }>();

export function checkRateLimit(
  userId: string,
  action: string,
  config: RateLimitConfig = RATE_LIMITS.COMMAND
): { allowed: boolean; remaining: number; resetAt: number } {
  const key = `${action}:${userId}`;
  const now = Date.now();

  let record = rateLimitCache.get(key);

  // Reset if window expired
  if (!record || now >= record.resetAt) {
    record = {
      count: 0,
      resetAt: now + config.windowMs,
    };
    rateLimitCache.set(key, record);
  }

  // Check limit
  record.count++;
  const allowed = record.count <= config.maxRequests;
  const remaining = Math.max(0, config.maxRequests - record.count);

  return {
    allowed,
    remaining,
    resetAt: record.resetAt,
  };
}

/**
 * Clear rate limit for user (admin function)
 */
export function clearRateLimit(userId: string, action?: string): void {
  if (action) {
    rateLimitCache.delete(`${action}:${userId}`);
  } else {
    // Clear all rate limits for user
    for (const key of rateLimitCache.keys()) {
      if (key.endsWith(`:${userId}`)) {
        rateLimitCache.delete(key);
      }
    }
  }
}

/**
 * Cleanup expired rate limits (run periodically)
 */
export function cleanupRateLimits(): void {
  const now = Date.now();
  let cleaned = 0;

  for (const [key, record] of rateLimitCache.entries()) {
    if (now >= record.resetAt) {
      rateLimitCache.delete(key);
      cleaned++;
    }
  }

  if (cleaned > 0) {
    logger.debug(`Cleaned up ${cleaned} expired rate limit records`);
  }
}

// Cleanup rate limits every 5 minutes
setInterval(cleanupRateLimits, 5 * 60 * 1000);
