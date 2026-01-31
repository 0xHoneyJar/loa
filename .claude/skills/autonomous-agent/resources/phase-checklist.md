# Phase Execution Checklist

## Overview

Each phase in the 8-phase execution model has mandatory and optional checklist items. Items marked **[M]** are mandatory; items marked **[O]** are optional.

---

## Phase 0: Preflight

**Purpose**: Establish session context and detect operator type.

### Checklist

- [M] Detect operator type (AI/human)
- [M] Check for existing checkpoint in `.loa-checkpoint/`
- [M] If resuming, load checkpoint state
- [M] Initialize trajectory log
- [M] Validate project structure (grimoires/, .claude/)
- [O] Check for NOTES.md recovery anchor
- [O] Validate .loa.config.yaml exists

### Verification Commands

```bash
# Check operator detection
cat .loa-checkpoint/operator-type.yaml

# Verify trajectory initialized
ls -la grimoires/loa/a2a/trajectory/

# Check project structure
ls -la grimoires/loa/ .claude/skills/
```

### Exit Criteria

- Operator type determined
- Session state established (new or resumed)
- Trajectory log initialized

---

## Phase 1: Discovery

**Purpose**: Ground in codebase reality and create/validate PRD.

### Checklist

- [M] Check for existing `grimoires/loa/prd.md`
- [M] If brownfield: Run `/ride` for codebase grounding
- [M] If greenfield or PRD missing: Run `/plan-and-analyze`
- [M] Load context from `grimoires/loa/context/`
- [M] Validate PRD has goals (G-1, G-2, etc.)
- [O] Check reality staleness (> 7 days)
- [O] Validate PRD against codebase reality

### Verification Commands

```bash
# Check PRD exists
test -f grimoires/loa/prd.md && echo "PRD exists"

# Check for goals
grep -E "^## G-[0-9]|Goal.*G-[0-9]" grimoires/loa/prd.md

# Check reality freshness
stat grimoires/loa/reality/
```

### Exit Criteria

- `grimoires/loa/prd.md` exists and is valid
- Goals identified with G-N format
- Reality files current (if brownfield)

---

## Phase 2: Design

**Purpose**: Create architecture and sprint plan.

### Checklist

- [M] Check for existing `grimoires/loa/sdd.md`
- [M] If SDD missing: Run `/architect`
- [M] Validate SDD references PRD goals
- [M] Check for existing `grimoires/loa/sprint.md`
- [M] If sprint plan missing: Run `/sprint-plan`
- [M] Validate sprint plan has Appendix C (goal traceability)
- [O] Register sprints in Sprint Ledger
- [O] Validate task dependencies

### Verification Commands

```bash
# Check SDD exists
test -f grimoires/loa/sdd.md && echo "SDD exists"

# Check sprint plan
test -f grimoires/loa/sprint.md && echo "Sprint plan exists"

# Check goal traceability
grep -A 10 "Appendix C" grimoires/loa/sprint.md

# Check ledger
cat grimoires/loa/ledger.json
```

### Exit Criteria

- `grimoires/loa/sdd.md` exists and is valid
- `grimoires/loa/sprint.md` exists with tasks
- Appendix C maps goals to tasks

---

## Phase 3: Implementation

**Purpose**: Execute sprint tasks with production-quality code.

### Checklist

- [M] Determine current sprint from state or ledger
- [M] Check for audit feedback first (`auditor-sprint-feedback.md`)
- [M] Check for engineer feedback (`engineer-feedback.md`)
- [M] Address all feedback before new work
- [M] Run `/implement sprint-N` for each pending sprint
- [M] Create `reviewer.md` with implementation notes
- [M] Log decisions to NOTES.md
- [O] Run tests after each task
- [O] Update trajectory with task completions

### Verification Commands

```bash
# Check for feedback files
ls grimoires/loa/a2a/sprint-*/

# Verify reviewer.md created
test -f grimoires/loa/a2a/sprint-N/reviewer.md

# Run tests
npm test  # or appropriate test command
```

### Exit Criteria

- All sprint tasks implemented
- `reviewer.md` created with implementation notes
- Tests passing (if applicable)
- No unaddressed feedback

---

## Phase 4: Audit

**Purpose**: Quality gate validation through review and security audit.

### Checklist

- [M] Run `/review-sprint sprint-N` for code review
- [M] Wait for "All good" or address feedback
- [M] If feedback received, return to Phase 3
- [M] Run `/audit-sprint sprint-N` for security audit
- [M] Wait for "APPROVED" or address findings
- [M] If findings received, return to Phase 3
- [O] Track remediation loop count
- [O] Escalate if max_loops exceeded

### Verification Commands

```bash
# Check review status
grep -i "all good" grimoires/loa/a2a/sprint-N/engineer-feedback.md

# Check audit status
grep -i "APPROVED" grimoires/loa/a2a/sprint-N/auditor-sprint-feedback.md

# Check COMPLETED marker
test -f grimoires/loa/a2a/sprint-N/COMPLETED
```

### Exit Criteria

- Engineer feedback: "All good"
- Auditor feedback: "APPROVED"
- `COMPLETED` marker exists

---

## Phase 4.5: Remediation Loop

**Purpose**: Address audit/review findings iteratively.

### Checklist

- [M] Parse findings from feedback files
- [M] Prioritize by severity (CRITICAL > HIGH > MEDIUM > LOW)
- [M] Address findings in priority order
- [M] Increment loop counter
- [M] Check if max_loops exceeded (default: 3)
- [M] If exceeded, trigger escalation
- [M] Re-run audit after fixes
- [O] Log each remediation attempt

### Verification Commands

```bash
# Check loop count
grep "remediation_loop" .loa-checkpoint/phase-audit.yaml

# Check remaining findings
grep -E "CRITICAL|HIGH" grimoires/loa/a2a/sprint-N/auditor-sprint-feedback.md
```

### Exit Criteria

- All findings addressed, OR
- Escalation triggered (max_loops exceeded)

---

## Phase 5: Submit

**Purpose**: Create draft PR for human review.

### Checklist

- [M] Verify all sprints have COMPLETED marker
- [M] Aggregate changes across sprints
- [M] Create draft PR with summary
- [M] Reference PRD goals in PR description
- [M] Include test results in PR
- [O] Add reviewers based on CODEOWNERS
- [O] Link to related issues

### Verification Commands

```bash
# Check all sprints completed
for d in grimoires/loa/a2a/sprint-*/; do
  test -f "$d/COMPLETED" && echo "$d: COMPLETED"
done

# Check PR created
gh pr list --state open --head $(git branch --show-current)
```

### Exit Criteria

- Draft PR created
- All sprints referenced
- PRD goals linked

---

## Phase 6: Deploy (Optional)

**Purpose**: Deploy to staging/production if configured.

### Checklist

- [M] Check if deployment configured in `.loa.config.yaml`
- [M] If `require_human_deploy_approval: true`, wait for approval
- [M] Run `/deploy-production` if approved
- [M] Verify health checks pass
- [O] Create deployment documentation
- [O] Update deployment history

### Verification Commands

```bash
# Check deployment config
grep -A 5 "deployment:" .loa.config.yaml

# Check health after deploy
curl -s https://your-app/health
```

### Exit Criteria

- Deployment successful (if configured)
- Health checks passing
- Human approval obtained (if required)

---

## Phase 7: Learning

**Purpose**: Capture feedback and lessons learned.

### Checklist

- [M] Run `/retrospective` for session analysis
- [M] Generate feedback entries for gaps found
- [M] Check PRD against reality for goal drift
- [M] If major gaps found, trigger PRD iteration
- [M] Save learnings to `grimoires/loa/feedback/`
- [O] Run `/compound` for pattern extraction
- [O] Update NOTES.md with learnings

### Verification Commands

```bash
# Check feedback captured
ls grimoires/loa/feedback/

# Check for gaps
cat grimoires/loa/gaps.yaml

# Check learnings in NOTES
grep -A 5 "## Learnings" grimoires/loa/NOTES.md
```

### Exit Criteria

- Feedback file created with learnings
- Gaps documented (if found)
- PRD iteration triggered (if major gaps)

---

## Summary Table

| Phase | Required Files | Exit Signal |
|-------|----------------|-------------|
| 0 | `.loa-checkpoint/operator-type.yaml` | Operator detected |
| 1 | `grimoires/loa/prd.md` | PRD with goals |
| 2 | `grimoires/loa/sdd.md`, `sprint.md` | Sprint plan ready |
| 3 | `a2a/sprint-N/reviewer.md` | Tasks implemented |
| 4 | `a2a/sprint-N/COMPLETED` | Audit passed |
| 4.5 | N/A | Findings addressed |
| 5 | Draft PR | PR created |
| 6 | Deployment health | Deployed (optional) |
| 7 | `feedback/*.yaml` | Learnings captured |
