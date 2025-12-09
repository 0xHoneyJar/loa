---
description: Launch the paranoid auditor to audit server setup, deployment plans, and infrastructure security
---

I'm launching the paranoid cypherpunk auditor agent in **infrastructure audit mode** to review your DevOps server setup, deployment plans, and infrastructure security.

**What this command does**:
- Audits server setup scripts for security vulnerabilities
- Reviews deployment configurations and procedures
- Validates infrastructure security hardening
- Checks for secrets exposure and credential management issues
- Assesses operational runbooks for completeness
- Verifies backup and disaster recovery procedures

**Audit Scope**:
- Server setup scripts and configurations
- Deployment documentation and runbooks
- Security checklists and hardening procedures
- PM2/systemd service configurations
- Nginx/reverse proxy configurations
- SSL/TLS certificate management
- Firewall and network security rules
- Monitoring and alerting setup

The auditor will produce a comprehensive report with:
- Critical issues requiring immediate attention
- High/medium/low priority findings
- Security checklist status
- Infrastructure threat model
- Actionable remediation steps

<Task
  subagent_type="paranoid-auditor"
  prompt="You are performing a **DevOps Infrastructure Security Audit** for the agentic-base project. This is a specialized audit focusing on server setup, deployment plans, and infrastructure security.

## Audit Context

The user has prepared server setup documentation and deployment scripts for deploying the DevRel integration application to a bare metal/VPS server. Your mission is to audit this infrastructure work before production deployment.

## Scope of Audit

### 1. Server Setup Scripts
Review all scripts in `docs/deployment/scripts/` (if they exist):
- `01-initial-setup.sh` - Initial server configuration
- `02-security-hardening.sh` - Security hardening
- `03-install-dependencies.sh` - Dependency installation
- `04-deploy-app.sh` - Application deployment
- `05-setup-monitoring.sh` - Monitoring setup
- `06-setup-ssl.sh` - SSL/domain configuration

For each script, check:
- Command injection vulnerabilities
- Hardcoded secrets or credentials
- Insecure file permissions
- Missing error handling
- Unsafe sudo usage
- Unvalidated user input
- Insecure package sources
- Missing idempotency

### 2. Deployment Documentation
Review all docs in `docs/deployment/`:
- `server-setup-guide.md` - Setup instructions
- `runbooks/server-operations.md` - Operational procedures
- `security-checklist.md` - Security verification
- `verification-checklist.md` - Deployment verification
- `quick-reference.md` - Quick reference card
- `DEPLOYMENT-INFRASTRUCTURE-COMPLETE.md` - Infrastructure overview
- `integration-layer-handover.md` - Handover documentation

Check for:
- Missing security steps
- Incomplete procedures
- Dangerous recommendations
- Missing backup/recovery procedures
- Unclear rollback instructions
- Missing incident response procedures

### 3. Service Configurations
Review configuration files:
- PM2 ecosystem config (`devrel-integration/ecosystem.config.js`)
- systemd service files (`docs/deployment/*.service`)
- nginx configurations (`docs/deployment/nginx/*.conf`)
- Environment templates (`.env.local.example`)

Check for:
- Running as root (should be non-root user)
- Overly permissive file permissions
- Missing resource limits
- Insecure environment variable handling
- Weak TLS configurations
- Missing security headers
- Open proxy vulnerabilities

### 4. Security Hardening
Verify security measures:
- SSH hardening (key-only auth, no root login)
- Firewall configuration (UFW rules)
- fail2ban configuration
- Automatic security updates
- Audit logging configuration
- sysctl security parameters

### 5. Secrets Management
Audit credential handling:
- How are secrets stored?
- How are secrets deployed to the server?
- Are secrets in git history?
- Is there a rotation procedure?
- Are secrets encrypted at rest?
- What happens if secrets leak?

### 6. Network Security
Review network configuration:
- What ports are exposed?
- Are there IP restrictions?
- Is there a reverse proxy?
- Is TLS properly configured?
- Are internal services exposed externally?
- Is there protection against DDoS?

### 7. Monitoring & Observability
Assess monitoring setup:
- Are critical metrics monitored?
- Are there alerts for anomalies?
- Are logs centralized?
- Is there audit trail for access?
- Can security incidents be detected?
- Is there a status page?

### 8. Backup & Recovery
Verify disaster recovery:
- Are configurations backed up?
- Is there a tested restore procedure?
- What's the Recovery Time Objective?
- What's the Recovery Point Objective?
- Are backups encrypted?
- Are backups stored off-site?

## Audit Methodology

1. **Read all deployment documentation** in `docs/deployment/`
2. **Read all setup scripts** in `docs/deployment/scripts/` (if present)
3. **Read service configurations** (PM2, systemd, nginx)
4. **Read the devrel-integration source** for deployment-relevant code
5. **Cross-reference with security checklists**
6. **Identify gaps and vulnerabilities**
7. **Produce comprehensive audit report**

## Files to Read

Start by reading these files to understand the infrastructure:
1. `docs/deployment/server-setup-guide.md`
2. `docs/deployment/security-checklist.md`
3. `docs/deployment/verification-checklist.md`
4. `docs/deployment/runbooks/server-operations.md`
5. `docs/deployment/quick-reference.md`
6. `docs/deployment/DEPLOYMENT-INFRASTRUCTURE-COMPLETE.md`
7. `devrel-integration/ecosystem.config.js` (if exists)
8. Any `.service` files in `docs/deployment/`
9. Any nginx configs in `docs/deployment/nginx/`
10. `devrel-integration/secrets/.env.local.example` (if exists)

## Special Focus Areas

Pay extra attention to:

1. **Server Access Security**
   - Is SSH properly hardened?
   - Are there backdoor accounts?
   - Is sudo usage appropriate?

2. **Application Isolation**
   - Is the app running as non-root?
   - Are there container boundaries?
   - Can the app access system resources it shouldn't?

3. **Secrets in Scripts**
   - Any hardcoded tokens, passwords, or API keys?
   - Are environment files handled securely?
   - Can secrets be extracted from process listings?

4. **Network Exposure**
   - What's publicly accessible?
   - Are debug endpoints exposed?
   - Can internal services be reached externally?

5. **Update Procedures**
   - Is there a secure update path?
   - Can updates be rolled back?
   - Are dependencies updated regularly?

6. **Incident Response**
   - What happens if server is compromised?
   - How quickly can access be revoked?
   - Is there forensic logging?

## Report Structure

Produce an audit report saved to `DEPLOYMENT-SECURITY-AUDIT.md` with:

### Required Sections

1. **Executive Summary**
   - Overall risk assessment
   - Key findings summary
   - Deployment readiness verdict

2. **Critical Issues** (Must fix before deployment)
   - Any immediate security risks
   - Vulnerabilities that could lead to compromise

3. **High Priority Issues** (Should fix before production)
   - Significant security gaps
   - Missing hardening measures

4. **Medium Priority Issues** (Fix soon after deployment)
   - Configuration improvements
   - Missing best practices

5. **Low Priority Issues** (Technical debt)
   - Minor improvements
   - Nice-to-have enhancements

6. **Infrastructure Security Checklist**
   ```
   ### Server Security
   - [✅/❌] SSH key-only authentication
   - [✅/❌] Root login disabled
   - [✅/❌] fail2ban configured
   - [✅/❌] Firewall enabled with deny-by-default
   - [✅/❌] Automatic security updates
   - [✅/❌] Audit logging enabled

   ### Application Security
   - [✅/❌] Running as non-root user
   - [✅/❌] Resource limits configured
   - [✅/❌] Secrets not in scripts
   - [✅/❌] Environment file secured
   - [✅/❌] Logs don't expose secrets

   ### Network Security
   - [✅/❌] TLS 1.2+ only
   - [✅/❌] Strong cipher suites
   - [✅/❌] HTTPS redirect
   - [✅/❌] Security headers set
   - [✅/❌] Internal ports not exposed

   ### Operational Security
   - [✅/❌] Backup procedure documented
   - [✅/❌] Recovery tested
   - [✅/❌] Secret rotation documented
   - [✅/❌] Incident response plan
   - [✅/❌] Access revocation procedure
   ```

7. **Threat Model**
   - Trust boundaries
   - Attack vectors
   - Blast radius analysis
   - Residual risks

8. **Recommendations**
   - Immediate actions (before deployment)
   - Short-term improvements (after deployment)
   - Long-term infrastructure roadmap

9. **Positive Findings**
   - What was done well
   - Good security practices observed

## Audit Standards

Apply these standards during your review:

- **CIS Benchmarks** for Linux server hardening
- **OWASP** for application security
- **NIST 800-53** for security controls
- **SOC 2** operational security requirements
- **12-Factor App** deployment principles

## Your Mission

Be paranoid. Assume:
- Every script will be run by someone who doesn't read comments
- Every config file might be copied to other servers
- Every secret might accidentally be committed
- Every port might be scanned by attackers
- Every update might break something

Find the vulnerabilities before attackers do. The team needs honest assessment of infrastructure security before going to production.

**Begin your systematic infrastructure audit now.**"
/>
