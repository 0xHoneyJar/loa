---
name: "deploy-production"
version: "1.0.0"
description: |
  Design and deploy production infrastructure.
  IaC, CI/CD, monitoring, security hardening, operational docs.

arguments: []

agent: "deploying-infrastructure"
agent_path: "skills/deploying-infrastructure/"

context_files:
  - path: "grimoires/loa/prd.md"
    required: true
    purpose: "Product requirements for infrastructure needs"
  - path: "grimoires/loa/sdd.md"
    required: true
    purpose: "Architecture for deployment design"
  - path: "grimoires/loa/sprint.md"
    required: true
    purpose: "Sprint completion status"
  - path: "grimoires/loa/a2a/integration-context.md"
    required: false
    purpose: "Organizational context and MCP tools"

pre_flight:
  - check: "file_exists"
    path: "grimoires/loa/prd.md"
    error: "PRD not found. Run /plan-and-analyze first."

  - check: "file_exists"
    path: "grimoires/loa/sdd.md"
    error: "SDD not found. Run /architect first."

  - check: "file_exists"
    path: "grimoires/loa/sprint.md"
    error: "Sprint plan not found. Run /sprint-plan first."

outputs:
  - path: "grimoires/loa/deployment/"
    type: "directory"
    description: "Deployment documentation and runbooks"
  - path: "grimoires/loa/a2a/deployment-report.md"
    type: "file"
    description: "Deployment report for audit"

mode:
  default: "foreground"
  allow_background: true
---

# Deploy Production

## Purpose

Design and deploy production infrastructure with security-first approach. Creates IaC, CI/CD pipelines, monitoring, and comprehensive operational documentation.

## Invocation

```
/deploy-production
/deploy-production background
```

## Agent

Launches `deploying-infrastructure` from `skills/deploying-infrastructure/`.

See: `skills/deploying-infrastructure/SKILL.md` for full workflow details.

## Prerequisites

- PRD, SDD, and sprint plan created
- Sprints implemented and approved
- Security audit passed (recommended)

## Workflow

1. **Project Review**: Read PRD, SDD, sprint plan, implementation reports
2. **Requirements Clarification**: Ask about cloud, scaling, security, budget
3. **Infrastructure Design**: IaC, networking, compute, data, security
4. **Implementation**: Provision resources, configure services
5. **Deployment**: Execute with zero-downtime strategies
6. **Monitoring Setup**: Observability, alerting, dashboards
7. **Documentation**: Create runbooks and operational docs
8. **Knowledge Transfer**: Handover with critical info
9. **Analytics**: Update usage metrics (THJ users only)
10. **Feedback**: Suggest `/feedback` command

## Arguments

| Argument | Description | Required |
|----------|-------------|----------|
| `background` | Run as subagent for parallel execution | No |

## Outputs

| Path | Description |
|------|-------------|
| `grimoires/loa/deployment/infrastructure.md` | Architecture overview |
| `grimoires/loa/deployment/deployment-guide.md` | How to deploy |
| `grimoires/loa/deployment/runbooks/` | Operational procedures |
| `grimoires/loa/deployment/monitoring.md` | Dashboards, alerts |
| `grimoires/loa/deployment/security.md` | Access, secrets |
| `grimoires/loa/deployment/disaster-recovery.md` | Backup, failover |
| `grimoires/loa/a2a/deployment-report.md` | Report for audit |

## Requirements Clarification

The architect will ask about:
- **Deployment Environment**: Cloud provider, regions
- **Blockchain/Crypto**: Chains, nodes, key management
- **Scale and Performance**: Traffic, data volume, SLAs
- **Security and Compliance**: SOC 2, GDPR, secrets
- **Budget and Cost**: Constraints, optimization
- **Team and Operations**: Size, on-call, tools
- **Monitoring**: Metrics, channels, retention
- **CI/CD**: Repository, branch strategy, deployment
- **Backup and DR**: RPO/RTO, frequency, failover

## Quality Standards

- Infrastructure as Code (version controlled)
- Security (defense in depth, least privilege)
- Monitoring (comprehensive before going live)
- Automation (CI/CD fully automated)
- Documentation (complete operational docs)
- Tested (staging tested, DR validated)
- Scalable (handles expected load)
- Cost-Optimized (within budget)
- Recoverable (backups tested, DR in place)

## Error Handling

| Error | Cause | Resolution |
|-------|-------|------------|
| "PRD not found" | Missing prd.md | Run `/plan-and-analyze` first |
| "SDD not found" | Missing sdd.md | Run `/architect` first |
| "Sprint plan not found" | Missing sprint.md | Run `/sprint-plan` first |

## Feedback Loop

After deployment, run `/audit-deployment` for security review:

```
/deploy-production
      ↓
[deployment-report.md created]
      ↓
/audit-deployment
      ↓
[feedback or approval]
      ↓
If issues: fix and re-run /deploy-production
If approved: Ready for production
```

## Next Step

After deployment: `/audit-deployment` for infrastructure security audit
