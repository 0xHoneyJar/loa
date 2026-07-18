# session-cap-bb — real bridgebuilder dispatch contract

L3 DispatchContract phase scripts wired by `session-cap-fanout.sh` for the
`bridgebuilder` post-reset fan-out phase (bd-fanout-real-dispatch-9jv6,
Tranche 1). Unlike the generic `../example-*.sh` no-ops, these fire a real
review.

| Phase | Behavior |
|-------|----------|
| `reader.sh` | Sanity-gates on `.run/session-limit-state.json`: absent ⇒ noop-normal, present-but-corrupt ⇒ abort. Hands the captured `active_run_state_snapshot` forward. |
| `decider.sh` | **Fail-closed.** `action:dispatch` only if `sprint_plan.state` or `bridge.state` ∈ {RUNNING, HALTED}; else `action:noop`. |
| `dispatcher.sh` | On dispatch, runs `bridgebuilder-review/resources/entry.sh --repo <owner/repo>` with **no** `--pr` (BB self-discovers open PRs + dedups). On noop, exits 0. |
| `awaiter.sh` | Pass-through — dispatch is synchronous under the phase timeout. |
| `logger.sh` | Records dispatched?/repo/exit-code into the `cycle.phase` payload; cleans the handoff dir. |

## Cross-phase handoff

`prior_phases_json` carries only an `output_hash` (a sha256 of stdout), never
the upstream output itself. State is therefore passed out-of-band through a
per-cycle temp dir `${TMPDIR:-/tmp}/loa-session-cap-bb.<cycle_id>/` that every
phase re-derives identically from the shared `cycle_id`. `TMPDIR` is on the L3
`env -i` allowlist, so the same path resolves under cron as interactively.

## Env overrides (test / operator)

| Var | Default | Purpose |
|-----|---------|---------|
| `LOA_SESSION_CAP_STATE_FILE` | `.run/session-limit-state.json` | capture marker path (reader) |
| `LOA_SESSION_CAP_BB_REPO` | derived from `git remote get-url origin` | `owner/repo` passed as `--repo` |
| `LOA_SESSION_CAP_BB_ENTRY` | `../../../bridgebuilder-review/resources/entry.sh` | BB entrypoint (dispatcher) |

Under the L3 sandbox these are only visible if listed in
`LOA_L3_PHASE_ENV_PASSTHROUGH`; production runs rely on the defaults.

## Safety

Arming this (via `session_cap.post_reset_fanout.enabled: true`) posts **live PR
review comments unattended on cron**. The flag defaults to false.
