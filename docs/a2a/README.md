# Agent-to-Agent (A2A) Communication

This directory contains files that enable agents to communicate and coordinate with each other through structured feedback loops.

## Files

### Integration Context

#### `integration-context.md` (Optional)
**Created by**: `context-engineering-expert` agent (via `/integrate-org-workflow`)
**Read by**: All downstream agents

When this file exists, it provides organizational workflow context to all agents:
- Available tools (Discord, Linear, Google Docs, etc.)
- Knowledge sources (LEARNINGS library, user personas, community feedback)
- Context preservation requirements (how to link back to source discussions)
- Team structure and roles
- Documentation locations

**All agents check for this file before starting their work** and adapt their behavior based on the organizational integration context provided.

#### `integration-context.md.template`
Template for generating the integration context file. The `context-engineering-expert` agent uses this as a starting point and customizes it based on organizational discovery.

---

### Implementation Feedback Loop (Phases 4-5)

#### `reviewer.md`
**Created by**: `sprint-task-implementer` agent (via `/implement`)
**Read by**: `senior-tech-lead-reviewer` agent (via `/review-sprint`)

Implementation report containing:
- Tasks completed
- Files created/modified
- Test coverage details
- Technical decisions made
- Verification steps performed
- How previous feedback was addressed (if applicable)

#### `engineer-feedback.md`
**Created by**: `senior-tech-lead-reviewer` agent (via `/review-sprint`)
**Read by**: `sprint-task-implementer` agent (via `/implement`)

Review feedback containing:
- Issues found in implementation
- Required changes
- Clarifications needed
- Quality concerns
- Approval status ("All good" when approved)

---

### Deployment Feedback Loop (Server Setup & Audit)

#### `deployment-report.md`
**Created by**: `devops-crypto-architect` agent (via `/setup-server`)
**Read by**: `paranoid-auditor` agent (via `/audit-deployment`)

Deployment infrastructure report containing:
- Server configuration details
- Scripts generated (with status)
- Configuration files created
- Security implementation checklist
- Documentation created
- Technical decisions with rationale
- Known limitations
- Verification steps for auditor
- Previous audit feedback addressed (if revision)

#### `deployment-feedback.md`
**Created by**: `paranoid-auditor` agent (via `/audit-deployment`)
**Read by**: `devops-crypto-architect` agent (via `/setup-server`)

Security audit feedback containing:
- Audit verdict: **CHANGES_REQUIRED** or **APPROVED - LET'S FUCKING GO**
- Critical issues (must fix before deployment)
- High priority issues (should fix before production)
- Medium/Low priority issues (fix after deployment)
- Infrastructure security checklist status
- Previous feedback verification status
- Positive findings (what was done well)
- Next steps

#### `deployment-report.md.template`
Template for the DevOps engineer to structure their deployment report.

#### `deployment-feedback.md.template`
Template for the security auditor to structure their feedback.

---

## Workflows

### Phase 0: Integration (Optional)
```
/integrate-org-workflow
    ↓
context-engineering-expert creates integration-context.md
    ↓
All downstream agents read this file and adapt behavior
```

### Phases 4-5: Implementation Feedback Loop
```
/implement sprint-1
    ↓
sprint-task-implementer creates reviewer.md
    ↓
Human or /review-sprint reviews code and report
    ↓
Creates engineer-feedback.md with feedback or "All good"
    ↓ (if feedback provided)
/implement sprint-1 (again)
    ↓
sprint-task-implementer reads feedback, fixes issues
    ↓
Updates reviewer.md with changes
    ↓
(repeat until approved with "All good")
```

### Deployment Feedback Loop (Server Setup → Audit → Deploy)
```
/setup-server
    ↓
devops-crypto-architect creates infrastructure
    ↓
Writes deployment-report.md
    ↓
/audit-deployment
    ↓
paranoid-auditor reviews infrastructure
    ↓
Writes deployment-feedback.md
    ↓
├── If CHANGES_REQUIRED:
│   ↓
│   /setup-server (again)
│   ↓
│   devops-crypto-architect reads feedback
│   ↓
│   Fixes issues, updates report
│   ↓
│   (repeat until approved)
│
└── If APPROVED - LET'S FUCKING GO:
    ↓
    /deploy-go
    ↓
    Execute production deployment
    ↓
    Verify and document completion
```

---

## Feedback Loop Patterns

### Implementation Pattern (Engineer ↔ Reviewer)

| Command | Agent | Reads | Writes |
|---------|-------|-------|--------|
| `/implement` | sprint-task-implementer | `engineer-feedback.md` | `reviewer.md` |
| `/review-sprint` | senior-tech-lead-reviewer | `reviewer.md` | `engineer-feedback.md` |

**Approval Signal**: Reviewer writes "All good" to `engineer-feedback.md`

### Deployment Pattern (DevOps ↔ Auditor)

| Command | Agent | Reads | Writes |
|---------|-------|-------|--------|
| `/setup-server` | devops-crypto-architect | `deployment-feedback.md` | `deployment-report.md` |
| `/audit-deployment` | paranoid-auditor | `deployment-report.md` | `deployment-feedback.md` |
| `/deploy-go` | devops-crypto-architect | `deployment-feedback.md` | (updates status) |

**Approval Signal**: Auditor writes "APPROVED - LET'S FUCKING GO" to `deployment-feedback.md`

---

## Design Principles

### Stateless Agent Invocations
Each agent invocation is stateless. Context is maintained through:
- Document artifacts in `docs/`
- A2A communication files in `docs/a2a/`
- Explicit reading of previous outputs

### Clear Approval Signals
- Implementation: "All good" in `engineer-feedback.md`
- Deployment: "APPROVED - LET'S FUCKING GO" in `deployment-feedback.md`

### Iterative Quality Improvement
Feedback loops enable iterative quality improvement without blocking progress:
1. Work is done and reported
2. Review identifies issues
3. Issues are addressed
4. Cycle repeats until approved

### Separation of Concerns
- **Engineers** focus on implementation quality
- **Reviewers** focus on code quality and correctness
- **DevOps** focuses on infrastructure reliability
- **Auditors** focus on security and operational safety

---

## Notes

- These files enable **stateless agent invocations** - each agent reads context from files rather than maintaining conversation history
- The `integration-context.md` file makes the framework **org-aware** while remaining **workflow-agnostic** when used standalone
- The feedback loop files enable **iterative quality improvement** without blocking progress
- The deployment feedback loop ensures **security-first deployment** with explicit approval gates
