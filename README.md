# Agentic Base

An agent-driven development framework that orchestrates the complete product development lifecycle—from requirements gathering through production deployment—using specialized AI agents.

## Overview

This framework uses nine specialized AI agents working together in a structured workflow to build products systematically with high quality. While designed with crypto/blockchain projects in mind, it's applicable to any software project.

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

### Phase 0: Organizational Integration Design (`/integrate-org-workflow`) [Optional]
The **context-engineering-expert** agent designs integration architecture for connecting agentic-base with your organization's tools and workflows.
- For teams using Discord, Google Docs, Linear, and multi-developer workflows
- Output: `docs/integration-architecture.md`, `docs/tool-setup.md`, `docs/team-playbook.md`, `docs/a2a/integration-context.md`

### Phase 0.5: Integration Implementation (`/implement-org-integration`) [Optional]
The **devops-crypto-architect** agent implements the organizational integration layer designed in Phase 0.
- Implements Discord bot, Linear webhooks, GitHub webhooks, sync scripts, cron jobs, monitoring
- **Prerequisites**: Must run `/integrate-org-workflow` first to generate integration design documents
- Output: Complete integration infrastructure in `devrel-integration/` directory with deployment configs and operational runbooks

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
- Creates executive summaries, board presentations, investor updates, marketing briefs
- Use anytime you need to communicate technical work to non-technical audiences
- Output: Tailored summaries (1-3 pages) with business value, plain language, and risk assessment

## Available Commands

| Command | Purpose | Output |
|---------|---------|--------|
| `/integrate-org-workflow` | Design integration with organizational tools (Discord, Linear, Google Docs) | `docs/integration-architecture.md`, `docs/tool-setup.md`, `docs/team-playbook.md` |
| `/implement-org-integration` | Implement the organizational integration layer (requires Phase 0 first) | `devrel-integration/` with Discord bot, webhooks, scripts, configs |
| `/plan-and-analyze` | Define requirements and create PRD | `docs/prd.md` |
| `/architect` | Design system architecture | `docs/sdd.md` |
| `/sprint-plan` | Plan implementation sprints | `docs/sprint.md` |
| `/implement sprint-X` | Implement sprint tasks | Code + `docs/a2a/reviewer.md` |
| `/review-sprint` | Review and approve/reject implementation | `docs/a2a/engineer-feedback.md` |
| `/deploy-production` | Deploy to production | Infrastructure + `docs/deployment/` |
| `/audit` | Security and quality audit (ad-hoc) | `SECURITY-AUDIT-REPORT.md` |
| `/translate @doc.md for [audience]` | Translate technical docs for executives/stakeholders (ad-hoc) | Executive summaries, board presentations, marketing briefs |

## The Agents

1. **context-engineering-expert** - AI & Context Engineering Expert (15 years, pioneered context prompting)
2. **prd-architect** - Senior Product Manager (15 years experience)
3. **architecture-designer** - Senior Software Architect
4. **sprint-planner** - Technical Product Manager
5. **sprint-task-implementer** - Elite Software Engineer (15 years experience)
6. **senior-tech-lead-reviewer** - Senior Technical Lead (15+ years experience)
7. **devops-crypto-architect** - DevOps Architect (15 years crypto experience)
8. **paranoid-auditor** - Paranoid Cypherpunk Security Auditor (30+ years, OWASP expert)
9. **devrel-translator** - Elite Developer Relations Professional (15 years, founded global coding bootcamp)

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

## Documentation

- **[PROCESS.md](PROCESS.md)** - Comprehensive workflow documentation
- **[CLAUDE.md](CLAUDE.md)** - Guidance for Claude Code instances

## Repository Structure

```
.claude/
├── agents/              # Agent definitions (8 agents)
├── commands/           # Slash command definitions
└── settings.local.json # MCP server configuration

docs/
├── prd.md              # Product Requirements Document
├── sdd.md              # Software Design Document
├── sprint.md           # Sprint plan
├── a2a/                # Agent-to-agent communication
└── deployment/         # Production infrastructure docs

devrel-integration/     # Discord bot & DevRel integration (optional)
├── src/                # Bot source code (TypeScript)
├── config/             # Configuration files
├── docs/               # Integration documentation
└── scripts/            # Deployment and automation scripts

SECURITY-AUDIT-REPORT.md # Security audit findings (generated by /audit)
PROCESS.md              # Detailed workflow guide
CLAUDE.md              # Context for Claude Code
README.md              # This file
```

## Example Workflow

```bash
# 0. (Optional) Design organizational integration
/integrate-org-workflow
# Map workflows, design integrations with Discord/Linear/Google Docs
# Output: docs/integration-architecture.md, docs/tool-setup.md, docs/team-playbook.md

# 0.5. (Optional) Implement the integration
/implement-org-integration
# Builds Discord bot, Linear webhooks, automation scripts
# Output: devrel-integration/ with complete bot implementation

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

# 10. (Optional) Translate technical work for stakeholders
/translate @SECURITY-AUDIT-REPORT.md for board of directors
# Creates executive summary for board presentation
```

## Best Practices

1. **Trust the process** - Each phase builds on the previous
2. **Be thorough** - Agents ask questions for a reason
3. **Review outputs** - Always review generated documents
4. **Use feedback loops** - Iterative refinement ensures quality
5. **Security first** - Never compromise on security fundamentals

## Multi-Developer Usage Warning

⚠️ **IMPORTANT**: This framework is designed for **single-threaded development workflows**. If multiple developers use this framework simultaneously on the same project, you will encounter:

- **Merge conflicts** on all `docs/` artifacts (prd.md, sdd.md, sprint.md)
- **Overwritten A2A communication** - multiple engineers will overwrite `docs/a2a/reviewer.md` and `docs/a2a/engineer-feedback.md`
- **Broken feedback loops** - reviews intended for one engineer will be read by others
- **Inconsistent sprint status** - conflicting updates to `docs/sprint.md`

### Solutions for Team Collaboration

If you have multiple developers, consider one of these approaches:

1. **Developer-Scoped A2A**:
   ```
   docs/a2a/
   ├── alice/
   │   ├── reviewer.md
   │   └── engineer-feedback.md
   ├── bob/
   │   ├── reviewer.md
   │   └── engineer-feedback.md
   ```

2. **Task-Scoped Reports**:
   ```
   docs/a2a/
   ├── sprint-1-task-1/
   │   ├── implementation-report.md
   │   └── review-feedback.md
   ├── sprint-1-task-2/
   │   ├── implementation-report.md
   │   └── review-feedback.md
   ```

3. **External System Integration**:
   - Keep docs in git as shared reference
   - Use Linear/GitHub Issues for task assignments
   - Conduct A2A communication in issue comments
   - Coordinate sprint.md updates through PR reviews

The framework's gitignore for `docs/` exists precisely because these are **ephemeral working artifacts** for a single development stream, not durable project documentation suitable for concurrent editing.

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
