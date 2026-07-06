# Sprint Task Implementer Reference

## Pre-Implementation Checklist

### Feedback Check (CRITICAL)
- [ ] Check `auditor-sprint-feedback.md` FIRST (security audit)
- [ ] Check `engineer-feedback.md` SECOND (senior lead)
- [ ] Check `integration-context.md` for org context
- [ ] If CHANGES_REQUIRED, address ALL issues before new work

### Context Gathering
- [ ] Read `grimoires/loa/sprint.md` for tasks and acceptance criteria
- [ ] Read `grimoires/loa/sdd.md` for technical architecture
- [ ] Read `grimoires/loa/prd.md` for business requirements
- [ ] Review existing codebase patterns and conventions
- [ ] Identify dependencies between tasks

## Code Quality Checklist

### Naming and Structure
- [ ] Clear, descriptive variable and function names
- [ ] Consistent naming conventions with existing code
- [ ] Logical file organization
- [ ] Appropriate separation of concerns

### Code Style
- [ ] Follows project style guide
- [ ] Consistent formatting (linting passes)
- [ ] No unnecessary complexity
- [ ] DRY principles applied

### Documentation
- [ ] Complex logic has explanatory comments
- [ ] Public APIs have documentation
- [ ] README updated if needed
- [ ] CHANGELOG updated with version

### Error Handling
- [ ] All errors are caught and handled
- [ ] Error messages are informative
- [ ] No silent failures
- [ ] Proper logging in place

### Security
- [ ] No hardcoded secrets or credentials
- [ ] Input validation present
- [ ] No SQL/XSS injection vulnerabilities
- [ ] Proper authentication checks

## Testing Checklist

### Unit Tests
- [ ] All new functions have unit tests
- [ ] Happy path tested
- [ ] Error conditions tested
- [ ] Edge cases covered
- [ ] Boundary conditions tested

### Integration Tests
- [ ] API endpoints tested
- [ ] Database interactions tested
- [ ] External service integrations mocked/tested

### Test Quality
- [ ] Tests are readable and maintainable
- [ ] Tests follow AAA pattern (Arrange, Act, Assert)
- [ ] No flaky tests
- [ ] Tests run in isolation

### Coverage
- [ ] Line coverage meets threshold
- [ ] Critical paths covered
- [ ] New code has corresponding tests

## Documentation Checklist

### Implementation Report
- [ ] Executive Summary present
- [ ] All tasks documented
- [ ] Files created/modified listed
- [ ] Test coverage documented
- [ ] Verification steps provided

### If Addressing Feedback
- [ ] Each feedback item quoted
- [ ] Resolution documented
- [ ] Verification steps for fixes

## Versioning Checklist

### Version Update
- [ ] Determined correct bump type (MAJOR/MINOR/PATCH)
- [ ] Updated package.json version
- [ ] Updated CHANGELOG.md
- [ ] Version referenced in report

### SemVer Decision Guide

| Change | Bump |
|--------|------|
| New feature | MINOR |
| Bug fix | PATCH |
| Breaking API change | MAJOR |
| Add optional parameter | MINOR |
| Rename exported function | MAJOR |
| Performance improvement (no API change) | PATCH |
| Security fix | PATCH (or MINOR if new feature) |

## Common Anti-Patterns to Avoid

### Code
- Empty catch blocks
- Magic numbers/strings
- Long functions (>50 lines)
- Deep nesting (>3 levels)
- Copy-paste code

### Testing
- Tests without assertions
- Testing implementation details
- Flaky tests
- Tests that depend on order
- No error case testing

### Documentation
- Outdated comments
- Missing verification steps
- Vague descriptions
- No file paths or line numbers

## Parallel Implementation Guidelines

### When to Split

| Context | Tasks | Strategy |
|---------|-------|----------|
| SMALL (<3,000 lines) | Any | Sequential |
| MEDIUM (3,000-8,000) | 1-2 | Sequential |
| MEDIUM | 3+ independent | Parallel |
| MEDIUM | 3+ with deps | Sequential with ordering |
| LARGE (>8,000) | Any | MUST split |

### Consolidation Requirements

After parallel implementation:
1. Collect all agent results
2. Check for conflicts
3. Run integration tests
4. Generate unified report

---

## Version Format: MAJOR.MINOR.PATCH

- **MAJOR**: Breaking changes (incompatible API changes)
- **MINOR**: New features (backwards-compatible additions)
- **PATCH**: Bug fixes (backwards-compatible fixes)

### When to Update Version

| Change | Bump | Example |
|--------|------|---------|
| New feature implementation | MINOR | 0.1.0 → 0.2.0 |
| Bug fix | PATCH | 0.2.0 → 0.2.1 |
| Breaking API change | MAJOR | 0.2.1 → 1.0.0 |

### Version Update Process

1. Determine bump type based on changes
2. Update package.json version
3. Update CHANGELOG.md with sections: Added, Changed, Fixed, Removed, Security
4. Reference version in completion comments

## Task Plan Template

Structure for the complex-task plan (see the implementing-tasks SKILL.md `<task_planning>` section for when to use it):

```markdown
## Task Plan: [Task Name]

### Objective
[What this task accomplishes]

### Approach
1. [Step 1]
2. [Step 2]
3. [Step 3]

### Files to Modify
- `path/to/file.ts` - [what changes]
- `path/to/other.ts` - [what changes]

### Dependencies
- [What must exist before this task]
- [External services needed]

### Risks
- [What could go wrong]
- [Mitigation approach]

### Verification
- [How we'll know it works]
- [Specific tests to write]

### Acceptance Criteria
- [ ] [Criterion 1]
- [ ] [Criterion 2]
```

## Beads Workflow (beads_rust)

When beads_rust (`br`) is installed, the full task lifecycle:

### Session Start
```bash
br sync --import-only  # Import latest state from JSONL
```

### Task Lifecycle
```bash
# Get ready work
.claude/scripts/beads/get-ready-work.sh 1 --ids-only

# Update task status
br update <task-id> --status in_progress

# Log discovered issues during implementation
.claude/scripts/beads/log-discovered-issue.sh "<parent-id>" "Issue description" bug 2

# Complete task
br close <task-id> --reason "Implemented per acceptance criteria"
```

### Semantic Labels for Tracking
| Label | Purpose | Example |
|-------|---------|---------|
| `discovered-during:<id>` | Traceability | Auto-added by log-discovered-issue.sh |
| `needs-review` | Review gate | `br label add <id> needs-review` |
| `review-approved` | Passed review | `br label add <id> review-approved` |
| `security` | Security concern | `br label add <id> security` |

### Session End
```bash
br sync --flush-only  # Export SQLite → JSONL before commit
```

**Protocol Reference**: See `.claude/protocols/beads-integration.md`

## File Creation Safety (CRITICAL)

When creating source files, Bash heredocs can **silently corrupt** content containing template literal syntax.

### The Problem

JSX/TypeScript template literals (`${variable}`) use identical syntax to shell variables:

```bash
# DANGEROUS: Unquoted heredoc - ${active} becomes empty string
cat > Button.tsx << EOF
<button className={`btn ${active ? 'active' : ''}`}>
EOF
# Result: <button className={`btn  ? 'active' : ''`}>  ← CORRUPTED
```

This corruption is **silent** - no error is raised, the file is created, and the bug may not be caught until runtime.

### Rules

1. **Use Write tool** for ALL source files (PREFERRED)
   - `.tsx`, `.jsx`, `.ts`, `.js`, `.vue`, `.svelte`, etc.
   - Content is passed exactly as-is
   - No shell interpretation occurs

2. **If heredoc required**, use **quoted delimiter**:
   ```bash
   cat > file.tsx <<'EOF'  # Note: 'EOF' is QUOTED
   const x = `Value: ${variable}`;  # Preserved literally
   EOF
   ```

3. **NEVER use unquoted heredoc** for source files:
   ```bash
   cat > file.tsx << EOF   # DANGEROUS - will corrupt ${...}
   ```

### High-Risk Extensions

Always use Write tool or quoted heredoc for:
- `.tsx`, `.jsx` - React/JSX
- `.ts`, `.js`, `.mjs`, `.cjs` - JavaScript/TypeScript
- `.vue`, `.svelte`, `.astro` - Component frameworks
- `.graphql`, `.gql` - GraphQL
- `.md` - Markdown with code blocks

### Pre-Write Checklist Addition

- [ ] File extension checked (source file → Write tool)
- [ ] Content contains `${...}` → verified method is safe

### Protocol Reference

See `.claude/protocols/safe-file-creation.md` for complete decision tree and examples.
