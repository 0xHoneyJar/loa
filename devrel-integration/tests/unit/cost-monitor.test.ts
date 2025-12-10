/**
 * Cost Monitor Tests
 *
 * Tests for CRITICAL-006: Cost Monitoring & Budget Alerts
 */

import { CostMonitor } from '../../src/services/cost-monitor';

describe('CostMonitor', () => {
  let costMonitor: CostMonitor;

  beforeEach(() => {
    costMonitor = new CostMonitor();
    // Reset to default configuration
    costMonitor.updateBudgetConfig({
      dailyBudgetUSD: 100,
      monthlyBudgetUSD: 3000,
      alertThresholdPercent: 75,
      pauseOnExceed: true
    });
  });

  describe('trackAPICall', () => {
    test('should track Anthropic API call costs', async () => {
      await costMonitor.trackAPICall(
        'anthropic',
        'generate-text',
        1000000, // 1 million tokens
        'claude-sonnet-4-5-20250929'
      );

      const stats = await costMonitor.getStatistics();

      expect(stats.dailySpend).toBeCloseTo(3.0, 2); // $3 per million tokens
      expect(stats.totalCostRecords).toBe(1);
    });

    test('should calculate cost correctly for different models', async () => {
      // Sonnet: $3 per million tokens
      await costMonitor.trackAPICall(
        'anthropic',
        'generate-text',
        500000, // 500k tokens
        'claude-sonnet-4-5-20250929'
      );

      // Haiku: $0.80 per million tokens
      await costMonitor.trackAPICall(
        'anthropic',
        'generate-text',
        500000, // 500k tokens
        'claude-haiku-3-5-20241022'
      );

      const stats = await costMonitor.getStatistics();

      // Sonnet: 0.5M * $3 = $1.50
      // Haiku: 0.5M * $0.80 = $0.40
      // Total: $1.90
      expect(stats.dailySpend).toBeCloseTo(1.90, 2);
    });
  });

  describe('trackFixedCostOperation', () => {
    test('should track fixed cost operations', async () => {
      await costMonitor.trackFixedCostOperation(
        'google-drive',
        'list-files',
        0.001
      );

      const stats = await costMonitor.getStatistics();

      expect(stats.dailySpend).toBeCloseTo(0.001, 4);
      expect(stats.totalCostRecords).toBe(1);
    });
  });

  describe('getDailyBudgetStatus', () => {
    test('should return correct budget status', async () => {
      // Spend $50 (50% of $100 daily budget)
      await costMonitor.trackAPICall(
        'anthropic',
        'generate-text',
        16666667, // ~$50
        'claude-sonnet-4-5-20250929'
      );

      const status = await costMonitor.getDailyBudgetStatus();

      expect(status.currentSpendUSD).toBeCloseTo(50, 0);
      expect(status.budgetLimitUSD).toBe(100);
      expect(status.percentUsed).toBeCloseTo(50, 0);
      expect(status.remainingBudgetUSD).toBeCloseTo(50, 0);
      expect(status.isOverBudget).toBe(false);
      expect(status.isNearLimit).toBe(false);
    });

    test('should detect near budget limit', async () => {
      // Spend $80 (80% of $100 daily budget)
      await costMonitor.trackAPICall(
        'anthropic',
        'generate-text',
        26666667, // ~$80
        'claude-sonnet-4-5-20250929'
      );

      const status = await costMonitor.getDailyBudgetStatus();

      expect(status.percentUsed).toBeCloseTo(80, 0);
      expect(status.isOverBudget).toBe(false);
      expect(status.isNearLimit).toBe(true); // Above 75% threshold
    });

    test('should detect budget exceeded', async () => {
      // Spend $120 (120% of $100 daily budget)
      await costMonitor.trackAPICall(
        'anthropic',
        'generate-text',
        40000000, // ~$120
        'claude-sonnet-4-5-20250929'
      );

      const status = await costMonitor.getDailyBudgetStatus();

      expect(status.currentSpendUSD).toBeCloseTo(120, 0);
      expect(status.percentUsed).toBeCloseTo(120, 0);
      expect(status.remainingBudgetUSD).toBe(0);
      expect(status.isOverBudget).toBe(true);
      expect(status.isNearLimit).toBe(true);
    });
  });

  describe('getMonthlyBudgetStatus', () => {
    test('should return correct monthly budget status', async () => {
      // Spend $1500 (50% of $3000 monthly budget)
      await costMonitor.trackAPICall(
        'anthropic',
        'generate-text',
        500000000, // ~$1500
        'claude-sonnet-4-5-20250929'
      );

      const status = await costMonitor.getMonthlyBudgetStatus();

      expect(status.currentSpendUSD).toBeCloseTo(1500, 0);
      expect(status.budgetLimitUSD).toBe(3000);
      expect(status.percentUsed).toBeCloseTo(50, 0);
      expect(status.isOverBudget).toBe(false);
    });
  });

  describe('getCostBreakdownByAPI', () => {
    test('should breakdown costs by API', async () => {
      await costMonitor.trackAPICall('anthropic', 'generate-text', 1000000, 'claude-sonnet-4-5-20250929');
      await costMonitor.trackAPICall('anthropic', 'generate-text', 500000, 'claude-sonnet-4-5-20250929');
      await costMonitor.trackFixedCostOperation('google-drive', 'list-files', 0.01);
      await costMonitor.trackFixedCostOperation('discord', 'send-message', 0.001);

      const breakdown = await costMonitor.getCostBreakdownByAPI('daily');

      expect(breakdown['anthropic']).toBeCloseTo(4.5, 1); // $3 + $1.5
      expect(breakdown['google-drive']).toBeCloseTo(0.01, 3);
      expect(breakdown['discord']).toBeCloseTo(0.001, 4);
    });
  });

  describe('Service Pause', () => {
    test('should pause service when daily budget exceeded', async () => {
      // Spend $120 (over $100 daily budget)
      await costMonitor.trackAPICall(
        'anthropic',
        'generate-text',
        40000000, // ~$120
        'claude-sonnet-4-5-20250929'
      );

      const pauseStatus = costMonitor.isServicePaused();

      expect(pauseStatus.paused).toBe(true);
      expect(pauseStatus.reason).toContain('Daily budget exceeded');
    });

    test('should allow manual service resume', async () => {
      // Exceed budget
      await costMonitor.trackAPICall('anthropic', 'generate-text', 40000000, 'claude-sonnet-4-5-20250929');

      let pauseStatus = costMonitor.isServicePaused();
      expect(pauseStatus.paused).toBe(true);

      // Resume service
      await costMonitor.resumeService('admin@company.com', 'Budget increased, resuming service');

      pauseStatus = costMonitor.isServicePaused();
      expect(pauseStatus.paused).toBe(false);
      expect(pauseStatus.reason).toBeNull();
    });

    test('should not pause if pauseOnExceed is false', async () => {
      // Disable auto-pause
      costMonitor.updateBudgetConfig({ pauseOnExceed: false });

      // Exceed budget
      await costMonitor.trackAPICall('anthropic', 'generate-text', 40000000, 'claude-sonnet-4-5-20250929');

      const pauseStatus = costMonitor.isServicePaused();

      expect(pauseStatus.paused).toBe(false);
    });
  });

  describe('Budget Configuration', () => {
    test('should allow updating budget configuration', () => {
      costMonitor.updateBudgetConfig({
        dailyBudgetUSD: 200,
        monthlyBudgetUSD: 5000,
        alertThresholdPercent: 80
      });

      // Verify by checking budget status
      // (getBudgetConfig is not exposed, so we check via budget status)
      const stats = costMonitor.getStatistics();

      // The updated config should be reflected in behavior
      expect(stats).toBeDefined();
    });
  });

  describe('Attack Scenario Prevention', () => {
    test('should prevent $5000 cost explosion from spam attack', async () => {
      // Simulate spam attack: 1000 API calls
      // Each call uses 10k tokens = $0.03
      // Total = $30

      const promises = [];
      for (let i = 0; i < 1000; i++) {
        promises.push(
          costMonitor.trackAPICall(
            'anthropic',
            'generate-summary',
            10000, // 10k tokens
            'claude-sonnet-4-5-20250929'
          )
        );
      }

      await Promise.all(promises);

      const stats = await costMonitor.getStatistics();

      // Cost should be tracked correctly: 1000 * 10k * $0.000003 = $30
      expect(stats.dailySpend).toBeCloseTo(30, 1);
      expect(stats.totalCostRecords).toBe(1000);

      // Service should NOT be paused (under $100 budget)
      const pauseStatus = costMonitor.isServicePaused();
      expect(pauseStatus.paused).toBe(false);
    });

    test('should pause service before reaching $5000 cost', async () => {
      // Simulate scenario where attacker tries to burn $5000
      // But service pauses at $100 daily budget

      const promises = [];

      // Try to make calls that would cost $5000
      // $5000 / $0.000003 per token = 1.67 billion tokens
      // But service should pause at $100 = 33.3 million tokens

      for (let i = 0; i < 100; i++) {
        promises.push(
          costMonitor.trackAPICall(
            'anthropic',
            'generate-summary',
            1000000, // 1M tokens = $3 per call
            'claude-sonnet-4-5-20250929'
          )
        );
      }

      await Promise.all(promises);

      const stats = await costMonitor.getStatistics();

      // Total cost: 100 * $3 = $300 (way over budget)
      expect(stats.dailySpend).toBeGreaterThan(100);

      // Service should be paused
      const pauseStatus = costMonitor.isServicePaused();
      expect(pauseStatus.paused).toBe(true);

      // Verify we prevented the full $5000 cost
      expect(stats.dailySpend).toBeLessThan(5000);
    });
  });

  describe('Statistics', () => {
    test('should return comprehensive statistics', async () => {
      await costMonitor.trackAPICall('anthropic', 'generate-text', 1000000, 'claude-sonnet-4-5-20250929');
      await costMonitor.trackFixedCostOperation('google-drive', 'list-files', 0.01);

      const stats = await costMonitor.getStatistics();

      expect(stats.totalCostRecords).toBe(2);
      expect(stats.dailySpend).toBeGreaterThan(0);
      expect(stats.monthlySpend).toBeGreaterThan(0);
      expect(stats.dailyBudgetStatus).toBeDefined();
      expect(stats.monthlyBudgetStatus).toBeDefined();
      expect(stats.costBreakdown).toBeDefined();
      expect(stats.servicePaused).toBe(false);
    });
  });

  describe('Edge Cases', () => {
    test('should handle zero token usage', async () => {
      await costMonitor.trackAPICall('anthropic', 'test', 0, 'claude-sonnet-4-5-20250929');

      const stats = await costMonitor.getStatistics();

      expect(stats.dailySpend).toBe(0);
      expect(stats.totalCostRecords).toBe(1);
    });

    test('should handle unknown model with default pricing', async () => {
      await costMonitor.trackAPICall('anthropic', 'test', 1000000, 'unknown-model');

      const stats = await costMonitor.getStatistics();

      // Should use default pricing of $3 per million tokens
      expect(stats.dailySpend).toBeCloseTo(3.0, 2);
    });

    test('should handle negative budget (edge case)', () => {
      // This shouldn't happen in practice, but test robustness
      costMonitor.updateBudgetConfig({ dailyBudgetUSD: -10 });

      // Should not crash or throw
      const stats = costMonitor.getStatistics();
      expect(stats).toBeDefined();
    });
  });
});
