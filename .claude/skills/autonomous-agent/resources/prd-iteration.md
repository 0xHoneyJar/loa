# PRD Iteration Protocol

## Overview

The PRD Iteration Protocol handles the feedback loop from implementation back to requirements. When Phase 7 (Learning) discovers significant gaps between PRD goals and actual implementation, it triggers PRD refinement.

Reference: Issue #29 - PRD Iteration Logic

## Gap Classification

### Major Gaps

Gaps that require PRD iteration before proceeding:

| Category | Example | Action |
|----------|---------|--------|
| **Missing Goal** | Core functionality not specified in PRD | Trigger `/refine-prd` |
| **Scope Creep** | Implemented features not in any goal | Document, possibly remove |
| **Goal Blocked** | Technical constraint prevents goal | Revise goal or add prerequisite |
| **Misunderstood Requirement** | Implementation doesn't match intent | Clarify and re-implement |

### Minor Gaps

Gaps addressable in next sprint without PRD changes:

| Category | Example | Action |
|----------|---------|--------|
| **Edge Case** | Unhappy path not handled | Add task to next sprint |
| **Polish** | UX improvement opportunity | Backlog item |
| **Documentation** | Missing or unclear docs | Documentation task |
| **Test Coverage** | Insufficient tests | Testing task |

## Phase 7 PRD Check Process

### Step 1: Goal Achievement Review

For each PRD goal (G-1, G-2, etc.):

```markdown
## Goal Achievement Review

| Goal | Status | Evidence | Gap Type |
|------|--------|----------|----------|
| G-1: Autonomous Execution | ACHIEVED | All phases complete, tests pass | - |
| G-2: Separation of Concerns | AT_RISK | Docs created but not verified | Minor |
| G-3: Measurable Selection | BLOCKED | QMD not available | Major |
| G-4: Feedback Loop | ACHIEVED | Feedback files created | - |
| G-5: Context Management | ACHIEVED | Checkpoints under 150K | - |
```

### Step 2: Gap Classification

```bash
# Pseudo-logic for gap classification
for goal in prd_goals:
    status = validate_goal(goal)

    if status == "BLOCKED":
        gaps.major.append({
            "goal": goal.id,
            "reason": "Technical constraint prevents completion",
            "action": "refine_prd"
        })

    elif status == "AT_RISK":
        # Check if gap is scope-related
        if is_scope_issue(goal):
            gaps.major.append({
                "goal": goal.id,
                "reason": "Scope mismatch",
                "action": "refine_prd"
            })
        else:
            gaps.minor.append({
                "goal": goal.id,
                "reason": "Needs additional work",
                "action": "next_sprint"
            })
```

### Step 3: Write gaps.yaml

```yaml
# grimoires/loa/gaps.yaml
version: 1
execution_id: "exec-abc123"
generated_at: "2026-01-31T16:00:00Z"
prd_version: "1.0.0"

summary:
  total_goals: 5
  achieved: 3
  at_risk: 1
  blocked: 1
  major_gaps: 1
  minor_gaps: 1

gaps:
  major:
    - id: gap-001
      goal_id: G-3
      goal_title: "Measurable Skill Selection (Gate 0)"
      status: BLOCKED
      reason: "QMD (Query-Match-Dispatch) not available in current environment"
      impact: "Cannot automatically select skills based on task semantics"
      recommendation: "Defer Gate 0 automation to V3, use human selection for V2"
      action: refine_prd

  minor:
    - id: gap-002
      goal_id: G-2
      goal_title: "Clear Separation of Concerns"
      status: AT_RISK
      reason: "Documentation created but integration not verified"
      impact: "Architecture may diverge without verification"
      recommendation: "Add integration test in next sprint"
      action: next_sprint

recommendation: |
  One major gap found (G-3: Measurable Selection).

  Recommended action: Run `/refine-prd` to:
  1. Revise G-3 scope for V2 (human-assisted selection)
  2. Add G-3b for future QMD integration

  Minor gap (G-2) can be addressed in Sprint 4.
```

### Step 4: Trigger Decision

```
IF major_gaps > 0:
    RECOMMEND /refine-prd
    INCLUDE gaps.yaml in context
    HALT autonomous execution until PRD revised

ELIF minor_gaps > 0:
    LOG gaps to feedback file
    CONTINUE to next sprint/cycle
    ADD minor gap tasks to backlog

ELSE:
    LOG "All goals achieved"
    PROCEED with deployment (if configured)
```

## /refine-prd Trigger Conditions

The `/refine-prd` command should be triggered when:

1. **Major Gap Detected**: Any goal is BLOCKED or has scope issues
2. **Multiple Minor Gaps**: 3+ minor gaps suggest systemic PRD issue
3. **User Request**: Human explicitly requests PRD refinement
4. **Feedback Escalation**: Same feedback item seen 3+ sessions

## gaps.yaml Schema

```yaml
# .claude/schemas/gaps.schema.yaml
$schema: "http://json-schema.org/draft-07/schema#"
type: object
required:
  - version
  - execution_id
  - generated_at
  - summary
  - gaps
properties:
  version:
    type: integer
    const: 1
  execution_id:
    type: string
  generated_at:
    type: string
    format: date-time
  prd_version:
    type: string
  summary:
    type: object
    required:
      - total_goals
      - achieved
    properties:
      total_goals:
        type: integer
      achieved:
        type: integer
      at_risk:
        type: integer
      blocked:
        type: integer
      major_gaps:
        type: integer
      minor_gaps:
        type: integer
  gaps:
    type: object
    properties:
      major:
        type: array
        items:
          $ref: "#/definitions/gap_entry"
      minor:
        type: array
        items:
          $ref: "#/definitions/gap_entry"
  recommendation:
    type: string

definitions:
  gap_entry:
    type: object
    required:
      - id
      - goal_id
      - status
      - reason
      - action
    properties:
      id:
        type: string
        pattern: "^gap-[0-9]{3}$"
      goal_id:
        type: string
        pattern: "^G-[0-9]+$"
      goal_title:
        type: string
      status:
        enum: [BLOCKED, AT_RISK, PARTIAL]
      reason:
        type: string
      impact:
        type: string
      recommendation:
        type: string
      action:
        enum: [refine_prd, next_sprint, backlog, escalate]
```

## Integration with Continuous Learning

Gaps flow into the Compound Learning system:

```
gaps.yaml → Pattern Detection → Similar gaps across sessions?
                ↓                        ↓
          Single occurrence         Multiple occurrences
                ↓                        ↓
           Log & monitor        Extract as skill/protocol update
```

### Gap-to-Skill Promotion

When same gap type appears across 3+ sessions:

1. Elevate from feedback to skill candidate
2. Run through 4-gate quality filter
3. If passes, create skill to prevent future occurrences

Example:
```yaml
# Promoted from gap to skill
name: check-qmd-availability
trigger: "Before Gate 0 automation"
action: "Verify QMD binary in PATH, fallback to human selection"
```

## Configuration

In `.loa.config.yaml`:

```yaml
autonomous_agent:
  prd_iteration:
    # Enable PRD iteration detection
    enabled: true
    # Output file for gaps
    gaps_file: grimoires/loa/gaps.yaml
    # Threshold for minor gaps to trigger review
    minor_gap_threshold: 3
    # Auto-recommend /refine-prd on major gaps
    auto_recommend_refine: true
    # Block autonomous execution on major gaps
    block_on_major_gaps: true
```
