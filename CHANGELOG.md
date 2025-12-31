# Changelog

All notable changes to Loa will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
