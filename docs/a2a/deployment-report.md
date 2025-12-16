# Deployment Report: Onomancer Bot Production Infrastructure

**Date**: December 16, 2025
**DevOps Architect**: DevOps Crypto Architect Agent
**Target Environment**: OVH Bare Metal VPS (Single Server MVP)
**Status**: INFRASTRUCTURE READY - AUDIT FIXES APPLIED

---

## Executive Summary

This report documents the comprehensive production deployment infrastructure created for the Onomancer Bot. The infrastructure builds upon the December 15, 2024 prototype deployment experience and lessons learned, providing a complete set of scripts, configurations, and runbooks for reliable production operation.

---

## Security Audit Fixes (December 16, 2025)

The following issues identified by the paranoid-auditor security audit have been addressed:

| Finding | Severity | Fix Applied |
|---------|----------|-------------|
| HIGH-001: Missing SSH hardening | HIGH | ✅ Added STEP 5.5 to server-setup.sh with password auth disable, root login disable, key-based auth enforcement |
| HIGH-002: Directory path inconsistency | HIGH | ✅ Separated BASE_DIR and APP_DIR in all scripts (deploy.sh, rollback.sh) with clear comments |
| MEDIUM-003: PM2 env_file unreliable | MEDIUM | ✅ Removed env_file from generated ecosystem.config.js, added comment documenting Dec 15 known issue |

**SSH Hardening Details** (server-setup.sh STEP 5.5):
- Creates `.ssh` directory for devrel user with proper permissions (700)
- Safety check: Only hardens if SSH keys exist (prevents lockout)
- Disables: PasswordAuthentication, ChallengeResponseAuthentication, UsePAM
- Enables: PubkeyAuthentication
- Disables: PermitRootLogin
- Provides manual hardening instructions if keys not yet configured
- Uses Ubuntu-correct `ssh` service name (not `sshd`)

**Directory Structure Clarification**:
```
BASE_DIR="/opt/devrel-integration"          # Root installation directory
APP_DIR="$BASE_DIR/devrel-integration"      # Cloned repo (app code)
SECRETS_DIR="$BASE_DIR/secrets"             # Credentials (chmod 700)
DATA_DIR="$BASE_DIR/data"                   # SQLite database
BACKUP_DIR="$BASE_DIR/backups"              # Database backups
PM2_HOME="$BASE_DIR/.pm2"                   # PM2 process manager home
```

---

## Previous Deployment Lessons (December 15, 2024)

The following fixes from the prototype deployment have been incorporated:

| Issue | Root Cause | Status |
|-------|------------|--------|
| Token validation too strict | Regex patterns | ✅ Fixed in codebase |
| Missing schema.sql in dist | TypeScript doesn't copy SQL | ✅ postbuild script added |
| DOC_ROOT path incorrect | Path resolution | ✅ Fixed in codebase |
| folder-ids.json missing | Template not in repo | ✅ Documented in guide |
| PM2 env loading | env_file unreliable | ✅ Deploy script handles |
| SSH service name | Ubuntu uses `ssh` not `sshd` | ✅ Documented |

---

## Infrastructure Deliverables

### Scripts Created

| Script | Purpose | Location |
|--------|---------|----------|
| `server-setup.sh` | Initial server configuration | `devrel-integration/docs/deployment/scripts/` |
| `deploy.sh` | Application deployment | `devrel-integration/docs/deployment/scripts/` |
| `rollback.sh` | Version rollback | `devrel-integration/docs/deployment/scripts/` |
| `nginx-onomancer.conf` | Nginx configuration | `devrel-integration/docs/deployment/scripts/` |

### Documentation Created

| Document | Purpose | Location |
|----------|---------|----------|
| `infrastructure.md` | Architecture overview | `devrel-integration/docs/deployment/` |
| `deployment-guide.md` | Step-by-step deployment | `devrel-integration/docs/deployment/` |
| `monitoring.md` | Monitoring setup | `devrel-integration/docs/deployment/` |
| `deployment-runbook.md` | Deployment procedures | `devrel-integration/docs/deployment/runbooks/` |
| `incident-response.md` | Incident handling | `devrel-integration/docs/deployment/runbooks/` |
| `backup-restore.md` | Backup & restore | `devrel-integration/docs/deployment/runbooks/` |

### Configuration Updated

| File | Changes | Location |
|------|---------|----------|
| `ecosystem.config.js` | Production-ready PM2 config | `devrel-integration/` |

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     OVH VPS Server                           │
│                   (Ubuntu 22.04 LTS)                         │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                   Nginx                              │   │
│  │         (Reverse Proxy + TLS Termination)            │   │
│  │               SSL via Let's Encrypt                  │   │
│  └────────────────────────┬────────────────────────────┘   │
│                           │ :3000                           │
│  ┌────────────────────────▼────────────────────────────┐   │
│  │                   PM2 Process Manager                │   │
│  │  ┌──────────────────────────────────────────────┐   │   │
│  │  │            Onomancer Bot (Node.js)            │   │   │
│  │  └──────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                    Data Layer                         │   │
│  │  ┌─────────────────┐    ┌─────────────────────────┐ │   │
│  │  │  SQLite DB      │    │  Redis (Optional)       │ │   │
│  │  └─────────────────┘    └─────────────────────────┘ │   │
│  └─────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                   System Services                     │   │
│  │  • fail2ban • UFW Firewall • logrotate • certbot    │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

---

## Security Implementation

### Defense in Depth

| Layer | Implementation |
|-------|---------------|
| 1. Network | UFW Firewall (22, 80, 443 only) |
| 2. SSH | fail2ban (3 retry limit) + key-only auth + root login disabled |
| 3. Transport | TLS 1.3 via Let's Encrypt |
| 4. Rate Limiting | Nginx (10 req/s API, 30 req/s webhooks) |
| 5. Application | Helmet, input validation, CORS |
| 6. Secrets | chmod 600/700, non-root user |

### Security Headers (Nginx)

- `Strict-Transport-Security` (HSTS)
- `X-Frame-Options: SAMEORIGIN`
- `X-Content-Type-Options: nosniff`
- `X-XSS-Protection: 1; mode=block`
- `Content-Security-Policy`
- `Referrer-Policy: strict-origin-when-cross-origin`

---

## Deployment Process

### First-Time Deployment

```bash
# 1. Server Setup (as root)
./server-setup.sh --domain onomancer.example.com --email admin@example.com

# 2. Deploy Application (as devrel user)
su - devrel
cd /opt/devrel-integration/devrel-integration
./docs/deployment/scripts/deploy.sh

# 3. Register Discord Commands
npm run register-commands

# 4. Verify
pm2 status
pm2 logs onomancer-bot --lines 20
```

### Update Deployment

```bash
cd /opt/devrel-integration
git pull
cd devrel-integration
./docs/deployment/scripts/deploy.sh
```

---

## Monitoring Setup

### Key Metrics

| Metric | Warning | Critical |
|--------|---------|----------|
| Memory | >70% | >85% |
| Disk | >80% | >90% |
| Restarts | >3/hr | >10/hr |
| Error Rate | >5% | >20% |

### Commands

```bash
pm2 status          # Process status
pm2 monit           # Real-time dashboard
pm2 logs            # Application logs
```

---

## Backup Strategy

| Data | Frequency | Retention |
|------|-----------|-----------|
| SQLite DB | Daily | 7 days |
| Secrets | Manual | Permanent |
| Logs | Rotated | 14 days |

---

## Recovery Objectives

| Scenario | RTO | RPO |
|----------|-----|-----|
| Application crash | 5 min | 0 |
| Database corruption | 30 min | 24 hr |
| Server failure | 2 hr | 24 hr |

---

## Prerequisites Checklist

Before deployment:

- [ ] OVH VPS provisioned (Ubuntu 22.04, 2GB RAM, 20GB disk)
- [ ] Domain name configured (DNS A record)
- [ ] Discord Bot Token ready
- [ ] Google Service Account JSON ready
- [ ] Anthropic API Key ready
- [ ] Linear API Token ready (optional)
- [ ] SSH access confirmed

---

## File Structure After Deployment

```
/opt/devrel-integration/
├── devrel-integration/
│   ├── dist/                # Compiled application
│   ├── secrets/             # Credentials (chmod 700)
│   │   ├── .env.local       # Environment variables
│   │   └── service-account.json
│   ├── data/                # Runtime data
│   │   └── onomancer.db     # SQLite database
│   ├── backups/             # Database backups
│   ├── logs/                # Symlink to /var/log/devrel
│   ├── docs/
│   │   └── deployment/      # Deployment infrastructure
│   └── ecosystem.config.js  # PM2 configuration
└── .git/
```

---

## Known Limitations

1. **Single Server**: No redundancy (acceptable for MVP)
2. **SQLite**: Limited concurrent writes (sufficient for MVP scale)
3. **Discord Bot**: Single instance only (WebSocket limitation)

### Scaling Path

If scaling needed:
1. Add load balancer + second server
2. Migrate SQLite → PostgreSQL
3. External Redis cluster
4. Container orchestration (K8s)

---

## Verification Commands

```bash
# Process status
pm2 status

# Check for errors
pm2 logs onomancer-bot --err --lines 20

# Health check (if nginx configured)
curl -s https://your-domain.com/health | jq .

# Test Discord command
# In Discord: /show-sprint
```

---

## Next Steps

1. **Provision Server**: Order OVH VPS with Ubuntu 22.04
2. **Run Setup**: Execute `server-setup.sh` with domain
3. **Configure Secrets**: Add all credentials to `.env.local`
4. **Deploy**: Run `deploy.sh`
5. **Verify**: Test Discord commands
6. **Monitor**: Set up alerts as needed

---

## Support Resources

| Resource | Location |
|----------|----------|
| Deployment Guide | `devrel-integration/docs/deployment/deployment-guide.md` |
| Architecture | `devrel-integration/docs/deployment/infrastructure.md` |
| Monitoring | `devrel-integration/docs/deployment/monitoring.md` |
| Incident Response | `devrel-integration/docs/deployment/runbooks/incident-response.md` |
| Original Runbook | `devrel-integration/docs/DEPLOYMENT_RUNBOOK.md` |
| Credentials Guide | `devrel-integration/docs/CREDENTIALS_SETUP_GUIDE.md` |

---

**Infrastructure Status: READY FOR PRODUCTION DEPLOYMENT**

*Report generated by DevOps Crypto Architect Agent*
*Date: 2025-12-16*
