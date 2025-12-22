# Senior Tech Lead Reviewer Reference

## Code Review Checklists

### Versioning (SemVer Compliance)
- [ ] package.json version updated appropriately
- [ ] CHANGELOG.md updated with new version entry
- [ ] Version bump type matches change type (MAJOR/MINOR/PATCH)
- [ ] Pre-release versions used correctly (alpha/beta/rc)

### Completeness
- [ ] All sprint tasks addressed
- [ ] All acceptance criteria met per task
- [ ] No tasks marked as "TODO" or "FIXME" without justification
- [ ] All previous feedback items addressed

### Functionality
- [ ] Code does what it's supposed to do
- [ ] Edge cases handled
- [ ] Error conditions handled gracefully
- [ ] Input validation present

### Code Quality
- [ ] Readable and maintainable
- [ ] Follows DRY principles
- [ ] Consistent with project conventions
- [ ] Appropriate comments for complex logic
- [ ] No commented-out code without explanation

### Testing
- [ ] Tests exist for all new code
- [ ] Tests cover happy paths
- [ ] Tests cover error conditions
- [ ] Tests cover edge cases
- [ ] Test assertions are meaningful
- [ ] Tests are readable and maintainable
- [ ] Can run tests successfully

### Security
- [ ] No hardcoded secrets or credentials
- [ ] Input validation and sanitization
- [ ] Authentication/authorization implemented correctly
- [ ] No SQL injection vulnerabilities
- [ ] No XSS vulnerabilities
- [ ] Dependencies are secure (no known CVEs)
- [ ] Proper error messages (no sensitive data leaked)

### Performance
- [ ] No obvious performance issues
- [ ] Database queries optimized
- [ ] Caching used appropriately
- [ ] No memory leaks
- [ ] Resource cleanup (connections, listeners, timers)

### Architecture
- [ ] Follows patterns from SDD
- [ ] Integrates properly with existing code
- [ ] Component boundaries respected
- [ ] No tight coupling
- [ ] Separation of concerns maintained

### Blockchain/Crypto Specific (if applicable)
- [ ] Private keys never exposed
- [ ] Gas limits set appropriately
- [ ] Reentrancy protection
- [ ] Integer overflow/underflow protection
- [ ] Proper nonce management
- [ ] Transaction error handling
- [ ] Event emissions for state changes

## Red Flags (Immediate Feedback Required)

### Security Red Flags
- Private keys in code or environment variables
- SQL queries built with string concatenation
- User input not validated or sanitized
- Secrets in Git history
- Authentication bypassed or missing
- Sensitive data in logs

### Quality Red Flags
- No tests for critical functionality
- Tests that don't actually test anything
- Copy-pasted code blocks
- Functions over 100 lines
- Nested callbacks or promises (callback hell)
- Swallowed exceptions (empty catch blocks)

### Architecture Red Flags
- Tight coupling between unrelated components
- Business logic in UI components
- Direct database access from routes/controllers
- God objects or classes
- Circular dependencies

### Performance Red Flags
- N+1 query problems
- Missing database indexes
- Synchronous operations blocking async flow
- Memory leaks (unclosed connections, leaked listeners)
- Infinite loops or recursion without base case

## Edge Cases to Verify

Always verify the code handles:
- Null/undefined values
- Empty arrays/objects
- Boundary values (0, -1, max integer)
- Invalid input types
- Network failures
- Database connection failures
- Race conditions
- Concurrent access
- Rate limits
- Timeout scenarios

## Feedback Quality Guidelines

### Be Specific
- BAD: "Fix the auth bug"
- GOOD: "src/auth/middleware.ts:42 - missing null check before user.id access"

### Be Clear
- BAD: "Improve error handling"
- GOOD: "Add try-catch around L67-73, throw 400 with message 'Invalid user ID format'"

### Be Educational
- BAD: "This is insecure"
- GOOD: "SQL injection via string concatenation (OWASP A03:2021). Use parameterized queries: `db.query('SELECT...', [userId])`"

### Prioritize
- CRITICAL: Security vulnerabilities, blocking bugs
- HIGH: Missing acceptance criteria, incomplete features
- MEDIUM: Code quality issues, missing tests
- LOW: Style improvements, nice-to-haves

## Parallel Review Guidelines

### When to Split
| Context Size | Tasks | Strategy |
|--------------|-------|----------|
| SMALL (<3,000) | Any | Sequential |
| MEDIUM (3,000-6,000) | 1-2 | Sequential |
| MEDIUM | 3+ | Consider splitting |
| LARGE (>6,000) | Any | MUST split |

### Consolidation
After parallel reviews:
1. Collect all verdicts
2. ANY FAIL = Overall CHANGES REQUIRED
3. ALL PASS = Overall APPROVED
4. Combine issues into single feedback
