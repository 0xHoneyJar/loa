# Audit-Log Recovery Runbook

**Cycle**: cycle-098-agent-network
**Source**: SDD §3.4.4 (recovery procedure) + §3.7 (persistence policy)
**Audience**: Loa operators

## Purpose

L1 (panel-decisions) and L2 (cost-budget-events) audit logs are
chain-critical and UNTRACKED — they are not in git, so `git checkout`
cannot recover them after corruption or accidental deletion. This runbook
is the operator's playbook when those logs are damaged or lost.

## Persistence policy (per SDD §3.7)

| Log | Path | git tracked? | chain critical? | Snapshot cadence |
|-----|------|--------------|-----------------|------------------|
| L1 panel-decisions | `.run/panel-decisions.jsonl` | No | Yes | **Daily** (RPO 24h) |
| L2 cost-budget-events | `.run/cost-budget-events.jsonl` | No | Yes | **Daily** (RPO 24h) |
| L3 cycles | `.run/cycles.jsonl` | No | No | Optional (re-emission idempotent) |
| L4 trust-ledger | `grimoires/loa/trust-ledger.jsonl` | Yes | Yes | Standard PR cadence |

**RPO (Recovery Point Objective) for L1 + L2: 24 hours.** Entries written
between the most recent daily snapshot and the failure point are
unrecoverable. Snapshots are tracked in `grimoires/loa/audit-archive/`.

## Daily snapshot job (Sprint 2C)

The daily snapshot is shipped as `.claude/scripts/audit/audit-snapshot.sh`.
The entire flow is idempotent and safe to invoke ad-hoc.

### Install (one-time setup)

```bash
.claude/scripts/audit/audit-snapshot-install.sh install
```

This appends a marker-tagged crontab line firing at 04:00 UTC by default.
Override schedule via `.loa.config.yaml::audit_snapshot.cron_expression`
(e.g., `"0 3 * * *"` for 03:00 UTC). The default avoids overlap with the
6h reconciliation cron firing on `0 */6 * * *`.

### Verify status

```bash
.claude/scripts/audit/audit-snapshot-install.sh status
```

### Uninstall

```bash
.claude/scripts/audit/audit-snapshot-install.sh uninstall
```

### Manual trigger (e.g., before a planned migration)

```bash
.claude/scripts/audit/audit-snapshot.sh
```

## Recovery procedures

### Scenario 1: Corruption detected mid-session

Symptoms:
- `audit_verify_chain .run/cost-budget-events.jsonl` returns non-zero
- A budget verdict halts with `[CHAIN-BROKEN]` in stderr
- Log file still exists but integrity is suspect

Procedure:

```bash
# 1. Stop active L2 invocations to avoid further writes during recovery.
.claude/scripts/budget/budget-reconcile-install.sh uninstall

# 2. Run the recovery procedure (re-source the lib).
source .claude/scripts/audit-envelope.sh
audit_recover_chain .run/cost-budget-events.jsonl

# 3. Inspect the restored log.
tail -5 .run/cost-budget-events.jsonl
# Look for [CHAIN-RECOVERED source=snapshot_archive snapshot=...]
# Followed by [CHAIN-GAP-RESTORED-FROM-SNAPSHOT-RPO-24H ...]

# 4. Re-install the reconciliation cron.
.claude/scripts/budget/budget-reconcile-install.sh install
```

If `audit_recover_chain` exits non-zero, no snapshot is available — see
Scenario 3.

### Scenario 2: File accidentally deleted

Symptoms:
- `.run/panel-decisions.jsonl` or `.run/cost-budget-events.jsonl` is gone
- Active L1/L2 invocation creates a fresh empty file (chain restarts at
  GENESIS, losing all prior history)

Procedure:

```bash
# Stop active L2 (or L1) invocations.
.claude/scripts/budget/budget-reconcile-install.sh uninstall

# Manually decompress the most recent snapshot.
ls -lt grimoires/loa/audit-archive/*-L2.jsonl.gz | head -1
gzip -dc grimoires/loa/audit-archive/$(ls -t grimoires/loa/audit-archive/*-L2.jsonl.gz | head -1 | xargs basename) > .run/cost-budget-events.jsonl

# Manually append the recovery markers (so the chain knows there's a gap).
{
    echo "[CHAIN-GAP-RESTORED-FROM-SNAPSHOT-RPO-24H snapshot=<basename>]"
    echo "[CHAIN-RECOVERED source=snapshot_archive snapshot=<basename>]"
} >> .run/cost-budget-events.jsonl

# Re-verify.
source .claude/scripts/audit-envelope.sh
audit_verify_chain .run/cost-budget-events.jsonl
```

In practice, just calling `audit_recover_chain` does this for you.

### Scenario 3: No snapshot available

Symptoms:
- `grimoires/loa/audit-archive/` has no `<date>-L2.jsonl.gz` archive for
  the missing log
- Either daily snapshot job never ran, or all archives lost

Procedure:

```bash
# 1. Capture the broken state for forensic analysis.
cp .run/cost-budget-events.jsonl /tmp/l2-broken-$(date +%s).jsonl

# 2. Initialize a fresh chain with explicit gap markers.
{
    echo "[CHAIN-LOST audit_archive_missing reason=no_snapshot_for_recovery ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)]"
    echo "[CHAIN-RESTARTED ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)]"
} > .run/cost-budget-events.jsonl

# 3. Verify and resume.
source .claude/scripts/audit-envelope.sh
audit_verify_chain .run/cost-budget-events.jsonl  # OK 0 entries

# 4. File a forensic note in NOTES.md describing what was lost and when.

# 5. Install the daily snapshot job to prevent recurrence.
.claude/scripts/audit/audit-snapshot-install.sh install
```

### Scenario 4: Snapshot signature verification fails

Symptoms:
- `audit_recover_chain` reports the snapshot's chain integrity check
  failed
- Or `<archive>.sig` file exists but signature does not verify against
  the writer's pubkey

Procedure:
1. Treat as Scenario 3 — no trusted snapshot available
2. Investigate whether the snapshot was tampered with (compare against
   any offsite backup)
3. Rotate the writer's signing key (signing-key compromise playbook in
   `grimoires/loa/runbooks/audit-keys-bootstrap/README.md`)

## Operational expectations

- Snapshots are committed to git as part of the operator's regular workflow
  (e.g., a daily cron + commit hook, or a weekly batch)
- The L1/L2 logs themselves remain UNTRACKED (per SDD §3.7's privacy
  rationale: panelist reasoning + cost data may contain redacted-but-
  sensitive content; daily snapshots are the controlled access path)
- After every snapshot, expect 1 new file:
  `grimoires/loa/audit-archive/<utc-date>-L1.jsonl.gz` (and `-L2`)
- When `LOA_AUDIT_SIGNING_KEY_ID` is configured, a sidecar
  `.jsonl.gz.sig` JSON file accompanies each archive

## Related artifacts

- Snapshot writer: `.claude/scripts/audit/audit-snapshot.sh`
- Snapshot installer: `.claude/scripts/audit/audit-snapshot-install.sh`
- Recovery function: `audit_recover_chain` in `.claude/scripts/audit-envelope.sh`
- Retention policy: `.claude/data/audit-retention-policy.yaml`
- SDD reference: §3.4.4 (recovery procedure), §3.7 (persistence policy)
- Sprint reference: cycle-098 Sprint 2C
