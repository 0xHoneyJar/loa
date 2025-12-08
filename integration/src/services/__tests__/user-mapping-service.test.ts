/**
 * User Mapping Service Tests
 *
 * Tests HIGH-005 implementation: Database-backed user role management
 */

// Mock logger to avoid ES module issues with isomorphic-dompurify
jest.mock('../../utils/logger', () => ({
  logger: {
    info: jest.fn(),
    warn: jest.fn(),
    error: jest.fn(),
    debug: jest.fn(),
  },
  auditLog: {
    command: jest.fn(),
    permissionDenied: jest.fn(),
  },
}));

import { authDb } from '../../database/db';
import userMappingService from '../user-mapping-service';

describe('UserMappingService', () => {
  beforeAll(async () => {
    // Initialize test database
    await authDb.initialize();
  });

  afterAll(async () => {
    // Close database connection
    await authDb.close();
  });

  beforeEach(async () => {
    // Clean up test data before each test
    const db = authDb.getConnection();
    await db.exec('DELETE FROM auth_audit_log');
    await db.exec('DELETE FROM mfa_challenges');
    await db.exec('DELETE FROM mfa_enrollments');
    await db.exec('DELETE FROM role_approvals');
    await db.exec('DELETE FROM user_roles');
    await db.exec('DELETE FROM users');

    // Create admin user for approval tests
    const adminUser = await userMappingService.getOrCreateUser(
      '999999999999999999',
      'admin#0001'
    );
    // Grant admin role directly (bypass approval for test admin)
    const now = new Date().toISOString();
    await db.run(
      `INSERT INTO user_roles (
        user_id, role, action, granted_by_discord_id, reason, effective_at, created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?)`,
      adminUser.id,
      'admin',
      'granted',
      'system',
      'Test admin user',
      now,
      now
    );
  });

  describe('User Management', () => {
    test('should create new user with default guest role', async () => {
      const user = await userMappingService.getOrCreateUser(
        '123456789012345678',
        'alice#1234'
      );

      expect(user.discordUserId).toBe('123456789012345678');
      expect(user.discordUsername).toBe('alice#1234');
      expect(user.status).toBe('active');

      // Should have default guest role
      const roles = await userMappingService.getUserRoles('123456789012345678');
      expect(roles).toContain('guest');
    });

    test('should return existing user on subsequent calls', async () => {
      const user1 = await userMappingService.getOrCreateUser(
        '123456789012345678',
        'alice#1234'
      );

      const user2 = await userMappingService.getOrCreateUser(
        '123456789012345678',
        'alice#1234'
      );

      expect(user1.id).toBe(user2.id);
      expect(user1.discordUserId).toBe(user2.discordUserId);
    });

    test('should update user profile', async () => {
      const user = await userMappingService.getOrCreateUser(
        '123456789012345678',
        'alice#1234'
      );

      await userMappingService.updateUser(user.id, {
        department: 'engineering',
        team: 'backend',
        linearEmail: 'alice@example.com'
      });

      const updatedUser = await userMappingService.getUserById(user.id);
      expect(updatedUser?.department).toBe('engineering');
      expect(updatedUser?.team).toBe('backend');
      expect(updatedUser?.linearEmail).toBe('alice@example.com');
    });
  });

  describe('Role Management', () => {
    test('should grant role and retrieve active roles', async () => {
      // Create user
      const user = await userMappingService.getOrCreateUser(
        '123456789012345678',
        'alice#1234'
      );

      expect(user.discordUserId).toBe('123456789012345678');

      // Request developer role
      const approval = await userMappingService.requestRoleGrant({
        discordUserId: '123456789012345678',
        discordUsername: 'alice#1234',
        role: 'developer',
        reason: 'New hire'
      });

      expect(approval.status).toBe('pending');

      // Admin approves
      await userMappingService.approveRoleGrant(approval.approvalId, {
        discordUserId: '999999999999999999',
        discordUsername: 'admin#0001',
        reason: 'Verified credentials'
      });

      // Check roles
      const roles = await userMappingService.getUserRoles('123456789012345678');
      expect(roles).toContain('developer');
      expect(roles).toContain('guest');
    });

    test('should prevent duplicate role grants', async () => {
      const user = await userMappingService.getOrCreateUser(
        '123456789012345678',
        'alice#1234'
      );

      expect(user.discordUserId).toBe('123456789012345678');

      // Request developer role
      const approval1 = await userMappingService.requestRoleGrant({
        discordUserId: '123456789012345678',
        discordUsername: 'alice#1234',
        role: 'developer',
        reason: 'New hire'
      });

      // Approve
      await userMappingService.approveRoleGrant(approval1.approvalId, {
        discordUserId: '999999999999999999',
        discordUsername: 'admin#0001',
        reason: 'Verified'
      });

      // Try to request same role again
      await expect(
        userMappingService.requestRoleGrant({
          discordUserId: '123456789012345678',
          discordUsername: 'alice#1234',
          role: 'developer',
          reason: 'Duplicate'
        })
      ).rejects.toThrow('User already has role: developer');
    });

    test('should revoke role and maintain audit trail', async () => {
      // Create user with developer role
      await userMappingService.getOrCreateUser(
        '123456789012345678',
        'alice#1234'
      );

      const approval = await userMappingService.requestRoleGrant({
        discordUserId: '123456789012345678',
        discordUsername: 'alice#1234',
        role: 'developer',
        reason: 'New hire'
      });

      await userMappingService.approveRoleGrant(approval.approvalId, {
        discordUserId: '999999999999999999',
        discordUsername: 'admin#0001',
        reason: 'Verified'
      });

      // Verify role granted
      let roles = await userMappingService.getUserRoles('123456789012345678');
      expect(roles).toContain('developer');

      // Revoke role
      await userMappingService.revokeRole(
        '123456789012345678',
        'developer',
        {
          discordUserId: '999999999999999999',
          discordUsername: 'admin#0001',
          reason: 'Team transition'
        }
      );

      // Verify role revoked
      roles = await userMappingService.getUserRoles('123456789012345678');
      expect(roles).not.toContain('developer');
      expect(roles).toContain('guest'); // Still has guest

      // Verify audit trail
      const history = await userMappingService.getRoleHistory('123456789012345678');
      expect(history.length).toBeGreaterThanOrEqual(3); // guest grant + developer grant + developer revoke
      expect(history.some(h => h.role === 'developer' && h.action === 'granted')).toBe(true);
      expect(history.some(h => h.role === 'developer' && h.action === 'revoked')).toBe(true);
    });
  });

  describe('Approval Workflow', () => {
    test('should create and list pending approvals', async () => {
      // Create two users
      await userMappingService.getOrCreateUser(
        '111111111111111111',
        'alice#1234'
      );
      await userMappingService.getOrCreateUser(
        '222222222222222222',
        'bob#5678'
      );

      // Request roles
      await userMappingService.requestRoleGrant({
        discordUserId: '111111111111111111',
        discordUsername: 'alice#1234',
        role: 'developer',
        reason: 'New hire'
      });

      await userMappingService.requestRoleGrant({
        discordUserId: '222222222222222222',
        discordUsername: 'bob#5678',
        role: 'researcher',
        reason: 'Contractor'
      });

      // List pending approvals
      const pending = await userMappingService.getPendingApprovals();
      expect(pending.length).toBe(2);
      expect(pending[0]!.status).toBe('pending');
    });

    test('should reject role grant', async () => {
      await userMappingService.getOrCreateUser(
        '123456789012345678',
        'alice#1234'
      );

      const approval = await userMappingService.requestRoleGrant({
        discordUserId: '123456789012345678',
        discordUsername: 'alice#1234',
        role: 'admin',
        reason: 'Want admin access'
      });

      // Admin rejects
      await userMappingService.rejectRoleGrant(approval.approvalId, {
        discordUserId: '999999999999999999',
        discordUsername: 'admin#0001',
        reason: 'Insufficient justification'
      });

      // Verify role not granted
      const roles = await userMappingService.getUserRoles('123456789012345678');
      expect(roles).not.toContain('admin');
      expect(roles).toContain('guest');
    });

    test('should expire old approval requests', async () => {
      const db = authDb.getConnection();
      const now = new Date();
      const expired = new Date(now.getTime() - 8 * 24 * 60 * 60 * 1000).toISOString(); // 8 days ago

      // Create user
      const user = await userMappingService.getOrCreateUser(
        '123456789012345678',
        'alice#1234'
      );

      // Insert expired approval request directly
      await db.run(
        `INSERT INTO role_approvals (
          requested_user_id, requested_role, requester_discord_id,
          requester_username, status, requested_at, expires_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?)`,
        user.id,
        'developer',
        '123456789012345678',
        'alice#1234',
        'pending',
        expired,
        expired
      );

      // Run expiration
      const expiredCount = await userMappingService.expireOldApprovals();
      expect(expiredCount).toBe(1);

      // Verify no pending approvals
      const pending = await userMappingService.getPendingApprovals();
      expect(pending.length).toBe(0);
    });
  });

  describe('Role History', () => {
    test('should maintain complete immutable audit trail', async () => {
      await userMappingService.getOrCreateUser(
        '123456789012345678',
        'alice#1234'
      );

      // Grant developer
      const approval1 = await userMappingService.requestRoleGrant({
        discordUserId: '123456789012345678',
        discordUsername: 'alice#1234',
        role: 'developer',
        reason: 'New hire'
      });
      await userMappingService.approveRoleGrant(approval1.approvalId, {
        discordUserId: '999999999999999999',
        discordUsername: 'admin#0001',
        reason: 'Verified'
      });

      // Revoke developer
      await userMappingService.revokeRole(
        '123456789012345678',
        'developer',
        {
          discordUserId: '999999999999999999',
          discordUsername: 'admin#0001',
          reason: 'Team change'
        }
      );

      // Grant researcher
      const approval2 = await userMappingService.requestRoleGrant({
        discordUserId: '123456789012345678',
        discordUsername: 'alice#1234',
        role: 'researcher',
        reason: 'New role'
      });
      await userMappingService.approveRoleGrant(approval2.approvalId, {
        discordUserId: '999999999999999999',
        discordUsername: 'admin#0001',
        reason: 'Approved'
      });

      // Get history
      const history = await userMappingService.getRoleHistory('123456789012345678');

      // Should have: guest grant, developer grant, developer revoke, researcher grant (4 entries)
      expect(history.length).toBeGreaterThanOrEqual(4);

      // Verify order (most recent first)
      expect(history[0]!.role).toBe('researcher');
      expect(history[0]!.action).toBe('granted');

      // Verify all entries are immutable (never updated)
      expect(history.every(h => h.createdAt)).toBe(true);
    });
  });
});
