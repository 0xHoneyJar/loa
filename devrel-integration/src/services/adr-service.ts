/**
 * ADR (Architecture Decision Record) Management Service
 *
 * Sprint 5 - Task 5.1: ADR Management Service
 *
 * Provides ADR creation, storage, search, and retrieval functionality.
 * ADRs capture technical decisions with context, rationale, and alternatives.
 *
 * Storage: Google Docs in `/Products/{Product}/ADRs/ADR-{Number}.md`
 *
 * Features:
 * - Create ADRs with structured template
 * - Auto-assign ADR numbers (incrementing)
 * - Full-text search across all ADRs
 * - List/get ADRs by product
 * - Cache ADR index for fast lookups
 */

import { logger } from '../utils/logger';
import { getCurrentTenant } from './tenant-context';
import { tieredCache } from './tiered-cache';

// =============================================================================
// Types
// =============================================================================

export type ADRStatus = 'Proposed' | 'Accepted' | 'Deprecated' | 'Superseded';

export interface ADR {
  /** ADR number within the product */
  number: number;
  /** Product this ADR belongs to */
  product: string;
  /** ADR title */
  title: string;
  /** Current status */
  status: ADRStatus;
  /** Context and problem statement */
  context: string;
  /** The decision made */
  decision: string;
  /** Why this decision was made */
  rationale: string;
  /** Alternatives considered */
  alternatives?: string[];
  /** Consequences of this decision */
  consequences?: string;
  /** Google Doc URL */
  documentUrl?: string;
  /** When the ADR was created */
  createdAt: Date;
  /** Who created the ADR */
  createdBy?: string;
  /** When the ADR was last updated */
  updatedAt?: Date;
  /** Tags for categorization */
  tags?: string[];
}

export interface CreateADRParams {
  product: string;
  title: string;
  context: string;
  decision: string;
  rationale: string;
  alternatives?: string[];
  consequences?: string;
  tags?: string[];
  createdBy?: string;
}

export interface ADRSearchResult {
  adr: ADR;
  /** Match excerpt with context */
  excerpt: string;
  /** Score indicating relevance */
  score: number;
}

export interface ADRIndex {
  product: string;
  adrs: ADRIndexEntry[];
  lastUpdated: Date;
}

export interface ADRIndexEntry {
  number: number;
  title: string;
  status: ADRStatus;
  createdAt: Date;
  documentUrl?: string;
  tags?: string[];
}

// =============================================================================
// ADR Template
// =============================================================================

function generateADRContent(adr: ADR): string {
  const header = `# ADR-${adr.number}: ${adr.title}

**Status:** ${adr.status}
**Date:** ${adr.createdAt.toISOString().split('T')[0]}
**Product:** ${adr.product}
${adr.tags?.length ? `**Tags:** ${adr.tags.join(', ')}` : ''}
${adr.createdBy ? `**Author:** ${adr.createdBy}` : ''}

---`;

  const context = `
## Context

${adr.context}`;

  const decision = `
## Decision

${adr.decision}`;

  const rationale = `
## Rationale

${adr.rationale}`;

  const alternatives = adr.alternatives?.length
    ? `
## Alternatives Considered

${adr.alternatives.map((alt, i) => `${i + 1}. ${alt}`).join('\n')}`
    : '';

  const consequences = adr.consequences
    ? `
## Consequences

${adr.consequences}`
    : '';

  const footer = `
---

*This ADR was created via the DevRel Integration Bot.*
*Last updated: ${(adr.updatedAt || adr.createdAt).toISOString()}*`;

  return `${header}${context}${decision}${rationale}${alternatives}${consequences}${footer}`;
}

// =============================================================================
// ADR Service Implementation
// =============================================================================

export class ADRService {
  private static instance: ADRService;

  /** In-memory storage for MVP (replace with Google Docs in production) */
  private adrStore = new Map<string, ADR[]>();

  /** Index for fast lookups */
  private indexStore = new Map<string, ADRIndex>();

  /** Google Docs storage service (injected) */
  private googleDocsService?: {
    createDocument(title: string, content: string, folderId?: string): Promise<{ id: string; url: string }>;
    updateDocument(docId: string, content: string): Promise<void>;
    getDocumentContent(docId: string): Promise<string>;
  };

  constructor() {
    // Initialize with empty stores
  }

  /**
   * Get singleton instance
   */
  static getInstance(): ADRService {
    if (!ADRService.instance) {
      ADRService.instance = new ADRService();
    }
    return ADRService.instance;
  }

  /**
   * Inject Google Docs service for persistence
   */
  setGoogleDocsService(service: typeof this.googleDocsService): void {
    this.googleDocsService = service;
  }

  // ===========================================================================
  // Public API
  // ===========================================================================

  /**
   * Create a new ADR
   */
  async createADR(params: CreateADRParams): Promise<{ adrNumber: number; documentUrl: string }> {
    const tenant = getCurrentTenant();
    const tenantId = tenant.tenantId;

    logger.info('Creating ADR', {
      tenantId,
      product: params.product,
      title: params.title,
    });

    // Get next ADR number for this product
    const adrNumber = await this.getNextADRNumber(params.product);

    // Create ADR object
    const adr: ADR = {
      number: adrNumber,
      product: params.product,
      title: params.title,
      status: 'Proposed',
      context: params.context,
      decision: params.decision,
      rationale: params.rationale,
      alternatives: params.alternatives,
      consequences: params.consequences,
      createdAt: new Date(),
      createdBy: params.createdBy,
      tags: params.tags,
    };

    // Generate document content
    const content = generateADRContent(adr);

    // Store in Google Docs if available
    let documentUrl = '';
    if (this.googleDocsService) {
      try {
        const doc = await this.googleDocsService.createDocument(
          `ADR-${adrNumber}: ${params.title}`,
          content
        );
        documentUrl = doc.url;
        adr.documentUrl = documentUrl;
        logger.info('ADR stored in Google Docs', { adrNumber, documentUrl });
      } catch (error) {
        logger.warn('Failed to store ADR in Google Docs, using in-memory storage', {
          error: error instanceof Error ? error.message : String(error),
        });
      }
    }

    // Store in memory
    const productKey = this.getProductKey(tenantId, params.product);
    if (!this.adrStore.has(productKey)) {
      this.adrStore.set(productKey, []);
    }
    this.adrStore.get(productKey)!.push(adr);

    // Update index
    await this.updateIndex(tenantId, params.product, adr);

    // Invalidate cache
    await tieredCache.invalidate(tenantId, `adr:index:${params.product}`);
    await tieredCache.invalidate(tenantId, `adr:list:${params.product}`);

    logger.info('ADR created successfully', {
      tenantId,
      product: params.product,
      adrNumber,
      documentUrl,
    });

    return {
      adrNumber,
      documentUrl: documentUrl || `local://adr/${params.product}/${adrNumber}`,
    };
  }

  /**
   * Get a specific ADR by product and number
   */
  async getADR(product: string, number: number): Promise<ADR | null> {
    const tenant = getCurrentTenant();
    const tenantId = tenant.tenantId;
    const cacheKey = `adr:${product}:${number}`;

    // Check cache
    const cached = await tieredCache.get<ADR>(tenantId, cacheKey);
    if (cached) {
      return cached;
    }

    // Get from store
    const productKey = this.getProductKey(tenantId, product);
    const adrs = this.adrStore.get(productKey) || [];
    const adr = adrs.find(a => a.number === number) || null;

    if (adr) {
      // Cache for future lookups
      await tieredCache.set(tenantId, cacheKey, adr, 30 * 60); // 30 min TTL
    }

    return adr;
  }

  /**
   * List all ADRs for a product
   */
  async listADRs(product: string): Promise<ADR[]> {
    const tenant = getCurrentTenant();
    const tenantId = tenant.tenantId;
    const cacheKey = `adr:list:${product}`;

    // Check cache
    return await tieredCache.getOrFetch(
      tenantId,
      cacheKey,
      async () => {
        const productKey = this.getProductKey(tenantId, product);
        const adrs = this.adrStore.get(productKey) || [];
        return adrs.sort((a, b) => b.number - a.number); // Most recent first
      },
      { cacheType: 'adr', l2TtlSeconds: 10 * 60 }
    );
  }

  /**
   * Search ADRs across all products
   */
  async searchADRs(query: string, options?: { product?: string; limit?: number }): Promise<ADRSearchResult[]> {
    const tenant = getCurrentTenant();
    const tenantId = tenant.tenantId;
    const limit = options?.limit || 20;

    logger.debug('Searching ADRs', { tenantId, query, options });

    const results: ADRSearchResult[] = [];
    const queryLower = query.toLowerCase();
    const queryTerms = queryLower.split(/\s+/).filter(t => t.length > 2);

    // Search through all ADRs (or filter by product)
    for (const [key, adrs] of this.adrStore.entries()) {
      if (!key.startsWith(`${tenantId}:`)) continue;

      const product = key.split(':')[1];
      if (options?.product && product !== options.product) continue;

      for (const adr of adrs) {
        const score = this.calculateSearchScore(adr, queryTerms);
        if (score > 0) {
          const excerpt = this.generateExcerpt(adr, queryTerms);
          results.push({ adr, excerpt, score });
        }
      }
    }

    // Sort by score and limit results
    return results
      .sort((a, b) => b.score - a.score)
      .slice(0, limit);
  }

  /**
   * Update an existing ADR's status
   */
  async updateADRStatus(product: string, number: number, status: ADRStatus): Promise<boolean> {
    const tenant = getCurrentTenant();
    const tenantId = tenant.tenantId;

    const adr = await this.getADR(product, number);
    if (!adr) {
      logger.warn('ADR not found for status update', { product, number });
      return false;
    }

    adr.status = status;
    adr.updatedAt = new Date();

    // Invalidate caches
    await tieredCache.invalidate(tenantId, `adr:${product}:${number}`);
    await tieredCache.invalidate(tenantId, `adr:list:${product}`);
    await tieredCache.invalidate(tenantId, `adr:index:${product}`);

    logger.info('ADR status updated', { product, number, status });
    return true;
  }

  /**
   * Get ADR index for a product (lightweight list for UI)
   */
  async getIndex(product: string): Promise<ADRIndex | null> {
    const tenant = getCurrentTenant();
    const tenantId = tenant.tenantId;
    const cacheKey = `adr:index:${product}`;

    return await tieredCache.getOrFetch(
      tenantId,
      cacheKey,
      async () => {
        const key = `${tenantId}:${product}`;
        return this.indexStore.get(key) || null;
      },
      { cacheType: 'adr', l2TtlSeconds: 15 * 60 }
    );
  }

  /**
   * Get all products that have ADRs
   */
  async getProductsWithADRs(): Promise<string[]> {
    const tenant = getCurrentTenant();
    const tenantId = tenant.tenantId;
    const prefix = `${tenantId}:`;

    const products: string[] = [];
    for (const key of this.adrStore.keys()) {
      if (key.startsWith(prefix)) {
        products.push(key.substring(prefix.length));
      }
    }
    return products;
  }

  /**
   * Clear all ADRs (for testing)
   */
  clearAll(): void {
    this.adrStore.clear();
    this.indexStore.clear();
  }

  // ===========================================================================
  // Private Methods
  // ===========================================================================

  /**
   * Get product-scoped key
   */
  private getProductKey(tenantId: string, product: string): string {
    return `${tenantId}:${product}`;
  }

  /**
   * Get next ADR number for a product
   */
  private async getNextADRNumber(product: string): Promise<number> {
    const tenant = getCurrentTenant();
    const productKey = this.getProductKey(tenant.tenantId, product);
    const adrs = this.adrStore.get(productKey) || [];

    if (adrs.length === 0) {
      return 1;
    }

    const maxNumber = Math.max(...adrs.map(a => a.number));
    return maxNumber + 1;
  }

  /**
   * Update the ADR index for a product
   */
  private async updateIndex(tenantId: string, product: string, adr: ADR): Promise<void> {
    const key = `${tenantId}:${product}`;
    let index = this.indexStore.get(key);

    if (!index) {
      index = {
        product,
        adrs: [],
        lastUpdated: new Date(),
      };
      this.indexStore.set(key, index);
    }

    // Add or update entry
    const existingIndex = index.adrs.findIndex(e => e.number === adr.number);
    const entry: ADRIndexEntry = {
      number: adr.number,
      title: adr.title,
      status: adr.status,
      createdAt: adr.createdAt,
      documentUrl: adr.documentUrl,
      tags: adr.tags,
    };

    if (existingIndex >= 0) {
      index.adrs[existingIndex] = entry;
    } else {
      index.adrs.push(entry);
    }

    index.lastUpdated = new Date();
  }

  /**
   * Calculate search relevance score
   */
  private calculateSearchScore(adr: ADR, queryTerms: string[]): number {
    let score = 0;
    const titleLower = adr.title.toLowerCase();
    const contextLower = adr.context.toLowerCase();
    const decisionLower = adr.decision.toLowerCase();
    const rationaleLower = adr.rationale.toLowerCase();
    const tagsLower = (adr.tags || []).join(' ').toLowerCase();

    for (const term of queryTerms) {
      // Title matches are most valuable
      if (titleLower.includes(term)) {
        score += 10;
      }
      // Tags are second most valuable
      if (tagsLower.includes(term)) {
        score += 8;
      }
      // Decision matches
      if (decisionLower.includes(term)) {
        score += 5;
      }
      // Context matches
      if (contextLower.includes(term)) {
        score += 3;
      }
      // Rationale matches
      if (rationaleLower.includes(term)) {
        score += 2;
      }
    }

    return score;
  }

  /**
   * Generate search excerpt with highlighted terms
   */
  private generateExcerpt(adr: ADR, queryTerms: string[]): string {
    // Find the best matching section
    const sections = [
      { name: 'title', text: adr.title },
      { name: 'decision', text: adr.decision },
      { name: 'context', text: adr.context },
      { name: 'rationale', text: adr.rationale },
    ];

    for (const section of sections) {
      const lower = section.text.toLowerCase();
      for (const term of queryTerms) {
        const index = lower.indexOf(term);
        if (index >= 0) {
          // Return excerpt around the match
          const start = Math.max(0, index - 50);
          const end = Math.min(section.text.length, index + term.length + 100);
          let excerpt = section.text.substring(start, end);

          if (start > 0) excerpt = '...' + excerpt;
          if (end < section.text.length) excerpt = excerpt + '...';

          return `[${section.name}] ${excerpt}`;
        }
      }
    }

    // Default to title + decision summary
    return `${adr.title}: ${adr.decision.substring(0, 100)}...`;
  }
}

// =============================================================================
// Export Singleton Instance
// =============================================================================

export const adrService = ADRService.getInstance();
export default adrService;

// =============================================================================
// Convenience Functions
// =============================================================================

/**
 * Create a new ADR
 */
export async function createADR(params: CreateADRParams): Promise<{ adrNumber: number; documentUrl: string }> {
  return adrService.createADR(params);
}

/**
 * Search ADRs
 */
export async function searchADRs(query: string, options?: { product?: string; limit?: number }): Promise<ADRSearchResult[]> {
  return adrService.searchADRs(query, options);
}

/**
 * Get ADR by product and number
 */
export async function getADR(product: string, number: number): Promise<ADR | null> {
  return adrService.getADR(product, number);
}

/**
 * List all ADRs for a product
 */
export async function listADRs(product: string): Promise<ADR[]> {
  return adrService.listADRs(product);
}
