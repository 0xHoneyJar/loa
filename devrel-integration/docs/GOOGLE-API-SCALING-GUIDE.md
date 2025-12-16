# Google API Scaling Guide

**Document:** Google API Optimization & Scaling
**Version:** 1.0
**Date:** 2025-12-15
**Author:** Architecture Designer Agent
**Related Branch:** `trrfrm-ggl-scaling`

---

## Table of Contents

1. [Quota Reference](#quota-reference)
2. [Current Optimizations](#current-optimizations)
3. [Caching Strategy](#caching-strategy)
4. [Rate Limiting](#rate-limiting)
5. [Cost Optimization](#cost-optimization)
6. [Monitoring](#monitoring)
7. [Troubleshooting](#troubleshooting)

---

## Quota Reference

### Google Drive API

| Quota | Limit | Scope | Notes |
|-------|-------|-------|-------|
| Queries per day | 1,000,000,000 | Per project | Effectively unlimited |
| Queries per 100 seconds | 12,000 | Per user | **Primary limit** |
| Queries per 100 seconds | 12,000 | Per project | Shared across all users |

### Google Docs API

| Quota | Limit | Scope | Notes |
|-------|-------|-------|-------|
| Read requests per minute | 300 | Per user | **Bottleneck for document scanning** |
| Write requests per minute | 60 | Per user | Limiting for batch operations |
| Read requests per minute | 3,000 | Per project | Project-wide limit |
| Write requests per minute | 600 | Per project | Project-wide limit |

### Key Insight

**Docs API per-user limit (300/min) is the primary bottleneck**, not Drive API.

Solution: Use **Drive Export API** instead of Docs API for text extraction.

---

## Current Optimizations

### 1. Drive Export API (40x Improvement)

**Before**: Docs API at 300 requests/minute
```typescript
// OLD: Uses Docs API (300/min per user) - AVOID
const response = await this.docs.documents.get({ documentId });
const content = extractTextFromDocumentBody(response.data.body);
```

**After**: Drive Export API at 12,000 requests/minute
```typescript
// NEW: Uses Drive API (12,000/min per user) - PREFERRED
const response = await this.drive.files.export({
  fileId: documentId,
  mimeType: 'text/plain'
}, { responseType: 'text' });
const content = response.data as string;
```

**Implementation**: `devrel-integration/src/services/google-docs-monitor.ts`

### 2. Separate Rate Limiters

Different APIs have different quotas - use separate rate limiters:

```typescript
// src/services/api-rate-limiter.ts
const API_CONFIGS = {
  'google-drive': {
    maxRequestsPerMinute: 1000,  // Quota: 12,000/min (conservative)
    maxRetries: 5,
    initialBackoffMs: 1000,
    maxBackoffMs: 30000
  },
  'google-docs-read': {
    maxRequestsPerMinute: 250,   // Quota: 300/min (conservative)
    maxRetries: 5,
    initialBackoffMs: 2000,
    maxBackoffMs: 60000
  },
  'google-docs-write': {
    maxRequestsPerMinute: 50,    // Quota: 60/min (conservative)
    maxRetries: 5,
    initialBackoffMs: 3000,
    maxBackoffMs: 120000
  }
};
```

### 3. Drive Changes API (94% Reduction)

Instead of polling all documents, use incremental change detection:

```typescript
// src/services/drive-changes-monitor.ts
class DriveChangesMonitor {
  async getChanges(): Promise<DriveChange[]> {
    // Only fetch documents that changed since last check
    const response = await this.drive.changes.list({
      pageToken: this.savedPageToken,
      spaces: 'drive',
      fields: 'newStartPageToken, changes(fileId, file(name, mimeType))'
    });

    // Save token for next poll
    this.savedPageToken = response.data.newStartPageToken;

    return response.data.changes;
  }
}
```

**Impact**: 94% reduction in API calls for document monitoring.

### 4. Document Caching

Redis-based caching with TTL:

```typescript
// src/services/document-cache.ts
const CACHE_TTL = {
  documentContent: 15 * 60,    // 15 minutes
  folderIds: 60 * 60,          // 1 hour
  permissions: 30 * 60,        // 30 minutes
  changeToken: 24 * 60 * 60    // 24 hours
};
```

---

## Caching Strategy

### Content-Addressable Cache

Hash document content for cache keys - same content always hits cache:

```typescript
import { createHash } from 'crypto';

function getContentHash(content: string): string {
  const normalized = content.trim().replace(/\s+/g, ' ');
  return createHash('sha256').update(normalized).digest('hex').slice(0, 16);
}

// Cache key format
const cacheKey = `${tenantId}:doc:${contentHash}`;
```

### Tiered Cache Hierarchy

```
┌─────────────────────────────────────────────────────┐
│  L1: In-Memory (LRU)                                │
│  - TTL: 1-5 minutes                                 │
│  - Size: 100 entries                                │
│  - Use: Repeated queries within same session        │
├─────────────────────────────────────────────────────┤
│  L2: Redis                                          │
│  - TTL: 15-60 minutes                               │
│  - Size: Unlimited                                  │
│  - Use: Cross-request, team-wide sharing            │
├─────────────────────────────────────────────────────┤
│  L3: Google Docs (Permanent)                        │
│  - TTL: Permanent                                   │
│  - Size: Unlimited                                  │
│  - Use: Audit trail, historical access              │
└─────────────────────────────────────────────────────┘
```

### Cache Flow

```
Request for document
    │
    ▼
┌─────────────────┐
│ Check L1 (RAM)  │──HIT──▶ Return immediately
└────────┬────────┘
         │ MISS
         ▼
┌─────────────────┐
│ Check L2 (Redis)│──HIT──▶ Promote to L1, Return
└────────┬────────┘
         │ MISS
         ▼
┌─────────────────┐
│ Fetch from API  │──────▶ Write to L1 + L2, Return
└─────────────────┘
```

### Expected Cache Performance

| Scenario | L1 Hit Rate | L2 Hit Rate | API Calls |
|----------|-------------|-------------|-----------|
| Cold start | 0% | 0% | 100% |
| Steady state (1 user) | 60% | 30% | 10% |
| Steady state (team) | 40% | 50% | 10% |
| **Target** | **50%** | **40%** | **<10%** |

---

## Rate Limiting

### Exponential Backoff

```typescript
async function withRetry<T>(
  fn: () => Promise<T>,
  maxRetries: number = 5,
  initialBackoffMs: number = 1000
): Promise<T> {
  let lastError: Error;

  for (let attempt = 0; attempt < maxRetries; attempt++) {
    try {
      return await fn();
    } catch (error) {
      lastError = error;

      if (!isRetryable(error)) {
        throw error;
      }

      const backoff = initialBackoffMs * Math.pow(2, attempt);
      const jitter = Math.random() * 1000;
      await sleep(backoff + jitter);
    }
  }

  throw lastError;
}

function isRetryable(error: any): boolean {
  const status = error?.response?.status;
  return status === 429 || status === 503 || status === 500;
}
```

### Token Bucket Rate Limiter

```typescript
class TokenBucketRateLimiter {
  private tokens: number;
  private lastRefill: number;
  private readonly maxTokens: number;
  private readonly refillRate: number; // tokens per second

  async acquire(): Promise<void> {
    this.refill();

    if (this.tokens < 1) {
      const waitTime = (1 - this.tokens) / this.refillRate * 1000;
      await sleep(waitTime);
      this.refill();
    }

    this.tokens -= 1;
  }

  private refill(): void {
    const now = Date.now();
    const elapsed = (now - this.lastRefill) / 1000;
    this.tokens = Math.min(this.maxTokens, this.tokens + elapsed * this.refillRate);
    this.lastRefill = now;
  }
}
```

### Configuration by API

```typescript
const RATE_LIMITS = {
  'google-drive': {
    maxTokens: 100,      // Burst capacity
    refillRate: 16.67,   // 1000/min = 16.67/sec
  },
  'google-docs-read': {
    maxTokens: 25,       // Burst capacity
    refillRate: 4.17,    // 250/min = 4.17/sec
  },
  'google-docs-write': {
    maxTokens: 5,        // Burst capacity
    refillRate: 0.83,    // 50/min = 0.83/sec
  },
};
```

---

## Cost Optimization

### Google Workspace Costs

| Resource | Free Tier | Expected Usage | Monthly Cost |
|----------|-----------|----------------|--------------|
| Drive API calls | 1B/day | ~1,000/day | $0 |
| Docs API calls | 300/min/user | ~100/min peak | $0 |
| Storage | 15GB | ~1GB | $0 |
| Workspace Business | - | 10 users | $60-120 |

**Key insight**: API calls are essentially free. Workspace subscription is the cost.

### Optimization Strategies

1. **Use Drive Export API** instead of Docs API (40x quota increase)
2. **Implement caching** to reduce redundant API calls
3. **Use Changes API** for incremental polling (94% reduction)
4. **Batch operations** where possible
5. **For SaaS**: Let tenants bring their own Workspace

### Cost Per Operation

| Operation | API Calls | Cost |
|-----------|-----------|------|
| List folder contents | 1 Drive | ~$0 |
| Export document text | 1 Drive | ~$0 |
| Create new document | 1 Docs write | ~$0 |
| Update document | 1-5 Docs writes | ~$0 |
| Full folder scan (100 docs) | 101 Drive | ~$0 |

---

## Monitoring

### Metrics to Track

```typescript
// Google API call metrics
google_api_calls_total{api="drive|docs", method="get|create|update|export"}
google_api_latency_seconds{api="drive|docs", method="..."}
google_api_errors_total{api="drive|docs", error_code="429|500|503"}

// Rate limiter metrics
rate_limiter_tokens_available{api="drive|docs"}
rate_limiter_wait_time_seconds{api="drive|docs"}

// Cache metrics
cache_hits_total{tier="l1|l2"}
cache_misses_total{tier="l1|l2"}
cache_hit_rate{tier="l1|l2"}
```

### Alerting Thresholds

| Metric | Warning | Critical |
|--------|---------|----------|
| 429 errors/hour | > 5 | > 20 |
| API latency p95 | > 2s | > 5s |
| Cache hit rate | < 80% | < 60% |
| Rate limiter wait time | > 1s avg | > 5s avg |

### Logging

```typescript
// Log all API calls for debugging
logger.info('Google API call', {
  api: 'drive',
  method: 'files.export',
  fileId: fileId,
  duration: durationMs,
  cached: false,
  rateLimitWait: waitMs,
});
```

---

## Troubleshooting

### Common Issues

#### 1. "Rate Limit Exceeded" (429 errors)

**Symptoms**: 429 errors, increasing latency

**Diagnosis**:
```bash
# Check recent API usage
grep "Google API call" logs/app.log | grep -c "$(date +%H):"
```

**Solutions**:
- Increase cache TTL
- Reduce polling frequency
- Switch from Docs API to Drive Export API
- Implement stricter rate limiting

#### 2. "Quota Exceeded"

**Symptoms**: 403 errors with "quotaExceeded" reason

**Diagnosis**:
- Check Google Cloud Console → APIs & Services → Quotas
- Look for per-user vs per-project limits

**Solutions**:
- Request quota increase in GCP Console
- Distribute load across multiple service accounts
- Implement caching to reduce API calls

#### 3. Cache Misses Too High

**Symptoms**: Cache hit rate < 60%, high API call volume

**Diagnosis**:
```bash
# Check cache stats
redis-cli INFO stats | grep hit
```

**Solutions**:
- Increase cache TTL
- Use content-addressable caching
- Warm cache proactively for hot documents

#### 4. Stale Data Issues

**Symptoms**: Users see outdated document content

**Diagnosis**:
- Check cache TTLs
- Check Change API page token freshness

**Solutions**:
- Reduce cache TTL for frequently updated docs
- Implement cache invalidation on webhook events
- Add "force refresh" option to commands

### Debug Commands

```bash
# Check Redis cache entries
redis-cli KEYS "thj:doc:*" | wc -l

# Check cache TTL
redis-cli TTL "thj:doc:abc123"

# Clear cache for a document
redis-cli DEL "thj:doc:abc123"

# Clear all document cache
redis-cli KEYS "thj:doc:*" | xargs redis-cli DEL

# Check rate limiter state
redis-cli GET "ratelimit:google-drive:tokens"
```

---

## Related Documents

- `docs/SCALING-ARCHITECTURE.md` - Overall scaling strategy
- `docs/sdd.md` Section 9 - Scalability & Performance
- `devrel-integration/docs/RATE-LIMITING-GUIDE.md` - General rate limiting

---

**Document History:**
- v1.0 (2025-12-15): Initial version based on `trrfrm-ggl-scaling` work
