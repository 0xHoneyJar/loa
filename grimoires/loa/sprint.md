# Sprint Plan: Construct-Aware Constraint Yielding

> Cycle: cycle-029 | PRD: grimoires/loa/prd.md | SDD: grimoires/loa/sdd.md
> Source: [#376](https://github.com/0xHoneyJar/loa/issues/376)
> Sprints: 3 | Team: 1 developer (AI-assisted)
> Flatline: PRD reviewed (3 HC, 2 DISPUTED), SDD reviewed (3 HC, 1 DISPUTED)

## Overview

Implement construct-aware constraint yielding across Loa's three enforcement layers. Constructs with manifest `workflow` declarations can compose the pipeline at their chosen depth. 3 sprints ordered by dependency: foundation scripts → constraint integration → events + test suite.

---

## Sprint 1: Manifest Reader + Workflow Activator (global sprint-22)

**Goal**: Build the two foundation scripts that read construct manifests and manage workflow state. After this sprint, a construct pack can declare workflow gates and Loa can detect and track the active construct.

**Dependencies**: None

### Task 1.1: Manifest Workflow Reader Script

**File**: `.claude/scripts/construct-workflow-read.sh`

**Description**: Create shell script that reads and validates the `workflow` section from a pack's manifest.json. Supports two modes: full read (outputs entire workflow JSON) and gate query (outputs specific gate value).

**Acceptance Criteria**:
- [ ] Reads `workflow` section from manifest.json via jq
- [ ] Exit 0 with valid workflow JSON on stdout when workflow section exists
- [ ] Exit 1 when no workflow section (pack uses default pipeline)
- [ ] Exit 2 on validation error (invalid gate values, implement: skip)
- [ ] `--gate <name>` mode outputs single gate value
- [ ] Validates all gate values against allowed sets (SDD Section 3.1 table)
- [ ] `implement: required` enforced — cannot be set to `skip`
- [ ] `condense` accepted but logged as advisory to stderr
- [ ] Defaults applied for missing optional fields (depth: full, app_zone_access: false, etc.)
- [ ] Fail-closed: any jq parse error → exit 1 (no workflow)

**Testing**: Tests in `tests/test_construct_workflow.sh` — valid manifest, missing workflow, implement:skip rejection, condense advisory, invalid values, missing fields with defaults.

### Task 1.2: Construct Workflow Activator Script

**File**: `.claude/scripts/construct-workflow-activate.sh`

**Description**: Manages `.run/construct-workflow.json` lifecycle. Four subcommands: `activate` (creates state file by calling the reader), `deactivate` (removes state file), `check` (returns current state), `gate` (returns specific gate value from active state).

**Acceptance Criteria**:
- [ ] `activate --construct <name> --slug <slug> --manifest <path>` creates `.run/construct-workflow.json`
- [ ] State file contains: construct, slug, manifest_path, activated_at, depth, app_zone_access, gates, verification
- [ ] Activation calls `construct-workflow-read.sh` internally to validate manifest
- [ ] Activation fails (exit 1) if reader returns no workflow, fails (exit 2) if validation error
- [ ] `deactivate` removes `.run/construct-workflow.json`, exits 0 even if file doesn't exist
- [ ] `deactivate --complete <sprint_id>` also creates COMPLETED marker at `grimoires/loa/a2a/<sprint_id>/COMPLETED`
- [ ] `check` exits 0 with JSON on stdout when active, exit 1 when not
- [ ] `gate <gate_name>` outputs gate value when active, exit 1 when not
- [ ] Manifest path validated to be within `.claude/constructs/packs/` (security invariant)

**Testing**: activate/deactivate lifecycle, check states, gate queries, invalid manifest path rejection, deactivate --complete marker creation.

### Task 1.3: Activation Protocol Document

**File**: `.claude/protocols/construct-workflow-activation.md`

**Description**: Document the activation contract for construct SKILL.md authors. Specifies the preamble pattern: check manifest for workflow, call activate, do work, call deactivate.

**Acceptance Criteria**:
- [ ] Protocol document created with activation sequence (SDD Section 3.1.1)
- [ ] Includes example preamble code for SKILL.md files
- [ ] Documents all subcommands and their exit codes
- [ ] References security invariants (installed packs only, fail-closed)

**Testing**: Document review — no code test needed.

---

## Sprint 2: Constraint Yielding + Pre-flight Integration (global sprint-23)

**Goal**: Wire construct awareness into the constraint enforcement layers. After this sprint, constraints.json contains yield metadata, CLAUDE.md renders yield clauses, and command pre-flights respect construct gate declarations.

**Dependencies**: Sprint 1 (state file must exist for pre-flight checks to read)

### Task 2.1: Constraint Data Model — Add `construct_yield` Field

**File**: `.claude/data/constraints.json`

**Description**: Add `construct_yield` object to C-PROC-001, C-PROC-003, C-PROC-004, and C-PROC-008. Each gets `enabled`, `condition`, `yield_text`, and `yield_on_gates` fields per SDD Section 3.4.

**Acceptance Criteria**:
- [ ] C-PROC-001 (`no_code_outside_implement`): yield_text added, yield_on_gates: `["implement"]`
- [ ] C-PROC-003 (`no_skip_to_implementation`): yield_text added, yield_on_gates: `["implement"]`
- [ ] C-PROC-004 (`no_skip_review_audit`): yield_text added, yield_on_gates: `["review", "audit"]`
- [ ] C-PROC-008 (`check_sprint_plan`): yield_text added, yield_on_gates: `["sprint"]`
- [ ] All other constraints unchanged
- [ ] JSON validates with jq

**Testing**: jq validation, field presence checks, no regression on other constraints.

### Task 2.2: Constraint Renderer — Yield Clause Rendering

**Files**: `.claude/scripts/generate-constraints.sh` + `.claude/scripts/templates/claude-loa-md-table.jq`

**Description**: Modify the jq rendering template to append yield_text in parentheses when `construct_yield.enabled` is true. The template `claude-loa-md-table.jq` currently renders `text_variants["claude-loa-md"]` or `rule_type + " " + text` — add a conditional branch that appends `(yield_text)` when `construct_yield.enabled` is present. The orchestrator `generate-constraints.sh` needs no structural changes since it already routes through the template.

**Acceptance Criteria**:
- [ ] `claude-loa-md-table.jq` modified: when `construct_yield.enabled`, appends `({yield_text})` to rendered rule text
- [ ] Constraints WITHOUT `construct_yield` render identically to before (template backward compatible)
- [ ] Hash-based change detection still works (idempotent regeneration)
- [ ] `--dry-run` mode shows preview without modifying CLAUDE.md
- [ ] Run `generate-constraints.sh` and verify `.claude/loa/CLAUDE.loa.md` output includes 4 yield clauses in constraint tables
- [ ] `.claude/loa/CLAUDE.loa.md` regenerated with updated constraint tables (this is a deliverable of this task)

**Testing**: Dry-run comparison, regeneration idempotency check, diff CLAUDE.loa.md before/after to verify only yield clause additions.

### Task 2.3: audit-sprint.md Pre-flight — Construct-Aware Skip

**File**: `.claude/commands/audit-sprint.md`

**Description**: Add `skip_when` fields to the "All good" content check and the engineer-feedback.md file_exists check. When a construct declares `review: skip`, these pre-flight checks are skipped.

**Acceptance Criteria**:
- [ ] `file_exists` check for engineer-feedback.md has `skip_when: {construct_gate: "review", gate_value: "skip"}`
- [ ] `content_contains` check for "All good" has `skip_when: {construct_gate: "review", gate_value: "skip"}`
- [ ] Default behavior unchanged — without active construct, checks enforced as before
- [ ] Comments in YAML explain the skip_when semantics

**Testing**: Manual verification — read the YAML, confirm structure. Integration tested in Sprint 3.

### Task 2.4: review-sprint.md Context Files — Construct-Aware Skip

**File**: `.claude/commands/review-sprint.md`

**Description**: Add `skip_when` to the sprint.md context_files entry. When a construct declares `sprint: skip`, sprint.md becomes optional (loaded if available, absence doesn't block).

**Acceptance Criteria**:
- [ ] `context_files` entry for sprint.md has `skip_when: {construct_gate: "sprint", gate_value: "skip"}`
- [ ] Default behavior unchanged — without active construct, sprint.md still required
- [ ] Comments explain that skip_when on context_files makes the file optional, not ignored

**Testing**: Manual verification — read the YAML, confirm structure. Integration tested in Sprint 3.

---

## Sprint 3: Lifecycle Events + Test Suite + Integration Verification (global sprint-24)

**Goal**: Add observability (lifecycle event logging) and comprehensive test coverage. Verify the full end-to-end flow: manifest → activate → constraint yield → pre-flight skip → deactivate.

**Dependencies**: Sprint 1 + Sprint 2

### Task 3.1: Lifecycle Event Logging

**File**: `.claude/scripts/construct-workflow-activate.sh` (modify)

**Description**: Add audit.jsonl event logging to the activate and deactivate subcommands. Log `construct.workflow.started` on activate and `construct.workflow.completed` on deactivate with full context.

**Acceptance Criteria**:
- [ ] `activate` appends `construct.workflow.started` event to `.run/audit.jsonl`
- [ ] Event includes: timestamp, event name, construct name, depth, gates, constraints_yielded list
- [ ] `constraints_yielded` computed by checking which C-PROC constraints would yield for the declared gates
- [ ] `deactivate` appends `construct.workflow.completed` event to `.run/audit.jsonl`
- [ ] Completed event includes: timestamp, event name, construct name, outcome, duration_seconds
- [ ] Events follow existing audit.jsonl JSON-per-line format

**Testing**: Activate with mock manifest, verify audit.jsonl contains both events with correct fields.

### Task 3.2: Comprehensive Test Suite

**File**: `tests/test_construct_workflow.sh`

**Description**: Complete test suite covering all FRs and NFs per SDD Section 6.2 test matrix. Uses plain bash test harness (same pattern as test_run_state_verify.sh).

**Acceptance Criteria**:
- [ ] All 20 test cases from SDD Section 6.2 implemented
- [ ] Tests use temp directories (no pollution of real .run/ or .claude/)
- [ ] Mock manifests created in temp dir for each test scenario
- [ ] Tests cover: reader validation, activator lifecycle, gate queries, constraint yield rendering, pre-flight skip_when, COMPLETED marker, default behavior, fail-closed
- [ ] **Integration test cases included**: end-to-end flow with mock construct manifest declaring `review: skip`, `audit: skip` — validates reader → activate → state file → gate query → deactivate → cleanup → audit events
- [ ] Integration tests verify: `construct-workflow-read.sh` validates correctly, `construct-workflow-activate.sh activate` creates state file with correct gates, `construct-workflow-activate.sh deactivate` removes state file, `.run/audit.jsonl` contains started+completed events
- [ ] All tests pass: `bash tests/test_construct_workflow.sh` exits 0
- [ ] No regression on existing tests: `bash tests/test_run_state_verify.sh` still passes

**Testing**: Self-testing — the test suite IS the deliverable. Integration verification is included as test cases, not a separate manual step.

---

## Risk Mitigation

| Risk | Sprint | Mitigation |
|------|--------|------------|
| generate-constraints.sh template change breaks output | 2 | Use `--dry-run` preview, diff against current CLAUDE.md |
| skip_when YAML not interpreted correctly by Claude | 2 | Clear comments, integration test in Sprint 3 |
| Stale construct-workflow.json left behind | 1 | Deactivation explicit + session-end cleanup + 24h staleness check |
| Existing tests regress | 3 | Run full test suite before and after |

## File Change Summary

| File | Action | Sprint |
|------|--------|--------|
| `.claude/scripts/construct-workflow-read.sh` | **NEW** | 1 |
| `.claude/scripts/construct-workflow-activate.sh` | **NEW** | 1 |
| `.claude/protocols/construct-workflow-activation.md` | **NEW** | 1 |
| `.claude/data/constraints.json` | MODIFY | 2 |
| `.claude/scripts/templates/claude-loa-md-table.jq` | MODIFY | 2 |
| `.claude/scripts/generate-constraints.sh` | MODIFY (if needed) | 2 |
| `.claude/loa/CLAUDE.loa.md` | REGENERATED (via generate-constraints.sh) | 2 |
| `.claude/commands/audit-sprint.md` | MODIFY | 2 |
| `.claude/commands/review-sprint.md` | MODIFY | 2 |
| `.claude/scripts/construct-workflow-activate.sh` | MODIFY (add events) | 3 |
| `tests/test_construct_workflow.sh` | **NEW** | 3 |

**Total**: 4 new files, 6 modified files, 1 regenerated file.

## Success Metrics

| Metric | Target |
|--------|--------|
| New test count | 20+ (SDD Section 6.2 matrix) |
| Existing test regression | 0 |
| Constraints modified | 4 (C-PROC-001/003/004/008) |
| New scripts | 2 (reader + activator) |
| Commands modified | 2 (audit-sprint.md + review-sprint.md) |
| Backwards compatibility | 100% — no behavior change without active construct |
