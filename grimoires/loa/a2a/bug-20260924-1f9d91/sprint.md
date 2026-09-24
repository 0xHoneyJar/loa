# Sprint Plan: Bug Fix — `check-permissions.sh` (preflight P2) reads only `.claude/settings.json` and treats deny entries as allowed

**Type**: bugfix
**Bug ID**: 20260924-1f9d91
**Source**: /bug (triage) — follow-up bead `bd-n7v3` from cycle-125 sprint-243 review round 1 (MEDIUM); maintainer instruction "proceed as you suggest" (2026-09-24)
**Sprint**: sprint-bug-246

---

## sprint-bug-246: `check-permissions.sh` reads only `.claude/settings.json` and treats deny entries as allowed

### Sprint Goal
Fix the reported bug with a failing test proving the fix: the run-mode permission check evaluates the same three settings layers Claude Code evaluates (`~/.claude/settings.json`, `.claude/settings.json`, `.claude/settings.local.json`), matches rules as JSON arrays rather than file text, lets a deny rule in any layer win, and tells the operator which file to fix.

### Deliverables
- [x] Failing test that reproduces the bug (`tests/unit/check-permissions.bats` CP-1..CP-8)
- [x] Source code fix (`check-permissions.sh` layered read + jq matching + deny-wins + `--root`; `run-preflight.sh` P2 wording)
- [x] All existing tests pass (no regressions)
- [x] Triage analysis document

### Technical Tasks

#### Task 1: Write Failing Test [G-5]
- Create unit tests reproducing the bug
- Verify tests fail with current code
- Test file: `tests/unit/check-permissions.bats`

**Acceptance Criteria**:
- Tests fail with current code, proving the bug exists: rules only in `settings.local.json` or `~/.claude/settings.json` → 16 missing; a pattern only inside `deny` → reported found; a deny rule for a required rule → exit 0
- Test names clearly describe the bug scenario
- Tests are isolated (temp `--root` and temp `HOME`; the repository's settings files are never read or written)

#### Task 2: Implement Fix [G-1, G-2]
- Fix root cause in `.claude/scripts/check-permissions.sh` (layered files, jq array evaluation, deny wins, `--root`, `denied` + `settings_files` in output, remedy names `settings.local.json`) and `.claude/scripts/run-preflight.sh` (P2 detail/fix text)
- Verify failing tests now pass
- Run `check-permissions.bats`, `run-preflight.bats`, `settings-permissions.bats`

**Acceptance Criteria**:
- Failing tests now pass
- No regressions in existing tests
- Fix addresses root cause (the checker evaluates the effective permission set), not just symptoms (no per-repo workaround, no relaxed exit code)

#### Task 3: Documentation and record
- `check-permissions.sh` header (layers, exit codes, `--root`), run-preflight P2 text; `repo-map-gen.sh` regen + `--validate` (+ `.checksum` sidecar), `.claude/checksums.json` regen, `bash -n`
- CHANGELOG `[Unreleased]` entry; `reviewer.md` with `## AC Verification` (file:line per row) and the E2E: on this machine `check-permissions.sh --json` still exits 0 and now lists the three files it consulted; a scratch root whose rules live only in `settings.local.json` passes, and a scratch deny of `Bash(git push:*)` is reported as denied; `run-preflight.sh --unattended` P2 unchanged (PASS)

### Acceptance Criteria
- [x] Bug is no longer reproducible: rules in any layer are effective; a deny entry never counts as allowed and a deny rule in any layer reports the rule as denied with its file
- [x] Failing test proves the fix
- [x] No regressions in existing tests
- [x] Fix addresses root cause (not just symptoms)

### Triage Reference
See: grimoires/loa/a2a/bug-20260924-1f9d91/triage.md
