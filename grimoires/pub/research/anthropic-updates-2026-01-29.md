# Anthropic Updates Analysis

**Date**: 2026-01-29
**Oracle Run**: 2026-01-29T10:30:00Z
**Analyst**: Claude (via Anthropic Oracle)

## Executive Summary

- **Async Hooks** (`async: true`) released in Claude Code 2.1.0 - Loa should adopt for non-blocking hooks (IMPLEMENTED)
- **Setup Hook** is new event type for `--init`/`--maintenance` flags - Loa could leverage for framework initialization
- **Skill Hot-Reload** automatically reloads skills without restart - Loa skills could benefit
- **context: fork** and `agent` field in skills enable subagent execution - could enhance parallel skill execution
- **New task management system** with dependency tracking - potential alignment with Beads integration

---

## New Features Identified

### Feature 1: Async Hooks (`async: true`)

**Source**: [Claude Code Changelog 2.1.0+](https://code.claude.com/docs/en/changelog)
**Relevance to Loa**: **HIGH**

**Description**:
Hooks can now run in the background without blocking Claude Code's execution. Add `async: true` to hook configuration for logging, notifications, or any side-effect that shouldn't slow things down.

**Potential Integration**:
- `SessionStart` hooks (update checks) - IMPLEMENTED
- `PermissionRequest` hooks (audit logging) - IMPLEMENTED
- Future `PostToolUse` logging hooks

**Implementation Effort**: Low
**Status**: IMPLEMENTED in this branch

---

### Feature 2: Setup Hook Event

**Source**: [Hooks Reference](https://code.claude.com/docs/en/hooks)
**Relevance to Loa**: **MEDIUM**

**Description**:
New `Setup` hook event triggers via `--init`, `--init-only`, or `--maintenance` flags. Has access to `CLAUDE_ENV_FILE` for persisting environment variables.

**Potential Integration**:
- Loa framework initialization
- Post-upgrade migrations via `upgrade-health-check.sh`
- Dependency installation checks

**Implementation Effort**: Medium

---

### Feature 3: Skill Hot-Reload

**Source**: [Skills Documentation](https://code.claude.com/docs/en/skills)
**Relevance to Loa**: **MEDIUM**

**Description**:
Skills in `~/.claude/skills` or `.claude/skills` automatically reload without restarting Claude Code. Changes to SKILL.md take effect immediately.

**Potential Integration**:
Loa skills already follow this pattern. No action needed.

**Implementation Effort**: None (already compatible)

---

### Feature 4: Skill Subagent Execution (`context: fork`)

**Source**: [Skills Documentation](https://code.claude.com/docs/en/skills)
**Relevance to Loa**: **HIGH**

**Description**:
Add `context: fork` to skill frontmatter to run in isolated subagent context. Combine with `agent` field to specify execution environment (Explore, Plan, general-purpose, or custom).

**Potential Integration**:
- `/ride` could use `context: fork` with `agent: Explore`
- `/architect` could use `agent: Plan`
- Parallel sprint execution via forked contexts

**Implementation Effort**: Medium

---

### Feature 5: New Task Management System

**Source**: [Changelog v2.1.16](https://github.com/anthropics/claude-code/releases)
**Relevance to Loa**: **MEDIUM**

**Description**:
Claude Code 2.1.16 introduced a new task management system with dependency tracking. Tasks can be created, updated, and deleted. Supports parallel execution with dependency resolution.

**Potential Integration**:
- Could complement Beads task graph
- Sprint task tracking enhancement
- Run Mode task coordination

**Implementation Effort**: High (needs architecture review)

---

### Feature 6: PR Review Status Indicator

**Source**: [Changelog v2.1.20](https://github.com/anthropics/claude-code/releases)
**Relevance to Loa**: **LOW**

**Description**:
Shows current branch's PR state (approved, changes requested, pending, draft) as colored dot with clickable link in prompt footer.

**Potential Integration**:
Nice-to-have awareness for `/implement` and `/review-sprint` commands.

**Implementation Effort**: Low (UI enhancement)

---

### Feature 7: Bash History Autocomplete

**Source**: [Changelog v2.1.14](https://github.com/anthropics/claude-code/releases)
**Relevance to Loa**: **LOW**

**Description**:
Type partial command with `!` prefix and Tab to complete from bash history.

**Potential Integration**:
Already available in Claude Code. No Loa changes needed.

**Implementation Effort**: None

---

### Feature 8: MCP Tool Search Auto Mode

**Source**: [Changelog v2.1.7](https://github.com/anthropics/claude-code/releases)
**Relevance to Loa**: **MEDIUM**

**Description**:
MCP tool search auto mode enabled by default. Defers if >10% context window. Configurable with `auto:N` syntax (0-100%).

**Potential Integration**:
MCP integrations documentation could mention this setting.

**Implementation Effort**: Low (documentation)

---

### Feature 9: PreToolUse `additionalContext` Return

**Source**: [Changelog v2.1.9](https://code.claude.com/docs/en/changelog)
**Relevance to Loa**: **HIGH** (already using)

**Description**:
PreToolUse hooks can now return `additionalContext` field to inject context into Claude's prompt before tool execution.

**Potential Integration**:
Already implemented in `memory-inject.sh` hook for Memory Stack.

**Implementation Effort**: None (already implemented)

---

### Feature 10: Session ID Access in Skills

**Source**: [Changelog v2.1.9](https://code.claude.com/docs/en/changelog)
**Relevance to Loa**: **LOW**

**Description**:
`${CLAUDE_SESSION_ID}` substitution available in skills for logging, creating session-specific files, or correlating output.

**Potential Integration**:
- Trajectory logging could use session ID
- NOTES.md session tracking

**Implementation Effort**: Low

---

## API Changes

| Change | Type | Impact on Loa | Action Required |
|--------|------|---------------|-----------------|
| `async: true` for hooks | New | Improves performance | Yes - DONE |
| `Setup` hook event | New | Could use for init | No (optional) |
| `context: fork` in skills | New | Parallel execution | No (optional) |
| `agent` field in skills | New | Subagent routing | No (optional) |
| `$ARGUMENTS[N]` syntax | Modified | Bracket syntax | No (already works) |
| `once: true` hook flag | New | One-time hooks | No (optional) |
| `additionalContext` return | New | Context injection | Yes - DONE |
| `respectGitignore` setting | New | @ file picker | No (optional) |
| `plansDirectory` setting | New | Plan storage | No (optional) |
| `showTurnDuration` setting | New | UI control | No (optional) |
| `language` setting | New | Response language | No (optional) |

---

## Deprecations & Breaking Changes

### npm Installation Deprecation

**Effective Date**: v2.1.15 (Jan 21, 2026)
**Loa Impact**: Low - installation instructions may need update
**Migration Path**: Use native install (`curl -fsSL https://claude.ai/install.sh | bash`) instead of npm

### OAuth URL Change

**Effective Date**: v2.1.7
**Loa Impact**: None - internal change
**Migration Path**: No action needed

---

## Best Practices Updates

### Prefer File Tools Over Bash

**Previous Approach**: Using `cat`, `sed`, `awk` via Bash tool
**New Recommendation**: Claude now prefers Read, Edit, Write tools over bash equivalents (v2.1.21)
**Loa Files Affected**: None (already follows this pattern in CLAUDE.md)

### Hook Timeout Extended

**Previous Approach**: 60 second hook timeout
**New Recommendation**: Tool hook timeout extended to 10 minutes (v2.1.3)
**Loa Files Affected**: Long-running hooks no longer need special handling

### Large Output Handling

**Previous Approach**: Truncate outputs >30K chars
**New Recommendation**: Large outputs saved to disk with file path reference (v2.1.0)
**Loa Files Affected**: Long test outputs now recoverable

---

## Gaps Analysis

| Loa Feature | Anthropic Capability | Gap | Priority |
|-------------|---------------------|-----|----------|
| Async Hooks | `async: true` | **CLOSED** - Implemented | - |
| Memory Injection | `additionalContext` | **CLOSED** - Implemented | - |
| Skill Forking | `context: fork` | Not using forked contexts | P2 |
| Task Dependencies | TaskUpdate with deps | Beads does this differently | P3 |
| Setup Automation | Setup hook | No `--init` hook | P2 |
| Session ID Tracking | `${CLAUDE_SESSION_ID}` | Not using in skills | P3 |
| PR Status | PR review indicator | Not leveraged | P3 |
| File Read Limits | `FILE_READ_MAX_OUTPUT_TOKENS` | Not documented | P3 |

---

## Recommended Actions

### Priority 1 (Immediate) - COMPLETED

1. **Add `async: true` to non-blocking hooks**: Improve startup and permission flow performance
   - Effort: Low
   - Files: `.claude/settings.json`
   - Status: **DONE**

2. **Document async hooks in protocols**: Update recommended-hooks.md
   - Effort: Low
   - Files: `.claude/protocols/recommended-hooks.md`
   - Status: **DONE**

### Priority 2 (Next Release)

1. **Add Setup hook for initialization**: Use `--init` flag for Loa framework setup
   - Effort: Medium
   - Files: `.claude/settings.json`, new script

2. **Explore `context: fork` for parallel skills**: Test `/ride` with forked context
   - Effort: Medium
   - Files: Skill frontmatter updates

3. **Add `once: true` to one-time hooks**: Session-start hooks that only need to run once
   - Effort: Low
   - Files: `.claude/settings.json`

### Priority 3 (Future)

1. **Session ID tracking in trajectory**: Use `${CLAUDE_SESSION_ID}` for better correlation
   - Effort: Low
   - Files: Trajectory scripts

2. **Document FILE_READ_MAX_OUTPUT_TOKENS**: Add to .loa.config.yaml options
   - Effort: Low
   - Files: Documentation

3. **Evaluate native task system alignment**: Compare with Beads approach
   - Effort: High
   - Files: Architecture review

---

## Sources Analyzed

- [Claude Code Documentation](https://code.claude.com/docs/en/overview)
- [Claude Code Changelog](https://code.claude.com/docs/en/changelog)
- [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks)
- [Claude Code Skills Reference](https://code.claude.com/docs/en/skills)
- [Claude Code Settings Reference](https://code.claude.com/docs/en/settings)
- [GitHub Releases](https://github.com/anthropics/claude-code/releases)

---

## Next Oracle Run

Recommended: 2026-02-05 or when Anthropic announces Claude Code 2.2.0
