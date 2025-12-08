# Rate Limiting Integration Guide

This guide shows how to integrate the CRITICAL-006 rate limiting services into your Discord bot commands and API operations.

## Table of Contents

1. [Overview](#overview)
2. [Rate Limiter Usage](#rate-limiter-usage)
3. [API Rate Limiter Usage](#api-rate-limiter-usage)
4. [Cost Monitor Usage](#cost-monitor-usage)
5. [Discord Bot Integration Example](#discord-bot-integration-example)
6. [Google Drive Integration Example](#google-drive-integration-example)
7. [Anthropic API Integration Example](#anthropic-api-integration-example)
8. [Configuration](#configuration)
9. [Monitoring & Alerts](#monitoring--alerts)

## Overview

The CRITICAL-006 implementation provides three complementary services:

1. **RateLimiter** - Per-user, per-action rate limiting (prevents command spam)
2. **APIRateLimiter** - External API throttling with exponential backoff (prevents quota exhaustion)
3. **CostMonitor** - Budget tracking and enforcement (prevents cost explosions)

## Rate Limiter Usage

### Basic Usage

```typescript
import { rateLimiter } from '../services/rate-limiter';

async function handleUserRequest(userId: string) {
  // Check rate limit FIRST
  const rateLimitResult = await rateLimiter.checkRateLimit(userId, 'generate-summary');

  if (!rateLimitResult.allowed) {
    // User is rate limited
    return {
      error: rateLimitResult.message,
      retryAfter: rateLimitResult.resetInMs
    };
  }

  // Process request...
  return { success: true };
}
```

### With Concurrent Request Tracking

```typescript
import { rateLimiter } from '../services/rate-limiter';

async function handleLongRunningRequest(userId: string) {
  // Check rate limit
  const rateLimitResult = await rateLimiter.checkRateLimit(userId, 'generate-summary');
  if (!rateLimitResult.allowed) {
    return { error: rateLimitResult.message };
  }

  // Check if user already has pending request
  const hasPending = await rateLimiter.checkPendingRequest(userId, 'generate-summary');
  if (hasPending) {
    return { error: '⏳ You already have a summary generation in progress.' };
  }

  try {
    // Mark request as pending
    await rateLimiter.markRequestPending(userId, 'generate-summary');

    // Process long-running operation...
    const result = await processRequest();

    return { success: true, result };

  } finally {
    // Always clear pending request
    await rateLimiter.clearPendingRequest(userId, 'generate-summary');
  }
}
```

### Rate Limit Status

```typescript
import { rateLimiter } from '../services/rate-limiter';

async function getRateLimitInfo(userId: string, action: string) {
  const status = await rateLimiter.getRateLimitStatus(userId, action);

  console.log(`Requests in window: ${status.requestsInWindow}/${status.maxRequests}`);
  console.log(`Window resets in: ${status.resetInMs}ms`);
}
```

## API Rate Limiter Usage

### Google Drive API

```typescript
import { apiRateLimiter } from '../services/api-rate-limiter';
import { google } from 'googleapis';

async function fetchDocuments() {
  const drive = google.drive({ version: 'v3', auth });

  // Wrap API call with throttling
  const files = await apiRateLimiter.throttleGoogleDriveAPI(async () => {
    const response = await drive.files.list({
      q: "mimeType='application/vnd.google-apps.document'",
      fields: 'files(id, name, modifiedTime)'
    });
    return response.data.files;
  }, 'list-documents');

  return files;
}
```

### Anthropic API

```typescript
import { apiRateLimiter } from '../services/api-rate-limiter';
import Anthropic from '@anthropic-ai/sdk';

async function generateText(prompt: string) {
  const anthropic = new Anthropic();

  // Wrap API call with throttling
  const response = await apiRateLimiter.throttleAnthropicAPI(async () => {
    return await anthropic.messages.create({
      model: 'claude-sonnet-4-5-20250929',
      max_tokens: 1024,
      messages: [{ role: 'user', content: prompt }]
    });
  }, 'generate-text');

  return response;
}
```

### Discord API

```typescript
import { apiRateLimiter } from '../services/api-rate-limiter';
import { TextChannel } from 'discord.js';

async function postToDiscord(channel: TextChannel, content: string) {
  // Wrap Discord API call with throttling
  const message = await apiRateLimiter.throttleDiscordAPI(async () => {
    return await channel.send(content);
  }, 'send-message');

  return message;
}
```

## Cost Monitor Usage

### Track API Costs

```typescript
import { costMonitor } from '../services/cost-monitor';
import Anthropic from '@anthropic-ai/sdk';

async function generateTextWithCostTracking(prompt: string) {
  // Check if service is paused due to budget
  const { paused, reason } = costMonitor.isServicePaused();
  if (paused) {
    throw new Error(`Service paused: ${reason}`);
  }

  const anthropic = new Anthropic();

  const response = await anthropic.messages.create({
    model: 'claude-sonnet-4-5-20250929',
    max_tokens: 1024,
    messages: [{ role: 'user', content: prompt }]
  });

  // Track cost
  const totalTokens = response.usage.input_tokens + response.usage.output_tokens;
  await costMonitor.trackAPICall(
    'anthropic',
    'generate-text',
    totalTokens,
    'claude-sonnet-4-5-20250929'
  );

  return response;
}
```

### Track Fixed-Cost Operations

```typescript
import { costMonitor } from '../services/cost-monitor';

async function fetchFromGoogleDrive() {
  // ... fetch logic ...

  // Track operation cost
  await costMonitor.trackFixedCostOperation(
    'google-drive',
    'list-files',
    0.001 // Estimated cost per API call
  );
}
```

### Check Budget Status

```typescript
import { costMonitor } from '../services/cost-monitor';

async function getBudgetStatus() {
  const dailyStatus = await costMonitor.getDailyBudgetStatus();
  const monthlyStatus = await costMonitor.getMonthlyBudgetStatus();

  console.log(`Daily: $${dailyStatus.currentSpendUSD.toFixed(2)} / $${dailyStatus.budgetLimitUSD}`);
  console.log(`Monthly: $${monthlyStatus.currentSpendUSD.toFixed(2)} / $${monthlyStatus.budgetLimitUSD}`);

  if (dailyStatus.isNearLimit) {
    console.warn('⚠️ Approaching daily budget limit!');
  }
}
```

## Discord Bot Integration Example

### Complete Discord Command Handler

```typescript
import { ChatInputCommandInteraction } from 'discord.js';
import { rateLimiter } from '../services/rate-limiter';
import { apiRateLimiter } from '../services/api-rate-limiter';
import { costMonitor } from '../services/cost-monitor';

export async function handleGenerateSummary(interaction: ChatInputCommandInteraction) {
  const userId = interaction.user.id;

  // STEP 1: Check rate limit
  const rateLimitResult = await rateLimiter.checkRateLimit(userId, 'generate-summary');
  if (!rateLimitResult.allowed) {
    return interaction.reply({
      content: rateLimitResult.message,
      ephemeral: true
    });
  }

  // STEP 2: Check concurrent requests
  const hasPending = await rateLimiter.checkPendingRequest(userId, 'generate-summary');
  if (hasPending) {
    return interaction.reply({
      content: '⏳ You already have a summary generation in progress.',
      ephemeral: true
    });
  }

  // STEP 3: Check budget status
  const { paused, reason } = costMonitor.isServicePaused();
  if (paused) {
    return interaction.reply({
      content: `❌ Service temporarily unavailable: ${reason}`,
      ephemeral: true
    });
  }

  await interaction.deferReply();

  try {
    // Mark request as pending
    await rateLimiter.markRequestPending(userId, 'generate-summary');

    // STEP 4: Fetch documents (with API rate limiting)
    const documents = await apiRateLimiter.throttleGoogleDriveAPI(async () => {
      return await fetchDocumentsFromGoogleDrive();
    }, 'fetch-documents');

    // STEP 5: Generate summary (with API rate limiting + cost tracking)
    const summary = await generateSummaryWithCostTracking(documents);

    // STEP 6: Post to Discord (with API rate limiting)
    await apiRateLimiter.throttleDiscordAPI(async () => {
      return await interaction.editReply({
        content: summary
      });
    }, 'post-summary');

  } catch (error) {
    await interaction.editReply({
      content: `❌ Error: ${error.message}`
    });
  } finally {
    // Always clear pending request
    await rateLimiter.clearPendingRequest(userId, 'generate-summary');
  }
}

async function generateSummaryWithCostTracking(documents: any[]) {
  const anthropic = new Anthropic();

  const response = await apiRateLimiter.throttleAnthropicAPI(async () => {
    return await anthropic.messages.create({
      model: 'claude-sonnet-4-5-20250929',
      max_tokens: 2048,
      messages: [{ role: 'user', content: 'Summarize these documents...' }]
    });
  }, 'generate-summary');

  // Track cost
  const totalTokens = response.usage.input_tokens + response.usage.output_tokens;
  await costMonitor.trackAPICall(
    'anthropic',
    'generate-summary',
    totalTokens,
    'claude-sonnet-4-5-20250929'
  );

  return response.content[0].text;
}
```

## Google Drive Integration Example

```typescript
import { googleDocsMonitor } from '../services/google-docs-monitor';
import { apiRateLimiter } from '../services/api-rate-limiter';
import { costMonitor } from '../services/cost-monitor';

export async function scanGoogleDocsWithRateLimiting() {
  // Wrap all Google Drive API calls with rate limiting
  const documents = await googleDocsMonitor.scanForChanges({
    windowDays: 7,
    maxDocuments: 100
  });

  // Track cost (estimate $0.001 per API call)
  await costMonitor.trackFixedCostOperation(
    'google-drive',
    'scan-documents',
    0.001 * documents.length
  );

  return documents;
}
```

## Anthropic API Integration Example

```typescript
import { devrelTranslator } from '../services/devrel-translator';
import { apiRateLimiter } from '../services/api-rate-limiter';
import { costMonitor } from '../services/cost-monitor';

export async function translateDocumentWithProtection(documentContent: string) {
  // Check budget before expensive operation
  const dailyStatus = await costMonitor.getDailyBudgetStatus();
  if (dailyStatus.isOverBudget) {
    throw new Error('Daily budget exceeded. Cannot process translation.');
  }

  // Wrap Anthropic API call
  const translation = await apiRateLimiter.throttleAnthropicAPI(async () => {
    return await devrelTranslator.translateForExecutives(documentContent);
  }, 'translate-document');

  // Track cost (estimate based on content length)
  const estimatedTokens = Math.ceil(documentContent.length / 4); // Rough estimate
  await costMonitor.trackAPICall(
    'anthropic',
    'translate-document',
    estimatedTokens,
    'claude-sonnet-4-5-20250929'
  );

  return translation;
}
```

## Configuration

### Update Budget Limits

```typescript
import { costMonitor } from '../services/cost-monitor';

// Update budget configuration
costMonitor.updateBudgetConfig({
  dailyBudgetUSD: 200,        // Increase to $200/day
  monthlyBudgetUSD: 5000,     // Increase to $5000/month
  alertThresholdPercent: 80,  // Alert at 80% instead of 75%
  pauseOnExceed: true         // Keep auto-pause enabled
});
```

### Custom Rate Limits

To modify rate limits, edit `src/services/rate-limiter.ts`:

```typescript
private getRateLimitConfig(action: string): RateLimitConfig {
  const configs: Record<string, RateLimitConfig> = {
    'generate-summary': {
      maxRequests: 10,     // Increase from 5 to 10
      windowMs: 60000      // Keep 1 minute window
    },
    // ... other configs
  };
}
```

## Monitoring & Alerts

### Get Statistics

```typescript
import { rateLimiter } from '../services/rate-limiter';
import { apiRateLimiter } from '../services/api-rate-limiter';
import { costMonitor } from '../services/cost-monitor';

async function getSystemStatistics() {
  const rateLimiterStats = rateLimiter.getStatistics();
  const apiRateLimiterStats = apiRateLimiter.getStatistics();
  const costMonitorStats = await costMonitor.getStatistics();

  console.log('=== Rate Limiter Stats ===');
  console.log(`Tracked users: ${rateLimiterStats.totalTrackedUsers}`);
  console.log(`Pending requests: ${rateLimiterStats.totalPendingRequests}`);

  console.log('\n=== API Rate Limiter Stats ===');
  console.log(`Tracked APIs: ${apiRateLimiterStats.trackedAPIs.join(', ')}`);
  console.log(`Total requests: ${apiRateLimiterStats.totalRequestsTracked}`);

  console.log('\n=== Cost Monitor Stats ===');
  console.log(`Daily spend: $${costMonitorStats.dailySpend.toFixed(2)}`);
  console.log(`Monthly spend: $${costMonitorStats.monthlySpend.toFixed(2)}`);
  console.log(`Service paused: ${costMonitorStats.servicePaused}`);

  console.log('\n=== Cost Breakdown ===');
  for (const [api, cost] of Object.entries(costMonitorStats.costBreakdown)) {
    console.log(`${api}: $${cost.toFixed(4)}`);
  }
}
```

### Manual Service Resume

```typescript
import { costMonitor } from '../services/cost-monitor';

// Resume service after budget increase
await costMonitor.resumeService(
  'admin@company.com',
  'Budget increased to $200/day, resuming service'
);
```

## Best Practices

1. **Always check rate limits first** - Before any expensive operation
2. **Track concurrent requests** - Prevent duplicate long-running operations
3. **Wrap all external API calls** - Use APIRateLimiter for automatic backoff
4. **Track all costs** - Even small API calls add up
5. **Monitor budget daily** - Review cost breakdowns regularly
6. **Set conservative limits** - Better to be too restrictive than too permissive
7. **Log all rate limit violations** - Helps identify attackers or bugs
8. **Test with realistic loads** - Ensure rate limits work under stress

## Troubleshooting

### User Getting Rate Limited Frequently

```typescript
// Check user's rate limit status
const status = await rateLimiter.getRateLimitStatus(userId, 'generate-summary');
console.log(`User has made ${status.requestsInWindow} requests`);
console.log(`Limit: ${status.maxRequests} per ${status.windowMs}ms`);

// Optionally reset for legitimate user
await rateLimiter.resetRateLimit(userId, 'generate-summary');
```

### API Quota Exhausted

```typescript
// Check API rate limit status
const status = await apiRateLimiter.getAPIRateLimitStatus('google-drive');
console.log(`Requests: ${status.requestCount}/${status.maxRequests}`);
console.log(`Retries: ${status.retries}`);

// Reset if needed
await apiRateLimiter.resetAPIRateLimit('google-drive');
```

### Budget Exceeded

```typescript
// Check current budget status
const dailyStatus = await costMonitor.getDailyBudgetStatus();
console.log(`Spent: $${dailyStatus.currentSpendUSD.toFixed(2)}`);
console.log(`Budget: $${dailyStatus.budgetLimitUSD}`);

// Get cost breakdown to identify expensive operations
const breakdown = await costMonitor.getCostBreakdownByAPI('daily');
for (const [api, cost] of Object.entries(breakdown)) {
  console.log(`${api}: $${cost.toFixed(2)}`);
}

// Resume service after approval
await costMonitor.resumeService('admin@company.com', 'Budget approved');
```

## Testing

See test files for comprehensive examples:
- `tests/unit/rate-limiter.test.ts`
- `tests/unit/api-rate-limiter.test.ts`
- `tests/unit/cost-monitor.test.ts`

Run tests:
```bash
npm test rate-limiter
npm test api-rate-limiter
npm test cost-monitor
```
