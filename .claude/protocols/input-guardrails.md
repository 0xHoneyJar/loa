# Input Guardrails Protocol

**Version**: 1.0.0
**Status**: Active
**Schema**: `.claude/schemas/guardrail-result.schema.json`

---

## Overview

Input guardrails provide pre-execution validation for skill invocations. They run BEFORE the Invisible Prompt Enhancement system to catch issues at the earliest point.

```
User Input → Input Guardrails → Prompt Enhancement → Skill Execution → Output Guardrails
              ↑ THIS LAYER
```

---

## Guardrail Types

### 1. PII Filter (`pii_filter`)

**Purpose**: Detect and redact sensitive data before processing.

**Patterns Detected**:
| Pattern | Regex | Action |
|---------|-------|--------|
| API Keys | `sk-[a-zA-Z0-9]{20,}`, `ghp_[a-zA-Z0-9]{36}`, `AKIA[A-Z0-9]{16}` | Redact |
| Email Addresses | `[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}` | Redact |
| Phone Numbers | `\b\d{3}[-.]?\d{3}[-.]?\d{4}\b` | Redact |
| SSN | `\b\d{3}-\d{2}-\d{4}\b` | Redact |
| Credit Cards | `\b\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}\b` | Redact |
| File Paths | `/home/[^/]+/`, `/Users/[^/]+/` | Anonymize |
| JWT Tokens | `eyJ[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9_-]{10,}` | Redact |
| Private Keys | `-----BEGIN [A-Z ]+ PRIVATE KEY-----` | Redact |

**Actions**:
- `redact`: Replace with `[REDACTED_TYPE]` placeholder
- `anonymize`: Replace identifying portion with generic value

**Output**:
```json
{
  "status": "PASS",
  "redactions": 2,
  "redacted_input": "Contact: [REDACTED_EMAIL] at [REDACTED_PHONE]"
}
```

### 2. Injection Detection (`injection_detection`)

**Purpose**: Detect prompt injection attempts in user input.

**Pattern Categories**:

| Category | Patterns | Weight |
|----------|----------|--------|
| Instruction Override | "ignore previous", "disregard instructions", "forget everything" | 0.4 |
| Role Confusion | "you are now", "act as", "pretend to be", "your new role" | 0.3 |
| Context Manipulation | "system prompt", "hidden instructions", "debug mode" | 0.2 |
| Encoding Evasion | Base64 commands, Unicode tricks, homoglyph attacks | 0.1 |

**Scoring**:
- Calculate weighted sum of matched patterns
- Threshold: 0.7 (configurable)
- Score >= threshold → FAIL

**Output**:
```json
{
  "status": "DETECTED",
  "score": 0.85,
  "patterns_matched": ["instruction_override", "role_confusion"],
  "threshold": 0.7
}
```

### 3. Relevance Check (`relevance_check`)

**Purpose**: Verify request matches the invoked skill's purpose.

**Implementation**:
- Compare input against skill's `triggers` and `description`
- Check for domain-specific keywords
- Confidence score 0-1

**Note**: High false positive rate. Recommended mode: `advisory` or `parallel`.

**Output**:
```json
{
  "status": "PASS",
  "confidence": 0.92,
  "skill_match": "implementing-tasks"
}
```

---

## Execution Modes

### Blocking Mode (`mode: blocking`)

```
Input → [Guardrail Check] → Pass? → Continue
                             ↓
                           Fail? → BLOCK (halt execution)
```

- Check MUST complete before skill execution
- Failure halts the workflow
- Use for: `pii_filter`, `injection_detection`

### Parallel Mode (`mode: parallel`)

```
Input → [Guardrail Check] ─┐
    ↓                      │
    [Skill Execution] ←────┤ (Tripwire if check fails)
```

- Check runs concurrently with skill
- If check fails before skill completes → tripwire (halt)
- If skill completes before check → wait for check result
- Use for: `relevance_check`

### Advisory Mode (`mode: advisory`)

```
Input → [Guardrail Check] → Log result
    ↓
    [Skill Execution] → Continue regardless
```

- Check logs warning but never blocks
- Use for: experimental checks, low-confidence detectors

---

## Failure Handling

### On BLOCK

1. Log guardrail result to trajectory
2. Display user-friendly message
3. Suggest remediation if applicable
4. Allow explicit override (for authorized users)

```
⚠️  Input Guardrail Blocked Execution
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Check: injection_detection
Score: 0.85 (threshold: 0.70)
Patterns: instruction_override, role_confusion

Your input contains patterns that may indicate prompt injection.
Please rephrase your request or use --bypass-guardrails if authorized.
```

### On WARN

1. Log guardrail result to trajectory
2. Display warning notification
3. Continue execution
4. Include warning in output metadata

### On Tripwire (Parallel Mode)

1. Halt skill execution immediately
2. Log tripwire event to trajectory
3. Optionally rollback uncommitted changes
4. Display tripwire notification

---

## Integration with Skill Loading Pipeline

### Load Order

```
1. Command Parsing
2. Skill Resolution (find matching skill)
3. ─► Danger Level Check (see danger-level.md)
4. ─► Input Guardrails (this protocol)
5. Invisible Prompt Enhancement
6. Skill KERNEL Execution
7. Output Guardrails (quality gates)
8. Retrospective Postlude
```

### Skill-Specific Configuration

Skills can override global guardrail settings in their `index.yaml`:

```yaml
# .claude/skills/implementing-tasks/index.yaml
input_guardrails:
  pii_filter:
    enabled: true
    mode: blocking
  injection_detection:
    enabled: true
    mode: blocking
    threshold: 0.65  # More sensitive for code execution
  relevance_check:
    enabled: false   # Disabled for this skill
```

---

## Configuration Reference

### Global Configuration

```yaml
# .loa.config.yaml
guardrails:
  input:
    enabled: true

    pii_filter:
      enabled: true
      mode: blocking
      patterns:
        api_keys: true
        emails: true
        phone_numbers: true
        ssn: true
        credit_cards: true
        file_paths: anonymize  # anonymize | redact | ignore
      log_redactions: true

    injection_detection:
      enabled: true
      mode: blocking
      threshold: 0.7
      patterns:
        - instruction_override
        - role_confusion
        - context_manipulation
        - encoding_evasion

    relevance_check:
      enabled: false  # High false positive rate
      mode: advisory
      confidence_threshold: 0.8

  logging:
    enabled: true
    directory: grimoires/loa/a2a/trajectory
    filename_pattern: "guardrails-{date}.jsonl"
```

### Environment Overrides

```bash
# Disable guardrails for debugging
LOA_GUARDRAILS_ENABLED=false

# Force advisory mode for all checks
LOA_GUARDRAILS_MODE=advisory
```

---

## Trajectory Logging

All guardrail events are logged to `grimoires/loa/a2a/trajectory/guardrails-{YYYY-MM-DD}.jsonl`.

**Log Entry Format**:
```json
{
  "type": "input_guardrail",
  "timestamp": "2026-02-03T10:30:00Z",
  "session_id": "abc123",
  "skill": "implementing-tasks",
  "action": "PROCEED",
  "latency_ms": 45,
  "checks": [
    {"name": "pii_filter", "status": "PASS", "redactions": 0},
    {"name": "injection_detection", "status": "PASS", "score": 0.1}
  ]
}
```

**Privacy Invariant**: Original PII values are NEVER logged. Only redaction counts and sanitized inputs.

---

## Performance Requirements

| Metric | Target |
|--------|--------|
| PII filter latency | < 50ms for 10KB input |
| Injection detection latency | < 50ms |
| Total blocking guardrail latency | < 100ms |
| Parallel mode overhead | < 10% |

---

## Error Handling

### Guardrail Script Failure

If a guardrail script fails to execute:
1. Log error to trajectory with `action: ERROR`
2. Apply fail-open policy (continue execution)
3. Include error in skill output metadata

**Fail-Open Rationale**: Guardrail failures should not block legitimate work. The error is logged for audit.

### Invalid Configuration

If guardrail configuration is invalid:
1. Log warning at skill load time
2. Fall back to defaults
3. Continue with default guardrail behavior

---

## Related Protocols

- [danger-level.md](danger-level.md) - Tool risk enforcement
- [feedback-loops.md](feedback-loops.md) - Quality gates (output guardrails)
- [run-mode.md](run-mode.md) - Autonomous execution safety

---

*Protocol Version 1.0.0 | Input Guardrails & Tool Risk Enforcement v1.20.0*
