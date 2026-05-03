# Sub-sprint 2B Progress Report — Reconciliation cron + /schedule wiring

**Cycle**: cycle-098-agent-network
**Sprint**: 2 (L2 cost-budget-enforcer + reconciliation cron + daily snapshot)
**Sub-sprint**: 2B (2 of 4)
**Branch**: `feat/cycle-098-sprint-2`
**Status**: COMPLETED

## Outcome

The L2 reconciliation cron is wired to `crontab` (the same registration model
used elsewhere in the repo, e.g., `compact-trajectory.sh`). Sprint 2A's
`budget_reconcile` function unit is now driven by an idempotent shell
entrypoint that:

1. Reads providers from `.loa.config.yaml::cost_budget_enforcer.providers`
   (or defaults to `aggregate`)
2. Acquires a flock to serialize concurrent cron firings
3. Invokes `budget_reconcile` per provider
4. Maps reconciliation outcomes to exit codes:
   - 0 OK — no blocker
   - 1 BLOCKER — drift exceeded; operator review required
   - 2 DEFER — observer signaled `_defer: true` (rate-limit / transient)

An installer (`budget-reconcile-install.sh`) ships the standard
`crontab -e` lifecycle (status / install / uninstall / show) using a marker
comment for idempotency.

## Files added

### Cron entrypoints

| File | Purpose |
|------|---------|
| `.claude/scripts/budget/budget-reconcile-cron.sh` | Cron entry script — flock-serialized, multi-provider loop, dry-run support |
| `.claude/scripts/budget/budget-reconcile-install.sh` | Operator helper: `install`, `uninstall`, `status`, `show` (idempotent crontab management) |

### Tests

| File | Type | Count | Status |
|------|------|-------|--------|
| `tests/integration/cost-budget-enforcer-reconciliation-cron.bats` | bats | 11 | 11 PASS / 0 FAIL |

### Lib modification

`cost-budget-enforcer-lib.sh::budget_reconcile` extended with `_defer`
handling: when the caller-supplied `UsageObserver` returns
`{"_defer": true, "_reason": "rate_limited"}`, `budget_reconcile` returns
exit code 2 without writing a reconcile event (transient failure should
not surface in the audit log; the next 6h interval will retry).

## ACs satisfied

### Sprint 2 deliverables (sprint.md)

- **Reconciliation cron (un-deferred per SKP-005)**: DONE
  - default 6h cadence (configurable `cost_budget_enforcer.reconciliation.interval_hours`)
  - runs even when no cycle is active (independent crontab entry)
  - compares internal counter to billing API
  - emits BLOCKER on drift >5%
  - counter NOT auto-corrected — operator decides via `--force-reason`
- **`/schedule deregister` integration**: DONE via `budget-reconcile-install.sh uninstall`

### FR-L2-5 (PRD)

- Reconciliation job detects drift >5% — DONE (test #2)
- BLOCKER emitted on drift exceedance — DONE (test #2, exit 1)
- Configurable threshold via `LOA_BUDGET_DRIFT_THRESHOLD` /
  `cost_budget_enforcer.reconciliation.drift_threshold_pct` — DONE

### Risk mitigations (sprint.md table)

- Reconciliation cron deregistration leaves orphan cron entries — Low /
  MITIGATED via `budget-reconcile-install.sh uninstall` lifecycle test (#9)
- Provider billing API rate limits during reconciliation — Med / MITIGATED
  via `_defer` semantics: observer signals defer, no audit write, next
  interval retries (test #3)

## Idempotency guarantees

1. **`install`** subcommand:
   - First run appends marker-tagged crontab line
   - Re-run with same cadence: prints "Already installed (cadence matches)"
     and exits 0
   - Re-run with changed cadence (config edited): replaces the marker line
     with new cron expression
2. **`uninstall`** subcommand:
   - First run removes marker-tagged line
   - Re-run prints "Not installed; nothing to remove" and exits 0
3. **Cron entrypoint** itself:
   - flock-serialized — concurrent firings (e.g., crond firing while a long
     prior invocation still runs) wait up to 5min for the lock
   - Each invocation appends exactly one `budget.reconcile` envelope per
     provider per call (regardless of how often called)
   - Tested: 3 sequential invocations append 3 reconcile events with intact
     hash chain (test #7)
   - Tested: 3 concurrent invocations serialize via flock; chain still
     intact (test #11)

## Lifecycle: enabled/disabled boundary

When operator sets `agent_network.primitives.L2.enabled: false`:
- Reconciliation cron deregistered via
  `.claude/scripts/budget/budget-reconcile-install.sh uninstall`
- Counter preserved (read-only); audit log sealed via Sprint 1's
  `audit_seal_chain` with `[L2-DISABLED]` marker (Sprint 2D wires the
  skill-level enable/disable hook)

## Operator runbook addition (Sprint 2B)

Sprint 2C will produce the full `audit-log-recovery.md` runbook. For now,
the install helper is self-documenting via `--help`:

```bash
# Install (read interval_hours from .loa.config.yaml)
.claude/scripts/budget/budget-reconcile-install.sh install

# Show what would be installed (no side effects)
.claude/scripts/budget/budget-reconcile-install.sh show

# Status (installed / not-installed)
.claude/scripts/budget/budget-reconcile-install.sh status

# Uninstall (idempotent)
.claude/scripts/budget/budget-reconcile-install.sh uninstall
```

## Testing strategy

Tests use a mock `OBSERVER` shell-script that emits whatever JSON is in
`OBSERVER_OUT` — making it easy to stage:
- success cases: `{"usd_used": <num>, "billing_ts": "<iso>"}`
- unreachable: missing OUT file → `{"_unreachable": true}`
- defer (rate-limited): `{"_defer": true, "_reason": "rate_limited"}`

The flock test runs 3 cron invocations concurrently and verifies all 3
reconcile envelopes appended in order with intact hash chain.

## Outcome stats

- Files added: 2 scripts + 1 BATS + lib delta = 4 changes
- Tests: 11 (11 PASS / 0 FAIL); cumulative Sprint 2 total: 42 / 42
- Sub-sprint 2B unblocks: 2C (snapshot job) + 2D (skill + integration)
