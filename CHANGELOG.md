# Changelog

All notable changes to Loa will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.15.0] - 2026-01-17

### Why This Release

This release removes the `/setup` phase entirely, allowing users to start with `/plan-and-analyze` immediately after cloning. THJ membership is now detected via the `LOA_CONSTRUCTS_API_KEY` environment variable instead of a marker file.

### ⚠️ Breaking Changes

- **`/setup` command removed**: No longer needed. Start directly with `/plan-and-analyze`
- **`/mcp-config` command removed**: MCP configuration is now documentation-only
- **`.loa-setup-complete` no longer created**: THJ detection uses API key presence
- **Phase 0 removed from workflow**: Workflow now starts at Phase 1

### Added

- **`is_thj_member()` function** (`.claude/scripts/constructs-lib.sh`)
  - Canonical source for THJ membership detection
  - Returns 0 when `LOA_CONSTRUCTS_API_KEY` is set and non-empty
  - Zero network dependency - environment variable check only

- **`check-thj-member.sh` script** (`.claude/scripts/check-thj-member.sh`)
  - Pre-flight check script for THJ-only commands
  - Used by `/feedback` to gate access

### Removed

- **`/setup` command** (`.claude/commands/setup.md`)
- **`/mcp-config` command** (`.claude/commands/mcp-config.md`)
- **`check_setup_complete()` function** (from `preflight.sh`)
- **`check_cached_detection()` function** (from `git-safety.sh`)
- **`is_detection_disabled()` function** (from `git-safety.sh`)

### Changed

- **All phase commands**: Removed `.loa-setup-complete` pre-flight check
  - `/plan-and-analyze` - No prerequisites, this is now the entry point
  - `/architect` - Only requires PRD
  - `/sprint-plan` - Only requires PRD and SDD
  - `/implement` - Only requires PRD, SDD, and sprint.md
  - `/review-sprint` - Unchanged (requires reviewer.md)
  - `/audit-sprint` - Unchanged (requires "All good" approval)
  - `/deploy-production` - Only requires PRD and SDD

- **`/feedback` command**: Uses script-based THJ detection
  - Now uses `check-thj-member.sh` pre-flight script
  - Error message directs OSS users to GitHub Issues
  - THJ members need `LOA_CONSTRUCTS_API_KEY` set

- **`analytics.sh`**: Updated to use `is_thj_member()` from constructs-lib.sh
  - `get_user_type()` returns "thj" or "oss" based on API key presence
  - `should_track_analytics()` delegates to `is_thj_member()`

- **`preflight.sh`**: Updated THJ detection
  - `check_user_is_thj()` now uses `is_thj_member()`
  - Sources `constructs-lib.sh` for canonical detection function

- **`git-safety.sh`**: Removed marker file detection layer
  - Template detection now uses origin URL, upstream remote, and GitHub API only
  - Removed cached detection that read from marker file

- **`check-prerequisites.sh`**: Removed marker file checks
  - All phases work without `.loa-setup-complete`
  - `setup` case removed entirely
  - `plan|prd` case now has no prerequisites

- **`.gitignore`**: Updated comment for `.loa-setup-complete`
  - Marked as legacy (v0.14.0 and earlier)
  - Entry remains for backward compatibility

### Documentation

- **README.md**: Updated Quick Start to remove `/setup` step
- **CLAUDE.md**: Removed Phase 0 from workflow table, added THJ detection note
- **PROCESS.md**: Updated overview to reflect seven-phase workflow

### Migration Guide

**For existing projects:**
- The `.loa-setup-complete` file is no longer needed
- THJ members should set `LOA_CONSTRUCTS_API_KEY` environment variable
- Existing marker files are safely ignored (not deleted)

**For new projects:**
- Clone and immediately run `/plan-and-analyze`
- THJ members: Set `LOA_CONSTRUCTS_API_KEY` for constructs access and `/feedback`
- OSS users: Full workflow access, submit feedback via GitHub Issues

## [0.14.0] - 2026-01-17

### Why This Release

This release introduces **Auto-Update Check** - automatic version checking that notifies users when updates are available. The check runs on session start via a SessionStart hook, caches results to minimize API calls, and auto-skips in CI environments.

### Added

- **Auto-Update Check** (`.claude/scripts/check-updates.sh`)
  ```bash
  check-updates.sh --notify   # Check and notify (SessionStart hook)
  check-updates.sh --check    # Force check (bypass cache)
  check-updates.sh --json     # JSON output for scripting
  check-updates.sh --quiet    # Suppress non-error output
  ```
  - Fetches latest release from GitHub API
  - Semver comparison with pre-release support
  - Cache management (24h TTL default)
  - CI environment detection (GitHub Actions, GitLab CI, Jenkins, CircleCI, Travis, Bitbucket, Azure)
  - Three notification styles: banner, line, silent
  - Major version warning highlighting

- **SessionStart Hook** (`.claude/settings.json`)
  - Runs update check automatically on Claude Code session start
  - Uses `--notify` flag for terminal-friendly output
  - Silent in CI environments

- **`/update --check` Flag**
  - Check for updates without performing update
  - `--json` flag for scripting integration
  - Returns exit code 1 when update available

- **Configuration** (`.loa.config.yaml`)
  ```yaml
  update_check:
    enabled: true                    # Master toggle
    cache_ttl_hours: 24              # Cache TTL (default: 24)
    notification_style: banner       # banner | line | silent
    include_prereleases: false       # Include pre-release versions
    upstream_repo: "0xHoneyJar/loa"  # GitHub repo to check
  ```

- **Environment Variable Overrides**
  - `LOA_DISABLE_UPDATE_CHECK=1` - Disable all checks
  - `LOA_UPDATE_CHECK_TTL=48` - Cache TTL in hours
  - `LOA_UPSTREAM_REPO=owner/repo` - Custom upstream
  - `LOA_UPDATE_NOTIFICATION=line` - Notification style

- **Comprehensive Test Suite**
  - 30 unit tests (`tests/unit/check-updates.bats`)
    - semver_compare: 10 tests
    - is_major_update: 4 tests
    - is_ci_environment: 9 tests
    - CLI arguments: 7 tests
  - 11 integration tests (`tests/integration/check-updates.bats`)
    - Full check with JSON output
    - Cache TTL behavior
    - Network failure handling
    - CI mode skipping
    - Quiet mode suppression
    - Banner notification format
    - Major version warning
    - Exit code validation

### Changed

- **CLAUDE.md**: Added Update Check section under Helper Scripts
  - Command usage with all flags
  - Exit codes documentation
  - Configuration options
  - Environment variables
  - Feature highlights

### Technical Details

- **Exit Codes**
  | Code | Meaning |
  |------|---------|
  | 0 | Up to date, disabled, or skipped |
  | 1 | Update available |
  | 2 | Error |

- **Cache Location**: `~/.loa/cache/update-check.json`

- **Network**: 2-second timeout, silent failure on errors

### Security

- All scripts use `set -euo pipefail` for safe execution
- No secrets or credentials required (public GitHub API)
- CI environment auto-detection prevents unwanted output in pipelines
- Sprint 1 & 2 security audits: **APPROVED - LETS FUCKING GO**

---

## [0.13.0] - 2026-01-12

### Why This Release

This release introduces the **Anthropic Oracle** - an automated system for monitoring Anthropic's official sources for updates relevant to Loa. Also includes research-driven improvements from Continuous-Claude-v3 and Kiro analysis, plus cross-platform compatibility fixes.

### Added

- **Anthropic Oracle** (`.claude/scripts/anthropic-oracle.sh`)
  ```bash
  anthropic-oracle.sh check      # Fetch latest Anthropic sources
  anthropic-oracle.sh sources    # List monitored URLs
  anthropic-oracle.sh history    # View check history
  anthropic-oracle.sh template   # Generate research template
  ```
  - Monitors 6 Anthropic sources: docs, changelog, API reference, blog, GitHub repos
  - 24-hour cache TTL (configurable via `ANTHROPIC_ORACLE_TTL`)
  - Interest areas: hooks, tools, context, agents, mcp, memory, skills, commands

- **Oracle Commands**
  - `/oracle` - Quick access to oracle script with workflow documentation
  - `/oracle-analyze` - Claude-assisted analysis of fetched content

- **GitHub Actions Workflow** (`.github/workflows/oracle.yml`)
  - Weekly automated checks (Mondays 9:00 UTC)
  - Creates analysis issues with structured prompts
  - Duplicate issue detection (7-day window)
  - Manual dispatch support

- **Risk Analysis Protocol** (`.claude/protocols/risk-analysis.md`)
  - Pre-mortem framework from Continuous-Claude-v3
  - Tiger/Paper Tiger/Elephant categorization
  - Two-pass verification methodology
  - Automation hooks for risk detection

- **Recommended Hooks Protocol** (`.claude/protocols/recommended-hooks.md`)
  - Claude Code hooks documentation
  - 6 recommended hook patterns (session continuity, grounding check, git safety, sprint completion, auto-test, drift detection)
  - Example scripts clearly marked as templates
  - Integration with Kiro and Continuous-Claude patterns

- **EARS Requirements Template** (`.claude/skills/discovering-requirements/resources/templates/ears-requirements.md`)
  - Easy Approach to Requirements Syntax
  - 6 patterns: Ubiquitous, Event-Driven, State-Driven, Conditional, Optional, Complex
  - PRD integration section
  - Referenced in `discovering-requirements` skill

### Changed

- **Oracle Script Cross-Platform Support**
  - Added bash 4+ version check with macOS upgrade instructions
  - Added `jq` and `curl` dependency validation
  - Follows `mcp-registry.sh` pattern for consistency

- **Documentation Updates**
  - CLAUDE.md now includes Anthropic Oracle section under Helper Scripts
  - Protocol index updated with new protocols

### Fixed

- Example hook scripts now clearly marked as "Example Only" to prevent confusion
- `.gitignore` updated to exclude `grimoires/pub/` content (except README.md)

### Security

- Oracle script uses `set -euo pipefail` for safe execution
- GitHub Actions workflow uses minimal permissions (`contents: read`, `issues: write`)
- No secrets or credentials in automated workflows
- Sprint 1 security audit: **APPROVED**

---

## [0.12.0] - 2026-01-12

### Why This Release

This release introduces the **Grimoires Restructure** - a reorganization of the grimoire directory structure for better separation of private project state and public shareable content. The new `grimoires/` directory serves as the home for all grimoires, with `grimoires/loa/` for private state and `grimoires/pub/` for public documents.

### Added

- **Grimoires Directory Structure**
  | Path | Git Status | Purpose |
  |------|------------|---------|
  | `grimoires/loa/` | Ignored | Private project state (PRD, SDD, notes, trajectories) |
  | `grimoires/pub/` | Tracked | Public documents (research, audits, shareable artifacts) |

- **Migration Tool** (`.claude/scripts/migrate-grimoires.sh`)
  ```bash
  migrate-grimoires.sh check      # Check if migration needed
  migrate-grimoires.sh plan       # Preview changes (dry-run)
  migrate-grimoires.sh run        # Execute migration
  migrate-grimoires.sh rollback   # Revert using backup
  migrate-grimoires.sh status     # Show current state
  ```
  - Backup-before-migrate pattern for safety
  - JSON output support for automation (`--json`)
  - Force mode for scripted usage (`--force`)

- **Public Grimoire Structure** (`grimoires/pub/`)
  ```
  grimoires/pub/
  ├── research/     # Research and analysis documents
  ├── docs/         # Shareable documentation
  ├── artifacts/    # Public build artifacts
  └── audits/       # Security audit reports
  ```

- **CI Template Protection**: Extended to protect `grimoires/pub/` from project-specific content in template repository

### Changed

- **Path Migration**: 134+ files updated from `loa-grimoire` to `grimoires/loa`
  - All scripts in `.claude/scripts/`
  - All skills in `.claude/skills/`
  - All commands in `.claude/commands/`
  - All protocols in `.claude/protocols/`
  - Configuration files (`.gitignore`, `.loa-version.json`, `.loa.config.yaml`)
  - Documentation (README.md, CLAUDE.md, INSTALLATION.md, PROCESS.md)

- **Update Script**: Now checks for grimoire migration after framework updates (Stage 11)

### Security

- Migration tool security audit: **APPROVED**
  - No command injection vulnerabilities (all paths hardcoded)
  - Safe shell scripting (`set -euo pipefail`)
  - Proper backup/rollback capability
  - Audit report: `grimoires/pub/audits/grimoires-restructure-audit.md`

### Migration Guide

Existing projects using `loa-grimoire/` will be prompted to migrate:

```bash
# Check if migration needed
.claude/scripts/migrate-grimoires.sh check

# Preview changes
.claude/scripts/migrate-grimoires.sh plan

# Execute migration (creates backup automatically)
.claude/scripts/migrate-grimoires.sh run

# If issues occur, rollback
.claude/scripts/migrate-grimoires.sh rollback
```

The migration tool will:
1. Create `grimoires/` directory structure
2. Move content from `loa-grimoire/` to `grimoires/loa/`
3. Update `.loa.config.yaml` and `.gitignore` references
4. Create `grimoires/pub/` with README files

### Breaking Changes

**None** - The migration tool provides a smooth upgrade path. Existing `loa-grimoire/` paths continue to work until manually migrated.

---

## [0.11.0] - 2026-01-12

### Why This Release

This release introduces **Context Management Optimization** and **Tool Search & MCP Enhancement** - two major features that improve Claude Code session management and tool discovery. Additionally, it adds a comprehensive **Claude Platform Integration** system with JSON schemas, skills adapters, and thinking trajectory logging.

### Added

- **Context Management System** (`.claude/scripts/`)
  | Script | Purpose |
  |--------|---------|
  | `context-manager.sh` | Dashboard for context lifecycle (status, preserve, compact, checkpoint, recover) |
  | `context-benchmark.sh` | Performance measurement and tracking (run, baseline, compare, history) |

- **Context Compaction Protocol** (`.claude/protocols/context-compaction.md`)
  - Defines preservation categories (ALWAYS vs COMPACTABLE)
  - Documents compaction workflow and recovery guarantees
  - Simplified checkpoint process (7 steps → 3 manual steps)

- **Tool Search & Discovery** (`.claude/scripts/tool-search-adapter.sh`)
  - Search MCP servers and Loa Constructs by name, description, scope
  - Relevance scoring: name=100, key=80, description=50, scope=30
  - Cache system with configurable TTL (~/.loa/cache/tool-search/)
  - Commands: `search`, `discover`, `cache list/clear`
  - JSON output support for automation

- **MCP Registry Search** (`.claude/scripts/mcp-registry.sh`)
  - New `search` command for finding MCP servers
  - Case-insensitive matching across name, description, scope
  - Shows configuration status in results

- **Claude Platform Integration**
  | Component | Purpose |
  |-----------|---------|
  | `.claude/schemas/` | JSON Schema validation for PRD, SDD, Sprint, Trajectory |
  | `schema-validator.sh` | CLI for validating documents against schemas |
  | `skills-adapter.sh` | Unified skill loading and invocation |
  | `thinking-logger.sh` | Trajectory logging for agent reasoning |

- **Comprehensive Test Suite** (1,795 lines across 5 test files)
  - `context-manager.bats` - 35 tests for context management
  - `tool-search-adapter.bats` - 33 tests for tool search
  - `schema-validator.bats` - Schema validation tests
  - `skills-adapter.bats` - Skills adapter tests
  - `thinking-logger.bats` - Thinking logger tests

### Changed

- **Session Continuity Protocol**: Enhanced with context manager integration (+82 lines)
- **Synthesis Checkpoint Protocol**: Simplified to 3 manual steps (+50 lines)
- **Configuration**: New sections in `.loa.config.yaml`
  ```yaml
  tool_search:
    enabled: true
    cache_ttl_hours: 24
    include_constructs: true
    default_limit: 10
    ranking:
      name_weight: 100
      key_weight: 80
      description_weight: 50
      scope_weight: 30

  context_management:
    enabled: true
    auto_checkpoint: true
    preserve_on_clear: true
  ```

- **CLAUDE.md**: Added Context Management and Tool Search documentation (+194 lines)

### Security

- All new scripts use `set -euo pipefail` for safe bash execution
- Comprehensive security audit passed (39 scripts, 626 tests)
- No hardcoded secrets, proper input validation
- Cache operations confined to user's home directory

### Breaking Changes

**None** - This release is fully backward compatible.

---

## [0.10.1] - 2026-01-04

### Why This Release

This release adds the **Loa Constructs CLI** - a command-line interface for installing packs and skills from the Loa Constructs Registry. Pack commands are now automatically symlinked to `.claude/commands/` after installation, making them immediately available.

### Added

- **`constructs-install.sh`** - New CLI for pack and skill installation
  ```bash
  constructs-install.sh pack <slug>              # Install pack from registry
  constructs-install.sh skill <vendor/slug>      # Install individual skill
  constructs-install.sh uninstall pack <slug>    # Remove a pack
  constructs-install.sh uninstall skill <slug>   # Remove a skill
  constructs-install.sh link-commands <slug|all> # Re-link pack commands
  ```

- **Automatic Command Symlinking** (Fixes #21)
  - Pack commands in `.claude/constructs/packs/{slug}/commands/` are automatically symlinked to `.claude/commands/`
  - User files are never overwritten (safety feature)
  - Existing pack symlinks are updated on reinstall

- **Skill Symlinking for Loader Discovery**
  - Pack skills symlinked to `.claude/constructs/skills/{pack}/` for loader compatibility

- **Comprehensive Test Suite**
  - 21 unit tests covering installation, symlinking, uninstall, and edge cases

### Fixed

- **#20**: Add CLI install command for Loa Constructs packs
- **#21**: Pack commands not automatically available after installation

### Directory Structure Update

```
.claude/constructs/packs/{slug}/
├── commands/           # Pack commands (auto-symlinked to .claude/commands/)
├── skills/             # Pack skills (auto-symlinked to .claude/constructs/skills/)
├── manifest.json       # Pack metadata
└── .license.json       # JWT license token
```

---

## [0.10.0] - 2026-01-03

### Why This Release

This release introduces **Loa Constructs** - a commercial skill distribution system that enables third-party skills and skill packs to be installed, validated, and loaded alongside local skills. Skills are JWT-signed with RS256, license-validated with grace periods, and support offline operation.

### Added

- **Loa Constructs Registry Integration**
  - Commercial skill distribution via `loa-constructs-api.fly.dev`
  - JWT-signed licenses with RS256 signature verification
  - Grace periods by tier: 24h (individual/pro), 72h (team), 168h (enterprise)
  - Offline operation with cached public keys
  - Skill packs for bundled skill distribution

- **New Scripts** (`.claude/scripts/`)
  | Script | Purpose |
  |--------|---------|
  | `constructs-loader.sh` | Main CLI for listing, validating, loading constructs |
  | `constructs-lib.sh` | Shared library functions for construct operations |
  | `license-validator.sh` | JWT license validation with RS256 signatures |

- **New Protocol** (`.claude/protocols/constructs-integration.md`)
  - Skill loading priority (local > override > registry > pack)
  - License validation flow with exit codes
  - Offline behavior and key caching
  - Directory structure for installed constructs

- **Auto-Gitignore for Constructs**
  - `.claude/constructs/` automatically added to `.gitignore` on install
  - Prevents accidental commit of licensed content
  - `ensure-gitignore` CLI command for manual verification

- **CI Template Protection**
  - `.claude/constructs/` added to forbidden paths in CI
  - Prevents licensed skills from being committed to template repository

- **Comprehensive Test Suite** (2700+ lines)
  - Unit tests for loader, lib, and license validator
  - Integration tests with mock API server
  - E2E tests for full workflow validation
  - Pack support and update check tests

### Changed

- **Configuration**: New `.loa.config.yaml` options
  ```yaml
  registry:
    enabled: true
    default_url: "https://loa-constructs-api.fly.dev/v1"
    validate_licenses: true
    offline_grace_hours: 24
    check_updates_on_setup: true
  ```

- **CLAUDE.md**: Added Registry Integration section with API endpoints, authentication, and CLI commands

### Directory Structure

```
.claude/constructs/
├── skills/{vendor}/{slug}/    # Installed skills
│   ├── .license.json          # JWT license token
│   ├── index.yaml             # Skill metadata
│   └── SKILL.md               # Instructions
├── packs/{name}/              # Skill packs
│   ├── .license.json          # Pack license
│   └── skills/                # Bundled skills
└── .constructs-meta.json      # Installation state
```

### Breaking Changes

**None** - This release is fully backward compatible. The constructs system is opt-in and does not affect existing local skills.

---

## [0.9.2] - 2025-12-31

### Why This Release

The `/update` command was overwriting project-specific `CHANGELOG.md` and `README.md` files with Loa framework template versions. These files define the project, not the framework, and should always be preserved during updates.

### Fixed

- **`/update` Command**: Now preserves project identity files during framework updates
  - Added `CHANGELOG.md` and `README.md` to the Merge Strategy table as preserved files
  - Added "Project Identity Files" section in Conflict Resolution guidance
  - These files are now automatically resolved with `--ours` (keep project version)
  - Updated Next Steps to link to upstream releases instead of local CHANGELOG

### Upgrade Instructions

No action required. The fix is in the `/update` command documentation itself, so future updates will properly preserve your project files.

If you previously lost your `CHANGELOG.md` or `README.md` during an update:
```bash
git checkout <commit-before-update> -- CHANGELOG.md README.md
git commit -m "fix: restore project CHANGELOG and README"
```

---

## [0.9.1] - 2025-12-30

### Why This Release

**CRITICAL UPGRADE**: Version 0.9.0 was released with project-specific artifacts (PRD, SDD, sprint plans, A2A files) that should never have been in the template. This polluted the template and caused new installations to include irrelevant documentation.

This release cleans up the template and adds strict CI guards to prevent this from happening again.

### Fixed

- **Template Pollution**: Removed all project-specific files from `loa-grimoire/`
  - Deleted: `prd.md`, `sdd.md`, `sprint.md`, `NOTES.md`
  - Deleted: All `a2a/sprint-*` directories and files
  - Deleted: `deployment/`, `reality/`, `analytics/`, `research/` contents
  - Each directory now contains only a README.md explaining its purpose

### Added

- **Template Protection CI Guard**: New GitHub Actions job that blocks forbidden files
  - Runs first, all other CI jobs depend on it passing
  - Blocks: `prd.md`, `sdd.md`, `sprint.md`, `NOTES.md`, `a2a/*`, `deployment/*`, `reality/*`, `analytics/*`, `research/*`
  - Escape hatch: `[skip-template-guard]` in commit message for exceptional cases
  - `.github/BRANCH_PROTECTION.md` documents required GitHub settings

- **Branch Protection**: GitHub API configured to enforce strict checks
  - `Template Protection` status check required
  - `Validate Framework Files` status check required
  - Admin bypass disabled (`enforce_admins: true`)

### Changed

- **`.gitignore`**: Now excludes all template-specific files by default
  - README.md files in each directory are preserved
  - Projects using Loa as a base will automatically ignore generated artifacts

### Upgrade Instructions

**If you installed v0.9.0**, you have polluted template files. To clean up:

```bash
# Pull the clean template
/update

# Or manually remove polluted files
rm -rf loa-grimoire/prd.md loa-grimoire/sdd.md loa-grimoire/sprint.md
rm -rf loa-grimoire/NOTES.md loa-grimoire/a2a/* loa-grimoire/deployment/*
rm -rf loa-grimoire/reality/* loa-grimoire/analytics/* loa-grimoire/research/*
```

**New installations** from v0.9.1+ will start clean automatically.

---

## [0.9.0] - 2025-12-27

### Why This Release

This release introduces the **Lossless Ledger Protocol** - a paradigm shift from "compact to survive" to "clear, don't compact." Instead of letting Claude's context compaction smudge your reasoning state, agents now proactively checkpoint their work to persistent ledgers before clearing context, enabling instant lossless recovery.

### Added

- **Lossless Ledger Protocol**: "Clear, Don't Compact" context management
  - Proactive `/clear` before compaction instead of reactive summarization
  - Tiered state recovery: Level 1 (~100 tokens), Level 2 (~500 tokens), Level 3 (full)
  - Session continuity across context clears with zero information loss
  - Grounding ratio enforcement (≥0.95 required before `/clear`)

- **Session Continuity Protocol** (`.claude/protocols/session-continuity.md`)
  - 7-level immutable truth hierarchy (Code → Beads → NOTES → Trajectory → Docs)
  - 3-phase session lifecycle: Start → During → Before Clear
  - Self-healing State Zone with git-based recovery
  - Lightweight identifier format for 97% token reduction

- **Grounding Enforcement Protocol** (`.claude/protocols/grounding-enforcement.md`)
  - 4 grounding types: `citation`, `code_reference`, `user_input`, `assumption`
  - Configurable enforcement levels: `strict` (blocking), `warn` (advisory), `disabled`
  - Script: `.claude/scripts/grounding-check.sh` - Calculates grounding ratio
  - Default threshold: 0.95 (95% of claims must be grounded)

- **Synthesis Checkpoint Protocol** (`.claude/protocols/synthesis-checkpoint.md`)
  - 7-step checkpoint before `/clear`: 2 blocking, 5 non-blocking
  - Step 1: Grounding verification (blocking if strict)
  - Step 2: Negative grounding ghost detection (blocking)
  - Steps 3-7: Decision sync, Bead update, handoff log, decay advisory, EDD verify
  - Script: `.claude/scripts/synthesis-checkpoint.sh`

- **Attention Budget Protocol** (`.claude/protocols/attention-budget.md`)
  - Traffic light system: Green (0-5k), Yellow (5-15k), Red (>15k tokens)
  - Delta-synthesis at Yellow threshold
  - Advisory-only (doesn't block)

- **JIT Retrieval Protocol** (`.claude/protocols/jit-retrieval.md`)
  - Lightweight identifiers: `${PROJECT_ROOT}/path:lines | purpose | timestamp`
  - 97% token reduction vs embedding full code blocks
  - `ck` semantic search integration with grep fallback

- **Self-Healing State Zone**
  - Script: `.claude/scripts/self-heal-state.sh`
  - Recovery priority: git history → git checkout → template
  - Automatic recovery of NOTES.md, trajectory/, .beads/

- **Comprehensive Test Suite** (127 tests)
  - 65+ unit tests for grounding-check, synthesis-checkpoint, self-heal-state
  - 22 integration tests for session lifecycle
  - 30+ edge case tests (zero-claim, corrupted data, missing files)
  - 10 performance benchmarks with PRD KPI validation

- **UAT Validation Script** (`.claude/scripts/validate-prd-requirements.sh`)
  - Validates all 11 Functional Requirements (FR-1 through FR-11)
  - Validates 2 Integration Requirements (IR-1, IR-2)
  - 45 automated checks with pass/fail/warning output

- **CI/CD Validation** (`.claude/scripts/check-loa.sh` enhanced)
  - `check_v090_protocols()` - Validates 5 protocol files
  - `check_v090_scripts()` - Validates 3 scripts (executable, shellcheck)
  - `check_v090_config()` - Validates grounding configuration
  - `check_notes_template()` - Validates NOTES.md sections

### Changed

- **NOTES.md Schema Extended**: New required sections
  - `## Session Continuity` - Critical context (~100 tokens)
  - `## Lightweight Identifiers` - Code references table
  - `## Decision Log` - Timestamped decisions with grounding

- **Trajectory Logging Enhanced**: New entry types
  - `session_handoff` - Context passed to next session
  - `negative_grounding` - Ghost feature detection
  - `test_scenario` - EDD verification entries

- **Configuration**: New `.loa.config.yaml` options
  ```yaml
  grounding:
    enforcement: warn    # strict | warn | disabled
    threshold: 0.95      # 0.00-1.00
  ```

### Technical Details

- **Performance Targets Met**
  | Metric | Target | Achieved |
  |--------|--------|----------|
  | Session recovery | <30s | ✅ |
  | Level 1 recovery | ~100 tokens | ✅ |
  | Grounding ratio | ≥0.95 | ✅ |
  | Token reduction (JIT) | 97% | ✅ |
  | Test coverage | >80% | ✅ 127 tests |

- **Sprints Completed**: 4 sprints, all approved
  - Sprint 1: Foundation & Core Protocols
  - Sprint 2: Enforcement Layer
  - Sprint 3: Integration Layer
  - Sprint 4: Quality & Polish

### Breaking Changes

**None** - This release is fully backward compatible. New protocols are additive.

---


## [0.8.0] - 2025-12-27

### Why This Release

This release adds **optional semantic code search** via the `ck` tool, enabling dramatically improved code understanding while maintaining full backward compatibility. The enhancement is **completely invisible** to users—your workflow remains unchanged whether or not you have `ck` installed.

### Added

- **Semantic Code Search Integration** (optional)
  - Vector-based search using nomic-v1.5 embeddings via `ck` tool
  - <500ms search latency on repositories up to 1M LOC
  - 80-90% cache hit rate with delta reindexing
  - Automatic fallback to grep when `ck` unavailable

- **Ghost Feature Detection**
  - Identifies documented but unimplemented features
  - Uses Negative Grounding Protocol (2+ diverse queries returning 0 results)
  - Creates Beads issues for discovered liabilities (if `bd` installed)

- **Shadow System Classification**
  - Identifies undocumented code in repositories
  - Classifies as Orphaned, Drifted, or Partial
  - Generates actionable drift reports

- **8 New Protocol Documents** (`.claude/protocols/`)
  - `preflight-integrity.md` - Integrity verification before operations
  - `tool-result-clearing.md` - Attention budget management
  - `trajectory-evaluation.md` - Agent reasoning audit (enhanced)
  - `negative-grounding.md` - Ghost feature detection protocol
  - `search-fallback.md` - Graceful degradation strategy
  - `citations.md` - Word-for-word citation requirements
  - `self-audit-checkpoint.md` - Pre-completion validation
  - `edd-verification.md` - Evaluation-Driven Development protocol

- **6 New Scripts** (`.claude/scripts/`)
  - `search-orchestrator.sh` - Unified search interface
  - `search-api.sh` - Search API functions (semantic_search, hybrid_search, regex_search)
  - `filter-search-results.sh` - Result deduplication and relevance filtering
  - `compact-trajectory.sh` - Trajectory log compression
  - `validate-protocols.sh` - Protocol documentation validation
  - `validate-ck-integration.sh` - CI/CD validation script (42 checks)

- **Test Suite** (127 total tests)
  - 79 unit tests for core scripts
  - 22 integration tests for /ride workflow
  - 26 edge case tests for error handling
  - Performance benchmarking with PRD target validation

- **Documentation**
  - `RELEASE_NOTES_CK_INTEGRATION.md` - Detailed release notes
  - `MIGRATION_GUIDE_CK.md` - Step-by-step migration guide
  - Updated `INSTALLATION.md` with ck installation instructions
  - Updated `README.md` with semantic search mentions

### Changed

- **`/ride` Command**: Enhanced with semantic analysis
  - Ghost Feature detection in drift report
  - Shadow System classification
  - Improved code reality extraction

- **`/setup` Command**: Shows ck installation status
  - Displays version if installed
  - Provides installation instructions if missing

- **`.gitignore`**: New entries
  - `.ck/` - Semantic search index directory
  - `.beads/` - Beads issue tracking
  - `loa-grimoire/a2a/trajectory/` - Agent reasoning logs

### Technical Details

- **Performance Targets Met**
  | Metric | Target | Achieved |
  |--------|--------|----------|
  | Search Speed (1M LOC) | <500ms | ✅ |
  | Cache Hit Rate | 80-90% | ✅ |
  | Grounding Ratio | ≥0.95 | ✅ |
  | User Experience Parity | 100% | ✅ |

- **Invisible Enhancement Pattern**: All commands work identically with or without `ck` installed. No mentions of "semantic search", "ck", or "fallback" in agent output.

### Breaking Changes

**None** - This release is fully backward compatible.

### Installation (Optional)

```bash
# Install ck for semantic search
cargo install ck-search

# Install bd for issue tracking
npm install -g beads-cli

# Both tools are optional - Loa works perfectly without them
```

---

## [0.7.0] - 2025-12-22

### Why This Release

This release introduces the **Mount & Ride** workflow for existing codebases. Instead of requiring a full discovery interview, developers can now mount Loa onto any repository and "ride" through the code to generate evidence-grounded documentation automatically.

### Added

- **`/mount` Command**: Install Loa framework onto existing repositories
  - Configures upstream remote for updates
  - Installs System Zone with integrity checksums
  - Initializes State Zone structure
  - Optional stealth mode (no commits)
  - Optional Beads initialization skip

- **`/ride` Command**: Analyze codebase and generate evidence-grounded docs
  - 10-phase analysis workflow
  - Code extraction: routes, models, dependencies, tech debt
  - Three-way drift analysis: Code vs Docs vs Context
  - Evidence-grounded PRD/SDD generation
  - Legacy documentation inventory and deprecation
  - Governance audit (CHANGELOG, CONTRIBUTING, SECURITY)
  - Trajectory self-audit for hallucination detection

- **Change Validation Protocol** (`.claude/protocols/change-validation.md`)
  - Pre-implementation validation checklist
  - File reference validation
  - Function/method existence verification
  - Dependency validation
  - Breaking change detection
  - Three validation levels (quick, standard, deep)

- **New Scripts**
  - `.claude/scripts/detect-drift.sh` - Quick/full drift detection between code and docs
  - `.claude/scripts/validate-change-plan.sh` - Validate sprint plans against codebase reality

### Changed

- Documentation updated to reference Mount & Ride workflow
- Command reference tables include `/mount` and `/ride`
- Helper scripts list expanded with new utilities

---

## [0.6.0] - 2025-12-22

### Why This Release

This release transforms Loa from a "fork-and-modify template" into an **enterprise-grade managed scaffolding framework** inspired by AWS Projen, Copier, and Google's ADK. The goal is to eliminate merge hell, enable painless updates, and provide ADK-level agent observability.

### Added

- **Three-Zone Model**: Clear ownership boundaries for files
  | Zone | Path | Owner | Permission |
  |------|------|-------|------------|
  | System | `.claude/` | Framework | Immutable, checksum-protected |
  | State | `loa-grimoire/`, `.beads/` | Project | Read/Write |
  | App | `src/`, `lib/`, `app/` | Developer | Read (write requires confirmation) |

- **Projen-Level Synthesis Protection**: System Zone integrity enforcement
  - SHA-256 checksums for all System Zone files (`.claude/checksums.json`)
  - Three enforcement levels: `strict`, `warn`, `disabled`
  - CI validation script: `.claude/scripts/check-loa.sh`

- **Copier-Level Migration Gates**: Safe framework updates
  - Fetch → Validate → Migrate → Swap pattern
  - Atomic swap with automatic rollback on failure
  - User overrides preserved in `.claude/overrides/`
  - New script: `.claude/scripts/update.sh`

- **ADK-Level Trajectory Evaluation**: Agent reasoning audit
  - JSONL trajectory logs in `loa-grimoire/a2a/trajectory/`
  - Grounding types: `citation`, `code_reference`, `assumption`, `user_input`
  - Evaluation-Driven Development (EDD): 3 test scenarios before task completion
  - New protocol: `.claude/protocols/trajectory-evaluation.md`

- **Structured Agentic Memory**: Persistent context across sessions
  - `loa-grimoire/NOTES.md` with standardized sections
  - Tool Result Clearing for attention budget management
  - New protocol: `.claude/protocols/structured-memory.md`

- **One-Command Installation**: Mount Loa onto existing repositories
  - `curl -fsSL .../mount-loa.sh | bash`
  - Handles remote setup, zone syncing, checksum generation
  - New script: `.claude/scripts/mount-loa.sh`

- **Version Manifest**: Schema tracking and migration support
  - `.loa-version.json` with framework version, schema version, zone definitions
  - Migration tracking for breaking changes
  - Integrity verification timestamps

- **User Configuration File**: Framework-safe customization
  - `.loa.config.yaml` (never modified by updates)
  - Persistence mode: `standard` or `stealth`
  - Integrity enforcement level
  - Memory and EDD settings

- **New Documentation**
  - `INSTALLATION.md`: Detailed installation, customization, troubleshooting guide

### Changed

- **All 8 SKILL.md Files Updated** with managed scaffolding integration:
  - Zone frontmatter for boundary enforcement
  - Integrity pre-check before execution
  - Factual grounding requirements (cite sources or flag as `[ASSUMPTION]`)
  - Structured memory protocol (read NOTES.md on start, log decisions)
  - Tool Result Clearing for attention budget management
  - Trajectory logging for audit

- **README.md**: Rewritten for v0.6.0
  - Three-zone model documentation
  - Managed scaffolding features
  - Updated quick start with mount-loa.sh

- **CLAUDE.md**: Added managed scaffolding architecture
  - Zone permissions table
  - Protocol references
  - Customization via overrides

- **PROCESS.md**: Added new protocol sections
  - Structured Agentic Memory section
  - Trajectory Evaluation section
  - Updated helper scripts list

### Technical Details

- **yq Compatibility**: Scripts support both mikefarah/yq (Go) and kislyuk/yq (Python)
- **Checksum Algorithm**: SHA-256 for integrity verification
- **Migration Pattern**: Blocking migrations with rollback support
- **Backup Retention**: 3 most recent `.claude.backup.*` directories kept

---

## [0.5.0] - 2025-12-21

### Added

- **Beads Integration**: Sprint lifecycle state management via `bd` CLI
  - Sprint state tracking in `.beads/` directory
  - Automatic bead creation on sprint start
  - State transitions: `pending` → `active` → `review` → `audit` → `done`
  - New script: `.claude/scripts/check-beads.sh`

### Changed

- Sprint commands now create/update beads for state tracking
- `/implement`, `/review-sprint`, `/audit-sprint` update bead status

---

## [0.4.0] - 2025-12-21

### Why This Release

This release delivers a major architectural refactor based on Anthropic's recommendations for Claude Code skills development. The focus is on action-oriented naming, modular architecture, and extracting deterministic logic to reusable scripts—making skills more maintainable and reducing context overhead.

### Added

- **v4 Command Architecture**: Thin routing layer with YAML frontmatter
  - `agent:` and `agent_path:` fields for skill routing
  - `command_type:` for special commands (wizard, survey, git)
  - `pre_flight:` validation checks before execution
  - `context_files:` with prioritized loading and variable substitution

- **3-Level Skills Architecture**: Modular structure for all 8 agents
  - Level 1: `index.yaml` - Metadata and triggers (~100 tokens)
  - Level 2: `SKILL.md` - KERNEL instructions (<500 lines)
  - Level 3: `resources/` - Templates, scripts, references (loaded on-demand)

- **Context-First Discovery**: `/plan-and-analyze` now ingests existing documentation
  - Auto-scans `loa-grimoire/context/` for `.md` files before interviewing
  - Presents understanding with source citations before asking questions
  - Only asks about gaps, ambiguities, and strategic decisions
  - Parallel ingestion for large context (>2000 lines)
  - New script: `.claude/scripts/assess-discovery-context.sh`

- **8 New Helper Scripts** (`.claude/scripts/`)
  | Script | Purpose |
  |--------|---------|
  | `check-feedback-status.sh` | Sprint feedback state detection |
  | `validate-sprint-id.sh` | Sprint ID format validation |
  | `check-prerequisites.sh` | Phase prerequisite checking |
  | `assess-discovery-context.sh` | Context size assessment |
  | `context-check.sh` | Parallel execution thresholds |
  | `preflight.sh` | Pre-flight validation functions |
  | `analytics.sh` | Analytics helpers (THJ only) |
  | `git-safety.sh` | Template detection utilities |

- **Protocol Documentation** (`.claude/protocols/`)
  - `git-safety.md` - Template detection, warning flow, remediation
  - `analytics.md` - THJ-only tracking, schema definitions
  - `feedback-loops.md` - A2A communication, approval markers

- **Context Directory** (`loa-grimoire/context/`)
  - New location for pre-discovery documentation
  - Template README with suggested file structure
  - Supports nested directories and any `.md` files

### Changed

- **Skill Naming Convention**: All 8 skills renamed from role-based to action-based (gerund form)
  | Old Name | New Name |
  |----------|----------|
  | `prd-architect` | `discovering-requirements` |
  | `architecture-designer` | `designing-architecture` |
  | `sprint-planner` | `planning-sprints` |
  | `sprint-task-implementer` | `implementing-tasks` |
  | `senior-tech-lead-reviewer` | `reviewing-code` |
  | `paranoid-auditor` | `auditing-security` |
  | `devops-crypto-architect` | `deploying-infrastructure` |
  | `devrel-translator` | `translating-for-executives` |

- **Documentation Streamlining**: Reduced CLAUDE.md from ~1700 to ~200 lines
  - Detailed specifications moved to `.claude/protocols/`
  - Single source of truth principle enforced
  - Command tables reference skill files for details

- **discovering-requirements Skill**: Complete rewrite for context-first workflow
  - Phase -1: Context Assessment (runs script)
  - Phase 0: Context Synthesis with XML context map
  - Phase 0.5: Targeted Interview for gaps only
  - Phases 1-7: Conditional based on context coverage
  - Full source tracing in PRD output

- **Parallel Execution Thresholds**: Standardized across skills
  | Skill | SMALL | MEDIUM | LARGE |
  |-------|-------|--------|-------|
  | discovering-requirements | <500 | 500-2000 | >2000 |
  | reviewing-code | <3,000 | 3,000-6,000 | >6,000 |
  | auditing-security | <2,000 | 2,000-5,000 | >5,000 |
  | implementing-tasks | <3,000 | 3,000-8,000 | >8,000 |
  | deploying-infrastructure | <2,000 | 2,000-5,000 | >5,000 |

### Breaking Changes

- **Skill Names Renamed**: All 8 skills have new names (see Changed section)
  - Custom commands referencing old names will need updates
  - Automation scripts using skill names must be migrated
  - Migration script available: `.claude/scripts/migrate-skill-names.sh`

### Migration Guide

If you have custom commands or scripts referencing old skill names:

```bash
# Run the migration script on your custom files
./.claude/scripts/migrate-skill-names.sh --check  # Preview changes
./.claude/scripts/migrate-skill-names.sh          # Apply changes
```

Or manually update references using this mapping:
- `prd-architect` → `discovering-requirements`
- `architecture-designer` → `designing-architecture`
- `sprint-planner` → `planning-sprints`
- `sprint-task-implementer` → `implementing-tasks`
- `senior-tech-lead-reviewer` → `reviewing-code`
- `paranoid-auditor` → `auditing-security`
- `devops-crypto-architect` → `deploying-infrastructure`
- `devrel-translator` → `translating-for-executives`

### Technical Details

- **Command Files Updated**: 10 commands with new skill references
- **Agent Files Renamed**: 8 agent files to match new naming
- **Index Files Updated**: 8 index.yaml files with gerund names
- **GitHub Templates Updated**: Issue templates reference new names
- All references to old skill names migrated throughout codebase

---

## [0.3.0] - 2025-12-20

### Why This Release

Claude Code has a tendency to proactively suggest git operations—committing changes, creating PRs, and pushing to remotes—which can be problematic when working in forked repositories. Developers using Loa as a template for their own projects were at risk of accidentally pushing proprietary code to the public upstream repository (`0xHoneyJar/loa`).

This release introduces comprehensive safety rails to prevent these accidents while still enabling intentional contributions back to the framework.

### Added
- **Git Safety Protocol**: Multi-layer protection against accidental pushes to upstream template repository
  - 4-layer template detection system (origin URL, upstream remote, loa remote, GitHub API)
  - Automatic detection during `/setup` with results stored in marker file
  - Warnings before push/PR operations targeting upstream
  - Prevents accidentally leaking project-specific code to the public Loa repository

- **`/contribute` command**: Guided OSS contribution workflow for contributing back to Loa
  - Pre-flight checks (feature branch, clean working tree, upstream remote)
  - Standards checklist (clean commits, no secrets, tests, DCO)
  - Automated secrets scanning with common patterns (API keys, tokens, credentials)
  - DCO sign-off verification with fix guidance
  - Guided PR creation with proper formatting
  - Handles both fork-based and direct repository contributions

- **Template detection in `/setup`**: New Phase 0.5 detects fork/template relationships
  - Runs before user-type selection
  - Displays safety notice when template detected
  - Stores detection metadata in `.loa-setup-complete` marker file

- **`/config` command**: Post-setup MCP server reconfiguration (THJ only)
  - Allows adding/removing MCP integrations after initial setup
  - Shows currently configured servers
  - Updates marker file with new configuration

### Changed
- **Setup marker file schema**: Now includes `template_source` object with detection metadata
  ```json
  {
    "template_source": {
      "detected": true,
      "repo": "0xHoneyJar/loa",
      "detection_method": "origin_url",
      "detected_at": "2025-12-20T10:00:00Z"
    }
  }
  ```
- **CLAUDE.md**: Added Git Safety Protocol documentation and `/contribute` command reference
- **CONTRIBUTING.md**: Updated with contribution workflow using `/contribute` command
- **Documentation**: Updated setup flow diagrams and command reference tables

### Security
- **Secrets scanning**: `/contribute` scans for common secret patterns before PR creation
  - AWS access keys (AKIA...)
  - GitHub tokens (ghp_...)
  - Slack tokens (xox...)
  - Private keys (-----BEGIN PRIVATE KEY-----)
  - Generic password/secret/api_key patterns
- **DCO enforcement**: Contribution workflow verifies Developer Certificate of Origin sign-off
- **Template isolation**: Prevents accidental code leakage from forked projects to upstream

---

## [0.2.0] - 2025-12-19

### Added
- **`/setup` command**: First-time onboarding workflow
  - Guided MCP server configuration (GitHub, Linear, Vercel, Discord, web3-stats)
  - Project initialization (git user info, project name detection)
  - Creates `.loa-setup-complete` marker file
  - Setup enforcement: `/plan-and-analyze` now requires setup completion
- **`/feedback` command**: Developer experience survey
  - 4-question survey with progress indicators
  - Linear integration: posts to "Loa Feedback" project
  - Analytics attachment: includes usage.json in feedback
  - Pending feedback safety net: saves locally before submission
- **`/update` command**: Framework update mechanism
  - Pre-flight checks (clean working tree, remote verification)
  - Fetch, preview, and confirm workflow
  - Merge conflict guidance per file type
  - CHANGELOG excerpt display after update
- **Analytics system**: Usage tracking for feedback context
  - `loa-grimoire/analytics/usage.json` for raw metrics
  - `loa-grimoire/analytics/summary.md` for human-readable summary
  - Tracks: phases, sprints, reviews, audits, deployments
  - Non-blocking: failures logged but don't interrupt workflows
  - Opt-in sharing: only sent via `/feedback` command

### Changed
- **Fresh template**: Removed all generated loa-grimoire content (PRD, SDD, sprint plans, A2A files) so new projects start clean
- All phase commands now update analytics on completion
- `/plan-and-analyze` blocks if setup marker is missing
- `/deploy-production` suggests running `/feedback` after deployment
- Documentation updated: CLAUDE.md, PROCESS.md, README.md
- Repository structure now includes `loa-grimoire/analytics/` directory
- `.gitignore` updated with setup marker and pending feedback entries

### Directory Structure
```
loa-grimoire/
├── analytics/           # NEW: Usage tracking
│   ├── usage.json       # Raw usage metrics
│   ├── summary.md       # Human-readable summary
│   └── pending-feedback.json # Pending submissions (gitignored)
└── ...

.loa-setup-complete      # NEW: Setup marker (gitignored)
```

---

## [0.1.0] - 2025-12-19

### Added
- Initial release of Loa agent-driven development framework
- 8 specialized AI agents (the Loa):
  - **prd-architect** - Product requirements discovery and PRD creation
  - **architecture-designer** - System design and SDD creation
  - **sprint-planner** - Sprint planning and task breakdown
  - **sprint-task-implementer** - Implementation with feedback loops
  - **senior-tech-lead-reviewer** - Code review and quality gates
  - **devops-crypto-architect** - Production deployment and infrastructure
  - **paranoid-auditor** - Security and quality audits
  - **devrel-translator** - Technical to executive translation
- 10 slash commands for workflow orchestration:
  - `/plan-and-analyze` - PRD creation
  - `/architect` - SDD creation
  - `/sprint-plan` - Sprint planning
  - `/implement` - Sprint implementation
  - `/review-sprint` - Code review
  - `/audit-sprint` - Sprint security audit
  - `/deploy-production` - Production deployment
  - `/audit` - Codebase security audit
  - `/audit-deployment` - Deployment infrastructure audit
  - `/translate` - Executive translation
- Agent-to-Agent (A2A) communication system
- Dual quality gates (code review + security audit)
- Background execution mode for parallel agent runs
- MCP server integrations (Linear, GitHub, Vercel, Discord, web3-stats)
- `loa-grimoire/` directory for Loa process artifacts
- `app/` directory for generated application code
- Comprehensive documentation (PROCESS.md, CLAUDE.md)
- Secret scanning workflow (TruffleHog, GitLeaks)
- AGPL-3.0 licensing

### Directory Structure
```
app/                    # Application source code (generated)
loa-grimoire/           # Loa process artifacts
├── prd.md              # Product Requirements Document
├── sdd.md              # Software Design Document
├── sprint.md           # Sprint plan
├── a2a/                # Agent-to-agent communication
└── deployment/         # Production infrastructure docs
```

[0.14.0]: https://github.com/0xHoneyJar/loa/releases/tag/v0.14.0
[0.13.0]: https://github.com/0xHoneyJar/loa/releases/tag/v0.13.0
[0.12.0]: https://github.com/0xHoneyJar/loa/releases/tag/v0.12.0
[0.11.0]: https://github.com/0xHoneyJar/loa/releases/tag/v0.11.0
[0.10.1]: https://github.com/0xHoneyJar/loa/releases/tag/v0.10.1
[0.10.0]: https://github.com/0xHoneyJar/loa/releases/tag/v0.10.0
[0.9.2]: https://github.com/0xHoneyJar/loa/releases/tag/v0.9.2
[0.9.1]: https://github.com/0xHoneyJar/loa/releases/tag/v0.9.1
[0.9.0]: https://github.com/0xHoneyJar/loa/releases/tag/v0.9.0
[0.8.0]: https://github.com/0xHoneyJar/loa/releases/tag/v0.8.0
[0.7.0]: https://github.com/0xHoneyJar/loa/releases/tag/v0.7.0
[0.6.0]: https://github.com/0xHoneyJar/loa/releases/tag/v0.6.0
[0.5.0]: https://github.com/0xHoneyJar/loa/releases/tag/v0.5.0
[0.4.0]: https://github.com/0xHoneyJar/loa/releases/tag/v0.4.0
[0.3.0]: https://github.com/0xHoneyJar/loa/releases/tag/v0.3.0
[0.2.0]: https://github.com/0xHoneyJar/loa/releases/tag/v0.2.0
[0.1.0]: https://github.com/0xHoneyJar/loa/releases/tag/v0.1.0
