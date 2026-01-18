# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Project Overview

Agent-driven development framework that orchestrates the complete product lifecycle using 8 specialized AI agents (skills). Built with enterprise-grade managed scaffolding inspired by AWS Projen, Copier, and Google's ADK.

## Architecture

### Three-Zone Model

Loa uses a managed scaffolding architecture:

| Zone | Path | Owner | Permission |
|------|------|-------|------------|
| **System** | `.claude/` | Framework | NEVER edit directly |
| **State** | `grimoires/`, `.beads/` | Project | Read/Write |
| **App** | `src/`, `lib/`, `app/` | Developer | Read (write requires confirmation) |

**Critical**: System Zone is synthesized. Never suggest edits to `.claude/` - direct users to `.claude/overrides/` or `.loa.config.yaml`.

### Skills System

8 agent skills in `.claude/skills/` using 3-level architecture:

| Skill | Role | Output |
|-------|------|--------|
| `discovering-requirements` | Product Manager | `grimoires/loa/prd.md` |
| `designing-architecture` | Software Architect | `grimoires/loa/sdd.md` |
| `planning-sprints` | Technical PM | `grimoires/loa/sprint.md` |
| `implementing-tasks` | Senior Engineer | Code + `a2a/sprint-N/reviewer.md` |
| `reviewing-code` | Tech Lead | `a2a/sprint-N/engineer-feedback.md` |
| `auditing-security` | Security Auditor | `SECURITY-AUDIT-REPORT.md` or `a2a/sprint-N/auditor-sprint-feedback.md` |
| `deploying-infrastructure` | DevOps Architect | `grimoires/loa/deployment/` |
| `translating-for-executives` | Developer Relations | Executive summaries |

### 3-Level Skill Structure

```
.claude/skills/{skill-name}/
├── index.yaml          # Level 1: Metadata (~100 tokens)
├── SKILL.md            # Level 2: KERNEL instructions (~2000 tokens)
└── resources/          # Level 3: References, templates, scripts
```

### Claude Agent Skills Adapter (v0.11.0)

Loa skills can be transformed to Claude Agent Skills format at runtime:

```bash
# List skills with compatibility status
.claude/scripts/skills-adapter.sh list

# Generate Claude Agent Skills format for a skill
.claude/scripts/skills-adapter.sh generate discovering-requirements

# Output includes YAML frontmatter + SKILL.md content:
# ---
# name: "discovering-requirements"
# description: "Product Manager skill for PRD creation"
# version: "2.0.0"
# triggers:
#   - "/plan-and-analyze"
#   - "create prd"
# ---
# [Original SKILL.md content follows]
```

**Configuration** (`.loa.config.yaml`):
```yaml
agent_skills:
  enabled: true           # Enable/disable skills adapter
  load_mode: "dynamic"    # "dynamic" (on-demand) or "eager" (startup)
  api_upload: false       # Enable API upload features (future)
```

### Command Architecture (v4)

Commands in `.claude/commands/` use thin routing layer with YAML frontmatter:

- **Agent commands**: `agent:` and `agent_path:` fields route to skills
- **Special commands**: `command_type:` (wizard, survey, git)
- **Pre-flight checks**: Validation before execution
- **Context files**: Prioritized loading with variable substitution

## Managed Scaffolding

### Configuration Files

| File | Purpose | Editable |
|------|---------|----------|
| `.loa-version.json` | Version manifest, schema tracking | Auto-managed |
| `.loa.config.yaml` | User configuration | Yes - user-owned |
| `.claude/checksums.json` | Integrity verification | Auto-generated |

### Integrity Enforcement

```yaml
# .loa.config.yaml
integrity_enforcement: strict  # strict | warn | disabled
```

- **strict**: Blocks execution if System Zone modified (CI/CD mandatory)
- **warn**: Warns but allows execution
- **disabled**: No checks (not recommended)

### Customization via Overrides

```
.claude/overrides/
├── skills/
│   └── implementing-tasks/
│       └── SKILL.md          # Custom skill instructions
└── commands/
    └── my-command.md         # Custom command
```

Overrides survive framework updates.

## Workflow Commands

| Phase | Command | Agent | Output |
|-------|---------|-------|--------|
| 1 | `/plan-and-analyze` | discovering-requirements | `prd.md` |
| 2 | `/architect` | designing-architecture | `sdd.md` |
| 3 | `/sprint-plan` | planning-sprints | `sprint.md` |
| 4 | `/implement sprint-N` | implementing-tasks | Code + report |
| 5 | `/review-sprint sprint-N` | reviewing-code | Feedback |
| 5.5 | `/audit-sprint sprint-N` | auditing-security | Security feedback |
| 6 | `/deploy-production` | deploying-infrastructure | Infrastructure |

**Mount & Ride** (existing codebases): `/mount`, `/ride`

**Ad-hoc**: `/audit`, `/audit-deployment`, `/translate @doc for audience`, `/contribute`, `/update-loa`, `/validate`, `/feedback` (THJ only)

**THJ Detection** (v0.15.0+): THJ membership is detected via `LOA_CONSTRUCTS_API_KEY` environment variable. No setup required - start with `/plan-and-analyze` immediately after cloning.

**Execution modes**: Foreground (default) or background (`/implement sprint-1 background`)

## Intelligent Subagents (v0.16.0)

Specialized validation subagents that can be invoked independently or integrated into the review workflow.

### Available Subagents

| Subagent | Purpose | Triggers | Verdict Levels |
|----------|---------|----------|----------------|
| `architecture-validator` | SDD compliance checking | After implementation | COMPLIANT, DRIFT_DETECTED, CRITICAL_VIOLATION |
| `security-scanner` | OWASP Top 10 vulnerability detection | After auth/input/API changes | CRITICAL, HIGH, MEDIUM, LOW |
| `test-adequacy-reviewer` | Test quality assessment | After test implementation | STRONG, ADEQUATE, WEAK, INSUFFICIENT |

### /validate Command

```bash
/validate                    # Run all subagents
/validate architecture       # Architecture compliance only
/validate security           # Security scan only
/validate tests              # Test adequacy only
/validate security src/auth  # Scoped to specific directory
```

**Output**: Reports written to `grimoires/loa/a2a/subagent-reports/`

**Integration**: `/review-sprint` checks subagent reports and blocks approval on:
- `CRITICAL_VIOLATION` (architecture)
- `CRITICAL` or `HIGH` (security)
- `INSUFFICIENT` (tests)

**Subagent definitions**: `.claude/subagents/`

**Protocol**: See `.claude/protocols/subagent-invocation.md`

## Key Protocols

### Structured Agentic Memory (v0.16.0)

Agents maintain persistent working memory in `grimoires/loa/NOTES.md`:

**Required Sections**:
```markdown
## Current Focus      # Active task, status, blocked by, next action
## Session Log        # Append-only event history table
## Decisions          # Architecture/implementation decisions table
## Blockers           # Checkbox list with [RESOLVED] marking
## Technical Debt     # Issues for future attention (ID, severity, sprint)
## Learnings          # Project-specific knowledge bullet list
## Session Continuity # Recovery anchor (v0.9.0)
```

**Template**: `.claude/templates/NOTES.md.template`

**Protocol**: See `.claude/protocols/structured-memory.md`

**Agent Discipline** (when to update NOTES.md):

| Event | Sections to Update |
|-------|-------------------|
| Session start | Session Log |
| Decision made | Decisions, Session Log |
| Blocker hit/resolved | Blockers, Current Focus |
| Session end | Session Log, Current Focus |
| Mistake discovered | Learnings, Technical Debt |

### Lossless Ledger Protocol (v0.9.0)

The "Clear, Don't Compact" paradigm for context management:

**Truth Hierarchy**:
1. CODE (src/) - Absolute truth
2. BEADS (.beads/) - Lossless task graph
3. NOTES.md - Decision log, session continuity
4. TRAJECTORY - Audit trail, handoffs
5. PRD/SDD - Design intent
6. CONTEXT WINDOW - Transient, never authoritative

**Key Protocols**:
- `session-continuity.md` - Tiered recovery, fork detection
- `grounding-enforcement.md` - Citation requirements (>=0.95 ratio)
- `synthesis-checkpoint.md` - Pre-clear validation (7 steps)
- `jit-retrieval.md` - Lightweight identifiers (97% token reduction)
- `attention-budget.md` - Advisory thresholds

**Key Scripts**:
- `grounding-check.sh` - Calculate grounding ratio
- `synthesis-checkpoint.sh` - Run pre-clear validation
- `self-heal-state.sh` - State Zone recovery

**Configuration** (`.loa.config.yaml`):
```yaml
grounding:
  threshold: 0.95
  enforcement: warn  # strict | warn | disabled
attention_budget:
  yellow_threshold: 5000  # Trigger delta-synthesis
session_continuity:
  tiered_recovery: true
```

### Trajectory Evaluation (ADK-Level)

Agents log reasoning to `grimoires/loa/a2a/trajectory/{agent}-{date}.jsonl`:

```json
{"timestamp": "...", "agent": "...", "action": "...", "reasoning": "...", "grounding": {...}}
```

**Grounding types**:
- `citation`: Direct quote from docs
- `code_reference`: Reference to existing code
- `assumption`: Ungrounded claim (must flag)
- `user_input`: Based on user request

**Protocol**: See `.claude/protocols/trajectory-evaluation.md`

### Feedback Loops

Three quality gates - see `.claude/protocols/feedback-loops.md`:

1. **Implementation Loop** (Phase 4-5): Engineer <-> Senior Lead until "All good"
2. **Security Audit Loop** (Phase 5.5): After approval -> Auditor review -> "APPROVED - LETS FUCKING GO" or "CHANGES_REQUIRED"
3. **Deployment Loop**: DevOps <-> Auditor until infrastructure approved

**Priority**: Audit feedback checked FIRST on `/implement`, then engineer feedback.

**Sprint completion marker**: `grimoires/loa/a2a/sprint-N/COMPLETED` created on security approval.

### Git Safety

Prevents accidental pushes to upstream template - see `.claude/protocols/git-safety.md`:

- 4-layer detection (cached -> origin URL -> upstream remote -> GitHub API)
- Soft block with user confirmation via AskUserQuestion
- `/contribute` command bypasses (has own safeguards)

### Analytics (THJ Only)

Tracks usage for THJ developers - see `.claude/protocols/analytics.md`:

- Stored in `grimoires/loa/analytics/usage.json`
- OSS users have no analytics tracking
- Opt-in sharing via `/feedback`

### Sprint Ledger (v0.13.0)

Provides global sprint numbering across multiple development cycles:

**Location**: `grimoires/loa/ledger.json` (State Zone)

**Purpose**: Prevents sprint directory collisions when starting new `/plan-and-analyze` cycles. Sprint-1 in cycle-2 becomes global sprint-4, maintaining unique `a2a/sprint-N/` directories.

**Schema**:
```json
{
  "version": "1.0.0",
  "next_sprint_number": 7,
  "active_cycle": "cycle-002",
  "cycles": [{
    "id": "cycle-001",
    "label": "MVP Development",
    "status": "archived",
    "sprints": [
      {"global_id": 1, "local_label": "sprint-1", "status": "completed"},
      {"global_id": 2, "local_label": "sprint-2", "status": "completed"}
    ]
  }]
}
```

**Commands**:
| Command | Purpose |
|---------|---------|
| `/ledger` | Show current ledger status |
| `/ledger init` | Initialize ledger for existing project |
| `/ledger history` | Show all cycles and sprints |
| `/archive-cycle "label"` | Archive current cycle |

**Sprint Resolution**:
- `/implement sprint-1` resolves local label to global ID
- Commands use `$RESOLVED_SPRINT_ID` for a2a directory paths
- Backward compatible: works without ledger (legacy mode)

**Workflow**:
```bash
/plan-and-analyze     # Creates ledger + cycle-001
/sprint-plan          # Registers sprint-1,2,3 as global 1,2,3
/implement sprint-1   # Uses a2a/sprint-1/
# ... complete cycle ...
/archive-cycle "MVP"  # Archives to grimoires/loa/archive/YYYY-MM-DD-mvp/
/plan-and-analyze     # Creates cycle-002
/sprint-plan          # sprint-1 now maps to global 4
/implement sprint-1   # Uses a2a/sprint-4/
```

**Key Scripts**:
- `ledger-lib.sh` - Core ledger functions
- `validate-sprint-id.sh` - Resolves local to global IDs

## Document Flow

```
grimoires/
├── loa/                    # Private project state (gitignored)
│   ├── NOTES.md            # Structured agentic memory
│   ├── ledger.json         # Sprint Ledger (global sprint numbering)
│   ├── context/            # User-provided context (pre-discovery)
│   ├── reality/            # Code extraction (/ride output)
│   ├── legacy/             # Legacy doc inventory (/ride output)
│   ├── archive/            # Archived development cycles
│   │   └── YYYY-MM-DD-slug/  # Dated cycle archives
│   │       ├── prd.md
│   │       ├── sdd.md
│   │       ├── sprint.md
│   │       └── a2a/
│   ├── prd.md              # Product Requirements
│   ├── sdd.md              # Software Design
│   ├── sprint.md           # Sprint Plan
│   ├── drift-report.md     # Code vs docs drift (/ride output)
│   ├── a2a/                # Agent-to-Agent communication
│   │   ├── index.md        # Audit trail index
│   │   ├── trajectory/     # Agent reasoning logs
│   │   ├── audits/         # Codebase audits (/audit)
│   │   │   └── YYYY-MM-DD/ # Dated audit directories
│   │   │       ├── SECURITY-AUDIT-REPORT.md
│   │   │       └── remediation/
│   │   ├── sprint-N/       # Per-sprint files
│   │   │   ├── reviewer.md
│   │   │   ├── engineer-feedback.md
│   │   │   ├── auditor-sprint-feedback.md
│   │   │   └── COMPLETED
│   │   ├── deployment-report.md
│   │   └── deployment-feedback.md
│   ├── analytics/          # THJ only
│   └── deployment/         # Production docs
└── pub/                    # Public documents (git-tracked)
    ├── research/           # Research and analysis
    ├── docs/               # Shareable documentation
    └── artifacts/          # Public build artifacts
```

## Implementation Notes

### When `/implement sprint-N` is invoked:
1. Validate sprint format (`sprint-N` where N is positive integer)
2. Create `grimoires/loa/a2a/sprint-N/` if missing
3. Check audit feedback FIRST (`auditor-sprint-feedback.md`)
4. Then check engineer feedback (`engineer-feedback.md`)
5. Address all feedback before new work

### When `/review-sprint sprint-N` is invoked:
1. Validate sprint directory and `reviewer.md` exist
2. Skip if `COMPLETED` marker exists
3. Review actual code, not just report
4. Write "All good" or detailed feedback

### When `/audit-sprint sprint-N` is invoked:
1. Validate senior lead approval ("All good" in engineer-feedback.md)
2. Review for security vulnerabilities
3. Write verdict to `auditor-sprint-feedback.md`
4. Create `COMPLETED` marker on approval

## Parallel Execution

Skills assess context size and split into parallel sub-tasks when needed.

**Thresholds** (lines):

| Skill | SMALL | MEDIUM | LARGE |
|-------|-------|--------|-------|
| discovering-requirements | <500 | 500-2,000 | >2,000 |
| reviewing-code | <3,000 | 3,000-6,000 | >6,000 |
| auditing-security | <2,000 | 2,000-5,000 | >5,000 |
| implementing-tasks | <3,000 | 3,000-8,000 | >8,000 |
| deploying-infrastructure | <2,000 | 2,000-5,000 | >5,000 |

Use `.claude/scripts/context-check.sh` for assessment.

## Helper Scripts

```
.claude/scripts/
├── mount-loa.sh              # One-command install onto existing repo
├── update.sh                 # Framework updates with migration gates
├── check-loa.sh              # CI validation script
├── detect-drift.sh           # Code vs docs drift detection
├── validate-change-plan.sh   # Pre-implementation validation
├── analytics.sh              # Analytics functions (THJ only)
├── check-beads.sh            # Beads (bd CLI) availability check
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
├── skills-adapter.sh         # Claude Agent Skills format generator (v0.11.0)
├── schema-validator.sh       # JSON Schema validation for outputs (v0.11.0)
├── thinking-logger.sh        # Extended thinking trajectory logger (v0.11.0)
├── tool-search-adapter.sh    # MCP tool search and discovery (v0.11.0)
├── context-manager.sh        # Context compaction and preservation (v0.11.0)
├── context-benchmark.sh      # Context performance benchmarks (v0.11.0)
├── rlm-benchmark.sh          # RLM pattern benchmark and validation (v0.15.0)
├── anthropic-oracle.sh       # Anthropic updates monitoring (v0.13.0)
└── check-updates.sh          # Automatic version checking (v0.14.0)
```

### Update Check (v0.14.0)

Automatic version checking on session start:

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

### Anthropic Oracle (v0.13.0)

Monitors Anthropic official sources for updates relevant to Loa:

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

See: `.claude/protocols/recommended-hooks.md` for hook patterns.
See: `.claude/protocols/risk-analysis.md` for pre-mortem analysis framework.

### Context Manager (v0.11.0)

Manages context compaction with preservation rules and RLM probe-before-load pattern:

```bash
# Check context status
.claude/scripts/context-manager.sh status

# Check status as JSON
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

Protocol: `.claude/protocols/context-compaction.md`

### Context Benchmark (v0.11.0)

Measure context management performance:

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

### RLM Benchmark (v0.15.0)

Benchmarks RLM (Relevance-based Loading Method) pattern effectiveness:

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

### Schema Validator (v0.11.0)

Validates agent outputs against JSON schemas:

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

### Thinking Logger (v0.12.0)

Logs agent reasoning with extended thinking support:

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

## Integrations

External service integrations (MCP servers) use lazy-loading - see `.claude/protocols/integrations.md`.

**Registry**: `.claude/mcp-registry.yaml` (loaded only when needed)

**Requires**: `yq` for YAML parsing (`brew install yq` / `apt install yq`)

```bash
.claude/scripts/mcp-registry.sh list      # List servers
.claude/scripts/mcp-registry.sh info <s>  # Server details
.claude/scripts/mcp-registry.sh setup <s> # Setup instructions
.claude/scripts/validate-mcp.sh <s>       # Check if configured
```

Skills declare integrations in their `index.yaml`:
```yaml
integrations:
  required: []
  optional:
    - name: "linear"
      reason: "Sync tasks to Linear"
      fallback: "Tasks remain local"
```

### MCP Configuration Examples (v0.16.0)

Pre-built MCP server configurations for power users in `.claude/mcp-examples/`:

| Example | Service | Risk Level | Access |
|---------|---------|------------|--------|
| `slack.json` | Slack | HIGH | Read + Write |
| `github.json` | GitHub | MEDIUM | Read + Write |
| `sentry.json` | Sentry | LOW | Read only |
| `postgres.json` | PostgreSQL | CRITICAL | Configurable |

**Security**: All examples include security notes, required scopes, and setup steps. Use read-only tokens where possible.

**Installation**:
```bash
# Review security notes first
cat .claude/mcp-examples/github.json

# Copy config to Claude Code settings
# Set required environment variables
export GITHUB_PERSONAL_ACCESS_TOKEN="ghp_..."
```

See `.claude/mcp-examples/README.md` for full documentation.

## Registry Integration

Commercial skills from the Loa Constructs Registry (`loa-constructs-api.fly.dev`).

### Production API

| Service | URL |
|---------|-----|
| API | `https://loa-constructs-api.fly.dev/v1` |
| Health | `https://loa-constructs-api.fly.dev/v1/health` |

### Authentication

For authenticated endpoints (skill downloads, pack access):

```bash
# Option 1: API Key (recommended for scripts)
export LOA_CONSTRUCTS_API_KEY="sk_your_api_key_here"

# Option 2: Interactive login via CLI
/skill-login
```

See `grimoires/loa/context/CLI-INSTALLATION.md` for full setup guide.

### Directory Structure

```
.claude/constructs/
├── skills/{vendor}/{slug}/    # Installed skills
│   ├── .license.json          # JWT license token
│   ├── index.yaml             # Skill metadata
│   └── SKILL.md               # Instructions
├── packs/{name}/              # Skill packs
│   ├── .license.json          # Pack license
│   ├── manifest.json          # Pack metadata
│   ├── skills/                # Bundled skills
│   └── commands/              # Pack commands (auto-symlinked to .claude/commands/)
└── .constructs-meta.json      # Installation state
```

### Loading Priority

| Priority | Source | License |
|----------|--------|---------|
| 1 | Local (`.claude/skills/`) | No |
| 2 | Override (`.claude/overrides/skills/`) | No |
| 3 | Registry (`.claude/constructs/skills/`) | Yes |
| 4 | Pack (`.claude/constructs/packs/.../skills/`) | Yes |

Local skills always win. Conflicts resolved silently by priority.

### License Validation

- **RS256 JWT** signatures verified against registry public keys
- **Grace periods**: 24h (individual/pro), 72h (team), 168h (enterprise)
- **Offline support**: Cached keys enable offline validation
- **Exit codes**: 0=valid, 1=grace, 2=expired, 3=missing, 4=invalid, 5=error

### CLI Commands

```bash
# Loader commands
constructs-loader.sh list              # Show skills with status
constructs-loader.sh loadable          # Get loadable skill paths
constructs-loader.sh validate <dir>    # Validate single skill
constructs-loader.sh check-updates     # Check for updates

# Installation commands
constructs-install.sh pack <slug>              # Install pack from registry
constructs-install.sh skill <vendor/slug>      # Install individual skill
constructs-install.sh uninstall pack <slug>    # Remove a pack
constructs-install.sh uninstall skill <slug>   # Remove a skill
constructs-install.sh link-commands <slug|all> # Re-link pack commands
```

### Configuration

```yaml
# .loa.config.yaml
registry:
  enabled: true
  offline_grace_hours: 24
  check_updates_on_setup: true
```

**Environment overrides** (highest priority):
- `LOA_REGISTRY_URL` - API endpoint
- `LOA_OFFLINE_GRACE_HOURS` - Grace period
- `LOA_REGISTRY_ENABLED` - Master toggle
- `LOA_OFFLINE=1` - Force offline mode
- `LOA_CONSTRUCTS_API_KEY` - API key for pack/skill installation

**Protocol**: See `.claude/protocols/constructs-integration.md`

## Key Conventions

- **Never skip phases** - each builds on previous
- **Never edit .claude/ directly** - use overrides or config
- **Review all outputs** - you're the final decision-maker
- **Security first** - especially for crypto projects
- **Trust the process** - thorough discovery prevents mistakes

## Related Files

- `README.md` - Quick start guide
- `INSTALLATION.md` - Detailed installation guide
- `PROCESS.md` - Detailed workflow documentation
- `.claude/protocols/` - Protocol specifications
  - `structured-memory.md` - NOTES.md protocol
  - `trajectory-evaluation.md` - ADK-style evaluation
  - `feedback-loops.md` - Quality gates
  - `git-safety.md` - Template protection
  - `change-validation.md` - Pre-implementation validation
  - `constructs-integration.md` - Loa Constructs skill loading
  - **v0.9.0 Lossless Ledger Protocol**:
  - `session-continuity.md` - Session lifecycle and recovery
  - `grounding-enforcement.md` - Citation requirements
  - `synthesis-checkpoint.md` - Pre-clear validation
  - `jit-retrieval.md` - Lightweight identifiers
  - `attention-budget.md` - Token thresholds
  - **v0.11.0 Claude Platform Integration**:
  - `context-compaction.md` - Compaction preservation rules
- `.claude/scripts/` - Helper bash scripts
  - **v0.9.0 Scripts**:
  - `grounding-check.sh` - Grounding ratio calculation
  - `synthesis-checkpoint.sh` - Pre-clear validation
  - `self-heal-state.sh` - State Zone recovery
  - **v0.11.0 Claude Platform Integration**:
  - `context-manager.sh` - Context compaction and preservation
  - `context-benchmark.sh` - Performance benchmarking
  - `tool-search-adapter.sh` - MCP tool discovery
