# Runbook: ledger hygiene rotation (cycle-124 FR-6)

**When**: `tools/check-ledger-hygiene.sh` exits 1 (CI post-test step, `pre-push-audit` hook, or by hand) because `.run/cost-ledger.jsonl` or `.run/model-invoke.jsonl` carries test rows — `mock-*` identities, `/tmp/cheval-e2e-*` paths, or (not scanned, but cleared by the same rotation) `/tmp/pytest-of-*` paths.

**Rule**: rotate, never edit. The MODELINV log is hash-chained and mutated only through `audit-envelope.sh` (agent-network invariant); the cost ledger is not chained and moves whole. Fix the leaking harness first (see `.claude/adapters/tests/conftest.py`, `tests/unit/ledger-isolation-discovery.bats`) or the fresh files fill up again.

## 1. MODELINV log — verify → seal → move → verify

```bash
bash .claude/scripts/audit-envelope.sh verify-chain .run/model-invoke.jsonl   # must print "OK N entries"
bash .claude/scripts/audit-envelope.sh seal MODELINV .run/model-invoke.jsonl  # appends the [MODELINV-DISABLED] marker
mkdir -p .run/archive
ARCHIVE=".run/archive/model-invoke-$(date -u +%Y%m%dT%H%M%SZ).jsonl"
mv .run/model-invoke.jsonl "$ARCHIVE"
bash .claude/scripts/audit-envelope.sh verify-chain "$ARCHIVE"                # seal markers are skipped by the walk
```

The next `audit_emit` finds no file and starts the fresh chain at `prev_hash: GENESIS` (`_audit_compute_prev_hash`; pinned by `tests/integration/ledger-hygiene-tripwire.bats` LH-7). Verification uses the host's signing posture — on an operator box with `LOA_AUDIT_SIGNING_KEY_ID` set the archive is signed and verifies under the trust-store cutoff; do not unset the key for this step.

## 2. Cost ledger — precondition, then move whole

Every test row must be priced at zero, so the `.run/.daily-spend-*.json` sidecars need no recomputation:

```bash
grep '"mock-' .run/cost-ledger.jsonl | grep -vc '"cost_micro_usd": *0[,}]'   # must print 0 (grep exits 1 on a zero count — that is the pass)
mv .run/cost-ledger.jsonl ".run/archive/cost-ledger-$(date -u +%Y%m%dT%H%M%SZ).jsonl"
```

If the count is not 0, stop: a test row carried real pricing and the sidecar totals for those days are wrong — recompute them from the archive before moving on.

## 3. Verify and record

```bash
bash tools/check-ledger-hygiene.sh        # expect two "SKIP: … absent" lines and exit 0
grep '^{' "$ARCHIVE" | jq -c . | head -3  # archive rows are JSON; its LAST line is the
                                          # `[MODELINV-DISABLED]` rotation seal, not JSON
ls -la .run/archive/                      # both archive paths
```

Record both archive paths in the sprint report. `git revert` cannot restore moved untracked files — the recorded paths are the rollback data (PRD §7).

## 4. Consumers on the fresh log

`economy.py`, `health.py`, `journal.py`, `modelinv-rollup.sh` and `modelinv-coverage-audit.py` read the fresh chain (empty until the next dispatch). `tests/unit/modelinv-v1.3-backcompat.bats` V11 replays `$PROJECT_ROOT/.run/model-invoke.jsonl` as its oracle (path fixed at line 38, no env override) and skips on an absent file; to replay the archive, run it from a scratch worktree whose `.run/` holds a copy:

```bash
WT="$(mktemp -d)/loa-backcompat"; git worktree add -q "$WT" HEAD
mkdir -p "$WT/.run" && cp "$ARCHIVE" "$WT/.run/model-invoke.jsonl"
(cd "$WT" && npx --no-install bats tests/unit/modelinv-v1.3-backcompat.bats)
git worktree remove --force "$WT"
```

(A one-line env override in that bats file would remove the worktree step; it is outside Task 1.1's file set.)

## 5. Restore (rollback)

Seal the fresh chain first, then move the archive back; the archive's trailing seal marker stays mid-file and is skipped by both the prev-hash walk and verification, so appends continue the original chain.

```bash
bash .claude/scripts/audit-envelope.sh seal MODELINV .run/model-invoke.jsonl
mv .run/model-invoke.jsonl ".run/archive/model-invoke-fresh-$(date -u +%Y%m%dT%H%M%SZ).jsonl"
mv "$ARCHIVE" .run/model-invoke.jsonl
bash .claude/scripts/audit-envelope.sh verify-chain .run/model-invoke.jsonl
mv .run/archive/cost-ledger-<stamp>.jsonl .run/cost-ledger.jsonl
```
