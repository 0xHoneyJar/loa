# Sprint Plan: Bug Fix — post-pr-orchestrator marks a degraded or failed Flatline PR review green; the kind:cli prompt-size failure behind the fleet report is fixed upstream since rc.3 (bd-jm55c)

**Type**: bugfix
**Bug ID**: 20261021-4439fd
**Source**: /bug (triage) — bead bd-jm55c (fleet request ono-sendai 2026-10-20, KF-039 recurrence 2); operator instruction 2026-10-21 ("the CLI Claude voice prompt-size failure (bd-jm55c)")
**Sprint**: sprint-bug-267

---

## sprint-bug-267: Flatline PR review verdict quality reaches the post-PR state; failed phases read `failed`

### Sprint Goal
Fix the reported bug with a failing test proving the fix: a DEGRADED or FAILED Flatline PR review (or one with no verdict-quality envelope) is recorded as a `failed` phase with a degraded summary and a non-green marker and never adds `PR-VALIDATED`; a timed-out or failed orchestrator run is `failed`, never `skipped`. Record that the prompt-transport half is fixed since rc.3 and answer the fleet.

### Deliverables
- [ ] Failing test that reproduces the bug (`tests/unit/post-pr-flatline-degraded.bats` PFD-1 … PFD-7)
- [ ] Source code fix (`.claude/scripts/post-pr-orchestrator.sh` `phase_flatline_pr`)
- [ ] All existing tests pass (no regressions: `tests/unit/post-pr-*.bats`)
- [ ] Triage analysis document; KF-039 attempt row; fleet reply sent

### Technical Tasks

#### Task 1: Write Failing Test [G-5]
- Create unit tests reproducing the bug
- Verify tests fail with current code
- Test file: `tests/unit/post-pr-flatline-degraded.bats`

**Acceptance Criteria**:
- Tests fail with current code, proving the bug exists: PFD-1/3 record `completed` + `PR-VALIDATED`; PFD-4/5 record `skipped`; PFD-6 records `completed`
- Test names clearly describe the bug scenario
- Tests are isolated (stub orchestrator under `$BATS_TEST_TMPDIR`, scratch `.run/` and state; the repository's `.run/` is never touched)
- Committed alone (`test(20261021-4439fd): failing test`) before any fix commit; SHA recorded in `reviewer.md` as `Red commit: <sha>`

#### Task 2: Implement Fix [G-1, G-2]
- Fix root cause in `.claude/scripts/post-pr-orchestrator.sh` (`phase_flatline_pr`: capture the `--json` envelope, read `verdict_quality.status`, `failed` + summary + `FLATLINE-PR-DEGRADED` on DEGRADED/FAILED/missing, `failed` on timeout/other; blocker and orchestrator-error branches unchanged)
- Verify failing tests now pass
- Run `tests/unit/post-pr-*.bats`

**Acceptance Criteria**:
- Failing tests now pass
- No regressions in existing tests
- Fix addresses root cause (the verdict is read; a failed phase is named failed), not just symptoms (no marker-only change, no new config)
- The fix is a later commit and does not weaken the test (`.claude/scripts/red-test-check.sh --red <Red commit> -- <test command>` exits 0)

#### Task 3: Documentation and record
- `post-pr-orchestrator.sh` header / phase doc-comment; `repo-map-gen.sh` regen + `--validate` (+ `.checksum` sidecar); `.claude/checksums.json` regen; `bash -n`
- KF-039 attempt row (`kf-write-lib.sh attempt --id KF-039 … --evidence "398859ad 10436350; ono-sendai .loa 764d80f8 rc.2; sprint-bug-267"`); fleet reply via `hosaka/.mailbox/bin/send.sh` (lead sends)
- CHANGELOG `[Unreleased]` `### Fixed` entry; `reviewer.md` with `## AC Verification` (file:line per row) and the E2E: the stub-driven DEGRADED run ends `READY_FOR_HITL` with `flatline_pr: failed`, marker `FLATLINE-PR-DEGRADED`, summary file present

### Acceptance Criteria
- [ ] Bug is no longer reproducible: a DEGRADED verdict never reads green; a failed or timed-out Flatline run reads `failed`
- [ ] Failing test proves the fix
- [ ] No regressions in existing tests
- [ ] Fix addresses root cause (not just symptoms)

### Triage Reference
See: grimoires/loa/a2a/bug-20261021-4439fd/triage.md
