# Trajectory Evaluation Protocol (ADK-Level)

> Evaluate not just the output, but the reasoning path.

## Purpose

Google's ADK emphasizes evaluating the **step-by-step execution trajectory**, not just final results. This catches:
- Hallucinated reasoning that happened to reach a correct answer
- Brittle approaches that work by accident
- Missed edge cases in the reasoning process

## Trajectory Log Location

```
loa-grimoire/a2a/trajectory/
  {agent}-{timestamp}.jsonl
```

## Log Format

Each line is a JSON object:

```json
{
  "timestamp": "2024-01-10T14:30:00Z",
  "agent": "implementing-tasks",
  "step": 3,
  "action": "file_read",
  "input": {"path": "src/auth/login.ts"},
  "reasoning": "Need to understand current auth implementation before modifying",
  "grounding": {
    "type": "citation",
    "source": "sdd.md:L145",
    "quote": "Authentication must use bcrypt with cost factor 12"
  },
  "output_summary": "Found existing bcrypt implementation with cost 10",
  "next_action": "Update cost factor to 12 per SDD requirement"
}
```

## Grounding Types

| Type | Description | Required Fields |
|------|-------------|-----------------|
| `citation` | Direct quote from documentation | `source`, `quote` |
| `code_reference` | Reference to existing code | `file`, `line`, `snippet` |
| `assumption` | Ungrounded claim | `assumption`, `confidence` |
| `user_input` | Based on user's explicit request | `message_id` |

## Agent Responsibilities

### Before Each Action
1. Log the intended action
2. Document the reasoning
3. Cite grounding (or flag as assumption)

### After Each Action
1. Summarize the output (not raw data)
2. State the next action and why

### On Task Completion
1. Generate trajectory summary
2. Self-evaluate: "Did I reach this conclusion through grounded reasoning?"

## Evaluation by reviewing-code Agent

When auditing a completed task:

1. Load trajectory log for the implementing agent
2. Check each step for:
   - Ungrounded assumptions
   - Reasoning jumps (conclusions without steps)
   - Contradictions with previous steps
3. Flag issues:
   ```markdown
   ## Trajectory Audit: PR #42

   Step 5: Ungrounded assumption about cache TTL
   Step 8: Reasoning jump - no explanation for architecture choice
   Steps 1-4, 6-7, 9-12: Well-grounded

   Recommendation: Request clarification on steps 5 and 8 before approval.
   ```

## Evaluation-Driven Development (EDD)

Before marking a task COMPLETE, agents must:

1. Create 3 diverse test scenarios:
   ```markdown
   ## Test Scenarios for: Implement User Authentication

   1. **Happy Path**: Valid credentials -> successful login -> JWT returned
   2. **Edge Case**: Expired password -> prompt for reset -> block login
   3. **Adversarial**: SQL injection attempt -> sanitized -> blocked with log
   ```

2. Verify each scenario is covered by implementation

3. Log test scenario creation in trajectory

## Configuration

In `.loa.config.yaml`:

```yaml
edd:
  enabled: true
  min_test_scenarios: 3
  trajectory_audit: true
  require_citations: true
```

## Retention

Trajectory logs are auto-compacted after `trajectory_retention_days` (default: 30).

To preserve a trajectory permanently:
```bash
mv loa-grimoire/a2a/trajectory/implementing-2024-01-10.jsonl \
   loa-grimoire/a2a/trajectory/archive/
```

## Why This Matters

Traditional evaluation checks only:
- Did the output compile?
- Did tests pass?
- Does the feature work?

Trajectory evaluation also checks:
- Was the reasoning sound?
- Were assumptions made explicit?
- Would this approach generalize?
- Did the agent understand *why*, not just *what*?

This catches "lucky guesses" and ensures reproducible quality.
