---
name: run
description: "Autonomous sprint execution mode"
role: review
primary_role: review
capabilities:
  schema_version: 1
  read_files: true
  search_code: true
  write_files: true
  execute_commands: true
  web_access: true
  user_interaction: true
  agent_spawn: true
  task_management: true
cost-profile: unbounded
---

## Cost

**Estimated per invocation**: Run Mode itself is low-cost (orchestration only). Cost comes from the sub-skills it invokes: Flatline Protocol (~$15–25/planning cycle), Bridgebuilder review (~$10–20/run), and implementation sessions (see [Cost Matrix](../../../docs/CONFIG_REFERENCE.md#cost-matrix)).
**External providers called**: None directly — delegates to Flatline (Opus 4.7 + GPT-5.3-codex) and Bridgebuilder (Opus 4.7 + GPT-5.3-codex) when those features are enabled.
**To cap spend**: Set `run_mode.defaults.max_cycles` and `hounfour.metering.budget.daily_micro_usd` in `.loa.config.yaml`. Budget enforcement is active when `hounfour.metering.enabled: true`.
**If cost is a concern**: Run `/loa setup` — the wizard will guide you to a budget-appropriate configuration.

<input_guardrails>
## Pre-Execution Guardrails (mechanized — cycle-119)

Skip this section entirely when `.loa.config.yaml` has `guardrails.input.enabled: false` or env
`LOA_GUARDRAILS_ENABLED=false`.

Otherwise: write the user's invocation prompt/args to a temp file (Write tool), then run
`.claude/scripts/guardrails-orchestrator.sh --skill run-mode --mode ${LOA_RUN_MODE:-interactive} --file <temp-file>`

| Outcome | Action |
|---------|--------|
| JSON `action: "BLOCK"` | HALT; report the script's `reason` to the user |
| JSON `action: "PROCEED"` or `"WARN"` | Continue (logging is handled by the script) |
| Script missing, non-zero exit, or unparseable output | Continue — fail-open, preserving pre-cycle-119 semantics |

Never pass prompt text as a bash argv (quote-blindness FP class) — always via `--file`.

**Skill-specific danger-level gating** (run-mode remains a **high** danger-level skill — autonomous
execution — this is additive on top of the orchestrator call above):

1. Before each skill invocation inside the run loop (`/implement`, `/review-sprint`, `/audit-sprint`,
   red-team, post-PR phases), run
   `.claude/scripts/danger-level-enforcer.sh --skill <invoked-skill> --mode autonomous`.
2. Result table: `PROCEED` → execute the skill; `WARN` → execute with enhanced trajectory logging;
   `BLOCK` → skip the skill invocation, log to trajectory, treat as a cycle with zero progress.
3. Override: `--allow-high` on the `/run` invocation permits high-risk skills that would otherwise
   `BLOCK` (e.g. `/run --bug "..." --allow-high` for high-risk-area bug fixes; see Bug Run Mode below).
4. In Interactive mode (not autonomous run-mode itself, but a nested interactive confirmation),
   require explicit user confirmation instead of BLOCK.
</input_guardrails>

# Run Mode Skill

You are an autonomous implementation agent. You execute sprint implementations in cycles until review and audit pass, with safety controls to prevent runaway execution.

This skill is the single source of truth for all `/run`, `/run sprint-plan`, `/run-status`,
`/run-halt`, and `/run-resume` behavior. Those commands are thin routers — see their files under
`.claude/commands/` for argument parsing only; execution logic lives here.

## Core Behavior

**State Machine:**
```
READY → JACK_IN → RUNNING → COMPLETE/HALTED → JACKED_OUT
```

## `/run <target>` — Pre-flight Checks (Jack-In)

Before any execution begins, perform these checks in order. Any failure halts before state is
created (`exit 1` semantics — report the error and stop, do not create `.run/`):

1. **Configuration check**: read `run_mode.enabled` via
   `yq '.run_mode.enabled // false' .loa.config.yaml`. If not `true`: HALT —
   "Run Mode not enabled. Set `run_mode.enabled: true` in `.loa.config.yaml`".
2. **Beads-first check** (autonomous mode requires beads by default, v1.29.0): run
   `.claude/scripts/beads/beads-health.sh --quick --json` and read `.status`. If `status` is
   neither `HEALTHY` nor `DEGRADED`, read `yq '.beads.autonomous.requires_beads // true' .loa.config.yaml`.
   If that resolves `true` (and `LOA_BEADS_AUTONOMOUS_OVERRIDE` is not `true`): HALT with —
   "Autonomous mode requires beads (status: `$status`). Install: `cargo install beads_rust && br init`.
   Override (not recommended): set `beads.autonomous.requires_beads: false` or
   `export LOA_BEADS_AUTONOMOUS_OVERRIDE=true`." Otherwise proceed. Either way, call
   `.claude/scripts/beads/update-beads-state.sh --health "$status"` to record the observed health.
3. **Branch safety**: run `.claude/scripts/run-mode-ice.sh validate` to confirm the current branch
   is not protected. Non-zero exit → HALT and surface the script's message.
4. **Permission check**: run `.claude/scripts/check-permissions.sh --quiet`. Non-zero exit → HALT.
5. **State check**: if `.run/state.json` exists, read `.state` via `jq -r '.state' .run/state.json`.
   If it is `RUNNING`: HALT — "Run already in progress. Use `/run-halt` or `/run-resume`."

## Initialization

Once pre-flight passes, initialize the run:

1. `mkdir -p .run`.
2. Generate `run_id="run-$(date +%Y%m%d)-$(openssl rand -hex 4)"` and an ISO-8601 `timestamp`
   (`date -u +"%Y-%m-%dT%H:%M:%SZ"`).
3. Resolve the initial push mode via ICE (single source of truth — never compute push mode
   independently): `--local` flag → `run-mode-ice.sh should-push local`; `--confirm-push` flag →
   `run-mode-ice.sh should-push prompt`; neither → `run-mode-ice.sh should-push`.
4. Write `.run/state.json` with this exact schema (fill in the resolved values):
   ```json
   {
     "run_id": "run-20260119-abc123",
     "target": "sprint-1",
     "branch": "feature/sprint-1",
     "state": "JACK_IN",
     "phase": "INIT",
     "timestamps": {
       "started": "2026-01-19T10:00:00Z",
       "last_activity": "2026-01-19T11:30:00Z"
     },
     "cycles": {
       "current": 0,
       "limit": 20,
       "history": []
     },
     "metrics": {
       "files_changed": 0,
       "files_deleted": 0,
       "commits": 0,
       "findings_fixed": 0
     },
     "options": {
       "max_cycles": 20,
       "timeout_hours": 8,
       "dry_run": false,
       "local_mode": false,
       "confirm_push": false,
       "push_mode": "AUTO"
     },
     "completion": {
       "pushed": false,
       "pr_created": false,
       "pr_url": null,
       "skipped_reason": null
     }
   }
   ```
5. Write `.run/circuit-breaker.json` with this exact schema:
   ```json
   {
     "state": "CLOSED",
     "triggers": {
       "same_issue": {"count": 0, "threshold": 3, "last_hash": null},
       "no_progress": {"count": 0, "threshold": 5},
       "cycle_count": {"current": 0, "limit": 20},
       "timeout": {"started": "2026-01-19T10:00:00Z", "limit_hours": 8}
     },
     "history": []
   }
   ```
6. `touch .run/deleted-files.log` (empty).
7. Create/checkout the feature branch via `.claude/scripts/run-mode-ice.sh ensure-branch "$target"`.

All subsequent `.run/*.json` mutations in this skill MUST use the atomic write pattern: pipe the
`jq` transform to a `.tmp` sibling, then `mv` the `.tmp` file over the original — never edit the
JSON file in place.

## Main Loop — Single Sprint (`/run sprint-N`)

```
while circuit_breaker.state == CLOSED:
  1. /implement $target
  2. Commit changes, then track deletions (see "Deleted Files Tracking" below)
  3. update_state(phase: REVIEW)
  4. /review-sprint $target
  5. If engineer-feedback.md has findings → record_cycle(findings), check circuit breaker
     (see "Circuit Breaker" below); on trip, HALT; else continue loop (back to step 1)
  6. update_state(phase: AUDIT)
  7. /audit-sprint $target
  8. If auditor-sprint-feedback.md has findings → same as step 5
  9. RED_TEAM_CODE gate (if enabled) — see below
  10. If COMPLETED marker exists → update_state(state: COMPLETE); break
Create draft PR (see "Completion and PR Creation")
Invoke Post-PR Validation (if enabled)
Update state to READY_FOR_HITL or JACKED_OUT
```

Call `check_rate_limit` (see "Rate Limiting" below) before each of steps 1, 4, and 7.

### RED_TEAM_CODE gate

1. Check `red_team.code_vs_design.enabled == true` in `.loa.config.yaml`.
2. Check SDD exists at `grimoires/loa/sdd.md` (or apply `skip_if_no_sdd` behavior — see table below).
3. Invoke:
   ```
   .claude/scripts/red-team-code-vs-design.sh \
     --sdd grimoires/loa/sdd.md \
     --diff - \              # pipe git diff main...HEAD
     --output grimoires/loa/a2a/sprint-{N}/red-team-code-findings.json \
     --sprint sprint-{N} \
     --prior-findings grimoires/loa/a2a/sprint-{N}/engineer-feedback.md \
     --prior-findings grimoires/loa/a2a/sprint-{N}/auditor-sprint-feedback.md
   ```
   Pass `--prior-findings` paths only when the file exists — this is the "Deliberative Council"
   pattern: the Red Team gate sees what reviewer/auditor already found, avoiding duplicate analysis.
4. Parse output `summary.actionable` count (CONFIRMED_DIVERGENCE above `severity_threshold`).
5. If `actionable > 0`: increment `red_team_code.cycles` in `.run/state.json`. If
   `red_team_code.cycles >= red_team_code.max_cycles` (default 2): log WARNING "Red Team
   code-vs-design max cycles reached, skipping" and continue to COMPLETE. Else: continue the main
   loop (back to `/implement`).
6. If `actionable == 0`: continue to COMPLETE.

| Setting | Default | Description |
|---------|---------|--------------|
| `red_team.code_vs_design.max_cycles` | 2 | Max re-implementation cycles triggered by divergence findings |
| `red_team.code_vs_design.severity_threshold` | 700 | Only CONFIRMED_DIVERGENCE findings above this severity trigger re-implementation |
| `skip_if_no_sdd: true` | — | No SDD → skip gate silently |
| `skip_if_no_sdd: false` | — | No SDD → error and HALT |

State tracked in `.run/state.json`:
```json
{
  "red_team_code": {
    "cycles": 0,
    "max_cycles": 2,
    "findings_total": 0,
    "divergences_found": 0,
    "last_findings_hash": null
  }
}
```

### Post-PR Validation (v1.25.0)

After PR creation, check `post_pr_validation.enabled` in `.loa.config.yaml`:
- `true`: invoke `.claude/scripts/post-pr-orchestrator.sh --pr-url <url> --mode autonomous`.
  Exit 0 → state = `READY_FOR_HITL`. Exit 2-5 (HALTED) → state = `HALTED`, create `[INCOMPLETE]`
  PR note.
- `false`: state = `JACKED_OUT`.

The orchestrator's phase sequence: `POST_PR_AUDIT` (consolidated PR audit + fix loop) →
`CONTEXT_CLEAR` (checkpoint + prompt user to `/clear`) → `E2E_TESTING` (fresh-eyes testing + fix
loop) → `FLATLINE_PR` (optional multi-model review, ~$1.50) → `READY_FOR_HITL`. Full spec:
`grimoires/loa/prd-post-pr-validation.md`.

## Circuit Breaker

Four triggers checked, in this order, against `.run/circuit-breaker.json`:

| Trigger | Default Threshold | Check |
|---------|-------------------|-------|
| Same Issue | 3 | `jq '.triggers.same_issue.count' .run/circuit-breaker.json` ≥ threshold |
| No Progress | 5 | `jq '.triggers.no_progress.count' .run/circuit-breaker.json` ≥ threshold |
| Cycle Limit | 20 | `jq '.triggers.cycle_count.current' .run/circuit-breaker.json` ≥ limit |
| Timeout | 8 hours | `$(($(date +%s) - $(date -d "$(jq -r '.triggers.timeout.started' .run/circuit-breaker.json)" +%s)))` ≥ `limit_hours * 3600` |

On the first trigger that fires, trip the breaker:
1. Atomically update `.run/circuit-breaker.json`:
   `jq --arg t "$trigger" --arg r "$reason" --arg ts "$timestamp" '.state = "OPEN" | .history += [{"timestamp": $ts, "trigger": $t, "reason": $r}]'`.
2. Atomically update `.run/state.json`: `jq '.state = "HALTED"'`.
3. Report: "CIRCUIT BREAKER TRIPPED: $reason" then "Run halted. Use `/run-resume --reset-ice` to
   continue."

### Issue Hash Tracking (Same-Issue trigger)

1. After each `/review-sprint` or `/audit-sprint`, compute a hash of the findings section:
   `grep -A 100 "## Findings\|## Issues\|## Changes Required" <feedback-file> | head -50 | md5sum | cut -d' ' -f1`
   (or `echo "none"` if the feedback file doesn't exist).
2. Read `last_hash` via `jq -r '.triggers.same_issue.last_hash // "none"' .run/circuit-breaker.json`.
3. If the new hash equals `last_hash` and is not `"none"`: increment count
   (`jq '.triggers.same_issue.count += 1'`). Otherwise: reset — set count to 1 and
   `last_hash` to the new hash in one `jq` call.

### Red Team Code-vs-Design Circuit Breaker

Separate counter from the main circuit breaker (see RED_TEAM_CODE gate above for behavior).

## Sprint Plan Execution Loop (`/run sprint-plan`)

### Sprint Discovery

Try each source in priority order; use the first that returns non-empty:

1. **Priority 1 — `sprint.md` sections**: `grep -E "^## Sprint [0-9]+:" grimoires/loa/sprint.md | sed 's/## Sprint \([0-9]*\):.*/sprint-\1/' | sort -t'-' -k2 -n`.
2. **Priority 2 — `ledger.json`**: read `active_cycle` via
   `jq -r '.active_cycle' grimoires/loa/ledger.json`, then
   `jq -r --arg cycle "$active_cycle" '.cycles[] | select(.id == $cycle) | .sprints[] | .local_label' grimoires/loa/ledger.json`.
3. **Priority 3 — a2a directories**: `find grimoires/loa/a2a -maxdepth 1 -type d -name "sprint-*" | sed 's|.*/||' | sort -t'-' -k2 -n`.
4. If all three are empty: HALT — "No sprints found".

### Pre-flight

Same 5 checks as `/run` above (steps 1-5), plus: after the state check, run sprint discovery
(above); if empty, HALT — "No sprints discovered". Otherwise report the discovered sprint list.

### Main Loop

```
initialize_sprint_plan_state()
for sprint in filtered_sprints (apply --from/--to: keep sprint N iff from <= N <= to):
  1. Check .run/sprint-plan-state.json for sprint already "completed" → skip
  2. Run the single-sprint main loop above for this sprint (max_cycles, timeout from options)
  3. COMPLETE → continue to next sprint; HALTED → break outer loop, preserve state
  4. Update .run/sprint-plan-state.json (mark sprint completed, advance current, roll up metrics)
create_plan_pr()
update_state(state: JACKED_OUT)
```

State file `.run/sprint-plan-state.json` schema:
```json
{
  "plan_id": "plan-20260119-abc123",
  "branch": "feature/release",
  "state": "RUNNING",
  "timestamps": {"started": "2026-01-19T10:00:00Z", "last_activity": "2026-01-19T14:30:00Z"},
  "sprints": {
    "total": 4,
    "completed": 2,
    "current": "sprint-3",
    "list": [
      {"id": "sprint-1", "status": "completed", "cycles": 2},
      {"id": "sprint-2", "status": "completed", "cycles": 3},
      {"id": "sprint-3", "status": "in_progress", "cycles": 1},
      {"id": "sprint-4", "status": "pending"}
    ]
  },
  "options": {"from": 1, "to": 4, "max_cycles": 20, "timeout_hours": 8},
  "metrics": {"total_cycles": 6, "total_files_changed": 45, "total_findings_fixed": 12}
}
```

### Sprint Failure Handling

On a HALTED sprint inside the plan loop:
1. Atomically update `.run/sprint-plan-state.json`:
   `jq --arg s "$failed_sprint" --arg r "$reason" '.state = "HALTED" | .failure = {"sprint": $s, "reason": $r, "timestamp": (now | strftime("%Y-%m-%dT%H:%M:%SZ"))}'`.
2. Create the incomplete PR (template below) via
   `.claude/scripts/run-mode-ice.sh pr-create "[INCOMPLETE] Run Mode: Sprint Plan" "$body" --draft`.
3. Report: "Sprint plan halted at $failed_sprint / Reason: $reason / Use `/run-resume` to continue
   from this point."

Incomplete PR body template:
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

### Completion PR (Consolidated, default v1.15.1)

1. Clean the context directory: `.claude/scripts/cleanup-context.sh --verbose` (archives
   `grimoires/loa/context/` to `{archive-path}/context/` then removes everything except
   `README.md`; archive location priority: active cycle's `archive_path` in `ledger.json` → most
   recent archived cycle's path → most recent `grimoires/loa/archive/20*` → fallback dated dir).
2. Build the sprint table: for each entry in `.run/sprint-plan-state.json` `.sprints.list[]`, emit
   a row `| id | ✅ Complete or ⏳ status | cycles | files_changed or - |`.
3. Build the commits-by-sprint section: for each sprint id, print `#### {id}: {title}` then
   `git log --oneline --grep="({sprint_id})"` reformatted as `- \`{hash}\` {message}` bullets.
4. Build the Flatline summary (see below).
5. Assemble the PR body:
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
6. Create the draft PR: `.claude/scripts/run-mode-ice.sh pr-create "Run Mode: Sprint Plan implementation" "$body" --draft`.

### Flatline Summary Generation

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

## Deleted Files Tracking

Log file: `.run/deleted-files.log`, format `file_path|sprint|cycle` (one line per deleted file).

1. After each commit in the main loop, collect deletions:
   `git diff --name-status HEAD~1 HEAD | grep "^D" | cut -f2`, and append
   `{file}|{sprint}|{cycle}` per file to `.run/deleted-files.log`.
2. To render the tree for a PR body: if the log is missing or empty, emit
   "No files deleted during this run." Otherwise:
   - Count lines: `wc -l < .run/deleted-files.log`.
   - Emit header `## 🗑️ DELETED FILES - REVIEW CAREFULLY`, then `**Total: {count} files deleted**`.
   - Inside a fenced code block, for each unique file (`cut -d'|' -f1 .../deleted-files.log | sort`),
     print `{dirname}/` then `└── {basename} ({sprint}, {cycle})` (metadata via
     `grep "^$file|" | cut -d'|' -f2,3`).
   - Close the fence, then append `> ⚠️ These deletions are intentional but please verify they are correct.`

## Completion and PR Creation (v1.30.0)

### Push Mode Resolution

Priority: `--local` > `--confirm-push` > config > default (`AUTO`). Delegate entirely to ICE as
the single source of truth:
- `--local` → `run-mode-ice.sh should-push local`
- `--confirm-push` → `run-mode-ice.sh should-push prompt`
- neither → `run-mode-ice.sh should-push` (reads `run_mode.git.auto_push` from config: `true` →
  `AUTO`, `false` → `LOCAL`, `prompt` → `PROMPT`; default `true`)

Record the resolved mode: `jq --arg mode "$push_mode" '.options.push_mode = $mode'` on
`.run/state.json`.

### LOCAL mode

1. Atomically set on `.run/state.json`:
   `.completion = {"pushed": false, "pr_created": false, "pr_url": null, "skipped_reason": "local_mode"} | .state = "JACKED_OUT"`.
2. Report:
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

### PROMPT mode

1. Display the same summary (branch/commits/files) and use the `AskUserQuestion` tool with two
   options: "Push and create PR" (proceeds to AUTO-mode flow below) or "Keep local only" (declined
   flow). `AskUserQuestion` is invoked by Claude directly — no bash equivalent.
2. Declined flow: same atomic update as LOCAL mode but `skipped_reason: "user_declined"`, and
   report:
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

### AUTO mode

1. Push: `.claude/scripts/run-mode-ice.sh push origin "$branch"`.
2. Build the PR body:
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
3. Create the draft PR: `pr_url=$(.claude/scripts/run-mode-ice.sh pr-create "Run Mode: $target implementation" "$body")`.
4. Atomically set: `.completion = {"pushed": true, "pr_created": true, "pr_url": $url, "skipped_reason": null} | .state = "JACKED_OUT"`.
5. Report: "[COMPLETE] All checks passed! ✓ PR created: $pr_url" then "[JACKED_OUT] Run complete."

## Rate Limiting

Tracks API calls per hour. File: `.run/rate-limit.json`:
```json
{"hour_boundary": "2026-01-19T10:00:00Z", "calls_this_hour": 45, "limit": 100, "waits": []}
```

Read the configured limit via `yq '.run_mode.rate_limiting.calls_per_hour // 100' .loa.config.yaml`.
Default 100 calls/hour.

Before each phase (`/implement`, `/review-sprint`, `/audit-sprint`), check the rate limit:

1. If `.run/rate-limit.json` doesn't exist, initialize it with `hour_boundary` = current hour
   (`date -u +"%Y-%m-%dT%H:00:00Z"`), `calls_this_hour: 0`, `limit` from config.
2. If the stored `hour_boundary` differs from the current hour, reset: set `hour_boundary` to the
   current hour and `calls_this_hour` to 0 (single `jq` call).
3. If `calls_this_hour >= limit`: this is a rate-limit wait (see below). Otherwise increment
   `calls_this_hour` by 1 and proceed.

### Rate-limit wait (replaces prior "Sleep (in real implementation...)" placeholder)

Do **not** call a fixed-duration `sleep` and hope the wait matches. Compute the wait window, then
poll with a bounded until-loop per `.claude/protocols/agent-ergonomics.md` item 1:

```bash
wait_seconds=$(( $(date -d "$hour_boundary" +%s) + 3600 - $(date +%s) + 60 ))  # +60s buffer
until [[ $(date +%s) -ge $(( $(date -d "$hour_boundary" +%s) + 3600 )) ]]; do sleep 2; done
```

Or, when running under the harness, use the Monitor tool to wait on the elapsed-time condition
instead of a bash poll loop. Record the wait in `.run/rate-limit.json`:
`jq --arg ts "$timestamp" --argjson w "$wait_seconds" '.waits += [{"timestamp": $ts, "wait_seconds": $w}]'`,
and set `.phase = "RATE_LIMITED"` on `.run/state.json`. Report the estimated wait in minutes and
that the run auto-resumes when the limit resets.

If `wait_seconds > 3600`: warn the user that the run will be automatically suspended, state is
preserved in `.run/`, and after the limit resets they should resume with `/run-resume`.

## `/run-status` — Display Progress

1. If `.run/state.json` doesn't exist: report "No run in progress. Start a new run with `/run
   sprint-N` or `/run sprint-plan`."
2. Otherwise read: `run_id`, `state`, `target`, `branch`, `phase` from `.run/state.json`; compute
   runtime as `elapsed = now_seconds - $(date -d "$started" +%s)`, formatted `{h}h {m}m`; read
   circuit-breaker counts/thresholds from `.run/circuit-breaker.json`; read metrics
   (`files_changed`, `files_deleted`, `commits`, `findings_fixed`) from `.run/state.json`.
3. Render the standard box report:
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
4. `--json`: emit
   `jq -s '{"run": .[0], "circuit_breaker": .[1], "computed": {"runtime_seconds": (now - (.[0].timestamps.started | fromdateiso8601)), "timeout_remaining_seconds": ((.[0].options.timeout_hours * 3600) - (now - (.[0].timestamps.started | fromdateiso8601)))}}' .run/state.json .run/circuit-breaker.json`.
   If no state file: emit `{"status": "no_run_in_progress"}`.
5. `--verbose`: after the standard report, also print:
   - `=== Cycle History ===` via
     `jq -r '.cycles.history[] | "Cycle \(.cycle): \(.phase) - \(.findings) findings, \(.files_changed) files"' .run/state.json`
   - `=== Circuit Breaker History ===` — if `.history | length == 0`, print "No circuit breaker
     trips"; else `jq -r '.history[] | "[\(.timestamp)] \(.trigger): \(.reason)"' .run/circuit-breaker.json`
   - `=== Deleted Files ===` — `cat .run/deleted-files.log` if non-empty, else "No files deleted"
6. Sprint plan variant: when `.run/sprint-plan-state.json` exists (in addition to or instead of
   `state.json`), render the equivalent box with Plan ID, per-sprint checklist (`[✓]`/`[→]`/`[ ]`
   with cycle counts), a percentage-complete line, and TOTAL METRICS section instead of the single
   run's METRICS/CIRCUIT BREAKER sections.

Reference tables — state indicators (`JACK_IN`→Initializing, `RUNNING`→Running, `HALTED`→HALTED,
`COMPLETE`→Complete, `JACKED_OUT`→Finished); phase indicators (`INIT`→Initializing,
`IMPLEMENT`→Implementing, `REVIEW`→In Review, `AUDIT`→In Audit); circuit breaker states
(`CLOSED`→CLOSED, `OPEN`→OPEN, manual intervention needed).

## `/run-halt` — Graceful Stop

### Pre-flight

1. If `.run/state.json` doesn't exist: "ERROR: No run in progress. Nothing to halt." → exit.
2. Read `.state`. If `JACKED_OUT`: "ERROR: Run already completed" → exit. If `HALTED`: "Run is
   already halted. Use `/run-resume` to continue or clean up with `rm -rf .run/`" → exit 0.

### Execution

1. Read `run_id`, `target`, `branch`, `phase` from `.run/state.json`; report them plus the halt
   reason (default `"Manual halt"`, or the `--reason` value).
2. If `--force`: warn "current phase interrupted" and skip step 3's phase-completion wait.
3. Otherwise, note phase-completion status per the current `phase`: `IMPLEMENT` → "Implementation
   phase safe to halt" (already committed in cycles); `REVIEW` → "Review can be resumed"; `AUDIT`
   → "Audit can be resumed".
4. Commit pending changes: if `git diff --quiet && git diff --staged --quiet` (nothing pending),
   report "No pending changes to commit" and skip. Otherwise `git add -A` then commit with:
   ```
   WIP: Run halted - {reason}

   This commit contains work-in-progress from an interrupted Run Mode session.
   Use /run-resume to continue from this point.

   Run ID: {run_id}
   Target: {target}
   Cycle: {cycles.current}
   Phase: {phase}
   ```
5. Push: `.claude/scripts/run-mode-ice.sh push origin "$branch"`.
6. Create or update the incomplete PR. Check for an existing PR first:
   `gh pr list --head "$branch" --json number -q '.[0].number'`. If found, `gh pr edit $number
   --title "[INCOMPLETE] Run Mode: $target" --body "$body"`; else
   `.claude/scripts/run-mode-ice.sh pr-create "[INCOMPLETE] Run Mode: $target" "$body" --draft`.
   PR body template:
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
7. Update state atomically: `jq --arg r "$reason" --arg ts "$timestamp" '.state = "HALTED" | .halt = {"reason": $r, "timestamp": $ts} | .timestamps.last_activity = $ts'`.
8. Report the halt summary box:
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

## `/run-resume` — Continue From Checkpoint

### Pre-flight

1. If `.run/state.json` doesn't exist: "ERROR: No run state found. Start a new run with `/run
   sprint-N`" → exit 1.
2. Read `.state`. If not `HALTED`: "ERROR: Run is not halted (state: {state})" — if `RUNNING`, add
   "Run is already in progress. Use `/run-status` to check."; if `JACKED_OUT`, add "Run is already
   complete. Start a new run with `/run sprint-N`." → exit 1.
3. Compare `git branch --show-current` against `.branch` in state. Mismatch → "ERROR: Branch
   mismatch / Expected: {expected} / Current: {current} / Checkout the correct branch: `git
   checkout {expected}`" → exit 1.
4. Unless `--force`: check branch divergence —
   `git fetch origin "$branch" 2>&1` (never redirect stash/git diagnostic output to `/dev/null`
   per `.claude/rules/stash-safety.md`'s spirit — surface fetch failures), then compare
   `git rev-parse HEAD` against `git rev-parse "origin/$branch"`. Same → fine. If
   `git merge-base --is-ancestor "origin/$branch" HEAD` succeeds (local ahead) → fine. Otherwise
   diverged: "ERROR: Branch has diverged from remote / Local: {local} / Remote: {remote} / This
   can happen if someone else pushed, or you made changes outside Run Mode. / To force resume: `/run-resume --force`.
   / To sync first: `git pull --rebase origin {branch}`" → exit 1.
5. If `.run/circuit-breaker.json` exists and `.state == "OPEN"` and `--reset-ice` was not passed:
   show the last trip (`jq '.history[-1]'` → trigger/reason/timestamp) and instruct: "To reset and
   continue: `/run-resume --reset-ice`. To continue without reset (may halt again): `/run-resume
   --force`." → exit 1.

### Resume Execution

1. Read `run_id`, `target`, `phase`, `cycles.current` from `.run/state.json`; report them.
2. If `--reset-ice`: reset the circuit breaker —
   `jq --arg ts "$timestamp" '.state = "CLOSED" | .triggers.same_issue.count = 0 | .triggers.same_issue.last_hash = null | .triggers.no_progress.count = 0 | .triggers.cycle_count.current = 0 | .triggers.timeout.started = $ts'`
   on `.run/circuit-breaker.json`.
3. Update `.run/state.json` atomically: `.state = "RUNNING" | del(.halt) | .timestamps.last_activity = $ts`.
4. Report "✓ State updated to RUNNING" then resume the main loop at the recorded `phase`:
   `INIT` → restart from initialization; `IMPLEMENT` → re-run `/implement $target` then continue
   the loop; `REVIEW` → re-run `/review-sprint $target` then continue; `AUDIT` → re-run
   `/audit-sprint $target` then continue; unknown phase → start from `IMPLEMENT`.

## ICE (Intrusion Countermeasures Electronics)

All git operations MUST go through the ICE wrapper: `.claude/scripts/run-mode-ice.sh <command> [args]`.

ICE enforces: never push to protected branches (main, master, staging, etc.); never merge (blocked
entirely); never delete branches (blocked); always create draft PRs (never ready for review).

Subcommands used by this skill: `validate`, `ensure-branch`, `checkout`, `push`, `push-upstream`,
`should-push [local|prompt]`, `pr-create`.

## State Files Reference

All state in `.run/`:

| File | Purpose |
|------|---------|
| `state.json` | Run progress, metrics, options |
| `sprint-plan-state.json` | Sprint plan progress (for `/run sprint-plan`) |
| `circuit-breaker.json` | Trigger counts, history |
| `deleted-files.log` | Tracked deletions for PR |
| `rate-limit.json` | API call tracking |

## Bug Run Mode (`/run --bug`)

Autonomous bug fixing with triage → implement → review → audit cycle.

```
/run --bug "Login fails when email contains + character"
/run --bug --from-issue 42
/run --bug "description" --allow-high
```

### Bug Run Loop

```
/run --bug "description"
       ▼
  TRIAGE       Invoke bug-triaging skill → triage.md, micro-sprint
       ▼
  IMPLEMENT    /implement sprint-bug-{N}   (test-first: write test → fix → verify)
       ▼
  REVIEW       /review-sprint sprint-bug-{N}   — findings → back to IMPLEMENT
       ▼
  AUDIT        /audit-sprint sprint-bug-{N}    — findings → back to IMPLEMENT
       ▼
  COMPLETE     COMPLETED marker + draft PR
```

### Bug Run Execution

1. **Pre-flight**: same as standard run (config check, ICE, permissions).
2. **Branch**: create `bugfix/{bug_id}` via ICE.
3. **Triage**: invoke `/bug` with the description or `--from-issue N` (passes the issue number to
   bug-triaging). Produces `triage.md` and a micro-sprint under `grimoires/loa/a2a/bug-{id}/`.
4. **High-risk check**: read `risk_level` from bug state. If `high` and `--allow-high` not set →
   HALT: "High-risk area detected (auth/payment/migration). Use --allow-high to proceed."
5. **Implementation loop**: same shape as the standard main loop but with the bug-scoped circuit
   breaker (below), targeting `sprint-bug-{N}`.
6. **Completion**: draft PR with confidence signals (below).

### Bug-Scoped Circuit Breaker

Tighter limits (bug scope is smaller), stored in `.run/bugs/{bug_id}/circuit-breaker.json`
(namespaced per bug):

| Trigger | Limit | Rationale |
|---------|-------|-----------|
| Same Issue | 3 cycles | Bug fix shouldn't need >3 review cycles |
| No Progress | 5 cycles | If no file changes, bug may be misdiagnosed |
| Cycle Limit | 10 total | Reduced from 20 (smaller scope) |
| Timeout | 2 hours | Reduced from 8 (smaller scope) |

### Bug State File

Per-bug namespaced state in `.run/bugs/{bug_id}/state.json`:
```json
{
  "schema_version": 1,
  "bug_id": "20260211-a3f2b1",
  "bug_title": "Login fails with + in email",
  "sprint_id": "sprint-bug-3",
  "state": "IMPLEMENTING",
  "mode": "autonomous",
  "created_at": "2026-02-11T10:00:00Z",
  "updated_at": "2026-02-11T10:30:00Z",
  "circuit_breaker": {
    "cycle_count": 1,
    "same_issue_count": 0,
    "no_progress_count": 0,
    "last_finding_hash": null
  },
  "confidence": {
    "reproduction_strength": "strong",
    "test_type": "unit",
    "risk_level": "low",
    "files_changed": 3,
    "lines_changed": 42
  }
}
```

Allowed state transitions (reject anything else):
```
TRIAGE → IMPLEMENTING       (triage complete)
IMPLEMENTING → REVIEWING    (implementation complete)
REVIEWING → IMPLEMENTING    (review found issues)
REVIEWING → AUDITING        (review passed)
AUDITING → IMPLEMENTING     (audit found issues)
AUDITING → COMPLETED        (audit passed)
ANY → HALTED                (circuit breaker or manual halt)
```

### Bug PR Creation (Confidence Signals)

On completion, create a draft PR via ICE:
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
**CRITICAL**: Bug PRs are ALWAYS draft. Never auto-merged. Human approval required.

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

## Safety Model

**4-Level Defense in Depth:**
1. **ICE Layer**: Git operations wrapped with safety checks
2. **Circuit Breaker**: Automatic halt on repeated failures
3. **Opt-In**: Requires explicit `run_mode.enabled: true`
4. **Visibility**: Draft PRs, deleted file tracking, metrics

**Human in the Loop**: shifted from phase checkpoints to PR review — all work visible in draft PR,
deleted files prominently displayed, clear audit trail in cycle history.

## Configuration

```yaml
run_mode:
  enabled: true  # Required to use /run
  defaults:
    max_cycles: 20
    timeout_hours: 8
  rate_limiting:
    calls_per_hour: 100
  circuit_breaker:
    same_issue_threshold: 3
    no_progress_threshold: 5
  git:
    branch_prefix: "feature/"
    create_draft_pr: true
    auto_push: true    # true | false | prompt
    base_branch: "main"                     # Branch to diff against (git-aware sync fallback)
    sprint_commit_pattern: '^feat\(sprint-' # grep -E pattern for sprint commits
  sprint_plan:
    branch_prefix: "feature/"
    default_branch_name: "release"
    consolidate_pr: true           # Create single PR for all sprints (default)
    commit_prefix: "feat"          # Prefix for sprint commits
    include_commits_by_sprint: true  # Group commits by sprint in PR
```

| Setting | Behavior |
|---------|----------|
| `run_mode.git.auto_push: true` | Push and create PR automatically (default) |
| `run_mode.git.auto_push: false` | Never auto-push (like always using `--local`) |
| `run_mode.git.auto_push: prompt` | Always ask before push (like always using `--confirm-push`) |

**Priority**: `--local` flag > `--confirm-push` flag > config setting > default (`true`)

## Error Recovery

On any error: state is preserved in `.run/`. Use `/run-status` to see current state, `/run-resume`
to continue, `/run-resume --reset-ice` if the circuit breaker tripped, or `rm -rf .run/` to start
fresh.

### Git-Aware State Sync (cycle-056, Issue #474)

When context compaction or session loss leaves `.run/sprint-plan-state.json` stuck at
`state: "RUNNING"` with `0` completed sprints — even though git history shows all sprint commits
already landed — `simstim-orchestrator.sh --sync-run-mode` cross-references git as a secondary
source of truth before returning `still_running`.

**When the fallback fires** (all three must hold):
1. `sprint-plan-state.json` shows `state: "RUNNING"` (the normal trigger)
2. `sprints.total` (or `sprints.list` length) resolves to a positive integer
3. `git log ${base_branch}..HEAD` shows at least `sprints.total` commits matching
   `run_mode.git.sprint_commit_pattern`

When satisfied: updates `.run/sprint-plan-state.json` to `state: "JACKED_OUT"` with
`git_inferred: true` and an ISO-8601 `git_inferred_at` timestamp; returns
`{ "synced": true, "reason": "git_inferred_completion", "commits_found": N, "commits_expected": M, "base_branch": "main" }`.

**When it does NOT fire**: in-flight runs with no commits yet, or partial runs
(`commits_found < commits_expected`) → existing `still_running` preserved; state already
`JACKED_OUT`/`HALTED` → existing validation flow.

**Known limitation**: counts matching commits, so a sprint that produced multiple matching commits
(e.g. review-feedback fix commits with the same prefix) can cause early satisfaction. Empirically
rare — squash-merge workflows produce one commit per sprint. Consider `br list --status closed`
as an authoritative alternative if this becomes a problem.

Replaces the previous requirement to use `--force-phase complete --yes` as a last-resort escape
hatch after session loss.

## Related

- `/run sprint-N` — Execute single sprint
- `/run sprint-plan` — Execute all sprints
- `/run-status` — Check current run progress
- `/run-halt` — Gracefully stop execution
- `/run-resume` — Continue from checkpoint
