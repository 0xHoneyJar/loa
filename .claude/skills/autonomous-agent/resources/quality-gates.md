# Quality Gates Protocol

## Overview

The Five Gates model ensures skill execution quality through progressive validation. This document defines the V2 Minimal implementation of each gate.

## The Five Gates

```
┌─────────────────────────────────────────────────────────────────┐
│                        SKILL EXECUTION                          │
├─────────────────────────────────────────────────────────────────┤
│  Gate 0        Gate 1        Gate 2        Gate 3        Gate 4 │
│  ───────       ───────       ───────       ───────       ────── │
│  Selection     Precondition  Execution     Output        Goal   │
│  ───────       ───────       ───────       ───────       ────── │
│  Right skill?  Inputs exist? Exit code?    Outputs exist? Goals │
│                                                          met?   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Gate 0: Skill Selection

**Question**: Is this the right skill for the task?

### V2 Minimal Implementation

**Method**: Human review (operator judgment)

**Future Vision**: QMD (Query-Match-Dispatch) with semantic matching

```yaml
# Current: Human decides which skill to invoke
# Future: Automatic skill selection based on task description

gate_0:
  method: human_review
  future: qmd_semantic_match
  confidence_threshold: 0.8
```

### Bypass Conditions

- Skill explicitly invoked by user (e.g., `/implement`)
- Skill invoked by orchestrator with task match

### Failure Mode

- Wrong skill selected → wasted execution
- No automated detection in V2

---

## Gate 1: Precondition Check

**Question**: Do all required inputs exist?

### V2 Minimal Implementation

**Method**: File existence check

```bash
# Check required inputs exist
check_preconditions() {
  local skill=$1
  local missing=()

  case $skill in
    "designing-architecture")
      [[ ! -f "grimoires/loa/prd.md" ]] && missing+=("prd.md")
      ;;
    "planning-sprints")
      [[ ! -f "grimoires/loa/prd.md" ]] && missing+=("prd.md")
      [[ ! -f "grimoires/loa/sdd.md" ]] && missing+=("sdd.md")
      ;;
    "implementing-tasks")
      [[ ! -f "grimoires/loa/sprint.md" ]] && missing+=("sprint.md")
      ;;
    "reviewing-code")
      # Check reviewer.md exists for target sprint
      [[ ! -f "grimoires/loa/a2a/sprint-${SPRINT}/reviewer.md" ]] && missing+=("reviewer.md")
      ;;
    "auditing-security")
      [[ ! -f "grimoires/loa/a2a/sprint-${SPRINT}/engineer-feedback.md" ]] && missing+=("engineer-feedback.md")
      ;;
  esac

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "GATE_1_FAILED: Missing inputs: ${missing[*]}"
    return 1
  fi
  return 0
}
```

### Exit Codes

| Code | Meaning | Action |
|------|---------|--------|
| 0 | All inputs present | Proceed to Gate 2 |
| 1 | Inputs missing | Block, request missing inputs |

### Configuration

```yaml
# In construct.yaml
handoffs:
  design_to_implementation:
    requires:
      - grimoires/{project}/sdd.md
      - grimoires/{project}/sprint.md
    on_missing: block  # block | warn | skip
```

---

## Gate 2: Execution Check

**Question**: Did the skill execute successfully?

### V2 Minimal Implementation

**Method**: Exit code evaluation

```yaml
# Standard exit codes
exit_codes:
  0: success       # Skill completed successfully
  1: retry         # Temporary failure, can retry
  2: blocked       # Permanent failure, needs intervention
```

### Exit Code Handling

```bash
execute_skill() {
  local skill=$1
  local result

  # Execute skill and capture exit code
  invoke_skill "$skill"
  result=$?

  case $result in
    0)
      echo "GATE_2_PASSED: Skill executed successfully"
      return 0
      ;;
    1)
      echo "GATE_2_RETRY: Temporary failure"
      # Check retry count
      if [[ $RETRY_COUNT -lt $MAX_RETRIES ]]; then
        ((RETRY_COUNT++))
        execute_skill "$skill"
      else
        echo "GATE_2_FAILED: Max retries exceeded"
        return 2
      fi
      ;;
    2)
      echo "GATE_2_BLOCKED: Permanent failure"
      return 2
      ;;
  esac
}
```

### Retry Logic

| Scenario | Retry? | Max Attempts |
|----------|--------|--------------|
| Network timeout | Yes | 3 |
| Tool error | Yes | 2 |
| Missing dependency | No | N/A |
| User abort | No | N/A |

---

## Gate 3: Output Check

**Question**: Were all expected outputs created?

### V2 Minimal Implementation

**Method**: File existence check

```bash
check_outputs() {
  local skill=$1
  local missing=()

  case $skill in
    "discovering-requirements")
      [[ ! -f "grimoires/loa/prd.md" ]] && missing+=("prd.md")
      ;;
    "designing-architecture")
      [[ ! -f "grimoires/loa/sdd.md" ]] && missing+=("sdd.md")
      ;;
    "planning-sprints")
      [[ ! -f "grimoires/loa/sprint.md" ]] && missing+=("sprint.md")
      ;;
    "implementing-tasks")
      [[ ! -f "grimoires/loa/a2a/sprint-${SPRINT}/reviewer.md" ]] && missing+=("reviewer.md")
      ;;
    "reviewing-code")
      [[ ! -f "grimoires/loa/a2a/sprint-${SPRINT}/engineer-feedback.md" ]] && missing+=("engineer-feedback.md")
      ;;
    "auditing-security")
      [[ ! -f "grimoires/loa/a2a/sprint-${SPRINT}/auditor-sprint-feedback.md" ]] && missing+=("auditor-sprint-feedback.md")
      ;;
  esac

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "GATE_3_FAILED: Missing outputs: ${missing[*]}"
    return 1
  fi
  return 0
}
```

### Configuration

```yaml
# In construct.yaml
contracts:
  discovery:
    outputs:
      - grimoires/{project}/prd.md
      - grimoires/{project}/reality/*.md
    exit_codes:
      0: success
      1: incomplete
      2: blocked
```

---

## Gate 4: Goal Achievement Check

**Question**: Were the PRD goals achieved?

### V2 Minimal Implementation

**Method**: Human review (end-of-cycle validation)

**Future Vision**: LLM-as-judge with structured evaluation

```yaml
gate_4:
  method: human_review
  future: llm_as_judge

  # Goal validation runs at end of sprint plan
  trigger: end_of_sprint_plan

  # Goal validator subagent
  validator: goal-validator

  # Verdicts
  verdicts:
    - GOAL_ACHIEVED
    - GOAL_AT_RISK
    - GOAL_BLOCKED
```

### Goal Traceability

Goals are tracked through Appendix C in sprint plan:

```markdown
## Appendix C: Goal Traceability

| Goal | Contributing Tasks |
|------|-------------------|
| G-1: Autonomous Execution | 1.2, 1.6, 2.1, 3.5 |
| G-2: Separation of Concerns | 3.1, 3.2 |
```

### Validation Process

1. E2E task executes in final sprint
2. Goal validator checks each G-N against implementation
3. Verdict returned per goal
4. Block on GOAL_BLOCKED, warn on GOAL_AT_RISK

---

## Remediation Loop

When any gate fails (except Gate 0), remediation loop activates:

```
┌──────────────────────────────────────────────────────────┐
│                   REMEDIATION LOOP                        │
├──────────────────────────────────────────────────────────┤
│                                                          │
│   Gate Failed ──▶ Parse Findings ──▶ Prioritize         │
│                         │                                │
│                         ▼                                │
│                   Fix Findings                           │
│                         │                                │
│                         ▼                                │
│              ┌─── Re-run Gate ───┐                      │
│              │                   │                       │
│              ▼                   ▼                       │
│           PASSED              FAILED                     │
│              │                   │                       │
│              ▼                   ▼                       │
│         Continue          Check Loop Count               │
│                                  │                       │
│                    ┌─────────────┴─────────────┐        │
│                    ▼                           ▼         │
│              < MAX_LOOPS              >= MAX_LOOPS       │
│                    │                           │         │
│                    ▼                           ▼         │
│               Retry Loop                  ESCALATE       │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

### Configuration

```yaml
remediation:
  max_loops: 3
  on_max_loops: escalate

  findings_priority:
    - CRITICAL   # Must fix, blocks all
    - HIGH       # Must fix before PR
    - MEDIUM     # Should fix
    - LOW        # Nice to fix
```

### Escalation

When `max_loops` exceeded:

1. Generate escalation report
2. Include:
   - Phase where blocked
   - Remaining findings
   - Remediation attempts
   - Suggested human actions
3. Halt autonomous execution
4. Await human intervention

---

## Gate Summary

| Gate | Question | V2 Method | Future Method |
|------|----------|-----------|---------------|
| 0 | Right skill? | Human review | QMD semantic match |
| 1 | Inputs exist? | File check | Schema validation |
| 2 | Executed OK? | Exit code | + Error analysis |
| 3 | Outputs exist? | File check | Schema validation |
| 4 | Goals achieved? | Human review | LLM-as-judge |

## AI vs Human Operator Differences

| Gate | AI Operator | Human Operator |
|------|-------------|----------------|
| 0 | Auto-select (when QMD ready) | Manual selection |
| 1 | Block on missing | Warn, allow override |
| 2 | Retry then escalate | Retry or abort |
| 3 | Block on missing | Warn, allow continue |
| 4 | Block on BLOCKED | Advisory |
