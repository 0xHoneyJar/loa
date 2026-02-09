# Rollback Playbook — Sprint 1 (Skill Benchmark Audit)

**Version**: 1.0.0
**Date**: 2026-02-09
**Issue**: #261
**Sprint**: Sprint 1 — Validation Foundation + Size Compliance

---

## Decision Criteria

### Who Decides

- **Primary**: @janitooor (maintainer)
- **Escalation**: Any contributor who observes regression signals

### Signals That Trigger Rollback

| Signal | Severity | Action |
|--------|----------|--------|
| Skill invocation fails after description change | HIGH | Rollback affected index.yaml |
| `/ride` produces different output after SKILL.md refactor | HIGH | Restore SKILL.md.bak |
| Validation script false-positives block CI | MEDIUM | Remove from CI, investigate |
| Schema change breaks existing tooling | MEDIUM | Revert schema changes |
| Near-limit skill exceeds 5K after unrelated edit | LOW | Monitor, no rollback needed |

---

## Rollback Steps

### Step 1: Restore riding-codebase SKILL.md

```bash
# Verify backup exists
ls -la .claude/skills/riding-codebase/SKILL.md.bak

# Restore from backup
cp .claude/skills/riding-codebase/SKILL.md.bak .claude/skills/riding-codebase/SKILL.md

# Remove extracted reference files
rm -rf .claude/skills/riding-codebase/resources/references/

# Verify word count is back to original
wc -w < .claude/skills/riding-codebase/SKILL.md
# Expected: ~6,905 words
```

### Step 2: Revert Schema Changes

```bash
# Revert description maxLength from 1024 back to 500
# Revert: remove negative_triggers field
git checkout main -- .claude/schemas/skill-index.schema.json
```

### Step 3: Remove Validation Script and Config

```bash
# Remove new files
rm -f .claude/scripts/validate-skill-benchmarks.sh
rm -f .claude/scripts/test-skill-benchmarks.sh
rm -f .claude/schemas/skill-benchmark.json
```

### Step 4: Remove CI Integration (if added)

```bash
# If the validator was added to a GitHub Actions workflow,
# revert that workflow file to the pre-Sprint-1 state
git checkout main -- .github/workflows/<workflow-file>.yml
```

---

## Re-Validation After Rollback

```bash
# 1. Verify existing validation still passes
.claude/scripts/validate-skills.sh

# 2. Verify no new files left behind
git status

# 3. Verify riding-codebase word count is original
wc -w < .claude/skills/riding-codebase/SKILL.md
# Should be ~6,905

# 4. Verify schema is original
jq '.properties.description.maxLength' .claude/schemas/skill-index.schema.json
# Should be 500
```

---

## Partial Rollback Options

Not all changes need to be rolled back together. Independent rollback paths:

| Change | Can Roll Back Independently | Dependencies |
|--------|----------------------------|-------------|
| Validation script + config | Yes | None |
| Schema update | Yes | None (descriptions still fit old limit) |
| riding-codebase refactor | Yes | Remove reference files too |
| Test fixtures | Yes | Already cleaned up after test run |

---

## Observation Period

- **Duration**: 7 days post-merge
- **SKILL.md.bak retention**: Keep for 7 days, then safe to remove
- **Monitoring**: Watch for skill invocation issues in daily usage
- **Decision point**: Day 7 — remove .bak files if no issues observed
