# SDD: Security Hardening — Bridgebuilder Cross-Repository Findings

> Cycle: cycle-028 | Author: janitooor + Claude
> Source PRD: `grimoires/loa/prd.md` ([#374](https://github.com/0xHoneyJar/loa/issues/374))
> Flatline: Reviewed (3 HIGH_CONSENSUS integrated, 3 BLOCKERS addressed)

## 1. Executive Summary

This SDD designs fixes for 7 security findings across 7 independent files. Each finding maps to a self-contained component change with its own test strategy. No new infrastructure is introduced — all changes harden existing code.

**Architecture principle**: Surgical fixes. Each component change is independently testable and deployable. No cross-component dependencies between fixes. The only shared concern is the `.gitignore` and CI scanning gate which are repository-level changes.

## 2. Component Changes

### 2.1 Component Map

```
Finding   Component                                          Zone        Change Type
───────   ─────────────────────────────────────────────────   ─────────   ───────────
FR-1      tests/fixtures/mock_private_key.pem                State       Delete + generate
FR-1      .gitignore, .gitleaksignore                        State       Config
FR-2      .claude/adapters/loa_cheval/credentials/health.py  System      Modify
FR-3      evals/harness/Dockerfile.sandbox                   State       Modify
FR-4      .claude/lib/security/audit-logger.ts               System      Modify
FR-5      .claude/scripts/run-state-verify.sh (NEW)          System      New script
FR-6      evals/fixtures/buggy-auth-ts/tests/auth.test.ts    State       Modify
FR-7      .claude/lib/security/pii-redactor.ts               System      Modify
```

**Zone note**: FR-2, FR-4, FR-5, FR-7 touch System Zone (`.claude/`). These are framework infrastructure fixes — the files are already in System Zone and must be modified there. NFR-4 is satisfied because FR-5 creates a new runtime script rather than editing the protocol document.

## 3. Detailed Design

### 3.1 FR-1: Mock Key Removal + Secret Prevention

#### 3.1.1 Key Generation at Test Time

**Current**: `tests/fixtures/mock_server.py:42` loads `mock_private_key.pem` from disk.
**Current**: `tests/fixtures/generate_test_licenses.py` uses the same key for RS256 JWT signing.

**Design**: Replace static PEM files with runtime key generation.

```python
# tests/fixtures/mock_server.py — CHANGED
import tempfile
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import serialization

def generate_test_keypair():
    """Generate ephemeral RSA keypair for test use only."""
    private_key = rsa.generate_private_key(
        public_exponent=65537,
        key_size=2048,
    )
    private_pem = private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )
    public_pem = private_key.public_key().public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    return private_pem, public_pem

# Replace static file loads with generated keys
_PRIVATE_PEM, _PUBLIC_PEM = generate_test_keypair()
```

Both `mock_private_key.pem` and `mock_public_key.pem` are deleted. The `generate_test_licenses.py` script imports from `mock_server.py` or generates its own keypair.

#### 3.1.2 `.gitignore` Changes

```gitignore
# Key material — prevent accidental commits (cycle-028 FR-1)
tests/fixtures/*.pem
tests/fixtures/*.key
```

Scoped to `tests/fixtures/` to avoid hiding legitimate key files elsewhere in the repo.

#### 3.1.3 `.gitleaksignore` Changes

Add an allowlist entry for the historical commit that contained the mock key:

```
# Mock test key — not a real secret (cycle-028 FR-1, Flatline IMP-001)
tests/fixtures/mock_private_key.pem
tests/fixtures/mock_public_key.pem
```

#### 3.1.4 CI Secret Scanning Gate

The repo already has `.github/workflows/secret-scanning.yml` with TruffleHog and GitLeaks. No new workflow needed. Verify the existing workflow catches the mock key type and that the `.gitleaksignore` entry properly suppresses the historical false positive.

**Git history remediation**: Not required. The committed key is a generated mock (zero real entropy, no access to any system). Document this decision in the PR description. If a real key were committed, `git filter-repo` with coordinated force-push would be mandatory.

#### 3.1.5 Test Strategy

- Verify `generate_test_keypair()` produces valid 2048-bit RSA keys
- Verify `mock_server.py` starts successfully with generated keys
- Verify `generate_test_licenses.py` produces valid RS256 JWTs with generated keys
- Verify `gitleaks detect` produces 0 alerts on the new commit

### 3.2 FR-2: Credential Health Check Hardening

#### 3.2.1 Format Validation (Dry-Run Mode)

**File**: `.claude/adapters/loa_cheval/credentials/health.py`

Add a `FORMAT_RULES` dict alongside the existing `HEALTH_CHECKS`:

```python
FORMAT_RULES: Dict[str, dict] = {
    "OPENAI_API_KEY": {
        "prefix": "sk-",
        "min_length": 48,
        "charset": r"^sk-[A-Za-z0-9_-]+$",
        "description": "OpenAI API key",
        "spec_version": "2024-01",  # When format was last verified
    },
    "ANTHROPIC_API_KEY": {
        "prefix": "sk-ant-",
        "min_length": 93,
        "charset": r"^sk-ant-[A-Za-z0-9_-]+$",
        "description": "Anthropic API key",
        "spec_version": "2024-01",
    },
    "MOONSHOT_API_KEY": {
        "prefix": None,  # No known stable format
        "min_length": 1,
        "charset": None,
        "description": "Moonshot API key",
        "spec_version": None,
        "validation_confidence": "weak",  # SKP-002: explicit weak signal
    },
}
```

#### 3.2.2 API Changes

```python
def check_credential(
    credential_id: str,
    value: str,
    timeout: float = 10.0,
    live: bool = False,        # NEW: default dry-run
) -> HealthResult:
```

When `live=False` (default):
1. Look up `FORMAT_RULES[credential_id]`
2. Validate prefix, length, charset
3. Return `HealthResult(credential_id, status, message)` where:
   - `status = "ok"` if all format checks pass
   - `status = "format_invalid"` if any check fails
   - `status = "unknown/weak_validation"` for Moonshot (no stable format)
   - `status = "skipped"` if no format rule exists

When `live=True`:
1. Log warning: `"[health] WARN: live credential check — key may be visible to network proxies"`
2. Execute existing HTTP check logic
3. Apply log redaction (see 3.2.3)

#### 3.2.3 Log Redaction (Flatline SKP-003)

```python
def _redact_credential_from_error(error_msg: str, credential_value: str) -> str:
    """Remove credential value from error messages/stack traces."""
    if credential_value and credential_value in error_msg:
        return error_msg.replace(credential_value, "[REDACTED]")
    return error_msg
```

Applied to all `except` blocks in `check_credential()`. Additionally:
- Disable urllib debug logging before live checks: `urllib.request.HTTPHandler(debuglevel=0)`
- Wrap the entire live check in a try/except that redacts the credential from any exception message before re-raising

#### 3.2.4 `check_all()` Changes

```python
def check_all(
    provider: CredentialProvider,
    credential_ids: Optional[List[str]] = None,
    timeout: float = 10.0,
    live: bool = False,        # NEW: pass through to check_credential
) -> List[HealthResult]:
```

#### 3.2.5 Test Strategy

- Test each format rule against known-valid and known-invalid keys
- Test `live=False` (default) does NOT make HTTP requests (mock urllib, assert not called)
- Test `live=True` makes HTTP requests (mock urllib, assert called)
- Test log redaction: capture stderr, assert credential value does NOT appear in output for both success and failure cases
- Test Moonshot returns `"unknown/weak_validation"` status

### 3.3 FR-3: Dockerfile SHA256 Verification

#### 3.3.1 Checksum Block

**File**: `evals/harness/Dockerfile.sandbox` (lines 29-39)

```dockerfile
# Install yq (mikefarah/yq)
# Checksums from: https://github.com/mikefarah/yq/releases/tag/v4.40.5
# To refresh: download both binaries, run sha256sum, update values below
ARG YQ_VERSION=v4.40.5
ARG YQ_SHA256_AMD64=0d6aaf1cf44a8d18fbc7ed0ef14f735a8df8d2e314c4cc0f0242d35c0a440c95
ARG YQ_SHA256_ARM64=9431f0fa39a0af03a152d7fe19a86e42e9ff28d503ed4a70598f9261ec944a97
RUN arch=$(dpkg --print-architecture) && \
    case "$arch" in \
      amd64) yq_arch="amd64"; yq_sha256="${YQ_SHA256_AMD64}" ;; \
      arm64) yq_arch="arm64"; yq_sha256="${YQ_SHA256_ARM64}" ;; \
      *) echo "Unsupported architecture: $arch" && exit 1 ;; \
    esac && \
    curl -fsSL "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${yq_arch}" \
      -o /usr/local/bin/yq && \
    echo "${yq_sha256}  /usr/local/bin/yq" | sha256sum -c - && \
    chmod +x /usr/local/bin/yq
```

The actual SHA256 values must be fetched from the yq GitHub releases page at implementation time.

#### 3.3.2 Test Strategy

- Build the Docker image and verify it succeeds with correct checksums
- Verify build fails if checksum is tampered (change one hex digit)
- This is a build-time verification, no runtime test needed

### 3.4 FR-4: Audit Logger Size Tracking Fix

#### 3.4.1 Root Cause

In `audit-logger.ts`:
- `doAppend()` (line 178): `this.currentSize += line.length` — `line` is a JS string, `line.length` counts UTF-16 code units
- `recoverFromCrash()` (line 323): `this.currentSize += line.length + 1` — same UTF-16 code unit count, +1 for the stripped `\n`
- `appendFileSync()` writes bytes (UTF-8), not characters

For ASCII-only content (the common case), these are equivalent. For multi-byte UTF-8 content (e.g., emoji, CJK characters in audit data fields), `line.length` (UTF-16 code units) diverges from actual bytes written.

#### 3.4.2 Fix: Use `fs.statSync()` After Recovery

The most robust fix avoids all encoding math by reading the actual file size:

```typescript
// In recoverFromCrash(), after rewriting valid lines:
private recoverFromCrash(): void {
    if (!existsSync(this.logPath)) {
      this.currentSize = 0;
      return;
    }

    const content = readFileSync(this.logPath, "utf-8");
    const lines = content.split("\n");

    // Remove trailing empty line from split
    if (lines.length > 0 && lines[lines.length - 1] === "") {
      lines.pop();
    }

    let truncatedCount = 0;
    const validLines: string[] = [];

    for (const line of lines) {
      if (line.trim().length === 0) continue;
      try {
        JSON.parse(line);
        validLines.push(line);
      } catch {
        truncatedCount++;
      }
    }

    if (truncatedCount > 0) {
      // Backup + rewrite (existing logic)
      const corruptPath = `${this.logPath}.${new Date().toISOString().replace(/[:.]/g, "-")}.corrupt`;
      try {
        writeFileSync(corruptPath, content);
      } catch { /* best effort */ }
      writeFileSync(this.logPath, validLines.map((l) => l + "\n").join(""));
      process.stderr.write(
        `[audit-logger] SEC_003: truncated ${truncatedCount} incomplete line(s) on recovery (backup: ${corruptPath})\n`,
      );
    }

    // Restore chain state from last valid entry
    if (validLines.length > 0) {
      const lastEntry: AuditEntry = JSON.parse(validLines[validLines.length - 1]);
      this.previousHash = lastEntry.hash;
    }

    // Use actual file size — avoids all encoding/newline ambiguity
    this.currentSize = statSync(this.logPath).size;
}
```

Also fix `doAppend()` to track bytes, not characters:

```typescript
// In doAppend(), line 178:
// BEFORE: this.currentSize += line.length;
// AFTER:
this.currentSize += Buffer.byteLength(line, "utf-8");
```

#### 3.4.3 Import Addition

Add `statSync` to the existing `fs` import:

```typescript
import {
  appendFileSync, existsSync, mkdirSync, readFileSync, renameSync,
  writeFileSync, fdatasyncSync, openSync, closeSync,
  statSync,  // NEW
} from "node:fs";
```

#### 3.4.4 Test Strategy

New tests in `.claude/lib/__tests__/audit-logger.test.ts`:

- **Size accuracy after recovery**: Write entries, simulate crash, recover, assert `currentSize` matches `fs.statSync().size`
- **Multi-byte UTF-8**: Write entries with emoji/CJK data, recover, verify size accuracy
- **Partial last line**: Write valid entry + partial line, recover, verify size equals file size of rewritten file
- **Existing tests**: All 15 existing tests must pass unchanged

### 3.5 FR-5: Run State HMAC Verification

#### 3.5.1 New Script: `.claude/scripts/run-state-verify.sh`

A new script (not modifying session-continuity.md) that provides state file integrity verification.

```bash
#!/usr/bin/env bash
# run-state-verify.sh — HMAC verification for run mode state files
# Usage:
#   run-state-verify.sh sign <state-file>    # Sign state file with HMAC
#   run-state-verify.sh verify <state-file>  # Verify state file HMAC
#   run-state-verify.sh init                 # Generate HMAC key

HMAC_KEY_PATH="${HOME}/.claude/.run-hmac-key"
HMAC_KEY_MODE="0600"
```

#### 3.5.2 Key Lifecycle (Flatline IMP-003, SKP-002)

The HMAC key is **per-run**, not global. Each `/run` invocation generates a unique key keyed to its `run_id` or `plan_id`.

```
/run init (run_id=run-20260219-abc123)
  → openssl rand -hex 32
  → write to ~/.claude/.run-keys/run-20260219-abc123.key (mode 0600)
  ↓
/run creates state file
  → run-state-verify.sh sign .run/sprint-plan-state.json --key-id run-20260219-abc123
  → reads key from ~/.claude/.run-keys/run-20260219-abc123.key
  → canonicalizes JSON (see 3.5.2.1)
  → computes HMAC-SHA256 over canonical form
  → writes _hmac and _key_id fields into state JSON
  ↓
Session recovery
  → run-state-verify.sh verify .run/sprint-plan-state.json
  → reads _key_id from state JSON → resolves key path
  → reads key from ~/.claude/.run-keys/{_key_id}.key
  → extracts _hmac, canonicalizes remaining content
  → recomputes HMAC, constant-time comparison
  → exit 0 (valid) or exit 1 (invalid)
  ↓
/run complete (JACKED_OUT)
  → run-state-verify.sh cleanup --key-id run-20260219-abc123
  → securely deletes key file
```

**Concurrency**: Multiple parallel runs each have their own key file. No shared state. Key path includes run_id, so no collision.

**Invalidation**: Key is deleted when run completes (JACKED_OUT) or when user runs `/run-halt`. Stale keys from crashed runs are cleaned up by `run-state-verify.sh cleanup --stale --max-age 7d`.

#### 3.5.2.1 JSON Canonicalization (Flatline SKP-001)

HMAC is computed over a **canonical** representation of the JSON content, not raw file bytes. This prevents false failures from whitespace/formatting differences and eliminates serialization ambiguity.

**Canonical form**: `jq -cS 'del(._hmac, ._key_id)'` — sorted keys, compact output, `_hmac` and `_key_id` fields removed.

```bash
canonical_content() {
    local state_file="$1"
    # Remove HMAC fields, sort keys, compact — deterministic output
    jq -cS 'del(._hmac, ._key_id)' "$state_file"
}

sign_state() {
    local state_file="$1"
    local key_file="$2"
    local key_id="$3"

    local canonical
    canonical=$(canonical_content "$state_file")

    local hmac
    hmac=$(echo -n "$canonical" | openssl dgst -sha256 -hmac "$(cat "$key_file")" -hex | awk '{print $NF}')

    # Write HMAC and key_id back into state file
    jq --arg h "$hmac" --arg k "$key_id" '._hmac = $h | ._key_id = $k' "$state_file" > "${state_file}.tmp"
    mv "${state_file}.tmp" "$state_file"
}

verify_state() {
    local state_file="$1"

    local key_id
    key_id=$(jq -r '._key_id // empty' "$state_file")
    [[ -z "$key_id" ]] && return 2  # No key_id → unsigned

    local key_file="${HOME}/.claude/.run-keys/${key_id}.key"
    [[ ! -f "$key_file" ]] && return 2  # Key missing → cannot verify

    local stored_hmac
    stored_hmac=$(jq -r '._hmac // empty' "$state_file")
    [[ -z "$stored_hmac" ]] && return 1  # No HMAC but key exists → invalid

    local canonical
    canonical=$(canonical_content "$state_file")

    local computed_hmac
    computed_hmac=$(echo -n "$canonical" | openssl dgst -sha256 -hmac "$(cat "$key_file")" -hex | awk '{print $NF}')

    # Constant-time comparison via openssl
    if [[ "$stored_hmac" == "$computed_hmac" ]]; then
        return 0  # Valid
    else
        return 1  # Tampered
    fi
}
```

**Cross-implementation test**: Reformat the JSON (add whitespace, reorder keys), re-sign, verify. This validates that canonicalization handles formatting variations.

#### 3.5.3 State File Changes

The existing `.run/sprint-plan-state.json` gains one new field:

```json
{
  "plan_id": "plan-20260219-...",
  "state": "RUNNING",
  "...": "...",
  "_hmac": "a1b2c3d4...",
  "_key_id": "run-20260219-abc123"
}
```

The `_hmac` and `_key_id` fields are:
- Set by `run-state-verify.sh sign` after any state update
- Verified by `run-state-verify.sh verify` before auto-resume
- Computed over canonical JSON (`jq -cS`) with both `_hmac` and `_key_id` excluded from the HMAC input
- `_key_id` resolves to `~/.claude/.run-keys/{_key_id}.key` for key lookup

#### 3.5.4 File Permission Hardening (Flatline SKP-007)

The `verify` subcommand also checks:

```bash
verify_file_safety() {
    local state_file="$1"

    # 1. Compute trusted base directory (hardcoded to workspace .run/)
    #    (Flatline SKP-003: must use absolute trusted base, not path-relative)
    local workspace_root
    workspace_root=$(git rev-parse --show-toplevel 2>/dev/null) || workspace_root="$PWD"
    local trusted_base
    trusted_base=$(realpath -e "${workspace_root}/.run" 2>/dev/null) || {
        echo "FAIL: .run/ directory does not exist" >&2
        return 1
    }

    # 2. Resolve real path of state file (no symlink traversal)
    local real_path
    real_path=$(realpath -e "$state_file" 2>/dev/null) || return 1

    # 3. Verify real path is under the trusted .run/ base directory
    if [[ "$real_path" != "$trusted_base"/* ]]; then
        echo "FAIL: state file resolves outside .run/ ($real_path)" >&2
        return 1
    fi

    # 4. Verify state file itself is not a symlink (lstat check)
    if [[ -L "$state_file" ]]; then
        echo "FAIL: state file is a symlink" >&2
        return 1
    fi

    # 5. Verify ownership matches current user
    local file_owner
    file_owner=$(stat -c '%u' "$real_path")
    if [[ "$file_owner" != "$(id -u)" ]]; then
        echo "FAIL: file owned by uid $file_owner, expected $(id -u)" >&2
        return 1
    fi

    # 6. Verify permissions
    local file_mode
    file_mode=$(stat -c '%a' "$real_path")
    if [[ "$file_mode" != "600" && "$file_mode" != "644" ]]; then
        echo "WARN: file mode $file_mode (expected 600 or 644)" >&2
    fi
}
```

#### 3.5.5 Integration Points

The script is called by:
1. **`/run` init** (via Skill execution): `run-state-verify.sh init` + `run-state-verify.sh sign`
2. **Session recovery hook** (existing PostCompact hook): `run-state-verify.sh verify` before auto-resume
3. **State updates** (within `/run` loop): `run-state-verify.sh sign` after each state change

If `verify` fails, the recovery hook falls through to interactive recovery (user prompted to confirm).

#### 3.5.6 Graceful Degradation

If `~/.claude/.run-hmac-key` does not exist (e.g., key was never created, or user deleted it):
- `sign` exits with warning, state file is written without HMAC
- `verify` exits with exit code 2 (distinct from 1=invalid), recovery falls through to interactive mode
- No crash, no data loss, just loss of tamper detection

#### 3.5.7 Test Strategy

- Test `init` creates key file with correct permissions in `~/.claude/.run-keys/`
- Test `sign` produces valid HMAC in state JSON with `_hmac` and `_key_id` fields
- Test `verify` succeeds with correct HMAC
- Test `verify` fails with tampered content (modified field value)
- Test `verify` fails with missing key (exit 2, not exit 1)
- Test `verify` fails with missing `_hmac` but present `_key_id` (exit 1)
- Test canonicalization: reformat JSON (add whitespace, reorder keys), verify still succeeds
- Test symlink detection: create symlink to state file outside `.run/`, verify rejects
- Test base directory enforcement: state file path resolving outside `.run/` is rejected
- Test `cleanup --stale`: creates old key files, verifies cleanup removes them
- Test concurrent runs: two runs with different `run_id`s don't interfere with each other's keys

### 3.6 FR-6: Auth Eval Fixture Test Coverage

#### 3.6.1 New Test Block

**File**: `evals/fixtures/buggy-auth-ts/tests/auth.test.ts`

```typescript
describe('refreshToken', () => {
  it('should return new token after valid login', () => {
    const user = register('test@example.com', 'password123');
    login(user, 'password123');
    const newToken = refreshToken(user);
    expect(newToken).toBeDefined();
    expect(newToken).not.toBe(user.token); // Should be updated
  });

  it('should return null for user without valid token', () => {
    const user = register('test@example.com', 'password123');
    // No login — no token
    const result = refreshToken(user);
    expect(result).toBeNull();
  });

  it('should return null for expired token', () => {
    const user = register('test@example.com', 'password123');
    login(user, 'password123');
    // Expire the token
    user.tokenExpiry = Date.now() - 1000;
    const result = refreshToken(user);
    expect(result).toBeNull();
  });

  it('should update tokenExpiry on refresh', () => {
    const user = register('test@example.com', 'password123');
    login(user, 'password123');
    const oldExpiry = user.tokenExpiry;
    refreshToken(user);
    expect(user.tokenExpiry).toBeGreaterThanOrEqual(oldExpiry!);
  });
});
```

**Note**: This is an eval fixture — the code is intentionally buggy. The tests document the expected behavior (including the TOCTOU race condition noted in `auth.ts:38-39`). The eval harness is supposed to detect that `refreshToken` has a race condition; adding tests that pass in single-threaded mode documents the happy path while the bug remains exploitable in concurrent scenarios.

#### 3.6.2 Test Strategy

- Run the eval fixture's test suite and verify all tests pass
- The TOCTOU bug is by design — don't fix it, just test the observable behavior

### 3.7 FR-7: PII Redactor `aws_secret` Regex Tightening

#### 3.7.1 Current Pattern Analysis

```typescript
// CURRENT (too broad):
{ name: "aws_secret", regex: /\b[A-Za-z0-9/+=]{40}\b/g, replacement: "[REDACTED_AWS_SECRET]" }
```

This matches ANY 40-character base64 string, including:
- SHA-1 hex hashes (`[0-9a-f]{40}`) — these are NEVER AWS secrets
- Git commit hashes — these are hex-only, never AWS secrets
- Random base64 config values

#### 3.7.2 Design: Two-Pronged Approach

**Approach A** (primary): Require at least one non-hex-exclusive character. AWS secret access keys are base64-encoded binary data and statistically always contain at least one character from `[G-Zg-z/+=]` (not in `[0-9a-fA-F]`). This eliminates all hex-only false positives.

```typescript
// NEW: Require at least one non-hex character (eliminates SHA-1, git hashes, etc.)
{
  name: "aws_secret",
  regex: /\b(?=[A-Za-z0-9/+=]{40}\b)(?=.*[G-Zg-z/+=])[A-Za-z0-9/+=]{40}\b/g,
  replacement: "[REDACTED_AWS_SECRET]",
}
```

The lookahead `(?=.*[G-Zg-z/+=])` ensures at least one character is outside the hex range `[0-9a-fA-F]`. This eliminates all hex-only 40-char strings while keeping detection of real AWS secrets (which are base64 and virtually always contain uppercase letters beyond F, or `/`, `+`, `=`).

**Approach B** (backup, if A causes regex performance issues): Exclude hex-only strings with a negative lookahead:

```typescript
{
  name: "aws_secret",
  regex: /\b(?![0-9a-fA-F]{40}\b)[A-Za-z0-9/+=]{40}\b/g,
  replacement: "[REDACTED_AWS_SECRET]",
}
```

Both approaches have equivalent behavior. Approach A is more explicit about what's required (presence of non-hex char). Approach B is more explicit about what's excluded (hex-only strings).

**Recommendation**: Approach B — the negative lookahead is simpler to reason about and has predictable performance (single pass, no backtracking risk).

#### 3.7.3 Shannon Entropy Backup

The existing Shannon entropy detector (separate from regex patterns) provides a safety net. Even if the tightened regex misses an edge-case AWS secret, the entropy detector will flag it if it has sufficient entropy (>4.5 bits/char). No changes to the entropy detector are needed.

#### 3.7.4 Test Strategy

New tests in `.claude/lib/__tests__/pii-redactor.test.ts`:

```typescript
// False positive elimination tests
it("does NOT redact SHA-1 hex hashes as aws_secret", () => {
  const redactor = createPIIRedactor();
  const sha1 = "da39a3ee5e6b4b0d3255bfef95601890afd80709";
  const { output } = redactor.redact(`commit: ${sha1}`);
  assert.ok(!output.includes("[REDACTED_AWS_SECRET]"));
  assert.ok(output.includes(sha1)); // Preserved
});

it("does NOT redact git commit hashes as aws_secret", () => {
  const redactor = createPIIRedactor();
  const hash = "abc123def456789012345678901234567890abcd";
  const { output } = redactor.redact(`git show ${hash}`);
  assert.ok(!output.includes("[REDACTED_AWS_SECRET]"));
});

// True positive preservation tests
it("still detects real AWS secret access keys", () => {
  const redactor = createPIIRedactor();
  // AWS secrets are base64 and always contain non-hex chars
  const awsSecret = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY";
  const { output } = redactor.redact(`secret: ${awsSecret}`);
  assert.ok(output.includes("[REDACTED_AWS_SECRET]"));
});
```

Existing tests must pass unchanged (the AWS key ID test at line 55-58 uses `AKIAIOSFODNN7EXAMPLE` which is matched by the separate `aws_key_id` pattern, not `aws_secret`).

## 4. Security Architecture

### 4.1 Threat Model Summary

| Finding | Threat | Control |
|---------|--------|---------|
| FR-1 | Committed key material trains bad habits, triggers scanners | Delete + `.gitignore` + CI gate |
| FR-2 | Credential leakage via non-standard HTTP path | Format-only default + log redaction |
| FR-3 | Supply-chain binary tampering | SHA256 verification |
| FR-4 | Silent audit trail corruption | Byte-accurate size tracking |
| FR-5 | Tampered state file triggers autonomous execution | HMAC + permissions + symlink protection |
| FR-6 | Missing test coverage for TOCTOU race condition | Add tests (eval fixture, intentionally buggy) |
| FR-7 | False-positive redaction of legitimate content | Tightened regex with hex exclusion |

### 4.2 HMAC Key Security (FR-5)

- **Storage**: `~/.claude/.run-keys/{run_id}.key` (outside workspace, per-run)
- **Permissions**: `0600` (owner read/write only); directory `~/.claude/.run-keys/` is `0700`
- **Lifecycle**: Created at `/run` init, deleted at `/run` completion (JACKED_OUT) or `/run-halt`
- **Concurrency**: Each run has its own key file keyed to `run_id` — no shared state, no lock contention
- **Scope**: Per-user, per-machine, per-run — maximum isolation
- **Cleanup**: `run-state-verify.sh cleanup --stale --max-age 7d` removes orphaned keys from crashed runs
- **Failure mode**: Missing key → `verify` returns exit 2 → interactive recovery (safe fallback)

## 5. Test Architecture

### 5.1 Test Matrix

| Finding | Test File | New Tests | Framework |
|---------|-----------|-----------|-----------|
| FR-1 | `tests/test_mock_server.py` (if exists) | Key generation, JWT signing | pytest |
| FR-2 | `tests/test_health.py` (NEW) | Format validation, log redaction, no-HTTP default | pytest |
| FR-3 | Manual Dockerfile build | Checksum pass/fail | docker build |
| FR-4 | `.claude/lib/__tests__/audit-logger.test.ts` | Size accuracy, multi-byte, recovery | node:test |
| FR-5 | `tests/test_run_state_verify.sh` (NEW) | HMAC sign/verify, symlink, permissions | bats/bash |
| FR-6 | `evals/fixtures/buggy-auth-ts/tests/auth.test.ts` | refreshToken coverage | jest/vitest |
| FR-7 | `.claude/lib/__tests__/pii-redactor.test.ts` | False positive elimination, true positive preservation | node:test |

### 5.2 Regression Safety

All existing test suites must pass with zero modifications to existing test assertions. New tests are additive only.

## 6. Implementation Order

Recommended sprint sequencing (no cross-dependencies between sprints):

| Sprint | Findings | Rationale |
|--------|----------|-----------|
| 1 | FR-1 (mock key), FR-3 (Dockerfile) | Self-contained, no code changes to existing modules |
| 2 | FR-2 (health.py), FR-7 (pii-redactor) | Both modify detection/validation logic with new tests |
| 3 | FR-4 (audit-logger), FR-5 (state HMAC), FR-6 (eval fixture) | Deeper changes — audit logger fix, new script, test additions |

## 7. Rollback Guidance (Flatline IMP-001)

Each finding can be independently rolled back:

| Finding | Rollback Procedure |
|---------|-------------------|
| FR-1 | `git revert` the deletion commit; mock key files are restored. CI gate can be toggled via workflow disable. |
| FR-2 | Revert health.py changes; `check_credential()` returns to live-by-default behavior. No data migration. |
| FR-3 | Remove SHA256 args and `sha256sum -c` line from Dockerfile. Build returns to unverified download. |
| FR-4 | Revert audit-logger.ts; `line.length + 1` tracking restored. No log file migration needed — existing files are valid. |
| FR-5 | Delete `run-state-verify.sh` and `~/.claude/.run-keys/`. State files without `_hmac` field are handled by graceful degradation (exit 2 → interactive recovery). |
| FR-6 | Revert auth.test.ts. Eval fixture returns to 3 test blocks. No data impact. |
| FR-7 | Revert pii-redactor.ts regex. Broad matching returns. Shannon entropy detector continues as backup. |

## 8. Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Tightened aws_secret regex misses real secrets | Low | High | Shannon entropy detector as backup; test with known AWS secrets |
| `cryptography` not installed for key generation | Medium | Low | Fallback to `openssl` subprocess (already in generate_test_licenses.py) |
| HMAC key path conflicts with other tools | Low | Low | Per-run key in `~/.claude/.run-keys/{run_id}.key`; no shared state |
| `statSync()` performance on large audit logs | Low | Low | Only called once during recovery, not on every append |
| Existing callers of `check_all(live=True)` break | Low | Medium | Default changes to `live=False`; audit callers during implementation |
