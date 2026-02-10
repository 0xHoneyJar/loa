# SDD: Bug Mode — Lightweight Bug-Fixing Workflow

**Version**: 1.1.0
**Status**: Draft (Flatline-reviewed)
**Author**: Architecture Phase (architect)
**PRD**: grimoires/loa/prd.md (v1.1.0)
**Issue**: [loa #278](https://github.com/0xHoneyJar/loa/issues/278)
**Date**: 2026-02-11

---

## 1. Executive Summary

This SDD defines the architecture for a lightweight bug-fixing workflow (`/bug`) that bypasses the PRD/SDD/Sprint Plan planning phases while preserving all quality gates (test-first execution, review, audit). The design introduces one new skill (`bug-triaging`), extends the existing run mode with a `--bug` flag, amends process compliance constraints, and adds micro-sprint lifecycle management to the Sprint Ledger.

The architecture follows Loa's existing patterns: the new skill is a self-contained directory under `.claude/skills/`, state is managed in `.run/`, artifacts land in `grimoires/loa/a2a/`, and the golden path is aware of active bug cycles. No existing skills are modified — the bug triage skill produces artifacts that the existing `/implement`, `/review-sprint`, and `/audit-sprint` skills consume unchanged.

---

## 2. System Architecture

### 2.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     User Invocation                          │
│  /bug "description"          /run --bug "description"        │
│  /bug --from-issue 42        /run --bug --from-issue 42      │
└──────────────────┬──────────────────────┬───────────────────┘
                   │ interactive          │ autonomous
┌──────────────────▼──────────────────────▼───────────────────┐
│                    Bug Triage Skill                           │
│  .claude/skills/bug-triaging/SKILL.md                        │
│                                                              │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │Eligiblty │  │ Hybrid   │  │ Codebase │  │ Sprint   │   │
│  │  Check   │→ │ Interview│→ │ Analysis │→ │ Integr.  │   │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘   │
│                                                              │
│  Output: grimoires/loa/a2a/bug-{id}/triage.md               │
│          grimoires/loa/sprint.md (micro-sprint)              │
└──────────────────────────────┬──────────────────────────────┘
                               │ handoff contract
┌──────────────────────────────▼──────────────────────────────┐
│                    Existing Skill Pipeline                    │
│                                                              │
│  /implement ──→ /review-sprint ──→ /audit-sprint             │
│  (test-first)    (code review)      (security audit)         │
│                                                              │
│  Artifacts: bug-{id}/reviewer.md, auditor-sprint-feedback.md │
└──────────────────────────────┬──────────────────────────────┘
                               │ COMPLETED
┌──────────────────────────────▼──────────────────────────────┐
│                    Completion & Cleanup                       │
│                                                              │
│  - COMPLETED marker created                                  │
│  - Beads task closed                                         │
│  - Ledger entry updated                                      │
│  - Draft PR created (autonomous mode)                        │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 Component Inventory

| Component | Type | Action | Path |
|-----------|------|--------|------|
| `bug-triaging` skill | New | Create | `.claude/skills/bug-triaging/` |
| `bug-triaging/index.yaml` | New | Create | `.claude/skills/bug-triaging/index.yaml` |
| `bug-triaging/SKILL.md` | New | Create | `.claude/skills/bug-triaging/SKILL.md` |
| `bug-triaging/resources/templates/triage.md` | New | Create | Triage handoff template |
| `bug-triaging/resources/templates/micro-sprint.md` | New | Create | Micro-sprint template |
| `constraints.json` | Existing | Amend | `.claude/data/constraints.json` |
| `run-mode/SKILL.md` | Existing | Extend | `.claude/skills/run-mode/SKILL.md` |
| `run-mode/index.yaml` | Existing | Extend | `.claude/skills/run-mode/index.yaml` |
| `golden-path.sh` | Existing | Extend | `.claude/scripts/golden-path.sh` |
| `CLAUDE.loa.md` | Existing | Amend | `.claude/loa/CLAUDE.loa.md` |
| `danger-level config` | Existing | Add entry | `.claude/data/constraints.json` or skill index |

### 2.3 Data Flow

```
User Input (description/issue)
       │
       ▼
  ┌─────────────┐     ┌──────────────┐
  │ Eligibility │────→│  REJECTED    │──→ "Use /plan instead"
  │   Check     │     └──────────────┘
  └──────┬──────┘
         │ ACCEPTED
         ▼
  ┌─────────────┐     ┌──────────────┐
  │   Hybrid    │────→│  triage.md   │  (handoff contract)
  │  Interview  │     └──────┬───────┘
  └─────────────┘            │
                             ▼
  ┌─────────────┐     ┌──────────────┐
  │  Codebase   │────→│ suspected    │
  │  Analysis   │     │ files, tests │
  └─────────────┘     └──────┬───────┘
                             │
                             ▼
                     ┌──────────────┐
                     │   Create     │
                     │ Micro-sprint │
                     │  (always)    │
                     └──────┬───────┘
                            │
                            ▼
                    ┌──────────────┐
                    │  /implement  │  (test-first)
                    │   --bug      │
                    └──────┬───────┘
                           ▼
                    ┌──────────────┐
                    │/review-sprint│
                    └──────┬───────┘
                           ▼
                    ┌──────────────┐
                    │/audit-sprint │
                    └──────┬───────┘
                           ▼
                      COMPLETED
```

---

## 3. Component Design

### 3.1 Bug Triage Skill (`bug-triaging`)

#### 3.1.1 Skill Registration

```yaml
# .claude/skills/bug-triaging/index.yaml
name: "bug-triaging"
version: "1.0.0"
model: "native"
color: "red"
effort_hint: medium
danger_level: moderate
categories:
  - quality
  - debugging
  - support

description: |
  Use this skill when a user reports a bug that needs fixing. Performs
  dependency check, eligibility validation, hybrid interview, codebase
  analysis, and creates a micro-sprint. Produces a triage.md handoff
  contract for the implement phase. Test-first is non-negotiable.
  Bugs always get their own micro-sprint (never injected into active sprints).

triggers:
  - "/bug"
  - "fix bug"
  - "debug issue"
  - "bug report"
  - "production bug"

inputs:
  - name: "description"
    type: "string"
    description: "Free-form bug description, error message, or stack trace"
    required: false
  - name: "from_issue"
    type: "integer"
    description: "GitHub issue number to import as bug report"
    required: false

outputs:
  - path: "grimoires/loa/a2a/bug-{id}/triage.md"
    description: "Bug analysis and handoff contract"
    format: detailed
  - path: "grimoires/loa/sprint.md"
    description: "Micro-sprint plan (if no active sprint)"
    format: standard
    condition: "no_active_sprint"

dependencies:
  upstream: []
  artifacts: []

protocols:
  required:
    - name: "session-continuity"
      path: ".claude/protocols/session-continuity.md"
      purpose: "Maintain triage context across sessions"
  recommended:
    - name: "grounding-enforcement"
      path: ".claude/protocols/grounding-enforcement.md"
      purpose: "Verify suspected files with source references"

input_guardrails:
  pii_filter:
    enabled: true
    mode: blocking
  injection_detection:
    enabled: true
    threshold: 0.7
  relevance_check:
    enabled: true
    reject_irrelevant: true
```

#### 3.1.2 SKILL.md Structure

The SKILL.md follows five phases. Each phase includes explicit failure modes and recovery actions.

**Phase 0: Dependency Check**

```
Algorithm:
1. Check required tools:
   - jq: required (JSON parsing for state files)
   - git: required (branch creation)
2. Check optional tools with fallbacks:
   - gh: optional (--from-issue requires it; fallback: manual paste of issue content)
   - br: optional (beads tracking; fallback: skip beads, warn user)
3. Check connectivity:
   - If --from-issue: verify `gh auth status` succeeds
4. If required tool missing: HALT with install guidance

Failure Modes:
- jq missing → HALT: "Install jq: brew install jq / apt install jq"
- gh not authenticated → HALT: "Run gh auth login first"
- br not found → WARN: "Beads not available. Task tracking will be skipped."
```

**Phase 1: Eligibility Check**

```
Algorithm:
1. Parse input (free-form text, --from-issue, or interactive prompt)
2. If --from-issue: fetch via `gh issue view {N} --json title,body,comments`
   - Apply PII redaction to imported content (issue body + comments)
3. Extract signals: error messages, stack traces, test names, regression refs
4. Require at least ONE verifiable artifact:
   - A failing test name that can be executed
   - Reproducible steps that can be followed to observe failure
   - A linked production incident with logs/error output
   - A stack trace with identifiable source locations
5. Check explicit disqualifiers (any one → REJECT):
   - Describes a new endpoint or API route
   - Describes a new UI flow or page
   - Requires schema changes or new database tables
   - Involves cross-service architectural changes
   - Requests new configuration options
6. Score eligibility:
   - Has verifiable artifact: +2 (required — see step 4)
   - Has stack trace or error log: +1
   - References regression from known baseline: +1
   - References failing test: +1
   - Matches any disqualifier: REJECT immediately
7. If score < 2: REJECT → "This looks like a feature request. Use /plan."
   If score == 2: CONFIRM with user → "This is borderline. Confirm this is a bug?"
   If score > 2: ACCEPT
8. Log classification decision to triage.md with reasoning

Calibration Examples:
- "Login fails with + in email" + stack trace → ACCEPT (score: 3)
- "Add dark mode support" → REJECT (new UI flow disqualifier)
- "API returns 500 on empty cart" → score 2 → CONFIRM
- "Test test_checkout fails after deploy" → ACCEPT (score: 3)
- "We need a logout button" → REJECT (new feature, no failure)

Failure Modes:
- --from-issue fetch fails → FALLBACK: ask user to paste issue content
- Score ambiguous (==2) → CONFIRM: ask user to verify it's a bug
- PII detected in imported content → QUARANTINE: redact and show user what was removed
```

**Phase 2: Hybrid Interview**

```
Algorithm:
1. Parse free-form input for known fields (reproduction, expected/actual, severity)
2. Identify gaps in required fields
3. For each gap, ask one targeted question (max 3-5 questions total)
4. Required fields:
   - reproduction_steps (if not extractable from stack trace)
   - expected_behavior
   - actual_behavior
   - severity (critical/high/medium/low)
5. Optional fields (Loa can infer):
   - affected_area
   - environment

Failure Modes:
- User cannot provide reproduction steps → WARN: "Without repro steps, fix may
  take longer. Proceed?" If yes, mark reproduction_strength as "weak".
- User provides contradictory info → ASK: clarifying question to resolve
```

**Phase 3: Codebase Analysis**

```
Algorithm:
1. Parse stack traces → extract file:line references
2. Keyword search: grep codebase for function/module names from error
3. Dependency mapping: trace imports/requires from affected files
4. Test discovery: glob for test files matching affected modules
5. Assess test infrastructure:
   - Search for test runners (jest, pytest, cargo test, go test, etc.)
   - If NO test runner found: HALT with guidance
     "No test runner detected. Set up test infrastructure before using /bug."
6. Determine test_type based on bug classification:
   - runtime_error/logic_bug → unit test
   - integration_issue → integration test
   - edge_case (user-facing) → e2e test
   - schema/contract → contract test
7. Produce suspected_files list with confidence scores
8. Check high-risk patterns in suspected files (auth, payment, migration, etc.)

Failure Modes:
- No test runner found → HALT: cannot proceed without test infrastructure
- No suspected files found → WARN: ask user for hints, expand search
- All suspected files low confidence → WARN: "Analysis inconclusive. Recommend
  manual investigation before proceeding."
```

**Phase 4: Micro-Sprint Creation & Handoff**

Bugs **always** get their own micro-sprint. This is a deliberate simplification that avoids concurrency issues, state corruption, and complex sprint-mutation semantics.

```
Algorithm:
1. Generate bug_id: YYYYMMDD-{6-char-hash} (or YYYYMMDD-i{N}-{hash} for issues)
2. Create state directory: .run/bugs/{bug_id}/
3. Write state file: .run/bugs/{bug_id}/state.json
4. Create micro-sprint in grimoires/loa/a2a/bug-{bug_id}/sprint.md
   (NOT grimoires/loa/sprint.md — bug sprints are namespaced per bug)
5. Register in ledger as type: "bugfix"
6. Create beads task (if br available)
7. Write triage.md (schema version 1) with all required handoff fields
8. Apply PII redaction to all output files (triage.md, sprint.md)
9. Return bug_id for implement phase

Failure Modes:
- Ledger write fails → WARN: proceed without ledger entry, note in NOTES.md
- Beads create fails → WARN: proceed without beads, note in NOTES.md
- State directory creation fails → HALT: filesystem issue, cannot proceed
```

#### 3.1.3 Triage Handoff Contract Schema

The `/implement` skill performs preflight validation of `triage.md` before execution:
1. Parse metadata section
2. Verify `schema_version` is supported (currently: 1)
3. Verify all required fields are present and non-empty
4. If validation fails → HALT with: "Triage handoff incomplete. Re-run /bug."

```markdown
# Bug Triage: {title}

## Metadata
- **schema_version**: 1
- **bug_id**: {YYYYMMDD}-{hash} or {YYYYMMDD}-i{issue}-{hash}
- **classification**: runtime_error | logic_bug | edge_case | integration_issue | regression
- **severity**: critical | high | medium | low
- **eligibility_score**: {N} (signals matched)
- **eligibility_reasoning**: {why accepted/confirmed}
- **test_type**: unit | integration | e2e | contract
- **risk_level**: low | medium | high
- **created**: {ISO timestamp}

## Reproduction
### Steps
1. {step}
2. {step}
...

### Expected Behavior
{description}

### Actual Behavior
{description}

### Environment
{local/staging/production} (optional)

## Analysis
### Suspected Files
| File | Line(s) | Confidence | Reason |
|------|---------|------------|--------|
| {path} | {lines} | high/medium/low | {why} |

### Related Tests
| Test File | Coverage |
|-----------|----------|
| {path} | {what it tests} |

### Test Target
{What the failing test should assert — the specific behavior to verify}

### Constraints
{Areas that must NOT be modified} (optional)

## Fix Strategy
{Proposed approach — brief, 2-3 sentences}
```

### 3.2 Run Mode Extension

#### 3.2.1 New Input: `--bug`

Add to `.claude/skills/run-mode/index.yaml` inputs:

```yaml
- name: "bug"
  type: "string"
  description: "Bug description for autonomous bug-fixing mode"
  required: false
- name: "bug_from_issue"
  type: "integer"
  description: "GitHub issue number for autonomous bug-fixing"
  required: false
```

#### 3.2.2 Bug Run Loop

```
/run --bug "description"
       │
       ▼
  ┌─────────────┐
  │  TRIAGE     │  Invoke bug-triaging skill
  │  (Phase 1)  │  Output: triage.md, sprint.md
  └──────┬──────┘
         │
         ▼
  ┌─────────────┐
  │  IMPLEMENT  │  /implement sprint-bug-{N} --bug
  │  (Phase 2)  │  Test-first: write test → fix → verify
  └──────┬──────┘
         │
         ▼
  ┌─────────────┐
  │  REVIEW     │  /review-sprint sprint-bug-{N}
  │  (Phase 3)  │  Scoped to bug fix only
  └──────┬──────┘
         │ if findings → back to IMPLEMENT
         ▼
  ┌─────────────┐
  │   AUDIT     │  /audit-sprint sprint-bug-{N}
  │  (Phase 4)  │  Standard audit checklist
  └──────┬──────┘
         │ if findings → back to IMPLEMENT
         ▼
  ┌─────────────┐
  │  COMPLETE   │  COMPLETED marker
  │  (Phase 5)  │  Draft PR with confidence signals
  └─────────────┘
```

#### 3.2.3 Circuit Breaker (Bug-Scoped)

| Trigger | Limit | Rationale |
|---------|-------|-----------|
| Same Issue | 3 cycles | Bug fix shouldn't need >3 review cycles |
| No Progress | 5 cycles | If no file changes, bug may be misdiagnosed |
| Cycle Limit | 10 total | Reduced from 20 (bug scope is smaller) |
| Timeout | 2 hours | Reduced from 8 (bug scope is smaller) |

#### 3.2.4 State File (Namespaced Per Bug)

State is isolated per bug to support concurrent bug fixes without corruption.

```json
// .run/bugs/{bug_id}/state.json  (NOT a global file)
{
  "state": "TRIAGE | IMPLEMENTING | REVIEWING | AUDITING | COMPLETED | HALTED",
  "bug_id": "20260211-a3f2b1",
  "bug_title": "Login fails with + in email",
  "sprint_id": "sprint-bug-1",
  "mode": "interactive | autonomous",
  "circuit_breaker": {
    "cycle_count": 0,
    "same_issue_count": 0,
    "no_progress_count": 0,
    "last_finding_hash": null
  },
  "timestamps": {
    "triage_started": null,
    "triage_completed": null,
    "implement_started": null,
    "review_started": null,
    "audit_started": null,
    "completed": null
  },
  "confidence": {
    "reproduction_strength": "strong | weak | manual_only",
    "test_type": "unit | integration | e2e | contract",
    "risk_level": "low | medium | high",
    "files_changed": 0,
    "lines_changed": 0
  }
}
```

### 3.3 Micro-Sprint Lifecycle

#### 3.3.1 Naming Convention

```
sprint-bug-{NNN}
```

Where `NNN` is a global counter from the Sprint Ledger (`global_sprint_counter`). This ensures micro-sprints don't collide with feature sprints.

#### 3.3.2 Micro-Sprint Template

```markdown
# Sprint Plan: Bug Fix — {bug_title}

**Type**: bugfix
**Bug ID**: {bug_id}
**Source**: /bug (triage)

## Sprint {sprint-bug-NNN}: {bug_title}

### Sprint Goal
Fix the reported bug with a failing test proving the fix.

### Deliverables
- [ ] Failing test that reproduces the bug
- [ ] Source code fix
- [ ] All existing tests pass (no regressions)
- [ ] Triage analysis document

### Technical Tasks

#### Task 1: Write Failing Test [G-5]
- Create {test_type} test reproducing the bug
- Verify test fails with current code
- Test file: {suggested_test_file}

#### Task 2: Implement Fix [G-1, G-2]
- Fix root cause in {suspected_files}
- Verify failing test now passes
- Run full test suite

### Acceptance Criteria
- [ ] Bug is no longer reproducible
- [ ] Failing test proves the fix
- [ ] No regressions in existing tests
- [ ] Fix addresses root cause (not just symptoms)

### Triage Reference
See: grimoires/loa/a2a/bug-{bug_id}/triage.md
```

#### 3.3.3 Lifecycle States

```
CREATED ──→ IN_PROGRESS ──→ REVIEW ──→ AUDIT ──→ COMPLETED
                 │              │          │
                 │              ▼          ▼
                 │         (findings)  (findings)
                 │              │          │
                 └──────────────┘──────────┘
                    (loop back)
```

| State | Entry Condition | Marker |
|-------|----------------|--------|
| CREATED | Triage produces sprint.md | `triage.md` exists |
| IN_PROGRESS | `/implement` begins | beads task `in_progress` |
| REVIEW | Implementation complete | `reviewer.md` exists |
| AUDIT | Review passes | `auditor-sprint-feedback.md` exists |
| COMPLETED | Audit passes | `COMPLETED` marker |

#### 3.3.4 Interaction with Active Feature Sprints

Bugs **always** create micro-sprints — they are never injected into active feature sprints. This is a deliberate architectural decision (per Flatline review SKP-002/SKP-005) that eliminates:
- State corruption from modifying shared sprint.md
- Concurrency issues with parallel bug fixes
- Complex pause/resume semantics
- Ambiguous review/audit scope

Micro-sprints are **fully independent**:
- Separate branch (`bugfix/{bug_id}`)
- Separate sprint file (`grimoires/loa/a2a/bug-{id}/sprint.md`)
- Separate state file (`.run/bugs/{bug_id}/state.json`)
- Separate review/audit cycle
- Separate COMPLETED marker
- Separate ledger entry
- Does NOT block or modify any active feature sprint

**Concurrent bugs**: Multiple bug fixes can run in parallel because each has fully namespaced state. The golden path detects the most recent active bug for status display.

### 3.4 Process Compliance Amendments

#### 3.4.1 Constraint Changes

**Amend C-PROC-003** (`.claude/data/constraints.json`):

```json
// BEFORE:
{
  "id": "C-PROC-003",
  "rule": "NEVER skip from sprint plan directly to implementation without /run sprint-plan or /run sprint-N",
  "reason": "/run wraps implement+review+audit in a cycle loop with circuit breaker"
}

// AFTER:
{
  "id": "C-PROC-003",
  "rule": "NEVER skip from sprint plan directly to implementation without /run sprint-plan, /run sprint-N, or /bug triage",
  "reason": "/run wraps implement+review+audit in a cycle loop with circuit breaker. /bug produces a triage handoff that feeds directly into /implement."
}
```

**Amend C-PROC-005**:

```json
// BEFORE:
{
  "id": "C-PROC-005",
  "rule": "ALWAYS use /run sprint-plan or /run sprint-N for implementation",
  "reason": "Ensures review+audit cycle with circuit breaker protection"
}

// AFTER:
{
  "id": "C-PROC-005",
  "rule": "ALWAYS use /run sprint-plan, /run sprint-N, or /bug for implementation",
  "reason": "Ensures review+audit cycle with circuit breaker protection. /bug enforces the same cycle for bug fixes."
}
```

**Add C-PROC-015** (new):

```json
{
  "id": "C-PROC-015",
  "type": "always",
  "category": "process_compliance_always",
  "rule": "ALWAYS validate bug eligibility before /bug implementation",
  "reason": "Prevents feature work from bypassing PRD/SDD gates via /bug. Must reference observed failure, regression, or stack trace."
}
```

#### 3.4.2 CLAUDE.loa.md Updates

Add to NEVER rules:
```
| NEVER use /bug for feature work that doesn't reference an observed failure | /bug bypasses PRD/SDD gates; feature work must go through /plan |
```

Add to ALWAYS rules:
```
| ALWAYS validate bug eligibility (observed failure, stack trace, or regression) before implementation via /bug | Prevents planning bypass; escalates to /plan if not a genuine bug |
```

### 3.5 Bug ID Generation

```python
# Pseudocode for bug ID generation
import hashlib, datetime

def generate_bug_id(title: str, issue_number: int | None = None) -> str:
    timestamp = datetime.now().strftime("%Y%m%d")
    raw = f"{title}{timestamp}{os.urandom(4).hex()}"
    short_hash = hashlib.sha256(raw.encode()).hexdigest()[:6]

    if issue_number:
        return f"{timestamp}-i{issue_number}-{short_hash}"
    return f"{timestamp}-{short_hash}"

# Examples:
# generate_bug_id("Login fails with + in email") → "20260211-a3f2b1"
# generate_bug_id("Login fails", issue_number=42) → "20260211-i42-a3f2b1"
```

Properties:
- **Unique**: Random bytes prevent collisions
- **Stable**: ID doesn't change if title is later edited
- **Safe**: No user text in filesystem paths
- **Sortable**: Chronological by prefix
- **Traceable**: Optional issue number embedded

### 3.6 Golden Path Awareness

#### 3.6.1 New Functions in `golden-path.sh`

All functions are shellcheck-compliant and tested with fixture files.

```bash
# Detect most recent active bug fix (namespaced state)
# Returns: bug_id on stdout, exit 0 if found, exit 1 if none
golden_detect_active_bug() {
  local bugs_dir=".run/bugs"
  [[ -d "$bugs_dir" ]] || return 1

  local latest_bug=""
  local latest_time=0

  for state_file in "$bugs_dir"/*/state.json; do
    [[ -f "$state_file" ]] || continue
    local state
    state=$(jq -r '.state // empty' "$state_file" 2>/dev/null) || continue
    if [[ "$state" != "COMPLETED" && "$state" != "HALTED" ]]; then
      local mtime
      mtime=$(stat -c %Y "$state_file" 2>/dev/null || stat -f %m "$state_file" 2>/dev/null) || continue
      if (( mtime > latest_time )); then
        latest_time=$mtime
        latest_bug=$(jq -r '.bug_id // empty' "$state_file" 2>/dev/null)
      fi
    fi
  done

  if [[ -n "$latest_bug" ]]; then
    echo "$latest_bug"
    return 0
  fi
  return 1
}

# Check if a micro-sprint exists for a given bug
# Args: $1 = bug_id
golden_detect_micro_sprint() {
  local bug_id="${1:-}"
  local sprint_file="grimoires/loa/a2a/bug-${bug_id}/sprint.md"
  [[ -f "$sprint_file" ]] && return 0
  return 1
}

# Dependency check: verify required tools are available
# Returns: 0 if all required present, 1 if missing
golden_bug_check_deps() {
  local missing=()
  command -v jq >/dev/null 2>&1 || missing+=("jq")
  command -v git >/dev/null 2>&1 || missing+=("git")

  if (( ${#missing[@]} > 0 )); then
    echo "Missing required tools: ${missing[*]}" >&2
    return 1
  fi
  return 0
}
```

#### 3.6.2 `/loa` Status Integration

When a bug fix is active, `/loa` should display:

```
Active Bug Fix: 20260211-a3f2b1
  Title: Login fails with + in email
  State: IMPLEMENTING
  Sprint: sprint-bug-1
  Next: /build (continues bug fix implementation)
```

#### 3.6.3 `/build` Behavior

When a micro-sprint is active, `/build` should route to:
```bash
/implement sprint-bug-{N} --bug
```

This is transparent — the user doesn't need to know about micro-sprints.

### 3.7 Beads Integration

#### 3.7.1 Task Creation

```bash
# After triage, create beads task
br create "Fix: {bug_title}" \
  --label bug \
  --label "severity:{severity}" \
  --priority {1-4 based on severity}
```

#### 3.7.2 Task Lifecycle

```bash
# Start implementation
br update {task_id} --status in_progress

# Complete implementation
br close {task_id}
```

#### 3.7.3 Beads Failure Handling

```bash
# If br is not available, skip silently with warning
if ! command -v br >/dev/null 2>&1; then
  echo "[bug] Beads not available. Task tracking skipped." >&2
  # Continue without beads — bug fix still works
fi

# If br create fails, warn but continue
if ! br create "Fix: ${bug_title}" --label bug 2>/dev/null; then
  echo "[bug] Beads task creation failed. Continuing without tracking." >&2
fi
```

### 3.8 Autonomous Mode Safety

#### 3.8.1 Human Checkpoint

Autonomous mode creates a draft PR in `ready-for-human-review` state:

```bash
# ICE creates draft PR
gh pr create --draft \
  --title "fix: {bug_title}" \
  --body "$(cat <<'EOF'
## Bug Fix: {bug_title}

**Bug ID**: {bug_id}
**Source**: {/bug or /run --bug}

### Confidence Signals
- Reproduction: {strong/weak/manual_only}
- Test type: {unit/integration/e2e/contract}
- Files changed: {N}
- Lines changed: {N}
- Risk level: {low/medium/high}

### Artifacts
- Triage: grimoires/loa/a2a/bug-{id}/triage.md
- Review: grimoires/loa/a2a/bug-{id}/reviewer.md
- Audit: grimoires/loa/a2a/bug-{id}/auditor-sprint-feedback.md

### Status: READY FOR HUMAN REVIEW
This PR was created by `/run --bug` autonomous mode.
Please review before merging.
EOF
)"
```

#### 3.8.2 High-Risk Area Detection

```bash
# High-risk patterns (checked during triage)
HIGH_RISK_PATTERNS=(
  "auth" "authentication" "login" "password" "token" "jwt" "oauth"
  "payment" "billing" "charge" "stripe" "checkout"
  "migration" "schema" "database" "db"
  "encrypt" "decrypt" "secret" "credential" "key"
)

# Check suspected files against patterns
for file in "${suspected_files[@]}"; do
  for pattern in "${HIGH_RISK_PATTERNS[@]}"; do
    if echo "$file" | grep -qi "$pattern"; then
      risk_level="high"
      if [[ "$mode" == "autonomous" && "$allow_high" != "true" ]]; then
        # HALT: require --allow-high flag
      fi
    fi
  done
done
```

---

## 4. File System Layout

### 4.1 New Files

```
.claude/skills/bug-triaging/
├── index.yaml                              # Skill registration
├── SKILL.md                                # Execution guide (~15K lines)
└── resources/
    └── templates/
        ├── triage.md                       # Handoff contract template
        └── micro-sprint.md                 # Micro-sprint template
```

### 4.2 Modified Files

```
.claude/data/constraints.json               # Amend C-PROC-003, C-PROC-005, add C-PROC-015
.claude/loa/CLAUDE.loa.md                   # Add NEVER/ALWAYS rules for /bug
.claude/skills/run-mode/index.yaml          # Add --bug, --bug-from-issue inputs
.claude/skills/run-mode/SKILL.md            # Add bug run loop section
.claude/scripts/golden-path.sh              # Add bug detection functions
```

### 4.3 Runtime Artifacts

```
.run/bugs/{bug_id}/
├── state.json                              # Bug fix state (per-bug, ephemeral)
└── circuit-breaker.json                    # Circuit breaker state (autonomous mode)

grimoires/loa/a2a/bug-{id}/
├── triage.md                               # Triage handoff contract (schema v1)
├── sprint.md                               # Micro-sprint plan (per-bug)
├── reviewer.md                             # Review findings
├── auditor-sprint-feedback.md              # Audit findings
└── COMPLETED                               # Completion marker

grimoires/loa/ledger.json                   # Updated with bugfix cycle entry
```

---

## 5. Security Considerations

| Concern | Mitigation |
|---------|------------|
| Bug description injection | Input guardrails: PII filter + injection detection on user input |
| Path traversal via bug ID | ID is timestamp + hash only — no user text in paths |
| Feature work bypassing /plan | Strict eligibility with verifiable artifacts + explicit disqualifiers |
| Autonomous mode unsafe merges | Draft PR with human approval gate; high-risk blocking |
| Sensitive data in user input | PII filter runs on user input before writing to triage.md |
| Sensitive data in imported issues | PII redaction applied to `gh issue view` content (body + comments) before processing |
| Secrets in triage.md output | Secret scanning (API keys, JWTs, tokens) on all written artifacts |
| Secrets in PR body | PII redaction applied to generated PR description before `gh pr create` |
| Concurrent state corruption | Per-bug namespaced state (`.run/bugs/{bug_id}/`) prevents cross-bug interference |

---

## 6. Testing Strategy

| Test | What It Verifies |
|------|-----------------|
| Dependency check | Missing jq/git halts; missing gh/br degrades gracefully |
| Eligibility rejection | Feature-shaped requests (new endpoint, UI flow, schema change) rejected |
| Eligibility acceptance | Bug reports with verifiable artifacts accepted |
| Eligibility borderline | Score==2 requests trigger user confirmation |
| Disqualifier detection | Explicit disqualifiers (new endpoint, schema change) trigger immediate REJECT |
| Triage handoff completeness | All required fields present in triage.md with schema_version |
| Implement preflight | /implement validates triage.md schema before execution |
| Micro-sprint creation | Per-bug sprint.md created in grimoires/loa/a2a/bug-{id}/ |
| State isolation | Concurrent bugs don't corrupt each other's .run/bugs/{id}/state.json |
| Bug ID uniqueness | No collisions across 1000 generated IDs |
| Bug ID safety | No special characters, path traversal, or length issues |
| Circuit breaker (bug-scoped) | Halts at 10 cycles / 2 hours |
| High-risk detection | Auth/payment/migration files trigger --allow-high gate |
| Autonomous PR creation | Draft PR with confidence signals, not auto-merged |
| PII redaction (input) | User input redacted before triage.md |
| PII redaction (import) | GitHub issue content redacted before processing |
| PII redaction (output) | PR body and artifacts scanned for secrets |
| Ledger integration | Micro-sprint registered with type: bugfix |
| Beads lifecycle | Task created, tracked, and closed; graceful degradation if br unavailable |
| Golden path awareness | /loa shows active bug, /build routes to bug sprint |
| Phase failure modes | Each phase halts/warns/falls back correctly per spec |

---

## 7. Migration & Rollback

### 7.1 Migration

No migration needed. Bug mode is purely additive:
- New skill directory (no existing files modified except constraints.json, golden-path.sh, run-mode)
- New constraint (C-PROC-015) doesn't break existing workflows
- Amended constraints (C-PROC-003, C-PROC-005) only add alternatives, don't remove existing paths

### 7.2 Rollback

If bug mode needs to be disabled:
1. Remove `.claude/skills/bug-triaging/` directory
2. Revert constraint amendments in `constraints.json`
3. Revert CLAUDE.loa.md amendments
4. Revert run-mode and golden-path changes
5. Clean up `.run/bug-state.json` if exists

All changes are isolated and revertible with a single `git revert`.

---

## 8. Sprint Mapping

| Sprint | Components | PRD Requirements |
|--------|-----------|-----------------|
| Sprint 1 | bug-triaging skill, triage handoff, micro-sprint, process compliance, beads | FR1, FR2, FR3, FR5, FR6, TNF1, TNF4 |
| Sprint 2 | run-mode --bug, autonomous loop, ledger integration, golden path, --from-issue | FR4, TNF2, TNF3, TNF5 |

---

*Generated by Loa architect phase for Issue #278 (Bug Mode). Grounded in codebase reality: skill-index.schema.json, constraints.json, golden-path.sh, run-mode SKILL.md.*
*Revised per Flatline Protocol review: 4 HIGH_CONSENSUS auto-integrated, 6 BLOCKERS addressed (always-micro-sprint, namespaced state, tightened eligibility, dependency checks, full PII pipeline, schema versioning).*
