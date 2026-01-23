# Software Design Document: Goal Traceability & End-to-End Validation

**Version:** 1.0
**Date:** 2026-01-23
**Author:** Software Architect Agent
**Status:** Draft
**PRD Reference:** `grimoires/loa/prd-goal-traceability.md`

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [System Architecture](#system-architecture)
3. [Component Design](#component-design)
4. [Data Architecture](#data-architecture)
5. [Integration Points](#integration-points)
6. [Security Considerations](#security-considerations)
7. [Testing Strategy](#testing-strategy)
8. [Implementation Order](#implementation-order)
9. [Rollback Plan](#rollback-plan)

---

## Executive Summary

This SDD describes the technical design for implementing Goal Traceability & End-to-End Validation in the Loa framework. The solution extends existing templates, skills, and scripts with minimal new components while maintaining backward compatibility.

**Key Design Decisions:**

1. **Goal IDs in Templates** - Extend PRD/sprint templates with Goal ID columns (no new file formats)
2. **Goal Validator Subagent** - New subagent following existing architecture-validator pattern
3. **Workflow State Script** - Lightweight bash script leveraging existing suggest-next-step.sh
4. **Graceful Degradation** - All features work without goal IDs (backward compatible)

**Estimated Effort:** 3 sprints (MVP + Fast Follow)

---

## System Architecture

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              GOAL TRACEABILITY LAYER                         │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐                   │
│  │   PRD.md     │    │  sprint.md   │    │  NOTES.md    │                   │
│  │              │    │              │    │              │                   │
│  │ Goals:       │───►│ Appendix C:  │───►│ Goal Status: │                   │
│  │ G-1, G-2     │    │ Goal Mapping │    │ G-1: partial │                   │
│  └──────────────┘    └──────────────┘    └──────────────┘                   │
│         │                   │                   │                            │
│         ▼                   ▼                   ▼                            │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │                         GOAL VALIDATOR SUBAGENT                          ││
│  │  - Reads PRD goals (G-1, G-2)                                           ││
│  │  - Checks sprint task completion                                         ││
│  │  - Validates E2E goal achievement                                        ││
│  │  - Returns: GOAL_ACHIEVED | GOAL_AT_RISK | GOAL_BLOCKED                 ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                   │                                          │
│                                   ▼                                          │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │                         REVIEW WORKFLOW                                  ││
│  │  reviewing-code skill → invokes goal-validator → blocks on AT_RISK      ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                              /loa GUIDED WORKFLOW                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐                   │
│  │ workflow-    │───►│ suggest-next │───►│ /loa command │                   │
│  │ state.sh     │    │ -step.sh     │    │              │                   │
│  │              │    │ (existing)   │    │ Prompts user │                   │
│  │ Detects:     │    │              │    │ [Y/n/exit]   │                   │
│  │ - PRD exists │    │ Returns:     │    │              │                   │
│  │ - SDD exists │    │ - Next cmd   │    │ Executes or  │                   │
│  │ - Sprint #   │    │ - Message    │    │ skips        │                   │
│  └──────────────┘    └──────────────┘    └──────────────┘                   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Zone Compliance

| Component | Zone | Permission | Rationale |
|-----------|------|------------|-----------|
| `prd-template.md` | System | Read-only | Updated via framework release |
| `sprint-template.md` | System | Read-only | Updated via framework release |
| `goal-validator.md` | System | Read-only | New subagent |
| `workflow-state.sh` | System | Execute | State detection |
| `loa.md` | System | Read-only | New command |
| `grimoires/loa/*.md` | State | Read-Write | PRD, sprint, NOTES outputs |
| `grimoires/loa/a2a/subagent-reports/` | State | Read-Write | Validator output |

---

## Component Design

### Component 1: Goal ID System (FR-1)

**Purpose:** Add explicit goal identifiers to PRD template and enable parsing.

**Changes to `prd-template.md`:**

```markdown
## Goals & Success Metrics

### Primary Goals

| ID | Goal | Measurement | Validation Method |
|----|------|-------------|-------------------|
| G-1 | {Goal 1 - specific and measurable} | {How to measure} | {How to validate} |
| G-2 | {Goal 2 - specific and measurable} | {How to measure} | {How to validate} |
| G-3 | {Goal 3 - specific and measurable} | {How to measure} | {How to validate} |
```

**Goal ID Format:**
- Pattern: `G-N` where N is positive integer
- Scope: Unique within PRD (not globally)
- Auto-assignment: Sprint planning assigns IDs if missing

**Parsing Logic (in planning-sprints skill):**

```bash
# Extract goal IDs from PRD
# If table has ID column, use those
# If not, auto-assign G-1, G-2, etc. based on goal order

# Regex pattern to match goal table rows
GOAL_PATTERN='^\| *G-[0-9]+ *\|'

# Check if PRD has explicit goal IDs
if grep -qE "${GOAL_PATTERN}" grimoires/loa/prd.md; then
    # Parse existing IDs
    GOALS=$(grep -E "${GOAL_PATTERN}" grimoires/loa/prd.md | awk -F'|' '{print $2}' | tr -d ' ')
else
    # Auto-assign IDs to prose goals
    # Count goals in "Primary Goals" section
    GOAL_COUNT=$(sed -n '/^### Primary Goals/,/^###/p' grimoires/loa/prd.md | grep -c '^[0-9]\.')
    # Generate G-1 through G-N
fi
```

**Backward Compatibility:**
- PRDs without goal IDs work normally
- Auto-assignment is informational (logged to trajectory)
- No errors thrown for missing IDs

---

### Component 2: Goal-Task Mapping (FR-2)

**Purpose:** Explicit mapping from goals to sprint tasks in Appendix C.

**Changes to `sprint-template.md`:**

```markdown
### C. PRD Goal Mapping

| Goal ID | Goal Description | Contributing Tasks | Validation Task |
|---------|------------------|-------------------|-----------------|
| G-1 | {From PRD} | Sprint 1: Task 1.1, Task 1.2 | Sprint N: Task N.5 |
| G-2 | {From PRD} | Sprint 2: Task 2.3 | Sprint N: Task N.5 |

**Goal Coverage Check:**
- [ ] All PRD goals have at least one contributing task
- [ ] All goals have a validation task in final sprint
- [ ] No orphan tasks (tasks not contributing to any goal)

**Per-Sprint Goal Contribution:**

Sprint 1: G-1 (partial: data model), G-2 (partial: API)
Sprint 2: G-1 (complete: integration), G-3 (complete: UI)
Sprint N: E2E validation of all goals
```

**Task Annotation Format:**

In each sprint's Technical Tasks section, append goal contribution:

```markdown
### Technical Tasks
- [ ] Task 1.1: Create timing data schema → **[G-1]**
- [ ] Task 1.2: Add timing columns to database → **[G-1]**
- [ ] Task 1.3: Create timing API endpoint → **[G-2]**
```

**Warning Generation:**

Planning skill generates warnings for:
1. Goals without any contributing tasks
2. Tasks not contributing to any goal
3. Missing E2E validation task in final sprint

```
⚠️ WARNING: Goal G-3 has no contributing tasks
⚠️ WARNING: Task 2.4 does not contribute to any goal
⚠️ WARNING: No E2E validation task found in final sprint
```

---

### Component 3: E2E Validation Task (FR-4)

**Purpose:** Auto-generate validation task in final sprint.

**E2E Validation Task Template:**

```markdown
### Task N.E2E: End-to-End Goal Validation

**Priority:** P0 (Must Complete)
**Goal Contribution:** All goals (G-1, G-2, G-3, ...)

**Description:**
Validate that all PRD goals are achieved through the complete implementation.

**Validation Steps:**

| Goal ID | Goal | Validation Action | Expected Result |
|---------|------|-------------------|-----------------|
| G-1 | {Goal description} | {Specific test/check} | {Pass criteria} |
| G-2 | {Goal description} | {Specific test/check} | {Pass criteria} |
| G-3 | {Goal description} | {Specific test/check} | {Pass criteria} |

**Acceptance Criteria:**
- [ ] Each goal validated with documented evidence
- [ ] Integration points verified (data flows end-to-end)
- [ ] No goal marked as "not achieved" without explicit justification
```

**Generation Logic:**

```python
# In planning-sprints skill, after all sprints defined:

def generate_e2e_task(goals, final_sprint_num):
    """Generate E2E validation task for final sprint."""

    validation_steps = []
    for goal in goals:
        validation_steps.append({
            "goal_id": goal.id,
            "goal_desc": goal.description,
            "validation_action": f"Verify {goal.measurement}",
            "expected_result": f"{goal.validation_method} passes"
        })

    return {
        "task_id": f"{final_sprint_num}.E2E",
        "title": "End-to-End Goal Validation",
        "priority": "P0",
        "goal_contribution": "All goals",
        "validation_steps": validation_steps
    }
```

---

### Component 4: Goal Validator Subagent (FR-5)

**Purpose:** Validate goal achievement during review phase.

**File:** `.claude/subagents/goal-validator.md`

```yaml
---
name: goal-validator
version: 1.0.0
description: Verify PRD goals are achieved through implementation
triggers:
  - after: implementing-tasks
  - before: reviewing-code (final sprint only)
  - command: /validate goals
severity_levels:
  - GOAL_ACHIEVED
  - GOAL_AT_RISK
  - GOAL_BLOCKED
output_path: grimoires/loa/a2a/subagent-reports/goal-validation-{date}.md
---

# Goal Validator

<objective>
Verify that sprint implementation contributes to PRD goal achievement.
For final sprint, verify all goals are achieved end-to-end.
</objective>

## Workflow

1. Load PRD from `grimoires/loa/prd.md`
2. Extract goals with IDs (G-1, G-2, etc.)
3. Load sprint plan from `grimoires/loa/sprint.md`
4. For each goal:
   a. Find contributing tasks
   b. Check task completion status
   c. Verify acceptance criteria met
   d. Check for integration gaps
5. Generate validation report
6. Return verdict

## Verdict Determination

| Verdict | Criteria |
|---------|----------|
| **GOAL_ACHIEVED** | All contributing tasks complete, acceptance criteria met, E2E validated |
| **GOAL_AT_RISK** | Tasks complete but validation uncertain or integration gaps detected |
| **GOAL_BLOCKED** | Contributing tasks incomplete or explicit blocker documented |

## Blocking Behavior

Configurable in `.loa.config.yaml`:

```yaml
goal_validation:
  block_on_at_risk: false  # Default: warn only
  block_on_blocked: true   # Default: always block
  require_e2e_task: true   # Default: require E2E task
```

- `GOAL_BLOCKED`: Always blocks `/review-sprint` approval
- `GOAL_AT_RISK`: Blocks only if `block_on_at_risk: true`
- `GOAL_ACHIEVED`: Proceed without issues

## Output Format

```markdown
## Goal Validation Report

**Date**: {date}
**Sprint**: {sprint-id}
**PRD Reference**: `grimoires/loa/prd.md`
**Verdict**: {GOAL_ACHIEVED | GOAL_AT_RISK | GOAL_BLOCKED}

---

### Goal Status Summary

| Goal ID | Goal | Status | Evidence |
|---------|------|--------|----------|
| G-1 | {description} | ✅ ACHIEVED | Task 1.1, 1.2 complete; E2E validated |
| G-2 | {description} | ⚠️ AT_RISK | Tasks complete; no E2E validation |
| G-3 | {description} | ❌ BLOCKED | Task 2.3 incomplete |

---

### Detailed Findings

#### G-1: {Goal Description}

**Status:** ACHIEVED
**Contributing Tasks:**
- [x] Sprint 1 Task 1.1 - Complete
- [x] Sprint 1 Task 1.2 - Complete
- [x] Sprint 2 Task 2.1 - Complete

**E2E Validation:**
- Verified via acceptance criteria check
- Integration confirmed: data flows from storage to API

#### G-2: {Goal Description}

**Status:** AT_RISK
**Contributing Tasks:**
- [x] Sprint 2 Task 2.3 - Complete

**Concern:**
- No E2E validation task exists
- [RECOMMENDATION] Add validation step to verify API returns expected data

---

### Recommendations

{Specific recommendations for addressing AT_RISK or BLOCKED goals}

---

*Generated by goal-validator v1.0.0*
```
```

---

### Component 5: Guided Workflow Command (FR-6)

**Purpose:** Interactive command guiding users through Loa workflow.

**File:** `.claude/commands/loa.md`

```yaml
---
command_type: wizard
description: Guided workflow command for Loa phases
output: Suggested next phase
---
```

```markdown
# /loa - Guided Workflow

## Purpose

Interactive workflow guide that detects current state and suggests the next step.

## Invocation

```
/loa
/loa --status   # Show status without prompting
```

## Workflow

1. Run `workflow-state.sh` to detect current state
2. Display workflow progress indicator
3. Suggest next command with explanation
4. Prompt user: [Y/n/exit]
5. Execute command or skip
6. Return to step 1 (unless exit)

## State Detection

The command uses `workflow-state.sh` to detect:

| State | Detection Logic | Next Step |
|-------|-----------------|-----------|
| No PRD | `! -f grimoires/loa/prd.md` | `/plan-and-analyze` |
| PRD only | PRD exists, no SDD | `/architect` |
| PRD + SDD | Both exist, no sprint plan | `/sprint-plan` |
| Sprint plan | Sprint plan exists | `/implement sprint-1` |
| In sprint | Sprint N in progress | `/review-sprint sprint-N` |
| Review feedback | Feedback exists, not "All good" | `/implement sprint-N` |
| Review approved | "All good" exists | `/audit-sprint sprint-N` |
| Audit approved | "APPROVED" exists | Next sprint or `/deploy-production` |
| Complete | All sprints done | "Workflow complete!" |

## Output Format

```
╔════════════════════════════════════════════════════════════════╗
║                    LOA WORKFLOW GUIDE                          ║
╠════════════════════════════════════════════════════════════════╣
║                                                                ║
║  Progress: [████████░░░░░░░░░░░░] 40%                          ║
║                                                                ║
║  Phase 1: /plan-and-analyze  ✓ Complete                       ║
║  Phase 2: /architect         ✓ Complete                       ║
║  Phase 3: /sprint-plan       ✓ Complete                       ║
║  Phase 4: /implement         ► In Progress (sprint-2)         ║
║  Phase 5: /review-sprint     ○ Pending                        ║
║  Phase 6: /audit-sprint      ○ Pending                        ║
║  Phase 7: /deploy-production ○ Pending                        ║
║                                                                ║
╠════════════════════════════════════════════════════════════════╣
║                                                                ║
║  SUGGESTED NEXT STEP:                                          ║
║                                                                ║
║  /implement sprint-2                                           ║
║                                                                ║
║  This will implement the tasks defined in Sprint 2 of your    ║
║  sprint plan, including the feature integration work.          ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝

Run /implement sprint-2? [Y/n/exit]:
```

## Exit Conditions

- User types 'exit' or 'q'
- User presses Ctrl+C
- Workflow is complete
- Error in state detection
```

**File:** `.claude/scripts/workflow-state.sh`

```bash
#!/usr/bin/env bash
# workflow-state.sh
# Purpose: Detect current Loa workflow state
# Usage: workflow-state.sh [--json]
#
# Exit codes:
#   0 - State detected successfully
#   1 - Error

set -euo pipefail

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
OUTPUT_FORMAT="${1:-text}"

# State detection
detect_state() {
    local state=""
    local current_sprint=""
    local progress=0

    # Check PRD
    if [[ ! -f "${PROJECT_ROOT}/grimoires/loa/prd.md" ]]; then
        state="no_prd"
        progress=0
    # Check SDD
    elif [[ ! -f "${PROJECT_ROOT}/grimoires/loa/sdd.md" ]]; then
        state="prd_only"
        progress=14
    # Check Sprint Plan
    elif [[ ! -f "${PROJECT_ROOT}/grimoires/loa/sprint.md" ]]; then
        state="prd_sdd"
        progress=28
    else
        # Sprint plan exists - determine sprint status
        # Find highest sprint number in plan
        local max_sprint=$(grep -oP 'Sprint \K[0-9]+' "${PROJECT_ROOT}/grimoires/loa/sprint.md" | sort -n | tail -1)

        # Find current sprint by checking a2a directories
        for ((i=1; i<=max_sprint; i++)); do
            local sprint_dir="${PROJECT_ROOT}/grimoires/loa/a2a/sprint-${i}"

            if [[ -f "${sprint_dir}/COMPLETED" ]]; then
                # Sprint completed
                continue
            elif [[ -f "${sprint_dir}/auditor-sprint-feedback.md" ]]; then
                # Audit exists - check status
                if grep -q "APPROVED" "${sprint_dir}/auditor-sprint-feedback.md" 2>/dev/null; then
                    continue  # Approved, check next sprint
                else
                    state="audit_feedback"
                    current_sprint="${i}"
                    break
                fi
            elif [[ -f "${sprint_dir}/engineer-feedback.md" ]]; then
                # Review exists - check status
                if grep -q "All good" "${sprint_dir}/engineer-feedback.md" 2>/dev/null; then
                    state="review_approved"
                    current_sprint="${i}"
                    break
                else
                    state="review_feedback"
                    current_sprint="${i}"
                    break
                fi
            elif [[ -f "${sprint_dir}/reviewer.md" ]]; then
                state="ready_for_review"
                current_sprint="${i}"
                break
            else
                state="in_sprint"
                current_sprint="${i}"
                break
            fi
        done

        # If all sprints completed
        if [[ -z "${state}" ]]; then
            state="complete"
            progress=100
        else
            # Calculate progress based on sprint and phase
            local sprint_weight=$((42 / max_sprint))  # 42% for implementation phase
            local base_progress=42  # After sprint plan

            case "${state}" in
                in_sprint)
                    progress=$((base_progress + (current_sprint - 1) * sprint_weight))
                    ;;
                ready_for_review|review_feedback)
                    progress=$((base_progress + current_sprint * sprint_weight - sprint_weight / 2))
                    ;;
                review_approved|audit_feedback)
                    progress=$((base_progress + current_sprint * sprint_weight - sprint_weight / 4))
                    ;;
            esac
        fi
    fi

    # Output
    if [[ "${OUTPUT_FORMAT}" == "--json" ]]; then
        echo "{\"state\":\"${state}\",\"sprint\":\"${current_sprint}\",\"progress\":${progress}}"
    else
        echo "STATE=${state}"
        echo "SPRINT=${current_sprint}"
        echo "PROGRESS=${progress}"
    fi
}

detect_state
```

---

### Component 6: NOTES.md Goal Status (FR-7)

**Purpose:** Track goal status across sprints in structured memory.

**Changes to `NOTES.md.template`:**

Add new section after "Technical Debt":

```markdown
## Goal Status

<!-- Track PRD goal progress across sprints -->
<!-- Update at: sprint completion, goal status change -->

| Goal ID | Goal Description | Status | Last Updated | Notes |
|---------|------------------|--------|--------------|-------|
| G-1 | {From PRD} | 🟡 PARTIAL | YYYY-MM-DD | Sprint 1 complete, Sprint 2 pending |
| G-2 | {From PRD} | 🟢 ACHIEVED | YYYY-MM-DD | Validated in Sprint 2 |
| G-3 | {From PRD} | 🔴 BLOCKED | YYYY-MM-DD | Blocker: API dependency |

**Status Legend:**
- 🟢 ACHIEVED - Goal fully validated
- 🟡 PARTIAL - Some contributing tasks complete
- 🔴 BLOCKED - Cannot progress (blocker documented)
- ⬜ NOT_STARTED - No contributing tasks complete
```

---

## Data Architecture

### Goal Tracking Data Model

```
grimoires/loa/
├── prd.md                          # Goals defined (G-1, G-2)
│   └── Goals section with ID column
├── sdd.md                          # Architecture decisions
├── sprint.md                       # Goal mapping (Appendix C)
│   ├── Appendix A: PRD Feature Mapping
│   ├── Appendix B: SDD Component Mapping
│   └── Appendix C: PRD Goal Mapping (NEW)
├── NOTES.md                        # Goal Status section (NEW)
└── a2a/
    ├── subagent-reports/
    │   └── goal-validation-{date}.md  # Validator output (NEW)
    └── sprint-N/
        ├── reviewer.md             # Implementation report
        ├── engineer-feedback.md    # Review feedback
        └── auditor-sprint-feedback.md # Audit feedback
```

### Goal State Machine

```
                   ┌─────────────────────────────────────┐
                   │                                     │
                   ▼                                     │
              NOT_STARTED                                │
                   │                                     │
                   │ First contributing task started     │
                   ▼                                     │
              PARTIAL ◄────────────────────────┐        │
                   │                           │        │
                   │ All tasks complete        │        │
                   │ OR E2E validated          │        │ Blocker added
                   ▼                           │        │
              ACHIEVED                    New task      │
                                          discovered    │
                   ▲                           │        │
                   │                           │        │
              BLOCKED ─────────────────────────┴────────┘
                   │ Blocker resolved
                   │
                   └───► PARTIAL
```

---

## Integration Points

### Skill Integration

| Skill | Integration Point | Change |
|-------|-------------------|--------|
| `discovering-requirements` | PRD generation | Use goal ID template |
| `planning-sprints` | Sprint generation | Generate Appendix C, E2E task |
| `implementing-tasks` | Task execution | Reference goal contributions |
| `reviewing-code` | Review workflow | Invoke goal-validator |

### Script Integration

| Script | Integration Point | Change |
|--------|-------------------|--------|
| `suggest-next-step.sh` | Workflow chaining | Add `/loa` support |
| `workflow-state.sh` | State detection | New script |
| `preflight.sh` | Pre-command validation | Check goal configuration |

### Command Integration

| Command | Integration Point | Change |
|---------|-------------------|--------|
| `/plan-and-analyze` | PRD creation | No change (template updated) |
| `/sprint-plan` | Sprint creation | Generate goal mapping |
| `/implement` | Task execution | No change (template updated) |
| `/review-sprint` | Review workflow | Invoke goal-validator |
| `/validate goals` | Manual validation | New command variant |
| `/loa` | Guided workflow | New command |

---

## Security Considerations

### No New Attack Surface

This feature adds no new security considerations:

- No external network calls
- No credential handling
- No file system access outside existing zones
- Read-only access to PRD/sprint files
- Write access only to State Zone (existing)

### Zone Compliance

All new components follow existing zone model:
- System Zone: Templates, subagent, scripts (read-only)
- State Zone: Goal validation reports, NOTES.md updates (read-write)

---

## Testing Strategy

### Unit Tests

| Component | Test | Location |
|-----------|------|----------|
| Goal ID parsing | Parse PRD with/without IDs | `tests/goal-parsing.bats` |
| Appendix C generation | Generate mapping from goals | `tests/goal-mapping.bats` |
| E2E task generation | Generate validation task | `tests/e2e-task.bats` |
| Workflow state detection | Detect all states | `tests/workflow-state.bats` |

### Integration Tests

| Scenario | Test |
|----------|------|
| Full workflow with goals | PRD → Sprint → Implement → Review with goal validation |
| Backward compatibility | Existing PRD without goal IDs works normally |
| Goal validator blocking | AT_RISK blocks when configured |

### Manual Validation

| Scenario | Steps |
|----------|-------|
| Goal traceability flow | 1. Create PRD with goals 2. Run /sprint-plan 3. Verify Appendix C 4. Implement 5. Review with goal validation |
| /loa guided workflow | 1. Start fresh repo 2. Run /loa 3. Follow prompts through workflow |

---

## Implementation Order

### Sprint 1: Goal Foundation (MVP Core)

**Tasks:**

1. **Update PRD template** - Add Goal ID column
2. **Update sprint template** - Add Appendix C, task annotations
3. **Update planning-sprints skill** - Generate goal mapping, E2E task
4. **Write goal ID parsing logic** - Extract/auto-assign goal IDs

**Deliverables:**
- PRD template with Goal ID column
- Sprint template with Appendix C
- Goal mapping generation in planning skill
- E2E validation task auto-generation

### Sprint 2: Goal Validation (MVP Complete)

**Tasks:**

1. **Create goal-validator subagent** - Following architecture-validator pattern
2. **Integrate into reviewing-code skill** - Invoke before approval
3. **Add configuration options** - `.loa.config.yaml` settings
4. **Update NOTES.md template** - Add Goal Status section

**Deliverables:**
- Goal validator subagent
- Review workflow integration
- Configuration options
- NOTES.md goal tracking

### Sprint 3: Guided Workflow (Fast Follow)

**Tasks:**

1. **Create workflow-state.sh** - State detection script
2. **Create /loa command** - Guided workflow wizard
3. **Integration with suggest-next-step.sh** - Leverage existing infrastructure
4. **Documentation updates** - CLAUDE.md, README.md

**Deliverables:**
- Workflow state detection
- /loa guided command
- Complete documentation

---

## Rollback Plan

### Feature Flags

All new features can be disabled via `.loa.config.yaml`:

```yaml
goal_traceability:
  enabled: true              # Master toggle
  require_goal_ids: false    # Don't require IDs (backward compat)
  generate_appendix_c: true  # Generate goal mapping
  generate_e2e_task: true    # Auto-generate E2E task

goal_validation:
  enabled: true              # Run goal validator
  block_on_at_risk: false    # Warn only on AT_RISK
  block_on_blocked: true     # Block on BLOCKED
```

### Rollback Steps

1. **Disable features** - Set `goal_traceability.enabled: false`
2. **Template rollback** - Templates are backward compatible (ID column optional)
3. **Skill rollback** - Skills check feature flags before generating goal content

### Data Migration

No migration needed:
- Existing PRDs work without goal IDs
- Existing sprint plans work without Appendix C
- All features are additive, not destructive

---

## Appendix

### A. Configuration Schema

```yaml
# .loa.config.yaml additions

goal_traceability:
  enabled: true                    # Enable goal traceability features
  require_goal_ids: false          # Require explicit goal IDs in PRD
  auto_assign_ids: true            # Auto-assign IDs if missing
  generate_appendix_c: true        # Generate goal mapping in sprint plan
  generate_e2e_task: true          # Auto-generate E2E validation task
  warn_unmapped_goals: true        # Warn if goals have no tasks
  warn_unmapped_tasks: false       # Warn if tasks map to no goals

goal_validation:
  enabled: true                    # Run goal validator during review
  block_on_at_risk: false          # Block approval on AT_RISK (default: warn)
  block_on_blocked: true           # Block approval on BLOCKED
  require_e2e_validation: true     # Require E2E task in final sprint

guided_workflow:
  enabled: true                    # Enable /loa command
  auto_execute: false              # Auto-execute suggestions (default: prompt)
  show_progress: true              # Show progress indicator
```

### B. Goal ID Regex Patterns

```bash
# Goal ID extraction
GOAL_ID_PATTERN='G-[0-9]+'

# Goal table row (with ID)
GOAL_TABLE_ROW='^\| *G-[0-9]+ *\|'

# Task with goal annotation
TASK_GOAL_ANNOTATION='\*\*\[G-[0-9]+(, *G-[0-9]+)*\]\*\*'
```

### C. Subagent Invocation

Goal validator follows existing subagent invocation protocol:

```bash
# Manual invocation
/validate goals

# Automatic invocation (in reviewing-code skill)
# After acceptance criteria check, before approval
```

---

*Generated by Software Architect Agent*
