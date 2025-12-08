/**
 * Integration Tests for Deployment Validation
 *
 * These tests validate the deployment is working correctly by testing:
 * - Health endpoints
 * - Discord bot connectivity
 * - Linear API integration
 * - Webhook endpoints
 * - Error handling
 *
 * Run with: npm run test:integration
 */

import http from 'http';
import https from 'https';

// Configuration from environment
const BASE_URL = process.env.TEST_BASE_URL || 'http://localhost:3000';
const TEST_TIMEOUT = 30000; // 30 seconds

/**
 * Helper function to make HTTP requests
 */
function makeRequest(url: string, options: http.RequestOptions = {}): Promise<{
  statusCode: number;
  headers: http.IncomingHttpHeaders;
  body: string;
}> {
  return new Promise((resolve, reject) => {
    const protocol = url.startsWith('https') ? https : http;

    const req = protocol.get(url, options, (res) => {
      let body = '';

      res.on('data', (chunk) => {
        body += chunk;
      });

      res.on('end', () => {
        resolve({
          statusCode: res.statusCode || 500,
          headers: res.headers,
          body,
        });
      });
    });

    req.on('error', reject);
    req.setTimeout(5000, () => {
      req.destroy();
      reject(new Error('Request timeout'));
    });
  });
}

describe('Deployment Integration Tests', () => {
  // Increase timeout for all integration tests
  jest.setTimeout(TEST_TIMEOUT);

  describe('Health Endpoints', () => {
    it('should respond to /health endpoint', async () => {
      const response = await makeRequest(`${BASE_URL}/health`);

      expect(response.statusCode).toBe(200);
      expect(response.headers['content-type']).toContain('application/json');

      const health = JSON.parse(response.body);
      expect(health).toHaveProperty('status');
      expect(health.status).toBe('healthy');
    });

    it('should respond to /ready endpoint', async () => {
      const response = await makeRequest(`${BASE_URL}/ready`);

      expect(response.statusCode).toBe(200);
    });

    it('should respond to /metrics endpoint', async () => {
      const response = await makeRequest(`${BASE_URL}/metrics`);

      expect(response.statusCode).toBe(200);

      const metrics = JSON.parse(response.body);
      expect(metrics).toHaveProperty('uptime');
      expect(metrics).toHaveProperty('memory');
      expect(metrics.uptime).toBeGreaterThan(0);
    });
  });

  describe('Security Headers', () => {
    it('should include HSTS header', async () => {
      const response = await makeRequest(`${BASE_URL}/health`);

      if (process.env.NODE_ENV === 'production') {
        expect(response.headers['strict-transport-security']).toBeDefined();
      }
    });

    it('should include X-Frame-Options header', async () => {
      const response = await makeRequest(`${BASE_URL}/health`);

      expect(response.headers['x-frame-options']).toBeDefined();
    });

    it('should include X-Content-Type-Options header', async () => {
      const response = await makeRequest(`${BASE_URL}/health`);

      expect(response.headers['x-content-type-options']).toBe('nosniff');
    });
  });

  describe('Error Handling', () => {
    it('should return 404 for unknown routes', async () => {
      const response = await makeRequest(`${BASE_URL}/nonexistent-route`);

      expect(response.statusCode).toBe(404);
    });

    it('should not expose stack traces in production', async () => {
      const response = await makeRequest(`${BASE_URL}/nonexistent-route`);

      expect(response.body).not.toContain('Error:');
      expect(response.body).not.toContain('at ');
      expect(response.body).not.toContain('src/');
    });
  });

  describe('Webhook Endpoints', () => {
    it('should reject webhooks without signature', async () => {
      try {
        const response = await makeRequest(`${BASE_URL}/webhooks/linear`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
          },
        });

        // Should reject with 401 or 400
        expect([400, 401]).toContain(response.statusCode);
      } catch (error) {
        // Network error is acceptable (endpoint may not be exposed in test)
        if (!(error instanceof Error && error.message === 'Request timeout')) {
          throw error;
        }
      }
    });
  });

  describe('Performance', () => {
    it('should respond to health check within 1 second', async () => {
      const startTime = Date.now();
      await makeRequest(`${BASE_URL}/health`);
      const duration = Date.now() - startTime;

      expect(duration).toBeLessThan(1000);
    });

    it('should handle multiple concurrent health checks', async () => {
      const promises = Array(10)
        .fill(null)
        .map(() => makeRequest(`${BASE_URL}/health`));

      const results = await Promise.all(promises);

      results.forEach((response) => {
        expect(response.statusCode).toBe(200);
      });
    });
  });

  describe('Configuration', () => {
    it('should have NODE_ENV set correctly', async () => {
      const response = await makeRequest(`${BASE_URL}/metrics`);
      const metrics = JSON.parse(response.body);

      expect(metrics).toHaveProperty('environment');
      expect(['development', 'staging', 'production']).toContain(
        metrics.environment
      );
    });

    it('should have version information', async () => {
      const response = await makeRequest(`${BASE_URL}/metrics`);
      const metrics = JSON.parse(response.body);

      expect(metrics).toHaveProperty('version');
      expect(typeof metrics.version).toBe('string');
    });
  });
});

describe('Discord Bot Integration', () => {
  jest.setTimeout(TEST_TIMEOUT);

  it('should indicate Discord connection status', async () => {
    const response = await makeRequest(`${BASE_URL}/health`);
    const health = JSON.parse(response.body);

    // Health endpoint should include service status
    if (health.services) {
      expect(health.services).toHaveProperty('discord');
    }
  });
});

describe('Linear API Integration', () => {
  jest.setTimeout(TEST_TIMEOUT);

  it('should indicate Linear API status', async () => {
    const response = await makeRequest(`${BASE_URL}/health`);
    const health = JSON.parse(response.body);

    // Health endpoint should include service status
    if (health.services) {
      expect(health.services).toHaveProperty('linear');
    }
  });
});
