# Development Process

This document outlines the comprehensive agent-driven development workflow. Our process leverages specialized AI agents to guide you from initial concept to production-ready implementation.

> **Note**: This is a base framework repository. When using as a template for a new project, uncomment the generated artifacts section in `.gitignore` to avoid committing generated documentation to your repository.

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

Our development process follows a structured, six-phase approach:

1. **Phase 1: Planning** → Product Requirements Document (PRD)
2. **Phase 2: Architecture** → Software Design Document (SDD)
3. **Phase 3: Sprint Planning** → Sprint Plan
4. **Phase 4: Implementation** → Production Code with Feedback Loop
5. **Phase 5: Review** → Quality Validation and Sprint Approval
6. **Phase 6: Deployment** → Production Infrastructure and Handover

Each phase is handled by a specialized agent with deep domain expertise, ensuring thorough discovery, clear documentation, high-quality implementation, rigorous quality control, and enterprise-grade production deployment.

> **For organizational integration and server deployment**, see [DEPLOY-ORG-PROCESS.md](DEPLOY-ORG-PROCESS.md).

---

## Agents

### 1. **prd-architect** (Product Manager)
- **Role**: Senior Product Manager with 15 years of experience
- **Expertise**: Requirements gathering, product strategy, user research
- **Responsibilities**:
  - Guide structured discovery across 7 phases
  - Extract complete, unambiguous requirements
  - Create comprehensive Product Requirements Documents
- **Output**: `docs/prd.md`

### 2. **architecture-designer** (Software Architect)
- **Role**: Senior Software Architect with deep technical expertise
- **Expertise**: System design, technology selection, scalability, security
- **Responsibilities**:
  - Review PRD and design system architecture
  - Define component structure and technical stack
  - Clarify uncertainties with concrete proposals
  - Make informed architectural decisions
- **Output**: `docs/sdd.md`

### 3. **sprint-planner** (Technical Product Manager)
- **Role**: Technical PM with engineering and product expertise
- **Expertise**: Sprint planning, task breakdown, team coordination
- **Responsibilities**:
  - Review PRD and SDD for comprehensive context
  - Break down work into actionable sprint tasks
  - Define acceptance criteria and priorities
  - Sequence tasks based on dependencies
- **Output**: `docs/sprint.md`

### 4. **sprint-task-implementer** (Senior Engineer)
- **Role**: Elite Software Engineer with 15 years of experience
- **Expertise**: Production-grade code, testing, documentation
- **Responsibilities**:
  - Implement sprint tasks with tests and documentation
  - Address feedback from senior technical lead
  - Iterate until sprint is approved
  - Generate detailed implementation reports
- **Output**: Production code + `docs/a2a/reviewer.md`

### 5. **senior-tech-lead-reviewer** (Senior Technical Lead)
- **Role**: Senior Technical Lead with 15+ years of experience
- **Expertise**: Code review, quality assurance, security auditing, technical leadership
- **Responsibilities**:
  - Review sprint implementation for completeness and quality
  - Validate all acceptance criteria are met
  - Check code quality, testing, security, performance
  - Verify previous feedback was addressed
  - Provide detailed, actionable feedback to engineers
  - Update sprint progress and approve completed sprints
- **Output**: `docs/a2a/engineer-feedback.md`, updated `docs/sprint.md`

### 6. **devops-crypto-architect** (DevOps Architect)
- **Role**: Battle-tested DevOps Architect with 15 years of crypto/blockchain infrastructure experience
- **Expertise**: Infrastructure as code, CI/CD, security, monitoring, blockchain operations
- **Responsibilities**:
  - Design production infrastructure (cloud, Kubernetes, blockchain nodes)
  - Implement infrastructure as code
  - Create CI/CD pipelines
  - Set up monitoring, alerting, and observability
  - Implement security hardening and secrets management
  - Generate handover documentation and runbooks
- **Output**: `docs/deployment/` with infrastructure code and operational docs

### 7. **paranoid-auditor** (Security Auditor)
- **Role**: Paranoid Cypherpunk Security Auditor with 30+ years of experience
- **Expertise**: OWASP Top 10, cryptographic implementation, secrets management, penetration testing
- **Responsibilities**:
  - Perform comprehensive security and quality audits
  - Identify vulnerabilities across OWASP Top 10 categories
  - Review cryptographic implementations and key management
  - Audit authentication, authorization, and access controls
  - Provide prioritized remediation guidance
- **Output**: `SECURITY-AUDIT-REPORT.md` with findings and remediation steps
- **Usage**: Ad-hoc, invoked before production, after major changes, or periodically

### 8. **devrel-translator** (Developer Relations Professional)
- **Role**: Elite Developer Relations Professional with 15 years of experience
- **Expertise**: Technical communication, executive summaries, stakeholder management
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

**Agent**: `prd-architect`

**Goal**: Define goals, requirements, scope, and create PRD

**Process**:
1. Agent asks targeted questions across 7 discovery phases:
   - Problem & Vision
   - Goals & Success Metrics
   - User & Stakeholder Context
   - Functional Requirements
   - Technical & Non-Functional Requirements
   - Scope & Prioritization
   - Risks & Dependencies
2. Agent asks 2-3 questions at a time (never overwhelming)
3. Agent probes for specifics and challenges assumptions
4. Only generates PRD when all questions are answered
5. Saves comprehensive PRD to `docs/prd.md`

**Command**:
```bash
/plan-and-analyze
```

**Output**: `docs/prd.md`

---

### Phase 2: Architecture (`/architect`)

**Agent**: `architecture-designer`

**Goal**: Design system architecture and create SDD

**Process**:
1. Carefully reviews `docs/prd.md` in its entirety
2. Designs system architecture, components, data models, APIs
3. For any uncertainties or ambiguous decisions:
   - Asks specific clarifying questions
   - Presents 2-3 concrete proposals with pros/cons
   - Explains technical tradeoffs
   - Waits for your decision
4. Validates all assumptions
5. Only generates SDD when completely confident (no doubts)
6. Saves comprehensive SDD to `docs/sdd.md`

**Command**:
```bash
/architect
```

**Output**: `docs/sdd.md`

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

**Agent**: `sprint-planner`

**Goal**: Break down work into actionable sprint tasks

**Process**:
1. Reviews both `docs/prd.md` and `docs/sdd.md` thoroughly
2. Analyzes requirements and architecture
3. Plans sprint breakdown and task sequencing
4. For any uncertainties:
   - Asks about team capacity, sprint duration, priorities
   - Presents proposals for sprint structure
   - Clarifies MVP scope and dependencies
   - Waits for your decisions
5. Only generates sprint plan when confident
6. Saves comprehensive sprint plan to `docs/sprint.md`

**Command**:
```bash
/sprint-plan
```

**Output**: `docs/sprint.md`

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

**Agent**: `sprint-task-implementer`

**Goal**: Implement sprint tasks with feedback-driven iteration

**Process**:

#### **Cycle 1: Initial Implementation**
1. **Check for Feedback**: Looks for `docs/a2a/engineer-feedback.md` (won't exist on first run)
2. **Review Documentation**: Reads all `docs/*` for context (PRD, SDD, sprint plan)
3. **Implement Tasks**:
   - Production-quality code
   - Comprehensive unit tests
   - Follow project conventions
   - Handle edge cases and errors
4. **Generate Report**: Saves detailed report to `docs/a2a/reviewer.md`

#### **Cycle 2+: Feedback Iteration**
1. **Read Feedback**: Senior technical lead creates `docs/a2a/engineer-feedback.md`
2. **Clarify if Needed**: Agent asks questions if feedback is unclear
3. **Fix Issues**: Address all feedback items systematically
4. **Update Report**: Generate new report at `docs/a2a/reviewer.md`
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
- `docs/a2a/reviewer.md` (implementation report)

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

**Agent**: `senior-tech-lead-reviewer`

**Goal**: Validate sprint completeness, code quality, and approve or request changes

**Process**:

#### **Review Workflow**
1. **Context Gathering**:
   - Reads `docs/prd.md` for product requirements
   - Reads `docs/sdd.md` for architecture and design
   - Reads `docs/sprint.md` for tasks and acceptance criteria
   - Reads `docs/a2a/reviewer.md` for engineer's implementation report
   - Reads `docs/a2a/engineer-feedback.md` for previous feedback (if exists)

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
   - Writes "All good" to `docs/a2a/engineer-feedback.md`
   - Updates `docs/sprint.md` with ✅ for completed tasks
   - Marks sprint as "COMPLETED"
   - Informs you to move to next sprint

   **Option B - Request Changes**:
   - Issues found (bugs, security, quality, incomplete tasks)
   - Previous feedback not addressed

   **Actions**:
   - Writes detailed feedback to `docs/a2a/engineer-feedback.md`
   - Does NOT update sprint completion status
   - Provides specific, actionable feedback with file paths and line numbers
   - Informs you that changes are required

**Command**:
```bash
/review-sprint
```

**Outputs**:
- `docs/a2a/engineer-feedback.md` (approval or feedback)
- Updated `docs/sprint.md` (if approved)

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

### Phase 6: Deployment (`/deploy-production`)

**Agent**: `devops-crypto-architect`

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
   Creates comprehensive docs in `docs/deployment/`:
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
- Comprehensive documentation (`docs/deployment/`)

---

### Ad-Hoc: Security Audit (`/audit`)

**Agent**: `paranoid-auditor`

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

**Agent**: `devrel-translator`

**Goal**: Translate complex technical documentation into stakeholder-appropriate communications

**When to Use**:
- Before board meetings or investor updates
- When executives need to understand technical decisions
- To create marketing briefs from technical features
- For compliance or legal team briefings

**Command**:
```bash
/translate @SECURITY-AUDIT-REPORT.md for board of directors
/translate @docs/sdd.md for executives
/translate @docs/sprint.md for marketing team
```

**Output**: Executive summaries, stakeholder briefings (1-3 pages tailored by audience)

---

## Custom Commands

| Command | Purpose | Agent | Output |
|---------|---------|-------|--------|
| `/plan-and-analyze` | Define requirements and create PRD | `prd-architect` | `docs/prd.md` |
| `/architect` | Design system architecture | `architecture-designer` | `docs/sdd.md` |
| `/sprint-plan` | Plan implementation sprints | `sprint-planner` | `docs/sprint.md` |
| `/implement {sprint}` | Implement sprint tasks | `sprint-task-implementer` | Code + `docs/a2a/reviewer.md` |
| `/review-sprint` | Review and approve/reject implementation | `senior-tech-lead-reviewer` | `docs/a2a/engineer-feedback.md` |
| `/deploy-production` | Deploy to production | `devops-crypto-architect` | `docs/deployment/` |
| `/audit` | Security audit (ad-hoc) | `paranoid-auditor` | `SECURITY-AUDIT-REPORT.md` |
| `/translate @doc for [audience]` | Executive translation (ad-hoc) | `devrel-translator` | Executive summaries |

> **For organizational integration commands** (`/integrate-org-workflow`, `/implement-org-integration`, `/setup-server`, `/audit-deployment`, `/deploy-go`), see [DEPLOY-ORG-PROCESS.md](DEPLOY-ORG-PROCESS.md).

---

## Document Artifacts

### Primary Documents

| Document | Path | Created By | Purpose |
|----------|------|------------|---------|
| **PRD** | `docs/prd.md` | `prd-architect` | Product requirements and business context |
| **SDD** | `docs/sdd.md` | `architecture-designer` | System design and technical architecture |
| **Sprint Plan** | `docs/sprint.md` | `sprint-planner` | Sprint tasks with acceptance criteria |
| **Security Audit** | `SECURITY-AUDIT-REPORT.md` | `paranoid-auditor` | Security vulnerabilities and remediation |

### Agent-to-Agent (A2A) Communication

| Document | Path | Created By | Purpose |
|----------|------|------------|---------|
| **Implementation Report** | `docs/a2a/reviewer.md` | `sprint-task-implementer` | Report for senior lead review |
| **Feedback** | `docs/a2a/engineer-feedback.md` | `senior-tech-lead-reviewer` | Feedback for engineer |

### Deployment Documentation

| Document | Path | Created By | Purpose |
|----------|------|------------|---------|
| **Infrastructure Overview** | `docs/deployment/infrastructure.md` | `devops-crypto-architect` | Architecture, resources, costs |
| **Deployment Guide** | `docs/deployment/deployment-guide.md` | `devops-crypto-architect` | Deploy, rollback, migrations |
| **Monitoring Guide** | `docs/deployment/monitoring.md` | `devops-crypto-architect` | Dashboards, metrics, alerts |
| **Security Guide** | `docs/deployment/security.md` | `devops-crypto-architect` | Access, secrets, compliance |
| **Disaster Recovery** | `docs/deployment/disaster-recovery.md` | `devops-crypto-architect` | Backup, restore, failover |
| **Runbooks** | `docs/deployment/runbooks/*.md` | `devops-crypto-architect` | Operational procedures |

---

## Agent-to-Agent Communication

### Implementation Feedback Loop (Phases 4-5)

#### **Engineer → Senior Lead** (`docs/a2a/reviewer.md`)

The engineer generates a comprehensive report after implementation:
- What was accomplished
- Files created/modified
- Test coverage
- Technical decisions
- Verification steps
- Feedback addressed (if revision)

#### **Senior Lead → Engineer** (`docs/a2a/engineer-feedback.md`)

The senior technical lead reviews and provides feedback:
- Issues found
- Required changes
- Clarifications needed
- Quality concerns
- Approval status ("All good" when approved)

The engineer reads this file on the next `/implement {sprint}` invocation, clarifies anything unclear, fixes all issues, and generates an updated report.

---

## Multi-Developer Usage Warning

⚠️ **CRITICAL**: This framework is architected for **single-threaded workflows**. The agent system assumes one active development stream at a time.

### Why Multi-Developer Concurrent Usage Breaks

If multiple developers use `/implement` simultaneously:

1. **A2A File Collisions**: Reports overwritten before review
2. **Sprint Status Conflicts**: Merge conflicts on task completion
3. **Context Confusion**: Mixed implementation context
4. **Broken Feedback Loops**: Feedback intended for wrong engineer

### Solutions for Team Collaboration

#### Option 1: Developer-Scoped A2A
```
docs/a2a/
├── alice/
│   ├── reviewer.md
│   └── engineer-feedback.md
├── bob/
│   ├── reviewer.md
│   └── engineer-feedback.md
```

#### Option 2: Task-Scoped Reports
```
docs/a2a/
├── sprint-1-task-1/
│   ├── implementation-report.md
│   └── review-feedback.md
├── sprint-1-task-2/
│   ├── implementation-report.md
│   └── review-feedback.md
```

#### Option 3: External System Integration
- Use Linear/GitHub Issues for task assignment
- Conduct A2A communication in issue comments
- Coordinate sprint.md updates through PR reviews

#### Option 4: Feature Branches
- Each developer works on feature branch with own docs snapshot
- A2A communication in branch-specific files
- Consolidate on merge

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
# 1. Define product requirements
/plan-and-analyze
# → Answer discovery questions
# → Review docs/prd.md

# 2. Design architecture
/architect
# → Answer technical questions
# → Review docs/sdd.md

# 3. Plan sprints
/sprint-plan
# → Clarify capacity and priorities
# → Review docs/sprint.md

# 4. Implement Sprint 1
/implement sprint-1
# → Agent implements tasks
# → Review docs/a2a/reviewer.md

# 5. Review Sprint 1
/review-sprint
# → Either approves or requests changes

# 6. Address feedback (if needed)
/implement sprint-1
# → Agent fixes issues
# → Re-review

# 7. Continue sprints until complete...

# 8. Security audit
/audit
# → Fix critical issues

# 9. Deploy to production
/deploy-production
# → Production infrastructure deployed
```

---

## Related Documentation

- **[README.md](README.md)** - Quick start guide
- **[DEPLOY-ORG-README.md](DEPLOY-ORG-README.md)** - Organizational integration quick start
- **[DEPLOY-ORG-PROCESS.md](DEPLOY-ORG-PROCESS.md)** - Detailed organizational deployment workflow
- **[CLAUDE.md](CLAUDE.md)** - Guidance for Claude Code instances

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
