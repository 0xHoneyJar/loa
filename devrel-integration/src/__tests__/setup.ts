/**
 * Jest Test Setup
 *
 * Global test configuration and mocks
 */

// Set test environment variables
process.env['NODE_ENV'] = 'test';
process.env['DISCORD_TOKEN'] = 'test_discord_token';
process.env['LINEAR_API_KEY'] = 'test_linear_key';
process.env['LINEAR_WEBHOOK_SECRET'] = 'test_webhook_secret';
process.env['VERCEL_WEBHOOK_SECRET'] = 'test_vercel_secret';

// Mock console methods to reduce noise in tests
global.console = {
  ...console,
  log: jest.fn(),
  debug: jest.fn(),
  info: jest.fn(),
  warn: jest.fn(),
  error: jest.fn(),
};

// Extend Jest matchers if needed
expect.extend({
  // Custom matchers can be added here
});

// Global test timeout
jest.setTimeout(10000);
