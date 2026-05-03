# Sub-sprint 2A Progress Report — L2 verdict-engine foundation

**Cycle**: cycle-098-agent-network
**Sprint**: 2 (L2 cost-budget-enforcer + reconciliation cron + daily snapshot)
**Sub-sprint**: 2A (1 of 4)
**Branch**: `feat/cycle-098-sprint-2`
**Status**: COMPLETED

## Outcome

The L2 verdict-engine foundation is in place. State machine implements
all 5 verdicts × 5 uncertainty modes per PRD §FR-L2 + SDD §1.5.3. Per-event
schema registry pattern (IMP-001 v1.1) lives in
`.claude/data/trajectory-schemas/budget-events/`, validated at write-time
by the L2 lib before the audit envelope is sealed and signed.

## Files added (1 lib + 6 schemas + 1 bats file)

### L2 library (Sprint 2A foundation)

| File | Purpose |
|------|---------|
| `.claude/scripts/lib/cost-budget-enforcer-lib.sh` | L2 lib — `budget_verdict`, `budget_get_usage`, `budget_record_call`, `budget_reconcile`. ~720 lines. |

### Per-event-type payload schemas (IMP-001 v1.1 registry pattern)

| File | Event type |
|------|-----------|
| `.claude/data/trajectory-schemas/budget-events/budget-allow.payload.schema.json` | `budget.allow` |
| `.claude/data/trajectory-schemas/budget-events/budget-warn-90.payload.schema.json` | `budget.warn_90` |
| `.claude/data/trajectory-schemas/budget-events/budget-halt-100.payload.schema.json` | `budget.halt_100` |
| `.claude/data/trajectory-schemas/budget-events/budget-halt-uncertainty.payload.schema.json` | `budget.halt_uncertainty` (5 reasons) |
| `.claude/data/trajectory-schemas/budget-events/budget-reconcile.payload.schema.json` | `budget.reconcile` |
| `.claude/data/trajectory-schemas/budget-events/budget-record-call.payload.schema.json` | `budget.record_call` |

### Tests

| File | Type | Count | Status |
|------|------|-------|--------|
| `tests/unit/cost-budget-enforcer-state-machine.bats` | bats | 31 | 31 PASS / 0 FAIL |

## Sprint 2 ACs — partial coverage by 2A

### Functional requirements (PRD §FR-L2)

- **FR-L2-1** allow when usage <90% AND data fresh — DONE (covers test #1, #2)
- **FR-L2-2** warn-90 when projected usage in [90, 100)% — DONE (test #3)
- **FR-L2-3** halt-100 when projected usage >=100% — DONE (test #4, #5)
- **FR-L2-4** halt-uncertainty:billing_stale — DONE (test #6)
- **FR-L2-5** Reconciliation drift >5% emits BLOCKER — DONE (test #20, #21)
  *(2B will wire the cron registration via /schedule)*
- **FR-L2-6** Counter inconsistency triggers halt-uncertainty — DONE (#7, #8)
- **FR-L2-7** Fail-closed under all uncertainty modes — DONE (#15)
- **FR-L2-8** Per-repo / per-provider caps — DONE (#12, #13)
- **FR-L2-9** Verdicts logged to JSONL — DONE (#16)
- **FR-L2-10** Integration tests for billing outage / drift / cap change — partial; 2B/2D round out

### Cross-cutting (CC-2 + CC-11)

- envelope is versioned (`schema_version`), hash-chained (`prev_hash`), signed when key present
- per-event-type schemas validated via ajv (R15 fallback to python `jsonschema`)
- chain integrity verified via `audit_verify_chain` (test #27)

### State machine (SDD §1.5.3 + IMP-004)

- 5 verdicts implemented: allow, warn-90, halt-100, halt-uncertainty, reconcile
- 5 uncertainty reasons: `billing_stale`, `counter_inconsistent`, `counter_drift`,
  `clock_drift`, `provider_lag`
- Verdict-trigger order: counter_inconsistent → billing_stale → provider_lag →
  clock_drift → halt-100 → warn-90 → allow

## TODO hooks for Sprint 2B (reconciliation cron)

`budget_reconcile` is implemented as a function unit (test #20-23). 2B wires:
1. `/schedule` registration (default 6h cadence; configurable
   `cost_budget_enforcer.reconciliation.interval_hours`)
2. `force-reconcile` operator action with reason capture (already supported in
   the function)
3. Cron-deregister on `enabled: false` lifecycle event
4. Integration tests — 6h cadence semantics; idempotent re-runs;
   billing-API 429 deferral

## TODO hooks for Sprint 2C (daily snapshot job)

The L2 audit log (`.run/cost-budget-events.jsonl`) is UNTRACKED and chain-critical
per SDD §3.4.4 + §3.7. 2C ships:
1. `/loa audit snapshot` command — exports L1 + L2 logs to
   `grimoires/loa/audit-archive/<utc-date>-<primitive>.jsonl.gz`
2. Snapshots Ed25519-signed by operator's writer key
3. Operator runbook update at `grimoires/loa/runbooks/audit-log-recovery.md`
4. Integration with `audit_recover_chain` UNTRACKED snapshot-restore path

## TODO hooks for Sprint 2D (L2 skill + integration)

1. `.claude/skills/cost-budget-enforcer/SKILL.md`
2. CLI entrypoint script `.claude/scripts/budget/budget_verdict.sh` (or
   per-skill convention)
3. `.loa.config.yaml.example` — `cost_budget_enforcer` block documentation
4. CLAUDE.md update — agent-network-audit-envelope section addition
5. Lore entry "fail-closed cost gate" at `grimoires/loa/lore/`
6. Compose hooks for L1 (FR-L1-9 cost-estimation integration) and L3 (L3 budget
   pre-check integration)
7. Protected-class router invocation for `budget.cap_increase` mid-cycle raises

## Design decisions worth recording

### 1. Counter is derived from audit log (single source of truth)

Counter for current UTC day is computed by tail-scanning the audit log for
`budget.record_call` events with matching `payload.utc_day` and provider.
No separate counter state file. This avoids dual-source-of-truth pitfalls.

### 2. Verdict-trigger order: severity-first

```
counter_inconsistent → billing_stale → provider_lag → clock_drift →
halt-100 → warn-90 → allow
```

Order matters because uncertainty modes overlap (e.g., billing_age >= 15min
implies billing_age >= 5min). Most-severe wins.

### 3. clock_drift is gated on freshness

Stale `billing_ts` will appear "drifted" from system clock — but that's a
staleness signal, not a clock-drift signal. Clock-drift check fires only
when `billing_age <= freshness_threshold`.

### 4. Per-event-type schema registry (IMP-001 v1.1)

Each event_type has its own payload schema at
`.claude/data/trajectory-schemas/budget-events/<event_type>.payload.schema.json`.
Lookup: `event_type` "budget.warn_90" → `budget-warn-90.payload.schema.json`
(underscore → dash, drop "budget." prefix).

### 5. Caller-supplied `UsageObserver` interface

Per SDD §1.6, the billing API client is caller-supplied. `LOA_BUDGET_OBSERVER_CMD`
or `cost_budget_enforcer.billing_observer_cmd` points to an executable that:
- Receives the provider id as `$1`
- Returns JSON `{"usd_used": <number>, "billing_ts": "<iso8601>"}` on stdout
- Returns non-zero or non-JSON on error (treated as `_unreachable`)
- Has 30s timeout (`timeout 30 <cmd> ...`)

This keeps the lib provider-agnostic and testable without external deps.

### 6. usd_remaining semantics (schema relaxation)

The `halt-100` schema previously required `usd_remaining: maximum 0`. Relaxed
to permit positive remaining at decision time — the verdict trigger uses the
*projected* `usage_pct` (which is `>= 100` per the schema), not the current
`usd_remaining`. The current remaining can be positive at the moment a call
about to push usage over the cap is rejected.

## Constraints honored

- Test-first: 31 BATS tests cover state machine, schema validation,
  argument validation, audit-log integrity, UTC-day rollover, per-provider
  isolation, and reconciliation
- Karpathy: surgical lib introduction; existing `audit-envelope.sh` and
  `protected-class-router.sh` reused unchanged
- Beads UNHEALTHY (#661): no beads writes
- System Zone authorization: cycle-098 PRD/SDD scope `.claude/scripts/lib/`,
  `.claude/data/trajectory-schemas/budget-events/`, and (Sprint 2D)
  `.claude/skills/cost-budget-enforcer/`. All within authorized expansion.

## Outcome stats

- Files added: 8 (1 lib + 6 schemas + 1 test)
- Lines: ~720 lib + ~150 schemas + ~570 tests = ~1440 added
- Tests: 31 (31 PASS / 0 FAIL)
- Regression: Sprint 1 audit-envelope and panel tests still PASS
- Ready for: Sub-sprint 2B (reconciliation cron + /schedule wiring)
