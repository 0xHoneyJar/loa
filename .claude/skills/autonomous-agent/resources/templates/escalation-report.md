# Escalation Report

**Generated:** {{timestamp}}
**Agent:** autonomous-agent
**Work Item:** {{work_item}}

---

## Summary

Autonomous execution has been **HALTED** after {{remediation_loops}} remediation attempts failed to meet quality thresholds.

Human intervention required.

---

## Audit Results

### Final Scores

| Dimension | Score | Threshold | Status |
|-----------|-------|-----------|--------|
| Security | {{security_score}}/5 | 4/5 | {{security_status}} |
| Architecture | {{architecture_score}}/5 | 4/5 | {{architecture_status}} |
| Code Quality | {{code_quality_score}}/5 | 4/5 | {{code_quality_status}} |
| DevOps | {{devops_score}}/5 | 4/5 | {{devops_status}} |
| Domain | {{domain_score}}/5 | 4/5 | {{domain_status}} |

### Failing Dimensions

{{#each failing_dimensions}}
- **{{name}}**: Score {{score}}/5 (needs {{threshold}})
{{/each}}

---

## Remediation History

### Loop 1
- **Findings addressed:** {{loop1_findings}}
- **Actions taken:** {{loop1_actions}}
- **Result:** {{loop1_result}}

### Loop 2
- **Findings addressed:** {{loop2_findings}}
- **Actions taken:** {{loop2_actions}}
- **Result:** {{loop2_result}}

### Loop 3
- **Findings addressed:** {{loop3_findings}}
- **Actions taken:** {{loop3_actions}}
- **Result:** {{loop3_result}}

---

## Outstanding Findings

{{#each outstanding_findings}}
### {{severity}}: {{title}}
- **Location:** {{location}}
- **Description:** {{description}}
- **Attempted fixes:** {{attempted_fixes}}
- **Why it persists:** {{persistence_reason}}
{{/each}}

---

## Recommendation

Based on analysis, human intervention needed for:

1. {{recommendation_1}}
2. {{recommendation_2}}
3. {{recommendation_3}}

---

## Trajectory Reference

Full execution log available at:
`grimoires/{{project}}/trajectory/{{date}}.jsonl`

---

## Next Steps

- [ ] Human reviews this escalation report
- [ ] Human addresses outstanding findings
- [ ] Human decides: fix and re-run OR accept with waivers
- [ ] Agent resumes with human guidance

---

*This escalation was generated automatically by the autonomous-agent skill after exhausting remediation attempts.*
