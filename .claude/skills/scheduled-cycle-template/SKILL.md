---
name: scheduled-cycle-template
description: L3 generic 5-phase autonomous-cycle template — schedules a DispatchContract (reader → decider → dispatcher → awaiter → logger) via /schedule, with flock-guarded concurrency, content-addressed idempotency, and optional L2 budget pre-check
agent: general-purpose
context: scoped
parallel_threshold: 3000
timeout_minutes: 30
zones:
  system:
    path: .claude
    permission: read
  state:
    paths: [grimoires/loa, .run]
    permission: read-write
  app:
    paths: [src, lib, app]
    permission: read
allowed-tools: Read, Bash
capabilities:
  schema_version: 1
  read_files: true
  search_code: false
  write_files: false
  execute_commands: true
  web_access: false
  user_interaction: false
  agent_spawn: false
  task_management: false
cost-profile: lightweight
---

# scheduled-cycle-template — L3 Cycle Skill (cycle-098 Sprint 3)

## Purpose

Compose `/schedule` (cron registration) with the existing autonomous-mode primitives into a generic 5-phase cycle: **read state → decide → dispatch → await → log**. Caller plugs five small phase scripts (the *DispatchContract*) into a YAML; the L3 lib runs them under a flock, records every phase to a hash-chained audit log, and (optionally) consults the L2 cost gate before letting any work begin.

This skill is **infrastructure**, not a finished application. It is the chassis on which scheduled work — periodic cleanup, watchdog rollups, cross-repo state digests — is built without each implementation re-deriving the same locking + idempotency + audit-log skeleton.

## Source

- RFC: [#655](https://github.com/0xHoneyJar/loa/issues/655)
- PRD: `grimoires/loa/prd.md` §FR-L3 (8 ACs)
- SDD: `grimoires/loa/sdd.md` §1.4.2 (component spec) + §5.5 (full API)
- Library: `.claude/scripts/lib/scheduled-cycle-lib.sh`
- Schemas: `.claude/data/trajectory-schemas/cycle-events/`

## When to use

| Scenario | Use this skill? |
|----------|-----------------|
| Periodic autonomous task with read → decide → act → audit shape | YES |
| Scheduled cleanup, garbage collection, rollup | YES |
| Cron firing where the next firing must NOT overlap the previous | YES |
| One-shot invocation from a human | NO — invoke phase scripts directly |
| Synchronous request/response in a session | NO — this is for unattended cron |
| Cross-repo aggregation needing fan-out | NO — use L5 cross-repo-status-reader |

## Configuration schema (ScheduleConfig YAML)

```yaml
schedule_id: nightly-cleanup           # ^[a-z0-9][a-z0-9_-]{0,63}$
schedule: "0 3 * * *"                  # cron expression (consumed by /schedule)
dispatch_contract:
  reader:     ".claude/skills/scheduled-cycle-template/contracts/example-reader.sh"
  decider:    ".claude/skills/scheduled-cycle-template/contracts/example-decider.sh"
  dispatcher: ".claude/skills/scheduled-cycle-template/contracts/example-dispatcher.sh"
  awaiter:    ".claude/skills/scheduled-cycle-template/contracts/example-awaiter.sh"
  logger:     ".claude/skills/scheduled-cycle-template/contracts/example-logger.sh"
  budget_estimate_usd: 0.50            # forwarded to L2 budget_verdict (when L2 + L3 gate enabled)
  timeout_seconds: 1800                # per-phase timeout (default 300)
```

## DispatchContract API

Each phase script is invoked by `_l3_run_phase` as:

```
<phase_path> <cycle_id> <schedule_id> <phase_index> <prior_phases_json>
```

| Argument | Description |
|----------|-------------|
| `cycle_id` | Content-addressed cycle identifier (sha256 of schedule_id + ts_bucket + dispatch_contract_hash). The same id at the top of every phase. |
| `schedule_id` | Caller-supplied id from ScheduleConfig. |
| `phase_index` | 0=reader, 1=decider, 2=dispatcher, 3=awaiter, 4=logger. |
| `prior_phases_json` | JSON array of prior phase records: `[{phase, started_at, completed_at, duration_seconds, outcome, exit_code, output_hash, …}]`. Empty `[]` for reader. |

**Phase contract:**
- **stdout** — arbitrary; sha256 captured as `output_hash` in cycle.phase event for replay determinism
- **stderr** — last 4KB captured as `diagnostic` on error/timeout (redacted via `_l3_redact_diagnostic`)
- **exit 0** — phase succeeded; cycle proceeds to next phase
- **exit non-zero** — phase failed; cycle aborts with `cycle.error{error_kind=phase_error}`
- **exit 124 / 137** — phase exceeded `timeout_seconds`; cycle aborts with `cycle.error{error_kind=phase_timeout}` (GNU coreutils `timeout` exit codes)

The 5 phases are conventional, not enforced — any of them can no-op. The order is fixed. Cycle-wide state is passed forward via stdout / stderr / `prior_phases_json`. Phases SHOULD be idempotent and side-effect-free until the dispatcher.

## Library functions

```bash
source .claude/scripts/lib/scheduled-cycle-lib.sh

cycle_invoke <schedule_yaml_path> [--cycle-id <id>] [--dry-run]
cycle_idempotency_check <cycle_id> [--log-path <path>]
cycle_replay <log_path> [--cycle-id <id>]
cycle_record_phase <cycle_id> <phase> <record_json>     # advanced
cycle_complete <cycle_id> <record_json>                 # advanced
```

Or invoke directly via the shipped subcommand dispatcher:

```bash
.claude/scripts/lib/scheduled-cycle-lib.sh invoke <schedule.yaml>
.claude/scripts/lib/scheduled-cycle-lib.sh replay .run/cycles.jsonl
```

**Exit codes:**
| Code | Meaning |
|------|---------|
| 0 | `cycle.complete` emitted (all 5 phases succeeded) |
| 1 | `cycle.error` emitted (phase failure or budget halt) |
| 2 | invalid arguments / contract validation failure |
| 4 | lock contention (`cycle.lock_failed` emitted) |

## Audit events (`.run/cycles.jsonl`)

Each line is an [agent-network audit envelope](../../data/trajectory-schemas/agent-network-envelope.schema.json) carrying one of:

| event_type | Emitted | Schema |
|-----------|---------|--------|
| `cycle.start` | once per cycle, after lock + idempotency + budget pre-check | `cycle-start.payload.schema.json` |
| `cycle.phase` | once per phase invocation (1–5 per cycle) | `cycle-phase.payload.schema.json` |
| `cycle.complete` | once per cycle on terminal success | `cycle-complete.payload.schema.json` |
| `cycle.error` | once per cycle on terminal failure (budget halt or any phase) | `cycle-error.payload.schema.json` |
| `cycle.lock_failed` | once per failed lock acquisition (no other events for that cycle) | `cycle-lock-failed.payload.schema.json` |

Use `cycle_replay` to reassemble the SDD §5.5.3 `CycleRecord` view from these events.

## /schedule integration (FR-L3-1)

`/schedule` is the Claude Code primitive that registers a cron expression to fire a command on schedule. The L3 cycle is registered by pointing it at the cycle invocation:

1. Define the ScheduleConfig YAML (e.g., at `.run/schedules/<schedule_id>.yaml`).
2. Use `/schedule` to register a cron firing:
   ```
   .claude/scripts/lib/scheduled-cycle-lib.sh invoke .run/schedules/<schedule_id>.yaml
   ```
3. Validate by running once with `--dry-run`:
   ```
   .claude/scripts/lib/scheduled-cycle-lib.sh invoke <yaml> --dry-run
   ```
   The dry-run emits `cycle.start` only and skips phase execution — useful for confirming the audit log path + lock + idempotency + budget plumbing works before letting the cycle do real work.

To deregister, remove the cron job via `/schedule` and (optionally) move the YAML out of the schedules directory. `enabled: false` at the cron level prevents firing without removing the artifact.

## L2 budget pre-check (FR-L3-6, compose-when-available, CC-9)

When `cost_budget_enforcer.enabled: true` AND L3's own `scheduled_cycle_template.budget_pre_check: true` (or `LOA_L3_BUDGET_PRECHECK_ENABLED=1`), L3 calls `budget_verdict <budget_estimate_usd> --cycle-id <id>` before the reader phase:

| Verdict | Effect |
|---------|--------|
| `allow` | proceed; verdict recorded in `cycle.start.budget_pre_check` |
| `warn-90` | proceed; warning logged + verdict recorded |
| `halt-100` | refuse; `cycle.error{error_phase=pre_check, error_kind=budget_halt}` |
| `halt-uncertainty` | refuse; same as halt-100; uncertainty_reason from L2 |

If L2 is disabled, missing, or `budget_estimate_usd` is 0/absent, the gate degrades silently (graceful skip, `budget_pre_check: null` in cycle.start).

## Idempotency (FR-L3-2)

`cycle_invoke` derives `cycle_id` content-addressed:

```
cycle_id = sha256(schedule_id || "\n" || ts_bucket || "\n" || canonical_jcs(dispatch_contract))
ts_bucket = current ISO-8601 minute (default; overrideable via --cycle-id)
```

Inside the lock, before emitting `cycle.start`, the lib checks the audit log for a `cycle.complete` event with the same `cycle_id`. If present, the invocation no-ops and returns 0. **Errored runs are retried** — only `cycle.complete` triggers the no-op. This means a failed dispatcher with the same content+ts_bucket can be re-fired (e.g., by manually re-running the cron) without rebuilding `cycle_id`.

Two simultaneous cron firings of the same schedule serialize at the flock — second invocation acquires after first releases, then either runs (different ts_bucket, different cycle_id) or skips (same ts_bucket, idempotent).

## Concurrency lock (FR-L3-5)

`flock -w <lock_timeout> 9` on `${lock_dir}/<schedule_id>.lock` (default `lock_dir=.run/cycles/`, `lock_timeout=30s`). Acquire failure emits `cycle.lock_failed{schedule_id, cycle_id, lock_path, acquire_timeout_seconds, attempted_at, diagnostic}` and exits 4.

## Configuration (.loa.config.yaml)

```yaml
scheduled_cycle_template:
  enabled: false                        # opt-in
  audit_log: .run/cycles.jsonl
  lock_dir: .run/cycles
  lock_timeout_seconds: 30
  budget_pre_check: false               # opt-in to L2 gate (compose-when-available)
  max_cycle_seconds: 14400              # caps timeout_seconds × 5 phases (anti-DoS)
  phase_path_allowed_prefixes:          # phase scripts MUST live under one of these
    - .claude/skills
    - .run/schedules
    - .run/cycles-contracts
  schedules: []                         # array of ScheduleConfig refs (paths)
```

Environment overrides:

| Env var | Purpose |
|---------|---------|
| `LOA_CYCLES_LOG` | override audit log path |
| `LOA_L3_LOCK_DIR` | override lock directory |
| `LOA_L3_LOCK_TIMEOUT_SECONDS` | override lock acquisition timeout |
| `LOA_L3_BUDGET_PRECHECK_ENABLED` | "1"/"true" to enable L2 budget gate |
| `LOA_L3_PHASE_PATH_ALLOWED_PREFIXES` | colon-separated allowlist override |
| `LOA_L3_PHASE_ENV_PASSTHROUGH` | space-separated extra env names exposed to phase scripts (validated against `[A-Z_][A-Z0-9_]*`) |
| `LOA_L3_MAX_CYCLE_SECONDS` | override projected-cycle-time cap |
| `LOA_L3_KILL_GRACE_SECONDS` | grace period after timeout TERM before KILL (default 5) |
| `LOA_L3_TEST_NOW` | tests: override "now" (also propagates to LOA_AUDIT_TEST_NOW) |
| `LOA_L3_TEST_MODE` | "1" to enable test-only escape hatches; implicit under bats |
| `LOA_L3_L2_LIB_OVERRIDE` | **test-only** L2 lib path; honored only in test mode |

## Security model

The chassis is hardened against malicious phase scripts and YAML authors:

- **Phase script paths are allowlisted.** Each `dispatch_contract.<phase>` is canonicalized (`realpath`) and must live under one of the `phase_path_allowed_prefixes`. Absolute paths outside the list and `..`-traversal relative paths are rejected at registration *and* at every cycle invocation.
- **Phase scripts run under `env -i`** with a minimal allowlist (`PATH`, `HOME`, `USER`, `LANG`, etc.) plus three explicit injects (`LOA_L3_CYCLE_ID`, `LOA_L3_SCHEDULE_ID`, `LOA_L3_PHASE_INDEX`). Caller can extend per-deployment via `LOA_L3_PHASE_ENV_PASSTHROUGH`. API keys, GitHub tokens, AWS credentials, and other host secrets are NOT visible to phase scripts by default.
- **Lock files are created with `O_NOFOLLOW`** (Python helper) or with a post-creation symlink check. An attacker who stages a symlink at `<lock_dir>/<schedule_id>.lock` does not weaponize the touch into a write-anywhere truncate.
- **Idempotency check requires the full audit envelope.** A `cycle.complete` line claiming a cycle was completed must have `schema_version` + `primitive_id == "L3"` + valid `prev_hash` + `outcome == "success"` + 5-element `phases_completed`; when the trust-store posture is `VERIFIED` and signature verification is on, `signature` + `signing_key_id` are also required. Bare-payload forgery cannot suppress real cycles.
- **`max_cycle_seconds` caps total cycle wall-clock** (default 14400s = 4h) so a malicious YAML setting `timeout_seconds: 86400` cannot park the lock for days.
- **`LOA_L3_L2_LIB_OVERRIDE`** is honored only under bats or when `LOA_L3_TEST_MODE=1` is explicit; in production it would source attacker-controlled bash code into the cycle process.

## Examples

The repo ships five copy-and-customize phase scripts at:

- `.claude/skills/scheduled-cycle-template/contracts/example-reader.sh`
- `.claude/skills/scheduled-cycle-template/contracts/example-decider.sh`
- `.claude/skills/scheduled-cycle-template/contracts/example-dispatcher.sh`
- `.claude/skills/scheduled-cycle-template/contracts/example-awaiter.sh`
- `.claude/skills/scheduled-cycle-template/contracts/example-logger.sh`

A working ScheduleConfig referencing them lives at `.claude/skills/scheduled-cycle-template/contracts/example-schedule.yaml`. Run a dry-cycle end-to-end:

```bash
.claude/scripts/lib/scheduled-cycle-lib.sh invoke \
    .claude/skills/scheduled-cycle-template/contracts/example-schedule.yaml \
    --cycle-id "demo-$(date -u +%Y%m%dT%H%M%SZ)"
```

## Composition with other primitives

| Primitive | Composition pattern |
|-----------|---------------------|
| **Audit envelope (Sprint 1A)** | All five `cycle.*` events flow through `audit_emit` → JSONL with hash chain |
| **Trust store auto-verify (Sprint 1.5 #690)** | Inherited via `audit_emit`'s pre-write check |
| **Cost-budget enforcer L2 (Sprint 2)** | Compose-when-available pre-read gate; `budget_estimate_usd` flows from ScheduleConfig |
| **`/schedule` (existing Loa)** | Cron registration; the L3 lib provides the *invocable* — `/schedule` provides the *firing* |
| **Future L4 graduated-trust** | Will gate dispatcher phases by tier; not wired in 3D |

## Engineering invariants

- `cycle.complete` is the **only** event that gates idempotency. Errors retry.
- The lock guards the entire cycle (cycle.start through terminal event), not just one phase.
- Phase scripts are **untrusted** by default — output is hashed but not interpreted; diagnostic stderr is redacted before logging; phases run under `timeout` to bound runaway work.
- The dispatch_contract_hash captures the *contract* (paths) but not the *content* of phase scripts. Operator pinning of phase script content is out of scope; consumers SHOULD checksum the contract directory if drift detection is required.

## Source files

| Path | Role |
|------|------|
| `.claude/scripts/lib/scheduled-cycle-lib.sh` | Library + CLI dispatcher |
| `.claude/data/trajectory-schemas/cycle-events/*.payload.schema.json` | 5 per-event-type payload schemas |
| `tests/unit/scheduled-cycle-lib-3A.bats` | Sprint 3A foundation tests (32) |
| `tests/unit/scheduled-cycle-lib-3B.bats` | Sprint 3B lock + idempotency + timeout (12) |
| `tests/integration/scheduled-cycle-lib-3C-budget.bats` | Sprint 3C L2 gate (11) |
| `tests/integration/scheduled-cycle-skill-3D.bats` | Sprint 3D skill + contracts (this) |
