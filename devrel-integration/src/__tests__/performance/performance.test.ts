/**
 * Performance Tests
 *
 * Sprint 4 Task 4.3: Performance Testing & Optimization
 *
 * Tests performance benchmarks for:
 * - Transformation duration
 * - API response times
 * - Discord command response times
 * - Concurrent load handling
 * - Memory usage
 */

import { ContentSanitizer } from '../../services/content-sanitizer';
import { SecretScanner } from '../../services/secret-scanner';
import { InputValidator } from '../../validators/input-validator';

describe('Performance Tests', () => {
  describe('Content Processing Performance', () => {
    const contentSanitizer = new ContentSanitizer();
    const secretScanner = new SecretScanner();
    const inputValidator = new InputValidator();

    // Generate test content of various sizes
    const generateContent = (sizeKB: number): string => {
      const baseContent =
        'This is test content for performance testing. ' +
        'It contains various words and sentences. ';
      const targetSize = sizeKB * 1024;
      let content = '';
      while (content.length < targetSize) {
        content += baseContent;
      }
      return content.substring(0, targetSize);
    };

    describe('Content Sanitization Performance', () => {
      it('should sanitize small content (<1KB) in under 10ms', () => {
        const content = generateContent(1);
        const start = performance.now();

        contentSanitizer.sanitizeContent(content);

        const duration = performance.now() - start;
        expect(duration).toBeLessThan(10);
      });

      it('should sanitize medium content (10KB) in under 50ms', () => {
        const content = generateContent(10);
        const start = performance.now();

        contentSanitizer.sanitizeContent(content);

        const duration = performance.now() - start;
        expect(duration).toBeLessThan(50);
      });

      it('should sanitize large content (100KB) in under 500ms', () => {
        const content = generateContent(100);
        const start = performance.now();

        contentSanitizer.sanitizeContent(content);

        const duration = performance.now() - start;
        expect(duration).toBeLessThan(500);
      });
    });

    describe('Secret Scanning Performance', () => {
      it('should scan small content (<1KB) in under 50ms', () => {
        const content = generateContent(1);
        const start = performance.now();

        secretScanner.scanForSecrets(content);

        const duration = performance.now() - start;
        expect(duration).toBeLessThan(50);
      });

      it('should scan medium content (10KB) in under 200ms', () => {
        const content = generateContent(10);
        const start = performance.now();

        secretScanner.scanForSecrets(content);

        const duration = performance.now() - start;
        expect(duration).toBeLessThan(200);
      });

      it('should scan large content (100KB) in under 2000ms', () => {
        const content = generateContent(100);
        const start = performance.now();

        secretScanner.scanForSecrets(content);

        const duration = performance.now() - start;
        expect(duration).toBeLessThan(2000);
      });
    });

    describe('Input Validation Performance', () => {
      it('should validate path in under 1ms', () => {
        const start = performance.now();

        for (let i = 0; i < 100; i++) {
          inputValidator.validateDocumentPath(`docs/test-${i}.md`);
        }

        const duration = performance.now() - start;
        const perOperation = duration / 100;
        expect(perOperation).toBeLessThan(1);
      });

      it('should validate multiple paths in under 10ms', () => {
        const paths = Array.from({ length: 10 }, (_, i) => `docs/test-${i}.md`);
        const start = performance.now();

        inputValidator.validateDocumentPaths(paths);

        const duration = performance.now() - start;
        expect(duration).toBeLessThan(10);
      });
    });
  });

  describe('Concurrent Processing Performance', () => {
    it('should handle 10 concurrent sanitization requests', async () => {
      const contentSanitizer = new ContentSanitizer();
      const content =
        'Test content for concurrent processing '.repeat(100);

      const start = performance.now();

      const promises = Array.from({ length: 10 }, () =>
        Promise.resolve(contentSanitizer.sanitizeContent(content))
      );

      await Promise.all(promises);

      const duration = performance.now() - start;
      // All 10 should complete in under 100ms
      expect(duration).toBeLessThan(100);
    });

    it('should handle 10 concurrent secret scans', async () => {
      const secretScanner = new SecretScanner();
      const content =
        'Test content for concurrent secret scanning '.repeat(100);

      const start = performance.now();

      const promises = Array.from({ length: 10 }, () =>
        Promise.resolve(secretScanner.scanForSecrets(content))
      );

      await Promise.all(promises);

      const duration = performance.now() - start;
      // All 10 should complete in under 500ms
      expect(duration).toBeLessThan(500);
    });
  });

  describe('Memory Usage', () => {
    it('should not leak memory during repeated operations', () => {
      const contentSanitizer = new ContentSanitizer();
      const content = 'Test content '.repeat(1000);

      // Get initial memory usage
      const initialMemory = process.memoryUsage().heapUsed;

      // Perform many operations
      for (let i = 0; i < 1000; i++) {
        contentSanitizer.sanitizeContent(content);
      }

      // Force garbage collection if available
      if (global.gc) {
        global.gc();
      }

      // Check memory usage hasn't grown excessively
      const finalMemory = process.memoryUsage().heapUsed;
      const memoryGrowthMB = (finalMemory - initialMemory) / (1024 * 1024);

      // Memory growth should be under 50MB for 1000 operations
      expect(memoryGrowthMB).toBeLessThan(50);
    });
  });

  describe('Throughput Benchmarks', () => {
    it('should process at least 100 validations per second', () => {
      const inputValidator = new InputValidator();
      const operationsCount = 100;

      const start = performance.now();

      for (let i = 0; i < operationsCount; i++) {
        inputValidator.validateDocumentPath(`docs/test-${i}.md`);
        inputValidator.validateAudience('leadership');
      }

      const duration = performance.now() - start;
      const opsPerSecond = (operationsCount * 2 * 1000) / duration;

      expect(opsPerSecond).toBeGreaterThan(100);
    });

    it('should sanitize at least 10 documents per second (10KB each)', () => {
      const contentSanitizer = new ContentSanitizer();
      const content = 'Test content '.repeat(1000); // ~12KB
      const documentsCount = 10;

      const start = performance.now();

      for (let i = 0; i < documentsCount; i++) {
        contentSanitizer.sanitizeContent(content);
      }

      const duration = performance.now() - start;
      const docsPerSecond = (documentsCount * 1000) / duration;

      expect(docsPerSecond).toBeGreaterThan(10);
    });
  });

  describe('Response Time Targets', () => {
    describe('Target: <60 seconds for document transformation', () => {
      it('should complete full security pipeline in under 1 second', () => {
        const contentSanitizer = new ContentSanitizer();
        const secretScanner = new SecretScanner();
        const inputValidator = new InputValidator();

        // Simulate full transformation pipeline
        const content = 'Test document content '.repeat(500); // ~10KB

        const start = performance.now();

        // Step 1: Input validation
        inputValidator.validateDocumentPath('docs/prd.md');
        inputValidator.validateAudience('leadership');

        // Step 2: Content sanitization
        const sanitized = contentSanitizer.sanitizeContent(content);

        // Step 3: Secret scanning
        secretScanner.scanForSecrets(sanitized.sanitized);

        const duration = performance.now() - start;

        // Security pipeline should complete in under 1 second
        // (AI transformation is external and tested separately)
        expect(duration).toBeLessThan(1000);
      });
    });

    describe('Target: <15 seconds for initial Discord response', () => {
      it('should acknowledge command in under 100ms', () => {
        // Simulate command acknowledgment
        const start = performance.now();

        // Minimal processing for acknowledgment
        const inputValidator = new InputValidator();
        inputValidator.validateCommandArgs('translate', ['mibera', '@prd', 'for', 'leadership']);

        const duration = performance.now() - start;

        // Initial acknowledgment should be instant
        expect(duration).toBeLessThan(100);
      });
    });
  });

  describe('Stress Tests', () => {
    it('should handle burst of 50 requests without failure', async () => {
      const contentSanitizer = new ContentSanitizer();
      const secretScanner = new SecretScanner();
      const content = 'Test content '.repeat(100);

      const results: boolean[] = [];

      const processRequest = async (): Promise<boolean> => {
        try {
          const sanitized = contentSanitizer.sanitizeContent(content);
          secretScanner.scanForSecrets(sanitized.sanitized);
          return true;
        } catch {
          return false;
        }
      };

      // Burst of 50 concurrent requests
      const promises = Array.from({ length: 50 }, () => processRequest());
      const batchResults = await Promise.all(promises);
      results.push(...batchResults);

      // All requests should succeed
      expect(results.every((r) => r === true)).toBe(true);
      expect(results.length).toBe(50);
    });

    it('should maintain performance under sustained load', async () => {
      const inputValidator = new InputValidator();
      const iterations = 1000;
      const durations: number[] = [];

      for (let i = 0; i < iterations; i++) {
        const start = performance.now();
        inputValidator.validateDocumentPath(`docs/test-${i % 100}.md`);
        durations.push(performance.now() - start);
      }

      // Calculate statistics
      const avgDuration = durations.reduce((a, b) => a + b, 0) / durations.length;
      const maxDuration = Math.max(...durations);

      // Average should be under 1ms
      expect(avgDuration).toBeLessThan(1);

      // Max should be under 10ms (no outliers)
      expect(maxDuration).toBeLessThan(10);
    });
  });
});
