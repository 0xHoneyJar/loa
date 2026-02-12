# Sprint Plan: Bridge Findings Fix — Iteration 3

**Source**: Bridge review iteration 2 findings (33 findings, score: 72)
**Bridge ID**: bridge-20260212-626561
**PR**: #293
**Date**: 2026-02-12
**Cycle**: cycle-005 (bridge iteration 3)

---

## Overview

| Aspect | Value |
|--------|-------|
| Total Sprints | 2 |
| Team | 1 AI agent (Claude Code via `/run sprint-plan`) |
| Sprint Duration | Autonomous execution |
| Focus | CRITICAL + HIGH + MEDIUM findings from bridge review |
| Findings Addressed | 1 CRITICAL + 6 HIGH + 9 MEDIUM (16 of 27 actionable) |

---

## Sprint 1: Critical & High Fixes — Correctness, Security, Schema

### Sprint Goal

Fix the CRITICAL field name mismatch, all HIGH security/correctness bugs, and the schema validation gaps. These directly affect runtime behavior and data integrity.

### Technical Tasks

#### Task 1.1: Fix `sprint_plan_source` field name mismatch in github-trail.sh [CRITICAL-1]

**File**: `.claude/scripts/bridge-github-trail.sh`
**What**: In `cmd_update_pr()` around line 180, change `.iterations[$i].source` to `.iterations[$i].sprint_plan_source`.
**Why**: Every iteration row in the PR summary silently displays "existing" because the jq query reads a non-existent field.
**AC**: The jq query reads `.iterations[$i].sprint_plan_source` and correctly displays "findings" for iteration 2+.

#### Task 1.2: Fix CLI-vs-config precedence inversion in bridge-orchestrator.sh [HIGH-2]

**File**: `.claude/scripts/bridge-orchestrator.sh`
**What**: In `load_bridge_config()`, only apply config values for variables that were NOT explicitly set via CLI flags. Track which were CLI-set using sentinel variables (e.g., `CLI_DEPTH=""` at top, set `CLI_DEPTH="$2"` in `--depth` handler, skip config override if `CLI_DEPTH` is set).
**Why**: `--depth 5` on CLI is silently overridden by config file's `depth: 3`. Standard precedence is CLI > config > default.
**AC**: Running `bridge-orchestrator.sh --depth 5` with a config that has `depth: 3` uses depth=5. Without `--depth`, uses config value.

#### Task 1.3: Fix shell injection in cmd_comment heredoc [HIGH-3]

**File**: `.claude/scripts/bridge-github-trail.sh`
**What**: At lines 106-117, replace the unquoted `<<EOF` heredoc with string concatenation. The review body content must not be subject to shell expansion.
**Why**: Review markdown containing backticks or `$()` patterns could be executed by the shell.
**AC**: Body is constructed using string concatenation. The `$(cat "$review_body")` is captured separately, then interpolated without shell expansion risk.

#### Task 1.4: Fix sed injection via unsanitized $title in vision capture [HIGH-4]

**File**: `.claude/scripts/bridge-vision-capture.sh`
**What**: At line 166, sanitize `$title` before using in sed pattern: `safe_title=$(printf '%s' "$title" | sed 's/[\\/&]/\\\\&/g')`. Then use `$safe_title` in the sed command.
**Why**: Vision titles containing `/`, `&`, or `\` break the sed command.
**AC**: A title like "Use Input/Output Buffers" does not break the sed command.

#### Task 1.5: Add bridge/eval to constraint schema enum [HIGH-1 configs]

**File**: `.claude/schemas/constraints.schema.json`
**What**: Add `"bridge"` and `"eval"` to the `category` enum.
**Why**: Constraint validation rejects bridge and eval entries because the schema doesn't list these categories.
**AC**: Running schema validation against constraints.json produces no category errors.

#### Task 1.6: Add bridge_constraints marker block to CLAUDE.loa.md [HIGH-2 configs]

**File**: `.claude/loa/CLAUDE.loa.md`
**What**: Add `<!-- @constraint-generated: start bridge_constraints -->` / `<!-- @constraint-generated: end bridge_constraints -->` marker block within the Run Bridge section. Populate with a table rendering the 5 C-BRIDGE constraints from constraints.json.
**Why**: Bridge constraints are defined in data layer but never rendered, making them invisible.
**AC**: Bridge constraints table appears in CLAUDE.loa.md Run Bridge section with all 5 C-BRIDGE rules.

#### Task 1.7: Create bridge-orchestrator.bats test file [HIGH-5 tests]

**File**: `tests/unit/bridge-orchestrator.bats`
**What**: Create test file covering:
- `--depth` without a value exits 2
- `--depth 0` and `--depth 11` are rejected (exit 2)
- `--depth abc` is rejected (exit 2)
- `--from` without a value exits 2
- Running on `main` branch exits 2
- Resume from HALTED returns correct iteration number
- Resume from non-resumable state exits 1
**Why**: Significant behavioral changes in orchestrator have zero test coverage.
**AC**: All tests pass. At least 7 test cases covering argument validation, branch protection, and resume logic.

---

## Sprint 2: Medium Fixes — Robustness, Docs, Test Coverage

### Sprint Goal

Fix the most impactful MEDIUM findings: sanitize PR body output, add missing argument guards, fix documentation inconsistencies, and fill test coverage gaps.

### Technical Tasks

#### Task 2.1: Fix echo -e interpreting escape sequences in PR body [MEDIUM-5 scripts]

**File**: `.claude/scripts/bridge-github-trail.sh`
**What**: At line 217, replace `echo -e "$new_body"` with real newlines from the start. Build `body` using `$'\n'` newlines instead of literal `\n` sequences, then use `printf '%s' "$new_body"`.
**Why**: Existing PR body content fetched from GitHub may contain `\n`, `\t` etc. that get interpreted by echo -e.
**AC**: PR body update preserves all literal backslash sequences in existing content.

#### Task 2.2: Add $2 validation guards to vision-capture and findings-parser [MEDIUM-7]

**Files**: `.claude/scripts/bridge-vision-capture.sh`, `.claude/scripts/bridge-findings-parser.sh`
**What**: Add `${2:-}` guards with explicit error messages to all argument parsers, matching the pattern in bridge-orchestrator.sh.
**Why**: Missing value after flag causes unhelpful error or undefined behavior with `set -u`.
**AC**: Running `bridge-vision-capture.sh --findings` (no value) produces "ERROR: --findings requires a value" and exits 2.

#### Task 2.3: Fix O(n^2) JSON array growth in findings parser [MEDIUM-8]

**File**: `.claude/scripts/bridge-findings-parser.sh`
**What**: Replace the `jq ... '. + [$f]'` loop with collecting JSON objects into a temp file, then `jq -s '.'` at the end.
**Why**: O(n^2) complexity causes slowdown with large reviews.
**AC**: Findings are collected into a temp file and slurped into a final array with single jq invocation.

#### Task 2.4: Fix depth limit mismatch — tighten to 1-5 [MEDIUM-3 configs]

**File**: `.claude/scripts/bridge-orchestrator.sh`
**What**: Change depth validation from `1-10` to `1-5` to match documentation. Line 174: change `10` to `5`.
**Why**: Script accepts 1-10 but all docs say max 5. Bridge iterations are expensive; conservative limit is safer.
**AC**: `--depth 6` is rejected with error message.

#### Task 2.5: Update Three-Zone Model docs to include .run [MEDIUM-4 configs]

**File**: `.claude/loa/CLAUDE.loa.md`
**What**: Update the Three-Zone Model table State row to: `| State | grimoires/, .beads/, .ck/, .run/ | Read/Write |`
**Why**: .run was added to state zones in .loa-version.json but not reflected in CLAUDE.loa.md.
**AC**: Three-Zone Model table lists all 4 state zone paths.

#### Task 2.6: Add sed end-marker for bridge summary in PR body [MEDIUM-9 scripts]

**File**: `.claude/scripts/bridge-github-trail.sh`
**What**: Add `<!-- bridge-summary-end -->` marker when building the bridge summary section. Change the sed deletion to target between start and end markers instead of to EOF.
**Why**: Current sed deletes everything after the summary, destroying any manually-added content.
**AC**: Bridge summary has end marker. Content after the end marker is preserved on update.

#### Task 2.7: Add last_score and get_current_iteration tests [MEDIUM-1, MEDIUM-2 tests]

**File**: `tests/unit/bridge-state.bats`
**What**:
- Add `last_score` assertions to existing flatline tests (verify jq '.flatline.last_score' returns expected value)
- Add `get_current_iteration` tests: zero iterations returns "0", after 2 iterations returns "2", missing file returns "0"
**Why**: These are public API functions/fields with no test assertions.
**AC**: At least 4 new test assertions pass.

#### Task 2.8: Update golden-path HALTED and JACKED_OUT fixtures to full schema [MEDIUM-3/4 tests]

**File**: `tests/unit/bridge-golden-path.bats`
**What**: Update the HALTED (line 78) and JACKED_OUT (line 93) detect_bridge_state fixtures AND the HALTED bridge_progress fixture (line 145) to use full schema matching the ITERATING fixtures (with schema_version, timestamps, bridgebuilder, metrics, finalization, flatline).
**Why**: Minimal fixtures pass by coincidence of jq defaults. Full schema ensures consistency.
**AC**: All 3 fixtures use full bridge state schema. All 11 golden-path tests pass.
