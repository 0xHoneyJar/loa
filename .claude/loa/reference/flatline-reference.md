# Flatline Protocol Reference

> Extracted from CLAUDE.loa.md for token efficiency. See: `.claude/loa/CLAUDE.loa.md` for inline summary.

## How It Works (v1.22.0)

Multi-model adversarial review using Claude Opus 4.6 + GPT-5.3-codex + Gemini 2.5 Pro for planning document quality assurance.

| Phase | Description |
|-------|-------------|
| Phase 0 | Knowledge retrieval (Tier 1: local + Tier 2: NotebookLM) |
| Phase 1 | 6 parallel calls: 3 models × 2 modes (review + skeptic) |
| Phase 2 | 6 cross-scoring calls: each model scores the other two |
| Phase 3 | Consensus extraction: HIGH/DISPUTED/LOW/BLOCKER (2-of-3 majority) |

## Consensus Thresholds (0-1000 scale)

| Category | Criteria | Action |
|----------|----------|--------|
| HIGH_CONSENSUS | Both models >700 | Auto-integrate |
| DISPUTED | Delta >300 | Present to user (interactive) / Log (autonomous) |
| LOW_VALUE | Both <400 | Discard |
| BLOCKER | Skeptic concern >700 | Must address / HALT (autonomous) |

## Autonomous Mode

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

## Autonomous Actions

| Category | Default Action | Description |
|----------|----------------|-------------|
| HIGH_CONSENSUS | `integrate` | Auto-apply to document |
| DISPUTED | `log` | Record for post-review |
| BLOCKER | `halt` | Stop workflow, escalate |
| LOW_VALUE | `skip` | Discard silently |

## Rollback Support

```bash
# Preview rollback
.claude/scripts/flatline-rollback.sh run --run-id <id> --dry-run

# Execute rollback
.claude/scripts/flatline-rollback.sh run --run-id <id>

# Single integration rollback
.claude/scripts/flatline-rollback.sh single --integration-id <id> --run-id <run-id>
```

## Usage

```bash
# Manual invocation
/flatline-review grimoires/loa/prd.md

# CLI with mode
.claude/scripts/flatline-orchestrator.sh --doc grimoires/loa/prd.md --phase prd --autonomous --json

# Rollback
/flatline-review --rollback --run-id flatline-run-abc123
```

## Configuration

```yaml
flatline_protocol:
  enabled: true
  models:
    primary: opus
    secondary: gpt-5.3-codex
  max_iterations: 5
  knowledge:
    notebooklm:
      enabled: false
      notebook_id: ""

# Tertiary model (3-model Flatline)
hounfour:
  flatline_tertiary_model: gemini-2.5-pro

autonomous_mode:
  enabled: false
  auto_enable_for_ai: true
  actions:
    high_consensus: integrate
    disputed: log
    blocker: halt
    low_value: skip
  snapshots:
    enabled: true
    max_count: 100
    max_bytes: 104857600
```

## NotebookLM (Optional Tier 2 Knowledge)

NotebookLM provides curated domain expertise. Requires one-time browser auth setup:

```bash
pip install --user patchright
patchright install chromium
python3 .claude/skills/flatline-knowledge/resources/notebooklm-query.py --setup-auth
```

**Protocol**: `.claude/protocols/flatline-protocol.md`
