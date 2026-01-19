# Product Requirements Document: Remove Setup Phase

**Version**: 1.0.0
**Status**: Draft
**Author**: Claude (Agent)
**Date**: 2026-01-17
**Feature Branch**: `feature/remove-setup-phase`

---

## 1. Executive Summary

This PRD defines the removal of the `/setup` phase from the Loa framework, eliminating the distinction between THJ (The HoneyJar) and OSS (Open Source) users at onboarding time. THJ membership detection will be preserved specifically for constructs registry access, using API key presence as the detection mechanism.

### 1.1 Problem Statement

The current `/setup` wizard:
1. Creates friction for new users who must run setup before using any phase commands
2. Artificially bifurcates users into "THJ" vs "OSS" categories at first use
3. Stores user type in a marker file (`.loa-setup-complete`) that adds complexity
4. Requires maintenance of parallel code paths for THJ vs OSS experiences

### 1.2 Proposed Solution

Remove the `/setup` phase entirely. Detect THJ membership dynamically based on the presence of a valid `LOA_CONSTRUCTS_API_KEY` environment variable, which is already required for constructs registry access.

### 1.3 Success Metrics

| Metric | Target |
|--------|--------|
| Lines of code removed | >300 |
| Files modified/deleted | ~15 |
| User onboarding steps | Reduced from 2 to 1 (no `/setup` required) |
| Breaking changes | 0 (graceful degradation for existing users) |

---

## 2. Background & Context

### 2.1 Current Architecture

The Loa framework currently uses a Three-Zone Model with a mandatory setup phase:

```
Current Flow:
  User clones/mounts Loa
  → /setup (REQUIRED)
  → Creates .loa-setup-complete with user_type
  → /plan-and-analyze (checks for marker)
  → /architect → /sprint-plan → etc.
```

The `.loa-setup-complete` marker file contains:
```json
{
  "user_type": "thj" | "oss",
  "setup_date": "2026-01-17T00:00:00Z",
  "template_detection": { "detected": true|false },
  "mcp_servers": ["github", "linear", ...]
}
```

### 2.2 THJ-Specific Features (Current)

| Feature | Current Check | Usage |
|---------|---------------|-------|
| Analytics tracking | `user_type == "thj"` in marker | Track usage for THJ developers |
| `/feedback` command | Pre-flight check on marker | Submit feedback to Linear |
| `/mcp-config` command | Pre-flight check on marker | Reconfigure MCP servers |
| Constructs registry | API key required | Commercial skill packs |

### 2.3 Why Change Now

1. **Constructs Registry is Live**: The registry already uses `LOA_CONSTRUCTS_API_KEY` for authentication
2. **Simpler Mental Model**: Users don't need to declare membership; it's implicit in having access
3. **Reduced Maintenance**: One code path instead of two
4. **Better DX**: Immediate productivity without setup ceremony

---

## 3. Requirements

### 3.1 Functional Requirements

#### FR-REM-01: Remove Setup Command
**Priority**: P0 (Critical)

Delete the `/setup` command and all associated infrastructure:
- `.claude/commands/setup.md`
- Setup wizard logic
- User type selection flow
- MCP configuration wizard

**Acceptance Criteria**:
- [ ] `/setup` command no longer exists
- [ ] No references to setup wizard in codebase
- [ ] Users can run `/plan-and-analyze` immediately after cloning

#### FR-REM-02: Remove Setup Marker File Dependency
**Priority**: P0 (Critical)

Remove all checks for `.loa-setup-complete`:
- Phase command pre-flight checks
- User type detection
- Template detection caching

**Acceptance Criteria**:
- [ ] No code references `.loa-setup-complete`
- [ ] Existing marker files are ignored (not deleted)
- [ ] All phase commands work without marker

#### FR-REM-03: API Key-Based THJ Detection
**Priority**: P0 (Critical)

Implement new THJ detection using `LOA_CONSTRUCTS_API_KEY`:

```bash
is_thj_member() {
    [[ -n "${LOA_CONSTRUCTS_API_KEY:-}" ]]
}
```

**Acceptance Criteria**:
- [ ] `is_thj_member()` function available in shared scripts
- [ ] Returns true when API key is set (non-empty)
- [ ] Returns false when API key is unset or empty
- [ ] No network call required (presence check only)

#### FR-REM-04: Preserve Analytics for THJ Members
**Priority**: P1 (High)

Analytics tracking continues for THJ members:
- Detection uses API key presence
- No change to analytics storage location
- Graceful degradation when not THJ

**Acceptance Criteria**:
- [ ] `should_track_analytics()` uses `is_thj_member()`
- [ ] Analytics still written to `grimoires/loa/analytics/`
- [ ] OSS users (no API key) have no analytics overhead

#### FR-REM-05: Update /feedback Command
**Priority**: P1 (High)

Modify `/feedback` to use API key detection:
- Remove marker file pre-flight check
- Add API key presence check
- Update error message for non-THJ users

**Acceptance Criteria**:
- [ ] `/feedback` works for users with API key
- [ ] Clear error message for users without API key
- [ ] Points OSS users to GitHub Issues

#### FR-REM-06: Remove /mcp-config Command
**Priority**: P2 (Medium)

The `/mcp-config` command exists only for post-setup MCP reconfiguration. Without setup, it serves no purpose.

**Acceptance Criteria**:
- [ ] `/mcp-config` command deleted
- [ ] No references to mcp-config in documentation
- [ ] MCP servers configured via standard Claude Code mechanisms

#### FR-REM-07: Update Documentation
**Priority**: P1 (High)

Update all documentation to reflect new flow:
- README.md: Remove Phase 0, update Quick Start
- PROCESS.md: Remove setup documentation
- CLAUDE.md: Update workflow table
- CHANGELOG.md: Document breaking change

**Acceptance Criteria**:
- [ ] No documentation references `/setup`
- [ ] Quick Start shows direct workflow entry
- [ ] THJ detection documented as API key-based

### 3.2 Non-Functional Requirements

#### NFR-01: Backward Compatibility
**Priority**: P0 (Critical)

Existing users with `.loa-setup-complete` files should experience no disruption:
- Marker files ignored but not deleted
- Existing THJ users who set API key continue working
- No migration script required

#### NFR-02: Zero Network Dependency for Detection
**Priority**: P0 (Critical)

THJ detection must not require network calls:
- Check API key presence only (not validity)
- Constructs loader validates key on actual use
- Offline users with API key are still detected as THJ

#### NFR-03: Minimal Code Changes
**Priority**: P1 (High)

Changes should be surgical and focused:
- Prefer deletion over modification
- Avoid refactoring unrelated code
- Maintain existing test patterns

---

## 4. Technical Design

### 4.1 New THJ Detection Function

Add to `.claude/scripts/constructs-lib.sh`:

```bash
# Check if user is a THJ member (has constructs API key)
# This replaces the old marker-file-based detection
# Returns: 0 if THJ member, 1 if not
is_thj_member() {
    [[ -n "${LOA_CONSTRUCTS_API_KEY:-}" ]]
}
```

### 4.2 Files to Delete

| File | Reason |
|------|--------|
| `.claude/commands/setup.md` | Setup wizard no longer needed |
| `.claude/commands/mcp-config.md` | Only existed for post-setup reconfiguration |

### 4.3 Files to Modify

| File | Changes |
|------|---------|
| `.claude/scripts/analytics.sh` | `get_user_type()` → use `is_thj_member()` |
| `.claude/scripts/preflight.sh` | Remove `check_setup_complete()`, add THJ check |
| `.claude/scripts/check-prerequisites.sh` | Remove `.loa-setup-complete` from all phases |
| `.claude/scripts/git-safety.sh` | Remove cached detection from marker |
| `.claude/commands/scripts/common.sh` | Update `get_user_type()` |
| `.claude/commands/feedback.md` | Update pre-flight to use API key |
| `.claude/commands/plan-and-analyze.md` | Remove setup prerequisite |
| `.claude/commands/architect.md` | Remove setup prerequisite |
| `.claude/commands/sprint-plan.md` | Remove setup prerequisite |
| `.claude/commands/implement.md` | Remove setup prerequisite |
| `.claude/commands/review-sprint.md` | Remove setup prerequisite |
| `.claude/commands/audit-sprint.md` | Remove setup prerequisite |
| `.claude/commands/deploy-production.md` | Remove setup prerequisite |
| `.gitignore` | Remove `.loa-setup-complete` entry |
| `CLAUDE.md` | Update workflow documentation |
| `README.md` | Update quick start, remove Phase 0 |
| `PROCESS.md` | Remove setup documentation |
| `CHANGELOG.md` | Document this change |

### 4.4 Migration Path

No migration required. The change is backward compatible:

1. **Existing THJ users**: Set `LOA_CONSTRUCTS_API_KEY` and continue
2. **Existing OSS users**: No change needed, commands just work
3. **New users**: No setup required, start with `/plan-and-analyze`

---

## 5. User Stories

### US-01: New User Onboarding
**As a** new Loa user
**I want to** start using Loa immediately after cloning
**So that** I can be productive without ceremony

**Acceptance Criteria**:
- Clone/mount Loa → run `/plan-and-analyze` directly
- No `/setup` prompt or requirement
- Clear documentation on getting started

### US-02: THJ Developer with Constructs Access
**As a** THJ developer
**I want to** access commercial skill packs
**So that** I can use premium features

**Acceptance Criteria**:
- Set `LOA_CONSTRUCTS_API_KEY` environment variable
- Constructs registry works as before
- Analytics tracked automatically
- `/feedback` command available

### US-03: OSS Developer
**As an** open source developer
**I want to** use Loa without any special configuration
**So that** I can contribute to projects using Loa

**Acceptance Criteria**:
- All core commands work without API key
- No analytics tracking (privacy preserved)
- `/feedback` shows helpful message pointing to GitHub Issues
- Constructs registry shows "API key required" message

### US-04: Existing User Upgrade
**As an** existing Loa user
**I want to** upgrade to the new version seamlessly
**So that** my workflow isn't disrupted

**Acceptance Criteria**:
- Existing `.loa-setup-complete` files are ignored
- No migration steps required
- THJ users need to set API key if they want constructs access

---

## 6. Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Existing THJ users confused by API key requirement | Medium | Medium | Clear documentation, CHANGELOG entry |
| Analytics data loss during transition | Low | Low | API key detection is additive, not destructive |
| Commands fail without setup marker | Low | High | Thorough testing of all phase commands |
| `/mcp-config` removal upsets users | Low | Low | Feature was rarely used, MCP config via Claude Code |

---

## 7. Testing Strategy

### 7.1 Unit Tests

| Test | Description |
|------|-------------|
| `is_thj_member()` with API key set | Returns 0 (true) |
| `is_thj_member()` with API key empty | Returns 1 (false) |
| `is_thj_member()` with API key unset | Returns 1 (false) |
| `should_track_analytics()` with API key | Returns 0 (true) |
| `should_track_analytics()` without API key | Returns 1 (false) |

### 7.2 Integration Tests

| Test | Description |
|------|-------------|
| `/plan-and-analyze` without setup | Command executes successfully |
| `/plan-and-analyze` with old marker | Command ignores marker, executes |
| `/feedback` with API key | Shows feedback wizard |
| `/feedback` without API key | Shows GitHub Issues link |
| Constructs loader with API key | Loads licensed skills |
| Constructs loader without API key | Shows API key required message |

### 7.3 Edge Cases

| Test | Description |
|------|-------------|
| Empty API key (`LOA_CONSTRUCTS_API_KEY=""`) | Treated as not THJ |
| Whitespace API key | Treated as not THJ |
| Invalid API key format | Still detected as THJ (validation on use) |
| Old marker + new API key | API key takes precedence |

---

## 8. Rollout Plan

### Phase 1: Implementation (Sprint 1)
- Delete `/setup` and `/mcp-config` commands
- Implement `is_thj_member()` function
- Update all prerequisite checks
- Update analytics detection

### Phase 2: Documentation (Sprint 1)
- Update README.md, PROCESS.md, CLAUDE.md
- Write CHANGELOG entry
- Update any external documentation

### Phase 3: Testing (Sprint 1)
- Run full test suite
- Manual testing of all phase commands
- Test with and without API key

### Phase 4: Release (Sprint 1)
- Version bump (minor: 0.15.0)
- Create GitHub release
- Announce in release notes

---

## 9. Appendix

### A. Current Setup Command Flow (Being Removed)

```
/setup
├── Phase 1: User Type Detection
│   ├── Check org membership (0xHoneyJar)
│   ├── Check email domain (@honeyjar.xyz)
│   └── Ask user if unclear
├── Phase 2: Template Detection
│   └── Check if working in upstream template
├── Phase 3: THJ-Specific Setup
│   ├── MCP Server Configuration
│   ├── Analytics Initialization
│   └── Create marker with user_type: "thj"
├── Phase 4: OSS-Specific Setup
│   ├── Welcome message
│   └── Create marker with user_type: "oss"
└── Output: .loa-setup-complete
```

### B. New Flow (After Implementation)

```
User clones/mounts Loa
├── (Optional) Set LOA_CONSTRUCTS_API_KEY for THJ features
├── /plan-and-analyze → Creates PRD
├── /architect → Creates SDD
├── /sprint-plan → Creates sprint.md
└── ... (continue workflow)
```

### C. API Key Documentation (For THJ Users)

```bash
# Add to shell profile (~/.bashrc, ~/.zshrc)
export LOA_CONSTRUCTS_API_KEY="sk_your_api_key_here"

# Or use direnv (.envrc in project)
export LOA_CONSTRUCTS_API_KEY="sk_your_api_key_here"
```

---

## 10. Approval

| Role | Name | Date | Status |
|------|------|------|--------|
| Product Owner | | | Pending |
| Tech Lead | | | Pending |
| Security | | | Pending |

---

*Document generated by Loa discovering-requirements agent*
*Next step: `/architect` to create Software Design Document*
