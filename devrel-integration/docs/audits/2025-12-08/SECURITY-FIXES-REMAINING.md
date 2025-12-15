# Remaining Security Fixes (High Priority)

This document lists the remaining HIGH priority security issues from the audit that need to be fixed before production deployment.

## ✅ Fixed Issues (Completed)

### CRITICAL-001: SecretsManager Not Invoked at Startup
**Status:** ✅ FIXED
**File:** `integration/src/bot.ts`
- Added SecretsManager initialization in async `startBot()` function
- Bot now validates all secrets before connecting to Discord
- Validates token format, file permissions, git tracking status
- Fails fast if secrets are invalid

### CRITICAL-002: File Path Traversal in /doc Command
**Status:** ✅ FIXED
**File:** `integration/src/handlers/commands.ts`
- Added DOC_ROOT absolute path validation
- Implements `path.startsWith()` check to prevent traversal
- Added symlink resolution check with `fs.realpathSync()`
- Logs and audits any traversal attempts

### HIGH-001: PII Filtering for Discord Messages
**Status:** ✅ FIXED
**File:** `integration/src/handlers/feedbackCapture.ts`
- Added `detectPII()` check before creating Linear issues
- Blocks feedback capture if PII detected (emails, phone numbers, SSNs)
- Sanitizes author info (redacts discriminator, partial ID)
- User-friendly error message explaining why feedback was blocked

---

## ⚠️ Remaining HIGH Priority Fixes

### HIGH-002: Webhook Timing Attack Surface
**Status:** ⚠️ TO BE FIXED
**File:** `integration/src/handlers/webhooks.ts`
**Priority:** HIGH (fix before production)

**Issue:**
The webhook handler error responses leak information through timing differences:
- "Invalid signature" error (crypto verification failed)
- "Invalid JSON" error (parse error after sig verification passed)

An attacker can measure response times to determine if their signature was valid.

**Remediation:**
```typescript
// ALL error responses should be generic and indistinguishable
export async function handleLinearWebhook(req: Request, res: Response): Promise<void> {
  try {
    // Enforce HTTPS in production
    if (process.env['NODE_ENV'] === 'production' && req.protocol !== 'https') {
      res.status(400).send('Bad Request');
      return;
    }

    const signature = req.headers['x-linear-signature'] as string;
    const rawPayload = req.body as Buffer;

    // 1. Verify signature FIRST (before any parsing)
    if (!signature) {
      res.status(400).send('Bad Request'); // Generic
      return;
    }

    const webhookSecret = process.env['LINEAR_WEBHOOK_SECRET'];
    if (!webhookSecret) {
      logger.error('LINEAR_WEBHOOK_SECRET not configured');
      res.status(500).send('Server Error'); // Generic
      return;
    }

    const isValid = verifyLinearSignature(rawPayload, signature, webhookSecret);
    if (!isValid) {
      logger.warn('Webhook signature verification failed', { ip: req.ip });
      res.status(401).send('Unauthorized'); // Generic, same timing
      return;
    }

    // 2. NOW parse payload (signature is valid)
    let data;
    try {
      data = JSON.parse(rawPayload.toString('utf-8'));
    } catch (error) {
      logger.error('Invalid webhook payload (valid signature)', { error, ip: req.ip });
      res.status(400).send('Bad Request'); // Same generic error
      return;
    }

    // 3. Validate timestamp (prevent replay attacks)
    const timestamp = data.createdAt;
    if (!timestamp) {
      res.status(400).send('Bad Request');
      return;
    }

    const webhookAge = Date.now() - new Date(timestamp).getTime();
    const MAX_AGE = 5 * 60 * 1000; // 5 minutes

    if (webhookAge > MAX_AGE || webhookAge < 0) {
      logger.warn(`Webhook timestamp invalid: ${webhookAge}ms`);
      res.status(400).send('Bad Request');
      return;
    }

    // Rest of processing...
  } catch (error) {
    logger.error('Error handling webhook:', error);
    res.status(500).send('Server Error'); // Always generic
  }
}
```

**Key Changes:**
- All error responses use generic messages
- No information leakage about what failed
- Consistent response structure prevents timing attacks

---

### HIGH-003: Unbounded Webhook Cache Memory Exhaustion
**Status:** ⚠️ TO BE FIXED
**File:** `integration/src/handlers/webhooks.ts`
**Priority:** HIGH (fix before production)

**Issue:**
The webhook deduplication uses unbounded `Set<string>`:
```typescript
const processedWebhooks = new Set<string>();
setInterval(() => processedWebhooks.clear(), 60 * 60 * 1000); // Clear hourly
```

An attacker can send thousands of webhooks to exhaust memory.

**Remediation:**
Use LRU cache with size limit:
```typescript
import { LRUCache } from 'lru-cache';

const processedWebhooks = new LRUCache<string, boolean>({
  max: 10000, // Max 10k webhooks tracked
  ttl: 60 * 60 * 1000, // 1 hour TTL (automatic expiry)
  updateAgeOnGet: false, // Don't reset TTL on duplicate check
});

// In webhook handler:
if (processedWebhooks.has(webhookId)) {
  res.status(200).send('OK'); // Already processed
  return;
}

processedWebhooks.set(webhookId, true);
```

**Benefits:**
- Bounded memory (max 10k entries)
- Automatic expiry (1 hour TTL)
- LRU eviction if limit reached
- Thread-safe

---

### HIGH-004: Role Validation Doesn't Fail Startup
**Status:** ⚠️ TO BE FIXED
**File:** `integration/src/bot.ts`
**Priority:** HIGH (fix before production)

**Issue:**
The bot calls `validateRoleConfiguration()` at startup but doesn't fail if validation fails. Bot continues running with misconfigured roles, leading to authorization bypass.

**Current code:**
```typescript
client.once(Events.ClientReady, async (readyClient) => {
  // ...
  await validateRoleConfiguration(readyClient); // Doesn't throw on failure
  // Bot continues even if roles missing
});
```

**Remediation:**
Make role validation throw on critical failures:
```typescript
// In middleware/auth.ts:
export async function validateRoleConfiguration(client: Client): Promise<void> {
  const errors: string[] = [];

  const guildId = process.env['DISCORD_GUILD_ID'];
  if (!guildId) {
    throw new Error('DISCORD_GUILD_ID not configured');
  }

  const guild = client.guilds.cache.get(guildId);
  if (!guild) {
    throw new Error(`Guild ${guildId} not found`);
  }

  // Validate admin roles exist
  const adminRoles = ['admin', 'moderator']; // From config
  for (const roleName of adminRoles) {
    const role = guild.roles.cache.find(r => r.name.toLowerCase() === roleName.toLowerCase());
    if (!role) {
      errors.push(`Admin role '${roleName}' not found in guild`);
    }
  }

  // Validate required roles for commands
  const requiredRoles = ['developers', 'product', 'qa']; // From bot-commands.yml
  for (const roleName of requiredRoles) {
    const role = guild.roles.cache.find(r => r.name.toLowerCase() === roleName.toLowerCase());
    if (!role) {
      errors.push(`Required role '${roleName}' not found in guild`);
    }
  }

  if (errors.length > 0) {
    logger.error('❌ Role configuration validation failed:');
    errors.forEach(err => logger.error(`  - ${err}`));
    throw new Error(`Role validation failed: ${errors.length} errors`);
  }

  logger.info('✅ Role configuration validated');
}
```

---

## Implementation Priority

1. **HIGH-002** (Webhook timing) - 15 minutes
2. **HIGH-003** (Webhook cache) - 10 minutes
3. **HIGH-004** (Role validation) - 10 minutes

**Total estimated time:** ~35 minutes

All fixes should be completed and tested before production deployment.

---

## Testing Checklist After Fixes

After implementing all fixes, test:

- [ ] Bot starts up with secrets validation
- [ ] Bot fails startup if secrets invalid
- [ ] `/doc` command prevents path traversal
- [ ] Feedback capture blocks PII
- [ ] Webhook signatures verified correctly
- [ ] Webhook cache doesn't grow unbounded
- [ ] Bot fails startup if required roles missing
- [ ] Build passes: `npm run build`
- [ ] No TypeScript errors
- [ ] Integration tests pass

---

## References

- Original audit: `SECURITY-AUDIT-REPORT.md`
- Webhook security: CWE-347, CWE-770
- PII protection: GDPR Article 6, CCPA 1798.100
- Path traversal: CWE-22, OWASP A01:2021
