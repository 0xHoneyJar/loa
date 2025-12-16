# Onomancer Bot - Infrastructure Architecture

> Production deployment architecture for the Onomancer Bot DevRel Documentation Automation System

**Version:** 1.0
**Date:** 2025-12-16
**Target Environment:** OVH Bare Metal VPS (Single Server MVP)

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [System Components](#system-components)
3. [Network Architecture](#network-architecture)
4. [Security Architecture](#security-architecture)
5. [Data Flow](#data-flow)
6. [External Dependencies](#external-dependencies)
7. [Scaling Considerations](#scaling-considerations)

---

## Architecture Overview

### Deployment Architecture Diagram

```
                                    ┌─────────────────────────────────────────────────────────────┐
                                    │                     OVH VPS Server                           │
                                    │                   (Ubuntu 22.04 LTS)                         │
┌──────────────┐                    │  ┌─────────────────────────────────────────────────────┐   │
│   Discord    │ ◄──────────────────┼──┤                   Nginx                              │   │
│   Gateway    │        WSS:443     │  │         (Reverse Proxy + TLS Termination)            │   │
└──────────────┘                    │  │               SSL via Let's Encrypt                  │   │
                                    │  └────────────────────────┬────────────────────────────┘   │
                                    │                           │ :3000                           │
                                    │  ┌────────────────────────▼────────────────────────────┐   │
                                    │  │                   PM2 Process Manager                │   │
                                    │  │  ┌──────────────────────────────────────────────┐   │   │
                                    │  │  │            Onomancer Bot (Node.js)            │   │   │
                                    │  │  │                                               │   │   │
┌──────────────┐                    │  │  │  ┌───────────────┐  ┌───────────────────┐   │   │   │
│   Google     │ ◄──────────────────┼──┼──┼──┤ Transformation │  │  Discord.js       │   │   │   │
│   Docs API   │        HTTPS:443   │  │  │  │ Pipeline       │  │  Client           │   │   │   │
└──────────────┘                    │  │  │  └───────────────┘  └───────────────────┘   │   │   │
                                    │  │  │                                               │   │   │
┌──────────────┐                    │  │  │  ┌───────────────┐  ┌───────────────────┐   │   │   │
│   Anthropic  │ ◄──────────────────┼──┼──┼──┤ Context       │  │  Command Handlers │   │   │   │
│   Claude API │        HTTPS:443   │  │  │  │ Aggregator    │  │                   │   │   │   │
└──────────────┘                    │  │  │  └───────────────┘  └───────────────────┘   │   │   │
                                    │  │  │                                               │   │   │
┌──────────────┐                    │  │  │  ┌───────────────┐  ┌───────────────────┐   │   │   │
│   Linear     │ ◄──────────────────┼──┼──┼──┤ Security      │  │  Cron Jobs        │   │   │   │
│   API        │        HTTPS:443   │  │  │  │ Services      │  │  (Weekly Digest)  │   │   │   │
└──────────────┘                    │  │  │  └───────────────┘  └───────────────────┘   │   │   │
                                    │  │  └──────────────────────────────────────────────┘   │   │
                                    │  └─────────────────────────────────────────────────────┘   │
                                    │                                                             │
                                    │  ┌─────────────────────────────────────────────────────┐   │
                                    │  │                    Data Layer                         │   │
                                    │  │  ┌─────────────────┐    ┌─────────────────────────┐ │   │
                                    │  │  │  SQLite DB      │    │  Redis (Optional)       │ │   │
                                    │  │  │  (Bot State)    │    │  (Cache + Rate Limit)   │ │   │
                                    │  │  └─────────────────┘    └─────────────────────────┘ │   │
                                    │  └─────────────────────────────────────────────────────┘   │
                                    │                                                             │
                                    │  ┌─────────────────────────────────────────────────────┐   │
                                    │  │                   System Services                     │   │
                                    │  │  • fail2ban (SSH Protection)                         │   │
                                    │  │  • ufw (Firewall)                                    │   │
                                    │  │  • logrotate (Log Management)                        │   │
                                    │  │  • certbot (SSL Certificate Renewal)                 │   │
                                    │  └─────────────────────────────────────────────────────┘   │
                                    └─────────────────────────────────────────────────────────────┘
```

---

## System Components

### 1. Web Server (Nginx)

**Purpose:** Reverse proxy, TLS termination, rate limiting

**Configuration:**
- Listens on port 443 (HTTPS) and 80 (HTTP redirect)
- TLS certificates via Let's Encrypt (certbot)
- Proxies to Node.js app on localhost:3000
- Adds security headers (X-Frame-Options, CSP, etc.)
- Rate limiting for webhook endpoints

**Files:**
- `/etc/nginx/sites-available/onomancer`
- `/etc/nginx/snippets/security-headers.conf`

### 2. Application Server (Node.js + PM2)

**Purpose:** Run Onomancer Bot application

**Configuration:**
- Node.js 20.x LTS
- PM2 for process management
- 2 instances (cluster mode for redundancy)
- Auto-restart on failure
- Memory limit: 1GB per instance

**Files:**
- `/opt/devrel-integration/ecosystem.config.js` (PM2 config)
- `/opt/devrel-integration/dist/` (compiled application)

### 3. Database (SQLite)

**Purpose:** Bot state, user preferences, session management

**Configuration:**
- File-based database at `/opt/devrel-integration/data/onomancer.db`
- Daily backups via cron
- WAL mode for concurrent reads

**Backup Strategy:**
- Daily backup to `/opt/devrel-integration/backups/`
- 7-day retention
- Monthly archive to remote storage (optional)

### 4. Cache (Redis - Optional)

**Purpose:** API response caching, rate limiting, session store

**Configuration:**
- Local Redis instance (if installed)
- Fallback to in-memory LRU cache if Redis unavailable
- 256MB memory limit
- LRU eviction policy

**Note:** Redis is optional for MVP. The application gracefully degrades to in-memory caching.

### 5. Security Services

**UFW Firewall Rules:**
```
22/tcp (SSH)     - Allow (rate-limited via fail2ban)
80/tcp (HTTP)    - Allow (redirects to HTTPS)
443/tcp (HTTPS)  - Allow
3000/tcp         - Deny (internal only, accessed via nginx)
```

**Fail2ban Jails:**
- `sshd` - SSH brute force protection
- `nginx-http-auth` - HTTP authentication failures
- `nginx-botsearch` - Bot scanner protection

---

## Network Architecture

### Inbound Traffic

| Port | Protocol | Source | Destination | Purpose |
|------|----------|--------|-------------|---------|
| 22 | TCP | Admin IPs | Server | SSH access |
| 80 | TCP | Any | Nginx | HTTP → HTTPS redirect |
| 443 | TCP | Any | Nginx | HTTPS (webhooks, health check) |

### Outbound Traffic

| Destination | Port | Protocol | Purpose |
|-------------|------|----------|---------|
| discord.com | 443 | WSS/HTTPS | Discord Gateway |
| gateway.discord.gg | 443 | WSS | Discord WebSocket |
| api.anthropic.com | 443 | HTTPS | Claude API |
| api.linear.app | 443 | HTTPS | Linear API |
| docs.googleapis.com | 443 | HTTPS | Google Docs API |
| drive.googleapis.com | 443 | HTTPS | Google Drive API |
| oauth2.googleapis.com | 443 | HTTPS | Google OAuth |

### Internal Communication

```
Nginx (:443) ──proxy_pass──► Node.js (:3000)
Node.js ────────────────────► SQLite (file)
Node.js ────────────────────► Redis (:6379) [optional]
```

---

## Security Architecture

### Defense in Depth Layers

```
Layer 1: Network (UFW Firewall)
    ↓
Layer 2: SSH Protection (fail2ban)
    ↓
Layer 3: TLS Termination (Nginx + Let's Encrypt)
    ↓
Layer 4: Rate Limiting (Nginx + Application)
    ↓
Layer 5: Application Security (Helmet, CORS, Input Validation)
    ↓
Layer 6: Business Logic Security (SecretScanner, ContentSanitizer)
    ↓
Layer 7: Data Protection (Encrypted env vars, file permissions)
```

### Credentials Management

| Credential | Storage Location | Access Method |
|------------|-----------------|---------------|
| Discord Bot Token | `/opt/devrel-integration/secrets/.env.local` | Environment variable |
| Google Service Account | `/opt/devrel-integration/secrets/service-account.json` | File path in env var |
| Anthropic API Key | `/opt/devrel-integration/secrets/.env.local` | Environment variable |
| Linear API Token | `/opt/devrel-integration/secrets/.env.local` | Environment variable |

**File Permissions:**
```bash
/opt/devrel-integration/secrets/           # drwx------ (700)
/opt/devrel-integration/secrets/.env.local # -rw------- (600)
/opt/devrel-integration/secrets/*.json     # -rw------- (600)
```

### Security Checklist

- [x] Non-root user (`devrel`) for application
- [x] UFW firewall enabled
- [x] fail2ban for SSH protection
- [x] TLS 1.3 only (nginx config)
- [x] HTTP security headers (CSP, X-Frame-Options, etc.)
- [x] Rate limiting on public endpoints
- [x] Secret scanning in transformation pipeline
- [x] Content sanitization for prompt injection defense
- [x] Audit logging for security events

---

## Data Flow

### Document Transformation Flow

```
1. User: /translate mibera @prd for leadership
              │
              ▼
2. Discord API → Onomancer Bot (Command Handler)
              │
              ▼
3. Document Resolver → Read docs/prd.md
              │
              ▼
4. Context Aggregator → Query Linear/GitHub (parallel)
              │
              ▼
5. Content Sanitizer → Clean input for LLM
              │
              ▼
6. Secret Scanner → Detect/redact secrets
              │
              ▼
7. SecureTranslationInvoker → Anthropic Claude API
              │
              ▼
8. Output Validator → Validate response quality
              │
              ▼
9. Google Docs Service → Create document in Drive
              │
              ▼
10. Discord Response → Send Google Docs link to user
```

### Data at Rest

| Data Type | Location | Encryption |
|-----------|----------|------------|
| Bot state (users, preferences) | SQLite DB | At-rest (OS-level) |
| Secrets (.env.local) | File system | File permissions (600) |
| Logs | /var/log/devrel/ | At-rest (OS-level) |
| Cache | Redis/Memory | Not encrypted (ephemeral) |

### Data in Transit

| Connection | Encryption |
|------------|------------|
| User → Discord | TLS 1.3 (Discord handles) |
| Bot → Discord API | TLS 1.3 |
| Bot → Anthropic API | TLS 1.3 |
| Bot → Google APIs | TLS 1.3 |
| Bot → Linear API | TLS 1.3 |
| Nginx → Bot | Localhost (no encryption needed) |

---

## External Dependencies

### Critical Dependencies

| Service | SLA | Fallback Strategy |
|---------|-----|-------------------|
| Discord API | 99.9% | Queue commands, retry with backoff |
| Anthropic Claude | 99.5% | Circuit breaker, return error to user |
| Google Docs API | 99.95% | Circuit breaker, cache recent results |
| Linear API | 99.9% | Graceful degradation (skip context) |

### Dependency Health Monitoring

The application includes circuit breakers and health checks for all external APIs:
- Circuit breaker trips after 5 consecutive failures
- Half-open state allows test requests every 30 seconds
- Full logs available at `/var/log/devrel/onomancer-*.log`

---

## Scaling Considerations

### Current Capacity (Single Server MVP)

| Resource | Capacity | Bottleneck |
|----------|----------|------------|
| Concurrent users | ~100 | Discord rate limits |
| Transformations/hour | ~60 | Anthropic API rate limits |
| Document storage | Unlimited | Google Drive quota |
| Bot state | ~10,000 users | SQLite performance |

### Future Scaling Path

If scaling becomes necessary:

1. **Horizontal Scaling (Phase 1):**
   - Add load balancer (HAProxy/Nginx)
   - Multiple Node.js instances behind LB
   - External Redis for shared cache/sessions
   - External PostgreSQL for bot state

2. **Container Orchestration (Phase 2):**
   - Docker containerization
   - Kubernetes (GKE/EKS) deployment
   - Auto-scaling based on queue depth
   - Managed Redis/PostgreSQL

3. **Serverless (Phase 3):**
   - Cloud Run for transformation workers
   - Cloud Functions for webhooks
   - Firestore for state management

---

## Directory Structure

```
/opt/devrel-integration/
├── dist/                    # Compiled application
│   ├── bot.js               # Main entry point
│   ├── commands/            # Command handlers
│   ├── services/            # Business logic
│   └── database/
│       └── schema.sql       # SQLite schema
├── secrets/                 # Credentials (chmod 700)
│   ├── .env.local           # Environment variables
│   └── service-account.json # Google credentials
├── data/                    # Runtime data
│   └── onomancer.db         # SQLite database
├── backups/                 # Database backups
├── logs/                    # Application logs (symlink to /var/log/devrel)
├── ecosystem.config.js      # PM2 configuration
└── package.json             # Node.js dependencies
```

---

## Version History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-12-16 | DevOps Architect | Initial architecture document |
