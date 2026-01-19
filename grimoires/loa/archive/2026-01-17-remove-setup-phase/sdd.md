# Software Design Document: Remove Setup Phase

**Version**: 1.0.0
**Status**: Draft
**Author**: Claude (Agent)
**Date**: 2026-01-17
**PRD Reference**: `grimoires/loa/remove-setup-phase-prd.md`
**Feature Branch**: `feature/remove-setup-phase`

---

## 1. Executive Summary

This SDD details the technical implementation for removing the `/setup` phase from Loa, transitioning from marker-file-based THJ detection to API-key-based detection using `LOA_CONSTRUCTS_API_KEY`.

### 1.1 Design Goals

| Goal | Description |
|------|-------------|
| **Simplification** | Remove setup ceremony, allow immediate workflow entry |
| **Single Detection Mechanism** | API key presence = THJ member |
| **Backward Compatibility** | Existing marker files ignored, not deleted |
| **Zero Network Dependency** | Check key presence only, not validity |

### 1.2 Architecture Impact

| Component | Impact |
|-----------|--------|
| Commands | 2 deleted, 11 modified (pre-flight removal) |
| Scripts | 4 modified (detection logic) |
| Documentation | 4 files updated |
| Configuration | `.gitignore` cleanup |

---

## 2. System Architecture

### 2.1 Current Architecture (Before)

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   /setup    │────▶│.loa-setup-complete│────▶│ Phase Commands  │
│   (wizard)  │     │  (marker file)    │     │  (pre-flight)   │
└─────────────┘     └──────────────────┘     └─────────────────┘
                           │
                    ┌──────┴──────┐
                    ▼             ▼
            ┌───────────┐   ┌───────────┐
            │user_type: │   │user_type: │
            │   "thj"   │   │   "oss"   │
            └───────────┘   └───────────┘
                    │             │
                    ▼             ▼
            ┌───────────┐   ┌───────────┐
            │ Analytics │   │ No Track  │
            │ /feedback │   │           │
            │ /mcp-conf │   │           │
            └───────────┘   └───────────┘
```

### 2.2 Target Architecture (After)

```
┌─────────────────────────────────────────────────────────────┐
│                      Environment                             │
│  LOA_CONSTRUCTS_API_KEY="sk_..."  (optional, for THJ)       │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────┐     ┌─────────────────┐
│ Phase Commands  │     │  is_thj_member()│
│ (no pre-flight  │     │  (key presence) │
│  for setup)     │     └─────────────────┘
└─────────────────┘              │
                    ┌────────────┴────────────┐
                    ▼                         ▼
            ┌───────────┐             ┌───────────┐
            │ API Key   │             │ No API    │
            │ Present   │             │ Key       │
            └───────────┘             └───────────┘
                    │                         │
                    ▼                         ▼
            ┌───────────┐             ┌───────────┐
            │ Analytics │             │ No Track  │
            │ /feedback │             │ /feedback │
            │ Constructs│             │ → GitHub  │
            └───────────┘             └───────────┘
```

### 2.3 Component Overview

| Component | Status | Changes |
|-----------|--------|---------|
| `setup.md` | DELETE | Remove wizard |
| `mcp-config.md` | DELETE | Remove reconfiguration |
| `constructs-lib.sh` | MODIFY | Add `is_thj_member()` |
| `analytics.sh` | MODIFY | Use `is_thj_member()` |
| `preflight.sh` | MODIFY | Remove setup checks |
| `git-safety.sh` | MODIFY | Remove cached detection |
| `check-prerequisites.sh` | MODIFY | Remove marker checks |
| `feedback.md` | MODIFY | Use API key detection |
| Phase commands (9) | MODIFY | Remove setup pre-flight |

---

## 3. Component Design

### 3.1 New THJ Detection Function

**Location**: `.claude/scripts/constructs-lib.sh`

```bash
# =============================================================================
# THJ Membership Detection
# =============================================================================
# Replaces marker-file-based detection with API key presence check.
# Zero network dependency - checks environment variable only.
#
# Returns: 0 if THJ member (API key present), 1 otherwise
# =============================================================================

is_thj_member() {
    # Check for non-empty API key
    [[ -n "${LOA_CONSTRUCTS_API_KEY:-}" ]]
}
```

**Design Decisions**:
1. **No validation**: Key presence = THJ (validation happens on registry use)
2. **No caching**: Environment check is instant (~1ms)
3. **Graceful default**: Missing/empty key = not THJ (OSS user)

### 3.2 Analytics Script Changes

**File**: `.claude/scripts/analytics.sh`

**Before** (lines 87-100):
```bash
get_user_type() {
    if [ -f ".loa-setup-complete" ]; then
        grep -o '"user_type": *"[^"]*"' .loa-setup-complete 2>/dev/null | cut -d'"' -f4
    else
        echo "unknown"
    fi
}

should_track_analytics() {
    local user_type=$(get_user_type)
    [ "$user_type" = "thj" ]
}
```

**After**:
```bash
# Source constructs-lib for is_thj_member
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/constructs-lib.sh" 2>/dev/null || true

get_user_type() {
    if is_thj_member; then
        echo "thj"
    else
        echo "oss"
    fi
}

should_track_analytics() {
    is_thj_member
}
```

### 3.3 Preflight Script Changes

**File**: `.claude/scripts/preflight.sh`

**Remove Functions**:
- `check_setup_complete()` - No longer needed
- `check_user_is_thj()` - Replaced by `is_thj_member()`

**Add Function**:
```bash
# Check if user is THJ member (for THJ-only commands)
# Uses constructs-lib.sh for detection
check_user_is_thj() {
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${SCRIPT_DIR}/constructs-lib.sh" 2>/dev/null || return 1
    is_thj_member
}
```

### 3.4 Git Safety Script Changes

**File**: `.claude/scripts/git-safety.sh`

**Remove Layer 1** (lines 8-18):
```bash
# REMOVE: check_cached_detection()
# This function reads .loa-setup-complete which we're eliminating
```

**Updated `detect_template()`**:
```bash
detect_template() {
    local method

    # Layer 1: Check origin URL (was Layer 2)
    method=$(check_origin_url) && { echo "$method"; return 0; }
    # Layer 2: Check upstream remote (was Layer 3)
    method=$(check_upstream_remote) && { echo "$method"; return 0; }
    # Layer 3: Check GitHub API (was Layer 4)
    method=$(check_github_api) && { echo "$method"; return 0; }

    return 1
}
```

**Remove Functions**:
- `check_cached_detection()` - Reads marker file
- `is_detection_disabled()` - Reads marker file

### 3.5 Check Prerequisites Script Changes

**File**: `.claude/scripts/check-prerequisites.sh`

**Remove `.loa-setup-complete` from all phase checks**:

| Phase | Before | After |
|-------|--------|-------|
| `setup` | No prereqs | REMOVE CASE |
| `plan\|prd` | `.loa-setup-complete` | No prereqs |
| `architect\|sdd` | `.loa-setup-complete`, `prd.md` | `prd.md` only |
| `sprint-plan` | `.loa-setup-complete`, `prd.md`, `sdd.md` | `prd.md`, `sdd.md` |
| `implement` | `.loa-setup-complete`, `prd.md`, `sdd.md`, `sprint.md` | `prd.md`, `sdd.md`, `sprint.md` |
| `deploy` | `.loa-setup-complete`, `prd.md`, `sdd.md` | `prd.md`, `sdd.md` |

### 3.6 Command Pre-Flight Changes

**Pattern**: Remove setup check from all phase command YAML frontmatter

**Before**:
```yaml
pre_flight:
  - check: "file_exists"
    path: ".loa-setup-complete"
    error: "Loa setup has not been completed. Run /setup first."

  - check: "file_exists"
    path: "grimoires/loa/prd.md"
    error: "PRD not found. Run /plan-and-analyze first."
```

**After**:
```yaml
pre_flight:
  - check: "file_exists"
    path: "grimoires/loa/prd.md"
    error: "PRD not found. Run /plan-and-analyze first."
```

**Commands to Modify**:
1. `.claude/commands/plan-and-analyze.md` - Remove setup check entirely (first phase)
2. `.claude/commands/architect.md` - Remove setup check
3. `.claude/commands/sprint-plan.md` - Remove setup check
4. `.claude/commands/implement.md` - Remove setup check
5. `.claude/commands/review-sprint.md` - Remove setup check
6. `.claude/commands/audit-sprint.md` - Remove setup check
7. `.claude/commands/deploy-production.md` - Remove setup check
8. `.claude/commands/ride.md` - Remove setup check (if present)
9. `.claude/commands/mount.md` - Remove setup check (if present)

### 3.7 Feedback Command Changes

**File**: `.claude/commands/feedback.md`

**Before** (lines 18-30):
```yaml
pre_flight:
  - check: "file_exists"
    path: ".loa-setup-complete"
    error: "Loa setup has not been completed. Run /setup first."

  - check: "content_contains"
    path: ".loa-setup-complete"
    pattern: '"user_type":\s*"thj"'
    error: |
      The /feedback command is only available for THJ team members.
```

**After**:
```yaml
pre_flight:
  - check: "script"
    script: ".claude/scripts/check-thj-member.sh"
    error: |
      The /feedback command is only available for THJ team members.

      For OSS users, please submit feedback via:
      https://github.com/0xHoneyJar/loa/issues

      THJ members: Set LOA_CONSTRUCTS_API_KEY to enable this command.
```

**New Script**: `.claude/scripts/check-thj-member.sh`
```bash
#!/bin/bash
# Check if user is THJ member via API key presence
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/constructs-lib.sh"

is_thj_member
```

---

## 4. Files to Delete

| File | Lines | Reason |
|------|-------|--------|
| `.claude/commands/setup.md` | 202 | Setup wizard no longer needed |
| `.claude/commands/mcp-config.md` | ~100 | Only existed for post-setup reconfiguration |

**Total Deletion**: ~300 lines

---

## 5. Files to Modify

### 5.1 Scripts

| File | Changes | Estimated Lines |
|------|---------|-----------------|
| `.claude/scripts/constructs-lib.sh` | Add `is_thj_member()` | +15 |
| `.claude/scripts/analytics.sh` | Replace `get_user_type()`, `should_track_analytics()` | ~20 |
| `.claude/scripts/preflight.sh` | Remove `check_setup_complete()`, update `check_user_is_thj()` | ~25 |
| `.claude/scripts/git-safety.sh` | Remove `check_cached_detection()`, `is_detection_disabled()` | ~30 |
| `.claude/scripts/check-prerequisites.sh` | Remove `.loa-setup-complete` from all cases | ~15 |

**New Script**:
| File | Purpose | Lines |
|------|---------|-------|
| `.claude/scripts/check-thj-member.sh` | THJ check for pre-flight | ~10 |

### 5.2 Commands

| File | Changes |
|------|---------|
| `.claude/commands/plan-and-analyze.md` | Remove setup pre-flight check |
| `.claude/commands/architect.md` | Remove setup pre-flight check |
| `.claude/commands/sprint-plan.md` | Remove setup pre-flight check |
| `.claude/commands/implement.md` | Remove setup pre-flight check |
| `.claude/commands/review-sprint.md` | Remove setup pre-flight check |
| `.claude/commands/audit-sprint.md` | Remove setup pre-flight check |
| `.claude/commands/deploy-production.md` | Remove setup pre-flight check |
| `.claude/commands/ride.md` | Remove setup pre-flight check (if present) |
| `.claude/commands/mount.md` | Remove setup pre-flight check (if present) |
| `.claude/commands/feedback.md` | Change THJ check to script-based |

### 5.3 Documentation

| File | Changes |
|------|---------|
| `CLAUDE.md` | Remove Phase 0, update workflow table |
| `README.md` | Remove `/setup` from Quick Start and workflow |
| `PROCESS.md` | Remove setup documentation section |
| `CHANGELOG.md` | Document breaking change |

### 5.4 Configuration

| File | Changes |
|------|---------|
| `.gitignore` | Remove `.loa-setup-complete` entry |

---

## 6. Data Flow

### 6.1 THJ Detection Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                         Command Invocation                       │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                     is_thj_member() called                       │
│                                                                  │
│   Check: [[ -n "${LOA_CONSTRUCTS_API_KEY:-}" ]]                 │
│                                                                  │
│   ┌───────────────┐         ┌───────────────┐                   │
│   │ Key Present   │         │ Key Missing   │                   │
│   │ Return 0      │         │ Return 1      │                   │
│   └───────┬───────┘         └───────┬───────┘                   │
└───────────┼─────────────────────────┼───────────────────────────┘
            │                         │
            ▼                         ▼
┌───────────────────┐     ┌───────────────────┐
│   THJ Features    │     │   OSS Features    │
│   - Analytics     │     │   - Core workflow │
│   - /feedback     │     │   - No analytics  │
│   - Constructs    │     │   - GitHub Issues │
└───────────────────┘     └───────────────────┘
```

### 6.2 Analytics Flow

```
Command Execution
        │
        ▼
should_track_analytics()
        │
        ├─── is_thj_member() ───┐
        │                       │
        ▼                       ▼
    true (THJ)              false (OSS)
        │                       │
        ▼                       │
track_usage()                   │
        │                       │
        ▼                       │
Write to                        │
grimoires/loa/analytics/        │
        │                       │
        └───────────────────────┘
                 │
                 ▼
        Command continues
```

### 6.3 Feedback Command Flow

```
/feedback invoked
        │
        ▼
Pre-flight: check-thj-member.sh
        │
        ├─── Exit 0 (THJ) ──────────┐
        │                           │
        ▼                           ▼
    Exit 1 (OSS)            Show feedback wizard
        │                           │
        ▼                           ▼
Display error:              Submit to Linear
"THJ members only.          (existing behavior)
 Use GitHub Issues."
```

---

## 7. API Contracts

### 7.1 Function: `is_thj_member()`

**Location**: `.claude/scripts/constructs-lib.sh`

**Signature**:
```bash
is_thj_member() -> exit_code
```

**Behavior**:
| Condition | Return | Meaning |
|-----------|--------|---------|
| `LOA_CONSTRUCTS_API_KEY` is set and non-empty | 0 | User is THJ member |
| `LOA_CONSTRUCTS_API_KEY` is unset | 1 | User is OSS |
| `LOA_CONSTRUCTS_API_KEY` is empty string | 1 | User is OSS |

**Usage**:
```bash
source constructs-lib.sh

if is_thj_member; then
    echo "THJ member - full features"
else
    echo "OSS user - core features only"
fi
```

### 7.2 Function: `get_user_type()` (Updated)

**Location**: `.claude/scripts/analytics.sh`

**Signature**:
```bash
get_user_type() -> string
```

**Returns**:
| Condition | Output |
|-----------|--------|
| `is_thj_member()` returns 0 | `"thj"` |
| `is_thj_member()` returns 1 | `"oss"` |

### 7.3 Script: `check-thj-member.sh`

**Location**: `.claude/scripts/check-thj-member.sh`

**Purpose**: Pre-flight check for THJ-only commands

**Exit Codes**:
| Code | Meaning |
|------|---------|
| 0 | User is THJ member |
| 1 | User is not THJ member |

---

## 8. Migration Strategy

### 8.1 No Migration Required

The change is backward compatible:

| User Type | Current State | After Change |
|-----------|---------------|--------------|
| Existing THJ | Has `.loa-setup-complete` with `user_type: "thj"` | Set `LOA_CONSTRUCTS_API_KEY`, marker ignored |
| Existing OSS | Has `.loa-setup-complete` with `user_type: "oss"` | Marker ignored, commands work |
| New THJ | No marker | Set `LOA_CONSTRUCTS_API_KEY`, no setup needed |
| New OSS | No marker | No setup needed, commands work |

### 8.2 Marker File Handling

**Decision**: Ignore, don't delete

**Rationale**:
1. Deleting user files is intrusive
2. Marker is gitignored, causes no harm
3. Users can delete manually if desired
4. Avoids edge cases with custom markers

### 8.3 Documentation Updates

**CHANGELOG.md Entry**:
```markdown
## [0.15.0] - 2026-01-XX

### Removed
- **BREAKING**: `/setup` command removed - no longer required before workflow
- `/mcp-config` command removed - use standard Claude Code MCP configuration

### Changed
- THJ detection now uses `LOA_CONSTRUCTS_API_KEY` environment variable
- All phase commands work immediately without setup
- `/feedback` command requires API key for THJ members

### Migration
- Existing users: Set `LOA_CONSTRUCTS_API_KEY` environment variable to access THJ features
- OSS users: No changes required, commands work immediately
- Existing `.loa-setup-complete` files are ignored (can be deleted)
```

---

## 9. Testing Strategy

### 9.1 Unit Tests

**New Test File**: `tests/unit/thj-detection.bats`

```bash
@test "is_thj_member: returns 0 when API key is set" {
    export LOA_CONSTRUCTS_API_KEY="sk_test_key"
    source_is_thj_member
    run is_thj_member
    [[ "$status" -eq 0 ]]
}

@test "is_thj_member: returns 1 when API key is empty" {
    export LOA_CONSTRUCTS_API_KEY=""
    source_is_thj_member
    run is_thj_member
    [[ "$status" -eq 1 ]]
}

@test "is_thj_member: returns 1 when API key is unset" {
    unset LOA_CONSTRUCTS_API_KEY
    source_is_thj_member
    run is_thj_member
    [[ "$status" -eq 1 ]]
}

@test "get_user_type: returns 'thj' when API key set" {
    export LOA_CONSTRUCTS_API_KEY="sk_test_key"
    source_analytics
    result=$(get_user_type)
    [[ "$result" == "thj" ]]
}

@test "get_user_type: returns 'oss' when API key unset" {
    unset LOA_CONSTRUCTS_API_KEY
    source_analytics
    result=$(get_user_type)
    [[ "$result" == "oss" ]]
}

@test "should_track_analytics: returns 0 when THJ" {
    export LOA_CONSTRUCTS_API_KEY="sk_test_key"
    source_analytics
    run should_track_analytics
    [[ "$status" -eq 0 ]]
}

@test "should_track_analytics: returns 1 when OSS" {
    unset LOA_CONSTRUCTS_API_KEY
    source_analytics
    run should_track_analytics
    [[ "$status" -eq 1 ]]
}
```

### 9.2 Integration Tests

**New Test File**: `tests/integration/setup-removal.bats`

```bash
@test "plan-and-analyze: works without .loa-setup-complete" {
    rm -f .loa-setup-complete
    # Simulate command pre-flight check
    run check_prerequisites --phase plan
    [[ "$status" -eq 0 ]]
}

@test "architect: works without .loa-setup-complete" {
    rm -f .loa-setup-complete
    # Create required PRD
    mkdir -p grimoires/loa
    echo "# PRD" > grimoires/loa/prd.md
    run check_prerequisites --phase architect
    [[ "$status" -eq 0 ]]
}

@test "feedback: works with API key set" {
    export LOA_CONSTRUCTS_API_KEY="sk_test_key"
    run .claude/scripts/check-thj-member.sh
    [[ "$status" -eq 0 ]]
}

@test "feedback: fails gracefully without API key" {
    unset LOA_CONSTRUCTS_API_KEY
    run .claude/scripts/check-thj-member.sh
    [[ "$status" -eq 1 ]]
}

@test "git-safety: detects template without marker" {
    rm -f .loa-setup-complete
    # Mock origin URL to template
    run detect_template
    # Should still work via URL/API checks
}
```

### 9.3 Edge Case Tests

| Test | Description | Expected |
|------|-------------|----------|
| Empty API key | `LOA_CONSTRUCTS_API_KEY=""` | Treated as OSS |
| Whitespace key | `LOA_CONSTRUCTS_API_KEY="   "` | Treated as THJ (non-empty) |
| Invalid key format | `LOA_CONSTRUCTS_API_KEY="invalid"` | Treated as THJ (validation on use) |
| Old marker + API key | Both exist | API key takes precedence |
| Old marker, no key | Marker with `thj`, no env var | Treated as OSS |

---

## 10. Rollout Plan

### Sprint 1: Implementation

**Task 1.1**: Core Detection (2 hours)
- Add `is_thj_member()` to `constructs-lib.sh`
- Create `check-thj-member.sh` script
- Update `analytics.sh` with new detection

**Task 1.2**: Remove Setup Infrastructure (2 hours)
- Delete `setup.md` command
- Delete `mcp-config.md` command
- Update `.gitignore`

**Task 1.3**: Update Pre-flights (1.5 hours)
- Remove setup checks from all 9+ commands
- Update `feedback.md` to use script-based check
- Update `preflight.sh`

**Task 1.4**: Update Scripts (1.5 hours)
- Update `check-prerequisites.sh`
- Update `git-safety.sh`
- Remove marker file dependencies

**Task 1.5**: Documentation (1 hour)
- Update `CLAUDE.md`
- Update `README.md`
- Update `PROCESS.md`
- Write `CHANGELOG.md` entry

**Task 1.6**: Testing (1.5 hours)
- Write unit tests for `is_thj_member()`
- Write integration tests for commands
- Manual testing of full workflow

### Release

**Version**: 0.15.0 (minor bump - breaking change but documented migration)

**Release Notes Focus**:
1. Immediate workflow entry (no setup required)
2. THJ features via API key
3. Backward compatible (markers ignored)

---

## 11. Security Considerations

### 11.1 API Key Handling

| Aspect | Approach |
|--------|----------|
| Storage | User's environment, not in repo |
| Validation | On constructs registry use, not on presence check |
| Exposure | Never logged, never written to files |
| Scope | Only used for THJ feature detection |

### 11.2 No Security Degradation

- Constructs registry still validates API key on download
- License validation unchanged
- Git safety still prevents template pushes (via URL/API checks)

---

## 12. Appendix

### A. File Change Summary

| Operation | Files | Count |
|-----------|-------|-------|
| DELETE | `setup.md`, `mcp-config.md` | 2 |
| CREATE | `check-thj-member.sh`, `thj-detection.bats`, `setup-removal.bats` | 3 |
| MODIFY | Scripts (5), Commands (10), Docs (4), Config (1) | 20 |
| TOTAL | | ~25 |

### B. Lines of Code Impact

| Category | Before | After | Delta |
|----------|--------|-------|-------|
| Commands | ~2500 | ~2200 | -300 |
| Scripts | ~1500 | ~1480 | -20 |
| Tests | ~800 | ~900 | +100 |
| **Net** | | | **-220** |

### C. Environment Variable Documentation

```bash
# THJ Member Configuration
# Add to ~/.bashrc, ~/.zshrc, or .envrc

# Required for THJ features (analytics, /feedback, constructs)
export LOA_CONSTRUCTS_API_KEY="sk_your_api_key_here"

# Verification
echo $LOA_CONSTRUCTS_API_KEY  # Should show your key
```

---

*Document generated by Loa designing-architecture agent*
*Next step: `/sprint-plan` to create implementation tasks*

