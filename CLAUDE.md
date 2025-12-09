# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an agent-driven development framework that orchestrates a complete product development lifecycle—from requirements gathering through production deployment—using specialized AI agents. The framework is designed for building crypto/blockchain projects but applicable to any software project.

## Architecture

### Agent System

The framework uses nine specialized agents that work together in a structured workflow:

1. **context-engineering-expert** (AI & Context Engineering Expert) - Organizational workflow integration and multi-tool orchestration
2. **prd-architect** (Product Manager) - Requirements discovery and PRD creation
3. **architecture-designer** (Software Architect) - System design and SDD creation
4. **sprint-planner** (Technical PM) - Sprint planning and task breakdown
5. **sprint-task-implementer** (Senior Engineer) - Implementation with feedback loops
6. **senior-tech-lead-reviewer** (Senior Technical Lead) - Code review and quality gates
7. **devops-crypto-architect** (DevOps Architect) - Production deployment and infrastructure
8. **paranoid-auditor** (Security Auditor) - Comprehensive security and quality audits (ad-hoc use)
9. **devrel-translator** (Developer Relations) - Translates technical work into executive-ready communications (ad-hoc use)

Agents are defined in `.claude/agents/` and invoked via custom slash commands in `.claude/commands/`.

### Document Flow

The workflow produces structured artifacts in the `docs/` directory:

- `docs/integration-architecture.md` - Integration architecture for org tools (optional)
- `docs/tool-setup.md` - Tool configuration and setup guide (optional)
- `docs/team-playbook.md` - Team playbook for using integrated system (optional)
- `docs/prd.md` - Product Requirements Document
- `docs/sdd.md` - Software Design Document
- `docs/sprint.md` - Sprint plan with tasks and acceptance criteria
- `docs/a2a/reviewer.md` - Implementation reports from engineers
- `docs/a2a/engineer-feedback.md` - Review feedback from senior technical lead
- `docs/a2a/deployment-report.md` - Infrastructure reports from DevOps
- `docs/a2a/deployment-feedback.md` - Security audit feedback from auditor
- `docs/deployment/` - Production infrastructure documentation and runbooks

### Agent-to-Agent (A2A) Communication

The framework uses two feedback loops for quality assurance:

#### Implementation Feedback Loop (Phases 4-5)
- Engineer writes implementation report to `docs/a2a/reviewer.md`
- Senior lead writes feedback to `docs/a2a/engineer-feedback.md`
- Engineer reads feedback on next invocation, fixes issues, and updates report
- Cycle continues until senior lead approves with "All good"

#### Deployment Feedback Loop (Server Setup & Audit)
- DevOps creates infrastructure and writes report to `docs/a2a/deployment-report.md`
- Auditor reviews and writes feedback to `docs/a2a/deployment-feedback.md`
- DevOps reads feedback on next invocation, fixes issues, and updates report
- Cycle continues until auditor approves with "APPROVED - LET'S FUCKING GO"
- After approval, `/deploy-go` executes the production deployment

## Development Workflow Commands

### Phase 0: Organizational Integration Design (Optional)
```bash
/integrate-org-workflow
```
Launches `context-engineering-expert` agent to design integration architecture for connecting agentic-base with your organization's existing tools and workflows (Discord, Google Docs, Linear, etc.). Especially valuable for multi-team initiatives and multi-developer concurrent collaboration. Agent asks targeted questions about current workflows, pain points, integration requirements, team structure, and generates comprehensive integration architecture, tool setup guides, team playbooks, and implementation specifications. Outputs `docs/integration-architecture.md`, `docs/tool-setup.md`, `docs/team-playbook.md`, and `docs/a2a/integration-context.md`.

### Phase 0.5: Integration Implementation (Optional)
```bash
/implement-org-integration
```
Launches `devops-crypto-architect` agent to implement the organizational integration layer designed in Phase 0. Reviews integration architecture documents and implements Discord bot, Linear webhooks, GitHub webhooks, sync scripts, cron jobs, and monitoring. Creates complete integration infrastructure in `devrel-integration/` directory with deployment configs, operational runbooks, and testing procedures. **Prerequisites**: Must run `/integrate-org-workflow` first to generate integration design documents.

### Phase 1: Requirements
```bash
/plan-and-analyze
```
Launches `prd-architect` agent for structured discovery across 7 phases. Agent asks 2-3 questions at a time to extract complete requirements. Outputs `docs/prd.md`.

### Phase 2: Architecture
```bash
/architect
```
Launches `architecture-designer` agent to review PRD and design system architecture. Agent presents proposals for uncertain decisions with pros/cons. Outputs `docs/sdd.md`.

### Phase 3: Sprint Planning
```bash
/sprint-plan
```
Launches `sprint-planner` agent to break down work into actionable sprint tasks with acceptance criteria, dependencies, and assignments. Outputs `docs/sprint.md`.

### Phase 4: Implementation
```bash
/implement sprint-1
```
Launches `sprint-task-implementer` agent to execute sprint tasks. On first run, implements tasks. On subsequent runs, reads `docs/a2a/engineer-feedback.md`, addresses feedback, and regenerates report at `docs/a2a/reviewer.md`.

### Phase 5: Review
```bash
/review-sprint
```
Launches `senior-tech-lead-reviewer` agent to validate implementation against acceptance criteria. Either approves (writes "All good" to feedback file, updates sprint.md with ✅) or requests changes (writes detailed feedback to `docs/a2a/engineer-feedback.md`).

### Phase 6: Deployment
```bash
/deploy-production
```
Launches `devops-crypto-architect` agent to design and deploy production infrastructure. Creates IaC, CI/CD pipelines, monitoring, and comprehensive operational documentation in `docs/deployment/`.

### Deployment Feedback Loop: Server Setup → Audit → Deploy

The deployment workflow uses a feedback loop between DevOps and Security Auditor:

```
/setup-server → /audit-deployment → (repeat until approved) → /deploy-go
```

#### Step 1: Server Setup
```bash
/setup-server
```
Launches `devops-crypto-architect` agent in **server setup mode** to configure a bare metal or VPS server. The agent:
- Asks about server access details, services to deploy, security requirements
- Generates setup scripts in `docs/deployment/scripts/`
- Creates configuration files (PM2, systemd, nginx)
- Writes deployment report to `docs/a2a/deployment-report.md`

On subsequent runs, reads `docs/a2a/deployment-feedback.md` and addresses audit feedback first.

#### Step 2: Security Audit
```bash
/audit-deployment
```
Launches `paranoid-auditor` agent to review deployment infrastructure. The agent:
- Reads `docs/a2a/deployment-report.md` for context
- Audits all scripts, configs, and documentation
- Writes feedback to `docs/a2a/deployment-feedback.md`
- Verdict: **CHANGES_REQUIRED** or **APPROVED - LET'S FUCKING GO**

**Audit scope includes**:
- Server setup scripts for security vulnerabilities
- Deployment configurations and procedures
- Infrastructure security hardening (SSH, firewall, fail2ban)
- Secrets management and credential handling
- PM2/systemd/nginx configurations
- Backup and disaster recovery procedures

#### Step 3: Deploy (After Approval)
```bash
/deploy-go
```
Launches `devops-crypto-architect` agent to execute production deployment. The agent:
- Verifies `docs/a2a/deployment-feedback.md` contains "APPROVED - LET'S FUCKING GO"
- Refuses to proceed if not approved
- Guides deployment execution with verification steps
- Documents deployment completion

**Complete workflow example**:
```bash
# 1. DevOps creates infrastructure
/setup-server
# Agent asks questions, generates scripts, writes deployment-report.md

# 2. Security audit
/audit-deployment
# Agent reviews, writes deployment-feedback.md with CHANGES_REQUIRED

# 3. DevOps fixes issues
/setup-server
# Agent reads feedback, fixes issues, updates report

# 4. Re-audit
/audit-deployment
# Agent verifies fixes, writes "APPROVED - LET'S FUCKING GO"

# 5. Execute deployment
/deploy-go
# Agent guides production deployment execution
```

### Ad-Hoc: Security Audit (Codebase)
```bash
/audit
```
Launches `paranoid-auditor` agent to perform comprehensive security and quality audit of the codebase. Use this proactively:
- Before production deployment
- After major code changes or new integrations
- When implementing security-sensitive features (auth, payments, data handling)
- Periodically for ongoing projects

The agent performs:
- OWASP Top 10 vulnerability assessment
- Cryptographic implementation review
- Secrets and credential management audit
- Input validation and sanitization review
- Authentication and authorization analysis
- Data privacy and PII handling review
- Infrastructure security assessment
- Dependency and supply chain analysis

Outputs `SECURITY-AUDIT-REPORT.md` with prioritized findings (CRITICAL/HIGH/MEDIUM/LOW) and actionable remediation guidance.

### Ad-Hoc: Executive Translation
```bash
/translate @document.md for [audience]
```
Launches `devrel-translator` agent to translate technical documentation into executive-ready communications. Use this to:
- Create executive summaries from technical docs (PRD, SDD, audit reports, sprint updates)
- Prepare board presentations and investor updates
- Brief non-technical stakeholders on technical progress
- Explain architecture decisions to business stakeholders
- Translate security audits into risk assessments for executives

**Example invocations**:
```bash
/translate @SECURITY-AUDIT-REPORT.md for board of directors
/translate @docs/sdd.md for executives
/translate @docs/sprint.md for investors
/translate @docs/audits/2025-12-08/FINAL-AUDIT-REMEDIATION-REPORT.md for CEO
```

The agent creates:
- **Executive summaries** (1-2 pages, plain language, business-focused)
- **Stakeholder briefings** (tailored by audience: execs, board, investors, product, compliance)
- **Visual communication** (diagram suggestions, flowcharts, risk matrices)
- **FAQs** (anticipating stakeholder questions)
- **Risk assessments** (honest, transparent, actionable)

The agent focuses on:
- **Business value** over technical details
- **Clear analogies** for complex concepts
- **Specific metrics** and quantified impact
- **Honest risk** communication
- **Actionable next steps** with decision points

## Key Architectural Patterns

### Feedback-Driven Implementation

Implementation uses an iterative cycle:
1. Engineer implements → generates report
2. Senior lead reviews → provides feedback or approval
3. If feedback: engineer addresses issues → generates updated report
4. Repeat until approved

This ensures quality without blocking progress.

### Stateless Agent Invocations

Each agent invocation is stateless. Context is maintained through:
- Document artifacts in `docs/`
- A2A communication files in `docs/a2a/`
- Explicit reading of previous outputs

### Proactive Agent Invocation

Claude Code will automatically suggest relevant agents when:
- User wants to integrate with org tools → `context-engineering-expert`
- User needs to implement integration layer → `devops-crypto-architect` (integration mode)
- User describes a product idea → `prd-architect`
- User mentions architecture decisions → `architecture-designer`
- User wants to break down work → `sprint-planner`
- User mentions infrastructure/deployment → `devops-crypto-architect`

## MCP Server Integrations

The framework has pre-configured MCP servers for common tools:

- **linear** - Issue and project management
- **github** - Repository operations, PRs, issues
- **vercel** - Deployment and hosting
- **discord** - Community/team communication
- **web3-stats** - Blockchain data (Dune API, Blockscout)

These are enabled in `.claude/settings.local.json` and available for agents to use.

## Important Conventions

### Document Structure

All planning documents live in `docs/`:
- Primary docs: `prd.md`, `sdd.md`, `sprint.md`
- A2A communication: `docs/a2a/`
- Deployment docs: `docs/deployment/`

**Note**: This is a base framework repository. When using as a template for a new project, uncomment the generated artifacts section in `.gitignore` to avoid committing generated documentation (prd.md, sdd.md, sprint.md, a2a/, deployment/).

### Sprint Status Tracking

In `docs/sprint.md`, sprint tasks are marked with:
- No emoji = Not started
- ✅ = Completed and approved

The senior tech lead updates these after approval.

### Agent Prompts

Agent definitions in `.claude/agents/` include:
- `name` - Agent identifier
- `description` - When to invoke the agent
- `model` - AI model to use
- `color` - UI color coding

Command definitions in `.claude/commands/` contain the slash command expansion text.

## Working with Agents

### When to Use Each Agent

- **context-engineering-expert**: Designing integration with org tools (Discord, Linear, Google Docs), mapping workflows, adapting framework for multi-developer teams, designing context flow across platforms (Phase 0)
- **devops-crypto-architect**:
  - **Integration mode**: Implementing Discord bots, webhooks, sync scripts from integration architecture (Phase 0.5)
  - **Server setup mode**: Configuring bare metal/VPS servers, installing dependencies, security hardening (Ad-hoc via `/setup-server`)
  - **Deployment mode**: Production infrastructure, CI/CD pipelines, blockchain nodes, monitoring (Phase 6)
- **prd-architect**: Starting new features, unclear requirements (Phase 1)
- **architecture-designer**: Technical design decisions, choosing tech stack (Phase 2)
- **sprint-planner**: Breaking down work, planning implementation (Phase 3)
- **sprint-task-implementer**: Writing production code (Phase 4)
- **senior-tech-lead-reviewer**: Validating implementation quality (Phase 5)
- **paranoid-auditor**:
  - **Code audit mode**: Security audits, vulnerability assessment, OWASP Top 10 review (Ad-hoc via `/audit`)
  - **Deployment audit mode**: Infrastructure security, server hardening, deployment script review (Ad-hoc via `/audit-deployment`)
- **devrel-translator**: Translating technical documentation for executives, board, investors; creating executive summaries, stakeholder briefings, board presentations from PRDs, SDDs, audit reports (Ad-hoc)

### Agent Communication Style

Agents are instructed to:
- Ask clarifying questions rather than making assumptions
- Present proposals with pros/cons for uncertain decisions
- Never generate documents until confident they have complete information
- Be thorough and professional in their domain expertise

### Feedback Guidelines

When providing feedback in `docs/a2a/engineer-feedback.md`:
- Be specific with file paths and line numbers
- Explain the reasoning, not just what to fix
- Distinguish critical issues from nice-to-haves
- Test the implementation before approving

## Repository Structure

```
.claude/
├── agents/              # Agent definitions (9 agents)
├── commands/           # Slash command definitions
└── settings.local.json # MCP server configuration

docs/
├── integration-architecture.md  # Org tool integration design (optional)
├── tool-setup.md       # Integration setup guide (optional)
├── team-playbook.md    # Team usage guide (optional)
├── prd.md              # Product Requirements Document
├── sdd.md              # Software Design Document
├── sprint.md           # Sprint plan with tasks
├── a2a/                # Agent-to-agent communication
│   ├── reviewer.md              # Engineer implementation reports
│   ├── engineer-feedback.md     # Senior lead feedback
│   ├── deployment-report.md     # DevOps infrastructure reports
│   └── deployment-feedback.md   # Security audit feedback
└── deployment/         # Production infrastructure docs
    ├── scripts/        # Server setup scripts
    ├── runbooks/       # Operational procedures
    └── ...

devrel-integration/     # Discord bot & DevRel integration (optional)
├── src/                # Bot source code (TypeScript)
├── config/             # Configuration files
├── docs/               # Integration documentation
└── scripts/            # Deployment and automation scripts

PROCESS.md              # Comprehensive workflow documentation
CLAUDE.md              # This file
```

## Notes for Claude Code

- Always read `docs/prd.md`, `docs/sdd.md`, and `docs/sprint.md` for context when working on implementation tasks
- When `/implement` is invoked, check for `docs/a2a/engineer-feedback.md` first—if it exists, address the feedback before proceeding
- The senior tech lead role is played by the human user during review phases
- Never skip phases—each builds on the previous
- The process is designed for thorough discovery and iterative refinement, not speed
- Security is paramount, especially for crypto/blockchain projects
