---
description: Launch the DevOps crypto architect to review the complete project, create deployment infrastructure, and implement production deployment
---

I'm launching the devops-crypto-architect agent to handle production deployment and infrastructure implementation.

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

Let me launch the agent now to begin the production deployment process.

<Task
  subagent_type="devops-crypto-architect"
  prompt="You are conducting a production deployment and infrastructure handover. The development team has completed all sprints, and the senior technical lead has approved the project for production deployment.

## Phase 1: Project Review and Context Gathering

Read ALL project documentation to understand what you're deploying:

1. **Product Requirements** (docs/prd.md):
   - Understand business goals and user needs
   - Identify critical features and priorities
   - Note compliance and security requirements

2. **System Design** (docs/sdd.md):
   - Understand technical architecture
   - Review technology stack decisions
   - Note scalability and performance requirements
   - Identify external integrations and dependencies

3. **Sprint Plans** (docs/sprint.md):
   - Review all completed sprints
   - Understand what was built
   - Note any technical debt or future considerations

4. **Implementation Reports** (docs/a2a/reviewer.md):
   - Review technical decisions made during implementation
   - Understand code structure and organization
   - Note any infrastructure considerations mentioned

5. **Codebase Review**:
   - Review actual application code
   - Identify configuration needs (environment variables, secrets)
   - Review dependencies and package manifests
   - Check for existing deployment configs (Dockerfile, docker-compose, etc.)
   - Identify database migration needs
   - Check for existing tests and how to run them

## Phase 2: Requirements Clarification

Ask the user specific questions about deployment requirements. NEVER make assumptions. Ask about:

### Deployment Environment
- **Cloud Provider**: AWS, GCP, Azure, or self-hosted?
- **Regions**: Which regions for deployment? Multi-region?
- **Environments**: Dev, staging, production? How many?
- **Domain**: What domain(s) will this use? DNS management?

### Blockchain/Crypto Specific (if applicable)
- **Chains**: Which blockchains to support? (Ethereum, Solana, Cosmos, etc.)
- **Node Infrastructure**: Deploy own nodes or use third-party providers?
- **Validator/RPC**: Need to run validators or just RPC nodes?
- **Indexers**: Need blockchain indexers? Which ones?
- **Key Management**: HSM requirements? MPC? Custody solution?

### Scale and Performance
- **Expected Traffic**: Daily active users? Requests per second?
- **Data Volume**: Database size estimates? Storage needs?
- **Geographic Distribution**: Where are users located?
- **Performance SLAs**: Required latency? Uptime guarantees?

### Security and Compliance
- **Compliance**: SOC 2, ISO 27001, GDPR, other requirements?
- **Authentication**: OAuth, SSO, custom? Provider details?
- **Secrets Management**: Vault, AWS Secrets Manager, other?
- **Audit Logging**: Requirements for audit trails?
- **Network Security**: VPN access? IP whitelisting?

### Budget and Cost
- **Budget Constraints**: Monthly infrastructure budget?
- **Cost Priorities**: Optimize for cost or performance?
- **Reserved Instances**: Long-term commitments acceptable?

### Team and Operations
- **Team Size**: How many engineers will operate this?
- **On-Call**: On-call rotation setup? Paging service?
- **Existing Tools**: Current monitoring/logging stack?
- **Access Management**: How will team access infrastructure?

### Monitoring and Alerting
- **Metrics**: What metrics are critical to monitor?
- **Alerting**: Who gets alerts? Channels (Slack, PagerDuty, email)?
- **Logging**: Retention requirements? Log analysis needs?
- **Observability**: APM requirements? Distributed tracing?

### CI/CD
- **Git Repository**: GitHub, GitLab, Bitbucket, other?
- **Branch Strategy**: GitFlow, trunk-based, other?
- **Deployment Strategy**: Rolling, blue-green, canary?
- **Approval Process**: Manual approvals required? Who approves?

### Backup and Disaster Recovery
- **RPO/RTO**: Recovery Point/Time Objectives?
- **Backup Frequency**: How often to backup data?
- **DR Region**: Disaster recovery region?
- **Failover**: Automated or manual failover?

Present 2-3 options with pros/cons when multiple valid approaches exist. Wait for user decisions before proceeding.

## Phase 3: Infrastructure Design

Based on requirements, design comprehensive infrastructure:

### Infrastructure as Code
- Choose IaC tool (Terraform recommended for multi-cloud)
- Design module structure for reusability
- Plan state management (remote backend)
- Design for multiple environments (dev, staging, prod)

### Compute Infrastructure
- Container orchestration (Kubernetes, ECS, etc.)
- Node pools/instance groups sizing
- Autoscaling policies
- Load balancing strategy

### Networking
- VPC/Network design with subnets
- Security groups/firewall rules
- CDN configuration (CloudFlare, CloudFront)
- DNS configuration

### Data Layer
- Database selection and configuration
- Read replicas for scaling
- Backup and PITR setup
- Migration strategy

### Blockchain Infrastructure (if applicable)
- Node deployment strategy
- RPC load balancing and caching
- Indexer infrastructure
- Oracle infrastructure

### Security
- Secrets management setup
- Key management (HSM/MPC if needed)
- Network security and segmentation
- TLS/SSL certificate management
- WAF and DDoS protection

### CI/CD Pipeline
- Build pipeline design
- Test automation integration
- Security scanning (containers, dependencies)
- Deployment automation
- Rollback procedures

### Monitoring and Observability
- Metrics collection (Prometheus/CloudWatch)
- Log aggregation (Loki/ELK/CloudWatch)
- Distributed tracing (Jaeger/Tempo)
- Custom dashboards (Grafana)
- Alert rules and notification channels

## Phase 4: Implementation

Implement the infrastructure systematically:

### Step 1: Foundation
- Set up IaC repository structure
- Configure remote state backend
- Create base networking (VPC, subnets, security groups)
- Set up DNS and domain configuration

### Step 2: Security Foundation
- Set up secrets management (Vault/AWS Secrets Manager)
- Configure key management (HSM if needed)
- Set up IAM roles and policies
- Configure audit logging

### Step 3: Compute and Data
- Deploy Kubernetes cluster (or compute platform)
- Deploy databases with backups
- Deploy caching layer (Redis)
- Deploy message queues (if needed)

### Step 4: Blockchain Infrastructure (if applicable)
- Deploy blockchain nodes
- Set up RPC load balancing
- Deploy indexers
- Configure monitoring for blockchain-specific metrics

### Step 5: Application Deployment
- Create Dockerfiles (if not exists)
- Create Kubernetes manifests/Helm charts
- Configure environment-specific settings
- Deploy to staging first, then production

### Step 6: CI/CD Pipeline
- Create GitHub Actions/GitLab CI pipelines
- Configure build and test stages
- Add security scanning
- Set up automated deployments
- Configure rollback procedures

### Step 7: Monitoring and Observability
- Deploy monitoring stack (Prometheus, Grafana)
- Deploy logging stack (Loki/ELK)
- Create dashboards for key metrics
- Configure alert rules
- Set up on-call rotation (PagerDuty/Opsgenie)

### Step 8: Testing and Validation
- Test deployment process end-to-end
- Run smoke tests on deployed application
- Verify monitoring and alerting
- Test disaster recovery procedures
- Load test to validate scaling

## Phase 5: Documentation and Handover

Create comprehensive operational documentation at docs/deployment/:

### 1. Infrastructure Overview (docs/deployment/infrastructure.md)
- Architecture diagram (text-based or description)
- Cloud resources inventory
- Network topology
- Security architecture
- Cost breakdown and optimization opportunities

### 2. Deployment Guide (docs/deployment/deployment-guide.md)
- How to deploy to each environment
- Deployment checklist
- Rollback procedures
- Database migration procedures
- Configuration management

### 3. Operational Runbooks (docs/deployment/runbooks/)
Create runbooks for common operations:
- **runbooks/deployment.md**: Deployment procedures
- **runbooks/rollback.md**: Rollback procedures
- **runbooks/scaling.md**: Scaling up/down
- **runbooks/incident-response.md**: Incident response
- **runbooks/backup-restore.md**: Backup and restore
- **runbooks/monitoring.md**: Monitoring and alerting guide
- **runbooks/security.md**: Security procedures

### 4. Monitoring Guide (docs/deployment/monitoring.md)
- Dashboard locations and descriptions
- Key metrics to monitor
- Alert definitions and severities
- On-call procedures
- Log analysis guide

### 5. Security Guide (docs/deployment/security.md)
- Access management procedures
- Secrets rotation procedures
- Key management procedures (HSM/MPC)
- Security incident response
- Compliance checklist

### 6. Disaster Recovery Plan (docs/deployment/disaster-recovery.md)
- RPO/RTO definitions
- Backup procedures and verification
- Disaster recovery procedures
- Failover procedures
- Post-incident recovery

### 7. Cost Optimization (docs/deployment/cost-optimization.md)
- Current cost breakdown
- Cost optimization opportunities
- Reserved instance recommendations
- Monitoring and cost alerts

### 8. Blockchain Operations (docs/deployment/blockchain-ops.md) - if applicable
- Node operations and maintenance
- RPC endpoint management
- Indexer operations
- Gas management and optimization
- Key management procedures

### 9. Troubleshooting Guide (docs/deployment/troubleshooting.md)
- Common issues and solutions
- Debug procedures
- Log analysis techniques
- Performance troubleshooting

### 10. Infrastructure as Code Documentation (docs/deployment/iac-guide.md)
- Repository structure
- How to make infrastructure changes
- How to add new environments
- State management procedures
- Module documentation

## Phase 6: Knowledge Transfer

Provide clear handover summary to the user:

### Summary Checklist
Present a checklist of what was completed:
- [ ] Infrastructure deployed and tested
- [ ] Application deployed to production
- [ ] CI/CD pipelines operational
- [ ] Monitoring and alerting configured
- [ ] Backups configured and tested
- [ ] Security hardening complete
- [ ] Documentation complete
- [ ] Team access configured
- [ ] DNS and domains configured
- [ ] Cost monitoring set up

### Critical Information
Provide:
- Production URLs and endpoints
- Dashboard URLs (Grafana, etc.)
- Repository locations (IaC, configs)
- Secrets locations (Vault, etc.)
- On-call setup status
- Cost estimates (current and projected)

### Next Steps
Recommend:
- Schedule team training sessions
- Set up regular cost reviews
- Schedule disaster recovery drills
- Plan for security audits
- Set up automated security scanning
- Review and optimize after 30 days

### Open Items
List any:
- Items that need user action
- Future optimizations to consider
- Technical debt or improvements
- Monitoring gaps to address

## Quality Standards

Your deployment must meet these standards:
- ✅ **Infrastructure as Code**: All infrastructure version controlled
- ✅ **Security**: Defense in depth, secrets management, least privilege
- ✅ **Monitoring**: Comprehensive observability before going live
- ✅ **Automation**: CI/CD pipelines fully automated
- ✅ **Documentation**: Complete operational documentation
- ✅ **Tested**: Deployment tested in staging, DR procedures validated
- ✅ **Scalable**: Can handle expected load with room to grow
- ✅ **Cost-Optimized**: Running efficiently within budget
- ✅ **Recoverable**: Backups tested, disaster recovery plan in place

## Critical Reminders

1. **Never commit secrets**: Use secrets management, never hardcode
2. **Test before production**: Deploy to staging first, always
3. **Monitor everything**: Deploy monitoring before the application
4. **Document as you go**: Don't leave documentation for the end
5. **Security first**: Defense in depth, zero-trust architecture
6. **Cost awareness**: Set up cost monitoring and alerts early
7. **Plan for failure**: Backups, disaster recovery, rollback procedures
8. **Blockchain key management**: For crypto projects, key management is life-or-death

Your mission is to take a completed application and deploy it to production with enterprise-grade infrastructure, security, monitoring, and operational procedures. The handover documentation must enable the team to operate this system confidently and independently.

Save all documentation to docs/deployment/ directory."
/>
