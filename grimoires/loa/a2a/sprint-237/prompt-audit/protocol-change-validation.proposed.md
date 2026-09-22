# Change Validation Protocol

Protocol for validating proposed changes against codebase reality before implementation.

---

## When to Apply

Apply change validation:

- Before starting `/implement` sprint tasks
- When planning major refactoring
- After updating PRD/SDD with new requirements
- When integrating external contributions
- Before merging branches with significant changes

---

## Validation Checklist

### 1. File Reference Validation

```bash
# Extract and validate file references
.claude/scripts/validate-change-plan.sh grimoires/loa/sprint.md
```

**Check that:**
- [ ] All referenced source files exist
- [ ] Directory structure matches expectations
- [ ] No typos in file paths

### 2. Function/Method Validation

**Check that:**
- [ ] Functions to be modified exist
- [ ] Function signatures match expectations
- [ ] No deprecated functions being extended

### 3. Dependency Validation

**Check that:**
- [ ] New dependencies are explicitly listed
- [ ] Existing dependencies are compatible
- [ ] No version conflicts introduced

### 4. Breaking Change Detection

**Check that:**
- [ ] API changes are documented
- [ ] Schema migrations are planned
- [ ] Downstream consumers are identified
- [ ] Rollback plan exists

---

## Integration with Workflow

### Validation in Preflight

Commands like `/implement` should include validation:

```yaml
pre_flight:
  - check: "script_passes"
    script: ".claude/scripts/validate-change-plan.sh"
    args: ["grimoires/loa/sprint.md"]
    error: "Change plan validation failed. Review warnings."
```

---

## Handling Validation Results

### Warnings (Exit Code 1)

Warnings indicate potential issues but don't block:

| Warning | Action |
|---------|--------|
| File not found | Verify path or confirm new file |
| Function not found | Confirm new function or fix reference |
| Uncommitted changes | Commit or stash before modifying |
| Dependency not installed | Add to package.json or requirements.txt |

### Blockers (Exit Code 2)

Blockers require explicit resolution:

| Blocker | Resolution |
|---------|------------|
| Breaking changes | Document migration path |
| Schema conflicts | Plan migration script |
| Security implications | Get security review |

---

## Evidence Requirements

A validated plan records, per touched file, the current state it was checked against (for a modification: size, functions, last change; for a new file: directory exists, no naming conflict, imports resolve; for a deletion: no imports, no test references, not a CODEOWNERS critical path, with the `grep` that proved it) and the proposed change.

---

## Automation

The same script fits a pre-commit hook or a CI step: run it against `grimoires/loa/sprint.md` when the file exists and fail on exit code 2 (blockers); warnings (exit 1) pass.

---

## NOTES.md Integration

Log the validation outcome and any acknowledged warnings as a Decision Log entry.

---

## Related Scripts

- `.claude/scripts/validate-change-plan.sh` - Main validation script
- `.claude/scripts/detect-drift.sh` - Drift detection for ongoing monitoring
- `.claude/scripts/check-prerequisites.sh` - Phase prerequisite checks
