/**
 * Tenant Context Provider Tests
 *
 * Sprint 4 - Task 4.0: Tenant Context Foundation
 *
 * Tests for TenantContextProvider functionality including:
 * - Context propagation via AsyncLocalStorage
 * - Feature flag checking
 * - Tenant configuration loading
 * - Backward compatibility (default tenant)
 */

import * as fs from 'fs';
import * as path from 'path';
import { TenantContextProvider } from '../tenant-context';
import {
  TenantContext,
  DEFAULT_TENANT_ID,
  DEFAULT_TENANT_CONFIG,
} from '../../types/tenant';

// Mock fs module
jest.mock('fs');
const mockFs = fs as jest.Mocked<typeof fs>;

// Mock logger
jest.mock('../../utils/logger', () => ({
  logger: {
    info: jest.fn(),
    debug: jest.fn(),
    warn: jest.fn(),
    error: jest.fn(),
  },
}));

describe('TenantContextProvider', () => {
  let provider: TenantContextProvider;
  const testConfigDir = '/test/config/tenants';

  beforeEach(() => {
    jest.resetAllMocks();
    provider = new TenantContextProvider(testConfigDir);

    // Default mock: config directory exists
    mockFs.existsSync.mockReturnValue(true);
  });

  describe('initialization', () => {
    it('should create config directory if it does not exist', async () => {
      mockFs.existsSync.mockReturnValueOnce(false); // Directory doesn't exist
      mockFs.existsSync.mockReturnValueOnce(false); // Config file doesn't exist
      mockFs.mkdirSync.mockReturnValue(undefined);
      mockFs.writeFileSync.mockReturnValue(undefined);

      await provider.initialize();

      expect(mockFs.mkdirSync).toHaveBeenCalledWith(testConfigDir, { recursive: true });
    });

    it('should load default tenant on initialization', async () => {
      const mockTenantConfig = {
        tenantId: 'thj',
        name: 'The Honey Jar',
        config: {
          enabledFeatures: ['transformations'],
          maxTransformationsPerDay: 100,
          maxConcurrentTransforms: 3,
          allowedPersonas: ['leadership'],
        },
      };

      mockFs.existsSync.mockReturnValue(true);
      mockFs.readFileSync.mockReturnValue(JSON.stringify(mockTenantConfig));

      await provider.initialize();

      const tenant = provider.getCurrentTenant();
      expect(tenant.tenantId).toBe('thj');
      expect(tenant.name).toBe('The Honey Jar');
    });

    it('should create default config if tenant config file does not exist', async () => {
      mockFs.existsSync.mockReturnValueOnce(true); // Directory exists
      mockFs.existsSync.mockReturnValueOnce(false); // Config file doesn't exist
      mockFs.writeFileSync.mockReturnValue(undefined);

      await provider.initialize();

      expect(mockFs.writeFileSync).toHaveBeenCalled();
      const tenant = provider.getCurrentTenant();
      expect(tenant.tenantId).toBe(DEFAULT_TENANT_ID);
    });
  });

  describe('getCurrentTenant', () => {
    it('should return default tenant when not in context', async () => {
      const mockTenantConfig = {
        tenantId: 'thj',
        name: 'The Honey Jar',
        config: DEFAULT_TENANT_CONFIG,
      };

      mockFs.readFileSync.mockReturnValue(JSON.stringify(mockTenantConfig));
      await provider.initialize();

      const tenant = provider.getCurrentTenant();
      expect(tenant.tenantId).toBe('thj');
    });

    it('should return context tenant when within withTenantContext', async () => {
      const mockThjConfig = {
        tenantId: 'thj',
        name: 'The Honey Jar',
        config: DEFAULT_TENANT_CONFIG,
      };
      const mockOtherConfig = {
        tenantId: 'other',
        name: 'Other Tenant',
        config: DEFAULT_TENANT_CONFIG,
      };

      mockFs.readFileSync
        .mockReturnValueOnce(JSON.stringify(mockThjConfig))
        .mockReturnValueOnce(JSON.stringify(mockOtherConfig));

      await provider.initialize();

      let contextTenantId: string | undefined;

      await provider.withTenantContext('other', async () => {
        contextTenantId = provider.getCurrentTenant().tenantId;
      });

      expect(contextTenantId).toBe('other');
    });
  });

  describe('withTenantContext', () => {
    it('should propagate tenant context through async operations', async () => {
      const mockConfig = {
        tenantId: 'test-tenant',
        name: 'Test Tenant',
        config: DEFAULT_TENANT_CONFIG,
      };

      mockFs.readFileSync.mockReturnValue(JSON.stringify(mockConfig));
      await provider.initialize();

      const results: string[] = [];

      await provider.withTenantContext('test-tenant', async () => {
        results.push(provider.getCurrentTenant().tenantId);

        // Simulate async operation
        await new Promise(resolve => setTimeout(resolve, 10));

        results.push(provider.getCurrentTenant().tenantId);
      });

      expect(results).toEqual(['test-tenant', 'test-tenant']);
    });

    it('should handle nested contexts correctly', async () => {
      const mockThjConfig = {
        tenantId: 'thj',
        name: 'THJ',
        config: DEFAULT_TENANT_CONFIG,
      };
      const mockOtherConfig = {
        tenantId: 'other',
        name: 'Other',
        config: DEFAULT_TENANT_CONFIG,
      };

      // Mock setup: initialize() loads 'thj', then getTenant('thj') loads again, then getTenant('other')
      mockFs.readFileSync
        .mockReturnValueOnce(JSON.stringify(mockThjConfig))  // initialize()
        .mockReturnValueOnce(JSON.stringify(mockThjConfig))  // withTenantContext('thj')
        .mockReturnValueOnce(JSON.stringify(mockOtherConfig));  // withTenantContext('other')

      await provider.initialize();

      const results: string[] = [];

      await provider.withTenantContext('thj', async () => {
        results.push(provider.getCurrentTenant().tenantId);

        // This would normally not be recommended, but testing isolation
        await provider.withTenantContext('other', async () => {
          results.push(provider.getCurrentTenant().tenantId);
        });

        results.push(provider.getCurrentTenant().tenantId);
      });

      expect(results).toEqual(['thj', 'other', 'thj']);
    });
  });

  describe('isFeatureEnabled', () => {
    it('should return true for enabled features', async () => {
      const mockConfig = {
        tenantId: 'thj',
        name: 'THJ',
        config: {
          ...DEFAULT_TENANT_CONFIG,
          enabledFeatures: ['transformations', 'notifications'],
        },
      };

      mockFs.readFileSync.mockReturnValue(JSON.stringify(mockConfig));
      await provider.initialize();

      expect(provider.isFeatureEnabled('transformations')).toBe(true);
      expect(provider.isFeatureEnabled('notifications')).toBe(true);
    });

    it('should return false for disabled features', async () => {
      const mockConfig = {
        tenantId: 'thj',
        name: 'THJ',
        config: {
          ...DEFAULT_TENANT_CONFIG,
          enabledFeatures: ['transformations'],
        },
      };

      mockFs.readFileSync.mockReturnValue(JSON.stringify(mockConfig));
      await provider.initialize();

      expect(provider.isFeatureEnabled('webhooks')).toBe(false);
      expect(provider.isFeatureEnabled('cost-dashboard')).toBe(false);
    });
  });

  describe('isPersonaAllowed', () => {
    it('should return true for allowed personas', async () => {
      const mockConfig = {
        tenantId: 'thj',
        name: 'THJ',
        config: {
          ...DEFAULT_TENANT_CONFIG,
          allowedPersonas: ['leadership', 'product'],
        },
      };

      mockFs.readFileSync.mockReturnValue(JSON.stringify(mockConfig));
      await provider.initialize();

      expect(provider.isPersonaAllowed('leadership')).toBe(true);
      expect(provider.isPersonaAllowed('product')).toBe(true);
    });

    it('should return false for disallowed personas', async () => {
      const mockConfig = {
        tenantId: 'thj',
        name: 'THJ',
        config: {
          ...DEFAULT_TENANT_CONFIG,
          allowedPersonas: ['leadership'],
        },
      };

      mockFs.readFileSync.mockReturnValue(JSON.stringify(mockConfig));
      await provider.initialize();

      expect(provider.isPersonaAllowed('marketing')).toBe(false);
      expect(provider.isPersonaAllowed('devrel')).toBe(false);
    });
  });

  describe('getCacheTTL', () => {
    it('should return configured TTL values', async () => {
      const mockConfig = {
        tenantId: 'thj',
        name: 'THJ',
        config: {
          ...DEFAULT_TENANT_CONFIG,
          cacheTTL: {
            documentContent: 300,
            transformResults: 600,
            folderIds: 1200,
          },
        },
      };

      mockFs.readFileSync.mockReturnValue(JSON.stringify(mockConfig));
      await provider.initialize();

      expect(provider.getCacheTTL('documentContent')).toBe(300);
      expect(provider.getCacheTTL('transformResults')).toBe(600);
      expect(provider.getCacheTTL('folderIds')).toBe(1200);
    });

    it('should return default TTL for missing config', async () => {
      const mockConfig = {
        tenantId: 'thj',
        name: 'THJ',
        config: {
          ...DEFAULT_TENANT_CONFIG,
          cacheTTL: undefined,
        },
      };

      mockFs.readFileSync.mockReturnValue(JSON.stringify(mockConfig));
      await provider.initialize();

      // Should fall back to DEFAULT_TENANT_CONFIG values
      expect(provider.getCacheTTL('documentContent')).toBe(DEFAULT_TENANT_CONFIG.cacheTTL!.documentContent);
    });
  });

  describe('cache management', () => {
    it('should cache loaded tenants', async () => {
      const mockConfig = {
        tenantId: 'cached-tenant',
        name: 'Cached Tenant',
        config: DEFAULT_TENANT_CONFIG,
      };

      mockFs.readFileSync.mockReturnValue(JSON.stringify(mockConfig));
      await provider.initialize();

      // First call loads from file
      await provider.getTenant('cached-tenant');
      const readCallCount = mockFs.readFileSync.mock.calls.length;

      // Second call should use cache
      await provider.getTenant('cached-tenant');
      expect(mockFs.readFileSync.mock.calls.length).toBe(readCallCount);
    });

    it('should clear cache when requested', async () => {
      const mockConfig = {
        tenantId: 'thj',
        name: 'THJ',
        config: DEFAULT_TENANT_CONFIG,
      };

      mockFs.readFileSync.mockReturnValue(JSON.stringify(mockConfig));
      await provider.initialize();

      // Load tenant to populate cache
      await provider.getTenant('thj');
      const initialReadCount = mockFs.readFileSync.mock.calls.length;

      // Clear cache
      provider.clearCache();

      // Should read from file again
      await provider.getTenant('thj');
      expect(mockFs.readFileSync.mock.calls.length).toBeGreaterThan(initialReadCount);
    });

    it('should reload specific tenant', async () => {
      const mockConfig = {
        tenantId: 'thj',
        name: 'THJ',
        config: DEFAULT_TENANT_CONFIG,
      };

      mockFs.readFileSync.mockReturnValue(JSON.stringify(mockConfig));
      await provider.initialize();

      // Initial load
      await provider.getTenant('thj');
      const initialReadCount = mockFs.readFileSync.mock.calls.length;

      // Reload
      await provider.reloadTenant('thj');
      expect(mockFs.readFileSync.mock.calls.length).toBeGreaterThan(initialReadCount);
    });
  });

  describe('backward compatibility', () => {
    it('should work without explicit tenant context', async () => {
      const mockConfig = {
        tenantId: 'thj',
        name: 'The Honey Jar',
        config: DEFAULT_TENANT_CONFIG,
      };

      mockFs.readFileSync.mockReturnValue(JSON.stringify(mockConfig));
      await provider.initialize();

      // Should work without withTenantContext
      const tenant = provider.getCurrentTenant();
      expect(tenant).toBeDefined();
      expect(tenant.tenantId).toBe('thj');
    });

    it('should handle initialization failure gracefully', async () => {
      mockFs.existsSync.mockReturnValue(true);
      mockFs.readFileSync.mockImplementation(() => {
        throw new Error('Read error');
      });

      await provider.initialize();

      // Should fall back to in-memory default
      const tenant = provider.getCurrentTenant();
      expect(tenant.tenantId).toBe(DEFAULT_TENANT_ID);
    });
  });

  describe('tenantId validation (path traversal prevention)', () => {
    it('should accept valid tenant IDs', async () => {
      const validIds = ['thj', 'tenant-1', 'my-tenant-123', 'a', 'ab', 'a1b2c3'];

      for (const id of validIds) {
        const mockConfig = {
          tenantId: id,
          name: 'Test',
          config: DEFAULT_TENANT_CONFIG,
        };
        mockFs.existsSync.mockReturnValue(true);
        mockFs.readFileSync.mockReturnValue(JSON.stringify(mockConfig));

        await provider.initialize();
        const tenant = await provider.getTenant(id);
        expect(tenant.tenantId).toBe(id);

        provider.clearCache();
      }
    });

    it('should reject path traversal attempts', async () => {
      mockFs.existsSync.mockReturnValue(true);
      await provider.initialize();

      await expect(provider.getTenant('../etc/passwd')).rejects.toThrow('Invalid tenant ID');
      await expect(provider.getTenant('../../secrets')).rejects.toThrow('Invalid tenant ID');
      await expect(provider.getTenant('tenant/../admin')).rejects.toThrow('Invalid tenant ID');
    });

    it('should reject tenant IDs with invalid characters', async () => {
      mockFs.existsSync.mockReturnValue(true);
      await provider.initialize();

      await expect(provider.getTenant('tenant/id')).rejects.toThrow('Invalid tenant ID');
      await expect(provider.getTenant('tenant\\id')).rejects.toThrow('Invalid tenant ID');
      await expect(provider.getTenant('tenant.id')).rejects.toThrow('Invalid tenant ID');
      await expect(provider.getTenant('tenant:id')).rejects.toThrow('Invalid tenant ID');
      await expect(provider.getTenant('tenant id')).rejects.toThrow('Invalid tenant ID');
    });

    it('should reject tenant IDs starting or ending with hyphen', async () => {
      mockFs.existsSync.mockReturnValue(true);
      await provider.initialize();

      await expect(provider.getTenant('-tenant')).rejects.toThrow('Invalid tenant ID');
      await expect(provider.getTenant('tenant-')).rejects.toThrow('Invalid tenant ID');
      await expect(provider.getTenant('-')).rejects.toThrow('Invalid tenant ID');
    });

    it('should reject empty or null tenant IDs', async () => {
      mockFs.existsSync.mockReturnValue(true);
      await provider.initialize();

      await expect(provider.getTenant('')).rejects.toThrow('Tenant ID is required');
      await expect(provider.getTenant(null as unknown as string)).rejects.toThrow('Tenant ID is required');
      await expect(provider.getTenant(undefined as unknown as string)).rejects.toThrow('Tenant ID is required');
    });
  });
});
