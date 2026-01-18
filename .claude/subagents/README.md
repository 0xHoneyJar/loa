# Loa Subagents

Intelligent validation agents that run between implementation and review to catch issues early.

## Overview

Subagents are specialized validators that enhance Loa's quality gate pipeline. They run automatically or on-demand to detect architectural drift, security vulnerabilities, and test gaps before human review.

```
/implement → [Subagents] → /review-sprint → /audit-sprint
               │
    ┌──────────┴──────────┐
    │ architecture-validator │
    │ security-scanner       │
    │ test-adequacy-reviewer │
    └────────────────────────┘
```

## Available Subagents

| Subagent | Purpose | Blocking Severity |
|----------|---------|-------------------|
| `architecture-validator` | Verify implementation matches SDD | CRITICAL_VIOLATION |
| `security-scanner` | Detect vulnerabilities early | CRITICAL, HIGH |
| `test-adequacy-reviewer` | Assess test quality | INSUFFICIENT |

## Invocation

### On-Demand via /validate

```bash
/validate                    # Run all subagents on sprint scope
/validate architecture       # Run architecture-validator only
/validate security          # Run security-scanner only
/validate tests             # Run test-adequacy-reviewer only
/validate security src/auth/ # Run on specific scope
```

### Automatic Triggers

Subagents can run:
- **After `/implement`**: Early detection (optional, configurable)
- **Before `/review-sprint`**: Safety net before human review (recommended)

## Subagent Definition Format

Each subagent is a markdown file with YAML frontmatter:

```yaml
---
name: subagent-name
version: 1.0.0
description: What this subagent validates
triggers:
  - after: implementing-tasks
  - before: reviewing-code
  - command: /validate type
severity_levels:
  - LEVEL_1
  - LEVEL_2
output_path: grimoires/loa/a2a/subagent-reports/{type}-{date}.md
---

# Subagent Name

<objective>
What this subagent validates and why.
</objective>

<checks>
## Category 1
- Check 1
- Check 2

## Category 2
- Check 3
- Check 4
</checks>

<output_format>
Template for the validation report.
</output_format>
```

## Scope Determination

Subagents determine which files to validate from:

1. **Explicit argument**: `/validate security src/auth/` - highest priority
2. **Sprint context**: Current sprint task files from `sprint.md`
3. **Git diff**: Changed files since last commit - fallback

## Report Output

All reports go to `grimoires/loa/a2a/subagent-reports/`:

```
subagent-reports/
├── architecture-validation-2026-01-18.md
├── security-scan-2026-01-18.md
├── test-adequacy-2026-01-18.md
└── .gitkeep
```

## Severity Levels and Actions

### architecture-validator

| Level | Meaning | Action |
|-------|---------|--------|
| COMPLIANT | Matches SDD | Proceed |
| DRIFT_DETECTED | Minor deviation | Warn, proceed |
| CRITICAL_VIOLATION | Major deviation | Block approval |

### security-scanner

| Level | Meaning | Action |
|-------|---------|--------|
| CRITICAL | Exploitable vulnerability | Block approval |
| HIGH | Significant risk | Block approval |
| MEDIUM | Moderate risk | Warn, reviewer discretion |
| LOW | Minor issue | Informational |

### test-adequacy-reviewer

| Level | Meaning | Action |
|-------|---------|--------|
| STRONG | Excellent coverage | Proceed |
| ADEQUATE | Good enough | Proceed |
| WEAK | Gaps present | Warn, reviewer discretion |
| INSUFFICIENT | Major gaps | Block approval |

## Integration with Quality Gates

Subagents integrate with Loa's existing feedback loop:

```
/implement sprint-N
      ↓
/validate (optional or automatic)
      ↓
[Blocking issues?] → Yes → Fix issues, re-implement
      ↓ No
/review-sprint sprint-N
      ↓
/audit-sprint sprint-N
```

## Creating Custom Subagents

1. Create a new `.md` file in `.claude/subagents/`
2. Follow the YAML frontmatter format above
3. Define checks specific to your validation needs
4. Add to the `/validate` command if needed

## Protocol Reference

See `.claude/protocols/subagent-invocation.md` for the full invocation protocol.
