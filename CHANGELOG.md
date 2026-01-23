# Changelog

All notable changes to Loa will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.5.0] - 2026-01-23 — Recursive JIT Context System

### Why This Release

Introduces the **Recursive JIT Context System** — a comprehensive solution for context management in long-running agent sessions. This release addresses the fundamental challenge of Claude Code's automatic context summarization by providing semantic caching, intelligent condensation, and continuous synthesis to persistent ledgers.

*"The code remembers what the context forgets."*

### Added

- **Recursive JIT Context System** (`.claude/scripts/`)
  - `cache-manager.sh` — Semantic result caching with mtime-based invalidation
    - LRU eviction, TTL expiration (30 days default)
    - Secret pattern detection on write
    - Integrity verification with SHA256 hashes
  - `condense.sh` — Result condensation engine
    - Strategies: `structured_verdict` (~50 tokens), `identifiers_only` (~20), `summary` (~100)
    - Full result externalization to `.claude/cache/full/`
  - `early-exit.sh` — Parallel subagent coordination
    - File-based "first-to-finish wins" protocol
    - Session management, agent registration, result passing
  - `synthesize-to-ledger.sh` — Continuous synthesis trigger
    - Writes decisions to NOTES.md and trajectory at RLM trigger points
    - Survives Claude Code's automatic context summarization

- **Continuous Synthesis** — Anti-platform-summarization defense
  - RLM operations (cache set, condense, early-exit) trigger automatic ledger writes
  - Decisions externalized to NOTES.md Decision Log
  - Trajectory entries for audit trail
  - Optional bead comment injection (when `br` available)
  - Configuration in `.loa.config.yaml`:
    ```yaml
    recursive_jit:
      continuous_synthesis:
        enabled: true
        on_cache_set: true
        on_condense: true
        on_early_exit: true
        update_bead: true
    ```

- **Post-Upgrade Health Check** (`upgrade-health-check.sh`)
  - Detects bd → br migration status
  - Finds deprecated references in settings.local.json
  - Identifies new config sections available
  - Suggests recommended permissions for new features
  - Auto-fix mode: `--fix` flag applies safe corrections
  - Runs automatically after `update.sh`

- **Upgrade Completion Banner** (`upgrade-banner.sh`)
  - Cyberpunk-themed ASCII art completion message
  - Rotating quotes from Neuromancer, Blade Runner, The Matrix, Ghost in the Shell
  - Original Loa-themed quotes about synthesis and context management
  - CHANGELOG highlights parsing (when available)
  - Mount mode vs upgrade mode with appropriate next steps
  - JSON output for scripting: `--json`

- **beads_rust Integration** with Continuous Synthesis
  - Active bead detection from NOTES.md Session Continuity
  - Automatic `[Synthesis] <message>` comment injection
  - Redundant persistence: NOTES.md + trajectory + bead comments

- **Protocol Documentation**
  - `.claude/protocols/recursive-context.md` — Full RLM system documentation
  - Architecture diagrams, integration patterns, configuration reference

### Changed

- **Opt-Out Defaults** — All RLM features now enabled by default
  - Scripts use `// true` fallbacks instead of `// false`
  - Users can disable features in config rather than needing to enable them
  - Ships with sane defaults for immediate benefit

- **CLAUDE.md** — Updated with Recursive JIT Context section
  - New scripts documented in Helper Scripts table
  - Protocol references added

### Technical Details

- **Two-Level Context Management**
  - Platform level: Claude Code's automatic summarization (outside Loa's control)
  - Framework level: Loa's protocols for proactive externalization (full control)
  - Solution: Write to ledgers BEFORE platform summarization occurs

- **Performance Targets**
  - Cache hit rate: >30% over 30 days
  - Context reduction: 30-40% via condensation
  - Cache lookup: <100ms
  - Condensation: <50ms

### Migration Notes

No migration required. All features are enabled by default and backward compatible.

Run `upgrade-health-check.sh` after upgrading to check for:
- Legacy `bd` references that should be `br`
- Missing config sections
- Recommended permission additions

## [1.4.0] - 2026-01-22 — Clean Upgrade & CLAUDE.md Diet

### Why This Release

Eliminates git history pollution during framework upgrades and dramatically reduces CLAUDE.md size for better Claude Code context efficiency.

### Added

- **Clean Upgrade Commits**: Framework upgrades now create single atomic commits
  - `mount-loa.sh` and `update.sh` create conventional commits: `chore(loa): upgrade framework v{OLD} -> v{NEW}`
  - Version tags: `loa@v{VERSION}` for easy upgrade history tracking
  - Query history with `git tag -l 'loa@*'`
  - Rollback with `git revert HEAD` or `git checkout loa@v{VERSION} -- .claude`

- **Upgrade Configuration**: New `.loa.config.yaml` section
  ```yaml
  upgrade:
    auto_commit: true   # Create git commit after upgrade
    auto_tag: true      # Create version tag
    commit_prefix: "chore"  # Conventional commit prefix
  ```

- **`--no-commit` Flag**: Skip automatic commit creation
  - `mount-loa.sh --no-commit`
  - `update.sh --no-commit`

- **Protocol Documentation**
  - `.claude/protocols/helper-scripts.md` - Comprehensive script documentation
  - `.claude/protocols/upgrade-process.md` - 12-stage upgrade workflow documentation

### Changed

- **CLAUDE.md**: Reduced from 1,157 lines to 321 lines (72% reduction)
  - Core instructions remain in CLAUDE.md
  - Detailed documentation moved to protocol files
  - References added for JIT loading when needed

### Technical Details

- **Stealth Mode**: No commits created in stealth persistence mode
- **Tag Handling**: Existing tags are not overwritten
- **Dirty Tree**: Warnings shown but upgrades continue
- **Config Priority**: CLI flags > config file > defaults

### Migration Notes

No migration required. Existing installations will gain clean upgrade behavior automatically on next update.

## [1.3.1] - 2026-01-20 — Gitignore Hardening

### Why This Release

Security and hygiene improvements to ensure sensitive files and project-specific state are never accidentally committed.

### Added

- **Simstim `.gitignore`** — Protects user-specific configuration
  - `simstim.toml` (contains Telegram chat IDs)
  - Audit logs and Python artifacts

- **Enhanced Beads exclusions** — Runtime files now properly ignored
  - `daemon.lock` (process lock)
  - `.local_version` (local br version)
  - `beads.db` (SQLite database)
  - `*.meta.json` (sync metadata)
  - `*.jsonl` (task graph - template repo only)

- **Archive exclusion** — `grimoires/loa/archive/` now ignored
  - Project-specific development cycle history
  - Prevents template pollution

### Security

All user-specific and runtime files are now protected from accidental commits.

## [1.3.0] - 2026-01-20 — Simstim Telegram Bridge

### Why This Release

This release introduces **Simstim**, a Telegram bridge for remote monitoring and control of Loa (Claude Code) sessions. **Ported from [takopi.dev](https://takopi.dev/)** and adapted for Loa workflows. Named after the neural interface technology in William Gibson's Sprawl trilogy, Simstim lets you experience your AI agent workflows from anywhere—approve permissions, monitor phases, and control execution from your phone.

### Added

- **Simstim Package** (`simstim/`)
  - Full Python package with CLI interface
  - Telegram bot integration for permission relay
  - Auto-approve policy engine with pattern matching
  - Phase transition and quality gate notifications
  - Offline queue with automatic reconnection
  - Comprehensive JSONL audit logging

- **Permission Features**
  - One-tap approve/deny from Telegram
  - Configurable timeout with default action
  - Rate limiting per user
  - Denial backoff for abuse prevention

- **Policy Engine**
  - TOML-based policy configuration
  - Pattern matching for file paths and commands
  - Allowlist/blocklist support
  - Fail-closed defaults for security

- **Monitoring Capabilities**
  - Phase transition notifications
  - Quality gate alerts (review/audit)
  - NOTES.md update detection
  - Sprint progress tracking

### Security Hardening

Comprehensive security audit identified and remediated 9 vulnerabilities:

| Finding | Severity | CWE | Fix |
|---------|----------|-----|-----|
| SIMSTIM-001 | CRITICAL | CWE-522 | SafeSecretStr for token protection |
| SIMSTIM-002 | CRITICAL | CWE-78 | Command allowlist, shell=False enforcement |
| SIMSTIM-003 | HIGH | CWE-285 | Fail-closed authorization by default |
| SIMSTIM-004 | HIGH | CWE-312 | Credential redaction in notifications |
| SIMSTIM-005 | HIGH | CWE-943 | Literal-only policy value comparisons |
| SIMSTIM-006 | MEDIUM | CWE-208 | Constant-time rate limit evaluation |
| SIMSTIM-007 | MEDIUM | CWE-200 | Extended redaction (30+ patterns, JWT, AWS keys) |
| SIMSTIM-008 | MEDIUM | CWE-778 | HMAC-SHA256 audit log hash chain |
| SIMSTIM-009 | MEDIUM | CWE-74 | Environment variable whitelist |

**Security Grade: A** (Production-ready)

**221 Security Tests** covering all vulnerability remediations.

### Technical Details

- **Architecture**: Bridge pattern with event queue
- **Dependencies**: Python 3.11+, python-telegram-bot, pydantic
- **Configuration**: TOML-based with environment variable expansion
- **Logging**: Structured JSONL with tamper-evident hash chains

### Installation

```bash
pip install simstim
simstim config --init
simstim start -- /implement sprint-1
```

See `simstim/README.md` for full documentation.

## [1.2.0] - 2026-01-20 — Beads Migration & Security Hardening

### Why This Release

This release introduces comprehensive bd → br migration tooling for projects transitioning from Python beads to beads_rust, plus security hardening that brings the framework to Grade A audit status.

### Added

- **Migration Tooling** (`migrate-to-br.sh`)
  - Full bd → br migration script with schema compatibility handling
  - Prefix normalization for mixed JSONL files (e.g., `arrakis-*` → `loa-*`)
  - Daemon cleanup and lockfile handling
  - `--dry-run` mode for safe preview
  - `--force` mode for re-migration
  - Automatic backup creation

- **Enhanced Beads Detection** (`check-beads.sh` rewrite)
  - Detects bd vs br installation
  - Returns `MIGRATION_NEEDED` (exit 3) when bd found
  - JSON output mode for scripting (`--json`)
  - Detailed status reporting

- **Symlink Validation** (`constructs-install.sh`)
  - New `validate_symlink_target()` function
  - Prevents path traversal attacks via symlinks
  - Validates targets stay within constructs directory

- **Config Validation** (`update.sh`)
  - New `validate_config()` function
  - Validates YAML syntax before processing
  - Graceful fallback to defaults on invalid config

### Security Hardening

All MEDIUM findings from security audit remediated:

| Finding | Fix |
|---------|-----|
| M-002: Missing strict mode | All 57 scripts now have `set -euo pipefail` |
| M-001: Temp file leaks | Cleanup traps added to 6 mktemp locations |
| M-003: Symlink validation | Path traversal prevention implemented |
| L-003: Config validation | YAML syntax validation before use |

**Security Grade: A** (upgraded from A-)

### Changed

- `analytics.sh` - Added strict mode, cleanup trap, BASH_SOURCE fix
- `context-check.sh` - Added strict mode
- `git-safety.sh` - Added strict mode
- `detect-drift.sh` - Added cleanup trap, removed manual rm
- `update.sh` - Added config validation, cleanup traps (4 locations)

### Scripts

New/updated scripts in `.claude/scripts/beads/`:

| Script | Purpose |
|--------|---------|
| `migrate-to-br.sh` | **NEW** - Full bd → br migration |
| `check-beads.sh` | Rewritten for bd/br detection |
| `install-br.sh` | Updated with better error handling |

## [1.1.1] - 2026-01-20 — br Permissions

### Added

- **Pre-approved `br` commands** in `.claude/settings.json`
  - 17 command patterns: `br:*`, `br create:*`, `br list:*`, `br show:*`, `br update:*`, `br close:*`, `br sync:*`, `br ready:*`, `br dep:*`, `br blocked:*`, `br stats:*`, `br doctor:*`, `br prime:*`, `br init:*`, `br search:*`, `br import:*`, `br export:*`
  - All beads_rust CLI commands now work without permission prompts

## [1.1.0] - 2026-01-20 — beads_rust Migration

### Why This Release

This release migrates from Python-based `bd` CLI to the Rust-based `br` CLI for task management, delivering significant performance and reliability improvements. Additionally, a comprehensive security remediation sprint addressed 16 vulnerabilities across the framework.

### Performance Improvements

- **10x faster startup** - Rust binary vs Python interpreter cold start
- **Lower memory footprint** - Native binary vs Python runtime overhead
- **Instant CLI responses** - No import delays or virtualenv activation

### Reliability Improvements

- **Single binary distribution** - No Python version conflicts or dependency issues
- **SQLite with WAL mode** - Better concurrency for daemon operations
- **Crash-resistant state** - Atomic writes prevent corruption

### Developer Experience

- **Simplified installation** - `cargo install beads_rust` or download binary
- **No virtualenv management** - Eliminates `bd` activation dance
- **Consistent behavior** - Same binary across all platforms

### Technical Debt Reduction

- **Removes Python dependency** - Framework is now pure shell + Rust
- **Eliminates daemon startup issues** - Rust daemon is more stable
- **Cleaner error messages** - Rust's error handling is more precise

### Changed

- **All beads scripts migrated** to use `br` CLI instead of `bd`
  - `check-beads.sh` - Updated detection and installation
  - `create-sprint-epic.sh` - Uses `br create`
  - `create-sprint-task.sh` - New script for task creation
  - `get-ready-work.sh` - Replaces `get-ready-by-priority.sh`
  - `get-sprint-tasks.sh` - Updated for `br list`
  - `install-br.sh` - Replaces `install-beads.sh`
  - `loa-prime.sh` - New context recovery script
  - `log-discovered-issue.sh` - New issue logging
  - `sync-and-commit.sh` - Replaces `sync-to-git.sh`

- **Protocols updated**
  - `beads-integration.md` - New comprehensive protocol (replaces `beads-workflow.md`)
  - `session-continuity.md` - Updated for `br` commands
  - `session-end.md` - Updated sync workflow

- **Skills updated** (6 files)
  - Task management instructions updated for `br` CLI

- **Documentation**
  - CLAUDE.md - Updated beads section with `br` commands
  - README.md - Updated installation instructions
  - PROCESS.md - Updated workflow references

### Security Hardening

Comprehensive security audit identified and remediated 16 vulnerabilities:

| Severity | Fixed | Key Fixes |
|----------|-------|-----------|
| CRITICAL | 3 | Shell injection prevention, credential permissions, log sanitization |
| HIGH | 8 | Path traversal, jq/yq injection, symlink attacks, content verification |
| MEDIUM | 4 | Temp file cleanup, input validation library |
| LOW | 1 | Rate limiting infrastructure |

**Security Grade**: B+ → **A-** (Production-ready)

#### Security Functions Added

- `secure_credentials_file()` - Enforces 600/400 file permissions
- `sanitize_sensitive_data()` - Redacts credentials from permission logs
- `validate_path_safe()` - Prevents path traversal attacks
- `validate_identifier()` - Sanitizes yq/jq arguments
- `safe_symlink()` - Validates symlink targets before creation
- `verify_content_hash()` - SHA256 verification for downloads
- `validate_api_key()`, `validate_url()`, `validate_safe_identifier()` - Input validation library
- `check_rate_limit()`, `reset_rate_limit()` - Rate limiting infrastructure

### Migration Guide

**For existing projects using `bd`:**

1. Install beads_rust: `cargo install beads_rust`
2. The `br` CLI is API-compatible with `bd` for common operations
3. Existing `.beads/` directory and data are compatible
4. Run `br doctor` to verify installation

**Command mapping:**
| Old (`bd`) | New (`br`) |
|------------|------------|
| `bd create` | `br create` |
| `bd list` | `br list` |
| `bd sync` | `br sync` |
| `bd prime` | `br prime` |

### Breaking Changes

- **`bd` CLI no longer supported** - Framework now requires `br` (beads_rust)
- Old beads scripts removed: `install-beads.sh`, `get-ready-by-priority.sh`, `sync-to-git.sh`
- `beads-workflow.md` protocol replaced by `beads-integration.md`

---

## [1.0.1] - 2026-01-19

### Fixed

- **Template Pollution**: `grimoires/loa/ledger.json` was being tracked in git and shipped with the template, causing new projects mounted with Loa to inherit development cycle history from the Loa framework itself.

### Changed

- Added `grimoires/loa/ledger.json` and `grimoires/loa/ledger.json.bak` to `.gitignore`
- Removed existing `ledger.json` from git tracking

### Remediation

If you mounted Loa v1.0.0 and see "active cycle Documentation Coherence" or similar inherited state:

```bash
# Option 1: Delete the inherited ledger and start fresh
rm grimoires/loa/ledger.json
/plan-and-analyze

# Option 2: Pull the fix via update
/update-loa
```

New projects mounted from v1.0.1+ will start with a clean slate.

---

## [1.0.0] - 2026-01-19 — Run Mode AI (Autonomous Initiation)

### Why This Release

This is **Loa's first major release** — a milestone that marks the framework's evolution from experimental agent orchestration to production-ready autonomous development. **Run Mode AI** ("AI" = Autonomous Initiation) represents the culmination of 19 iterative releases, 6 development cycles, and comprehensive battle-testing across real-world projects.

Loa 1.0.0 delivers:

1. **Autonomous Sprint Execution**: `/run sprint-N` executes complete implement → review → audit cycles without human intervention
2. **Multi-Sprint Orchestration**: `/run sprint-plan` executes entire sprint plans, creating a single draft PR
3. **4-Level Safety Defense**: ICE Layer, Circuit Breaker, Opt-In, and Visibility controls prevent runaway execution
4. **Continuous Learning**: Agents extract non-obvious discoveries into reusable skills
5. **Intelligent Subagents**: Specialized validation (architecture, security, tests) with automated quality gates
6. **Documentation Coherence**: Every task ships with its documentation — no batching at sprint end

### Major Features Summary

This release bundles all capabilities developed since v0.1.0:

#### Core Framework
- **9 Specialized AI Agents** orchestrating the complete product lifecycle
- **Three-Zone Model**: System (`.claude/`), State (`grimoires/`), App (`src/`)
- **Enterprise-Grade Managed Scaffolding** inspired by AWS Projen, Copier, Google ADK
- **3-Level Skills Architecture**: Metadata → Instructions → Resources

#### Autonomous Execution (v0.18.0)
- **`/run sprint-N`** — Single sprint autonomous execution
- **`/run sprint-plan`** — Multi-sprint execution with single PR
- **`/run-status`** — Progress monitoring with circuit breaker state
- **`/run-halt`** — Graceful stop with incomplete PR creation
- **`/run-resume`** — Checkpoint-based continuation
- **ICE Layer** — Git safety wrapper blocking protected branches
- **Circuit Breaker** — Halts on same-issue repetition, no progress, cycle limits

#### Continuous Learning (v0.17.0)
- **`/retrospective`** — Manual skill extraction from session
- **`/skill-audit`** — Lifecycle management (approve, reject, prune, stats)
- **Four Quality Gates**: Discovery Depth, Reusability, Trigger Clarity, Verification
- **Phase Gating**: Enabled during implement/review/audit/deploy phases

#### Intelligent Subagents (v0.16.0)
- **`/validate`** command with architecture, security, tests, docs subagents
- **architecture-validator** — SDD compliance checking
- **security-scanner** — OWASP Top 10 vulnerability detection
- **test-adequacy-reviewer** — Test quality assessment
- **documentation-coherence** — Per-task documentation validation (v0.19.0)

#### Context Management (v0.9.0-v0.15.0)
- **Lossless Ledger Protocol** — "Clear, Don't Compact" paradigm
- **Session Continuity** — Tiered recovery (L1: ~100 tokens, L2: ~500, L3: full)
- **Grounding Enforcement** — 95% citation requirement before `/clear`
- **Sprint Ledger** — Global sprint numbering across development cycles
- **RLM Pattern** — Probe-before-load achieving 29.3% token reduction

#### Developer Experience
- **Frictionless Permissions** — 150+ pre-approved commands (npm, git, docker, etc.)
- **Permission Audit** — HITL request logging and analysis
- **Auto-Update Check** — Session-start version checking
- **MCP Configuration Examples** — Pre-built integrations for Slack, GitHub, Sentry, Postgres

#### Mount & Ride Workflow (v0.7.0)
- **`/mount`** — Install Loa onto existing repositories
- **`/ride`** — Analyze codebase, generate evidence-grounded docs
- **Drift Detection** — Three-way analysis: Code vs Docs vs Context
- **Ghost Feature Detection** — Identifies documented but unimplemented features

### Removed Phases
- **`/setup` command** — No longer needed (v0.15.0). Start directly with `/plan-and-analyze`
- **Phase 0** — THJ detection via `LOA_CONSTRUCTS_API_KEY` environment variable

### Complete Workflow

```
Phase 1:   /plan-and-analyze  → grimoires/loa/prd.md
Phase 2:   /architect         → grimoires/loa/sdd.md
Phase 3:   /sprint-plan       → grimoires/loa/sprint.md
Phase 4:   /implement sprint-N → Code + reviewer.md
Phase 5:   /review-sprint     → engineer-feedback.md
Phase 5.5: /audit-sprint      → auditor-sprint-feedback.md + COMPLETED marker
Phase 6:   /deploy-production → deployment/

Autonomous: /run sprint-N      → Draft PR with full cycle execution
            /run sprint-plan   → Multi-sprint Draft PR
```

### Full Agent Roster (The Loa)

| Agent | Role | Output |
|-------|------|--------|
| `discovering-requirements` | Senior Product Manager | PRD |
| `designing-architecture` | Software Architect | SDD |
| `planning-sprints` | Technical PM | Sprint Plan |
| `implementing-tasks` | Senior Engineer | Code + Report |
| `reviewing-code` | Tech Lead | Approval/Feedback |
| `auditing-security` | Security Auditor | Security Approval |
| `deploying-infrastructure` | DevOps Architect | Infrastructure |
| `translating-for-executives` | Developer Relations | Summaries |
| `run-mode` | Autonomous Executor | Draft PR + State |

### Configuration Reference

```yaml
# .loa.config.yaml (v1.0.0)
persistence_mode: standard        # standard | stealth
integrity_enforcement: strict     # strict | warn | disabled

grounding:
  enforcement: warn               # strict | warn | disabled
  threshold: 0.95

run_mode:
  enabled: false                  # IMPORTANT: Explicit opt-in
  defaults:
    max_cycles: 20
    timeout_hours: 8
  circuit_breaker:
    same_issue_threshold: 3
    no_progress_threshold: 5

continuous_learning:
  enabled: true
  auto_extract: true
  require_approval: true

agent_skills:
  enabled: true
  load_mode: dynamic              # dynamic | eager
```

### Breaking Changes

None from v0.19.0. All existing projects continue to work unchanged.

**From earlier versions (pre-v0.15.0)**:
- `/setup` command removed — start with `/plan-and-analyze`
- `/update` renamed to `/update-loa`
- `loa-grimoire/` migrated to `grimoires/loa/`

### Security

All 19 releases passed security audits:
- No hardcoded credentials
- All scripts use `set -euo pipefail`
- Shell safety (`shellcheck` compliant)
- Input validation on all user-facing scripts
- Path traversal prevention
- Test isolation with `BATS_TMPDIR`

### Test Coverage

| Category | Count |
|----------|-------|
| Unit Tests | 700+ |
| Integration Tests | 180+ |
| Edge Case Tests | 100+ |

### Acknowledgments

This major release represents the collective efforts of multiple development cycles:
- **cycle-001**: Foundation, Managed Scaffolding, Lossless Ledger Protocol
- **cycle-002**: Semantic Search, Mount & Ride, Context Improvements
- **cycle-003**: Sprint Ledger, Auto-Update, Anthropic Oracle
- **cycle-004**: Continuous Learning Skill
- **cycle-005**: Run Mode, Permission Audit
- **cycle-006**: Documentation Coherence

---

## [0.19.0] - 2026-01-19

### Why This Release

The **Documentation Coherence** release enforces atomic per-task documentation validation:

1. **Atomic Enforcement**: Every task ships with its documentation - no batching at sprint end
2. **Integrated Workflow**: documentation-coherence subagent runs during review, audit, and deploy phases
3. **Clear Blocking Rules**: CHANGELOG missing = blocked; new command without CLAUDE.md = blocked

### Added

#### documentation-coherence Subagent (Sprint 1)

- **`.claude/subagents/documentation-coherence.md`** - Per-task documentation validation
  - Task type detection: new feature, bug fix, new command, API change, refactor, security fix, config change
  - Per-task documentation requirements matrix
  - Severity levels: COHERENT, NEEDS_UPDATE, ACTION_REQUIRED
  - Escalation rules (missing CHANGELOG → ACTION_REQUIRED)
  - Task-level and sprint-level report formats
  - Blocking behavior per trigger documented

#### /validate docs Command (Sprint 1)

- **`/validate docs`** - Run documentation-coherence on demand
  - `/validate docs --sprint` - Sprint-level verification
  - `/validate docs --task N` - Specific task verification
  - Advisory (non-blocking) when run manually
  - Produces reports at `grimoires/loa/a2a/subagent-reports/`

#### Skill Integrations (Sprint 2)

- **reviewing-code skill**: New "Documentation Verification (Required)" section
  - Pre-review check for documentation-coherence report
  - Documentation checklist with blocking criteria
  - "Cannot Approve If" conditions
  - Approval/rejection language templates

- **auditing-security skill**: New "Documentation Audit (Required)" section
  - Sprint documentation coverage verification
  - Security-specific documentation checks (SECURITY.md, auth docs, API docs)
  - Red flags for secrets/internal info in docs
  - Audit checklist additions

- **deploying-infrastructure skill**: New "Release Documentation Verification (Required)" section
  - Pre-deployment documentation checklist
  - CHANGELOG verification (version set, all tasks, breaking changes)
  - README verification (features, quick start, links)
  - Deployment and operational documentation requirements
  - "Cannot Deploy If" conditions

#### Tests (Sprint 1-2)

- `tests/unit/documentation-coherence.bats` - 54 unit tests
  - Task type detection, CHANGELOG verification, severity levels
  - Report format generation, escalation rules
- `tests/integration/documentation-coherence.bats` - 31 integration tests
  - Skill integrations, cross-references, blocking behavior

#### Context Cleanup Script

- **`.claude/scripts/cleanup-context.sh`** - Discovery context archive and cleanup
  - **Archives first**: Copies context to `{archive-path}/context/` before cleaning
  - Automatically called by `/run sprint-plan` on completion
  - Smart archive location: uses ledger.json or finds most recent archive
  - Supports `--dry-run`, `--verbose`, and `--no-archive` options
  - Preserves valuable discovery context while ensuring fresh start

#### v0.8.0 Spec Compliance (Skills Housekeeping)

- **`.claude/protocols/verification-loops.md`** - New protocol (P1.1)
  - 7-level verification hierarchy (tests → type check → lint → build → integration → E2E → manual)
  - Agent responsibilities for implementing-tasks, reviewing-code, deploying-infrastructure
  - Minimum viable verification requirements
  - Integration with quality gates workflow

- **implementing-tasks skill**: Task-Level Planning section (P1.2)
  - Complex task criteria (3+ files, architectural decisions, >2 hours)
  - Task plan template with Objective, Approach, Files, Dependencies, Risks, Verification
  - Plan review requirements before implementing
  - Plans stored at `grimoires/loa/a2a/sprint-N/task-{N}-plan.md`

- **reviewing-code skill**: Complexity Review section (P1.3)
  - Function complexity checks (>50 lines, >5 params, nesting >3)
  - Code duplication detection (>3 occurrences)
  - Dependency analysis (circular imports, unused)
  - Naming quality assessment
  - Dead code detection
  - Blocking vs non-blocking complexity verdicts

- **deploying-infrastructure skill**: E2E Verification section (P1.4)
  - Pre-deployment verification matrix (tests, build, type check, security scan)
  - Infrastructure verification checklist
  - Staging environment test requirements
  - E2E test categories (happy path, error handling, auth, data integrity)
  - Verification report template for deployment reports
  - Blocking conditions for deployment

- **PROCESS.md**: Context Hygiene section (P2.1)
  - Loading priority table (NOTES.md → sprint files → PRD/SDD → source → tests)
  - Grep vs skim decision guidance
  - When to request file tree
  - Context budget awareness (Green/Yellow/Red zones)
  - Tool result clearing examples

- **PROCESS.md**: Long-Running Task Guidance (P2.3)
  - Session handoff protocol with NOTES.md updates
  - Checkpoint creation examples
  - Multi-file refactoring tracking patterns
  - Avoiding context exhaustion (>2 hour tasks)
  - Recovery after interruption steps

- **CONTRIBUTING.md**: Command Optimization section (P3.1)
  - Parallel call patterns with good/bad examples
  - Sequential patterns for dependencies
  - Command invocation examples
  - Pre-flight check patterns
  - Context loading optimization
  - Error message quality guidelines
  - Command documentation requirements

### Changed

- **CLAUDE.md**: Added documentation-coherence to subagents table
- **CLAUDE.md**: Added `/validate docs` to commands table
- **/validate command**: Now includes docs subcommand with options

### PRD/SDD References

- PRD: `grimoires/loa/prd.md` (cycle-006)
- SDD: `grimoires/loa/sdd.md` (cycle-006)

---

## [0.18.0] - 2026-01-19

### Why This Release

The **Run Mode** release enables autonomous sprint execution with human-in-the-loop shifted to PR review:

1. **Autonomous Execution**: `/run sprint-N` executes implement → review → audit cycles until all pass
2. **Safety Controls**: 4-level defense (ICE, Circuit Breaker, Opt-In, Visibility) prevents runaway execution
3. **Multi-Sprint Support**: `/run sprint-plan` executes entire sprint plans with single PR
4. **Resumable State**: Checkpoint-based execution allows halt and resume from any point

### Added

#### Run Mode Commands (Sprint 2-3)

- **`/run sprint-N`** - Autonomous single sprint execution
  - Cycles through implement → review → audit until all pass
  - Options: `--max-cycles`, `--timeout`, `--branch`, `--dry-run`
  - Creates draft PR on completion
  - Never merges or pushes to protected branches

- **`/run sprint-plan`** - Multi-sprint execution
  - Three-tier sprint discovery (sprint.md → ledger.json → directories)
  - Options: `--from N`, `--to N` for partial execution
  - Single PR for entire plan
  - Graceful failure handling with incomplete PR

- **`/run-status`** - Progress display
  - Box-formatted run info, metrics, circuit breaker status
  - Options: `--json`, `--verbose`
  - Sprint plan progress tree for multi-sprint runs

- **`/run-halt`** - Graceful stop
  - Completes current phase before stopping
  - Creates draft PR marked `[INCOMPLETE]`
  - Options: `--force`, `--reason "..."`

- **`/run-resume`** - Continue from checkpoint
  - Branch divergence detection
  - Circuit breaker state check
  - Options: `--reset-ice`, `--force`

#### Safety Infrastructure (Sprint 1)

- **`.claude/scripts/run-mode-ice.sh`** - Git operation safety wrapper
  - Blocks push to protected branches (main, master, staging, etc.)
  - Blocks all merge operations
  - Blocks branch deletion
  - Enforces draft-only PR creation

- **`.claude/scripts/check-permissions.sh`** - Permission validation
  - Verifies required Claude Code permissions
  - Clear error messages for missing permissions

- **`.claude/protocols/run-mode.md`** - Safety protocol
  - 4-level defense in depth documentation
  - State machine transitions
  - Circuit breaker triggers and thresholds

#### Circuit Breaker (Sprint 2)

- **Same Issue Detection**: Hash-based comparison, halts after 3 repetitions
- **No Progress Detection**: Halts after 5 cycles without file changes
- **Cycle Limit**: Halts after configurable max cycles (default 20)
- **Timeout**: Halts after configurable runtime (default 8 hours)
- **State**: CLOSED (normal) → OPEN (halted), reset with `--reset-ice`

#### State Management (Sprint 2)

- **`.run/state.json`** - Run progress, metrics, cycle history
- **`.run/circuit-breaker.json`** - Trigger counts, trip history
- **`.run/deleted-files.log`** - Tracked deletions for PR body
- **`.run/rate-limit.json`** - Hour boundary API call tracking

#### Skill & Configuration (Sprint 4)

- **`.claude/skills/run-mode/`** - Run Mode skill definition
  - `index.yaml`: Triggers, inputs, outputs, safety requirements
  - `SKILL.md`: KERNEL instructions for autonomous execution

- **`.loa.config.yaml`**: `run_mode` section
  - `enabled`: Master toggle (defaults to `false` for safety)
  - `defaults.max_cycles`: Maximum cycles before halt
  - `defaults.timeout_hours`: Maximum runtime
  - `rate_limiting.calls_per_hour`: API exhaustion prevention
  - `circuit_breaker.same_issue_threshold`: Repetition tolerance
  - `circuit_breaker.no_progress_threshold`: Empty cycle tolerance
  - `git.branch_prefix`: Auto-created branch prefix
  - `git.create_draft_pr`: Always true (enforced)

#### Tests (Sprint 1-2)

- `tests/unit/run-mode-ice.bats`: ICE wrapper safety tests
- `tests/unit/circuit-breaker.bats`: Circuit breaker trigger tests
- `tests/integration/run-mode.bats`: End-to-end Run Mode tests

#### Permission Audit

- **`.claude/scripts/permission-audit.sh`** - HITL permission request logging
  - Logs all commands that required human approval
  - `view`: Display permission request log
  - `analyze`: Show patterns and frequency
  - `suggest`: Recommend permissions to add to settings.json
  - `clear`: Clear the log

- **`/permission-audit`** command for easy access

- **`PermissionRequest` hook** in settings.json enables automatic logging

### Changed

- **CLAUDE.md**:
  - Updated skill count from 8 to 9
  - Added Run Mode section with commands, safety model, configuration
  - Added `run-mode` to skills table
  - Added Run Mode commands to workflow commands list

- **`.gitignore`**: Added `.run/` directory (Run Mode state)
- **`.gitignore`**: Added `permission-requests.jsonl` (user-specific audit log)
- **`.claude/settings.json`**: Updated to new Claude Code v2.1.12+ hooks format
- **`.claude/settings.json`**: Added `PermissionRequest` hook for audit logging

### Security

- **Explicit Opt-In**: Run Mode disabled by default
- **ICE Layer**: All git operations wrapped with safety checks
- **Draft PRs Only**: Never creates ready-for-review PRs
- **Protected Branches**: Push to main/master/staging always blocked
- **Merge Block**: Merge operations completely disabled
- **Deleted File Tracking**: All deletions prominently displayed in PR

### PRD/SDD References

- PRD: `grimoires/loa/prd.md` (cycle-005)
- SDD: `grimoires/loa/sdd.md` (cycle-005)

---

## [0.17.0] - 2026-01-19

### Why This Release

The **Continuous Learning Skill** release enables Loa agents to build compound knowledge over time:

1. **Skill Extraction**: Agents detect non-obvious discoveries during implementation and extract them into reusable skills
2. **Quality Gates**: Four gates (Discovery Depth, Reusability, Trigger Clarity, Verification) prevent low-value extraction
3. **Lifecycle Management**: `/retrospective` and `/skill-audit` commands for approval, rejection, and pruning workflows

**Research Foundation**: Based on Voyager (Wang et al., 2023), CASCADE (2024), Reflexion (Shinn et al., 2023), and SEAgent (2025).

### Added

#### Continuous Learning Skill (Sprint 1-2)

- **`.claude/skills/continuous-learning/`** - Core skill definition
  - `index.yaml`: Skill metadata with triggers and phase activation
  - `SKILL.md`: KERNEL instructions for discovery detection and extraction
  - `resources/skill-template.md`: Template for extracted skills
  - `resources/examples/nats-jetstream-consumer-durable.md`: Example skill

- **`.claude/protocols/continuous-learning.md`** - Evaluation protocol
  - Four quality gates with pass/fail criteria
  - Phase gating table (enabled during implement/review/audit/deploy)
  - Zone compliance rules (State Zone only for extracted skills)
  - Trajectory logging format

- **State Zone directories** for skill lifecycle:
  - `grimoires/loa/skills/`: Active extracted skills
  - `grimoires/loa/skills-pending/`: Skills awaiting approval
  - `grimoires/loa/skills-archived/`: Rejected or pruned skills

#### Commands (Sprint 3)

- **`/retrospective`** - Manual skill extraction
  - Five-step workflow: Session Analysis → Quality Gates → Cross-Reference → Extract → Summary
  - `--scope <agent>`: Limit extraction to specific agent context
  - `--force`: Skip quality gate prompts
  - Example conversation flow with output formats

- **`/skill-audit`** - Lifecycle management
  - `--pending`: List skills awaiting approval
  - `--approve <name>`: Move skill to active
  - `--reject <name>`: Archive skill with reason
  - `--prune`: Review for low-value skills (>90 days, <2 matches)
  - `--stats`: Show skill usage statistics

#### Configuration & Documentation (Sprint 4)

- **`.loa.config.yaml`**: `continuous_learning` section
  - `enabled`: Master toggle
  - `auto_extract`: Enable/disable automatic extraction
  - `require_approval`: Skip or require pending workflow
  - `quality_gates.min_discovery_depth`: 1-3 threshold
  - `pruning.prune_after_days`: Age-based archive threshold
  - `pruning.prune_min_matches`: Usage-based retention threshold

- **CLAUDE.md**: New "Continuous Learning Skill (v0.17.0)" section
  - Command reference table
  - Quality gates documentation
  - Phase activation table
  - Configuration examples

#### Tests (Sprint 4)

- `tests/unit/quality-gates.bats`: Quality gate logic validation
- `tests/unit/zone-compliance.bats`: State Zone write enforcement
- `tests/integration/retrospective.bats`: End-to-end extraction flow
- `tests/integration/skill-audit.bats`: Lifecycle management flows

### Changed

- **CLAUDE.md**: Added `/retrospective` and `/skill-audit` to ad-hoc commands
- **Document flow diagram**: Now includes extracted skills in `grimoires/loa/`

### PRD/SDD References

- PRD: `grimoires/loa/prd.md` (cycle-004)
- SDD: `grimoires/loa/sdd.md` (cycle-004)

---

## [0.16.0] - 2026-01-18

### Why This Release

The **Loa Orchestration** release delivers three key developer experience improvements:

1. **Frictionless Permissions**: 150+ pre-approved commands eliminate permission prompts for standard development operations (npm, git, docker, etc.)

2. **Intelligent Subagents**: Three validation subagents (architecture-validator, security-scanner, test-adequacy-reviewer) provide automated quality gates

3. **Enhanced Agent Memory**: Structured NOTES.md protocol with 6 required sections ensures consistent context preservation across sessions

### Added

#### Frictionless Permissions (Sprint 1)

- **150+ pre-allowed patterns** in `.claude/settings.json`
  - Package managers: npm, pnpm, yarn, bun, cargo, pip, poetry, gem, go
  - Git operations: add, commit, push, pull, branch, merge, rebase, stash
  - Containers: docker, docker-compose, kubectl, helm
  - Runtimes: node, python, ruby, java, go, rustc
  - Testing: jest, vitest, pytest, mocha, bats
  - Build tools: webpack, vite, esbuild, tsc, swc
  - Deploy CLIs: vercel, fly, railway, aws, gcloud

- **Security deny list**
  - Privilege escalation blocked: sudo, su, doas
  - Destructive operations: rm -rf /, fork bombs
  - Remote code execution: curl|bash, wget|sh
  - Device attacks: /dev/sda, dd, mkfs

- **Documentation**: New "Frictionless Permissions" section in INSTALLATION.md

#### Intelligent Subagents (Sprints 2-3)

- **`.claude/subagents/` directory** with three validation agents:
  - `architecture-validator.md`: SDD compliance, structural and naming checks
  - `security-scanner.md`: OWASP Top 10, input validation, auth/authz
  - `test-adequacy-reviewer.md`: Coverage quality, test smells, missing tests

- **`/validate` command**
  - `/validate` - Run all subagents
  - `/validate architecture|security|tests` - Run specific subagent
  - `/validate security src/auth` - Scoped validation

- **Subagent Invocation Protocol** (`.claude/protocols/subagent-invocation.md`)
  - Scope determination: explicit > sprint context > git diff
  - Output location: `grimoires/loa/a2a/subagent-reports/`
  - Quality gate integration with blocking verdicts

- **`reviewing-code` skill updated**: Checks subagent reports, blocks on CRITICAL/HIGH

#### Enhanced NOTES.md Protocol (Sprint 4)

- **Required sections defined** (`.claude/protocols/structured-memory.md`):
  - Current Focus: Active task, status, blocked by, next action
  - Session Log: Append-only event history table
  - Decisions: Architecture/implementation decisions with rationale
  - Blockers: Checkbox list with [RESOLVED] marking
  - Technical Debt: ID, description, severity, found by, sprint
  - Learnings: Project-specific knowledge
  - Session Continuity: Recovery anchor (v0.9.0)

- **Agent Discipline events**: Session start, decision made, blocker hit/resolved, session end, mistake discovered

- **NOTES.md template** (`.claude/templates/NOTES.md.template`)

#### MCP Configuration Examples (Sprint 5)

- **`.claude/mcp-examples/` directory** for power users:
  - `slack.json` - HIGH risk (read + write)
  - `github.json` - MEDIUM risk (read + write)
  - `sentry.json` - LOW risk (read only)
  - `postgres.json` - CRITICAL risk (configurable)

- **Security documentation**: Required scopes, setup steps, risk levels, recommendations

### Changed

- **`reviewing-code` skill**: Now checks `a2a/subagent-reports/` for blocking verdicts
- **`structured-memory.md` protocol**: Enhanced with v0.16.0 required sections and agent discipline
- **CLAUDE.md**: New sections for Intelligent Subagents and MCP examples
- **README.md**: Updated repository structure, frictionless permissions note

### Test Coverage

New tests added:
- `tests/unit/settings-permissions.bats`: Permission patterns validation
- `tests/unit/subagent-loader.bats`: Subagent loading and YAML validation
- `tests/unit/subagent-reports.bats`: Security scanner and test adequacy
- `tests/unit/notes-template.bats`: NOTES.md template sections
- `tests/integration/validate-flow.bats`: End-to-end /validate command

### Security

All 5 sprints passed security audit:
- No hardcoded credentials in any file
- All scripts use `set -euo pipefail`
- Deny list prevents dangerous commands
- MCP examples use environment variable placeholders only

---

## [0.15.0] - 2026-01-18

### Why This Release

This release delivers two major feature cycles:

1. **Sprint Ledger** (Cycle 1): Global sprint numbering across multiple development cycles, preventing directory collisions when running `/plan-and-analyze` multiple times.

2. **RLM Context Improvements** (Cycle 2): Probe-before-load pattern achieving 29.3% token reduction, based on MIT CSAIL research on Recursive Language Models.

Additionally, this release removes the `/setup` phase, allowing users to start immediately with `/plan-and-analyze`.

### Added

#### Sprint Ledger (v0.13.0 features)

- **`/ledger` command**: View current ledger status and sprint history
- **`/archive-cycle "label"` command**: Archive completed cycles with full artifact preservation
- **`ledger-lib.sh` script**: Core ledger functions (init, create_cycle, add_sprint, resolve_sprint)
- **`validate-sprint-id.sh` script**: Resolves local sprint IDs (sprint-1) to global IDs (sprint-7)
- **Cycle archiving**: Preserves PRD, SDD, sprint.md and all a2a artifacts to `grimoires/loa/archive/`
- **Backward compatibility**: Projects without ledger work exactly as before (legacy mode)

#### RLM Context Improvements (v0.15.0 features)

- **Probe-Before-Load Pattern** (`context-manager.sh`)
  - `probe <file|dir> --json`: Lightweight metadata extraction without loading content
  - `should-load <file> --json`: Decision engine for selective loading
  - Achieves **29.3% token reduction** with only **0.6% overhead**

- **Schema Validator Assertions** (`schema-validator.sh`)
  - `assert <file> --schema prd --json`: Programmatic validation mode
  - Field existence, enum validation, semver format, array checks
  - Replaces re-prompting with code-based verification

- **RLM Benchmark Framework** (`rlm-benchmark.sh`)
  - `run --target <dir> --json`: Compare current vs RLM loading patterns
  - `baseline`: Capture metrics for future comparison
  - `compare`: Delta analysis against baseline
  - `report`: Generate markdown report with methodology and results

- **Trajectory logging**: All new operations logged to `grimoires/loa/a2a/trajectory/`

### Changed

- **`/plan-and-analyze`**: Creates ledger and cycle automatically on first run
- **`/sprint-plan`**: Registers sprints in ledger with global IDs
- **`/implement sprint-N`**: Resolves local ID to global directory
- **`/review-sprint sprint-N`**: Resolves local ID to global directory
- **`/audit-sprint sprint-N`**: Resolves ID and updates completion status in ledger
- **`/update` renamed to `/update-loa`**: Avoids conflict with Claude Code built-in command

### Configuration

New options in `.loa.config.yaml`:

```yaml
context_management:
  probe_before_load: true
  max_eager_load_lines: 500
  relevance_keywords: ["export", "class", "interface", "function"]
  exclude_patterns: ["*.test.ts", "*.spec.ts", "node_modules/**"]
```

### Test Coverage

| Category | Count |
|----------|-------|
| Unit Tests | 652 |
| Integration Tests | 149 |
| Edge Case Tests | 86 |
| **Total** | **887** |

New tests added:
- 100+ Sprint Ledger tests (Cycle 1)
- 120+ RLM Context tests (Cycle 2)

### Security

All 12 sprints across both cycles passed security audit:
- No hardcoded credentials
- Shell safety (`set -euo pipefail`)
- Input validation
- No command injection
- Test isolation
- Path traversal prevention

### Documentation

- `CLAUDE.md`: Sprint Ledger and RLM Benchmark sections
- `grimoires/pub/research/rlm-release-notes.md`: Release notes
- `grimoires/pub/research/benchmarks/final-report.md`: Benchmark results
- `grimoires/pub/research/rlm-recursive-language-models.md`: Research analysis

---

### Previous 0.15.0 Changes (Setup Removal)

This release also removes the `/setup` phase entirely, allowing users to start with `/plan-and-analyze` immediately after cloning. THJ membership is now detected via the `LOA_CONSTRUCTS_API_KEY` environment variable instead of a marker file.

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

[1.1.0]: https://github.com/0xHoneyJar/loa/releases/tag/v1.1.0
[1.0.1]: https://github.com/0xHoneyJar/loa/releases/tag/v1.0.1
[1.0.0]: https://github.com/0xHoneyJar/loa/releases/tag/v1.0.0
[0.19.0]: https://github.com/0xHoneyJar/loa/releases/tag/v0.19.0
[0.18.0]: https://github.com/0xHoneyJar/loa/releases/tag/v0.18.0
[0.17.0]: https://github.com/0xHoneyJar/loa/releases/tag/v0.17.0
[0.16.0]: https://github.com/0xHoneyJar/loa/releases/tag/v0.16.0
[0.15.0]: https://github.com/0xHoneyJar/loa/releases/tag/v0.15.0
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
