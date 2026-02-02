<!-- @loa-managed: true | version: 1.18.0 | hash: PLACEHOLDER -->
<!-- WARNING: This file is managed by the Loa Framework. Do not edit directly. -->

# Loa Framework Instructions

Agent-driven development framework. Skills auto-load their SKILL.md when invoked.

## Reference Files

| Topic | Location |
|-------|----------|
| Configuration | `.loa.config.yaml.example` |
| Context/Memory | `.claude/loa/reference/context-engineering.md` |
| Protocols | `.claude/loa/reference/protocols-summary.md` |
| Scripts | `.claude/loa/reference/scripts-reference.md` |

## Three-Zone Model

| Zone | Path | Permission |
|------|------|------------|
| System | `.claude/` | NEVER edit |
| State | `grimoires/`, `.beads/` | Read/Write |
| App | `src/`, `lib/`, `app/` | Confirm writes |

**Critical**: Never edit `.claude/` - use `.claude/overrides/` or `.loa.config.yaml`.

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

- **Memory**: Maintain `grimoires/loa/NOTES.md`
- **Feedback**: Check audit feedback FIRST, then engineer feedback
- **Karpathy**: Think Before Coding, Simplicity First, Surgical Changes, Goal-Driven
- **Git Safety**: 4-layer upstream detection with soft block

## Invisible Prompt Enhancement (v1.17.0)

Prompts are automatically enhanced before skill execution using PTCF framework.

| Behavior | Description |
|----------|-------------|
| Automatic | Prompts scoring < 4 are enhanced invisibly |
| Silent | No enhancement UI shown to user |
| Passthrough | Errors use original prompt unchanged |
| Logged | Activity logged to `grimoires/loa/a2a/trajectory/prompt-enhancement-*.jsonl` |

**Configuration** (`.loa.config.yaml`):
```yaml
prompt_enhancement:
  invisible_mode:
    enabled: true
```

**Disable per-command**: Add `enhance: false` to command frontmatter.

**View stats**: `/loa` shows enhancement metrics.

## Invisible Retrospective Learning (v1.19.0)

Learnings are automatically detected and captured during skill execution without user invocation.

| Behavior | Description |
|----------|-------------|
| Automatic | Session scanned for learning signals after skill completion |
| Silent | No output unless finding passes 3+ quality gates |
| Quality Gates | Depth, Reusability, Trigger Clarity, Verification |
| Logged | Activity logged to `grimoires/loa/a2a/trajectory/retrospective-*.jsonl` |

**Skills with postludes**:
- `implementing-tasks` - Bug fixes, debugging discoveries
- `auditing-security` - Security patterns and remediations
- `reviewing-code` - Code review insights

**Configuration** (`.loa.config.yaml`):
```yaml
invisible_retrospective:
  enabled: true
  surface_threshold: 3  # Min gates to surface (out of 4)
  skills:
    implementing-tasks: true
    auditing-security: true
    reviewing-code: true
```

**Integration**: Qualified learnings are added to `grimoires/loa/NOTES.md ## Learnings` and queued for upstream detection (PR #143).

**View stats**: `/loa` shows retrospective metrics.

## Conventions

- Never skip phases - each builds on previous
- Never edit `.claude/` directly
- Security first
