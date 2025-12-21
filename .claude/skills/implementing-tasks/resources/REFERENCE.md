# Sprint Task Implementer Reference

## Pre-Implementation Checklist

### Feedback Check (CRITICAL)
- [ ] Check `auditor-sprint-feedback.md` FIRST (security audit)
- [ ] Check `engineer-feedback.md` SECOND (senior lead)
- [ ] Check `integration-context.md` for org context
- [ ] If CHANGES_REQUIRED, address ALL issues before new work

### Context Gathering
- [ ] Read `loa-grimoire/sprint.md` for tasks and acceptance criteria
- [ ] Read `loa-grimoire/sdd.md` for technical architecture
- [ ] Read `loa-grimoire/prd.md` for business requirements
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
