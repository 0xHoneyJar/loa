/**
 * Input Validator Tests
 *
 * Validates that input validator blocks 50+ command and path injection attempts.
 * Tests for CRITICAL-002 remediation.
 */

import { InputValidator } from '../../src/validators/input-validator';

describe('InputValidator', () => {
  let validator: InputValidator;

  beforeEach(() => {
    validator = new InputValidator();
  });

  describe('Path Traversal Attacks', () => {
    test('should block ../ path traversal', () => {
      const result = validator.validateDocumentPath('../../../etc/passwd');
      expect(result.valid).toBe(false);
      expect(result.errors[0]).toContain('Path traversal');
    });

    test('should block ..\\ Windows path traversal', () => {
      const result = validator.validateDocumentPath('..\\..\\Windows\\System32\\config\\sam');
      expect(result.valid).toBe(false);
      expect(result.errors[0]).toContain('Path traversal');
    });

    test('should block URL-encoded path traversal (%2e%2e)', () => {
      const result = validator.validateDocumentPath('%2e%2e/%2e%2e/etc/passwd');
      expect(result.valid).toBe(false);
      expect(result.errors[0]).toContain('Path traversal');
    });

    test('should block double URL-encoded path traversal', () => {
      const result = validator.validateDocumentPath('%252e%252e/%252e%252e/etc/passwd');
      expect(result.valid).toBe(false);
      expect(result.errors[0]).toContain('Path traversal');
    });

    test('should block null byte injection', () => {
      const result = validator.validateDocumentPath('docs/safe.md\0../../etc/passwd');
      expect(result.valid).toBe(false);
      expect(result.errors[0]).toContain('Path traversal');
    });

    test('should block home directory reference (~)', () => {
      const result = validator.validateDocumentPath('~/../../etc/passwd');
      expect(result.valid).toBe(false);
      expect(result.errors[0]).toContain('Path traversal');
    });

    test('should block mixed encoding path traversal', () => {
      const result = validator.validateDocumentPath('.%2e/.%2e/etc/passwd');
      expect(result.valid).toBe(false);
    });
  });

  describe('Absolute Path Attacks', () => {
    test('should block Unix absolute paths (/etc/passwd)', () => {
      const result = validator.validateDocumentPath('/etc/passwd');
      expect(result.valid).toBe(false);
      expect(result.errors[0]).toContain('Absolute paths are not allowed');
    });

    test('should block Windows absolute paths (C:\\)', () => {
      const result = validator.validateDocumentPath('C:\\Windows\\System32\\config\\sam');
      expect(result.valid).toBe(false);
      expect(result.errors[0]).toContain('Absolute paths are not allowed');
    });

    test('should block UNC paths (\\\\server\\share)', () => {
      const result = validator.validateDocumentPath('\\\\server\\share\\file.txt');
      expect(result.valid).toBe(false);
      expect(result.errors[0]).toContain('Absolute paths are not allowed');
    });

    test('should block drive letter paths (D:\\)', () => {
      const result = validator.validateDocumentPath('D:\\sensitive\\data.txt');
      expect(result.valid).toBe(false);
      expect(result.errors[0]).toContain('Absolute paths are not allowed');
    });
  });

  describe('System Directory Access Attempts', () => {
    test('should block /etc/ access', () => {
      const result = validator.validateDocumentPath('/etc/shadow.md');
      expect(result.valid).toBe(false);
      expect(result.errors.some(e => e.includes('Absolute paths') || e.includes('system directories'))).toBe(true);
    });

    test('should block /var/ access', () => {
      const result = validator.validateDocumentPath('/var/log/auth.log.md');
      expect(result.valid).toBe(false);
    });

    test('should block /usr/ access', () => {
      const result = validator.validateDocumentPath('/usr/bin/sudo.md');
      expect(result.valid).toBe(false);
    });

    test('should block /proc/ access', () => {
      const result = validator.validateDocumentPath('/proc/self/environ.md');
      expect(result.valid).toBe(false);
    });

    test('should block Windows system directories', () => {
      const result = validator.validateDocumentPath('C:\\Windows\\System32\\cmd.exe.md');
      expect(result.valid).toBe(false);
    });
  });

  describe('Command Injection Attacks', () => {
    test('should block semicolon command chaining', () => {
      const result = validator.validateDocumentPath('file.md; rm -rf /');
      expect(result.valid).toBe(false);
      expect(result.errors[0]).toContain('Special characters');
    });

    test('should block pipe operators', () => {
      const result = validator.validateDocumentPath('file.md | cat /etc/passwd');
      expect(result.valid).toBe(false);
      expect(result.errors[0]).toContain('Special characters');
    });

    test('should block ampersand background execution', () => {
      const result = validator.validateDocumentPath('file.md & malicious_script');
      expect(result.valid).toBe(false);
      expect(result.errors[0]).toContain('Special characters');
    });

    test('should block command substitution with backticks', () => {
      const result = validator.validateDocumentPath('file`whoami`.md');
      expect(result.valid).toBe(false);
      expect(result.errors[0]).toContain('Special characters');
    });

    test('should block command substitution with $()', () => {
      const result = validator.validateDocumentPath('file$(whoami).md');
      expect(result.valid).toBe(false);
      expect(result.errors[0]).toContain('Special characters');
    });

    test('should block redirection operators', () => {
      const result = validator.validateDocumentPath('file.md > /tmp/output');
      expect(result.valid).toBe(false);
      expect(result.errors[0]).toContain('Special characters');
    });

    test('should block input redirection', () => {
      const result = validator.validateDocumentPath('file.md < /etc/passwd');
      expect(result.valid).toBe(false);
      expect(result.errors[0]).toContain('Special characters');
    });

    test('should block curly brace expansion', () => {
      const result = validator.validateDocumentPath('file{1,2,3}.md');
      expect(result.valid).toBe(false);
      expect(result.errors[0]).toContain('Special characters');
    });

    test('should block square bracket globbing', () => {
      const result = validator.validateDocumentPath('file[abc].md');
      expect(result.valid).toBe(false);
      expect(result.errors[0]).toContain('Special characters');
    });
  });

  describe('Extension Validation', () => {
    test('should allow .md files', () => {
      const result = validator.validateDocumentPath('docs/valid-file.md');
      expect(result.valid).toBe(true);
    });

    test('should allow .gdoc files', () => {
      const result = validator.validateDocumentPath('docs/valid-file.gdoc');
      expect(result.valid).toBe(true);
    });

    test('should block .txt files', () => {
      const result = validator.validateDocumentPath('docs/file.txt');
      expect(result.valid).toBe(false);
      expect(result.errors[0]).toContain('Only .md, .gdoc files are allowed');
    });

    test('should block .sh scripts', () => {
      const result = validator.validateDocumentPath('scripts/malicious.sh');
      expect(result.valid).toBe(false);
    });

    test('should block .exe executables', () => {
      const result = validator.validateDocumentPath('malware.exe');
      expect(result.valid).toBe(false);
    });

    test('should block files with no extension', () => {
      const result = validator.validateDocumentPath('docs/noextension');
      expect(result.valid).toBe(false);
    });

    test('should block double extensions', () => {
      const result = validator.validateDocumentPath('file.md.exe');
      expect(result.valid).toBe(false);
    });
  });

  describe('Multiple Document Validation', () => {
    test('should validate multiple valid paths', () => {
      const result = validator.validateDocumentPaths([
        'docs/file1.md',
        'docs/file2.md',
        'docs/file3.gdoc'
      ]);

      expect(result.valid).toBe(true);
      expect(result.resolvedPaths).toHaveLength(3);
    });

    test('should reject if any path is invalid', () => {
      const result = validator.validateDocumentPaths([
        'docs/valid.md',
        '../../../etc/passwd.md',
        'docs/also-valid.md'
      ]);

      expect(result.valid).toBe(false);
      expect(result.errors.length).toBeGreaterThan(0);
    });

    test('should enforce document limit (max 10)', () => {
      const paths = Array(15).fill('docs/file.md');
      const result = validator.validateDocumentPaths(paths);

      expect(result.valid).toBe(false);
      expect(result.errors[0]).toContain('Too many documents');
    });

    test('should reject empty array', () => {
      const result = validator.validateDocumentPaths([]);
      expect(result.valid).toBe(false);
      expect(result.errors[0]).toContain('At least one document');
    });

    test('should deduplicate paths', () => {
      const result = validator.validateDocumentPaths([
        'docs/file.md',
        'docs/file.md',
        'docs/other.md'
      ]);

      expect(result.valid).toBe(true);
      expect(result.resolvedPaths).toHaveLength(2);
      expect(result.warnings[0]).toContain('Duplicate');
    });

    test('should reject non-array input', () => {
      const result = validator.validateDocumentPaths('not-an-array' as any);
      expect(result.valid).toBe(false);
      expect(result.errors[0]).toContain('must be provided as an array');
    });
  });

  describe('Command Arguments Validation', () => {
    test('should allow valid command names', () => {
      const result = validator.validateCommandArgs('translate-doc', ['arg1', 'arg2']);
      expect(result.valid).toBe(true);
    });

    test('should block special characters in command names', () => {
      const result = validator.validateCommandArgs('translate; rm -rf /', []);
      expect(result.valid).toBe(false);
      expect(result.errors[0]).toContain('Invalid command name');
    });

    test('should block uppercase in command names', () => {
      const result = validator.validateCommandArgs('TRANSLATE', []);
      expect(result.valid).toBe(false);
    });

    test('should block command injection in arguments', () => {
      const result = validator.validateCommandArgs('translate', ['arg1; rm -rf /']);
      expect(result.valid).toBe(false);
      expect(result.errors[0]).toContain('special characters');
    });

    test('should block pipe operators in arguments', () => {
      const result = validator.validateCommandArgs('translate', ['arg1 | cat /etc/passwd']);
      expect(result.valid).toBe(false);
    });

    test('should block redirection in arguments', () => {
      const result = validator.validateCommandArgs('translate', ['arg1 > /tmp/output']);
      expect(result.valid).toBe(false);
    });

    test('should reject non-array arguments', () => {
      const result = validator.validateCommandArgs('translate', 'not-array' as any);
      expect(result.valid).toBe(false);
      expect(result.errors[0]).toContain('must be an array');
    });
  });

  describe('Audience Validation', () => {
    test('should allow valid audience descriptions', () => {
      const result = validator.validateAudience('COO, Head of BD, executives');
      expect(result.valid).toBe(true);
    });

    test('should trim whitespace', () => {
      const result = validator.validateAudience('  executives  ');
      expect(result.valid).toBe(true);
      expect(result.sanitized).toBe('executives');
    });

    test('should reject empty audience', () => {
      const result = validator.validateAudience('');
      expect(result.valid).toBe(false);
      expect(result.errors[0]).toContain('cannot be empty');
    });

    test('should reject audience with special characters', () => {
      const result = validator.validateAudience('executives; DROP TABLE users;');
      expect(result.valid).toBe(false);
      expect(result.errors[0]).toContain('invalid characters');
    });

    test('should reject audience over 200 characters', () => {
      const longAudience = 'a'.repeat(201);
      const result = validator.validateAudience(longAudience);
      expect(result.valid).toBe(false);
      expect(result.errors[0]).toContain('too long');
    });

    test('should allow parentheses in audience', () => {
      const result = validator.validateAudience('Marketing team (social media focus)');
      expect(result.valid).toBe(true);
    });

    test('should reject HTML/script tags', () => {
      const result = validator.validateAudience('executives<script>alert(1)</script>');
      expect(result.valid).toBe(false);
    });
  });

  describe('Format Validation', () => {
    test('should allow valid format: executive', () => {
      const result = validator.validateFormat('executive');
      expect(result.valid).toBe(true);
    });

    test('should allow valid format: marketing', () => {
      const result = validator.validateFormat('marketing');
      expect(result.valid).toBe(true);
    });

    test('should allow valid format: product', () => {
      const result = validator.validateFormat('product');
      expect(result.valid).toBe(true);
    });

    test('should allow valid format: engineering', () => {
      const result = validator.validateFormat('engineering');
      expect(result.valid).toBe(true);
    });

    test('should allow valid format: unified', () => {
      const result = validator.validateFormat('unified');
      expect(result.valid).toBe(true);
    });

    test('should normalize format to lowercase', () => {
      const result = validator.validateFormat('EXECUTIVE');
      expect(result.valid).toBe(true);
      expect(result.sanitized).toBe('executive');
    });

    test('should reject invalid format', () => {
      const result = validator.validateFormat('invalid-format');
      expect(result.valid).toBe(false);
      expect(result.errors[0]).toContain('Invalid format');
    });

    test('should reject empty format', () => {
      const result = validator.validateFormat('');
      expect(result.valid).toBe(false);
    });
  });

  describe('Edge Cases and Complex Attacks', () => {
    test('should handle very long paths', () => {
      const longPath = 'a/'.repeat(300) + 'file.md';
      const result = validator.validateDocumentPath(longPath);
      expect(result.valid).toBe(false);
      expect(result.errors[0]).toContain('too long');
    });

    test('should reject paths with newlines', () => {
      const result = validator.validateDocumentPath('file.md\nmalicious');
      expect(result.valid).toBe(false);
    });

    test('should reject paths with carriage returns', () => {
      const result = validator.validateDocumentPath('file.md\rmalicious');
      expect(result.valid).toBe(false);
    });

    test('should reject null input', () => {
      const result = validator.validateDocumentPath(null as any);
      expect(result.valid).toBe(false);
      expect(result.errors[0]).toContain('required');
    });

    test('should reject undefined input', () => {
      const result = validator.validateDocumentPath(undefined as any);
      expect(result.valid).toBe(false);
    });

    test('should reject numeric input', () => {
      const result = validator.validateDocumentPath(12345 as any);
      expect(result.valid).toBe(false);
    });

    test('should reject object input', () => {
      const result = validator.validateDocumentPath({ path: 'file.md' } as any);
      expect(result.valid).toBe(false);
    });

    test('should warn about hidden files', () => {
      const result = validator.validateDocumentPath('.hidden-file.md');
      expect(result.valid).toBe(true); // Valid, but warning
      expect(result.warnings[0]).toContain('Hidden files');
    });
  });

  describe('Sanitization for Display', () => {
    test('should remove HTML tags', () => {
      const sanitized = validator.sanitizeForDisplay('<script>alert(1)</script>Hello');
      expect(sanitized).not.toContain('<script>');
      expect(sanitized).not.toContain('</script>');
    });

    test('should escape ampersands', () => {
      const sanitized = validator.sanitizeForDisplay('Fish & Chips');
      expect(sanitized).toContain('&amp;');
    });

    test('should limit length to 1000 chars', () => {
      const longInput = 'a'.repeat(2000);
      const sanitized = validator.sanitizeForDisplay(longInput);
      expect(sanitized.length).toBe(1000);
    });

    test('should handle null input', () => {
      const sanitized = validator.sanitizeForDisplay(null as any);
      expect(sanitized).toBe('');
    });

    test('should handle undefined input', () => {
      const sanitized = validator.sanitizeForDisplay(undefined as any);
      expect(sanitized).toBe('');
    });
  });
});
