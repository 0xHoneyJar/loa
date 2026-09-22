# Input Guardrails Protocol

**Schema**: `.claude/schemas/guardrail-result.schema.json`

---

## Overview

Input guardrails validate skill input before execution, running ahead of Invisible Prompt Enhancement to catch issues at the earliest point.

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
  "status": "FAIL",
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

**Blocking** (`mode: blocking`): the check completes before the skill runs, and a failure halts the workflow. Use for `pii_filter`, `injection_detection`.

**Parallel** (`mode: parallel`): the check runs alongside the skill. A check that fails before the skill finishes is a tripwire that halts execution; a skill that finishes first waits for the check result. Use for `relevance_check`.

**Advisory** (`mode: advisory`): the check logs a result but never blocks; the skill continues regardless. Use for experimental checks and low-confidence detectors.

---

## Failure Handling

**On BLOCK**: log the result to trajectory, show the message below, suggest remediation if applicable, and allow override for authorized users.

```
⚠️  Input Guardrail Blocked Execution
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Check: injection_detection
Score: 0.85 (threshold: 0.70)
Patterns: instruction_override, role_confusion

Your input contains patterns that may indicate prompt injection.
Please rephrase your request or use --bypass-guardrails if authorized.
```

**On WARN**: log the result, display a warning notification, continue execution, and include the warning in output metadata.

**On Tripwire** (parallel mode): halt skill execution immediately, log the tripwire event, optionally roll back uncommitted changes, and display a tripwire notification.

---

## Integration with Skill Loading Pipeline

Load order: Command Parsing → Skill Resolution → Danger Level Check (`danger-level.md`) → Input Guardrails (this protocol) → Invisible Prompt Enhancement → Skill KERNEL Execution → Output Guardrails (quality gates) → Retrospective Postlude.

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

**Guardrail script failure**: if a script fails to execute, log the error to trajectory with `action: ERROR`, apply fail-open policy (continue execution), and include the error in skill output metadata. Guardrail failures should not block legitimate work; the error is logged for audit.

**Invalid configuration**: if guardrail configuration is invalid, log a warning at skill load time, fall back to defaults, and continue with default guardrail behavior.

---

## Related Protocols

- [danger-level.md](danger-level.md) - Tool risk enforcement
- [feedback-loops.md](feedback-loops.md) - Quality gates (output guardrails)
- [run-mode.md](run-mode.md) - Autonomous execution safety
