# Sprint Plan: Bug Fix — The post-merge pipeline cannot cut a pre-release (no rc entry, release never flagged `prerelease`, README check rejects an rc version)

**Type**: bugfix
**Bug ID**: 20260923-27d899
**Source**: /bug (triage) — operator prompt `grimoires/loa/a2a/prompts/release-2.0.0-rc1-2026-09-23.md` §4 Phase A, executed inside PR #1266
**Sprint**: sprint-bug-240

---

## sprint-bug-240: The post-merge pipeline cannot cut a pre-release

### Sprint Goal
Fix the reported bug with failing tests proving the fix: when the topmost CHANGELOG heading names a release candidate of the version the commits warrant, the prepared candidate, its tag and its GitHub release carry that prerelease version and the release is flagged `prerelease`; a later heading naming the bare version promotes out of the prerelease; the README version check accepts a prerelease framework version.

### Deliverables
- [x] Failing tests that reproduce the bug (`tests/unit/semver-bump.bats`, `tests/unit/post-merge-publication.bats`, `tests/unit/sync-readme-version.bats`)
- [x] Source code fix (`semver-bump.sh` transition, orchestrator release flag + candidate field, `sync-readme-version.sh` prerelease support)
- [x] All existing tests pass (no regressions)
- [x] Triage analysis document

### Technical Tasks

#### Task 1: Write Failing Tests [G-5]
- Create unit tests reproducing the bug
- Verify tests fail with current code
- Test files: `tests/unit/semver-bump.bats` (5 cases), `tests/unit/post-merge-publication.bats` (2 cases), `tests/unit/sync-readme-version.bats` (3 cases)

**Acceptance Criteria**:
- Tests fail with current code, proving the bug exists: rc heading ignored (`next 2.0.0`), no `prerelease_transition` field, candidate without `prerelease`, release POST without the flag, `--check` exit 2 on `2.0.0-rc.1`
- Test names clearly describe the bug scenario
- Tests are isolated (temp fixtures; mocked `gh`; no writes to the repo or `.run/`)

#### Task 2: Implement Fix [G-1, G-2]
- Fix root cause in `.claude/scripts/semver-bump.sh` (CHANGELOG-signalled enter/promote transition, additive `prerelease_transition` output), `.claude/scripts/post-merge-orchestrator.sh` (`prerelease` on the candidate, the POST body and the read-back), `.claude/scripts/sync-readme-version.sh` (prerelease grammar, shields `--` escaping, lock-step sed)
- Verify failing tests now pass
- Run the touched suites and the release-pipeline suites (`post-merge-*.bats`, `semver-*.bats`, `release-notes-gen.bats`, `sync-readme-version.bats`)

**Acceptance Criteria**:
- Failing tests now pass
- No regressions in existing tests
- Fix addresses root cause (a formal, tested transition the pipeline reads), not just symptoms (no hand-edited candidate, no manual tag)

#### Task 3: Documentation and record
- Runbook section in `grimoires/loa/runbooks/post-merge-candidates.md` and a paragraph in `PROCESS.md` Versioning Contract (signal, `rc.1 → rc.2`, promotion, marker sync)
- `repo-map-gen.sh` regen + `--validate`, `.claude/checksums.json` regen, `bash -n` on touched scripts
- CHANGELOG entry; `reviewer.md` with `## AC Verification` (file:line per row)

### Acceptance Criteria
- [x] Bug is no longer reproducible: the sandbox from triage returns `next 2.0.0-rc.1`, the candidate carries `prerelease: true`, the mocked release POST carries `prerelease: true`, `--check` exits 0 on the rc version
- [x] Failing test proves the fix
- [x] No regressions in existing tests
- [x] Fix addresses root cause (not just symptoms)

### Triage Reference
See: grimoires/loa/a2a/bug-20260923-27d899/triage.md
