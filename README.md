# Agentic Base

An agent-driven development framework that orchestrates the complete product development lifecycle—from requirements gathering through production deployment—using specialized AI agents.

## Overview

This framework uses specialized AI agents working together in a structured workflow to build products systematically with high quality. While designed with crypto/blockchain projects in mind, it's applicable to any software project.

## Quick Start

### Prerequisites

- [Claude Code](https://claude.ai/code) installed
- Git configured

### Setup

1. **Clone this repository**
   ```bash
   git clone https://github.com/0xHoneyJar/agentic-base.git
   cd agentic-base
   ```

2. **Configure .gitignore for your project**

   Uncomment the generated artifacts section in `.gitignore` to avoid committing generated documentation:
   ```bash
   # Uncomment these lines in .gitignore:
   # docs/a2a/reviewer.md
   # docs/a2a/engineer-feedback.md
   # docs/prd.md
   # docs/sdd.md
   # docs/sprint.md
   # docs/deployment/
   ```

3. **Start Claude Code**
   ```bash
   claude-code
   ```

4. **Begin the workflow**
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
- Output: Production code + `docs/a2a/reviewer.md`

### Phase 5: Review (`/review-sprint`)
The **senior-tech-lead-reviewer** agent validates implementation quality.
- Output: `docs/a2a/engineer-feedback.md` (approval or feedback)

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

## Core Commands

| Command | Purpose | Output |
|---------|---------|--------|
| `/plan-and-analyze` | Define requirements and create PRD | `docs/prd.md` |
| `/architect` | Design system architecture | `docs/sdd.md` |
| `/sprint-plan` | Plan implementation sprints | `docs/sprint.md` |
| `/implement sprint-X` | Implement sprint tasks | Code + `docs/a2a/reviewer.md` |
| `/review-sprint` | Review and approve/reject implementation | `docs/a2a/engineer-feedback.md` |
| `/deploy-production` | Deploy to production | Infrastructure + `docs/deployment/` |
| `/audit` | Security and quality audit (ad-hoc) | `SECURITY-AUDIT-REPORT.md` |
| `/translate @doc.md for [audience]` | Translate technical docs for stakeholders (ad-hoc) | Executive summaries |

## The Agents

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
Implementation uses an iterative cycle where the senior tech lead reviews code and provides feedback until approval. This ensures quality without blocking progress.

### Agent-to-Agent Communication
Agents communicate through structured documents in `docs/a2a/`:
- Engineers write implementation reports
- Senior leads provide feedback
- Engineers address feedback and iterate

### MCP Server Integrations
Pre-configured integrations with:
- **Linear** - Issue and project management
- **GitHub** - Repository operations
- **Vercel** - Deployment and hosting
- **Discord** - Community communication
- **Web3-stats** - Blockchain data (Dune, Blockscout)

## Organizational Deployment (Optional)

For teams needing multi-tool integration and server deployment:

| Command | Purpose |
|---------|---------|
| `/integrate-org-workflow` | Design integration with Discord, Linear, Google Docs |
| `/implement-org-integration` | Build Discord bot, webhooks, sync scripts |
| `/setup-server` | Configure production server |
| `/audit-deployment` | Security audit of deployment infrastructure |
| `/deploy-go` | Execute production deployment (requires audit approval) |

See **[DEPLOY-ORG-README.md](DEPLOY-ORG-README.md)** for the complete organizational deployment workflow.

## Documentation

- **[PROCESS.md](PROCESS.md)** - Comprehensive workflow documentation
- **[DEPLOY-ORG-README.md](DEPLOY-ORG-README.md)** - Organizational integration & server deployment guide
- **[DEPLOY-ORG-PROCESS.md](DEPLOY-ORG-PROCESS.md)** - Detailed organizational deployment workflow
- **[CLAUDE.md](CLAUDE.md)** - Guidance for Claude Code instances

## Repository Structure

```
.claude/
├── agents/              # Agent definitions
├── commands/           # Slash command definitions
└── settings.local.json # MCP server configuration

docs/
├── prd.md              # Product Requirements Document
├── sdd.md              # Software Design Document
├── sprint.md           # Sprint plan
├── a2a/                # Agent-to-agent communication
└── deployment/         # Production infrastructure docs

PROCESS.md              # Core workflow guide
DEPLOY-ORG-README.md    # Org integration & deployment guide
DEPLOY-ORG-PROCESS.md   # Detailed org deployment workflow
CLAUDE.md               # Context for Claude Code
README.md               # This file
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
# Review docs/a2a/reviewer.md

# 5. Review Sprint 1
/review-sprint
# Either approved or feedback provided

# 6. Address feedback (if needed)
/implement sprint-1
# Repeat until approved

# 7. Continue with remaining sprints...

# 8. Security audit (before production)
/audit
# Review SECURITY-AUDIT-REPORT.md, fix critical issues

# 9. Deploy to production
/deploy-production
# Production infrastructure deployed
```

## Multi-Developer Usage Warning

⚠️ **IMPORTANT**: This framework is designed for **single-threaded development workflows**. If multiple developers use this framework simultaneously on the same project, you will encounter conflicts.

### Solutions for Team Collaboration

1. **Developer-Scoped A2A**: Separate directories per developer
2. **Task-Scoped Reports**: Per-task implementation reports
3. **External System Integration**: Use Linear/GitHub for task assignment
4. **Feature Branches**: Branch-specific documentation

See [PROCESS.md](PROCESS.md) for detailed multi-developer guidance.

## Best Practices

1. **Trust the process** - Each phase builds on the previous
2. **Be thorough** - Agents ask questions for a reason
3. **Review outputs** - Always review generated documents
4. **Use feedback loops** - Iterative refinement ensures quality
5. **Security first** - Never compromise on security fundamentals

## Why Use This Framework?

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

MIT

## Links

- [Claude Code Documentation](https://docs.claude.ai/claude-code)
- [Repository](https://github.com/0xHoneyJar/agentic-base)
