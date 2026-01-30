# Phase Completion Checklist

Use this checklist to verify each phase is complete before proceeding.

---

## Phase 0: Preflight ✓

- [ ] `grimoires/loa/NOTES.md` read (or created)
- [ ] No CRITICAL blockers in blockers section
- [ ] System Zone integrity verified (`.loa-version.json` exists)
- [ ] Work item selected from WORKLEDGER.md
- [ ] Attention budget counters initialized
- [ ] Trajectory file created: `grimoires/{project}/trajectory/{date}.jsonl`
- [ ] Preflight entry logged to trajectory

---

## Phase 1: Discovery ✓

- [ ] Codebase grounded (if new repo): `/ride` completed
- [ ] Requirements discovered: `/discover` completed
- [ ] PRD exists: `grimoires/{project}/prd.md`
- [ ] PRD has executive summary
- [ ] PRD has problem statement with evidence
- [ ] PRD has measurable goals
- [ ] PRD has user stories with acceptance criteria
- [ ] PRD has technical constraints
- [ ] PRD has dependencies
- [ ] PRD has risks with mitigations
- [ ] All claims grounded with citations or [ASSUMPTION] flags
- [ ] Phase 1 logged to trajectory

---

## Phase 2: Design ✓

- [ ] Architecture designed: `/architect` completed
- [ ] SDD exists: `grimoires/{project}/sdd.md`
- [ ] SDD has system diagrams
- [ ] SDD has component design
- [ ] SDD has data flow
- [ ] SDD has security considerations
- [ ] Sprint planned: `/sprint-plan` completed
- [ ] `sprint.md` exists with atomic tasks
- [ ] Each task has acceptance criteria
- [ ] Task dependencies mapped
- [ ] SDD traces to PRD requirements (full coverage)
- [ ] Phase 2 logged to trajectory

---

## Phase 3: Implementation ✓

- [ ] Each sprint task completed
- [ ] Implementation follows SDD design
- [ ] Unit tests written and passing
- [ ] Integration tests passing (if applicable)
- [ ] No linter errors
- [ ] No security vulnerabilities introduced
- [ ] Conventional commit messages used
- [ ] Tool Result Clearing applied when needed
- [ ] Attention budget respected
- [ ] Changes committed (not yet pushed)
- [ ] Phase 3 logged to trajectory

---

## Phase 4: Audit ✓

- [ ] `/audit` executed
- [ ] All dimensions scored:
  - [ ] Security score: ___/5
  - [ ] Architecture score: ___/5
  - [ ] Code Quality score: ___/5
  - [ ] DevOps score: ___/5
  - [ ] Domain score (if applicable): ___/5
- [ ] `audit-report.md` generated
- [ ] All scores >= threshold (default: 4)?
  - YES → Proceed to Phase 5
  - NO → Enter Phase 4.5 Remediation
- [ ] Phase 4 logged to trajectory

---

## Phase 4.5: Remediation ✓

- [ ] Audit failures analyzed
- [ ] Findings sorted by severity
- [ ] CRITICAL/HIGH findings addressed
- [ ] Fixes verified locally
- [ ] Re-audit executed
- [ ] Remediation loop count: ___/3
- [ ] Loop outcome:
  - [ ] PASS → Proceed to Phase 5
  - [ ] FAIL & loops < 3 → Repeat 4.5
  - [ ] FAIL & loops >= 3 → Escalate
- [ ] Phase 4.5 logged to trajectory

---

## Phase 5: Submission ✓

- [ ] Audit PASSED (all scores >= threshold)
- [ ] Branch pushed to fork
- [ ] PR created with:
  - [ ] Conventional commit title
  - [ ] PRD summary in body
  - [ ] Sprint changes documented
  - [ ] Audit report linked
  - [ ] CI files note (if applicable)
- [ ] No secrets in diff
- [ ] PR URL logged
- [ ] Phase 5 logged to trajectory

---

## Phase 6: Deployment ✓

- [ ] Deployment approval obtained (if required)
- [ ] `/deploy-production` executed
- [ ] Deployment successful
- [ ] `/audit-deploy` executed
- [ ] Health checks passing
- [ ] No error rate increase
- [ ] Performance within bounds
- [ ] OR rollback executed (if issues)
- [ ] Phase 6 logged to trajectory

---

## Phase 7: Learning ✓

- [ ] Execution reviewed:
  - [ ] Successes noted
  - [ ] Remediations analyzed
  - [ ] Patterns identified
- [ ] NOTES.md updated with session summary
- [ ] MEMORY.md updated (if significant learning)
- [ ] Trajectory archived
- [ ] Work item marked complete in WORKLEDGER.md
- [ ] CHANGELOG.md updated
- [ ] Workspace committed and pushed
- [ ] Phase 7 logged to trajectory

---

## End-of-Run Summary

```
Work Item: ________________________
Started:   ________________________
Completed: ________________________
Phases:    0 ✓  1 ✓  2 ✓  3 ✓  4 ✓  5 ✓  6 ✓  7 ✓
Audit:     PASS / FAIL (after ___ remediation loops)
PR:        ________________________
Learnings: ________________________
```
