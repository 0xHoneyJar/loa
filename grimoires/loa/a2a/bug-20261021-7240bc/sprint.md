# Sprint Plan: Bug Fix — `seed-corpus-from-record.sh --build-manifest` regresses the curated multi-site manifests because `labels/pr-NN.tsv` cannot express them (bd-y4pqj)

**Type**: bugfix
**Bug ID**: 20261021-7240bc
**Source**: /bug (triage) — bead bd-y4pqj (cycle-131 follow-up); operator instruction 2026-10-21 ("the labels file drift (bd-y4pqj)")
**Sprint**: sprint-bug-268

---

## sprint-bug-268: labels files reproduce the curated manifests byte for byte

### Sprint Goal
Fix the reported bug with a failing test proving the fix: every record fixture's labels file holds one row per curated anchor (text when unique, `@L<n>` otherwise) and the manifest's approval line, so `--build-manifest pr-NN` reproduces the tracked manifest byte for byte, and a bats case pins that for pr-11 … pr-18.

### Deliverables
- [ ] Failing test that reproduces the bug (`evals/tests/seed-corpus.bats` SC-9 … SC-12)
- [ ] Source code fix (`evals/harness/seed-corpus-from-record.sh`: `@L<n>` grammar, `--sync-labels`; the eight labels files synced; `SHA256SUMS` refrozen)
- [ ] All existing tests pass (no regressions: `evals/tests/` 534 cases)
- [ ] Triage analysis document

### Technical Tasks

#### Task 1: Write Failing Test [G-5]
- Create unit tests reproducing the bug
- Verify tests fail with current code
- Test file: `evals/tests/seed-corpus.bats` (SC-9 byte-identical rebuild for pr-11 … pr-18; SC-10 `@L<n>`; SC-11 `--sync-labels` idempotent; SC-12 freeze/check)

**Acceptance Criteria**:
- Tests fail with current code, proving the bug exists: SC-9 differs on every record fixture; SC-10 refuses `@L5`; SC-11/12 report an unknown mode
- Test names clearly describe the bug scenario
- Tests are isolated (scratch corpus under `$BATS_TEST_TMPDIR` holding only labels, manifests, `fixture.yaml` and the head files the labels name; the tracked corpus is read, never written)
- Committed alone (`test(20261021-7240bc): failing test`) before any fix commit; SHA recorded in `reviewer.md` as `Red commit: <sha>`

#### Task 2: Implement Fix [G-1, G-2]
- Fix root cause in `evals/harness/seed-corpus-from-record.sh` (`@L<n>` explicit-line form in `build_manifest`; `--sync-labels pr-NN`; header docs), run `--sync-labels` over pr-11 … pr-18, `--freeze`
- Verify failing tests now pass
- Run the whole `evals/tests/`

**Acceptance Criteria**:
- Failing tests now pass; the tracked manifests are byte-identical to before (`git diff --stat -- evals/fixtures/review-prs/manifests` empty)
- No regressions in existing tests
- Fix addresses root cause (one source of truth the generator can express), not just symptoms (no hand-edited manifests, no skipped fixtures)
- The fix is a later commit and does not weaken the test (`.claude/scripts/red-test-check.sh --red <Red commit> -- <test command>` exits 0)

#### Task 3: Documentation and record
- Script header (modes, `@L<n>` grammar), labels header comment; `bash -n`
- CHANGELOG `[Unreleased]` `### Fixed` entry; `reviewer.md` with `## AC Verification` (file:line per row) and the E2E: `--build-manifest pr-17` on a scratch copy reproduces the tracked manifest (`cmp` silent) and `--check` passes; bead bd-y4pqj closed by the lead at completion

### Acceptance Criteria
- [ ] Bug is no longer reproducible: every record fixture rebuilds byte for byte
- [ ] Failing test proves the fix
- [ ] No regressions in existing tests
- [ ] Fix addresses root cause (not just symptoms)

### Triage Reference
See: grimoires/loa/a2a/bug-20261021-7240bc/triage.md
