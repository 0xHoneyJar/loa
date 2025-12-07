# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an agent-driven development framework that orchestrates a complete product development lifecycle—from requirements gathering through production deployment—using specialized AI agents. The framework is designed for building crypto/blockchain projects but applicable to any software project.

## Architecture

### Agent System

The framework uses seven specialized agents that work together in a structured workflow:

1. **context-engineering-expert** (AI & Context Engineering Expert) - Organizational workflow integration and multi-tool orchestration
2. **prd-architect** (Product Manager) - Requirements discovery and PRD creation
3. **architecture-designer** (Software Architect) - System design and SDD creation
4. **sprint-planner** (Technical PM) - Sprint planning and task breakdown
5. **sprint-task-implementer** (Senior Engineer) - Implementation with feedback loops
6. **senior-tech-lead-reviewer** (Senior Technical Lead) - Code review and quality gates
7. **devops-crypto-architect** (DevOps Architect) - Production deployment and infrastructure

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
- `docs/deployment/` - Production infrastructure documentation and runbooks

### Agent-to-Agent (A2A) Communication

The implementation phase uses a feedback loop:
- Engineer writes implementation report to `docs/a2a/reviewer.md`
- Senior lead writes feedback to `docs/a2a/engineer-feedback.md`
- Engineer reads feedback on next invocation, fixes issues, and updates report
- Cycle continues until senior lead approves

## Development Workflow Commands

### Phase 0: Organizational Integration (Optional)
```bash
/integrate-org-workflow
```
Launches `context-engineering-expert` agent to integrate agentic-base with your organization's existing tools and workflows (Discord, Google Docs, Linear, etc.). Especially valuable for multi-team initiatives and multi-developer concurrent collaboration. Agent asks targeted questions about current workflows, pain points, integration requirements, team structure, and generates comprehensive integration architecture, tool setup guides, team playbooks, and implementation code. Outputs `docs/integration-architecture.md`, `docs/tool-setup.md`, `docs/team-playbook.md`, and integration code.

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

- **context-engineering-expert**: Integrating with org tools (Discord, Linear, Google Docs), adapting framework for multi-developer teams, designing context flow across platforms
- **prd-architect**: Starting new features, unclear requirements
- **architecture-designer**: Technical design decisions, choosing tech stack
- **sprint-planner**: Breaking down work, planning implementation
- **sprint-task-implementer**: Writing production code
- **senior-tech-lead-reviewer**: Validating implementation quality
- **devops-crypto-architect**: Infrastructure, deployment, CI/CD, monitoring

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
├── agents/              # Agent definitions (7 agents)
├── commands/           # Slash command definitions (7 commands)
└── settings.local.json # MCP server configuration

docs/
├── integration-architecture.md  # Org tool integration design (optional)
├── tool-setup.md       # Integration setup guide (optional)
├── team-playbook.md    # Team usage guide (optional)
├── prd.md              # Product Requirements Document
├── sdd.md              # Software Design Document
├── sprint.md           # Sprint plan with tasks
├── a2a/                # Agent-to-agent communication
│   ├── reviewer.md     # Engineer implementation reports
│   └── engineer-feedback.md  # Senior lead feedback
└── deployment/         # Production infrastructure docs
    ├── infrastructure.md
    ├── deployment-guide.md
    ├── runbooks/
    └── ...

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
