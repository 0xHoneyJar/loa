# Context Understanding Presentation Specimens

Canonical presentation specimens for Step 0 (codebase understanding, brownfield)
and Step 3 (combined codebase + documentation understanding). Both SKILL.md call
sites point here: present the codebase section alone for Step 0; present both
sections for Step 3.

## Codebase Understanding

```markdown
## What I've Learned From Your Codebase

I've analyzed your existing codebase (N files, X lines).

### Existing Architecture
[CODE:src/index.ts:1-50] Your application uses [pattern] with:
- Component A [CODE:src/components/a.tsx:10]
- Service B [CODE:src/services/b.ts:1]

### Implemented Features
Based on code analysis:
- User authentication [CODE:src/auth/index.ts:1-100]
- Data persistence [CODE:src/db/client.ts:1-50]

### Current State
From consistency report:
- [summary of code consistency findings]

### Proposed Additions
Based on codebase analysis, the following would integrate well:
- [suggested additions grounded in existing patterns]

---
```

## Documentation Understanding

```markdown
## What I've Learned From Your Documentation

I've reviewed N files (X lines) from your context directory.

### Problem & Vision
> From vision.md:12-15: "exact quote from document..."

I understand the core problem is [summary]. The vision is [summary].

### Users & Stakeholders
> From users.md:23-45: "description of personas..."

You've defined N personas: [list with 1-line each].

### Conflicts Noted
- [if any conflicts between reality and context]

### What I Still Need to Understand
1. **Success Metrics**: What quantifiable outcomes define success?
2. **Persona Priority**: Which user persona should we optimize for first?
3. **Timeline**: What are the key milestones and deadlines?

Should I proceed with these clarifying questions, or would you like to
correct my understanding first?
```
