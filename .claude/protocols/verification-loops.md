# Verification Loops Protocol

## Purpose

Static analysis (subagents) catches patterns. Verification catches runtime reality.
"Give Claude a way to verify its work" - this 2-3x quality of final result.

## Verification Hierarchy

| Level | Method | When |
|-------|--------|------|
| 1. Tests | Run test suite | After any code change |
| 2. Type check | Run compiler/type checker | After any code change |
| 3. Lint | Run linter | After any code change |
| 4. Build | Compile/bundle | After changes that affect build |
| 5. Integration | Run integration tests | After API/service changes |
| 6. E2E | Run end-to-end tests | Before review approval |
| 7. Manual | Human verification | Before deployment |

## Agent Responsibilities

### implementing-tasks

After completing implementation:

1. **Run tests:** `npm test` / `pytest` / equivalent
2. **Include results:** Test output in task completion message
3. **Fix failures:** Task not complete if tests fail
4. **Document gaps:** Note any untested scenarios in NOTES.md

```markdown
## Task Completion: Task 4

### Implementation
- Created src/middleware/rate-limit.ts
- Added Redis integration

### Verification
```bash
$ npm test

 PASS  tests/middleware/rate-limit.test.ts
 ✓ should allow requests under limit (45ms)
 ✓ should block requests over limit (23ms)
 ✓ should reset after window (102ms)

Test Suites: 1 passed, 1 total
Tests:       3 passed, 3 total
```

### Gaps
- No load testing yet (deferred to pre-deployment)
```

### reviewing-code

Before approval:

1. **Verify tests ran:** Check implementation includes test output
2. **Verify tests pass:** No failing tests in output
3. **Run additional checks:** If tests seem insufficient, request more

### deploying-infrastructure

Before deployment:

1. **Run full test suite:** All tests, not just changed
2. **Run E2E tests:** Full application verification
3. **Smoke test staging:** Manual verification of key flows
4. **Document results:** Include in deployment report

## Project-Specific Verification

Each project should define verification in `grimoires/loa/context/verification.md`:

```markdown
# Verification Approach

## Test Commands
- Unit: `npm test`
- Integration: `npm run test:integration`
- E2E: `npm run test:e2e`

## Build Verification
- Build: `npm run build`
- Type check: `npm run typecheck`

## Manual Verification
Key flows to verify manually before deployment:
1. User registration and login
2. Core feature X workflow
3. Payment flow (if applicable)

## Performance Criteria
- p95 response time < 500ms
- Error rate < 0.1%
```

## Verification Failures

When verification fails:

1. **Stop:** Do not proceed with incomplete verification
2. **Fix:** Address the failure
3. **Re-verify:** Run verification again
4. **Document:** Note what failed and how it was fixed

## Minimum Viable Verification

At absolute minimum, every task must:
- [ ] Run existing tests
- [ ] Pass existing tests
- [ ] Include test output in completion message

Without this, task is not complete.

## Verification vs Subagents

| Aspect | Subagents | Verification |
|--------|-----------|--------------|
| What | Static analysis | Runtime execution |
| When | Before review | During implementation |
| Catches | Patterns, drift | Actual bugs |
| Cost | Low (no execution) | Medium (runs code) |
| Coverage | Structure | Behavior |

Both are needed. Subagents catch architectural issues. Verification catches runtime bugs.

## Integration with Quality Gates

```
implement → verify → subagent scan → review → audit → deploy
              ↑           ↑
         Run tests    Static checks
```

Verification happens BEFORE subagent scans. If tests fail, don't waste time on static analysis.
