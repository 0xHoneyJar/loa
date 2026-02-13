# Input Guardrails & Danger Level Reference

> Extracted from CLAUDE.loa.md for token efficiency. See: `.claude/loa/CLAUDE.loa.md` for inline summary.

## Guardrail Types (v1.20.0)

| Type | Mode | Purpose |
|------|------|---------|
| `pii_filter` | blocking | Redact API keys, emails, SSN, etc. |
| `injection_detection` | blocking | Detect prompt injection patterns |
| `relevance_check` | advisory | Verify request matches skill |

## Danger Level Enforcement

| Level | Interactive | Autonomous |
|-------|-------------|------------|
| `safe` | Execute | Execute |
| `moderate` | Notice | Log |
| `high` | Confirm | BLOCK (use `--allow-high`) |
| `critical` | Confirm+Reason | ALWAYS BLOCK |

**Skills by danger level** (synced with index.yaml 2026-02-06):
- `safe`: continuous-learning, enhancing-prompts, flatline-knowledge, mounting-framework, translating-for-executives, browsing-constructs
- `moderate`: bug-triaging, discovering-requirements, designing-architecture, planning-sprints, implementing-tasks, reviewing-code, riding-codebase, simstim-workflow
- `high`: auditing-security, deploying-infrastructure, run-mode, run-bridge
- `critical`: autonomous-agent

## Run Mode Integration

```bash
# Allow high-risk skills in autonomous mode
/run sprint-1 --allow-high
/run sprint-plan --allow-high
```

## Configuration

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
