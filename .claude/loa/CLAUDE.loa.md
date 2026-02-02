<!-- @loa-managed: true | version: 1.21.0 | hash: PLACEHOLDER -->
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

**Ad-hoc**: `/audit`, `/translate`, `/validate`, `/feedback`, `/compound`, `/enhance`, `/flatline-review`, `/update-loa`, `/loa`

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

## Input Guardrails & Danger Level (v1.20.0)

Pre-execution validation for skill invocations based on OpenAI's "A Practical Guide to Building Agents".

### Guardrail Types

| Type | Mode | Purpose |
|------|------|---------|
| `pii_filter` | blocking | Redact API keys, emails, SSN, etc. |
| `injection_detection` | blocking | Detect prompt injection patterns |
| `relevance_check` | advisory | Verify request matches skill |

### Danger Level Enforcement

| Level | Interactive | Autonomous |
|-------|-------------|------------|
| `safe` | Execute | Execute |
| `moderate` | Notice | Log |
| `high` | Confirm | BLOCK (use `--allow-high`) |
| `critical` | Confirm+Reason | ALWAYS BLOCK |

**Skills by danger level**:
- `safe`: discovering-requirements, designing-architecture, reviewing-code, auditing-security
- `moderate`: implementing-tasks, planning-sprints, mounting-framework
- `high`: deploying-infrastructure, run-mode, autonomous-agent

### Run Mode Integration

```bash
# Allow high-risk skills in autonomous mode
/run sprint-1 --allow-high
/run sprint-plan --allow-high
```

### Configuration

```yaml
guardrails:
  input:
    enabled: true
    pii_filter:
      enabled: true
      mode: blocking
    injection_detection:
      enabled: true
      threshold: 0.7
  danger_level:
    enforce: true
```

**Protocols**: `.claude/protocols/input-guardrails.md`, `.claude/protocols/danger-level.md`

**View stats**: `/loa` shows retrospective metrics.

## Flatline Protocol (v1.17.0)

Multi-model adversarial review using Claude Opus 4.5 + GPT-5.2 for planning document quality assurance.

### How It Works

| Phase | Description |
|-------|-------------|
| Phase 0 | Knowledge retrieval (Tier 1: local + Tier 2: NotebookLM) |
| Phase 1 | 4 parallel calls: GPT review, Opus review, GPT skeptic, Opus skeptic |
| Phase 2 | Cross-scoring: GPT scores Opus suggestions, Opus scores GPT suggestions |
| Phase 3 | Consensus extraction: HIGH/DISPUTED/LOW/BLOCKER classification |

### Consensus Thresholds (0-1000 scale)

| Category | Criteria | Action |
|----------|----------|--------|
| HIGH_CONSENSUS | Both models >700 | Auto-integrate |
| DISPUTED | Delta >300 | Present to user |
| LOW_VALUE | Both <400 | Discard |
| BLOCKER | Skeptic concern >700 | Must address |

### Usage

```bash
# Manual invocation
/flatline-review grimoires/loa/prd.md

# CLI
.claude/scripts/flatline-orchestrator.sh --doc grimoires/loa/prd.md --phase prd --json
```

### Configuration

```yaml
flatline_protocol:
  enabled: true
  models:
    primary: opus
    secondary: gpt-5.2
  knowledge:
    notebooklm:
      enabled: false        # Optional Tier 2
      notebook_id: ""
```

### NotebookLM (Optional Tier 2 Knowledge)

NotebookLM provides curated domain expertise. Requires one-time browser auth setup:

```bash
pip install --user patchright
patchright install chromium
python3 .claude/skills/flatline-knowledge/resources/notebooklm-query.py --setup-auth
```

**Protocol**: `.claude/protocols/flatline-protocol.md`

## Conventions

- Never skip phases - each builds on previous
- Never edit `.claude/` directly
- Security first
