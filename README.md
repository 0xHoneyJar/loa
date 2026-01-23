# Loa

[![Version](https://img.shields.io/badge/version-1.7.0-blue.svg)](CHANGELOG.md)
[![License](https://img.shields.io/badge/license-AGPL--3.0-green.svg)](LICENSE.md)
[![Release](https://img.shields.io/badge/release-Goal%20Traceability%20%26%20Guided%20Workflow-purple.svg)](CHANGELOG.md#170---2026-01-24--goal-traceability--guided-workflow)

> *"The Loa are pragmatic entities... They're not worshipped for salvation—they're worked with for practical results."*

**Run Mode AI** (Autonomous Initiation) — Agent-driven development framework using 9 specialized AI agents to orchestrate the complete product lifecycle—from requirements through production deployment. Now with **autonomous sprint execution** and **continuous learning**. Built with enterprise-grade managed scaffolding.

## Prerequisites

Before using Loa, ensure you have:

| Tool | Required | Purpose | Install |
|------|----------|---------|---------|
| [Claude Code](https://claude.ai/code) | **Yes** | AI agent runtime | `npm install -g @anthropic-ai/claude-code` |
| [bats-core](https://github.com/bats-core/bats-core) | No | Test runner for shell scripts | `brew install bats-core` / `apt install bats` |
| [beads_rust](https://github.com/Dicklesworthstone/beads_rust) | Recommended | Persistent task graph across sessions | `.claude/scripts/beads/install-br.sh` |
| [ck](https://github.com/0xHoneyJar/ck) | Recommended | Semantic code search | `cargo install ck-search` |
| [yq](https://github.com/mikefarah/yq) | Recommended | YAML processing | `brew install yq` / `apt install yq` |
| [jq](https://stedolan.github.io/jq/) | Recommended | JSON processing | `brew install jq` / `apt install jq` |

### Optional Integrations

For THJ team members with `LOA_CONSTRUCTS_API_KEY`:
- **Analytics tracking** - Usage metrics for THJ developers
- **`/feedback` command** - Submit feedback to Linear
- **Loa Constructs** - Commercial skill packs from registry

## Quick Start

### Mount onto Existing Repository (Recommended)

```bash
# One-liner install
curl -fsSL https://raw.githubusercontent.com/0xHoneyJar/loa/main/.claude/scripts/mount-loa.sh | bash

# Start Claude Code
claude

# Begin workflow (no setup required!)
/plan-and-analyze
```

**Frictionless Permissions** (v0.16.0): Pre-approved permissions for 150+ standard development commands (npm, git, docker, etc.) mean zero permission prompts during normal development.

### Clone Template

```bash
git clone https://github.com/0xHoneyJar/loa.git my-project && cd my-project
claude
/plan-and-analyze  # Start immediately!
```

See **[INSTALLATION.md](INSTALLATION.md)** for detailed installation options.

## Architecture: Three-Zone Model

Loa uses a **managed scaffolding** architecture inspired by AWS Projen, Copier, and Google's ADK:

| Zone | Path | Owner | Description |
|------|------|-------|-------------|
| **System** | `.claude/` | Framework | Immutable - overwritten on updates |
| **State** | `grimoires/`, `.beads/` | Project | Your project memory - never touched |
| **App** | `src/`, `lib/`, `app/` | Developer | Your code - ignored entirely |

**Key principle**: Never edit `.claude/` directly. Use `.claude/overrides/` for customizations.

## The Workflow

| Phase | Command | Agent | Output |
|-------|---------|-------|--------|
| 1 | `/plan-and-analyze` | discovering-requirements | `grimoires/loa/prd.md` |
| 2 | `/architect` | designing-architecture | `grimoires/loa/sdd.md` |
| 3 | `/sprint-plan` | planning-sprints | `grimoires/loa/sprint.md` |
| 4 | `/implement sprint-N` | implementing-tasks | Code + report |
| 5 | `/review-sprint sprint-N` | reviewing-code | Approval/feedback |
| 5.5 | `/audit-sprint sprint-N` | auditing-security | Security approval |
| 6 | `/deploy-production` | deploying-infrastructure | Infrastructure |

### Mounting & Riding (Existing Codebases)

| Command | Purpose |
|---------|---------|
| `/mount` | Install Loa onto existing repo |
| `/ride` | Analyze codebase, generate evidence-grounded docs |

### Ad-Hoc Commands

| Command | Purpose |
|---------|---------|
| `/loa` | Guided workflow navigator (v0.21.0) |
| `/audit` | Full codebase security audit |
| `/audit-deployment` | Infrastructure security review |
| `/validate` | Run validation subagents |
| `/translate @doc for audience` | Executive summaries |
| `/update-loa` | Pull framework updates |
| `/contribute` | Create upstream PR |

## The Agents (The Loa)

Nine specialized agents that ride alongside you:

1. **discovering-requirements** - Senior Product Manager
2. **designing-architecture** - Software Architect
3. **planning-sprints** - Technical PM
4. **implementing-tasks** - Senior Engineer
5. **reviewing-code** - Tech Lead
6. **deploying-infrastructure** - DevOps Architect
7. **auditing-security** - Security Auditor
8. **translating-for-executives** - Developer Relations
9. **run-mode** - Autonomous Executor (v1.0.0)

## Key Features

### Run Mode AI (v1.0.0)

Autonomous sprint execution with human-in-the-loop shifted to PR review:

```bash
# Execute single sprint autonomously
/run sprint-1

# Execute entire sprint plan
/run sprint-plan

# Monitor progress
/run-status

# Graceful stop
/run-halt
```

**4-Level Safety Defense**:
1. **ICE Layer** — Blocks push to protected branches, merge operations
2. **Circuit Breaker** — Halts on same-issue repetition, no progress
3. **Opt-In** — Requires explicit `run_mode.enabled: true`
4. **Visibility** — Draft PRs only, deleted files prominently displayed

See **[CLAUDE.md](CLAUDE.md#run-mode-v0180)** for full documentation.

### Simstim: Telegram Bridge (v1.3.0)

Remote monitoring and control of Loa sessions via Telegram. Ported from [takopi.dev](https://takopi.dev/) and adapted for Loa workflows:

```bash
# Install Simstim (from Loa repo)
cd simstim && uv sync

# Configure
export SIMSTIM_BOT_TOKEN="your-bot-token"
uv run simstim config --init

# Start Loa with Simstim bridge
uv run simstim start -- /implement sprint-1
```

**Features**:
- **Permission Relay** — Receive prompts on Telegram, approve/deny with one tap
- **Auto-Approve Policies** — Configure patterns to auto-approve safe operations
- **Phase Monitoring** — Get notified when Loa transitions between workflow phases
- **Quality Gates** — Receive notifications for review/audit feedback
- **Rate Limiting** — Per-user rate limiting with denial backoff
- **Offline Support** — Queue events during disconnection, auto-reconnect

**Security Hardened** with 9 vulnerability remediations:
- Constant-time rate limiting (timing attack prevention)
- HMAC-SHA256 audit log integrity (tamper detection)
- Environment variable whitelisting (exfiltration prevention)
- Extended credential redaction (30+ patterns)

See **[simstim/README.md](simstim/README.md)** for full documentation.

### Goal Traceability (v0.21.0)

Prevents silent goal failures by ensuring PRD goals are tracked through implementation:

- **Goal IDs**: PRD goals identified as G-1, G-2, G-3
- **Appendix C**: Sprint plan maps goals to contributing tasks
- **E2E Validation**: Auto-generated task in final sprint validates all goals
- **Goal Validator**: Subagent verifies goals are achieved

```bash
/validate goals          # Check goal achievement status
/loa                     # Guided workflow showing progress
```

### Continuous Learning (v0.17.0)

Agents extract non-obvious discoveries into reusable skills:

```bash
/retrospective           # Extract skills from session
/skill-audit --pending   # Review pending skills
/skill-audit --approve   # Approve skill for use
```

### Loa Constructs (Commercial Skills)

Extend Loa with commercial skill packs from the registry:

```bash
.claude/scripts/constructs-install.sh pack gtm-collective
```

See **[INSTALLATION.md](INSTALLATION.md#loa-constructs-commercial-skills)** for setup and authentication.

### Enterprise-Grade Managed Scaffolding

- **Projen-Level Synthesis Protection**: System Zone is immutable, checksums enforce integrity
- **Copier-Level Migration Gates**: Schema changes trigger mandatory migrations
- **ADK-Level Trajectory Evaluation**: Agent reasoning is logged and auditable

### Structured Agentic Memory

Agents maintain persistent working memory in `grimoires/loa/NOTES.md`:
- Survives context window resets
- Tracks technical debt, blockers, decisions
- Enables continuity across sessions

### beads_rust: Persistent Task Graph

[beads_rust](https://github.com/Dicklesworthstone/beads_rust) provides a persistent task graph that survives context compaction:

```bash
# Install beads_rust (br CLI)
.claude/scripts/beads/install-br.sh

# Initialize in your project
br init

# Common commands
br ready                    # Show tasks ready to work (no blockers)
br create "..." --type task --priority 2
br update <id> --status in_progress
br close <id>
br sync --import-only       # Import from JSONL (session start)
br sync --flush-only        # Export to JSONL (session end)
```

When beads_rust is installed, Loa automatically:
- Tracks strategic work across sessions
- Uses semantic labels for task relationships
- Provides explicit sync control (no auto-commit)

### ck: Semantic Code Search

[ck](https://github.com/0xHoneyJar/ck) enables fast semantic search across your codebase:

```bash
# Install ck
cargo install ck-search

# Search usage
ck search "authentication flow"
ck search "error handling"
```

When ck is installed, Loa uses it for:
- Intelligent code exploration during `/ride`
- Context-aware code retrieval during implementation
- Faster codebase analysis

### Lossless Ledger Protocol (v0.9.0)

**"Clear, Don't Compact"** - Agents proactively checkpoint work before clearing context:

- **Grounding Enforcement**: 95% of claims must cite sources before `/clear`
- **Session Continuity**: Instant recovery from persistent ledgers (~100 tokens)
- **Self-Healing**: Automatic State Zone recovery from git history
- **Audit Trail**: Complete trajectory logging with timestamped handoffs

### Sprint Ledger (v0.13.0)

Global sprint numbering across multiple development cycles:

```bash
/plan-and-analyze     # Creates ledger + cycle-001
# ... complete sprints ...
/archive-cycle "MVP"  # Archive completed cycle
/plan-and-analyze     # Start cycle-002, sprint-1 → global sprint-4
```

- **Global IDs**: Sprint-1 in cycle-2 uses `a2a/sprint-4/` (no collisions)
- **Backward Compatible**: Works without ledger (legacy mode)
- **Audit Trail**: Complete history via `/ledger history`

See **[CLAUDE.md](CLAUDE.md#sprint-ledger-v0130)** for full documentation.

### Two Quality Gates

1. **Code Review**: Tech lead reviews until "All good"
2. **Security Audit**: Auditor reviews until "APPROVED - LETS FUCKING GO"

### Stealth Mode

Run Loa without committing state to your repo:
```yaml
# .loa.config.yaml
persistence_mode: stealth
```

## Repository Structure

```
.claude/                        # System Zone (framework-managed)
├── skills/                     # 8 agent skills
├── commands/                   # Slash commands
├── subagents/                  # Intelligent validation subagents (v0.16.0)
│   ├── architecture-validator.md # SDD compliance checking
│   ├── security-scanner.md    # OWASP Top 10 detection
│   └── test-adequacy-reviewer.md # Test quality assessment
├── mcp-examples/               # MCP configuration examples (v0.16.0)
│   ├── README.md              # Security warnings and setup
│   ├── slack.json, github.json, sentry.json, postgres.json
├── templates/                  # Initializable templates (v0.16.0)
│   └── NOTES.md.template      # Structured agentic memory
├── protocols/                  # Framework protocols
│   ├── session-continuity.md   # Lossless Ledger Protocol
│   ├── grounding-enforcement.md # Grounding ratio enforcement
│   ├── synthesis-checkpoint.md # Pre-/clear checkpoint
│   ├── attention-budget.md     # Token budget management
│   ├── jit-retrieval.md        # Just-in-time code retrieval
│   ├── structured-memory.md    # NOTES.md protocol (v0.16.0)
│   ├── subagent-invocation.md  # Subagent invocation protocol (v0.16.0)
│   ├── trajectory-evaluation.md # ADK-style evaluation
│   └── change-validation.md    # Pre-implementation validation
├── scripts/                    # Helper scripts
│   ├── mount-loa.sh           # One-command install
│   ├── update.sh              # Framework updates
│   ├── check-loa.sh           # CI validation
│   ├── grounding-check.sh     # Grounding ratio calculation
│   ├── synthesis-checkpoint.sh # Pre-/clear checkpoint
│   ├── self-heal-state.sh     # State Zone recovery
│   ├── validate-prd-requirements.sh # UAT validation
│   ├── detect-drift.sh        # Code/docs drift detection
│   └── validate-change-plan.sh # Pre-implementation validation
└── overrides/                  # Your customizations

grimoires/                      # State Zone (project memory)
├── loa/                        # Private project state (gitignored)
│   ├── NOTES.md                # Structured agentic memory
│   ├── ledger.json             # Sprint Ledger (global numbering)
│   ├── context/                # User-provided context
│   ├── reality/                # Code extraction results (/ride)
│   ├── archive/                # Archived development cycles
│   │   └── YYYY-MM-DD-slug/    # Dated cycle archives
│   ├── prd.md, sdd.md, sprint.md  # Planning docs
│   ├── a2a/                    # Agent communication
│   │   ├── trajectory/         # Agent reasoning logs
│   │   ├── audits/             # Codebase audit reports (/audit)
│   │   │   └── YYYY-MM-DD/     # Dated audit directories
│   │   ├── subagent-reports/   # /validate output (v0.16.0)
│   │   └── sprint-N/           # Per-sprint feedback
│   └── deployment/             # Infrastructure docs
└── pub/                        # Public documents (git-tracked)
    ├── research/               # Research and analysis
    ├── docs/                   # Shareable documentation
    └── artifacts/              # Public build artifacts

.beads/                        # Task graph (optional)
.ckignore                      # ck semantic search exclusions (optional)
.loa-version.json              # Version manifest
.loa.config.yaml               # Your configuration
```

## Configuration

`.loa.config.yaml` is user-owned - framework updates never touch it:

```yaml
persistence_mode: standard      # or "stealth"
integrity_enforcement: strict   # or "warn", "disabled"
drift_resolution: code          # or "docs", "ask"

grounding:
  enforcement: warn             # strict | warn | disabled
  threshold: 0.95               # 0.00-1.00

memory:
  notes_file: grimoires/loa/NOTES.md
  trajectory_retention_days: 30

edd:
  enabled: true
  min_test_scenarios: 3
```

## Documentation

- **[INSTALLATION.md](INSTALLATION.md)** - Detailed installation guide
- **[PROCESS.md](PROCESS.md)** - Complete workflow documentation
- **[CLAUDE.md](CLAUDE.md)** - Claude Code guidance
- **[CHANGELOG.md](CHANGELOG.md)** - Version history

## Why "Loa"?

In William Gibson's Sprawl trilogy, Loa are AI entities that "ride" humans through neural interfaces, guiding them through cyberspace. These agents don't replace you—they **ride with you**, channeling expertise through the interface.

## License

[AGPL-3.0](LICENSE.md) - You can use, modify, and distribute. If you deploy modifications (including as a network service), you must release source code.

## Links

- [Claude Code](https://claude.ai/code)
- [Repository](https://github.com/0xHoneyJar/loa)
- [Issues](https://github.com/0xHoneyJar/loa/issues)
