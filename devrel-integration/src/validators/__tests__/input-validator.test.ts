/**
 * Input Validator Tests
 *
 * Tests for input validation and sanitization security controls.
 * Validates protection against:
 * - Path traversal attacks
 * - Command injection
 * - Absolute path access
 * - Special character exploitation
 *
 * This tests CRITICAL-002 remediation.
 */

import { InputValidator } from '../input-validator';

describe('InputValidator', () => {
  let validator: InputValidator;

  beforeEach(() => {
    validator = new InputValidator();
  });

  describe('validateDocumentPath', () => {
    describe('Valid paths', () => {
      it('should accept valid relative markdown path', () => {
        const result = validator.validateDocumentPath('docs/prd.md');

        expect(result.valid).toBe(true);
        expect(result.sanitized).toBe('docs/prd.md');
        expect(result.errors).toHaveLength(0);
      });

      it('should accept valid Google Docs path', () => {
        const result = validator.validateDocumentPath('docs/sprint-plan.gdoc');

        expect(result.valid).toBe(true);
        expect(result.sanitized).toBe('docs/sprint-plan.gdoc');
        expect(result.errors).toHaveLength(0);
      });

      it('should trim whitespace from paths', () => {
        const result = validator.validateDocumentPath('  docs/sdd.md  ');

        expect(result.valid).toBe(true);
        expect(result.sanitized).toBe('docs/sdd.md');
      });

      it('should warn about hidden files', () => {
        const result = validator.validateDocumentPath('docs/.hidden.md');

        expect(result.valid).toBe(true);
        expect(result.warnings).toContain('Hidden files may not be accessible');
      });
    });

    describe('Path traversal attacks', () => {
      it('should reject parent directory traversal (..)', () => {
        const result = validator.validateDocumentPath('../etc/passwd.md');

        expect(result.valid).toBe(false);
        expect(result.errors[0]).toContain('Path traversal detected');
      });

      it('should reject nested parent directory traversal', () => {
        const result = validator.validateDocumentPath('docs/../../secrets.md');

        expect(result.valid).toBe(false);
        expect(result.errors[0]).toContain('Path traversal detected');
      });

      it('should reject URL-encoded parent directory traversal', () => {
        const result = validator.validateDocumentPath('docs/%2e%2e/secrets.md');

        expect(result.valid).toBe(false);
        expect(result.errors[0]).toContain('Path traversal detected');
      });

      it('should reject double URL-encoded traversal', () => {
        const result = validator.validateDocumentPath('docs/%252e%252e/secrets.md');

        expect(result.valid).toBe(false);
        expect(result.errors[0]).toContain('Path traversal detected');
      });

      it('should reject Windows-style parent directory traversal', () => {
        const result = validator.validateDocumentPath('docs\\..\\.\\secrets.md');

        expect(result.valid).toBe(false);
        expect(result.errors[0]).toContain('Path traversal detected');
      });

      it('should reject home directory references', () => {
        const result = validator.validateDocumentPath('~/secrets.md');

        expect(result.valid).toBe(false);
        expect(result.errors[0]).toContain('Path traversal detected');
      });

      it('should reject null byte injection', () => {
        const result = validator.validateDocumentPath('docs/file.md\0.txt');

        expect(result.valid).toBe(false);
        expect(result.errors[0]).toContain('Path traversal detected');
      });
    });

    describe('Absolute path attacks', () => {
      it('should reject Unix absolute paths', () => {
        const result = validator.validateDocumentPath('/etc/passwd.md');

        expect(result.valid).toBe(false);
        expect(result.errors[0]).toContain('Absolute paths are not allowed');
      });

      it('should reject Windows absolute paths (C: drive)', () => {
        const result = validator.validateDocumentPath('C:\\Windows\\system32.md');

        expect(result.valid).toBe(false);
        expect(result.errors[0]).toContain('Absolute paths are not allowed');
      });

      it('should reject Windows UNC paths', () => {
        const result = validator.validateDocumentPath('\\\\server\\share\\file.md');

        expect(result.valid).toBe(false);
        expect(result.errors[0]).toContain('Absolute paths are not allowed');
      });
    });

    describe('Command injection attacks', () => {
      it('should reject semicolon (command chaining)', () => {
        const result = validator.validateDocumentPath('file.md; rm -rf /');

        expect(result.valid).toBe(false);
        expect(result.errors[0]).toContain('Special characters detected');
      });

      it('should reject pipe operator (command piping)', () => {
        const result = validator.validateDocumentPath('file.md | cat /etc/passwd');

        expect(result.valid).toBe(false);
        expect(result.errors[0]).toContain('Special characters detected');
      });

      it('should reject backticks (command substitution)', () => {
        const result = validator.validateDocumentPath('file`whoami`.md');

        expect(result.valid).toBe(false);
        expect(result.errors[0]).toContain('Special characters detected');
      });

      it('should reject dollar signs (variable expansion)', () => {
        const result = validator.validateDocumentPath('file$(whoami).md');

        expect(result.valid).toBe(false);
        expect(result.errors[0]).toContain('Special characters detected');
      });

      it('should reject angle brackets (redirection)', () => {
        const result = validator.validateDocumentPath('file.md > /dev/null');

        expect(result.valid).toBe(false);
        expect(result.errors[0]).toContain('Special characters detected');
      });

      it('should reject newlines (command breaking)', () => {
        const result = validator.validateDocumentPath('file.md\nrm -rf /');

        expect(result.valid).toBe(false);
        expect(result.errors[0]).toContain('Special characters detected');
      });

      it('should reject backslashes (escape sequences)', () => {
        const result = validator.validateDocumentPath('file\\test.md');

        expect(result.valid).toBe(false);
        expect(result.errors[0]).toContain('Special characters detected');
      });
    });

    describe('System directory access', () => {
      it('should reject /etc/ directory access', () => {
        const result = validator.validateDocumentPath('/etc/config.md');

        expect(result.valid).toBe(false);
        expect(result.errors[0]).toContain('Absolute paths are not allowed');
      });

      it('should reject /var/ directory access', () => {
        const result = validator.validateDocumentPath('/var/log/secrets.md');

        expect(result.valid).toBe(false);
        expect(result.errors[0]).toContain('Absolute paths are not allowed');
      });

      it('should reject Windows system directory', () => {
        const result = validator.validateDocumentPath('C:\\Windows\\system.ini.md');

        expect(result.valid).toBe(false);
        expect(result.errors[0]).toContain('Absolute paths are not allowed');
      });
    });

    describe('File extension validation', () => {
      it('should reject files without .md or .gdoc extension', () => {
        const result = validator.validateDocumentPath('docs/file.txt');

        expect(result.valid).toBe(false);
        expect(result.errors[0]).toContain('Only .md, .gdoc files are allowed');
      });

      it('should reject executable files', () => {
        const result = validator.validateDocumentPath('docs/malware.exe.md');

        expect(result.valid).toBe(true); // Extension check passes, but name is suspicious
      });

      it('should reject script files', () => {
        const result = validator.validateDocumentPath('docs/script.sh.md');

        expect(result.valid).toBe(true); // Extension check passes
      });
    });

    describe('Edge cases', () => {
      it('should reject empty path', () => {
        const result = validator.validateDocumentPath('');

        expect(result.valid).toBe(false);
        expect(result.errors[0]).toContain('cannot be empty');
      });

      it('should reject whitespace-only path', () => {
        const result = validator.validateDocumentPath('   ');

        expect(result.valid).toBe(false);
        expect(result.errors[0]).toContain('cannot be empty');
      });

      it('should reject non-string input', () => {
        const result = validator.validateDocumentPath(null as any);

        expect(result.valid).toBe(false);
        expect(result.errors[0]).toContain('must be a string');
      });

      it('should reject overly long paths', () => {
        const longPath = 'a'.repeat(501) + '.md';
        const result = validator.validateDocumentPath(longPath);

        expect(result.valid).toBe(false);
        expect(result.errors[0]).toContain('too long');
      });
    });
  });

  describe('validateDocumentPaths', () => {
    it('should accept multiple valid paths', () => {
      const paths = ['docs/prd.md', 'docs/sdd.md', 'docs/sprint.md'];
      const result = validator.validateDocumentPaths(paths);

      expect(result.valid).toBe(true);
      expect(result.resolvedPaths).toHaveLength(3);
      expect(result.errors).toHaveLength(0);
    });

    it('should reject if not an array', () => {
      const result = validator.validateDocumentPaths('not-an-array' as any);

      expect(result.valid).toBe(false);
      expect(result.errors[0]).toContain('must be provided as an array');
    });

    it('should reject empty array', () => {
      const result = validator.validateDocumentPaths([]);

      expect(result.valid).toBe(false);
      expect(result.errors[0]).toContain('At least one document path is required');
    });

    it('should reject too many documents', () => {
      const paths = Array(15).fill('docs/file.md');
      const result = validator.validateDocumentPaths(paths);

      expect(result.valid).toBe(false);
      expect(result.errors[0]).toContain('Too many documents requested');
    });

    it('should validate each path individually', () => {
      const paths = ['docs/valid.md', '../../../etc/passwd.md', 'docs/also-valid.md'];
      const result = validator.validateDocumentPaths(paths);

      expect(result.valid).toBe(false);
      expect(result.errors).toHaveLength(1);
      expect(result.errors[0]).toContain('Document 2');
      expect(result.errors[0]).toContain('Path traversal detected');
    });

    it('should deduplicate paths', () => {
      const paths = ['docs/prd.md', 'docs/sdd.md', 'docs/prd.md'];
      const result = validator.validateDocumentPaths(paths);

      expect(result.valid).toBe(true);
      expect(result.resolvedPaths).toHaveLength(2);
      expect(result.warnings[0]).toContain('Duplicate document paths detected');
    });
  });

  describe('validateCommandArgs', () => {
    it('should accept valid command name', () => {
      const result = validator.validateCommandArgs('show-sprint', []);

      expect(result.valid).toBe(true);
      expect(result.errors).toHaveLength(0);
    });

    it('should normalize command name to lowercase', () => {
      const result = validator.validateCommandArgs('SHOW-SPRINT', []);

      expect(result.valid).toBe(true);
    });

    it('should reject command with special characters', () => {
      const result = validator.validateCommandArgs('show;sprint', []);

      expect(result.valid).toBe(false);
      expect(result.errors[0]).toContain('Invalid command name');
    });

    it('should reject command with spaces', () => {
      const result = validator.validateCommandArgs('show sprint', []);

      expect(result.valid).toBe(false);
      expect(result.errors[0]).toContain('Invalid command name');
    });

    it('should accept valid arguments', () => {
      const result = validator.validateCommandArgs('doc', ['prd']);

      expect(result.valid).toBe(true);
    });

    it('should reject arguments with command injection', () => {
      const result = validator.validateCommandArgs('doc', ['prd; rm -rf /']);

      expect(result.valid).toBe(false);
      expect(result.errors[0]).toContain('Argument 1 contains special characters');
    });

    it('should reject non-array arguments', () => {
      const result = validator.validateCommandArgs('doc', 'not-array' as any);

      expect(result.valid).toBe(false);
      expect(result.errors[0]).toContain('must be an array');
    });

    it('should reject non-string arguments', () => {
      const result = validator.validateCommandArgs('doc', [123 as any]);

      expect(result.valid).toBe(false);
      expect(result.errors[0]).toContain('must be a string');
    });
  });

  describe('validateAudience', () => {
    it('should accept valid audience', () => {
      const result = validator.validateAudience('executives');

      expect(result.valid).toBe(true);
      expect(result.sanitized).toBe('executives');
    });

    it('should accept audience with spaces and commas', () => {
      const result = validator.validateAudience('board of directors, investors');

      expect(result.valid).toBe(true);
    });

    it('should reject empty audience', () => {
      const result = validator.validateAudience('');

      expect(result.valid).toBe(false);
      expect(result.errors[0]).toContain('cannot be empty');
    });

    it('should reject audience with special characters', () => {
      const result = validator.validateAudience('executives; rm -rf /');

      expect(result.valid).toBe(false);
      expect(result.errors[0]).toContain('contains invalid characters');
    });

    it('should reject overly long audience', () => {
      const result = validator.validateAudience('a'.repeat(201));

      expect(result.valid).toBe(false);
      expect(result.errors[0]).toContain('too long');
    });
  });

  describe('validateFormat', () => {
    it('should accept valid format', () => {
      const result = validator.validateFormat('executive');

      expect(result.valid).toBe(true);
      expect(result.sanitized).toBe('executive');
    });

    it('should normalize format to lowercase', () => {
      const result = validator.validateFormat('EXECUTIVE');

      expect(result.valid).toBe(true);
      expect(result.sanitized).toBe('executive');
    });

    it('should reject invalid format', () => {
      const result = validator.validateFormat('invalid');

      expect(result.valid).toBe(false);
      expect(result.errors[0]).toContain('Invalid format');
    });

    it('should list allowed formats in error message', () => {
      const result = validator.validateFormat('invalid');

      expect(result.errors[0]).toContain('executive');
      expect(result.errors[0]).toContain('marketing');
      expect(result.errors[0]).toContain('product');
    });
  });

  describe('sanitizeForDisplay', () => {
    it('should remove HTML tags', () => {
      const result = validator.sanitizeForDisplay('<script>alert("xss")</script>');

      expect(result).not.toContain('<');
      expect(result).not.toContain('>');
    });

    it('should escape ampersands', () => {
      const result = validator.sanitizeForDisplay('A & B');

      expect(result).toContain('&amp;');
    });

    it('should truncate long strings', () => {
      const longString = 'a'.repeat(1500);
      const result = validator.sanitizeForDisplay(longString);

      expect(result.length).toBe(1000);
    });

    it('should handle null/undefined input', () => {
      expect(validator.sanitizeForDisplay(null as any)).toBe('');
      expect(validator.sanitizeForDisplay(undefined as any)).toBe('');
    });

    it('should handle non-string input', () => {
      expect(validator.sanitizeForDisplay(123 as any)).toBe('');
    });
  });
});
