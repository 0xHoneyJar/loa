# Development Process

This document outlines the comprehensive agent-driven development workflow. Our process leverages specialized AI agents to guide you from initial concept to production-ready implementation.

> **Note**: This is a base framework repository that THJ uses for development of our products. If you are not a part of THJ, when using as a template for a new project, uncomment the generated artifacts section in `.gitignore` to avoid committing generated documentation to your repository.

## Protocol References

Detailed specifications are maintained in separate protocol files:

- **Git Safety**: `.claude/protocols/git-safety.md` - Template detection, warning flow, remediation
- **Analytics**: `.claude/protocols/analytics.md` - THJ-only usage tracking, schema, helper functions
- **Feedback Loops**: `.claude/protocols/feedback-loops.md` - A2A communication, approval markers

## Table of Contents

- [Overview](#overview)
- [Agents](#agents)
- [Workflow](#workflow)
- [Custom Commands](#custom-commands)
- [Document Artifacts](#document-artifacts)
- [Agent-to-Agent Communication](#agent-to-agent-communication)
- [Best Practices](#best-practices)

---

## Overview

Our development process follows a structured, eight-phase approach:

0. **Phase 0: Setup** → Initial configuration and analytics initialization
1. **Phase 1: Planning** → Product Requirements Document (PRD)
2. **Phase 2: Architecture** → Software Design Document (SDD)
3. **Phase 3: Sprint Planning** → Sprint Plan
4. **Phase 4: Implementation** → Production Code with Feedback Loop
5. **Phase 5: Review** → Quality Validation and Sprint Approval
6. **Phase 5.5: Sprint Security Audit** → Security Review and Approval
7. **Phase 6: Deployment** → Production Infrastructure and Handover
8. **Post-Deployment: Feedback** → Developer experience survey

Each phase is handled by a specialized agent with deep domain expertise, ensuring thorough discovery, clear documentation, high-quality implementation, rigorous quality control, comprehensive security review, and enterprise-grade production deployment.

> **For production deployment**, use the `/deploy-production` command which generates deployment documentation in `loa-grimoire/deployment/`.

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
- **Output**: `loa-grimoire/prd.md`

### 2. **designing-architecture** (Software Architect)
- **Role**: Senior Software Architect with deep technical expertise
- **Expertise**: System design, technology selection, scalability, security
- **Skill**: `.claude/skills/designing-architecture/`
- **Responsibilities**:
  - Review PRD and design system architecture
  - Define component structure and technical stack
  - Clarify uncertainties with concrete proposals
  - Make informed architectural decisions
- **Output**: `loa-grimoire/sdd.md`

### 3. **planning-sprints** (Technical Product Manager)
- **Role**: Technical PM with engineering and product expertise
- **Expertise**: Sprint planning, task breakdown, team coordination
- **Skill**: `.claude/skills/planning-sprints/`
- **Responsibilities**:
  - Review PRD and SDD for comprehensive context
  - Break down work into actionable sprint tasks
  - Define acceptance criteria and priorities
  - Sequence tasks based on dependencies
- **Output**: `loa-grimoire/sprint.md`

### 4. **implementing-tasks** (Senior Engineer)
- **Role**: Elite Software Engineer with 15 years of experience
- **Expertise**: Production-grade code, testing, documentation
- **Skill**: `.claude/skills/implementing-tasks/`
- **Responsibilities**:
  - Implement sprint tasks with tests and documentation
  - Address feedback from senior technical lead
  - Iterate until sprint is approved
  - Generate detailed implementation reports
- **Output**: Production code + `loa-grimoire/a2a/reviewer.md`

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
- **Output**: `loa-grimoire/a2a/engineer-feedback.md`, updated `loa-grimoire/sprint.md`

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
- **Output**: `loa-grimoire/deployment/` with infrastructure code and operational docs

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
  - Sprint audit: `loa-grimoire/a2a/auditor-sprint-feedback.md` (per-sprint security review)
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

### Phase 0: Setup (`/setup`)

<!-- CANONICAL_LOCATION: protocols/analytics.md -->

**Goal**: Configure Loa for first-time use with user-appropriate experience

**User Type Detection**:
The setup command asks "Are you a THJ team member?" to determine the appropriate pathway:

#### **THJ Developers** (Internal Team)
Full-featured experience with analytics and MCP integrations:

1. **Welcome & Analytics Notice**:
   - Displays Loa's purpose and workflow overview
   - Explains what analytics are collected and where they're stored
   - Confirms local-only storage with opt-in sharing via `/feedback`

2. **MCP Server Configuration** (Multichoice):
   - Offers selection of MCP servers: Linear, GitHub, Vercel, Discord, web3-stats, All, Skip
   - For each selected MCP, provides:
     - **Guided setup**: Step-by-step configuration instructions
     - **Documentation link**: External setup guide

3. **Project Initialization**:
   - Extracts project name from `git remote get-url origin`
   - Gets developer info from `git config user.name/email`
   - Creates `loa-grimoire/analytics/usage.json` with initial data
   - Creates `.loa-setup-complete` marker file with `user_type: "thj"`

4. **Configuration Summary**:
   - Lists all MCPs and their status
   - Shows initialized analytics location
   - Provides next steps (run `/plan-and-analyze`)

#### **OSS Users** (Open Source Community)
Streamlined experience without analytics:

1. **Welcome**:
   - Displays Loa's purpose and workflow overview
   - Points to documentation and community resources

2. **Marker File Creation**:
   - Creates `.loa-setup-complete` with `user_type: "oss"`
   - No analytics initialization
   - No MCP configuration prompts

3. **Next Steps**:
   - Provides quick start guide
   - Points to GitHub issues for support

**Command**:
```bash
/setup
```

**Outputs**:
- `.loa-setup-complete` marker file (includes `user_type` field)
- `loa-grimoire/analytics/usage.json` (THJ only)
- `loa-grimoire/analytics/summary.md` (THJ only)

**Setup Enforcement**:
- `/plan-and-analyze` checks for `.loa-setup-complete`
- If missing, prompts user to run `/setup` first
- Ensures consistent onboarding experience

---

### Post-Setup: MCP Configuration (`/config`) - THJ Only

**Goal**: Reconfigure MCP server integrations after initial setup

**Availability**: THJ developers only (checks `user_type` in `.loa-setup-complete`)

**Process**:
1. **User Type Verification**:
   - Reads `.loa-setup-complete` and checks `user_type`
   - If OSS user: Displays error and stops

2. **Current Configuration Display**:
   - Shows currently configured MCP servers
   - Indicates which servers are active

3. **MCP Multichoice Selection**:
   - Linear, GitHub, Vercel, Discord, web3-stats, All, Skip
   - Provides guided setup or documentation for selected servers

4. **Update Marker File**:
   - Updates `.loa-setup-complete` with new MCP configuration

**Command**:
```bash
/config
```

**Output**: Updated `.loa-setup-complete` with new MCP configuration

---

### Phase 1: Planning (`/plan-and-analyze`)

**Agent**: `discovering-requirements`

**Goal**: Define goals, requirements, scope, and create PRD

**Context-First Discovery**: If `loa-grimoire/context/` contains documentation, the agent reads it first, presents understanding with citations, and only asks questions about gaps. More context = fewer questions.

**Process**:
1. Agent scans `loa-grimoire/context/` for existing documentation
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
6. Saves PRD with source tracing to `loa-grimoire/prd.md`

**Command**:
```bash
/plan-and-analyze
```

**Output**: `loa-grimoire/prd.md`

---

### Phase 2: Architecture (`/architect`)

**Agent**: `designing-architecture`

**Goal**: Design system architecture and create SDD

**Process**:
1. Carefully reviews `loa-grimoire/prd.md` in its entirety
2. Designs system architecture, components, data models, APIs
3. For any uncertainties or ambiguous decisions:
   - Asks specific clarifying questions
   - Presents 2-3 concrete proposals with pros/cons
   - Explains technical tradeoffs
   - Waits for your decision
4. Validates all assumptions
5. Only generates SDD when completely confident (no doubts)
6. Saves comprehensive SDD to `loa-grimoire/sdd.md`

**Command**:
```bash
/architect
```

**Output**: `loa-grimoire/sdd.md`

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
1. Reviews both `loa-grimoire/prd.md` and `loa-grimoire/sdd.md` thoroughly
2. Analyzes requirements and architecture
3. Plans sprint breakdown and task sequencing
4. For any uncertainties:
   - Asks about team capacity, sprint duration, priorities
   - Presents proposals for sprint structure
   - Clarifies MVP scope and dependencies
   - Waits for your decisions
5. Only generates sprint plan when confident
6. Saves comprehensive sprint plan to `loa-grimoire/sprint.md`

**Command**:
```bash
/sprint-plan
```

**Output**: `loa-grimoire/sprint.md`

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
1. **Check for Feedback**: Looks for `loa-grimoire/a2a/engineer-feedback.md` (won't exist on first run)
2. **Review Documentation**: Reads all `loa-grimoire/*` for context (PRD, SDD, sprint plan)
3. **Implement Tasks**:
   - Production-quality code
   - Comprehensive unit tests
   - Follow project conventions
   - Handle edge cases and errors
4. **Generate Report**: Saves detailed report to `loa-grimoire/a2a/reviewer.md`

#### **Cycle 2+: Feedback Iteration**
1. **Read Feedback**: Senior technical lead creates `loa-grimoire/a2a/engineer-feedback.md`
2. **Clarify if Needed**: Agent asks questions if feedback is unclear
3. **Fix Issues**: Address all feedback items systematically
4. **Update Report**: Generate new report at `loa-grimoire/a2a/reviewer.md`
5. **Repeat**: Cycle continues until approved

**Command**:
```bash
# First implementation
/implement sprint-1

# After receiving feedback (repeat as needed)
/implement sprint-1
```

**Outputs**:
- Production code with tests
- `loa-grimoire/a2a/reviewer.md` (implementation report)

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
   - Reads `loa-grimoire/prd.md` for product requirements
   - Reads `loa-grimoire/sdd.md` for architecture and design
   - Reads `loa-grimoire/sprint.md` for tasks and acceptance criteria
   - Reads `loa-grimoire/a2a/reviewer.md` for engineer's implementation report
   - Reads `loa-grimoire/a2a/engineer-feedback.md` for previous feedback (if exists)

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
   - Writes "All good" to `loa-grimoire/a2a/engineer-feedback.md`
   - Updates `loa-grimoire/sprint.md` with ✅ for completed tasks
   - Marks sprint as "COMPLETED"
   - Informs you to move to next sprint

   **Option B - Request Changes**:
   - Issues found (bugs, security, quality, incomplete tasks)
   - Previous feedback not addressed

   **Actions**:
   - Writes detailed feedback to `loa-grimoire/a2a/engineer-feedback.md`
   - Does NOT update sprint completion status
   - Provides specific, actionable feedback with file paths and line numbers
   - Informs you that changes are required

**Command**:
```bash
/review-sprint
```

**Outputs**:
- `loa-grimoire/a2a/engineer-feedback.md` (approval or feedback)
- Updated `loa-grimoire/sprint.md` (if approved)

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
- ✅ Sprint must be approved by senior tech lead ("All good" in `loa-grimoire/a2a/engineer-feedback.md`)

**Process**:

#### **Security Audit Workflow**
1. **Context Gathering**:
   - Reads `loa-grimoire/prd.md` for product requirements
   - Reads `loa-grimoire/sdd.md` for architecture and security requirements
   - Reads `loa-grimoire/sprint.md` for sprint tasks and scope
   - Reads `loa-grimoire/a2a/reviewer.md` for implementation details

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
   - Checks if `loa-grimoire/a2a/auditor-sprint-feedback.md` exists from previous audit
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
   - Writes "APPROVED - LETS FUCKING GO" to `loa-grimoire/a2a/auditor-sprint-feedback.md`
   - Confirms sprint is ready for next sprint or deployment
   - User can proceed to next sprint or Phase 6 (Deployment)

   **Option B - Request Security Changes**:
   - CRITICAL or HIGH security issues found
   - Previous security feedback not fully addressed
   - Security best practices violated

   **Actions**:
   - Writes "CHANGES_REQUIRED" with detailed security feedback to `loa-grimoire/a2a/auditor-sprint-feedback.md`
   - Provides specific security issues with:
     - Severity level (CRITICAL/HIGH/MEDIUM/LOW)
     - Affected files and line numbers
     - Vulnerability description
     - Security impact and exploit scenario
     - Specific remediation steps
   - User must run `/implement sprint-X` to address security issues

**Command**:
```bash
/audit-sprint
```

**Outputs**:
- `loa-grimoire/a2a/auditor-sprint-feedback.md` (security approval or detailed feedback)

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
   - Agent reads `loa-grimoire/a2a/auditor-sprint-feedback.md` FIRST (highest priority)
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
- Sprint planner checks `loa-grimoire/a2a/auditor-sprint-feedback.md` FIRST
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
   Creates comprehensive docs in `loa-grimoire/deployment/`:
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
- Comprehensive documentation (`loa-grimoire/deployment/`)

---

### Post-Deployment: Developer Feedback (`/feedback`) - THJ Only

**Goal**: Collect developer experience feedback and submit to Linear

**Availability**: THJ developers only (checks `user_type` in `.loa-setup-complete`)

**When to Use**:
- After completing a deployment
- After significant time using Loa
- When suggested by `/deploy-production`

**Process**:

1. **User Type Verification**:
   - Reads `.loa-setup-complete` and checks `user_type`
   - If OSS user: Displays error with GitHub issues link and stops

2. **Check for Pending Feedback**:
   - Looks for `loa-grimoire/analytics/pending-feedback.json`
   - If found, offers to submit pending feedback first

3. **Survey (4 Questions)**:
   - **Q1** (1/4): "What's one thing you would change about Loa?" (free text)
   - **Q2** (2/4): "What's one thing you loved about using Loa?" (free text)
   - **Q3** (3/4): "How would you rate this experience vs other approaches?" (1-5 scale)
   - **Q4** (4/4): "How comfortable are you with the agent-driven process?" (A-E choice)

4. **Prepare Submission**:
   - Loads analytics from `loa-grimoire/analytics/usage.json`
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

### Maintenance: Framework Updates (`/update`)

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
/update
```

**Merge Strategy**:
| File Location | Behavior |
|---------------|----------|
| `.claude/skills/` | Updated to latest Loa versions |
| `.claude/commands/` | Updated to latest Loa versions |
| `app/` | Preserved (your code) |
| `loa-grimoire/prd.md` | Preserved (your docs) |
| `loa-grimoire/analytics/` | Preserved (your data) |

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
/translate @loa-grimoire/sdd.md for executives
/translate @loa-grimoire/sprint.md for marketing team
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
| `/setup` | First-time configuration | wizard | `.loa-setup-complete`, analytics | All users |
| `/config` | Reconfigure MCP servers | wizard | Updated `.loa-setup-complete` | THJ only |
| `/plan-and-analyze` | Define requirements and create PRD | `discovering-requirements` | `loa-grimoire/prd.md` | All users |
| `/architect` | Design system architecture | `designing-architecture` | `loa-grimoire/sdd.md` | All users |
| `/sprint-plan` | Plan implementation sprints | `planning-sprints` | `loa-grimoire/sprint.md` | All users |
| `/implement {sprint}` | Implement sprint tasks | `implementing-tasks` | Code + `loa-grimoire/a2a/reviewer.md` | All users |
| `/review-sprint {sprint}` | Review and approve/reject implementation | `reviewing-code` | `loa-grimoire/a2a/engineer-feedback.md` | All users |
| `/audit-sprint {sprint}` | Security audit of sprint implementation | `auditing-security` | `loa-grimoire/a2a/auditor-sprint-feedback.md` | All users |
| `/deploy-production` | Deploy to production | `deploying-infrastructure` | `loa-grimoire/deployment/` | All users |
| `/feedback` | Submit developer experience feedback | survey | Linear issue in "Loa Feedback" | THJ only |
| `/update` | Pull framework updates from upstream | git | Merged updates | All users |
| `/contribute` | Create OSS contribution PR | git | GitHub PR | All users |
| `/audit` | Security audit (ad-hoc) | `auditing-security` | `SECURITY-AUDIT-REPORT.md` | All users |
| `/audit-deployment` | Deployment infrastructure audit (ad-hoc) | `auditing-security` | `loa-grimoire/a2a/deployment-feedback.md` | All users |
| `/translate @doc for [audience]` | Executive translation (ad-hoc) | `translating-for-executives` | Executive summaries | All users |

**User Type Notes**:
- **THJ only**: Commands restricted to THJ team members (requires `user_type: "thj"` in `.loa-setup-complete`)
- **All users**: Available to both THJ developers and OSS users
- Analytics updates in phase commands are automatically skipped for OSS users

> **For deployment procedures**, use `/deploy-production` which generates comprehensive runbooks in `loa-grimoire/deployment/runbooks/`.

---

## Document Artifacts

### Primary Documents

| Document | Path | Created By | Purpose |
|----------|------|------------|---------|
| **PRD** | `loa-grimoire/prd.md` | `discovering-requirements` | Product requirements and business context |
| **SDD** | `loa-grimoire/sdd.md` | `designing-architecture` | System design and technical architecture |
| **Sprint Plan** | `loa-grimoire/sprint.md` | `planning-sprints` | Sprint tasks with acceptance criteria |
| **Security Audit** | `SECURITY-AUDIT-REPORT.md` | `auditing-security` | Security vulnerabilities and remediation |

### Agent-to-Agent (A2A) Communication

| Document | Path | Created By | Purpose |
|----------|------|------------|---------|
| **Implementation Report** | `loa-grimoire/a2a/reviewer.md` | `implementing-tasks` | Report for senior lead review |
| **Code Review Feedback** | `loa-grimoire/a2a/engineer-feedback.md` | `reviewing-code` | Code review feedback for engineer |
| **Security Audit Feedback** | `loa-grimoire/a2a/auditor-sprint-feedback.md` | `auditing-security` | Security feedback for engineer |

### Deployment Documentation

| Document | Path | Created By | Purpose |
|----------|------|------------|---------|
| **Infrastructure Overview** | `loa-grimoire/deployment/infrastructure.md` | `deploying-infrastructure` | Architecture, resources, costs |
| **Deployment Guide** | `loa-grimoire/deployment/deployment-guide.md` | `deploying-infrastructure` | Deploy, rollback, migrations |
| **Monitoring Guide** | `loa-grimoire/deployment/monitoring.md` | `deploying-infrastructure` | Dashboards, metrics, alerts |
| **Security Guide** | `loa-grimoire/deployment/security.md` | `deploying-infrastructure` | Access, secrets, compliance |
| **Disaster Recovery** | `loa-grimoire/deployment/disaster-recovery.md` | `deploying-infrastructure` | Backup, restore, failover |
| **Runbooks** | `loa-grimoire/deployment/runbooks/*.md` | `deploying-infrastructure` | Operational procedures |

---

## Agent-to-Agent Communication

<!-- CANONICAL_LOCATION: protocols/feedback-loops.md -->

The framework uses three feedback loops for quality assurance:

### 1. Implementation Feedback Loop (Phases 4-5)

#### **Engineer → Senior Lead** (`loa-grimoire/a2a/reviewer.md`)

The engineer generates a comprehensive report after implementation:
- What was accomplished
- Files created/modified
- Test coverage
- Technical decisions
- Verification steps
- Feedback addressed (if revision)

#### **Senior Lead → Engineer** (`loa-grimoire/a2a/engineer-feedback.md`)

The senior technical lead reviews and provides feedback:
- Issues found
- Required changes
- Clarifications needed
- Quality concerns
- Approval status ("All good" when approved)

The engineer reads this file on the next `/implement {sprint}` invocation, clarifies anything unclear, fixes all issues, and generates an updated report.

### 2. Sprint Security Feedback Loop (Phase 5.5)

#### **Engineer → Security Auditor** (`loa-grimoire/a2a/reviewer.md` + implemented code)

After senior lead approval, the security auditor reviews:
- Implementation report context
- Actual code files (security-focused review)
- Security requirements from PRD/SDD

#### **Security Auditor → Engineer** (`loa-grimoire/a2a/auditor-sprint-feedback.md`)

The security auditor provides security-focused feedback:
- Security vulnerabilities (CRITICAL/HIGH/MEDIUM/LOW)
- Affected files with line numbers
- Exploit scenarios and security impact
- Specific remediation guidance
- Approval status ("APPROVED - LETS FUCKING GO" when secure)

The engineer reads this file with HIGHEST PRIORITY on the next `/implement {sprint}` invocation, addresses ALL CRITICAL and HIGH security issues, and generates an updated report with security fixes documented.

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

---

## Example Workflow

```bash
# 0. First-time setup (once per project)
/setup
# → Asks if you're a THJ team member
# → THJ: Configure MCP servers, initialize analytics
# → OSS: Quick welcome, documentation pointers
# → Creates .loa-setup-complete marker with user_type

# 0.5. Reconfigure MCP servers (THJ only, optional)
/config
# → Shows current MCP configuration
# → Offers multichoice selection for new MCPs

# 1. Define product requirements
/plan-and-analyze
# → Answer discovery questions
# → Review loa-grimoire/prd.md

# 2. Design architecture
/architect
# → Answer technical questions
# → Review loa-grimoire/sdd.md

# 3. Plan sprints
/sprint-plan
# → Clarify capacity and priorities
# → Review loa-grimoire/sprint.md

# 4. Implement Sprint 1
/implement sprint-1
# → Agent implements tasks
# → Review loa-grimoire/a2a/reviewer.md

# 5. Review Sprint 1
/review-sprint
# → Either approves or requests changes

# 6. Address code review feedback (if needed)
/implement sprint-1
# → Agent fixes issues
# → Re-review until "All good"

# 7. Security audit Sprint 1 (after approval)
/audit-sprint
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
/update
# → Pull latest Loa improvements
# → Review CHANGELOG.md for new features
```

---

## Related Documentation

- **[README.md](README.md)** - Quick start guide
- **[CLAUDE.md](CLAUDE.md)** - Guidance for Claude Code instances

### Protocol Files

Detailed specifications for complex behaviors:

- `.claude/protocols/git-safety.md` - Template detection, warning flow, remediation steps
- `.claude/protocols/analytics.md` - THJ-only usage tracking, schema definitions
- `.claude/protocols/feedback-loops.md` - A2A communication, approval markers, flow diagrams

### Helper Scripts

Bash utilities for deterministic operations:

- `.claude/scripts/analytics.sh` - Analytics helper functions
- `.claude/scripts/git-safety.sh` - Template detection functions
- `.claude/scripts/context-check.sh` - Context size assessment for parallel execution
- `.claude/scripts/preflight.sh` - Pre-flight validation functions

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
