---
name: goal-validator
version: 1.0.0
description: Verify PRD goals are achieved through implementation
context: fork
agent: Explore
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
4. Load current sprint's implementation report
5. For each goal:
   a. Find contributing tasks from Appendix C
   b. Check task completion status
   c. Verify acceptance criteria met
   d. Check for integration gaps
6. Generate validation report
7. Return verdict

## Goal Extraction

Parse goals from PRD's Goals section:

```
# If PRD has goal table with ID column:
| ID | Goal | Measurement | Validation Method |
|----|------|-------------|-------------------|
| G-1 | ... | ... | ... |

# Extract: goal_id, goal_description, measurement, validation_method
```

If PRD uses numbered list format without IDs:
- Auto-assign G-1, G-2, G-3 based on order
- Log: `[INFO] Auto-assigned goal IDs: G-1, G-2, G-3`

## Task Completion Check

For each goal, find contributing tasks from sprint.md Appendix C:

```
| Goal ID | Goal Description | Contributing Tasks | Validation Task |
|---------|------------------|-------------------|-----------------|
| G-1 | ... | Sprint 1: Task 1.1, Task 1.2 | Sprint 3: Task 3.E2E |
```

Check completion by:
1. Reading sprint.md task checkboxes
2. Reading implementation report (reviewer.md)
3. Verifying acceptance criteria are checked

## Verdict Determination

| Verdict | Criteria |
|---------|----------|
| **GOAL_ACHIEVED** | All contributing tasks complete, acceptance criteria met, E2E validated (if applicable) |
| **GOAL_AT_RISK** | Tasks complete but: validation uncertain, missing E2E task, or integration gaps detected |
| **GOAL_BLOCKED** | Contributing tasks incomplete OR explicit blocker documented in NOTES.md |

### Overall Verdict Logic

```
if any goal is BLOCKED:
    overall = GOAL_BLOCKED
elif any goal is AT_RISK:
    overall = GOAL_AT_RISK
else:
    overall = GOAL_ACHIEVED
```

## Blocking Behavior

Configurable in `.loa.config.yaml`:

```yaml
goal_validation:
  enabled: true              # Master toggle
  block_on_at_risk: false    # Default: warn only
  block_on_blocked: true     # Default: always block
  require_e2e_task: true     # Default: require E2E task in final sprint
```

- `GOAL_BLOCKED`: Always blocks `/review-sprint` approval
- `GOAL_AT_RISK`: Blocks only if `block_on_at_risk: true`
- `GOAL_ACHIEVED`: Proceed without issues

## Integration Gap Detection

Check for producer-consumer patterns:

1. **New Data without Consumer:**
   - Search for new database columns/tables (CREATE TABLE, ALTER TABLE ADD)
   - Search for read operations on that data
   - If no consumers found: flag as integration gap

2. **New API without Caller:**
   - Search for new endpoints (@Get, @Post, router definitions)
   - Search for API calls to those endpoints
   - If no callers found: flag as integration gap

Integration gaps elevate goal status to AT_RISK unless marked intentional.

## Output Format

Write report to `grimoires/loa/a2a/subagent-reports/goal-validation-{date}.md`:

```markdown
## Goal Validation Report

**Date**: {YYYY-MM-DD}
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

---

#### G-2: {Goal Description}

**Status:** AT_RISK
**Contributing Tasks:**
- [x] Sprint 2 Task 2.3 - Complete

**Concern:**
- No E2E validation task exists
- [RECOMMENDATION] Add validation step to verify API returns expected data

---

### Integration Gap Analysis

| Pattern | Found | Consumer | Status |
|---------|-------|----------|--------|
| timing_columns table | ✅ | calculate_score() | ✅ Connected |
| /api/timing endpoint | ✅ | None found | ⚠️ GAP |

---

### Recommendations

1. {Specific recommendation for addressing AT_RISK goals}
2. {Specific recommendation for integration gaps}

---

*Generated by goal-validator v1.0.0*
```

## Example Invocations

```bash
# Manual invocation via /validate command
/validate goals

# Automatic invocation during review (final sprint)
# Triggered by reviewing-code skill before approval

# Scoped to specific sprint
/validate goals sprint-3
```

## Integration with Review Workflow

The reviewing-code skill should:

1. Check if this is the final sprint (all sprints complete after this)
2. If final sprint, invoke goal-validator before approval
3. Check verdict:
   - GOAL_BLOCKED: Write feedback requiring goal fixes
   - GOAL_AT_RISK: Warn in feedback (or block if configured)
   - GOAL_ACHIEVED: Proceed with standard review

## Backward Compatibility

- If PRD has no goal IDs: auto-assign and continue
- If sprint has no Appendix C: warn but don't block
- If goal_validation disabled in config: skip entirely

## JIT Retrieval Pattern

Follow the JIT retrieval protocol to avoid eager loading of full files:

### Lightweight Identifiers

Store references, not content:

```
# Instead of loading full files:
| Identifier | Purpose | Last Verified |
|------------|---------|---------------|
| ${PROJECT_ROOT}/grimoires/loa/prd.md:L90-110 | Goal definitions | HH:MM:SSZ |
| ${PROJECT_ROOT}/grimoires/loa/sprint.md:L300-350 | Appendix C | HH:MM:SSZ |
```

### On-Demand Retrieval

Load content only when needed for verification:

```bash
# Use ck for semantic search if available
if command -v ck &>/dev/null; then
  ck --hybrid "G-1 contributing tasks" grimoires/loa/sprint.md --top-k 5
else
  grep -n "G-1" grimoires/loa/sprint.md
fi
```

## Semantic Cache Integration

Cache goal validation results to avoid redundant computation across sessions:

### Cache Key Generation

```bash
# Generate cache key from validation parameters
cache_key=$(.claude/scripts/cache-manager.sh generate-key \
  --paths "grimoires/loa/prd.md,grimoires/loa/sprint.md" \
  --query "goal-validation" \
  --operation "goal-validator")
```

### Cache Check Before Validation

```bash
# Check cache first (mtime-based invalidation handles freshness)
if cached=$(.claude/scripts/cache-manager.sh get --key "$cache_key"); then
  # Cache hit - use cached verdict if files unchanged
  echo "Using cached goal validation: $cached"
else
  # Cache miss - perform full validation
  # ... run validation workflow ...

  # Condense and cache result
  condensed=$(.claude/scripts/condense.sh condense \
    --strategy structured_verdict \
    --input <(echo "$validation_result"))

  .claude/scripts/cache-manager.sh set \
    --key "$cache_key" \
    --condensed "$condensed" \
    --sources "grimoires/loa/prd.md,grimoires/loa/sprint.md"
fi
```

### Condensed Verdict Format

```json
{
  "verdict": "GOAL_AT_RISK",
  "goals": {
    "G-1": "ACHIEVED",
    "G-2": "AT_RISK",
    "G-3": "ACHIEVED"
  },
  "concerns": ["G-2: No E2E validation task"],
  "report_path": "grimoires/loa/a2a/subagent-reports/goal-validation-2026-01-23.md"
}
```

## Beads Workflow (beads_rust)

When beads_rust (`br`) is installed, use it to track goal validation:

### Session Start

```bash
br sync --import-only  # Import latest state from JSONL
```

### Recording Goal Validation Results

```bash
# Create validation finding as issue (if gaps found)
if [[ "$verdict" == "GOAL_AT_RISK" ]] || [[ "$verdict" == "GOAL_BLOCKED" ]]; then
  br create --title "Goal validation: $verdict" \
    --type task \
    --priority 1 \
    --json
fi

# Add goal status labels to sprint epic
br label add <sprint-epic-id> "goal-validation:$verdict"
```

### Using Labels for Goal Status

| Label | Meaning | When to Apply |
|-------|---------|---------------|
| `goal-validation:achieved` | All goals met | After GOAL_ACHIEVED verdict |
| `goal-validation:at-risk` | Needs attention | After GOAL_AT_RISK verdict |
| `goal-validation:blocked` | Sprint blocked | After GOAL_BLOCKED verdict |
| `needs-e2e-validation` | Missing E2E task | When E2E task not found |

### Session End

```bash
br sync --flush-only  # Export SQLite → JSONL before commit
```

**Protocol Reference**: See `.claude/protocols/beads-integration.md`

## Truth Hierarchy Compliance

Goal validation follows the Lossless Ledger truth hierarchy:

```
1. CODE (src/)           ← Check actual implementation exists
2. BEADS (.beads/)       ← Track validation state across sessions
3. NOTES.md              ← Log decisions, update Goal Status section
4. TRAJECTORY            ← Record validation reasoning
5. PRD/SDD               ← Source of goal definitions
```

### Fork Detection

If NOTES.md Goal Status conflicts with validation results:
1. **Validation wins** - Fresh analysis is authoritative
2. **Flag the fork** - Log discrepancy to trajectory
3. **Update NOTES.md** - Resync Goal Status section
