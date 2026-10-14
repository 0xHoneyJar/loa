# run-mode render templates (cycle-121 split from SKILL.md)

Verbatim PR bodies, report boxes, and rendering steps referenced by pointer from SKILL.md. Reproduce blocks EXACTLY as written (placeholders in {braces} resolve from .run state).

## sprint-plan-incomplete-pr-body

```
## Run Mode Sprint Plan - INCOMPLETE

### Status: HALTED

Sprint plan execution stopped at **{failed_sprint}**.

**Reason:** {reason}

### Completed Sprints
{list_completed_sprints}

### Remaining Sprints
{list_remaining_sprints}

### Metrics
- Total cycles: {jq '.metrics.total_cycles' .run/sprint-plan-state.json}
- Files changed: {jq '.metrics.total_files_changed' .run/sprint-plan-state.json}
- Findings fixed: {jq '.metrics.total_findings_fixed' .run/sprint-plan-state.json}

### Flatline Review Summary (v1.22.0)
{generate_flatline_summary — see below}

{generate_deleted_tree — see "Deleted Files Tracking"}

---
:warning: **INCOMPLETE** - Use `/run-resume` to continue

:robot: Generated autonomously with Run Mode
```

## completion-pr-body

```
## 🚀 Run Mode: Sprint Plan Complete

### Summary

| Metric | Value |
|--------|-------|
| **Sprints Completed** | {sprints.completed} |
| **Total Cycles** | {metrics.total_cycles} |
| **Files Changed** | {metrics.total_files_changed} |
| **Findings Fixed** | {metrics.total_findings_fixed} |

### Sprint Breakdown

| Sprint | Status | Cycles | Files Changed |
|--------|--------|--------|---------------|
{sprint table from step 2}

{deleted files tree — see "Deleted Files Tracking"}

### Commits by Sprint

{commits-by-sprint from step 3}

### Flatline Review Summary (v1.22.0)
{flatline summary from step 4}

### Test Results
All tests passing (verified by /audit-sprint for each sprint).

### Context Cleanup
Discovery context cleaned and ready for next cycle.

---
🤖 Generated autonomously with Run Mode
```

## flatline-summary-steps


1. If `.flatline/runs/` doesn't exist: emit `_No Flatline reviews executed during this run._` and
   stop.
2. Find manifests newer than the state file:
   `find .flatline/runs -name "*.json" -newer .run/sprint-plan-state.json`. If none: same as step 1.
3. For each manifest, read `.phase`, `.metrics.high_consensus`, `.metrics.disputed`,
   `.metrics.blockers`, `.status` via `jq -r`. Accumulate totals; build a row
   `| PHASE | high | disputed | blockers | ✅ or ⚠️ |`.
4. Emit the table (`| Phase | HIGH | DISPUTED | BLOCKER | Status |` header) then
   `**Totals:** {total_high} integrated, {total_disputed} disputed (logged), {total_blockers} blockers`.
5. If `total_disputed > 0`: emit a `<details>` block listing each disputed item from
   `.flatline/runs/{run_id}-disputed.json` (`.[] | "- **{id}**: {description} (delta: {delta})"`).
6. If `total_high > 0`: append the rollback hint:
   `` `.claude/scripts/flatline-rollback.sh run --run-id <run_id> --dry-run` ``.

## local-mode-report

```
[COMPLETE] Sprint implementation finished (LOCAL MODE)

Changes committed to local branch: {branch}
Total commits: {commits}
Files changed: {files}

⚠️  LOCAL MODE: No push or PR created.

To push manually when ready:
  git push -u origin {branch}

To create PR:
  gh pr create --draft
```

## prompt-declined-report

```
[COMPLETE] Sprint implementation finished

Changes committed to local branch: {branch}
Total commits: {commits}
Files changed: {files}

ℹ️  Push skipped at your request.

To push when ready:
  git push -u origin {branch}

To create PR:
  gh pr create --draft
```

## auto-mode-pr-body

```
## Run Mode Autonomous Implementation

### Summary
- **Target:** {target}
- **Cycles:** {cycles.current}
- **Files Changed:** {metrics.files_changed}
- **Commits:** {metrics.commits}
- **Findings Fixed:** {metrics.findings_fixed}

{deleted files tree}

### Test Results
All tests passing (verified by /audit-sprint).

---
🤖 Generated autonomously with Run Mode
```

## run-status-box

```
╔══════════════════════════════════════════════════════════════╗
║                    RUN MODE STATUS                            ║
╠══════════════════════════════════════════════════════════════╣
║ Run ID:    {run_id}
║ State:     {state}
║ Target:    {target}
║ Branch:    {branch}
╠══════════════════════════════════════════════════════════════╣
║ PROGRESS
║ ─────────────────────────────────────────────────────────────
║ Cycle:     {current} / {limit}
║ Phase:     {phase}
║ Runtime:   {runtime} / {timeout_hours}h 00m
╠══════════════════════════════════════════════════════════════╣
║ METRICS
║ ─────────────────────────────────────────────────────────────
║ Files changed:   {files_changed}
║ Files deleted:   {files_deleted}
║ Commits:         {commits}
║ Findings fixed:  {findings_fixed}
╠══════════════════════════════════════════════════════════════╣
║ CIRCUIT BREAKER: {cb_state}
║ ─────────────────────────────────────────────────────────────
║ Same issue:      {same}/{same_threshold}
║ No progress:     {no_progress}/{no_progress_threshold}
║ Cycle count:     {current}/{limit}
║ Timeout:         {runtime} / {timeout_hours}h 00m
╚══════════════════════════════════════════════════════════════╝
```

## halt-incomplete-pr-body

```
## Run Mode Implementation - INCOMPLETE

### Status: HALTED

**Run ID:** {run_id}
**Target:** {target}
**Halt Reason:** {reason}

### Progress at Halt
- Cycles completed: {cycles.current}
- Files changed: {metrics.files_changed}
- Findings fixed: {metrics.findings_fixed}

### Cycle History
```
{jq -r '.cycles.history[] | "Cycle \(.cycle): \(.phase) - \(.findings) findings"' .run/state.json}
```

{deleted files tree}

---
:warning: **INCOMPLETE** - This PR represents partial work.

### To Resume
```
/run-resume
```

### To Abandon
```
rm -rf .run/
git branch -D {branch}
```

:robot: Generated autonomously with Run Mode
```

## halt-summary-box

```
╔══════════════════════════════════════════════════════════════╗
║                    RUN HALTED                                 ║
╠══════════════════════════════════════════════════════════════╣
║ Run ID:    {run_id}
║ Target:    {target}
║ Branch:    {branch}
║ Reason:    {reason}
╠══════════════════════════════════════════════════════════════╣
║ State preserved in .run/
║
║ To resume:
║   /run-resume
║
║ To reset circuit breaker and resume:
║   /run-resume --reset-ice
║
║ To abandon:
║   rm -rf .run/
╚══════════════════════════════════════════════════════════════╝
```

## bug-pr-body

```
## Bug Fix: {bug_title}

**Bug ID**: {bug_id}
**Source**: /run --bug

### Confidence Signals
- Reproduction: {strong/weak/manual_only}
- Test type: {unit/integration/e2e/contract}
- Files changed: {N}
- Lines changed: {N}
- Risk level: {low/medium/high}

### Artifacts
- Triage: grimoires/loa/a2a/bug-{id}/triage.md
- Review: grimoires/loa/a2a/bug-{id}/reviewer.md
- Audit: grimoires/loa/a2a/bug-{id}/auditor-sprint-feedback.md

### Status: READY FOR HUMAN REVIEW
This PR was created by `/run --bug` autonomous mode.
Please review before merging.
```

## high-risk-area-detection

### High-Risk Area Detection

Checked against suspected files during triage (Phase 3): `auth, authentication, login, password,
token, jwt, oauth, payment, billing, charge, stripe, checkout, migration, schema, database, db,
encrypt, decrypt, secret, credential, key`.

| Mode | Risk Level | Behavior |
|------|-----------|----------|
| Interactive | high | WARN: display risk, ask confirmation |
| Autonomous | high (no `--allow-high`) | **HALT**: require `--allow-high` |
| Autonomous | high (`--allow-high`) | Proceed with `risk_level: high` in PR |
| Any | low/medium | Proceed normally |


