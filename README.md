# Loa

<!-- AGENT-CONTEXT: Loa is an agent-driven development framework for Claude Code.
Primary interface: 5 Golden Path commands (/loa, /plan, /build, /review, /ship).
Power user interface: 48 slash commands (truenames).
Architecture: Three-zone model (System: .claude/, State: grimoires/ + .beads/, App: src/).
Configuration: .loa.config.yaml (user-owned, never modified by framework).
Health check: /loa doctor
Version: 1.88.0
-->

[![Version](https://img.shields.io/badge/version-1.102.0-blue.svg)](CHANGELOG.md)
[![License](https://img.shields.io/badge/license-AGPL--3.0-green.svg)](LICENSE.md)
[![Release](https://img.shields.io/badge/release-Spiral%20Autopoietic%20Orchestrator-purple.svg)](CHANGELOG.md#1880---2026-04-15)

> *"The Loa are pragmatic entities... They're not worshipped for salvation—they're worked with for practical results."*

## What Is This?

Loa is an agent-driven development framework for [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview) (Anthropic's official CLI). It adds 18 specialized AI agents, quality gates, persistent memory, and structured workflows on top of Claude Code — including a self-improving [spiral orchestrator](#spiral-autopoietic-orchestrator) that can autonomously plan, build, review, and learn across multiple development cycles. Works on macOS and Linux. Created by [@janitooor](https://github.com/janitooor) at [The Honey Jar](https://0xhoneyjar.xyz).

### Why "Loa"?

In William Gibson's Sprawl trilogy (*Neuromancer*, *Count Zero*), Loa are AI entities that "ride" humans through neural interfaces — a metaphor Gibson adapted from Haitian Vodou via the anthropological work of Robert Tallant and (likely) Maya Deren. These agents don't replace you — they **ride with you**, channeling expertise through the interface. See [docs/ecosystem-architecture.md](docs/ecosystem-architecture.md#naming--the-scholarly-chain) for the full naming lineage.

## Quick Start (~2 minutes)

**Prerequisites**: [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview) (Anthropic's CLI for Claude), Git, jq, [yq v4+](https://github.com/mikefarah/yq). See **[INSTALLATION.md](INSTALLATION.md)** for full details.

> [!WARNING]
> **Some Loa features invoke external AI APIs and incur costs.** The three most expensive are:
> - **Flatline Protocol** — multi-model adversarial review (~$15–25 per planning cycle, Opus + GPT-5.3-codex)
> - **Simstim** — HITL-accelerated full cycle (~$25–65 per cycle, Opus + GPT-5.3-codex + Gemini)
> - **Spiral** — autonomous multi-cycle orchestrator (~$10–35 per cycle depending on profile)
>
> **Flatline Protocol** and **Simstim** are **enabled by default** but require API keys (`OPENAI_API_KEY`, `GOOGLE_API_KEY`) to function — without them, multi-model review phases are skipped. **Spiral** is **disabled by default** and must be explicitly enabled. See [`docs/CONFIG_REFERENCE.md`](docs/CONFIG_REFERENCE.md#cost-matrix) for the full cost table. Run `/loa setup` inside Claude Code before enabling autonomous modes to choose a budget-appropriate configuration.

```bash
# Install (one command, any existing repo — adds Loa as git submodule)
curl -fsSL https://raw.githubusercontent.com/0xHoneyJar/loa/main/.claude/scripts/mount-loa.sh | bash

# Or pin to a specific version
curl -fsSL https://raw.githubusercontent.com/0xHoneyJar/loa/main/.claude/scripts/mount-loa.sh | bash -s -- --tag v1.109.4

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
- **Multi-agent orchestration**: 18 specialized skills, not one general-purpose prompt
- **Quality gates**: Two-phase review (code + security) prevents unreviewed code from shipping
- **Session persistence**: Beads task graph + persistent memory survive context clears
- **Adversarial review**: Flatline Protocol uses cross-model dissent (Opus + GPT) for planning QA
- **Self-improving spiral**: `/spiral` dispatches autonomous development cycles with evidence-gated quality gates that the LLM cannot skip — [benchmarked](grimoires/loa/reports/spiral-harness-benchmark-report.md) and validated
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

**48 total commands.** Type `/loa` for the Golden Path or see [PROCESS.md](PROCESS.md) for all commands.

## The Agents

Eighteen specialized skills that ride alongside you:

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
| spiraling | Autopoietic Meta-Orchestrator |
| riding-codebase | Codebase Analyst |
| continuous-learning | Learning Extractor |
| flatline-knowledge | Knowledge Retriever |
| browsing-constructs | Construct Browser |
| mounting-framework | Framework Installer |
| autonomous-agent | Autonomous Agent |

## Spiral Autopoietic Orchestrator

The spiral (`/spiral`) is a self-improving meta-loop that dispatches autonomous development cycles. Each cycle runs the full Loa workflow (plan, build, review, audit), then harvests lessons to seed the next cycle. The system learns from its own output.

```
/spiral --start "Build feature X"
│
├── SEED    — query Vision Registry for relevant prior insights
├── SIMSTIM — dispatch full cycle (PRD → SDD → Sprint → Implement → Review → Audit → PR)
├── HARVEST — extract learnings, promote patterns, capture visions
└── EVALUATE — check stopping conditions, decide whether to continue
```

Quality gates are **evidence-gated**: a bash orchestrator sequences phases as separate `claude -p` subprocesses, with Flatline multi-model review, independent code review, and independent security audit running in bash between phases. The LLM cannot skip gates because it is not the LLM's decision.

**Cost optimization**: Sonnet handles planning and implementation (~5x cheaper tokens), Opus handles review and audit (judgment quality). [Benchmarked](grimoires/loa/reports/spiral-harness-benchmark-report.md) at equivalent output quality across both models. Default budget: $15/cycle.

**Kaironic termination**: unlike most agentic pipelines that only stop when wall-clock caps fire (budget / max iterations / timeout), the spiral observes its own findings-rate and halts on `flatline_convergence` — 2 consecutive cycles producing < 3 new findings each. The loop decides "we've reached a plateau" and terminates *before* exhausting budget. Second-order cybernetic convergence; see `.claude/skills/spiraling/SKILL.md` for the distinction between chronos (wall-clock) and kairos (signal-exhaustion) stopping conditions.

```yaml
# .loa.config.yaml — enable the spiral
spiral:
  enabled: true
  harness:
    executor_model: sonnet    # planning + implementation
    advisor_model: opus       # review + audit
```

See [RFC-060](grimoires/loa/proposals/rfc-060-spiral.md) for the design, [harness architecture](grimoires/loa/proposals/spiral-harness-architecture.md) for the engineering pattern, and [benchmark report](grimoires/loa/reports/spiral-harness-benchmark-report.md) for the data.

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
| **Spiral Orchestrator** | Self-improving meta-loop: plan → build → review → harvest → repeat | [RFC-060](grimoires/loa/proposals/rfc-060-spiral.md) |
| **Evidence-Gated Harness** | Bash-enforced quality gates that LLMs cannot skip — flight recorder audit trail | [Architecture](grimoires/loa/proposals/spiral-harness-architecture.md) |
| **Advisor Strategy** | Sonnet executes (~5x cheaper), Opus judges (review/audit quality) | [Benchmark](grimoires/loa/reports/spiral-harness-benchmark-report.md) |
| **Vision Registry** | Speculative insight capture from bridge iterations, graduated to active mode | [Visions](grimoires/loa/visions/) |
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

