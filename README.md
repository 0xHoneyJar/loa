# Loa

[![Version](https://img.shields.io/badge/version-1.18.0-blue.svg)](CHANGELOG.md)
[![License](https://img.shields.io/badge/license-AGPL--3.0-green.svg)](LICENSE.md)
[![Release](https://img.shields.io/badge/release-Visual%20Communication%20%26%20Invisible%20Enhancement-purple.svg)](CHANGELOG.md#1180---2026-02-02--visual-communication--invisible-enhancement)

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

**Ad-hoc**: `/audit`, `/translate`, `/validate`, `/compound`, `/feedback`, `/constructs`, `/enhance`, `/update-loa`, `/loa` (guided workflow)

See **[PROCESS.md](PROCESS.md)** for complete workflow documentation.

## The Agents

Ten specialized agents that ride alongside you:

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
| enhancing-prompts | Prompt Engineer |
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
| **Prompt Enhancement** | PTCF-based prompt analysis and improvement | [CHANGELOG.md](CHANGELOG.md#1150---2026-02-02--prompt-enhancement--developer-experience) |
| **Consolidated Sprint PRs** | Single PR for entire sprint plan execution | [CHANGELOG.md](CHANGELOG.md#1150---2026-02-02--prompt-enhancement--developer-experience) |
| **URL Registry** | Canonical URLs to prevent agent hallucination | [CHANGELOG.md](CHANGELOG.md#1150---2026-02-02--prompt-enhancement--developer-experience) |
| **Oracle Compound Learnings** | Query Loa's own knowledge with weighted sources | [CHANGELOG.md](CHANGELOG.md#1120---2026-02-01--oracle-compound-learnings) |
| **Smart Feedback Routing** | Auto-route feedback to correct ecosystem repo | [CHANGELOG.md](CHANGELOG.md#1110---2026-02-01--autonomous-agents--developer-experience) |
| **WIP Branch Testing** | Test Loa feature branches before merging | [CHANGELOG.md](CHANGELOG.md#1110---2026-02-01--smart-feedback-routing--developer-experience) |
| **Compound Learning** | Cross-session pattern detection + feedback loop | [CHANGELOG.md](CHANGELOG.md#1100---2026-01-30--compound-learning--visual-communication) |
| **Visual Communication** | Beautiful Mermaid diagram rendering | [CLAUDE.md](CLAUDE.md#visual-communication) |
| **Memory Stack** | Vector database + mid-stream semantic grounding | [INSTALLATION.md](INSTALLATION.md#memory-stack-optional) |
| **Context Cleanup** | Auto-archive previous cycle before new `/plan-and-analyze` | [CLAUDE.md](CLAUDE.md#claude-code-21x-features) |
| **Run Mode** | Autonomous sprint execution with draft PRs | [CLAUDE.md](CLAUDE.md#run-mode) |
| **Simstim** | Telegram bridge for remote monitoring | [simstim/README.md](simstim/README.md) |
| **Goal Traceability** | PRD goals tracked through implementation | [CLAUDE.md](CLAUDE.md#goal-traceability) |
| **Continuous Learning** | Extract discoveries into reusable skills | [CLAUDE.md](CLAUDE.md#key-protocols) |
| **Feedback Traces** | Execution traces for regression debugging | [CHANGELOG.md](CHANGELOG.md#1100---2026-01-30--compound-learning--visual-communication) |
| **Loa Constructs** | Commercial skill packs from registry | [INSTALLATION.md](INSTALLATION.md#loa-constructs-commercial-skills) |
| **Sprint Ledger** | Global sprint numbering across cycles | [CLAUDE.md](CLAUDE.md#sprint-ledger) |
| **Structured Memory** | Persistent working memory in NOTES.md | [PROCESS.md](PROCESS.md#structured-agentic-memory) |
| **beads_rust** | Persistent task graph across sessions | [INSTALLATION.md](INSTALLATION.md#beads_rust-optional) |
| **ck Search** | Semantic code search | [INSTALLATION.md](INSTALLATION.md#ck-semantic-code-search) |
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
