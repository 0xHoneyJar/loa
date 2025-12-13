/**
 * Summary Commands Tests
 *
 * Sprint 3 - Tasks 3.3 & 3.4 Tests
 *
 * Tests for /exec-summary and /audit-summary command handlers.
 */

import {
  parseSprintId,
  parseSeverityBreakdown,
  formatSeverityBreakdown,
} from '../summary-commands';

describe('Summary Commands', () => {
  describe('parseSprintId', () => {
    it('should parse simple sprint-N format', () => {
      const result = parseSprintId('sprint-1');
      expect(result).not.toBeNull();
      expect(result?.sprintNumber).toBe(1);
      expect(result?.project).toBeUndefined();
      expect(result?.isRemediation).toBe(false);
    });

    it('should parse sprintN format (no hyphen)', () => {
      const result = parseSprintId('sprint1');
      expect(result).not.toBeNull();
      expect(result?.sprintNumber).toBe(1);
    });

    it('should parse project-sprint-N format', () => {
      const result = parseSprintId('mibera-sprint-1');
      expect(result).not.toBeNull();
      expect(result?.sprintNumber).toBe(1);
      expect(result?.project).toBe('mibera');
    });

    it('should parse case-insensitive input', () => {
      const result = parseSprintId('SPRINT-2');
      expect(result).not.toBeNull();
      expect(result?.sprintNumber).toBe(2);
    });

    it('should detect remediation suffix', () => {
      const result = parseSprintId('sprint-1-remediation');
      expect(result).not.toBeNull();
      expect(result?.sprintNumber).toBe(1);
      expect(result?.isRemediation).toBe(true);
    });

    it('should handle multi-digit sprint numbers', () => {
      const result = parseSprintId('sprint-12');
      expect(result).not.toBeNull();
      expect(result?.sprintNumber).toBe(12);
    });

    it('should return null for invalid formats', () => {
      expect(parseSprintId('invalid')).toBeNull();
      expect(parseSprintId('')).toBeNull();
      expect(parseSprintId('sprint-abc')).toBeNull();
      expect(parseSprintId('sprint--1')).toBeNull();
    });

    it('should parse just a number', () => {
      const result = parseSprintId('3');
      expect(result).not.toBeNull();
      expect(result?.sprintNumber).toBe(3);
    });

    it('should preserve original input', () => {
      const result = parseSprintId('MIBERA-Sprint-1-Remediation');
      expect(result).not.toBeNull();
      expect(result?.originalInput).toBe('MIBERA-Sprint-1-Remediation');
    });
  });

  describe('parseSeverityBreakdown', () => {
    it('should count severity mentions in content', () => {
      const content = `
        ## Security Audit Report

        CRITICAL: SQL injection vulnerability
        HIGH: Missing input validation
        HIGH: Weak password policy
        MEDIUM: Missing rate limiting
        MEDIUM: Verbose error messages
        MEDIUM: No CSRF protection
        LOW: Missing security headers
        LOW: Debug mode enabled
      `;

      const breakdown = parseSeverityBreakdown(content);
      expect(breakdown.critical).toBe(1);
      expect(breakdown.high).toBe(2);
      expect(breakdown.medium).toBe(3);
      expect(breakdown.low).toBe(2);
      expect(breakdown.total).toBe(8);
    });

    it('should handle content with no severity mentions', () => {
      const content = 'This is a clean report with no issues found.';
      const breakdown = parseSeverityBreakdown(content);
      expect(breakdown.total).toBe(0);
    });

    it('should handle mixed case severity labels', () => {
      const content = `
        Critical: Issue 1
        CRITICAL: Issue 2
        critical: Issue 3
      `;
      const breakdown = parseSeverityBreakdown(content);
      // Only Critical and CRITICAL should match (regex pattern)
      expect(breakdown.critical).toBeGreaterThanOrEqual(2);
    });

    it('should not count severity words in normal text', () => {
      // The regex requires a colon or whitespace after the severity word
      const content = 'This is critical for our business. The high priority task.';
      const breakdown = parseSeverityBreakdown(content);
      expect(breakdown.total).toBe(0);
    });
  });

  describe('formatSeverityBreakdown', () => {
    it('should format breakdown with correct emoji indicators', () => {
      const breakdown = {
        critical: 1,
        high: 2,
        medium: 3,
        low: 5,
        total: 11,
      };

      const formatted = formatSeverityBreakdown(breakdown);

      expect(formatted).toContain('CRITICAL: 1 issues');
      expect(formatted).toContain('HIGH: 2 issues');
      expect(formatted).toContain('MEDIUM: 3 issues');
      expect(formatted).toContain('LOW: 5 issues');
      expect(formatted).toContain('\u2022'); // bullet point
    });

    it('should handle zero counts', () => {
      const breakdown = {
        critical: 0,
        high: 0,
        medium: 0,
        low: 0,
        total: 0,
      };

      const formatted = formatSeverityBreakdown(breakdown);
      expect(formatted).toContain('CRITICAL: 0 issues');
    });
  });
});
