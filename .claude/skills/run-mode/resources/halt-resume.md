# run-mode `/run-halt` and `/run-resume`

## run-halt

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
   → verbatim block: `resources/render-templates.md` §halt-incomplete-pr-body
7. Update state atomically: `jq --arg r "$reason" --arg ts "$timestamp" '.state = "HALTED" | .halt = {"reason": $r, "timestamp": $ts} | .timestamps.last_activity = $ts'`.
8. Report the halt summary box:
   → verbatim block: `resources/render-templates.md` §halt-summary-box

## run-resume

### Pre-flight

0. Run `.claude/scripts/run-preflight.sh --unattended --resume` (P6 inverted: a resumable state
   passes, nothing to resume fails). Non-zero exit → surface its checklist and stop.
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

1. Read `run_id`, `target`, `phase`, `cycles.current` from `.run/state.json`; report them, then
   report `.claude/scripts/run-checkpoint.sh read` (sprint / last closed task / phase, or
   "sprint granularity"). `/implement` resumes at the first open bead (`br ready`) — the
   checkpoint never overrides beads.
2. If `--reset-ice`: reset the circuit breaker —
   `jq --arg ts "$timestamp" '.state = "CLOSED" | .triggers.same_issue.count = 0 | .triggers.same_issue.last_hash = null | .triggers.no_progress.count = 0 | .triggers.cycle_count.current = 0 | .triggers.timeout.started = $ts'`
   on `.run/circuit-breaker.json`.
3. Update `.run/state.json` atomically: `.state = "RUNNING" | del(.halt) | .timestamps.last_activity = $ts`.
4. Report "✓ State updated to RUNNING" then resume the main loop at the recorded `phase`:
   `INIT` → restart from initialization; `IMPLEMENT` → re-run `/implement $target` then continue
   the loop; `REVIEW` → re-run `/review-sprint $target` then continue; `AUDIT` → re-run
   `/audit-sprint $target` then continue; unknown phase → start from `IMPLEMENT`.
