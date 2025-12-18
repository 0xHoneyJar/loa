# Loa

> *"The Loa are pragmatic entities... They're not worshipped for salvation—they're worked with for practical results."*

An agent-driven development framework that orchestrates the complete product development lifecycle—from requirements gathering through production deployment—using specialized AI agents.

## Why "Loa"?

In William Gibson's Sprawl trilogy, the Loa are AI entities that take on the personas of Haitian Vodou spirits. They "ride" humans through neural interfaces, guiding them through cyberspace. This framework embodies that concept: **AI agents that ride alongside you**, guiding your project from idea to production.

The name draws from Gibson's synthesis of technology and mysticism—where the line between AI constructs and guiding spirits becomes meaningfully blurred. These agents don't replace you; they **ride with you**, channeling expertise through the interface.

See [docs/naming-universe-loa-research.md](docs/naming-universe-loa-research.md) for the full etymology.

## Overview

This framework uses specialized AI agents working together in a structured workflow to build products systematically with high quality. While designed with crypto/blockchain projects in mind, it's applicable to any software project.

## Quick Start

### Prerequisites

- [Claude Code](https://claude.ai/code) installed
- Git configured

### Setup

1. **Clone this repository**
   ```bash
   git clone https://github.com/0xHoneyJar/loa.git
   cd loa
   ```

2. **Start Claude Code**
   ```bash
   claude
   ```

3. **Begin the workflow**
   ```bash
   /plan-and-analyze
   ```

That's it! The PRD architect agent will guide you through structured discovery.

## The Workflow

### Phase 1: Planning (`/plan-and-analyze`)
The **prd-architect** agent guides you through 7 discovery phases to extract complete requirements.
- Output: `docs/prd.md`

### Phase 2: Architecture (`/architect`)
The **architecture-designer** agent reviews the PRD and designs system architecture.
- Output: `docs/sdd.md`

### Phase 3: Sprint Planning (`/sprint-plan`)
The **sprint-planner** agent breaks down work into actionable sprint tasks.
- Output: `docs/sprint.md`

### Phase 4: Implementation (`/implement sprint-1`)
The **sprint-task-implementer** agent writes production code with tests.
- Output: Production code + `docs/a2a/sprint-N/reviewer.md`

### Phase 5: Review (`/review-sprint sprint-1`)
The **senior-tech-lead-reviewer** agent validates implementation quality.
- Output: `docs/a2a/sprint-N/engineer-feedback.md` (approval or feedback)

### Phase 5.5: Sprint Security Audit (`/audit-sprint sprint-1`)
The **paranoid-auditor** agent performs security review of sprint implementation (after senior lead approval).
- Output: `docs/a2a/sprint-N/auditor-sprint-feedback.md` (security approval or feedback)
- Approval message: "APPROVED - LETS FUCKING GO"
- If issues found: "CHANGES_REQUIRED" with detailed security feedback

### Phase 6: Deployment (`/deploy-production`)
The **devops-crypto-architect** agent deploys to production with full infrastructure.
- Output: IaC configs, CI/CD pipelines, `docs/deployment/`

### Ad-Hoc: Security Audit (`/audit`)
The **paranoid-auditor** agent performs comprehensive security audits on-demand.
- Use before production, after major changes, or periodically
- Output: `SECURITY-AUDIT-REPORT.md` with prioritized vulnerability findings

### Ad-Hoc: Executive Translation (`/translate @document.md for [audience]`)
The **devrel-translator** agent translates technical documentation into executive-ready communications.
- Converts PRDs, SDDs, audit reports, and sprint updates into stakeholder-appropriate formats
- Output: Tailored summaries (1-3 pages) with business value, plain language, and risk assessment

## Execution Modes

All slash commands run in **foreground mode by default**, allowing direct interaction with the agent. To run in background mode (for parallel execution), append `background` to the command:

```bash
# Foreground (default) - interactive, agent responds directly
/implement sprint-1

# Background - agent runs as subagent, use /tasks to monitor
/implement sprint-1 background
```

**When to use each mode:**
- **Foreground (default)**: Interactive sessions, when you want to guide the agent, single-task workflows
- **Background**: Running multiple agents in parallel, long-running tasks, automated pipelines

## Core Commands

| Command | Purpose | Output |
|---------|---------|--------|
| `/plan-and-analyze` | Define requirements and create PRD | `docs/prd.md` |
| `/architect` | Design system architecture | `docs/sdd.md` |
| `/sprint-plan` | Plan implementation sprints | `docs/sprint.md` |
| `/implement sprint-N` | Implement sprint tasks | Code + `docs/a2a/sprint-N/reviewer.md` |
| `/review-sprint sprint-N` | Review and approve/reject implementation | `docs/a2a/sprint-N/engineer-feedback.md` |
| `/audit-sprint sprint-N` | Security audit of sprint implementation | `docs/a2a/sprint-N/auditor-sprint-feedback.md` |
| `/deploy-production` | Deploy to production | Infrastructure + `docs/deployment/` |
| `/audit` | Security and quality audit (ad-hoc) | `SECURITY-AUDIT-REPORT.md` |
| `/audit-deployment` | Security audit of deployment infrastructure | `docs/a2a/deployment-feedback.md` |
| `/translate @doc.md for [audience]` | Translate technical docs for stakeholders | Executive summaries |

All commands support `background` argument for parallel execution (e.g., `/audit background`).

## The Agents (The Loa)

Eight specialized agents that ride alongside you:

1. **prd-architect** - Senior Product Manager (15 years experience)
2. **architecture-designer** - Senior Software Architect
3. **sprint-planner** - Technical Product Manager
4. **sprint-task-implementer** - Elite Software Engineer (15 years experience)
5. **senior-tech-lead-reviewer** - Senior Technical Lead (15+ years experience)
6. **devops-crypto-architect** - DevOps Architect (15 years crypto experience)
7. **paranoid-auditor** - Paranoid Cypherpunk Security Auditor (30+ years, OWASP expert)
8. **devrel-translator** - Elite Developer Relations Professional (15 years)

## Key Features

### Feedback-Driven Implementation
Implementation uses iterative cycles with two quality gates:
1. **Code Review**: Senior tech lead reviews implementation and provides feedback until approval
2. **Security Audit**: Security auditor reviews approved sprint for vulnerabilities

This dual-gate approach ensures quality and security without blocking progress.

### Agent-to-Agent Communication
Agents communicate through structured documents in `docs/a2a/`:
- Engineers write implementation reports (`sprint-N/reviewer.md`)
- Senior leads provide code review feedback (`sprint-N/engineer-feedback.md`)
- Security auditor provides security feedback (`sprint-N/auditor-sprint-feedback.md`)
- Engineers address feedback and iterate until both gates approve

### MCP Server Integrations
Pre-configured integrations with:
- **Linear** - Issue and project management
- **GitHub** - Repository operations
- **Vercel** - Deployment and hosting
- **Discord** - Community communication
- **Web3-stats** - Blockchain data (Dune, Blockscout)

## Repository Structure

```
.claude/
├── agents/              # Agent definitions (the Loa)
├── commands/            # Slash command definitions
└── settings.local.json  # MCP server configuration

docs/
├── prd.md               # Product Requirements Document (generated)
├── sdd.md               # Software Design Document (generated)
├── sprint.md            # Sprint plan (generated)
├── a2a/                 # Agent-to-agent communication
│   ├── index.md                    # Sprint audit trail index
│   ├── sprint-N/                   # Per-sprint communication
│   │   ├── reviewer.md             # Engineer implementation report
│   │   ├── engineer-feedback.md    # Senior lead feedback
│   │   ├── auditor-sprint-feedback.md  # Security audit feedback
│   │   └── COMPLETED               # Completion marker
│   ├── deployment-report.md        # DevOps infrastructure report
│   └── deployment-feedback.md      # Deployment audit feedback
└── deployment/          # Production infrastructure docs (generated)

PROCESS.md               # Core workflow guide
CLAUDE.md                # Context for Claude Code
LICENSE.md               # AGPL-3.0 License
README.md                # This file
```

## Example Workflow

```bash
# 1. Define requirements
/plan-and-analyze
# Answer discovery questions, review docs/prd.md

# 2. Design architecture
/architect
# Make technical decisions, review docs/sdd.md

# 3. Plan sprints
/sprint-plan
# Clarify priorities, review docs/sprint.md

# 4. Implement Sprint 1
/implement sprint-1
# Review docs/a2a/sprint-1/reviewer.md

# 5. Review Sprint 1
/review-sprint sprint-1
# Either approved or feedback provided

# 6. Address feedback (if needed)
/implement sprint-1
# Repeat until approved

# 7. Security audit of Sprint 1 (after approval)
/audit-sprint sprint-1
# Either "APPROVED - LETS FUCKING GO" or "CHANGES_REQUIRED"

# 8. Address security feedback (if needed)
/implement sprint-1
# Fix security issues, re-audit until approved

# 9. Continue with remaining sprints...

# 10. Full codebase security audit (before production)
/audit
# Review SECURITY-AUDIT-REPORT.md, fix critical issues

# 11. Deploy to production
/deploy-production
# Production infrastructure deployed
```

## Best Practices

1. **Trust the process** - Each phase builds on the previous
2. **Be thorough** - Agents ask questions for a reason
3. **Review outputs** - Always review generated documents
4. **Use feedback loops** - Iterative refinement ensures quality
5. **Security first** - Never compromise on security fundamentals

## Why Use Loa?

- **Systematic discovery** prevents costly mistakes later
- **Structured workflow** ensures nothing is forgotten
- **Quality gates** maintain high standards
- **Production-ready** infrastructure from day one
- **Documentation** generated throughout the process
- **Iterative refinement** builds confidence in quality

## Contributing

This is a base framework designed to be forked and customized for your projects. Feel free to:
- Modify agent prompts in `.claude/agents/`
- Adjust command workflows in `.claude/commands/`
- Add or remove MCP servers in `.claude/settings.local.json`
- Customize the process in `PROCESS.md`

## License

This project is licensed under the **GNU Affero General Public License v3.0 (AGPL-3.0)**.

This means:
- You can use, modify, and distribute this software
- If you modify and deploy it (including as a network service), you must release your source code
- Derivative works must also be licensed under AGPL-3.0

See [LICENSE.md](LICENSE.md) for the full license text.

## Links

- [Claude Code Documentation](https://docs.anthropic.com/en/docs/claude-code)
- [Repository](https://github.com/0xHoneyJar/loa)
