# PRD: Bug Mode — Lightweight Bug-Fixing Workflow for Loa

**Version**: 1.1.0
**Status**: Draft (revised per Flatline Protocol review)
**Author**: Discovery Phase (plan-and-analyze)
**Issue**: [loa #278](https://github.com/0xHoneyJar/loa/issues/278)
**Date**: 2026-02-11

---

## 1. Problem Statement

Loa's workflow enforces a full **PRD → SDD → Sprint Plan → Implement → Review → Audit** pipeline for every code change. This is correct for feature development but creates significant friction for the most common post-deployment activity: **fixing bugs**.

The real-world pattern (reported by zergucci in issue #278):

1. User builds features with Loa's full workflow — works great
2. User deploys and tests production code
3. User discovers bugs (edge cases, runtime errors, logic issues)
4. User invokes Loa to fix the bug
5. **Loa demands full plan-and-analyze** — a PRD for a null pointer fix
6. User bypasses Loa entirely and talks to "raw Claude"
7. All quality gates (test-first, review, audit) are lost

**The gap**: There is no path between "full ceremony" and "no ceremony." The NEVER rules in `CLAUDE.loa.md` explicitly block writing application code outside `/implement`, and there's no configuration to bypass PRD/SDD for lightweight fixes. Users who need to fix bugs are forced to either:

- **Option A**: Run the full 6-phase workflow for a one-line fix (30+ minutes of planning overhead)
- **Option B**: Abandon Loa's quality gates entirely (lose test-first, review, and audit)

Neither option is acceptable. Bug fixing needs its own workflow that's **lightweight on planning** but **preserves quality gates**.

> Source: [Issue #278](https://github.com/0xHoneyJar/loa/issues/278), zergucci Discord transcript (2026-02-11)

## 2. Goals & Success Metrics

### Goals

| # | Goal | Measurable Outcome |
|---|------|-------------------|
| G1 | Provide a lightweight bug-fixing workflow that skips PRD/SDD/Sprint Plan | `/bug` command goes from description to implementation in <2 minutes of triage |
| G2 | Preserve all quality gates (test-first, review, audit) | Bug fixes go through implement → review → audit cycle, same as feature sprints |
| G3 | Integrate with sprint lifecycle and beads task tracking | Bugs tracked as sprint tasks in beads, visible in ledger |
| G4 | Support both interactive and autonomous execution | Interactive by default, `/run --bug` for autonomous batch fixing |
| G5 | Use test-driven bug fixing (reproduce → fix → verify) | Every bug fix starts with a failing test, fix is validated by test passing |

### Success Metrics

| # | Metric | Current | Target |
|---|--------|---------|--------|
| M1 | Time from bug report to implementation start | 30+ min (full planning) | <2 min (triage only) |
| M2 | Bug fixes going through quality gates | ~0% (users bypass Loa) | 100% (review + audit enforced) |
| M3 | Bug fixes with automated reproduction | Unknown (no tracking) | 100% (at least one automated check per fix) |
| M4 | Sprint/beads traceability for bug fixes | 0% (bypassed) | 100% (ledger + beads tracked) |

## 3. User & Stakeholder Context

### Primary Persona: Loa Power User (zergucci)

Developers who use Loa's full workflow for feature development and are comfortable with `/run sprint-plan`, beads, and the implement/review/audit cycle. They deploy features, test in production, and need to fix bugs quickly **without leaving the Loa ecosystem**.

**Pain points**:
- Full plan-and-analyze is overkill for bug fixes
- After context compaction, Loa forgets sprint completion status
- Resorting to "raw Claude" loses all quality gates and traceability

**Needs**:
- Describe bug → Loa investigates → test-first fix → review → audit
- Bugs tracked in beads with full lifecycle
- Autonomous mode for batch bug fixing

### Secondary Persona: Loa New User

Developers exploring Loa who hit their first bug. The `/bug` truename provides a safe entry point that's less intimidating than the full workflow while still teaching Loa's quality culture (test-first, review gates).

## 4. Functional Requirements

### FR1: Bug Triage Phase (replaces PRD/SDD/Sprint Plan)

The triage phase is a **hybrid interview**: accept free-form input first, then ask structured follow-ups for any gaps.

#### FR1.0: Bug Eligibility Policy

**CRITICAL**: `/bug` is strictly for defects, not features. The triage phase enforces eligibility before proceeding.

**Eligibility criteria** (at least one required):
- References an **observed failure** (error message, crash, incorrect output)
- Includes a **stack trace** or error log
- Describes a **regression** from a known working baseline (version/commit)
- References a **failing test** by name

**Rejection criteria** (any one triggers escalation):
- Request describes **new behavior** not previously implemented
- No observable failure can be articulated
- Triage cannot produce a **reproducible failing condition** within the triage phase
- Request involves **architectural changes** to multiple systems

**Escalation path**: If input fails eligibility, triage terminates with:
> "This looks like a feature request, not a bug. Use `/plan` to start the full workflow."

The classification decision (accepted/rejected + reasoning) is logged in `triage.md` for audit trail.

#### FR1.1: Free-Form Input

The user provides initial bug description in any format:

```bash
/bug "Login fails when email contains a + character"
/bug "API returns 500 on empty cart checkout"
/bug   # Interactive — prompts for description
```

Accepted input formats:
- Plain text description
- Error message / stack trace (paste)
- GitHub issue reference (`/bug --from-issue 42`)
- Test failure name (`/bug "test_checkout_empty_cart fails"`)

#### FR1.2: Structured Follow-Up

After parsing the free-form input, Loa identifies gaps and asks targeted follow-ups. Maximum 3-5 questions covering:

| Field | Question If Missing | Priority |
|-------|-------------------|----------|
| Reproduction steps | "How do you trigger this bug?" | Required |
| Expected vs actual behavior | "What should happen vs what happens?" | Required |
| Severity | "Is this blocking production?" | Required |
| Affected area | "Which part of the codebase?" | Optional (Loa can analyze) |
| Environment | "Local, staging, or production?" | Optional |

#### FR1.3: Codebase Analysis

After triage, Loa performs targeted codebase analysis:

1. **Error trace analysis**: Parse stack traces to locate source files
2. **Keyword search**: Search codebase for relevant functions/modules
3. **Dependency mapping**: Identify related files that may need changes
4. **Test discovery**: Find existing tests for the affected area

Output: A structured **bug analysis** document (not a PRD) containing:
- Bug classification (runtime error, logic bug, edge case, integration issue)
- Affected files with line references
- Existing test coverage assessment
- Proposed fix strategy

#### FR1.3.1: Triage→Implement Handoff Contract

The triage phase produces a structured handoff document (`triage.md`) with **required fields** that the implement phase consumes:

| Field | Required | Description |
|-------|----------|-------------|
| `bug_id` | Yes | Stable identifier (timestamp + short hash) |
| `title` | Yes | One-line summary |
| `classification` | Yes | `runtime_error` \| `logic_bug` \| `edge_case` \| `integration_issue` \| `regression` |
| `reproduction_steps` | Yes | Numbered steps to trigger the bug |
| `expected_behavior` | Yes | What should happen |
| `actual_behavior` | Yes | What actually happens |
| `suspected_files` | Yes | List of files with line references |
| `test_target` | Yes | What the failing test should assert |
| `test_type` | Yes | `unit` \| `integration` \| `e2e` \| `contract` (see FR2) |
| `severity` | Yes | `critical` \| `high` \| `medium` \| `low` |
| `environment` | No | Where the bug was observed |
| `constraints` | No | Areas that must NOT be modified |
| `related_tests` | No | Existing tests in the affected area |

If the implement phase receives a `triage.md` missing required fields, it halts with an error and returns to triage.

#### FR1.4: Sprint Integration

After triage completes:

| Scenario | Action |
|----------|--------|
| Active sprint exists | Add bug as priority task to current sprint's task list |
| No active sprint | Create a **micro-sprint** with a single bug-fix task |

**Active Sprint Integration Rules**:
- Bug task is **prepended** to the task queue (not appended) — bugs are priority
- Bug task gets its own **branch** (`bugfix/{bug_id}`) even within an active sprint
- Review/audit of the bug fix is **scoped to the bug task only**, not the entire sprint
- Active sprint progress is **paused** during bug fix, then resumed
- If the active sprint is mid-review or mid-audit, the bug fix creates a separate review/audit pass

**Micro-sprint** structure:
- Minimal `grimoires/loa/sprint.md` with one task
- Registered in Sprint Ledger as a full cycle (type: `bugfix`)
- Single beads task created (if beads available)
- Branch: `bugfix/{bug_id}` (not `feature/`)

**Micro-sprint Lifecycle**:

| State | Condition | Marker |
|-------|-----------|--------|
| Created | Triage completes, sprint.md written | `triage.md` exists |
| In Progress | `/implement` begins | beads task `in_progress` |
| Review | Implementation complete | `reviewer.md` exists |
| Audit | Review passes | `auditor-sprint-feedback.md` exists |
| Completed | Audit passes | `COMPLETED` marker created |

**Naming convention**: `sprint-bug-{NNN}` where NNN is a global counter from the Sprint Ledger.

**Interaction with active sprints**: A micro-sprint is **independent** — it has its own review/audit cycle, its own COMPLETED marker, and its own ledger entry. It does not block or modify the active feature sprint.

### FR2: Test-First Execution

Bug mode enforces **test-driven debugging** (zergucci's core request). Test-first is **non-negotiable** — there is no degraded "fix-only" mode.

1. **Write failing test**: Create a test that reproduces the bug
2. **Verify test fails**: Run the test to confirm it captures the bug
3. **Implement fix**: Modify source code to fix the root cause
4. **Verify test passes**: Run the test to confirm the fix works
5. **Run full test suite**: Ensure no regressions

This is delegated to `/implement` with a `--bug` context flag that instructs the implementing skill to follow the test-first protocol.

#### FR2.1: Acceptable Test Types

The triage phase determines the appropriate test type based on bug classification:

| Test Type | When To Use | Example |
|-----------|-------------|---------|
| **Unit test** | Isolated logic bugs, pure function errors | Wrong calculation, bad parsing |
| **Integration test** | Cross-module failures, API contract violations | Service A calls Service B incorrectly |
| **E2E test** | User-facing workflow failures | Checkout flow breaks on edge case |
| **Contract test** | API response format changes, schema drift | Endpoint returns unexpected shape |

**Hierarchy of evidence** (minimum requirement):
1. At least one **automated test** that reproduces the bug (any type from above)
2. Plus a **documented reproduction script** in `triage.md` (human-readable steps)

**If no test infrastructure exists**: Bug mode halts during triage with:
> "No test runner detected. Set up test infrastructure before using /bug. See your framework's testing guide."

This is not a soft warning — test-first is a hard requirement. Projects without tests should use `/plan` to set up testing as a feature first.

### FR3: Quality Gates (Review + Audit)

After implementation, the standard quality gates execute:

1. **`/review-sprint`**: Code review of the bug fix
   - Verifies test adequately captures the bug
   - Checks fix doesn't introduce new issues
   - Validates fix addresses root cause (not just symptoms)

2. **`/audit-sprint`**: Security and quality audit
   - Standard audit checklist
   - Creates `COMPLETED` marker on approval

This reuses existing skill infrastructure — no new review/audit skills needed.

### FR4: Autonomous Mode

Bug mode supports autonomous execution through `/run`:

```bash
# Fix a single bug autonomously
/run --bug "Login fails with + in email"

# Fix bug from GitHub issue autonomously
/run --bug --from-issue 42
```

Autonomous mode follows the same circuit breaker rules as sprint execution:
- Same Issue: 3 cycles max
- No Progress: 5 cycles max
- Cycle Limit: 10 (reduced from 20 for bug scope)
- Timeout: 2 hours (reduced from 8 for bug scope)

**Human checkpoint requirement**: Autonomous mode creates a **draft PR** but does NOT mark it as ready for merge. The PR enters a `ready-for-human-review` state where the user must:
1. Review the fix, test, and audit artifacts
2. Explicitly approve (convert draft → ready)

**Confidence signals** included in the PR description:
- Reproduction strength: How reliably the test reproduces the bug
- Test type used (unit/integration/e2e/contract)
- Files touched and lines changed
- Risk level: `low` (isolated change) / `medium` (cross-module) / `high` (auth, payments, data)

**High-risk area blocking**: For bugs in sensitive areas (authentication, payments, data migrations, encryption), autonomous mode requires explicit user opt-in via `--allow-high`. Without it, autonomous mode halts after triage with:
> "Bug is in a high-risk area ({area}). Use `/run --bug --allow-high` to proceed autonomously, or fix interactively with `/bug`."

### FR5: Artifact Trail

Bug mode creates a traceable artifact trail:

```
grimoires/loa/a2a/bug-{id}/
├── triage.md              # Bug analysis from triage phase (handoff contract)
├── reviewer.md            # Review findings
├── auditor-sprint-feedback.md  # Audit findings
└── COMPLETED              # Completion marker
```

**ID scheme**: `{timestamp}-{short_hash}` (e.g., `20260211-a3f2b1`). The timestamp is `YYYYMMDD` and the short hash is 6 hex characters derived from the bug title + timestamp. This ensures:
- **Uniqueness**: No collisions even for same-titled bugs on different days
- **Stability**: ID doesn't change if title is edited
- **Safety**: No user-provided text in filesystem paths (human-readable title stored inside `triage.md`)
- **Sortability**: Chronological ordering by directory name

If `--from-issue N` is used, the ID also includes the issue number: `20260211-i42-a3f2b1`.

### FR6: Process Compliance Amendment

The NEVER rule "NEVER skip from sprint plan directly to implementation" must be amended to allow bug mode's lightweight path:

**Current**: Code cannot be written without a sprint plan created by `/sprint-plan`
**Amended**: Code cannot be written without either (a) a sprint plan from `/sprint-plan`, OR (b) a bug triage from `/bug`

This is the **only** process compliance change. All other NEVER/ALWAYS rules remain intact.

## 5. Technical & Non-Functional Requirements

### TNF1: New Skill — `bug-triage`

A new skill directory at `.claude/skills/bug-triage/`:

| File | Purpose |
|------|---------|
| `index.yaml` | Metadata: `danger_level: moderate`, `effort_hint: medium`, `categories: [quality, debugging]` |
| `SKILL.md` | Triage workflow: input parsing, gap analysis, codebase analysis, sprint integration |
| `resources/templates/triage.md` | Template for bug analysis document |

**Triggers**: `/bug`, `debug bug`, `fix bug`, `bug report`

### TNF2: Run Mode Extension

Extend `.claude/skills/run-mode/SKILL.md` to support `--bug` flag:

- New entry point: `/run --bug "description"`
- Reduced circuit breaker limits (10 cycles, 2h timeout)
- Single-sprint loop: triage → implement → review → audit
- Same ICE git safety, draft PR creation, post-PR validation

### TNF3: Sprint Ledger Integration

Micro-sprints registered in `grimoires/loa/ledger.json`:

```json
{
  "type": "bugfix",
  "label": "Bug: Login fails with + in email",
  "sprints": ["sprint-bug-1"],
  "source_issue": "#42"
}
```

### TNF4: Beads Integration

If beads_rust (`br`) is available:

- Create task from triage output: `br create "Fix: {bug_title}" --label bug`
- Track lifecycle: `br update {id} --status in_progress` → `br close {id}`
- Link to parent sprint if adding to existing sprint

### TNF5: Golden Path Awareness

While `/bug` is a truename (not a golden path command), the golden path should be **aware** of it:

- `/loa` status should show active bug fixes
- `/build` should not conflict with active bug micro-sprints
- `golden-path.sh` state detection should recognize bug cycles

### TNF6: Performance

| Metric | Target |
|--------|--------|
| Triage phase completion | <2 minutes (with follow-ups) |
| Total bug fix cycle (interactive) | <15 minutes for simple bugs |
| Total bug fix cycle (autonomous) | <30 minutes including review + audit |

## 6. Scope & Prioritization

### MVP (Sprint 1)

| # | Feature | Priority |
|---|---------|----------|
| 1 | `/bug` command with hybrid triage | P0 |
| 2 | Micro-sprint creation (when no active sprint) | P0 |
| 3 | Test-first execution via `/implement --bug` | P0 |
| 4 | Review + audit gates (reuse existing) | P0 |
| 5 | Artifact trail in `grimoires/loa/a2a/bug-{id}/` | P0 |
| 6 | Process compliance amendment | P0 |
| 7 | Beads integration | P1 |

### Sprint 2

| # | Feature | Priority |
|---|---------|----------|
| 1 | Autonomous mode (`/run --bug`) | P0 |
| 2 | Sprint Ledger integration (bugfix cycle type) | P0 |
| 3 | `--from-issue` GitHub issue intake | P1 |
| 4 | Golden path awareness (`/loa` shows bug status) | P1 |

### Out of Scope

| Feature | Reason |
|---------|--------|
| Bug mode as golden path command | Keeps 5-command golden path pristine; truename for power users |
| Automated bug detection | Bug mode is reactive (user reports bug), not proactive |
| Multi-bug batch triage | One bug per `/bug` invocation; use `/run --bug` for sequential autonomous fixes |
| Integration with external bug trackers (Jira, Linear) | Future consideration; GitHub issues via `--from-issue` is sufficient for MVP |

## 7. Risks & Dependencies

### Risks

| # | Risk | Impact | Mitigation |
|---|------|--------|------------|
| R1 | Process compliance amendment creates a "loophole" for bypassing planning | Users might use `/bug` for features to skip PRD | Strict bug eligibility policy (FR1.0): must reference observed failure, regression, or stack trace. Classification logged in triage.md. Escalation to `/plan` if not a bug. |
| R2 | Micro-sprints pollute the Sprint Ledger | Ledger fills with single-task cycles | Ledger type field (`bugfix` vs `feature`) enables filtering. `/ledger` shows counts by type. |
| R3 | Test-first enforcement blocks codebases without test infrastructure | Bug mode halts if project has no test runner | Triage detects missing test infrastructure and halts with guidance to set up tests via `/plan`. No degraded fix-only mode — test-first is non-negotiable. |
| R4 | Autonomous bug fixing may loop on hard-to-reproduce bugs | Circuit breaker triggers, wasting compute | Reduced limits (10 cycles, 2h) and enhanced circuit breaker: detect "flaky test" patterns and halt early. |
| R5 | Autonomous mode produces incorrect fixes without human verification | Wrong patch merged with a misleading test | Draft PR with `ready-for-human-review` state. Confidence signals in PR description. High-risk areas require `--allow-high` opt-in. |

### Dependencies

| # | Dependency | Type | Status |
|---|-----------|------|--------|
| D1 | Existing `/implement` skill | Reuse | Available |
| D2 | Existing `/review-sprint` skill | Reuse | Available |
| D3 | Existing `/audit-sprint` skill | Reuse | Available |
| D4 | Existing `/run` mode infrastructure | Extend | Available |
| D5 | Sprint Ledger (`grimoires/loa/ledger.json`) | Extend | Available |
| D6 | beads_rust (`br`) | Optional integration | Available where installed |
| D7 | Process compliance rules in `CLAUDE.loa.md` | Amendment needed | Controlled by framework |

## 8. User Stories

### US1: Interactive Bug Fix (Primary Flow)

**As a** Loa power user,
**I want to** describe a bug and have Loa investigate, write a test, fix it, and review it,
**So that** I can fix production bugs quickly without losing quality gates.

**Acceptance Criteria**:
- `/bug "description"` triggers eligibility check then hybrid triage (<2 min)
- Feature-shaped requests are rejected with escalation to `/plan`
- Codebase analysis identifies affected files
- Triage produces complete handoff contract (all required fields in triage.md)
- Appropriate test type selected based on bug classification
- Failing test written before fix attempted
- Fix validated by test passing
- `/review-sprint` and `/audit-sprint` execute
- Artifacts saved to `grimoires/loa/a2a/bug-{timestamp}-{hash}/`

### US2: Bug Fix During Active Sprint

**As a** developer mid-sprint,
**I want to** fix a production bug without derailing my current sprint,
**So that** the bug is tracked alongside sprint work.

**Acceptance Criteria**:
- `/bug` detects active sprint and adds bug as priority task
- Bug task is trackable in beads alongside sprint tasks
- Review/audit covers bug fix as part of sprint review
- Sprint completion not blocked by bug task completion

### US3: Autonomous Bug Fix

**As a** developer with a known bug,
**I want to** kick off an autonomous fix cycle and walk away,
**So that** the bug is fixed, tested, reviewed, and ready for my PR review.

**Acceptance Criteria**:
- `/run --bug "description"` runs triage → implement → review → audit autonomously
- Circuit breaker halts on stuck bugs (10 cycles, 2h timeout)
- Draft PR created in `ready-for-human-review` state (not auto-merged)
- PR includes confidence signals (reproduction strength, test type, risk level)
- High-risk areas (auth, payments, data) blocked unless `--allow-high` flag used
- ICE git safety prevents push to protected branches

### US4: Bug Fix from GitHub Issue

**As a** developer triaging GitHub issues,
**I want to** feed a GitHub issue directly into bug mode,
**So that** issue context (title, body, comments) informs the triage.

**Acceptance Criteria**:
- `/bug --from-issue 42` fetches issue via `gh issue view`
- Issue title, body, and comments parsed as triage input
- Follow-up questions only for gaps not covered by issue

---

*Generated by Loa plan-and-analyze from Issue #278 (zergucci) with codebase grounding.*
*Revised per Flatline Protocol review: 3 HIGH_CONSENSUS auto-integrated, 1 DISPUTED resolved (remove fix-only mode), 5 BLOCKERS addressed (eligibility policy, test hierarchy, micro-sprint lifecycle, safe IDs, human checkpoint).*
