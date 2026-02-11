<!-- @loa-managed: true | version: 1.0.0 -->
# Loa Framework Instructions

## Process Compliance

### NEVER Rules
| Rule | Why |
|------|-----|
<!-- @constraint-generated: start process_compliance_never | hash:test -->
<!-- DO NOT EDIT — generated from .claude/data/constraints.json -->
| NEVER write application code outside of /implement skill invocation | Code written outside /implement bypasses review and audit gates |
<!-- C-PROC-001 no_code_outside_implement -->
<!-- @constraint-generated: end process_compliance_never -->

### ALWAYS Rules
| Rule | Why |
|------|-----|
<!-- @constraint-generated: start process_compliance_always | hash:test -->
<!-- DO NOT EDIT — generated from .claude/data/constraints.json -->
| ALWAYS complete the full implement → review → audit cycle | Partial cycles leave unreviewed code in the codebase |
<!-- C-PROC-005 always_complete_review_audit -->
| ALWAYS validate bug eligibility before /bug implementation | Prevents feature work from bypassing PRD/SDD gates via /bug |
<!-- C-PROC-015 validate_bug_eligibility -->
<!-- @constraint-generated: end process_compliance_always -->
