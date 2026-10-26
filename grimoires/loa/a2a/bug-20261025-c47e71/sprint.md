# Sprint Plan: Bug Fix — `classify-pr-type.sh` classifies housekeeping merges from a `chore/` branch as `cycle` when the branch name carries the cycle id (bd-ahxmh)

**Type**: bugfix
**Bug ID**: 20261025-c47e71
**Source**: /bug (triage) — bead bd-ahxmh (found at the cycle-134 close, 2026-10-25); operator instruction 2026-10-26 ("do what can easily be done")
**Sprint**: sprint-bug-277

---

## sprint-bug-277: housekeeping merges classify `other`

### Sprint Goal
Fix the reported bug with a failing test proving the fix: a merge from a `chore/…` branch or a subject with the conventional `chore` prefix classifies `other` even when it names a cycle, so the archive, ledger and decisions-confirm merges no longer prepare a release candidate; cycle merges, labelled PRs and `fix` subjects keep their classification.

### Deliverables
- [ ] Failing test that reproduces the bug (`tests/unit/post-merge-classifier.bats` PCT-T28 …: the two real archive merge subjects, the squash form, the ledger push, the decisions merge → `other`; chore + `cycle` label → `cycle`; the Sprint 276 merge subject → `cycle`)
- [ ] Source code fix (`.claude/scripts/classify-pr-type.sh`: one housekeeping rule before the cycle-id rule; header comment)
- [ ] All existing tests pass (no regressions: `post-merge-classifier.bats` 27 cases, `classify-merge-pr.bats` KF063-T1 … T14, `post-merge-workflow-guards.bats`)
- [ ] System Zone manifests regenerated in the fix commit (`checksums.json`, `REPO-MAP.md`) under the bounded marker
- [ ] Triage analysis document

### Technical Tasks

#### Task 1: Write Failing Test [G-5]
- Create unit tests reproducing the bug
- Verify tests fail with current code
- Test file: `tests/unit/post-merge-classifier.bats`

**Acceptance Criteria**:
- Tests fail with current code, proving the bug exists: every housekeeping subject prints `cycle` today
- Test names clearly describe the bug scenario (archive merge, squash form, ledger push, decisions merge, label precedence, sprint merge unchanged)
- Tests are isolated (the classifier is run with `--title`/`--labels` only; no git, no network)
- Committed alone (`test(20261025-c47e71): failing test`) before any fix commit; SHA recorded in `reviewer.md` as `Red commit: <sha>`

#### Task 2: Implement Fix [G-1, G-2]
- Fix root cause in `.claude/scripts/classify-pr-type.sh` (`classify_pr_type`: after the labels rule and before `\bcycle-[0-9]+\b`, return `other` for `^Merge pull request #[0-9]+ from [^ ]+/chore/` or `^chore(\([^)]*\))?:`); header comment names the rule and the incident
- Verify failing tests now pass
- Run `tests/unit/post-merge-classifier.bats`, `tests/unit/classify-merge-pr.bats`, `tests/unit/post-merge-workflow-guards.bats`, `bash -n`

**Acceptance Criteria**:
- Failing tests now pass; the three suites are green
- No regressions in existing tests (the PCT backtest list still classifies `cycle`)
- Fix addresses root cause (rule order: housekeeping recognised before the cycle-id keyword), not just symptoms (no special-casing of the two subjects)
- The fix is a later commit and does not weaken the test (`.claude/scripts/red-test-check.sh --red <Red commit> -- npx --no-install bats tests/unit/post-merge-classifier.bats` exits 0)
- System Zone manifests regenerated in the same commit (`tools/gen-checksums.sh --check`, `tools/check-manifest-paths.sh`, `repo-map-gen.sh --validate` pass)

#### Task 3: Documentation and record
- CHANGELOG `[Unreleased]` `### Fixed` entry (bd-ahxmh); `reviewer.md` with `## AC Verification` (file:line per row) and the E2E: the classifier on the live subjects of PR #1293 / #1297 / #1298 prints `other`, on PR #1296 prints `cycle`

### Acceptance Criteria
- [ ] Bug is no longer reproducible: the archive merge subjects classify `other`
- [ ] Failing test proves the fix
- [ ] No regressions in existing tests
- [ ] Fix addresses root cause (not just symptoms)

### Triage Reference
See: grimoires/loa/a2a/bug-20261025-c47e71/triage.md
