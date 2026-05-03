# Sub-sprint 2C Progress Report — Daily snapshot job

**Cycle**: cycle-098-agent-network
**Sprint**: 2 (L2 cost-budget-enforcer + reconciliation cron + daily snapshot)
**Sub-sprint**: 2C (3 of 4)
**Branch**: `feat/cycle-098-sprint-2`
**Status**: COMPLETED

## Outcome

The producer side of the L1/L2 hash-chain recovery loop is in place. Sprint 1C
shipped `_audit_recover_from_snapshot` in `audit-envelope.sh` (consumer); 2C
ships `audit-snapshot.sh` (producer) and the operator runbook so RPO 24h is
genuinely 24h, not aspirational.

The daily snapshot reads `.claude/data/audit-retention-policy.yaml`,
filters to chain-critical UNTRACKED primitives (L1, L2 by default),
gzip-compresses each rolling log to
`grimoires/loa/audit-archive/<utc-date>-<primitive>.jsonl.gz`, and
optionally signs the archive (`.sig` JSON sidecar) when an operator
writer key is configured.

The runbook (`grimoires/loa/runbooks/audit-log-recovery.md`) is the
operator's playbook for 4 recovery scenarios: corruption mid-session,
file deleted, no snapshot available, and signature failure.

## Files added

### Snapshot scripts

| File | Purpose |
|------|---------|
| `.claude/scripts/audit/audit-snapshot.sh` | Snapshot writer — reads retention policy, validates source chain, gzip-compresses, optionally signs |
| `.claude/scripts/audit/audit-snapshot-install.sh` | Operator helper for crontab integration (`install`/`uninstall`/`status`/`show`) |

### Tests

| File | Type | Count | Status |
|------|------|-------|--------|
| `tests/integration/audit-snapshot.bats` | bats | 13 | 13 PASS / 0 FAIL |

### Runbook

| File | Purpose |
|------|---------|
| `grimoires/loa/runbooks/audit-log-recovery.md` | Operator runbook — 4 recovery scenarios, install/uninstall, RPO/RTO docs |

## ACs satisfied

### Sprint 2 deliverable (sprint.md)

- **Daily snapshot job for L1/L2 untracked logs** (per SKP-001 §3.4.4↔§3.7
  reconciliation, RPO 24h, was 7d) — DONE
- **Snapshot-archive restore path documented in runbook** — DONE

### Cross-cutting (CC-2 + CC-11 round-out)

- Snapshots flow into the existing `_audit_recover_from_snapshot` pathway —
  verified end-to-end by integration test #10 (snapshot → corrupt log →
  audit_recover_chain → markers present)
- Optional Ed25519 signature sidecar `.jsonl.gz.sig` carries
  `{schema_version, primitive_id, utc_day, sha256, signing_key_id, signed_at, signature}`
- `.gitkeep`-equivalent: `grimoires/loa/audit-archive/` is created on first
  snapshot

### Idempotency + safety guarantees

- Same-day re-runs do not overwrite existing archives (test #3)
- Broken source chain refuses to snapshot (test #5) — never archive corruption
- Missing source log gracefully skipped, not errored (test #6)
- chain_critical=false primitives skipped (test #7)
- git_tracked=true primitives skipped (test #8) — no double-archival

## Recovery flow (end-to-end demonstrated)

```
Steady state (each day at 04:00 UTC):
  daily cron → audit-snapshot.sh →
    For each chain-critical, untracked primitive:
      1. Read .run/<basename> rolling log
      2. audit_verify_chain — refuse if broken
      3. gzip → grimoires/loa/audit-archive/<utc-day>-<P>.jsonl.gz
      4. Optionally Ed25519-sign → <archive>.sig

Failure recovery (mid-session corruption or accidental rm):
  audit_recover_chain .run/<basename> →
    1. audit_verify_chain — chain broken? continue
    2. Try git history (TRACKED logs only) — fail for L1/L2 (UNTRACKED)
    3. Try snapshot archive — locate latest <date>-<P>.jsonl.gz
    4. Validate snapshot's internal chain integrity — refuse if broken
    5. Decompress + restore + append markers:
         [CHAIN-GAP-RESTORED-FROM-SNAPSHOT-RPO-24H snapshot=<basename>]
         [CHAIN-RECOVERED source=snapshot_archive snapshot=<basename>]
```

## Lifecycle: enabled/disabled boundary

When operator sets `agent_network.primitives.L2.enabled: false`:
- `.claude/scripts/budget/budget-reconcile-install.sh uninstall` (Sprint 2B)
- `.claude/scripts/audit/audit-snapshot-install.sh uninstall` (Sprint 2C) is
  optional — operator may want to keep the daily snapshot of L1 even when
  L2 is disabled. The snapshot script gracefully skips primitives whose
  source log is missing.

## Operator runbook scenarios

The runbook covers:
1. Corruption mid-session — `audit_recover_chain` Just Works
2. File deleted — `audit_recover_chain` finds latest snapshot and restores
3. No snapshot available — capture forensic, restart with [CHAIN-LOST] marker
4. Snapshot signature failure — treat as no-snapshot + investigate tampering

## Outcome stats

- Files added: 2 scripts + 1 BATS + 1 runbook = 4 artifacts
- Tests: 13 (13 PASS / 0 FAIL); cumulative Sprint 2 (2A+2B+2C) = 55 / 55
- Sub-sprint 2C unblocks: 2D (skill + integration with full runbook
  reference)
