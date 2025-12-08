/**
 * Document Size Validator Tests
 *
 * Tests for HIGH-003: Input Length Limits (DoS Prevention)
 */

import {
  validateDocumentSize,
  validateDigest,
  validateCommandInput,
  validateParameterLength,
  validateDocumentNames,
  prioritizeDocumentsByRecency,
  assertValidDocumentSize,
  assertValidDigest,
  assertValidCommandInput,
  ValidationError,
  DOCUMENT_LIMITS,
  DIGEST_LIMITS,
  INPUT_LIMITS,
  type Document,
} from '../document-size-validator';

describe('Document Size Validator', () => {
  describe('validateDocumentSize', () => {
    test('should pass validation for document within limits', () => {
      const doc: Document = {
        id: '1',
        name: 'test.md',
        content: 'Hello world'.repeat(100), // ~1,100 characters
        pageCount: 5,
        sizeBytes: 2000,
      };

      const result = validateDocumentSize(doc);

      expect(result.valid).toBe(true);
      expect(result.error).toBeUndefined();
    });

    test('should fail validation for document exceeding page limit', () => {
      const doc: Document = {
        id: '1',
        name: 'large-doc.pdf',
        content: 'Content',
        pageCount: 51, // Exceeds MAX_PAGES (50)
      };

      const result = validateDocumentSize(doc);

      expect(result.valid).toBe(false);
      expect(result.error).toContain('exceeds maximum 50 pages');
      expect(result.details).toEqual({
        currentValue: 51,
        maxValue: DOCUMENT_LIMITS.MAX_PAGES,
        metric: 'pages',
      });
    });

    test('should fail validation for document exceeding character limit', () => {
      const doc: Document = {
        id: '1',
        name: 'huge-doc.txt',
        content: 'a'.repeat(100_001), // Exceeds MAX_CHARACTERS (100,000)
        pageCount: 10,
      };

      const result = validateDocumentSize(doc);

      expect(result.valid).toBe(false);
      expect(result.error).toContain('exceeds maximum 100000 characters');
      expect(result.details).toEqual({
        currentValue: 100_001,
        maxValue: DOCUMENT_LIMITS.MAX_CHARACTERS,
        metric: 'characters',
      });
    });

    test('should fail validation for document exceeding size limit', () => {
      const doc: Document = {
        id: '1',
        name: 'large-file.pdf',
        content: 'Content',
        sizeBytes: 11 * 1024 * 1024, // 11 MB, exceeds MAX_SIZE_MB (10)
      };

      const result = validateDocumentSize(doc);

      expect(result.valid).toBe(false);
      expect(result.error).toContain('exceeds maximum 10MB');
      expect(result.details?.metric).toBe('bytes');
    });

    test('should pass validation for document at exact limits', () => {
      const doc: Document = {
        id: '1',
        name: 'boundary-doc.txt',
        content: 'a'.repeat(100_000), // Exactly MAX_CHARACTERS
        pageCount: 50, // Exactly MAX_PAGES
        sizeBytes: 10 * 1024 * 1024, // Exactly MAX_SIZE_BYTES
      };

      const result = validateDocumentSize(doc);

      expect(result.valid).toBe(true);
    });

    test('should handle document without optional fields', () => {
      const doc: Document = {
        id: '1',
        name: 'simple.txt',
        content: 'Short content',
      };

      const result = validateDocumentSize(doc);

      expect(result.valid).toBe(true);
    });
  });

  describe('validateDigest', () => {
    test('should pass validation for digest within limits', () => {
      const docs: Document[] = Array.from({ length: 5 }, (_, i) => ({
        id: `${i}`,
        name: `doc${i}.md`,
        content: 'Content '.repeat(1000), // ~8,000 characters each
      }));

      const result = validateDigest(docs);

      expect(result.valid).toBe(true);
    });

    test('should fail validation for too many documents', () => {
      const docs: Document[] = Array.from({ length: 11 }, (_, i) => ({
        id: `${i}`,
        name: `doc${i}.md`,
        content: 'Content',
      }));

      const result = validateDigest(docs);

      expect(result.valid).toBe(false);
      expect(result.error).toContain('exceeds maximum 10');
      expect(result.details).toEqual({
        currentValue: 11,
        maxValue: DIGEST_LIMITS.MAX_DOCUMENTS,
        metric: 'documents',
      });
    });

    test('should fail validation for total characters exceeding limit', () => {
      const docs: Document[] = Array.from({ length: 10 }, (_, i) => ({
        id: `${i}`,
        name: `doc${i}.md`,
        content: 'a'.repeat(50_001), // 10 docs * 50,001 = 500,010 total
      }));

      const result = validateDigest(docs);

      expect(result.valid).toBe(false);
      expect(result.error).toContain('exceeds maximum 500000');
      expect(result.details?.metric).toBe('total_characters');
    });

    test('should fail validation if any individual document exceeds limits', () => {
      const docs: Document[] = [
        {
          id: '1',
          name: 'normal.md',
          content: 'Normal content',
        },
        {
          id: '2',
          name: 'huge.md',
          content: 'a'.repeat(100_001), // Exceeds individual limit
        },
      ];

      const result = validateDigest(docs);

      expect(result.valid).toBe(false);
      expect(result.error).toContain('exceeds maximum 100000 characters');
    });

    test('should pass validation for empty digest', () => {
      const result = validateDigest([]);

      expect(result.valid).toBe(true);
    });

    test('should pass validation for digest at exact limits', () => {
      const docs: Document[] = Array.from({ length: 10 }, (_, i) => ({
        id: `${i}`,
        name: `doc${i}.md`,
        content: 'a'.repeat(50_000), // 10 docs * 50,000 = 500,000 total
      }));

      const result = validateDigest(docs);

      expect(result.valid).toBe(true);
    });
  });

  describe('validateCommandInput', () => {
    test('should pass validation for short command', () => {
      const input = '/translate @security-audit.md for executives';

      const result = validateCommandInput(input);

      expect(result.valid).toBe(true);
    });

    test('should fail validation for command exceeding limit', () => {
      const input = 'a'.repeat(501); // Exceeds MAX_COMMAND_LENGTH (500)

      const result = validateCommandInput(input);

      expect(result.valid).toBe(false);
      expect(result.error).toContain('exceeds maximum 500 characters');
      expect(result.details).toEqual({
        currentValue: 501,
        maxValue: INPUT_LIMITS.MAX_COMMAND_LENGTH,
        metric: 'characters',
      });
    });

    test('should pass validation for command at exact limit', () => {
      const input = 'a'.repeat(500); // Exactly MAX_COMMAND_LENGTH

      const result = validateCommandInput(input);

      expect(result.valid).toBe(true);
    });
  });

  describe('validateParameterLength', () => {
    test('should pass validation for short parameter', () => {
      const result = validateParameterLength('format', 'executive');

      expect(result.valid).toBe(true);
    });

    test('should fail validation for parameter exceeding limit', () => {
      const longValue = 'a'.repeat(101); // Exceeds MAX_PARAMETER_LENGTH (100)

      const result = validateParameterLength('audience', longValue);

      expect(result.valid).toBe(false);
      expect(result.error).toContain('Parameter "audience" exceeds maximum 100 characters');
      expect(result.details).toEqual({
        currentValue: 101,
        maxValue: INPUT_LIMITS.MAX_PARAMETER_LENGTH,
        metric: 'characters',
      });
    });

    test('should pass validation for parameter at exact limit', () => {
      const value = 'a'.repeat(100); // Exactly MAX_PARAMETER_LENGTH

      const result = validateParameterLength('param', value);

      expect(result.valid).toBe(true);
    });
  });

  describe('validateDocumentNames', () => {
    test('should pass validation for few document names', () => {
      const names = ['doc1.md', 'doc2.md'];

      const result = validateDocumentNames(names);

      expect(result.valid).toBe(true);
    });

    test('should fail validation for too many document names', () => {
      const names = ['doc1.md', 'doc2.md', 'doc3.md', 'doc4.md']; // Exceeds MAX_DOCUMENT_NAMES (3)

      const result = validateDocumentNames(names);

      expect(result.valid).toBe(false);
      expect(result.error).toContain('maximum 3');
      expect(result.details).toEqual({
        currentValue: 4,
        maxValue: INPUT_LIMITS.MAX_DOCUMENT_NAMES,
        metric: 'document_names',
      });
    });

    test('should pass validation for exactly 3 document names', () => {
      const names = ['doc1.md', 'doc2.md', 'doc3.md']; // Exactly MAX_DOCUMENT_NAMES

      const result = validateDocumentNames(names);

      expect(result.valid).toBe(true);
    });

    test('should pass validation for empty list', () => {
      const result = validateDocumentNames([]);

      expect(result.valid).toBe(true);
    });
  });

  describe('prioritizeDocumentsByRecency', () => {
    test('should return all documents if within limit', () => {
      const docs: Document[] = Array.from({ length: 5 }, (_, i) => ({
        id: `${i}`,
        name: `doc${i}.md`,
        content: 'Content',
      }));

      const getLastModified = (doc: Document) =>
        new Date(2025, 11, Number(doc.id) + 1);

      const result = prioritizeDocumentsByRecency(docs, getLastModified);

      expect(result.length).toBe(5);
      expect(result).toEqual(docs);
    });

    test('should return most recent N documents when exceeding limit', () => {
      const docs: Document[] = Array.from({ length: 15 }, (_, i) => ({
        id: `${i}`,
        name: `doc${i}.md`,
        content: 'Content',
      }));

      // Most recent: doc14 (Dec 15), doc13 (Dec 14), ..., doc5 (Dec 6)
      const getLastModified = (doc: Document) =>
        new Date(2025, 11, Number(doc.id) + 1);

      const result = prioritizeDocumentsByRecency(docs, getLastModified);

      expect(result.length).toBe(DIGEST_LIMITS.MAX_DOCUMENTS); // 10
      expect(result[0]!.id).toBe('14'); // Most recent
      expect(result[9]!.id).toBe('5'); // 10th most recent
    });

    test('should handle same last modified dates', () => {
      const docs: Document[] = Array.from({ length: 12 }, (_, i) => ({
        id: `${i}`,
        name: `doc${i}.md`,
        content: 'Content',
      }));

      const sameDate = new Date(2025, 11, 8);
      const getLastModified = () => sameDate;

      const result = prioritizeDocumentsByRecency(docs, getLastModified);

      expect(result.length).toBe(10);
    });
  });

  describe('assertValidDocumentSize', () => {
    test('should not throw for valid document', () => {
      const doc: Document = {
        id: '1',
        name: 'test.md',
        content: 'Valid content',
      };

      expect(() => assertValidDocumentSize(doc)).not.toThrow();
    });

    test('should throw ValidationError for invalid document', () => {
      const doc: Document = {
        id: '1',
        name: 'huge.md',
        content: 'a'.repeat(100_001),
      };

      expect(() => assertValidDocumentSize(doc)).toThrow(ValidationError);
      expect(() => assertValidDocumentSize(doc)).toThrow('exceeds maximum 100000 characters');
    });

    test('should include details in ValidationError', () => {
      const doc: Document = {
        id: '1',
        name: 'huge.md',
        content: 'a'.repeat(100_001),
      };

      try {
        assertValidDocumentSize(doc);
        fail('Should have thrown ValidationError');
      } catch (error) {
        expect(error).toBeInstanceOf(ValidationError);
        const validationError = error as ValidationError;
        expect(validationError.details).toEqual({
          currentValue: 100_001,
          maxValue: DOCUMENT_LIMITS.MAX_CHARACTERS,
          metric: 'characters',
        });
      }
    });
  });

  describe('assertValidDigest', () => {
    test('should not throw for valid digest', () => {
      const docs: Document[] = [
        { id: '1', name: 'doc1.md', content: 'Content 1' },
        { id: '2', name: 'doc2.md', content: 'Content 2' },
      ];

      expect(() => assertValidDigest(docs)).not.toThrow();
    });

    test('should throw ValidationError for invalid digest', () => {
      const docs: Document[] = Array.from({ length: 11 }, (_, i) => ({
        id: `${i}`,
        name: `doc${i}.md`,
        content: 'Content',
      }));

      expect(() => assertValidDigest(docs)).toThrow(ValidationError);
      expect(() => assertValidDigest(docs)).toThrow('exceeds maximum 10');
    });
  });

  describe('assertValidCommandInput', () => {
    test('should not throw for valid command', () => {
      const input = '/translate @doc.md for executives';

      expect(() => assertValidCommandInput(input)).not.toThrow();
    });

    test('should throw ValidationError for invalid command', () => {
      const input = 'a'.repeat(501);

      expect(() => assertValidCommandInput(input)).toThrow(ValidationError);
      expect(() => assertValidCommandInput(input)).toThrow('exceeds maximum 500 characters');
    });
  });

  describe('Attack Scenario Prevention', () => {
    test('should prevent HIGH-003 attack: DoS via 1000-page document', () => {
      // Attack Scenario:
      // - Attacker uploads 1000-page PDF to Google Drive
      // - DevRel bot attempts to process document
      // - API calls timeout (Anthropic 100k token limit)
      // - Memory exhaustion (OOM kills container)
      // - Service unavailable for all users

      const attackDoc: Document = {
        id: 'malicious-1',
        name: 'attack-doc.pdf',
        content: 'Page content\n'.repeat(100_000), // Simulates large document
        pageCount: 1000, // 1000 pages
        sizeBytes: 50 * 1024 * 1024, // 50 MB
      };

      // Before fix: Would attempt to process, causing timeout/OOM
      // After fix: Rejected immediately with clear error

      const result = validateDocumentSize(attackDoc);

      expect(result.valid).toBe(false);
      expect(result.error).toContain('exceeds maximum 50 pages');

      // Verify service remains available (no processing attempted)
      expect(result.details?.currentValue).toBe(1000);
      expect(result.details?.maxValue).toBe(50);
    });

    test('should prevent HIGH-003 attack: DoS via 100+ documents in digest', () => {
      // Attack Scenario:
      // - Attacker creates 100+ documents in Google Drive folder
      // - Weekly digest attempts to process all documents
      // - Total content exceeds Anthropic API token limit
      // - Request times out, retry loop begins
      // - Service stuck in retry loop, unavailable

      const attackDocs: Document[] = Array.from({ length: 100 }, (_, i) => ({
        id: `attack-${i}`,
        name: `doc${i}.md`,
        content: 'Content '.repeat(5000), // ~40k characters each
      }));

      // Before fix: Would attempt to process all 100 docs, causing timeout
      // After fix: Rejected immediately

      const result = validateDigest(attackDocs);

      expect(result.valid).toBe(false);
      expect(result.error).toContain('exceeds maximum 10');
      expect(result.details?.currentValue).toBe(100);
    });

    test('should prevent HIGH-003 attack: DoS via unlimited command input', () => {
      // Attack Scenario:
      // - Attacker sends Discord command with 10,000 character input
      // - Command parser processes entire input
      // - Database query with huge WHERE clause
      // - Query timeout, database connection exhausted
      // - All Discord commands fail

      const attackCommand = '/translate ' + 'a'.repeat(10_000);

      // Before fix: Would attempt to parse entire command
      // After fix: Rejected immediately

      const result = validateCommandInput(attackCommand);

      expect(result.valid).toBe(false);
      expect(result.error).toContain('exceeds maximum 500 characters');
      expect(result.details?.currentValue).toBe(10_011); // '/translate ' + 10,000 'a's
    });

    test('should handle legitimate large document gracefully', () => {
      // Legitimate use case: 45-page document (within limits)
      const legitimateDoc: Document = {
        id: 'legit-1',
        name: 'quarterly-report.pdf',
        content: 'x'.repeat(80_000), // Exactly 80k characters
        pageCount: 45,
        sizeBytes: 8 * 1024 * 1024, // 8 MB
      };

      const result = validateDocumentSize(legitimateDoc);

      expect(result.valid).toBe(true);
    });

    test('should prioritize recent documents when digest exceeds limit', () => {
      // Legitimate use case: 15 documents changed this week
      // System should process 10 most recent, skip oldest 5

      const docs: Document[] = Array.from({ length: 15 }, (_, i) => ({
        id: `doc-${i}`,
        name: `doc${i}.md`,
        content: 'Content',
      }));

      // doc14 is most recent (Dec 15), doc0 is oldest (Dec 1)
      const getLastModified = (doc: Document) => {
        const dayOffset = parseInt(doc.id.split('-')[1]!);
        return new Date(2025, 11, dayOffset + 1);
      };

      const prioritized = prioritizeDocumentsByRecency(docs, getLastModified);

      expect(prioritized.length).toBe(10);
      expect(prioritized[0]!.id).toBe('doc-14'); // Most recent
      expect(prioritized[9]!.id).toBe('doc-5'); // 10th most recent

      // Oldest 5 documents (doc-0 through doc-4) are excluded
      const includedIds = prioritized.map(d => d.id);
      expect(includedIds).not.toContain('doc-0');
      expect(includedIds).not.toContain('doc-4');
    });
  });
});
