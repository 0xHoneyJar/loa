# Infrastructure Documentation

**Project:** {Project Name}
**Version:** v{X.Y.Z}
**Last Updated:** {DATE}
**Author:** DevOps Crypto Architect

---

## Overview

{High-level description of the infrastructure and its purpose}

### Architecture Diagram

```
{ASCII diagram or reference to diagram file}

Example:
┌─────────────────────────────────────────────────────────────────┐
│                         Internet                                 │
└────────────────────────────┬────────────────────────────────────┘
                             │
                    ┌────────▼────────┐
                    │  CloudFlare CDN  │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │  Load Balancer   │
                    └────────┬────────┘
                             │
         ┌───────────────────┼───────────────────┐
         │                   │                   │
    ┌────▼────┐        ┌────▼────┐        ┌────▼────┐
    │  App 1  │        │  App 2  │        │  App 3  │
    └────┬────┘        └────┬────┘        └────┬────┘
         │                   │                   │
         └───────────────────┼───────────────────┘
                             │
                    ┌────────▼────────┐
                    │    Database      │
                    └─────────────────┘
```

---

## Components

### Compute

| Component | Type | Count | Specification |
|-----------|------|-------|---------------|
| {App servers} | {EC2/GCE} | {N} | {Instance type, AMI} |
| {Workers} | {EC2/GCE} | {N} | {Instance type, AMI} |

**Auto-scaling Configuration:**
- Minimum: {N}
- Maximum: {N}
- Target CPU: {%}
- Scale-up cooldown: {seconds}
- Scale-down cooldown: {seconds}

### Database

| Database | Engine | Version | Size | Multi-AZ |
|----------|--------|---------|------|----------|
| Primary | {PostgreSQL} | {15.4} | {db.t3.medium} | {Yes/No} |
| Cache | {Redis} | {7.2} | {cache.t3.micro} | {Yes/No} |

**Connection Details:**
- Primary endpoint: `{endpoint}`
- Read replica: `{endpoint}` (if applicable)
- Port: {5432}
- Max connections: {100}

### Storage

| Bucket/Volume | Type | Size | Purpose |
|---------------|------|------|---------|
| {bucket-name} | {S3/GCS} | {Size} | {Purpose} |
| {volume-name} | {EBS/PD} | {Size} | {Purpose} |

**Lifecycle Policies:**
- {Policy 1}
- {Policy 2}

### Networking

**VPC Configuration:**
- VPC CIDR: `{10.0.0.0/16}`
- Region: `{us-east-1}`

**Subnets:**
| Name | CIDR | AZ | Type |
|------|------|----|------|
| public-1 | 10.0.1.0/24 | us-east-1a | Public |
| public-2 | 10.0.2.0/24 | us-east-1b | Public |
| private-1 | 10.0.10.0/24 | us-east-1a | Private |
| private-2 | 10.0.11.0/24 | us-east-1b | Private |

**Security Groups:**
| Name | Inbound | Outbound | Purpose |
|------|---------|----------|---------|
| {sg-web} | 443/tcp from 0.0.0.0/0 | All | Web traffic |
| {sg-app} | 8080/tcp from sg-web | All | App servers |
| {sg-db} | 5432/tcp from sg-app | All | Database |

---

## Security

### Secrets Management

**Provider:** {HashiCorp Vault | AWS Secrets Manager}

**Secrets Inventory:**
| Secret | Path | Rotation | Used By |
|--------|------|----------|---------|
| DB Password | /prod/db/password | 90 days | App servers |
| API Key | /prod/api/key | Manual | Workers |

### TLS/SSL

- **Certificate Provider:** {Let's Encrypt | ACM}
- **Renewal:** {Automatic via cert-manager}
- **Domains:** {List of domains}

### IAM Roles

| Role | Attached To | Permissions |
|------|-------------|-------------|
| {app-role} | App servers | S3 read, Secrets read |
| {worker-role} | Workers | S3 read/write, SQS |

---

## CI/CD

### Pipeline Overview

```
┌─────────┐    ┌──────────┐    ┌───────────┐    ┌──────────┐
│  Push   │───▶│  Build   │───▶│  Test     │───▶│  Deploy  │
└─────────┘    └──────────┘    └───────────┘    └──────────┘
```

### Stages

1. **Build**
   - Docker image build
   - Version tagging
   - Image scanning (Trivy)

2. **Test**
   - Unit tests
   - Integration tests
   - Security scan (SAST)

3. **Deploy**
   - Push to registry
   - Update Kubernetes manifests
   - ArgoCD sync

### Deployment Configuration

- **Strategy:** {Blue-green | Canary | Rolling}
- **Rollback:** {Command or procedure}
- **Approval:** {Required for production}

---

## Monitoring

### Dashboards

| Dashboard | URL | Purpose |
|-----------|-----|---------|
| Application | {URL} | App health, requests, errors |
| Infrastructure | {URL} | CPU, memory, disk, network |
| Database | {URL} | Connections, queries, replication |

### Key Metrics

| Metric | Alert Threshold | Runbook |
|--------|-----------------|---------|
| CPU Usage | > 80% for 5m | runbooks/cpu-high.md |
| Memory Usage | > 85% for 5m | runbooks/memory-high.md |
| Error Rate | > 1% for 2m | runbooks/errors.md |
| P99 Latency | > 500ms for 5m | runbooks/latency.md |

### Log Access

```bash
# View application logs
{command to view logs}

# Search for errors
{command to search}
```

---

## Disaster Recovery

### Backup Schedule

| Component | Frequency | Retention | Location |
|-----------|-----------|-----------|----------|
| Database | Daily | 30 days | {S3 bucket} |
| Config | On change | 90 days | {Git/S3} |
| Secrets | On change | Vault | {Vault backup} |

### Recovery Procedures

1. **Database Recovery:** See `runbooks/database-restore.md`
2. **Full Recovery:** See `runbooks/disaster-recovery.md`

### RTO/RPO

- **RTO (Recovery Time Objective):** {X hours}
- **RPO (Recovery Point Objective):** {X hours}

---

## Operational Procedures

### Scaling

```bash
# Scale application
{scaling command}
```

### Deployments

```bash
# Deploy new version
{deployment command}

# Rollback
{rollback command}
```

### Maintenance

- **Maintenance Window:** {Day/Time}
- **Notification:** {Channel/procedure}

---

## Cost

### Monthly Estimate

| Service | Cost |
|---------|------|
| Compute | ${X} |
| Database | ${X} |
| Storage | ${X} |
| Network | ${X} |
| Monitoring | ${X} |
| **Total** | **${X}** |

### Cost Optimization

- Reserved instances for baseline
- Spot instances for workers
- S3 lifecycle policies
- Right-sized resources

---

## References

- **IaC Repository:** `{path/to/terraform}`
- **Application Repository:** `{path/to/app}`
- **Runbooks:** `loa-grimoire/deployment/runbooks/`
- **ADRs:** `{path/to/adrs}`

---

*Generated by DevOps Crypto Architect Agent*
