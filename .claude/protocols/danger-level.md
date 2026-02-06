# Danger Level Protocol

**Version**: 1.0.0
**Status**: Active
**Schema**: `.claude/schemas/guardrail-result.schema.json`

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

<!-- PROTO-002: Synchronized with index.yaml sources of truth (2026-02-06) -->

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

## Mode-Specific Behavior

### Interactive Mode

User is present and can respond to prompts.

| Level | Behavior |
|-------|----------|
| **safe** | Execute immediately, no confirmation |
| **moderate** | Execute with brief notice in output |
| **high** | Require explicit confirmation before execute |
| **critical** | Require confirmation WITH reason explanation |

**Confirmation Flow (high/critical)**:
```
┌────────────────────────────────────────────────────────────┐
│ ⚠️  High-Risk Skill Confirmation                           │
├────────────────────────────────────────────────────────────┤
│ Skill: deploying-infrastructure                            │
│ Danger Level: high                                         │
│                                                            │
│ This skill can:                                            │
│ • Create cloud resources with cost implications           │
│ • Modify production infrastructure                         │
│ • Execute external API calls                               │
│                                                            │
│ Continue? [y/N]                                            │
└────────────────────────────────────────────────────────────┘
```

### Autonomous Mode

Running via `/run` command without human-in-the-loop.

| Level | Behavior |
|-------|----------|
| **safe** | Execute immediately |
| **moderate** | Execute with enhanced trajectory logging |
| **high** | BLOCK unless `--allow-high` flag provided |
| **critical** | ALWAYS BLOCK (no override available) |

**Blocking Message (autonomous)**:
```
┌────────────────────────────────────────────────────────────┐
│ 🛑 Skill Blocked in Autonomous Mode                        │
├────────────────────────────────────────────────────────────┤
│ Skill: deploying-infrastructure                            │
│ Danger Level: high                                         │
│ Mode: autonomous                                           │
│                                                            │
│ High-risk skills are blocked in autonomous mode by         │
│ default. To allow, re-run with:                           │
│                                                            │
│   /run sprint-N --allow-high                               │
│                                                            │
│ Note: critical skills cannot be overridden.                │
└────────────────────────────────────────────────────────────┘
```

---

## Decision Matrix

| Danger Level | Interactive | Autonomous | Autonomous + `--allow-high` |
|--------------|-------------|------------|----------------------------|
| safe | ✅ Execute | ✅ Execute | ✅ Execute |
| moderate | ✅ Execute (notice) | ✅ Execute (log) | ✅ Execute (log) |
| high | ⚠️ Confirm | 🛑 BLOCK | ⚠️ Execute (warn + log) |
| critical | ⚠️ Confirm + Reason | 🛑 BLOCK | 🛑 BLOCK (no override) |

---

## Override Mechanisms

### `--allow-high` Flag

Enables execution of `high` danger level skills in autonomous mode.

```bash
/run sprint-1 --allow-high
/run sprint-plan --allow-high
```

**Behavior**:
- Allows `high` skills to execute
- Logs warning to trajectory
- Does NOT allow `critical` skills (always blocked)

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

**Note**: `critical: always_block` cannot be changed. This is a safety invariant.

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

**Schema Validation**: The `danger_level` field is validated against the enum in `skill-index.schema.json`.

---

## Logging

### Trajectory Events

All danger level decisions are logged:

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

### Log Actions

| Action | Meaning |
|--------|---------|
| `PROCEED` | Execution allowed |
| `WARN` | Execution allowed with warning |
| `BLOCK` | Execution prevented |

---

## Integration Points

### 1. Skill Loading

Danger level checked immediately after skill resolution:

```
Command Parse → Skill Resolve → ─► Danger Level Check → Input Guardrails → Execute
```

### 2. Run Mode

Run Mode controller checks danger level before each skill invocation:

```python
for task in sprint.tasks:
    skill = resolve_skill(task)
    if not check_danger_level(skill, mode='autonomous', allow_high=flags.allow_high):
        halt_run_mode("Blocked by danger level")
    execute_skill(skill, task)
```

### 3. Autonomous Agent

The `/autonomous` orchestrator respects danger levels for all phase skills:

```
Phase 4 (Implementation) → check danger_level → Execute or Block
Phase 7 (Deploy)         → check danger_level → Execute or Block
```

---

## Safety Invariants

These invariants MUST NOT be violated:

1. **Critical Never Autonomous**: `critical` skills cannot run in autonomous mode, regardless of flags
2. **Logging Always**: All danger level decisions are logged to trajectory
3. **Schema Enforcement**: Danger levels must be valid enum values
4. **Fail-Closed**: Unknown danger levels default to `critical` behavior

---

## Troubleshooting

### "Skill Blocked" in Run Mode

**Cause**: Skill has `high` or `critical` danger level.

**Solution**:
- For `high`: Use `--allow-high` flag
- For `critical`: Cannot override. Run interactively instead.

### Confirmation Prompts in Scripts

**Cause**: Running `high`/`critical` skill in interactive mode.

**Solution**:
- Use `/run` command for autonomous execution
- Or pipe `yes` to confirmation (not recommended)

### Missing Danger Level

**Cause**: Skill `index.yaml` doesn't declare `danger_level`.

**Resolution**: Unknown skills default to `critical` (fail-safe). Add explicit declaration for clarity.

---

## Related Protocols

- [input-guardrails.md](input-guardrails.md) - Pre-execution validation
- [run-mode.md](run-mode.md) - Autonomous execution safety
- [feedback-loops.md](feedback-loops.md) - Quality gates

---

*Protocol Version 1.0.0 | Input Guardrails & Tool Risk Enforcement v1.20.0*
