import { User, Guild, GuildMember, Client } from 'discord.js';
import { logger } from '../utils/logger';

/**
 * Role-Based Access Control (RBAC)
 *
 * SECURITY FIXES:
 * - CRITICAL #4: Comprehensive RBAC implementation
 * - Enforces permissions for all commands and actions
 * - Audits all privileged operations
 * - Prevents privilege escalation
 */

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
 * Get user roles from Discord guild member
 */
export async function getUserRoles(user: User, guild: Guild): Promise<UserRole[]> {
  try {
    const member = await guild.members.fetch(user.id);
    return getUserRolesFromMember(member);
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
 * Check permission with audit logging
 */
export async function checkPermissionWithAudit(
  user: User,
  guild: Guild,
  permission: Permission
): Promise<{ granted: boolean; audit: PermissionAudit }> {
  const userRoles = await getUserRoles(user, guild);
  const granted = hasPermissionForRoles(userRoles, permission);

  const audit: PermissionAudit = {
    userId: user.id,
    username: user.tag,
    permission,
    granted,
    roles: userRoles,
    timestamp: new Date(),
    guildId: guild.id,
  };

  // Log permission check
  if (!granted) {
    logger.warn('Permission denied', {
      userId: user.id,
      username: user.tag,
      permission,
      roles: userRoles,
    });
  }

  return { granted, audit };
}

/**
 * Require permission (throws if denied)
 */
export async function requirePermission(
  user: User,
  guild: Guild | null,
  permission: Permission
): Promise<void> {
  if (!guild) {
    throw new PermissionError('Commands must be used in a server channel', permission);
  }

  const { granted } = await checkPermissionWithAudit(user, guild, permission);

  if (!granted) {
    throw new PermissionError(
      `You don't have permission to use this feature. Required: ${permission}`,
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
  config: RateLimitConfig = { maxRequests: 5, windowMs: 60000 }
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
