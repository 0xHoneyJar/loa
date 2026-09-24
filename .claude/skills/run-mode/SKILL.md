---
name: run
description: "Autonomous sprint execution: /run sprint-N and /run sprint-plan wrap implement->review->audit cycles with circuit breaker, ICE git safety, and draft-PR completion. Use for UNATTENDED execution of an existing sprint plan. (Contrast: autonomous-agent orchestrates the FULL lifecycle from requirements; simstim keeps a human driving the planning phases.)"
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

Run Mode itself is orchestration; cost comes from the sub-skills it invokes (Flatline, Bridgebuilder, implementation sessions — see the [Cost Matrix](../../../docs/CONFIG_REFERENCE.md#cost-matrix)). Cap spend with `run_mode.defaults.max_cycles` and `hounfour.metering.budget.daily_micro_usd` in `.loa.config.yaml` (enforced when `hounfour.metering.enabled: true`); `/loa setup` guides a budget-appropriate configuration.

<input_guardrails>
## Pre-Execution Guardrails

Skip this section entirely when `.loa.config.yaml` has `guardrails.input.enabled: false` or env
`LOA_GUARDRAILS_ENABLED=false`.

Otherwise: write the user's invocation prompt/args to a temp file (Write tool), then run
`.claude/scripts/guardrails-orchestrator.sh --skill run-mode --mode ${LOA_RUN_MODE:-interactive} --file <temp-file>`

| Outcome | Action |
|---------|--------|
| JSON `action: "BLOCK"` | HALT; report the script's `reason` to the user |
| JSON `action: "PROCEED"` or `"WARN"` | Continue (logging is handled by the script) |
| Script missing, non-zero exit, or unparseable output | Continue — fail-open. |

Never pass prompt text as a bash argv (quote-blindness FP class) — always via `--file`.

**Danger-level gating** (run-mode is a **high** danger-level skill; additive to the orchestrator call
above): before each skill invocation inside the run loop (`/implement`, `/review-sprint`,
`/audit-sprint`, red-team, post-PR phases), run
`.claude/scripts/danger-level-enforcer.sh --skill <invoked-skill> --mode autonomous`.
`PROCEED` → execute; `WARN` → execute with enhanced trajectory logging; `BLOCK` → skip the
invocation, log to trajectory, count a zero-progress cycle. `--allow-high` on the `/run` invocation
permits skills that would otherwise `BLOCK` (e.g. `/run --bug "..." --allow-high`; see
`resources/bug-run-mode.md`). A nested interactive confirmation asks the user instead of blocking.
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
2. **Preflight checklist**: run `.claude/scripts/run-preflight.sh --unattended`. Non-zero exit →
   HALT and surface its checklist verbatim (it names each failed predicate and the fix: P1
   defaultMode, P2 allow rules, P3 voices, P4 breakers, P5 NOTES size, P6 run state, P7 beads,
   P8 branch). Then call `.claude/scripts/beads/update-beads-state.sh --health "$(jq -r .status
   <(.claude/scripts/beads/beads-health.sh --quick --json))"` to record the observed beads health.

## Initialization

Once pre-flight passes, initialize the run:

1. `mkdir -p .run`.
2. Generate `run_id="run-$(date +%Y%m%d)-$(openssl rand -hex 4)"` and an ISO-8601 `timestamp`
   (`date -u +"%Y-%m-%dT%H:%M:%SZ"`).
3. Resolve the initial push mode via ICE (single source of truth — never compute push mode
   independently): `--local` flag → `run-mode-ice.sh should-push local`; `--confirm-push` flag →
   `run-mode-ice.sh should-push prompt`; neither → `run-mode-ice.sh should-push`.
4. Write `.run/state.json` with this exact schema (fill in the resolved values):
   → verbatim block: `resources/state-schemas.md` §run-state-schema
5. Write `.run/circuit-breaker.json` with this exact schema:
   → verbatim block: `resources/state-schemas.md` §circuit-breaker-schema
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
  3. update_state(phase: REVIEW); checkpoint(phase: REVIEW)
  4. /review-sprint $target
  5. If `verdict-derive.sh --gate review` on engineer-feedback.md does not exit 0 with
     `.verdict == APPROVED` (anything else — including an inconsistent trailer — counts as
     findings) → record_cycle(findings), check circuit breaker
     (see "Circuit Breaker" below); on trip, HALT; else continue loop (back to step 1)
  6. update_state(phase: AUDIT); checkpoint(phase: AUDIT)
  7. /audit-sprint $target
  8. If `verdict-derive.sh --gate audit` on auditor-sprint-feedback.md does not exit 0 with
     `.verdict == APPROVED` → same as step 5 (golden-path's `_gp_sprint_is_audited` additionally
     re-derives the review trailer and cross-checks `excluded` ⇔ `excluded_confirmed`)
  9. RED_TEAM_CODE gate (if enabled) — see resources/conditional-procedures.md §red-team-code-gate
  10. If COMPLETED marker exists → update_state(state: COMPLETE); break
Create draft PR (see "Completion and PR Creation" — resources/completion-modes.md)
Invoke Post-PR Validation if enabled — resources/conditional-procedures.md §post-pr-validation
Update state to READY_FOR_HITL or JACKED_OUT
```

Call `check_rate_limit` (see "Rate Limiting" below) before each of steps 1, 4, and 7.
`checkpoint(...)` = `.claude/scripts/run-checkpoint.sh write --sprint $target --phase <PHASE>`
(when `.run/sprint-plan-state.json` exists); `/implement` writes the per-task checkpoint on each
`br close`. Beads stay the recovery truth — the checkpoint is a hint `/run-resume` reports.

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

1. After each `/review-sprint` or `/audit-sprint`, compute the same-issue hash from the
   DERIVED verdict when the feedback file carries a `<!-- LOA-VERDICT` trailer:
   `bash .claude/scripts/verdict-derive.sh --file <feedback-file> --gate review|audit --json 2>/dev/null | jq -Sc '{verdict,counts}' | md5sum | cut -d' ' -f1`
   No-trailer fallback (legacy files without a trailer): `grep -A 100 "## Findings\|## Issues\|## Changes Required" <feedback-file> | head -50 | md5sum | cut -d' ' -f1`
   (or `echo "none"` if the feedback file doesn't exist). The derived hash is coarser than the
   prose hash — identical verdict+counts on different findings collide, so the breaker trips
   sooner, which HALTs for a human (the loud direction).
2. Read `last_hash` via `jq -r '.triggers.same_issue.last_hash // "none"' .run/circuit-breaker.json`.
3. If the new hash equals `last_hash` and is not `"none"`: increment count
   (`jq '.triggers.same_issue.count += 1'`). Otherwise: reset — set count to 1 and
   `last_hash` to the new hash in one `jq` call.

### Red Team Code-vs-Design Circuit Breaker

Separate counter from the main circuit breaker (see `resources/conditional-procedures.md`
§red-team-code-gate for behavior).

## Sprint Plan Execution Loop (`/run sprint-plan`)

`/run sprint-plan` wraps the single-sprint main loop above across every sprint the repo defines:
discovery (from `sprint.md`, `ledger.json`, or `grimoires/loa/a2a/sprint-*` directories, in that
priority order), a pre-flight identical to `/run`'s, a per-sprint loop that runs the main loop
above and records completion in `.run/sprint-plan-state.json`, failure handling that produces an
`[INCOMPLETE]` PR and preserves state for `/run-resume`, and a consolidated completion PR once
every sprint finishes. Full procedure, including the exact discovery commands and PR body
assembly: `resources/sprint-plan-mode.md`.

## Deleted Files Tracking

Log file: `.run/deleted-files.log`, format `file_path|sprint|cycle` (one line per deleted file).

1. After each commit in the main loop, collect deletions:
   `git diff --name-status HEAD~1 HEAD | grep "^D" | cut -f2`, and append
   `{file}|{sprint}|{cycle}` per file to `.run/deleted-files.log`.
2. PR-body rendering of the log (tree format, header, warning line): `resources/completion-modes.md`
   §Deleted Files Tree.

## Completion and PR Creation

Push mode resolves in priority order — `--local` flag, then `--confirm-push` flag, then
`run_mode.git.auto_push` in config (`true`→AUTO, `false`→LOCAL, `prompt`→PROMPT; default `true`) —
always via `.claude/scripts/run-mode-ice.sh should-push`, never computed independently, and the
resolved mode is recorded on `.run/state.json` (`jq --arg mode "$push_mode" '.options.push_mode =
$mode'`). LOCAL mode commits nothing further and reports locally; PROMPT mode asks the user via
`AskUserQuestion` and then follows LOCAL or AUTO; AUTO mode pushes via ICE and opens a draft PR.
Exact steps and report/PR-body templates for all three: `resources/completion-modes.md`.

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
3. If `calls_this_hour >= limit`: this is a rate-limit wait (procedure:
   `resources/conditional-procedures.md` §rate-limit-wait). Otherwise increment `calls_this_hour`
   by 1 and proceed.

## `/run-status` — Display Progress

Reports run or sprint-plan progress: state, phase, branch, elapsed runtime, circuit-breaker
counts, and metrics from `.run/state.json` and `.run/circuit-breaker.json`, with `--json` and
`--verbose` variants and a sprint-plan-specific box when `.run/sprint-plan-state.json` exists. If
`.run/state.json` doesn't exist, report that no run is in progress. Full rendering steps:
`resources/run-status.md`.

## `/run-halt` — Graceful Stop

Commits pending work, pushes, and opens or updates an `[INCOMPLETE]` PR before setting state to
`HALTED`, so a halted run is always resumable. Pre-flight and exact steps:
`resources/halt-resume.md` §run-halt.

## `/run-resume` — Continue From Checkpoint

Validates state, branch, and (unless `--force`) that the branch hasn't diverged from its remote,
then resumes the main loop at the recorded phase. `--reset-ice` clears a tripped circuit breaker
first. Pre-flight and exact steps: `resources/halt-resume.md` §run-resume.

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

Autonomous bug fixing — triage, then the same implement → review → audit cycle as above, scoped to a `sprint-bug-{N}` micro-sprint with tighter circuit-breaker limits and a
confidence-annotated draft PR:

```
/run --bug "Login fails when email contains + character"
/run --bug --from-issue 42
/run --bug "description" --allow-high
```

Triage flags high-risk areas (auth, payment, migration, secrets, and related keywords);
autonomous mode halts on a `high` finding unless `--allow-high` is passed. Full loop, state
schema, and PR template: `resources/bug-run-mode.md`.

## Safety Model

Defense in depth: ICE-wrapped git, the circuit breaker, explicit opt-in (`run_mode.enabled: true`),
and visibility (draft PRs, deleted-file tracking, cycle history). The human checkpoint is PR review,
not phase gates.

## Configuration

→ verbatim block: `resources/state-schemas.md` §configuration-yaml

## Error Recovery

On any error: state is preserved in `.run/`. Use `/run-status` to see current state, `/run-resume`
to continue, `/run-resume --reset-ice` if the circuit breaker tripped, or `rm -rf .run/` to start
fresh.

### Git-Aware State Sync

→ verbatim block: `resources/state-schemas.md` §git-aware-state-sync (recovery for RUNNING-but-actually-done sprint-plan state via `simstim-orchestrator.sh --sync-run-mode`)

## Provenance

Guardrail orchestration originates from cycle-119; git-aware state sync from cycle-056 (#474).
