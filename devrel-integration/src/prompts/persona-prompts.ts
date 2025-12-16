/**
 * Persona Transformation Prompts
 *
 * Sprint 2 - Task 2.2: Persona Transformation Prompts
 *
 * Implements 4 persona-specific transformation prompts for the devrel-translator agent:
 * - Leadership: Executive summary (1-2 pages, business-focused, plain language, metrics-driven)
 * - Product: Technical article (2-3 pages, feature-focused, user stories, acceptance criteria)
 * - Marketing: Blog draft (1-2 pages, customer-focused, benefits, use cases, engaging tone)
 * - DevRel: Technical tutorial (3-4 pages, code-level, implementation details, architecture)
 *
 * Each prompt includes:
 * - Role context
 * - Audience description
 * - Output format and structure
 * - Tone guidelines
 * - Content guidelines
 * - Example structure
 */

import { logger } from '../utils/logger';

// =============================================================================
// Types and Interfaces
// =============================================================================

export type PersonaType = 'leadership' | 'product' | 'marketing' | 'devrel';

export type DocumentType = 'prd' | 'sdd' | 'sprint' | 'audit' | 'reviewer' | 'general';

export interface LinearIssue {
  id: string;
  title: string;
  description?: string;
  status: string;
  priority?: number;
  assignee?: string;
  labels?: string[];
  url?: string;
}

export interface GitHubPR {
  number: number;
  title: string;
  description?: string;
  status: 'open' | 'closed' | 'merged';
  author?: string;
  url?: string;
  changedFiles?: number;
  additions?: number;
  deletions?: number;
}

export interface DiscordMessage {
  id: string;
  content: string;
  author: string;
  timestamp: string;
  channel?: string;
  reactions?: string[];
}

export interface PersonaPromptParams {
  documentType: DocumentType;
  projectName: string;
  sourceContent: string;
  additionalContext?: {
    linearIssues?: LinearIssue[];
    githubPRs?: GitHubPR[];
    discordFeedback?: DiscordMessage[];
    sprintId?: string;
    summary?: string;
  };
}

export interface PersonaPromptConfig {
  persona: PersonaType;
  roleContext: string;
  audienceDescription: string;
  outputFormat: {
    length: string;
    structure: string[];
    technicalLevel: 'low' | 'medium' | 'high';
  };
  toneGuidelines: {
    tone: string;
    avoid: string[];
    emphasize: string[];
  };
  contentGuidelines: {
    focusAreas: string[];
    requiredSections: string[];
    optionalSections: string[];
  };
  exampleStructure: string;
}

// =============================================================================
// Persona Configurations
// =============================================================================

const PERSONA_CONFIGS: Record<PersonaType, PersonaPromptConfig> = {
  leadership: {
    persona: 'leadership',
    roleContext:
      'You are an experienced executive communication specialist translating technical documentation into strategic briefings for C-suite executives and board members.',
    audienceDescription:
      'C-suite executives (CEO, CTO, CFO), board members, and senior leadership who need to understand business impact, strategic alignment, risks, and key decisions without technical details.',
    outputFormat: {
      length: '1-2 pages (500-800 words)',
      structure: [
        'Executive Summary (2-3 sentences)',
        'Business Impact',
        'Key Metrics & KPIs',
        'Risks & Mitigations',
        'Strategic Alignment',
        'Timeline & Milestones',
        'Decision Points / Action Items',
      ],
      technicalLevel: 'low',
    },
    toneGuidelines: {
      tone: 'Professional, concise, strategic, action-oriented',
      avoid: [
        'Technical jargon',
        'Implementation details',
        'Code references',
        'Acronyms without explanation',
        'Lengthy explanations',
      ],
      emphasize: [
        'Business value',
        'ROI metrics',
        'Risk assessment',
        'Strategic fit',
        'Competitive advantage',
        'Timeline impact',
      ],
    },
    contentGuidelines: {
      focusAreas: [
        'Business impact and value',
        'Resource requirements',
        'Timeline and milestones',
        'Risks and mitigation strategies',
        'Strategic alignment',
        'Key decisions needed',
      ],
      requiredSections: ['Executive Summary', 'Business Impact', 'Risks', 'Next Steps'],
      optionalSections: ['Competitive Analysis', 'Budget Impact', 'Team Updates'],
    },
    exampleStructure: `# Executive Summary

[2-3 sentence overview of what was accomplished, its business value, and key outcomes]

## Business Impact

- **Revenue Impact:** [Quantified impact on revenue/cost savings]
- **Customer Value:** [How this benefits customers]
- **Operational Efficiency:** [Process improvements]

## Key Metrics

| Metric | Before | After | Change |
|--------|--------|-------|--------|
| [Metric 1] | [Value] | [Value] | [+/-X%] |

## Risks & Mitigations

| Risk | Severity | Mitigation | Status |
|------|----------|------------|--------|
| [Risk] | High/Med/Low | [Action] | [Status] |

## Timeline

- **Completed:** [What's done]
- **In Progress:** [Current work]
- **Next Milestone:** [Date] - [Deliverable]

## Decision Points

1. [Decision needed with options and recommendation]

## Next Steps

1. [Action item with owner and date]`,
  },

  product: {
    persona: 'product',
    roleContext:
      'You are a senior product manager translating technical documentation into product-focused articles that help product teams understand features, user impact, and roadmap implications.',
    audienceDescription:
      'Product managers, product designers, and product leaders who need to understand user impact, feature specifications, acceptance criteria, and roadmap alignment.',
    outputFormat: {
      length: '2-3 pages (800-1500 words)',
      structure: [
        'Feature Overview',
        'User Stories',
        'Acceptance Criteria',
        'User Impact Analysis',
        'Dependencies & Constraints',
        'Roadmap Implications',
        'Success Metrics',
      ],
      technicalLevel: 'medium',
    },
    toneGuidelines: {
      tone: 'User-focused, structured, analytical, outcome-oriented',
      avoid: [
        'Deep technical implementation details',
        'Code snippets',
        'Infrastructure specifics',
        'Security audit findings (summarize only)',
      ],
      emphasize: [
        'User value',
        'Feature capabilities',
        'User stories',
        'Acceptance criteria',
        'Success metrics',
        'Dependencies',
      ],
    },
    contentGuidelines: {
      focusAreas: [
        'User impact and value',
        'Feature specifications',
        'Acceptance criteria',
        'User stories and personas',
        'Dependencies on other features',
        'Roadmap fit',
      ],
      requiredSections: ['Feature Overview', 'User Stories', 'Acceptance Criteria', 'Success Metrics'],
      optionalSections: ['Competitive Analysis', 'A/B Test Plan', 'Launch Checklist'],
    },
    exampleStructure: `# Feature Overview

## Summary
[2-3 paragraphs describing the feature, its purpose, and user value]

## User Stories

### As a [persona], I want to [action] so that [benefit]

**Acceptance Criteria:**
- [ ] Given [context], when [action], then [outcome]
- [ ] Given [context], when [action], then [outcome]

### As a [persona], I want to [action] so that [benefit]

**Acceptance Criteria:**
- [ ] Given [context], when [action], then [outcome]

## User Impact Analysis

### Target Users
- **Primary:** [User segment and size]
- **Secondary:** [User segment and size]

### Expected Outcomes
- [Outcome 1 with expected metric change]
- [Outcome 2 with expected metric change]

## Dependencies & Constraints

| Dependency | Type | Status | Impact |
|------------|------|--------|--------|
| [Feature/System] | Required/Optional | Done/In Progress | [Impact] |

## Success Metrics

| Metric | Current | Target | Measurement Method |
|--------|---------|--------|-------------------|
| [Metric] | [Value] | [Value] | [How measured] |

## Roadmap Implications

- **Prerequisites:** [What must be done first]
- **Enables:** [What this unblocks]
- **Timeline:** [Expected delivery]`,
  },

  marketing: {
    persona: 'marketing',
    roleContext:
      'You are a creative marketing writer translating technical documentation into engaging blog content and marketing materials that resonate with customers and prospects.',
    audienceDescription:
      'Potential customers, existing users, industry analysts, and the broader tech community who want to understand product capabilities, benefits, and use cases in an accessible, engaging way.',
    outputFormat: {
      length: '1-2 pages (500-800 words)',
      structure: [
        'Compelling Headline',
        'Hook/Opening',
        'Problem Statement',
        'Solution Overview',
        'Key Benefits',
        'Use Cases',
        'Call to Action',
      ],
      technicalLevel: 'low',
    },
    toneGuidelines: {
      tone: 'Engaging, conversational, benefit-focused, inspiring',
      avoid: [
        'Technical jargon',
        'Internal process details',
        'Negative competitor mentions',
        'Unsubstantiated claims',
        'Complex architecture details',
      ],
      emphasize: [
        'Customer benefits',
        'Real-world use cases',
        'Success stories',
        'Competitive advantages',
        'Easy-to-understand value propositions',
      ],
    },
    contentGuidelines: {
      focusAreas: [
        'Customer value and benefits',
        'Use cases and scenarios',
        'Problem-solution narrative',
        'Competitive differentiation',
        'Call to action',
      ],
      requiredSections: ['Headline', 'Problem', 'Solution', 'Benefits', 'Call to Action'],
      optionalSections: ['Customer Quote', 'Comparison Table', 'FAQ'],
    },
    exampleStructure: `# [Compelling Headline that Captures Attention]

**[Subheadline that expands on the value proposition]**

---

## The Challenge

[2-3 paragraphs describing the problem your audience faces in relatable terms]

## Introducing [Feature/Product Name]

[2-3 paragraphs describing the solution in benefit-focused language]

## Key Benefits

### [Benefit 1 Title]
[Description of benefit with concrete outcome]

### [Benefit 2 Title]
[Description of benefit with concrete outcome]

### [Benefit 3 Title]
[Description of benefit with concrete outcome]

## Real-World Use Cases

### [Use Case 1]
[Brief story or scenario showing the feature in action]

### [Use Case 2]
[Brief story or scenario showing the feature in action]

## What Our Users Are Saying

> "[Customer quote about the benefit they experienced]"
> — [Customer Name], [Title] at [Company]

## Get Started Today

[Clear call to action with next steps]

[Button: Try It Free / Learn More / Contact Sales]`,
  },

  devrel: {
    persona: 'devrel',
    roleContext:
      'You are an experienced developer advocate creating technical tutorials and documentation that help developers understand, implement, and succeed with the technology.',
    audienceDescription:
      'Software developers, engineers, and technical architects who need detailed implementation guidance, code examples, architecture explanations, and best practices.',
    outputFormat: {
      length: '3-4 pages (1200-2000 words)',
      structure: [
        'Overview & Prerequisites',
        'Architecture Explanation',
        'Step-by-Step Implementation',
        'Code Examples',
        'Best Practices',
        'Troubleshooting',
        'Next Steps & Resources',
      ],
      technicalLevel: 'high',
    },
    toneGuidelines: {
      tone: 'Technical, educational, practical, developer-friendly',
      avoid: [
        'Marketing language',
        'Vague descriptions',
        'Untested code',
        'Missing error handling',
        'Incomplete examples',
      ],
      emphasize: [
        'Working code examples',
        'Step-by-step instructions',
        'Architecture decisions',
        'Best practices',
        'Common pitfalls',
        'Performance considerations',
      ],
    },
    contentGuidelines: {
      focusAreas: [
        'Technical implementation details',
        'Code examples with explanations',
        'Architecture patterns',
        'API usage',
        'Error handling',
        'Testing approaches',
        'Performance optimization',
      ],
      requiredSections: ['Overview', 'Prerequisites', 'Implementation', 'Code Examples', 'Next Steps'],
      optionalSections: ['Performance Benchmarks', 'Security Considerations', 'Migration Guide'],
    },
    exampleStructure: `# [Technical Title]: [Specific Implementation/Feature]

## Overview

[2-3 paragraphs explaining what this tutorial covers and why it matters]

## Prerequisites

- [Requirement 1 with version]
- [Requirement 2 with link]
- [Knowledge requirement]

## Architecture

[Explanation of the technical architecture with diagram description]

\`\`\`
┌─────────────────┐     ┌─────────────────┐
│   Component A   │────▶│   Component B   │
└─────────────────┘     └─────────────────┘
\`\`\`

## Implementation

### Step 1: [Setup/Configuration]

[Explanation of what we're doing and why]

\`\`\`typescript
// Example code with comments
const config = {
  option: 'value',
};
\`\`\`

### Step 2: [Core Implementation]

[Explanation of the main implementation]

\`\`\`typescript
// Main implementation code
async function implementation() {
  // Implementation details with error handling
}
\`\`\`

### Step 3: [Integration/Testing]

[How to test and verify the implementation]

\`\`\`bash
# Testing commands
npm test
\`\`\`

## Best Practices

1. **[Practice 1]:** [Explanation]
2. **[Practice 2]:** [Explanation]
3. **[Practice 3]:** [Explanation]

## Troubleshooting

### Issue: [Common Problem]
**Solution:** [How to fix it]

### Issue: [Another Problem]
**Solution:** [How to fix it]

## Next Steps

- [Link to advanced topic]
- [Link to related tutorial]
- [Link to API reference]

## Resources

- [Official Documentation]
- [GitHub Repository]
- [Community Forum]`,
  },
};

// =============================================================================
// Prompt Generator
// =============================================================================

/**
 * Generate a persona-specific transformation prompt
 */
export function generatePersonaPrompt(
  persona: PersonaType,
  params: PersonaPromptParams
): string {
  const config = PERSONA_CONFIGS[persona];

  if (!config) {
    throw new Error(`Unknown persona: ${persona}`);
  }

  logger.info('Generating persona prompt', {
    persona,
    documentType: params.documentType,
    projectName: params.projectName,
    hasAdditionalContext: !!params.additionalContext,
  });

  // Build context section
  const contextSection = buildContextSection(params);

  // Build the full prompt
  const prompt = `${config.roleContext}

## Your Task

Transform the following technical documentation into a ${persona}-focused summary for ${config.audienceDescription.toLowerCase()}.

## Output Requirements

**Length:** ${config.outputFormat.length}
**Technical Level:** ${config.outputFormat.technicalLevel}
**Required Sections:** ${config.contentGuidelines.requiredSections.join(', ')}

## Tone Guidelines

**Tone:** ${config.toneGuidelines.tone}

**Emphasize:**
${config.toneGuidelines.emphasize.map(e => `- ${e}`).join('\n')}

**Avoid:**
${config.toneGuidelines.avoid.map(a => `- ${a}`).join('\n')}

## Content Focus Areas

${config.contentGuidelines.focusAreas.map(f => `- ${f}`).join('\n')}

## Project Context

**Project Name:** ${params.projectName}
**Document Type:** ${params.documentType}
${params.additionalContext?.sprintId ? `**Sprint:** ${params.additionalContext.sprintId}` : ''}

${contextSection}

## Source Document

${params.sourceContent}

## Output Format Example

${config.exampleStructure}

---

Generate the ${persona} summary now. Follow the structure and guidelines above precisely. Do not include any meta-commentary about the transformation process.`;

  logger.debug('Generated persona prompt', {
    persona,
    promptLength: prompt.length,
    estimatedTokens: Math.ceil(prompt.length / 4),
  });

  return prompt;
}

/**
 * Build additional context section
 */
function buildContextSection(params: PersonaPromptParams): string {
  const sections: string[] = [];

  if (params.additionalContext?.summary) {
    sections.push(`## Summary\n\n${params.additionalContext.summary}`);
  }

  if (params.additionalContext?.linearIssues && params.additionalContext.linearIssues.length > 0) {
    const issuesList = params.additionalContext.linearIssues
      .slice(0, 10) // Limit to 10 issues
      .map(
        issue =>
          `- **${issue.title}** (${issue.status})${issue.priority ? ` - Priority: ${issue.priority}` : ''}`
      )
      .join('\n');

    sections.push(`## Related Linear Issues\n\n${issuesList}`);
  }

  if (params.additionalContext?.githubPRs && params.additionalContext.githubPRs.length > 0) {
    const prsList = params.additionalContext.githubPRs
      .slice(0, 5) // Limit to 5 PRs
      .map(
        pr =>
          `- **#${pr.number}: ${pr.title}** (${pr.status})${
            pr.changedFiles ? ` - ${pr.changedFiles} files changed` : ''
          }`
      )
      .join('\n');

    sections.push(`## Related Pull Requests\n\n${prsList}`);
  }

  if (
    params.additionalContext?.discordFeedback &&
    params.additionalContext.discordFeedback.length > 0
  ) {
    const feedbackList = params.additionalContext.discordFeedback
      .slice(0, 5) // Limit to 5 messages
      .map(msg => `- "${msg.content.substring(0, 200)}..." — ${msg.author}`)
      .join('\n');

    sections.push(`## Community Feedback\n\n${feedbackList}`);
  }

  return sections.length > 0 ? `## Additional Context\n\n${sections.join('\n\n')}` : '';
}

/**
 * Get persona configuration
 */
export function getPersonaConfig(persona: PersonaType): PersonaPromptConfig {
  const config = PERSONA_CONFIGS[persona];
  if (!config) {
    throw new Error(`Unknown persona: ${persona}`);
  }
  return config;
}

/**
 * Get all available personas
 */
export function getAvailablePersonas(): PersonaType[] {
  return Object.keys(PERSONA_CONFIGS) as PersonaType[];
}

/**
 * Validate persona prompt parameters
 */
export function validatePromptParams(params: PersonaPromptParams): {
  valid: boolean;
  errors: string[];
} {
  const errors: string[] = [];

  if (!params.projectName || params.projectName.trim().length === 0) {
    errors.push('Project name is required');
  }

  if (!params.sourceContent || params.sourceContent.trim().length === 0) {
    errors.push('Source content is required');
  }

  const validDocTypes: DocumentType[] = ['prd', 'sdd', 'sprint', 'audit', 'reviewer', 'general'];
  if (!validDocTypes.includes(params.documentType)) {
    errors.push(`Invalid document type: ${params.documentType}`);
  }

  // Check source content length (rough token estimate)
  const estimatedTokens = Math.ceil(params.sourceContent.length / 4);
  if (estimatedTokens > 100000) {
    errors.push(`Source content too large: ~${estimatedTokens} tokens (max 100,000)`);
  }

  return {
    valid: errors.length === 0,
    errors,
  };
}

/**
 * Estimate output tokens based on persona
 */
export function estimateOutputTokens(persona: PersonaType): { min: number; max: number } {
  const config = PERSONA_CONFIGS[persona];

  // Parse length string (e.g., "1-2 pages (500-800 words)")
  const wordMatch = config.outputFormat.length.match(/(\d+)-(\d+)\s*words/);

  if (wordMatch) {
    const minWords = parseInt(wordMatch[1]!, 10);
    const maxWords = parseInt(wordMatch[2]!, 10);

    // Rough conversion: 1 word ≈ 1.3 tokens
    return {
      min: Math.ceil(minWords * 1.3),
      max: Math.ceil(maxWords * 1.3),
    };
  }

  // Default estimates based on page count
  const pageMatch = config.outputFormat.length.match(/(\d+)-(\d+)\s*pages?/);
  if (pageMatch) {
    const minPages = parseInt(pageMatch[1]!, 10);
    const maxPages = parseInt(pageMatch[2]!, 10);

    // Rough conversion: 1 page ≈ 500 words ≈ 650 tokens
    return {
      min: minPages * 650,
      max: maxPages * 650,
    };
  }

  // Fallback defaults
  return { min: 500, max: 2000 };
}

// =============================================================================
// Export
// =============================================================================

export default {
  generatePersonaPrompt,
  getPersonaConfig,
  getAvailablePersonas,
  validatePromptParams,
  estimateOutputTokens,
  PERSONA_CONFIGS,
};
