import crypto from 'crypto';
import { Request, Response } from 'express';
import { handleLinearWebhook, handleVercelWebhook } from '../webhooks';

describe('Webhook Security', () => {
  let mockReq: Partial<Request>;
  let mockRes: Partial<Response>;
  let statusSpy: jest.Mock;
  let sendSpy: jest.Mock;
  let jsonSpy: jest.Mock;

  beforeEach(() => {
    statusSpy = jest.fn().mockReturnThis();
    sendSpy = jest.fn().mockReturnThis();
    jsonSpy = jest.fn().mockReturnThis();

    mockRes = {
      status: statusSpy,
      send: sendSpy,
      json: jsonSpy
    };

    process.env.LINEAR_WEBHOOK_SECRET = 'test_linear_secret';
    process.env.VERCEL_WEBHOOK_SECRET = 'test_vercel_secret';
    process.env.NODE_ENV = 'production';
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  describe('Linear Webhook', () => {
    const createLinearSignature = (payload: Buffer, secret: string): string => {
      return 'sha256=' + crypto
        .createHmac('sha256', secret)
        .update(payload)
        .digest('hex');
    };

    it('should reject webhooks over HTTP in production', async () => {
      const payload = Buffer.from(JSON.stringify({ data: 'test' }));

      mockReq = {
        protocol: 'http',
        headers: {},
        body: payload
      };

      await handleLinearWebhook(mockReq as Request, mockRes as Response);

      expect(statusSpy).toHaveBeenCalledWith(400);
      expect(sendSpy).toHaveBeenCalledWith('HTTPS required');
    });

    it('should reject webhooks without signature', async () => {
      const payload = Buffer.from(JSON.stringify({ data: 'test' }));

      mockReq = {
        protocol: 'https',
        headers: {},
        body: payload
      };

      await handleLinearWebhook(mockReq as Request, mockRes as Response);

      expect(statusSpy).toHaveBeenCalledWith(401);
      expect(sendSpy).toHaveBeenCalledWith('Missing signature');
    });

    it('should reject webhooks with invalid signature', async () => {
      const payload = Buffer.from(JSON.stringify({ data: 'test' }));
      const invalidSignature = 'sha256=invalid';

      mockReq = {
        protocol: 'https',
        headers: {
          'x-linear-signature': invalidSignature
        },
        body: payload
      };

      await handleLinearWebhook(mockReq as Request, mockRes as Response);

      expect(statusSpy).toHaveBeenCalledWith(401);
      expect(sendSpy).toHaveBeenCalledWith('Invalid signature');
    });

    it('should accept webhooks with valid signature', async () => {
      const webhookData = {
        webhookId: 'test-webhook-1',
        action: 'create',
        type: 'Issue',
        createdAt: new Date().toISOString()
      };
      const payload = Buffer.from(JSON.stringify(webhookData));
      const validSignature = createLinearSignature(payload, 'test_linear_secret');

      mockReq = {
        protocol: 'https',
        headers: {
          'x-linear-signature': validSignature
        },
        body: payload,
        ip: '127.0.0.1'
      };

      await handleLinearWebhook(mockReq as Request, mockRes as Response);

      expect(statusSpy).toHaveBeenCalledWith(200);
      expect(sendSpy).toHaveBeenCalledWith('OK');
    });

    it('should reject webhooks without timestamp', async () => {
      const webhookData = {
        webhookId: 'test-webhook-1',
        action: 'create',
        type: 'Issue'
        // Missing createdAt
      };
      const payload = Buffer.from(JSON.stringify(webhookData));
      const validSignature = createLinearSignature(payload, 'test_linear_secret');

      mockReq = {
        protocol: 'https',
        headers: {
          'x-linear-signature': validSignature
        },
        body: payload
      };

      await handleLinearWebhook(mockReq as Request, mockRes as Response);

      expect(statusSpy).toHaveBeenCalledWith(400);
      expect(sendSpy).toHaveBeenCalledWith('Missing timestamp');
    });

    it('should reject old webhooks (replay attack prevention)', async () => {
      const oldDate = new Date(Date.now() - 10 * 60 * 1000); // 10 minutes ago
      const webhookData = {
        webhookId: 'test-webhook-1',
        action: 'create',
        type: 'Issue',
        createdAt: oldDate.toISOString()
      };
      const payload = Buffer.from(JSON.stringify(webhookData));
      const validSignature = createLinearSignature(payload, 'test_linear_secret');

      mockReq = {
        protocol: 'https',
        headers: {
          'x-linear-signature': validSignature
        },
        body: payload
      };

      await handleLinearWebhook(mockReq as Request, mockRes as Response);

      expect(statusSpy).toHaveBeenCalledWith(400);
      expect(sendSpy).toHaveBeenCalledWith('Webhook expired');
    });

    it('should reject duplicate webhooks (idempotency)', async () => {
      const webhookData = {
        webhookId: 'duplicate-webhook',
        action: 'create',
        type: 'Issue',
        createdAt: new Date().toISOString()
      };
      const payload = Buffer.from(JSON.stringify(webhookData));
      const validSignature = createLinearSignature(payload, 'test_linear_secret');

      mockReq = {
        protocol: 'https',
        headers: {
          'x-linear-signature': validSignature
        },
        body: payload,
        ip: '127.0.0.1'
      };

      // First request - should succeed
      await handleLinearWebhook(mockReq as Request, mockRes as Response);
      expect(statusSpy).toHaveBeenCalledWith(200);

      // Reset mocks
      statusSpy.mockClear();
      sendSpy.mockClear();

      // Second request with same ID - should be rejected
      await handleLinearWebhook(mockReq as Request, mockRes as Response);
      expect(statusSpy).toHaveBeenCalledWith(200);
      expect(sendSpy).toHaveBeenCalledWith('Already processed');
    });
  });

  describe('Vercel Webhook', () => {
    const createVercelSignature = (payload: string, secret: string): string => {
      return crypto
        .createHmac('sha1', secret)
        .update(payload)
        .digest('hex');
    };

    it('should reject webhooks over HTTP in production', async () => {
      const payload = JSON.stringify({ type: 'deployment.created' });

      mockReq = {
        protocol: 'http',
        headers: {},
        body: Buffer.from(payload)
      };

      await handleVercelWebhook(mockReq as Request, mockRes as Response);

      expect(statusSpy).toHaveBeenCalledWith(400);
      expect(sendSpy).toHaveBeenCalledWith('HTTPS required');
    });

    it('should reject webhooks without signature', async () => {
      const payload = JSON.stringify({ type: 'deployment.created' });

      mockReq = {
        protocol: 'https',
        headers: {},
        body: Buffer.from(payload)
      };

      await handleVercelWebhook(mockReq as Request, mockRes as Response);

      expect(statusSpy).toHaveBeenCalledWith(401);
      expect(sendSpy).toHaveBeenCalledWith('Missing signature');
    });

    it('should reject webhooks with invalid signature', async () => {
      const payload = JSON.stringify({ type: 'deployment.created' });

      mockReq = {
        protocol: 'https',
        headers: {
          'x-vercel-signature': 'invalid'
        },
        body: Buffer.from(payload)
      };

      await handleVercelWebhook(mockReq as Request, mockRes as Response);

      expect(statusSpy).toHaveBeenCalledWith(401);
      expect(sendSpy).toHaveBeenCalledWith('Invalid signature');
    });

    it('should accept webhooks with valid signature', async () => {
      const webhookData = {
        id: 'vercel-webhook-1',
        type: 'deployment.created',
        deployment: {
          url: 'test-deployment.vercel.app'
        }
      };
      const payload = JSON.stringify(webhookData);
      const validSignature = createVercelSignature(payload, 'test_vercel_secret');

      mockReq = {
        protocol: 'https',
        headers: {
          'x-vercel-signature': validSignature
        },
        body: Buffer.from(payload),
        ip: '127.0.0.1'
      };

      await handleVercelWebhook(mockReq as Request, mockRes as Response);

      expect(statusSpy).toHaveBeenCalledWith(200);
      expect(sendSpy).toHaveBeenCalledWith('OK');
    });
  });

  describe('Timing Attack Prevention', () => {
    it('should use constant-time comparison for signatures', async () => {
      const payload = Buffer.from(JSON.stringify({
        webhookId: 'test',
        action: 'create',
        type: 'Issue',
        createdAt: new Date().toISOString()
      }));

      const validSignature = 'sha256=' + crypto
        .createHmac('sha256', 'test_linear_secret')
        .update(payload)
        .digest('hex');

      // Create slightly different signature
      const invalidSignature = validSignature.slice(0, -1) + 'a';

      mockReq = {
        protocol: 'https',
        headers: {
          'x-linear-signature': invalidSignature
        },
        body: payload
      };

      const start = process.hrtime.bigint();
      await handleLinearWebhook(mockReq as Request, mockRes as Response);
      const invalidDuration = process.hrtime.bigint() - start;

      // Reset
      statusSpy.mockClear();
      sendSpy.mockClear();

      mockReq.headers = {
        'x-linear-signature': validSignature
      };

      const start2 = process.hrtime.bigint();
      await handleLinearWebhook(mockReq as Request, mockRes as Response);
      const validDuration = process.hrtime.bigint() - start2;

      // Timing should be similar (not orders of magnitude different)
      // This is a basic check - real timing attacks are more sophisticated
      const ratio = Number(invalidDuration) / Number(validDuration);
      expect(ratio).toBeGreaterThan(0.5);
      expect(ratio).toBeLessThan(2.0);
    });
  });
});
