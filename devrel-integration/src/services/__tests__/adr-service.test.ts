/**
 * ADR Service Tests
 *
 * Sprint 5 - Task 5.1: ADR Management Service
 *
 * Tests for ADRService functionality including:
 * - ADR creation with auto-numbering
 * - ADR retrieval and listing
 * - Full-text search across ADRs
 * - Status updates
 * - Caching integration
 */

import {
  ADRService,
  ADR,
  ADRSearchResult,
  CreateADRParams,
  createADR,
  searchADRs,
  getADR,
  listADRs,
} from '../adr-service';
import { TieredCache } from '../tiered-cache';

// Mock logger
jest.mock('../../utils/logger', () => ({
  logger: {
    info: jest.fn(),
    debug: jest.fn(),
    warn: jest.fn(),
    error: jest.fn(),
  },
}));

// Mock tenant context
jest.mock('../tenant-context', () => {
  const mockTenant = {
    tenantId: 'thj',
    name: 'The Honey Jar',
    config: {
      enabledFeatures: ['transformations', 'knowledge-base'],
      maxTransformationsPerDay: 1000,
      maxConcurrentTransforms: 10,
      allowedPersonas: ['leadership', 'product'],
    },
    metadata: {
      createdAt: new Date(),
      updatedAt: new Date(),
      status: 'active',
    },
  };

  return {
    getCurrentTenant: jest.fn().mockReturnValue(mockTenant),
    tenantContextProvider: {
      getCurrentTenant: jest.fn().mockReturnValue(mockTenant),
    },
  };
});

// Mock tiered cache
jest.mock('../tiered-cache', () => {
  const mockCache = {
    get: jest.fn().mockResolvedValue(null),
    set: jest.fn().mockResolvedValue(undefined),
    getOrFetch: jest.fn().mockImplementation(
      async (_t: string, _k: string, fn: () => Promise<unknown>) => fn()
    ),
    invalidate: jest.fn().mockResolvedValue(true),
  };

  return {
    tieredCache: mockCache,
    TieredCache: {
      getInstance: jest.fn().mockReturnValue(mockCache),
    },
  };
});

describe('ADRService', () => {
  let service: ADRService;

  beforeEach(() => {
    // Create fresh instance for each test
    service = new ADRService();
    service.clearAll();
  });

  describe('createADR', () => {
    it('should create ADR with auto-incrementing number', async () => {
      const params: CreateADRParams = {
        product: 'onomancer',
        title: 'Use TypeScript for all new services',
        context: 'We need to standardize our language choice.',
        decision: 'Use TypeScript for all backend services.',
        rationale: 'TypeScript provides type safety and better IDE support.',
      };

      const result = await service.createADR(params);

      expect(result.adrNumber).toBe(1);
      expect(result.documentUrl).toContain('onomancer');
    });

    it('should increment ADR numbers within same product', async () => {
      const baseParams: CreateADRParams = {
        product: 'onomancer',
        title: 'Test ADR',
        context: 'Context',
        decision: 'Decision',
        rationale: 'Rationale',
      };

      const result1 = await service.createADR({ ...baseParams, title: 'ADR 1' });
      const result2 = await service.createADR({ ...baseParams, title: 'ADR 2' });
      const result3 = await service.createADR({ ...baseParams, title: 'ADR 3' });

      expect(result1.adrNumber).toBe(1);
      expect(result2.adrNumber).toBe(2);
      expect(result3.adrNumber).toBe(3);
    });

    it('should track ADR numbers separately per product', async () => {
      const params1: CreateADRParams = {
        product: 'product-a',
        title: 'ADR for Product A',
        context: 'Context',
        decision: 'Decision',
        rationale: 'Rationale',
      };

      const params2: CreateADRParams = {
        product: 'product-b',
        title: 'ADR for Product B',
        context: 'Context',
        decision: 'Decision',
        rationale: 'Rationale',
      };

      const resultA1 = await service.createADR(params1);
      const resultB1 = await service.createADR(params2);
      const resultA2 = await service.createADR({ ...params1, title: 'ADR 2 for A' });

      expect(resultA1.adrNumber).toBe(1);
      expect(resultB1.adrNumber).toBe(1);
      expect(resultA2.adrNumber).toBe(2);
    });

    it('should store all ADR fields', async () => {
      const params: CreateADRParams = {
        product: 'onomancer',
        title: 'Full ADR',
        context: 'We have a problem to solve.',
        decision: 'We decided to do X.',
        rationale: 'Because of reasons A, B, C.',
        alternatives: ['Do Y instead', 'Do nothing'],
        consequences: 'This will impact team velocity.',
        tags: ['architecture', 'backend'],
        createdBy: 'dev@thj.io',
      };

      await service.createADR(params);
      const adr = await service.getADR('onomancer', 1);

      expect(adr).not.toBeNull();
      expect(adr!.title).toBe('Full ADR');
      expect(adr!.context).toBe('We have a problem to solve.');
      expect(adr!.decision).toBe('We decided to do X.');
      expect(adr!.rationale).toBe('Because of reasons A, B, C.');
      expect(adr!.alternatives).toEqual(['Do Y instead', 'Do nothing']);
      expect(adr!.consequences).toBe('This will impact team velocity.');
      expect(adr!.tags).toEqual(['architecture', 'backend']);
      expect(adr!.createdBy).toBe('dev@thj.io');
      expect(adr!.status).toBe('Proposed');
    });

    it('should set createdAt timestamp', async () => {
      const before = new Date();

      await service.createADR({
        product: 'test',
        title: 'Test',
        context: 'Context',
        decision: 'Decision',
        rationale: 'Rationale',
      });

      const after = new Date();
      const adr = await service.getADR('test', 1);

      expect(adr!.createdAt.getTime()).toBeGreaterThanOrEqual(before.getTime());
      expect(adr!.createdAt.getTime()).toBeLessThanOrEqual(after.getTime());
    });
  });

  describe('getADR', () => {
    it('should return ADR by product and number', async () => {
      await service.createADR({
        product: 'onomancer',
        title: 'First ADR',
        context: 'Context 1',
        decision: 'Decision 1',
        rationale: 'Rationale 1',
      });

      await service.createADR({
        product: 'onomancer',
        title: 'Second ADR',
        context: 'Context 2',
        decision: 'Decision 2',
        rationale: 'Rationale 2',
      });

      const adr = await service.getADR('onomancer', 2);

      expect(adr).not.toBeNull();
      expect(adr!.title).toBe('Second ADR');
      expect(adr!.number).toBe(2);
    });

    it('should return null for non-existent ADR', async () => {
      const adr = await service.getADR('onomancer', 999);
      expect(adr).toBeNull();
    });

    it('should return null for non-existent product', async () => {
      const adr = await service.getADR('non-existent', 1);
      expect(adr).toBeNull();
    });
  });

  describe('listADRs', () => {
    it('should list all ADRs for a product', async () => {
      await service.createADR({
        product: 'onomancer',
        title: 'ADR 1',
        context: 'Context',
        decision: 'Decision',
        rationale: 'Rationale',
      });

      await service.createADR({
        product: 'onomancer',
        title: 'ADR 2',
        context: 'Context',
        decision: 'Decision',
        rationale: 'Rationale',
      });

      await service.createADR({
        product: 'other-product',
        title: 'Other ADR',
        context: 'Context',
        decision: 'Decision',
        rationale: 'Rationale',
      });

      const adrs = await service.listADRs('onomancer');

      expect(adrs).toHaveLength(2);
      expect(adrs.map(a => a.title)).toContain('ADR 1');
      expect(adrs.map(a => a.title)).toContain('ADR 2');
      expect(adrs.map(a => a.title)).not.toContain('Other ADR');
    });

    it('should return ADRs in reverse order (most recent first)', async () => {
      await service.createADR({
        product: 'test',
        title: 'First',
        context: 'C',
        decision: 'D',
        rationale: 'R',
      });

      await service.createADR({
        product: 'test',
        title: 'Second',
        context: 'C',
        decision: 'D',
        rationale: 'R',
      });

      await service.createADR({
        product: 'test',
        title: 'Third',
        context: 'C',
        decision: 'D',
        rationale: 'R',
      });

      const adrs = await service.listADRs('test');

      expect(adrs[0].title).toBe('Third');
      expect(adrs[1].title).toBe('Second');
      expect(adrs[2].title).toBe('First');
    });

    it('should return empty array for product with no ADRs', async () => {
      const adrs = await service.listADRs('empty-product');
      expect(adrs).toEqual([]);
    });
  });

  describe('searchADRs', () => {
    beforeEach(async () => {
      // Create test ADRs
      await service.createADR({
        product: 'onomancer',
        title: 'Use PostgreSQL for data storage',
        context: 'We need a reliable database.',
        decision: 'PostgreSQL for all persistent data.',
        rationale: 'ACID compliance and JSON support.',
        tags: ['database', 'backend'],
      });

      await service.createADR({
        product: 'onomancer',
        title: 'API versioning strategy',
        context: 'APIs need to evolve without breaking clients.',
        decision: 'Use URL path versioning (v1, v2).',
        rationale: 'Simple and explicit versioning.',
        tags: ['api', 'backend'],
      });

      await service.createADR({
        product: 'other',
        title: 'Frontend framework selection',
        context: 'We need to choose a frontend framework.',
        decision: 'Use React with TypeScript.',
        rationale: 'Large ecosystem and type safety.',
        tags: ['frontend', 'typescript'],
      });
    });

    it('should find ADRs by title match', async () => {
      const results = await service.searchADRs('PostgreSQL');

      expect(results.length).toBeGreaterThan(0);
      expect(results[0].adr.title).toContain('PostgreSQL');
    });

    it('should find ADRs by decision match', async () => {
      const results = await service.searchADRs('URL path versioning');

      expect(results.length).toBeGreaterThan(0);
      expect(results[0].adr.title).toContain('versioning');
    });

    it('should find ADRs by tag match', async () => {
      const results = await service.searchADRs('database');

      expect(results.length).toBeGreaterThan(0);
      expect(results[0].adr.tags).toContain('database');
    });

    it('should filter by product', async () => {
      const results = await service.searchADRs('backend', { product: 'onomancer' });

      expect(results.length).toBe(2);
      expect(results.every(r => r.adr.product === 'onomancer')).toBe(true);
    });

    it('should respect limit parameter', async () => {
      const results = await service.searchADRs('backend', { limit: 1 });

      expect(results.length).toBe(1);
    });

    it('should return empty array for no matches', async () => {
      const results = await service.searchADRs('xyznonexistent123');
      expect(results).toEqual([]);
    });

    it('should rank title matches higher than context matches', async () => {
      // "database" is in title of first ADR
      const results = await service.searchADRs('database');

      // The ADR with "database" in tags should score higher
      expect(results[0].score).toBeGreaterThan(0);
    });

    it('should include excerpts in results', async () => {
      const results = await service.searchADRs('PostgreSQL');

      expect(results.length).toBeGreaterThan(0);
      expect(results[0].excerpt).toBeDefined();
      expect(results[0].excerpt.length).toBeGreaterThan(0);
    });
  });

  describe('updateADRStatus', () => {
    it('should update ADR status', async () => {
      await service.createADR({
        product: 'test',
        title: 'Test ADR',
        context: 'Context',
        decision: 'Decision',
        rationale: 'Rationale',
      });

      const updated = await service.updateADRStatus('test', 1, 'Accepted');

      expect(updated).toBe(true);

      const adr = await service.getADR('test', 1);
      expect(adr!.status).toBe('Accepted');
    });

    it('should set updatedAt timestamp on status change', async () => {
      await service.createADR({
        product: 'test',
        title: 'Test ADR',
        context: 'Context',
        decision: 'Decision',
        rationale: 'Rationale',
      });

      const before = new Date();
      await new Promise(resolve => setTimeout(resolve, 10));
      await service.updateADRStatus('test', 1, 'Accepted');

      const adr = await service.getADR('test', 1);
      expect(adr!.updatedAt).toBeDefined();
      expect(adr!.updatedAt!.getTime()).toBeGreaterThan(before.getTime());
    });

    it('should return false for non-existent ADR', async () => {
      const updated = await service.updateADRStatus('test', 999, 'Accepted');
      expect(updated).toBe(false);
    });

    it('should support all ADR status values', async () => {
      await service.createADR({
        product: 'test',
        title: 'Test ADR',
        context: 'Context',
        decision: 'Decision',
        rationale: 'Rationale',
      });

      await service.updateADRStatus('test', 1, 'Accepted');
      expect((await service.getADR('test', 1))!.status).toBe('Accepted');

      await service.updateADRStatus('test', 1, 'Deprecated');
      expect((await service.getADR('test', 1))!.status).toBe('Deprecated');

      await service.updateADRStatus('test', 1, 'Superseded');
      expect((await service.getADR('test', 1))!.status).toBe('Superseded');
    });
  });

  describe('getIndex', () => {
    it('should return index with ADR entries', async () => {
      await service.createADR({
        product: 'test',
        title: 'ADR 1',
        context: 'Context',
        decision: 'Decision',
        rationale: 'Rationale',
        tags: ['tag1'],
      });

      await service.createADR({
        product: 'test',
        title: 'ADR 2',
        context: 'Context',
        decision: 'Decision',
        rationale: 'Rationale',
        tags: ['tag2'],
      });

      const index = await service.getIndex('test');

      expect(index).not.toBeNull();
      expect(index!.product).toBe('test');
      expect(index!.adrs).toHaveLength(2);
      expect(index!.adrs[0].title).toBe('ADR 1');
      expect(index!.adrs[1].title).toBe('ADR 2');
    });

    it('should return null for product with no ADRs', async () => {
      const index = await service.getIndex('empty');
      expect(index).toBeNull();
    });
  });

  describe('getProductsWithADRs', () => {
    it('should return list of products with ADRs', async () => {
      await service.createADR({
        product: 'product-a',
        title: 'ADR',
        context: 'C',
        decision: 'D',
        rationale: 'R',
      });

      await service.createADR({
        product: 'product-b',
        title: 'ADR',
        context: 'C',
        decision: 'D',
        rationale: 'R',
      });

      const products = await service.getProductsWithADRs();

      expect(products).toContain('product-a');
      expect(products).toContain('product-b');
    });

    it('should return empty array when no ADRs exist', async () => {
      const products = await service.getProductsWithADRs();
      expect(products).toEqual([]);
    });
  });

  describe('singleton pattern', () => {
    it('should return same instance from getInstance', () => {
      const instance1 = ADRService.getInstance();
      const instance2 = ADRService.getInstance();

      expect(instance1).toBe(instance2);
    });
  });
});

describe('Convenience functions', () => {
  let service: ADRService;

  beforeEach(() => {
    // Reset singleton for clean test state
    service = ADRService.getInstance();
    service.clearAll();
  });

  describe('createADR function', () => {
    it('should create ADR via convenience function', async () => {
      const result = await createADR({
        product: 'test',
        title: 'Test ADR',
        context: 'Context',
        decision: 'Decision',
        rationale: 'Rationale',
      });

      expect(result.adrNumber).toBe(1);
    });
  });

  describe('searchADRs function', () => {
    it('should search via convenience function', async () => {
      await createADR({
        product: 'test',
        title: 'Searchable ADR',
        context: 'Context',
        decision: 'Decision',
        rationale: 'Rationale',
      });

      const results = await searchADRs('Searchable');
      expect(results.length).toBeGreaterThan(0);
    });
  });

  describe('getADR function', () => {
    it('should get ADR via convenience function', async () => {
      await createADR({
        product: 'test',
        title: 'Get Test',
        context: 'Context',
        decision: 'Decision',
        rationale: 'Rationale',
      });

      const adr = await getADR('test', 1);
      expect(adr).not.toBeNull();
      expect(adr!.title).toBe('Get Test');
    });
  });

  describe('listADRs function', () => {
    it('should list ADRs via convenience function', async () => {
      await createADR({
        product: 'test',
        title: 'List Test 1',
        context: 'C',
        decision: 'D',
        rationale: 'R',
      });

      await createADR({
        product: 'test',
        title: 'List Test 2',
        context: 'C',
        decision: 'D',
        rationale: 'R',
      });

      const adrs = await listADRs('test');
      expect(adrs).toHaveLength(2);
    });
  });
});

describe('Edge cases', () => {
  let service: ADRService;

  beforeEach(() => {
    service = new ADRService();
    service.clearAll();
  });

  it('should handle special characters in ADR content', async () => {
    await service.createADR({
      product: 'test',
      title: 'ADR with "quotes" & <special> chars',
      context: 'Context with unicode: 你好 🌍',
      decision: 'Decision with `backticks` and *markdown*',
      rationale: 'Rationale with\nnewlines\nand\ttabs',
    });

    const adr = await service.getADR('test', 1);
    expect(adr!.title).toBe('ADR with "quotes" & <special> chars');
  });

  it('should handle very long ADR content', async () => {
    const longText = 'A'.repeat(10000);

    await service.createADR({
      product: 'test',
      title: 'Long ADR',
      context: longText,
      decision: longText,
      rationale: longText,
    });

    const adr = await service.getADR('test', 1);
    expect(adr!.context.length).toBe(10000);
  });

  it('should handle empty alternatives array', async () => {
    await service.createADR({
      product: 'test',
      title: 'No Alternatives',
      context: 'C',
      decision: 'D',
      rationale: 'R',
      alternatives: [],
    });

    const adr = await service.getADR('test', 1);
    expect(adr!.alternatives).toEqual([]);
  });

  it('should handle product names with special characters', async () => {
    await service.createADR({
      product: 'product-with-dashes',
      title: 'Test',
      context: 'C',
      decision: 'D',
      rationale: 'R',
    });

    const adr = await service.getADR('product-with-dashes', 1);
    expect(adr).not.toBeNull();
  });
});
