# Helper Scripts Reference

> **Protocol Version**: 1.0
> **Last Updated**: 2026-01-22
> **CLAUDE.md Reference**: Section "Helper Scripts"

Complete documentation for Loa framework scripts in `.claude/scripts/`.

## Script Directory Structure

```
.claude/scripts/
├── mount-loa.sh              # One-command install onto existing repo
├── update.sh                 # Framework updates with migration gates
├── check-loa.sh              # CI validation script
├── detect-drift.sh           # Code vs docs drift detection
├── validate-change-plan.sh   # Pre-implementation validation
├── analytics.sh              # Analytics functions (THJ only)
├── beads/                    # beads_rust helper scripts directory
│   ├── check-beads.sh        # beads_rust (br CLI) availability check
│   ├── install-br.sh         # Install beads_rust if not present
│   ├── loa-prime.sh          # Session priming (ready, blocked, recent)
│   ├── sync-and-commit.sh    # Flush SQLite + optional commit
│   ├── get-ready-work.sh     # Query ready tasks by priority
│   ├── create-sprint-epic.sh # Create sprint epic with labels
│   ├── create-sprint-task.sh # Create task under sprint epic
│   ├── log-discovered-issue.sh # Log discovered issues with traceability
│   └── get-sprint-tasks.sh   # Get tasks for a sprint epic
├── git-safety.sh             # Template detection
├── context-check.sh          # Parallel execution assessment
├── preflight.sh              # Pre-flight validation
├── assess-discovery-context.sh  # PRD context ingestion
├── check-feedback-status.sh  # Sprint feedback state
├── check-prerequisites.sh    # Phase prerequisites
├── validate-sprint-id.sh     # Sprint ID validation
├── mcp-registry.sh           # MCP registry queries
├── validate-mcp.sh           # MCP configuration validation
├── constructs-loader.sh      # Loa Constructs skill loader
├── constructs-lib.sh         # Loa Constructs shared utilities
├── license-validator.sh      # JWT license validation
├── skills-adapter.sh         # Claude Agent Skills format generator
├── schema-validator.sh       # JSON Schema validation for outputs
├── thinking-logger.sh        # Extended thinking trajectory logger
├── tool-search-adapter.sh    # MCP tool search and discovery
├── context-manager.sh        # Context compaction and preservation
├── context-benchmark.sh      # Context performance benchmarks
├── rlm-benchmark.sh          # RLM pattern benchmark and validation
├── anthropic-oracle.sh       # Anthropic updates monitoring
├── check-updates.sh          # Automatic version checking
├── permission-audit.sh       # Permission request logging and analysis
├── cleanup-context.sh        # Discovery context cleanup for cycle completion
└── mermaid-url.sh            # Beautiful Mermaid preview URL generator
```

---

## Core Scripts

### mount-loa.sh

One-command installation of Loa onto an existing repository.

```bash
# Standard install
curl -fsSL https://raw.githubusercontent.com/0xHoneyJar/loa/main/.claude/scripts/mount-loa.sh | bash

# With options
./mount-loa.sh --branch main --stealth --skip-beads

# Recovery install (when /update is broken)
curl -fsSL https://raw.githubusercontent.com/0xHoneyJar/loa/main/.claude/scripts/mount-loa.sh | bash -s -- --force
```

**Options**:
| Option | Description |
|--------|-------------|
| `--branch <name>` | Loa branch to use (default: main) |
| `--force`, `-f` | Force remount without prompting |
| `--stealth` | Add state files to .gitignore |
| `--skip-beads` | Don't install/initialize Beads CLI |
| `--no-commit` | Skip creating git commit after mount |

**Clean Upgrade Behavior** (v1.4.0+):
- Creates a single atomic commit: `chore(loa): mount framework v{VERSION}`
- Creates version tag: `loa@v{VERSION}`
- Respects stealth mode (no commits)
- Configurable via `.loa.config.yaml` `upgrade:` section

### update.sh

Framework updates with strict enforcement and migration gates.

```bash
# Standard update
.claude/scripts/update.sh

# Check for updates only
.claude/scripts/update.sh --check

# Force update (skip integrity check)
.claude/scripts/update.sh --force

# Dry run (preview changes)
.claude/scripts/update.sh --dry-run
```

**Options**:
| Option | Description |
|--------|-------------|
| `--dry-run` | Preview changes without applying |
| `--force` | Skip integrity check |
| `--force-restore` | Force restore from upstream |
| `--check` | Check for updates only |
| `--json` | Output JSON (for --check) |
| `--no-commit` | Skip creating git commit after update |

**Workflow**:
1. Integrity Check (BLOCKING in strict mode)
2. Fetch to staging
3. Validation (YAML, shell syntax)
4. Migrations (BLOCKING)
5. Atomic Swap
6. Restore Overrides
7. Update Manifest
8. Generate Checksums
9. Apply Stealth Mode
10. Regenerate Config Snapshot
11. Create Atomic Commit
12. Check for Grimoire Migration

### check-loa.sh

CI validation script for Loa installation integrity.

```bash
.claude/scripts/check-loa.sh
```

Checks:
- Loa installation status
- System Zone integrity (sha256 checksums)
- Schema version
- Structured memory presence
- Configuration validity
- Zone structure

---

## Permission Audit (v0.18.0)

Logs and analyzes permission requests that required HITL approval.

```bash
.claude/scripts/permission-audit.sh view       # View permission request log
.claude/scripts/permission-audit.sh analyze    # Analyze patterns and frequency
.claude/scripts/permission-audit.sh suggest    # Get suggestions for settings.json
.claude/scripts/permission-audit.sh clear      # Clear the log
```

**Slash Command**: `/permission-audit`

**How It Works**:
1. A `PermissionRequest` hook logs every command that requires approval
2. Log stored at `grimoires/loa/analytics/permission-requests.jsonl`
3. `suggest` command recommends permissions to add based on frequency

**Example Workflow**:
```bash
# After a session with many permission prompts
/permission-audit suggest

# Output shows frequently requested commands:
# [suggest] "Bash(flyctl:*)" (12 times)
# [suggest] "Bash(pm2:*)" (8 times)

# Add suggested permissions to settings.json
```

---

## Context Cleanup (v0.19.0)

Archives and cleans discovery context directory after sprint plan completion.

```bash
.claude/scripts/cleanup-context.sh              # Archive then clean
.claude/scripts/cleanup-context.sh --dry-run    # Preview without changes
.claude/scripts/cleanup-context.sh --verbose    # Show detailed output
.claude/scripts/cleanup-context.sh --no-archive # Just delete (not recommended)
```

**Automatic**: Called by `/run sprint-plan` on successful completion.

**Manual**: Can be run before starting a new `/plan-and-analyze` cycle.

**Behavior**:
1. **Archive**: Copies all context files to `{archive-path}/context/`
2. **Clean**: Removes all files from `grimoires/loa/context/` except `README.md`
3. **Preserve**: `README.md` explaining the directory is always kept

**Archive Location Priority**:
1. Active cycle's archive_path from ledger.json
2. Most recent archived cycle's path from ledger.json
3. Most recent `grimoires/loa/archive/20*` directory
4. Fallback: `grimoires/loa/archive/{date}-context-archive/`

---

## Update Check (v0.14.0)

Automatic version checking on session start.

```bash
.claude/scripts/check-updates.sh --notify   # Check and notify (default for hooks)
.claude/scripts/check-updates.sh --check    # Force check (bypass cache)
.claude/scripts/check-updates.sh --json     # JSON output for scripting
.claude/scripts/check-updates.sh --quiet    # Suppress non-error output
```

**Exit Codes**:
- `0`: Up to date or check disabled/skipped
- `1`: Update available
- `2`: Error

**Configuration** (`.loa.config.yaml`):
```yaml
update_check:
  enabled: true                    # Master toggle
  cache_ttl_hours: 24              # Cache TTL (default: 24)
  notification_style: banner       # banner | line | silent
  include_prereleases: false       # Include pre-release versions
  upstream_repo: "0xHoneyJar/loa"  # GitHub repo to check
```

**Environment Variables** (override config):
- `LOA_DISABLE_UPDATE_CHECK=1` - Disable all checks
- `LOA_UPDATE_CHECK_TTL=48` - Cache TTL in hours
- `LOA_UPSTREAM_REPO=owner/repo` - Custom upstream
- `LOA_UPDATE_NOTIFICATION=line` - Notification style

**Features**:
- Runs automatically on session start via SessionStart hook
- Auto-skips in CI environments (GitHub Actions, GitLab CI, Jenkins, etc.)
- Caches results to minimize API calls (24h default)
- Shows major version warnings
- Silent failure on network errors

---

## Anthropic Oracle (v0.13.0)

Monitors Anthropic official sources for updates relevant to Loa.

```bash
.claude/scripts/anthropic-oracle.sh check     # Fetch latest sources
.claude/scripts/anthropic-oracle.sh sources   # List monitored URLs
.claude/scripts/anthropic-oracle.sh history   # View check history
```

**Workflow**:
1. Run `anthropic-oracle.sh check` to fetch sources
2. Run `/oracle-analyze` to analyze with Claude
3. Generate research document at `grimoires/pub/research/`

**Automated**: Weekly GitHub Actions workflow creates issues for review.

---

## Context Manager (v0.11.0)

Manages context compaction with preservation rules and RLM probe-before-load pattern.

```bash
# Check context status
.claude/scripts/context-manager.sh status
.claude/scripts/context-manager.sh status --json

# View preservation rules
.claude/scripts/context-manager.sh rules

# Run pre-compaction check
.claude/scripts/context-manager.sh compact --dry-run

# Run simplified checkpoint (3 manual steps)
.claude/scripts/context-manager.sh checkpoint

# Recover context at different levels
.claude/scripts/context-manager.sh recover 1  # Minimal (~100 tokens)
.claude/scripts/context-manager.sh recover 2  # Standard (~500 tokens)
.claude/scripts/context-manager.sh recover 3  # Full (~2000 tokens)

# RLM Pattern: Probe before loading
.claude/scripts/context-manager.sh probe src/           # Probe directory
.claude/scripts/context-manager.sh probe file.ts --json # Probe file with JSON output
.claude/scripts/context-manager.sh should-load file.ts  # Get load/skip decision
```

**Probe Output Fields**:
| Field | Description |
|-------|-------------|
| `file` / `files` | File path(s) probed |
| `lines` | Line count |
| `estimated_tokens` | Token estimate for context budget |
| `extension` | File extension |
| `total_files` | File count (directory probe) |

**Preservation Rules** (configurable in `.loa.config.yaml`):

| Item | Status | Rationale |
|------|--------|-----------|
| NOTES.md Session Continuity | PRESERVED | Recovery anchor |
| NOTES.md Decision Log | PRESERVED | Audit trail |
| Trajectory entries | PRESERVED | External files |
| Active bead references | PRESERVED | Task continuity |
| Tool results | COMPACTABLE | Summarized after use |
| Thinking blocks | COMPACTABLE | Logged to trajectory |

**Simplified Checkpoint** (7 steps → 3 manual):
1. Verify Decision Log updated
2. Verify Bead updated
3. Verify EDD test scenarios

---

## Context Benchmark (v0.11.0)

Measure context management performance.

```bash
# Run benchmark
.claude/scripts/context-benchmark.sh run

# Set baseline
.claude/scripts/context-benchmark.sh baseline

# Compare against baseline
.claude/scripts/context-benchmark.sh compare

# View benchmark history
.claude/scripts/context-benchmark.sh history

# JSON output
.claude/scripts/context-benchmark.sh run --json
.claude/scripts/context-benchmark.sh run --save  # Save to analytics
```

**Target Metrics (v0.11.0)**:
- Token reduction: -15%
- Checkpoint steps: 3 (was 7)
- Recovery success: 100%

---

## RLM Benchmark (v0.15.0)

Benchmarks RLM (Relevance-based Loading Method) pattern effectiveness.

```bash
# Run benchmark on target codebase
.claude/scripts/rlm-benchmark.sh run --target ./src --json

# Create baseline for comparison
.claude/scripts/rlm-benchmark.sh baseline --target ./src

# Compare against baseline
.claude/scripts/rlm-benchmark.sh compare --target ./src --json

# Generate detailed report
.claude/scripts/rlm-benchmark.sh report --target ./src

# Multiple iterations for stability
.claude/scripts/rlm-benchmark.sh run --target ./src --iterations 3 --json
```

**Output Metrics**:
| Metric | Description |
|--------|-------------|
| `current_pattern.tokens` | Full-load token count |
| `current_pattern.files` | Total files analyzed |
| `rlm_pattern.tokens` | RLM-optimized token count |
| `rlm_pattern.savings_pct` | Token reduction percentage |
| `deltas.rlm_tokens` | Change from baseline |

**PRD Success Criteria**: ≥15% token reduction on realistic codebases.

---

## Schema Validator (v0.11.0)

Validates agent outputs against JSON schemas.

```bash
# Validate a file (auto-detects schema based on path)
.claude/scripts/schema-validator.sh validate grimoires/loa/prd.md

# List available schemas
.claude/scripts/schema-validator.sh list

# Override schema detection
.claude/scripts/schema-validator.sh validate output.json --schema prd

# Validation modes
.claude/scripts/schema-validator.sh validate file.md --mode strict   # Fail on errors
.claude/scripts/schema-validator.sh validate file.md --mode warn     # Warn only (default)
.claude/scripts/schema-validator.sh validate file.md --mode disabled # Skip validation

# JSON output for automation
.claude/scripts/schema-validator.sh validate file.md --json

# Programmatic assertions (for testing/automation)
.claude/scripts/schema-validator.sh assert file.json --schema prd --json
# Returns: {"status": "passed", "assertions": [...]} or {"status": "failed", "errors": [...]}
```

**Assert Command**: Programmatic validation for CI/CD and testing:
- Exit code 0 = passed, non-zero = failed
- JSON output includes `status`, `assertions`, `errors` fields
- Validates required fields, semver format, status enums

**Auto-Detection Rules**:
| Pattern | Schema |
|---------|--------|
| `**/prd.md`, `**/*-prd.md` | `prd.schema.json` |
| `**/sdd.md`, `**/*-sdd.md` | `sdd.schema.json` |
| `**/sprint.md`, `**/*-sprint.md` | `sprint.schema.json` |
| `**/trajectory/*.jsonl` | `trajectory-entry.schema.json` |

---

## Thinking Logger (v0.12.0)

Logs agent reasoning with extended thinking support.

```bash
# Log a simple entry
.claude/scripts/thinking-logger.sh log \
  --agent implementing-tasks \
  --action "Created user model" \
  --phase implementation

# Log with extended thinking
.claude/scripts/thinking-logger.sh log \
  --agent designing-architecture \
  --action "Evaluated patterns" \
  --thinking \
  --think-step "1:analysis:Consider microservices vs monolith" \
  --think-step "2:evaluation:Microservices adds complexity" \
  --think-step "3:decision:Chose modular monolith"

# Log with grounding citations
.claude/scripts/thinking-logger.sh log \
  --agent reviewing-code \
  --action "Found SQL injection" \
  --grounding code_reference \
  --ref "src/db.ts:45-50" \
  --confidence 0.95

# Read trajectory entries
.claude/scripts/thinking-logger.sh read grimoires/loa/a2a/trajectory/implementing-tasks-2025-01-11.jsonl --last 5

# Initialize trajectory directory
.claude/scripts/thinking-logger.sh init
```

**Thinking Step Format**: `step:type:thought`
- step: Integer (1, 2, 3...)
- type: analysis, hypothesis, evaluation, decision, reflection
- thought: Free-text description

**Grounding Types**:
- `citation`: Reference to documentation
- `code_reference`: Reference to source code
- `assumption`: Unverified claim (flagged)
- `user_input`: Based on user request
- `inference`: Derived from other facts

---

## Mermaid URL Generator (v1.10.0)

Generates Beautiful Mermaid preview URLs for diagram rendering.

```bash
# From file
.claude/scripts/mermaid-url.sh diagram.mmd

# From stdin
echo 'graph TD; A-->B' | .claude/scripts/mermaid-url.sh --stdin

# With custom theme
echo 'graph TD; A-->B' | .claude/scripts/mermaid-url.sh --stdin --theme dracula

# Check configuration
.claude/scripts/mermaid-url.sh --check
```

**Options**:
| Option | Description |
|--------|-------------|
| `--stdin` | Read Mermaid source from stdin |
| `--theme <name>` | Override theme (default: from config or github) |
| `--check` | Display visual communication config status |
| `--help` | Show usage information |

**Available Themes**:
- `github` (default), `dracula`, `nord`, `tokyo-night`
- `solarized-light`, `solarized-dark`, `catppuccin`

**Configuration** (`.loa.config.yaml`):
```yaml
visual_communication:
  enabled: true
  theme: "github"
  include_preview_urls: true
```

**Output**: Full URL to agents.craft.do/mermaid with base64-encoded diagram.

**Note**: If diagram source exceeds 1500 characters, a warning is displayed.

---

## Related Protocols

- `.claude/protocols/context-compaction.md` - Context preservation rules
- `.claude/protocols/upgrade-process.md` - Framework upgrade workflow
- `.claude/protocols/constructs-integration.md` - Registry integration
- `.claude/protocols/recommended-hooks.md` - Hook patterns
- `.claude/protocols/risk-analysis.md` - Pre-mortem analysis framework
- `.claude/protocols/visual-communication.md` - Visual output standards
