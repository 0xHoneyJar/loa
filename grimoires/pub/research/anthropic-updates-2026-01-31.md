# Anthropic Oracle Analysis: AskUserQuestion & Playground Plugin

**Date:** 2026-01-31
**Focus:** AskUserQuestion Tool UX + Playground Plugin
**Analyst:** Claude Opus 4.5

---

## Executive Summary

- **Playground Plugin** announced by Thariq ([@trq212](https://x.com/trq212)) creates standalone HTML files for visual, interactive Claude Code workflows
- **AskUserQuestion** received key UX improvements: auto-submit for single-select (v2.0.55), external editor support (Ctrl+G)
- **Frontend Design Plugin** (120k+ installs) is the closest official plugin for interactive HTML generation
- **Key DX insight**: Time pressure in AskUserQuestion UI is a friction point; "Type something else..." pauses the timer
- **Opportunity for Loa**: Integrate playground-style visual workflows for architecture diagrams, sprint planning boards, and approval interfaces

---

## 1. The Playground Plugin (Thariq's Announcement)

### What It Does

From [Thariq's announcement](https://x.com/trq212) on Jan 29, 2026:

> "We've published a new Claude Code plugin called **playground** that helps Claude generate HTML playgrounds. These are standalone HTML files that let you visualize a problem with Claude, interact with it and give you an output prompt to paste back into Claude Code."

### Installation

```bash
/plugin marketplace update claude-plugins-official
/plugin install playground@claude-plugins-official
```

### Use Cases Demonstrated

| Use Case | Prompt Example |
|----------|----------------|
| **AskUserQuestion Layout Redesign** | "Use the playground skill to create a playground that helps me explore new layout changes to the AskUserQuestion Tool" |
| **Writing Critique** | "Review my SKILL.MD and give me inline suggestions I can approve, reject or comment" |
| **Video Editing** | "Tweak my Remotion intro screen to be more interesting and delightful" |
| **Architecture Diagrams** | "Show how this email agent codebase works and let me comment on particular nodes" |
| **Game Balancing** | "Help me balance the 'Inferno' hero's deck" |

### Key Insight for DX

> "Think of a unique way of interacting with the model and then ask it to express that."

The playground creates a **bidirectional** interface - work in the terminal OR in the UI.

---

## 2. AskUserQuestion Tool Updates

### Version History

| Version | Change | Impact |
|---------|--------|--------|
| **v2.0.45** | Initial interactive question tool | Foundation |
| **v2.0.55** | Auto-submit for single-select on last question | Reduced clicks |
| **v2.1.x** | External editor support (Ctrl+G) in "Other" input | Power users |
| **v2.1.x** | Error display when editor fails during Ctrl+G | Error handling |

### Current Capabilities

```json
{
  "questions": [
    {
      "question": "Which auth strategy should we use?",
      "header": "Auth",
      "options": [
        { "label": "JWT (Recommended)", "description": "Stateless, scalable" },
        { "label": "Session-based", "description": "Traditional, server-side" },
        { "label": "OAuth 2.0", "description": "Third-party integration" }
      ],
      "multiSelect": false
    }
  ]
}
```

**Key Parameters:**
- `multiSelect: true` - Checkbox-style multiple selections
- `header` - Short label (max 12 chars) displayed as chip/tag
- `options` - 2-4 options per question, 1-4 questions per call
- "Other" option always available for freeform text

### UX Friction Points (from [TorqSoftware analysis](https://torqsoftware.com/blog/2026/2026-01-14-claude-ask-user-question/))

1. **Timed interface** - Questions rotate through options with time pressure
2. **Reading interruption** - "I'd find myself thinking 'come back, I wasn't finished reading that'"
3. **Workaround** - Select "Type something else..." to pause the timer

### UX Best Practices

1. Place recommended option **first** with "(Recommended)" suffix
2. Keep headers under 12 characters
3. Provide descriptions for complex trade-offs
4. Use `multiSelect: true` when choices aren't mutually exclusive
5. Avoid using for plan approval (use ExitPlanMode instead)

---

## 3. Related Plugins

### Frontend Design Plugin

**Installs:** 120,556
**Source:** [claude.com/plugins](https://claude.com/plugins)

> "Craft production-grade frontends with distinctive design. Generates polished code that avoids generic AI aesthetics."

```bash
/plugin install frontend-design@claude-code-plugins
```

### Playwright Plugin

**Installs:** 36,463

Browser automation allowing Claude to interact with web pages and capture screenshots.

### Figma Plugin

**Installs:** 21,430

Design file access and component extraction for design-to-code workflow.

---

## 4. Loa Integration Opportunities

### Immediate Wins

| Opportunity | Implementation | Effort |
|-------------|----------------|--------|
| **Visual Sprint Board** | Use playground to render interactive sprint plan | Medium |
| **Architecture Diagram Comments** | SDD diagrams with inline feedback | Medium |
| **Approval Flows** | Replace text-based approvals with visual checkboxes | Low |
| **Goal Traceability UI** | Visual mapping of G-N goals to sprint tasks | High |

### Proposed Skill Enhancement

```yaml
# .claude/skills/visual-approval/SKILL.md
name: visual-approval
description: Generate HTML playground for visual approval flows
triggers:
  - /approve-visual
  - /review-visual
dependencies:
  - playground@claude-plugins-official
```

### AskUserQuestion Usage in Loa Skills

Skills that could benefit from improved AskUserQuestion patterns:

1. **discovering-requirements** - Tech stack selection, feature prioritization
2. **planning-sprints** - Task assignment, effort estimation
3. **designing-architecture** - Pattern selection, database choices
4. **reviewing-code** - Approval with detailed options

### Sample Enhancement

```markdown
<!-- In skill KERNEL -->
When presenting options to the user, use AskUserQuestion with:
- Clear headers (max 12 chars)
- Recommended option first with "(Recommended)" suffix
- Descriptions explaining trade-offs
- multiSelect for non-exclusive choices

Avoid time-pressure scenarios by providing clear, scannable options.
```

---

## 5. Gaps Analysis

| Anthropic Offers | Loa Has | Gap |
|------------------|---------|-----|
| Playground plugin | Mermaid diagrams | Interactive HTML generation |
| Auto-submit UX | Standard prompts | Streamlined approval flows |
| External editor (Ctrl+G) | N/A | Power user input |
| Frontend Design plugin | N/A | Visual prototyping |

---

## 6. Recommended Actions

### Priority 1: Document Playground Plugin
- [ ] Add playground plugin to recommended integrations
- [ ] Create examples in `.claude/mcp-examples/`
- [ ] Document use cases for Loa workflows

### Priority 2: Enhance AskUserQuestion Patterns
- [ ] Update skill KERNELs with best practices
- [ ] Add "(Recommended)" pattern to discovering-requirements
- [ ] Consider multiSelect for tech stack choices

### Priority 3: Visual Communication Expansion
- [ ] Extend `/beautiful-mermaid` to support playground-style interactivity
- [ ] Create visual sprint board skill
- [ ] Prototype goal traceability UI

---

## Sources

- [Thariq (@trq212) Playground Announcement](https://x.com/trq212) - Jan 29, 2026
- [Claude Code Plugins Directory](https://claude.com/plugins)
- [Claude Code Changelog](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- [AskUserQuestion First Impressions - TorqSoftware](https://torqsoftware.com/blog/2026/2026-01-14-claude-ask-user-question/)
- [Handle approvals and user input - Claude API Docs](https://platform.claude.com/docs/en/agent-sdk/user-input)
- [Claude Code System Prompts - Piebald-AI](https://github.com/Piebald-AI/claude-code-system-prompts)
- [ClaudeLog Changelog](https://claudelog.com/claude-code-changelog/)
- [CladueFast Changelog](https://claudefa.st/blog/guide/changelog)
