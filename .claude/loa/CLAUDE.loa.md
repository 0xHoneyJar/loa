<!-- @loa-managed: true | version: 1.18.0 | hash: PLACEHOLDER -->
<!-- WARNING: This file is managed by the Loa Framework. Do not edit directly. -->
<!-- Changes will be overwritten on framework update. Use CLAUDE.md for project-specific instructions. -->

# Loa Framework Instructions

> Agent-driven development framework using 11 specialized AI agents (skills) to orchestrate the complete product lifecycle.

## Quick Reference

| Reference | Location |
|-----------|----------|
| Configuration examples | `.loa.config.yaml.example` |
| Context engineering | `.claude/loa/reference/context-engineering.md` |
| Protocols summary | `.claude/loa/reference/protocols-summary.md` |
| Scripts reference | `.claude/loa/reference/scripts-reference.md` |
| Version features | `.claude/loa/reference/version-features.md` |

Skills auto-load their documentation when invoked.

## Architecture

### Three-Zone Model

| Zone | Path | Owner | Permission |
|------|------|-------|------------|
| **System** | `.claude/` | Framework | NEVER edit directly |
| **State** | `grimoires/`, `.beads/` | Project | Read/Write |
| **App** | `src/`, `lib/`, `app/` | Developer | Read (write requires confirmation) |

**Critical**: Never suggest edits to `.claude/` - direct users to `.claude/overrides/` or `.loa.config.yaml`.

### Skills System

11 agent skills in `.claude/skills/` with 3-level architecture:
- **Level 1**: `index.yaml` - Metadata (~100 tokens)
- **Level 2**: `SKILL.md` - KERNEL instructions (~2000 tokens)
- **Level 3**: `resources/` - References, templates, scripts

| Skill | Role | Output |
|-------|------|--------|
| `autonomous-agent` | Meta-Orchestrator | Checkpoints + draft PR |
| `discovering-requirements` | Product Manager | `prd.md` |
| `designing-architecture` | Software Architect | `sdd.md` |
| `planning-sprints` | Technical PM | `sprint.md` |
| `implementing-tasks` | Senior Engineer | Code + report |
| `reviewing-code` | Tech Lead | Feedback |
| `auditing-security` | Security Auditor | Audit feedback |
| `deploying-infrastructure` | DevOps Architect | Infrastructure |
| `translating-for-executives` | Developer Relations | Summaries |
| `run-mode` | Autonomous Executor | Draft PR |
| `enhancing-prompts` | Prompt Engineer | Enhanced prompts |

## Workflow Commands

| Phase | Command | Output |
|-------|---------|--------|
| 1 | `/plan-and-analyze` | PRD |
| 2 | `/architect` | SDD |
| 3 | `/sprint-plan` | Sprint Plan |
| 4 | `/implement sprint-N` | Code |
| 5 | `/review-sprint sprint-N` | Feedback |
| 5.5 | `/audit-sprint sprint-N` | Approval |
| 6 | `/deploy-production` | Infrastructure |

**Ad-hoc**: `/audit`, `/translate`, `/validate`, `/feedback`, `/compound`, `/enhance`, `/update-loa`, `/loa`

**Run Mode**: `/run sprint-N`, `/run sprint-plan`, `/run-status`, `/run-halt`, `/run-resume`

## Intelligent Subagents

| Subagent | Purpose |
|----------|---------|
| `architecture-validator` | SDD compliance |
| `security-scanner` | OWASP Top 10 |
| `test-adequacy-reviewer` | Test quality |
| `goal-validator` | PRD goal verification |

**Usage**: `/validate`, `/validate architecture`, `/validate security`, `/validate goals`

## Key Protocols

### Structured Agentic Memory

Maintain `grimoires/loa/NOTES.md` with: Current Focus, Session Log, Decisions, Blockers, Goal Status, Learnings.

### Feedback Loops

1. **Implementation Loop**: Engineer <-> Senior Lead until "All good"
2. **Security Audit Loop**: After approval -> Auditor review -> "APPROVED"
3. **Priority**: Check audit feedback FIRST, then engineer feedback

### Karpathy Principles

- Think Before Coding (surface assumptions)
- Simplicity First (no speculative features)
- Surgical Changes (only necessary lines)
- Goal-Driven (define success criteria)

### Git Safety

- 4-layer upstream detection
- Soft block with confirmation
- `/contribute` bypasses with safeguards

## Document Flow

```
grimoires/loa/
├── NOTES.md      # Working memory
├── ledger.json   # Sprint numbering
├── prd.md        # Requirements
├── sdd.md        # Design
├── sprint.md     # Plan
└── a2a/          # Agent communication
```

## Implementation Notes

### When `/implement sprint-N` is invoked:
1. Check audit feedback FIRST (`auditor-sprint-feedback.md`)
2. Then check engineer feedback (`engineer-feedback.md`)
3. Address all feedback before new work

### When `/review-sprint sprint-N` is invoked:
1. Review actual code, not just report
2. Write "All good" or detailed feedback

### When `/audit-sprint sprint-N` is invoked:
1. Validate senior lead approval
2. Review for security vulnerabilities
3. Create `COMPLETED` marker on approval

## Key Conventions

- Never skip phases - each builds on previous
- Never edit `.claude/` directly - use overrides or config
- Review all outputs - you're the final decision-maker
- Security first - especially for crypto projects

## Related Files

- `README.md` - Quick start guide
- `PROCESS.md` - Workflow documentation
- `.claude/protocols/` - Protocol specifications
- `.claude/schemas/` - JSON Schema definitions
