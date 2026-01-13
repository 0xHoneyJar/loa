# Anthropic Updates Analysis

**Date**: 2026-01-13
**Oracle Run**: 2026-01-13T10:03:00Z
**Analyst**: Claude (via Anthropic Oracle)
**Loa Version**: 0.13.0

## Executive Summary

Major developments from Anthropic since last analysis:

1. **Claude Code 2.1.x** - Significant features including skill hot-reload, hooks in agent frontmatter, LSP support, and advanced context management
2. **Claude Opus 4.5** released (Nov 2025) - Best model for coding, agents, and computer use
3. **Claude Agent SDK** released (Sep 2025) - Official framework for building autonomous agents
4. **MCP Donation** (Dec 2025) - Model Context Protocol donated to Agentic AI Foundation
5. **Documentation moved** to `platform.claude.com` - URL updates needed

---

## Critical: URL Updates Required

Anthropic docs have moved. Update oracle sources:

| Old URL | New URL |
|---------|---------|
| `docs.anthropic.com/en/docs/claude-code` | Redirects to GitHub repo |
| `docs.anthropic.com/en/release-notes/claude-code` | Redirects to `github.com/anthropics/claude-code/blob/main/CHANGELOG.md` |
| N/A | `code.claude.com/docs/en/*` (new docs home) |
| N/A | `platform.claude.com/docs/en/*` (platform docs) |

**Action Required**: Update `.claude/scripts/anthropic-oracle.sh` SOURCES array.

---

## New Features Identified

### Feature 1: Automatic Skill Hot-Reload (v2.1.0)

**Source**: CHANGELOG.md
**Relevance to Loa**: **HIGH**

**Description**: Skills in `~/.claude/skills` or `.claude/skills` are now immediately available without restarting the session. Changes are detected and loaded dynamically.

**Potential Integration**:
- Loa skills could leverage this for faster development iteration
- Consider adapting `.claude/scripts/skills-adapter.sh` to support hot-reload events
- Could enable "live editing" of skills during sessions

**Implementation Effort**: Low

---

### Feature 2: Skill Context Forking (v2.1.0)

**Source**: CHANGELOG.md
**Relevance to Loa**: **HIGH**

**Description**: Skills can now run in a forked sub-agent context using `context: fork` in skill frontmatter. This isolates skill execution from the main conversation.

**Potential Integration**:
- Loa skills (especially `/audit-sprint`, `/review-sprint`) could benefit from isolation
- Prevents skill execution from polluting main conversation context
- Could improve context management in long sessions

**Implementation Effort**: Low - frontmatter addition only

**Example**:
```yaml
---
name: my-skill
context: fork
---
```

---

### Feature 3: Hooks in Agent/Skill Frontmatter (v2.1.0)

**Source**: CHANGELOG.md
**Relevance to Loa**: **HIGH**

**Description**: Agents and skills can now define PreToolUse, PostToolUse, and Stop hooks scoped to their lifecycle directly in frontmatter.

**Potential Integration**:
- Loa skills could define validation hooks inline
- Could replace some external hook scripts with embedded frontmatter
- Enables per-skill security policies

**Implementation Effort**: Medium

**Example**:
```yaml
---
name: implementing-tasks
hooks:
  PreToolUse:
    - command: ".claude/scripts/validate-tool.sh"
      timeout: 30000
---
```

---

### Feature 4: LSP (Language Server Protocol) Tool (v2.0.74)

**Source**: CHANGELOG.md
**Relevance to Loa**: **MEDIUM**

**Description**: Go-to-definition, find references, and hover documentation via LSP integration.

**Potential Integration**:
- Could enhance `/implement` skill with better code navigation
- Useful for `/review-sprint` to understand code relationships
- Consider adding LSP server config to MCP registry

**Implementation Effort**: Medium

---

### Feature 5: Background Agent Support (v2.0.60)

**Source**: CHANGELOG.md
**Relevance to Loa**: **HIGH**

**Description**: Agents can run in background while user works. Unified Ctrl+B for backgrounding.

**Potential Integration**:
- Long-running Loa skills (audits, reviews) could run in background
- `/implement sprint-N background` mode could be enhanced
- Consider background mode for `/audit-sprint`

**Implementation Effort**: Low - already partially supported

---

### Feature 6: Agent Setting & CLI Flag (v2.0.59)

**Source**: CHANGELOG.md
**Relevance to Loa**: **HIGH**

**Description**: `--agent` CLI flag and `agent` setting to configure main thread with specific agent's system prompt, tool restrictions, and model.

**Potential Integration**:
- Could preset Claude Code to use Loa skills automatically
- Enables "Loa mode" activation without manual setup
- Consider creating a Loa-specific agent configuration

**Implementation Effort**: Low

---

### Feature 7: Wildcard Bash Permissions (v2.1.0)

**Source**: CHANGELOG.md
**Relevance to Loa**: **MEDIUM**

**Description**: Support for `Bash(npm *)`, `Bash(* install)`, `Bash(git * main)` patterns.

**Potential Integration**:
- Simplify Loa's permission rules in recommended hooks
- Could reduce permission prompts during development
- Update `.claude/protocols/recommended-hooks.md`

**Implementation Effort**: Low

---

### Feature 8: Plugin System (v2.0.12)

**Source**: CHANGELOG.md
**Relevance to Loa**: **HIGH**

**Description**: Full plugin system with marketplaces, commands, agents, hooks, and MCP servers.

**Potential Integration**:
- Loa could be distributed as a plugin marketplace
- Would simplify installation and updates
- Could enable modular skill packs

**Implementation Effort**: High

**Docs**: https://code.claude.com/docs/en/plugins

---

### Feature 9: Claude in Chrome (v2.0.72)

**Source**: CHANGELOG.md
**Relevance to Loa**: **LOW**

**Description**: Control browser from Claude Code via Chrome extension.

**Potential Integration**:
- Could enable web-based documentation checking
- Useful for deployment verification skills

**Implementation Effort**: Medium

---

### Feature 10: Named Sessions (v2.0.64)

**Source**: CHANGELOG.md
**Relevance to Loa**: **MEDIUM**

**Description**: `/rename` to name sessions, `claude --resume <name>` to resume.

**Potential Integration**:
- Could name sessions by sprint or phase
- Improve session continuity protocol
- Consider auto-naming based on active work

**Implementation Effort**: Low

---

## API Changes

| Change | Type | Impact on Loa | Action Required |
|--------|------|---------------|-----------------|
| Agent SDK released | New | Could replace Task tool usage | Consider integration |
| MCP `list_changed` notifications | New | Dynamic tool updates | Update MCP registry docs |
| `language` setting | New | Multi-language support | Document in config |
| `respectGitignore` setting | New | File picker behavior | Document in config |
| Plugin hooks | New | PreToolUse, PostToolUse, Stop | Review hook patterns |
| Slash commands merged with skills | Changed | Simplified model | Update documentation |
| NPM installation deprecated | Deprecated | Installation docs | Update INSTALLATION.md |
| Legacy SDK entrypoint removed | Breaking | SDK users | Migrate to agent-sdk |

---

## Deprecations & Breaking Changes

### NPM Installation Deprecated (v2.1.x)

**Effective Date**: Current
**Loa Impact**: Documentation updates needed
**Migration Path**:
```bash
# New recommended install
curl -fsSL https://claude.ai/install.sh | bash
# or
brew install --cask claude-code
```

### Legacy SDK Removed (v2.0.25)

**Effective Date**: v2.0.25
**Loa Impact**: If using SDK, migration required
**Migration Path**: https://platform.claude.com/docs/en/agent-sdk/migration-guide

### Output Styles Deprecated (v2.0.30)

**Effective Date**: v2.0.30
**Loa Impact**: Low - Loa uses skills instead
**Migration Path**: Use --system-prompt-file, skills, or plugins

---

## Best Practices Updates

### Skill Discovery from Nested Directories (v2.1.6)

**Previous Approach**: Skills only from `.claude/skills/`
**New Recommendation**: Skills auto-discovered from nested `.claude/skills` directories
**Loa Files Affected**: Consider reorganizing skills if needed

### Simplified Slash Commands (v2.1.3)

**Previous Approach**: Separate slash commands and skills
**New Recommendation**: Merged mental model - skills ARE slash commands
**Loa Files Affected**: Documentation, CLAUDE.md

### Tool Hook Timeout (v2.1.3)

**Previous Approach**: 60 second timeout
**New Recommendation**: 10 minute timeout for long-running hooks
**Loa Files Affected**: Hook scripts can now run longer

---

## Gaps Analysis

| Loa Feature | Anthropic Capability | Gap | Priority |
|-------------|---------------------|-----|----------|
| Skills Adapter | Native skills format | Nearly aligned | P3 |
| Context Manager | Auto-compacting | Could leverage native | P2 |
| Beads integration | Named sessions | Could sync session names | P3 |
| Constructs registry | Plugin marketplace | Could migrate to plugins | P1 |
| MCP registry | Native MCP config | Aligned | - |
| Hot-reload | Native hot-reload | Could leverage | P2 |
| Background execution | Native background | Already using | - |

---

## Recommended Actions

### Priority 1 (Immediate)

1. **Update Oracle Sources**
   - Effort: Low
   - Files: `.claude/scripts/anthropic-oracle.sh`
   - Action: Update SOURCES array with new URLs

2. **Document New Settings**
   - Effort: Low
   - Files: `CLAUDE.md`, `.loa.config.yaml`
   - Action: Add `language`, `respectGitignore`, `agent` settings

3. **Update Installation Docs**
   - Effort: Low
   - Files: `INSTALLATION.md`, `README.md`
   - Action: Use new curl/homebrew install instead of npm

### Priority 2 (Next Release - v0.14.0)

1. **Add context: fork to Heavy Skills**
   - Effort: Low
   - Files: `.claude/skills/*/index.yaml`
   - Action: Add `context: fork` to audit/review skills

2. **Leverage Skill Hot-Reload**
   - Effort: Medium
   - Files: Skills adapter, documentation
   - Action: Document hot-reload workflow for skill development

3. **Inline Hooks in Skills**
   - Effort: Medium
   - Files: `.claude/skills/*/index.yaml`
   - Action: Move hook definitions into skill frontmatter

### Priority 3 (Future)

1. **Explore Plugin Distribution**
   - Effort: High
   - Files: New plugin manifest structure
   - Action: Consider Loa as plugin marketplace

2. **Agent SDK Integration**
   - Effort: High
   - Files: New agent definitions
   - Action: Evaluate Agent SDK for custom agent building

3. **LSP Integration**
   - Effort: Medium
   - Files: MCP registry
   - Action: Add LSP configuration for major languages

---

## Version Mapping

| Claude Code | Loa | Key Changes |
|-------------|-----|-------------|
| 2.1.6 | 0.13.0 | Current |
| 2.1.0 | - | Skill hot-reload, hooks in frontmatter |
| 2.0.74 | - | LSP tool |
| 2.0.64 | - | Named sessions |
| 2.0.60 | - | Background agents |
| 2.0.20 | - | Claude Skills support |
| 2.0.12 | - | Plugin system |
| 2.0.0 | - | Native VS Code, SDK rename |

---

## Sources Analyzed

- [Claude Code CHANGELOG.md](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- [Claude Code GitHub Repository](https://github.com/anthropics/claude-code)
- [Anthropic News](https://www.anthropic.com/news)
- [Anthropic Python SDK](https://github.com/anthropics/anthropic-sdk-python)

---

## Next Oracle Run

Recommended: 2026-01-20 or when Claude Code 2.2.x releases.

---

## Appendix: New Environment Variables

From CHANGELOG analysis:

| Variable | Purpose | Version |
|----------|---------|---------|
| `CLAUDE_CODE_TMPDIR` | Override temp directory | 2.1.5 |
| `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS` | Disable background tasks | 2.1.4 |
| `FORCE_AUTOUPDATE_PLUGINS` | Force plugin updates | 2.1.2 |
| `IS_DEMO` | Hide email/org from UI | 2.1.0 |
| `CLAUDE_CODE_SHELL` | Override shell detection | 2.0.65 |
| `CLAUDE_CODE_FILE_READ_MAX_OUTPUT_TOKENS` | File read token limit | 2.1.0 |
| `CLAUDE_CODE_EXIT_AFTER_STOP_DELAY` | Auto-exit in SDK mode | 2.0.35 |
| `BASH_DEFAULT_TIMEOUT_MS` | Bash command timeout | 2.0.19 |
| `BASH_MAX_TIMEOUT_MS` | Max bash timeout | 2.0.108 |
