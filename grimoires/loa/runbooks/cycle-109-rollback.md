# cycle-109 substrate-hardening — rollback runbook

> **Audience**: operators / on-call. **Use when**: a cycle-109 regression
> surfaces in production and you need to fall back to the pre-cycle-109
> substrate. **Read first**: this runbook supersedes any runtime-flag
> rollback guidance from cycle-107 or earlier. **There is no runtime-flag
> rollback path post-cycle-109.**

---

## TL;DR

The cycle-109 cycle removed `hounfour.flatline_routing` as a load-bearing
runtime knob. cheval is now the unconditional substrate dispatch path for
all consumers. Rollback is therefore performed at the **git layer**, not
the **config layer**.

```bash
# 1. Identify the cycle-109 sprint-3 merge commits
git log --oneline --merges --grep "cycle-109" main | head

# 2. Revert each merge commit, newest-first
git revert -m 1 <sprint-3-merge-sha>
git revert -m 1 <sprint-2-merge-sha>
git revert -m 1 <sprint-1-merge-sha>

# 3. Verify CI passes against the reverted tree
gh pr create --base main --title "rollback: cycle-109 → pre-cycle-109 substrate"
gh pr checks --watch

# 4. Once green, restore the pre-cycle-109 `hounfour.flatline_routing: false`
#    config in .loa.config.yaml if your operator state diverged.
```

See [Per-commit revert sequence](#per-commit-revert-sequence) below for
fine-grained reverts that don't unwind the entire cycle.

---

## Decision matrix — when to roll back

| Symptom | Root cause class | Action |
|---|---|---|
| All flatline-review runs emit `status: FAILED` regardless of substrate health | verdict-quality envelope construction bug | Per-commit revert of T2.3 producer integration (`c61dae3f`) |
| `extract_json_content` falls through to `{"improvements":[]}` on Opus shapes | normalize-json regression | Per-commit revert of T3.3 corpus changes if they introduced the parser regression — unlikely, T3.3 was test-only |
| Activation regression matrix runs >15 min on every PR | CI workflow misconfiguration | Per-commit revert of T3.10 (`.github/workflows/activation-regression.yml`) — non-substrate change |
| `model-adapter.sh` always exits with "MODEL_INVOKE not executable" | T3.6 made cheval unconditional; the missing binary path is now a hard error rather than soft fallback | Restore MODEL_INVOKE binary OR revert T3.6 (`d8b1fdd2`) to re-enable legacy fallback |
| Mock-mode tests (FLATLINE_MOCK_MODE=true) fail with "Legacy adapter not found" | T3.7 deleted the legacy file but mock-mode still delegates to it | Revert T3.7 (operator-approved per C109.OP-S3); OR migrate mock-mode fixtures to cheval's --mock-fixture-dir |
| `hounfour.flatline_routing` config key reads no longer change behavior | Expected — cycle-109 phased it out (T3.6 + T3.8) | No action needed; the flag is informational post-T3.8 |
| Multi-model consensus emits FAILED on contradicted BLOCKERs that should be DEGRADED | classify_consensus regression (T2.9) | Revert T2.9 (`8218319a`) to restore "consensus" placeholder |

---

## Per-commit revert sequence

The cycle-109 sprint-3 commit chain (SDD §5.3.1) is built to be
revertible per commit. The order matters: revert in reverse-dependency
order so the working tree never enters an unbootable state.

### Sprint 3 commit chain

| Commit | Task | Revert effect |
|---|---|---|
| A (`fffbe395`) | T3.1 matrix scaffold | Removes activation matrix fixtures + bats. CI workflow at T3.10 still references the bats path; revert T3.10 first OR keep both. |
| B (`3feb1a2a`+`86cd754e`+`46e9ce0e`+`8a4ab4ff`+`93ebf28f`+`3b7b97a8`) | T3.2-T3.5 Cluster B fixes | Removes regression coverage for #864/#863/#793/#820. Substrate behavior unchanged. |
| C (`144f1bd9`+`d8b1fdd2`) | T3.6 feature-flag removal | Restores `is_flatline_routing_enabled` branches at FL + model-adapter main(). Legacy fallback re-activates. |
| D (gated) | T3.7 legacy deletion | Restores `model-adapter.sh.legacy` (1081 LOC). Mock mode resumes working. |
| E (gated) | T3.8 flag removal | Restores `hounfour.flatline_routing` reading sites. |
| F (gated) | T3.9 CLAUDE.md update | Restores pre-cycle-109 Multi-Model Activation section. |

### Sprint 2 commit chain

Sprint 2 commits (T2.1-T2.10) shipped 17 commits in test-first pairs.
The verdict-quality envelope is **additive**; reverting Sprint 2 removes
the `verdict_quality` field from all substrate outputs but does NOT
break the pre-cycle-109 substrate (consumers handle absent
`verdict_quality` gracefully — that backward-compat is verified by
every consumer's bats: T35-1 / T36-4 / VQ1 etc.).

---

## Pre-delete safety baseline

Before T3.7 lands (destructive deletion of legacy file), the SDD §5.3.4
risk mitigation requires capturing a baseline:

```bash
# Captured at commit-C boundary (after T3.6, before T3.7):
grimoires/loa/cycles/cycle-109-substrate-hardening/baselines/legacy-final-baseline.json
```

This snapshot records the last-known-good state of the legacy path
(LOC count, hash, last-modified, behavior trace on a canonical fixture
set). For forensic rollback, the baseline lets operators compare
post-revert substrate behavior against the pre-deletion baseline to
verify the revert actually restored the legacy path correctly.

To capture (run at commit-C boundary, before merging T3.7):

```bash
# From repo root, on the sprint-3 branch:
tools/cycle-baseline-capture.sh \
    --phase pre-delete-legacy \
    --output grimoires/loa/cycles/cycle-109-substrate-hardening/baselines/legacy-final-baseline.json
```

If the baseline is missing when you revert, you can still roll back —
you just lose the forensic delta. Don't block on baseline capture
during an outage.

---

## CI re-validation after rollback

1. After landing the revert PR:
   ```bash
   gh pr checks --watch
   ```

2. Verify the cycle-109 conformance matrix re-runs against the pre-revert
   state and asserts the regressions are CORRECTLY classified per the
   pre-cycle-109 expectations:
   ```bash
   bats tests/unit/cycle-109-conformance-matrix.bats
   ```
   If the matrix now FAILS on fixtures that previously passed, that's the
   signal that the revert introduced a regression in the OPPOSITE direction
   — investigate before merging.

3. Verify the activation regression CI workflow at
   `.github/workflows/activation-regression.yml` doesn't fail on the
   revert's tree shape. The matrix-shape contract gate is the canary;
   if it fails, dimensions.json or fixture paths drifted.

---

## When NOT to roll back

- Cosmetic / log-line changes in cheval substrate
- Non-substrate refactors elsewhere in the repo (e.g., bridgebuilder
  TypeScript hot-path changes; those rollbacks live in BB's own runbook)
- Anything that doesn't directly affect operator-facing flatline /
  bridgebuilder / red-team review output

The cycle-109 rollback path is heavy-weight by design — reverting
multiple sprint merges to restore a pre-substrate-hardening world.
Don't trigger it for issues a per-PR fix-forward can address.

---

## See also

- `grimoires/loa/cycles/cycle-109-substrate-hardening/sprint.md` — sprint plan
- `grimoires/loa/cycles/cycle-109-substrate-hardening/sdd.md` §5.3.1 — commit sequence
- `grimoires/loa/cycles/cycle-109-substrate-hardening/operator-approval.md` — C109.OP-S2 / C109.OP-S3 markers
- `grimoires/loa/cycles/cycle-109-substrate-hardening/baselines/legacy-loc.json` — captured baseline of legacy LOC at cycle-kickoff
- `grimoires/loa/runbooks/audit-log-recovery.md` — adjacent recovery runbook (audit chain rebuild)
- `.github/workflows/activation-regression.yml` — CI activation matrix
