# Context Templates for /adopt

Place these files in `loa-grimoire/context/` before running `/adopt` to guide the adoption process.

> **Remember: CODE IS TRUTH**
> These context files provide HYPOTHESES to verify against code.
> They guide WHERE to look, not WHAT to report.
> Code evidence always wins conflicts.

---

## Quick Start

```bash
mkdir -p loa-grimoire/context

# Copy relevant templates and fill in what you know:
# - architecture-notes.md   (system design, module boundaries)
# - stakeholder-context.md  (business priorities, critical features)
# - tribal-knowledge.md     (gotchas, unwritten rules)
# - roadmap-context.md      (planned changes, deprecations)
# - constraints.md          (technical/business constraints)
# - glossary.md             (domain terminology)
```

---

## architecture-notes.md

```markdown
# Architecture Notes

> What we believe about the system architecture.
> /adopt will VERIFY these claims against actual code.

## Overview

[High-level description of the system architecture]

## Key Modules

- **[Module Name]**: [Purpose, key files]
- **[Module Name]**: [Purpose, key files]

## Data Flow

[How data moves through the system]

## External Dependencies

- [Service]: [What it's used for]

## Known Technical Debt

- [Area]: [Description of debt]

## Architecture Decisions

- [Decision]: [Rationale]

## Diagrams

[ASCII diagrams or links to architecture diagrams]
```

---

## stakeholder-context.md

```markdown
# Stakeholder Context

> Business context that helps prioritize what to document.
> /adopt will focus on these areas with extra care.

## Business Goals

- [Goal 1]
- [Goal 2]

## Critical Features (Must Document Accurately)

- **[Feature]**: [Why it's critical]

## User Types

- **[User Type]**: [What they do]

## Success Metrics

- [Metric]: [Target]

## Priorities

1. [Highest priority area]
2. [Second priority]
3. [Third priority]

## Stakeholder Concerns

- [Concern]: [Context]
```

---

## tribal-knowledge.md

```markdown
# Tribal Knowledge

> Things the team knows but aren't written down.
> /adopt will verify these against code and flag any mismatches.

## Gotchas

- **[Area]**: [What's surprising or counterintuitive]

## Historical Context

- [Why something is the way it is]

## Unwritten Rules

- [Rule]: [Reason]

## Known Issues

- [Issue]: [Workaround]

## "Everyone Knows" Facts

- [Fact]: [But is it still true? /adopt will check]

## Key Contacts

- **[Area]**: [Who to ask]
```

---

## roadmap-context.md

```markdown
# Roadmap Context

> Helps /adopt distinguish incomplete features from removed features.

## Planned Features

- **[Feature]**: [Status - planned/in-progress/blocked]

## Deprecations

- **[Feature/API]**: [Timeline, replacement]

## Migrations In Progress

- **[From -> To]**: [Status]

## Tech Debt Priorities

1. [Debt item]: [When planned to address]

## Recently Removed

- **[Feature]**: [When removed, why]

## Currently Broken/Disabled

- **[Feature]**: [Status, expected fix timeline]
```

---

## constraints.md

```markdown
# Constraints

> Known limitations that affect system design.
> /adopt will look for these patterns in code.

## Technical Constraints

- [Constraint]: [Reason]

## Business Constraints

- [Constraint]: [Reason]

## Compliance Requirements

- [Requirement]: [Details]

## Performance Requirements

- [Metric]: [Target]

## Integration Constraints

- [System]: [Limitations]

## Legacy System Dependencies

- [System]: [Why we can't change it]
```

---

## glossary.md

```markdown
# Domain Glossary

> Terminology specific to this codebase/domain.
> Helps /adopt use consistent naming in generated docs.

## Business Terms

| Term | Definition | Code Equivalent |
|------|------------|-----------------|
| [Term] | [What it means] | [Variable/class name in code] |

## Technical Terms

| Term | Definition | Where Used |
|------|------------|------------|
| [Term] | [What it means] | [Files/modules] |

## Acronyms

| Acronym | Full Form | Context |
|---------|-----------|---------|
| [ABC] | [Actual Business Concept] | [When used] |

## Ambiguous Terms

| Term | Meaning in THIS codebase |
|------|--------------------------|
| [Term] | [Specific meaning here, may differ from industry standard] |
```

---

## interview-notes.md

```markdown
# Interview Notes

> Knowledge captured from team conversations.
> /adopt will verify claims against code.

## Interview: [Person/Role] - [Date]

### Key Points

- [Point 1]
- [Point 2]

### Claims to Verify

- [ ] [Claim about system behavior]
- [ ] [Claim about architecture]

### Recommended Areas to Investigate

- [Area]: [Why]

---

## Interview: [Another Person] - [Date]

...
```

---

## How Context Affects /adopt

| Context Type | How It's Used |
|--------------|---------------|
| `architecture*.md` | Guides module boundary detection in Phase 1 |
| `stakeholder*.md` | Prioritizes features to document in PRD |
| `tribal*.md` | Flags areas to investigate carefully |
| `roadmap*.md` | Distinguishes ghost features vs planned features |
| `constraints*.md` | Adds to SDD constraints section |
| `glossary*.md` | Ensures consistent naming in artifacts |
| `interview*.md` | Provides claims checklist to verify |

## What Happens to Wrong Context

If your context file claims something that code contradicts:

1. **Loa artifact reflects CODE** (not your claim)
2. **Drift report notes the mismatch**
3. **You learn something new about your codebase**

This is a feature, not a bug. /adopt helps you discover where team beliefs have drifted from reality.

---

## Example: Full Context Directory

```
loa-grimoire/context/
├── architecture-notes.md      # System design beliefs
├── stakeholder-context.md     # Business priorities
├── tribal-knowledge.md        # Unwritten rules
├── roadmap-context.md         # Planned changes
├── constraints.md             # Known limitations
├── glossary.md                # Domain terminology
└── interview-alice-2024.md    # Team interview notes
```

Run `/adopt` and watch these beliefs get validated (or corrected) against actual code.
