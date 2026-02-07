/**
 * Task Scheduler — periodic task execution with state machine, overlap policy, and jitter.
 *
 * State machine: PENDING → RUNNING → COMPLETED/FAILED
 * Extended states added in T2.1b (TIMED_OUT, DISABLED) and T2.1c (mutex, shutdown).
 *
 * Per SDD Section 4.3.1.
 */
import { LoaLibError } from "../errors.js";
import {
  CircuitBreaker,
  type CircuitBreakerConfig,
} from "../persistence/circuit-breaker.js";

// ── Types ────────────────────────────────────────────

export type TaskState = "PENDING" | "RUNNING" | "COMPLETED" | "FAILED" | "TIMED_OUT" | "DISABLED";

export interface ScheduledTaskConfig {
  id: string;
  fn: (signal?: AbortSignal) => Promise<void>;
  intervalMs: number;
  /** If true, skip this firing if task is still running. Default: true */
  skipOnOverlap?: boolean;
  /** Maximum random jitter in ms added to interval. Default: 0 */
  jitterMs?: number;
  /** Start enabled. Default: true */
  enabled?: boolean;
  /** Per-task circuit breaker config. If omitted, no CB is used. */
  circuitBreaker?: Partial<CircuitBreakerConfig>;
  /** Mutex group name. Tasks in the same group execute serially. */
  mutexGroup?: string;
}

export interface TaskStatus {
  id: string;
  state: TaskState;
  enabled: boolean;
  lastRunAt: number | null;
  lastError: Error | null;
  runCount: number;
  failCount: number;
  cbState?: "CLOSED" | "OPEN" | "HALF_OPEN";
}

export interface SchedulerConfig {
  clock?: { now(): number };
  logger?: { info(msg: string): void; error(msg: string): void };
  onTaskError?: (taskId: string, error: Error) => void;
  /** Max ms to wait for running tasks during shutdown(). Default: 5000 */
  shutdownTimeoutMs?: number;
}

// ── Internal Task Entry ─────────────────────────────

interface TaskEntry {
  config: ScheduledTaskConfig;
  state: TaskState;
  enabled: boolean;
  lastRunAt: number | null;
  lastError: Error | null;
  runCount: number;
  failCount: number;
  timerId: ReturnType<typeof setTimeout> | null;
  cb: CircuitBreaker | null;
  abortController: AbortController | null;
  runningPromise: Promise<void> | null;
}

// ── Scheduler Class ─────────────────────────────────

export class Scheduler {
  private readonly tasks = new Map<string, TaskEntry>();
  private readonly clock: { now(): number };
  private readonly logger?: { info(msg: string): void; error(msg: string): void };
  private readonly onTaskError?: (taskId: string, error: Error) => void;
  private readonly shutdownTimeoutMs: number;
  /** Per-group queue of pending mutex operations */
  private readonly mutexQueues = new Map<string, Promise<void>>();
  private running = false;
  private shuttingDown = false;

  constructor(config?: SchedulerConfig) {
    this.clock = config?.clock ?? { now: () => Date.now() };
    this.logger = config?.logger;
    this.onTaskError = config?.onTaskError;
    this.shutdownTimeoutMs = config?.shutdownTimeoutMs ?? 5000;
  }

  register(taskConfig: ScheduledTaskConfig): void {
    if (this.tasks.has(taskConfig.id)) {
      throw new LoaLibError(
        `Task "${taskConfig.id}" is already registered`,
        "SCH_004",
        false,
      );
    }

    const cb = taskConfig.circuitBreaker
      ? new CircuitBreaker(taskConfig.circuitBreaker, { now: this.clock.now })
      : null;

    const entry: TaskEntry = {
      config: { skipOnOverlap: true, jitterMs: 0, enabled: true, ...taskConfig },
      state: "PENDING",
      enabled: taskConfig.enabled ?? true,
      lastRunAt: null,
      lastError: null,
      runCount: 0,
      failCount: 0,
      timerId: null,
      cb,
      abortController: null,
      runningPromise: null,
    };

    this.tasks.set(taskConfig.id, entry);
    this.logger?.info(`Task registered: ${taskConfig.id}`);

    // If scheduler is already running, start the task's interval
    if (this.running && entry.enabled) {
      this.scheduleNext(entry);
    }
  }

  unregister(taskId: string): void {
    const entry = this.getEntry(taskId);
    if (entry.timerId !== null) {
      clearTimeout(entry.timerId);
    }
    this.tasks.delete(taskId);
    this.logger?.info(`Task unregistered: ${taskId}`);
  }

  enable(taskId: string): void {
    const entry = this.getEntry(taskId);
    entry.enabled = true;
    if (this.running && entry.timerId === null) {
      this.scheduleNext(entry);
    }
  }

  disable(taskId: string): void {
    const entry = this.getEntry(taskId);
    entry.enabled = false;
    if (entry.timerId !== null) {
      clearTimeout(entry.timerId);
      entry.timerId = null;
    }
  }

  getStatus(taskId: string): TaskStatus {
    const entry = this.getEntry(taskId);
    return this.toStatus(entry);
  }

  getAllStatuses(): TaskStatus[] {
    return Array.from(this.tasks.values()).map((e) => this.toStatus(e));
  }

  start(): void {
    if (this.running) return;
    this.running = true;
    for (const entry of this.tasks.values()) {
      if (entry.enabled) {
        this.scheduleNext(entry);
      }
    }
    this.logger?.info("Scheduler started");
  }

  stop(): void {
    if (!this.running) return;
    this.running = false;
    for (const entry of this.tasks.values()) {
      if (entry.timerId !== null) {
        clearTimeout(entry.timerId);
        entry.timerId = null;
      }
    }
    this.logger?.info("Scheduler stopped");
  }

  /** Manually trigger a task immediately. */
  async runNow(taskId: string): Promise<void> {
    const entry = this.getEntry(taskId);
    await this.executeTask(entry);
  }

  /** Cancel a running task by aborting its AbortController. */
  cancel(taskId: string): void {
    const entry = this.getEntry(taskId);
    if (entry.abortController) {
      entry.abortController.abort();
      this.logger?.info(`Task ${taskId}: cancelled`);
    }
  }

  isRunning(): boolean {
    return this.running;
  }

  /**
   * Graceful shutdown: stop scheduling, abort all running tasks,
   * then wait for running tasks to drain (up to shutdownTimeoutMs).
   */
  async shutdown(timeoutMs?: number): Promise<void> {
    if (this.shuttingDown) return;
    this.shuttingDown = true;
    this.logger?.info("Scheduler shutting down");

    // Stop all timers
    this.stop();

    // Abort all running tasks
    const drainPromises: Promise<void>[] = [];
    for (const entry of this.tasks.values()) {
      if (entry.abortController) {
        entry.abortController.abort();
      }
      if (entry.runningPromise) {
        drainPromises.push(entry.runningPromise);
      }
    }

    if (drainPromises.length > 0) {
      const timeout = timeoutMs ?? this.shutdownTimeoutMs;
      const timer = new Promise<void>((resolve) => setTimeout(resolve, timeout));
      await Promise.race([
        Promise.allSettled(drainPromises),
        timer,
      ]);
    }

    this.shuttingDown = false;
    this.logger?.info("Scheduler shutdown complete");
  }

  // ── Private ────────────────────────────────────────

  private getEntry(taskId: string): TaskEntry {
    const entry = this.tasks.get(taskId);
    if (!entry) {
      throw new LoaLibError(
        `Task "${taskId}" not found`,
        "SCH_005",
        false,
      );
    }
    return entry;
  }

  private toStatus(entry: TaskEntry): TaskStatus {
    return {
      id: entry.config.id,
      state: entry.state,
      enabled: entry.enabled,
      lastRunAt: entry.lastRunAt,
      lastError: entry.lastError,
      runCount: entry.runCount,
      failCount: entry.failCount,
      cbState: entry.cb?.getState(),
    };
  }

  private scheduleNext(entry: TaskEntry): void {
    // Guard against zombie tasks: if the entry was unregistered while executing,
    // the closure still holds a reference but the map no longer contains it.
    if (!this.tasks.has(entry.config.id)) return;
    if (!this.running || !entry.enabled) return;

    const jitter = entry.config.jitterMs
      ? Math.floor(Math.random() * entry.config.jitterMs)
      : 0;
    const delay = entry.config.intervalMs + jitter;

    entry.timerId = setTimeout(() => {
      entry.timerId = null;
      if (!this.running || !entry.enabled) return;

      // Overlap policy: skip if task still running
      if (entry.state === "RUNNING" && entry.config.skipOnOverlap) {
        this.logger?.info(`Task ${entry.config.id}: skipping (still running)`);
        this.scheduleNext(entry);
        return;
      }

      this.executeTask(entry).then(() => {
        this.scheduleNext(entry);
      });
    }, delay);
  }

  private async executeTask(entry: TaskEntry): Promise<void> {
    const group = entry.config.mutexGroup;
    if (group) {
      // Serialize within mutex group: wait for the previous task in this group
      const prev = this.mutexQueues.get(group) ?? Promise.resolve();
      const current = prev.then(() => this.doExecute(entry));
      this.mutexQueues.set(group, current.catch(() => {}));
      await current;
    } else {
      await this.doExecute(entry);
    }
  }

  private async doExecute(entry: TaskEntry): Promise<void> {
    // Circuit breaker gate: skip if CB is OPEN
    if (entry.cb) {
      const cbState = entry.cb.getState();
      if (cbState === "OPEN") {
        this.logger?.info(
          `Task ${entry.config.id}: circuit breaker OPEN, skipping execution`,
        );
        return;
      }
    }

    const ac = new AbortController();
    entry.abortController = ac;
    entry.state = "RUNNING";
    entry.lastRunAt = this.clock.now();

    const taskPromise = (async () => {
      try {
        await entry.config.fn(ac.signal);
        if (ac.signal.aborted) {
          // Cancellation is user-initiated, not a system failure.
          // Don't count it toward circuit breaker failure threshold.
          entry.state = "FAILED";
          entry.lastError = new Error("Task was cancelled");
          entry.failCount++;
          return;
        }
        entry.state = "COMPLETED";
        entry.runCount++;
        entry.cb?.recordSuccess();
      } catch (err: unknown) {
        const error = err instanceof Error ? err : new Error(String(err));
        entry.state = "FAILED";
        entry.lastError = error;
        entry.failCount++;
        // Only count real failures toward circuit breaker, not cancellations
        if (!ac.signal.aborted) {
          entry.cb?.recordFailure();
        }
        this.logger?.error(`Task ${entry.config.id} failed: ${error.message}`);
        this.onTaskError?.(entry.config.id, error);
      } finally {
        entry.abortController = null;
        entry.runningPromise = null;
      }
    })();

    entry.runningPromise = taskPromise;
    await taskPromise;
  }
}

export function createScheduler(config?: SchedulerConfig): Scheduler {
  return new Scheduler(config);
}
