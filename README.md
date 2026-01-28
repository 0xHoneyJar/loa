# Loa

[![Version](https://img.shields.io/badge/version-1.7.1-blue.svg)](CHANGELOG.md)
[![License](https://img.shields.io/badge/license-AGPL--3.0-green.svg)](LICENSE.md)
[![Release](https://img.shields.io/badge/release-Goal%20Traceability%20%26%20Guided%20Workflow-purple.svg)](CHANGELOG.md#170---2026-01-24--goal-traceability--guided-workflow)

> *"The Loa are pragmatic entities... They're not worshipped for salvation—they're worked with for practical results."*

**Run Mode AI** — Agent-driven development framework using 9 specialized AI agents to orchestrate the complete product lifecycle. From requirements through production deployment.

## Quick Start

```bash
# One-liner install onto any repo
curl -fsSL https://raw.githubusercontent.com/0xHoneyJar/loa/main/.claude/scripts/mount-loa.sh | bash

# Start Claude Code and begin
claude
/plan-and-analyze
```

See **[INSTALLATION.md](INSTALLATION.md)** for detailed setup options and prerequisites.

## The Workflow

| Phase | Command | Output |
|-------|---------|--------|
| 1 | `/plan-and-analyze` | Product Requirements (PRD) |
| 2 | `/architect` | Software Design (SDD) |
| 3 | `/sprint-plan` | Sprint Plan |
| 4 | `/implement sprint-N` | Code + Tests |
| 5 | `/review-sprint sprint-N` | Approval or Feedback |
| 5.5 | `/audit-sprint sprint-N` | Security Approval |
| 6 | `/deploy-production` | Infrastructure |

**Ad-hoc**: `/audit`, `/translate`, `/validate`, `/loa` (guided workflow)

See **[PROCESS.md](PROCESS.md)** for complete workflow documentation.

## The Agents

Nine specialized agents that ride alongside you:

| Agent | Role |
|-------|------|
| discovering-requirements | Senior Product Manager |
| designing-architecture | Software Architect |
| planning-sprints | Technical PM |
| implementing-tasks | Senior Engineer |
| reviewing-code | Tech Lead |
| auditing-security | Security Auditor |
| deploying-infrastructure | DevOps Architect |
| translating-for-executives | Developer Relations |
| run-mode | Autonomous Executor |

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
| **Run Mode** | Autonomous sprint execution with draft PRs | [CLAUDE.md](CLAUDE.md#run-mode) |
| **Simstim** | Telegram bridge for remote monitoring | [simstim/README.md](simstim/README.md) |
| **Goal Traceability** | PRD goals tracked through implementation | [CLAUDE.md](CLAUDE.md#goal-traceability) |
| **Continuous Learning** | Extract discoveries into reusable skills | [CLAUDE.md](CLAUDE.md#key-protocols) |
| **Loa Constructs** | Commercial skill packs from registry | [INSTALLATION.md](INSTALLATION.md#loa-constructs-commercial-skills) |
| **Sprint Ledger** | Global sprint numbering across cycles | [CLAUDE.md](CLAUDE.md#sprint-ledger) |
| **Structured Memory** | Persistent working memory in NOTES.md | [PROCESS.md](PROCESS.md#structured-agentic-memory) |
| **beads_rust** | Persistent task graph across sessions | [INSTALLATION.md](INSTALLATION.md) |
| **ck Search** | Semantic code search | [INSTALLATION.md](INSTALLATION.md#optional-enhancements) |
| **Quality Gates** | Two-phase review: Tech Lead + Security Auditor | [PROCESS.md](PROCESS.md#agent-to-agent-communication) |

## Documentation

| Document | Purpose |
|----------|---------|
| **[INSTALLATION.md](INSTALLATION.md)** | Setup, prerequisites, configuration, updates |
| **[PROCESS.md](PROCESS.md)** | Complete workflow, agents, commands, protocols |
| **[CLAUDE.md](CLAUDE.md)** | Technical reference for Claude Code |
| **[CHANGELOG.md](CHANGELOG.md)** | Version history |

## Why "Loa"?

In William Gibson's Sprawl trilogy, Loa are AI entities that "ride" humans through neural interfaces. These agents don't replace you—they **ride with you**, channeling expertise through the interface.

## License

[AGPL-3.0](LICENSE.md) — Use, modify, distribute freely. Network service deployments must release source code.

## Links

- [Claude Code](https://claude.ai/code)
- [Repository](https://github.com/0xHoneyJar/loa)
- [Issues](https://github.com/0xHoneyJar/loa/issues)
