# run-mode conditional procedures

Referenced by pointer from SKILL.md for paths that don't run on every cycle: the RED_TEAM_CODE
gate, Post-PR Validation, and the rate-limit wait. Reproduce commands exactly.

## red-team-code-gate

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
→ verbatim block: `resources/state-schemas.md` §red-team-code-state

## post-pr-validation

After PR creation, check `post_pr_validation.enabled` in `.loa.config.yaml`:
- `true`: invoke `.claude/scripts/post-pr-orchestrator.sh --pr-url <url> --mode autonomous`.
  Exit 0 → state = `READY_FOR_HITL`. Exit 2-5 (HALTED) → state = `HALTED`, create `[INCOMPLETE]`
  PR note.
- `false`: state = `JACKED_OUT`.

The orchestrator's phase sequence: `POST_PR_AUDIT` (consolidated PR audit + fix loop) →
`CONTEXT_CLEAR` (checkpoint + prompt user to `/clear`) → `E2E_TESTING` (fresh-eyes testing + fix
loop) → `FLATLINE_PR` (optional multi-model review, ~$1.50) → `READY_FOR_HITL`. Full spec:
`grimoires/loa/prd-post-pr-validation.md`.

## rate-limit-wait

When `calls_this_hour >= limit` in `.run/rate-limit.json`, compute the wait window and poll with a
bounded until-loop per `.claude/protocols/agent-ergonomics.md` item 1 — do not call a
fixed-duration `sleep` and hope the wait matches:

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
