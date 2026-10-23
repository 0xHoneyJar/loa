# Sprint Plan: Bug Fix — `archive-cycle.sh` archives the wrong cycle by default, deletes git-tracked archives by default, and never updates the live ledger

**Type**: bugfix
**Bug ID**: 20261021-ba367a
**Source**: /bug (triage) — operator instruction 2026-10-21 ("fix the archive script's cycle detection and its default deletion of tracked archives"); issue #1263 (ledger never updated) folded in: same script, same contract section, open reproduction
**Sprint**: sprint-bug-266

---

## sprint-bug-266: `archive-cycle.sh` default cycle, tracked-archive protection, live-ledger update

### Sprint Goal
Fix the reported bug with a failing test proving the fix: the default `--cycle` is the ledger's active or newest cycle; nothing git-tracked is deleted and the default retention keeps every archive; a real archive updates the live ledger exactly as `.claude/commands/archive-cycle.md` documents, refusing an incomplete cycle unless `--force`.

### Deliverables
- [ ] Failing test that reproduces the bug (`tests/unit/archive-cycle-default-and-ledger.bats` ACL-1 … ACL-7)
- [ ] Source code fix (`.claude/scripts/archive-cycle.sh`: default cycle, keep-all default, tracked skip, ledger mutation, `--force`; `.claude/commands/archive-cycle.md`)
- [ ] All existing tests pass (no regressions: `archive-cycle-retention.bats`, `archive-cycle-per-subdir.bats`, `post-merge-archive-gate.bats`, `ledger-lib` suites)
- [ ] Triage analysis document

### Technical Tasks

#### Task 1: Write Failing Test [G-5]
- Create unit tests reproducing the bug
- Verify tests fail with current code
- Test file: `tests/unit/archive-cycle-default-and-ledger.bats`

**Acceptance Criteria**:
- Tests fail with current code, proving the bug exists: ACL-1/2 name `cycle-<count>` with the legacy fallback; ACL-3 deletes 5; ACL-4 lists tracked directories for deletion; ACL-5 leaves the ledger unchanged; ACL-7 archives an incomplete cycle
- Test names clearly describe the bug scenario
- Tests are isolated (scratch git repo, scratch ledger and config under `$BATS_TEST_TMPDIR`; the repository's `grimoires/`, `.loa.config.yaml` and archives are never read or written)
- Committed alone (`test(20261021-ba367a): failing test`) before any fix commit; SHA recorded in `reviewer.md` as `Red commit: <sha>`

#### Task 2: Implement Fix [G-1, G-2]
- Fix root cause in `.claude/scripts/archive-cycle.sh` (`get_current_cycle`; `RETENTION` default; `cleanup_old_archives` tracked skip; ledger mutation through `ledger-lib.sh` + `--force` gate) and `.claude/commands/archive-cycle.md`
- Verify failing tests now pass
- Run `tests/unit/archive-cycle-*.bats`, `tests/unit/post-merge-archive-gate.bats`, `tests/unit/ledger*.bats`

**Acceptance Criteria**:
- Failing tests now pass
- No regressions in existing tests
- Fix addresses root cause (the script derives its defaults from the ledger and protects tracked history; one ledger mutation shared with `ledger-lib.sh` primitives), not just symptoms (no per-call flag advice, no relaxed exit code)
- The fix is a later commit and does not weaken the test (`.claude/scripts/red-test-check.sh --red <Red commit> -- <test command>` exits 0)

#### Task 3: Documentation and record
- `archive-cycle.sh` header (default cycle rule, retention keep-all default, tracked protection, `--force`, exit codes); `archive-cycle.md`; `repo-map-gen.sh` regen + `--validate` (+ `.checksum` sidecar); `.claude/checksums.json` regen; `bash -n`
- CHANGELOG `[Unreleased]` `### Fixed` entry (closes #1263); `reviewer.md` with `## AC Verification` (file:line per row) and the E2E: on this repository `archive-cycle.sh --dry-run` now names `archive/cycle-131-honest-measurement` and reports nothing to delete

### Acceptance Criteria
- [ ] Bug is no longer reproducible: the default dry run names the newest cycle and deletes nothing; a pruning run never removes a tracked directory; a real archive updates the live ledger
- [ ] Failing test proves the fix
- [ ] No regressions in existing tests
- [ ] Fix addresses root cause (not just symptoms)

### Triage Reference
See: grimoires/loa/a2a/bug-20261021-ba367a/triage.md
