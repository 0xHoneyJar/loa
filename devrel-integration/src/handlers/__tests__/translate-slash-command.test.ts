/**
 * Translate Slash Command Tests
 *
 * Sprint 3 - Task 3.2 Tests
 *
 * Tests for /translate command handler utilities.
 */

import {
  resolveDocumentReference,
  isValidProject,
  formatProjectName,
  KNOWN_PROJECTS,
  DOCUMENT_SHORTHANDS,
} from '../translate-slash-command';

describe('Translate Slash Command', () => {
  describe('resolveDocumentReference', () => {
    it('should resolve @prd shorthand', () => {
      const result = resolveDocumentReference('@prd');
      expect(result).not.toBeNull();
      expect(result?.path).toBe('prd.md');
      expect(result?.documentType).toBe('prd');
      expect(result?.isShorthand).toBe(true);
    });

    it('should resolve @sdd shorthand', () => {
      const result = resolveDocumentReference('@sdd');
      expect(result).not.toBeNull();
      expect(result?.path).toBe('sdd.md');
      expect(result?.documentType).toBe('sdd');
    });

    it('should resolve @sprint shorthand', () => {
      const result = resolveDocumentReference('@sprint');
      expect(result).not.toBeNull();
      expect(result?.path).toBe('sprint.md');
      expect(result?.documentType).toBe('sprint');
    });

    it('should resolve @reviewer shorthand', () => {
      const result = resolveDocumentReference('@reviewer');
      expect(result).not.toBeNull();
      expect(result?.path).toBe('a2a/reviewer.md');
      expect(result?.documentType).toBe('reviewer');
    });

    it('should resolve @audit shorthand', () => {
      const result = resolveDocumentReference('@audit');
      expect(result).not.toBeNull();
      expect(result?.path).toBe('SECURITY-AUDIT-REPORT.md');
      expect(result?.documentType).toBe('audit');
    });

    it('should handle case-insensitive shorthands', () => {
      const result = resolveDocumentReference('@PRD');
      expect(result).not.toBeNull();
      expect(result?.path).toBe('prd.md');
    });

    it('should resolve full path with @ prefix', () => {
      const result = resolveDocumentReference('@docs/a2a/engineer-feedback.md');
      expect(result).not.toBeNull();
      expect(result?.path).toBe('docs/a2a/engineer-feedback.md');
      expect(result?.isShorthand).toBe(false);
    });

    it('should resolve path without @ prefix', () => {
      const result = resolveDocumentReference('docs/deployment/runbook.md');
      expect(result).not.toBeNull();
      expect(result?.path).toBe('docs/deployment/runbook.md');
      expect(result?.isShorthand).toBe(false);
    });

    it('should return null for unknown @ shorthands without path', () => {
      const result = resolveDocumentReference('@unknown');
      expect(result).toBeNull();
    });

    it('should infer document type from path', () => {
      const prdResult = resolveDocumentReference('docs/my-prd.md');
      expect(prdResult?.documentType).toBe('prd');

      const sddResult = resolveDocumentReference('docs/my-sdd.md');
      expect(sddResult?.documentType).toBe('sdd');

      const auditResult = resolveDocumentReference('docs/audit-report.md');
      expect(auditResult?.documentType).toBe('audit');

      const otherResult = resolveDocumentReference('docs/random-doc.md');
      expect(otherResult?.documentType).toBe('general');
    });
  });

  describe('isValidProject', () => {
    it('should validate known projects', () => {
      expect(isValidProject('mibera')).toBe(true);
      expect(isValidProject('fatbera')).toBe(true);
      expect(isValidProject('interpol')).toBe(true);
      expect(isValidProject('onomancer')).toBe(true);
    });

    it('should be case-insensitive', () => {
      expect(isValidProject('MIBERA')).toBe(true);
      expect(isValidProject('MiBera')).toBe(true);
    });

    it('should reject unknown projects', () => {
      expect(isValidProject('unknown')).toBe(false);
      expect(isValidProject('')).toBe(false);
      expect(isValidProject('random-project')).toBe(false);
    });

    it('should validate set-and-forgetti variations', () => {
      expect(isValidProject('setforgetti')).toBe(true);
      expect(isValidProject('set-and-forgetti')).toBe(true);
    });
  });

  describe('formatProjectName', () => {
    it('should format known project names', () => {
      expect(formatProjectName('mibera')).toBe('MiBera');
      expect(formatProjectName('fatbera')).toBe('FatBera');
      expect(formatProjectName('interpol')).toBe('Interpol');
      expect(formatProjectName('onomancer')).toBe('Onomancer');
    });

    it('should handle Set & Forgetti variations', () => {
      expect(formatProjectName('setforgetti')).toBe('Set & Forgetti');
      expect(formatProjectName('set-and-forgetti')).toBe('Set & Forgetti');
    });

    it('should capitalize unknown projects', () => {
      expect(formatProjectName('newproject')).toBe('Newproject');
    });

    it('should be case-insensitive for input', () => {
      expect(formatProjectName('MIBERA')).toBe('MiBera');
    });
  });

  describe('KNOWN_PROJECTS constant', () => {
    it('should contain expected projects', () => {
      expect(KNOWN_PROJECTS).toContain('mibera');
      expect(KNOWN_PROJECTS).toContain('fatbera');
      expect(KNOWN_PROJECTS).toContain('interpol');
      expect(KNOWN_PROJECTS).toContain('onomancer');
    });

    it('should have unique entries', () => {
      const unique = new Set(KNOWN_PROJECTS);
      expect(unique.size).toBe(KNOWN_PROJECTS.length);
    });
  });

  describe('DOCUMENT_SHORTHANDS constant', () => {
    it('should have expected shorthands', () => {
      // Paths are relative to docs/ directory (DocumentResolver base)
      expect(DOCUMENT_SHORTHANDS['@prd']).toBe('prd.md');
      expect(DOCUMENT_SHORTHANDS['@sdd']).toBe('sdd.md');
      expect(DOCUMENT_SHORTHANDS['@sprint']).toBe('sprint.md');
      expect(DOCUMENT_SHORTHANDS['@reviewer']).toBe('a2a/reviewer.md');
      expect(DOCUMENT_SHORTHANDS['@audit']).toBe('SECURITY-AUDIT-REPORT.md');
    });
  });
});
