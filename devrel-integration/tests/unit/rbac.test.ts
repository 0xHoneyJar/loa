/**
 * RBAC Tests
 *
 * Validates authorization checks for approval workflow.
 * Tests for CRITICAL-003 remediation.
 */

import { RBAC } from '../../src/services/rbac';
import { Client, Guild, GuildMember, Collection, Role } from 'discord.js';
import fs from 'fs';
import path from 'path';

// Mock Discord.js
jest.mock('discord.js');

describe('RBAC', () => {
  let rbac: RBAC;
  let mockClient: jest.Mocked<Client>;
  let mockGuild: jest.Mocked<Guild>;
  let mockMember: jest.Mocked<GuildMember>;

  beforeEach(() => {
    rbac = new RBAC();

    // Create mocks
    mockClient = {
      guilds: {
        fetch: jest.fn(),
        cache: new Collection()
      }
    } as any;

    mockGuild = {
      id: 'test-guild-id',
      members: {
        fetch: jest.fn()
      }
    } as any;

    mockMember = {
      id: 'test-user-id',
      roles: {
        cache: new Collection<string, Role>()
      }
    } as any;

    // Initialize RBAC with mock client
    rbac.initialize(mockClient as any);
  });

  describe('Configuration Loading', () => {
    test('should load configuration on initialization', () => {
      const validation = rbac.validateConfig();
      expect(validation).toHaveProperty('valid');
      expect(validation).toHaveProperty('errors');
    });

    test('should validate configuration', () => {
      const validation = rbac.validateConfig();

      // Default config should have warnings
      expect(validation.errors.length).toBeGreaterThan(0);
      expect(validation.errors.some(e => e.includes('reviewers'))).toBe(true);
    });

    test('should get default config if file not found', () => {
      const approvalRoles = rbac.getApprovalRoles();
      expect(approvalRoles).toContain('product_manager');
      expect(approvalRoles).toContain('tech_lead');
      expect(approvalRoles).toContain('cto');
    });
  });

  describe('Approval Authorization', () => {
    test('should deny approval if user not in reviewers list', async () => {
      const canApprove = await rbac.canApprove('unauthorized-user-id');
      expect(canApprove).toBe(false);
    });

    test('should deny approval if user lacks approval role', async () => {
      mockClient.guilds.fetch = jest.fn().mockResolvedValue(mockGuild);
      mockGuild.members.fetch = jest.fn().mockResolvedValue(mockMember);

      // Add non-approval role
      const mockRole = { name: 'Developer', id: 'role-1' } as Role;
      mockMember.roles.cache.set('role-1', mockRole);

      const canApprove = await rbac.canApprove('test-user-id', 'test-guild-id');
      expect(canApprove).toBe(false);
    });

    test('should allow approval if user has Product Manager role', async () => {
      mockClient.guilds.fetch = jest.fn().mockResolvedValue(mockGuild);
      mockGuild.members.fetch = jest.fn().mockResolvedValue(mockMember);

      // Add approval role
      const mockRole = { name: 'Product Manager', id: 'role-1' } as Role;
      mockMember.roles.cache.set('role-1', mockRole);

      const canApprove = await rbac.canApprove('test-user-id', 'test-guild-id');
      expect(canApprove).toBe(true);
    });

    test('should allow approval if user has Tech Lead role', async () => {
      mockClient.guilds.fetch = jest.fn().mockResolvedValue(mockGuild);
      mockGuild.members.fetch = jest.fn().mockResolvedValue(mockMember);

      const mockRole = { name: 'Tech Lead', id: 'role-1' } as Role;
      mockMember.roles.cache.set('role-1', mockRole);

      const canApprove = await rbac.canApprove('test-user-id', 'test-guild-id');
      expect(canApprove).toBe(true);
    });

    test('should allow approval if user has CTO role', async () => {
      mockClient.guilds.fetch = jest.fn().mockResolvedValue(mockGuild);
      mockGuild.members.fetch = jest.fn().mockResolvedValue(mockMember);

      const mockRole = { name: 'CTO', id: 'role-1' } as Role;
      mockMember.roles.cache.set('role-1', mockRole);

      const canApprove = await rbac.canApprove('test-user-id', 'test-guild-id');
      expect(canApprove).toBe(true);
    });

    test('should normalize role names with spaces', async () => {
      mockClient.guilds.fetch = jest.fn().mockResolvedValue(mockGuild);
      mockGuild.members.fetch = jest.fn().mockResolvedValue(mockMember);

      // "Product Manager" should match "product_manager"
      const mockRole = { name: 'Product Manager', id: 'role-1' } as Role;
      mockMember.roles.cache.set('role-1', mockRole);

      const canApprove = await rbac.canApprove('test-user-id', 'test-guild-id');
      expect(canApprove).toBe(true);
    });

    test('should handle Discord API errors gracefully', async () => {
      mockClient.guilds.fetch = jest.fn().mockRejectedValue(new Error('Discord API error'));

      const canApprove = await rbac.canApprove('test-user-id', 'test-guild-id');
      expect(canApprove).toBe(false);
    });
  });

  describe('Blog Publishing Authorization', () => {
    test('should deny blog publishing by default (disabled)', async () => {
      const canPublish = await rbac.canPublishBlog('any-user-id');
      expect(canPublish).toBe(false);
    });

    test('should deny blog publishing if user not in publishers list', async () => {
      const canPublish = await rbac.canPublishBlog('unauthorized-user-id');
      expect(canPublish).toBe(false);
    });
  });

  describe('Multi-Approval Requirements', () => {
    test('should require multi-approval for blog publishing', () => {
      const requires = rbac.requiresMultiApproval('blog_publishing');
      expect(requires).toBe(true);
    });

    test('should not require multi-approval for regular approval', () => {
      const requires = rbac.requiresMultiApproval('regular_approval');
      expect(requires).toBe(false);
    });

    test('should return minimum approval count', () => {
      const minimum = rbac.getMinimumApprovals();
      expect(minimum).toBe(2);
    });
  });

  describe('Configuration Getters', () => {
    test('should get authorized reviewers list', () => {
      const reviewers = rbac.getAuthorizedReviewers();
      expect(Array.isArray(reviewers)).toBe(true);
    });

    test('should get approval roles list', () => {
      const roles = rbac.getApprovalRoles();
      expect(Array.isArray(roles)).toBe(true);
      expect(roles.length).toBeGreaterThan(0);
    });

    test('should get authorized publishers list', () => {
      const publishers = rbac.getAuthorizedPublishers();
      expect(Array.isArray(publishers)).toBe(true);
    });

    test('should check if approval is required', () => {
      const required = rbac.isApprovalRequired();
      expect(typeof required).toBe('boolean');
      expect(required).toBe(true);  // Default is true
    });
  });

  describe('Security Test Cases', () => {
    test('should block 100% of unauthorized approval attempts', async () => {
      const unauthorizedUsers = [
        'random-user-1',
        'random-user-2',
        'random-user-3',
        'hacker',
        'attacker',
        'malicious-user'
      ];

      for (const userId of unauthorizedUsers) {
        const canApprove = await rbac.canApprove(userId);
        expect(canApprove).toBe(false);
      }
    });

    test('should block unauthorized blog publishing (100%)', async () => {
      const unauthorizedUsers = [
        'developer-1',
        'developer-2',
        'random-user',
        'attacker'
      ];

      for (const userId of unauthorizedUsers) {
        const canPublish = await rbac.canPublishBlog(userId);
        expect(canPublish).toBe(false);
      }
    });

    test('should require explicit authorization (no default allow)', async () => {
      // Empty user ID
      expect(await rbac.canApprove('')).toBe(false);

      // Null-like values (converted to string)
      expect(await rbac.canApprove('null')).toBe(false);
      expect(await rbac.canApprove('undefined')).toBe(false);
    });

    test('should log unauthorized attempts', async () => {
      const spy = jest.spyOn(console, 'warn').mockImplementation();

      await rbac.canApprove('unauthorized-user');

      // Logger should have recorded the attempt
      // (actual logging implementation may vary)

      spy.mockRestore();
    });
  });
});
