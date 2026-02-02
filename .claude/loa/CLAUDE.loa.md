<!-- @loa-managed: true | version: 1.18.0 | hash: PLACEHOLDER -->
<!-- WARNING: This file is managed by the Loa Framework. Do not edit directly. -->
<!-- Changes will be overwritten on framework update. Use CLAUDE.md for project-specific instructions. -->

# Loa Framework Instructions

> Agent-driven development framework using 11 specialized AI agents (skills).

## Quick Reference

| Reference | Location |
|-----------|----------|
| Configuration | `.loa.config.yaml.example` |
| Context engineering | `.claude/loa/reference/context-engineering.md` |
| Protocols | `.claude/loa/reference/protocols-summary.md` |
| Scripts | `.claude/loa/reference/scripts-reference.md` |
| Version features | `.claude/loa/reference/version-features.md` |

Skills auto-load their SKILL.md when invoked.

## Architecture

### Three-Zone Model

| Zone | Path | Permission |
|------|------|------------|
| **System** | `.claude/` | NEVER edit |
| **State** | `grimoires/`, `.beads/` | Read/Write |
| **App** | `src/`, `lib/`, `app/` | Confirm writes |

**Critical**: Never edit `.claude/` - use `.claude/overrides/` or `.loa.config.yaml`.

### Skills

11 skills in `.claude/skills/` with 3-level architecture (index.yaml → SKILL.md → resources/).

| Skill | Role |
|-------|------|
| `autonomous-agent` | Meta-Orchestrator |
| `discovering-requirements` | Product Manager |
| `designing-architecture` | Software Architect |
| `planning-sprints` | Technical PM |
| `implementing-tasks` | Senior Engineer |
| `reviewing-code` | Tech Lead |
| `auditing-security` | Security Auditor |
| `deploying-infrastructure` | DevOps Architect |
| `translating-for-executives` | Developer Relations |
| `run-mode` | Autonomous Executor |
| `enhancing-prompts` | Prompt Engineer |

## Workflow

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

## Key Protocols

- **Memory**: Maintain `grimoires/loa/NOTES.md` (Current Focus, Session Log, Decisions, Blockers)
- **Feedback Priority**: Check audit feedback FIRST, then engineer feedback
- **Karpathy**: Think Before Coding, Simplicity First, Surgical Changes, Goal-Driven
- **Git Safety**: 4-layer upstream detection, soft block with confirmation

## Document Flow

```
grimoires/loa/
├── NOTES.md      # Working memory
├── ledger.json   # Sprint numbering
├── prd.md, sdd.md, sprint.md
└── a2a/          # Agent communication
```

## Key Conventions

- Never skip phases
- Never edit `.claude/` directly
- Review all outputs
- Security first
