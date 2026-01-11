# Loa

[![Version](https://img.shields.io/badge/version-0.11.0-blue.svg)](CHANGELOG.md)
[![License](https://img.shields.io/badge/license-AGPL--3.0-green.svg)](LICENSE.md)

> *"The Loa are pragmatic entities... They're not worshipped for salvation—they're worked with for practical results."*

Agent-driven development framework using 8 specialized AI agents to orchestrate the complete product lifecycle—from requirements through production deployment. Built with enterprise-grade managed scaffolding.

## Quick Start

### Mount onto Existing Repository (Recommended)

```bash
# One-liner install
curl -fsSL https://raw.githubusercontent.com/0xHoneyJar/loa/main/.claude/scripts/mount-loa.sh | bash

# Start Claude Code
claude

# Run setup
/setup

# Begin workflow
/plan-and-analyze
```

### Clone Template

```bash
git clone https://github.com/0xHoneyJar/loa.git my-project && cd my-project
claude
/setup
/plan-and-analyze
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
| 0 | `/setup` | - | `.loa-setup-complete` |
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
| `/audit` | Full codebase security audit |
| `/audit-deployment` | Infrastructure security review |
| `/translate @doc for audience` | Executive summaries |
| `/update` | Pull framework updates |
| `/contribute` | Create upstream PR |

## The Agents (The Loa)

Eight specialized agents that ride alongside you:

1. **discovering-requirements** - Senior Product Manager
2. **designing-architecture** - Software Architect
3. **planning-sprints** - Technical PM
4. **implementing-tasks** - Senior Engineer
5. **reviewing-code** - Tech Lead
6. **deploying-infrastructure** - DevOps Architect
7. **auditing-security** - Security Auditor
8. **translating-for-executives** - Developer Relations

## Key Features

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

### Lossless Ledger Protocol (v0.9.0)

**"Clear, Don't Compact"** - Agents proactively checkpoint work before clearing context:

- **Grounding Enforcement**: 95% of claims must cite sources before `/clear`
- **Session Continuity**: Instant recovery from persistent ledgers (~100 tokens)
- **Self-Healing**: Automatic State Zone recovery from git history
- **Audit Trail**: Complete trajectory logging with timestamped handoffs

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
├── protocols/                  # Framework protocols
│   ├── session-continuity.md   # Lossless Ledger Protocol
│   ├── grounding-enforcement.md # Grounding ratio enforcement
│   ├── synthesis-checkpoint.md # Pre-/clear checkpoint
│   ├── attention-budget.md     # Token budget management
│   ├── jit-retrieval.md        # Just-in-time code retrieval
│   ├── structured-memory.md    # NOTES.md protocol
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
│   ├── context/                # User-provided context
│   ├── reality/                # Code extraction results (/ride)
│   ├── prd.md, sdd.md, sprint.md  # Planning docs
│   ├── a2a/                    # Agent communication
│   │   ├── trajectory/         # Agent reasoning logs
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
