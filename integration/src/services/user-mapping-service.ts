/**
 * User Mapping Service
 *
 * Implements HIGH-005: Immutable user-to-role mappings with database backend.
 * Provides CRUD operations for users, roles, and approval workflows.
 *
 * Security Features:
 * - Immutable role audit trail (never update/delete user_roles)
 * - Admin approval workflow for sensitive role grants
 * - Complete authorization audit logging
 * - Department/team-based access control
 */

import { authDb } from '../database/db';
import { logger, auditLog } from '../utils/logger';

export interface User {
  id: number;
  discordUserId: string;
  discordUsername: string;
  discordDiscriminator?: string;
  linearUserId?: string;
  linearEmail?: string;
  department?: string;
  team?: string;
  status: 'active' | 'suspended' | 'deactivated';
  firstSeenAt: string;
  lastSeenAt: string;
  createdAt: string;
  updatedAt: string;
}

export interface UserRole {
  id: number;
  userId: number;
  role: 'admin' | 'developer' | 'researcher' | 'guest';
  action: 'granted' | 'revoked';
  grantedByUserId?: number;
  grantedByDiscordId?: string;
  approvalId?: number;
  reason?: string;
  metadata?: string;
  effectiveAt: string;
  expiresAt?: string;
  createdAt: string;
}

export interface RoleApproval {
  id: number;
  requestedUserId: number;
  requestedRole: 'admin' | 'developer' | 'researcher';
  requestedDepartment?: string;
  requesterDiscordId: string;
  requesterUsername: string;
  status: 'pending' | 'approved' | 'rejected' | 'expired';
  approverUserId?: number;
  approverDiscordId?: string;
  approvalReason?: string;
  requestedAt: string;
  reviewedAt?: string;
  expiresAt: string;
}

export class UserMappingService {
  /**
   * Get or create user by Discord ID
   */
  async getOrCreateUser(discordUserId: string, discordUsername: string): Promise<User> {
    const db = authDb.getConnection();
    const now = new Date().toISOString();

    // Check if user exists
    let user = await db.get<User>(
      'SELECT * FROM users WHERE discord_user_id = ?',
      discordUserId
    );

    if (user) {
      // Update last seen timestamp
      await db.run(
        'UPDATE users SET last_seen_at = ?, updated_at = ? WHERE id = ?',
        now, now, user.id
      );
      user.lastSeenAt = now;
      user.updatedAt = now;
      return user;
    }

    // Create new user
    const result = await db.run(
      `INSERT INTO users (
        discord_user_id, discord_username, status,
        first_seen_at, last_seen_at, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?)`,
      discordUserId, discordUsername, 'active', now, now, now, now
    );

    user = await db.get<User>(
      'SELECT * FROM users WHERE id = ?',
      result.lastID
    );

    if (!user) {
      throw new Error('Failed to create user');
    }

    logger.info('New user created', {
      userId: user.id,
      discordUserId: user.discordUserId,
      discordUsername: user.discordUsername
    });

    // Grant default guest role
    await this.grantRoleInternal(
      user.id,
      'guest',
      undefined,
      'system',
      'Default role for new user'
    );

    return user;
  }

  /**
   * Get user by Discord ID
   */
  async getUserByDiscordId(discordUserId: string): Promise<User | null> {
    const db = authDb.getConnection();
    const user = await db.get<User>(
      'SELECT * FROM users WHERE discord_user_id = ?',
      discordUserId
    );
    return user || null;
  }

  /**
   * Get user by internal ID
   */
  async getUserById(userId: number): Promise<User | null> {
    const db = authDb.getConnection();
    const user = await db.get<User>(
      'SELECT * FROM users WHERE id = ?',
      userId
    );
    return user || null;
  }

  /**
   * Update user profile
   */
  async updateUser(
    userId: number,
    updates: Partial<Pick<User, 'department' | 'team' | 'linearUserId' | 'linearEmail' | 'status'>>
  ): Promise<void> {
    const db = authDb.getConnection();
    const now = new Date().toISOString();

    const fields: string[] = [];
    const values: any[] = [];

    if (updates.department !== undefined) {
      fields.push('department = ?');
      values.push(updates.department);
    }
    if (updates.team !== undefined) {
      fields.push('team = ?');
      values.push(updates.team);
    }
    if (updates.linearUserId !== undefined) {
      fields.push('linear_user_id = ?');
      values.push(updates.linearUserId);
    }
    if (updates.linearEmail !== undefined) {
      fields.push('linear_email = ?');
      values.push(updates.linearEmail);
    }
    if (updates.status !== undefined) {
      fields.push('status = ?');
      values.push(updates.status);
    }

    if (fields.length === 0) {
      return;
    }

    fields.push('updated_at = ?');
    values.push(now);
    values.push(userId);

    await db.run(
      `UPDATE users SET ${fields.join(', ')} WHERE id = ?`,
      ...values
    );

    logger.info('User updated', { userId, updates });
  }

  /**
   * Get user's currently active roles
   */
  async getUserRoles(discordUserId: string): Promise<string[]> {
    const db = authDb.getConnection();
    const now = new Date().toISOString();

    // Get user
    const user = await this.getUserByDiscordId(discordUserId);
    if (!user) {
      return ['guest']; // Default to guest for unknown users
    }

    // Query active roles using complex logic from schema
    const rows = await db.all<Array<{ role: string }>>(
      `SELECT DISTINCT ur.role
       FROM user_roles ur
       WHERE ur.user_id = ?
         AND ur.effective_at <= ?
         AND (ur.expires_at IS NULL OR ur.expires_at > ?)
         AND ur.action = 'granted'
         AND ur.role NOT IN (
           SELECT role FROM user_roles
           WHERE user_id = ur.user_id
             AND role = ur.role
             AND action = 'revoked'
             AND effective_at > ur.effective_at
         )`,
      user.id, now, now
    );

    const roles = rows.map(r => r.role);

    // Always include guest role
    if (!roles.includes('guest')) {
      roles.push('guest');
    }

    return roles;
  }

  /**
   * Request role grant (requires admin approval for non-guest roles)
   */
  async requestRoleGrant(request: {
    discordUserId: string;
    discordUsername: string;
    role: 'admin' | 'developer' | 'researcher';
    department?: string;
    reason: string;
  }): Promise<{ approvalId: number; status: 'pending' }> {
    const db = authDb.getConnection();
    const now = new Date().toISOString();
    const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString(); // 7 days

    // Get or create user
    const user = await this.getOrCreateUser(request.discordUserId, request.discordUsername);

    // Check if user already has this role
    const currentRoles = await this.getUserRoles(request.discordUserId);
    if (currentRoles.includes(request.role)) {
      throw new Error(`User already has role: ${request.role}`);
    }

    // Check for pending approval
    const pendingApproval = await db.get<RoleApproval>(
      `SELECT * FROM role_approvals
       WHERE requested_user_id = ?
         AND requested_role = ?
         AND status = 'pending'
         AND expires_at > ?`,
      user.id, request.role, now
    );

    if (pendingApproval) {
      return { approvalId: pendingApproval.id, status: 'pending' };
    }

    // Create approval request
    const result = await db.run(
      `INSERT INTO role_approvals (
        requested_user_id, requested_role, requested_department,
        requester_discord_id, requester_username, status,
        requested_at, expires_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
      user.id, request.role, request.department || null,
      request.discordUserId, request.discordUsername, 'pending',
      now, expiresAt
    );

    logger.info('Role approval requested', {
      approvalId: result.lastID,
      userId: user.id,
      discordUserId: request.discordUserId,
      role: request.role,
      reason: request.reason
    });

    auditLog.command(
      request.discordUserId,
      request.discordUsername,
      'role_request',
      [request.role, request.reason]
    );

    return { approvalId: result.lastID!, status: 'pending' };
  }

  /**
   * Approve role grant (admin only)
   */
  async approveRoleGrant(
    approvalId: number,
    approver: {
      discordUserId: string;
      discordUsername: string;
      reason: string;
    }
  ): Promise<void> {
    const db = authDb.getConnection();
    const now = new Date().toISOString();

    // Get approval
    const approval = await db.get<RoleApproval>(
      'SELECT * FROM role_approvals WHERE id = ?',
      approvalId
    );

    if (!approval) {
      throw new Error('Approval not found');
    }

    if (approval.status !== 'pending') {
      throw new Error(`Approval already ${approval.status}`);
    }

    if (approval.expiresAt < now) {
      // Mark as expired
      await db.run(
        'UPDATE role_approvals SET status = ? WHERE id = ?',
        'expired', approvalId
      );
      throw new Error('Approval request has expired');
    }

    // Get approver user
    const approverUser = await this.getUserByDiscordId(approver.discordUserId);
    if (!approverUser) {
      throw new Error('Approver not found');
    }

    // Verify approver has admin role
    const approverRoles = await this.getUserRoles(approver.discordUserId);
    if (!approverRoles.includes('admin')) {
      throw new Error('Only admins can approve role grants');
    }

    // Update approval
    await db.run(
      `UPDATE role_approvals
       SET status = ?, approver_user_id = ?, approver_discord_id = ?,
           approval_reason = ?, reviewed_at = ?
       WHERE id = ?`,
      'approved', approverUser.id, approver.discordUserId,
      approver.reason, now, approvalId
    );

    // Grant role
    await this.grantRoleInternal(
      approval.requestedUserId,
      approval.requestedRole,
      approverUser.id,
      approver.discordUserId,
      `Approved by admin: ${approver.reason}`,
      approvalId
    );

    logger.info('Role grant approved', {
      approvalId,
      userId: approval.requestedUserId,
      role: approval.requestedRole,
      approverUserId: approverUser.id,
      approverDiscordId: approver.discordUserId
    });

    auditLog.command(
      approver.discordUserId,
      approver.discordUsername,
      'role_approval',
      [String(approvalId), approval.requestedRole, approver.reason]
    );
  }

  /**
   * Reject role grant (admin only)
   */
  async rejectRoleGrant(
    approvalId: number,
    rejector: {
      discordUserId: string;
      discordUsername: string;
      reason: string;
    }
  ): Promise<void> {
    const db = authDb.getConnection();
    const now = new Date().toISOString();

    // Get approval
    const approval = await db.get<RoleApproval>(
      'SELECT * FROM role_approvals WHERE id = ?',
      approvalId
    );

    if (!approval) {
      throw new Error('Approval not found');
    }

    if (approval.status !== 'pending') {
      throw new Error(`Approval already ${approval.status}`);
    }

    // Get rejector user
    const rejectorUser = await this.getUserByDiscordId(rejector.discordUserId);
    if (!rejectorUser) {
      throw new Error('Rejector not found');
    }

    // Verify rejector has admin role
    const rejectorRoles = await this.getUserRoles(rejector.discordUserId);
    if (!rejectorRoles.includes('admin')) {
      throw new Error('Only admins can reject role grants');
    }

    // Update approval
    await db.run(
      `UPDATE role_approvals
       SET status = ?, approver_user_id = ?, approver_discord_id = ?,
           approval_reason = ?, reviewed_at = ?
       WHERE id = ?`,
      'rejected', rejectorUser.id, rejector.discordUserId,
      rejector.reason, now, approvalId
    );

    logger.info('Role grant rejected', {
      approvalId,
      userId: approval.requestedUserId,
      role: approval.requestedRole,
      rejectorUserId: rejectorUser.id,
      rejectorDiscordId: rejector.discordUserId,
      reason: rejector.reason
    });

    auditLog.permissionDenied(
      approval.requesterDiscordId,
      approval.requesterUsername,
      `Role request rejected: ${rejector.reason}`
    );
  }

  /**
   * Internal method to grant role (bypasses approval)
   */
  private async grantRoleInternal(
    userId: number,
    role: 'admin' | 'developer' | 'researcher' | 'guest',
    grantedByUserId: number | undefined,
    grantedByDiscordId: string,
    reason: string,
    approvalId?: number
  ): Promise<void> {
    const db = authDb.getConnection();
    const now = new Date().toISOString();

    await db.run(
      `INSERT INTO user_roles (
        user_id, role, action, granted_by_user_id, granted_by_discord_id,
        approval_id, reason, effective_at, created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      userId, role, 'granted', grantedByUserId || null, grantedByDiscordId,
      approvalId || null, reason, now, now
    );

    logger.info('Role granted', {
      userId,
      role,
      grantedByDiscordId,
      reason
    });
  }

  /**
   * Revoke role from user (admin only)
   */
  async revokeRole(
    discordUserId: string,
    role: 'admin' | 'developer' | 'researcher',
    revokedBy: {
      discordUserId: string;
      discordUsername: string;
      reason: string;
    }
  ): Promise<void> {
    const db = authDb.getConnection();
    const now = new Date().toISOString();

    // Get user
    const user = await this.getUserByDiscordId(discordUserId);
    if (!user) {
      throw new Error('User not found');
    }

    // Verify revoker has admin role
    const revokerRoles = await this.getUserRoles(revokedBy.discordUserId);
    if (!revokerRoles.includes('admin')) {
      throw new Error('Only admins can revoke roles');
    }

    // Check if user has this role
    const currentRoles = await this.getUserRoles(discordUserId);
    if (!currentRoles.includes(role)) {
      throw new Error(`User does not have role: ${role}`);
    }

    // Get revoker user
    const revokerUser = await this.getUserByDiscordId(revokedBy.discordUserId);

    // Revoke role (immutable audit trail)
    await db.run(
      `INSERT INTO user_roles (
        user_id, role, action, granted_by_user_id, granted_by_discord_id,
        reason, effective_at, created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
      user.id, role, 'revoked', revokerUser?.id || null, revokedBy.discordUserId,
      revokedBy.reason, now, now
    );

    logger.info('Role revoked', {
      userId: user.id,
      discordUserId,
      role,
      revokedByDiscordId: revokedBy.discordUserId,
      reason: revokedBy.reason
    });

    auditLog.command(
      revokedBy.discordUserId,
      revokedBy.discordUsername,
      'role_revocation',
      [discordUserId, role, revokedBy.reason]
    );
  }

  /**
   * Get pending role approvals
   */
  async getPendingApprovals(): Promise<RoleApproval[]> {
    const db = authDb.getConnection();
    const now = new Date().toISOString();

    const approvals = await db.all<RoleApproval[]>(
      `SELECT * FROM role_approvals
       WHERE status = 'pending' AND expires_at > ?
       ORDER BY requested_at ASC`,
      now
    );

    return approvals;
  }

  /**
   * Get role history for user (audit trail)
   */
  async getRoleHistory(discordUserId: string): Promise<UserRole[]> {
    const db = authDb.getConnection();

    const user = await this.getUserByDiscordId(discordUserId);
    if (!user) {
      return [];
    }

    const history = await db.all<UserRole[]>(
      `SELECT * FROM user_roles
       WHERE user_id = ?
       ORDER BY effective_at DESC`,
      user.id
    );

    return history;
  }

  /**
   * Expire old approval requests (run periodically)
   */
  async expireOldApprovals(): Promise<number> {
    const db = authDb.getConnection();
    const now = new Date().toISOString();

    const result = await db.run(
      `UPDATE role_approvals
       SET status = 'expired'
       WHERE status = 'pending' AND expires_at <= ?`,
      now
    );

    if (result.changes && result.changes > 0) {
      logger.info('Expired old approval requests', { count: result.changes });
    }

    return result.changes || 0;
  }
}

export default new UserMappingService();
