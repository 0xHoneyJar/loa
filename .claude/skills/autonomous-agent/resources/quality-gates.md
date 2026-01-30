# Quality Gates

Mandatory checkpoints that must PASS before proceeding.

---

## Gate 1: PRD Completeness

**When:** End of Phase 1 (Discovery)
**Blocks:** Phase 2 (Design)

### Criteria

| Check | Required |
|-------|----------|
| Executive summary present | ✓ |
| Problem statement with evidence | ✓ |
| Goals with metrics | ✓ |
| User stories with acceptance criteria | ✓ |
| Technical constraints documented | ✓ |
| Dependencies identified | ✓ |
| Risks with mitigations | ✓ |
| All claims grounded | ✓ |

### Pass Condition
ALL checks must be satisfied.

### On Failure
1. Identify missing sections
2. Re-run discovery for gaps
3. Do NOT proceed until complete

---

## Gate 2: Design Traceability

**When:** End of Phase 2 (Design)
**Blocks:** Phase 3 (Implementation)

### Criteria

| Check | Required |
|-------|----------|
| SDD covers all PRD requirements | ✓ |
| Each requirement has design mapping | ✓ |
| Sprint tasks trace to SDD | ✓ |
| Tasks are atomic | ✓ |
| Tasks have acceptance criteria | ✓ |
| No unaddressed requirements | ✓ |

### Pass Condition
100% requirement coverage in design.

### On Failure
1. Identify unmapped requirements
2. Update SDD/sprint
3. Re-verify traceability

---

## Gate 3: Implementation Quality

**When:** End of Phase 3 (Implementation)
**Blocks:** Phase 4 (Audit)

### Criteria

| Check | Required |
|-------|----------|
| All sprint tasks complete | ✓ |
| All tests passing | ✓ |
| No linter errors | ✓ |
| No security vulnerabilities | ✓ |
| Commits follow conventions | ✓ |
| Attention budget respected | ✓ |

### Pass Condition
ALL checks must be satisfied.

### On Failure
1. Fix failing tests
2. Resolve linter errors
3. Address security issues
4. Do NOT proceed to audit with known issues

---

## Gate 4: Audit Pass (CRITICAL)

**When:** End of Phase 4 (Audit)
**Blocks:** Phase 5 (Submission)

### Criteria

| Dimension | Minimum Score |
|-----------|---------------|
| Security | 4/5 |
| Architecture | 4/5 |
| Code Quality | 4/5 |
| DevOps | 4/5 |
| Domain (if applicable) | 4/5 |

### Pass Condition
ALL dimension scores >= audit_threshold (default: 4).

### On Failure
1. Enter Remediation Loop (Phase 4.5)
2. Fix highest severity findings first
3. Re-audit
4. Max 3 remediation loops
5. Escalate if still failing after 3 loops

### Escalation
If max_remediation_loops exceeded:
- Generate escalation report
- Halt autonomous execution
- Notify human
- Wait for guidance

---

## Gate 5: PR Quality

**When:** Before PR Creation (Phase 5)
**Blocks:** PR submission

### Criteria

| Check | Required |
|-------|----------|
| Audit PASSED | ✓ |
| No secrets in diff | ✓ |
| PR title follows conventions | ✓ |
| PR body has context | ✓ |
| Audit report linked | ✓ |

### Pass Condition
ALL checks must be satisfied.

### On Failure
1. Fix issue (remove secrets, improve title/body)
2. Re-verify
3. Do NOT create PR with issues

---

## Gate 6: Deployment Verification

**When:** After deployment (Phase 6)
**Blocks:** Completion

### Criteria

| Check | Threshold |
|-------|-----------|
| Health checks | All passing |
| Error rate | No increase |
| Latency p99 | Within bounds |
| Functionality | Core flows working |

### Pass Condition
ALL health metrics within acceptable bounds.

### On Failure
1. Initiate rollback
2. Verify rollback successful
3. Log incident
4. Escalate to human

---

## Gate Configuration

```yaml
# Default thresholds (can be overridden)
quality_gates:
  audit_threshold: 4
  max_remediation_loops: 3
  require_human_deploy_approval: true
  error_rate_increase_threshold: 0.01  # 1%
  latency_increase_threshold: 0.20     # 20%
```

---

## Gate Logging

Every gate check must be logged to trajectory:

```jsonl
{"ts":"...","agent":"autonomous-agent","phase":4,"action":"gate_check","gate":"audit_pass","scores":{"security":4,"architecture":5,"code_quality":4,"devops":4},"result":"PASS"}
```

```jsonl
{"ts":"...","agent":"autonomous-agent","phase":4,"action":"gate_check","gate":"audit_pass","scores":{"security":3,"architecture":4,"code_quality":4,"devops":4},"result":"FAIL","reason":"security below threshold"}
```
