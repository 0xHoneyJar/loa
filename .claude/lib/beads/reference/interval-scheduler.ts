/**
 * Reference Implementation: Interval-Based Scheduler
 *
 * A simple scheduler using setInterval for periodic tasks.
 * This is a REFERENCE IMPLEMENTATION for demonstration and testing.
 * Production deployments may want cron-based or distributed scheduling.
 *
 * @module beads/reference/interval-scheduler
 * @version 1.0.0
 */

import type { SchedulerTask, IScheduler } from "../interfaces";

/**
 * Configuration for IntervalScheduler
 */
export interface IntervalSchedulerConfig {
  /** Enable verbose logging */
  verbose?: boolean;

  /** Auto-disable tasks after consecutive failures (default: 3) */
  maxFailures?: number;
}

/**
 * Interval-based Task Scheduler
 *
 * Uses Node.js setInterval for periodic task execution.
 * Tracks task status and handles failures gracefully.
 *
 * **Limitations**:
 * - Tasks run in-process only (no persistence)
 * - Intervals reset on restart
 * - No coordination for distributed systems
 *
 * @example
 * ```typescript
 * const scheduler = new IntervalScheduler({ verbose: true });
 *
 * await scheduler.register({
 *   id: "health-check",
 *   name: "Beads Health Check",
 *   intervalMs: 60000,
 *   handler: async () => { await checkHealth(); },
 *   enabled: true,
 * });
 *
 * // Later...
 * await scheduler.disable("health-check");
 * await scheduler.shutdown();
 * ```
 */
export class IntervalScheduler implements IScheduler {
  private tasks: Map<string, SchedulerTask> = new Map();
  private intervals: Map<string, ReturnType<typeof setInterval>> = new Map();
  private readonly verbose: boolean;
  private readonly maxFailures: number;

  constructor(config?: IntervalSchedulerConfig) {
    this.verbose = config?.verbose ?? false;
    this.maxFailures = config?.maxFailures ?? 3;
  }

  /**
   * Register a new scheduled task
   */
  async register(task: SchedulerTask): Promise<void> {
    if (this.tasks.has(task.id)) {
      throw new Error(`Task ${task.id} already registered`);
    }

    // Initialize task state
    const fullTask: SchedulerTask = {
      ...task,
      failureCount: 0,
      maxFailures: task.maxFailures ?? this.maxFailures,
    };

    this.tasks.set(task.id, fullTask);

    if (fullTask.enabled) {
      this.startInterval(fullTask);
    }

    if (this.verbose) {
      console.log(`[scheduler] Registered task: ${task.name} (${task.intervalMs}ms)`);
    }
  }

  /**
   * Enable a task
   */
  async enable(taskId: string): Promise<void> {
    const task = this.getTask(taskId);
    if (task.enabled) return;

    task.enabled = true;
    task.failureCount = 0; // Reset failures on re-enable
    this.startInterval(task);

    if (this.verbose) {
      console.log(`[scheduler] Enabled task: ${task.name}`);
    }
  }

  /**
   * Disable a task
   */
  async disable(taskId: string): Promise<void> {
    const task = this.getTask(taskId);
    if (!task.enabled) return;

    task.enabled = false;
    this.stopInterval(taskId);

    if (this.verbose) {
      console.log(`[scheduler] Disabled task: ${task.name}`);
    }
  }

  /**
   * Unregister a task
   */
  async unregister(taskId: string): Promise<void> {
    this.stopInterval(taskId);
    this.tasks.delete(taskId);

    if (this.verbose) {
      console.log(`[scheduler] Unregistered task: ${taskId}`);
    }
  }

  /**
   * Get status of all tasks
   */
  async getStatus(): Promise<SchedulerTask[]> {
    return Array.from(this.tasks.values());
  }

  /**
   * Manually run a task
   */
  async runNow(taskId: string): Promise<void> {
    const task = this.getTask(taskId);
    await this.executeTask(task);
  }

  /**
   * Shutdown scheduler and all tasks
   */
  async shutdown(): Promise<void> {
    for (const taskId of this.intervals.keys()) {
      this.stopInterval(taskId);
    }
    this.tasks.clear();

    if (this.verbose) {
      console.log("[scheduler] Shutdown complete");
    }
  }

  // ---------------------------------------------------------------------------
  // Private Helpers
  // ---------------------------------------------------------------------------

  private getTask(taskId: string): SchedulerTask {
    const task = this.tasks.get(taskId);
    if (!task) {
      throw new Error(`Task not found: ${taskId}`);
    }
    return task;
  }

  private startInterval(task: SchedulerTask): void {
    if (this.intervals.has(task.id)) {
      this.stopInterval(task.id);
    }

    const interval = setInterval(() => {
      this.executeTask(task).catch((e) => {
        console.error(`[scheduler] Unhandled error in ${task.id}:`, e);
      });
    }, task.intervalMs);

    this.intervals.set(task.id, interval);
  }

  private stopInterval(taskId: string): void {
    const interval = this.intervals.get(taskId);
    if (interval) {
      clearInterval(interval);
      this.intervals.delete(taskId);
    }
  }

  private async executeTask(task: SchedulerTask): Promise<void> {
    if (!task.enabled) return;

    try {
      await task.handler();

      // Success - reset failure count
      task.lastRun = new Date().toISOString();
      task.lastError = undefined;
      task.failureCount = 0;

      if (this.verbose) {
        console.log(`[scheduler] Task ${task.name} completed successfully`);
      }
    } catch (e) {
      const error = e instanceof Error ? e.message : String(e);

      task.lastRun = new Date().toISOString();
      task.lastError = error;
      task.failureCount = (task.failureCount ?? 0) + 1;

      console.error(`[scheduler] Task ${task.name} failed (${task.failureCount}): ${error}`);

      // Auto-disable after max failures
      if (task.failureCount >= (task.maxFailures ?? this.maxFailures)) {
        console.warn(`[scheduler] Task ${task.name} auto-disabled after ${task.failureCount} failures`);
        await this.disable(task.id);
      }
    }
  }
}

/**
 * Factory function
 */
export function createIntervalScheduler(
  config?: IntervalSchedulerConfig,
): IntervalScheduler {
  return new IntervalScheduler(config);
}
