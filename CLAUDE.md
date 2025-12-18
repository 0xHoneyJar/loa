# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an agent-driven development framework that orchestrates a complete product development lifecycle—from requirements gathering through production deployment—using specialized AI agents. The framework is designed for building crypto/blockchain projects but applicable to any software project.

## Architecture

### Agent System

The framework uses eight specialized agents that work together in a structured workflow:

1. **prd-architect** (Product Manager) - Requirements discovery and PRD creation
2. **architecture-designer** (Software Architect) - System design and SDD creation
3. **sprint-planner** (Technical PM) - Sprint planning and task breakdown
4. **sprint-task-implementer** (Senior Engineer) - Implementation with feedback loops
5. **senior-tech-lead-reviewer** (Senior Technical Lead) - Code review and quality gates
6. **devops-crypto-architect** (DevOps Architect) - Production deployment and infrastructure
7. **paranoid-auditor** (Security Auditor) - Comprehensive security and quality audits
8. **devrel-translator** (Developer Relations) - Translates technical work into executive-ready communications

Agents are defined in `.claude/agents/` and invoked via custom slash commands in `.claude/commands/`.

### Document Flow

The workflow produces structured artifacts in the `docs/` directory:

- `docs/prd.md` - Product Requirements Document
- `docs/sdd.md` - Software Design Document
- `docs/sprint.md` - Sprint plan with tasks and acceptance criteria
- `docs/a2a/index.md` - Sprint audit trail index (auto-maintained)
- `docs/a2a/sprint-N/` - Sprint-specific A2A communication (preserves audit trail)
  - `reviewer.md` - Implementation report from engineer
  - `engineer-feedback.md` - Review feedback from senior technical lead
  - `auditor-sprint-feedback.md` - Security audit feedback
  - `COMPLETED` - Completion marker (created by audit-sprint on approval)
- `docs/a2a/deployment-report.md` - Infrastructure reports from DevOps
- `docs/a2a/deployment-feedback.md` - Security audit feedback for deployment infrastructure
- `docs/deployment/` - Production infrastructure documentation and runbooks

### Agent-to-Agent (A2A) Communication

The framework uses three feedback loops for quality assurance:

#### Implementation Feedback Loop (Phases 4-5)
- Engineer writes implementation report to `docs/a2a/sprint-N/reviewer.md`
- Senior lead writes feedback to `docs/a2a/sprint-N/engineer-feedback.md`
- Engineer reads feedback on next invocation, fixes issues, and updates report
- Cycle continues until senior lead approves with "All good"

#### Sprint Security Audit Feedback Loop (Phase 5.5)
- After senior lead approval, security auditor reviews sprint implementation
- Auditor writes feedback to `docs/a2a/sprint-N/auditor-sprint-feedback.md`
- Verdict: "CHANGES_REQUIRED" (with security issues) or "APPROVED - LETS FUCKING GO"
- If changes required:
  - Engineer reads audit feedback on next `/implement sprint-N` invocation (checked FIRST)
  - Engineer addresses all CRITICAL and HIGH security issues
  - Engineer updates report with "Security Audit Feedback Addressed" section
  - Re-run `/audit-sprint sprint-N` to verify fixes
- Cycle continues until auditor approves
- On approval: Creates `docs/a2a/sprint-N/COMPLETED` marker file
- After approval, move to next sprint or deployment

#### Deployment Feedback Loop
- DevOps creates infrastructure and writes report to `docs/a2a/deployment-report.md`
- Auditor reviews via `/audit-deployment` and writes feedback to `docs/a2a/deployment-feedback.md`
- DevOps addresses feedback, updates infrastructure, and regenerates report
- Cycle continues until auditor approves with "APPROVED - LET'S FUCKING GO"

## Development Workflow Commands

### Execution Modes

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
Launches `sprint-task-implementer` agent to execute sprint tasks. The agent:
- Creates `docs/a2a/sprint-1/` directory if it doesn't exist
- Checks for existing feedback files (audit feedback checked FIRST, then engineer feedback)
- Implements tasks and generates report at `docs/a2a/sprint-1/reviewer.md`
- Updates `docs/a2a/index.md` with sprint status

On subsequent runs, reads `docs/a2a/sprint-1/engineer-feedback.md`, addresses feedback, and regenerates report.

### Phase 5: Review
```bash
/review-sprint sprint-1
```
Launches `senior-tech-lead-reviewer` agent to validate implementation against acceptance criteria. The agent:
- Validates sprint directory exists and contains `reviewer.md`
- Reviews actual code, not just the report
- Either approves (writes "All good" to `docs/a2a/sprint-1/engineer-feedback.md`, updates sprint.md with ✅)
- Or requests changes (writes detailed feedback to `docs/a2a/sprint-1/engineer-feedback.md`)
- Updates `docs/a2a/index.md` with review status

### Phase 5.5: Sprint Security Audit
```bash
/audit-sprint sprint-1
```
Launches `paranoid-auditor` agent to perform security and quality audit of sprint implementation. Run this AFTER `/review-sprint` approval. The agent:
- Validates sprint directory and senior lead approval ("All good" in engineer-feedback.md)
- Reviews implementation for security vulnerabilities (OWASP Top 10, injection, auth issues)
- Audits secrets management and credential handling
- Checks input validation and sanitization
- Verifies error handling and information disclosure
- Writes feedback to `docs/a2a/sprint-1/auditor-sprint-feedback.md`
- Verdict: **CHANGES_REQUIRED** or **APPROVED - LETS FUCKING GO**
- On approval: Creates `docs/a2a/sprint-1/COMPLETED` marker file
- Updates `docs/a2a/index.md` with audit status

**Feedback loop**:
```
/implement sprint-1 → /review-sprint sprint-1 → /audit-sprint sprint-1 → (if changes) → back to /implement sprint-1
                                                        ↓
                                               (if approved: LETS FUCKING GO)
                                                        ↓
                                               Creates COMPLETED marker
                                                        ↓
                                               Move to sprint-2
```

If audit finds issues:
1. Auditor writes "CHANGES_REQUIRED" with detailed security feedback
2. Run `/implement sprint-1` to address audit feedback
3. Engineer fixes issues and updates report
4. Re-run `/audit-sprint sprint-1` to verify fixes
5. Repeat until approved

**Use this proactively**:
- After every sprint review approval
- Before moving to next sprint
- Before production deployment
- After implementing security-sensitive features

### Phase 6: Deployment
```bash
/deploy-production
```
Launches `devops-crypto-architect` agent to design and deploy production infrastructure. Creates IaC, CI/CD pipelines, monitoring, and comprehensive operational documentation in `docs/deployment/`.

### Ad-Hoc: Deployment Infrastructure Audit
```bash
/audit-deployment
```
Launches `paranoid-auditor` agent to review deployment infrastructure. Use this to audit:
- Server setup scripts for security vulnerabilities
- Deployment configurations and procedures
- Infrastructure security hardening (SSH, firewall, fail2ban)
- Secrets management and credential handling
- PM2/systemd/nginx configurations
- Backup and disaster recovery procedures

The agent:
- Reads `docs/a2a/deployment-report.md` for context (if exists)
- Audits all scripts, configs, and documentation in `docs/deployment/`
- Writes feedback to `docs/a2a/deployment-feedback.md`
- Verdict: **CHANGES_REQUIRED** or **APPROVED - LET'S FUCKING GO**

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

## Linear Documentation Requirements

All agents that touch code or make decisions must document their work in Linear to create a complete audit trail. This enables:
- **Async collaboration**: Team members can understand decisions made in their absence
- **Context preservation**: Future developers understand why code was written a certain way
- **Accountability**: Clear record of who did what and when
- **Traceability**: Link from code back to requirements and decisions

### Integration Context

Linear team/project IDs and label configuration are stored in `docs/a2a/integration-context.md`. This file provides:
- Team ID and project ID for creating issues
- Standard label taxonomy for consistent organization
- Issue and commit message templates
- Workflow state mappings

### Agent Linear Documentation Responsibilities

| Agent | Documents In Linear |
|-------|-------------------|
| **sprint-planner** | Creates sprint project, documents planning decisions and rationale |
| **sprint-task-implementer** | Creates parent issue per task, sub-issues per component, tracks progress with comments |
| **senior-tech-lead-reviewer** | Adds review findings to implementation issues, documents approval/rejection with reasoning |
| **devops-crypto-architect** | Creates infrastructure issues, documents deployment decisions and configurations |
| **paranoid-auditor** | Creates security finding issues (CRITICAL/HIGH), adds comments for MEDIUM/LOW findings |

### Standard Label Taxonomy

All agents use consistent labels for organization:

**Agent Labels** (who did the work):
- `agent:implementer` - Sprint implementation work
- `agent:reviewer` - Code review work (implicit - reviewers add comments to implementer issues)
- `agent:devops` - Infrastructure and deployment work
- `agent:auditor` - Security audit findings
- `agent:planner` - Sprint planning work

**Type Labels** (what kind of work):
- `type:feature` - New functionality
- `type:bugfix` - Bug fixes
- `type:refactor` - Code improvements
- `type:infrastructure` - DevOps/deployment work
- `type:security` - Security-related work
- `type:audit-finding` - Security audit findings
- `type:planning` - Planning documentation

**Priority Labels** (for audit findings):
- `priority:critical` - Must fix immediately (blocking)
- `priority:high` - Must fix before production

**Sprint Labels**:
- `sprint:sprint-1`, `sprint:sprint-2`, etc.

**Source Labels** (where work originated):
- `source:discord` - From Discord feedback
- `source:internal` - Internal/agent-generated

### Required Documentation Content

**Implementation Issues** must include:
- Task description and acceptance criteria
- Discord source URL (if applicable)
- Implementation approach and key decisions
- Files modified with line ranges
- Test coverage details
- Verification steps

**Review Comments** must include:
- Review verdict (approved/changes requested)
- Specific findings with file:line references
- Reasoning for decisions
- Previous feedback verification status

**Audit Findings** must include:
- Severity level and OWASP/CWE references
- Proof of concept
- Impact assessment
- Specific remediation steps
- Verification method

### Querying Linear for Context

Agents can query Linear for context before starting work:

```typescript
// Find all implementation work for current sprint
mcp__linear__list_issues({
  filter: { labels: { some: { name: { eq: "sprint:sprint-1" } } } }
})

// Find all unresolved security findings
mcp__linear__list_issues({
  filter: {
    labels: { some: { name: { eq: "type:audit-finding" } } },
    state: { neq: "Done" }
  }
})

// Find all infrastructure work
mcp__linear__list_issues({
  filter: { labels: { some: { name: { eq: "agent:devops" } } } }
})
```

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

- **prd-architect**: Starting new features, unclear requirements (Phase 1 via `/plan-and-analyze`)
- **architecture-designer**: Technical design decisions, choosing tech stack (Phase 2 via `/architect`)
- **sprint-planner**: Breaking down work, planning implementation (Phase 3 via `/sprint-plan`)
- **sprint-task-implementer**: Writing production code (Phase 4 via `/implement`)
- **senior-tech-lead-reviewer**: Validating implementation quality (Phase 5 via `/review-sprint`)
- **devops-crypto-architect**: Production infrastructure, CI/CD pipelines, blockchain nodes, monitoring (Phase 6 via `/deploy-production`)
- **paranoid-auditor**:
  - **Code audit mode**: Security audits, vulnerability assessment, OWASP Top 10 review (Ad-hoc via `/audit`)
  - **Sprint audit mode**: Security review of sprint implementation after senior lead approval (Phase 5.5 via `/audit-sprint`)
  - **Deployment audit mode**: Infrastructure security, server hardening, deployment script review (Ad-hoc via `/audit-deployment`)
- **devrel-translator**: Translating technical documentation for executives, board, investors; creating executive summaries, stakeholder briefings, board presentations from PRDs, SDDs, audit reports (Ad-hoc via `/translate`)

### Agent Communication Style

Agents are instructed to:
- Ask clarifying questions rather than making assumptions
- Present proposals with pros/cons for uncertain decisions
- Never generate documents until confident they have complete information
- Be thorough and professional in their domain expertise

### Feedback Guidelines

When providing feedback in `docs/a2a/sprint-N/engineer-feedback.md`:
- Be specific with file paths and line numbers
- Explain the reasoning, not just what to fix
- Distinguish critical issues from nice-to-haves
- Test the implementation before approving

## Repository Structure

```
.claude/
├── agents/              # Agent definitions (8 agents)
├── commands/           # Slash command definitions (10 commands)
└── settings.local.json # MCP server configuration

docs/
├── prd.md              # Product Requirements Document
├── sdd.md              # Software Design Document
├── sprint.md           # Sprint plan with tasks
├── a2a/                # Agent-to-agent communication (preserves audit trail)
│   ├── index.md                   # Sprint audit trail index (auto-maintained)
│   ├── sprint-1/                  # Sprint 1 A2A files
│   │   ├── reviewer.md            # Engineer implementation report
│   │   ├── engineer-feedback.md   # Senior lead feedback
│   │   ├── auditor-sprint-feedback.md # Security audit feedback
│   │   └── COMPLETED              # Completion marker (created by audit-sprint)
│   ├── sprint-2/                  # Sprint 2 A2A files (same structure)
│   │   └── ...
│   ├── deployment-report.md       # DevOps infrastructure reports
│   └── deployment-feedback.md     # Deployment security audit feedback
└── deployment/         # Production infrastructure docs
    ├── scripts/        # Server setup scripts
    ├── runbooks/       # Operational procedures
    └── ...

app/                    # Application source code (generated by sprints)
├── src/                # Source code
├── tests/              # Test files
└── ...                 # Project-specific structure

PROCESS.md              # Comprehensive workflow documentation
CLAUDE.md               # This file
```

## Parallel Execution Guidelines

Agents are designed to handle large contexts by splitting work into parallel sub-tasks. This prevents context overflow and improves performance.

### Context Assessment (Phase -1)

All agents begin with a context assessment phase:

```bash
# Quick size check
wc -l docs/prd.md docs/sdd.md docs/sprint.md docs/a2a/*.md 2>/dev/null
```

**Thresholds vary by agent type:**

| Agent | SMALL | MEDIUM | LARGE |
|-------|-------|--------|-------|
| senior-tech-lead-reviewer | <3,000 | 3,000-6,000 | >6,000 |
| paranoid-auditor | <2,000 | 2,000-5,000 | >5,000 |
| sprint-task-implementer | <3,000 | 3,000-8,000 | >8,000 |
| devops-crypto-architect | <2,000 | 2,000-5,000 | >5,000 |

### Splitting Strategies by Agent

**senior-tech-lead-reviewer**: Split by sprint task
- Each task gets its own parallel Explore agent
- Results consolidated into single verdict

**paranoid-auditor**: Split by audit category
- 5 parallel agents: Security, Architecture, Code Quality, DevOps, Blockchain/Crypto
- Results consolidated with combined findings

**sprint-task-implementer**: Split by task or feedback source
- Option A: Parallel feedback checking (audit + senior lead)
- Option B: Parallel task implementation (independent tasks)

**devops-crypto-architect**: Split by infrastructure component
- Group components by dependency level
- Batch 1: Network + Security (no dependencies)
- Batch 2: Compute + Database + Storage (depend on network)
- Batch 3: Monitoring + CI/CD (depend on compute)

### Parallel Execution Pattern

Agents use the Task tool with `subagent_type="Explore"` for parallel work:

```
Spawn N parallel Explore agents, one per {task/category/component}:

Agent 1: "{Specific instructions for task 1}
- Reference specific files and requirements
- Define exact deliverables
- Return: structured summary for consolidation"

Agent 2: "{Specific instructions for task 2}
- Reference specific files and requirements
- Define exact deliverables
- Return: structured summary for consolidation"

... (similar for remaining tasks)
```

### Consolidation Requirements

After parallel execution, agents must:
1. Collect results from all sub-agents
2. Check for conflicts or inconsistencies
3. Generate unified output (report, verdict, implementation)
4. Ensure no gaps in coverage

### When NOT to Split

- **SMALL contexts**: Always proceed sequentially
- **Highly interdependent tasks**: Dependencies require sequential execution
- **Single-focus work**: One task with no natural divisions
- **User explicitly requests sequential**: Honor user preference

### Decision Matrix

| Context | Independence | Strategy |
|---------|--------------|----------|
| SMALL | Any | Sequential |
| MEDIUM | Low | Sequential with ordering |
| MEDIUM | High | Parallel by task/component |
| LARGE | Any | MUST split into parallel |

## Notes for Claude Code

- Always read `docs/prd.md`, `docs/sdd.md`, and `docs/sprint.md` for context when working on implementation tasks
- When `/implement sprint-N` is invoked:
  - Validate sprint name format (must be `sprint-N` where N is positive integer)
  - Create `docs/a2a/sprint-N/` directory if it doesn't exist
  - Check for audit feedback first (`docs/a2a/sprint-N/auditor-sprint-feedback.md`)
  - Then check for engineer feedback (`docs/a2a/sprint-N/engineer-feedback.md`)
  - Address all feedback before proceeding with new work
- When `/review-sprint sprint-N` is invoked:
  - Validate sprint directory and `reviewer.md` exist
  - Check for `COMPLETED` marker (skip if already completed)
- When `/audit-sprint sprint-N` is invoked:
  - Validate senior lead approval exists ("All good" in engineer-feedback.md)
  - Create `COMPLETED` marker on approval
- All sprint A2A files are preserved in `docs/a2a/sprint-N/` for audit trail
- The `docs/a2a/index.md` provides organizational memory across sprints
- The senior tech lead role is played by the human user during review phases
- Never skip phases—each builds on the previous
- The process is designed for thorough discovery and iterative refinement, not speed
- Security is paramount, especially for crypto/blockchain projects
- **Parallel execution**: Agents should assess context size first and split into parallel sub-tasks when context exceeds thresholds
