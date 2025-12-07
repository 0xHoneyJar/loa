# Agent Documentation Index

## Overview

The agentic-base framework includes 7 specialized AI agents that work together to orchestrate the complete product development lifecycle—from requirements gathering through production deployment.

## The Seven Agents

### Phase 0: Integration (Optional)
1. **[Context Engineering Expert](./01-context-engineering-expert.md)** - Organizational workflow integration
   - **Role**: AI & Context Engineering Expert (15 years)
   - **Command**: `/integrate-org-workflow`
   - **Purpose**: Bridge agentic-base with organizational tools (Discord, Google Docs, Linear, etc.)
   - **When to Use**: Multi-team initiatives, multi-developer coordination, workflow integration

### Phase 1: Requirements
2. **[PRD Architect](./02-prd-architect.md)** - Product requirements discovery
   - **Role**: Senior Product Manager (15 years)
   - **Command**: `/plan-and-analyze`
   - **Purpose**: Transform ambiguous ideas into crystal-clear Product Requirements Documents
   - **When to Use**: Starting new features, unclear requirements, planning projects

### Phase 2: Architecture
3. **[Architecture Designer](./03-architecture-designer.md)** - System design
   - **Role**: Elite Software Architect (15 years)
   - **Command**: `/architect`
   - **Purpose**: Transform PRDs into comprehensive Software Design Documents
   - **When to Use**: Technical design decisions, choosing tech stack, architecture planning

### Phase 3: Sprint Planning
4. **[Sprint Planner](./04-sprint-planner.md)** - Task breakdown and scheduling
   - **Role**: Technical Product Manager (15 years)
   - **Command**: `/sprint-plan`
   - **Purpose**: Break down work into actionable 2.5-day sprint tasks
   - **When to Use**: Breaking down work, planning implementation, creating sprint schedules

### Phase 4: Implementation
5. **[Sprint Task Implementer](./05-sprint-task-implementer.md)** - Code implementation
   - **Role**: Elite Software Engineer (15 years)
   - **Command**: `/implement sprint-X`
   - **Purpose**: Implement sprint tasks with comprehensive tests and documentation
   - **When to Use**: Writing production code, implementing features, addressing feedback

### Phase 5: Review
6. **[Senior Tech Lead Reviewer](./06-senior-tech-lead-reviewer.md)** - Quality validation
   - **Role**: Senior Technical Lead (15+ years)
   - **Command**: `/review-sprint`
   - **Purpose**: Validate implementation quality and provide feedback
   - **When to Use**: Reviewing code, validating completeness, ensuring quality standards

### Phase 7: Deployment
7. **[DevOps Crypto Architect](./07-devops-crypto-architect.md)** - Infrastructure and deployment
   - **Role**: DevOps Architect (15 years crypto experience)
   - **Command**: `/deploy-production`
   - **Purpose**: Deploy to production with enterprise-grade infrastructure
   - **When to Use**: Infrastructure setup, deployment, CI/CD, monitoring, blockchain operations

## Agent Interaction Flow

```
User Idea/Requirement
        ↓
[0. Context Engineering Expert] ← Optional: Integrate with org tools
        ↓
[1. PRD Architect] → docs/prd.md
        ↓
[2. Architecture Designer] → docs/sdd.md
        ↓
[3. Sprint Planner] → docs/sprint.md
        ↓
[4. Sprint Task Implementer] → Code + docs/a2a/reviewer.md
        ↓
[5. Senior Tech Lead Reviewer] → docs/a2a/engineer-feedback.md
        ↓ (if feedback)
[4. Sprint Task Implementer] → Revisions + updated report
        ↓ (repeat until approved)
[5. Senior Tech Lead Reviewer] → Approval ✅
        ↓
[Next Sprint or Phase 7]
        ↓
[7. DevOps Crypto Architect] → Production Infrastructure
```

## Agent-to-Agent (A2A) Communication

The framework uses structured A2A communication files that enable agents to share context and coordinate work.

### Integration Context (Phase 0)
When the **Context Engineering Expert** has been run, it generates `docs/a2a/integration-context.md`:
- **Purpose**: Provides all downstream agents with organizational workflow context
- **Content**: Available tools, knowledge sources, team structure, context preservation requirements
- **Usage**: All agents check for this file first and adapt their behavior based on organizational integration

### Implementation Feedback Loop (Phases 4-5)
**Sprint Task Implementer** and **Senior Tech Lead Reviewer** use a feedback cycle:

1. **Sprint Task Implementer** generates `docs/a2a/reviewer.md` (implementation report)
2. **Senior Tech Lead Reviewer** reads report and code, provides `docs/a2a/engineer-feedback.md`
3. **Sprint Task Implementer** reads feedback, addresses issues, generates updated report
4. Cycle repeats until **Senior Tech Lead Reviewer** approves

### Document Flow
```
docs/
├── prd.md                  # PRD Architect output
├── sdd.md                  # Architecture Designer output
├── sprint.md               # Sprint Planner output (updated by Reviewer)
├── a2a/                    # Agent-to-Agent communication
│   ├── integration-context.md  # Context Engineering Expert → All Agents
│   ├── reviewer.md             # Implementer → Reviewer
│   └── engineer-feedback.md    # Reviewer → Implementer
├── integration-architecture.md # Context Engineering Expert output (human-facing)
├── tool-setup.md               # Context Engineering Expert output (human-facing)
├── team-playbook.md            # Context Engineering Expert output (human-facing)
└── deployment/                 # DevOps Crypto Architect output
    ├── infrastructure.md
    ├── deployment-guide.md
    ├── runbooks/
    └── ...
```

## Key Principles

### 1. Specialization
Each agent has deep expertise in their domain. They bring 15+ years of experience and domain-specific knowledge.

### 2. Structured Workflow
Agents work sequentially, building on previous outputs:
- PRD informs SDD
- SDD guides Sprint Plan
- Sprint Plan drives Implementation
- Implementation validated by Review
- All phases inform Deployment

### 3. Quality Gates
Each phase has validation checkpoints:
- PRD: Complete requirements before architecture
- SDD: Clear design before sprint planning
- Sprint: Actionable tasks before implementation
- Implementation: Production-ready before approval
- Deployment: Enterprise-grade infrastructure

### 4. Feedback-Driven Iteration
Implementation uses feedback loops:
- Implementer → Reviewer → Feedback → Implementer
- Iterate until quality standards met
- No compromises on security or critical issues

### 5. Documentation as Artifact
Every phase produces durable artifacts:
- Documents serve as project memory
- Enable async work and team changes
- Provide context for future decisions
- Support knowledge permanence

## When to Use Each Agent

| Scenario | Agent | Command |
|----------|-------|---------|
| Need to integrate with org tools | Context Engineering Expert | `/integrate-org-workflow` |
| Starting new project/feature | PRD Architect | `/plan-and-analyze` |
| Have PRD, need technical design | Architecture Designer | `/architect` |
| Have PRD+SDD, need task breakdown | Sprint Planner | `/sprint-plan` |
| Ready to implement sprint tasks | Sprint Task Implementer | `/implement sprint-X` |
| Code ready for review | Senior Tech Lead Reviewer | `/review-sprint` |
| Need infrastructure/deployment | DevOps Crypto Architect | `/deploy-production` |

## Agent Communication Style

### All Agents Share
- **Questioning mindset**: Ask clarifying questions before proceeding
- **Documentation focus**: Generate comprehensive artifacts
- **Quality emphasis**: No shortcuts, production-ready output
- **Context awareness**: Read all relevant docs before starting
- **Iterative approach**: Refine based on feedback

### Agent-Specific Styles
- **Context Engineering Expert**: Consultative, pragmatic, educational
- **PRD Architect**: Patient, thorough, conversational
- **Architecture Designer**: Technical, precise, justification-focused
- **Sprint Planner**: Strategic, clear, actionable
- **Sprint Task Implementer**: Technical, detailed, autonomous
- **Senior Tech Lead Reviewer**: Critical, constructive, educational
- **DevOps Crypto Architect**: Security-first, pragmatic, transparent

## Multi-Developer Usage

⚠️ **Important**: The framework is designed for single-threaded workflows. For multi-developer teams:

1. Use **Context Engineering Expert** to design integration with:
   - Linear (per-initiative isolation or linear-centric workflow)
   - Discord (community feedback collection)
   - Google Docs (collaborative requirements)

2. Adapt A2A communication:
   - Per-developer directories
   - Per-task scoped reports
   - External system integration (Linear comments, GitHub PR reviews)

3. See the [Multi-Developer Usage Warning](../README.md#multi-developer-usage-warning) for details

## Further Reading

- **[PROCESS.md](../PROCESS.md)** - Comprehensive workflow documentation
- **[Hivemind Laboratory Methodology](../HIVEMIND-LABORATORY-METHODOLOGY.md)** - Knowledge management approach
- **[Integration Updates](../HIVEMIND-INTEGRATION-UPDATES.md)** - Org tool integration guide
- Individual agent docs (see links above)

## Getting Started

1. Start with `/plan-and-analyze` to create your PRD
2. Use `/architect` to design your system
3. Run `/sprint-plan` to break down work
4. Execute `/implement sprint-1` to start coding
5. Use `/review-sprint` to validate quality
6. Repeat implementation/review until approved
7. Finally `/deploy-production` when ready

For organizational integration, start with `/integrate-org-workflow` before Phase 1.

---

*Each agent brings deep expertise to their domain. Trust the process, engage actively with questions, and leverage the structured workflow to build exceptional products.*
