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

## Note for Template Users

This directory is intentionally empty in the template. Trajectory logs are generated during agent execution and excluded from version control via `.gitignore`.
