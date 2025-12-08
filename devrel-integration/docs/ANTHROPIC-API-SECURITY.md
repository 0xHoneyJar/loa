# Anthropic API Key Security Documentation

**Document Version**: 1.0
**Last Updated**: December 8, 2025
**Owner**: Security Team
**Related Issues**: HIGH-010 (Anthropic API Key Privilege Documentation)

---

## Table of Contents

1. [Overview](#1-overview)
2. [API Key Security Model](#2-api-key-security-model)
3. [Least Privilege Configuration](#3-least-privilege-configuration)
4. [Key Creation and Management](#4-key-creation-and-management)
5. [Key Rotation Procedures](#5-key-rotation-procedures)
6. [Usage Monitoring and Cost Control](#6-usage-monitoring-and-cost-control)
7. [Rate Limiting and Throttling](#7-rate-limiting-and-throttling)
8. [Key Revocation Procedures](#8-key-revocation-procedures)
9. [Multi-Environment Strategy](#9-multi-environment-strategy)
10. [Incident Response](#10-incident-response)
11. [Compliance and Audit](#11-compliance-and-audit)
12. [Operational Procedures](#12-operational-procedures)

---

## 1. Overview

### Purpose

This document defines security policies, procedures, and best practices for managing Anthropic API keys used by the agentic-base integration system. Anthropic API keys provide programmatic access to Claude models for translation generation, document summarization, and executive communication tasks.

**Security Criticality**: HIGH
**Risk if Compromised**: Unauthorized API usage, cost escalation, data exposure, service disruption

### Scope

This document covers:
- API key creation, storage, rotation, and revocation
- Least privilege access configuration
- Usage monitoring and cost control
- Rate limiting and quota management
- Incident response for key compromise
- Compliance with SOC 2, GDPR, and security best practices

### Related Documents

- `config/secrets-rotation-policy.yaml` - Automated rotation schedule (180-day interval)
- `src/services/cost-monitor.ts` - Real-time cost tracking and budget enforcement
- `src/services/api-rate-limiter.ts` - Rate limiting and throttling (20 req/min)
- `src/services/translation-invoker-secure.ts` - Secure API invocation with retry logic
- `docs/DISASTER-RECOVERY.md` - Backup and recovery procedures (includes secrets)
- `README-SECURITY.md` - CRITICAL security implementations (CRITICAL-006, CRITICAL-008)

---

## 2. API Key Security Model

### Anthropic's Security Features

Anthropic provides the following security controls for API keys:

#### 2.1 Key Permissions (Limited Scoping)

**Current Limitations** (as of December 2025):
- ❌ Anthropic does **NOT** support fine-grained permissions for API keys
- ❌ Cannot restrict keys to specific models, workspaces, or operations
- ❌ All keys have full access to all Claude models and API endpoints
- ✅ Can assign keys to specific workspaces in multi-organization accounts

**Recommendation**: Due to lack of fine-grained permissions, implement application-level controls:
1. **Cost monitoring** - Budget limits to prevent runaway usage
2. **Rate limiting** - Request throttling to prevent quota exhaustion
3. **Usage tracking** - Audit all API calls with detailed logging
4. **Multi-environment keys** - Separate keys for dev/staging/production

**Feature Request**: Anthropic does not currently support more fine-grained permissions. Customers should submit feature requests for:
- Model-specific key restrictions (e.g., key limited to Claude Sonnet, not Opus)
- Operation-specific restrictions (e.g., read-only vs. write access)
- IP whitelisting for key usage

#### 2.2 Secret Scanning Integration

**GitHub Integration**:
- ✅ Anthropic partners with GitHub's Secret Scanning program
- ✅ Public repositories scanned automatically for exposed Claude API keys
- ✅ When key detected, GitHub notifies Anthropic and key is **automatically deactivated**
- ✅ Key pattern: `sk-ant-api03-[a-zA-Z0-9_-]{95}`

**Implementation**:
- Secret scanning enabled in `src/services/output-validator.ts:51`
- Secret detection in `src/services/secret-scanner.ts:146`
- Automated leak detection (CRITICAL-005, CRITICAL-008)

#### 2.3 Console Monitoring

**Available in Claude Console**:
- ✅ View API usage logs and patterns
- ✅ Set spending limits (Custom Rate Limit organizations)
- ✅ Configure auto-reload thresholds (Standard Rate Limit organizations)
- ✅ Review historical usage by key, model, and time period
- ✅ Track token consumption and costs

**Limitations**:
- ❌ No real-time alerting (must implement custom monitoring)
- ❌ No anomaly detection (must implement custom logic)
- ❌ No IP-based access logs

#### 2.4 Key Display Policy

**Security Note**:
- ⚠️ API keys displayed **ONLY ONCE** during creation
- ⚠️ Anthropic cannot retrieve or display the key after initial generation
- ⚠️ If key is lost, must create new key and revoke old one

**Implication**: Secure storage is mandatory. Lost keys cannot be recovered.

---

## 3. Least Privilege Configuration

### 3.1 Application-Level Access Control

Since Anthropic does not support API key scoping, implement least privilege at the application layer:

#### Model Selection Restriction

```typescript
// src/services/translation-invoker-secure.ts:330

// SECURITY: Restrict to most cost-effective model
const ALLOWED_MODEL = 'claude-sonnet-4-5-20250929';  // Sonnet only, not Opus

async invokeAIAgent(prompt: string): Promise<string> {
  const anthropic = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });

  const message = await anthropic.messages.create({
    model: ALLOWED_MODEL,  // NEVER use 'claude-opus' in production
    max_tokens: 4096,
    messages: [{ role: 'user', content: prompt }]
  });

  return message.content[0].text;
}
```

**Rationale**: Claude Opus is 5x more expensive than Sonnet. Restricting to Sonnet prevents accidental cost escalation.

#### Operation Restriction

```typescript
// Allowed operations for API key
const ALLOWED_OPERATIONS = [
  'document_translation',     // /translate command
  'executive_summary',        // DevRel translations
  'stakeholder_briefing'      // Board/investor communications
];

// DISALLOWED operations (even if API supports them)
const DISALLOWED_OPERATIONS = [
  'code_generation',          // Not required for our use case
  'image_analysis',           // Not required
  'long_context_processing'   // Use batch API if needed
];
```

### 3.2 Workspace Assignment (Multi-Org Accounts)

**If using Anthropic Enterprise with multiple workspaces**:

1. Create dedicated workspace: `agentic-base-production`
2. Assign API key to this workspace only
3. Do not use organization-wide keys
4. Limit workspace members to DevOps and Security teams

**Benefit**: Isolates API usage and prevents cross-workspace access.

### 3.3 Network-Level Restrictions

**Application-Level IP Whitelisting** (since Anthropic lacks native IP restrictions):

```typescript
// src/services/translation-invoker-secure.ts

const ALLOWED_SOURCE_IPS = [
  '10.0.1.0/24',        // Production server subnet
  '192.168.1.100/32'    // Emergency admin workstation
];

async function validateSourceIP(requestIP: string): Promise<boolean> {
  // Check if request originates from allowed IP range
  if (!ALLOWED_SOURCE_IPS.some(cidr => ipInRange(requestIP, cidr))) {
    logger.error('API call rejected: Source IP not whitelisted', { requestIP });
    return false;
  }
  return true;
}
```

**Note**: This is NOT a substitute for Anthropic native IP whitelisting (which doesn't exist), but provides application-layer defense.

---

## 4. Key Creation and Management

### 4.1 Key Creation Procedure

**When to Create New Keys**:
- ✅ Initial system setup
- ✅ Scheduled rotation (every 180 days, per `secrets-rotation-policy.yaml`)
- ✅ Multi-environment deployment (dev, staging, prod get separate keys)
- ✅ Key compromise (immediate rotation)
- ❌ NEVER share keys between environments or teams

**Creation Steps**:

1. **Log into Claude Console**:
   - Navigate to: https://console.anthropic.com/settings/keys
   - Authenticate with MFA (required for production key operations)

2. **Generate New Key**:
   - Click "Create Key"
   - **Key Name**: Use descriptive, environment-specific naming
     - ✅ Good: `agentic-base-prod-translation-2025-12-08`
     - ❌ Bad: `my-key`, `test`, `api-key-1`
   - **Workspace** (if multi-org): Select `agentic-base-production`
   - Click "Create"

3. **Copy Key Immediately**:
   - ⚠️ Key displayed **ONLY ONCE**
   - Copy to clipboard immediately
   - **DO NOT** close dialog until key is securely stored

4. **Store Key Securely**:
   - Production: Store in GPG-encrypted `.env.local` file (see DISASTER-RECOVERY.md)
   - Staging: Store in CI/CD secret vault (GitHub Secrets, GitLab CI Variables)
   - Development: Store in local `.env` file (NEVER commit to git, add to `.gitignore`)

5. **Verify Key Works**:
   ```bash
   # Test API call with new key
   curl https://api.anthropic.com/v1/messages \
     -H "x-api-key: $ANTHROPIC_API_KEY" \
     -H "anthropic-version: 2023-06-01" \
     -H "content-type: application/json" \
     -d '{
       "model": "claude-sonnet-4-5-20250929",
       "max_tokens": 10,
       "messages": [{"role": "user", "content": "Hello"}]
     }'
   ```

6. **Update Rotation Tracking**:
   - Edit `config/secrets-rotation-policy.yaml`
   - Update `last_rotated` field: `"2025-12-08"`
   - Next rotation calculated automatically: `"2026-06-06"` (180 days)

### 4.2 Key Naming Convention

**Format**: `{project}-{environment}-{purpose}-{date}`

**Examples**:
- `agentic-base-prod-translation-2025-12-08`
- `agentic-base-staging-testing-2025-12-08`
- `agentic-base-dev-local-2025-12-08`

**Benefits**:
- Easy to identify key purpose in Console
- Rotation date visible in name (aids audit)
- Environment clearly indicated (prevents prod key in dev)

### 4.3 Key Storage

#### Production Environment

**Storage Location**: `/opt/agentic-base/integration/.env.local`

**Permissions**:
```bash
chmod 600 .env.local           # Owner read/write only
chown app:app .env.local       # Application user ownership
```

**Encryption**: GPG-encrypted backup (see `scripts/backup-secrets.sh`)

**Format**:
```bash
# .env.local (production)
ANTHROPIC_API_KEY=sk-ant-api03-XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
```

#### Staging/CI Environment

**GitHub Actions Secrets**:
1. Navigate to: `Settings > Secrets and variables > Actions`
2. Click "New repository secret"
3. Name: `ANTHROPIC_API_KEY_STAGING`
4. Value: `sk-ant-api03-...`
5. Click "Add secret"

**GitLab CI/CD Variables**:
1. Navigate to: `Settings > CI/CD > Variables`
2. Click "Add variable"
3. Key: `ANTHROPIC_API_KEY_STAGING`
4. Value: `sk-ant-api03-...`
5. Flags: ✅ Protected, ✅ Masked
6. Click "Add variable"

#### Development Environment

**Local `.env` file**:
```bash
# .env (development)
ANTHROPIC_API_KEY=sk-ant-api03-DEV_KEY_HERE
NODE_ENV=development
```

**CRITICAL**: Ensure `.env` is in `.gitignore`:
```
# .gitignore
.env
.env.local
.env.*.local
```

### 4.4 Key Metadata Tracking

**Maintain inventory in secure location** (e.g., password manager, KMS):

| Key Name | Environment | Created Date | Last Rotated | Next Rotation | Status |
|----------|-------------|--------------|--------------|---------------|--------|
| agentic-base-prod-translation-2025-12-08 | Production | 2025-12-08 | 2025-12-08 | 2026-06-06 | Active |
| agentic-base-staging-testing-2025-12-08 | Staging | 2025-12-08 | 2025-12-08 | 2026-06-06 | Active |
| agentic-base-prod-translation-2025-06-08 | Production | 2025-06-08 | 2025-06-08 | 2025-12-04 | Revoked |

---

## 5. Key Rotation Procedures

### 5.1 Rotation Schedule

**Rotation Interval**: 180 days (per `config/secrets-rotation-policy.yaml:30`)

**Rationale**:
- Anthropic recommendation: 90 days
- Our policy: 180 days for API keys (less frequent access than bot tokens)
- Balances security (regular rotation) with operational overhead

**Reminder Timeline**:
- **Day 166** (14 days before expiry): Email + Discord notification
- **Day 173** (7 days before expiry): Email + Discord notification (escalated)
- **Day 180** (expiry): CRITICAL alert, service may pause (if `auto_pause_on_leak: true`)
- **Day 181+**: Daily critical alerts until rotation complete

### 5.2 Planned Rotation Procedure

**When to Execute**: Every 180 days (scheduled maintenance window)

**Prerequisites**:
- [ ] Maintenance window scheduled (low-traffic period)
- [ ] Team notified of upcoming rotation
- [ ] Backup of current `.env.local` file created

**Steps**:

1. **Create New Key** (see Section 4.1):
   - Generate new key in Claude Console
   - Name: `agentic-base-prod-translation-{DATE}`
   - Copy key immediately

2. **Update Environment Variables**:
   ```bash
   # Backup current key
   cp .env.local .env.local.backup-$(date +%Y%m%d)

   # Update .env.local with new key
   sed -i 's/ANTHROPIC_API_KEY=.*/ANTHROPIC_API_KEY=NEW_KEY_HERE/' .env.local
   ```

3. **Restart Application**:
   ```bash
   # Docker Compose
   docker-compose restart

   # PM2
   pm2 restart agentic-base-bot
   ```

4. **Verify New Key Works**:
   ```bash
   # Check application logs
   docker-compose logs -f agentic-base-bot
   # Look for: "Anthropic API connection successful"

   # Test translation command in Discord
   /translate @docs/prd.md for executives
   ```

5. **Monitor for 15 Minutes**:
   - Check application logs for errors
   - Verify translation commands work
   - Check cost monitor dashboard (no spike in failed requests)

6. **Revoke Old Key**:
   - Log into Claude Console
   - Navigate to API Keys page
   - Find old key (e.g., `agentic-base-prod-translation-2025-06-08`)
   - Click menu → "Delete API Key"
   - Confirm deletion

7. **Update Rotation Tracking**:
   ```yaml
   # config/secrets-rotation-policy.yaml
   anthropic_api_key:
     interval_days: 180
     last_rotated: "2025-12-08"  # ← Update this
     next_rotation: "2026-06-06"  # ← Calculated automatically
   ```

8. **Audit Trail**:
   ```bash
   # Log rotation event
   echo "$(date -Iseconds) - Rotated Anthropic API key (scheduled rotation)" >> logs/secrets-rotation.log
   ```

9. **Backup New Key**:
   ```bash
   # Encrypted backup
   ./scripts/backup-secrets.sh
   ```

### 5.3 Emergency Rotation (Key Compromise)

**Trigger Conditions**:
- Key exposed in public repository
- Key detected in application logs
- Unauthorized usage detected (cost spike, unusual API calls)
- Security team notification of potential breach

**Emergency Procedure** (execute within 15 minutes):

1. **IMMEDIATELY Revoke Compromised Key**:
   - Log into Claude Console
   - Navigate to API Keys → Find compromised key
   - Delete key **immediately** (do NOT wait for new key)
   - Service will stop working (acceptable during incident)

2. **Create New Key** (5 minutes):
   - Generate new key in Console
   - Copy key immediately
   - Store securely

3. **Update Environment and Restart** (5 minutes):
   ```bash
   # Update key
   nano .env.local  # Replace ANTHROPIC_API_KEY value

   # Restart immediately
   docker-compose restart  # OR pm2 restart agentic-base-bot
   ```

4. **Verify Service Restored** (2 minutes):
   ```bash
   # Check logs
   docker-compose logs -f agentic-base-bot

   # Test command
   /translate @docs/prd.md for executives
   ```

5. **Audit Unauthorized Usage** (30 minutes):
   - Log into Claude Console → Usage tab
   - Filter by old key (before revocation)
   - Review all API calls in last 48 hours
   - Document suspicious activity:
     - Unusual models (e.g., Opus instead of Sonnet)
     - High token consumption spikes
     - Requests outside business hours
     - Unexpected geographic origin (if available)

6. **Notify Stakeholders** (immediate):
   - Email: security-team@company.com, cto@company.com
   - Discord: Post to #security-alerts channel
   - Subject: "SECURITY INCIDENT: Anthropic API Key Compromised and Rotated"
   - Include: Time of detection, revocation time, estimated exposure window, action taken

7. **Update Rotation Tracking**:
   ```yaml
   # config/secrets-rotation-policy.yaml
   anthropic_api_key:
     last_rotated: "2025-12-08"  # Emergency rotation date
     next_rotation: "2026-06-06"
   ```

8. **Root Cause Analysis** (within 24 hours):
   - How was key exposed?
   - What systems/repositories were affected?
   - What controls failed?
   - What additional remediation is needed?

### 5.4 Rotation Automation

**Future Enhancement**: Automate key rotation via script

**Design**:
```bash
#!/bin/bash
# scripts/rotate-anthropic-key.sh

# 1. Check if rotation due (read from secrets-rotation-policy.yaml)
# 2. If due, send notification to security team
# 3. Manual approval required (read from approval file)
# 4. If approved, generate new key via Anthropic API (if available)
# 5. Update .env.local atomically
# 6. Restart application
# 7. Verify new key works
# 8. Revoke old key via Anthropic API
# 9. Update secrets-rotation-policy.yaml
# 10. Send completion notification
```

**Note**: Anthropic API does not currently support key generation via API. Rotation must be manual until feature is available.

---

## 6. Usage Monitoring and Cost Control

### 6.1 Real-Time Cost Tracking

**Implementation**: `src/services/cost-monitor.ts:48`

**Budget Configuration**:
```typescript
private budgetConfig: BudgetConfig = {
  dailyBudgetUSD: 100,        // $100/day limit
  monthlyBudgetUSD: 3000,     // $3000/month limit
  alertThresholdPercent: 75,  // Alert at 75% of budget
  pauseOnExceed: true         // Auto-pause if budget exceeded
};
```

**Cost Tracking per API Call**:
```typescript
await costMonitor.trackAPICall(
  'anthropic',
  'document_translation',
  tokensUsed: 2500,
  model: 'claude-sonnet-4-5-20250929'
);
```

**Budget Alerts**:
- **75% threshold**: Email notification to finance and engineering teams
- **90% threshold**: Escalated alert to CTO and security team
- **100% threshold**: CRITICAL alert, service auto-pauses if `pauseOnExceed: true`

### 6.2 Cost Estimation

**Claude Sonnet 4.5 Pricing** (as of December 2025):
- Input tokens: $3.00 per million tokens
- Output tokens: $15.00 per million tokens

**Typical Translation Costs**:
| Document Size | Input Tokens | Output Tokens | Cost per Translation |
|---------------|--------------|---------------|----------------------|
| 1 page (~500 words) | 700 | 500 | $0.0096 |
| 10 pages (~5,000 words) | 7,000 | 3,500 | $0.0735 |
| 50 pages (~25,000 words) | 35,000 | 15,000 | $0.3300 |

**Daily Budget Calculation**:
- **$100/day budget** → ~1,300 translations of 1-page documents
- **$100/day budget** → ~130 translations of 10-page documents
- **$100/day budget** → ~30 translations of 50-page documents

**Recommendation**: Monitor usage patterns weekly, adjust budget based on team size and usage trends.

### 6.3 Console Usage Monitoring

**Claude Console Dashboards**:

1. **Usage Overview**:
   - Navigate to: Console → Usage
   - View: Total requests, tokens consumed, costs by day/week/month
   - Filter: By API key, model, date range

2. **Cost Breakdown**:
   - Navigate to: Console → Billing
   - View: Itemized costs by model and date
   - Download: CSV export for finance reporting

3. **Spending Limits** (Custom Rate Limit orgs only):
   - Navigate to: Console → Settings → Billing
   - Set: Hard limit (service stops at limit)
   - Set: Soft limit (alert only, service continues)

**Monitoring Frequency**:
- **Daily**: Check cost dashboard (automated script)
- **Weekly**: Review usage trends, adjust budgets if needed
- **Monthly**: Export usage report for finance and compliance

### 6.4 Anomaly Detection

**Automated Alerts for Suspicious Usage**:

```typescript
// src/services/cost-monitor.ts (enhancement)

async detectAnomalies(): Promise<void> {
  // Baseline: Average usage over last 7 days
  const baseline = this.calculateBaselineUsage(7);

  // Current usage: Last 1 hour
  const currentUsage = this.getCurrentUsage(1);

  // Anomaly: Usage spike >3x baseline
  if (currentUsage > baseline * 3) {
    logger.error('ANOMALY DETECTED: API usage spike', {
      baseline,
      currentUsage,
      factor: currentUsage / baseline
    });

    // Send alert
    await this.sendAlert({
      severity: 'HIGH',
      message: 'Anthropic API usage spike detected (3x normal)',
      action: 'Review recent API calls for unauthorized usage'
    });
  }
}
```

**Alert Triggers**:
- Usage spike (>3x baseline in 1 hour)
- Cost spike (>$50 in 1 hour)
- Unusual model usage (Opus instead of Sonnet)
- Requests outside business hours (8 PM - 8 AM)
- Failed authentication attempts (>5 in 15 minutes)

---

## 7. Rate Limiting and Throttling

### 7.1 Anthropic API Rate Limits

**Tier-Based Limits** (as of December 2025):

| Tier | Requests/Min | Tokens/Min (Input) | Tokens/Min (Output) | Typical Usage |
|------|--------------|-------------------|---------------------|---------------|
| Tier 1 (Free) | 50 | 40,000 | 8,000 | Development, testing |
| Tier 2 (Build) | 1,000 | 80,000 | 16,000 | Small production |
| Tier 3 (Scale) | 2,000 | 160,000 | 32,000 | Medium production |
| Tier 4 (Custom) | Negotiated | Negotiated | Negotiated | Enterprise |

**Our Tier**: Tier 2 (Build) - 1,000 req/min, 80k tokens/min

### 7.2 Application-Level Rate Limiting

**Implementation**: `src/services/api-rate-limiter.ts:85`

**Conservative Limit**: 20 requests/minute (5% of Tier 2 limit)

**Rationale**:
- Prevents quota exhaustion from bugs or DoS attacks
- Leaves headroom for burst traffic (50x buffer)
- Multiple services may share same key

**Configuration**:
```typescript
async throttleAnthropicAPI<T>(operation: () => Promise<T>): Promise<T> {
  const api = 'anthropic';

  // Check rate limit (20 req/min)
  await this.checkAPIRateLimit(api);

  try {
    const result = await operation();
    this.recordRequest(api);
    return result;
  } catch (error) {
    if (this.isRateLimitError(error)) {
      // Exponential backoff: 1s, 2s, 4s, 8s
      await this.exponentialBackoff(api);
      return await operation();  // Retry once
    }
    throw error;
  }
}
```

### 7.3 Exponential Backoff

**Retry Strategy**:
- Initial delay: 1 second
- Max delay: 8 seconds
- Max retries: 3 attempts
- Backoff factor: 2x (1s → 2s → 4s → 8s)

**Implementation**: `src/services/retry-handler.ts` (HIGH-004)

**Error Codes Triggering Backoff**:
- `429` - Rate limit exceeded
- `529` - Service overloaded
- `503` - Service temporarily unavailable

### 7.4 Circuit Breaker

**Implementation**: `src/services/circuit-breaker.ts` (HIGH-004)

**States**:
- **CLOSED**: Normal operation, all requests pass through
- **OPEN**: Too many failures (≥5), block all requests for 60 seconds
- **HALF_OPEN**: After 60 seconds, allow 1 test request

**Benefits**:
- Prevents cascading failures
- Saves API costs (stops calling failing API)
- Fast recovery when API restored

**Thresholds**:
```typescript
{
  failureThreshold: 5,       // Open circuit after 5 failures
  resetTimeoutMs: 60000,     // Test recovery after 60 seconds
  successThreshold: 2        // Close circuit after 2 successes
}
```

---

## 8. Key Revocation Procedures

### 8.1 When to Revoke Keys

**Immediate Revocation**:
- ✅ Key exposed in public repository (GitHub, GitLab, etc.)
- ✅ Key detected in application logs
- ✅ Key detected in error messages or support tickets
- ✅ Unauthorized usage detected (cost spike, unusual API calls)
- ✅ Employee offboarding (if personal account used)
- ✅ Suspected compromise (phishing, malware, etc.)

**Scheduled Revocation**:
- ✅ After successful rotation (revoke old key)
- ✅ After 180 days (per rotation policy)
- ✅ After migration to new environment (revoke old environment key)

**DO NOT Revoke**:
- ❌ During active translation operations (wait for completion)
- ❌ Without creating replacement key first (except emergencies)
- ❌ Without notifying team first (except emergencies)

### 8.2 Revocation Procedure

**Standard Revocation** (planned, non-emergency):

1. **Pre-Revocation Checklist**:
   - [ ] New key generated and tested
   - [ ] New key deployed to production
   - [ ] Application restarted with new key
   - [ ] New key verified functional (test translation command)
   - [ ] Team notified of upcoming revocation

2. **Revoke Key in Console**:
   - Log into Claude Console
   - Navigate to: Settings → API Keys
   - Find old key in list
   - Click menu (⋮) next to key
   - Select "Delete API Key"
   - Confirm deletion with "Yes, delete this key"

3. **Verify Revocation**:
   - Key should disappear from API Keys list immediately
   - Test that old key no longer works:
     ```bash
     curl -H "x-api-key: OLD_KEY_HERE" https://api.anthropic.com/v1/messages/...
     # Should return: 401 Unauthorized
     ```

4. **Update Documentation**:
   - Update key inventory (Section 4.4 table)
   - Mark old key as "Revoked" with revocation date
   - Archive old key metadata (do NOT store revoked key value)

**Emergency Revocation** (compromised key):

1. **Revoke Immediately** (do NOT wait for replacement):
   - Log into Console
   - Delete compromised key **immediately**
   - Service will stop (acceptable during incident)

2. **Generate Replacement Key** (within 5 minutes):
   - Create new key (see Section 4.1)
   - Deploy to production
   - Restart application

3. **Incident Response** (see Section 10)

### 8.3 Post-Revocation Verification

**Checklist**:
- [ ] Application still running (no crashes)
- [ ] Translation commands work (`/translate @docs/prd.md for executives`)
- [ ] No errors in application logs
- [ ] Cost monitor shows continued API usage (confirms new key in use)
- [ ] Old key returns 401 Unauthorized if tested

---

## 9. Multi-Environment Strategy

### 9.1 Environment Isolation

**Principle**: Each environment (dev, staging, prod) must have separate API keys.

**Benefits**:
- Prevents dev/staging usage from exhausting prod quota
- Isolates security incidents (compromised dev key ≠ compromised prod key)
- Enables environment-specific rate limits and budgets
- Simplifies auditing (track costs per environment)

### 9.2 Environment Configuration

| Environment | Key Name | Budget | Rate Limit | Rotation Interval |
|-------------|----------|--------|------------|-------------------|
| **Production** | `agentic-base-prod-translation-{DATE}` | $100/day | 20 req/min | 180 days |
| **Staging** | `agentic-base-staging-testing-{DATE}` | $10/day | 5 req/min | 180 days |
| **Development** | `agentic-base-dev-local-{DATE}` | $5/day | 2 req/min | 365 days |

### 9.3 Development Environment

**Key Storage**: Local `.env` file (NOT committed to git)

**Restrictions**:
- Lower budget ($5/day) to prevent accidental cost escalation
- Lower rate limit (2 req/min) to encourage efficient testing
- Longer rotation interval (365 days) for developer convenience

**Best Practices**:
- Use mock responses for unit tests (see `translation-invoker-secure.ts:348`)
- Only use real API for integration tests
- Run `NODE_ENV=test` for automated tests (uses mock, not real API)

### 9.4 CI/CD Environment

**GitHub Actions Secrets**:
```yaml
# .github/workflows/test.yml
env:
  ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY_STAGING }}
  NODE_ENV: test  # Use mock responses for CI tests
```

**GitLab CI Variables**:
```yaml
# .gitlab-ci.yml
test:
  variables:
    ANTHROPIC_API_KEY: $ANTHROPIC_API_KEY_STAGING
    NODE_ENV: test
```

**Best Practices**:
- Use staging key (NOT production key) in CI/CD
- Set `NODE_ENV=test` to use mock responses (avoid API costs)
- Only run real API integration tests in nightly builds

---

## 10. Incident Response

### 10.1 Incident Classification

| Severity | Scenario | Response Time | Action |
|----------|----------|---------------|--------|
| **CRITICAL** | Key in public GitHub repo | 15 minutes | Immediate revocation, emergency rotation |
| **HIGH** | Unauthorized usage detected (cost spike >$500) | 1 hour | Revoke key, audit usage, root cause analysis |
| **MEDIUM** | Key in application logs | 4 hours | Rotate key, clean logs, audit trail |
| **LOW** | Routine rotation overdue | 24 hours | Scheduled rotation, update tracking |

### 10.2 Incident Response Playbook: Key Compromise

**Trigger**: Key detected in public repository, logs, or unauthorized usage

**Response Steps**:

1. **Contain (0-15 minutes)**:
   - Revoke compromised key in Console
   - Service will stop (acceptable)
   - Generate new key immediately
   - Deploy new key and restart application

2. **Assess (15-60 minutes)**:
   - Log into Claude Console → Usage
   - Filter by compromised key (before revocation)
   - Review all API calls in last 48 hours:
     - Time of first unauthorized call
     - Total unauthorized usage (requests, tokens, cost)
     - Models used (Sonnet vs. Opus)
     - Unusual patterns (geographic, time-of-day)
   - Determine:
     - When was key compromised?
     - What data was accessed (if any)?
     - Estimated cost impact

3. **Notify (immediate)**:
   - Email: security-team@company.com, cto@company.com
   - Discord: Post to #security-alerts
   - Include: Time of detection, revocation time, exposure window, cost impact

4. **Investigate (1-24 hours)**:
   - **Root Cause**: How was key exposed?
     - Committed to git? (Check git history: `git log -S 'sk-ant-api03'`)
     - Logged to file? (Check application logs)
     - Shared via Slack/email? (Audit communication channels)
     - Phishing/malware? (Check employee devices)
   - **Blast Radius**: What other secrets may be exposed?
     - Check same repository for other secrets
     - Run secret scanner: `./scripts/secret-scanner.sh`
   - **Timeline**: Reconstruct sequence of events

5. **Remediate (1-7 days)**:
   - Fix root cause (e.g., add `.env` to `.gitignore`)
   - Remove leaked key from git history (if in public repo):
     ```bash
     # Use BFG Repo-Cleaner or git-filter-repo
     git filter-repo --invert-paths --path .env
     git push --force
     ```
   - Update secrets scanning CI/CD checks
   - Team training (if human error)

6. **Document (7 days)**:
   - Create post-incident report:
     - Timeline of events
     - Root cause analysis
     - Impact assessment (cost, data exposure)
     - Remediation actions taken
     - Lessons learned
     - Action items to prevent recurrence

### 10.3 Incident Response: Cost Spike

**Trigger**: Daily budget exceeded ($100+), unusual cost spike

**Response Steps**:

1. **Verify (0-5 minutes)**:
   - Check cost monitor dashboard
   - Confirm spike is real (not false positive)
   - Identify time period of spike

2. **Pause (if auto-pause disabled)**:
   ```typescript
   // Manually trigger service pause
   costMonitor.pauseService('Manual pause due to cost spike investigation');
   ```

3. **Investigate (5-30 minutes)**:
   - Review application logs for unusual activity
   - Check for:
     - Infinite loops (retrying failed API calls)
     - DoS attack (flood of /translate commands)
     - Misconfigured retry logic
     - Accidental Opus usage (should be Sonnet only)

4. **Remediate**:
   - Fix bug/misconfiguration
   - Restart application
   - Resume service:
     ```typescript
     costMonitor.resumeService();
     ```

5. **Monitor**:
   - Watch costs for next 24 hours
   - Verify spike does not recur

---

## 11. Compliance and Audit

### 11.1 SOC 2 Compliance

**Trust Service Criteria**:

| Criterion | Requirement | Implementation |
|-----------|-------------|----------------|
| **CC6.1** | Logical access controls | API key restricted to production servers only (IP whitelisting) |
| **CC6.6** | Access is removed timely | Key revocation within 15 minutes of offboarding/compromise |
| **CC6.7** | Access controls for privileged users | Admin-only access to Claude Console (MFA required) |
| **CC7.2** | Monitoring activities | Real-time cost monitoring, usage alerts, anomaly detection |

**Audit Evidence**:
- Key rotation logs (`logs/secrets-rotation.log`)
- Usage logs (Claude Console exports)
- Cost monitor alerts (email/Discord records)
- Incident response records (post-incident reports)

### 11.2 GDPR Compliance

**Data Protection Requirements**:

| Article | Requirement | Implementation |
|---------|-------------|----------------|
| **Article 32** | Security of processing | Encrypted key storage (GPG), regular rotation (180 days) |
| **Article 33** | Breach notification | Incident response playbook (notify within 72 hours) |
| **Article 25** | Data protection by design | Least privilege (application-level restrictions), cost monitoring |

**Personal Data Handling**:
- API prompts MAY contain PII (document author names, email addresses)
- Anthropic's policy: Does NOT train on API data
- Data retention: API requests logged for 30 days (Anthropic policy), then deleted

### 11.3 Audit Trail

**Events Logged**:
- Key creation (manual log in Console)
- Key rotation (automated log in `logs/secrets-rotation.log`)
- Key revocation (manual log in Console)
- API usage (automatic via Claude Console)
- Cost alerts (email/Discord records)
- Budget exceeded events (cost monitor logs)
- Anomalies detected (application logs)

**Retention**:
- Rotation logs: 365 days (per `secrets-rotation-policy.yaml:112`)
- Application logs: 90 days (per DISASTER-RECOVERY.md)
- Claude Console data: 30 days (Anthropic policy)

**Audit Queries**:
```sql
-- Example: Query cost monitor logs for high-cost API calls
SELECT timestamp, operation, tokensUsed, costUSD
FROM cost_records
WHERE costUSD > 1.0  -- Flag calls costing >$1
ORDER BY costUSD DESC
LIMIT 100;
```

---

## 12. Operational Procedures

### 12.1 Daily Operations

**Automated Checks** (cron job, 9:00 AM daily):
```bash
#!/bin/bash
# scripts/anthropic-api-daily-check.sh

# 1. Check if key rotation due
DAYS_UNTIL_ROTATION=$(./scripts/check-rotation-status.sh anthropic_api_key)
if [ "$DAYS_UNTIL_ROTATION" -le 14 ]; then
  # Send reminder notification
  echo "⚠️ Anthropic API key rotation due in $DAYS_UNTIL_ROTATION days" | \
    ./scripts/send-discord-notification.sh security-alerts
fi

# 2. Check cost usage
DAILY_SPEND=$(./scripts/get-daily-cost.sh)
if (( $(echo "$DAILY_SPEND > 75" | bc -l) )); then
  # Alert: 75% of $100/day budget
  echo "⚠️ Anthropic API daily spend: \$$DAILY_SPEND (75% of budget)" | \
    ./scripts/send-discord-notification.sh engineering-alerts
fi

# 3. Check for anomalies
./scripts/detect-api-anomalies.sh
```

### 12.2 Weekly Operations

**Usage Review** (Friday, 4:00 PM):
1. Log into Claude Console → Usage
2. Export usage report (CSV)
3. Review:
   - Total requests this week
   - Total cost this week
   - Top 10 most expensive API calls
   - Any unusual patterns
4. Share summary with engineering team (Discord #engineering)

### 12.3 Monthly Operations

**Billing Reconciliation**:
1. Export monthly usage from Claude Console
2. Compare with internal cost monitor logs
3. Identify discrepancies (if any)
4. Submit report to finance team

**Security Audit**:
1. Review all API keys in Console
2. Verify all keys are named and tracked
3. Check for unused keys (no usage in 30 days) → revoke
4. Verify rotation schedule is current
5. Review incident logs (if any key compromises)

### 12.4 Quarterly Operations

**Compliance Audit** (see Section 11.1):
1. Export rotation logs, usage logs, cost logs
2. Verify SOC 2 and GDPR compliance
3. Generate audit report for compliance team
4. Address any findings

**Policy Review**:
1. Review this document (ANTHROPIC-API-SECURITY.md)
2. Update budget limits if needed (based on usage trends)
3. Update rotation intervals if Anthropic recommendations change
4. Incorporate lessons learned from incidents

---

## Appendix A: Quick Reference

### Key Creation
```bash
# 1. Create key in Console: https://console.anthropic.com/settings/keys
# 2. Name: agentic-base-prod-translation-YYYY-MM-DD
# 3. Copy key immediately (only shown once)
# 4. Store in .env.local
# 5. Update secrets-rotation-policy.yaml
```

### Key Rotation (Planned)
```bash
# 1. Create new key in Console
# 2. Update .env.local
# 3. Restart: docker-compose restart
# 4. Verify: /translate @docs/prd.md for executives
# 5. Revoke old key in Console
# 6. Update secrets-rotation-policy.yaml
```

### Key Revocation (Emergency)
```bash
# 1. Revoke in Console (immediate)
# 2. Create new key
# 3. Update .env.local
# 4. Restart: docker-compose restart
# 5. Notify: security-team@company.com
# 6. Audit unauthorized usage in Console
```

### Cost Check
```bash
# Daily cost
curl -s "$(./scripts/get-daily-cost.sh)"

# Monthly cost
# Log into Console → Billing
```

### Test API Key
```bash
curl https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{
    "model": "claude-sonnet-4-5-20250929",
    "max_tokens": 10,
    "messages": [{"role": "user", "content": "Hello"}]
  }'
```

---

## Appendix B: Sources

This document references official Anthropic documentation and security best practices:

- [API Key Best Practices: Keeping Your Keys Safe and Secure | Claude Help Center](https://support.claude.com/en/articles/9767949-api-key-best-practices-keeping-your-keys-safe-and-secure)
- [Anthropic Claude API Key: The Essential Guide | Nightfall AI Security 101](https://www.nightfall.ai/ai-security-101/anthropic-claude-api-key)
- [Claude API Integration Complete Tutorial Guide for Anthropic](https://www.blackmoreops.com/claude-api-integration-complete-tutorial-guide/)

---

**Document End**

**Next Steps**:
1. Review and approve this document (Security Team)
2. Implement automated rotation checks (DevOps Team)
3. Schedule quarterly policy review (Compliance Team)
4. Train team on key management procedures (All Engineering)
