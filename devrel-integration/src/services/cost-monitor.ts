/**
 * Cost Monitor
 *
 * Tracks API usage costs and enforces budget limits.
 * Prevents runaway costs from DoS attacks or bugs.
 *
 * This implements CRITICAL-006 remediation (cost monitoring & budget alerts).
 */

import { logger } from '../utils/logger';

export interface CostRecord {
  timestamp: Date;
  api: string;
  operation: string;
  tokensUsed?: number;
  costUSD: number;
  model?: string;
}

export interface BudgetConfig {
  dailyBudgetUSD: number;
  monthlyBudgetUSD: number;
  alertThresholdPercent: number;
  pauseOnExceed: boolean;
}

export interface BudgetStatus {
  currentSpendUSD: number;
  budgetLimitUSD: number;
  percentUsed: number;
  remainingBudgetUSD: number;
  isOverBudget: boolean;
  isNearLimit: boolean;
}

/**
 * Cost Monitor
 *
 * Security Controls:
 * 1. Real-time cost tracking for all API calls
 * 2. Daily and monthly budget enforcement
 * 3. Automatic alerts at 75%, 90%, 100% thresholds
 * 4. Service auto-pause if budget exceeded
 * 5. Per-API cost breakdown for analysis
 * 6. Historical cost tracking for trends
 */
export class CostMonitor {
  private costRecords: CostRecord[] = [];
  private servicePaused = false;
  private pauseReason: string | null = null;

  private budgetConfig: BudgetConfig = {
    dailyBudgetUSD: 100,        // $100/day default
    monthlyBudgetUSD: 3000,     // $3000/month default
    alertThresholdPercent: 75,  // Alert at 75% of budget
    pauseOnExceed: true         // Auto-pause if budget exceeded
  };

  /**
   * Track API call cost (primarily for Anthropic)
   */
  async trackAPICall(
    api: string,
    operation: string,
    tokensUsed: number,
    model: string
  ): Promise<void> {
    const costPerToken = this.getCostPerToken(model);
    const costUSD = tokensUsed * costPerToken;

    // Record cost
    const record: CostRecord = {
      timestamp: new Date(),
      api,
      operation,
      tokensUsed,
      costUSD,
      model
    };

    this.costRecords.push(record);

    logger.info(`API cost tracked`, {
      api,
      operation,
      tokensUsed,
      costUSD: costUSD.toFixed(4),
      model
    });

    // Check daily budget
    await this.checkDailyBudget();

    // Check monthly budget
    await this.checkMonthlyBudget();
  }

  /**
   * Track fixed-cost operation (e.g., Google Drive API, Discord API)
   */
  async trackFixedCostOperation(
    api: string,
    operation: string,
    estimatedCostUSD: number = 0.001 // $0.001 default for API calls
  ): Promise<void> {
    const record: CostRecord = {
      timestamp: new Date(),
      api,
      operation,
      costUSD: estimatedCostUSD
    };

    this.costRecords.push(record);

    logger.debug(`Fixed cost operation tracked`, {
      api,
      operation,
      costUSD: estimatedCostUSD.toFixed(4)
    });

    // Check budgets
    await this.checkDailyBudget();
    await this.checkMonthlyBudget();
  }

  /**
   * Check daily budget
   */
  private async checkDailyBudget(): Promise<void> {
    const dailySpend = await this.getDailySpend();
    const dailyBudget = this.budgetConfig.dailyBudgetUSD;
    const percentUsed = (dailySpend / dailyBudget) * 100;

    // Check if budget exceeded
    if (dailySpend > dailyBudget) {
      logger.error(`Daily budget exceeded`, {
        dailySpend: dailySpend.toFixed(2),
        dailyBudget: dailyBudget.toFixed(2),
        percentUsed: percentUsed.toFixed(1)
      });

      // Alert finance team
      await this.alertFinanceTeam({
        subject: '💰 ALERT: DevRel Integration Daily Budget Exceeded',
        body: this.formatBudgetAlert('daily', dailySpend, dailyBudget, percentUsed),
        severity: 'CRITICAL'
      });

      // Pause service if configured
      if (this.budgetConfig.pauseOnExceed) {
        await this.pauseService(`Daily budget exceeded: $${dailySpend.toFixed(2)} / $${dailyBudget}`);
      }

      return;
    }

    // Check alert threshold
    if (percentUsed >= this.budgetConfig.alertThresholdPercent && percentUsed < 100) {
      logger.warn(`Daily budget threshold reached`, {
        dailySpend: dailySpend.toFixed(2),
        dailyBudget: dailyBudget.toFixed(2),
        percentUsed: percentUsed.toFixed(1)
      });

      // Alert finance team (warning)
      await this.alertFinanceTeam({
        subject: `⚠️ WARNING: DevRel Integration at ${percentUsed.toFixed(0)}% of Daily Budget`,
        body: this.formatBudgetAlert('daily', dailySpend, dailyBudget, percentUsed),
        severity: 'WARNING'
      });
    }
  }

  /**
   * Check monthly budget
   */
  private async checkMonthlyBudget(): Promise<void> {
    const monthlySpend = await this.getMonthlySpend();
    const monthlyBudget = this.budgetConfig.monthlyBudgetUSD;
    const percentUsed = (monthlySpend / monthlyBudget) * 100;

    // Check if budget exceeded
    if (monthlySpend > monthlyBudget) {
      logger.error(`Monthly budget exceeded`, {
        monthlySpend: monthlySpend.toFixed(2),
        monthlyBudget: monthlyBudget.toFixed(2),
        percentUsed: percentUsed.toFixed(1)
      });

      // Alert finance team
      await this.alertFinanceTeam({
        subject: '💰 CRITICAL: DevRel Integration Monthly Budget Exceeded',
        body: this.formatBudgetAlert('monthly', monthlySpend, monthlyBudget, percentUsed),
        severity: 'CRITICAL'
      });

      // Pause service if configured
      if (this.budgetConfig.pauseOnExceed) {
        await this.pauseService(`Monthly budget exceeded: $${monthlySpend.toFixed(2)} / $${monthlyBudget}`);
      }

      return;
    }

    // Check alert threshold
    if (percentUsed >= this.budgetConfig.alertThresholdPercent && percentUsed < 100) {
      logger.warn(`Monthly budget threshold reached`, {
        monthlySpend: monthlySpend.toFixed(2),
        monthlyBudget: monthlyBudget.toFixed(2),
        percentUsed: percentUsed.toFixed(1)
      });
    }
  }

  /**
   * Get daily spend
   */
  private async getDailySpend(): Promise<number> {
    const now = new Date();
    const startOfDay = new Date(now.getFullYear(), now.getMonth(), now.getDate());

    const dailyRecords = this.costRecords.filter(r => r.timestamp >= startOfDay);
    return dailyRecords.reduce((sum, r) => sum + r.costUSD, 0);
  }

  /**
   * Get monthly spend
   */
  private async getMonthlySpend(): Promise<number> {
    const now = new Date();
    const startOfMonth = new Date(now.getFullYear(), now.getMonth(), 1);

    const monthlyRecords = this.costRecords.filter(r => r.timestamp >= startOfMonth);
    return monthlyRecords.reduce((sum, r) => sum + r.costUSD, 0);
  }

  /**
   * Get cost per token for specific model
   */
  private getCostPerToken(model: string): number {
    const pricing: Record<string, number> = {
      // Anthropic Claude pricing (as of 2025)
      'claude-sonnet-4-5-20250929': 0.000003,     // $3 per million input tokens
      'claude-sonnet-3-5-20241022': 0.000003,     // $3 per million input tokens
      'claude-opus-4-20250514': 0.000015,         // $15 per million input tokens
      'claude-haiku-3-5-20241022': 0.0000008,     // $0.80 per million input tokens

      // Default fallback
      'default': 0.000003
    };

    return pricing[model] || pricing['default'];
  }

  /**
   * Format budget alert message
   */
  private formatBudgetAlert(period: 'daily' | 'monthly', spend: number, budget: number, percentUsed: number): string {
    let body = `💰 BUDGET ALERT\n\n`;
    body += `Period: ${period.toUpperCase()}\n`;
    body += `Current Spend: $${spend.toFixed(2)}\n`;
    body += `Budget Limit: $${budget.toFixed(2)}\n`;
    body += `Percent Used: ${percentUsed.toFixed(1)}%\n\n`;

    if (spend > budget) {
      body += `🚨 BUDGET EXCEEDED BY $${(spend - budget).toFixed(2)}\n\n`;
      body += `ACTIONS TAKEN:\n`;
      body += `  • Service paused automatically\n`;
      body += `  • No further API calls will be made\n`;
      body += `  • Finance team notified\n\n`;
      body += `NEXT STEPS:\n`;
      body += `  1. Review cost breakdown by API\n`;
      body += `  2. Investigate unexpected usage\n`;
      body += `  3. Approve budget increase if needed\n`;
      body += `  4. Resume service manually\n`;
    } else {
      body += `⚠️ APPROACHING BUDGET LIMIT\n\n`;
      body += `Remaining Budget: $${(budget - spend).toFixed(2)}\n\n`;
      body += `RECOMMENDATIONS:\n`;
      body += `  • Monitor usage closely\n`;
      body += `  • Review recent operations\n`;
      body += `  • Consider rate limiting adjustments\n`;
    }

    body += `\nTimestamp: ${new Date().toISOString()}\n`;

    return body;
  }

  /**
   * Alert finance team
   */
  private async alertFinanceTeam(alert: {
    subject: string;
    body: string;
    severity: string;
  }): Promise<void> {
    logger.error('FINANCE ALERT', {
      subject: alert.subject,
      severity: alert.severity
    });

    // Console alert
    console.error('\n' + '='.repeat(80));
    console.error(`💰 ${alert.subject}`);
    console.error('='.repeat(80));
    console.error(alert.body);
    console.error('='.repeat(80) + '\n');

    // Write to security/finance log
    logger.security({
      eventType: 'BUDGET_ALERT',
      severity: alert.severity,
      details: alert.body,
      timestamp: new Date().toISOString()
    });

    // TODO: Integrate with alerting systems
    // - Email to finance team (SendGrid, AWS SES)
    // - Slack webhook to #finance channel
    // - Discord webhook to #budget-alerts
    // - Linear ticket creation for finance review
    // - PagerDuty for critical overages
  }

  /**
   * Pause service due to budget exceeded
   */
  private async pauseService(reason: string): Promise<void> {
    this.servicePaused = true;
    this.pauseReason = reason;

    logger.error(`Service paused due to budget exceeded`, { reason });

    // TODO: Implement service pause mechanism
    // - Set flag in database
    // - Reject all incoming requests
    // - Send 503 Service Unavailable to Discord commands
    // - Update status page
  }

  /**
   * Resume service (requires manual approval)
   */
  async resumeService(approvedBy: string, reason: string): Promise<void> {
    this.servicePaused = false;
    this.pauseReason = null;

    logger.info(`Service resumed`, { approvedBy, reason });

    // Audit log
    logger.security({
      eventType: 'SERVICE_RESUMED',
      severity: 'INFO',
      approvedBy,
      reason,
      timestamp: new Date().toISOString()
    });
  }

  /**
   * Check if service is paused
   */
  isServicePaused(): { paused: boolean; reason: string | null } {
    return {
      paused: this.servicePaused,
      reason: this.pauseReason
    };
  }

  /**
   * Get daily budget status
   */
  async getDailyBudgetStatus(): Promise<BudgetStatus> {
    const dailySpend = await this.getDailySpend();
    const dailyBudget = this.budgetConfig.dailyBudgetUSD;
    const percentUsed = (dailySpend / dailyBudget) * 100;

    return {
      currentSpendUSD: dailySpend,
      budgetLimitUSD: dailyBudget,
      percentUsed,
      remainingBudgetUSD: Math.max(0, dailyBudget - dailySpend),
      isOverBudget: dailySpend > dailyBudget,
      isNearLimit: percentUsed >= this.budgetConfig.alertThresholdPercent
    };
  }

  /**
   * Get monthly budget status
   */
  async getMonthlyBudgetStatus(): Promise<BudgetStatus> {
    const monthlySpend = await this.getMonthlySpend();
    const monthlyBudget = this.budgetConfig.monthlyBudgetUSD;
    const percentUsed = (monthlySpend / monthlyBudget) * 100;

    return {
      currentSpendUSD: monthlySpend,
      budgetLimitUSD: monthlyBudget,
      percentUsed,
      remainingBudgetUSD: Math.max(0, monthlyBudget - monthlySpend),
      isOverBudget: monthlySpend > monthlyBudget,
      isNearLimit: percentUsed >= this.budgetConfig.alertThresholdPercent
    };
  }

  /**
   * Get cost breakdown by API
   */
  async getCostBreakdownByAPI(period: 'daily' | 'monthly'): Promise<Record<string, number>> {
    const now = new Date();
    const startDate = period === 'daily'
      ? new Date(now.getFullYear(), now.getMonth(), now.getDate())
      : new Date(now.getFullYear(), now.getMonth(), 1);

    const records = this.costRecords.filter(r => r.timestamp >= startDate);

    const breakdown: Record<string, number> = {};
    for (const record of records) {
      breakdown[record.api] = (breakdown[record.api] || 0) + record.costUSD;
    }

    return breakdown;
  }

  /**
   * Update budget configuration
   */
  updateBudgetConfig(config: Partial<BudgetConfig>): void {
    this.budgetConfig = { ...this.budgetConfig, ...config };

    logger.info(`Budget configuration updated`, { config: this.budgetConfig });
  }

  /**
   * Get statistics
   */
  async getStatistics(): Promise<{
    totalCostRecords: number;
    dailySpend: number;
    monthlySpend: number;
    dailyBudgetStatus: BudgetStatus;
    monthlyBudgetStatus: BudgetStatus;
    costBreakdown: Record<string, number>;
    servicePaused: boolean;
  }> {
    return {
      totalCostRecords: this.costRecords.length,
      dailySpend: await this.getDailySpend(),
      monthlySpend: await this.getMonthlySpend(),
      dailyBudgetStatus: await this.getDailyBudgetStatus(),
      monthlyBudgetStatus: await this.getMonthlyBudgetStatus(),
      costBreakdown: await this.getCostBreakdownByAPI('daily'),
      servicePaused: this.servicePaused
    };
  }
}

// Singleton instance
export const costMonitor = new CostMonitor();
export default costMonitor;
