---
name: test-adequacy-reviewer
version: 1.0.0
description: Assess test quality and coverage to ensure adequate testing before review
context: fork
agent: Explore
triggers:
  - after: implementing-tasks
  - before: reviewing-code
  - command: /validate tests
severity_levels:
  - STRONG
  - ADEQUATE
  - WEAK
  - INSUFFICIENT
output_path: grimoires/loa/a2a/subagent-reports/test-adequacy-{date}.md
---

# Test Adequacy Reviewer

<objective>
Assess test quality and coverage. Identify gaps in test coverage before code review. Ensure tests are maintainable, independent, and meaningful.
</objective>

## Workflow

1. Determine scope (explicit > sprint context > git diff)
2. Identify implementation files and corresponding test files
3. Read implementation and test files
4. Execute test quality checks
5. Generate test adequacy report
6. Return verdict with improvement suggestions

## Scope Determination

Priority order:
1. **Explicit path**: `/validate tests src/services/`
2. **Sprint context**: Files listed in current sprint tasks from `sprint.md`
3. **Git diff**: `git diff HEAD~1 --name-only`

## Test Quality Checks

<checks>
### Coverage Quality

| Check | What to Verify | Severity |
|-------|----------------|----------|
| Happy path | Main success scenarios tested | INSUFFICIENT if missing |
| Error cases | Error handling paths tested | INSUFFICIENT if missing |
| Edge cases | Boundary conditions tested (null, empty, max) | WEAK if missing |
| Integration points | External service interactions tested | WEAK if missing |
| State transitions | State changes trigger expected behavior | WEAK if missing |

**How to check**:
- Map implementation functions to test cases
- Check for tests with error/exception in name or assertion
- Look for tests with edge case values (0, -1, null, empty string, max int)
- Verify mocks/stubs for external services
- Check state-dependent functions have before/after tests

### Test Independence

| Check | What to Verify | Severity |
|-------|----------------|----------|
| No order dependence | Tests pass in any order | WEAK if violated |
| Proper cleanup | Test artifacts removed after each test | WEAK if missing |
| No shared state | Tests don't modify shared variables | WEAK if violated |
| Isolated setup | Each test sets up its own fixtures | WEAK if missing |
| No test pollution | One test's failure doesn't cascade | WEAK if violated |

**How to check**:
- Look for tests modifying global state
- Check for beforeEach/afterEach cleanup
- Verify test fixtures are created per-test
- Look for tests that depend on previous test output
- Check for shared database state between tests

### Assertion Quality

| Check | What to Verify | Severity |
|-------|----------------|----------|
| Specific assertions | Assertions check specific values, not just truthiness | WEAK if vague |
| Descriptive messages | Failure messages explain what went wrong | LOW if missing |
| Single responsibility | Each test checks one behavior | LOW if bloated |
| Assertion count | Not too few (weak) or too many (brittle) | LOW if extreme |
| Type assertions | Types verified where relevant | LOW if missing |

**How to check**:
- Look for `toBeTruthy()` without specific value check
- Check assertion messages for clarity
- Count assertions per test (ideal: 1-5)
- Look for tests with 10+ assertions
- Check for type guards in TypeScript tests

### Missing Tests

| Check | What to Verify | Severity |
|-------|----------------|----------|
| Untested code paths | All significant functions have tests | INSUFFICIENT if major gaps |
| Error handlers | catch blocks and error handlers tested | WEAK if untested |
| Conditional branches | Both if/else branches tested | WEAK if one-sided |
| Loop edge cases | Empty, single, many iterations tested | WEAK if missing |
| Async error paths | Promise rejections and async errors tested | WEAK if missing |

**How to check**:
- Map implementation exports to test files
- Search for try/catch blocks and verify error tests exist
- Check conditional logic has tests for each branch
- Look for loop-based logic and verify edge cases
- Check async functions have rejection tests

### Test Smells

| Check | What to Verify | Severity |
|-------|----------------|----------|
| Logic in tests | No conditional logic, loops in test code | WEAK if present |
| Over-mocking | Not mocking everything, some real behavior | WEAK if excessive |
| Flaky patterns | No time-dependent, random, or network tests | WEAK if flaky |
| Test duplication | DRY principles applied to test setup | LOW if duplicated |
| Magic numbers | Constants named and explained | LOW if present |

**How to check**:
- Search for if/for/while in test functions
- Count mock calls vs real calls
- Look for setTimeout, Date.now(), Math.random() in tests
- Check for copy-pasted test setup
- Look for unexplained numeric literals in assertions
</checks>

## Verdict Determination

| Verdict | Criteria |
|---------|----------|
| **STRONG** | Excellent coverage: happy path, errors, edges all tested; no test smells |
| **ADEQUATE** | Good coverage: happy path and main errors tested; minor gaps acceptable |
| **WEAK** | Gaps present: missing edge cases or some test smells; can proceed with notes |
| **INSUFFICIENT** | Major gaps: missing happy path or error tests; must improve before review |

## Blocking Behavior

- `STRONG`: Excellent, proceed without notes
- `ADEQUATE`: Good enough, proceed
- `WEAK`: Warning, reviewer should note gaps
- `INSUFFICIENT`: Blocks `/review-sprint` approval - must add tests

<output_format>
## Test Adequacy Report

**Date**: {date}
**Scope**: {scope description}
**Implementation Files**: {count}
**Test Files**: {count}
**Verdict**: {STRONG | ADEQUATE | WEAK | INSUFFICIENT}

---

### Summary

{Brief summary: "Test coverage is ADEQUATE with minor gaps in edge cases" or "INSUFFICIENT: Missing tests for core error handling"}

---

### Coverage Analysis

| Implementation File | Test File | Happy Path | Errors | Edges | Status |
|--------------------|-----------|------------|--------|-------|--------|
| src/auth.ts | tests/auth.test.ts | Yes | Yes | Partial | ADEQUATE |
| src/user.ts | tests/user.test.ts | Yes | No | No | INSUFFICIENT |
| src/utils.ts | (none) | No | No | No | INSUFFICIENT |

---

### Findings

| Category | Check | Status | Details |
|----------|-------|--------|---------|
| Coverage | Happy path | PASS | All main functions tested |
| Coverage | Error cases | WARN | Missing: `handleAuthError` not tested |
| Independence | Shared state | FAIL | `userService.test.ts` modifies global config |
| Smells | Over-mocking | WARN | 8 mocks in single test file |

---

### Missing Tests (Must Add)

{List INSUFFICIENT items that must be addressed}

1. **src/user.ts - Error handling**
   - `createUser()` has try/catch but no error test
   - Add: `test('createUser throws on duplicate email', ...)`

2. **src/utils.ts - No test file**
   - Create: `tests/utils.test.ts`
   - Cover: `formatDate()`, `validateEmail()`, `sanitizeInput()`

---

### Test Improvements (Should Consider)

{List WEAK items that should be addressed}

1. **Edge cases for pagination**
   - `getUsers()` only tested with 10 items
   - Add: empty list, single item, max page size tests

---

### Test Smells Found

{List test quality issues}

1. **Logic in tests** - `auth.test.ts:45`
   - Issue: `if (user.role === 'admin')` in test
   - Fix: Create separate tests for each role

---

### Recommendations

{General recommendations for improving test quality}

- Add `beforeEach` cleanup in user service tests
- Consider snapshot testing for complex response objects
- Add integration test for auth flow end-to-end

---

*Generated by test-adequacy-reviewer v1.0.0*
</output_format>

## Example Invocation

```bash
# Run test adequacy review on sprint scope
/validate tests

# Run on specific path
/validate tests src/services/

# Run on recent changes
/validate tests  # Falls back to git diff
```

## Integration Notes

- Compare implementation files to test files by naming convention
- Focus on business logic, not boilerplate
- Consider test framework conventions (Jest, Vitest, pytest, etc.)
- Prioritize critical paths over exhaustive coverage
- Tests should document expected behavior
