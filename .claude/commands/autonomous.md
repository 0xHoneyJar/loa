# /autonomous Command

## Purpose

Meta-orchestrator for exhaustive Loa process compliance. Executes end-to-end autonomous workflow with 8-phase execution model, quality gates, operator detection, and continuous learning.

## Invocation

The `/autonomous` command has its own multi-phase workflow structure. You can provide context:

```bash
/autonomous implement the feature from the PRD
```

The command executes through its 8 phases without using Claude Code's native Plan Mode.

## Usage

```
/autonomous [target] [options]
/autonomous
/autonomous --dry-run
/autonomous --detect-only
/autonomous --resume-from=design
```

## Arguments

| Argument | Description | Required |
|----------|-------------|----------|
| `target` | Work item or sprint to execute | No |

## Options

| Option | Description | Default |
|--------|-------------|---------|
| `--dry-run` | Validate without executing | false |
| `--detect-only` | Only detect operator type | false |
| `--resume-from PHASE` | Resume from specific phase | none |

## 8-Phase Execution Model

```
PREFLIGHT → DISCOVER → DESIGN → IMPLEMENT → AUDIT → SUBMIT → DEPLOY → LEARN
                                              ↓
                                         REMEDIATE (max 3 loops)
                                              ↓
                                          ESCALATE
```

## Operator Detection

Automatically detects AI vs Human operators:
- **AI operators**: Strict quality gates, mandatory audit, auto-skill wrapping
- **Human operators**: Advisory gates, flexible workflow

Detection methods:
1. Environment: `LOA_OPERATOR=ai` or `CLAWDBOT_AGENT=true`
2. AGENTS.md markers
3. HEARTBEAT.md presence
4. Non-interactive TTY

## Exit Codes

| Code | Meaning | Action |
|------|---------|--------|
| 0 | Success | Proceed |
| 1 | Failure (retriable) | Retry up to max |
| 2 | Blocked | Escalate to human |

## Examples

```bash
# Full autonomous execution
/autonomous

# Dry run - validate without executing
/autonomous --dry-run

# Check operator detection
/autonomous --detect-only

# Resume from design phase
/autonomous --resume-from=design
```

## Skill Reference

See `.claude/skills/autonomous-agent/SKILL.md` for full implementation details.

---

agent: autonomous-agent
agent_path: .claude/skills/autonomous-agent/SKILL.md
