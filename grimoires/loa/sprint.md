# Sprint Plan: Bridge Findings Fix — Iteration 2

**Source**: Bridge review iteration 1 findings (39 findings, score: 137)
**Bridge ID**: bridge-20260212-626561
**PR**: #293
**Date**: 2026-02-12
**Cycle**: cycle-005 (bridge iteration 2)

---

## Overview

| Aspect | Value |
|--------|-------|
| Total Sprints | 2 |
| Team | 1 AI agent (Claude Code via `/run sprint-plan`) |
| Sprint Duration | Autonomous execution |
| Focus | CRITICAL + HIGH findings from bridge review |
| Findings Addressed | 16 CRITICAL/HIGH + 4 MEDIUM (20 of 39) |

---

## Sprint 1: Critical Code Fixes — Security, Correctness, Cross-References

### Sprint Goal

Fix all 5 CRITICAL findings and the most impactful HIGH findings affecting code correctness and security. These are blocking bugs that affect runtime behavior.

### Technical Tasks

#### Task 1.1: Fix JSON Injection in `init_bridge_state` **[CRITICAL-1]**

**File to modify:** `.claude/scripts/bridge-state.sh`

Replace the unquoted heredoc in `init_bridge_state()` with `jq -n --arg` construction for all string values.

**Acceptance Criteria:**
- [ ] `init_bridge_state()` uses `jq -n` with `--arg` for bridge_id, branch, and other string values
- [ ] Branch names containing `"`, `\`, or special characters produce valid JSON
- [ ] All existing bridge-state.bats tests still pass

#### Task 1.2: Fix Subshell Variable Loss in Vision Capture **[CRITICAL-2]**

**File to modify:** `.claude/scripts/bridge-vision-capture.sh`

Replace pipe-to-while patterns with process substitution.

**Acceptance Criteria:**
- [ ] Lines 115-150: `jq ... | while` replaced with `while ... done < <(jq ...)`
- [ ] Lines 156-170: Same fix for second loop
- [ ] `captured` variable correctly reflects actual count after loop
- [ ] All existing bridge-vision-capture.bats tests still pass

#### Task 1.3: Fix Broken Lore Cross-References **[CRITICAL-3, CRITICAL-4, CRITICAL-5]**

**Files to modify:**
- `.claude/data/lore/mibera/core.yaml` — change `flatline` to `glossary-flatline`
- `.claude/data/lore/mibera/rituals.yaml` — change `flatline` to `glossary-flatline`, `ice-defense` to `ice`, `simstim-experience` to `simstim`
- `.claude/data/lore/mibera/glossary.yaml` — change `ice-defense` to `ice`

**Acceptance Criteria:**
- [ ] No `related` field references `flatline` (use `glossary-flatline`)
- [ ] No `related` field references `ice-defense` (use `ice`)
- [ ] No `related` field references `simstim-experience` (use `simstim`)
- [ ] All lore-validation.bats tests still pass

#### Task 1.4: Fix Resume Return Value Bug **[HIGH-1]**

**File to modify:** `.claude/scripts/bridge-orchestrator.sh`

Replace `return "$last_iteration"` with stdout communication in `handle_resume()`.

**Acceptance Criteria:**
- [ ] `handle_resume()` uses `echo "$last_iteration"` to communicate value
- [ ] Caller captures via `start_iteration=$(handle_resume)`
- [ ] Resume works correctly for iteration > 0 under `set -e`

#### Task 1.5: Fix Missing `last_score` Field **[HIGH-6]**

**File to modify:** `.claude/scripts/bridge-state.sh`

Add `last_score` field write to `update_flatline()`.

**Acceptance Criteria:**
- [ ] `update_flatline()` writes `.flatline.last_score = $current_score` to state file
- [ ] `golden_bridge_progress()` in golden-path.sh reads correct non-zero scores
- [ ] All bridge-state.bats tests still pass

#### Task 1.6: Fix printf Format String Injection **[HIGH-2]**

**File to modify:** `.claude/scripts/bridge-github-trail.sh`

Replace `printf` with format-safe construction in `cmd_update_pr()`.

**Acceptance Criteria:**
- [ ] Line 202: no user-controlled data in printf format string
- [ ] PR body construction uses `printf '%s'` or string concatenation
- [ ] All bridge-github-trail.bats tests still pass

#### Task 1.7: Fix Double-Escaping in Findings Parser **[MEDIUM-2]**

**File to modify:** `.claude/scripts/bridge-findings-parser.sh`

Remove manual `sed` escaping before `jq --arg`.

**Acceptance Criteria:**
- [ ] Lines 123-129: remove `sed 's/"/\\"/g'` calls
- [ ] Let `jq --arg` handle JSON string escaping automatically
- [ ] Findings containing quotation marks are correctly represented in JSON
- [ ] All bridge-findings-parser.bats tests still pass

#### Task 1.8: Fix `sed -i` Portability **[MEDIUM-3]**

**File to modify:** `.claude/scripts/bridge-vision-capture.sh`

Replace `sed -i` with portable temp file pattern.

**Acceptance Criteria:**
- [ ] Lines 166, 174: replace `sed -i` with `sed ... > tmp && mv tmp original` pattern
- [ ] Works on both GNU and BSD sed

---

## Sprint 2: Schema Fixes, Documentation Gaps, Test Coverage

### Sprint Goal

Fix HIGH findings in data schemas and documentation, and add critical missing test coverage.

### Technical Tasks

#### Task 2.1: Fix Duplicate ICE Mapping **[HIGH-3]**

**File to modify:** `.claude/data/lore/neuromancer/mappings.yaml`

Merge duplicate `concept: ice` entries.

**Acceptance Criteria:**
- [ ] Single `concept: ice` entry with combined description covering both `run-mode-ice.sh` and circuit breakers
- [ ] YAML parses cleanly

#### Task 2.2: Fix Shared Error Codes **[HIGH-4, HIGH-5]**

**File to modify:** `.claude/data/constraints.json`

Assign unique error codes to duplicated constraints.

**Acceptance Criteria:**
- [ ] C-PROC-003 gets unique error code (E115)
- [ ] C-PROC-007 gets unique error code (E116)
- [ ] No two constraints share the same error_code

#### Task 2.3: Fix CLAUDE.loa.md Documentation Gaps **[HIGH-10, HIGH-11]**

**File to modify:** `.claude/loa/CLAUDE.loa.md`

**Acceptance Criteria:**
- [ ] `run-bridge` added to high danger level list
- [ ] Post-compact recovery section includes `.run/bridge-state.json` check
- [ ] `--from` flag added to bridge usage examples

#### Task 2.4: Fix Test Fixture Schema and Add HALTED Tests **[HIGH-7, HIGH-8, HIGH-9]**

**Files to modify:**
- `tests/unit/bridge-state.bats` — add HALTED transition tests, add update_iteration_findings tests
- `tests/unit/bridge-golden-path.bats` — fix test fixture to match actual schema

**Acceptance Criteria:**
- [ ] 5 new HALTED state transition tests added
- [ ] 3 new update_iteration_findings() tests added
- [ ] ITERATING->ITERATING self-transition test added (MEDIUM-7)
- [ ] bridge-golden-path.bats fixture uses schema that `bridge-state.sh` actually produces
- [ ] All tests pass

#### Task 2.5: Fix Remaining Medium Issues **[MEDIUM-4, MEDIUM-11, MEDIUM-12, MEDIUM-13]**

**Files to modify:**
- `.claude/scripts/bridge-orchestrator.sh` — numeric validation, argument guard
- `.loa-version.json` — add `.run` to state zones
- `.claude/commands/run-bridge.md` — fix related section

**Acceptance Criteria:**
- [ ] `--depth` validates numeric input
- [ ] Argument parsing guards against missing `$2`
- [ ] `.run` added to `zones.state` in `.loa-version.json`
- [ ] Related section in run-bridge.md corrected
- [ ] Protected branch check made unconditional (LOW-1)

---

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| Breaking existing tests | Run full test suite after each task |
| Introducing new bugs in fixes | Minimal surgical changes, run parser/state tests |
| System zone edits | Required for fixing scripts — within bridge iteration context |
