# Loa

<!-- AGENT-CONTEXT: Loa is an agent-driven development framework for Claude Code.
Primary interface: 5 Golden Path commands (/loa, /plan, /build, /review, /ship).
Power user interface: 47 slash commands (truenames).
Architecture: Three-zone model (System: .claude/, State: grimoires/ + .beads/, App: src/).
Configuration: .loa.config.yaml (user-owned, never modified by framework).
Health check: /loa doctor
Version: 1.36.0
-->

[![Version](https://img.shields.io/badge/version-1.39.1-blue.svg)](CHANGELOG.md)
[![License](https://img.shields.io/badge/license-AGPL--3.0-green.svg)](LICENSE.md)
[![Release](https://img.shields.io/badge/release-Post--Merge%20Automation-purple.svg)](CHANGELOG.md#1360---2026-02-13)

> *"The Loa are pragmatic entities... They're not worshipped for salvation—they're worked with for practical results."*

## What Is This?

Loa is an agent-driven development framework for [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview) (Anthropic's official CLI). It adds 17 specialized AI agents, quality gates, persistent memory, and structured workflows on top of Claude Code. Works on macOS and Linux. Created by [@janitooor](https://github.com/janitooor) at [The Honey Jar](https://0xhoneyjar.xyz).

### Why "Loa"?

In William Gibson's Sprawl trilogy, Loa are AI entities that "ride" humans through neural interfaces. These agents don't replace you—they **ride with you**, channeling expertise through the interface.

## Quick Start (~2 minutes)

**Prerequisites**: [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview) (Anthropic's CLI for Claude), Git, jq, [yq v4+](https://github.com/mikefarah/yq). See **[INSTALLATION.md](INSTALLATION.md)** for full details.

```bash
# Install (one command, any existing repo — adds Loa as git submodule)
curl -fsSL https://raw.githubusercontent.com/0xHoneyJar/loa/main/.claude/scripts/mount-loa.sh | bash

# Or pin to a specific version
curl -fsSL https://raw.githubusercontent.com/0xHoneyJar/loa/main/.claude/scripts/mount-loa.sh | bash -s -- --tag v1.39.0

# Start Claude Code
claude

# These are slash commands typed inside Claude Code, not your terminal.
# 5 commands. Full development cycle.
/plan      # Requirements -> Architecture -> Sprints
/build     # Implement the current sprint
/review    # Code review + security audit
/ship      # Deploy and archive
```

After install, you should see `.loa/` (submodule), `.claude/` (symlinks), `grimoires/loa/`, and `.loa.config.yaml` in your repo. Run `/loa doctor` inside Claude Code to verify everything is healthy.

> **Three ways to install**: Submodule mode (default, recommended for existing projects), clone template (new projects), or vendored mode (legacy — no symlink support). See **[INSTALLATION.md](INSTALLATION.md#choosing-your-installation-method)** for the full comparison.

Not sure where you are? `/loa` shows your current state, health, and next step.

New project? See **[INSTALLATION.md](INSTALLATION.md#method-2-clone-template)** to clone the template. For detailed setup, optional tools (beads, ck), and configuration, start there too.

## Why Loa?

**The problem**: AI coding assistants are powerful but unstructured. Without guardrails, you get ad-hoc code with no traceability, no security review, and no memory across sessions.

**The solution**: Loa adds structure without ceremony. Each phase produces a traceable artifact (PRD, SDD, Sprint Plan, Code, Review, Audit) using specialized AI agents. Your code gets reviewed by a Tech Lead agent *and* a Security Auditor agent before it ships.

**Key differentiators**:
- **Multi-agent orchestration**: 17 specialized skills, not one general-purpose prompt
- **Quality gates**: Two-phase review (code + security) prevents unreviewed code from shipping
- **Session persistence**: Beads task graph + persistent memory survive context clears
- **Adversarial review**: Flatline Protocol uses cross-model dissent (Opus + GPT-5.2) for planning QA
- **Zero-config start**: Mount onto any repo, type `/plan`, start building

## The Workflow

### Golden Path (5 commands, zero arguments)

| Command | What It Does |
|---------|-------------|
| `/loa` | Where am I? What's next? |
| `/plan` | Plan your project (requirements -> architecture -> sprints) |
| `/build` | Build the current sprint |
| `/review` | Review and audit your work |
| `/ship` | Deploy and archive |

Each Golden Path command auto-detects context and does the right thing. No arguments needed. First run of `/plan` takes 2-5 minutes and creates `grimoires/loa/prd.md`.

### Diagnostics

If something isn't working, start here:

```bash
/loa doctor          # Full system health check with structured error codes
/loa doctor --json   # CI-friendly output
```

### Power User Commands (Truenames)

For fine-grained control, use the underlying commands directly:

| Phase | Command | Output |
|-------|---------|--------|
| 1 | `/plan-and-analyze` | Product Requirements (PRD) |
| 2 | `/architect` | Software Design (SDD) |
| 3 | `/sprint-plan` | Sprint Plan |
| 4 | `/implement sprint-N` | Code + Tests |
| 5 | `/review-sprint sprint-N` | Approval or Feedback |
| 5.5 | `/audit-sprint sprint-N` | Security Approval |
| 6 | `/deploy-production` | Infrastructure |

**47 total commands.** Type `/loa` for the Golden Path or see [PROCESS.md](PROCESS.md) for all commands.

## The Agents

Seventeen specialized skills that ride alongside you:

| Skill | Role |
|-------|------|
| discovering-requirements | Senior Product Manager |
| designing-architecture | Software Architect |
| planning-sprints | Technical PM |
| implementing-tasks | Senior Engineer |
| reviewing-code | Tech Lead |
| auditing-security | Security Auditor |
| deploying-infrastructure | DevOps Architect |
| translating-for-executives | Developer Relations |
| enhancing-prompts | Prompt Engineer |
| run-mode | Autonomous Executor |
| run-bridge | Excellence Loop Operator |
| simstim-workflow | HITL Orchestrator |
| riding-codebase | Codebase Analyst |
| continuous-learning | Learning Extractor |
| flatline-knowledge | Knowledge Retriever |
| browsing-constructs | Construct Browser |
| mounting-framework | Framework Installer |
| autonomous-agent | Autonomous Agent |

## Architecture

Loa uses a **three-zone model** inspired by AWS Projen and Google's ADK:

| Zone | Path | Description |
|------|------|-------------|
| **System** | `.claude/` | Framework-managed (never edit directly) |
| **State** | `grimoires/`, `.beads/` | Project memory |
| **App** | `src/`, `lib/` | Your code |

**Key principle**: Customize via `.claude/overrides/` and `.loa.config.yaml`, not by editing `.claude/` directly.

## Key Features

| Feature | Description | Documentation |
|---------|-------------|---------------|
| **Golden Path** | 5 zero-arg commands for 90% of users | [CLAUDE.md](CLAUDE.md#golden-path) |
| **Error Codes & `/loa doctor`** | Structured LOA-E001+ codes with fix suggestions | [Data](.claude/data/error-codes.json) |
| **Flatline Protocol** | Multi-model adversarial review (Opus + GPT-5.2) | [Protocol](.claude/protocols/flatline-protocol.md) |
| **Adversarial Dissent** | Cross-model challenge during review and audit | [CHANGELOG.md](CHANGELOG.md) |
| **Cross-Repo Patterns** | 25 reusable patterns in 5 library modules | [Lib](.claude/lib/) |
| **DRY Constraint Registry** | Single-source constraint generation from JSON | [Data](.claude/data/constraints.json) |
| **Beads-First Architecture** | Persistent task tracking (recommended; required for `/run` mode, works without for interactive use) | [CLAUDE.md](CLAUDE.md#beads-first-architecture) |
| **Persistent Memory** | Session-spanning observations with progressive disclosure | [Scripts](.claude/scripts/memory-query.sh) |
| **Input Guardrails** | PII filtering, injection detection, danger levels | [Protocol](.claude/protocols/input-guardrails.md) |
| **Portable Persistence** | WAL-based persistence with circuit breakers | [Lib](.claude/lib/persistence/) |
| **Cross-Platform Compat** | Shell scripting protocol for macOS + Linux | [Scripts](.claude/scripts/compat-lib.sh) |
| **Prompt Enhancement** | PTCF-based prompt analysis and improvement | [CHANGELOG.md](CHANGELOG.md) |
| **Run Mode** | Autonomous sprint execution with draft PRs | [CLAUDE.md](CLAUDE.md#run-mode) |
| **Run Bridge** | Iterative excellence loop with Bridgebuilder review and flatline detection | [CLAUDE.md](CLAUDE.md#run-bridge) |
| **Lore Knowledge Base** | Cultural/philosophical context for agent skills (Mibera + Neuromancer) | [Data](.claude/data/lore/) |
| **Vision Registry** | Speculative insight capture from bridge iterations | [Visions](grimoires/loa/visions/) |
| **Grounded Truth** | Checksum-verified codebase summaries extending `/ride` | [Script](.claude/scripts/ground-truth-gen.sh) |
| **Simstim** | HITL accelerated development (PRD -> SDD -> Sprint -> Run) | [Command](.claude/commands/simstim.md) |
| **Compound Learning** | Cross-session pattern detection + feedback loop | [CHANGELOG.md](CHANGELOG.md) |
| **Construct Manifest Standard** | Event-driven contracts with schema validation | [CHANGELOG.md](CHANGELOG.md) |
| **Quality Gates** | Two-phase review: Tech Lead + Security Auditor | [PROCESS.md](PROCESS.md#agent-to-agent-communication) |
| **Loa Constructs** | Commercial skill packs from registry | [INSTALLATION.md](INSTALLATION.md#loa-constructs-commercial-skills) |
| **Sprint Ledger** | Global sprint numbering across cycles | [CLAUDE.md](CLAUDE.md#sprint-ledger) |
| **beads_rust** | Persistent task graph across sessions | [INSTALLATION.md](INSTALLATION.md#beads_rust-optional) |
| **ck Search** | Semantic code search | [INSTALLATION.md](INSTALLATION.md#ck-semantic-code-search) |

## Documentation

| Document | Purpose |
|----------|---------|
| **[INSTALLATION.md](INSTALLATION.md)** | Setup, prerequisites, configuration, updates |
| **[PROCESS.md](PROCESS.md)** | Complete workflow, agents, commands, protocols |
| **[CLAUDE.md](CLAUDE.md)** | Technical reference for Claude Code |
| **[CHANGELOG.md](CHANGELOG.md)** | Version history |

## Maintainer

[@janitooor](https://github.com/janitooor)

## License

[AGPL-3.0](LICENSE.md) — Use, modify, distribute freely. Network service deployments must release source code.

Commercial licenses are available for organizations that wish to use Loa without AGPL obligations.

## Links

- [Repository](https://github.com/0xHoneyJar/loa)
- [Issues](https://github.com/0xHoneyJar/loa/issues)
- [Changelog](CHANGELOG.md)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview)
- [beads_rust](https://github.com/Dicklesworthstone/beads_rust)

Ridden with [Loa](https://github.com/0xHoneyJar/loa)

