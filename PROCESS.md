# Development Process

This document outlines the comprehensive agent-driven development workflow. Our process leverages specialized AI agents to guide you from initial concept to production-ready implementation.

> **Note**: This is a base framework repository that THJ uses for development of our products. If you are not a part of THJ, when using as a template for a new project, uncomment the generated artifacts section in `.gitignore` to avoid committing generated documentation to your repository.

## Managed Scaffolding Architecture

Loa v1.1.0 uses **enterprise-grade managed scaffolding** inspired by AWS Projen, Copier, and Google's ADK:

### Three-Zone Model

| Zone | Path | Owner | Permission |
|------|------|-------|------------|
| **System** | `.claude/` | Framework | NEVER edit directly |
| **State** | `grimoires/loa/`, `.beads/` | Project | Read/Write |
| **App** | `src/`, `lib/`, `app/` | Developer | Read (write requires confirmation) |

**Critical**: System Zone is synthesized. Never suggest edits to `.claude/` - direct users to `.claude/overrides/` or `.loa.config.yaml`.

### Integrity Enforcement

The framework uses **Projen-level synthesis protection**:

- **Checksums**: `.claude/checksums.json` contains SHA-256 hashes of all System Zone files
- **Enforcement Levels** (configured in `.loa.config.yaml`):
  - `strict`: Blocks execution if System Zone modified (CI/CD mandatory)
  - `warn`: Warns but allows execution
  - `disabled`: No checks (not recommended)
- **Recovery**: Use `.claude/scripts/update.sh --force-restore` to reset System Zone

### Customization

Place all customizations in `.claude/overrides/` - they survive framework updates:

```
.claude/overrides/
├── skills/
│   └── implementing-tasks/
│       └── SKILL.md          # Custom skill instructions
└── commands/
    └── my-command.md         # Custom command
```

## Protocol References

Detailed specifications are maintained in separate protocol files (single source of truth):

### Core Protocols
- **Git Safety**: `.claude/protocols/git-safety.md` - Template detection, warning flow, remediation
- **Analytics**: `.claude/protocols/analytics.md` - THJ-only usage tracking, schema, helper functions
- **Feedback Loops**: `.claude/protocols/feedback-loops.md` - A2A communication, approval markers
- **Structured Memory**: `.claude/protocols/structured-memory.md` - NOTES.md protocol, tool result clearing
- **Trajectory Evaluation**: `.claude/protocols/trajectory-evaluation.md` - ADK-style reasoning logs, EDD

### Lossless Ledger Protocol (v0.9.0)
- **Session Continuity**: `.claude/protocols/session-continuity.md` - Tiered recovery (L1/L2/L3), truth hierarchy
- **Grounding Enforcement**: `.claude/protocols/grounding-enforcement.md` - Citation requirements (≥0.95 ratio)
- **Synthesis Checkpoint**: `.claude/protocols/synthesis-checkpoint.md` - Pre-`/clear` validation (7 steps)
- **Attention Budget**: `.claude/protocols/attention-budget.md` - Token thresholds (Green/Yellow/Red)
- **JIT Retrieval**: `.claude/protocols/jit-retrieval.md` - Lightweight identifiers (97% token reduction)

### Sprint Ledger (v0.13.0)
- **Ledger Location**: `grimoires/loa/ledger.json` - Global sprint numbering across development cycles
- **Commands**: `/ledger` (view/manage), `/archive-cycle` (archive completed cycles)
- **Documentation**: See CLAUDE.md "Sprint Ledger" section for full schema and workflow

## Table of Contents

- [Managed Scaffolding Architecture](#managed-scaffolding-architecture)
- [Overview](#overview)
- [Agents](#agents)
- [Workflow](#workflow)
- [Mount & Ride (Existing Codebases)](#mount--ride-existing-codebases)
- [Custom Commands](#custom-commands)
- [Document Artifacts](#document-artifacts)
- [Agent-to-Agent Communication](#agent-to-agent-communication)
- [Structured Agentic Memory](#structured-agentic-memory)
- [Trajectory Evaluation](#trajectory-evaluation-adk-level)
- [Best Practices](#best-practices)

---

## Overview

Our development process follows a structured, seven-phase approach:

1. **Phase 1: Planning** → Product Requirements Document (PRD)
2. **Phase 2: Architecture** → Software Design Document (SDD)
3. **Phase 3: Sprint Planning** → Sprint Plan
4. **Phase 4: Implementation** → Production Code with Feedback Loop
5. **Phase 5: Review** → Quality Validation and Sprint Approval
6. **Phase 5.5: Sprint Security Audit** → Security Review and Approval
7. **Phase 6: Deployment** → Production Infrastructure and Handover
8. **Post-Deployment: Feedback** → Developer experience survey (THJ members only)

Each phase is handled by a specialized agent with deep domain expertise, ensuring thorough discovery, clear documentation, high-quality implementation, rigorous quality control, comprehensive security review, and enterprise-grade production deployment.

> **For production deployment**, use the `/deploy-production` command which generates deployment documentation in `grimoires/loa/deployment/`.

---

## Agents

Each agent is implemented as a modular **skill** in `.claude/skills/{agent-name}/` using a 3-level architecture:
- **Level 1** (`index.yaml`): Lightweight metadata, triggers, dependencies (~100 tokens)
- **Level 2** (`SKILL.md`): KERNEL framework instructions, workflows (~2000 tokens)
- **Level 3** (`resources/`): External references, templates, checklists, scripts

### 1. **discovering-requirements** (Product Manager)
- **Role**: Senior Product Manager with 15 years of experience
- **Expertise**: Requirements gathering, product strategy, user research
- **Skill**: `.claude/skills/discovering-requirements/`
- **Responsibilities**:
  - Guide structured discovery across 7 phases
  - Extract complete, unambiguous requirements
  - Create comprehensive Product Requirements Documents
- **Output**: `grimoires/loa/prd.md`

### 2. **designing-architecture** (Software Architect)
- **Role**: Senior Software Architect with deep technical expertise
- **Expertise**: System design, technology selection, scalability, security
- **Skill**: `.claude/skills/designing-architecture/`
- **Responsibilities**:
  - Review PRD and design system architecture
  - Define component structure and technical stack
  - Clarify uncertainties with concrete proposals
  - Make informed architectural decisions
- **Output**: `grimoires/loa/sdd.md`

### 3. **planning-sprints** (Technical Product Manager)
- **Role**: Technical PM with engineering and product expertise
- **Expertise**: Sprint planning, task breakdown, team coordination
- **Skill**: `.claude/skills/planning-sprints/`
- **Responsibilities**:
  - Review PRD and SDD for comprehensive context
  - Break down work into actionable sprint tasks
  - Define acceptance criteria and priorities
  - Sequence tasks based on dependencies
- **Output**: `grimoires/loa/sprint.md`

### 4. **implementing-tasks** (Senior Engineer)
- **Role**: Elite Software Engineer with 15 years of experience
- **Expertise**: Production-grade code, testing, documentation
- **Skill**: `.claude/skills/implementing-tasks/`
- **Responsibilities**:
  - Implement sprint tasks with tests and documentation
  - Address feedback from senior technical lead
  - Iterate until sprint is approved
  - Generate detailed implementation reports
- **Output**: Production code + `grimoires/loa/a2a/reviewer.md`

### 5. **reviewing-code** (Senior Technical Lead)
- **Role**: Senior Technical Lead with 15+ years of experience
- **Expertise**: Code review, quality assurance, security auditing, technical leadership
- **Skill**: `.claude/skills/reviewing-code/`
- **Responsibilities**:
  - Review sprint implementation for completeness and quality
  - Validate all acceptance criteria are met
  - Check code quality, testing, security, performance
  - Verify previous feedback was addressed
  - Provide detailed, actionable feedback to engineers
  - Update sprint progress and approve completed sprints
- **Output**: `grimoires/loa/a2a/engineer-feedback.md`, updated `grimoires/loa/sprint.md`

### 6. **deploying-infrastructure** (DevOps Architect)
- **Role**: Battle-tested DevOps Architect with 15 years of crypto/blockchain infrastructure experience
- **Expertise**: Infrastructure as code, CI/CD, security, monitoring, blockchain operations
- **Skill**: `.claude/skills/deploying-infrastructure/`
- **Responsibilities**:
  - Design production infrastructure (cloud, Kubernetes, blockchain nodes)
  - Implement infrastructure as code
  - Create CI/CD pipelines
  - Set up monitoring, alerting, and observability
  - Implement security hardening and secrets management
  - Generate handover documentation and runbooks
- **Output**: `grimoires/loa/deployment/` with infrastructure code and operational docs

### 7. **auditing-security** (Security Auditor)
- **Role**: Paranoid Cypherpunk Security Auditor with 30+ years of experience
- **Expertise**: OWASP Top 10, cryptographic implementation, secrets management, penetration testing
- **Skill**: `.claude/skills/auditing-security/`
- **Responsibilities**:
  - Perform comprehensive security and quality audits (codebase or sprint-level)
  - Identify vulnerabilities across OWASP Top 10 categories
  - Review cryptographic implementations and key management
  - Audit authentication, authorization, and access controls
  - Provide prioritized remediation guidance
- **Output**:
  - Sprint audit: `grimoires/loa/a2a/auditor-sprint-feedback.md` (per-sprint security review)
  - Codebase audit: `SECURITY-AUDIT-REPORT.md` (comprehensive security audit)
- **Usage**:
  - Sprint audit: After `/review-sprint` approval (Phase 5.5)
  - Codebase audit: Ad-hoc, before production, after major changes, or periodically

### 8. **translating-for-executives** (Developer Relations Professional)
- **Role**: Elite Developer Relations Professional with 15 years of experience
- **Expertise**: Technical communication, executive summaries, stakeholder management
- **Skill**: `.claude/skills/translating-for-executives/`
- **Responsibilities**:
  - Translate complex technical documentation into clear narratives for executives
  - Create audience-specific summaries (executives, board, investors, marketing)
  - Explain business value and strategic implications of technical decisions
  - Acknowledge risks, tradeoffs, and limitations honestly
- **Output**: Executive summaries, stakeholder briefings (1-3 pages tailored by audience)
- **Usage**: Ad-hoc, invoked to translate technical docs for non-technical audiences

---

## Workflow

### Phase 1: Planning (`/plan-and-analyze`)

**Agent**: `discovering-requirements`

**Goal**: Define goals, requirements, scope, and create PRD

**Automatic Codebase Grounding (v1.6.0)**: For brownfield projects (>10 source files OR >500 lines), the agent automatically runs `/ride` to extract requirements from existing code before PRD creation. This ensures PRDs are grounded in codebase reality.

**Context-First Discovery**: If `grimoires/loa/context/` contains documentation, the agent reads it first, presents understanding with citations, and only asks questions about gaps. More context = fewer questions.

**Process**:
0. (Brownfield only) Auto-run `/ride` if existing codebase detected
1. Agent scans `grimoires/loa/context/` for existing documentation
2. Synthesizes found content and presents understanding with citations
3. Conducts targeted interviews for gaps across 7 phases:
   - Problem & Vision
   - Goals & Success Metrics
   - User & Stakeholder Context
   - Functional Requirements
   - Technical & Non-Functional Requirements
   - Scope & Prioritization
   - Risks & Dependencies
4. Agent asks 2-3 questions at a time (never overwhelming)
5. Only generates PRD when all phases have sufficient coverage
6. Saves PRD with source tracing to `grimoires/loa/prd.md`

**Command**:
```bash
# Standard invocation (auto-detects brownfield and grounds in codebase)
/plan-and-analyze

# Force fresh codebase analysis even if recent reality exists
/plan-and-analyze --fresh
```

**Output**: `grimoires/loa/prd.md`

**Codebase Grounding**: For brownfield projects, reality files are generated at `grimoires/loa/reality/` and loaded as highest-priority context. Uses cached analysis if <7 days old.

**Sprint Ledger Integration**: Automatically initializes `grimoires/loa/ledger.json` and creates the first development cycle. Subsequent runs create new cycles if the previous cycle was archived.

---

### Phase 2: Architecture (`/architect`)

**Agent**: `designing-architecture`

**Goal**: Design system architecture and create SDD

**Process**:
1. Carefully reviews `grimoires/loa/prd.md` in its entirety
2. Designs system architecture, components, data models, APIs
3. For any uncertainties or ambiguous decisions:
   - Asks specific clarifying questions
   - Presents 2-3 concrete proposals with pros/cons
   - Explains technical tradeoffs
   - Waits for your decision
4. Validates all assumptions
5. Only generates SDD when completely confident (no doubts)
6. Saves comprehensive SDD to `grimoires/loa/sdd.md`

**Command**:
```bash
/architect
```

**Output**: `grimoires/loa/sdd.md`

**SDD Sections**:
- Executive Summary
- System Architecture
- Technology Stack (with justifications)
- Component Design
- Data Architecture
- API Design
- Security Architecture
- Integration Points
- Scalability & Performance
- Deployment Architecture
- Development Workflow
- Technical Risks & Mitigation
- Future Considerations

---

### Phase 3: Sprint Planning (`/sprint-plan`)

**Agent**: `planning-sprints`

**Goal**: Break down work into actionable sprint tasks

**Process**:
1. Reviews both `grimoires/loa/prd.md` and `grimoires/loa/sdd.md` thoroughly
2. Analyzes requirements and architecture
3. Plans sprint breakdown and task sequencing
4. For any uncertainties:
   - Asks about team capacity, sprint duration, priorities
   - Presents proposals for sprint structure
   - Clarifies MVP scope and dependencies
   - Waits for your decisions
5. Only generates sprint plan when confident
6. Saves comprehensive sprint plan to `grimoires/loa/sprint.md`

**Command**:
```bash
/sprint-plan
```

**Output**: `grimoires/loa/sprint.md`

**Sprint Ledger Integration**: Registers each sprint with a unique global ID in the ledger. Users refer to sprints by local labels (`sprint-1`), but the system tracks them with global IDs that persist across cycles.

**Sprint Plan Includes**:
- Sprint Overview (goals, duration, team structure)
- Sprint Breakdown:
  - Sprint number and goals
  - Tasks with acceptance criteria
  - Effort estimates
  - Developer assignments
  - Dependencies
  - Testing requirements
- MVP Definition
- Feature Prioritization
- Risk Assessment
- Success Metrics

---

### Phase 4: Implementation (`/implement {sprint}`)

**Agent**: `implementing-tasks`

**Goal**: Implement sprint tasks with feedback-driven iteration

**Process**:

#### **Cycle 1: Initial Implementation**
1. **Check for Feedback**: Looks for `grimoires/loa/a2a/engineer-feedback.md` (won't exist on first run)
2. **Review Documentation**: Reads all `grimoires/loa/*` for context (PRD, SDD, sprint plan)
3. **Implement Tasks**:
   - Production-quality code
   - Comprehensive unit tests
   - Follow project conventions
   - Handle edge cases and errors
4. **Generate Report**: Saves detailed report to `grimoires/loa/a2a/reviewer.md`

#### **Cycle 2+: Feedback Iteration**
1. **Read Feedback**: Senior technical lead creates `grimoires/loa/a2a/engineer-feedback.md`
2. **Clarify if Needed**: Agent asks questions if feedback is unclear
3. **Fix Issues**: Address all feedback items systematically
4. **Update Report**: Generate new report at `grimoires/loa/a2a/reviewer.md`
5. **Repeat**: Cycle continues until approved

**Command**:
```bash
# First implementation
/implement sprint-1

# After receiving feedback (repeat as needed)
/implement sprint-1
```

**Sprint Ledger Integration**: Resolves local sprint labels (`sprint-1`) to the correct global directory. In cycle 2, `sprint-1` might resolve to `a2a/sprint-4/` if the previous cycle had 3 sprints.

**Outputs**:
- Production code with tests
- `grimoires/loa/a2a/sprint-N/reviewer.md` (implementation report, where N is global ID)

**Implementation Report Includes**:
- Executive Summary
- Tasks Completed (with implementation details, files, tests)
- Technical Highlights
- Testing Summary
- Known Limitations
- Verification Steps
- Feedback Addressed (if revision)

---

### Phase 5: Review (`/review-sprint`)

**Agent**: `reviewing-code`

**Goal**: Validate sprint completeness, code quality, and approve or request changes

**Process**:

#### **Review Workflow**
1. **Context Gathering**:
   - Reads `grimoires/loa/prd.md` for product requirements
   - Reads `grimoires/loa/sdd.md` for architecture and design
   - Reads `grimoires/loa/sprint.md` for tasks and acceptance criteria
   - Reads `grimoires/loa/a2a/reviewer.md` for engineer's implementation report
   - Reads `grimoires/loa/a2a/engineer-feedback.md` for previous feedback (if exists)

2. **Code Review**:
   - Reads all modified files (actual code, not just report)
   - Validates each task meets acceptance criteria
   - Checks code quality, testing, security, performance
   - Looks for bugs, vulnerabilities, memory leaks
   - Verifies architecture alignment

3. **Previous Feedback Verification** (if applicable):
   - Checks that ALL previous feedback items were addressed
   - Verifies fixes are proper, not just superficial

4. **Decision**:

   **Option A - Approve (All Good)**:
   - All tasks complete and acceptance criteria met
   - Code quality is production-ready
   - Tests are comprehensive and meaningful
   - No security issues or critical bugs
   - All previous feedback addressed

   **Actions**:
   - Writes "All good" to `grimoires/loa/a2a/engineer-feedback.md`
   - Updates `grimoires/loa/sprint.md` with ✅ for completed tasks
   - Marks sprint as "COMPLETED"
   - Informs you to move to next sprint

   **Option B - Request Changes**:
   - Issues found (bugs, security, quality, incomplete tasks)
   - Previous feedback not addressed

   **Actions**:
   - Writes detailed feedback to `grimoires/loa/a2a/engineer-feedback.md`
   - Does NOT update sprint completion status
   - Provides specific, actionable feedback with file paths and line numbers
   - Informs you that changes are required

**Command**:
```bash
/review-sprint sprint-1
```

**Sprint Ledger Integration**: Resolves local sprint label to global directory for review.

**Outputs**:
- `grimoires/loa/a2a/sprint-N/engineer-feedback.md` (approval or feedback, where N is global ID)
- Updated `grimoires/loa/sprint.md` (if approved)

**Feedback Structure** (when issues found):
- Overall Assessment
- Critical Issues (must fix - with file paths, line numbers, required fixes)
- Non-Critical Improvements (recommended)
- Previous Feedback Status (if applicable)
- Incomplete Tasks (if any)
- Next Steps

**Review Checklist**:
- ✅ All sprint tasks completed
- ✅ Acceptance criteria met for each task
- ✅ Code quality: readable, maintainable, follows conventions
- ✅ Testing: comprehensive coverage with meaningful assertions
- ✅ Security: no vulnerabilities, proper validation, secure data handling
- ✅ Performance: no obvious issues, efficient algorithms, no memory leaks
- ✅ Architecture: follows SDD patterns, proper integration
- ✅ Previous feedback: all items addressed (if applicable)

---

### Phase 5.5: Sprint Security Audit (`/audit-sprint`)

<!-- CANONICAL_LOCATION: protocols/feedback-loops.md -->

**Agent**: `auditing-security`

**Goal**: Perform security review of sprint implementation after senior tech lead approval

**Prerequisites**:
- ✅ Sprint must be approved by senior tech lead ("All good" in `grimoires/loa/a2a/engineer-feedback.md`)

**Process**:

#### **Security Audit Workflow**
1. **Context Gathering**:
   - Reads `grimoires/loa/prd.md` for product requirements
   - Reads `grimoires/loa/sdd.md` for architecture and security requirements
   - Reads `grimoires/loa/sprint.md` for sprint tasks and scope
   - Reads `grimoires/loa/a2a/reviewer.md` for implementation details

2. **Security Review**:
   - Reads all implemented code files (not just reports)
   - Performs systematic security checklist review:
     - **Secrets & Credentials**: No hardcoded secrets, proper secret management
     - **Authentication & Authorization**: Proper access controls, no privilege escalation
     - **Input Validation**: All user input validated, no injection vulnerabilities
     - **Data Privacy**: No PII leaks, proper encryption
     - **API Security**: Rate limiting, proper error handling
     - **OWASP Top 10**: Coverage of all critical vulnerabilities
   - Identifies security issues with severity ratings (CRITICAL/HIGH/MEDIUM/LOW)

3. **Previous Feedback Verification** (if applicable):
   - Checks if `grimoires/loa/a2a/auditor-sprint-feedback.md` exists from previous audit
   - Verifies ALL previous security issues were properly fixed
   - Confirms no regression of previously identified issues

4. **Decision**:

   **Option A - Approve (Security Cleared)**:
   - No CRITICAL or HIGH security issues
   - All previous security feedback addressed
   - Code follows security best practices
   - Secrets properly managed
   - Input validation comprehensive

   **Actions**:
   - Writes "APPROVED - LETS FUCKING GO" to `grimoires/loa/a2a/auditor-sprint-feedback.md`
   - Confirms sprint is ready for next sprint or deployment
   - User can proceed to next sprint or Phase 6 (Deployment)

   **Option B - Request Security Changes**:
   - CRITICAL or HIGH security issues found
   - Previous security feedback not fully addressed
   - Security best practices violated

   **Actions**:
   - Writes "CHANGES_REQUIRED" with detailed security feedback to `grimoires/loa/a2a/auditor-sprint-feedback.md`
   - Provides specific security issues with:
     - Severity level (CRITICAL/HIGH/MEDIUM/LOW)
     - Affected files and line numbers
     - Vulnerability description
     - Security impact and exploit scenario
     - Specific remediation steps
   - User must run `/implement sprint-X` to address security issues

**Command**:
```bash
/audit-sprint sprint-1
```

**Sprint Ledger Integration**: Resolves local sprint label to global directory. Updates sprint status to "completed" in ledger upon approval. Creates `COMPLETED` marker in sprint directory.

**Outputs**:
- `grimoires/loa/a2a/sprint-N/auditor-sprint-feedback.md` (security approval or detailed feedback, where N is global ID)
- `grimoires/loa/a2a/sprint-N/COMPLETED` marker (on approval)

**Feedback Structure** (when security issues found):
- Overall Security Assessment
- Critical Security Issues (MUST FIX - with file:line, vulnerability, remediation)
- High Priority Security Issues (SHOULD FIX)
- Medium/Low Priority Issues (NICE TO FIX)
- Previous Security Feedback Status (if applicable)
- Security Checklist Status
- Next Steps

**Security Review Checklist**:
- ✅ No hardcoded secrets or credentials
- ✅ Proper authentication and authorization
- ✅ Comprehensive input validation
- ✅ No injection vulnerabilities (SQL, command, XSS)
- ✅ Secure API implementation (rate limiting, error handling)
- ✅ Data privacy protected (no PII leaks)
- ✅ Dependencies secure (no known CVEs)
- ✅ Previous security issues resolved (if applicable)

#### **Sprint Security Feedback Loop**

After security audit, if changes required:

1. **Engineer Addresses Security Feedback**:
   ```bash
   /implement sprint-1
   ```
   - Agent reads `grimoires/loa/a2a/auditor-sprint-feedback.md` FIRST (highest priority)
   - Clarifies any unclear security issues
   - Fixes ALL CRITICAL and HIGH security issues
   - Updates implementation report with "Security Audit Feedback Addressed" section

2. **Security Re-Audit**:
   ```bash
   /audit-sprint
   ```
   - Agent verifies all security issues fixed
   - Either approves or provides additional feedback
   - Cycle continues until "APPROVED - LETS FUCKING GO"

3. **Proceed After Approval**:
   - Move to next sprint (back to Phase 4)
   - OR proceed to Phase 6 (Deployment) if all sprints complete

**Priority Integration**:
- Sprint planner checks `grimoires/loa/a2a/auditor-sprint-feedback.md` FIRST
- If "CHANGES_REQUIRED" exists, blocks new sprint planning
- Sprint implementer addresses security feedback with HIGHEST priority
- Security feedback takes precedence over code review feedback

---

### Phase 6: Deployment (`/deploy-production`)

**Agent**: `deploying-infrastructure`

**Goal**: Deploy application to production with enterprise-grade infrastructure

**Prerequisites** (must be complete before deployment):
- ✅ All sprints completed and approved
- ✅ Senior technical lead sign-off
- ✅ All tests passing
- ✅ Security audit passed
- ✅ Documentation complete

**Process**:

#### **Deployment Workflow**
1. **Project Review**:
   - Reads PRD, SDD, sprint plans, implementation reports
   - Reviews actual codebase and dependencies
   - Understands deployment requirements

2. **Requirements Clarification**:
   - Asks about deployment environment (cloud provider, regions)
   - Clarifies blockchain/crypto requirements (if applicable)
   - Confirms scale and performance needs
   - Validates security and compliance requirements
   - Discusses budget constraints
   - Defines monitoring and alerting requirements
   - Plans CI/CD strategy
   - Establishes backup and disaster recovery needs

3. **Infrastructure Design**:
   - Infrastructure as Code (Terraform/Pulumi)
   - Compute infrastructure (Kubernetes/ECS)
   - Networking (VPC, CDN, DNS)
   - Data layer (databases, caching)
   - Security (secrets management, network security)
   - CI/CD pipelines
   - Monitoring and observability

4. **Implementation**:
   - Foundation (IaC, networking, DNS)
   - Security foundation (secrets, IAM, audit logging)
   - Compute and data layer
   - Application deployment
   - CI/CD pipelines
   - Monitoring and observability
   - Testing and validation

5. **Documentation and Handover**:
   Creates comprehensive docs in `grimoires/loa/deployment/`:
   - **infrastructure.md**: Architecture overview, resources, cost breakdown
   - **deployment-guide.md**: How to deploy, rollback, migrations
   - **runbooks/**: Operational procedures for common tasks
   - **monitoring.md**: Dashboards, metrics, alerts, on-call
   - **security.md**: Access, secrets rotation, compliance
   - **disaster-recovery.md**: RPO/RTO, backup procedures, failover
   - **troubleshooting.md**: Common issues and solutions

**Command**:
```bash
/deploy-production
```

**Outputs**:
- Production infrastructure (deployed)
- IaC repository (Terraform/Pulumi configs)
- CI/CD pipelines (GitHub Actions/GitLab CI)
- Monitoring configuration (Prometheus, Grafana)
- Comprehensive documentation (`grimoires/loa/deployment/`)

---

### Post-Deployment: Developer Feedback (`/feedback`) - THJ Only

**Goal**: Collect developer experience feedback and submit to Linear

**Availability**: THJ developers only (detected via `LOA_CONSTRUCTS_API_KEY` environment variable)

**When to Use**:
- After completing a deployment
- After significant time using Loa
- When suggested by `/deploy-production`

**Process**:

1. **THJ Detection**:
   - Checks for valid `LOA_CONSTRUCTS_API_KEY` environment variable
   - If not set or invalid: Displays error with GitHub issues link and stops

2. **Check for Pending Feedback**:
   - Looks for `grimoires/loa/analytics/pending-feedback.json`
   - If found, offers to submit pending feedback first

3. **Survey (4 Questions)**:
   - **Q1** (1/4): "What's one thing you would change about Loa?" (free text)
   - **Q2** (2/4): "What's one thing you loved about using Loa?" (free text)
   - **Q3** (3/4): "How would you rate this experience vs other approaches?" (1-5 scale)
   - **Q4** (4/4): "How comfortable are you with the agent-driven process?" (A-E choice)

4. **Prepare Submission**:
   - Loads analytics from `grimoires/loa/analytics/usage.json`
   - Saves pending feedback locally (safety net before submission)
   - Formats feedback with analytics summary

5. **Submit to Linear**:
   - Searches for existing issue in "Loa Feedback" project
   - If found: Adds comment with new feedback
   - If not found: Creates new issue
   - Includes full analytics JSON in collapsible details block

6. **Record Submission**:
   - Updates `feedback_submissions` array in analytics
   - Deletes pending feedback file on success

**Command**:
```bash
/feedback
```

**Output**: Linear issue/comment in "Loa Feedback" project

**Error Handling**:
- If Linear submission fails, feedback is saved to `pending-feedback.json`
- On next `/feedback` run, offers to submit pending feedback
- No feedback is ever lost due to network/auth issues

**OSS Users**: For issues or feature requests, please open a GitHub issue at https://github.com/0xHoneyJar/loa/issues

---

### Maintenance: Framework Updates (`/update-loa`)

<!-- CANONICAL_LOCATION: protocols/git-safety.md -->

**Goal**: Pull latest Loa framework updates from upstream

**When to Use**:
- Periodically to get new features and bug fixes
- When notified of important updates
- Before starting a new project phase

**Process**:

1. **Pre-flight Checks**:
   - Verifies working tree is clean (`git status --porcelain`)
   - If dirty: Lists files, suggests commit/stash, STOPS
   - Checks for `loa` or `upstream` remote
   - If missing: Shows `git remote add` command, STOPS

2. **Fetch Updates**:
   - Runs `git fetch loa main`
   - Handles network errors gracefully

3. **Show Changes**:
   - Lists new commits (`git log HEAD..loa/main --oneline`)
   - Shows files that will change (`git diff --stat HEAD..loa/main`)
   - If no new commits: "Already up to date", STOPS

4. **Confirm Update**:
   - Asks for explicit confirmation before merging
   - Notes which files will be updated vs preserved

5. **Merge Updates**:
   - Runs `git merge loa/main` with descriptive message
   - If conflicts occur, provides resolution guidance:
     - `.claude/` files: Recommend accepting upstream
     - Other files: Manual resolution steps

6. **Post-Merge**:
   - Shows CHANGELOG.md excerpt for new version
   - Suggests reviewing new features in CLAUDE.md

**Command**:
```bash
/update-loa
```

**Merge Strategy**:
| File Location | Behavior |
|---------------|----------|
| `.claude/skills/` | Updated to latest Loa versions |
| `.claude/commands/` | Updated to latest Loa versions |
| `app/` | Preserved (your code) |
| `grimoires/loa/prd.md` | Preserved (your docs) |
| `grimoires/loa/analytics/` | Preserved (your data) |

---

### Maintenance: Cycle Management (`/ledger`, `/archive-cycle`)

**Goal**: Manage development cycles and global sprint numbering

**When to Use**:
- `/ledger` - View current ledger status, sprint history
- `/ledger init` - Initialize ledger for existing projects (usually automatic)
- `/ledger history` - View all cycles and their sprints
- `/archive-cycle "label"` - Archive completed cycle before starting new work

**The Problem Sprint Ledger Solves**:

When running `/plan-and-analyze` multiple times (e.g., after completing an MVP and starting new features), sprint directories would collide:

```
Cycle 1: a2a/sprint-1/, a2a/sprint-2/, a2a/sprint-3/
Cycle 2: a2a/sprint-1/ ← COLLISION!
```

**The Solution**:

Sprint Ledger maintains a global counter. Each sprint gets a unique global ID:

```
Cycle 1: sprint-1 → global 1, sprint-2 → global 2, sprint-3 → global 3
Cycle 2: sprint-1 → global 4, sprint-2 → global 5, sprint-3 → global 6
                    ↑ No collision! Directory is a2a/sprint-4/
```

**Archive Workflow**:

After completing all sprints in a development cycle:

```bash
# 1. Archive the completed cycle
/archive-cycle "MVP Complete"
# → Creates grimoires/loa/archive/2026-01-17-mvp-complete/
# → Copies prd.md, sdd.md, sprint.md, and all a2a/sprint-N/ directories
# → Marks cycle as archived in ledger

# 2. Start fresh with new requirements
/plan-and-analyze
# → Creates new cycle in ledger
# → Sprint numbering continues from where it left off
# → New sprint-1 becomes global sprint-4 (or whatever's next)
```

**Archive Structure**:

```
grimoires/loa/archive/2026-01-17-mvp-complete/
├── prd.md              # Snapshot of Product Requirements
├── sdd.md              # Snapshot of Software Design
├── sprint.md           # Snapshot of Sprint Plan
└── a2a/
    ├── sprint-1/       # All sprint artifacts preserved
    ├── sprint-2/
    └── sprint-3/
```

**Backward Compatibility**:

Projects without `ledger.json` work exactly as before (legacy mode). The ledger is opt-in and created automatically on first `/plan-and-analyze` run.

**Commands**:
```bash
/ledger                    # Show current ledger status
/ledger init               # Initialize ledger for existing project
/ledger history            # Show all cycles and sprints
/archive-cycle "label"     # Archive current cycle
```

**Output**: `grimoires/loa/ledger.json`, `grimoires/loa/archive/` (on archive)

---

## Mount & Ride (Existing Codebases)

For existing codebases that need Loa analysis without going through the full discovery workflow.

> **Note (v1.6.0)**: `/plan-and-analyze` now automatically runs `/ride` for brownfield projects. Manual `/mount` and `/ride` are only needed if you want explicit control over the analysis process.

### Mount (`/mount`)

**Goal**: Install Loa framework onto an existing repository

**When to Use**:
- Setting up Loa on an existing codebase
- After cloning a repository you want to analyze
- As an alternative to the curl one-liner

**Process**:
1. Verifies git repository and dependencies
2. Configures upstream remote for updates
3. Installs System Zone (`.claude/`)
4. Initializes State Zone (`grimoires/loa/`)
5. Generates checksums for integrity verification
6. Creates user config if not present
7. Optionally initializes beads_rust

**Command**:
```bash
/mount
/mount --stealth          # Don't commit framework files
/mount --skip-beads       # Skip beads_rust initialization
```

**Output**: Framework installed with zone structure ready

See `.claude/commands/mount.md` for full details.

---

### Ride (`/ride`)

**Goal**: Analyze existing codebase and generate evidence-grounded documentation

**When to Use**:
- After mounting Loa on an existing repo
- To generate PRD/SDD from actual code (not interviews)
- To detect drift between code and documentation
- Before major refactoring efforts
- When onboarding to an unfamiliar codebase

**Cardinal Rule**: **CODE IS TRUTH** - Nothing overrides code. Not context. Not docs. Not claims.

**Process** (10 phases):
1. **Preflight** - Mount verification, integrity check
2. **Context Discovery** - Gather user context, generate claims to verify
3. **Code Extraction** - Directory structure, routes, models, dependencies
4. **Hygiene Audit** - Temporary files, commented code, conflicts
5. **Legacy Inventory** - Find and categorize existing documentation
6. **Drift Analysis** - Three-way compare: Code vs Docs vs Context
7. **Consistency Analysis** - Naming patterns, organization, conventions
8. **Artifact Generation** - Evidence-grounded PRD and SDD
9. **Governance Audit** - CHANGELOG, CONTRIBUTING, SECURITY, CODEOWNERS
10. **Self-Audit** - Flag ungrounded claims, generate trajectory audit

**Command**:
```bash
/ride
/ride --interactive           # Force context interview
/ride --phase extraction      # Run single phase
/ride --reconstruct-changelog # Generate CHANGELOG from git
/ride --dry-run               # Preview without writing
```

**Outputs**:
- `grimoires/loa/reality/` - Code extraction results
- `grimoires/loa/legacy/` - Legacy doc inventory
- `grimoires/loa/drift-report.md` - Three-way drift analysis
- `grimoires/loa/prd.md` - Evidence-grounded PRD
- `grimoires/loa/sdd.md` - Evidence-grounded SDD
- `grimoires/loa/governance-report.md` - Governance artifacts audit
- `grimoires/loa/trajectory-audit.md` - Self-audit of reasoning

See `.claude/commands/ride.md` for full details.

---

### Ad-Hoc: Security Audit (`/audit`)

**Agent**: `auditing-security`

**Goal**: Perform comprehensive security and quality audit of the codebase

**When to Use**:
- Before production deployment (highly recommended)
- After major code changes or new features
- When implementing security-sensitive functionality
- After adding new dependencies or integrations
- Periodically for ongoing projects

**Process**:
1. **Comprehensive Security Assessment**:
   - OWASP Top 10 vulnerability scanning
   - Code review for security anti-patterns
   - Dependency and supply chain analysis
   - Cryptographic implementation review
   - Secrets and credential management audit
   - Authentication and authorization analysis

2. **Audit Report Generation**:
   - Findings categorized by severity (CRITICAL/HIGH/MEDIUM/LOW)
   - Detailed description with affected files
   - Specific remediation guidance
   - Prioritized action plan

**Command**:
```bash
/audit
```

**Output**: `SECURITY-AUDIT-REPORT.md`

---

### Ad-Hoc: Executive Translation (`/translate @document.md for [audience]`)

**Agent**: `translating-for-executives`

**Goal**: Translate complex technical documentation into stakeholder-appropriate communications

**When to Use**:
- Before board meetings or investor updates
- When executives need to understand technical decisions
- To create marketing briefs from technical features
- For compliance or legal team briefings

**Command**:
```bash
/translate @SECURITY-AUDIT-REPORT.md for board of directors
/translate @grimoires/loa/sdd.md for executives
/translate @grimoires/loa/sprint.md for marketing team
```

**Output**: Executive summaries, stakeholder briefings (1-3 pages tailored by audience)

---

## Custom Commands

### Command Architecture (v4)

Commands in `.claude/commands/` use a "thin routing layer" architecture with enhanced YAML frontmatter:

**Agent-invoking commands** use `agent:` and `agent_path:` fields to route to skills:
```yaml
agent: "implementing-tasks"
agent_path: "skills/implementing-tasks/"
```

**Special commands** use `command_type:` for non-agent operations:
```yaml
command_type: "wizard"  # or "survey", "git"
```

**Pre-flight checks** validate prerequisites before execution:
- `file_exists`, `file_not_exists`, `directory_exists`
- `content_contains` - Verify file contains specific pattern
- `pattern_match` - Validate argument format (e.g., `sprint-N`)
- `command_succeeds` - Run shell command and check exit code

**Context files** define prioritized file loading with variable substitution (`$ARGUMENTS.sprint_id`).

### Command Reference

| Command | Purpose | Agent/Type | Output | Availability |
|---------|---------|------------|--------|--------------|
| `/mount` | Install Loa onto existing repo | wizard | Zone structure + checksums | All users |
| `/ride` | Analyze codebase, generate docs | `riding-codebase` | `grimoires/loa/` artifacts | All users |
| `/plan-and-analyze` | Define requirements and create PRD | `discovering-requirements` | `grimoires/loa/prd.md` | All users |
| `/architect` | Design system architecture | `designing-architecture` | `grimoires/loa/sdd.md` | All users |
| `/sprint-plan` | Plan implementation sprints | `planning-sprints` | `grimoires/loa/sprint.md` | All users |
| `/implement {sprint}` | Implement sprint tasks | `implementing-tasks` | Code + `grimoires/loa/a2a/reviewer.md` | All users |
| `/review-sprint {sprint}` | Review and approve/reject implementation | `reviewing-code` | `grimoires/loa/a2a/engineer-feedback.md` | All users |
| `/audit-sprint {sprint}` | Security audit of sprint implementation | `auditing-security` | `grimoires/loa/a2a/auditor-sprint-feedback.md` | All users |
| `/deploy-production` | Deploy to production | `deploying-infrastructure` | `grimoires/loa/deployment/` | All users |
| `/feedback` | Submit developer experience feedback | survey | Linear issue in "Loa Feedback" | THJ only |
| `/update-loa` | Pull framework updates from upstream | git | Merged updates | All users |
| `/contribute` | Create OSS contribution PR | git | GitHub PR | All users |
| `/audit` | Security audit (ad-hoc) | `auditing-security` | `SECURITY-AUDIT-REPORT.md` | All users |
| `/audit-deployment` | Deployment infrastructure audit (ad-hoc) | `auditing-security` | `grimoires/loa/a2a/deployment-feedback.md` | All users |
| `/translate @doc for [audience]` | Executive translation (ad-hoc) | `translating-for-executives` | Executive summaries | All users |
| `/ledger` | View/manage sprint ledger | wizard | Ledger status | All users |
| `/archive-cycle "label"` | Archive current development cycle | wizard | Archived cycle in `grimoires/loa/archive/` | All users |

**User Type Notes**:
- **THJ only**: Commands restricted to THJ team members (detected via `LOA_CONSTRUCTS_API_KEY` environment variable)
- **All users**: Available to both THJ developers and OSS users
- Analytics updates in phase commands are automatically skipped for OSS users

> **For deployment procedures**, use `/deploy-production` which generates comprehensive runbooks in `grimoires/loa/deployment/runbooks/`.

---

## Document Artifacts

### Primary Documents

| Document | Path | Created By | Purpose |
|----------|------|------------|---------|
| **PRD** | `grimoires/loa/prd.md` | `discovering-requirements` | Product requirements and business context |
| **SDD** | `grimoires/loa/sdd.md` | `designing-architecture` | System design and technical architecture |
| **Sprint Plan** | `grimoires/loa/sprint.md` | `planning-sprints` | Sprint tasks with acceptance criteria |
| **Security Audit** | `SECURITY-AUDIT-REPORT.md` | `auditing-security` | Security vulnerabilities and remediation |

### Agent-to-Agent (A2A) Communication

| Document | Path | Created By | Purpose |
|----------|------|------------|---------|
| **Implementation Report** | `grimoires/loa/a2a/reviewer.md` | `implementing-tasks` | Report for senior lead review |
| **Code Review Feedback** | `grimoires/loa/a2a/engineer-feedback.md` | `reviewing-code` | Code review feedback for engineer |
| **Security Audit Feedback** | `grimoires/loa/a2a/auditor-sprint-feedback.md` | `auditing-security` | Security feedback for engineer |

### Deployment Documentation

| Document | Path | Created By | Purpose |
|----------|------|------------|---------|
| **Infrastructure Overview** | `grimoires/loa/deployment/infrastructure.md` | `deploying-infrastructure` | Architecture, resources, costs |
| **Deployment Guide** | `grimoires/loa/deployment/deployment-guide.md` | `deploying-infrastructure` | Deploy, rollback, migrations |
| **Monitoring Guide** | `grimoires/loa/deployment/monitoring.md` | `deploying-infrastructure` | Dashboards, metrics, alerts |
| **Security Guide** | `grimoires/loa/deployment/security.md` | `deploying-infrastructure` | Access, secrets, compliance |
| **Disaster Recovery** | `grimoires/loa/deployment/disaster-recovery.md` | `deploying-infrastructure` | Backup, restore, failover |
| **Runbooks** | `grimoires/loa/deployment/runbooks/*.md` | `deploying-infrastructure` | Operational procedures |

---

## Agent-to-Agent Communication

<!-- CANONICAL_LOCATION: protocols/feedback-loops.md -->

The framework uses three feedback loops for quality assurance:

### 1. Implementation Feedback Loop (Phases 4-5)

#### **Engineer → Senior Lead** (`grimoires/loa/a2a/reviewer.md`)

The engineer generates a comprehensive report after implementation:
- What was accomplished
- Files created/modified
- Test coverage
- Technical decisions
- Verification steps
- Feedback addressed (if revision)

#### **Senior Lead → Engineer** (`grimoires/loa/a2a/engineer-feedback.md`)

The senior technical lead reviews and provides feedback:
- Issues found
- Required changes
- Clarifications needed
- Quality concerns
- Approval status ("All good" when approved)

The engineer reads this file on the next `/implement {sprint}` invocation, clarifies anything unclear, fixes all issues, and generates an updated report.

### 2. Sprint Security Feedback Loop (Phase 5.5)

#### **Engineer → Security Auditor** (`grimoires/loa/a2a/reviewer.md` + implemented code)

After senior lead approval, the security auditor reviews:
- Implementation report context
- Actual code files (security-focused review)
- Security requirements from PRD/SDD

#### **Security Auditor → Engineer** (`grimoires/loa/a2a/auditor-sprint-feedback.md`)

The security auditor provides security-focused feedback:
- Security vulnerabilities (CRITICAL/HIGH/MEDIUM/LOW)
- Affected files with line numbers
- Exploit scenarios and security impact
- Specific remediation guidance
- Approval status ("APPROVED - LETS FUCKING GO" when secure)

The engineer reads this file with HIGHEST PRIORITY on the next `/implement {sprint}` invocation, addresses ALL CRITICAL and HIGH security issues, and generates an updated report with security fixes documented.

---

## Structured Agentic Memory

Agents maintain persistent working memory in `grimoires/loa/NOTES.md`:

### Memory Structure

```markdown
## Active Sub-Goals
<!-- Current objectives being pursued -->

## Discovered Technical Debt
<!-- Issues found during implementation that need future attention -->

## Blockers & Dependencies
<!-- External factors affecting progress -->

## Session Continuity
<!-- Key context to restore on next session -->
| Timestamp | Agent | Summary |

## Decision Log
<!-- Major decisions with rationale -->
```

### Agent Protocol

1. **Session Start**: Read NOTES.md to restore context
2. **During Execution**: Log significant decisions with rationale
3. **Before Compaction/End**: Summarize session insights
4. **Tool Result Clearing**: Apply semantic memory decay after heavy operations

See `.claude/protocols/structured-memory.md` for detailed protocol.

---

## Trajectory Evaluation (ADK-Level)

Agents log reasoning to `grimoires/loa/a2a/trajectory/{agent}-{date}.jsonl`:

### Log Format

```json
{"timestamp": "...", "agent": "...", "action": "...", "reasoning": "...", "grounding": {...}}
```

### Grounding Types

- `citation`: Direct quote from docs
- `code_reference`: Reference to existing code
- `assumption`: Ungrounded claim (must flag)
- `user_input`: Based on user request

### Evaluation-Driven Development (EDD)

- **Minimum 3 test scenarios** before marking a task complete
- **Factual grounding**: All claims must cite sources or be flagged as `[ASSUMPTION]`
- **Trajectory audit**: Reasoning logs are auditable for hallucination detection

See `.claude/protocols/trajectory-evaluation.md` for detailed protocol.

---

## Best Practices

### For All Phases

1. **Answer Thoroughly**: Agents ask questions for a reason
2. **Clarify Early**: If unclear, ask agents to rephrase
3. **Review Outputs**: Always review generated documents
4. **Iterate Freely**: Use the feedback loop for improvement

### For Implementation

- **Provide Clear Feedback**: Be specific in feedback files
- **Use File References**: Include file paths and line numbers
- **Explain Why**: Don't just say "fix this"—explain reasoning
- **Test Before Approving**: Run verification steps from report

### For DevOps & Infrastructure

- Security first—never compromise on fundamentals
- Automate everything that can be automated
- Design for failure—everything will eventually fail
- Monitor before deploying—can't fix what you can't see
- Document runbooks and incident response procedures

### Context Hygiene (v0.19.0)

Efficient context loading prevents token waste and maintains focus:

#### Loading Priority

| Priority | File/Type | When to Load | How |
|----------|-----------|--------------|-----|
| 1 | NOTES.md | Always at session start | Full read |
| 2 | Current sprint files | When implementing/reviewing | Full read |
| 3 | PRD/SDD | When needing requirements/architecture | Targeted search |
| 4 | Source code | When implementing specific feature | JIT retrieval |
| 5 | Test files | When writing/reviewing tests | JIT retrieval |

#### What to Grep vs What to Skim

**Use Grep For:**
- Finding specific function/class definitions
- Locating error messages or constants
- Finding all usages of a symbol
- Checking for patterns across files

**Use Skim (Read) For:**
- Understanding file structure and flow
- Reviewing code architecture
- Getting context around a function
- Initial codebase orientation

#### When to Request File Tree

**Do Request Tree:**
- First time exploring a directory
- When looking for test file locations
- When understanding module organization
- Before major refactoring

**Don't Request Tree:**
- When you already know the file path
- For small directories you've seen before
- When a single grep would suffice

#### Context Budget Awareness

Monitor context usage to maintain efficiency:

| Zone | Status | Action |
|------|--------|--------|
| Green (<5000 tokens active) | Healthy | Continue normally |
| Yellow (5000-10000 tokens) | Warning | Consider summarizing, clear tool results |
| Red (>10000 tokens) | Critical | Run checkpoint, archive to NOTES.md |

#### Tool Result Clearing

After heavy operations (large grep, API calls, file reads):

1. **Extract**: Pull key information into structured notes
2. **Summarize**: Replace raw output with one-line summary
3. **Clear**: Let raw data decay from active context

Example:
```
# Before: 500 tokens of grep output
# After: 30 tokens
"Found 47 AuthService refs across 12 files. Key locations: src/auth/service.ts:45, src/api/routes.ts:123"
```

### Long-Running Task Guidance (v0.19.0)

For tasks that span multiple sessions or involve many files:

#### Session Handoff Protocol

Before ending a session with incomplete work:

1. **Update NOTES.md**:
   - Current Focus section with exact state
   - List of completed vs remaining items
   - Any blockers or decisions needed

2. **Create Checkpoint**:
   ```markdown
   ## Session Continuity

   ### Last Working State
   - Task: Implementing auth middleware
   - Progress: 3/5 subtasks complete
   - Current file: src/auth/middleware.ts:67
   - Next action: Add rate limiting logic

   ### Blocked By
   - [ ] Need decision on rate limit values

   ### Files Modified This Session
   - src/auth/middleware.ts (new)
   - src/auth/index.ts (updated exports)
   - tests/auth/middleware.test.ts (partial)
   ```

3. **Commit Partial Work**:
   - Commit with `WIP:` prefix
   - Or stash with descriptive message

#### Multi-File Refactoring

When touching many files:

1. **Plan First**: List all files that will change
2. **Group Changes**: Batch related changes together
3. **Test Incrementally**: Run tests after each batch
4. **Track Progress**: Check off files in NOTES.md

Example tracking:
```markdown
## Refactor: AuthService → AuthModule

- [x] src/auth/service.ts → src/auth/module/index.ts
- [x] src/auth/types.ts → src/auth/module/types.ts
- [ ] src/api/routes.ts (update imports)
- [ ] src/middleware/auth.ts (update imports)
- [ ] tests/auth/*.test.ts (update imports)
```

#### Avoiding Context Exhaustion

For tasks >2 hours estimated:

1. **Break into subtasks** with clear boundaries
2. **Complete subtask fully** before starting next
3. **Run tests after each subtask** (verification loop)
4. **Update NOTES.md after each subtask**
5. **Consider parallel agents** for independent subtasks

#### Recovery After Interruption

When resuming interrupted work:

1. Read NOTES.md Session Continuity section
2. Check git status for uncommitted changes
3. Run `br ready` if using beads_rust
4. Verify last test run status
5. Resume from documented checkpoint

---

## Example Workflow

```bash
# 1. Define product requirements (no setup required!)
/plan-and-analyze
# → Answer discovery questions
# → Review grimoires/loa/prd.md
# → Creates ledger.json with first cycle (Sprint Ledger)

# 2. Design architecture
/architect
# → Answer technical questions
# → Review grimoires/loa/sdd.md

# 3. Plan sprints
/sprint-plan
# → Clarify capacity and priorities
# → Review grimoires/loa/sprint.md
# → Registers sprints in ledger with global IDs

# 4. Implement Sprint 1
/implement sprint-1
# → Agent implements tasks
# → Review grimoires/loa/a2a/sprint-1/reviewer.md

# 5. Review Sprint 1
/review-sprint sprint-1
# → Either approves or requests changes

# 6. Address code review feedback (if needed)
/implement sprint-1
# → Agent fixes issues
# → Re-review until "All good"

# 7. Security audit Sprint 1 (after approval)
/audit-sprint sprint-1
# → Either "APPROVED - LETS FUCKING GO" or "CHANGES_REQUIRED"

# 8. Address security feedback (if needed)
/implement sprint-1
# → Fix security issues
# → Re-audit until approved

# 9. Continue with remaining sprints...
# → Each sprint goes through: implement → review → audit → approve

# 10. Full codebase security audit (before production)
/audit
# → Fix any critical issues

# 11. Deploy to production
/deploy-production
# → Production infrastructure deployed

# 12. Submit feedback (THJ only, optional but encouraged)
/feedback
# → Answer 4 survey questions
# → Feedback + analytics posted to Linear
# → OSS users: Open GitHub issue instead

# 13. Get framework updates (periodically)
/update-loa
# → Pull latest Loa improvements
# → Review CHANGELOG.md for new features

# ─────────────────────────────────────────────────────────
# STARTING A NEW DEVELOPMENT CYCLE (after MVP complete)
# ─────────────────────────────────────────────────────────

# 14. Archive completed cycle
/archive-cycle "MVP Complete"
# → Creates snapshot in grimoires/loa/archive/
# → Preserves all sprint artifacts
# → Clears active cycle in ledger

# 15. Start fresh with new requirements
/plan-and-analyze
# → Creates new cycle in ledger
# → Sprint numbering continues (sprint-1 → global sprint-4, etc.)
# → Repeat workflow from step 2...
```

---

## Related Documentation

- **[README.md](README.md)** - Quick start guide
- **[INSTALLATION.md](INSTALLATION.md)** - Detailed installation and update guide
- **[CLAUDE.md](CLAUDE.md)** - Guidance for Claude Code instances

### Protocol Files

Detailed specifications for complex behaviors:

**Core Protocols**:
- `.claude/protocols/git-safety.md` - Template detection, warning flow, remediation steps
- `.claude/protocols/analytics.md` - THJ-only usage tracking, schema definitions
- `.claude/protocols/feedback-loops.md` - A2A communication, approval markers, flow diagrams
- `.claude/protocols/change-validation.md` - Pre-implementation validation protocol
- `.claude/protocols/structured-memory.md` - NOTES.md protocol, tool result clearing
- `.claude/protocols/trajectory-evaluation.md` - ADK-style evaluation, EDD

**v0.9.0 Lossless Ledger Protocols**:
- `.claude/protocols/session-continuity.md` - Session lifecycle, tiered recovery
- `.claude/protocols/grounding-enforcement.md` - Citation requirements (≥0.95 ratio)
- `.claude/protocols/synthesis-checkpoint.md` - Pre-`/clear` validation (7 steps)
- `.claude/protocols/attention-budget.md` - Token thresholds (Green/Yellow/Red)
- `.claude/protocols/jit-retrieval.md` - Lightweight identifiers (97% token reduction)

### Helper Scripts

Bash utilities for deterministic operations:

**Core Scripts**:
- `.claude/scripts/mount-loa.sh` - One-command install onto existing repo
- `.claude/scripts/update.sh` - Framework updates with migration gates
- `.claude/scripts/check-loa.sh` - CI validation script (integrity, schema, zones)
- `.claude/scripts/detect-drift.sh` - Code vs documentation drift detection
- `.claude/scripts/validate-change-plan.sh` - Pre-implementation change validation
- `.claude/scripts/analytics.sh` - Analytics helper functions
- `.claude/scripts/git-safety.sh` - Template detection functions
- `.claude/scripts/context-check.sh` - Context size assessment for parallel execution
- `.claude/scripts/preflight.sh` - Pre-flight validation functions

**v0.9.0 Lossless Ledger Scripts**:
- `.claude/scripts/grounding-check.sh` - Calculate grounding ratio for citations
- `.claude/scripts/synthesis-checkpoint.sh` - Run pre-`/clear` validation (7 steps)
- `.claude/scripts/self-heal-state.sh` - State Zone recovery from git history
- `.claude/scripts/validate-prd-requirements.sh` - UAT validation against PRD

---

## Tips for Success

1. **Trust the Process**: Each phase builds on the previous—don't skip steps
2. **Be Patient**: Thorough discovery prevents costly mistakes later
3. **Engage Actively**: Agents need your input for good decisions
4. **Review Everything**: You're the final decision-maker
5. **Use Feedback Loop**: The implementation cycle is your quality gate
6. **Security First**: Especially for crypto/blockchain—never compromise

---

**Remember**: This process is designed to be thorough and iterative. Quality takes time, and each phase ensures you're building the right thing, the right way. Embrace the process, engage with the agents, and leverage their expertise to build exceptional products.
