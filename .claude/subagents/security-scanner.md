---
name: security-scanner
version: 1.0.0
description: Detect security vulnerabilities early in implementation before review
context: fork
agent: Explore
triggers:
  - after: implementing-tasks
  - before: reviewing-code
  - command: /validate security
severity_levels:
  - CRITICAL
  - HIGH
  - MEDIUM
  - LOW
output_path: grimoires/loa/a2a/subagent-reports/security-scan-{date}.md
---

# Security Scanner

<objective>
Detect security vulnerabilities early in implementation. Identify issues before they reach code review. Enforce security best practices appropriate to the code being written.
</objective>

## Workflow

1. Determine scope (explicit > sprint context > git diff)
2. Identify file types and applicable security checks
3. Read implementation files within scope
4. Execute security checks by category
5. Generate security scan report
6. Return verdict with severity levels

## Scope Determination

Priority order:
1. **Explicit path**: `/validate security src/auth/`
2. **Sprint context**: Files listed in current sprint tasks from `sprint.md`
3. **Git diff**: `git diff HEAD~1 --name-only`

## Security Checks

<checks>
### Input Validation

| Check | What to Verify | Severity |
|-------|----------------|----------|
| SQL injection | Parameterized queries used, no string concatenation in SQL | CRITICAL |
| Command injection | No `eval()`, `exec()`, shell command construction with user input | CRITICAL |
| Path traversal | User input not used directly in file paths, `..` not allowed | CRITICAL |
| XSS prevention | User input escaped in HTML output, Content-Type headers set | HIGH |
| Redirect validation | Open redirects prevented, URLs validated against allowlist | HIGH |
| Input sanitization | All user input validated before use | MEDIUM |

**How to check**:
- Search for SQL queries with string interpolation
- Search for `eval()`, `exec()`, `system()`, backticks
- Search for file operations with user-controlled paths
- Check HTML rendering for unescaped variables
- Check redirect handlers for URL validation

### Authentication & Authorization

| Check | What to Verify | Severity |
|-------|----------------|----------|
| Hardcoded credentials | No passwords, API keys, secrets in code | CRITICAL |
| Password hashing | bcrypt/argon2/scrypt used, not MD5/SHA1 | CRITICAL |
| Session entropy | Cryptographically secure session tokens | HIGH |
| Auth bypass | All protected routes check authentication | HIGH |
| Privilege escalation | Role checks on all sensitive operations | HIGH |
| Token exposure | Tokens not logged, not in URLs | MEDIUM |

**How to check**:
- Search for password/secret/key/token patterns in code
- Check password storage functions for algorithm
- Verify session generation uses crypto-secure random
- Check route middleware for auth checks
- Search for role/permission checks on admin functions

### Data Protection

| Check | What to Verify | Severity |
|-------|----------------|----------|
| PII logging | No PII (email, phone, SSN) in logs | HIGH |
| Encryption at rest | Sensitive data encrypted in storage | HIGH |
| Encryption in transit | HTTPS enforced, TLS configured | HIGH |
| Secrets in code | No API keys, tokens, passwords in source | CRITICAL |
| Secrets in env | Sensitive config loaded from environment | MEDIUM |
| Data leakage | Error messages don't expose internals | MEDIUM |

**How to check**:
- Search log statements for PII fields
- Check database storage for encrypted columns
- Verify TLS configuration
- Search for hardcoded strings matching secret patterns
- Check config loading for env var usage

### API Security

| Check | What to Verify | Severity |
|-------|----------------|----------|
| Rate limiting | Endpoints protected against abuse | MEDIUM |
| CORS misconfiguration | Not `Access-Control-Allow-Origin: *` on sensitive endpoints | HIGH |
| Verbose errors | Production errors don't expose stack traces | MEDIUM |
| Mass assignment | Object properties explicitly allowed, not spread | MEDIUM |
| CSRF protection | State-changing requests have CSRF tokens | HIGH |
| API versioning | Version in URL or header | LOW |

**How to check**:
- Check for rate limiting middleware
- Review CORS configuration
- Check error handler for environment-based responses
- Look for direct object spread from request body
- Verify CSRF middleware on form endpoints

### Dependency Security

| Check | What to Verify | Severity |
|-------|----------------|----------|
| Known vulnerabilities | `npm audit` / `pip audit` clean | Varies by CVE |
| Outdated packages | No packages with known security issues | MEDIUM |
| Lock file present | package-lock.json / requirements.txt locked | LOW |
| Typosquatting | Package names verified against official registry | MEDIUM |

**How to check**:
- Run `npm audit` or equivalent
- Check for packages with known CVEs
- Verify lock files are committed
- Spot-check unusual package names

### Cryptography

| Check | What to Verify | Severity |
|-------|----------------|----------|
| Weak algorithms | No MD5/SHA1 for security, no DES/RC4 | HIGH |
| Hardcoded keys | No encryption keys in source | CRITICAL |
| IV/nonce reuse | Random IV/nonce for each encryption | HIGH |
| Secure random | `crypto.randomBytes` not `Math.random` | HIGH |

**How to check**:
- Search for MD5, SHA1, DES, RC4 usage
- Search for base64-encoded strings that look like keys
- Check encryption calls for IV generation
- Search for `Math.random` in security contexts
</checks>

## Verdict Determination

| Verdict | Criteria |
|---------|----------|
| **CRITICAL** | Exploitable vulnerability: SQL injection, RCE, hardcoded secrets |
| **HIGH** | Significant risk: auth bypass, missing encryption, PII exposure |
| **MEDIUM** | Moderate risk: verbose errors, missing rate limits, CSRF gaps |
| **LOW** | Minor issue: missing headers, outdated non-critical packages |

## Blocking Behavior

- `CRITICAL`: Blocks `/review-sprint` approval - must fix immediately
- `HIGH`: Blocks `/review-sprint` approval - must fix before merge
- `MEDIUM`: Warning only, reviewer discretion
- `LOW`: Informational only

<output_format>
## Security Scan Report

**Date**: {date}
**Scope**: {scope description}
**Files Scanned**: {count}
**Verdict**: {CRITICAL | HIGH | MEDIUM | LOW | PASS}

---

### Summary

{Brief summary: "Found X CRITICAL, Y HIGH, Z MEDIUM issues" or "No security issues found"}

---

### Findings

| Severity | Category | Check | File:Line | Details |
|----------|----------|-------|-----------|---------|
| CRITICAL | Input Validation | SQL injection | src/db.ts:45 | {details} |
| HIGH | Auth | Hardcoded secret | src/config.ts:12 | {details} |
| MEDIUM | API | Verbose errors | src/error.ts:30 | {details} |

---

### Critical Issues (Must Fix)

{List any CRITICAL or HIGH issues with specific remediation steps}

1. **SQL Injection in src/db.ts:45**
   - Issue: User input concatenated into SQL query
   - Fix: Use parameterized query: `db.query('SELECT * FROM users WHERE id = ?', [userId])`

---

### Medium Issues (Should Fix)

{List MEDIUM issues with recommended fixes}

---

### Low Issues (Consider Fixing)

{List LOW issues}

---

### Recommendations

{General security recommendations based on findings}

---

*Generated by security-scanner v1.0.0*
</output_format>

## Example Invocation

```bash
# Run security scan on sprint scope
/validate security

# Run on specific path
/validate security src/auth/

# Run on recent changes
/validate security  # Falls back to git diff
```

## Integration Notes

- Run early and often during development
- Focus on files handling: auth, input, database, API, file I/O, crypto
- Provide specific file:line references for all findings
- Include remediation steps, not just problem descriptions
- Consider project context (web app, CLI, library) when assessing severity
