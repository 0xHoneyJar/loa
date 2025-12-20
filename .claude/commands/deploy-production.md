---
description: Launch the DevOps crypto architect to review the complete project, create deployment infrastructure, and implement production deployment
args: [background]
---

I'm launching the devops-crypto-architect agent to handle production deployment and infrastructure implementation.

**Execution Mode**: {{ "background - use /tasks to monitor" if "background" in $ARGUMENTS else "foreground (default)" }}

## Pre-flight Check: Setup Verification

Before proceeding, verify that Loa setup is complete:

1. Check if `.loa-setup-complete` marker file exists in the project root
2. If the marker file **does NOT exist**:
   - Display this message:
     ```
     Loa setup has not been completed for this project.

     Please run `/setup` first to:
     - Configure MCP integrations
     - Initialize project analytics

     After setup is complete, run `/deploy-production` again.
     ```
   - **STOP** - Do not proceed with deployment
3. If the marker file **exists**, proceed with the deployment process

---

**Prerequisites** (verified before deployment):
- ✅ All sprints completed and approved by senior technical lead
- ✅ All acceptance criteria met
- ✅ Code quality validated
- ✅ Security audit passed
- ✅ Tests passing
- ✅ Documentation complete

The DevOps architect will:
1. **Review project documentation**: PRD, SDD, sprint plans, implementation reports
2. **Assess current state**: Review codebase, dependencies, configuration
3. **Design infrastructure**: Cloud resources, Kubernetes, blockchain nodes, security architecture
4. **Clarify requirements**: Ask about deployment targets, scaling needs, budget, compliance
5. **Create deployment plan**: Infrastructure as Code, CI/CD pipelines, monitoring
6. **Implement infrastructure**: Provision resources, configure services, set up pipelines
7. **Deploy application**: Execute deployment with zero-downtime strategies
8. **Set up monitoring**: Observability, alerting, logging, blockchain-specific metrics
9. **Generate handover documentation**: Runbooks, architecture diagrams, operational procedures
10. **Conduct knowledge transfer**: Document operational procedures and train team

The deployment architect will create:
- Infrastructure as Code (Terraform/Pulumi)
- CI/CD pipelines (GitHub Actions/GitLab CI)
- Kubernetes manifests and Helm charts
- Monitoring and alerting configuration
- Security hardening and secrets management
- Deployment runbooks and operational documentation
- Disaster recovery procedures
- Cost optimization strategies

{{ if "background" in $ARGUMENTS }}
Running in background mode. Use `/tasks` to monitor progress.

<Task
  subagent_type="devops-crypto-architect"
  prompt="You are conducting a production deployment and infrastructure handover. The development team has completed all sprints, and the senior technical lead has approved the project for production deployment.

## Phase 1: Project Review

Read ALL project documentation:
1. `loa-grimoire/prd.md` - Product requirements
2. `loa-grimoire/sdd.md` - System design
3. `loa-grimoire/sprint.md` - Completed sprints
4. `loa-grimoire/a2a/reviewer.md` - Implementation reports
5. Codebase review - Identify config needs, dependencies, existing deployment configs

## Phase 2: Requirements Clarification

Ask specific questions about:
- **Deployment Environment**: Cloud provider, regions, environments
- **Blockchain/Crypto** (if applicable): Chains, node infrastructure, key management
- **Scale and Performance**: Traffic, data volume, SLAs
- **Security and Compliance**: SOC 2, GDPR, secrets management
- **Budget and Cost**: Constraints, optimization priorities
- **Team and Operations**: Size, on-call, existing tools
- **Monitoring and Alerting**: Metrics, channels, retention
- **CI/CD**: Git repository, branch strategy, deployment strategy
- **Backup and DR**: RPO/RTO, backup frequency, failover

Present 2-3 options with pros/cons when multiple valid approaches exist.

## Phase 3: Infrastructure Design

Design comprehensive infrastructure:
- **IaC**: Terraform module structure, state management
- **Compute**: Container orchestration, autoscaling
- **Networking**: VPC, security groups, CDN, DNS
- **Data Layer**: Database, replicas, backups
- **Security**: Secrets management, key management, TLS
- **CI/CD**: Build, test, security scanning, deployment automation
- **Monitoring**: Metrics, logs, tracing, dashboards, alerts

## Phase 4: Implementation

Implement systematically:
1. Foundation (IaC repo, state backend, networking, DNS)
2. Security Foundation (secrets, IAM, audit logging)
3. Compute and Data (Kubernetes, databases, caching)
4. Blockchain Infrastructure (if applicable)
5. Application Deployment (Dockerfiles, K8s manifests, environment config)
6. CI/CD Pipeline (build, test, scan, deploy)
7. Monitoring and Observability (stack, dashboards, alerts)
8. Testing and Validation (E2E, smoke tests, DR validation, load testing)

## Phase 5: Documentation

Create comprehensive docs at `loa-grimoire/deployment/`:
1. `infrastructure.md` - Architecture overview
2. `deployment-guide.md` - How to deploy
3. `runbooks/` - Deployment, rollback, scaling, incidents, backups, monitoring, security
4. `monitoring.md` - Dashboards, metrics, alerts, on-call
5. `security.md` - Access, secrets rotation, key management
6. `disaster-recovery.md` - RPO/RTO, backups, failover
7. `cost-optimization.md` - Breakdown, opportunities
8. `troubleshooting.md` - Common issues, debug procedures
9. `iac-guide.md` - Repo structure, making changes

## Phase 6: Knowledge Transfer

Provide handover:
- Summary checklist of completed items
- Critical info (URLs, dashboards, repos, secrets locations)
- Next steps (training, cost reviews, DR drills, security audits)
- Open items requiring user action

## Quality Standards

- ✅ Infrastructure as Code (version controlled)
- ✅ Security (defense in depth, least privilege)
- ✅ Monitoring (comprehensive before going live)
- ✅ Automation (CI/CD fully automated)
- ✅ Documentation (complete operational docs)
- ✅ Tested (staging tested, DR validated)
- ✅ Scalable (handles expected load)
- ✅ Cost-Optimized (within budget)
- ✅ Recoverable (backups tested, DR in place)

Save all documentation to `loa-grimoire/deployment/`.

## Phase 7: Analytics Update (NON-BLOCKING)

After deployment is complete, update analytics:

1. Read and validate loa-grimoire/analytics/usage.json
2. Add deployment entry to `deployments` array with:
   - `completed_at`: current ISO timestamp
   - `success`: true
3. Increment `totals.commands_executed`
4. Regenerate loa-grimoire/analytics/summary.md

Use safe jq patterns with --arg for variable injection:
```bash
TIMESTAMP=$(date -u +\"%Y-%m-%dT%H:%M:%SZ\")

jq --arg ts \"$TIMESTAMP\" '
  .deployments += [{
    \"completed_at\": $ts,
    \"success\": true
  }] |
  .totals.commands_executed += 1
' loa-grimoire/analytics/usage.json > loa-grimoire/analytics/usage.json.tmp && \
mv loa-grimoire/analytics/usage.json.tmp loa-grimoire/analytics/usage.json
```

Analytics updates are NON-BLOCKING - if they fail, log a warning but complete the deployment process.

## Phase 8: Feedback Suggestion

After successful deployment, display this message:

```
---

## Help Improve Loa!

Your feedback helps improve Loa for everyone. Now that you've completed your project,
we'd love to hear about your experience.

Run `/feedback` to:
- Rate your experience with Loa agents
- Share what worked well
- Suggest improvements
- Help us prioritize features

Your feedback is submitted to the Loa Feedback project in Linear and helps us
make the framework better for all developers.

---
```"
/>
{{ else }}
Let me begin the production deployment process.

You are conducting a production deployment and infrastructure handover. The development team has completed all sprints, and the senior technical lead has approved the project for production deployment.

## Phase 1: Project Review

Read ALL project documentation:
1. `loa-grimoire/prd.md` - Product requirements
2. `loa-grimoire/sdd.md` - System design
3. `loa-grimoire/sprint.md` - Completed sprints
4. `loa-grimoire/a2a/reviewer.md` - Implementation reports
5. Codebase review - Identify config needs, dependencies, existing deployment configs

## Phase 2: Requirements Clarification

Ask specific questions about:
- **Deployment Environment**: Cloud provider, regions, environments
- **Blockchain/Crypto** (if applicable): Chains, node infrastructure, key management
- **Scale and Performance**: Traffic, data volume, SLAs
- **Security and Compliance**: SOC 2, GDPR, secrets management
- **Budget and Cost**: Constraints, optimization priorities
- **Team and Operations**: Size, on-call, existing tools
- **Monitoring and Alerting**: Metrics, channels, retention
- **CI/CD**: Git repository, branch strategy, deployment strategy
- **Backup and DR**: RPO/RTO, backup frequency, failover

Present 2-3 options with pros/cons when multiple valid approaches exist.

## Phase 3: Infrastructure Design

Design comprehensive infrastructure:
- **IaC**: Terraform module structure, state management
- **Compute**: Container orchestration, autoscaling
- **Networking**: VPC, security groups, CDN, DNS
- **Data Layer**: Database, replicas, backups
- **Security**: Secrets management, key management, TLS
- **CI/CD**: Build, test, security scanning, deployment automation
- **Monitoring**: Metrics, logs, tracing, dashboards, alerts

## Phase 4: Implementation

Implement systematically:
1. Foundation (IaC repo, state backend, networking, DNS)
2. Security Foundation (secrets, IAM, audit logging)
3. Compute and Data (Kubernetes, databases, caching)
4. Blockchain Infrastructure (if applicable)
5. Application Deployment (Dockerfiles, K8s manifests, environment config)
6. CI/CD Pipeline (build, test, scan, deploy)
7. Monitoring and Observability (stack, dashboards, alerts)
8. Testing and Validation (E2E, smoke tests, DR validation, load testing)

## Phase 5: Documentation

Create comprehensive docs at `loa-grimoire/deployment/`:
1. `infrastructure.md` - Architecture overview
2. `deployment-guide.md` - How to deploy
3. `runbooks/` - Deployment, rollback, scaling, incidents, backups, monitoring, security
4. `monitoring.md` - Dashboards, metrics, alerts, on-call
5. `security.md` - Access, secrets rotation, key management
6. `disaster-recovery.md` - RPO/RTO, backups, failover
7. `cost-optimization.md` - Breakdown, opportunities
8. `troubleshooting.md` - Common issues, debug procedures
9. `iac-guide.md` - Repo structure, making changes

## Phase 6: Knowledge Transfer

Provide handover:
- Summary checklist of completed items
- Critical info (URLs, dashboards, repos, secrets locations)
- Next steps (training, cost reviews, DR drills, security audits)
- Open items requiring user action

## Quality Standards

- ✅ Infrastructure as Code (version controlled)
- ✅ Security (defense in depth, least privilege)
- ✅ Monitoring (comprehensive before going live)
- ✅ Automation (CI/CD fully automated)
- ✅ Documentation (complete operational docs)
- ✅ Tested (staging tested, DR validated)
- ✅ Scalable (handles expected load)
- ✅ Cost-Optimized (within budget)
- ✅ Recoverable (backups tested, DR in place)

Save all documentation to `loa-grimoire/deployment/`.

## Phase 7: Analytics Update (NON-BLOCKING)

After deployment is complete, update analytics:

1. Read and validate loa-grimoire/analytics/usage.json
2. Add deployment entry to `deployments` array with:
   - `completed_at`: current ISO timestamp
   - `success`: true
3. Increment `totals.commands_executed`
4. Regenerate loa-grimoire/analytics/summary.md

Use safe jq patterns with --arg for variable injection:
```bash
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

jq --arg ts "$TIMESTAMP" '
  .deployments += [{
    "completed_at": $ts,
    "success": true
  }] |
  .totals.commands_executed += 1
' loa-grimoire/analytics/usage.json > loa-grimoire/analytics/usage.json.tmp && \
mv loa-grimoire/analytics/usage.json.tmp loa-grimoire/analytics/usage.json
```

Then regenerate summary.md with updated values.

Analytics updates are NON-BLOCKING - if they fail, log a warning but complete the deployment process.

## Phase 8: Feedback Suggestion

After successful deployment, display this message:

```
---

## Help Improve Loa!

Your feedback helps improve Loa for everyone. Now that you've completed your project,
we'd love to hear about your experience.

Run `/feedback` to:
- Rate your experience with Loa agents
- Share what worked well
- Suggest improvements
- Help us prioritize features

Your feedback is submitted to the Loa Feedback project in Linear and helps us
make the framework better for all developers.

---
```
{{ endif }}
