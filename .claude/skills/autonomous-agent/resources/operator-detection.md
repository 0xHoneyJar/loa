# Operator Detection

Loa adapts behavior based on whether the operator is human or AI.

## Configuration

```yaml
# .loa.config.yaml
operator:
  type: auto | human | ai
  
  ai_config:
    enforce_autonomous_skill: true    # Auto-invoke /autonomous
    strict_quality_gates: true        # All gates mandatory
    require_audit_before_pr: true     # No PR without audit pass
    require_audit_before_deploy: true # No deploy without verification
    max_remediation_loops: 3          # Escalate after N failures
```

## Detection Heuristics (when `type: auto`)

| Check | Weight | How |
|-------|--------|-----|
| Environment variable | High | `CLAWDBOT_AGENT=true` or `LOA_OPERATOR=ai` |
| AGENTS.md markers | High | Contains `operator: ai` or AI-specific patterns |
| Heartbeat config | Medium | Presence of `HEARTBEAT.md` with cron patterns |
| No interactive TTY | Medium | `process.stdin.isTTY === false` |
| Session context | Low | No human greeting patterns in first message |

### Detection Logic

```typescript
function detectOperatorType(): 'human' | 'ai' {
  // Explicit environment override
  if (process.env.LOA_OPERATOR === 'ai') return 'ai';
  if (process.env.LOA_OPERATOR === 'human') return 'human';
  if (process.env.CLAWDBOT_AGENT === 'true') return 'ai';
  
  // Check AGENTS.md for markers
  const agentsMd = readFileSync('AGENTS.md', 'utf-8');
  if (agentsMd.includes('operator: ai') || 
      agentsMd.includes('autonomous agent') ||
      agentsMd.includes('AI operator')) {
    return 'ai';
  }
  
  // Check for heartbeat patterns
  if (existsSync('HEARTBEAT.md')) {
    const heartbeat = readFileSync('HEARTBEAT.md', 'utf-8');
    if (heartbeat.includes('cron') || heartbeat.includes('heartbeat')) {
      return 'ai';
    }
  }
  
  // Check TTY
  if (!process.stdin.isTTY) {
    return 'ai';  // Non-interactive = likely AI
  }
  
  return 'human';  // Default to human
}
```

## Behavior Differences

### Human Operator (`type: human`)

```
/implement → Interactive flow
           → Ask clarifying questions
           → Suggest but don't enforce audit
           → Allow PR without full process
```

### AI Operator (`type: ai`)

```
/implement → Auto-wrap with /autonomous
           → No clarifying questions (use context)
           → MANDATORY audit before PR
           → Full quality gates enforced
           → Escalate on failure, don't retry forever
```

## Auto-Wrapping

When AI operator detected and `enforce_autonomous_skill: true`:

```typescript
// Before any skill execution
if (config.operator.type === 'ai' && 
    config.operator.ai_config.enforce_autonomous_skill) {
  
  // Wrap the requested skill in autonomous orchestration
  const originalSkill = requestedSkill;
  
  return executeAutonomous({
    targetSkill: originalSkill,
    enforceAudit: config.operator.ai_config.require_audit_before_pr,
    maxLoops: config.operator.ai_config.max_remediation_loops,
  });
}
```

## AGENTS.md Markers

AI operators should include in their AGENTS.md:

```markdown
## Operator

- **Type**: AI Agent
- **Name**: [Agent name]
- **Framework**: Loa
- **Autonomous**: true

## Quality Requirements

This agent operates autonomously and must:
- Follow exhaustive loa process
- Pass audit before any PR
- Escalate after 3 remediation failures
```

## Environment Variables

| Variable | Values | Description |
|----------|--------|-------------|
| `LOA_OPERATOR` | `human`, `ai` | Explicit operator type |
| `CLAWDBOT_AGENT` | `true`, `false` | Running inside Clawdbot |
| `LOA_STRICT_MODE` | `true`, `false` | Force strict quality gates |

## Integration Points

### Clawdbot

Set in Clawdbot's agent execution:
```bash
export CLAWDBOT_AGENT=true
export LOA_OPERATOR=ai
```

### CI/CD

For automated runs:
```yaml
env:
  LOA_OPERATOR: ai
  LOA_STRICT_MODE: true
```

### Local Development

For human developers:
```bash
# Default - no env vars needed
# Or explicitly:
export LOA_OPERATOR=human
```
