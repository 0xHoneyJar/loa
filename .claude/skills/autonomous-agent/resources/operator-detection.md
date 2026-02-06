# Operator Detection Protocol

## Overview

The autonomous-agent skill auto-detects whether it is being operated by a human or an AI agent. This detection changes behavior to enforce stricter quality gates for AI operators while preserving human flexibility.

## Detection Heuristics

Detection proceeds in priority order (first match wins):

### 1. Explicit Environment Variables (Highest Priority)

```bash
# Explicit operator type
LOA_OPERATOR=ai          # Forces AI mode
LOA_OPERATOR=human       # Forces human mode

# Clawdbot/Moltbot signatures (ALWAYS check these first)
CLAWDBOT_GATEWAY_TOKEN   # Present = Clawdbot runtime
CLAWDBOT_GATEWAY_PORT    # Present = Clawdbot runtime
CLAWDBOT_PATH_BOOTSTRAPPED=1  # Clawdbot workspace initialized

# Other AI agent markers
CLAWDBOT_AGENT=true      # Explicit Clawdbot marker
CLAUDECODE=1             # Claude Code runtime
CURSOR_AGENT=true        # Cursor AI
WINDSURF_AGENT=true      # Windsurf AI
AIDER_SESSION=true       # Aider AI
```

**Verdict**: If ANY of these are present → `AI_OPERATOR`

**Critical**: Check for `CLAWDBOT_GATEWAY_TOKEN` or `CLAWDBOT_GATEWAY_PORT` FIRST. These are definitive proof of Clawdbot/Moltbot AI operation.

### 1.5. Clawdbot/Moltbot Workspace Detection

If env vars inconclusive, check for Clawdbot/moltbot workspace signatures:

```bash
# Check for Clawdbot config
[ -f "$HOME/.clawdbot/clawdbot.json" ] && echo "AI_OPERATOR"

# Check for clawdbot binary
which clawdbot &>/dev/null && echo "AI_OPERATOR"

# Moltbot workspace signature files (any 2+ = AI_OPERATOR)
MOLTBOT_SIGNATURES=(
  "AGENTS.md"      # Agent instructions
  "SOUL.md"        # Agent identity/personality
  "IDENTITY.md"    # Agent identity metadata
  "HEARTBEAT.md"   # Cron/heartbeat config
  "TOOLS.md"       # Tool configuration
  "USER.md"        # User context
  "WORKLEDGER.md"  # Work tracking
)

count=0
for sig in "${MOLTBOT_SIGNATURES[@]}"; do
  [ -f "$sig" ] && ((count++))
done
[ $count -ge 2 ] && echo "AI_OPERATOR"
```

**Verdict**: 
- Any Clawdbot config/binary → `AI_OPERATOR`
- 2+ moltbot signature files → `AI_OPERATOR` (high confidence)
- 1 signature file → weak signal, continue to next check

### 2. AGENTS.md Markers

Check for `AGENTS.md` in repository root:

```markdown
<!-- AGENTS.md -->
# AI Agent Instructions

This repository is configured for AI-assisted development.

## Active Agents
- clawdbot: PR automation
- cursor: code completion
```

**Detection**: File exists AND contains agent configuration → `AI_OPERATOR`

### 3. HEARTBEAT.md Patterns

Check for automated heartbeat patterns in `.claude/HEARTBEAT.md`:

```markdown
<!-- HEARTBEAT.md -->
Last activity: 2026-01-31T14:00:00Z
Agent: claude-opus-4-6
Session: autonomous-run-abc123
```

**Detection**: Recent heartbeat (< 5 minutes) with Agent field → `AI_OPERATOR`

### 4. TTY Detection (Lowest Priority)

```bash
# Check if running in interactive terminal
if [ -t 0 ] && [ -t 1 ]; then
  # stdin and stdout are TTY - likely human
  verdict="HUMAN_OPERATOR"
else
  # No TTY - likely automated/AI
  verdict="AI_OPERATOR"
fi
```

**Note**: TTY detection is a weak signal. Prefer explicit markers.

## Behavior Differences

### AI Operator Mode

When `AI_OPERATOR` detected:

| Aspect | Behavior |
|--------|----------|
| **Quality Gates** | All gates mandatory (no skip) |
| **Audit Requirement** | Must pass audit before PR |
| **Deploy Approval** | Blocked (requires human) |
| **Remediation Loops** | Max 3, then escalate |
| **Context Warnings** | Aggressive (80K soft limit) |
| **Skill Wrapping** | Auto-wrap with `/autonomous` |

### Human Operator Mode

When `HUMAN_OPERATOR` detected:

| Aspect | Behavior |
|--------|----------|
| **Quality Gates** | Advisory (can skip with justification) |
| **Audit Requirement** | Recommended, not mandatory |
| **Deploy Approval** | Human is the approver |
| **Remediation Loops** | Unlimited (human judgment) |
| **Context Warnings** | Standard (150K hard limit) |
| **Skill Wrapping** | Skills invoked directly |

## Auto-Wrapping Logic

When AI operator is detected and `enforce_autonomous_skill: true`:

```
User invokes: /implement sprint-1
Auto-wrapped: /autonomous --phase=implementation --target=sprint-1
```

This ensures:
1. Proper phase context established
2. Quality gates enforced
3. Trajectory logging active
4. Checkpoint management enabled

### Bypass for Sub-Skills

Sub-skills invoked by `/autonomous` are NOT re-wrapped:

```
/autonomous
  └── /implement sprint-1     # NOT wrapped again
       └── /review-sprint 1   # NOT wrapped again
```

Detection: Check `LOA_AUTONOMOUS_ACTIVE=true` environment variable.

## Configuration

In `.loa.config.yaml`:

```yaml
autonomous_agent:
  operator:
    # Detection mode: auto | human | ai
    type: auto

    # AI-specific configuration
    ai_config:
      # Auto-wrap skills with /autonomous
      enforce_autonomous_skill: true

      # All quality gates mandatory
      strict_quality_gates: true

      # Must pass audit before PR creation
      require_audit_before_pr: true

      # Must pass audit before deploy
      require_audit_before_deploy: true
```

## Implementation Notes

### Detection Caching

Operator type is detected once per session and cached:

```bash
# Cache location
.loa-checkpoint/operator-type.yaml

# Schema
operator_type: AI_OPERATOR | HUMAN_OPERATOR
detected_at: 2026-01-31T14:00:00Z
detection_method: env_var | agents_md | heartbeat | tty
confidence: high | medium | low
```

### Override Mechanism

Human can override AI detection:

```bash
# Force human mode for current session
export LOA_OPERATOR=human

# Or via config
autonomous_agent:
  operator:
    type: human  # Explicit override
```

### Logging

Detection events logged to trajectory:

```jsonl
{"event": "operator_detected", "type": "AI_OPERATOR", "method": "env_var", "confidence": "high"}
```

## Security Considerations

1. **No Trust Escalation**: AI operators cannot self-promote to human
2. **Audit Trail**: All operator detection logged
3. **Fail-Secure**: Unknown → AI_OPERATOR (stricter by default)
4. **Human Override**: Only humans can override to human mode
