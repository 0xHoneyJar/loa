# Agent Trajectory Logs (`trajectory/`)

This directory contains agent reasoning audit trails in JSONL format.

## Purpose

Trajectory logs capture the step-by-step reasoning of each agent, enabling:

- **Post-hoc evaluation** of agent decisions
- **Grounding verification** (citations vs assumptions)
- **Debugging** when agents produce unexpected outputs

## Format

Each log file follows the pattern `{agent}-{date}.jsonl`:

```json
{"timestamp": "2024-01-15T10:30:00Z", "agent": "implementing-tasks", "action": "read_file", "reasoning": "Need to understand existing auth flow", "grounding": {"type": "code_reference", "source": "src/auth/login.ts"}}
```

### Grounding Types

- `citation`: Direct quote from documentation
- `code_reference`: Reference to existing code
- `assumption`: Ungrounded claim (should be flagged)
- `user_input`: Based on explicit user request

## Security Notice

**IMPORTANT**: Trajectory logs may contain sensitive information including:

- Agent thinking/reasoning content
- Memory search queries and results
- File paths and code snippets
- Session identifiers

**Recommendations**:
1. Never commit trajectory logs to version control (already in `.gitignore`)
2. Periodically review and purge old logs
3. Do not share trajectory files with untrusted parties
4. Consider encrypting logs in sensitive environments

Logs older than 30 days can typically be safely deleted:
```bash
find grimoires/loa/a2a/trajectory -name "*.jsonl" -mtime +30 -delete
```

## Note for Template Users

This directory is intentionally empty in the template. Trajectory logs are generated during agent execution and excluded from version control via `.gitignore`.
