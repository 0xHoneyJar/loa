---
name: cost-budget-enforcer
description: L2 cost-budget enforcer — daily token cap with fail-closed semantics under uncertainty (billing-API primary, internal counter fallback, periodic reconciliation cron)
agent: general-purpose
context: scoped
parallel_threshold: 3000
timeout_minutes: 5
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

# cost-budget-enforcer — L2 Daily-Cap Skill (cycle-098 Sprint 2)

## Purpose

Daily token-cap enforcement for autonomous Loa cycles. Replaces the
free-running `make-an-API-call-and-hope-it-doesn't-cost-too-much` pattern
with an explicit pre-call gate that returns one of:

| Verdict | Meaning | Caller behavior |
|---------|---------|-----------------|
| `allow` | <90% of cap, fresh data | proceed |
| `warn-90` | 90-100% projected, fresh data | proceed but operator alerted |
| `halt-100` | ≥100% projected, fresh data | **MUST NOT** proceed |
| `halt-uncertainty` | One of 5 uncertainty modes | **MUST NOT** proceed (fail-closed) |

The 5 uncertainty modes (`uncertainty_reason` field):
- `billing_stale` — billing API >15min unreachable AND counter >75% of cap
- `counter_inconsistent` — counter is negative, decreasing, or backwards
- `counter_drift` — reconciliation detected drift >5% from billing API
- `clock_drift` — system clock vs billing_ts diff >60s tolerance
- `provider_lag` — billing API lag ≥5min when counter shows >75% of cap

The verdict order is **severity-first**:
`counter_inconsistent → billing_stale → provider_lag → clock_drift → halt-100 → warn-90 → allow`

## Source

- RFC: [#654](https://github.com/0xHoneyJar/loa/issues/654)
- PRD: `grimoires/loa/prd.md` §FR-L2 (10 ACs)
- SDD: `grimoires/loa/sdd.md` §1.4.2 (component spec) + §1.5.3 (state diagram) + §5.4 (full API)
- Decisions: SKP-005 (un-deferred reconciliation cron); SKP-001 (RPO 24h for L1/L2 untracked logs)

## When to use

| Scenario | Use this skill? |
|----------|-----------------|
| Pre-call cost check during a sleep window or autonomous run | YES |
| Post-call counter update after billing-API confirms a charge | YES (`budget_record_call`) |
| Operator force-reconcile after billing-API drift incident | YES (`budget_reconcile --force-reason "..."`) |
| Manual ad-hoc usage query (not gated) | YES (`budget_get_usage`) |
| Mid-cycle daily-cap raise (operator action) | NO — protected-class `budget.cap_increase` short-circuits to operator queue |

## Configuration

`.loa.config.yaml::cost_budget_enforcer.*` (opt-in; disabled by default per `agent_network.primitives.L2.enabled: false`):

```yaml
cost_budget_enforcer:
  daily_cap_usd: 50.00
  freshness_threshold_seconds: 300       # 5 min — billing data is "fresh"
  stale_halt_pct: 75                     # counter % triggering stale_halt + provider_lag
  clock_tolerance_seconds: 60            # ±60s for clock_drift
  provider_lag_halt_seconds: 300         # 5 min provider_lag threshold
  billing_stale_halt_seconds: 900        # 15 min billing_stale threshold
  audit_log: .run/cost-budget-events.jsonl
  billing_observer_cmd: /path/to/observer-shim.sh   # caller-supplied UsageObserver
  per_provider_caps:                                # optional sub-caps per provider
    openai: 5.00
    anthropic: 30.00
  providers:                                        # used by reconciliation cron
    - aggregate
    - anthropic
    - openai
  reconciliation:
    interval_hours: 6                    # cron cadence for budget_reconcile
    drift_threshold_pct: 5.0
audit_snapshot:
  cron_expression: "0 4 * * *"          # daily snapshot of L1/L2 logs
```

Environment variable overrides (highest precedence): see lib header.

## Library API

The skill is implemented as `.claude/scripts/lib/cost-budget-enforcer-lib.sh`.
Source it and call:

```bash
source .claude/scripts/lib/cost-budget-enforcer-lib.sh

# Pre-call verdict
budget_verdict <estimated_usd> [--provider <id>] [--cycle-id <id>]
# Stdout: verdict payload JSON; exit 0=allow/warn-90, 1=halt-100/halt-uncertainty.

# Read-only state query
budget_get_usage [--provider <id>]
# Stdout: {usd_used, usd_remaining, daily_cap_usd, last_billing_ts, counter_ts,
#          freshness_seconds, provider, utc_day}

# Post-call accounting
budget_record_call <actual_usd> --provider <id> [--cycle-id <id>] [--model-id <id>] [--verdict-ref <hash>]

# Reconciliation (cron-driven; can be invoked ad-hoc)
budget_reconcile [--provider <id>] [--force-reason <text>]
# Exit codes: 0=OK, 1=BLOCKER (drift>threshold), 2=DEFER (rate-limited/transient)
```

CLI form:

```bash
.claude/scripts/budget/budget-cli.sh verdict 1.50 --provider anthropic
.claude/scripts/budget/budget-cli.sh usage --provider anthropic
.claude/scripts/budget/budget-cli.sh record 1.42 --provider anthropic --model-id claude-opus-4-7
.claude/scripts/budget/budget-cli.sh reconcile --provider anthropic
```

## UsageObserver Interface

The lib invokes `LOA_BUDGET_OBSERVER_CMD <provider>` (or
`cost_budget_enforcer.billing_observer_cmd`). The command is expected to
print one of three JSON shapes on stdout:

| Shape | Meaning |
|-------|---------|
| `{"usd_used": <number>, "billing_ts": "<iso8601>"}` | Success — usage from billing API |
| `{"_unreachable": true, "_reason": "<text>"}` | Billing API unreachable (logs reconcile event with `billing_api_unreachable: true`) |
| `{"_defer": true, "_reason": "rate_limited"}` | Transient — skip without writing audit event; next 6h interval retries |

The lib applies a 30-second timeout. Provider-agnostic: keep
provider-specific HTTP client logic in the observer shim.

## Reconciliation cron + Daily snapshot

Two separate crontab entries support L2 production operation:

```bash
# 6h cadence reconciliation (Sprint 2B)
.claude/scripts/budget/budget-reconcile-install.sh install

# Daily snapshot for chain-recovery RPO 24h (Sprint 2C)
.claude/scripts/audit/audit-snapshot-install.sh install
```

Operator runbook for recovery: `grimoires/loa/runbooks/audit-log-recovery.md`.

## Composition with other primitives

- **L1 hitl-jury-panel**: when L1 panel decisions involve cost — `panel_invoke` MAY call `budget_verdict` first to short-circuit on halt-uncertainty
- **L3 scheduled-cycle-template** (Sprint 3): scheduled-cycle reader phase invokes `budget_verdict` as part of pre-read budget pre-check
- **Protected-class router**: `budget.cap_increase` (mid-cycle daily-cap raise) is a protected class — use `protected-class-router.sh check budget.cap_increase` and route to operator queue rather than auto-applying

## Observability

Every verdict appends one envelope to `.run/cost-budget-events.jsonl`:

```json
{
  "schema_version": "1.1.0",
  "primitive_id": "L2",
  "event_type": "budget.allow",
  "ts_utc": "2026-05-04T12:00:00.000000Z",
  "prev_hash": "<sha256-hex>",
  "payload": {
    "verdict": "allow",
    "usd_used": 8.50,
    "usd_remaining": 41.50,
    "daily_cap_usd": 50.00,
    "estimated_usd_for_call": 1.50,
    ...
  },
  "redaction_applied": null,
  "signature": "<base64-when-signed>",
  "signing_key_id": "<writer-key>"
}
```

Per-event-type schemas live at
`.claude/data/trajectory-schemas/budget-events/`. The lib validates payloads
against these schemas before sealing the envelope.

## Safety guarantees

- **Fail-closed**: NEVER `allow` under uncertainty (PRD §FR-L2-7); 5
  uncertainty modes covered with mode-specific diagnostic context
- **Hash-chained**: every envelope's `prev_hash` chains to prior entry
  (Sprint 1A); `audit_verify_chain` walks the chain at every read
- **Ed25519-signed**: when `LOA_AUDIT_SIGNING_KEY_ID` is configured, every
  envelope is signed; trust-store strict-after enforcement (Sprint 1B F1)
  rejects strip-attack downgrade attempts
- **Recoverable**: chain-critical L2 log is UNTRACKED for privacy; daily
  snapshot job (Sprint 2C) ships RPO 24h restore via `audit_recover_chain`
- **flock-serialized**: concurrent verdicts and reconciliation cron firings
  serialize via per-log flock (Sprint 1 review remediation F3)

## Testing

Unit tests: `tests/unit/cost-budget-enforcer-state-machine.bats` (31 tests)
Integration tests: `tests/integration/cost-budget-enforcer-reconciliation-cron.bats` (11 tests)
Snapshot tests: `tests/integration/audit-snapshot.bats` (13 tests)

Cumulative: 55 / 55 PASS.
