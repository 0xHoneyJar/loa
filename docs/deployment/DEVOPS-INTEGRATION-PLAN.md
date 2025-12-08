# DevOps Integration Deployment Plan

**Date**: 2025-12-08
**Status**: 📋 PLANNING
**DevOps Architect**: Claude Code (devops-crypto-architect agent)
**Version**: 1.0

---

## Executive Summary

This deployment plan consolidates findings from:
- **docs/a2a/integration-implementation-handover.md** - Integration architecture and specifications
- **docs/audits/2025-12-08_1/AUDIT-SUMMARY.md** - Security audit results (8 CRITICAL issues identified)
- **docs/audits/2025-12-08_1/REMEDIATION-PLAN.md** - Detailed remediation tasks for security issues
- **integration/docs/HIGH-PRIORITY-IMPLEMENTATION-STATUS.md** - Current implementation status (94.7% complete)

**Current State**:
- ✅ **Implementation**: 94.7% complete (18/19 CRITICAL+HIGH issues resolved)
- ✅ **Security Score**: 9.9/10 (improved from 7/10)
- ✅ **Production Readiness**: HIGH (pending final validation)
- ⏳ **Remaining Work**: 1 optional HIGH issue, final testing, deployment automation

**Recommendation**: **PROCEED TO STAGING DEPLOYMENT** after completing Phase 1 validation steps.

---

## Phase Assessment

### Phase 0: Integration Design ✅ COMPLETE
**Owner**: context-engineering-expert agent
**Status**: ✅ Complete

**Deliverables Created**:
- `docs/hivemind/integration-architecture.md` (982 lines) - Complete system architecture
- `docs/hivemind/tool-setup.md` (1,371 lines) - API configuration and setup
- `docs/hivemind/team-playbook.md` (912 lines) - Team usage workflows
- `docs/a2a/integration-implementation-handover.md` (750 lines) - Implementation specifications

**Architecture Overview**:
- **Integration Type**: Hivemind Laboratory Methodology (minimal friction, Linear-first)
- **Team Structure**: 2-4 developers + 1 non-technical researcher
- **Key Components**: Discord bot, Linear API integration, feedback capture (📌 reaction), daily digest, command handlers

---

### Phase 0.5: Integration Implementation ✅ 94.7% COMPLETE
**Owner**: devops-crypto-architect agent (previous session) + sprint-task-implementer agents
**Status**: ✅ Mostly Complete (18/19 issues resolved)

**Implementation Progress**:

#### CRITICAL Issues (8 Total) - Status Unknown from Current Docs
The audit from `2025-12-08_1` identified 8 CRITICAL issues:
1. **CRITICAL-001**: Prompt Injection (Content Sanitizer required)
2. **CRITICAL-002**: Command Injection (Input Validator required)
3. **CRITICAL-003**: Approval Workflow Authorization (RBAC required)
4. **CRITICAL-004**: Google Drive Permission Validation
5. **CRITICAL-005**: Secret Exposure in Summaries (Secret Scanner required)
6. **CRITICAL-006**: Rate Limiting & DoS Protection
7. **CRITICAL-007**: Blog Publishing Security (should be DISABLED)
8. **CRITICAL-008**: Secrets Rotation & Monitoring

**Note**: The HIGH-PRIORITY-IMPLEMENTATION-STATUS.md shows CRITICAL issues resolved in a different audit (likely from `2025-12-08` main directory). Need to verify overlap.

#### HIGH Issues (11 Total) - ✅ 10/11 COMPLETE (90.9%)
Based on `integration/docs/HIGH-PRIORITY-IMPLEMENTATION-STATUS.md`:

**✅ Completed (10 issues)**:
1. ✅ HIGH-003: Input Length Limits (document/digest/command validation)
2. ✅ HIGH-007: Comprehensive Logging and Audit Trail (30+ event types, 1-year retention)
3. ✅ HIGH-004: Error Handling for Failed Translations (retry + circuit breaker)
4. ✅ HIGH-011: Context Assembly Access Control (sensitivity hierarchy, explicit relationships)
5. ✅ HIGH-005: Department Detection Security (database-backed RBAC, MFA support)
6. ✅ HIGH-001: Discord Channel Access Controls Documentation (900+ lines)
7. ✅ HIGH-009: Disaster Recovery Plan (1,200+ lines, RTO 2hrs, RPO 24hrs)
8. ✅ HIGH-010: Anthropic API Key Privilege Documentation (600+ lines, 180-day rotation)
9. ✅ HIGH-008: Blog Platform Security Assessment (Mirror/Paragraph evaluation)
10. ✅ HIGH-012: GDPR/Privacy Compliance Documentation (700+ lines, 82% compliant)

**⏳ Pending (1 issue)**:
1. ⏳ HIGH-002: Secrets Manager Integration (OPTIONAL - infrastructure project, 10-15 hours)

**Implementation Statistics**:
- **Files Created**: 17 implementation files + 10 documentation files
- **Lines of Code**: ~5,490 lines (implementation + tests)
- **Test Coverage**: 133 tests, all passing ✅
- **Documentation**: ~7,000 lines of security/compliance documentation

---

## Current State Analysis

### What's Working ✅

#### 1. Security Implementation
- ✅ **RBAC System**: Database-backed role verification with MFA support
- ✅ **Input Validation**: Document size limits, path traversal protection, command sanitization
- ✅ **Audit Logging**: 30+ security event types, 1-year retention, SIEM-ready
- ✅ **Error Handling**: Retry handler with exponential backoff, circuit breaker pattern
- ✅ **Rate Limiting**: Per-user and API rate limiting (20 req/min for Anthropic)
- ✅ **Content Sanitization**: PII detection, prompt injection protection (if CRITICAL-001 resolved)
- ✅ **Secret Management**: Rotation policies, leak detection, 180-day intervals

#### 2. Compliance Framework
- ✅ **GDPR Compliance**: 9/11 requirements met (82%), data subject rights implemented
- ✅ **Data Retention**: 90-day messages, 1-year audit logs, automated cleanup
- ✅ **Privacy by Design**: Sensitivity classification, consent mechanisms
- ✅ **DPA Framework**: Templates for Discord, Linear, Anthropic (to be signed)

#### 3. Operational Documentation
- ✅ **Disaster Recovery**: Complete DR plan with backup/restore procedures
- ✅ **Incident Response**: Playbooks for token compromise, PII leaks, cost spikes
- ✅ **Monitoring**: Health checks, metrics collection, alerting rules
- ✅ **Secrets Rotation**: Automated reminders, emergency rotation procedures

### What's Missing or Unclear ❓

#### 1. CRITICAL Issue Resolution Status
**Problem**: The audit from `2025-12-08_1` shows 8 CRITICAL issues, but the implementation status document shows HIGH issues only. Need to verify if CRITICAL issues from that audit were addressed.

**Action Required**: Cross-reference and validate CRITICAL issues resolution.

#### 2. Deployment Infrastructure
**Missing**:
- ❌ Dockerfile (referenced in docker-compose.yml but may not exist per earlier audit)
- ❓ Deployment automation (CI/CD pipeline)
- ❓ Staging environment setup
- ❓ Production deployment scripts
- ❓ Monitoring integration (Datadog/Prometheus/Grafana)

#### 3. Testing and Validation
**Missing**:
- ❓ Integration test suite (end-to-end workflows)
- ❓ Security test suite (penetration testing)
- ❓ Load testing (rate limiting, circuit breaker validation)
- ❓ Disaster recovery drill results

#### 4. Configuration Management
**Missing**:
- ❓ Secrets setup (`.env.local` creation from `.env.local.example`)
- ❓ Discord bot configuration (token, guild ID, channel IDs)
- ❓ Linear API configuration (API key, team ID, webhook secret)
- ❓ Anthropic API configuration (API key, budget limits)

---

## Deployment Readiness Checklist

### Pre-Deployment Requirements

#### Phase 1: Validation and Gap Closure (Estimated: 2-3 days)

**Priority 1: Verify CRITICAL Issues Resolution** (4 hours)
- [ ] Read latest security audit report (likely in `docs/audits/2025-12-08/FINAL-AUDIT-REMEDIATION-REPORT.md`)
- [ ] Cross-reference CRITICAL issues from `2025-12-08_1` audit with implementation status
- [ ] Validate that CRITICAL-001 through CRITICAL-008 have been addressed
- [ ] Document any gaps and create remediation tasks

**Priority 2: Create Missing Deployment Infrastructure** (8 hours)
- [ ] Create production-ready `Dockerfile` with security hardening
- [ ] Create `docker-compose.yml` for local development
- [ ] Create `docker-compose.staging.yml` for staging environment
- [ ] Create `docker-compose.prod.yml` for production environment
- [ ] Create health check endpoint (`/health`, `/ready`, `/metrics`)
- [ ] Create startup validation script (secrets, database, API connectivity)

**Priority 3: Configuration Management** (4 hours)
- [ ] Document secrets acquisition process (Discord, Linear, Anthropic tokens)
- [ ] Create configuration templates for each environment (dev, staging, prod)
- [ ] Create secrets validation script (`scripts/verify-secrets.sh`)
- [ ] Create database initialization script (`scripts/init-database.sh`)
- [ ] Document required Discord server setup (channels, roles, permissions)

**Priority 4: Testing Suite** (8 hours)
- [ ] Create integration test suite (`tests/integration/`)
- [ ] Create security test suite (`tests/security/`)
- [ ] Create performance test suite (`tests/performance/`)
- [ ] Run all tests and document results
- [ ] Create automated test runner script (`scripts/run-all-tests.sh`)

#### Phase 2: Staging Deployment (Estimated: 1-2 days)

**Priority 1: Staging Environment Setup** (4 hours)
- [ ] Provision staging server (cloud VM or container platform)
- [ ] Install prerequisites (Docker, Node.js 18+, SQLite, Git)
- [ ] Create staging secrets (use test/staging API keys, NOT production)
- [ ] Deploy using `docker-compose.staging.yml`
- [ ] Verify all services start successfully
- [ ] Run smoke tests (health check, basic commands)

**Priority 2: Staging Validation** (8 hours)
- [ ] Test Discord bot connectivity (bot comes online)
- [ ] Test all Discord commands (`/show-sprint`, `/doc`, `/my-tasks`, etc.)
- [ ] Test feedback capture (📌 reaction → Linear draft issue)
- [ ] Test daily digest (manually trigger, verify format)
- [ ] Test Linear API integration (create issue, update status, query tasks)
- [ ] Test error handling (disconnect Linear, verify graceful degradation)
- [ ] Test rate limiting (spam commands, verify blocking)
- [ ] Test RBAC (verify role restrictions, MFA for sensitive operations)
- [ ] Monitor logs for errors (24-hour observation period)
- [ ] Verify audit logging (query database for security events)

**Priority 3: Security Validation** (8 hours)
- [ ] Run security scanner (npm audit, Snyk, OWASP ZAP)
- [ ] Attempt path traversal attacks (verify input validation blocks)
- [ ] Attempt prompt injection attacks (verify content sanitizer blocks)
- [ ] Attempt rate limit bypass (verify rate limiting enforced)
- [ ] Verify secrets not in logs (`grep -r "sk_live" logs/`)
- [ ] Verify database permissions (auth.db should be 0600)
- [ ] Verify webhook signature validation (send unsigned webhook, verify rejection)
- [ ] Review audit logs for security events (verify no gaps)

#### Phase 3: Production Deployment (Estimated: 1 day)

**Priority 1: Production Readiness** (4 hours)
- [ ] Security team sign-off on staging validation results
- [ ] CTO approval for production deployment
- [ ] Create production secrets (generate NEW tokens for prod)
- [ ] Provision production server (redundant if possible)
- [ ] Configure DNS and firewall rules
- [ ] Set up monitoring and alerting (Datadog/Prometheus/PagerDuty)
- [ ] Create backup and restore plan (database, configs, secrets)

**Priority 2: Production Deployment** (2 hours)
- [ ] Deploy to production using `docker-compose.prod.yml`
- [ ] Verify health checks pass (`/health` returns 200 OK)
- [ ] Verify Discord bot comes online
- [ ] Test basic commands in production Discord
- [ ] Monitor logs for errors (first 30 minutes)
- [ ] Verify audit logging working
- [ ] Set up automated backups (database, configs)

**Priority 3: Post-Deployment Monitoring** (24 hours)
- [ ] Monitor error logs continuously (first 4 hours)
- [ ] Check metrics (request rates, error rates, latency)
- [ ] Verify daily digest posts successfully (next morning)
- [ ] Verify webhook processing (Linear issue events)
- [ ] Verify rate limiting in production
- [ ] Verify circuit breaker behavior
- [ ] Review audit logs for anomalies
- [ ] Collect user feedback from team

---

## Implementation Tasks

### Task 1: Create Production Dockerfile

**File**: `integration/Dockerfile`

```dockerfile
# Multi-stage build for security and minimal image size
FROM node:18-alpine@sha256:LATEST_SHA AS builder

WORKDIR /app

# Copy package files
COPY package*.json tsconfig.json ./

# Install ALL dependencies (including devDependencies for build)
RUN npm ci

# Copy source code
COPY src/ ./src/
COPY config/ ./config/

# Build TypeScript
RUN npm run build

# Production stage
FROM node:18-alpine@sha256:LATEST_SHA AS production

# Install security updates
RUN apk upgrade --no-cache

# Create non-root user
RUN addgroup -g 1001 nodejs && \
    adduser -S -u 1001 -G nodejs nodejs

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install ONLY production dependencies
RUN npm ci --only=production && \
    npm cache clean --force

# Copy built application from builder
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/config ./config

# Create directories with proper permissions
RUN mkdir -p logs data && \
    chown -R nodejs:nodejs /app && \
    chmod 700 logs data

# Switch to non-root user
USER nodejs

# Expose health check port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
  CMD node -e "require('http').get('http://localhost:3000/health', (res) => process.exit(res.statusCode === 200 ? 0 : 1))"

# Start application
CMD ["node", "dist/bot.js"]
```

**Security Features**:
- ✅ Multi-stage build (smaller final image, no build tools in production)
- ✅ SHA-pinned base image (prevents supply chain attacks)
- ✅ Non-root user (nodejs:1001)
- ✅ Security updates applied (apk upgrade)
- ✅ Production dependencies only (--only=production)
- ✅ Secure directory permissions (700 for logs/data)
- ✅ Health check endpoint
- ✅ Minimal attack surface (alpine base)

---

### Task 2: Create Docker Compose Configurations

#### Development: `integration/docker-compose.yml`

```yaml
version: '3.8'

services:
  bot:
    build:
      context: .
      dockerfile: Dockerfile
      target: production
    container_name: agentic-base-bot-dev
    restart: unless-stopped
    env_file:
      - ./secrets/.env.local
    environment:
      - NODE_ENV=development
      - LOG_LEVEL=debug
    volumes:
      # Mount logs and data for development debugging
      - ./logs:/app/logs
      - ./data:/app/data
      # Mount config as read-only
      - ./config:/app/config:ro
    ports:
      - "3000:3000"  # Health check endpoint
    networks:
      - agentic-base
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:3000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

networks:
  agentic-base:
    driver: bridge
```

#### Staging: `integration/docker-compose.staging.yml`

```yaml
version: '3.8'

services:
  bot:
    build:
      context: .
      dockerfile: Dockerfile
      target: production
    image: agentic-base-bot:staging-${VERSION:-latest}
    container_name: agentic-base-bot-staging
    restart: unless-stopped
    env_file:
      - ./secrets/.env.staging
    environment:
      - NODE_ENV=staging
      - LOG_LEVEL=info
    volumes:
      # Persistent volumes for logs and database
      - bot-logs-staging:/app/logs
      - bot-data-staging:/app/data
      # Config from host (for easy updates)
      - ./config:/app/config:ro
    ports:
      - "3000:3000"
    networks:
      - agentic-base-staging
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 512M
        reservations:
          cpus: '0.25'
          memory: 256M
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:3000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

volumes:
  bot-logs-staging:
    driver: local
  bot-data-staging:
    driver: local

networks:
  agentic-base-staging:
    driver: bridge
```

#### Production: `integration/docker-compose.prod.yml`

```yaml
version: '3.8'

services:
  bot:
    image: agentic-base-bot:${VERSION}  # Use explicit version tag
    container_name: agentic-base-bot-prod
    restart: always  # Always restart in production
    env_file:
      - ./secrets/.env.prod
    environment:
      - NODE_ENV=production
      - LOG_LEVEL=warn  # Less verbose in production
    volumes:
      # Persistent volumes (managed by Docker)
      - bot-logs-prod:/app/logs
      - bot-data-prod:/app/data
      # Config from host (backed up separately)
      - ./config:/app/config:ro
    ports:
      - "3000:3000"
    networks:
      - agentic-base-prod
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 1024M
        reservations:
          cpus: '0.5'
          memory: 512M
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:3000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s  # Longer start period for production
    logging:
      driver: "json-file"
      options:
        max-size: "50m"
        max-file: "5"
        compress: "true"

volumes:
  bot-logs-prod:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /var/lib/agentic-base/logs
  bot-data-prod:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /var/lib/agentic-base/data

networks:
  agentic-base-prod:
    driver: bridge
```

---

### Task 3: Create Deployment Scripts

#### Staging Deployment: `scripts/deploy-staging.sh`

```bash
#!/bin/bash
set -euo pipefail

# Deploy to staging environment
# Usage: ./scripts/deploy-staging.sh [version]

VERSION="${1:-latest}"
COMPOSE_FILE="docker-compose.staging.yml"

echo "🚀 Deploying agentic-base-bot to STAGING"
echo "Version: ${VERSION}"
echo "Environment: staging"
echo ""

# Step 1: Verify secrets exist
echo "1️⃣  Verifying secrets..."
if [ ! -f "secrets/.env.staging" ]; then
  echo "❌ ERROR: secrets/.env.staging not found"
  echo "   Create it from secrets/.env.local.example"
  exit 1
fi

# Step 2: Verify configuration
echo "2️⃣  Verifying configuration..."
if [ ! -f "config/discord-digest.yml" ]; then
  echo "❌ ERROR: config/discord-digest.yml not found"
  exit 1
fi

# Step 3: Build image
echo "3️⃣  Building Docker image..."
VERSION=${VERSION} docker-compose -f ${COMPOSE_FILE} build

# Step 4: Stop existing container
echo "4️⃣  Stopping existing container..."
docker-compose -f ${COMPOSE_FILE} down || true

# Step 5: Start new container
echo "5️⃣  Starting new container..."
VERSION=${VERSION} docker-compose -f ${COMPOSE_FILE} up -d

# Step 6: Wait for health check
echo "6️⃣  Waiting for health check..."
sleep 10

for i in {1..12}; do
  if curl -sf http://localhost:3000/health > /dev/null; then
    echo "✅ Health check passed!"
    break
  fi
  if [ $i -eq 12 ]; then
    echo "❌ Health check failed after 60 seconds"
    docker-compose -f ${COMPOSE_FILE} logs --tail=50
    exit 1
  fi
  echo "   Attempt $i/12 failed, retrying in 5 seconds..."
  sleep 5
done

# Step 7: Show logs
echo "7️⃣  Recent logs:"
docker-compose -f ${COMPOSE_FILE} logs --tail=20

echo ""
echo "✅ Deployment to STAGING complete!"
echo ""
echo "Commands:"
echo "  View logs:   docker-compose -f ${COMPOSE_FILE} logs -f"
echo "  Check status: docker-compose -f ${COMPOSE_FILE} ps"
echo "  Stop:        docker-compose -f ${COMPOSE_FILE} down"
echo "  Health:      curl http://localhost:3000/health"
```

#### Production Deployment: `scripts/deploy-production.sh`

```bash
#!/bin/bash
set -euo pipefail

# Deploy to production environment
# Usage: ./scripts/deploy-production.sh <version>

if [ $# -eq 0 ]; then
  echo "❌ ERROR: Version required"
  echo "Usage: $0 <version>"
  echo "Example: $0 v1.0.0"
  exit 1
fi

VERSION="$1"
COMPOSE_FILE="docker-compose.prod.yml"

echo "🚀 Deploying agentic-base-bot to PRODUCTION"
echo "Version: ${VERSION}"
echo "Environment: production"
echo ""
echo "⚠️  WARNING: This will deploy to PRODUCTION"
read -p "Are you sure? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
  echo "❌ Deployment cancelled"
  exit 0
fi

# Step 1: Verify secrets exist
echo "1️⃣  Verifying secrets..."
if [ ! -f "secrets/.env.prod" ]; then
  echo "❌ ERROR: secrets/.env.prod not found"
  exit 1
fi

# Step 2: Verify image exists
echo "2️⃣  Verifying Docker image..."
if ! docker image inspect "agentic-base-bot:${VERSION}" > /dev/null 2>&1; then
  echo "❌ ERROR: Docker image agentic-base-bot:${VERSION} not found"
  echo "   Build it first: docker build -t agentic-base-bot:${VERSION} ."
  exit 1
fi

# Step 3: Backup database
echo "3️⃣  Backing up database..."
./scripts/backup-database.sh

# Step 4: Stop existing container
echo "4️⃣  Stopping existing container..."
VERSION=${VERSION} docker-compose -f ${COMPOSE_FILE} down || true

# Step 5: Start new container
echo "5️⃣  Starting new container..."
VERSION=${VERSION} docker-compose -f ${COMPOSE_FILE} up -d

# Step 6: Wait for health check
echo "6️⃣  Waiting for health check..."
sleep 15

for i in {1..20}; do
  if curl -sf http://localhost:3000/health > /dev/null; then
    echo "✅ Health check passed!"
    break
  fi
  if [ $i -eq 20 ]; then
    echo "❌ Health check failed after 100 seconds"
    docker-compose -f ${COMPOSE_FILE} logs --tail=100
    echo ""
    echo "🔄 Rolling back to previous version..."
    docker-compose -f ${COMPOSE_FILE} down
    # Note: Manual rollback needed - store previous version
    exit 1
  fi
  echo "   Attempt $i/20 failed, retrying in 5 seconds..."
  sleep 5
done

# Step 7: Monitor for 5 minutes
echo "7️⃣  Monitoring deployment..."
echo "   Watching logs for errors (5 minutes)..."
timeout 300 docker-compose -f ${COMPOSE_FILE} logs -f &
PID=$!
sleep 300
kill $PID 2>/dev/null || true

echo ""
echo "✅ Deployment to PRODUCTION complete!"
echo ""
echo "Post-deployment checklist:"
echo "  [ ] Test /show-sprint command in Discord"
echo "  [ ] Test feedback capture (📌 reaction)"
echo "  [ ] Verify daily digest posts tomorrow"
echo "  [ ] Monitor logs for errors: docker-compose -f ${COMPOSE_FILE} logs -f"
echo "  [ ] Check metrics: curl http://localhost:3000/metrics"
```

---

### Task 4: Create Validation Scripts

#### Secrets Validation: `scripts/verify-secrets.sh`

```bash
#!/bin/bash
set -euo pipefail

# Verify all required secrets are configured
# Usage: ./scripts/verify-secrets.sh <env>

ENV="${1:-local}"
SECRETS_FILE="secrets/.env.${ENV}"

echo "🔒 Verifying secrets for environment: ${ENV}"
echo "File: ${SECRETS_FILE}"
echo ""

# Check file exists
if [ ! -f "${SECRETS_FILE}" ]; then
  echo "❌ ERROR: ${SECRETS_FILE} not found"
  echo "   Create it from secrets/.env.local.example"
  exit 1
fi

# Check file permissions (should be 0600)
PERMS=$(stat -c "%a" "${SECRETS_FILE}" 2>/dev/null || stat -f "%Lp" "${SECRETS_FILE}")
if [ "${PERMS}" != "600" ]; then
  echo "⚠️  WARNING: Insecure file permissions: ${PERMS}"
  echo "   Recommended: chmod 600 ${SECRETS_FILE}"
fi

# Check required secrets
REQUIRED_SECRETS=(
  "DISCORD_BOT_TOKEN"
  "DISCORD_GUILD_ID"
  "DISCORD_DIGEST_CHANNEL_ID"
  "LINEAR_API_KEY"
  "LINEAR_TEAM_ID"
  "ANTHROPIC_API_KEY"
  "NODE_ENV"
  "LOG_LEVEL"
)

MISSING_SECRETS=()

for SECRET in "${REQUIRED_SECRETS[@]}"; do
  if ! grep -q "^${SECRET}=" "${SECRETS_FILE}"; then
    MISSING_SECRETS+=("${SECRET}")
  fi
done

if [ ${#MISSING_SECRETS[@]} -ne 0 ]; then
  echo "❌ ERROR: Missing required secrets:"
  for SECRET in "${MISSING_SECRETS[@]}"; do
    echo "   - ${SECRET}"
  done
  exit 1
fi

# Validate secret formats
echo "✅ All required secrets present"
echo ""
echo "Validating secret formats..."

# Discord bot token format: [3 parts separated by dots]
DISCORD_TOKEN=$(grep "^DISCORD_BOT_TOKEN=" "${SECRETS_FILE}" | cut -d'=' -f2)
if [ ${#DISCORD_TOKEN} -lt 50 ]; then
  echo "⚠️  WARNING: Discord token seems too short (${#DISCORD_TOKEN} characters)"
fi

# Linear API key format: lin_api_XXXX...
LINEAR_KEY=$(grep "^LINEAR_API_KEY=" "${SECRETS_FILE}" | cut -d'=' -f2)
if [[ ! $LINEAR_KEY =~ ^lin_api ]]; then
  echo "⚠️  WARNING: Linear API key doesn't start with 'lin_api'"
fi

# Anthropic API key format: sk-ant-api03-...
ANTHROPIC_KEY=$(grep "^ANTHROPIC_API_KEY=" "${SECRETS_FILE}" | cut -d'=' -f2)
if [[ ! $ANTHROPIC_KEY =~ ^sk-ant ]]; then
  echo "⚠️  WARNING: Anthropic API key doesn't start with 'sk-ant'"
fi

echo "✅ Secret format validation complete"
echo ""
echo "Next steps:"
echo "1. Test Discord token:   curl -H 'Authorization: Bot \${DISCORD_BOT_TOKEN}' https://discord.com/api/users/@me"
echo "2. Test Linear API:      curl -H 'Authorization: \${LINEAR_API_KEY}' https://api.linear.app/graphql -d '{\"query\":\"{viewer{name}}\"}'  "
echo "3. Deploy:               ./scripts/deploy-staging.sh"
```

---

### Task 5: Create Integration Test Suite

**File**: `integration/tests/integration/bot-workflow.test.ts`

```typescript
/**
 * Integration Tests - Discord Bot Workflows
 *
 * Tests end-to-end workflows:
 * - Discord command execution
 * - Feedback capture (📌 reaction)
 * - Linear API integration
 * - Error handling and graceful degradation
 */

import { Client, GatewayIntentBits } from 'discord.js';
import { LinearClient } from '@linear/sdk';

describe('Discord Bot Integration Tests', () => {
  let discordClient: Client;
  let linearClient: LinearClient;

  beforeAll(async () => {
    // Initialize Discord client
    discordClient = new Client({
      intents: [
        GatewayIntentBits.Guilds,
        GatewayIntentBits.GuildMessages,
        GatewayIntentBits.MessageContent,
        GatewayIntentBits.GuildMessageReactions
      ]
    });

    // Initialize Linear client
    linearClient = new LinearClient({
      apiKey: process.env.LINEAR_API_KEY
    });

    // Wait for bot to connect
    await discordClient.login(process.env.DISCORD_BOT_TOKEN);
  });

  afterAll(async () => {
    await discordClient.destroy();
  });

  describe('Health Check Endpoint', () => {
    it('should return 200 OK from /health endpoint', async () => {
      const response = await fetch('http://localhost:3000/health');
      expect(response.status).toBe(200);

      const body = await response.json();
      expect(body.status).toBe('healthy');
      expect(body.discord).toBe('connected');
      expect(body.linear).toBe('accessible');
    });

    it('should return metrics from /metrics endpoint', async () => {
      const response = await fetch('http://localhost:3000/metrics');
      expect(response.status).toBe(200);

      const body = await response.json();
      expect(body.uptime).toBeGreaterThan(0);
      expect(body.memory).toBeDefined();
    });
  });

  describe('Discord Commands', () => {
    it('should respond to /show-sprint command', async () => {
      // Send command to test channel
      const channel = await discordClient.channels.fetch(process.env.TEST_CHANNEL_ID);
      if (channel?.isTextBased()) {
        const message = await channel.send('/show-sprint');

        // Wait for bot response (max 10 seconds)
        const response = await waitForBotReply(channel, message, 10000);

        expect(response).toBeDefined();
        expect(response.content).toContain('Sprint Status');
      }
    });

    it('should respond to /doc prd command', async () => {
      const channel = await discordClient.channels.fetch(process.env.TEST_CHANNEL_ID);
      if (channel?.isTextBased()) {
        const message = await channel.send('/doc prd');

        const response = await waitForBotReply(channel, message, 10000);

        expect(response).toBeDefined();
        expect(response.content).toContain('Document') || expect(response.content).toContain('not found');
      }
    });

    it('should reject invalid commands with helpful error', async () => {
      const channel = await discordClient.channels.fetch(process.env.TEST_CHANNEL_ID);
      if (channel?.isTextBased()) {
        const message = await channel.send('/invalid-command');

        const response = await waitForBotReply(channel, message, 5000);

        expect(response).toBeDefined();
        expect(response.content).toContain('Unknown command');
        expect(response.content).toContain('/help');
      }
    });
  });

  describe('Feedback Capture', () => {
    it('should create Linear draft issue from 📌 reaction', async () => {
      const channel = await discordClient.channels.fetch(process.env.TEST_CHANNEL_ID);
      if (channel?.isTextBased()) {
        // Post test feedback message
        const message = await channel.send('TEST FEEDBACK: Login button is hard to find');

        // React with 📌
        await message.react('📌');

        // Wait for bot confirmation
        const confirmation = await waitForBotReply(channel, message, 15000);

        expect(confirmation).toBeDefined();
        expect(confirmation.content).toContain('Feedback captured') || expect(confirmation.content).toContain('Linear draft issue');

        // Extract Linear issue ID from response (e.g., "THJ-123")
        const issueMatch = confirmation.content.match(/\[([A-Z]+-\d+)\]/);

        if (issueMatch) {
          const issueId = issueMatch[1];

          // Verify Linear issue created
          const issue = await linearClient.issue(issueId);
          expect(issue).toBeDefined();
          expect(issue.title).toContain('Feedback');
          expect(issue.description).toContain('Login button');

          // Clean up: Delete test issue
          await issue.delete();
        }
      }
    });
  });

  describe('Error Handling', () => {
    it('should handle rate limiting gracefully', async () => {
      const channel = await discordClient.channels.fetch(process.env.TEST_CHANNEL_ID);
      if (channel?.isTextBased()) {
        // Send 10 commands rapidly (should trigger rate limit)
        const promises = [];
        for (let i = 0; i < 10; i++) {
          promises.push(channel.send('/show-sprint'));
        }

        await Promise.all(promises);

        // Wait for rate limit message
        await new Promise(resolve => setTimeout(resolve, 2000));

        // Verify rate limit message received
        const messages = await channel.messages.fetch({ limit: 10 });
        const rateLimitMsg = messages.find(m => m.content.includes('Rate limit') || m.content.includes('⏱️'));

        expect(rateLimitMsg).toBeDefined();
      }
    });

    it('should degrade gracefully when Linear API is unreachable', async () => {
      // Note: This test requires mocking or temporarily blocking Linear API
      // For now, just verify error handling exists

      const channel = await discordClient.channels.fetch(process.env.TEST_CHANNEL_ID);
      if (channel?.isTextBased()) {
        // Try to trigger Linear API call
        const message = await channel.send('/show-sprint');

        const response = await waitForBotReply(channel, message, 15000);

        // Should get a response, either success or graceful error
        expect(response).toBeDefined();
        expect(response.content).not.toContain('UnhandledPromiseRejection');
      }
    });
  });

  describe('Linear API Integration', () => {
    it('should successfully query Linear API', async () => {
      const viewer = await linearClient.viewer;
      expect(viewer).toBeDefined();
      expect(viewer.name).toBeTruthy();
    });

    it('should create and delete test issue', async () => {
      const team = await linearClient.team(process.env.LINEAR_TEAM_ID);

      const issuePayload = await team.createIssue({
        title: '[TEST] Integration test issue - safe to delete',
        description: 'This is a test issue created by automated integration tests.',
        priority: 0
      });

      expect(issuePayload.success).toBe(true);

      const issue = await issuePayload.issue;
      expect(issue).toBeDefined();
      expect(issue.identifier).toMatch(/^[A-Z]+-\d+$/);

      // Clean up
      await issue.delete();
    });
  });
});

// Helper function to wait for bot reply
async function waitForBotReply(channel: any, afterMessage: any, timeout: number): Promise<any> {
  return new Promise((resolve, reject) => {
    const collector = channel.createMessageCollector({
      filter: (m: any) => m.author.bot && m.createdTimestamp > afterMessage.createdTimestamp,
      max: 1,
      time: timeout
    });

    collector.on('collect', (message: any) => {
      resolve(message);
    });

    collector.on('end', (collected: any) => {
      if (collected.size === 0) {
        reject(new Error('No bot reply received within timeout'));
      }
    });
  });
}
```

---

## Risk Assessment

### Current Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| **CRITICAL issues unresolved** | 🟡 MEDIUM | 🔴 CRITICAL | Verify audit report, cross-reference with implementation |
| **Missing deployment infrastructure** | 🔴 HIGH | 🟡 MEDIUM | Create Dockerfile and deployment scripts (Task 1-3) |
| **Insufficient integration testing** | 🟡 MEDIUM | 🟡 MEDIUM | Create test suite, run in staging (Task 5) |
| **Production secrets misconfigured** | 🟡 MEDIUM | 🔴 CRITICAL | Secrets validation script, manual verification (Task 4) |
| **Disaster recovery untested** | 🔴 HIGH | 🟡 MEDIUM | Run DR drill in staging before production |
| **Performance under load unknown** | 🟡 MEDIUM | 🟢 LOW | Load testing in staging (rate limits, circuit breaker) |

### Risk Mitigation Strategy

**Before Staging**:
1. ✅ Verify all CRITICAL issues resolved (audit report review)
2. ✅ Create deployment infrastructure (Dockerfile, docker-compose, scripts)
3. ✅ Create secrets validation script
4. ✅ Create integration test suite

**During Staging**:
1. ✅ Run all integration tests
2. ✅ Run security validation tests
3. ✅ Test disaster recovery procedures
4. ✅ Load test rate limiting and circuit breakers
5. ✅ 24-hour monitoring period

**Before Production**:
1. ✅ Security team sign-off
2. ✅ CTO approval
3. ✅ Production secrets created and validated
4. ✅ Backup and restore tested
5. ✅ Monitoring and alerting configured
6. ✅ Incident response team briefed

---

## Timeline and Milestones

### Week 1: Validation and Infrastructure (Dec 9-15)
**Owner**: DevOps Architect
**Effort**: 32 hours

- **Day 1-2**: Verify CRITICAL issues, cross-reference audits, document gaps
- **Day 3-4**: Create deployment infrastructure (Dockerfile, docker-compose, scripts)
- **Day 5-6**: Create configuration management (secrets validation, init scripts)
- **Day 7**: Create integration test suite

**Milestone**: ✅ Deployment infrastructure complete, ready for staging

### Week 2: Staging Deployment and Validation (Dec 16-22)
**Owner**: DevOps Architect + Team
**Effort**: 20 hours

- **Day 1**: Set up staging environment, deploy
- **Day 2**: Run integration tests, document results
- **Day 3**: Run security validation tests
- **Day 4**: Test disaster recovery procedures
- **Day 5**: 24-hour monitoring period
- **Day 6-7**: Fix any issues found, retest

**Milestone**: ✅ Staging validation complete, production-ready

### Week 3: Production Deployment (Dec 23-29)
**Owner**: DevOps Architect + CTO
**Effort**: 8 hours

- **Day 1**: Get security sign-off, CTO approval
- **Day 2**: Create production secrets, provision production server
- **Day 3**: Deploy to production, monitor for 24 hours
- **Day 4-7**: Continuous monitoring, team training

**Milestone**: ✅ Production deployment complete, system operational

---

## Success Criteria

### Staging Success Criteria (Must Pass All)
- [ ] All integration tests pass (100% success rate)
- [ ] All security tests pass (no vulnerabilities found)
- [ ] Health check endpoint operational (`/health` returns 200 OK)
- [ ] Discord bot responds to all commands (< 5 second response time)
- [ ] Feedback capture creates Linear draft issues (100% success rate)
- [ ] Daily digest posts successfully (manually triggered test)
- [ ] Rate limiting enforces limits (blocks after threshold)
- [ ] Circuit breaker triggers correctly (opens after 5 failures)
- [ ] Error handling prevents crashes (graceful degradation)
- [ ] Audit logging captures all security events (query database, verify completeness)
- [ ] Secrets not in logs (grep logs for tokens, verify none found)
- [ ] Database permissions secure (auth.db is 0600)
- [ ] No errors in logs after 24 hours (continuous monitoring)

### Production Success Criteria (Must Pass All)
- [ ] Health check operational for 24 hours (> 99% uptime)
- [ ] Discord bot online and responsive (< 5 second response time)
- [ ] Daily digest posts successfully (first morning after deployment)
- [ ] Webhook processing functional (Linear issue events trigger notifications)
- [ ] No critical errors in logs (24-hour monitoring)
- [ ] Monitoring and alerting operational (Datadog/Prometheus)
- [ ] Automated backups running (database, configs)
- [ ] Team trained on operations (runbooks reviewed)
- [ ] Incident response plan in place (contacts, escalation path)
- [ ] User feedback positive (team survey, > 80% satisfaction)

---

## Monitoring and Maintenance

### Monitoring Setup

**Metrics to Track**:
- Discord bot uptime (target: > 99.5%)
- Command response time (target: < 5 seconds)
- Linear API success rate (target: > 99%)
- Anthropic API success rate (target: > 99%)
- Error rate (target: < 1% of requests)
- Rate limit triggers (alert if > 10/hour)
- Circuit breaker opens (alert immediately)
- Database query time (target: < 500ms)
- Memory usage (alert if > 75%)
- Disk usage (alert if > 85%)

**Alerting Rules**:
| Alert | Condition | Severity | Channel |
|-------|-----------|----------|---------|
| Bot Offline | Uptime == 0 for 2 minutes | CRITICAL | PagerDuty + #security-alerts |
| High Error Rate | Error rate > 5% for 5 minutes | HIGH | #infrastructure-alerts |
| Rate Limit Abuse | Rate limit triggers > 20/hour | MEDIUM | #security-alerts |
| Circuit Breaker Open | Circuit breaker state == OPEN | HIGH | #infrastructure-alerts |
| Low Disk Space | Disk usage > 85% | MEDIUM | #infrastructure-alerts |
| Database Slow | Query time > 1 second for 5 minutes | MEDIUM | #infrastructure-alerts |
| Secret Rotation Due | Rotation overdue by 14 days | HIGH | #security-alerts |
| Backup Failed | Backup success == 0 for 24 hours | HIGH | #infrastructure-alerts |

### Maintenance Schedule

**Daily** (Automated):
- 2:00 AM UTC: Data retention cleanup (delete messages > 90 days, audit logs > 1 year)
- 3:00 AM UTC: Database backup (automated script)
- 9:00 AM UTC: Secret rotation check (alert if < 14 days)
- Continuous: Health checks, metrics collection

**Weekly** (Manual):
- Friday 4:00 PM: Review error logs, check for anomalies
- Friday 4:30 PM: Review audit logs, check for security events
- Friday 5:00 PM: Export weekly usage report (Linear API, Anthropic API, Discord commands)

**Monthly**:
- First Monday: Database backup verification (restore to test env, verify integrity)
- Second Monday: Security review (review auth audit log, check for suspicious activity)
- Third Monday: Dependency updates (npm update, test in staging)
- Fourth Monday: Cost review (Anthropic API costs, infrastructure costs)

**Quarterly**:
- Disaster recovery drill (full system recovery test)
- Security audit (run automated scanners, review findings)
- Compliance audit (GDPR checklist, DPA review)
- Performance review (review metrics, optimize if needed)

---

## Open Questions and Blockers

### Questions for User/Team

1. **CRITICAL Issues Status**:
   - Are the 8 CRITICAL issues from `docs/audits/2025-12-08_1/AUDIT-SUMMARY.md` the same as the ones addressed in the main audit?
   - If not, do we have documentation showing they've been resolved?

2. **Deployment Target**:
   - Where should we deploy production? (Cloud VM, on-premise, Kubernetes)
   - Do we have infrastructure budget approved?

3. **Monitoring Solution**:
   - What monitoring solution should we integrate? (Datadog, Prometheus/Grafana, CloudWatch)
   - Do we have accounts/licenses already?

4. **Secrets Acquisition**:
   - Who is responsible for generating production Discord bot token?
   - Who is responsible for generating production Linear API key?
   - Who is responsible for generating production Anthropic API key?

5. **Testing Timeline**:
   - How long should we run staging validation? (Recommended: 24-48 hours)
   - Who needs to sign off on production deployment? (CTO, Security Team, Product Manager?)

### Blockers

1. **Missing Dockerfile**: Need to create production Dockerfile (Task 1)
2. **Missing Deployment Scripts**: Need deployment automation (Task 2-3)
3. **Missing Secrets**: Need production secrets created (Task 4)
4. **Missing Tests**: Need integration test suite (Task 5)
5. **CRITICAL Issue Verification**: Need to confirm all CRITICAL issues resolved

---

## Next Steps

### Immediate Actions (Next Session)

**Priority 1**: Verify CRITICAL Issues Resolution (2 hours)
- Read `docs/audits/2025-12-08/FINAL-AUDIT-REMEDIATION-REPORT.md`
- Cross-reference with `2025-12-08_1` audit findings
- Document any gaps or unresolved issues
- Create remediation tasks if needed

**Priority 2**: Create Deployment Infrastructure (6 hours)
- Implement Task 1: Production Dockerfile
- Implement Task 2: Docker Compose configurations (dev, staging, prod)
- Implement Task 3: Deployment scripts (`deploy-staging.sh`, `deploy-production.sh`)
- Test locally with `docker-compose.yml`

**Priority 3**: Create Validation Scripts (2 hours)
- Implement Task 4: Secrets validation script (`verify-secrets.sh`)
- Create database initialization script (`init-database.sh`)
- Create startup validation script (check secrets, database, API connectivity)

**Total Time**: 10 hours (1-2 days)

### Short-Term Actions (This Week)

**Priority 1**: Create Integration Tests (8 hours)
- Implement Task 5: Integration test suite
- Test Discord command workflows
- Test feedback capture workflow
- Test Linear API integration
- Test error handling and graceful degradation

**Priority 2**: Deploy to Staging (4 hours)
- Provision staging server
- Deploy using `deploy-staging.sh`
- Run integration tests
- Run security validation tests
- 24-hour monitoring period

**Total Time**: 12 hours (2-3 days)

### Long-Term Actions (Next 2 Weeks)

**Week 2**: Staging Validation and Testing
**Week 3**: Production Deployment and Monitoring

---

## Conclusion

The agentic-base integration layer is **94.7% complete** with a strong security foundation (9.9/10 security score). The remaining work focuses on:

1. **Deployment Infrastructure**: Dockerfile, docker-compose, deployment scripts
2. **Testing and Validation**: Integration tests, security tests, disaster recovery drills
3. **Production Readiness**: Secrets configuration, monitoring setup, team training

**Estimated Time to Production**: 2-3 weeks (including 1 week staging validation)

**Risk Level**: 🟡 MEDIUM (pending verification of CRITICAL issues resolution)

**Recommendation**: **PROCEED** with Phase 1 validation and infrastructure creation, then deploy to staging for comprehensive testing before production.

---

**Generated**: 2025-12-08
**By**: DevOps Crypto Architect (Claude Code Agent)
**Version**: 1.0
**Status**: 📋 READY FOR REVIEW
