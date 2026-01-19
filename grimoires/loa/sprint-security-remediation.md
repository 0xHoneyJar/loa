# Security Remediation Sprint Plan

**Based on**: Security Audit Report (2026-01-19)
**Overall Risk Level**: MEDIUM → Target: LOW
**Scope**: Fix 3 CRITICAL, 8 HIGH, 5 MEDIUM issues

---

## Sprint Overview

| Sprint | Focus | Findings Addressed | Priority |
|--------|-------|-------------------|----------|
| Sprint 1 | Critical Fixes | CRITICAL-001, 002, 003 | P0 - Immediate |
| Sprint 2 | High Priority Hardening | HIGH-001 through HIGH-008 | P1 - Before Production |
| Sprint 3 | Medium & Test Coverage | MEDIUM-001 through 005, LOW-* | P2 - Next Quarter |

**Team**: 1 Developer (Claude Code agent)
**Sprint Duration**: Each sprint = atomic work unit

---

## Sprint 1: Critical Security Fixes

**Goal**: Eliminate all CRITICAL vulnerabilities
**Risk Reduction**: CRITICAL count from 3 → 0

### Task 1.1: Fix Unquoted Variable Expansion (CRITICAL-001)

**File**: `.claude/scripts/constructs-install.sh`
**Lines**: 378-440, 657-713

**Description**: Replace shell variable interpolation in Python heredocs with environment variable passing.

**Current Pattern** (Vulnerable):
```bash
python3 << PYEOF
with open('$tmp_file', 'r') as f:
    pack_dir = '$pack_dir'
PYEOF
```

**Fixed Pattern**:
```bash
export TMP_FILE="$tmp_file"
export PACK_DIR="$pack_dir"
python3 << 'PYEOF'
import os
tmp_file = os.environ['TMP_FILE']
pack_dir = os.environ['PACK_DIR']
PYEOF
```

**Acceptance Criteria**:
- [ ] All Python heredocs use `<< 'PYEOF'` (quoted) syntax
- [ ] Variables passed via environment, not interpolation
- [ ] No `$variable` expansion inside Python code blocks
- [ ] Script passes shellcheck with no warnings

**Estimated Effort**: 30 minutes
**Dependencies**: None

---

### Task 1.2: Secure Credential Storage (CRITICAL-002)

**File**: `.claude/scripts/constructs-install.sh`, `.claude/scripts/constructs-lib.sh`
**Lines**: 70-89 (constructs-install.sh)

**Description**: Add file permission enforcement and validation for credential storage.

**Implementation**:
1. Enforce 600 permissions on credential file creation
2. Validate permissions before reading
3. Add warning if file is world/group readable

**Code**:
```bash
secure_credentials_file() {
    local creds_file="${HOME}/.loa/credentials.json"
    
    # Create with secure permissions if needed
    if [[ ! -f "$creds_file" ]]; then
        mkdir -p "$(dirname "$creds_file")"
        touch "$creds_file"
        chmod 600 "$creds_file"
    fi
    
    # Validate permissions
    local perms
    perms=$(stat -c %a "$creds_file" 2>/dev/null || stat -f %Lp "$creds_file" 2>/dev/null)
    if [[ "$perms" != "600" ]]; then
        warn "Credential file has insecure permissions ($perms), fixing..."
        chmod 600 "$creds_file"
    fi
}
```

**Acceptance Criteria**:
- [ ] Credential file created with 600 permissions
- [ ] Permissions validated before reading
- [ ] Warning displayed if permissions incorrect
- [ ] Permissions auto-corrected on detection

**Estimated Effort**: 45 minutes
**Dependencies**: None

---

### Task 1.3: Sanitize Permission Audit Logs (CRITICAL-003)

**File**: `.claude/scripts/permission-audit.sh`
**Lines**: 60-65

**Description**: Add credential pattern redaction before logging tool input.

**Implementation**:
```bash
sanitize_sensitive_data() {
    local input="$1"
    echo "$input" | sed \
        -e 's/sk_[a-zA-Z0-9_-]\{20,\}/sk_REDACTED/g' \
        -e 's/ghp_[a-zA-Z0-9_-]\{36,\}/ghp_REDACTED/g' \
        -e 's/gho_[a-zA-Z0-9_-]\{36,\}/gho_REDACTED/g' \
        -e 's/Bearer [a-zA-Z0-9._-]\{20,\}/Bearer REDACTED/g' \
        -e 's/api[_-]\?key["\s:=]*[a-zA-Z0-9_-]\{16,\}/api_key: REDACTED/gi' \
        -e 's/password["\s:=]*[^"}\s]\{8,\}/password: REDACTED/gi' \
        -e 's/secret["\s:=]*[a-zA-Z0-9_-]\{16,\}/secret: REDACTED/gi'
}

# Before logging:
sanitized_input=$(sanitize_sensitive_data "$tool_input")
```

**Acceptance Criteria**:
- [ ] API keys (sk_*, ghp_*, gho_*) redacted
- [ ] Bearer tokens redacted
- [ ] Generic api_key/password/secret patterns redacted
- [ ] Test with sample sensitive input confirms redaction
- [ ] Original functionality preserved

**Estimated Effort**: 30 minutes
**Dependencies**: None

---

### Sprint 1 Verification

After completing all tasks:
1. Run shellcheck on modified scripts
2. Test constructs-install.sh with mock pack download
3. Verify credential file permissions enforcement
4. Verify log sanitization with test credentials

**Sprint 1 Success Criteria**:
- All 3 CRITICAL findings resolved
- No regressions in existing functionality
- Shellcheck clean on modified files

---

## Sprint 2: High Priority Hardening

**Goal**: Eliminate all HIGH vulnerabilities
**Risk Reduction**: HIGH count from 8 → 0

### Task 2.1: Path Traversal Validation (HIGH-001)

**Files**: `.claude/scripts/detect-drift.sh`, `.claude/scripts/constructs-install.sh`

**Description**: Add path validation function and apply to all file path operations.

**Implementation**:
```bash
# Add to common.sh or each script
validate_path_safe() {
    local base_dir="$1"
    local path="$2"
    local resolved
    
    # Resolve path (don't follow symlinks with -m)
    resolved=$(realpath -m "$base_dir/$path" 2>/dev/null) || {
        error "Invalid path: $path"
        return 1
    }
    
    # Ensure within base directory
    if [[ ! "$resolved" =~ ^"$base_dir" ]]; then
        error "Path traversal detected: $path resolves to $resolved"
        return 1
    fi
    
    echo "$resolved"
}
```

**Acceptance Criteria**:
- [ ] Path validation function implemented
- [ ] Applied to detect-drift.sh watch paths
- [ ] Applied to constructs-install.sh extraction paths
- [ ] Test with `../` paths confirms rejection

**Estimated Effort**: 45 minutes
**Dependencies**: None

---

### Task 2.2: jq/yq Argument Sanitization (HIGH-002, HIGH-006-008)

**Files**: `.claude/scripts/mcp-registry.sh`, multiple other scripts

**Description**: Quote all user-provided values in jq/yq filters.

**Pattern to fix**:
```bash
# Vulnerable
yq -e ".servers.${server}" "$REGISTRY"

# Fixed - use --arg for variable injection
yq -e --arg s "$server" '.servers[$s]' "$REGISTRY"
```

**Acceptance Criteria**:
- [ ] All jq/yq calls use --arg for user input
- [ ] No string interpolation in filter expressions
- [ ] Test with special characters (`.`, `|`, `[`) confirms safety

**Estimated Effort**: 1 hour
**Dependencies**: None

---

### Task 2.3: Symlink Attack Prevention (HIGH-003)

**File**: `.claude/scripts/constructs-install.sh`

**Description**: Validate symlink targets before operations.

**Implementation**:
```bash
safe_symlink() {
    local target="$1"
    local link_name="$2"
    local expected_base="$3"
    
    # If link exists, validate target
    if [[ -L "$link_name" ]]; then
        local existing_target
        existing_target=$(readlink -f "$link_name" 2>/dev/null)
        
        if [[ ! "$existing_target" =~ ^"$expected_base" ]]; then
            error "Symlink points outside expected directory: $existing_target"
            return 1
        fi
    fi
    
    # Create new symlink safely
    ln -sfn "$target" "$link_name"
}
```

**Acceptance Criteria**:
- [ ] Symlink targets validated before operations
- [ ] Cannot create links pointing outside project
- [ ] Existing malicious links detected and rejected

**Estimated Effort**: 30 minutes
**Dependencies**: Task 2.1 (path validation)

---

### Task 2.4: Python Extraction Path Validation (HIGH-005)

**File**: `.claude/scripts/constructs-install.sh`

**Description**: Add path validation in Python extraction script.

**Implementation**:
```python
import os

def safe_join(base, path):
    """Safely join paths, rejecting traversal attempts."""
    # Normalize the path
    normalized = os.path.normpath(path)
    
    # Reject absolute paths and parent traversal
    if normalized.startswith('/') or normalized.startswith('..'):
        raise ValueError(f"Path traversal attempt: {path}")
    
    full_path = os.path.join(base, normalized)
    real_base = os.path.realpath(base)
    real_full = os.path.realpath(full_path)
    
    # Verify result is under base
    if not real_full.startswith(real_base):
        raise ValueError(f"Path escapes base directory: {path}")
    
    return full_path
```

**Acceptance Criteria**:
- [ ] Path validation in Python extraction
- [ ] `../` paths rejected with error
- [ ] Absolute paths rejected
- [ ] Normal paths work correctly

**Estimated Effort**: 30 minutes
**Dependencies**: Task 1.1 (Python heredoc fix)

---

### Task 2.5: Content Signature Verification (HIGH-004)

**File**: `.claude/scripts/constructs-install.sh`, `.claude/scripts/anthropic-oracle.sh`

**Description**: Add content hash verification for registry downloads.

**Implementation**:
```bash
verify_content_hash() {
    local file="$1"
    local expected_hash="$2"
    
    if [[ -z "$expected_hash" ]]; then
        warn "No hash provided, skipping verification"
        return 0
    fi
    
    local actual_hash
    actual_hash=$(sha256sum "$file" | cut -d' ' -f1)
    
    if [[ "$actual_hash" != "$expected_hash" ]]; then
        error "Content hash mismatch: expected $expected_hash, got $actual_hash"
        return 1
    fi
    
    return 0
}
```

**Acceptance Criteria**:
- [ ] SHA256 verification for pack downloads
- [ ] Warning if no hash provided (graceful degradation)
- [ ] Error and abort on hash mismatch

**Estimated Effort**: 45 minutes
**Dependencies**: None

---

### Sprint 2 Verification

1. Run shellcheck on all modified scripts
2. Test path traversal rejection with crafted paths
3. Test jq injection prevention with special characters
4. Test symlink handling with malicious links
5. Test content verification with modified files

**Sprint 2 Success Criteria**:
- All 8 HIGH findings resolved
- No regressions in existing functionality
- Defense-in-depth layering verified

---

## Sprint 3: Medium Priority & Test Coverage

**Goal**: Resolve MEDIUM issues and improve test coverage
**Risk Reduction**: MEDIUM count from 5 → 0, Test coverage to 85%+

### Task 3.1: Trap Handlers for Temp Files (MEDIUM-001)

**Files**: All scripts using `mktemp`

**Description**: Add EXIT/INT/TERM traps for cleanup.

**Pattern**:
```bash
tmp_file=$(mktemp)
trap 'rm -f "$tmp_file"' EXIT INT TERM
```

**Acceptance Criteria**:
- [ ] All mktemp usage has corresponding trap
- [ ] Cleanup verified on normal exit
- [ ] Cleanup verified on interrupt (Ctrl+C)

**Estimated Effort**: 30 minutes

---

### Task 3.2: Input Validation Functions (MEDIUM-002)

**File**: Create `.claude/scripts/lib/validation.sh`

**Description**: Create reusable validation functions.

**Functions**:
- `validate_path()` - Path safety
- `validate_url()` - URL format
- `validate_identifier()` - Safe identifiers
- `sanitize_for_jq()` - jq-safe strings

**Estimated Effort**: 45 minutes

---

### Task 3.3: Regex Pattern Safety (MEDIUM-003)

**File**: `.claude/scripts/detect-drift.sh`

**Description**: Review and fix regex patterns for ReDoS safety.

**Estimated Effort**: 30 minutes

---

### Task 3.4: API Key Format Validation (MEDIUM-004)

**File**: `.claude/scripts/constructs-lib.sh`

**Description**: Add format validation for API keys.

**Pattern**:
```bash
validate_api_key() {
    local key="$1"
    # Loa API keys: sk_[a-zA-Z0-9]{32}
    if [[ ! "$key" =~ ^sk_[a-zA-Z0-9]{32}$ ]]; then
        error "Invalid API key format"
        return 1
    fi
    return 0
}
```

**Estimated Effort**: 15 minutes

---

### Task 3.5: JWT Claims Validation Tests (MEDIUM-005)

**Files**: `tests/unit/test_license_validator.bats`

**Description**: Add tests for JWT claim validation.

**Test Cases**:
- Issuer (`iss`) validation
- Audience (`aud`) validation
- Subject (`sub`) format validation
- Clock skew tolerance
- Key rotation scenarios

**Estimated Effort**: 1 hour

---

### Task 3.6: Low Priority Improvements (LOW-001 through LOW-004)

**Description**: Address remaining low-priority items.

- LOW-001: Add configurable registry URL
- LOW-002: Add return code checks to analytics.sh
- LOW-003: Add basic rate limiting
- LOW-004: Document test key usage, add .gitignore

**Estimated Effort**: 1 hour

---

## Summary

| Sprint | Tasks | Est. Effort | Findings Resolved |
|--------|-------|-------------|-------------------|
| Sprint 1 | 3 | 1.75 hours | 3 CRITICAL |
| Sprint 2 | 5 | 3.5 hours | 8 HIGH |
| Sprint 3 | 6 | 4 hours | 5 MEDIUM, 4 LOW |

**Total Estimated Effort**: ~9 hours
**Expected Outcome**: Security grade B+ → A

---

## Post-Remediation Verification

After all sprints complete:

1. **Re-run Security Audit**
   ```
   /audit
   ```

2. **Verify Compliance**
   - OWASP Top 10: PASS
   - CWE-78: PASS
   - CWE-22: PASS
   - SOC 2: PASS

3. **Update Documentation**
   - SECURITY.md with new security measures
   - CHANGELOG.md with security improvements

---

**Plan Created**: 2026-01-19
**Based on**: Security Audit Report 2026-01-19
**Target Completion**: After 3 sprints
