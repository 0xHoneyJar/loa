/**
 * Role Mapper Service Tests
 *
 * Sprint 3 - Task 3.6 Tests
 *
 * Tests for Discord role -> persona mapping service.
 */

import { RoleMapper } from '../role-mapper';

describe('RoleMapper', () => {
  let roleMapper: RoleMapper;

  beforeEach(() => {
    // Create fresh instance for each test
    roleMapper = new RoleMapper();
  });

  describe('initialization', () => {
    it('should initialize successfully', async () => {
      await expect(roleMapper.initialize()).resolves.not.toThrow();
    });

    it('should return default persona before initialization', () => {
      expect(roleMapper.getDefaultPersona()).toBe('product');
    });
  });

  describe('setRoleMapping', () => {
    it('should add a role mapping', () => {
      roleMapper.setRoleMapping('123456789', 'leadership');
      const mappings = roleMapper.getRoleMappings();
      expect(mappings.has('123456789')).toBe(true);
      expect(mappings.get('123456789')?.persona).toBe('leadership');
    });

    it('should update existing role mapping', () => {
      roleMapper.setRoleMapping('123456789', 'leadership');
      roleMapper.setRoleMapping('123456789', 'product');
      const mappings = roleMapper.getRoleMappings();
      expect(mappings.get('123456789')?.persona).toBe('product');
    });

    it('should assign correct priority based on persona', () => {
      roleMapper.setRoleMapping('1', 'leadership');
      roleMapper.setRoleMapping('2', 'product');
      roleMapper.setRoleMapping('3', 'marketing');
      roleMapper.setRoleMapping('4', 'devrel');

      const mappings = roleMapper.getRoleMappings();
      expect(mappings.get('1')?.priority).toBe(1);
      expect(mappings.get('2')?.priority).toBe(2);
      expect(mappings.get('3')?.priority).toBe(3);
      expect(mappings.get('4')?.priority).toBe(4);
    });
  });

  describe('removeRoleMapping', () => {
    it('should remove an existing role mapping', () => {
      roleMapper.setRoleMapping('123456789', 'leadership');
      expect(roleMapper.removeRoleMapping('123456789')).toBe(true);
      expect(roleMapper.getRoleMappings().has('123456789')).toBe(false);
    });

    it('should return false for non-existent mapping', () => {
      expect(roleMapper.removeRoleMapping('nonexistent')).toBe(false);
    });
  });

  describe('getRoleMappings', () => {
    it('should return all configured mappings', () => {
      roleMapper.setRoleMapping('1', 'leadership');
      roleMapper.setRoleMapping('2', 'product');

      const mappings = roleMapper.getRoleMappings();
      expect(mappings.size).toBe(2);
    });

    it('should return a copy of mappings', () => {
      roleMapper.setRoleMapping('1', 'leadership');
      const mappings = roleMapper.getRoleMappings();
      mappings.set('2', { persona: 'product', priority: 2 });

      // Original should not be affected
      expect(roleMapper.getRoleMappings().size).toBe(1);
    });
  });

  describe('getDefaultPersona', () => {
    it('should return default persona', () => {
      expect(roleMapper.getDefaultPersona()).toBe('product');
    });
  });
});

describe('RoleMapper Priority', () => {
  it('should prioritize leadership over other roles', () => {
    const roleMapper = new RoleMapper();
    roleMapper.setRoleMapping('leader-role', 'leadership');
    roleMapper.setRoleMapping('product-role', 'product');

    const mappings = roleMapper.getRoleMappings();
    const leaderPriority = mappings.get('leader-role')?.priority || 999;
    const productPriority = mappings.get('product-role')?.priority || 999;

    expect(leaderPriority).toBeLessThan(productPriority);
  });

  it('should prioritize product over marketing', () => {
    const roleMapper = new RoleMapper();
    roleMapper.setRoleMapping('product-role', 'product');
    roleMapper.setRoleMapping('marketing-role', 'marketing');

    const mappings = roleMapper.getRoleMappings();
    const productPriority = mappings.get('product-role')?.priority || 999;
    const marketingPriority = mappings.get('marketing-role')?.priority || 999;

    expect(productPriority).toBeLessThan(marketingPriority);
  });

  it('should prioritize marketing over devrel', () => {
    const roleMapper = new RoleMapper();
    roleMapper.setRoleMapping('marketing-role', 'marketing');
    roleMapper.setRoleMapping('devrel-role', 'devrel');

    const mappings = roleMapper.getRoleMappings();
    const marketingPriority = mappings.get('marketing-role')?.priority || 999;
    const devrelPriority = mappings.get('devrel-role')?.priority || 999;

    expect(marketingPriority).toBeLessThan(devrelPriority);
  });
});
