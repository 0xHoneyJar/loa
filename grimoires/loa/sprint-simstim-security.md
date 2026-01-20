# Sprint Plan: Simstim Security Remediation

**Document Version**: 1.0.0
**Status**: APPROVED
**Created**: 2026-01-20
**Source**: `grimoires/loa/a2a/audits/2026-01-20-simstim/SECURITY-AUDIT-REPORT.md`

## Overview

This sprint plan addresses the 9 security findings identified in the Simstim codebase audit dated 2026-01-20. Findings are organized into 3 sprints by severity level to ensure critical vulnerabilities are remediated first.

### Finding Summary

| ID | Severity | Title | Sprint |
|----|----------|-------|--------|
| SIMSTIM-001 | CRITICAL | Bot Token Exposure in Error Messages | 1 |
| SIMSTIM-002 | CRITICAL | Command Injection via `/start_phase` | 1 |
| SIMSTIM-003 | HIGH | Weak Authorization - Empty User List Allows All | 2 |
| SIMSTIM-004 | HIGH | ReDoS Vulnerability in Regex Patterns | 2 |
| SIMSTIM-005 | HIGH | Callback Data Injection | 2 |
| SIMSTIM-006 | MEDIUM | Rate Limiter Timing Attack | 3 |
| SIMSTIM-007 | MEDIUM | Incomplete Sensitive Data Redaction | 3 |
| SIMSTIM-008 | MEDIUM | Audit Log Tampering via Race Condition | 3 |
| SIMSTIM-009 | MEDIUM | Unsafe Environment Variable Expansion | 3 |

---

## Sprint 1: Critical Security Fixes

**Global ID**: 13
**Priority**: P0 (Critical)
**Focus**: Eliminate vulnerabilities that could lead to immediate compromise

### Task 1.1: Fix Bot Token Exposure (SIMSTIM-001)

**Finding**: Bot token appears in exception traces and log messages
**CWE**: CWE-532 (Insertion of Sensitive Information into Log File)
**CVSS**: 9.1 (Critical)

**Remediation**:
1. Create `SafeConfig` wrapper class that masks token on `__repr__`/`__str__`
2. Implement custom exception handler that redacts token before logging
3. Add token validation that fails fast without exposing value
4. Update all error messages to use `[REDACTED]` placeholder

**Files to Modify**:
- `src/simstim/config.py` - Add SafeConfig wrapper
- `src/simstim/telegram/bot.py` - Update exception handling
- `src/simstim/cli.py` - Mask token in error output

**Acceptance Criteria**:
- [ ] No bot token appears in any log output
- [ ] Exception traces show `[REDACTED]` instead of actual token
- [ ] Unit test validates token is never logged

### Task 1.2: Fix Command Injection (SIMSTIM-002)

**Finding**: `/start_phase` command passes user input to shell without sanitization
**CWE**: CWE-78 (Improper Neutralization of Special Elements in OS Command)
**CVSS**: 9.8 (Critical)

**Remediation**:
1. Implement allowlist validation for phase names
2. Use `shlex.quote()` for any values passed to shell
3. Replace shell execution with direct Python subprocess
4. Add input validation layer before command construction

**Files to Modify**:
- `src/simstim/telegram/handlers.py` - Add allowlist validation
- `src/simstim/bridge/loa_monitor.py` - Use subprocess safely
- `src/simstim/validation.py` - NEW: Input validation module

**Acceptance Criteria**:
- [ ] Phase names validated against allowlist
- [ ] Shell metacharacters rejected with clear error
- [ ] Subprocess uses `shell=False` with explicit args
- [ ] Security test confirms injection blocked

### Task 1.3: Security Test Suite for Critical Fixes

**Deliverable**: Comprehensive tests for SIMSTIM-001 and SIMSTIM-002

**Tests to Create**:
- Token exposure test (assert token never in output)
- Injection fuzzing test (shell metacharacters)
- Allowlist bypass attempts

**Files to Create**:
- `tests/security/test_token_exposure.py`
- `tests/security/test_command_injection.py`

**Acceptance Criteria**:
- [ ] 100% coverage of remediation code
- [ ] Fuzzing tests for injection vectors
- [ ] CI runs security tests on every PR

---

## Sprint 2: High Priority Hardening

**Global ID**: 14
**Priority**: P1 (High)
**Focus**: Close authentication and input validation gaps

### Task 2.1: Fix Empty User List Authorization (SIMSTIM-003)

**Finding**: Empty `authorized_users` list allows any Telegram user
**CWE**: CWE-862 (Missing Authorization)
**CVSS**: 7.5 (High)

**Remediation**:
1. Require explicit `authorized_users` configuration (fail if empty)
2. Add startup validation that rejects empty user lists
3. Implement fail-closed default (deny if not explicitly authorized)
4. Add warning logs when authorization checks are performed

**Files to Modify**:
- `src/simstim/config.py` - Add empty list validation
- `src/simstim/security/authorization.py` - Fail-closed implementation
- `src/simstim/cli.py` - Startup validation

**Acceptance Criteria**:
- [ ] Bot refuses to start with empty authorized_users
- [ ] Clear error message explains required configuration
- [ ] Authorization is fail-closed by default

### Task 2.2: Fix ReDoS Vulnerability (SIMSTIM-004)

**Finding**: Catastrophic backtracking in permission detection regex
**CWE**: CWE-1333 (Inefficient Regular Expression Complexity)
**CVSS**: 7.5 (High)

**Remediation**:
1. Replace nested quantifiers with atomic groups or possessive quantifiers
2. Add regex timeout using `regex` library with `timeout` parameter
3. Implement input length limits before regex matching
4. Add performance test that detects slow patterns

**Files to Modify**:
- `src/simstim/bridge/stdout_parser.py` - Rewrite patterns
- `pyproject.toml` - Add `regex` dependency

**Acceptance Criteria**:
- [ ] Patterns match in O(n) time
- [ ] 5-second timeout prevents hang
- [ ] Performance test validates <100ms for 10KB input

### Task 2.3: Fix Callback Data Injection (SIMSTIM-005)

**Finding**: Callback data parsed without HMAC verification
**CWE**: CWE-345 (Insufficient Verification of Data Authenticity)
**CVSS**: 7.5 (High)

**Remediation**:
1. Implement HMAC signing for callback data
2. Include timestamp in signed payload (prevent replay)
3. Verify signature before parsing callback
4. Reject callbacks older than 5 minutes

**Files to Modify**:
- `src/simstim/telegram/callbacks.py` - Add HMAC signing/verification
- `src/simstim/security/crypto.py` - NEW: Cryptographic utilities

**Acceptance Criteria**:
- [ ] All callbacks are HMAC-signed
- [ ] Unsigned callbacks rejected
- [ ] Replay attacks blocked by timestamp

### Task 2.4: Security Tests for High Priority Fixes

**Deliverable**: Tests for SIMSTIM-003, SIMSTIM-004, SIMSTIM-005

**Files to Create**:
- `tests/security/test_authorization.py`
- `tests/security/test_redos.py`
- `tests/security/test_callbacks.py`

**Acceptance Criteria**:
- [ ] Authorization edge cases tested
- [ ] ReDoS patterns validated for performance
- [ ] Callback HMAC verified

---

## Sprint 3: Medium Priority Fixes

**Global ID**: 15
**Priority**: P2 (Medium)
**Focus**: Defense-in-depth improvements

### Task 3.1: Fix Rate Limiter Timing Attack (SIMSTIM-006)

**Finding**: Rate limiter response time reveals user existence
**CWE**: CWE-208 (Observable Timing Discrepancy)
**CVSS**: 5.3 (Medium)

**Remediation**:
1. Add constant-time comparison for user lookups
2. Implement random jitter in rate limit responses
3. Return same response for authorized and unauthorized users

**Files to Modify**:
- `src/simstim/security/rate_limiter.py` - Add constant-time checks

**Acceptance Criteria**:
- [ ] Timing variance <1ms between user states
- [ ] Response jitter implemented

### Task 3.2: Fix Incomplete Redaction (SIMSTIM-007)

**Finding**: Base64-encoded and URL-encoded secrets not redacted
**CWE**: CWE-319 (Cleartext Transmission of Sensitive Information)
**CVSS**: 5.3 (Medium)

**Remediation**:
1. Add base64 pattern detection
2. Add URL-encoded pattern detection
3. Implement entropy-based detection for high-entropy strings
4. Add configurable entropy threshold

**Files to Modify**:
- `src/simstim/security/redaction.py` - Enhanced patterns

**Acceptance Criteria**:
- [ ] Base64-encoded secrets redacted
- [ ] URL-encoded secrets redacted
- [ ] High-entropy strings flagged

### Task 3.3: Fix Audit Log Race Condition (SIMSTIM-008)

**Finding**: Concurrent writes can corrupt or lose audit entries
**CWE**: CWE-362 (Concurrent Execution using Shared Resource)
**CVSS**: 5.3 (Medium)

**Remediation**:
1. Implement file locking with `fcntl` or `filelock`
2. Use atomic write pattern (write to temp, rename)
3. Add write queue with background flush
4. Implement log integrity verification (checksums)

**Files to Modify**:
- `src/simstim/audit/logger.py` - Atomic writes with locking
- `pyproject.toml` - Add `filelock` dependency

**Acceptance Criteria**:
- [ ] Concurrent writes don't corrupt logs
- [ ] Atomic write pattern implemented
- [ ] Integrity verification available

### Task 3.4: Fix Unsafe Environment Variable Expansion (SIMSTIM-009)

**Finding**: Config files allow `${VAR}` expansion in all fields
**CWE**: CWE-15 (External Control of System or Configuration Setting)
**CVSS**: 4.3 (Medium)

**Remediation**:
1. Define allowlist of fields that support env var expansion
2. Reject `${...}` syntax in non-allowed fields
3. Add validation during config load
4. Document which fields support expansion

**Files to Modify**:
- `src/simstim/config.py` - Restrict env var expansion

**Acceptance Criteria**:
- [ ] Only allowed fields expand env vars
- [ ] Unexpected expansion rejected with error
- [ ] Documentation updated

### Task 3.5: Security Tests for Medium Priority Fixes

**Deliverable**: Tests for SIMSTIM-006 through SIMSTIM-009

**Files to Create**:
- `tests/security/test_timing.py`
- `tests/security/test_redaction.py`
- `tests/security/test_audit_integrity.py`
- `tests/security/test_config_injection.py`

**Acceptance Criteria**:
- [ ] Timing tests verify constant-time operations
- [ ] Redaction tests cover encoding variants
- [ ] Audit tests verify integrity under load
- [ ] Config tests verify expansion restrictions

---

## Dependencies

### New Dependencies

| Package | Version | Purpose | Sprint |
|---------|---------|---------|--------|
| `regex` | >=2024.0 | Timeout support for ReDoS fix | 2 |
| `filelock` | >=3.12 | Cross-platform file locking | 3 |

### Test Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `pytest-timeout` | >=2.2 | ReDoS test timeouts |
| `hypothesis` | >=6.0 | Fuzzing for injection tests |

---

## Success Criteria

### Sprint 1 Completion
- [ ] All CRITICAL findings remediated
- [ ] Security tests pass
- [ ] No token exposure in any code path
- [ ] Command injection blocked

### Sprint 2 Completion
- [ ] All HIGH findings remediated
- [ ] Authorization fail-closed
- [ ] ReDoS patterns fixed
- [ ] Callback HMAC implemented

### Sprint 3 Completion
- [ ] All MEDIUM findings remediated
- [ ] Defense-in-depth layers added
- [ ] Full security test coverage
- [ ] Updated SECURITY.md

### Final Validation
- [ ] Re-run security audit (clean report)
- [ ] Update CHANGELOG with security fixes
- [ ] Bump version to 0.1.1 (security patch)

---

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| Regression in functionality | Comprehensive test suite before remediation |
| Breaking API changes | Document any API changes in CHANGELOG |
| Incomplete fix | Re-audit after each sprint |
| Performance impact | Benchmark critical paths |

---

## Timeline

Sprints should be executed sequentially. Do not begin Sprint 2 until Sprint 1 is approved. Critical vulnerabilities must be fixed before any further feature development.

**Blocking**: PR #41 (Simstim v0.1.0) should NOT be merged until at minimum Sprint 1 is complete.
