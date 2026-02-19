# PRD: Security Hardening — Bridgebuilder Cross-Repository Findings

> Cycle: cycle-028 | Author: janitooor + Claude
> Source: [#374](https://github.com/0xHoneyJar/loa/issues/374)
> Priority: P1 (security — addresses concrete vulnerabilities in framework infrastructure)
> Classification: Hardening cycle — no new features, only fixes to existing code
> Flatline: Reviewed (3 HIGH_CONSENSUS integrated, 6 BLOCKERS addressed)

## 1. Problem Statement

A downstream Bridgebuilder review targeting Loa framework code surfaced 7 security findings across test fixtures, credential infrastructure, eval harness, audit logging, session continuity, and PII redaction. These range from critical (committed key material) to medium (false-positive regex, missing test coverage).

While none of these findings represent active exploitation vectors in production, they represent defense-in-depth gaps in framework infrastructure that could:
- Train bad habits (committed private keys)
- Leak credentials outside normal API call paths (health check HTTP requests)
- Enable supply-chain compromise of eval environments (unsigned binary downloads)
- Cause silent data loss in forensic audit trails (size tracking drift)
- Allow privilege escalation through state file tampering (unverified auto-resume)
- Miss auth vulnerabilities in eval fixtures (untested refreshToken)
- Generate false-positive redactions in legitimate content (overly broad regex)

> Sources: #374 (Bridgebuilder cross-repository review findings)

## 2. Goals & Success Metrics

### Goals

1. **Eliminate all committed key material** from the repository, prevent future occurrences via `.gitignore` patterns, add pre-commit/CI secret scanning as a preventive gate, and document git history remediation guidance.
2. **Harden credential health checks** to avoid sending plaintext API keys through non-standard code paths, with explicit log/exception redaction guarantees.
3. **Add integrity verification** for all binary downloads in the eval harness.
4. **Fix audit logger crash recovery** to maintain exact byte-accurate size tracking.
5. **Add integrity verification** to run mode state file auto-resume with explicit threat model, keyed HMAC (not plain checksum), and file permission hardening.
6. **Complete test coverage** for auth eval fixture to cover the imported-but-untested `refreshToken` function.
7. **Tighten PII redaction regex** for `aws_secret` to reduce false positives while maintaining detection of actual AWS secret access keys.

### Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Findings addressed | 7/7 | All findings from #374 resolved |
| Secret scanner clean | 0 alerts | `gitleaks detect` and GitHub secret scanning produce zero alerts |
| CI secret scanning gate | Configured | `gitleaks` runs in CI or pre-commit hook on every push |
| Test regressions | 0 | All existing tests continue to pass |
| New test coverage | 100% of changes | Every code change accompanied by test |
| False-positive reduction (aws_secret) | >90% reduction | Measured against corpus of SHA-1 hashes, JWT fragments, base64 config values |

## 3. User & Stakeholder Context

### Primary Persona: Loa Framework Maintainer

The framework maintainer needs all security findings addressed without breaking existing functionality. Each fix must be independently verifiable and testable.

### Secondary Persona: Loa Developer

Developers relying on PII redaction, audit logging, and credential health checks need these tools to work correctly — no false positives in redaction, no silent data loss in audit trails, no credential leakage through diagnostic code paths.

### Tertiary Persona: Downstream Evaluator

Users running the eval harness need confidence that the sandbox image has not been tampered with via supply-chain attacks on unsigned binary downloads.

## 4. Functional Requirements

### FR-1: Remove Mock Private Key + Add `.gitignore` Patterns (Critical — Finding 1)

**File**: `tests/fixtures/mock_private_key.pem`

Remove the 2048-bit RSA private key from the repository. Replace with a generated-at-test-time approach or a clearly-marked, zero-entropy placeholder.

- Delete `tests/fixtures/mock_private_key.pem` from the repository
- Add `*.pem` and `*.key` patterns to `.gitignore` (targeted to `tests/fixtures/` path to avoid hiding legitimate key files elsewhere)
- Update any tests that reference this fixture to generate ephemeral keys at test time
- Verify `gitleaks detect` produces zero alerts after removal
- **Git history remediation** (Flatline IMP-001): Document whether `git filter-repo` / BFG history rewrite is required. Since this is a mock key (zero entropy, no real secret), document that history rewrite is not required but the key should be added to the `.gitleaksignore` allowlist for the historical commit. If the key were real, a coordinated force-push with downstream notification would be mandatory.
- **Preventive control** (Flatline IMP-003): Add `gitleaks` as a CI gate in the GitHub Actions workflow or as a pre-commit hook configuration. This prevents future secret commits at the source rather than relying on `.gitignore` (which only hides files, doesn't prevent explicit `git add -f`).

### FR-2: Harden Credential Health Checks (High — Finding 2)

**File**: `.claude/adapters/loa_cheval/credentials/health.py`

The `check_credential()` function (lines 56-105) sends real HTTP requests with plaintext API key values to provider endpoints. While the intent is lightweight validation, the key travels through `urllib.request` where it is visible to:
- Network proxy logs
- Corporate TLS inspection
- Python-level request interceptors

Harden by:
- Adding a `--dry-run` / `dry_run` mode that validates key format only (prefix, length, character set) without making HTTP requests
- Making dry-run the default; opt-in to live checks via explicit `--live` flag or `live=True` parameter
- Adding format validation rules per provider (sourced from official docs, versioned):
  - OpenAI: `sk-` prefix, 48+ chars
  - Anthropic: `sk-ant-` prefix, 93+ chars
  - Moonshot: return explicit `"unknown/weak_validation"` status (no stable format spec exists — Flatline SKP-002)
- Logging a warning when live mode is used
- **Log redaction guarantees** (Flatline SKP-003): When live mode is used, ensure API keys NEVER appear in logs, stack traces, or exception dumps. Disable `urllib` debug output. Wrap HTTP calls to redact `Authorization`/`x-api-key` headers from any error messages. Add tests that assert log output does not contain key material after both successful and failed health checks.

### FR-3: Add SHA256 Verification for yq Binary Download (High — Finding 3)

**File**: `evals/harness/Dockerfile.sandbox` (lines 29-39)

The yq binary is downloaded via `curl` without any integrity check. The base image is already digest-pinned (good), but the yq binary is not.

- Add SHA256 checksums for both amd64 and arm64 binaries of yq v4.40.5
- Verify checksum after download, fail build on mismatch
- Document checksum source and refresh procedure in a comment

### FR-4: Fix Audit Logger Crash Recovery Size Tracking (High — Finding 4)

**File**: `.claude/lib/security/audit-logger.ts` (lines 274-326)

The `recoverFromCrash()` method reconstructs `currentSize` by summing `line.length + 1` for each valid line. This can drift from actual file size because:
- `doAppend()` may use a different serialization (e.g., Buffer byte length vs. string character length for multi-byte UTF-8)
- The `+1` for newline assumes single-byte `\n` but doesn't account for potential `\r\n` on Windows or multi-byte characters

**Log file format invariants** (Flatline SKP-005): The audit log format is defined as UTF-8 encoded, newline-delimited JSON (`\n` only, no `\r\n`). Each line is a complete JSON object. These invariants must be enforced by both `doAppend()` and `recoverFromCrash()`.

Fix by:
- Using `fs.statSync()` to get the actual file size after rewriting valid lines (most accurate approach — avoids all encoding/newline ambiguity)
- Alternatively, using `Buffer.byteLength(line, 'utf-8') + 1` instead of `line.length + 1` for byte-accurate tracking
- Recovery must run with exclusive file access (use `fs.openSync()` with appropriate flags) to prevent concurrent append during recovery
- Adding tests for: ASCII-only content, multi-byte UTF-8 characters, partial last line, and size accuracy after recovery
- Adding a test that verifies `currentSize` matches `fs.statSync().size` after recovery

### FR-5: Add Integrity Check to Session Continuity Auto-Resume (Medium — Finding 5)

**File**: `.claude/protocols/session-continuity.md` (lines 98-116)

The run mode state check reads `.run/sprint-plan-state.json` and auto-resumes autonomous execution if `state == "RUNNING"`. Any process that can write to this file can trigger autonomous mode without user consent.

**Threat model** (Flatline IMP-002, SKP-006): The threat is an untrusted local process writing a crafted state file to trigger autonomous execution. A plain sha256 checksum provides NO tamper resistance because the attacker can recompute it. Therefore:

Harden by:
- Adding an HMAC-SHA256 field to the state file, keyed with a per-session secret stored in a permissions-restricted file (`~/.claude/.run-hmac-key`, mode 0600) created when `/run` initializes
- The HMAC key is generated from `openssl rand -hex 32` at `/run` init time and is NOT stored inside the workspace `.run/` directory (which is writable by any workspace process)
- Verifying the HMAC before auto-resuming; if verification fails, fall through to interactive recovery instead of auto-resume
- **File permission hardening** (Flatline SKP-007): Verify `.run/sprint-plan-state.json` ownership matches current user, mode is 0600, and path does not traverse symlinks (use `O_NOFOLLOW` or `realpath` comparison)
- Document the integrity check in the protocol (session-continuity.md update describes behavior, but enforcement is in runtime code per NFR-4)

### FR-6: Add refreshToken Test Coverage to Auth Eval Fixture (Medium — Finding 6)

**File**: `evals/fixtures/buggy-auth-ts/tests/auth.test.ts`

The test file imports `refreshToken` on line 1 but has zero test coverage for it. Only `register`, `login`, and `validateToken` are tested. This is an eval fixture (intentionally buggy code for eval testing), but the missing coverage is itself a gap the eval should surface.

- Add a `describe('refreshToken', ...)` block with tests for:
  - Token refresh after valid login
  - Refresh with expired token
  - Refresh with invalid token
  - TOCTOU race condition (concurrent refresh attempts)
- Ensure the tests align with the eval fixture's intentional bug patterns

### FR-7: Tighten `aws_secret` Regex Pattern (Medium — Finding 7)

**File**: `.claude/lib/security/pii-redactor.ts` (lines 67-70)

The current pattern `/\b[A-Za-z0-9/+=]{40}\b/g` matches any 40-character base64 string. This produces false positives on:
- SHA-1 hex hashes (40 chars, `[0-9a-f]`)
- SHA-256 hex hash substrings
- JWT token segments
- Random configuration values
- Git commit hashes

Tighten by:
- Requiring the pattern to appear in proximity to an AWS context indicator (e.g., preceded by `aws_secret`, `AWS_SECRET_ACCESS_KEY`, or an `AKIA`-prefixed key ID within 5 lines)
- Or restricting the character set more specifically: AWS secret keys always contain at least one `/` or `+` character (base64 encoding of binary data)
- Adding an allowlist for known non-secret 40-char patterns (hex-only strings are never AWS secrets)
- Adding tests with known false-positive examples to verify reduced false-positive rate

## 5. Non-Functional Requirements

### NFR-1: No Breaking Changes

All existing tests must continue to pass. Credential health check defaults change (dry-run by default), but existing callers can opt-in to live mode.

### NFR-2: Backward Compatibility

- Existing credential health check callers get format-only validation by default (safer)
- Existing PII redaction behavior must not lose detection of real AWS secrets
- Audit logger recovery must produce identical behavior for ASCII-only log files

### NFR-3: Test Coverage

Every code change must include corresponding test coverage. No untested fixes.

### NFR-4: No System Zone Edits

FR-5 (session-continuity.md) is in `.claude/protocols/` — a System Zone file. The fix must be implemented as a runtime check in the script that reads the state file, not as a direct edit to the protocol document. The protocol document update documents the new behavior but the enforcement is in code.

## 6. Scope & Prioritization

### In Scope (This Cycle)

- All 7 findings from #374
- Associated test coverage
- `.gitignore` hardening for key material

### Out of Scope

- Rotating any actual API keys (that's an operational task, not a code change)
- Replacing the eval sandbox container runtime
- Refactoring the entire PII redactor
- Adding new credential providers to health.py
- General audit logger performance optimization (only fixing the size tracking bug)

## 7. Risks & Dependencies

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Tightened aws_secret regex misses real secrets | Low | High | Test against corpus of known AWS secrets; keep Shannon entropy detector as backup |
| Credential format validation rejects valid keys | Low | Medium | Research actual format specs; allow live-check escape hatch |
| Mock key removal breaks tests | Low | Low | Generate ephemeral keys in test setup |
| HMAC key lifecycle adds complexity | Medium | Low | Per-session key in `~/.claude/.run-hmac-key` (mode 0600); no rotation needed since key is ephemeral per `/run` session |
| Dockerfile checksum becomes stale when yq updates | Medium | Low | Document refresh procedure in Dockerfile comment |

### Dependencies

- `tests/fixtures/mock_private_key.pem` usage must be traced before deletion
- `.claude/lib/security/audit-logger.ts` `doAppend()` method must be understood to ensure size tracking alignment
- AWS secret key format documentation for regex tightening
- yq v4.40.5 release checksums from GitHub releases page
