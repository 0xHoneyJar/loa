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

Our development process follows a structured, eight-phase approach:

1. **Phase 0: Organizational Integration Design** → Integration Architecture and Tool Setup (optional, for teams)
2. **Phase 0.5: Integration Implementation** → Discord Bot, Webhooks, Sync Scripts (optional, requires Phase 0)
3. **Phase 1: Planning** → Product Requirements Document (PRD)
4. **Phase 2: Architecture** → Software Design Document (SDD)
5. **Phase 3: Sprint Planning** → Sprint Plan
6. **Phase 4: Implementation** → Production Code with Feedback Loop
7. **Phase 5: Review** → Quality Validation and Sprint Approval
8. **Phase 6: Deployment** → Production Infrastructure and Handover

Each phase is handled by a specialized agent with deep domain expertise, ensuring thorough discovery, clear documentation, high-quality implementation, rigorous quality control, and enterprise-grade production deployment.

---

## Agents

### 1. **context-engineering-expert** (AI & Context Engineering Expert)
- **Role**: Pioneering AI expert with 15 years of experience in context engineering
- **Expertise**: Multi-tool orchestration, prompt engineering, workflow integration, agent coordination
- **Responsibilities**:
  - Map and analyze existing organizational workflows
  - Design integration architecture between agentic-base and org tools
  - Create context flow patterns across Discord, Google Docs, Linear, etc.
  - Adapt framework for multi-developer concurrent collaboration
  - Document integration specifications and requirements
  - Design adoption and change management strategy
- **Output**: `docs/integration-architecture.md`, `docs/tool-setup.md`, `docs/team-playbook.md`, `docs/a2a/integration-context.md`
- **Note**: This agent designs but does NOT implement. Use `/implement-org-integration` after this phase to build the integration layer.

### 2. **prd-architect** (Product Manager)
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
- **Expertise**: Infrastructure as code, CI/CD, security, monitoring, blockchain operations, cypherpunk security
- **Modes**:
  - **Integration Implementation Mode** (Phase 0.5): Implements Discord bots, webhooks, sync scripts based on integration architecture
  - **Production Deployment Mode** (Phase 6): Implements production infrastructure, CI/CD pipelines, monitoring
- **Integration Responsibilities** (Phase 0.5):
  - Review integration architecture and specifications
  - Implement Discord bot with command handlers and event listeners
  - Implement webhook handlers (Linear, GitHub, Vercel)
  - Implement cron jobs and scheduled tasks
  - Create deployment configs (Docker, systemd, PM2)
  - Set up monitoring and logging for integration layer
  - Create operational runbooks for integration maintenance
- **Deployment Responsibilities** (Phase 6):
  - Review project documentation (PRD, SDD, sprint plans)
  - Design production infrastructure (cloud, Kubernetes, blockchain nodes)
  - Implement infrastructure as code
  - Create CI/CD pipelines
  - Set up monitoring, alerting, and observability
  - Implement security hardening and secrets management
  - Generate handover documentation and runbooks
- **Output**:
  - Phase 0.5: `integration/` directory with complete integration infrastructure
  - Phase 6: `docs/deployment/` with infrastructure code and operational docs

### 7. **paranoid-auditor** (Security Auditor)
- **Role**: Paranoid Cypherpunk Security Auditor with 30+ years of experience
- **Expertise**: OWASP Top 10, cryptographic implementation, secrets management, penetration testing
- **Responsibilities**:
  - Perform comprehensive security and quality audits
  - Identify vulnerabilities across OWASP Top 10 categories
  - Review cryptographic implementations and key management
  - Audit authentication, authorization, and access controls
  - Assess input validation and sanitization
  - Review data privacy and PII handling
  - Evaluate infrastructure security
  - Analyze dependencies and supply chain risks
  - Provide prioritized remediation guidance
- **Output**: `SECURITY-AUDIT-REPORT.md` with findings and remediation steps
- **Usage**: Ad-hoc, invoked before production, after major changes, or periodically

### 8. **devrel-translator** (Developer Relations Professional)
- **Role**: Elite Developer Relations Professional with 15 years of experience
- **Expertise**: Technical communication, executive summaries, stakeholder management, educational content creation
- **Background**: Founded and scaled a world-class coding bootcamp (now franchised globally), created all educational materials from scratch
- **Responsibilities**:
  - Translate complex technical documentation into clear, compelling narratives for executives and stakeholders
  - Create audience-specific summaries (executives, board, investors, marketing, product, compliance)
  - Generate executive summaries, board presentations, investor updates, marketing briefs
  - Explain business value and strategic implications of technical decisions
  - Acknowledge risks, tradeoffs, and limitations honestly
  - Use analogies and plain language to make technology accessible
  - Provide actionable next steps and decision points
- **Output**: Executive summaries, stakeholder briefings, board presentations (1-3 pages tailored by audience)
- **Usage**: Ad-hoc, invoked to translate PRDs, SDDs, audit reports, sprint updates for non-technical audiences

---

## Workflow

### Phase 0: Organizational Integration (`/integrate-org-workflow`) [Optional]

**Agent**: `context-engineering-expert`

**Goal**: Integrate agentic-base with your organization's existing tools and workflows

**When to Use**:
- You have multi-team initiatives spanning departments
- Discussions happen in Discord/Slack
- Requirements documented in Google Docs/Notion
- Project tracking in Linear/Jira
- Multiple developers working concurrently
- Need to adapt agentic-base to your organizational processes

**Process**:
1. Agent asks targeted questions across 6 discovery phases:
   - Current Workflow Mapping (tools, roles, handoffs)
   - Pain Points & Bottlenecks (where context gets lost)
   - Integration Requirements (which tools, automation level)
   - Team Structure & Permissions (authority, access controls)
   - Data & Context Requirements (what info agents need)
   - Success Criteria & Constraints (goals, limitations)
2. Agent designs integration architecture
3. Agent proposes adaptation strategies for multi-developer teams
4. Generates comprehensive integration documentation
5. Documents implementation specifications (does NOT implement code)

**Command**:
```bash
/integrate-org-workflow
```

**Outputs**:
- `docs/integration-architecture.md` - Architecture and data flow diagrams
- `docs/tool-setup.md` - Configuration guide for APIs, webhooks, bots
- `docs/team-playbook.md` - How teams use the integrated system
- `docs/a2a/integration-context.md` - Context for downstream agents
- Implementation specifications and technology recommendations
- Adoption and change management plan

**Next Step**: After Phase 0 completes, run `/implement-org-integration` (Phase 0.5) to build the integration layer.

**Integration Architecture Includes**:
- Current vs. proposed workflow diagrams
- Tool interaction map (which tools communicate)
- Data flow diagrams (how information moves)
- Agent trigger points (when agents activate)
- Context preservation strategy
- Security and permissions model
- Rollout phases (incremental adoption)

**Multi-Developer Adaptation Strategies**:
- Initiative-based isolation (per Linear initiative)
- Linear-centric workflow (issues as source of truth)
- Branch-based workflows (feature branch scoped docs)
- Hybrid orchestration (mix of shared docs and per-task issues)

**Common Integration Patterns**:
1. **Discord → Linear → Agentic-Base**: Team discusses in Discord, creates Linear initiative, triggers agent workflow
2. **Google Docs → Linear → Implementation**: Collaborative requirements doc → Linear project → agent implementation
3. **Multi-Team Orchestration**: Leadership initiative → multiple sub-projects → coordinated implementation
4. **Discord-Native**: Agents as bot team members, all workflow in Discord

---

### Phase 0.5: Integration Implementation (`/implement-org-integration`)

**Agent**: `devops-crypto-architect` (Integration Implementation Mode)

**Goal**: Implement the Discord bot, webhooks, sync scripts, and integration infrastructure designed in Phase 0

**When to Use**: After completing Phase 0 (`/integrate-org-workflow`) and having integration architecture documentation

**Prerequisites**:
- `docs/integration-architecture.md` exists (integration design)
- `docs/tool-setup.md` exists (tool configuration documented)
- `docs/team-playbook.md` exists (team workflows documented)
- `docs/a2a/integration-context.md` exists (agent integration context)

**Process**:
1. Agent reviews all integration architecture documents
2. Plans implementation based on specifications
3. Implements Discord bot with command handlers
4. Implements webhook handlers (Linear, GitHub, Vercel)
5. Implements cron jobs and scheduled tasks
6. Creates deployment configs (Docker, docker-compose, systemd, PM2)
7. Sets up monitoring, logging, and health checks
8. Creates tests for integration components
9. Deploys to development/staging for validation
10. Generates operational runbooks and documentation

**Command**:
```bash
/implement-org-integration
```

**Outputs**:
- `integration/src/` - Complete bot and webhook implementation
- `integration/config/` - Configuration files (committed to git)
- `integration/secrets/.env.local.example` - Secrets template
- `integration/Dockerfile`, `docker-compose.yml` - Deployment configs
- `integration/README.md` - Integration guide and quick start
- `integration/DEPLOYMENT.md` - Deployment instructions
- `docs/deployment/runbooks/integration-operations.md` - Operational runbook
- `docs/deployment/integration-layer-handover.md` - Handover document

**Implementation Includes**:
- Discord bot with event listeners and command handlers
- Linear webhook handler with signature verification
- GitHub/Vercel webhook handlers (if needed)
- Daily digest cron job
- Feedback capture (emoji reactions → Linear issues)
- Structured logging with health check endpoints
- Rate limiting and error handling
- Unit and integration tests
- Deployment-ready infrastructure

**Testing Checklist**:
- Bot connects to Discord successfully
- Commands work in Discord (e.g., `/show-sprint`)
- Emoji reactions create Linear draft issues
- Webhooks trigger correctly with signature verification
- Cron jobs execute on schedule
- Logs are written properly
- Health check endpoint responds
- Error handling prevents crashes

---

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
   - Clarifies blockchain/crypto requirements (nodes, chains, key management)
   - Confirms scale and performance needs (traffic, data volume)
   - Validates security and compliance requirements
   - Discusses budget constraints
   - Understands team and operational needs
   - Defines monitoring and alerting requirements
   - Plans CI/CD strategy
   - Establishes backup and disaster recovery needs

3. **Infrastructure Design**:
   - Infrastructure as Code (Terraform/Pulumi)
   - Compute infrastructure (Kubernetes/ECS)
   - Networking (VPC, CDN, DNS)
   - Data layer (databases, caching)
   - Blockchain infrastructure (nodes, RPC, indexers) if applicable
   - Security (secrets management, HSM/MPC, network security)
   - CI/CD pipelines
   - Monitoring and observability

4. **Implementation**:
   - Foundation (IaC, networking, DNS)
   - Security foundation (secrets, IAM, audit logging)
   - Compute and data layer
   - Blockchain infrastructure (if applicable)
   - Application deployment
   - CI/CD pipelines
   - Monitoring and observability
   - Testing and validation

5. **Documentation and Handover**:
   Creates comprehensive docs in `docs/deployment/`:
   - **infrastructure.md**: Architecture overview, resources, cost breakdown
   - **deployment-guide.md**: How to deploy, rollback, migrations
   - **runbooks/**: Operational procedures for common tasks
     - deployment.md, rollback.md, scaling.md
     - incident-response.md, backup-restore.md
     - monitoring.md, security.md
   - **monitoring.md**: Dashboards, metrics, alerts, on-call
   - **security.md**: Access, secrets rotation, key management, compliance
   - **disaster-recovery.md**: RPO/RTO, backup procedures, failover
   - **cost-optimization.md**: Cost breakdown and optimization opportunities
   - **blockchain-ops.md**: Node operations, RPC management (if applicable)
   - **troubleshooting.md**: Common issues and solutions
   - **iac-guide.md**: IaC repository structure and usage

6. **Knowledge Transfer**:
   - Deployment completion checklist
   - Production URLs and endpoints
   - Dashboard locations
   - Repository locations
   - Critical access information
   - Cost estimates
   - Next steps and recommendations
   - Open items requiring action

**Command**:
```bash
/deploy-production
```

**Outputs**:
- Production infrastructure (deployed)
- IaC repository (Terraform/Pulumi configs)
- CI/CD pipelines (GitHub Actions/GitLab CI)
- Kubernetes manifests/Helm charts
- Monitoring configuration (Prometheus, Grafana)
- Comprehensive documentation (`docs/deployment/`)

**Deployment Deliverables**:
- ✅ Infrastructure deployed and tested
- ✅ Application running in production
- ✅ CI/CD pipelines operational
- ✅ Monitoring and alerting configured
- ✅ Backups configured and tested
- ✅ Security hardening complete
- ✅ Operational documentation complete
- ✅ Team access configured
- ✅ Cost monitoring enabled
- ✅ Disaster recovery tested

**Quality Standards**:
- Infrastructure as Code (all resources version controlled)
- Security (defense in depth, secrets management, least privilege)
- Monitoring (comprehensive observability before going live)
- Automation (fully automated CI/CD)
- Documentation (complete operational runbooks)
- Tested (staging deployment, DR procedures validated)
- Scalable (handles expected load with room to grow)
- Cost-optimized (efficient within budget)
- Recoverable (backups tested, DR plan in place)

---

### Ad-Hoc: Security Audit (`/audit`)

**Agent**: `paranoid-auditor`

**Goal**: Perform comprehensive security and quality audit of the codebase and infrastructure

**When to Use**:
- Before production deployment (highly recommended)
- After major code changes or new features
- When implementing security-sensitive functionality (authentication, payments, data handling)
- After adding new dependencies or integrations
- Periodically for ongoing projects (quarterly recommended)
- When compliance or security certification is required

**Process**:
1. **Comprehensive Security Assessment**:
   - OWASP Top 10 vulnerability scanning
   - Code review for security anti-patterns
   - Dependency and supply chain analysis
   - Cryptographic implementation review
   - Secrets and credential management audit
   - Input validation and sanitization review
   - Authentication and authorization analysis
   - Data privacy and PII handling assessment
   - Infrastructure security evaluation
   - Error handling and information disclosure review

2. **Audit Report Generation**:
   - Findings categorized by severity (CRITICAL/HIGH/MEDIUM/LOW)
   - Each finding includes:
     - Detailed description of the vulnerability
     - Affected files and code locations
     - Security impact and exploitation scenarios
     - Specific remediation guidance
     - Code examples for fixes
   - Overall risk assessment and security posture evaluation
   - Prioritized action plan

3. **Remediation**:
   - Address CRITICAL issues immediately (must be fixed before production)
   - Plan HIGH priority fixes in current sprint
   - Schedule MEDIUM issues for upcoming sprints
   - Track LOW priority items in backlog

**Command**:
```bash
/audit
```

**Output**:
- `SECURITY-AUDIT-REPORT.md` - Comprehensive security audit report with findings and remediation guidance

**Audit Scope Includes**:
- ✅ Injection vulnerabilities (SQL, command, XSS, etc.)
- ✅ Authentication and session management
- ✅ Sensitive data exposure
- ✅ XML/XXE attacks
- ✅ Broken access control
- ✅ Security misconfiguration
- ✅ Cross-Site Scripting (XSS)
- ✅ Insecure deserialization
- ✅ Using components with known vulnerabilities
- ✅ Insufficient logging and monitoring
- ✅ Cryptographic implementation
- ✅ API security
- ✅ Secrets management
- ✅ Infrastructure security

**Best Practices**:
- Run audit before every production deployment
- Address all CRITICAL findings before going live
- Re-run audit after fixing critical issues to verify fixes
- Use audit report as input for security documentation
- Track security debt and remediation progress
- Integrate security reviews into CI/CD pipeline

---

### Ad-Hoc: Executive Translation (`/translate @document.md for [audience]`)

**Agent**: `devrel-translator`

**Goal**: Translate complex technical documentation into clear, stakeholder-appropriate communications

**When to Use**:
- Before board meetings or investor updates
- When executives need to understand technical decisions
- To create marketing briefs from technical features
- For compliance or legal team briefings
- When product managers need accessible technical summaries
- To transform PRDs/SDDs into executive summaries

**Process**:
1. **Deep Understanding** (Agent reads thoroughly):
   - Reviews all provided technical documentation
   - Understands context and business implications
   - Identifies key points relevant to target audience
   - Spots risks, tradeoffs, and limitations

2. **Audience Analysis**:
   - Determines technical depth appropriate for audience
   - Identifies what matters most (business value, risk, cost, timeline)
   - Tailors message to decision context

3. **Value Translation**:
   - Leads with business outcomes, not technical details
   - Uses analogies to relate to familiar business concepts
   - Quantifies impact with specific metrics
   - Shows tradeoffs and acknowledges what was sacrificed
   - Connects to strategic business goals

4. **Executive Summary Creation**:
   - **What We Built**: 1-2 paragraphs in plain language
   - **Why It Matters**: Business value with specific metrics
   - **Key Achievements**: Measurable outcomes with numbers
   - **Risks & Limitations**: Honest assessment of tradeoffs
   - **What's Next**: Immediate actions and short-term milestones
   - **Investment Required**: Time, budget, resources needed
   - **Risk Assessment**: Overall risk level with justification

5. **Supporting Materials** (when helpful):
   - FAQ section anticipating stakeholder questions
   - Visual suggestions (diagrams, flowcharts, risk matrices)
   - Stakeholder-specific versions (exec vs. board vs. marketing)

**Command**:
```bash
# Translate security audit for board
/translate @SECURITY-AUDIT-REPORT.md for board of directors

# Create executive summary from SDD
/translate @docs/sdd.md for executives

# Generate marketing brief from sprint update
/translate @docs/sprint.md for marketing team

# Product briefing from PRD
/translate @docs/prd.md for product manager
```

**Output**:
- Executive summaries (1-3 pages tailored by audience)
- Board presentations (strategic focus, governance, risk management)
- Investor updates (market opportunity, competitive advantage, ROI)
- Marketing briefs (features, value props, positioning)
- Product briefings (technical details, user impact, constraints)

**Communication Principles**:
- ✅ Lead with value ("Reduces security risk by 73%" vs. "Implemented RBAC")
- ✅ Use analogies ("Like a security guard checking IDs" for authentication)
- ✅ Be specific ("Saves 8 hours/week per developer" vs. "improves efficiency")
- ✅ Show tradeoffs ("Prioritized security over speed for production readiness")
- ✅ Acknowledge gaps ("Low priority issues deferred due to resource constraints")
- ❌ Don't oversimplify (respect audience intelligence)
- ❌ Don't hide risks (stakeholders need honest assessment)
- ❌ Don't use jargon without defining it

**Example Use Cases**:
1. **Security Audit → Board Presentation**:
   - Input: 50-page technical security audit
   - Output: 2-page executive summary with business risk assessment, compliance implications, remediation status

2. **SDD → Investor Update**:
   - Input: Detailed system design document
   - Output: 1-page summary covering technology choices, competitive advantage, scalability story, technical moat

3. **Sprint Update → Executive Sync**:
   - Input: Sprint progress reports and technical implementation details
   - Output: 1-page update with what shipped (user-facing value), what's at risk, decisions needed, metrics

---

## Custom Commands

### `/integrate-org-workflow`
Integrate agentic-base with organizational tools and workflows.
- **Location**: `.claude/commands/integrate-org-workflow.md`
- **Agent**: `context-engineering-expert`
- **Output**: `docs/integration-architecture.md`, `docs/tool-setup.md`, `docs/team-playbook.md`, integration code

### `/plan-and-analyze`
Launch PRD architect to define goals, requirements, and scope.
- **Location**: `.claude/commands/plan-and-analyze.md`
- **Agent**: `prd-architect`
- **Output**: `docs/prd.md`

### `/architect`
Launch architecture designer to review PRD and create SDD.
- **Location**: `.claude/commands/architect.md`
- **Agent**: `architecture-designer`
- **Output**: `docs/sdd.md`

### `/sprint-plan`
Launch sprint planner to review PRD/SDD and create sprint plan.
- **Location**: `.claude/commands/sprint-plan.md`
- **Agent**: `sprint-planner`
- **Output**: `docs/sprint.md`

### `/implement {sprint}`
Launch implementation engineer to execute sprint tasks with feedback loop.
- **Location**: `.claude/commands/implement.md`
- **Agent**: `sprint-task-implementer`
- **Output**: Code + `docs/a2a/reviewer.md`

### `/review-sprint`
Launch senior technical lead to review sprint implementation and provide feedback or approval.
- **Location**: `.claude/commands/review-sprint.md`
- **Agent**: `senior-tech-lead-reviewer`
- **Output**: `docs/a2a/engineer-feedback.md`, updated `docs/sprint.md`

### `/deploy-production`
Launch DevOps crypto architect to deploy application to production with enterprise infrastructure.
- **Location**: `.claude/commands/deploy-production.md`
- **Agent**: `devops-crypto-architect`
- **Output**: Production infrastructure, IaC configs, CI/CD pipelines, `docs/deployment/`

### `/audit`
Launch paranoid security auditor to perform comprehensive security and quality audit (ad-hoc).
- **Location**: `.claude/commands/audit.md`
- **Agent**: `paranoid-auditor`
- **Output**: `SECURITY-AUDIT-REPORT.md`
- **Usage**: Before production, after major changes, or periodically

### `/translate @document.md for [audience]`
Launch DevRel translator to create executive-ready communications from technical documentation (ad-hoc).
- **Location**: `.claude/commands/translate.md`
- **Agent**: `devrel-translator`
- **Output**: Executive summaries, board presentations, marketing briefs (1-3 pages tailored by audience)
- **Usage**: Anytime you need to communicate technical work to non-technical stakeholders
- **Examples**:
  - `/translate @SECURITY-AUDIT-REPORT.md for board of directors`
  - `/translate @docs/sdd.md for executives`
  - `/translate @docs/sprint.md for marketing team`

---

## Document Artifacts

### Primary Documents

| Document | Path | Created By | Purpose |
|----------|------|------------|---------|
| **PRD** | `docs/prd.md` | `prd-architect` | Product requirements and business context |
| **SDD** | `docs/sdd.md` | `architecture-designer` | System design and technical architecture |
| **Sprint Plan** | `docs/sprint.md` | `sprint-planner` | Sprint tasks with acceptance criteria |
| **Security Audit Report** | `SECURITY-AUDIT-REPORT.md` | `paranoid-auditor` | Security vulnerabilities and remediation guidance |

### Agent-to-Agent (A2A) Communication

| Document | Path | Created By | Purpose |
|----------|------|------------|---------|
| **Integration Context** | `docs/a2a/integration-context.md` | `context-engineering-expert` | Organizational context for all downstream agents |
| **Implementation Report** | `docs/a2a/reviewer.md` | `sprint-task-implementer` | Detailed report for senior lead review |
| **Feedback** | `docs/a2a/engineer-feedback.md` | Senior Technical Lead (you) | Feedback for engineer to address |

### Deployment Documentation

| Document | Path | Created By | Purpose |
|----------|------|------------|---------|
| **Infrastructure Overview** | `docs/deployment/infrastructure.md` | `devops-crypto-architect` | Architecture, resources, cost breakdown |
| **Deployment Guide** | `docs/deployment/deployment-guide.md` | `devops-crypto-architect` | How to deploy, rollback, migrations |
| **Monitoring Guide** | `docs/deployment/monitoring.md` | `devops-crypto-architect` | Dashboards, metrics, alerts |
| **Security Guide** | `docs/deployment/security.md` | `devops-crypto-architect` | Access management, secrets, compliance |
| **Disaster Recovery** | `docs/deployment/disaster-recovery.md` | `devops-crypto-architect` | Backup, restore, failover procedures |
| **Cost Optimization** | `docs/deployment/cost-optimization.md` | `devops-crypto-architect` | Cost breakdown and optimization |
| **Blockchain Ops** | `docs/deployment/blockchain-ops.md` | `devops-crypto-architect` | Node operations, RPC management |
| **Troubleshooting** | `docs/deployment/troubleshooting.md` | `devops-crypto-architect` | Common issues and solutions |
| **IaC Guide** | `docs/deployment/iac-guide.md` | `devops-crypto-architect` | Infrastructure as Code usage |
| **Runbooks** | `docs/deployment/runbooks/*.md` | `devops-crypto-architect` | Operational procedures |

---

## Agent-to-Agent Communication

The framework uses structured A2A communication to coordinate agents and preserve organizational context.

### **Integration Context** (`docs/a2a/integration-context.md`)

**Created by**: `context-engineering-expert` (Phase 0)
**Read by**: All downstream agents (Phases 1-7)

When `/integrate-org-workflow` has been run, this file provides:
- **Available organizational tools**: Discord, Linear, Google Docs, etc.
- **Knowledge sources**: Where to find past learnings, user personas, community feedback
- **Context preservation requirements**: How to link back to source discussions
- **Team structure**: Which teams exist, how work is organized
- **Documentation locations**: Where to update status and changelogs

**Agent behavior when this file exists**:
- **PRD Architect**: Queries LEARNINGS library, references existing personas, checks community feedback
- **Architecture Designer**: Reviews past experiments, considers team structure in design decisions
- **Sprint Planner**: Links tasks to source discussions, checks current project state
- **Sprint Task Implementer**: Maintains context chains, updates documentation per org standards
- **Senior Tech Lead Reviewer**: Verifies community intent, checks documentation updates
- **DevOps Crypto Architect**: Tracks deployments in org tools, notifies correct channels

**If this file doesn't exist**: Agents proceed with standard workflow using only local docs.

### **Implementation Feedback Loop** (Phases 4-5)

#### **Engineer → Senior Lead** (`docs/a2a/reviewer.md`)

The engineer generates a comprehensive report after implementation:
- What was accomplished
- Files created/modified
- Test coverage
- Technical decisions
- Verification steps
- Feedback addressed (if revision)

#### **Senior Lead → Engineer** (`docs/a2a/engineer-feedback.md`)

You (as senior technical lead) review the implementation and provide feedback:
- Issues found
- Required changes
- Clarifications needed
- Quality concerns

The engineer will read this file on the next `/implement {sprint}` invocation, clarify anything unclear, fix all issues, and generate an updated report.

---

## Multi-Developer Usage Warning

⚠️ **CRITICAL**: This framework is architected for **single-threaded workflows**. The agent system assumes one active development stream at a time.

### Why Multi-Developer Concurrent Usage Breaks

If multiple developers use `/implement` simultaneously on the same project:

1. **A2A File Collisions**:
   - `docs/a2a/reviewer.md` gets overwritten by each engineer
   - `docs/a2a/engineer-feedback.md` is shared across all engineers
   - Engineer A reads feedback intended for Engineer B
   - Reports are overwritten before senior lead can review them

2. **Sprint Status Conflicts**:
   - Multiple engineers update `docs/sprint.md` simultaneously
   - Merge conflicts on task completion status
   - Inconsistent ✅ markers depending on who pushed last

3. **Context Confusion**:
   - Implementation reports reference different code changes
   - Senior lead reviews incomplete or mixed context
   - Feedback becomes ambiguous about which engineer/task it addresses

4. **Broken Feedback Loops**:
   - The A2A cycle is inherently single-threaded
   - Assumes one engineer ↔ one reviewer conversation
   - Parallel conversations in the same files create chaos

### Solutions for Team Collaboration

To adapt this framework for multiple developers, you must modify the structure:

#### Option 1: Developer-Scoped A2A Communication
```
docs/a2a/
├── alice/
│   ├── reviewer.md
│   └── engineer-feedback.md
├── bob/
│   ├── reviewer.md
│   └── engineer-feedback.md
```

**Requires**: Modifying agent prompts to read/write from developer-specific directories.

#### Option 2: Task-Scoped Implementation Reports
```
docs/a2a/
├── sprint-1-task-1/
│   ├── implementation-report.md
│   └── review-feedback.md
├── sprint-1-task-2/
│   ├── implementation-report.md
│   └── review-feedback.md
```

**Requires**: Task-based invocation (e.g., `/implement sprint-1-task-1`) with isolated A2A channels per task.

#### Option 3: External System Integration
- Keep `docs/prd.md`, `docs/sdd.md`, `docs/sprint.md` in git as **read-only shared references**
- Assign sprint tasks via Linear/GitHub Issues
- Conduct A2A communication in issue comments (not files)
- Use PR reviews for code validation instead of A2A files
- Coordinate `docs/sprint.md` updates through a single point of authority (tech lead)

**Advantage**: Leverages existing project management tools and PR workflows that are designed for concurrency.

#### Option 4: Feature Branches with Scoped Documentation
- Each developer works on a feature branch with their own `docs/` snapshot
- A2A communication happens in branch-specific files
- On merge, consolidate sprint status in main branch
- Conflicts resolved during PR review

**Advantage**: Git branching model provides isolation; disadvantage: documentation divergence across branches.

### Recommended Approach

For teams with 2+ developers working concurrently:

1. **Use Linear/GitHub Issues** (already in MCP config) for task assignment and tracking
2. **Keep planning docs** (prd.md, sdd.md, sprint.md) in git as shared, read-only references
3. **Use PR comments** for implementation feedback instead of A2A files
4. **Coordinate sprint status** updates through a designated tech lead who maintains sprint.md
5. **Consider task-scoped branches** if you want to preserve the A2A feedback loop model per task

The current framework's `.gitignore` excludes `docs/` precisely because these are **ephemeral artifacts** for a single-threaded workflow, not durable documentation designed for concurrent multi-developer editing.

---

## Best Practices

### For All Phases

1. **Answer Thoroughly**: Agents ask questions for a reason—provide detailed answers
2. **Clarify Early**: If an agent's question is unclear, ask them to rephrase
3. **Review Outputs**: Always review generated documents (PRD, SDD, sprint plan)
4. **Iterate Freely**: Use the feedback loop—it's designed for iterative improvement

### For Planning Phase

- Be specific about user personas and pain points
- Define measurable success metrics
- Clearly state what's in scope vs. out of scope
- Document assumptions and risks

### For Architecture Phase

- When presented with proposals, consider long-term maintainability
- Don't over-engineer—choose the simplest solution that meets requirements
- Validate technology stack choices against team expertise
- Consider operational complexity

### For Sprint Planning

- Be realistic about team capacity
- Prioritize ruthlessly—not everything needs to be in Sprint 1
- Validate dependencies are correctly identified
- Ensure acceptance criteria are specific and measurable

### For Implementation

- **Provide Clear Feedback**: Be specific in `docs/a2a/engineer-feedback.md`
- **Use File References**: Include file paths and line numbers
- **Explain Why**: Don't just say "fix this"—explain the reasoning
- **Test Before Approving**: Run the verification steps from the report

### For DevOps & Infrastructure

- Security first—never compromise on security fundamentals
- Automate everything that can be automated
- Design for failure—everything will eventually fail
- Monitor before deploying—can't fix what you can't see
- Document runbooks and incident response procedures
- Consider cost implications of architectural decisions
- For crypto/blockchain: Proper key management is life-or-death

---

## Example Workflow

```bash
# 1. Define product requirements
/plan-and-analyze
# → Answer discovery questions
# → Review docs/prd.md

# 2. Design architecture
/architect
# → Answer technical questions and choose proposals
# → Review docs/sdd.md

# 3. Plan sprints
/sprint-plan
# → Clarify team capacity and priorities
# → Review docs/sprint.md

# 4. Implement Sprint 1
/implement sprint-1
# → Agent implements tasks
# → Review docs/a2a/reviewer.md

# 5. Review Sprint 1
/review-sprint
# → Senior tech lead reviews code and implementation
# → Either:
#    - Approves: writes "All good", updates docs/sprint.md with ✅
#    - Requests changes: writes feedback to docs/a2a/engineer-feedback.md

# 6. Address feedback (if needed)
/implement sprint-1
# → Agent reads feedback, clarifies, fixes issues
# → Review updated docs/a2a/reviewer.md

# 7. Re-review Sprint 1
/review-sprint
# → Repeat review cycle until approved

# 8. Implement Sprint 2 (after Sprint 1 approved)
/implement sprint-2
# → Continue process for next sprint

# 9. Review Sprint 2
/review-sprint
# → Continue cycle

# ... Continue until all sprints complete ...

# 10. Deploy to Production (after all sprints approved)
/deploy-production
# → DevOps architect reviews project
# → Asks about deployment requirements
# → Designs and implements infrastructure
# → Deploys application to production
# → Sets up monitoring and CI/CD
# → Creates comprehensive operational documentation
# → Provides handover and knowledge transfer
```

---

## Infrastructure & DevOps

For infrastructure, deployment, security, and operational concerns, use the **devops-crypto-architect** agent:

**When to Use**:
- Infrastructure setup (cloud, Kubernetes, bare-metal)
- Blockchain node operations (validators, RPCs, indexers)
- CI/CD pipeline setup
- Security hardening and key management
- Monitoring and observability
- Performance optimization
- Cost optimization
- Disaster recovery planning

**Invoke Automatically**: The agent activates when you mention infrastructure, deployment, DevOps, security hardening, or blockchain operations.

**Agent Capabilities**:
- Infrastructure as Code (Terraform, Pulumi, CloudFormation)
- Container orchestration (Kubernetes, Docker, Helm)
- Multi-chain blockchain operations (Ethereum, Solana, Cosmos, Bitcoin, L2s)
- Security (HSMs, MPC, secrets management, zero-trust architecture)
- CI/CD (GitHub Actions, GitLab CI, ArgoCD, Flux)
- Monitoring (Prometheus, Grafana, Loki, blockchain-specific metrics)
- Smart contract deployment automation (Foundry, Hardhat, Anchor)

---

## Tips for Success

1. **Trust the Process**: Each phase builds on the previous—don't skip steps
2. **Be Patient**: Thorough discovery prevents costly mistakes later
3. **Engage Actively**: Agents need your input to make good decisions
4. **Review Everything**: You're the final decision-maker—review all outputs
5. **Use Feedback Loop**: The implementation feedback cycle is your quality gate
6. **Document Decisions**: Agents document their reasoning—review and validate
7. **Think Long-Term**: Consider maintainability, scalability, and team growth
8. **Security First**: Especially for crypto/blockchain projects—never compromise on security

---

## Questions?

If you have questions about the process:
- Review the agent definitions in `.claude/agents/`
- Check the command definitions in `.claude/commands/`
- Review existing artifacts in `docs/`
- Ask Claude Code for help with `/help`

---

**Remember**: This process is designed to be thorough and iterative. Quality takes time, and each phase ensures you're building the right thing, the right way, with the right team structure. Embrace the process, engage with the agents, and leverage their expertise to build exceptional products.
