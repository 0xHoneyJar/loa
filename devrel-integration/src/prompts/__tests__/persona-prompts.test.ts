/**
 * Persona Prompts Tests
 *
 * Tests for persona-specific transformation prompts:
 * - Leadership persona
 * - Product persona
 * - Marketing persona
 * - DevRel persona
 * - Prompt generation
 * - Content guidelines
 */

import {
  generatePersonaPrompt,
  getPersonaConfig,
  PersonaType,
  PersonaPromptParams,
  PERSONA_CONFIGS,
  DOCUMENT_TYPE_CONTEXT,
} from '../persona-prompts';

describe('Persona Prompts', () => {
  describe('PERSONA_CONFIGS', () => {
    it('should have all four personas defined', () => {
      expect(PERSONA_CONFIGS.leadership).toBeDefined();
      expect(PERSONA_CONFIGS.product).toBeDefined();
      expect(PERSONA_CONFIGS.marketing).toBeDefined();
      expect(PERSONA_CONFIGS.devrel).toBeDefined();
    });

    it('should have required fields for each persona', () => {
      const requiredFields = [
        'roleContext',
        'audienceDescription',
        'outputFormat',
        'toneGuidelines',
        'contentGuidelines',
        'exampleStructure',
      ];

      Object.values(PERSONA_CONFIGS).forEach((config) => {
        requiredFields.forEach((field) => {
          expect(config[field]).toBeDefined();
          expect(config[field].length).toBeGreaterThan(0);
        });
      });
    });
  });

  describe('DOCUMENT_TYPE_CONTEXT', () => {
    it('should have context for all document types', () => {
      expect(DOCUMENT_TYPE_CONTEXT.prd).toBeDefined();
      expect(DOCUMENT_TYPE_CONTEXT.sdd).toBeDefined();
      expect(DOCUMENT_TYPE_CONTEXT.sprint).toBeDefined();
      expect(DOCUMENT_TYPE_CONTEXT.audit).toBeDefined();
      expect(DOCUMENT_TYPE_CONTEXT.reviewer).toBeDefined();
      expect(DOCUMENT_TYPE_CONTEXT.general).toBeDefined();
    });
  });

  describe('getPersonaConfig', () => {
    it('should return leadership config', () => {
      const config = getPersonaConfig('leadership');

      expect(config.roleContext).toContain('executive');
      expect(config.audienceDescription).toBeDefined();
    });

    it('should return product config', () => {
      const config = getPersonaConfig('product');

      expect(config.roleContext).toContain('product');
      expect(config.audienceDescription).toBeDefined();
    });

    it('should return marketing config', () => {
      const config = getPersonaConfig('marketing');

      expect(config.roleContext).toContain('marketing');
      expect(config.audienceDescription).toBeDefined();
    });

    it('should return devrel config', () => {
      const config = getPersonaConfig('devrel');

      expect(config.roleContext).toContain('developer');
      expect(config.audienceDescription).toBeDefined();
    });

    it('should throw for invalid persona', () => {
      expect(() => getPersonaConfig('invalid' as PersonaType)).toThrow();
    });
  });

  describe('generatePersonaPrompt - Leadership', () => {
    const baseParams: PersonaPromptParams = {
      documentType: 'prd',
      projectName: 'Onomancer Bot',
      sourceContent: '# PRD\n\n## Overview\nA Discord bot for naming.',
    };

    it('should generate leadership prompt with executive focus', () => {
      const prompt = generatePersonaPrompt('leadership', baseParams);

      expect(prompt).toContain('leadership');
      expect(prompt).toContain('Onomancer Bot');
      expect(prompt).toContain('PRD');
    });

    it('should include strategic language for leadership', () => {
      const prompt = generatePersonaPrompt('leadership', baseParams);

      // Leadership prompts should emphasize business value, ROI, strategic impact
      expect(prompt.toLowerCase()).toMatch(/strategic|business|value|roi|impact/);
    });

    it('should include tone guidelines', () => {
      const prompt = generatePersonaPrompt('leadership', baseParams);

      // Should reference the tone expected
      expect(prompt).toContain(PERSONA_CONFIGS.leadership.toneGuidelines);
    });
  });

  describe('generatePersonaPrompt - Product', () => {
    const baseParams: PersonaPromptParams = {
      documentType: 'sprint',
      projectName: 'Onomancer Bot',
      sourceContent: '# Sprint 1\n\n## Tasks\n- Implement feature X',
    };

    it('should generate product prompt with feature focus', () => {
      const prompt = generatePersonaPrompt('product', baseParams);

      expect(prompt).toContain('product');
      expect(prompt).toContain('Onomancer Bot');
    });

    it('should include user-centric language', () => {
      const prompt = generatePersonaPrompt('product', baseParams);

      // Product prompts should emphasize user value, features, priorities
      expect(prompt.toLowerCase()).toMatch(/user|feature|priorit|requirement/);
    });
  });

  describe('generatePersonaPrompt - Marketing', () => {
    const baseParams: PersonaPromptParams = {
      documentType: 'general',
      projectName: 'Onomancer Bot',
      sourceContent: '# Project Update\n\nNew features released.',
    };

    it('should generate marketing prompt with engagement focus', () => {
      const prompt = generatePersonaPrompt('marketing', baseParams);

      expect(prompt).toContain('marketing');
      expect(prompt).toContain('Onomancer Bot');
    });

    it('should include engagement-oriented language', () => {
      const prompt = generatePersonaPrompt('marketing', baseParams);

      // Marketing prompts should emphasize story, engagement, community
      expect(prompt.toLowerCase()).toMatch(/story|engage|community|brand|message/);
    });
  });

  describe('generatePersonaPrompt - DevRel', () => {
    const baseParams: PersonaPromptParams = {
      documentType: 'sdd',
      projectName: 'Onomancer Bot',
      sourceContent: '# SDD\n\n## Architecture\nMicroservices-based design.',
    };

    it('should generate devrel prompt with technical focus', () => {
      const prompt = generatePersonaPrompt('devrel', baseParams);

      expect(prompt).toContain('devrel');
      expect(prompt).toContain('Onomancer Bot');
    });

    it('should include developer-focused language', () => {
      const prompt = generatePersonaPrompt('devrel', baseParams);

      // DevRel prompts should emphasize technical accuracy, developer experience
      expect(prompt.toLowerCase()).toMatch(/developer|technical|api|integration|documentation/);
    });
  });

  describe('generatePersonaPrompt - Additional context', () => {
    it('should include Linear issues when provided', () => {
      const params: PersonaPromptParams = {
        documentType: 'sprint',
        projectName: 'Test Project',
        sourceContent: '# Sprint\n\nContent here.',
        additionalContext: {
          linearIssues: [
            {
              id: 'ISSUE-1',
              title: 'Implement feature',
              description: 'Description here',
              state: 'In Progress',
              priority: 2,
            },
          ],
        },
      };

      const prompt = generatePersonaPrompt('product', params);

      expect(prompt).toContain('ISSUE-1');
      expect(prompt).toContain('Implement feature');
    });

    it('should include GitHub PRs when provided', () => {
      const params: PersonaPromptParams = {
        documentType: 'reviewer',
        projectName: 'Test Project',
        sourceContent: '# Implementation Report\n\nChanges made.',
        additionalContext: {
          githubPRs: [
            {
              number: 42,
              title: 'Add new feature',
              body: 'PR description',
              state: 'open',
              url: 'https://github.com/org/repo/pull/42',
            },
          ],
        },
      };

      const prompt = generatePersonaPrompt('devrel', params);

      expect(prompt).toContain('42');
      expect(prompt).toContain('Add new feature');
    });

    it('should include Discord feedback when provided', () => {
      const params: PersonaPromptParams = {
        documentType: 'general',
        projectName: 'Test Project',
        sourceContent: '# Update\n\nProject status.',
        additionalContext: {
          discordFeedback: [
            {
              id: 'msg-1',
              content: 'Great work on the feature!',
              author: 'user123',
              timestamp: new Date().toISOString(),
              channel: 'feedback',
            },
          ],
        },
      };

      const prompt = generatePersonaPrompt('marketing', params);

      expect(prompt).toContain('Discord');
      expect(prompt).toContain('Great work');
    });
  });

  describe('generatePersonaPrompt - Document types', () => {
    const personas: PersonaType[] = ['leadership', 'product', 'marketing', 'devrel'];
    const docTypes = ['prd', 'sdd', 'sprint', 'audit', 'reviewer', 'general'] as const;

    it('should generate prompts for all persona/document combinations', () => {
      personas.forEach((persona) => {
        docTypes.forEach((docType) => {
          const params: PersonaPromptParams = {
            documentType: docType,
            projectName: 'Test Project',
            sourceContent: `# ${docType.toUpperCase()}\n\nContent.`,
          };

          const prompt = generatePersonaPrompt(persona, params);

          expect(prompt).toBeTruthy();
          expect(prompt.length).toBeGreaterThan(100);
        });
      });
    });

    it('should include document type context', () => {
      const params: PersonaPromptParams = {
        documentType: 'audit',
        projectName: 'Test Project',
        sourceContent: '# Security Audit\n\nFindings here.',
      };

      const prompt = generatePersonaPrompt('leadership', params);

      expect(prompt).toContain(DOCUMENT_TYPE_CONTEXT.audit);
    });
  });

  describe('generatePersonaPrompt - Output format', () => {
    it('should include output format guidelines', () => {
      const params: PersonaPromptParams = {
        documentType: 'prd',
        projectName: 'Test Project',
        sourceContent: '# PRD\n\nContent.',
      };

      const prompt = generatePersonaPrompt('leadership', params);

      expect(prompt).toContain(PERSONA_CONFIGS.leadership.outputFormat);
    });

    it('should include example structure', () => {
      const params: PersonaPromptParams = {
        documentType: 'prd',
        projectName: 'Test Project',
        sourceContent: '# PRD\n\nContent.',
      };

      const prompt = generatePersonaPrompt('leadership', params);

      expect(prompt).toContain(PERSONA_CONFIGS.leadership.exampleStructure);
    });
  });

  describe('edge cases', () => {
    it('should handle empty source content', () => {
      const params: PersonaPromptParams = {
        documentType: 'general',
        projectName: 'Test Project',
        sourceContent: '',
      };

      const prompt = generatePersonaPrompt('leadership', params);

      expect(prompt).toBeTruthy();
    });

    it('should handle very long source content', () => {
      const params: PersonaPromptParams = {
        documentType: 'sdd',
        projectName: 'Test Project',
        sourceContent: 'A'.repeat(100000),
      };

      const prompt = generatePersonaPrompt('devrel', params);

      expect(prompt).toBeTruthy();
    });

    it('should handle special characters in project name', () => {
      const params: PersonaPromptParams = {
        documentType: 'prd',
        projectName: 'Project <with> "special" & chars',
        sourceContent: '# Content',
      };

      const prompt = generatePersonaPrompt('product', params);

      expect(prompt).toContain('Project <with> "special" & chars');
    });

    it('should handle markdown in source content', () => {
      const params: PersonaPromptParams = {
        documentType: 'sdd',
        projectName: 'Test Project',
        sourceContent: `
# Heading
## Subheading

- List item
- Another item

\`\`\`typescript
const code = 'example';
\`\`\`

| Table | Header |
|-------|--------|
| Cell  | Data   |
        `,
      };

      const prompt = generatePersonaPrompt('devrel', params);

      expect(prompt).toBeTruthy();
      expect(prompt).toContain('Heading');
    });
  });
});
