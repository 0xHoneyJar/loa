/**
 * Tenant Context Types
 *
 * Sprint 4 - Task 4.0: Tenant Context Foundation
 *
 * Defines tenant context interfaces and types for multi-tenancy support.
 * This foundation enables future SaaS transformation with minimal refactoring.
 *
 * Current Implementation:
 * - Single tenant ("thj" - The Honey Jar) hardcoded for MVP
 * - TenantContext passed through services for future extensibility
 * - Configuration loaded from /config/tenants/{tenantId}.json
 */

// =============================================================================
// Core Tenant Types
// =============================================================================

/**
 * Tenant configuration for feature flags and limits
 */
export interface TenantConfig {
  /** Features enabled for this tenant */
  enabledFeatures: TenantFeature[];
  /** Maximum transformations allowed per day */
  maxTransformationsPerDay: number;
  /** Maximum concurrent transformations */
  maxConcurrentTransforms: number;
  /** Personas this tenant can use */
  allowedPersonas: PersonaType[];
  /** Cache TTL overrides (in seconds) */
  cacheTTL?: {
    documentContent?: number;
    transformResults?: number;
    folderIds?: number;
  };
  /** Rate limit overrides */
  rateLimits?: {
    transformationsPerMinute?: number;
    apiCallsPerMinute?: number;
  };
}

/**
 * Tenant quotas and usage tracking
 */
export interface TenantQuotas {
  /** Current usage counts */
  current: {
    transformationsToday: number;
    concurrentTransforms: number;
    apiCallsThisMinute: number;
  };
  /** Quota limits (from config) */
  limits: {
    maxTransformationsPerDay: number;
    maxConcurrentTransforms: number;
    maxApiCallsPerMinute: number;
  };
  /** Usage reset timestamps */
  resetTimes: {
    dailyReset: Date;
    minuteReset: Date;
  };
}

/**
 * Tenant credentials and secrets
 * NOTE: In production SaaS, tenants would bring their own credentials
 */
export interface TenantCredentials {
  /** Google Workspace configuration */
  googleWorkspace?: {
    serviceAccountKeyPath?: string;
    delegatedUserEmail?: string;
    folderId?: string;
  };
  /** Discord bot configuration */
  discord?: {
    guildId?: string;
    notificationChannelId?: string;
  };
  /** Linear workspace configuration */
  linear?: {
    teamId?: string;
    projectId?: string;
  };
}

/**
 * Complete tenant context
 */
export interface TenantContext {
  /** Unique tenant identifier */
  tenantId: string;
  /** Display name for the tenant */
  name: string;
  /** Tenant configuration */
  config: TenantConfig;
  /** Tenant quotas (loaded at runtime) */
  quotas?: TenantQuotas;
  /** Tenant credentials (loaded at runtime) */
  credentials?: TenantCredentials;
  /** Metadata */
  metadata: {
    createdAt: Date;
    updatedAt: Date;
    status: TenantStatus;
  };
}

// =============================================================================
// Enums and Constants
// =============================================================================

/**
 * Features that can be enabled per tenant
 */
export type TenantFeature =
  | 'transformations'
  | 'notifications'
  | 'webhooks'
  | 'knowledge-base'
  | 'marketing-support'
  | 'cost-dashboard'
  | 'advanced-caching';

/**
 * Persona types (duplicated here for tenant context independence)
 */
export type PersonaType = 'leadership' | 'product' | 'marketing' | 'devrel';

/**
 * Tenant status
 */
export type TenantStatus = 'active' | 'suspended' | 'trial' | 'inactive';

// =============================================================================
// Default Values
// =============================================================================

/**
 * Default tenant configuration for new tenants
 */
export const DEFAULT_TENANT_CONFIG: TenantConfig = {
  enabledFeatures: ['transformations', 'notifications'],
  maxTransformationsPerDay: 100,
  maxConcurrentTransforms: 3,
  allowedPersonas: ['leadership', 'product', 'marketing', 'devrel'],
  cacheTTL: {
    documentContent: 15 * 60, // 15 minutes
    transformResults: 30 * 60, // 30 minutes
    folderIds: 60 * 60, // 1 hour
  },
  rateLimits: {
    transformationsPerMinute: 10,
    apiCallsPerMinute: 100,
  },
};

/**
 * Default tenant ID for MVP (The Honey Jar)
 */
export const DEFAULT_TENANT_ID = 'thj';

/**
 * All available features
 */
export const ALL_FEATURES: TenantFeature[] = [
  'transformations',
  'notifications',
  'webhooks',
  'knowledge-base',
  'marketing-support',
  'cost-dashboard',
  'advanced-caching',
];

/**
 * All available personas
 */
export const ALL_PERSONAS: PersonaType[] = [
  'leadership',
  'product',
  'marketing',
  'devrel',
];
