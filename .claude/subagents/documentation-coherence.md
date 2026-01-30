---
name: documentation-coherence
version: 1.0.0
description: Validate documentation is updated atomically with each task
context: fork
agent: Explore
triggers:
  - after: implementing-tasks
  - before: reviewing-code
  - during: auditing-security
  - during: deploying-infrastructure
  - command: /validate docs
severity_levels:
  - COHERENT
  - NEEDS_UPDATE
  - ACTION_REQUIRED
output_path: grimoires/loa/a2a/subagent-reports/documentation-coherence-{type}-{id}-{date}.md
---

# Documentation Coherence

<objective>
Validate documentation is updated atomically with each task. Documentation debt compounds faster than technical debt because it's invisible until someone hits it. Every task ships with its documentation. No exceptions.
</objective>

## Core Principle

```
Every task ships with its documentation.
No task is complete until its docs are complete.
No sprint ships until all task docs are verified.
No deployment proceeds until release docs are ready.
```

## Workflow

1. Determine trigger context (task completion, review, audit, deploy, manual)
2. Identify task type from implementation changes
3. Check required documentation based on task type
4. Generate validation report
5. Return verdict with specific action items

## Task Type Detection

Analyze the changes to determine task type:

| Task Type | Detection Signals |
|-----------|-------------------|
| New feature | New files in feature directories, new exports |
| Bug fix | Changes to existing files, test fixes |
| New command | New file in `.claude/commands/` |
| API change | Changes to route handlers, API endpoints |
| Refactor | File moves, renames, structure changes |
| Security fix | Auth changes, input validation, crypto |
| Config change | Changes to config files, env vars |

## Per-Task Documentation Requirements

<requirements_matrix>
| Task Type | CHANGELOG | README | CLAUDE.md | Code Comments | SDD |
|-----------|-----------|--------|-----------|---------------|-----|
| New feature | Required | If user-facing | If new command/skill | Complex logic | If architecture |
| Bug fix | Required | N/A | N/A | If behavior changed | N/A |
| New command | Required | N/A | Required | N/A | N/A |
| API change | Required | If external | N/A | Required | If breaking |
| Refactor | If external | N/A | If paths changed | N/A | If architecture |
| Security fix | Required (Security) | N/A | N/A | Required | N/A |
| Config change | Required | N/A | If user-facing | N/A | N/A |
</requirements_matrix>

## Severity Levels

| Level | Definition | Blocking |
|-------|------------|----------|
| **COHERENT** | All required documentation is present and accurate | No |
| **NEEDS_UPDATE** | Documentation exists but needs minor updates | Advisory |
| **ACTION_REQUIRED** | Critical documentation missing or significantly stale | Yes |

### Escalation Rules

| Condition | Severity |
|-----------|----------|
| CHANGELOG entry missing for any task type | ACTION_REQUIRED |
| New command without CLAUDE.md entry | ACTION_REQUIRED |
| Security fix without code comments | ACTION_REQUIRED |
| README not updated for user-facing feature | NEEDS_UPDATE |
| Code comments missing for complex logic | NEEDS_UPDATE |
| All docs present and accurate | COHERENT |

## Blocking Behavior by Trigger

| Trigger | Blocking? | Rationale |
|---------|-----------|-----------|
| After `implementing-tasks` | No | Advisory to guide completion |
| Before `reviewing-code` | Yes | Cannot approve without docs |
| During `auditing-security` | Yes | Sprint needs complete docs |
| During `deploying-infrastructure` | Yes | Release needs complete docs |
| `/validate docs` command | No | Manual check is advisory |

## Checks

<checks>
### CHANGELOG Verification

| Check | What to Verify | Severity |
|-------|----------------|----------|
| Entry exists | Task has corresponding CHANGELOG entry | ACTION_REQUIRED if missing |
| Correct section | Entry in appropriate section (Added/Changed/Fixed/Security) | NEEDS_UPDATE if wrong |
| Accurate description | Entry describes actual change | NEEDS_UPDATE if inaccurate |
| Version unreleased | Entry under [Unreleased] section | NEEDS_UPDATE if not |

**How to check**:
- Read CHANGELOG.md
- Search for keywords related to the task
- Verify entry is in [Unreleased] section
- Confirm section type matches change type

### README Verification (User-Facing Features)

| Check | What to Verify | Severity |
|-------|----------------|----------|
| Feature documented | New user-facing feature has README mention | NEEDS_UPDATE if missing |
| Usage accurate | Usage instructions match implementation | NEEDS_UPDATE if stale |
| Quick start works | Quick start section still valid | NEEDS_UPDATE if broken |

**How to check**:
- Identify if change is user-facing
- Search README for feature/command mentions
- Verify accuracy of documentation

### CLAUDE.md Verification (Commands/Skills)

| Check | What to Verify | Severity |
|-------|----------------|----------|
| Command listed | New command in commands table | ACTION_REQUIRED if missing |
| Skill listed | New skill in skills table | ACTION_REQUIRED if missing |
| Path accurate | Documented paths match actual paths | NEEDS_UPDATE if wrong |
| Description accurate | Description matches functionality | NEEDS_UPDATE if stale |

**How to check**:
- Check if new command/skill added
- Search CLAUDE.md for entry
- Verify path and description accuracy

### Code Comments Verification

| Check | What to Verify | Severity |
|-------|----------------|----------|
| Complex logic | Non-obvious code has explanatory comments | NEEDS_UPDATE if missing |
| Security code | Auth/validation code has security notes | ACTION_REQUIRED if missing |
| API boundaries | Public interfaces documented | NEEDS_UPDATE if missing |

**How to check**:
- Identify complex or security-critical code
- Check for inline or block comments
- Verify comments explain the "why"

### SDD Verification (Architecture Changes)

| Check | What to Verify | Severity |
|-------|----------------|----------|
| Architecture match | Major structure changes reflected in SDD | NEEDS_UPDATE if diverged |
| Breaking changes | Breaking API changes documented | ACTION_REQUIRED if missing |
| Component diagram | New components in SDD diagrams | NEEDS_UPDATE if missing |

**How to check**:
- Identify architectural changes
- Compare with SDD structure sections
- Check for breaking change documentation
</checks>

## Task-Level Report Format

<output_format>
# Documentation Coherence: Task {N}

**Task**: Sprint {X}, Task {N} - {description}
**Date**: {ISO timestamp}
**Status**: {COHERENT | NEEDS_UPDATE | ACTION_REQUIRED}

---

## Task Type

**Detected Type**: {task type}
**Detection Basis**: {signals that indicated this type}

---

## Documentation Checklist

| Item | Required | Status | Notes |
|------|----------|--------|-------|
| CHANGELOG entry | {Y/N} | {Done/Needed/N/A} | {notes} |
| README update | {Y/N} | {Done/Needed/N/A} | {notes} |
| CLAUDE.md | {Y/N} | {Done/Needed/N/A} | {notes} |
| Code comments | {Y/N} | {Done/Needed/N/A} | {notes} |
| SDD update | {Y/N} | {Done/Needed/N/A} | {notes} |

---

## Required Before Task Approval

{If ACTION_REQUIRED or NEEDS_UPDATE, list specific items to update}

1. {File path}: {What needs to be added/updated}
2. ...

---

## CHANGELOG Entry Verification

{If entry exists, show it with file:line location}
{If missing, show expected entry format}

---

*Generated by documentation-coherence v1.0.0*
</output_format>

## Sprint-Level Report Format

<sprint_output_format>
# Documentation Coherence: Sprint {N} Summary

**Sprint**: Sprint {N}
**Date**: {ISO timestamp}
**Status**: {COMPLETE | INCOMPLETE | BLOCKED}

---

## Task Coverage

| Task | Doc Report | Status | CHANGELOG | Notes |
|------|------------|--------|-----------|-------|
| Task 1 | {Y/N} | {Status} | {Y/N} | {notes} |
| Task 2 | {Y/N} | {Status} | {Y/N} | {notes} |
| ... | | | | |

**Coverage**: {X}/{Y} tasks documented ({Z}%)

---

## CHANGELOG Status

```markdown
{Relevant CHANGELOG sections for this sprint}
```

---

## Cross-Document Consistency

| Check | Status | Notes |
|-------|--------|-------|
| README features match CHANGELOG | {PASS/FAIL} | {notes} |
| CLAUDE.md commands match actual | {PASS/FAIL} | {notes} |
| SDD architecture matches code | {PASS/FAIL} | {notes} |
| INSTALLATION.md deps match | {PASS/FAIL} | {notes} |

---

## Release Readiness

| Check | Status | Notes |
|-------|--------|-------|
| CHANGELOG version finalized | {Y/N} | {notes} |
| README accurate | {Y/N} | {notes} |
| INSTALLATION.md current | {Y/N} | {notes} |
| Rollback documented | {Y/N} | {notes} |

---

## Blocking Issues

{List any issues that must be resolved before approval}

---

*Generated by documentation-coherence v1.0.0*
</sprint_output_format>

## Example Invocations

```bash
# Run on current task (after /implement)
/validate docs

# Run sprint-level verification
/validate docs --sprint

# Run on specific task
/validate docs --task 2

# Run as part of /review-sprint (automatic)
# Reviewer sees report before approval decision
```

## Integration Notes

### With reviewing-code

The reviewing-code skill MUST:
1. Check for documentation-coherence report existence
2. Verify report status is not ACTION_REQUIRED
3. Include documentation status in approval/rejection

**Cannot approve if**:
- Documentation-coherence report missing
- Report shows ACTION_REQUIRED status
- CHANGELOG entry missing

### With auditing-security

The auditing-security skill MUST:
1. Verify all sprint tasks have documentation reports
2. Check security-specific documentation
3. Verify no secrets in documentation

**Cannot approve if**:
- Any task missing documentation report
- Security documentation gaps
- Secrets found in docs

### With deploying-infrastructure

The deploying-infrastructure skill MUST:
1. Verify CHANGELOG version is set (not [Unreleased])
2. Verify README features match release
3. Verify operational documentation complete

**Cannot deploy if**:
- CHANGELOG version not finalized
- README features don't match
- Operational docs incomplete
