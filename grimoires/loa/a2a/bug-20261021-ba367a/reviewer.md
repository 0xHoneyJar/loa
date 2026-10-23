# sprint-bug-266 (bug 20261021-ba367a) — implementer A report

Model: global.anthropic.claude-opus-5-5
Red commit: 868e22e7 (fix: 86755261)

## What was built
- **Task 1 (tests)**: `tests/unit/archive-cycle-default-and-ledger.bats` (new, ACL-1…ACL-7). It builds a scratch git repo under `$BATS_TEST_TMPDIR` with hermetic copies of archive-cycle.sh, bootstrap.sh, path-lib.sh and ledger-lib.sh, plus a five-entry modern ledger. The ACL-1 active cycle is not the newest, so "active first" and "max" are told apart.
- **Task 2 (fix)** in `.claude/scripts/archive-cycle.sh`:
  - `get_current_cycle` (:173) returns the active cycle number, else the max `cycle-N`, else 1. An unreadable ledger is an error.
  - `RETENTION=0` (:49) is the default. `load_config` (:93) reads the yaml key only when present and rejects non-integers.
  - `--force` (:86) and `_count_incomplete_sprints` (:194) copy the ledger-lib `archive_cycle` gate. It runs before any write (:252, refusal :292); dry-run only reports.
  - `_update_ledger_archived` (:209) sources ledger-lib.sh in a subshell, locks, and writes via `_write_ledger`. It runs after the archive's ledger copy (:350), never under `--dry-run`.
  - `_archive_dir_tracked` (:366) and the partition in `cleanup_old_archives` (:423, WARN :434) keep tracked dirs.
  - The header documents every new rule, flag and exit code.
- **Task 3 (docs)**: `.claude/commands/archive-cycle.md` gets a "Script Contract" table (:121) and an error row (:235).

## Red run
At red, 6 of 7 fail by assertion and ACL-6 passes (it pins the dry-run no-write behaviour):
```
not ok 1 ACL-1 …  `[[ "$output" == *"Would create archive at: "*"/grimoires/loa/archive/cycle-120-active"* ]]' failed
not ok 2 ACL-2 …  `[[ "$output" == *"Would create archive at: "*"/grimoires/loa/archive/cycle-131-done"* ]]' failed
not ok 3 ACL-3 …  `[[ "$output" == *"Nothing to delete"* ]]' failed
not ok 4 ACL-4 …  `[[ "$output" == *"tracked archive kept: "*"/archive/cycle-test-${i}; prune it with git"* ]]' failed
not ok 5 ACL-5 …  `[ "$(jq -r '.active_cycle' "$L")" = "null" ]' failed
ok 6 ACL-6: --dry-run leaves the ledger byte-identical
not ok 7 ACL-7 …  `[ "$status" -eq 1 ]' failed
```
On a clean `git archive HEAD` export, red gives these 6 failures and full gives 7/7.

## How it was tested
Command: `~/.cache/loa/cycle-128/s2d/bin/bats <file>` per file, plus `bash -n .claude/scripts/archive-cycle.sh` (OK).

| File | ok | not ok |
|---|---|---|
| archive-cycle-default-and-ledger.bats | 7 | 0 |
| archive-cycle-retention.bats | 5 | 0 |
| archive-cycle-per-subdir.bats | 6 | 0 |
| post-merge-archive-gate.bats | 8 | 0 |
| ledger-lib.bats | 42 | 0 |
| ledger-transactions.bats | 16 | 0 |
| ledger-compound-validation.bats | 7 | 0 |
| ledger-isolation-discovery.bats | 5 | 0 |

None of the existing tests encodes the old default: retention passes an explicit `--retention`, and per-subdir passes an explicit `--cycle` with `--retention 0`. No existing test was edited. shellcheck is not installed on this host, so it was not run. `tools/check-no-raw-sha256sum.sh` passes. The fix removed two `|| echo` swallow shapes and added none (archive-cycle.sh is not in the jq scanner's enforced set).

Manual scratch checks (`~/.cache/loa/cycle-132/scratch-bug-a-checks.sh`) passed for the yaml key, a bad yaml value, a blocked ledger lock (exit 1, ledger unchanged) and a missing ledger.

E2E in the worktree, which holds the real ledger and archives. The ledger was byte-identical afterwards:
```
$ bash .claude/scripts/archive-cycle.sh --dry-run
[DRY-RUN] Would create archive at: …/loa-wt-buga/grimoires/loa/archive/cycle-131-honest-measurement
[DRY-RUN] Cycle id: cycle-131-honest-measurement
[DRY-RUN] Would update ledger: cycle-131-honest-measurement status=archived, archived=<now>, archive_path=grimoires/loa/archive/cycle-131-honest-measurement
[DRY-RUN] Artifact source: /home/merlin/Documents/thj/code/loa/grimoires/loa   (copy list elided)
[DRY-RUN] retention 0 (default: no --retention, no compound_learning.archive.retention_cycles) → keeping all archives, skipping cleanup
[DRY-RUN] Nothing to delete
$ bash .claude/scripts/archive-cycle.sh --cycle 131 --retention 1 --dry-run   (tail)
[DRY-RUN] Would keep 2 git-tracked archive(s) past retention=1:
[WARN] tracked archive kept: …/archive/2026-02-26-cycle-042-vision-activation; prune it with git
[WARN] tracked archive kept: …/archive/2026-02-25-organizational-memory-sovereignty; prune it with git
[DRY-RUN] Nothing to delete (every archive past retention=1 is git-tracked)
```

## AC evidence
- Failing test reproduces each fault: PASS. See the red run above, failing at test lines 99, 109, 119, 133, 156 and 182.
- Names descriptive, tests isolated: PASS, `tests/unit/archive-cycle-default-and-ledger.bats:19-66`.
- Tests committed alone: the lead does this with bug-a-red.patch, which touches only the test file (red.stat).
- Failing tests now pass: PASS, 7/7.
- No regressions: PASS, see the table.
- Root cause fixed: PASS, `archive-cycle.sh:173` (default cycle), `:366`/`:423` (tracked), `:209` (ledger-lib mutation); no exit code relaxed.
- The fix does not weaken the test: the test file is identical between red and full. The lead runs red-test-check.sh.
- Header and docs: PASS, `archive-cycle.sh:7-46` and `archive-cycle.md:121-131`.
- E2E: PASS. The default dry run names `archive/cycle-131-honest-measurement` and deletes nothing.
- Bug no longer reproducible: PASS, by the E2E above and ACL-4/ACL-5.

## DECISION bullets
- DECISION: The tracked check uses `git ls-files --error-unmatch`, not `ls-files | grep -q .`. Under `set -o pipefail`, an early-exiting grep can SIGPIPE git and turn a tracked directory into a false "untracked". Any git exit code other than 1 (no match) counts as tracked, so a directory that cannot be verified is kept rather than deleted.
- DECISION: A missing ledger-lib.sh WARNs, skips the ledger update and exits 0. I rejected exit 1 because the per-subdir AC-1.4 hermetic copies lack the lib and I don't own that test.
- DECISION: Re-archiving re-stamps `archived` and `archive_path`, as ledger-lib `archive_cycle` does. I rejected keeping the first timestamp, since that archive was overwritten.
- DECISION: `archive_path` is relative to the repo root, per the contract and the cycle-131 row; a dir outside the root stays absolute.
- DECISION: A ledger update failure after the archive exists exits 1 naming the archive and leaves it in place. I rejected a deleting rollback on an error path.
- DECISION: The completeness gate applies only when the cycle has a ledger entry. A legacy-fallback cycle with no entry archives as before and prints that the ledger was not updated.
- DECISION: `--dry-run` exits 0 even when the gate would refuse; it prints what a real run would do and that `--force` overrides it.
- DECISION: A non-integer yaml `retention_cycles` exits 1 instead of reaching `[[ -le ]]` as garbage. A yq read failure is treated as an absent key, which means keep-all, the safe direction.
- DECISION: The deletion set is the old keep-newest-N set minus tracked dirs; tracked dirs are not replaced by older untracked ones.
- DECISION: An unreadable ledger while deriving the default cycle exits 1 with "pass --cycle N". I rejected the old silent fallback to 1.
- DECISION: Tracked-kept WARNs go to stderr; the dry run adds one stdout header, leaving the deletion list format unchanged.

## CHANGELOG entry text (`### Fixed`)
- `archive-cycle.sh` now defaults to the ledger's active or newest cycle instead of `cycle-<entry count>`, keeps every archive unless a retention is set, and never deletes git-tracked archive directories. A real archive now records `status`, `archived`, `archive_path` and `active_cycle: null` in the live ledger, refusing incomplete cycles unless `--force` (bug 20261021-ba367a, bead <bead-id>; closes #1263).

## What the lead must do
- Apply `bug-a-red.patch` and commit, then apply `bug-a-full.patch` (code, doc and test file) and commit. `grimoires/loa/a2a/` is gitignored, so copy this report to the record branch's `bug-20261021-ba367a/reviewer.md` yourself. Run `red-test-check.sh --red <sha> -- ~/.cache/loa/cycle-128/s2d/bin/bats tests/unit/archive-cycle-default-and-ledger.bats`.
- Regenerate `.claude/checksums.json` and REPO-MAP (with `--validate` and the `.checksum` sidecar), and add the CHANGELOG bullet. No bead references ba367a in `.beads/`, so fill in the bead id.
- Out of scope, worth a note: the real ledger's cycle-131 entry stores an absolute `prd` path into the main checkout, so from a worktree the artifact source resolves to the main checkout's grimoire. That predates this fix; the artifact-root resolver is unchanged.
- Run shellcheck in CI, since it is not installed here.
- Optional follow-up: add ledger-lib.sh to the hermetic copy in archive-cycle-per-subdir.bats, then flip the missing-lib case to fail closed.
