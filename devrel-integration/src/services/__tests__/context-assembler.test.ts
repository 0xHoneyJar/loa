/**
 * Context Assembler Test Suite
 *
 * Tests for HIGH-011: Context Assembly Access Control
 */

// Mock logger to avoid ES module issues with validation dependencies
jest.mock('../../utils/logger', () => ({
  logger: {
    info: jest.fn(),
    warn: jest.fn(),
    error: jest.fn(),
    debug: jest.fn(),
  },
  auditLog: {
    contextAssembly: jest.fn(),
    permissionDenied: jest.fn(),
  },
}));

import {
  ContextAssembler,
  SensitivityLevel,
} from '../context-assembler';
import { DocumentResolver } from '../document-resolver';

describe('ContextAssembler', () => {
  let assembler: ContextAssembler;
  let mockResolver: jest.Mocked<DocumentResolver>;

  beforeEach(() => {
    // Create mock resolver
    mockResolver = {
      resolveDocument: jest.fn(),
      resolveDocuments: jest.fn(),
      readDocument: jest.fn(),
      readDocuments: jest.fn(),
      getAllowedDirectories: jest.fn(),
      isPathAllowed: jest.fn(),
    } as any;

    assembler = new ContextAssembler(mockResolver);
  });

  describe('Sensitivity Hierarchy', () => {
    test('should allow same sensitivity level access', () => {
      expect(assembler.canAccessContext(SensitivityLevel.INTERNAL, SensitivityLevel.INTERNAL)).toBe(true);
      expect(assembler.canAccessContext(SensitivityLevel.CONFIDENTIAL, SensitivityLevel.CONFIDENTIAL)).toBe(true);
    });

    test('should allow higher sensitivity to access lower sensitivity', () => {
      expect(assembler.canAccessContext(SensitivityLevel.RESTRICTED, SensitivityLevel.CONFIDENTIAL)).toBe(true);
      expect(assembler.canAccessContext(SensitivityLevel.RESTRICTED, SensitivityLevel.INTERNAL)).toBe(true);
      expect(assembler.canAccessContext(SensitivityLevel.RESTRICTED, SensitivityLevel.PUBLIC)).toBe(true);

      expect(assembler.canAccessContext(SensitivityLevel.CONFIDENTIAL, SensitivityLevel.INTERNAL)).toBe(true);
      expect(assembler.canAccessContext(SensitivityLevel.CONFIDENTIAL, SensitivityLevel.PUBLIC)).toBe(true);

      expect(assembler.canAccessContext(SensitivityLevel.INTERNAL, SensitivityLevel.PUBLIC)).toBe(true);
    });

    test('should deny lower sensitivity to access higher sensitivity', () => {
      expect(assembler.canAccessContext(SensitivityLevel.PUBLIC, SensitivityLevel.INTERNAL)).toBe(false);
      expect(assembler.canAccessContext(SensitivityLevel.PUBLIC, SensitivityLevel.CONFIDENTIAL)).toBe(false);
      expect(assembler.canAccessContext(SensitivityLevel.PUBLIC, SensitivityLevel.RESTRICTED)).toBe(false);

      expect(assembler.canAccessContext(SensitivityLevel.INTERNAL, SensitivityLevel.CONFIDENTIAL)).toBe(false);
      expect(assembler.canAccessContext(SensitivityLevel.INTERNAL, SensitivityLevel.RESTRICTED)).toBe(false);

      expect(assembler.canAccessContext(SensitivityLevel.CONFIDENTIAL, SensitivityLevel.RESTRICTED)).toBe(false);
    });

    test('should correctly compare sensitivity levels', () => {
      expect(assembler.getSensitivityLevel(SensitivityLevel.PUBLIC)).toBe(0);
      expect(assembler.getSensitivityLevel(SensitivityLevel.INTERNAL)).toBe(1);
      expect(assembler.getSensitivityLevel(SensitivityLevel.CONFIDENTIAL)).toBe(2);
      expect(assembler.getSensitivityLevel(SensitivityLevel.RESTRICTED)).toBe(3);
    });

    test('should correctly determine if one sensitivity is higher than another', () => {
      expect(assembler.isHigherSensitivity(SensitivityLevel.RESTRICTED, SensitivityLevel.CONFIDENTIAL)).toBe(true);
      expect(assembler.isHigherSensitivity(SensitivityLevel.CONFIDENTIAL, SensitivityLevel.INTERNAL)).toBe(true);
      expect(assembler.isHigherSensitivity(SensitivityLevel.INTERNAL, SensitivityLevel.PUBLIC)).toBe(true);

      expect(assembler.isHigherSensitivity(SensitivityLevel.PUBLIC, SensitivityLevel.INTERNAL)).toBe(false);
      expect(assembler.isHigherSensitivity(SensitivityLevel.INTERNAL, SensitivityLevel.INTERNAL)).toBe(false);
    });
  });

  describe('Context Assembly - Basic Functionality', () => {
    test('should assemble context with no context documents', async () => {
      // Mock primary document with no context_documents
      const primaryContent = `---
sensitivity: internal
title: Primary Document
---

# Primary Content`;

      mockResolver.resolveDocument.mockResolvedValueOnce({
        type: 'filesystem',
        originalPath: 'docs/primary.md',
        resolvedPath: '/path/to/primary.md',
        exists: true,
      });

      mockResolver.readDocument.mockResolvedValueOnce(primaryContent);

      const result = await assembler.assembleContext('docs/primary.md');

      expect(result.primaryDocument.path).toBe('docs/primary.md');
      expect(result.primaryDocument.frontmatter.sensitivity).toBe(SensitivityLevel.INTERNAL);
      expect(result.contextDocuments).toHaveLength(0);
      expect(result.warnings).toHaveLength(0);
      expect(result.rejectedContexts).toHaveLength(0);
    });

    test('should assemble context with valid context documents', async () => {
      // Primary document
      const primaryContent = `---
sensitivity: confidential
title: Primary Document
context_documents:
  - docs/context1.md
  - docs/context2.md
---

# Primary Content`;

      // Context documents (same sensitivity)
      const context1Content = `---
sensitivity: confidential
title: Context 1
---

# Context 1 Content`;

      const context2Content = `---
sensitivity: internal
title: Context 2
---

# Context 2 Content`;

      mockResolver.resolveDocument
        .mockResolvedValueOnce({
          type: 'filesystem',
          originalPath: 'docs/primary.md',
          resolvedPath: '/path/to/primary.md',
          exists: true,
        })
        .mockResolvedValueOnce({
          type: 'filesystem',
          originalPath: 'docs/context1.md',
          resolvedPath: '/path/to/context1.md',
          exists: true,
        })
        .mockResolvedValueOnce({
          type: 'filesystem',
          originalPath: 'docs/context2.md',
          resolvedPath: '/path/to/context2.md',
          exists: true,
        });

      mockResolver.readDocument
        .mockResolvedValueOnce(primaryContent)
        .mockResolvedValueOnce(context1Content)
        .mockResolvedValueOnce(context2Content);

      const result = await assembler.assembleContext('docs/primary.md');

      expect(result.primaryDocument.path).toBe('docs/primary.md');
      expect(result.contextDocuments).toHaveLength(2);
      expect(result.contextDocuments[0]!.path).toBe('docs/context1.md');
      expect(result.contextDocuments[1]!.path).toBe('docs/context2.md');
      expect(result.warnings).toHaveLength(0);
      expect(result.rejectedContexts).toHaveLength(0);
    });

    test('should reject context document with higher sensitivity', async () => {
      // Primary document (internal)
      const primaryContent = `---
sensitivity: internal
title: Primary Document
context_documents:
  - docs/context-confidential.md
---

# Primary Content`;

      // Context document (confidential - higher sensitivity)
      const contextContent = `---
sensitivity: confidential
title: Confidential Context
---

# Confidential Content`;

      mockResolver.resolveDocument
        .mockResolvedValueOnce({
          type: 'filesystem',
          originalPath: 'docs/primary.md',
          resolvedPath: '/path/to/primary.md',
          exists: true,
        })
        .mockResolvedValueOnce({
          type: 'filesystem',
          originalPath: 'docs/context-confidential.md',
          resolvedPath: '/path/to/context-confidential.md',
          exists: true,
        });

      mockResolver.readDocument
        .mockResolvedValueOnce(primaryContent)
        .mockResolvedValueOnce(contextContent);

      const result = await assembler.assembleContext('docs/primary.md');

      expect(result.primaryDocument.path).toBe('docs/primary.md');
      expect(result.contextDocuments).toHaveLength(0);
      expect(result.rejectedContexts).toHaveLength(1);
      expect(result.rejectedContexts[0]!.path).toBe('docs/context-confidential.md');
      expect(result.rejectedContexts[0]!.reason).toContain('Sensitivity violation');
      expect(result.warnings.length).toBeGreaterThan(0);
    });

    test('should handle missing context documents gracefully', async () => {
      // Primary document
      const primaryContent = `---
sensitivity: internal
context_documents:
  - docs/missing.md
  - docs/exists.md
---

# Primary Content`;

      // Context document that exists
      const contextContent = `---
sensitivity: internal
---

# Context Content`;

      mockResolver.resolveDocument
        .mockResolvedValueOnce({
          type: 'filesystem',
          originalPath: 'docs/primary.md',
          resolvedPath: '/path/to/primary.md',
          exists: true,
        })
        .mockResolvedValueOnce({
          type: 'filesystem',
          originalPath: 'docs/missing.md',
          exists: false,
          error: 'File not found',
        })
        .mockResolvedValueOnce({
          type: 'filesystem',
          originalPath: 'docs/exists.md',
          resolvedPath: '/path/to/exists.md',
          exists: true,
        });

      mockResolver.readDocument
        .mockResolvedValueOnce(primaryContent)
        .mockResolvedValueOnce(contextContent);

      const result = await assembler.assembleContext('docs/primary.md');

      expect(result.primaryDocument.path).toBe('docs/primary.md');
      expect(result.contextDocuments).toHaveLength(1);
      expect(result.contextDocuments[0]!.path).toBe('docs/exists.md');
      expect(result.rejectedContexts).toHaveLength(1);
      expect(result.rejectedContexts[0]!.path).toBe('docs/missing.md');
      expect(result.warnings.length).toBeGreaterThan(0);
    });

    test('should apply default sensitivity when frontmatter missing', async () => {
      // Document without frontmatter
      const content = `# Document Without Frontmatter

Just plain content...`;

      mockResolver.resolveDocument.mockResolvedValueOnce({
        type: 'filesystem',
        originalPath: 'docs/no-frontmatter.md',
        resolvedPath: '/path/to/no-frontmatter.md',
        exists: true,
      });

      mockResolver.readDocument.mockResolvedValueOnce(content);

      const result = await assembler.assembleContext('docs/no-frontmatter.md');

      expect(result.primaryDocument.path).toBe('docs/no-frontmatter.md');
      expect(result.primaryDocument.frontmatter.sensitivity).toBe(SensitivityLevel.INTERNAL); // Default
      // Note: No warning is generated for missing frontmatter; default is applied silently
    });

    test('should limit number of context documents', async () => {
      // Primary document with many context docs
      const primaryContent = `---
sensitivity: internal
context_documents:
  - docs/ctx1.md
  - docs/ctx2.md
  - docs/ctx3.md
  - docs/ctx4.md
  - docs/ctx5.md
---

# Primary Content`;

      mockResolver.resolveDocument.mockResolvedValueOnce({
        type: 'filesystem',
        originalPath: 'docs/primary.md',
        resolvedPath: '/path/to/primary.md',
        exists: true,
      });

      mockResolver.readDocument.mockResolvedValueOnce(primaryContent);

      // Mock 3 context documents (limit is 3)
      for (let i = 1; i <= 3; i++) {
        mockResolver.resolveDocument.mockResolvedValueOnce({
          type: 'filesystem',
          originalPath: `docs/ctx${i}.md`,
          resolvedPath: `/path/to/ctx${i}.md`,
          exists: true,
        });

        mockResolver.readDocument.mockResolvedValueOnce(`---
sensitivity: internal
---

# Context ${i}`);
      }

      const result = await assembler.assembleContext('docs/primary.md', {
        maxContextDocuments: 3,
      });

      expect(result.primaryDocument.path).toBe('docs/primary.md');
      expect(result.contextDocuments).toHaveLength(3);
      expect(result.warnings).toContain('Context documents limited to 3 (5 specified)');
    });

    test('should detect and reject circular references', async () => {
      // Primary document that references itself
      const primaryContent = `---
sensitivity: internal
context_documents:
  - docs/primary.md
  - docs/other.md
---

# Primary Content`;

      // Other context document
      const otherContent = `---
sensitivity: internal
---

# Other Content`;

      mockResolver.resolveDocument
        .mockResolvedValueOnce({
          type: 'filesystem',
          originalPath: 'docs/primary.md',
          resolvedPath: '/path/to/primary.md',
          exists: true,
        })
        .mockResolvedValueOnce({
          type: 'filesystem',
          originalPath: 'docs/primary.md',
          resolvedPath: '/path/to/primary.md',
          exists: true,
        })
        .mockResolvedValueOnce({
          type: 'filesystem',
          originalPath: 'docs/other.md',
          resolvedPath: '/path/to/other.md',
          exists: true,
        });

      mockResolver.readDocument
        .mockResolvedValueOnce(primaryContent)
        .mockResolvedValueOnce(primaryContent) // Self-reference
        .mockResolvedValueOnce(otherContent);

      const result = await assembler.assembleContext('docs/primary.md', {
        allowCircularReferences: false,
      });

      expect(result.primaryDocument.path).toBe('docs/primary.md');
      expect(result.contextDocuments).toHaveLength(1);
      expect(result.contextDocuments[0]!.path).toBe('docs/other.md');
      expect(result.rejectedContexts).toHaveLength(1);
      expect(result.rejectedContexts[0]!.path).toBe('docs/primary.md');
      expect(result.rejectedContexts[0]!.reason).toBe('Circular reference');
    });

    test('should allow circular references when enabled', async () => {
      // Primary document that references itself
      const primaryContent = `---
sensitivity: internal
context_documents:
  - docs/primary.md
---

# Primary Content`;

      mockResolver.resolveDocument
        .mockResolvedValueOnce({
          type: 'filesystem',
          originalPath: 'docs/primary.md',
          resolvedPath: '/path/to/primary.md',
          exists: true,
        })
        .mockResolvedValueOnce({
          type: 'filesystem',
          originalPath: 'docs/primary.md',
          resolvedPath: '/path/to/primary.md',
          exists: true,
        });

      mockResolver.readDocument
        .mockResolvedValueOnce(primaryContent)
        .mockResolvedValueOnce(primaryContent);

      const result = await assembler.assembleContext('docs/primary.md', {
        allowCircularReferences: true,
      });

      expect(result.primaryDocument.path).toBe('docs/primary.md');
      expect(result.contextDocuments).toHaveLength(1);
      expect(result.contextDocuments[0]!.path).toBe('docs/primary.md');
      expect(result.rejectedContexts).toHaveLength(0);
    });
  });

  describe('Attack Scenario Prevention', () => {
    test('should prevent HIGH-011 attack: public doc accessing confidential context', async () => {
      // Public document trying to access confidential context
      const primaryContent = `---
sensitivity: public
context_documents:
  - docs/confidential-secrets.md
---

# Public Document`;

      const confidentialContent = `---
sensitivity: confidential
---

# API Keys and Secrets
- ANTHROPIC_API_KEY: sk-ant-...
- DATABASE_PASSWORD: super-secret`;

      mockResolver.resolveDocument
        .mockResolvedValueOnce({
          type: 'filesystem',
          originalPath: 'docs/public.md',
          resolvedPath: '/path/to/public.md',
          exists: true,
        })
        .mockResolvedValueOnce({
          type: 'filesystem',
          originalPath: 'docs/confidential-secrets.md',
          resolvedPath: '/path/to/confidential-secrets.md',
          exists: true,
        });

      mockResolver.readDocument
        .mockResolvedValueOnce(primaryContent)
        .mockResolvedValueOnce(confidentialContent);

      const result = await assembler.assembleContext('docs/public.md', {
        requestedBy: 'attacker',
      });

      // CRITICAL: Confidential document should be BLOCKED
      expect(result.contextDocuments).toHaveLength(0);
      expect(result.rejectedContexts).toHaveLength(1);
      expect(result.rejectedContexts[0]!.path).toBe('docs/confidential-secrets.md');
      expect(result.rejectedContexts[0]!.reason).toContain('Sensitivity violation');
      expect(result.rejectedContexts[0]!.reason).toContain('public document cannot access confidential context');
    });

    test('should prevent HIGH-011 attack: internal doc accessing restricted context', async () => {
      // Internal document trying to access restricted executive docs
      const primaryContent = `---
sensitivity: internal
context_documents:
  - docs/board-minutes.md
---

# Internal Document`;

      const restrictedContent = `---
sensitivity: restricted
---

# Board Minutes - RESTRICTED
- CEO Compensation: $5M
- M&A Target: Company X for $100M`;

      mockResolver.resolveDocument
        .mockResolvedValueOnce({
          type: 'filesystem',
          originalPath: 'docs/internal.md',
          resolvedPath: '/path/to/internal.md',
          exists: true,
        })
        .mockResolvedValueOnce({
          type: 'filesystem',
          originalPath: 'docs/board-minutes.md',
          resolvedPath: '/path/to/board-minutes.md',
          exists: true,
        });

      mockResolver.readDocument
        .mockResolvedValueOnce(primaryContent)
        .mockResolvedValueOnce(restrictedContent);

      const result = await assembler.assembleContext('docs/internal.md');

      // CRITICAL: Restricted document should be BLOCKED
      expect(result.contextDocuments).toHaveLength(0);
      expect(result.rejectedContexts).toHaveLength(1);
      expect(result.rejectedContexts[0]!.path).toBe('docs/board-minutes.md');
      expect(result.rejectedContexts[0]!.reason).toContain('internal document cannot access restricted context');
    });

    test('should allow HIGH-011 compliant access: restricted doc accessing all levels', async () => {
      // Restricted document can access all lower sensitivity levels
      const primaryContent = `---
sensitivity: restricted
context_documents:
  - docs/confidential.md
  - docs/internal.md
  - docs/public.md
---

# Restricted Document`;

      const confidentialContent = `---
sensitivity: confidential
---
# Confidential`;

      const internalContent = `---
sensitivity: internal
---
# Internal`;

      const publicContent = `---
sensitivity: public
---
# Public`;

      mockResolver.resolveDocument
        .mockResolvedValueOnce({
          type: 'filesystem',
          originalPath: 'docs/restricted.md',
          exists: true,
        })
        .mockResolvedValueOnce({
          type: 'filesystem',
          originalPath: 'docs/confidential.md',
          exists: true,
        })
        .mockResolvedValueOnce({
          type: 'filesystem',
          originalPath: 'docs/internal.md',
          exists: true,
        })
        .mockResolvedValueOnce({
          type: 'filesystem',
          originalPath: 'docs/public.md',
          exists: true,
        });

      mockResolver.readDocument
        .mockResolvedValueOnce(primaryContent)
        .mockResolvedValueOnce(confidentialContent)
        .mockResolvedValueOnce(internalContent)
        .mockResolvedValueOnce(publicContent);

      const result = await assembler.assembleContext('docs/restricted.md');

      // All context docs should be included (downward access is allowed)
      expect(result.contextDocuments).toHaveLength(3);
      expect(result.rejectedContexts).toHaveLength(0);
    });
  });

  describe('Frontmatter Validation', () => {
    test('should reject document with invalid sensitivity level', async () => {
      const primaryContent = `---
sensitivity: top-secret
---

# Invalid Sensitivity`;

      mockResolver.resolveDocument.mockResolvedValueOnce({
        type: 'filesystem',
        originalPath: 'docs/invalid.md',
        exists: true,
      });

      mockResolver.readDocument.mockResolvedValueOnce(primaryContent);

      const result = await assembler.assembleContext('docs/invalid.md');

      expect(result.warnings.length).toBeGreaterThan(0);
      expect(result.warnings[0]).toContain('invalid frontmatter');
    });

    test('should handle invalid YAML gracefully', async () => {
      const primaryContent = `---
sensitivity: internal
context_documents: not-an-array
tags: [tag1, tag2
---

# Invalid YAML`;

      mockResolver.resolveDocument.mockResolvedValueOnce({
        type: 'filesystem',
        originalPath: 'docs/bad-yaml.md',
        exists: true,
      });

      mockResolver.readDocument.mockResolvedValueOnce(primaryContent);

      const result = await assembler.assembleContext('docs/bad-yaml.md');

      // Should still work with defaults
      expect(result.primaryDocument.path).toBe('docs/bad-yaml.md');
      expect(result.primaryDocument.frontmatter.sensitivity).toBe(SensitivityLevel.INTERNAL); // Default
    });
  });

  describe('Edge Cases', () => {
    test('should handle primary document not found', async () => {
      mockResolver.resolveDocument.mockResolvedValueOnce({
        type: 'filesystem',
        originalPath: 'docs/missing.md',
        exists: false,
        error: 'File not found',
      });

      await expect(assembler.assembleContext('docs/missing.md')).rejects.toThrow(
        'Primary document not found or invalid'
      );
    });

    test('should handle empty context_documents array', async () => {
      const primaryContent = `---
sensitivity: internal
context_documents: []
---

# Primary Content`;

      mockResolver.resolveDocument.mockResolvedValueOnce({
        type: 'filesystem',
        originalPath: 'docs/primary.md',
        exists: true,
      });

      mockResolver.readDocument.mockResolvedValueOnce(primaryContent);

      const result = await assembler.assembleContext('docs/primary.md');

      expect(result.contextDocuments).toHaveLength(0);
      expect(result.warnings).toHaveLength(0);
    });

    test('should handle failOnValidationError option', async () => {
      const primaryContent = `---
sensitivity: invalid-level
---

# Invalid Document`;

      mockResolver.resolveDocument.mockResolvedValueOnce({
        type: 'filesystem',
        originalPath: 'docs/invalid.md',
        exists: true,
      });

      mockResolver.readDocument.mockResolvedValueOnce(primaryContent);

      await expect(
        assembler.assembleContext('docs/invalid.md', {
          failOnValidationError: true,
        })
      ).rejects.toThrow('invalid frontmatter');
    });
  });
});
