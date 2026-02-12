# Sprint Plan: Onboarding UX — Hive-Inspired Improvements

**PRD**: grimoires/loa/prd.md (v1.0.0)
**SDD**: grimoires/loa/sdd.md (v1.0.0)
**Source**: [PR #290](https://github.com/0xHoneyJar/loa/pull/290)
**Date**: 2026-02-12
**Cycle**: cycle-004

---

## Sprint 1: Context-Aware `/loa` Menu (FR-1)

**Global ID**: sprint-8
**Local ID**: sprint-1
**Goal**: Replace the static 3-option AskUserQuestion in `/loa` with a dynamic, state-aware menu that routes to the correct skill.
**Estimated effort**: Low

### Tasks

#### Task 1.1: Add `golden_detect_workflow_state()` to golden-path.sh

**File**: `.claude/scripts/golden-path.sh`
**Action**: Add new function that returns one of 9 states based on file presence checks.
**Acceptance Criteria**:
- [ ] Function returns exactly one of: `initial`, `prd_created`, `sdd_created`, `sprint_planned`, `implementing`, `reviewing`, `auditing`, `complete`, `bug_active`
- [ ] Priority order: bug_active > initial > prd_created > sdd_created > implementing > reviewing > auditing > complete > sprint_planned
- [ ] Bug detection uses existing `golden_detect_active_bug()`
- [ ] Planning phases use existing `golden_detect_plan_phase()`

#### Task 1.2: Add `golden_menu_options()` to golden-path.sh

**File**: `.claude/scripts/golden-path.sh`
**Action**: Add function that outputs pipe-delimited menu options per state.
**Acceptance Criteria**:
- [ ] Each state produces exactly 3 context-specific options + 1 constant ("View all commands")
- [ ] `implementing` state includes correct sprint-N number in label
- [ ] `bug_active` state includes truncated bug title (max 40 chars)
- [ ] Output format: `label|description|action` (one per line)
- [ ] Slot 1 is always the recommended action

#### Task 1.3: Update `/loa` command with dynamic menu

**File**: `.claude/commands/loa.md`
**Action**: Replace static AskUserQuestion (lines 202-215) with dynamic menu powered by `golden_menu_options()`.
**Acceptance Criteria**:
- [ ] Menu options are state-dependent, not static
- [ ] Slot 1 labeled "(Recommended)"
- [ ] Routing table maps action values to skill invocations
- [ ] Destructive option "Plan new cycle" requires confirmation
- [ ] Fallback: display copyable command on skill invocation failure
- [ ] `/loa --json` still works without menu

#### Task 1.4: Add framework eval tasks

**Files**: `evals/tasks/framework/golden-menu-*.yaml`
**Action**: Create 3 eval tasks testing menu output for different states.
**Acceptance Criteria**:
- [ ] `golden-menu-initial.yaml`: Tests output when no PRD exists
- [ ] `golden-menu-implementing.yaml`: Tests sprint-N in label
- [ ] `golden-menu-bug.yaml`: Tests bug title in label
- [ ] All tasks pass in framework eval suite
- [ ] Baseline updated

---

## Sprint 2: Post-Mount Verification (FR-2)

**Global ID**: sprint-9
**Local ID**: sprint-2
**Goal**: Add a verification step to `mount-loa.sh` that validates the install after sync.
**Estimated effort**: Medium

### Tasks

#### Task 2.1: Implement `verify_mount()` function

**File**: `.claude/scripts/mount-loa.sh`
**Action**: Add function that checks framework files, deps, optional tools, and API key presence.
**Acceptance Criteria**:
- [ ] Checks: framework files, config, jq, yq, git, br (optional), ck (optional), ANTHROPIC_API_KEY (advisory)
- [ ] JSON output via `jq -n --arg` (not string concatenation — Flatline SKP-004)
- [ ] NFR-8: Zero key material in any output — boolean presence only
- [ ] Exit 0 for success+warnings, exit 1 for failure
- [ ] `--strict` flag converts warnings to failure
- [ ] `--quiet` flag suppresses output
- [ ] `--json` flag for structured output

#### Task 2.2: Wire verify_mount() into mount flow

**File**: `.claude/scripts/mount-loa.sh`
**Action**: Call `verify_mount` after feature gates enforcement (line ~1192), before banner.
**Acceptance Criteria**:
- [ ] Verification runs automatically on standard mount
- [ ] `--quiet` passed through from main() args
- [ ] Mount does NOT fail if only warnings (optional tools missing)
- [ ] Mount DOES fail if required deps missing (shouldn't happen — preflight catches these)

#### Task 2.3: Update completion banner

**File**: `.claude/scripts/mount-loa.sh` (or `upgrade-banner.sh`)
**Action**: Update next-steps section to reference `/loa setup` as step 2.
**Acceptance Criteria**:
- [ ] Next steps show: 1) Start Claude Code, 2) Run `/loa setup`, 3) Start planning with `/plan`

#### Task 2.4: Add framework eval tasks

**Files**: `evals/tasks/framework/mount-verify-*.yaml`
**Action**: Create eval tasks for verification function.
**Acceptance Criteria**:
- [ ] `mount-verify-json.yaml`: Tests `--json` produces valid JSON
- [ ] `mount-verify-redaction.yaml`: Tests no `sk-` patterns in output
- [ ] All tasks pass, baseline updated

---

## Sprint 3: Setup Wizard + Archetypes (FR-3 + FR-4)

**Global ID**: sprint-10
**Local ID**: sprint-3
**Goal**: Create `/loa setup` wizard and project archetype templates for `/plan`.
**Estimated effort**: Medium
**Dependencies**: Shares validation pattern with Sprint 2's `verify_mount()`.

### Tasks

#### Task 3.1: Create `loa-setup-check.sh` validation engine

**File**: `.claude/scripts/loa-setup-check.sh` (NEW)
**Action**: Shell script that validates environment and outputs JSONL.
**Acceptance Criteria**:
- [ ] Outputs one JSON line per check (step, name, status, detail)
- [ ] Step 1: API key presence (boolean only — NFR-8, no length)
- [ ] Step 2: Required deps (jq, yq, git) with version info
- [ ] Step 3: Optional tools (br, ck) with install instructions
- [ ] Step 4: Config status (feature toggles from .loa.config.yaml)
- [ ] Exit 0 if all required pass, exit 1 if any required fail
- [ ] Executable standalone: `.claude/scripts/loa-setup-check.sh`

#### Task 3.2: Create `/loa setup` command file

**File**: `.claude/commands/loa-setup.md` (NEW)
**Action**: Markdown command that drives the 4-step interactive wizard.
**Acceptance Criteria**:
- [ ] Runs `loa-setup-check.sh` and presents results
- [ ] Step 4 uses AskUserQuestion with multiSelect for feature toggles
- [ ] Updates `.loa.config.yaml` via `yq` only with user consent
- [ ] `--check` flag runs non-interactive validation only
- [ ] Never writes secrets to disk

#### Task 3.3: Create archetype template files

**Files**: `.claude/data/archetypes/{rest-api,cli-tool,library,fullstack}.yaml` (NEW)
**Action**: Create 4 YAML templates with context for common project types.
**Acceptance Criteria**:
- [ ] Each template has: name, description, tags, context (vision, technical, non_functional, testing, risks)
- [ ] Each template < 50 lines
- [ ] Valid YAML (parseable by yq)

#### Task 3.4: Add archetype selection to `/plan`

**File**: `.claude/commands/plan.md`
**Action**: Add archetype selection step before Phase 1 for first-time projects.
**Acceptance Criteria**:
- [ ] Only shown when no PRD exists AND no completed cycles in ledger
- [ ] Lists archetypes from `.claude/data/archetypes/` via yq
- [ ] "Other" skips to standard blank-slate interview
- [ ] Selected archetype written to `grimoires/loa/context/archetype.md`
- [ ] Context ingestion pipeline picks up archetype automatically

#### Task 3.5: Add framework eval tasks

**Files**: `evals/tasks/framework/setup-check-*.yaml`, `evals/tasks/framework/archetype-*.yaml`
**Action**: Create eval tasks for setup and archetypes.
**Acceptance Criteria**:
- [ ] `setup-check-redaction.yaml`: No `sk-` patterns in output
- [ ] `archetype-schema.yaml`: All archetypes have required fields
- [ ] All tasks pass, baseline updated

---

## Sprint 4: Polish — Qualification + Formatting Pack (FR-5 + FR-6)

**Global ID**: sprint-11
**Local ID**: sprint-4
**Goal**: Add use-case qualification to `/plan` and design the auto-formatting construct pack.
**Estimated effort**: Low
**Note**: FR-6 ships in the loa-constructs repo, not this one. This sprint creates the spec only.

### Tasks

#### Task 4.1: Add use-case qualification to `/plan`

**File**: `.claude/commands/plan.md`
**Action**: Add brief qualification step before archetype selection for first-time projects.
**Acceptance Criteria**:
- [ ] Shows "Loa works best for..." guidance
- [ ] Only for first-time projects (same skip conditions as archetypes)
- [ ] AskUserQuestion: "Continue?" or "Show me what Loa adds"
- [ ] Never blocks — always allows continuing
- [ ] "Show me what Loa adds" displays feature comparison

#### Task 4.2: Create auto-format construct pack spec

**File**: `grimoires/loa/a2a/sprint-4/auto-format-construct-spec.md` (NEW)
**Action**: Document the construct pack specification for auto-formatting hooks.
**Acceptance Criteria**:
- [ ] Pack manifest format defined
- [ ] Hook scripts for: Python (ruff), JS/TS (prettier), Go (gofmt), Rust (rustfmt)
- [ ] Installation via `/constructs` documented
- [ ] Non-destructive: doesn't overwrite existing hooks
- [ ] Language detection strategy documented

#### Task 4.3: Version bump and CHANGELOG

**Action**: Bump version to 1.34.0, update CHANGELOG with all sprint deliverables.
**Acceptance Criteria**:
- [ ] `.loa-version.json` → 1.34.0
- [ ] `README.md` version badge → 1.34.0
- [ ] `.claude/loa/CLAUDE.loa.md` version header → 1.34.0
- [ ] `CHANGELOG.md` entry for v1.34.0 with all features

---

## Sprint Summary

| Sprint | Global ID | FRs | Files Modified | Files Created | LOC |
|--------|-----------|-----|----------------|---------------|-----|
| 1 | sprint-8 | FR-1 | 2 | 3 eval tasks | ~130 |
| 2 | sprint-9 | FR-2 | 1 | 2 eval tasks | ~100 |
| 3 | sprint-10 | FR-3, FR-4 | 1 | 6 new + 2 eval | ~250 |
| 4 | sprint-11 | FR-5, FR-6 | 1 | 1 spec doc | ~50 |
| **Total** | | | **5** | **14** | **~530** |

## Ledger Registration

Sprints to register in `grimoires/loa/ledger.json`:

```json
"sprints": ["sprint-8", "sprint-9", "sprint-10", "sprint-11"]
```

Global sprint counter advances from 7 to 11.
