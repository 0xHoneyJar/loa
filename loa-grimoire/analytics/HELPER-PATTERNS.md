# Analytics Helper Patterns

> Reusable patterns for updating analytics across all Loa commands.
> All patterns are non-blocking - failures are logged but don't stop the main workflow.

## Core Principles

1. **Non-blocking**: Analytics failures never stop the main workflow
2. **Safe injection**: Always use `jq --arg` for variable injection (prevents injection attacks)
3. **Graceful degradation**: Handle missing/corrupt files gracefully
4. **Regenerate summary**: Always regenerate summary.md after any usage.json update

---

## Pattern 1: Safe Read with Fallback

Read usage.json safely, handling missing or corrupt files:

```bash
# Read analytics file with fallback
ANALYTICS_FILE="loa-grimoire/analytics/usage.json"
if [ -f "$ANALYTICS_FILE" ]; then
  # Validate JSON before using
  if jq empty "$ANALYTICS_FILE" 2>/dev/null; then
    ANALYTICS_VALID=true
  else
    echo "Warning: Analytics file is corrupt, skipping analytics update"
    ANALYTICS_VALID=false
  fi
else
  echo "Warning: Analytics file not found, skipping analytics update"
  ANALYTICS_VALID=false
fi
```

---

## Pattern 2: Increment Counter

Increment a numeric counter safely:

```bash
# Increment commands_executed counter
jq '.totals.commands_executed += 1' "$ANALYTICS_FILE" > "$ANALYTICS_FILE.tmp" && \
  mv "$ANALYTICS_FILE.tmp" "$ANALYTICS_FILE"
```

---

## Pattern 3: Mark Phase Complete

Mark a phase as complete with timestamp:

```bash
# Mark PRD phase complete
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
jq --arg ts "$TIMESTAMP" '.phases.prd.completed_at = $ts' "$ANALYTICS_FILE" > "$ANALYTICS_FILE.tmp" && \
  mv "$ANALYTICS_FILE.tmp" "$ANALYTICS_FILE"
```

---

## Pattern 4: Update Sprint Iteration

Find or create sprint entry and increment iteration counter:

```bash
# Update sprint implementation iteration
SPRINT_NAME="sprint-1"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Check if sprint exists, create if not, then increment
jq --arg name "$SPRINT_NAME" --arg ts "$TIMESTAMP" '
  if (.sprints | map(.name) | index($name)) then
    .sprints |= map(if .name == $name then .implementation_iterations += 1 | .last_updated = $ts else . end)
  else
    .sprints += [{
      "name": $name,
      "implementation_iterations": 1,
      "review_iterations": 0,
      "audit_iterations": 0,
      "completed": false,
      "started_at": $ts,
      "completed_at": null,
      "last_updated": $ts
    }]
  end
' "$ANALYTICS_FILE" > "$ANALYTICS_FILE.tmp" && mv "$ANALYTICS_FILE.tmp" "$ANALYTICS_FILE"
```

---

## Pattern 5: Complete Analytics Update Block

Full non-blocking analytics update with all safety checks:

```bash
# === ANALYTICS UPDATE (NON-BLOCKING) ===
(
  ANALYTICS_FILE="loa-grimoire/analytics/usage.json"

  # Skip if file doesn't exist or is invalid
  if [ ! -f "$ANALYTICS_FILE" ] || ! jq empty "$ANALYTICS_FILE" 2>/dev/null; then
    echo "Analytics: Skipped (file missing or invalid)"
    exit 0
  fi

  # Perform update (example: mark PRD complete)
  TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  jq --arg ts "$TIMESTAMP" '
    .phases.prd.completed_at = $ts |
    .totals.phases_completed += 1 |
    .totals.commands_executed += 1
  ' "$ANALYTICS_FILE" > "$ANALYTICS_FILE.tmp" && mv "$ANALYTICS_FILE.tmp" "$ANALYTICS_FILE"

  echo "Analytics: Updated successfully"
) || echo "Analytics: Update failed (non-blocking)"
# === END ANALYTICS UPDATE ===
```

---

## Pattern 6: Summary Regeneration

Regenerate summary.md from usage.json after every analytics update.

### Summary Format (from SDD Section 4.2.4)

The summary.md file should be regenerated with the following structure:

```markdown
# Loa Usage Analytics Summary

> Auto-generated summary of framework usage for the current project.

## Project Overview

| Field | Value |
|-------|-------|
| Project Name | {project_name or "*Not yet configured*"} |
| Framework Version | {framework_version} |
| Developer | {developer.git_user_name or "*Not yet configured*"} |
| Setup Completed | {Yes/No based on setup.completed_at} |

## Phase Progress

| Phase | Status | Started | Completed | Duration |
|-------|--------|---------|-----------|----------|
| PRD | {Complete/In Progress/Not started} | {date or -} | {date or -} | {calculated or -} |
| SDD | {Complete/In Progress/Not started} | {date or -} | {date or -} | {calculated or -} |
| Sprint Planning | {Complete/In Progress/Not started} | {date or -} | {date or -} | {calculated or -} |

## Sprint Summary

| Sprint | Impl | Reviews | Audits | Status |
|--------|------|---------|--------|--------|
| {for each sprint in sprints array} |
| sprint-1 | 2 | 1 | 1 | Complete |
| sprint-2 | 1 | 0 | 0 | In Progress |
| *No sprints recorded* | - | - | - | - | (if empty)

## Totals

| Metric | Count |
|--------|-------|
| Commands Executed | {totals.commands_executed} |
| Phases Completed | {totals.phases_completed} |
| Sprints Completed | {totals.sprints_completed} |
| Reviews Completed | {totals.reviews_completed} |
| Audits Completed | {totals.audits_completed} |
| Feedback Submitted | {Yes/No} |

## MCP Servers Configured

{List each from setup.mcp_servers_configured, or "*None configured yet*"}

---

*Last updated: {current ISO timestamp}*
*Schema version: {schema_version}*
```

### Regeneration Logic

After updating usage.json, regenerate summary.md by:

1. **Read usage.json** and parse the JSON
2. **Extract values** with graceful fallbacks for missing data
3. **Calculate derived values**:
   - Duration = completed_at - started_at (if both exist)
   - Sprint status = "Complete" if completed=true, else "In Progress" if started_at, else "Not started"
4. **Format dates** as YYYY-MM-DD for display
5. **Write summary.md** with the template above

### Handling Missing/Partial Data

- Missing project_name → "*Not yet configured*"
- Missing developer info → "*Not yet configured*"
- Empty sprints array → Show "No sprints recorded" row
- Missing timestamps → Show "-"
- Null values → Show appropriate placeholder

### Implementation Notes

The summary regeneration should be done by the agent inline after each analytics update. The agent should:

1. Read the updated usage.json
2. Extract the relevant fields
3. Generate the markdown using the template format
4. Write to loa-grimoire/analytics/summary.md

This is a simple read-transform-write operation that doesn't require bash scripting - the agent can do it directly using file read/write operations.

---

## Usage in Commands

Each command should include analytics update logic at the appropriate completion point:

| Command | Analytics Update Point | Fields Updated |
|---------|----------------------|----------------|
| /setup | After marker file created | setup.completed_at, setup.mcp_servers_configured |
| /plan-and-analyze | After PRD saved | phases.prd.completed_at, totals.phases_completed |
| /architect | After SDD saved | phases.sdd.completed_at, totals.phases_completed |
| /sprint-plan | After sprint.md saved | phases.sprint_planning.completed_at, totals.phases_completed |
| /implement | After report generated | sprints[].implementation_iterations |
| /review-sprint | After feedback written | sprints[].review_iterations (via reviews array) |
| /audit-sprint | After audit complete | sprints[].audit_iterations (via audits array) |
| /deploy-production | After deployment complete | deployments[], totals |
| /feedback | After submission | totals.feedback_submitted |

---

## Security Notes (from Sprint 1 Audit)

1. **Always use `--arg` for variable injection**: Never interpolate shell variables directly into jq filters
2. **Validate JSON before write**: The `> tmp && mv tmp orig` pattern ensures atomic writes
3. **Handle corrupt files gracefully**: Check with `jq empty` before processing
4. **Non-blocking by design**: Wrap in subshell with `|| echo "failed"` fallback

---

*Created: Sprint 3 Implementation*
*Last updated: 2025-12-19*
