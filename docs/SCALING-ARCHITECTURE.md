# Scaling Architecture Guide

**Document:** Onomancer Bot Scaling Architecture
**Version:** 1.0
**Date:** 2025-12-15
**Author:** Architecture Designer Agent
**Status:** Approved for Implementation

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Current Scale Targets](#current-scale-targets)
3. [Multi-Tenancy Architecture](#multi-tenancy-architecture)
4. [Caching Architecture](#caching-architecture)
5. [Unit Economics](#unit-economics)
6. [Implementation Roadmap](#implementation-roadmap)
7. [Monitoring & Observability](#monitoring--observability)

---

## Executive Summary

This document defines the scaling architecture for Onomancer Bot, designed to support:

- **MVP**: 10-20 concurrent users, 5-10 projects, single tenant
- **Future SaaS**: Multi-tenant deployment with per-tenant billing

### Key Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Multi-tenancy prep | Tenant Context Pattern | Minimal overhead now, easy extension later |
| Caching strategy | Content-Addressable + Tiered | Maximum cache hits, reduced API costs |
| Primary cost driver | Claude API tokens | Caching reduces by ~80% |
| SaaS cost model | Tenant-owned Workspace | Shifts fixed costs to tenants |

### Quick Reference: Cost Per Transformation

| Scenario | Cost |
|----------|------|
| Uncached (4 personas) | ~$0.28 |
| Cached (90% hit rate) | ~$0.03 |
| Monthly (50 transforms) | ~$14-40 |

---

## Current Scale Targets

### MVP Phase (Single Tenant)

| Dimension | Target | Notes |
|-----------|--------|-------|
| Concurrent users | 10-20 | Team stability priority |
| Projects/products | 5-10 | Multi-project support |
| Transformations/day | 5-20 | With intelligent caching |
| Weekly digests | 4 | One per persona |

### Resource Requirements

```
┌─────────────────────────────────────────────────────┐
│           Single Server Deployment                   │
├─────────────────────────────────────────────────────┤
│  CPU: 2 cores                                        │
│  RAM: 4GB (2GB app + 2GB Redis)                     │
│  Storage: 20GB SSD                                  │
│  Network: 100 Mbps                                  │
└─────────────────────────────────────────────────────┘
```

### External API Quotas

| Service | Quota | Expected Usage | Headroom |
|---------|-------|----------------|----------|
| Claude API | 50 req/min | ~10 req/min | 5x |
| Google Drive API | 12,000 req/min | ~100 req/min | 120x |
| Google Docs API | 300 req/min/user | ~50 req/min | 6x |
| Linear API | 600 req/min | ~20 req/min | 30x |
| Discord API | 50 req/sec | ~1 req/sec | 50x |

---

## Multi-Tenancy Architecture

### Design Philosophy

**Build for today, design for tomorrow.**

- MVP: Single tenant with hardcoded config
- Future: Multi-tenant with per-tenant isolation
- Transition: Minimal refactoring required

### Tenant Context Pattern

```typescript
// src/types/tenant.ts
interface TenantContext {
  tenantId: string;           // Unique identifier (e.g., "thj", "acme-corp")
  name: string;               // Display name
  config: TenantConfig;       // Tenant-specific settings
  quotas: TenantQuotas;       // Usage limits
  credentials: TenantCreds;   // API credentials (encrypted)
}

interface TenantConfig {
  googleWorkspaceId?: string;       // Tenant's Workspace (optional)
  discordServerId: string;          // Discord server ID
  defaultPersonas: string[];        // Which personas to generate
  folderIds: Record<string, string>;// Google Drive folder mapping
}

interface TenantQuotas {
  transformationsPerDay: number;    // e.g., 50
  transformationsPerMonth: number;  // e.g., 1000
  storageGB: number;                // e.g., 10
  usersMax: number;                 // e.g., 20
}
```

### Implementation Guidelines

#### 1. Service Layer Pattern

```typescript
// BEFORE (MVP - implicit single tenant)
class TransformationService {
  async transform(document: Document, persona: string): Promise<Result> {
    const folderId = process.env.GOOGLE_FOLDER_ID; // Hardcoded
    // ...
  }
}

// AFTER (Tenant-aware)
class TransformationService {
  async transform(
    ctx: TenantContext,  // Added tenant context
    document: Document,
    persona: string
  ): Promise<Result> {
    const folderId = ctx.config.folderIds[persona];
    // ...
  }
}
```

#### 2. Storage Key Namespacing

```typescript
// Cache keys - always prefix with tenantId
const cacheKey = `${tenantId}:transform:${contentHash}:${persona}`;
const sessionKey = `${tenantId}:session:${userId}`;

// Google Drive paths
const folderPath = `/tenants/${tenantId}/Products/${product}/`;

// Database queries
const issues = await db.query(
  'SELECT * FROM issues WHERE tenant_id = ?',
  [tenantId]
);
```

#### 3. Usage Tracking

```typescript
interface UsageRecord {
  tenantId: string;
  userId: string;
  timestamp: Date;
  operation: 'transform' | 'query' | 'storage';
  details: {
    inputTokens?: number;
    outputTokens?: number;
    storageBytes?: number;
    apiCalls?: number;
  };
}

// Track every billable operation
async function trackUsage(ctx: TenantContext, op: UsageRecord): Promise<void> {
  await db.insert('usage_records', {
    ...op,
    tenantId: ctx.tenantId,
  });
}
```

#### 4. Configuration Externalization

```
config/
├── tenants/
│   ├── thj.json           # Current tenant (MVP)
│   └── {tenant-id}.json   # Future tenants
├── defaults.json          # Default settings
└── quotas.json            # Quota tiers
```

```json
// config/tenants/thj.json
{
  "tenantId": "thj",
  "name": "The Honey Jar",
  "config": {
    "discordServerId": "123456789",
    "googleWorkspaceId": "C0xxxxxx",
    "defaultPersonas": ["leadership", "product", "marketing", "devrel"],
    "folderIds": {
      "root": "1abc...",
      "products": "2def...",
      "shared": "3ghi..."
    }
  },
  "quotas": {
    "transformationsPerDay": 100,
    "transformationsPerMonth": 2000,
    "storageGB": 50,
    "usersMax": 50
  }
}
```

---

## Caching Architecture

### Cache Flow Diagram

```
┌──────────────────────────────────────────────────────────────────┐
│                    Transformation Request                         │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│  1. Generate Content Hash                                         │
│     contentHash = sha256(normalize(document.content))            │
│     cacheKey = `${tenantId}:transform:${contentHash}:${persona}` │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│  2. Check L1 Cache (In-Memory)                                   │
│     TTL: 1-5 minutes | Size: 100 entries                         │
│     ├── HIT  → Return immediately                                │
│     └── MISS → Continue to L2                                    │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│  3. Check L2 Cache (Redis)                                       │
│     TTL: 15-60 minutes | Size: Unlimited                         │
│     ├── HIT  → Promote to L1, Return                             │
│     └── MISS → Continue to L3                                    │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│  4. Check L3 Cache (Google Docs - Permanent)                     │
│     TTL: Permanent | Size: Unlimited                             │
│     ├── HIT  → Promote to L1+L2, Return                          │
│     └── MISS → Continue to Transform                             │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│  5. Transform (Cache Miss)                                        │
│     - Call Claude API                                             │
│     - Write to L1, L2, L3                                        │
│     - Return result                                               │
└──────────────────────────────────────────────────────────────────┘
```

### Content-Addressable Caching

**Problem**: Traditional path-based caching invalidates when files are renamed or moved.

**Solution**: Hash document content to generate cache keys.

```typescript
// src/services/content-cache.ts
import { createHash } from 'crypto';

export class ContentAddressableCache {
  /**
   * Generate a cache key based on document content.
   * Same content = same key, regardless of filename/path.
   */
  hashContent(content: string): string {
    // Normalize to maximize cache hits
    const normalized = content
      .trim()
      .replace(/\s+/g, ' ')           // Collapse whitespace
      .replace(/\r\n/g, '\n');        // Normalize line endings

    return createHash('sha256')
      .update(normalized)
      .digest('hex')
      .slice(0, 16);  // 16 chars = 64 bits = sufficient uniqueness
  }

  /**
   * Get or compute a transformation result.
   */
  async getOrTransform(
    tenantId: string,
    document: Document,
    persona: string,
    transformFn: () => Promise<TransformResult>
  ): Promise<TransformResult> {
    const contentHash = this.hashContent(document.content);
    const cacheKey = `${tenantId}:transform:${contentHash}:${persona}`;

    // Check cache hierarchy
    const cached = await this.tieredCache.get(cacheKey);
    if (cached) {
      this.metrics.trackCacheHit(cacheKey);
      return cached;
    }

    // Cache miss - transform
    this.metrics.trackCacheMiss(cacheKey);
    const result = await transformFn();

    // Write to all cache tiers
    await this.tieredCache.set(cacheKey, result);

    return result;
  }
}
```

### Stale-While-Revalidate Pattern

For non-critical queries, return stale data immediately while refreshing in background.

```typescript
async getWithRevalidation(
  key: string,
  revalidateFn: () => Promise<TransformResult>,
  maxStaleMs: number = 300000  // 5 minutes
): Promise<TransformResult> {
  const entry = await this.get(key);

  if (entry) {
    const age = Date.now() - entry.timestamp;

    if (age < maxStaleMs) {
      // Fresh enough - return as-is
      return entry.value;
    }

    // Stale but usable - return immediately, refresh in background
    this.backgroundRefresh(key, revalidateFn).catch(err => {
      logger.warn('Background refresh failed', { key, error: err });
    });

    return entry.value;
  }

  // No cached data - must wait for fresh
  const fresh = await revalidateFn();
  await this.set(key, fresh);
  return fresh;
}
```

### Cache Configuration

```typescript
// src/config/cache.ts
export const CACHE_CONFIG = {
  l1: {
    maxSize: 100,           // Max entries
    ttlMs: 5 * 60 * 1000,   // 5 minutes
  },
  l2: {
    ttlSeconds: {
      transformation: 3600,  // 1 hour
      linearIssue: 300,      // 5 minutes
      githubPR: 600,         // 10 minutes
      folderIds: 3600,       // 1 hour
      userRoles: 3600,       // 1 hour
    },
  },
  staleWhileRevalidate: {
    maxStaleMs: 300000,      // 5 minutes
    backgroundRefreshEnabled: true,
  },
};
```

---

## Unit Economics

### Cost Breakdown by Component

#### Claude API (Primary Cost Driver)

| Operation | Input Tokens | Output Tokens | Cost |
|-----------|-------------|---------------|------|
| Transform PRD (1 persona) | ~12,000 | ~2,000 | $0.07 |
| Transform PRD (4 personas) | ~48,000 | ~8,000 | $0.28 |
| Weekly digest | ~20,000 | ~4,000 | $0.12 |
| Content validation | ~5,000 | ~1,000 | $0.04 |
| Decision search | ~2,000 | ~500 | $0.02 |

**Pricing**: Claude Sonnet 3.5 @ $3/M input, $15/M output tokens

#### Google Workspace

| Resource | Free Tier | Expected Usage | Monthly Cost |
|----------|-----------|----------------|--------------|
| Drive API | 1B/day | ~1,000/day | $0 |
| Docs API | 300/min/user | ~100/min peak | $0 |
| Storage | 15GB | ~1GB | $0 |
| Workspace Business | - | 10 users | $60-120 |

#### Infrastructure

| Resource | MVP | Production | SaaS |
|----------|-----|------------|------|
| Compute | $0 (existing) | $20/month | Shared |
| Redis | $0 (Upstash free) | $15/month | Shared |
| Monitoring | $0 (basic logs) | $20/month | Shared |

### Monthly Cost Projections

#### Without Caching

| Volume | Claude | Google | Infra | Total |
|--------|--------|--------|-------|-------|
| 50 transforms/mo | $14 | $60-120 | $0-55 | $74-189 |
| 100 transforms/mo | $28 | $60-120 | $0-55 | $88-203 |
| 200 transforms/mo | $56 | $60-120 | $0-55 | $116-231 |

#### With 90% Cache Hit Rate

| Volume | Claude (10%) | Google | Infra | Total | Savings |
|--------|--------------|--------|-------|-------|---------|
| 50 transforms/mo | $1.40 | $60-120 | $0-55 | $61-176 | 17% |
| 100 transforms/mo | $2.80 | $60-120 | $0-55 | $63-178 | 28% |
| 200 transforms/mo | $5.60 | $60-120 | $0-55 | $66-181 | 43% |

### Cost Optimization Strategies

1. **Maximize Cache Hits**
   - Content-addressable caching
   - Stale-while-revalidate
   - Cross-user cache sharing

2. **Reduce Token Usage**
   - Batch persona transforms (share context)
   - Truncate large documents (summarize first)
   - Use Haiku for validation, Sonnet for transforms

3. **Shift Costs to Tenants (SaaS)**
   - Tenant-owned Google Workspace
   - Usage-based billing
   - Quota enforcement

### SaaS Pricing Model (Future)

| Tier | Users | Transforms/mo | Price/mo |
|------|-------|---------------|----------|
| Starter | 5 | 100 | $49 |
| Team | 20 | 500 | $149 |
| Business | 50 | 2000 | $399 |
| Enterprise | Unlimited | Custom | Custom |

**Unit economics target**: 70%+ gross margin at scale

---

## Implementation Roadmap

### Sprint 3 Tasks (Discord Commands & Triggers)

Add to existing Sprint 3:

- [ ] **Task 3.X: Tenant Context Foundation** (1 day)
  - Create `TenantContext` interface and types
  - Create `config/tenants/thj.json` configuration
  - Add `getTenantContext()` helper function
  - Default tenantId to "thj" for MVP

### Sprint 4 Tasks (Build Status & Notifications)

Add to existing Sprint 4:

- [ ] **Task 4.X: Content-Addressable Cache** (1.5 days)
  - Implement `ContentAddressableCache` class
  - Add content hashing with normalization
  - Integrate with transformation pipeline
  - Add cache hit/miss metrics

### Sprint 5 Tasks (Knowledge Base)

Add to existing Sprint 5:

- [ ] **Task 5.X: Tiered Cache Implementation** (1 day)
  - Implement `TieredCache` class (L1 + L2)
  - Add cache promotion logic (L2 → L1)
  - Add stale-while-revalidate pattern
  - Configure TTLs per data type

### Sprint 6 Tasks (Marketing Support)

Add to existing Sprint 6:

- [ ] **Task 6.X: Usage Tracking** (0.5 days)
  - Create `UsageRecord` schema
  - Track transformation token usage
  - Track API calls per tenant
  - Add usage summary endpoint

### Sprint 7 Tasks (Final Testing)

Add to existing Sprint 7:

- [ ] **Task 7.X: Cost Monitoring Dashboard** (0.5 days)
  - Add cost estimation to metrics
  - Create usage report command
  - Document cost optimization procedures

---

## Monitoring & Observability

### Key Metrics to Track

```typescript
// Cache Performance
onomancer_cache_hits_total{tier="l1|l2|l3", tenant="thj"}
onomancer_cache_misses_total{tier="l1|l2|l3", tenant="thj"}
onomancer_cache_hit_rate{tenant="thj"}  // Gauge: 0.0 - 1.0

// Cost Tracking
onomancer_tokens_used_total{type="input|output", tenant="thj"}
onomancer_api_calls_total{service="claude|google|linear", tenant="thj"}
onomancer_estimated_cost_dollars{tenant="thj"}  // Gauge: running total

// Performance
onomancer_transformation_duration_seconds{persona="leadership|product|...", tenant="thj"}
onomancer_cache_lookup_duration_seconds{tier="l1|l2|l3"}
```

### Alerting Thresholds

| Metric | Warning | Critical |
|--------|---------|----------|
| Cache hit rate | < 80% | < 60% |
| Transformation latency p95 | > 45s | > 60s |
| Daily token usage | > 80% quota | > 95% quota |
| Error rate | > 5% | > 10% |

### Cost Alerts

```yaml
# Alert when daily spend exceeds threshold
- alert: HighDailySpend
  expr: increase(onomancer_estimated_cost_dollars[24h]) > 10
  for: 1h
  labels:
    severity: warning
  annotations:
    summary: "Daily spend exceeds $10"

# Alert when approaching monthly budget
- alert: MonthlyBudgetWarning
  expr: onomancer_estimated_cost_dollars > 150
  for: 1h
  labels:
    severity: critical
  annotations:
    summary: "Approaching monthly budget of $200"
```

---

## Appendix: Related Documents

- **SDD Section 9**: Scalability & Performance (detailed implementation)
- **GOOGLE-API-SCALING-GUIDE.md**: Google API quota optimization
- **Sprint Plan**: Task assignments and timelines
- **PRD Section FR-7**: Build status requirements

---

**Document History:**
- v1.0 (2025-12-15): Initial version based on architecture interview
