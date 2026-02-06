<!-- @loa-managed: true | version: 1.30.0 | hash: PLACEHOLDER -->
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

## Beads-First Architecture (v1.29.0)

**Beads task tracking is the EXPECTED DEFAULT, not an optional enhancement.**

*"We're building spaceships. Safety of operators and users is paramount."*

### Philosophy

Working without beads is treated as an **abnormal state** requiring explicit, time-limited acknowledgment. Health checks run at every workflow boundary.

### Health Check

```bash
# Check beads status
.claude/scripts/beads/beads-health.sh --json
```

| Status | Exit Code | Meaning | Action |
|--------|-----------|---------|--------|
| `HEALTHY` | 0 | All checks pass | Proceed |
| `NOT_INSTALLED` | 1 | br binary not found | Prompt install |
| `NOT_INITIALIZED` | 2 | No .beads directory | Prompt br init |
| `MIGRATION_NEEDED` | 3 | Schema incompatible | Must fix |
| `DEGRADED` | 4 | Partial functionality | Warn, proceed |
| `UNHEALTHY` | 5 | Critical issues | Must fix |

### Autonomous Mode

**Autonomous mode REQUIRES beads** (unless overridden):

```bash
# /run preflight will HALT if beads unavailable
/run sprint-1  # Blocked if beads.autonomous.requires_beads: true

# Override (not recommended)
export LOA_BEADS_AUTONOMOUS_OVERRIDE=true
# Or set beads.autonomous.requires_beads: false in config
```

### Opt-Out Workflow

When beads unavailable, users can acknowledge and continue (24h expiry):

```bash
# Record opt-out with reason
.claude/scripts/beads/update-beads-state.sh --opt-out "Reason"

# Check if opt-out is valid
.claude/scripts/beads/update-beads-state.sh --opt-out-check
```

### Configuration

```yaml
beads:
  mode: recommended  # required | recommended | disabled
  opt_out:
    confirmation_interval_hours: 24
    require_reason: true
  autonomous:
    requires_beads: true
```

**Protocol**: `.claude/protocols/beads-preflight.md`

## Three-Zone Model

| Zone | Path | Permission |
|------|------|------------|
| System | `.claude/` | NEVER edit |
| State | `grimoires/`, `.beads/` | Read/Write |
| App | `src/`, `lib/`, `app/` | Confirm writes |

**Critical**: Never edit `.claude/` - use `.claude/overrides/` or `.loa.config.yaml`.

## File Creation Safety

**CRITICAL**: Bash heredocs silently corrupt source files containing `${...}` template literals.

| Method | Shell Expansion | When to Use |
|--------|-----------------|-------------|
| **Write tool** | None | Source files (.tsx, .jsx, .ts, .js, etc.) - PREFERRED |
| `<<'EOF'` (quoted) | None | Shell content with literal `${...}` |
| `<< EOF` (unquoted) | Yes | Shell scripts needing variable expansion only |

**Rule**: For source files, ALWAYS use Write tool. If heredoc required, ALWAYS quote the delimiter.

**Protocol**: `.claude/protocols/safe-file-creation.md`

## Configurable Paths (v1.27.0)

Grimoire and state file locations are configurable via `.loa.config.yaml`:

```yaml
paths:
  grimoire: grimoires/loa          # Default
  beads: .beads                    # Default
  soul:
    source: grimoires/loa/BEAUVOIR.md
    output: grimoires/loa/SOUL.md
```

**Environment overrides**: `LOA_GRIMOIRE_DIR`, `LOA_BEADS_DIR`, `LOA_SOUL_SOURCE`, `LOA_SOUL_OUTPUT`

**Rollback**: Set `LOA_USE_LEGACY_PATHS=1` to bypass config and use hardcoded defaults.

**Requirements**: yq v4+ (mikefarah/yq) for YAML parsing. Missing yq uses defaults with warning.

## Golden Path (v1.30.0)

**5 commands for 90% of users.** All existing truename commands remain available for power users.

| Command | What It Does | Routes To |
|---------|-------------|-----------|
| `/loa` | Where am I? What's next? | Status + health + next step |
| `/plan` | Plan your project | `/plan-and-analyze` → `/architect` → `/sprint-plan` |
| `/build` | Build the current sprint | `/implement sprint-N` (auto-detected) |
| `/review` | Review and audit your work | `/review-sprint` + `/audit-sprint` |
| `/ship` | Deploy and archive | `/deploy-production` + `/archive-cycle` |

**Design**: Porcelain & Plumbing (git model). Golden commands are zero-arg by default with auto-detection. Truenames accept specific arguments for power users.

**Script**: `.claude/scripts/golden-path.sh` — shared state resolution helpers.

## Workflow (Truenames)

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

## Run Mode State Recovery (v1.27.0)

**CRITICAL**: After context compaction or session recovery, ALWAYS check for active run mode.

### Detection

Check `.run/sprint-plan-state.json`:
```bash
if [[ -f .run/sprint-plan-state.json ]]; then
  state=$(jq -r '.state' .run/sprint-plan-state.json)
  if [[ "$state" == "RUNNING" ]]; then
    # ACTIVE RUN MODE - Resume autonomous execution
  fi
fi
```

### When state=RUNNING

1. **Do NOT ask for confirmation** - continue autonomously
2. Read current sprint from `.sprints.current` field
3. Resume the sprint execution loop
4. Update `.timestamps.last_activity` on each action

### State Values

| State | Meaning | Action |
|-------|---------|--------|
| `RUNNING` | Active autonomous execution | Resume immediately |
| `HALTED` | Stopped due to error/blocker | Await `/run-resume` |
| `JACKED_OUT` | Completed successfully | No action needed |

### Recovery Sequence

```
1. Check .run/sprint-plan-state.json exists
2. If state=RUNNING:
   a. Log: "Resuming run mode after context recovery"
   b. Read sprints.current for active sprint
   c. Continue sprint execution loop
   d. Do NOT prompt user for confirmation
3. If state=HALTED:
   a. Inform user of halt reason
   b. Await /run-resume command
```

**Rationale**: Run mode is designed for overnight/unattended execution. Context compaction should not interrupt autonomous operation.

## Post-Compact Recovery Hooks (v1.28.0)

Loa provides automatic context recovery after compaction via Claude Code hooks.

### How It Works

1. **PreCompact Hook**: Saves current state to `.run/compact-pending`
2. **UserPromptSubmit Hook**: Detects marker, injects recovery reminder
3. **One-shot delivery**: Reminder appears once, marker is deleted

### Automatic Recovery

When compaction is detected, you will see a recovery reminder instructing you to:
1. Re-read this file (CLAUDE.md) for conventions
2. Check `.run/sprint-plan-state.json` - resume if `state=RUNNING`
3. Check `.run/simstim-state.json` - resume from last phase
4. Review `grimoires/loa/NOTES.md` for learnings

### Installation

Hooks are in `.claude/hooks/`. To enable, add to `~/.claude/settings.json`:
```json
{
  "hooks": {
    "PreCompact": [{"matcher": "", "hooks": [{"type": "command", "command": ".claude/hooks/pre-compact-marker.sh"}]}],
    "UserPromptSubmit": [{"matcher": "", "hooks": [{"type": "command", "command": ".claude/hooks/post-compact-reminder.sh"}]}]
  }
}
```

See `.claude/hooks/README.md` for full documentation.

## Flatline Beads Loop (v1.28.0)

Iterative multi-model refinement of task graphs. "Check your beads N times, implement once."

### How It Works

1. Export beads to JSON (`br list --json`)
2. Run Flatline Protocol review on task graph
3. Apply HIGH_CONSENSUS suggestions automatically
4. Repeat until changes "flatline" (< 5% change for 2 iterations)
5. Sync final state to git

### Usage

```bash
# Manual invocation
.claude/scripts/beads-flatline-loop.sh --max-iterations 6 --threshold 5

# In simstim workflow (Phase 6.5)
# Automatically runs after FLATLINE SPRINT phase when beads_rust is installed
```

### Configuration

```yaml
simstim:
  flatline:
    beads_loop: true    # Enable Flatline Beads Loop
```

Requires beads_rust (`br`). See: https://github.com/Dicklesworthstone/beads_rust

## Persistent Memory (v1.28.0)

Session-spanning observation storage with progressive disclosure for cross-session recall.

### How It Works

1. **Memory Writer Hook**: Captures observations from tool outputs when learning signals detected
2. **Observations File**: Stored in `grimoires/loa/memory/observations.jsonl`
3. **Progressive Disclosure**: Query at different detail levels to manage token budget

### Learning Signals

Automatically captured: discovered, learned, fixed, resolved, pattern, insight

### Query Interface

```bash
# Token-efficient index (~50 tokens per entry)
.claude/scripts/memory-query.sh --index

# Summary view (~200 tokens per entry)
.claude/scripts/memory-query.sh --summary --limit 5

# Full details (~500 tokens)
.claude/scripts/memory-query.sh --full obs-1234567890-abc123

# Filter by type
.claude/scripts/memory-query.sh --type learning

# Free-text search
.claude/scripts/memory-query.sh "authentication pattern"
```

### Configuration

```yaml
memory:
  enabled: true
  max_observations: 10000
  capture:
    discoveries: true
    errors: true
```

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

**Skills by danger level** (synced with index.yaml 2026-02-06):
- `safe`: continuous-learning, enhancing-prompts, flatline-knowledge, mounting-framework, translating-for-executives, browsing-constructs
- `moderate`: discovering-requirements, designing-architecture, planning-sprints, implementing-tasks, reviewing-code, riding-codebase, simstim-workflow
- `high`: auditing-security, deploying-infrastructure, run-mode
- `critical`: autonomous-agent

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

## Flatline Protocol (v1.22.0)

Multi-model adversarial review using Claude Opus 4.6 + GPT-5.2 for planning document quality assurance.

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
| DISPUTED | Delta >300 | Present to user (interactive) / Log (autonomous) |
| LOW_VALUE | Both <400 | Discard |
| BLOCKER | Skeptic concern >700 | Must address / HALT (autonomous) |

### Autonomous Mode (v1.22.0)

Flatline Protocol integrates with `/autonomous` and `/run sprint-plan` workflows.

| Mode | Behavior |
|------|----------|
| Interactive | Present findings to user, await decisions |
| Autonomous | HIGH_CONSENSUS auto-integrates, BLOCKER halts workflow |

**Mode Detection Priority**:
1. CLI flags (`--interactive`, `--autonomous`)
2. Environment (`LOA_FLATLINE_MODE`)
3. Config (`autonomous_mode.enabled`)
4. Auto-detect (strong AI signals only)
5. Default (interactive)

**Strong Signals** (trigger auto-enable): `CLAWDBOT_GATEWAY_TOKEN`, `LOA_OPERATOR=ai`
**Weak Signals** (require opt-in): Non-TTY, `CLAUDECODE`, `CLAWDBOT_AGENT`

### Autonomous Actions

| Category | Default Action | Description |
|----------|----------------|-------------|
| HIGH_CONSENSUS | `integrate` | Auto-apply to document |
| DISPUTED | `log` | Record for post-review |
| BLOCKER | `halt` | Stop workflow, escalate |
| LOW_VALUE | `skip` | Discard silently |

### Rollback Support

```bash
# Preview rollback
.claude/scripts/flatline-rollback.sh run --run-id <id> --dry-run

# Execute rollback
.claude/scripts/flatline-rollback.sh run --run-id <id>

# Single integration rollback
.claude/scripts/flatline-rollback.sh single --integration-id <id> --run-id <run-id>
```

### Usage

```bash
# Manual invocation
/flatline-review grimoires/loa/prd.md

# CLI with mode
.claude/scripts/flatline-orchestrator.sh --doc grimoires/loa/prd.md --phase prd --autonomous --json

# Rollback
/flatline-review --rollback --run-id flatline-run-abc123
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
      enabled: false
      notebook_id: ""

autonomous_mode:
  enabled: false                    # Require explicit opt-in
  auto_enable_for_ai: true          # Auto-enable for strong AI signals
  actions:
    high_consensus: integrate       # Auto-apply high consensus findings
    disputed: log                   # Log disputed for post-review
    blocker: halt                   # Halt workflow on blockers
    low_value: skip                 # Discard low value findings
  thresholds:
    disputed_halt_percent: 80       # Halt if >80% findings disputed
  snapshots:
    enabled: true
    max_count: 100
    max_bytes: 104857600           # 100MB
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
