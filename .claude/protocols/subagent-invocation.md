# Subagent Invocation Protocol

**Version**: 1.0.0
**Status**: Active
**Owner**: Framework

---

## Purpose

Define how Loa agents invoke validation subagents and process their results within the quality gate pipeline.

---

## Invocation Flow

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   /implement    │────▶│   Subagents     │────▶│  /review-sprint │
│   sprint-N      │     │   (optional)    │     │   sprint-N      │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                               │
                               ▼
                    ┌─────────────────────┐
                    │  subagent-reports/  │
                    │  ├── arch-*.md      │
                    │  ├── security-*.md  │
                    │  └── test-*.md      │
                    └─────────────────────┘
```

---

## Invocation Methods

### 1. On-Demand via /validate Command

User explicitly invokes validation:

```bash
/validate                    # All subagents, sprint scope
/validate architecture       # Specific subagent
/validate security src/auth/ # Specific scope
```

### 2. Automatic Triggers

Subagents declare triggers in their YAML frontmatter:

```yaml
triggers:
  - after: implementing-tasks   # Run after /implement
  - before: reviewing-code      # Run before /review-sprint approves
  - command: /validate type     # On-demand invocation
```

**Timing Options**:

| Option | When | Pros | Cons |
|--------|------|------|------|
| Post-implement | After `/implement` completes | Early detection | May slow workflow |
| Pre-review | Before `/review-sprint` approves | Safety net | Issues found late |
| On-demand only | `/validate` command | User control | May be forgotten |
| Hybrid (Recommended) | On-demand + pre-review | Flexibility + safety | Moderate complexity |

---

## Scope Determination

Subagents determine which files to validate using this priority:

### Priority Order

1. **Explicit argument** (highest priority)
   ```bash
   /validate security src/auth/
   # Scope: src/auth/**
   ```

2. **Sprint context** (if no explicit argument)
   - Read current sprint from `sprint.md`
   - Extract files listed in task definitions
   - Focus on files being modified in this sprint

3. **Git diff** (fallback)
   ```bash
   git diff HEAD~1 --name-only
   # Scope: recently changed files
   ```

### Scope Resolution Logic

```
if explicit_path:
    scope = explicit_path
elif sprint_context_available:
    scope = extract_files_from_sprint_tasks()
else:
    scope = git_diff_files()
```

---

## Report Output

### Location

All subagent reports go to:
```
grimoires/loa/a2a/subagent-reports/
```

### Naming Convention

```
{subagent-name}-{date}.md
```

Examples:
- `architecture-validation-2026-01-18.md`
- `security-scan-2026-01-18.md`
- `test-adequacy-2026-01-18.md`

### Report Structure

Each report must include:
1. **Header**: Date, scope, verdict
2. **Summary**: Brief findings overview
3. **Findings Table**: Category, check, status, details
4. **Critical Issues**: Blocking items
5. **Recommendations**: Actionable fixes

---

## Verdict Processing

### Severity to Action Mapping

| Subagent | Blocking Severity | Action |
|----------|-------------------|--------|
| architecture-validator | CRITICAL_VIOLATION | Block review approval |
| security-scanner | CRITICAL, HIGH | Block review approval |
| test-adequacy-reviewer | INSUFFICIENT | Block review approval |

### Integration with Quality Gates

```
Subagent runs
      ↓
Verdict returned
      ↓
[Blocking verdict?]
      ├── Yes → Stop workflow, require fixes
      └── No → Continue to next phase
```

### Blocking Behavior

When a blocking verdict is returned:

1. **Summarize findings** in response to user
2. **Do not proceed** with review approval
3. **Require fixes** before re-running validation
4. **Log to NOTES.md** for session continuity

---

## Subagent Loading

### Directory Structure

```
.claude/subagents/
├── README.md                    # Overview and usage
├── architecture-validator.md    # SDD compliance
├── security-scanner.md          # Vulnerability detection
└── test-adequacy-reviewer.md    # Test quality
```

### Loading Process

1. Read subagent file from `.claude/subagents/`
2. Parse YAML frontmatter for metadata
3. Extract checks from `<checks>` section
4. Use `<output_format>` as report template

### Frontmatter Schema

```yaml
name: string          # Subagent identifier
version: string       # Semantic version
description: string   # Brief description
triggers:             # When to run
  - after: skill-name
  - before: skill-name
  - command: /validate type
severity_levels:      # Valid verdicts
  - LEVEL_1
  - LEVEL_2
output_path: string   # Report location template
```

---

## Error Handling

### Subagent Not Found

```
Error: Subagent 'unknown-validator' not found in .claude/subagents/
Available subagents: architecture-validator, security-scanner, test-adequacy-reviewer
```

### Invalid Scope

```
Warning: No files found in scope 'src/nonexistent/'
Falling back to git diff scope.
```

### SDD Not Found

For architecture-validator:
```
Error: SDD not found at grimoires/loa/sdd.md
Run /architect first to generate SDD.
```

---

## Configuration

### .loa.config.yaml Options

```yaml
subagents:
  enabled: true                    # Master toggle
  auto_run_post_implement: false   # Run after /implement
  auto_run_pre_review: true        # Run before /review-sprint approval
  blocking_enabled: true           # Respect blocking verdicts
```

### Environment Overrides

```bash
LOA_SUBAGENTS_ENABLED=0           # Disable all subagents
LOA_SUBAGENTS_BLOCKING=0          # Ignore blocking verdicts (not recommended)
```

---

## Best Practices

1. **Run early, run often**: Use `/validate` during development
2. **Fix blocking issues immediately**: Don't accumulate technical debt
3. **Review drift warnings**: Minor issues compound over time
4. **Keep SDD updated**: Subagents validate against SDD, not assumptions
5. **Scope appropriately**: Narrow scope for faster validation

---

## Related Documentation

- `.claude/subagents/README.md` - Subagent overview
- `.claude/commands/validate.md` - /validate command
- `.claude/protocols/feedback-loops.md` - Quality gate pipeline
