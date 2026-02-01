# DevOps Crypto Architect Reference

## Infrastructure as Code Checklist

### Terraform Best Practices
- [ ] Use modules for reusable components
- [ ] Separate environments with workspaces or directories
- [ ] Use remote state (S3, GCS, Terraform Cloud)
- [ ] Enable state locking (DynamoDB for AWS)
- [ ] Use variables for all configurable values
- [ ] Pin provider versions (`~> 5.0` constraints)
- [ ] Use data sources for existing resources
- [ ] Implement proper tagging strategy
- [ ] Use locals for computed values
- [ ] Document all modules with README
- [ ] Run `terraform fmt` before commit
- [ ] Run `terraform validate` in CI

### Docker Best Practices
- [ ] Use official base images
- [ ] Pin image versions (not `latest`)
- [ ] Multi-stage builds to minimize size
- [ ] Run as non-root user
- [ ] Use `.dockerignore`
- [ ] One process per container
- [ ] Use COPY instead of ADD
- [ ] Set proper health checks
- [ ] Don't store secrets in images
- [ ] Scan images for vulnerabilities (Trivy)
- [ ] Sign images (Cosign/Sigstore)

### Kubernetes Best Practices
- [ ] Use namespaces for isolation
- [ ] Set resource requests and limits
- [ ] Use liveness and readiness probes
- [ ] Configure pod disruption budgets
- [ ] Use network policies
- [ ] Enable RBAC
- [ ] Use secrets for sensitive data
- [ ] Set security contexts (non-root, read-only fs)
- [ ] Use horizontal pod autoscaling
- [ ] Configure pod anti-affinity
- [ ] Use node selectors/taints for placement

## Security Hardening Checklist

### Secrets Management
- [ ] No hardcoded secrets in code
- [ ] No secrets in environment variables (prefer mounted secrets)
- [ ] Use external secrets manager (Vault, AWS SM, GCP SM)
- [ ] Secrets encrypted at rest
- [ ] Secret rotation policy defined
- [ ] Secrets access logged
- [ ] Least privilege access to secrets
- [ ] Secrets backup procedure documented
- [ ] Development secrets separate from production

### Network Security
- [ ] VPC with private subnets
- [ ] Security groups with minimal rules
- [ ] Network ACLs as secondary defense
- [ ] No public IPs on application servers
- [ ] Load balancer in public subnet only
- [ ] NAT Gateway for outbound traffic
- [ ] VPN or bastion for SSH access
- [ ] TLS 1.3 for all connections
- [ ] mTLS for service-to-service
- [ ] DDoS protection (CloudFlare, AWS Shield)
- [ ] WAF rules configured
- [ ] Rate limiting on APIs

### Identity & Access Management
- [ ] No root/admin account usage
- [ ] MFA enabled for all humans
- [ ] Service accounts for applications
- [ ] Least privilege principle
- [ ] Role-based access control
- [ ] Regular access reviews
- [ ] Access logging enabled
- [ ] Time-limited credentials
- [ ] No shared accounts
- [ ] Federated identity where possible

### Container Security
- [ ] Images from trusted registries
- [ ] Image vulnerability scanning
- [ ] No root containers
- [ ] Read-only root filesystem
- [ ] Dropped capabilities
- [ ] Seccomp profiles enabled
- [ ] AppArmor/SELinux policies
- [ ] Runtime security monitoring (Falco)
- [ ] Image signing and verification
- [ ] Registry access controls

### Key Management (Blockchain)
- [ ] HSM for production keys
- [ ] MPC for high-value wallets
- [ ] Key derivation documented (BIP32/39/44)
- [ ] Multi-sig where appropriate
- [ ] Key rotation procedures
- [ ] Cold storage for reserves
- [ ] Air-gapped signing for critical ops
- [ ] Key backup and recovery tested
- [ ] Access control for key operations
- [ ] Audit logging for key usage

## CI/CD Security Checklist

### Pipeline Security
- [ ] Secrets not in pipeline logs
- [ ] Pipeline-as-code version controlled
- [ ] Branch protection rules
- [ ] Required reviews for merges
- [ ] Status checks required
- [ ] Signed commits
- [ ] Dependency scanning (Dependabot, Snyk)
- [ ] SAST scanning (Semgrep, CodeQL)
- [ ] Container scanning
- [ ] License compliance checking

### Deployment Security
- [ ] Deployment approval gates
- [ ] Production deployments logged
- [ ] Rollback procedures tested
- [ ] Feature flags for gradual rollout
- [ ] Canary deployments enabled
- [ ] Zero-downtime deployments
- [ ] Deployment notifications
- [ ] Post-deployment verification
- [ ] Artifact signing

## Monitoring & Observability Checklist

### Metrics
- [ ] Application metrics exposed
- [ ] Infrastructure metrics collected
- [ ] Custom business metrics
- [ ] Prometheus scraping configured
- [ ] Long-term storage (Thanos/Cortex)
- [ ] Dashboard for each service
- [ ] SLI/SLO metrics defined
- [ ] Cardinality limits set

### Logging
- [ ] Structured logging (JSON)
- [ ] Log levels properly used
- [ ] No sensitive data in logs
- [ ] Centralized log aggregation
- [ ] Log retention policy
- [ ] Log access controls
- [ ] Searchable and filterable
- [ ] Correlation IDs for tracing

### Alerting
- [ ] Critical alerts for data loss risk
- [ ] High alerts for service impact
- [ ] Warning alerts for degradation
- [ ] Alert fatigue prevention
- [ ] Runbook linked to each alert
- [ ] On-call rotation defined
- [ ] Escalation paths documented
- [ ] Alert testing/validation

### Tracing
- [ ] Distributed tracing enabled
- [ ] Trace sampling configured
- [ ] Cross-service correlation
- [ ] Performance baselines established
- [ ] Critical paths identified

## Blockchain Infrastructure Checklist

### Node Operations
- [ ] Node diversity (multiple clients)
- [ ] Archive node for historical data
- [ ] Light nodes for low-latency queries
- [ ] Sync status monitoring
- [ ] Peer count monitoring
- [ ] Disk space alerts
- [ ] Memory usage monitoring
- [ ] Chain reorganization alerts
- [ ] Version upgrade procedures

### Validator Operations
- [ ] Slashing protection database
- [ ] Redundant beacon node connections
- [ ] Key backup procedures
- [ ] Missed attestation alerts
- [ ] Proposal tracking
- [ ] Sync committee monitoring
- [ ] Validator effectiveness metrics
- [ ] Exit procedures documented

### RPC Infrastructure
- [ ] Load balancing across nodes
- [ ] Rate limiting per client
- [ ] Request caching (Redis)
- [ ] WebSocket support
- [ ] Health checks for routing
- [ ] Request logging
- [ ] Error rate monitoring
- [ ] Latency percentiles

### Smart Contract Deployment
- [ ] Deployment scripts tested
- [ ] Gas estimation accurate
- [ ] Nonce management
- [ ] Multi-chain coordination
- [ ] Contract verification automated
- [ ] Upgrade procedures documented
- [ ] Proxy patterns if upgradeable
- [ ] Time-locked admin functions

## Disaster Recovery Checklist

### Backup Strategy
- [ ] Automated backup schedule
- [ ] Multiple backup locations
- [ ] Cross-region replication
- [ ] Backup encryption
- [ ] Backup integrity verification
- [ ] Point-in-time recovery capability
- [ ] Restore testing (quarterly minimum)
- [ ] Backup retention policy

### High Availability
- [ ] Multi-AZ deployment
- [ ] Auto-scaling configured
- [ ] Health checks active
- [ ] Automatic failover
- [ ] DNS failover configured
- [ ] Load balancer redundancy
- [ ] Database replication
- [ ] Stateless application design

### Incident Response
- [ ] Incident severity definitions
- [ ] On-call rotation schedule
- [ ] Communication channels defined
- [ ] Status page configured
- [ ] Post-mortem template
- [ ] Runbooks for common incidents
- [ ] Escalation procedures
- [ ] Customer communication templates

## Cost Optimization Checklist

### Compute
- [ ] Right-sized instances
- [ ] Reserved instances for baseline
- [ ] Spot instances for batch jobs
- [ ] Auto-scaling policies tuned
- [ ] Idle resource cleanup
- [ ] Development environment scheduling

### Storage
- [ ] Lifecycle policies configured
- [ ] Appropriate storage classes
- [ ] Unused volume cleanup
- [ ] Snapshot retention policy
- [ ] Data compression enabled

### Network
- [ ] Data transfer optimization
- [ ] CDN for static assets
- [ ] VPC endpoint for AWS services
- [ ] NAT gateway optimization
- [ ] Cross-region transfer minimization

### Monitoring
- [ ] Cost allocation tags
- [ ] Budget alerts
- [ ] Cost anomaly detection
- [ ] Regular cost reviews
- [ ] Reserved capacity planning

## Version Management Checklist

### Semantic Versioning
- [ ] MAJOR for breaking changes
- [ ] MINOR for new features
- [ ] PATCH for bug fixes
- [ ] Pre-release suffixes (-rc.1, -beta.1)
- [ ] Build metadata when needed

### Release Process
- [ ] CHANGELOG.md updated
- [ ] Version in package.json updated
- [ ] Git tag created (vX.Y.Z)
- [ ] GitHub release created
- [ ] Release notes written
- [ ] Migration guide if breaking
- [ ] Documentation updated

## Red Flags & Anti-Patterns

### Security Anti-Patterns
- Private keys in code or env vars
- Overly permissive IAM roles
- Secrets in Git repositories
- Missing rate limiting
- Running as root
- Unencrypted data at rest
- Public S3 buckets
- Default credentials

### Operational Anti-Patterns
- Manual server configuration
- Lack of monitoring
- No backup/DR plan
- Single points of failure
- Ignoring cost optimization
- No runbooks
- Alert fatigue
- Undocumented changes

### Blockchain Anti-Patterns
- Single RPC provider
- Unmonitored validator
- Hot wallet key exposure
- Ignoring MEV
- Centralized infrastructure
- No slashing protection
- Missing nonce management
- Unverified contracts

## Technology Quick Reference

### Instance Sizing Guide

| Workload | AWS | GCP | Azure |
|----------|-----|-----|-------|
| Light API | t3.small | e2-small | B1s |
| Medium API | t3.medium | e2-medium | B2s |
| Heavy API | c5.large | c2-standard-4 | D2s v3 |
| Database | r5.large | n2-highmem-4 | E4s v3 |
| Blockchain Node | i3.xlarge | n2-standard-8 | L8s v2 |
| Validator | c5.xlarge | c2-standard-8 | F8s v2 |

### Port Reference

| Service | Port | Protocol |
|---------|------|----------|
| SSH | 22 | TCP |
| HTTP | 80 | TCP |
| HTTPS | 443 | TCP |
| PostgreSQL | 5432 | TCP |
| Redis | 6379 | TCP |
| Prometheus | 9090 | TCP |
| Grafana | 3000 | TCP |
| Ethereum P2P | 30303 | TCP/UDP |
| Ethereum RPC | 8545 | TCP |
| Ethereum WS | 8546 | TCP |
| Solana P2P | 8000-8020 | UDP |
| Solana RPC | 8899 | TCP |

### Common Terraform Modules

| Purpose | Module |
|---------|--------|
| AWS VPC | terraform-aws-modules/vpc/aws |
| AWS EKS | terraform-aws-modules/eks/aws |
| AWS RDS | terraform-aws-modules/rds/aws |
| AWS S3 | terraform-aws-modules/s3-bucket/aws |
| AWS ALB | terraform-aws-modules/alb/aws |
