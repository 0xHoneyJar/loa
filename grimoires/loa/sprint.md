# Sprint Plan: Security Hardening — Bridgebuilder Cross-Repository Findings

> Cycle: cycle-028 | PRD: grimoires/loa/prd.md | SDD: grimoires/loa/sdd.md
> Source: [#374](https://github.com/0xHoneyJar/loa/issues/374)
> Sprints: 3 | Team: 1 developer (AI-assisted)
> Flatline: PRD reviewed (3 HIGH_CONSENSUS, 6 BLOCKERS addressed), SDD reviewed (3 HIGH_CONSENSUS, 3 BLOCKERS addressed)

## Overview

7 security findings from Bridgebuilder cross-repository review, grouped into 3 sprints by dependency and complexity. No cross-sprint dependencies — each sprint is independently shippable.

---

## Sprint 1: Key Material Removal + Binary Integrity (global sprint-19) ✅ REVIEW_APPROVED

**Goal**: Eliminate committed key material and add supply-chain integrity verification.

**Findings**: FR-1 (Critical), FR-3 (High)

### Task 1.1: Remove Mock Private Key and Generate Ephemeral Keys ✅

**File**: `tests/fixtures/mock_server.py`, `tests/fixtures/generate_test_licenses.py`

- [x] Implement `generate_test_keypair()` function using `cryptography` library
- [x] Update `mock_server.py` to use generated keys instead of loading from disk
- [x] Update `generate_test_licenses.py` to import from `mock_server.py` or generate its own keypair
- [x] Delete `tests/fixtures/mock_private_key.pem` and `tests/fixtures/mock_public_key.pem`
- [x] Add `tests/fixtures/*.pem` and `tests/fixtures/*.key` to `.gitignore`
- [x] Add allowlist entries to `.gitleaksignore` for historical commits
- [x] Verify existing `secret-scanning.yml` workflow covers this key type

**Acceptance Criteria**:
- `generate_test_keypair()` produces valid 2048-bit RSA keypair
- `mock_server.py` starts successfully with generated keys
- `generate_test_licenses.py` produces valid RS256 JWTs
- `gitleaks detect` produces 0 alerts on the new commit
- No `*.pem` or `*.key` files exist in `tests/fixtures/`
- All existing tests that referenced the mock key continue to pass
- Key rotation decision documented: mock key is zero-entropy (never real), history rewrite not required; `.gitleaksignore` scoped to exact commit/path with review note (Flatline IMP-002)

### Task 1.2: Add SHA256 Verification for yq Binary Download ✅

**File**: `evals/harness/Dockerfile.sandbox` (lines 29-39)

- [x] Add `YQ_SHA256_AMD64` and `YQ_SHA256_ARM64` build args with actual checksums from v4.40.5 release
- [x] Add `sha256sum -c` verification after `curl` download
- [x] Add architecture-switch logic (`dpkg --print-architecture`)
- [x] Add unsupported architecture fallback with `exit 1`
- [x] Document checksum source and refresh procedure in comment

**Acceptance Criteria**:
- Dockerfile builds successfully on amd64 with correct checksum
- Build fails if checksum is tampered (change one hex digit)
- Comment documents where checksums were sourced and how to refresh
- SHA256 values match: amd64=`0d6aaf1cf44a8d18fbc7ed0ef14f735a8df8d2e314c4cc0f0242d35c0a440c95`, arm64=`9431f0fa39a0af03a152d7fe19a86e42e9ff28d503ed4a70598f9261ec944a97`

---

## Sprint 2: Detection & Validation Hardening (global sprint-20) ✅ REVIEW_APPROVED

**Goal**: Harden credential health checks and reduce PII redaction false positives.

**Findings**: FR-2 (High), FR-7 (Medium)

### Task 2.1: Harden Credential Health Checks ✅

**File**: `.claude/adapters/loa_cheval/credentials/health.py`

- [x] Add `FORMAT_RULES` dict with per-provider validation (OpenAI: `sk-` prefix, 48+ chars; Anthropic: `sk-ant-` prefix, 93+ chars; Moonshot: `unknown/weak_validation`)
- [x] Add `live` parameter to `check_credential()` (default `False`)
- [x] Implement format-only validation path (dry-run mode)
- [x] Add `_redact_credential_from_error()` helper for log redaction
- [x] Wrap live HTTP checks with redaction for Authorization/x-api-key headers
- [x] Disable urllib debug output during live checks
- [x] Update `check_all()` to pass through `live` parameter
- [x] Create `tests/test_health.py` with comprehensive test suite

**Acceptance Criteria**:
- Default `check_credential()` (no `live` arg) does NOT make HTTP requests
- `live=True` makes HTTP requests with warning logged
- Moonshot returns explicit `"unknown/weak_validation"` status
- API key values NEVER appear in logs, stack traces, or exception dumps after both success and failure
- Centralized log capture test: run health checks with sentinel secret values and grep test output to confirm zero leakage (Flatline SKP-007)
- Format validation correctly accepts known-valid and rejects known-invalid keys per provider
- All existing callers work unchanged (backward compatible — just safer defaults)

### Task 2.2: Tighten `aws_secret` Regex Pattern ✅

**File**: `.claude/lib/security/pii-redactor.ts` (lines 67-70)

- [x] Replace broad regex with negative lookahead: `/\b(?![0-9a-fA-F]{40}\b)[A-Za-z0-9/+=]{40}\b/g`
- [x] Add false-positive tests: SHA-1 hex hashes, git commit hashes, hex-only strings
- [x] Add true-positive tests: known AWS secret access key format (e.g., `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY`)
- [x] Verify existing `aws_key_id` pattern (`AKIA...`) is unaffected
- [x] Verify Shannon entropy detector continues as backup

**Acceptance Criteria**:
- SHA-1 hex hashes (`[0-9a-f]{40}`) are NOT redacted as `aws_secret`
- Git commit hashes are NOT redacted as `aws_secret`
- Real AWS secret access keys (containing `/`, `+`, or uppercase letters > F) ARE still detected
- All existing pii-redactor tests pass unchanged
- No ReDoS regression (adversarial test still passes within time limit)

---

## Sprint 3: Audit Integrity + State Verification + Eval Coverage (global sprint-21) ✅ REVIEW_APPROVED

**Goal**: Fix audit logger crash recovery, add state file HMAC verification, and complete eval fixture test coverage.

**Findings**: FR-4 (High), FR-5 (Medium), FR-6 (Medium)

### Task 3.1: Fix Audit Logger Crash Recovery Size Tracking ✅

**File**: `.claude/lib/security/audit-logger.ts`

- [x] Add `statSync` to `node:fs` imports
- [x] In `recoverFromCrash()`: replace `currentSize += line.length + 1` accumulation with `statSync(this.logPath).size` after rewriting valid lines
- [x] In `doAppend()`: replace `this.currentSize += line.length` with `this.currentSize += Buffer.byteLength(line, "utf-8")`
- [x] Add test: size accuracy after recovery (assert `currentSize === statSync().size`)
- [x] Add test: multi-byte UTF-8 entries (emoji/CJK data) — verify size accuracy after recovery
- [x] Add test: partial last line recovery — verify size equals file size of rewritten file

**Acceptance Criteria**:
- After crash recovery, `currentSize` exactly matches `fs.statSync().size`
- Multi-byte UTF-8 entries (emoji, CJK) do not cause size drift
- Partial last line is correctly truncated during recovery
- All 15 existing audit-logger tests pass unchanged

### Task 3.2: Add HMAC Verification for Run State Files ✅

**Files**: `.claude/scripts/run-state-verify.sh` (NEW)

- [x] Create `run-state-verify.sh` with subcommands: `init`, `sign`, `verify`, `cleanup`
- [x] Implement per-run key generation in `~/.claude/.run-keys/{run_id}.key` (mode 0600)
- [x] Implement JSON canonicalization via `jq -cS 'del(._hmac, ._key_id)'`
- [x] Implement HMAC-SHA256 signing and verification
- [x] Implement `verify_file_safety()` with:
  - Hardcoded trusted base directory from `git rev-parse --show-toplevel`/.run
  - Symlink detection (`-L` check)
  - Ownership verification (current user uid)
  - Permission verification (0600/0644)
- [x] Implement graceful degradation: missing key → exit 2 (unsigned), tampered → exit 1
- [x] Implement `cleanup --stale --max-age 7d` for orphaned keys
- [x] Create `tests/test_run_state_verify.sh` (bats or plain bash tests)
  - Test sign + verify round-trip
  - Test tampered content detection
  - Test missing key handling (exit 2)
  - Test symlink detection
  - Test base directory enforcement
  - Test JSON canonicalization (reformat + verify still passes)
  - Test concurrent runs with different run_ids

**Acceptance Criteria**:
- `sign` adds `_hmac` and `_key_id` fields to state JSON
- `verify` returns exit 0 for valid, exit 1 for tampered, exit 2 for unsigned
- Symlink state files are rejected
- State files outside `.run/` are rejected
- Keys are per-run and isolated (no collision between concurrent runs)
- Missing key does not crash — falls through to interactive recovery
- Canonicalization handles whitespace/key-order variations

### Task 3.3: Add refreshToken Test Coverage to Auth Eval Fixture ✅

**File**: `evals/fixtures/buggy-auth-ts/tests/auth.test.ts`

- [x] Add `describe('refreshToken', ...)` block with 4 tests:
  - Token refresh after valid login
  - Refresh with no token (no login)
  - Refresh with expired token
  - Token expiry update on refresh
- [x] Ensure tests align with eval fixture's intentional bug patterns (TOCTOU race is by design)

**Acceptance Criteria**:
- `refreshToken` has test coverage for all documented paths
- All 4 new tests pass in single-threaded execution
- Existing 3 describe blocks (register, login, validateToken) pass unchanged
- Eval fixture's intentional bugs are NOT fixed — tests document observable behavior

---

## Risk Register

| Risk | Sprint | Mitigation |
|------|--------|------------|
| `cryptography` library not available | Sprint 1 | Fallback to `openssl` subprocess (already in generate_test_licenses.py) |
| Tightened aws_secret regex misses edge cases | Sprint 2 | Shannon entropy detector as backup; test with known AWS secrets |
| Existing callers of `check_all(live=True)` break | Sprint 2 | Default changes to safe mode; callers opt-in to live explicitly |
| `statSync()` edge case on empty file | Sprint 3 | Test with empty log file scenario |
| HMAC key path collision | Sprint 3 | Per-run key with run_id in filename — no collision possible |

## Dependencies

- No cross-sprint dependencies
- No external service dependencies
- All fixes are independently testable and deployable
- Sprint 1 → Sprint 2 → Sprint 3 is the recommended order but not required
