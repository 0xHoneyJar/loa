# run-mode `/run-status` — Display Progress

1. If `.run/state.json` doesn't exist: report "No run in progress. Start a new run with `/run
   sprint-N` or `/run sprint-plan`."
2. Otherwise read: `run_id`, `state`, `target`, `branch`, `phase` from `.run/state.json`; compute
   runtime as `elapsed = now_seconds - $(date -d "$started" +%s)`, formatted `{h}h {m}m`; read
   circuit-breaker counts/thresholds from `.run/circuit-breaker.json`; read metrics
   (`files_changed`, `files_deleted`, `commits`, `findings_fixed`) from `.run/state.json`.
3. Render the standard box report:
   → verbatim block: `resources/render-templates.md` §run-status-box
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
