# Sprint Plan: Bug Mode — Lightweight Bug-Fixing Workflow

**PRD**: grimoires/loa/prd.md (v1.1.0)
**SDD**: grimoires/loa/sdd.md (v1.1.0)
**Issue**: [loa #278](https://github.com/0xHoneyJar/loa/issues/278)
**Date**: 2026-02-11

---

## Sprint 1: Core Bug Triage Skill & Micro-Sprint Infrastructure

### Sprint Goal
Deliver the `/bug` command with full triage workflow, micro-sprint creation, test-first execution through existing `/implement`, and quality gates through existing `/review-sprint` and `/audit-sprint`. This sprint makes bug mode usable in interactive mode.

### Deliverables
- [ ] Bug triage skill (`bug-triaging`) with index.yaml and SKILL.md
- [ ] Triage handoff contract template (schema v1)
- [ ] Micro-sprint template and creation logic
- [ ] Process compliance amendments (constraints.json + CLAUDE.loa.md)
- [ ] Beads integration for bug task lifecycle
- [ ] Bug command registration

### Technical Tasks

#### Task 1.1: Create Bug Triage Skill Directory Structure **[G-1, TNF1]**
Create `.claude/skills/bug-triaging/` with:
- `index.yaml` — skill registration (danger_level: moderate, effort_hint: medium, triggers: /bug)
- `resources/templates/triage.md` — handoff contract template (schema v1)
- `resources/templates/micro-sprint.md` — micro-sprint template

**Acceptance Criteria**:
- index.yaml validates against `.claude/schemas/skill-index.schema.json`
- Templates contain all required fields from SDD Section 3.1.3
- Schema version field present in triage template

#### Task 1.2: Implement SKILL.md — Phase 0: Dependency Check **[G-1, SDD 3.1.2]**
Implement dependency checking at skill entry:
- Required: jq, git (HALT if missing)
- Optional: gh (fallback to manual paste), br (skip beads with warning)
- Auth check: `gh auth status` if --from-issue used

**Acceptance Criteria**:
- Missing jq → clear HALT message with install guidance
- Missing br → WARN + continue without beads
- Missing gh + --from-issue → HALT with auth guidance

#### Task 1.3: Implement SKILL.md — Phase 1: Eligibility Check **[G-1, FR1.0, SDD 3.1.2]**
Implement strict eligibility validation:
- Parse free-form input or fetch from `gh issue view`
- Apply PII redaction to imported content
- Require at least one verifiable artifact (failing test, repro steps, stack trace, incident logs)
- Check explicit disqualifiers (new endpoint, UI flow, schema change, cross-service)
- Score: <2 REJECT, ==2 CONFIRM with user, >2 ACCEPT
- Log classification decision with reasoning to triage.md

**Acceptance Criteria**:
- "Add dark mode support" → REJECTED (new UI flow disqualifier)
- "Login fails with + in email" + stack trace → ACCEPTED (score: 3+)
- "API returns 500 on empty cart" (no stack trace) → CONFIRM (score: 2)
- Classification decision and reasoning logged to triage.md
- PII redacted from imported GitHub issue content

#### Task 1.4: Implement SKILL.md — Phase 2: Hybrid Interview **[G-1, FR1.2, SDD 3.1.2]**
Implement gap detection and targeted follow-ups:
- Parse input for known fields (reproduction, expected/actual, severity)
- Ask max 3-5 targeted questions for gaps
- Required: reproduction_steps, expected_behavior, actual_behavior, severity
- Mark reproduction_strength as "weak" if user can't provide repro steps

**Acceptance Criteria**:
- Input with full details → no follow-up questions asked
- Input with only error message → asks for repro steps, expected/actual, severity
- Maximum 5 questions asked regardless of gaps

#### Task 1.5: Implement SKILL.md — Phase 3: Codebase Analysis **[G-1, FR1.3, SDD 3.1.2]**
Implement targeted codebase analysis:
- Parse stack traces for file:line references
- Keyword search for function/module names
- Dependency mapping of affected files
- Test discovery (glob for test files)
- Test infrastructure detection (jest, pytest, cargo test, go test, etc.)
- HALT if no test runner found
- Determine test_type based on classification
- Check high-risk patterns in suspected files

**Acceptance Criteria**:
- Stack trace input → suspected files extracted with line numbers
- No test runner → HALT with "Set up test infrastructure" message
- Auth-related files → risk_level set to "high"
- At least one suspected file identified (or warning if none found)

#### Task 1.6: Implement SKILL.md — Phase 4: Micro-Sprint Creation **[G-3, FR1.4, SDD 3.1.2]**
Implement always-micro-sprint creation:
- Generate bug_id: YYYYMMDD-{6-char-hash}
- Create `.run/bugs/{bug_id}/state.json` using atomic write (temp + rename)
- Create `grimoires/loa/a2a/bug-{bug_id}/sprint.md` from template
- Register in ledger as type: "bugfix" using atomic write (temp + rename)
- Create beads task if br available (graceful fallback if not)
- Write triage.md with all required handoff fields (schema v1)
- Apply PII redaction to all output files (see Appendix D)

**Acceptance Criteria**:
- Bug ID is unique, safe (no user text in paths), sortable
- State file created at `.run/bugs/{bug_id}/state.json` with schema v1 (see Appendix E)
- Sprint file at `grimoires/loa/a2a/bug-{bug_id}/sprint.md`
- Triage.md has schema_version: 1 and all required fields
- Ledger updated with bugfix cycle entry (atomic write)
- All outputs pass PII scan (no secrets, keys, tokens per Appendix D)
- All file writes use atomic temp + rename pattern

#### Task 1.7: Amend Process Compliance **[FR6, SDD 3.4]**
Update process compliance rules:
- Amend C-PROC-003 in constraints.json: add `/bug triage` as valid path
- Amend C-PROC-005 in constraints.json: add `/bug` as valid implementation path
- Add C-PROC-015 in constraints.json: ALWAYS validate bug eligibility
- Update CLAUDE.loa.md NEVER/ALWAYS tables

**Acceptance Criteria**:
- constraints.json valid JSON after amendments
- CLAUDE.loa.md NEVER table includes /bug feature-work prohibition
- CLAUDE.loa.md ALWAYS table includes bug eligibility validation
- Existing process compliance rules unchanged for feature workflows

#### Task 1.8: Register Bug Command **[G-1]**
Create the `/bug` command entry point:
- Add to `.claude/commands/bug.md` (command file that routes to skill)
- Register in skill index if needed
- Ensure `/bug` trigger activates `bug-triaging` skill

**Acceptance Criteria**:
- `/bug "description"` invokes bug-triaging skill
- `/bug` (no args) prompts for interactive description
- `/bug --from-issue 42` invokes with issue import

### Dependencies
- None (Sprint 1 is self-contained — uses existing implement/review/audit skills)

### Risks & Mitigation
| Risk | Mitigation |
|------|------------|
| Eligibility too strict for edge cases | Calibration examples in SKILL.md; score==2 triggers confirmation |
| Test infrastructure detection misses frameworks | Use extensible pattern list; log unrecognized runners |

### Success Metrics
- [ ] `/bug` command functional end-to-end in interactive mode
- [ ] Triage produces complete handoff contract
- [ ] Micro-sprint created with correct lifecycle markers
- [ ] Process compliance rules correctly amended

---

## Sprint 2: Autonomous Mode, Ledger Integration & Golden Path

### Sprint Goal
Add autonomous bug fixing (`/run --bug`), Sprint Ledger integration for bugfix cycles, `--from-issue` GitHub intake, and golden path awareness so `/loa` and `/build` recognize active bug fixes.

### Deliverables
- [ ] Run mode `--bug` extension with circuit breaker
- [ ] Sprint Ledger bugfix cycle type
- [ ] `--from-issue` GitHub issue import
- [ ] Golden path bug detection functions
- [ ] `/loa` status shows active bugs
- [ ] `/build` routes to bug micro-sprint

### Technical Tasks

#### Task 2.1: Extend Run Mode with --bug Flag **[G-4, FR4, TNF2, SDD 3.2]**
Add bug run loop to run-mode skill:
- New inputs: `--bug "description"`, `--bug-from-issue N`
- Bug run loop: triage → implement → review → audit
- Bug-scoped circuit breaker (10 cycles, 2h timeout)
- ICE git safety for bugfix branches
- Draft PR creation with confidence signals

**Acceptance Criteria**:
- `/run --bug "description"` executes full triage → implement → review → audit
- Circuit breaker halts at 10 cycles or 2 hours
- Draft PR created in `ready-for-human-review` state
- PR body includes confidence signals (reproduction strength, test type, risk level)
- ICE prevents push to protected branches

#### Task 2.2: Human Checkpoint & High-Risk Blocking **[SDD 3.8]**
Implement autonomous mode safety:
- Draft PR with confidence signals (not auto-merged)
- High-risk area detection (auth, payment, migration, encryption)
- `--allow-high` flag for opt-in to high-risk autonomous fixes
- HALT for high-risk without --allow-high

**Acceptance Criteria**:
- Bug in auth file + no --allow-high → HALT with guidance
- Bug in auth file + --allow-high → proceeds with risk_level: high in PR
- Confidence signals accurate in PR description
- PR never auto-merged — always draft

#### Task 2.3: Sprint Ledger Integration **[G-3, TNF3, SDD 3.3]**
Integrate bugfix cycles into Sprint Ledger:
- Register micro-sprints as `type: "bugfix"` in ledger.json
- Global counter increments for bug sprint naming
- `/ledger` shows bugfix entries with filtering

**Acceptance Criteria**:
- Ledger entry has `type: "bugfix"` and source issue reference
- `sprint-bug-{NNN}` naming uses global counter
- `/ledger` output distinguishes bugfix from feature cycles

#### Task 2.4: GitHub Issue Import (`--from-issue`) **[FR1.1, US4]**
Implement GitHub issue import:
- Fetch via `gh issue view {N} --json title,body,comments`
- Parse title, body, and comments as triage input
- Apply PII redaction to all imported content
- Fallback: if gh fails, prompt user to paste issue content

**Acceptance Criteria**:
- `/bug --from-issue 42` imports issue title, body, comments
- PII redacted from imported content before processing
- gh auth failure → clear error with fallback to manual paste
- Issue content used as initial input for triage phases

#### Task 2.5: Golden Path Bug Awareness **[TNF5, SDD 3.6]**
Extend golden-path.sh with bug detection:
- `golden_detect_active_bug()` — find most recent active bug
- `golden_detect_micro_sprint()` — check for bug sprint
- `golden_bug_check_deps()` — verify required tools
- `/loa` displays active bug fix status
- `/build` routes to bug micro-sprint when active

**Acceptance Criteria**:
- `/loa` shows "Active Bug Fix: {id}" when bug in progress
- `/build` during active bug → routes to `/implement sprint-bug-{N} --bug`
- No active bug → golden path behaves normally (no regression)
- Functions are shellcheck-compliant
- Concurrent bugs → shows most recently modified

### Dependencies
| Dependency | Sprint | Status |
|-----------|--------|--------|
| Bug triage skill | Sprint 1 | Must be complete |
| Process compliance amendments | Sprint 1 | Must be complete |

### Risks & Mitigation
| Risk | Mitigation |
|------|------------|
| Autonomous mode loops on unreproducible bugs | Bug-scoped circuit breaker (10 cycles, 2h); flaky test detection |
| Golden path regression | Test with fixtures for both bug-active and no-bug states |
| gh rate limiting on issue fetch | Graceful fallback to manual paste |

### Success Metrics
- [ ] `/run --bug` functional end-to-end with draft PR output
- [ ] High-risk areas correctly blocked without --allow-high
- [ ] `/loa` and `/build` aware of active bug fixes
- [ ] Ledger correctly tracks bugfix cycles
- [ ] `--from-issue` imports and processes GitHub issues

---

## Final Sprint: End-to-End Validation

### Task E2E: Goal Validation

| PRD Goal | Validation | Sprint |
|----------|-----------|--------|
| G1: Lightweight bug-fixing workflow | `/bug` goes from description to implementation in <2 min triage | Sprint 1 |
| G2: Preserve all quality gates | Bug fixes go through implement → review → audit | Sprint 1 |
| G3: Sprint lifecycle + beads tracking | Bugs tracked in ledger + beads | Sprint 1 + 2 |
| G4: Interactive + autonomous | `/bug` interactive + `/run --bug` autonomous | Sprint 1 + 2 |
| G5: Test-driven bug fixing | Every fix starts with failing test | Sprint 1 |

---

## Appendix A: PRD Feature Mapping

| Feature | Task(s) | Sprint |
|---------|---------|--------|
| `/bug` command with hybrid triage | 1.1-1.6, 1.8 | 1 |
| Bug eligibility policy | 1.3 | 1 |
| Triage handoff contract (schema v1) | 1.1, 1.6 | 1 |
| Micro-sprint creation | 1.6 | 1 |
| Process compliance amendment | 1.7 | 1 |
| Beads integration | 1.6 | 1 |
| Autonomous mode (`/run --bug`) | 2.1, 2.2 | 2 |
| Sprint Ledger integration | 2.3 | 2 |
| `--from-issue` GitHub intake | 2.4 | 2 |
| Golden path awareness | 2.5 | 2 |

## Appendix B: SDD Component Mapping

| SDD Component | Task(s) | Sprint |
|---------------|---------|--------|
| Bug triage skill (3.1) | 1.1-1.6 | 1 |
| Run mode extension (3.2) | 2.1, 2.2 | 2 |
| Micro-sprint lifecycle (3.3) | 1.6 | 1 |
| Process compliance (3.4) | 1.7 | 1 |
| Bug ID generation (3.5) | 1.6 | 1 |
| Golden path awareness (3.6) | 2.5 | 2 |
| Beads integration (3.7) | 1.6 | 1 |
| Autonomous mode safety (3.8) | 2.2 | 2 |

## Appendix C: Eligibility Scoring Rubric (per Flatline review)

Referenced by Task 1.3. Deterministic rubric for bug eligibility:

### Point System

| Signal | Points | Verifiable? |
|--------|--------|-------------|
| Failing test name (executable) | +2 | Yes — run the test |
| Reproducible steps (can be followed) | +2 | Yes — follow the steps |
| Stack trace with source locations | +1 | Yes — file:line exists |
| Error log from production incident | +1 | Yes — log is attached |
| References regression from known baseline | +1 | Yes — commit/version cited |
| Describes NEW behavior not previously implemented | -3 | Disqualifier |
| Requires new endpoint or API route | -3 | Disqualifier |
| Requires new UI flow or page | -3 | Disqualifier |
| Requires schema change or new database tables | -3 | Disqualifier |
| Cross-service architectural changes | -3 | Disqualifier |

### Decision Rules

| Score | Decision | Action |
|-------|----------|--------|
| Any disqualifier matched | REJECT | "This is a feature request. Use /plan." |
| Score < 2 | REJECT | "Insufficient evidence of a bug. Provide a stack trace, failing test, or repro steps." |
| Score == 2 | CONFIRM | "This is borderline. Please confirm: is this a defect in existing behavior?" |
| Score > 2 | ACCEPT | Proceed to Phase 2 |

### Exception Policy

Some bug fixes legitimately require changes that match disqualifiers (e.g., backward-compatible schema fix for data corruption). The CONFIRM path handles this:
- User can override a disqualifier with explicit confirmation
- Override is logged in triage.md with reasoning
- Overrides are surfaced in review/audit phases for human verification

## Appendix D: PII Redaction Specification (per Flatline review)

Referenced by Tasks 1.3, 1.6, 2.4. Uses existing `.claude/scripts/pii-filter.sh`.

### Categories & Patterns

| Category | Pattern Examples | Action |
|----------|-----------------|--------|
| API Keys | `sk-[a-zA-Z0-9]{32,}`, `AKIA[0-9A-Z]{16}` | Redact → `[REDACTED_API_KEY]` |
| JWT Tokens | `eyJ[a-zA-Z0-9_-]+\.eyJ[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+` | Redact → `[REDACTED_JWT]` |
| Bearer Tokens | `Bearer [a-zA-Z0-9_-]+` | Redact → `Bearer [REDACTED]` |
| Passwords | `password[=:]\s*\S+` | Redact → `password=[REDACTED]` |
| Email addresses | Standard email regex | Redact → `[REDACTED_EMAIL]` |
| IP addresses | IPv4/IPv6 patterns | Keep (needed for debugging) |
| Phone numbers | `\+?[0-9]{10,15}` | Redact → `[REDACTED_PHONE]` |

### Application Points

1. **Imported content** (gh issue view output): scan before parsing
2. **triage.md output**: scan before writing
3. **sprint.md output**: scan before writing
4. **PR body**: scan before `gh pr create`

### False-Positive Handling

- If redaction removes content needed for debugging, log what was removed
- User can add `--no-pii-filter` flag to disable (logged as security risk in triage.md)
- Allowlist: hex strings <16 chars, common test values (test@example.com, 127.0.0.1)

## Appendix E: Bug State Schema (per Flatline review)

Referenced by Tasks 1.6, 2.1, 2.5. Schema for `.run/bugs/{bug_id}/state.json`.

### Fields

```json
{
  "schema_version": 1,
  "bug_id": "string (YYYYMMDD-hash)",
  "bug_title": "string",
  "sprint_id": "string (sprint-bug-NNN)",
  "state": "enum (see transitions below)",
  "mode": "interactive | autonomous",
  "created_at": "ISO 8601",
  "updated_at": "ISO 8601",
  "circuit_breaker": {
    "cycle_count": "integer",
    "same_issue_count": "integer",
    "no_progress_count": "integer",
    "last_finding_hash": "string | null"
  },
  "confidence": {
    "reproduction_strength": "strong | weak | manual_only",
    "test_type": "unit | integration | e2e | contract",
    "risk_level": "low | medium | high",
    "files_changed": "integer",
    "lines_changed": "integer"
  }
}
```

### Allowed State Transitions

```
TRIAGE → IMPLEMENTING       (triage complete, implement begins)
IMPLEMENTING → REVIEWING    (implementation complete)
REVIEWING → IMPLEMENTING    (review found issues — loop back)
REVIEWING → AUDITING        (review passed)
AUDITING → IMPLEMENTING     (audit found issues — loop back)
AUDITING → COMPLETED        (audit passed — COMPLETED marker created)
ANY → HALTED                (circuit breaker triggered or manual halt)
```

Invalid transitions (e.g., TRIAGE → AUDITING) must be rejected with an error.

### Write Strategy

All state file writes use atomic temp-file + rename pattern:
```bash
# Write to temp file first, then atomic rename
tmp=$(mktemp ".run/bugs/${bug_id}/state.json.XXXXXX")
echo "$json" > "$tmp"
mv "$tmp" ".run/bugs/${bug_id}/state.json"
```

Ledger writes use the same pattern. This prevents corruption from partial writes.

---

---

## Sprint 3: Bridgebuilder Review Fixes — Schema Truth, Explicit Contracts & State Enforcement

### Sprint Goal
Address the three findings from the Bridgebuilder review on PR #279. Fix schema drift in run-mode index.yaml, add explicit ordering comment for sprint ID validation bypass, and implement state transition validation for bug mode. Prepare PR for merge.

### Source
[Bridgebuilder Review — PR #279](https://github.com/0xHoneyJar/loa/pull/279#issuecomment-3881433049)

### Deliverables
- [ ] Truthful `target` schema in `run-mode/index.yaml`
- [ ] Explicit ordering contract comment in `golden-path.sh`
- [ ] State transition validation function in `golden-path.sh`

### Technical Tasks

#### Task 3.1: Fix Schema Drift — Make `target` Conditional in index.yaml **[Finding 1, Medium]**

The `target` input is marked `required: true` but bug mode invocations don't specify a target. The schema lies to any agent or tool that reads index.yaml for validation.

**File**: `.claude/skills/run-mode/index.yaml`

**Change**: Make `target` not required, add validation note explaining conditional requirement.

**Acceptance Criteria**:
- `target.required` is `false` (or removed)
- Description or comment clarifies: "Required for sprint mode, generated during triage for bug mode"
- Bug mode inputExamples remain valid (no `target` field)
- Sprint mode inputExamples remain valid (have `target` field)

#### Task 3.2: Add Explicit Ordering Contract for Sprint ID Validation Bypass **[Finding 2, Low]**

The `_gp_validate_sprint_id` regex (`^sprint-[1-9][0-9]*$`) won't match `sprint-bug-N`, but this is intentional because bug routing happens via `golden_detect_active_bug()` early return BEFORE validation. This implicit ordering dependency should be explicit.

**File**: `.claude/scripts/golden-path.sh`

**Change**: Add a one-line comment at the `_gp_validate_sprint_id` function documenting the bypass contract.

**Acceptance Criteria**:
- Comment at `_gp_validate_sprint_id` explains: bug sprint IDs bypass via `golden_detect_active_bug` early return
- No functional code changes
- Comment follows existing codebase style

#### Task 3.3: Implement State Transition Validation Function **[Finding 3, Medium]**

State transitions are specified but not enforced by code. When Loa moves to multi-model (Hounfour), a less capable model might attempt invalid transitions. Add a validation function.

**File**: `.claude/scripts/golden-path.sh`

**Change**: Add `golden_validate_bug_transition()` function that takes `(current_state, proposed_state)` and returns 0 (valid) or 1 (invalid). Encode the transition table from SDD Appendix E / SKILL.md.

**Acceptance Criteria**:
- Function `golden_validate_bug_transition` exists in golden-path.sh
- TRIAGE → IMPLEMENTING returns 0
- TRIAGE → AUDITING returns 1 (invalid skip)
- IMPLEMENTING → COMPLETED returns 1 (skip review+audit)
- ANY → HALTED returns 0 (always valid)
- COMPLETED → anything returns 1 (terminal state)
- Function uses case/esac or associative array for O(1) lookup
- Function placed in the Bug Detection section alongside other bug helpers

### Dependencies
| Dependency | Sprint | Status |
|-----------|--------|--------|
| Bug Mode Sprint 1-2 | Sprint 1-2 | COMPLETED |

### Risks & Mitigation
| Risk | Mitigation |
|------|------------|
| Validation function not called yet | Designed for future Hounfour integration; presence enables opt-in |

### Success Metrics
- [ ] index.yaml schema truthful for both sprint and bug modes
- [ ] Ordering dependency explicit in code comment
- [ ] State transition validation function present and correct

---

*Generated by Loa sprint-plan phase for Issue #278 (Bug Mode). 3 sprints, 16 tasks, full PRD/SDD coverage.*
*Revised per Flatline Protocol review: 5 HIGH_CONSENSUS auto-integrated, 6 unique blocker concerns addressed.*
*Sprint 3 added per Bridgebuilder review on PR #279: 3 findings addressed (schema drift, ordering contract, state enforcement).*
