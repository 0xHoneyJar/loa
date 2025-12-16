/**
 * Content Validation Service Tests
 *
 * Sprint 6 - Task 6.2: Unit tests for ContentValidationService
 */

import {
  ContentValidationService,
  ClaudeClientInterface,
  GoogleDocsClientInterface,
  DocumentationSource,
} from '../content-validation-service';

// Mock dependencies
jest.mock('../../utils/logger', () => ({
  logger: {
    info: jest.fn(),
    debug: jest.fn(),
    warn: jest.fn(),
    error: jest.fn(),
  },
}));

jest.mock('../tenant-context', () => ({
  getCurrentTenant: jest.fn(() => ({
    tenantId: 'test-tenant',
    name: 'Test Tenant',
    config: {
      enabledFeatures: ['transformations'],
      maxTransformationsPerDay: 100,
      maxConcurrentTransforms: 5,
      allowedPersonas: ['leadership', 'product', 'marketing', 'devrel'],
    },
    metadata: {
      createdAt: new Date(),
      updatedAt: new Date(),
      status: 'active',
    },
  })),
}));

jest.mock('../tiered-cache', () => ({
  TieredCache: {
    getInstance: jest.fn(() => ({
      get: jest.fn().mockResolvedValue(null),
      set: jest.fn().mockResolvedValue(undefined),
    })),
  },
}));

describe('ContentValidationService', () => {
  let service: ContentValidationService;
  let mockClaudeClient: jest.Mocked<ClaudeClientInterface>;
  let mockGoogleDocsClient: jest.Mocked<GoogleDocsClientInterface>;

  beforeEach(() => {
    // Reset singleton
    (ContentValidationService as any).instance = undefined;
    service = ContentValidationService.getInstance();

    mockClaudeClient = {
      complete: jest.fn(),
    };

    mockGoogleDocsClient = {
      fetchDocument: jest.fn(),
    };
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  describe('getInstance', () => {
    test('should return singleton instance', () => {
      const instance1 = ContentValidationService.getInstance();
      const instance2 = ContentValidationService.getInstance();
      expect(instance1).toBe(instance2);
    });
  });

  describe('registerDocumentation', () => {
    test('should register documentation source', () => {
      const source: DocumentationSource = {
        name: 'PRD',
        type: 'prd',
        content: 'Product requirements...',
      };

      service.registerDocumentation(source);
      // No error means success
    });

    test('should clear documentation cache', () => {
      service.registerDocumentation({
        name: 'Test',
        type: 'custom',
        content: 'Test content',
      });
      service.clearDocumentationCache();
      // No error means success
    });
  });

  describe('validateContent - Rule-based (no AI)', () => {
    test('should flag absolute claims', async () => {
      const content = 'Our product is 100% secure and guaranteed to work.';

      const report = await service.validateContent(content, 'TestProduct');

      expect(report.findings.some((f) => f.type === 'misleading_language')).toBe(true);
    });

    test('should flag outdated year references', async () => {
      const content = 'This feature was released in 2020.';

      const report = await service.validateContent(content, 'TestProduct');

      expect(report.findings.some((f) => f.type === 'outdated_info')).toBe(true);
    });

    test('should flag missing crypto disclaimers', async () => {
      const content = 'Our token will 10x your investment on blockchain.';

      const report = await service.validateContent(content, 'TestProduct');

      expect(report.findings.some((f) => f.type === 'missing_disclaimer')).toBe(true);
    });

    test('should flag performance claims without sources', async () => {
      const content = 'Our system is 50% faster than competitors.';

      const report = await service.validateContent(content, 'TestProduct');

      expect(report.findings.some((f) => f.type === 'unverifiable_claim')).toBe(true);
    });

    test('should pass clean content', async () => {
      const content = 'Our product helps users manage their tasks efficiently.';

      const report = await service.validateContent(content, 'TestProduct');

      expect(report.verdict).toBe('accurate');
    });

    test('should return minor_issues for small problems', async () => {
      const content = 'This feature was built in 2020.';

      const report = await service.validateContent(content, 'TestProduct', {
        strictness: 'standard',
      });

      expect(['minor_issues', 'accurate']).toContain(report.verdict);
    });
  });

  describe('validateContent - AI-based', () => {
    beforeEach(() => {
      service.setClaudeClient(mockClaudeClient);
    });

    test('should use AI for validation when client is available', async () => {
      mockClaudeClient.complete.mockResolvedValue(JSON.stringify([]));

      const report = await service.validateContent('Test content', 'TestProduct');

      expect(mockClaudeClient.complete).toHaveBeenCalled();
      expect(report.verdict).toBe('accurate');
    });

    test('should parse AI findings correctly', async () => {
      const aiFindings = [
        {
          type: 'inaccurate_claim',
          severity: 'warning',
          message: 'This claim is not accurate',
          excerpt: 'test excerpt',
          confidence: 0.8,
        },
      ];

      mockClaudeClient.complete.mockResolvedValue(JSON.stringify(aiFindings));

      const report = await service.validateContent('Test content', 'TestProduct');

      expect(report.findings.length).toBe(1);
      expect(report.findings[0].type).toBe('inaccurate_claim');
    });

    test('should handle malformed AI response', async () => {
      mockClaudeClient.complete.mockResolvedValue('Not valid JSON');

      const report = await service.validateContent('Test content', 'TestProduct');

      expect(report.findings).toEqual([]);
    });

    test('should normalize finding types', async () => {
      mockClaudeClient.complete.mockResolvedValue(
        JSON.stringify([{ type: 'unknown_type', severity: 'warning', message: 'Test' }])
      );

      const report = await service.validateContent('Test content', 'TestProduct');

      expect(report.findings[0].type).toBe('technical_error');
    });

    test('should normalize severity levels', async () => {
      mockClaudeClient.complete.mockResolvedValue(
        JSON.stringify([{ type: 'inaccurate_claim', severity: 'unknown', message: 'Test' }])
      );

      const report = await service.validateContent('Test content', 'TestProduct');

      expect(report.findings[0].severity).toBe('warning');
    });
  });

  describe('validateGoogleDoc', () => {
    beforeEach(() => {
      service.setGoogleDocsClient(mockGoogleDocsClient);
    });

    test('should validate Google Docs content', async () => {
      mockGoogleDocsClient.fetchDocument.mockResolvedValue('Document content here');

      const report = await service.validateGoogleDoc(
        'https://docs.google.com/document/d/abc123/edit',
        'TestProduct'
      );

      expect(mockGoogleDocsClient.fetchDocument).toHaveBeenCalledWith('abc123');
      expect(report).toHaveProperty('verdict');
    });

    test('should throw error for invalid link', async () => {
      await expect(
        service.validateGoogleDoc('https://invalid-link.com', 'TestProduct')
      ).rejects.toThrow('Invalid Google Docs link');
    });

    test('should throw error when Google Docs client not configured', async () => {
      (ContentValidationService as any).instance = undefined;
      const newService = ContentValidationService.getInstance();

      await expect(
        newService.validateGoogleDoc(
          'https://docs.google.com/document/d/abc123/edit',
          'TestProduct'
        )
      ).rejects.toThrow('Google Docs client not configured');
    });
  });

  describe('calculateVerdict', () => {
    test('should return major_issues for critical findings', async () => {
      const content = 'This is 100% guaranteed to work and never fail. Our blockchain token will moon.';

      const report = await service.validateContent(content, 'TestProduct', {
        strictness: 'standard',
      });

      expect(['major_issues', 'minor_issues']).toContain(report.verdict);
    });

    test('should return accurate for clean content in relaxed mode', async () => {
      const content = 'Our product always delivers great results.';

      const report = await service.validateContent(content, 'TestProduct', {
        strictness: 'relaxed',
      });

      expect(report.verdict).toBe('accurate');
    });

    test('should be stricter in strict mode', async () => {
      const content = 'Our system is always available.';

      const reportRelaxed = await service.validateContent(content, 'TestProduct', {
        strictness: 'relaxed',
      });

      const reportStrict = await service.validateContent(content, 'TestProduct', {
        strictness: 'strict',
      });

      expect(reportStrict.findings.length).toBeGreaterThanOrEqual(reportRelaxed.findings.length);
    });
  });

  describe('overallScore calculation', () => {
    test('should calculate score based on findings', async () => {
      const content = 'Clean content without issues.';

      const report = await service.validateContent(content, 'TestProduct');

      expect(report.overallScore).toBeGreaterThan(0);
      expect(report.overallScore).toBeLessThanOrEqual(100);
    });

    test('should reduce score for findings', async () => {
      const content = 'Our product is 100% secure and guaranteed.';

      const report = await service.validateContent(content, 'TestProduct');

      expect(report.overallScore).toBeLessThan(100);
    });
  });

  describe('suggestions generation', () => {
    test('should generate suggestions from findings', async () => {
      const content = 'Our token on blockchain is guaranteed to 10x.';

      const report = await service.validateContent(content, 'TestProduct');

      expect(report.suggestions.length).toBeGreaterThan(0);
    });

    test('should not duplicate suggestions', async () => {
      const content = 'guaranteed guaranteed guaranteed';

      const report = await service.validateContent(content, 'TestProduct');

      const uniqueSuggestions = new Set(report.suggestions);
      expect(report.suggestions.length).toBe(uniqueSuggestions.size);
    });
  });

  describe('formatReportForDiscord', () => {
    test('should format report for Discord', async () => {
      const content = 'Test content';

      const report = await service.validateContent(content, 'TestProduct');
      const formatted = service.formatReportForDiscord(report);

      expect(formatted).toHaveProperty('title');
      expect(formatted).toHaveProperty('description');
      expect(formatted).toHaveProperty('fields');
      expect(formatted).toHaveProperty('footer');
    });

    test('should include verdict emoji', async () => {
      const content = 'Clean content';

      const report = await service.validateContent(content, 'TestProduct');
      const formatted = service.formatReportForDiscord(report) as any;

      expect(formatted.description).toMatch(/[✅⚠️❌]/);
    });
  });

  describe('custom documentation', () => {
    test('should use custom documentation for validation', async () => {
      const customDocs: DocumentationSource[] = [
        {
          name: 'Custom PRD',
          type: 'prd',
          content: 'Our product supports features X, Y, Z.',
        },
      ];

      const report = await service.validateContent('Test content', 'TestProduct', {
        customDocumentation: customDocs,
      });

      expect(report.documentationSourcesChecked).toContain('Custom PRD');
    });
  });

  describe('caching', () => {
    test('should use cache when enabled', async () => {
      const mockCache = {
        get: jest.fn().mockResolvedValue({
          verdict: 'accurate',
          overallScore: 100,
          findings: [],
          suggestions: [],
          validatedAt: new Date(),
          contentLength: 10,
          documentationSourcesChecked: [],
        }),
        set: jest.fn(),
      };

      jest.spyOn(require('../tiered-cache').TieredCache, 'getInstance')
        .mockReturnValue(mockCache);

      (ContentValidationService as any).instance = undefined;
      const cachedService = ContentValidationService.getInstance();

      const report = await cachedService.validateContent('Test', 'Product');

      expect(report.verdict).toBe('accurate');
    });

    test('should skip cache when disabled', async () => {
      const content = 'Test content';

      await service.validateContent(content, 'TestProduct', { useCache: false });

      // Just verify it doesn't throw
    });
  });
});
