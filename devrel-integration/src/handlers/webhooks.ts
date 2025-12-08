import express, { Request, Response } from 'express';
import crypto from 'crypto';
import { LRUCache } from 'lru-cache';
import { logger, audit } from '../utils/logger';

/**
 * SECURITY FIX (HIGH-003): Use LRU cache with size limit to prevent memory exhaustion
 * - Bounded to max 10k webhooks
 * - Automatic expiry after 1 hour TTL
 * - LRU eviction if limit reached
 */
const processedWebhooks = new LRUCache<string, boolean>({
  max: 10000, // Max 10k webhooks tracked
  ttl: 60 * 60 * 1000, // 1 hour TTL (automatic expiry)
  updateAgeOnGet: false, // Don't reset TTL on duplicate check
});

/**
 * Verify Linear webhook signature
 */
function verifyLinearSignature(
  payload: Buffer,
  signature: string,
  secret: string
): boolean {
  const expectedSignature = crypto
    .createHmac('sha256', secret)
    .update(payload)
    .digest('hex');

  const providedSignature = signature.replace('sha256=', '');

  // Use constant-time comparison to prevent timing attacks
  try {
    return crypto.timingSafeEqual(
      Buffer.from(expectedSignature),
      Buffer.from(providedSignature)
    );
  } catch {
    return false;
  }
}

/**
 * Verify Vercel webhook signature
 */
function verifyVercelSignature(
  payload: string,
  signature: string,
  secret: string
): boolean {
  const expectedSignature = crypto
    .createHmac('sha1', secret)
    .update(payload)
    .digest('hex');

  // Use constant-time comparison
  try {
    return crypto.timingSafeEqual(
      Buffer.from(expectedSignature),
      Buffer.from(signature)
    );
  } catch {
    return false;
  }
}

/**
 * Handle Linear webhook events
 *
 * SECURITY FIX (HIGH-002): All error responses use generic messages
 * to prevent timing attacks and information leakage
 */
export async function handleLinearWebhook(req: Request, res: Response): Promise<void> {
  try {
    // SECURITY: Enforce HTTPS in production
    if (process.env['NODE_ENV'] === 'production' && req.protocol !== 'https') {
      logger.warn('Linear webhook received over HTTP in production');
      res.status(400).send('Bad Request'); // Generic
      return;
    }

    const signature = req.headers['x-linear-signature'] as string;
    const payload = req.body;

    // 1. VERIFY SIGNATURE FIRST (before parsing)
    if (!signature) {
      logger.warn('Linear webhook missing signature header');
      res.status(400).send('Bad Request'); // Generic
      return;
    }

    const webhookSecret = process.env['LINEAR_WEBHOOK_SECRET'];
    if (!webhookSecret) {
      logger.error('LINEAR_WEBHOOK_SECRET not configured');
      res.status(500).send('Server Error'); // Generic
      return;
    }

    const isValid = verifyLinearSignature(payload, signature, webhookSecret);
    if (!isValid) {
      logger.warn('Linear webhook signature verification failed', { ip: req.ip });
      audit({
        action: 'webhook.signature_failed',
        resource: 'linear',
        userId: 'system',
        timestamp: new Date().toISOString(),
        details: { ip: req.ip },
      });
      res.status(401).send('Unauthorized'); // Generic, same timing
      return;
    }

    // 2. NOW PARSE PAYLOAD (signature is valid)
    let data;
    try {
      data = JSON.parse(payload.toString('utf-8'));
    } catch (error) {
      logger.error('Invalid webhook payload (valid signature)', { error, ip: req.ip });
      res.status(400).send('Bad Request'); // Same generic error
      return;
    }

    // 3. VALIDATE TIMESTAMP (prevent replay attacks)
    const timestamp = data.createdAt;
    if (!timestamp) {
      logger.warn('Linear webhook missing timestamp');
      res.status(400).send('Bad Request'); // Generic
      return;
    }

    const webhookAge = Date.now() - new Date(timestamp).getTime();
    const MAX_AGE = 5 * 60 * 1000; // 5 minutes

    if (webhookAge > MAX_AGE || webhookAge < 0) {
      logger.warn(`Linear webhook timestamp invalid: ${webhookAge}ms`);
      res.status(400).send('Bad Request'); // Generic
      return;
    }

    // 4. IDEMPOTENCY CHECK
    const webhookId = data.webhookId || data.id;
    if (!webhookId) {
      logger.warn('Linear webhook missing ID');
      res.status(400).send('Bad Request'); // Generic
      return;
    }

    if (processedWebhooks.has(webhookId)) {
      logger.info(`Duplicate Linear webhook ignored: ${webhookId}`);
      res.status(200).send('OK');
      return;
    }

    // Mark as processed
    processedWebhooks.set(webhookId, true);

    // 5. AUDIT LOG
    audit({
      action: 'webhook.received',
      resource: 'linear',
      userId: 'system',
      timestamp: new Date().toISOString(),
      details: {
        webhookId,
        action: data.action,
        type: data.type,
      },
    });

    // 6. PROCESS WEBHOOK
    logger.info(`Processing Linear webhook: ${data.action} for ${data.type}`);
    await processLinearWebhook(data);

    res.status(200).send('OK');
  } catch (error) {
    logger.error('Error handling Linear webhook:', error);
    res.status(500).send('Server Error'); // Always generic
  }
}

/**
 * Handle Vercel webhook events
 *
 * SECURITY FIX (HIGH-002): All error responses use generic messages
 * to prevent timing attacks and information leakage
 */
export async function handleVercelWebhook(req: Request, res: Response): Promise<void> {
  try {
    // SECURITY: Enforce HTTPS in production
    if (process.env['NODE_ENV'] === 'production' && req.protocol !== 'https') {
      logger.warn('Vercel webhook received over HTTP in production');
      res.status(400).send('Bad Request'); // Generic
      return;
    }

    const signature = req.headers['x-vercel-signature'] as string;
    const payload = req.body.toString();

    // 1. VERIFY SIGNATURE FIRST (before parsing)
    if (!signature) {
      logger.warn('Vercel webhook missing signature header');
      res.status(400).send('Bad Request'); // Generic
      return;
    }

    const webhookSecret = process.env['VERCEL_WEBHOOK_SECRET'];
    if (!webhookSecret) {
      logger.error('VERCEL_WEBHOOK_SECRET not configured');
      res.status(500).send('Server Error'); // Generic
      return;
    }

    const isValid = verifyVercelSignature(payload, signature, webhookSecret);
    if (!isValid) {
      logger.warn('Vercel webhook signature verification failed', { ip: req.ip });
      audit({
        action: 'webhook.signature_failed',
        resource: 'vercel',
        userId: 'system',
        timestamp: new Date().toISOString(),
        details: { ip: req.ip },
      });
      res.status(401).send('Unauthorized'); // Generic, same timing
      return;
    }

    // 2. NOW PARSE PAYLOAD (signature is valid)
    let data;
    try {
      data = JSON.parse(payload);
    } catch (error) {
      logger.error('Invalid webhook payload (valid signature)', { error, ip: req.ip });
      res.status(400).send('Bad Request'); // Same generic error
      return;
    }

    // 3. IDEMPOTENCY CHECK
    const webhookId = data.id || `${data.deployment?.url}-${Date.now()}`;
    if (processedWebhooks.has(webhookId)) {
      logger.info(`Duplicate Vercel webhook ignored: ${webhookId}`);
      res.status(200).send('OK');
      return;
    }

    // Mark as processed
    processedWebhooks.set(webhookId, true);

    // 4. AUDIT LOG
    audit({
      action: 'webhook.received',
      resource: 'vercel',
      userId: 'system',
      timestamp: new Date().toISOString(),
      details: {
        webhookId,
        type: data.type,
        deployment: data.deployment?.url,
      },
    });

    // 5. PROCESS WEBHOOK
    logger.info(`Processing Vercel webhook: ${data.type}`);
    await processVercelWebhook(data);

    res.status(200).send('OK');
  } catch (error) {
    logger.error('Error handling Vercel webhook:', error);
    res.status(500).send('Server Error'); // Always generic
  }
}

/**
 * Process Linear webhook data
 */
async function processLinearWebhook(data: any): Promise<void> {
  // TODO: Implement Linear webhook processing logic
  // - Issue state changes
  // - Issue assignments
  // - Comments
  // etc.
  logger.info('Linear webhook processed:', data);
}

/**
 * Process Vercel webhook data
 */
async function processVercelWebhook(data: any): Promise<void> {
  // TODO: Implement Vercel webhook processing logic
  // - Deployment events
  // - Preview deployments
  // etc.
  logger.info('Vercel webhook processed:', data);
}

/**
 * Create Express router for webhooks
 */
export function createWebhookRouter(): express.Router {
  const router = express.Router();

  // Use raw body for signature verification
  router.post('/linear', express.raw({ type: 'application/json' }), handleLinearWebhook);
  router.post('/vercel', express.raw({ type: 'application/json' }), handleVercelWebhook);

  return router;
}
