# Danger Level Protocol

Schema: `.claude/schemas/guardrail-result.schema.json`

---

## Overview

Danger levels provide graduated risk controls for skill execution. Each skill declares its risk level, and the system enforces appropriate safeguards based on execution mode.

```
Skill Invocation → Danger Level Check → Mode-Specific Enforcement → Execution or Block
```

---

## Danger Levels

| Level | Description | Examples |
|-------|-------------|----------|
| **safe** | Read-only operations, no side effects | `discovering-requirements`, `reviewing-code` |
| **moderate** | Writes to project files | `implementing-tasks`, `planning-sprints` |
| **high** | Creates infrastructure, external effects | `deploying-infrastructure` |
| **critical** | Full autonomous control, irreversible actions | `autonomous-agent` |

---

## Current Skill Assignments

| Skill | Danger Level | Rationale |
|-------|--------------|-----------|
| `discovering-requirements` | moderate | Writes analysis artifacts to grimoire |
| `designing-architecture` | moderate | Writes design documents to grimoire |
| `planning-sprints` | moderate | Writes sprint plans and ledger state |
| `implementing-tasks` | moderate | Writes code files |
| `reviewing-code` | moderate | Writes review feedback artifacts |
| `auditing-security` | high | Writes audit reports, may trigger emergency procedures |
| `deploying-infrastructure` | high | Creates infrastructure |
| `run-mode` | high | Autonomous execution |
| `autonomous-agent` | critical | Full autonomous control |
| `riding-codebase` | moderate | Writes reality artifacts to grimoire |
| `mounting-framework` | safe | Read-only framework setup (writes only to .claude/) |
| `continuous-learning` | safe | Read-only extraction |
| `translating-for-executives` | safe | Read-only translation |
| `enhancing-prompts` | safe | Read-only enhancement |
| `flatline-knowledge` | safe | Read-only knowledge retrieval |
| `simstim-workflow` | moderate | Orchestrates multi-step HITL workflow |
| `browsing-constructs` | safe | Read-only registry browsing |

---

## Decision Matrix

| Danger Level | Interactive | Autonomous | Autonomous + `--allow-high` |
|--------------|-------------|------------|------------------------------|
| safe | Execute | Execute | Execute |
| moderate | Execute (notice) | Execute (log) | Execute (log) |
| high | Confirm | BLOCK | Execute (warn + log) |
| critical | Confirm + reason required | BLOCK | BLOCK (no override) |

Interactive confirmation for `high`/`critical` names the skill, its danger level, and what it can do, then asks the user to continue. Autonomous blocking names the skill and level and tells the caller to re-run with `--allow-high`; `critical` has no override (see Safety Invariants).

---

## Override Mechanisms

### `--allow-high` Flag

Enables execution of `high` danger level skills in autonomous mode.

```bash
/run sprint-1 --allow-high
/run sprint-plan --allow-high
```

Allows `high` skills to execute and logs a warning to the trajectory. Does NOT allow `critical` skills (always blocked).

**Trajectory Entry**:
```json
{
  "type": "danger_level",
  "skill": "deploying-infrastructure",
  "level": "high",
  "mode": "autonomous",
  "action": "WARN",
  "override_used": true,
  "reason": "high-risk override via --allow-high flag"
}
```

### Configuration Override

Project-level configuration can adjust enforcement:

```yaml
# .loa.config.yaml
guardrails:
  danger_level:
    enforce: true
    interactive:
      safe: execute
      moderate: execute_with_notice
      high: confirm_required
      critical: confirm_with_reason
    autonomous:
      safe: execute
      moderate: execute_with_log
      high: block_without_flag
      critical: always_block
```

`critical: always_block` cannot be changed — this is a safety invariant.

---

## Skill Declaration

Skills declare their danger level in `index.yaml`:

```yaml
# .claude/skills/deploying-infrastructure/index.yaml
name: deploying-infrastructure
version: 1.0.0
danger_level: high
# ...
```

The `danger_level` field is validated against the enum in `skill-index.schema.json`.

---

## Logging

Every danger level decision is logged to the trajectory:

```json
{
  "type": "danger_level",
  "timestamp": "2026-02-03T10:30:00Z",
  "session_id": "abc123",
  "skill": "implementing-tasks",
  "action": "PROCEED",
  "level": "moderate",
  "mode": "autonomous",
  "override_used": false
}
```

| Action | Meaning |
|--------|---------|
| `PROCEED` | Execution allowed |
| `WARN` | Execution allowed with warning |
| `BLOCK` | Execution prevented |

---

## Integration Points

Danger level is checked at three points: immediately after skill resolution (Command Parse → Skill Resolve → Danger Level Check → Input Guardrails → Execute); by the Run Mode controller before every sprint task's skill invocation, halting the run on a failed check; and by the `/autonomous` orchestrator before Phase 4 (Implementation) and Phase 7 (Deploy).

---

## Safety Invariants

These invariants MUST NOT be violated:

1. **Critical Never Autonomous**: `critical` skills cannot run in autonomous mode, regardless of flags
2. **Logging Always**: All danger level decisions are logged to trajectory
3. **Schema Enforcement**: Danger levels must be valid enum values
4. **Fail-Closed**: Unknown danger levels default to `critical` behavior. The common cause is a skill's `index.yaml` omitting `danger_level` — add it explicitly for clarity

---

## Related Protocols

- [input-guardrails.md](input-guardrails.md) - Pre-execution validation
- [run-mode.md](run-mode.md) - Autonomous execution safety
- [feedback-loops.md](feedback-loops.md) - Quality gates
