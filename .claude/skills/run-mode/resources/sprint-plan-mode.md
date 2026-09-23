# run-mode Sprint Plan Execution Loop (`/run sprint-plan`)

## Sprint Discovery

Try each source in priority order; use the first that returns non-empty:

1. **Priority 1 — `sprint.md` sections**: `grep -E "^## Sprint [0-9]+:" grimoires/loa/sprint.md | sed 's/## Sprint \([0-9]*\):.*/sprint-\1/' | sort -t'-' -k2 -n`.
2. **Priority 2 — `ledger.json`**: read `active_cycle` via
   `jq -r '.active_cycle' grimoires/loa/ledger.json`, then
   `jq -r --arg cycle "$active_cycle" '.cycles[] | select(.id == $cycle) | .sprints[] | .local_label' grimoires/loa/ledger.json`.
3. **Priority 3 — a2a directories**: `find grimoires/loa/a2a -maxdepth 1 -type d -name "sprint-*" | sed 's|.*/||' | sort -t'-' -k2 -n`.
4. If all three are empty: HALT — "No sprints found".

## Pre-flight

Same as `/run` (config check, then `.claude/scripts/run-preflight.sh --unattended` — nonzero →
HALT with its checklist), plus: run sprint discovery (above); if empty, HALT — "No sprints
discovered". Otherwise report the discovered sprint list.

## Main Loop

```
initialize_sprint_plan_state()
for sprint in filtered_sprints (apply --from/--to: keep sprint N iff from <= N <= to):
  1. Check .run/sprint-plan-state.json for sprint already "completed" → skip
  2. Run the single-sprint main loop above for this sprint (max_cycles, timeout from options)
  3. COMPLETE → continue to next sprint; HALTED → break outer loop, preserve state
  4. Update .run/sprint-plan-state.json (mark sprint completed, advance current, roll up metrics);
     `.claude/scripts/run-checkpoint.sh write --sprint <next> --phase IMPLEMENT`
create_plan_pr()
update_state(state: JACKED_OUT)
```

State file `.run/sprint-plan-state.json` schema (`schema_version` 2 adds `checkpoint`; readers
accept 1 and 2 — a missing checkpoint means sprint granularity):
→ verbatim block: `resources/state-schemas.md` §sprint-plan-state-schema

Checkpoint discipline (cycle-125 FR-3): every write goes through `run-checkpoint.sh` (jq →
`.tmp.$$` → `mv -f` under `flock`); `/implement` writes `--task <bead-id> --phase IMPLEMENT`
after each `br close`; the loop above writes the phase changes. `run-checkpoint.sh read`
discards a checkpoint whose bead is not closed — beads remain the recovery source.

## Sprint Failure Handling

On a HALTED sprint inside the plan loop:
1. Atomically update `.run/sprint-plan-state.json`:
   `jq --arg s "$failed_sprint" --arg r "$reason" '.state = "HALTED" | .failure = {"sprint": $s, "reason": $r, "timestamp": (now | strftime("%Y-%m-%dT%H:%M:%SZ"))}'`.
2. Create the incomplete PR (template below) via
   `.claude/scripts/run-mode-ice.sh pr-create "[INCOMPLETE] Run Mode: Sprint Plan" "$body" --draft`.
3. Report: "Sprint plan halted at $failed_sprint / Reason: $reason / Use `/run-resume` to continue
   from this point."

Incomplete PR body template:
→ verbatim block: `resources/render-templates.md` §sprint-plan-incomplete-pr-body

## Completion PR (Consolidated)

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
   → verbatim block: `resources/render-templates.md` §completion-pr-body
6. Create the draft PR: `.claude/scripts/run-mode-ice.sh pr-create "Run Mode: Sprint Plan implementation" "$body" --draft`.

## Flatline Summary Generation
→ verbatim block: `resources/render-templates.md` §flatline-summary-steps
