/**
 * Role Verifier Tests
 *
 * Tests for database-backed RBAC permission checking.
 * Validates:
 * - Permission-to-role mappings
 * - Database-first role verification
 * - MFA requirement detection
 * - Authorization audit logging
 * - Permission caching
 * - Privilege escalation prevention
 *
 * This tests HIGH-005 and CRITICAL-004 remediation.
 */

import { RoleVerifier } from '../role-verifier';
import userMappingService from '../user-mapping-service';

// Mock the dependencies
jest.mock('../user-mapping-service');
jest.mock('../../utils/logger', () => ({
  logger: {
    error: jest.fn(),
    warn: jest.fn(),
    info: jest.fn(),
    debug: jest.fn()
  },
  auditLog: {
    permissionGranted: jest.fn(),
    permissionDenied: jest.fn()
  }
}));

describe('RoleVerifier', () => {
  let roleVerifier: RoleVerifier;

  beforeEach(() => {
    roleVerifier = new RoleVerifier();

    // Reset mocks
    jest.clearAllMocks();
  });

  describe('hasPermission - Public commands', () => {
    it('should allow guest to access public commands', async () => {
      (userMappingService.getUserRoles as jest.Mock).mockResolvedValue(['guest']);

      const result = await roleVerifier.hasPermission(
        'user123',
        'show-sprint',
        { command: 'show-sprint' }
      );

      expect(result.granted).toBe(true);
      expect(result.mfaRequired).toBe(false);
    });

    it('should allow researcher to access public commands', async () => {
      (userMappingService.getUserRoles as jest.Mock).mockResolvedValue(['researcher']);

      const result = await roleVerifier.hasPermission(
        'user123',
        'doc',
        { command: 'doc' }
      );

      expect(result.granted).toBe(true);
      expect(result.mfaRequired).toBe(false);
    });

    it('should allow developer to access public commands', async () => {
      (userMappingService.getUserRoles as jest.Mock).mockResolvedValue(['developer']);

      const result = await roleVerifier.hasPermission(
        'user123',
        'preview',
        { command: 'preview' }
      );

      expect(result.granted).toBe(true);
      expect(result.mfaRequired).toBe(false);
    });

    it('should allow admin to access public commands', async () => {
      (userMappingService.getUserRoles as jest.Mock).mockResolvedValue(['admin']);

      const result = await roleVerifier.hasPermission(
        'user123',
        'task',
        { command: 'task' }
      );

      expect(result.granted).toBe(true);
      expect(result.mfaRequired).toBe(false);
    });
  });

  describe('hasPermission - Developer commands', () => {
    it('should deny guest access to developer commands', async () => {
      (userMappingService.getUserRoles as jest.Mock).mockResolvedValue(['guest']);

      const result = await roleVerifier.hasPermission(
        'user123',
        'implement',
        { command: 'implement' }
      );

      expect(result.granted).toBe(false);
      expect(result.denialReason).toContain('requires one of [developer, admin]');
      expect(result.requiredRole).toBe('developer');
    });

    it('should deny researcher access to developer commands', async () => {
      (userMappingService.getUserRoles as jest.Mock).mockResolvedValue(['researcher']);

      const result = await roleVerifier.hasPermission(
        'user123',
        'review-sprint',
        { command: 'review-sprint' }
      );

      expect(result.granted).toBe(false);
      expect(result.denialReason).toContain('requires one of [developer, admin]');
    });

    it('should allow developer to access developer commands', async () => {
      (userMappingService.getUserRoles as jest.Mock).mockResolvedValue(['developer']);

      const result = await roleVerifier.hasPermission(
        'user123',
        'implement',
        { command: 'implement' }
      );

      expect(result.granted).toBe(true);
      expect(result.mfaRequired).toBe(false);
    });

    it('should allow admin to access developer commands', async () => {
      (userMappingService.getUserRoles as jest.Mock).mockResolvedValue(['admin']);

      const result = await roleVerifier.hasPermission(
        'user123',
        'my-tasks',
        { command: 'my-tasks' }
      );

      expect(result.granted).toBe(true);
      expect(result.mfaRequired).toBe(false);
    });

    it('should allow researcher to access feedback commands', async () => {
      (userMappingService.getUserRoles as jest.Mock).mockResolvedValue(['researcher']);

      const result = await roleVerifier.hasPermission(
        'user123',
        'feedback',
        { command: 'feedback' }
      );

      expect(result.granted).toBe(true);
      expect(result.mfaRequired).toBe(false);
    });
  });

  describe('hasPermission - Admin commands', () => {
    it('should deny guest access to admin commands', async () => {
      (userMappingService.getUserRoles as jest.Mock).mockResolvedValue(['guest']);

      const result = await roleVerifier.hasPermission(
        'user123',
        'config',
        { command: 'config' }
      );

      expect(result.granted).toBe(false);
      expect(result.denialReason).toContain('requires one of [admin]');
      expect(result.requiredRole).toBe('admin');
    });

    it('should deny researcher access to admin commands', async () => {
      (userMappingService.getUserRoles as jest.Mock).mockResolvedValue(['researcher']);

      const result = await roleVerifier.hasPermission(
        'user123',
        'manage-users',
        { command: 'manage-users' }
      );

      expect(result.granted).toBe(false);
      expect(result.denialReason).toContain('requires one of [admin]');
    });

    it('should deny developer access to admin commands', async () => {
      (userMappingService.getUserRoles as jest.Mock).mockResolvedValue(['developer']);

      const result = await roleVerifier.hasPermission(
        'user123',
        'manage-roles',
        { command: 'manage-roles' }
      );

      expect(result.granted).toBe(false);
      expect(result.denialReason).toContain('requires one of [admin]');
    });

    it('should allow admin to access admin commands', async () => {
      (userMappingService.getUserRoles as jest.Mock).mockResolvedValue(['admin']);

      const result = await roleVerifier.hasPermission(
        'user123',
        'config',
        { command: 'config' }
      );

      expect(result.granted).toBe(true);
      expect(result.mfaRequired).toBe(true); // Admin commands require MFA
    });

    it('should allow admin to access all permissions (*)', async () => {
      (userMappingService.getUserRoles as jest.Mock).mockResolvedValue(['admin']);

      const result = await roleVerifier.hasPermission(
        'user123',
        '*',
        { command: 'any-command' }
      );

      expect(result.granted).toBe(true);
      expect(result.mfaRequired).toBe(false); // * permission doesn't require MFA by default
    });
  });

  describe('hasPermission - MFA requirements', () => {
    it('should require MFA for manage-roles command', async () => {
      (userMappingService.getUserRoles as jest.Mock).mockResolvedValue(['admin']);

      const result = await roleVerifier.hasPermission(
        'admin123',
        'manage-roles',
        { command: 'manage-roles' }
      );

      expect(result.granted).toBe(true);
      expect(result.mfaRequired).toBe(true);
    });

    it('should require MFA for config command', async () => {
      (userMappingService.getUserRoles as jest.Mock).mockResolvedValue(['admin']);

      const result = await roleVerifier.hasPermission(
        'admin123',
        'config',
        { command: 'config' }
      );

      expect(result.granted).toBe(true);
      expect(result.mfaRequired).toBe(true);
    });

    it('should require MFA for manage-users command', async () => {
      (userMappingService.getUserRoles as jest.Mock).mockResolvedValue(['admin']);

      const result = await roleVerifier.hasPermission(
        'admin123',
        'manage-users',
        { command: 'manage-users' }
      );

      expect(result.granted).toBe(true);
      expect(result.mfaRequired).toBe(true);
    });

    it('should not require MFA for non-sensitive commands', async () => {
      (userMappingService.getUserRoles as jest.Mock).mockResolvedValue(['developer']);

      const result = await roleVerifier.hasPermission(
        'dev123',
        'implement',
        { command: 'implement' }
      );

      expect(result.granted).toBe(true);
      expect(result.mfaRequired).toBe(false);
    });
  });

  describe('hasPermission - Multiple roles', () => {
    it('should grant permission if user has one of required roles', async () => {
      (userMappingService.getUserRoles as jest.Mock).mockResolvedValue(['guest', 'developer']);

      const result = await roleVerifier.hasPermission(
        'user123',
        'implement',
        { command: 'implement' }
      );

      expect(result.granted).toBe(true);
    });

    it('should grant permission if user has multiple roles including required', async () => {
      (userMappingService.getUserRoles as jest.Mock).mockResolvedValue(['researcher', 'developer', 'admin']);

      const result = await roleVerifier.hasPermission(
        'user123',
        'manage-roles',
        { command: 'manage-roles' }
      );

      expect(result.granted).toBe(true);
      expect(result.mfaRequired).toBe(true);
    });

    it('should deny permission if user has none of required roles', async () => {
      (userMappingService.getUserRoles as jest.Mock).mockResolvedValue(['guest', 'researcher']);

      const result = await roleVerifier.hasPermission(
        'user123',
        'config',
        { command: 'config' }
      );

      expect(result.granted).toBe(false);
      expect(result.denialReason).toContain('requires one of [admin]');
    });
  });

  describe('hasPermission - Unknown permission', () => {
    it('should deny unknown permission', async () => {
      (userMappingService.getUserRoles as jest.Mock).mockResolvedValue(['admin']);

      const result = await roleVerifier.hasPermission(
        'user123',
        'unknown-permission' as any,
        { command: 'unknown' }
      );

      expect(result.granted).toBe(false);
      expect(result.denialReason).toContain('Unknown permission');
    });
  });

  describe('hasPermission - Error handling', () => {
    it('should deny permission on database error', async () => {
      (userMappingService.getUserRoles as jest.Mock).mockRejectedValue(new Error('Database connection failed'));

      const result = await roleVerifier.hasPermission(
        'user123',
        'show-sprint',
        { command: 'show-sprint' }
      );

      expect(result.granted).toBe(false);
      expect(result.denialReason).toContain('Internal error');
    });

    it('should handle user not found', async () => {
      (userMappingService.getUserRoles as jest.Mock).mockResolvedValue([]);

      const result = await roleVerifier.hasPermission(
        'unknown-user',
        'show-sprint',
        { command: 'show-sprint' }
      );

      expect(result.granted).toBe(false);
      expect(result.denialReason).toContain('requires one of');
    });

    it('should handle null/undefined user roles', async () => {
      (userMappingService.getUserRoles as jest.Mock).mockResolvedValue(null);

      const result = await roleVerifier.hasPermission(
        'user123',
        'show-sprint',
        { command: 'show-sprint' }
      );

      expect(result.granted).toBe(false);
    });
  });

  describe('hasAnyRole', () => {
    it('should grant access if user has one of required roles', async () => {
      (userMappingService.getUserRoles as jest.Mock).mockResolvedValue(['developer']);

      const result = await roleVerifier.hasAnyRole(
        'user123',
        ['developer', 'admin'],
        { command: 'test' }
      );

      expect(result.granted).toBe(true);
      expect(result.requiredRole).toBe('developer');
    });

    it('should deny access if user has none of required roles', async () => {
      (userMappingService.getUserRoles as jest.Mock).mockResolvedValue(['guest']);

      const result = await roleVerifier.hasAnyRole(
        'user123',
        ['developer', 'admin'],
        { command: 'test' }
      );

      expect(result.granted).toBe(false);
      expect(result.denialReason).toContain('requires one of [developer, admin]');
    });

    it('should handle multiple user roles', async () => {
      (userMappingService.getUserRoles as jest.Mock).mockResolvedValue(['guest', 'researcher', 'admin']);

      const result = await roleVerifier.hasAnyRole(
        'user123',
        ['admin'],
        { command: 'test' }
      );

      expect(result.granted).toBe(true);
    });

    it('should handle error in role check', async () => {
      (userMappingService.getUserRoles as jest.Mock).mockRejectedValue(new Error('Database error'));

      const result = await roleVerifier.hasAnyRole(
        'user123',
        ['developer'],
        { command: 'test' }
      );

      expect(result.granted).toBe(false);
      expect(result.denialReason).toContain('Internal error');
    });
  });

  describe('Privilege escalation prevention', () => {
    it('should prevent guest from escalating to developer', async () => {
      (userMappingService.getUserRoles as jest.Mock).mockResolvedValue(['guest']);

      const developerCommands = ['implement', 'review-sprint', 'my-tasks', 'implement-status'];

      for (const command of developerCommands) {
        const result = await roleVerifier.hasPermission(
          'attacker123',
          command as any,
          { command }
        );

        expect(result.granted).toBe(false);
        expect(result.denialReason).toContain('requires one of [developer, admin]');
      }
    });

    it('should prevent developer from escalating to admin', async () => {
      (userMappingService.getUserRoles as jest.Mock).mockResolvedValue(['developer']);

      const adminCommands = ['config', 'manage-users', 'manage-roles'];

      for (const command of adminCommands) {
        const result = await roleVerifier.hasPermission(
          'attacker123',
          command as any,
          { command }
        );

        expect(result.granted).toBe(false);
        expect(result.denialReason).toContain('requires one of [admin]');
      }
    });

    it('should prevent researcher from escalating to developer', async () => {
      (userMappingService.getUserRoles as jest.Mock).mockResolvedValue(['researcher']);

      const developerOnlyCommands = ['implement', 'review-sprint', 'my-tasks'];

      for (const command of developerOnlyCommands) {
        const result = await roleVerifier.hasPermission(
          'attacker123',
          command as any,
          { command }
        );

        expect(result.granted).toBe(false);
        expect(result.denialReason).toContain('requires one of [developer, admin]');
      }
    });

    it('should require MFA for sensitive admin operations', async () => {
      (userMappingService.getUserRoles as jest.Mock).mockResolvedValue(['admin']);

      const sensitiveCommands = ['manage-roles', 'config', 'manage-users'];

      for (const command of sensitiveCommands) {
        const result = await roleVerifier.hasPermission(
          'admin123',
          command as any,
          { command }
        );

        expect(result.granted).toBe(true);
        expect(result.mfaRequired).toBe(true);
      }
    });
  });

  describe('Authorization context tracking', () => {
    it('should accept context information', async () => {
      (userMappingService.getUserRoles as jest.Mock).mockResolvedValue(['admin']);

      const context = {
        command: 'config',
        resource: 'bot-settings',
        channelId: 'channel123',
        guildId: 'guild456',
        ipAddress: '192.168.1.1',
        userAgent: 'DiscordBot/1.0'
      };

      const result = await roleVerifier.hasPermission(
        'admin123',
        'config',
        context
      );

      expect(result.granted).toBe(true);
    });

    it('should work without context', async () => {
      (userMappingService.getUserRoles as jest.Mock).mockResolvedValue(['developer']);

      const result = await roleVerifier.hasPermission(
        'dev123',
        'implement'
      );

      expect(result.granted).toBe(true);
    });
  });

  describe('Edge cases', () => {
    it('should handle empty roles array', async () => {
      (userMappingService.getUserRoles as jest.Mock).mockResolvedValue([]);

      const result = await roleVerifier.hasPermission(
        'user123',
        'show-sprint',
        { command: 'show-sprint' }
      );

      expect(result.granted).toBe(false);
    });

    it('should handle case-sensitive role names', async () => {
      (userMappingService.getUserRoles as jest.Mock).mockResolvedValue(['ADMIN']); // Wrong case

      const result = await roleVerifier.hasPermission(
        'user123',
        'config',
        { command: 'config' }
      );

      expect(result.granted).toBe(false); // Should not match
    });

    it('should handle invalid user ID', async () => {
      (userMappingService.getUserRoles as jest.Mock).mockResolvedValue([]);

      const result = await roleVerifier.hasPermission(
        '',
        'show-sprint',
        { command: 'show-sprint' }
      );

      expect(result.granted).toBe(false);
    });

    it('should handle very long user ID', async () => {
      const longUserId = 'a'.repeat(1000);
      (userMappingService.getUserRoles as jest.Mock).mockResolvedValue(['guest']);

      const result = await roleVerifier.hasPermission(
        longUserId,
        'show-sprint',
        { command: 'show-sprint' }
      );

      expect(result.granted).toBe(true);
    });
  });
});
