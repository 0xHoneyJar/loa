# Sprint Plan: Bug Fix — Aleph gates block Loa; make Aleph opt-in

**Type**: bugfix
**Bug ID**: 20260922-13a3d1
**Source**: /bug (triage) — maintainer directive 2026-09-22, executed inside PR #1266
**Sprint**: sprint-bug-239

---

## sprint-bug-239: Aleph gates block Loa; make Aleph opt-in

### Sprint Goal
Fix the reported bug with a failing test proving the fix: Loa's required CI, mount/update path and health check no longer depend on Aleph bytes unless an operator has opted in; the opted-in behaviour is unchanged.

### Deliverables
- [ ] Failing test that reproduces the bug (`tests/unit/aleph-opt-in.bats`)
- [ ] Source code fix (opt-in predicate in front of every Aleph reach-in; config key documented)
- [ ] All existing tests pass (no regressions; the three Aleph suites skip unless opted in)
- [ ] Triage analysis document

### Technical Tasks

#### Task 1: Write Failing Test [G-5]
- Create unit tests reproducing the bug
- Verify tests fail with current code
- Test file: `tests/unit/aleph-opt-in.bats`

**Acceptance Criteria**:
- Tests fail with current code, proving the bug exists: the mount predicate returns 0 with no opt-in; `check-loa.sh` runs the Aleph check with no opt-in; the Aleph suites do not skip; the workflows have no gate; the config example has no `aleph.enabled`
- Test names clearly describe the bug scenario
- Tests are isolated (temp fixtures; no writes to the repo or `.run/`)

#### Task 2: Implement Fix [G-1, G-2]
- Fix root cause in `.claude/scripts/lib/aleph-opt-in.sh` (new), `.claude/scripts/mount-submodule.sh`, `.claude/scripts/check-loa.sh`, the three Aleph bats suites, `.github/workflows/aleph-bundle-integrity.yml`, `.github/workflows/aleph-release-sync.yml`, `.loa.config.yaml.example`, `.loa.config.yaml`
- Verify failing tests now pass
- Run full test suite

**Acceptance Criteria**:
- Failing tests now pass
- No regressions in existing tests (`skill-capabilities.bats`, `hook-wiring.bats`, mount/update suites, full `tests/unit/`)
- Fix addresses root cause (Aleph is opt-in everywhere it touches Loa), not just symptoms (no revert of the `capabilities:` block, no edit to Aleph-managed files)

#### Task 3: Verification and record
- `lint-invariants.sh`, `repo-map-gen.sh` regen + `--validate`, `.claude/checksums.json` regen, `bash -n` on touched scripts
- CHANGELOG entry; `reviewer.md` with `## AC Verification` (file:line per row)

### Acceptance Criteria
- [ ] Bug is no longer reproducible: `Shell Tests` and `Verify install` cannot go red on Aleph bytes when `aleph.enabled` is false
- [ ] Failing test proves the fix
- [ ] No regressions in existing tests
- [ ] Fix addresses root cause (not just symptoms)

### Triage Reference
See: grimoires/loa/a2a/bug-20260922-13a3d1/triage.md
