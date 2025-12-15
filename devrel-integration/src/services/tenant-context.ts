/**
 * Tenant Context Provider
 *
 * Sprint 4 - Task 4.0: Tenant Context Foundation
 *
 * Provides tenant context management for multi-tenancy support.
 * MVP implementation uses hardcoded "thj" tenant, but the pattern
 * enables future SaaS extensibility.
 *
 * Features:
 * - Load tenant configuration from JSON files
 * - Thread-safe context propagation via AsyncLocalStorage
 * - Feature flag checking
 * - Quota management
 * - Default tenant fallback for backward compatibility
 */

import { AsyncLocalStorage } from 'async_hooks';
import * as fs from 'fs';
import * as path from 'path';
import { logger } from '../utils/logger';
import {
  TenantContext,
  TenantConfig,
  TenantQuotas,
  TenantCredentials,
  TenantFeature,
  PersonaType,
  DEFAULT_TENANT_CONFIG,
  DEFAULT_TENANT_ID,
} from '../types/tenant';

// =============================================================================
// Types
// =============================================================================

export interface TenantConfigFile {
  tenantId: string;
  name: string;
  config: Partial<TenantConfig>;
  credentials?: Partial<TenantCredentials>;
  metadata?: {
    status?: 'active' | 'suspended' | 'trial' | 'inactive';
  };
}

// =============================================================================
// Validation
// =============================================================================

/**
 * Valid tenant ID pattern: alphanumeric with hyphens, 1-64 chars
 * Prevents path traversal attacks (e.g., "../etc/passwd")
 */
const TENANT_ID_PATTERN = /^[a-z0-9][a-z0-9-]{0,62}[a-z0-9]$|^[a-z0-9]$/i;

/**
 * Validate tenant ID to prevent path traversal
 * @throws Error if tenantId is invalid
 */
function validateTenantId(tenantId: string): void {
  if (!tenantId || typeof tenantId !== 'string') {
    throw new Error('Tenant ID is required');
  }
  if (!TENANT_ID_PATTERN.test(tenantId)) {
    throw new Error(
      `Invalid tenant ID: "${tenantId}". Must be 1-64 alphanumeric characters with optional hyphens (not at start/end).`
    );
  }
}

// =============================================================================
// Tenant Context Provider
// =============================================================================

export class TenantContextProvider {
  private static instance: TenantContextProvider;

  /** AsyncLocalStorage for thread-safe context propagation */
  private asyncLocalStorage = new AsyncLocalStorage<TenantContext>();

  /** Cache of loaded tenant configurations */
  private tenantCache = new Map<string, TenantContext>();

  /** Path to tenant configuration directory */
  private configDir: string;

  /** Default tenant context for backward compatibility */
  private defaultTenant: TenantContext | null = null;

  constructor(configDir?: string) {
    this.configDir = configDir || path.join(process.cwd(), 'config', 'tenants');
  }

  /**
   * Get singleton instance
   */
  static getInstance(): TenantContextProvider {
    if (!TenantContextProvider.instance) {
      TenantContextProvider.instance = new TenantContextProvider();
    }
    return TenantContextProvider.instance;
  }

  /**
   * Initialize the provider and load default tenant
   */
  async initialize(): Promise<void> {
    logger.info('Initializing TenantContextProvider', { configDir: this.configDir });

    try {
      // Ensure config directory exists
      if (!fs.existsSync(this.configDir)) {
        fs.mkdirSync(this.configDir, { recursive: true });
        logger.info('Created tenant config directory', { configDir: this.configDir });
      }

      // Load default tenant
      this.defaultTenant = await this.loadTenant(DEFAULT_TENANT_ID);

      logger.info('TenantContextProvider initialized', {
        defaultTenant: this.defaultTenant.tenantId,
        features: this.defaultTenant.config.enabledFeatures,
      });
    } catch (error) {
      // If default tenant config doesn't exist, create it
      if ((error as NodeJS.ErrnoException).code === 'ENOENT') {
        logger.warn('Default tenant config not found, creating default configuration');
        this.defaultTenant = this.createDefaultTenantContext();
        await this.saveTenantConfig(this.defaultTenant);
      } else {
        logger.error('Failed to initialize TenantContextProvider', {
          error: error instanceof Error ? error.message : String(error),
        });
        // Use in-memory default for resilience
        this.defaultTenant = this.createDefaultTenantContext();
      }
    }
  }

  /**
   * Get the current tenant context from AsyncLocalStorage
   * Falls back to default tenant if not in a tenant context
   */
  getCurrentTenant(): TenantContext {
    const context = this.asyncLocalStorage.getStore();
    if (context) {
      return context;
    }

    // Fallback to default tenant for backward compatibility
    if (this.defaultTenant) {
      return this.defaultTenant;
    }

    // Ultimate fallback - create in-memory default
    return this.createDefaultTenantContext();
  }

  /**
   * Get tenant by ID
   */
  async getTenant(tenantId: string): Promise<TenantContext> {
    // Check cache first
    const cached = this.tenantCache.get(tenantId);
    if (cached) {
      return cached;
    }

    // Load from config file
    const tenant = await this.loadTenant(tenantId);
    this.tenantCache.set(tenantId, tenant);
    return tenant;
  }

  /**
   * Run a function within a tenant context
   * This is the primary way to establish tenant context for an operation
   */
  async withTenantContext<T>(
    tenantId: string,
    fn: () => Promise<T>
  ): Promise<T> {
    const tenant = await this.getTenant(tenantId);
    return this.asyncLocalStorage.run(tenant, fn);
  }

  /**
   * Run a function with the current or default tenant context
   * Use this when tenantId is optional for backward compatibility
   */
  async withOptionalTenantContext<T>(
    tenantId: string | undefined,
    fn: () => Promise<T>
  ): Promise<T> {
    const effectiveTenantId = tenantId || DEFAULT_TENANT_ID;
    return this.withTenantContext(effectiveTenantId, fn);
  }

  /**
   * Check if a feature is enabled for the current tenant
   */
  isFeatureEnabled(feature: TenantFeature): boolean {
    const tenant = this.getCurrentTenant();
    return tenant.config.enabledFeatures.includes(feature);
  }

  /**
   * Check if a persona is allowed for the current tenant
   */
  isPersonaAllowed(persona: PersonaType): boolean {
    const tenant = this.getCurrentTenant();
    return tenant.config.allowedPersonas.includes(persona);
  }

  /**
   * Get cache TTL for a specific cache type
   */
  getCacheTTL(cacheType: 'documentContent' | 'transformResults' | 'folderIds'): number {
    const tenant = this.getCurrentTenant();
    const ttl = tenant.config.cacheTTL?.[cacheType];
    return ttl ?? DEFAULT_TENANT_CONFIG.cacheTTL![cacheType]!;
  }

  /**
   * Check if tenant has quota available for transformations
   */
  hasTransformationQuota(): boolean {
    const tenant = this.getCurrentTenant();
    if (!tenant.quotas) {
      return true; // No quota tracking = unlimited
    }
    return tenant.quotas.current.transformationsToday < tenant.quotas.limits.maxTransformationsPerDay;
  }

  /**
   * Increment transformation count for current tenant
   * NOTE: In production, this would update Redis/database
   */
  incrementTransformationCount(): void {
    const tenant = this.getCurrentTenant();
    if (tenant.quotas) {
      tenant.quotas.current.transformationsToday++;
      logger.debug('Transformation count incremented', {
        tenantId: tenant.tenantId,
        count: tenant.quotas.current.transformationsToday,
        limit: tenant.quotas.limits.maxTransformationsPerDay,
      });
    }
  }

  /**
   * Clear tenant cache (useful for testing or config reloads)
   */
  clearCache(): void {
    this.tenantCache.clear();
    logger.info('Tenant cache cleared');
  }

  /**
   * Reload a specific tenant's configuration
   */
  async reloadTenant(tenantId: string): Promise<TenantContext> {
    this.tenantCache.delete(tenantId);
    const tenant = await this.loadTenant(tenantId);
    this.tenantCache.set(tenantId, tenant);

    // Update default tenant if reloading it
    if (tenantId === DEFAULT_TENANT_ID) {
      this.defaultTenant = tenant;
    }

    logger.info('Tenant configuration reloaded', { tenantId });
    return tenant;
  }

  // =============================================================================
  // Private Methods
  // =============================================================================

  /**
   * Load tenant from configuration file
   */
  private async loadTenant(tenantId: string): Promise<TenantContext> {
    validateTenantId(tenantId);
    const configPath = path.join(this.configDir, `${tenantId}.json`);

    if (!fs.existsSync(configPath)) {
      throw Object.assign(new Error(`Tenant config not found: ${tenantId}`), {
        code: 'ENOENT',
      });
    }

    const configData = JSON.parse(fs.readFileSync(configPath, 'utf-8')) as TenantConfigFile;

    // Merge with defaults
    const config: TenantConfig = {
      ...DEFAULT_TENANT_CONFIG,
      ...configData.config,
      cacheTTL: {
        ...DEFAULT_TENANT_CONFIG.cacheTTL,
        ...configData.config.cacheTTL,
      },
      rateLimits: {
        ...DEFAULT_TENANT_CONFIG.rateLimits,
        ...configData.config.rateLimits,
      },
    };

    const tenant: TenantContext = {
      tenantId: configData.tenantId,
      name: configData.name,
      config,
      credentials: configData.credentials as TenantCredentials | undefined,
      metadata: {
        createdAt: new Date(),
        updatedAt: new Date(),
        status: configData.metadata?.status || 'active',
      },
    };

    logger.debug('Tenant loaded', {
      tenantId: tenant.tenantId,
      name: tenant.name,
      features: tenant.config.enabledFeatures,
    });

    return tenant;
  }

  /**
   * Save tenant configuration to file
   */
  private async saveTenantConfig(tenant: TenantContext): Promise<void> {
    validateTenantId(tenant.tenantId);
    const configPath = path.join(this.configDir, `${tenant.tenantId}.json`);

    const configData: TenantConfigFile = {
      tenantId: tenant.tenantId,
      name: tenant.name,
      config: tenant.config,
      credentials: tenant.credentials,
      metadata: {
        status: tenant.metadata.status,
      },
    };

    fs.writeFileSync(configPath, JSON.stringify(configData, null, 2));
    logger.info('Tenant configuration saved', { tenantId: tenant.tenantId, path: configPath });
  }

  /**
   * Create default tenant context for "thj"
   */
  private createDefaultTenantContext(): TenantContext {
    return {
      tenantId: DEFAULT_TENANT_ID,
      name: 'The Honey Jar',
      config: {
        ...DEFAULT_TENANT_CONFIG,
        // THJ gets all features enabled
        enabledFeatures: [
          'transformations',
          'notifications',
          'webhooks',
          'knowledge-base',
          'marketing-support',
          'cost-dashboard',
          'advanced-caching',
        ],
        maxTransformationsPerDay: 1000, // Higher limit for internal use
        maxConcurrentTransforms: 10,
      },
      metadata: {
        createdAt: new Date(),
        updatedAt: new Date(),
        status: 'active',
      },
    };
  }
}

// =============================================================================
// Export Singleton Instance
// =============================================================================

export const tenantContextProvider = TenantContextProvider.getInstance();
export default tenantContextProvider;

// =============================================================================
// Convenience Functions
// =============================================================================

/**
 * Get current tenant ID
 * Convenience function for use throughout the codebase
 */
export function getCurrentTenantId(): string {
  return tenantContextProvider.getCurrentTenant().tenantId;
}

/**
 * Get current tenant context
 * Convenience function for use throughout the codebase
 */
export function getCurrentTenant(): TenantContext {
  return tenantContextProvider.getCurrentTenant();
}

/**
 * Check if feature is enabled for current tenant
 * Convenience function for use throughout the codebase
 */
export function isFeatureEnabled(feature: TenantFeature): boolean {
  return tenantContextProvider.isFeatureEnabled(feature);
}

/**
 * Run function within tenant context
 * Convenience function for use throughout the codebase
 */
export async function withTenant<T>(
  tenantId: string,
  fn: () => Promise<T>
): Promise<T> {
  return tenantContextProvider.withTenantContext(tenantId, fn);
}
