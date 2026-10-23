/**
 * Progress reporter for multi-model review pipeline.
 * Outputs to stderr with per-phase and per-model activity tracking.
 * Configurable verbosity. No gaps > 30s in verbose mode.
 */

export interface ProgressConfig {
  verbose: boolean;
  heartbeatIntervalMs?: number;
}

export type ProgressPhase =
  | "preflight"
  | "config"
  | "review"
  | "scoring"
  | "posting"
  | "complete";

export interface ModelActivity {
  provider: string;
  model: string;
  phase: "pending" | "streaming" | "complete" | "error";
  startedAt?: number;
  completedAt?: number;
  inputTokens?: number;
  outputTokens?: number;
  latencyMs?: number;
}

const DEFAULT_HEARTBEAT_MS = 15_000; // 15 seconds

export class ProgressReporter {
  private readonly verbose: boolean;
  private readonly heartbeatMs: number;
  private heartbeatTimer: ReturnType<typeof setInterval> | null = null;
  private currentPhase: ProgressPhase = "preflight";
  private models: Map<string, ModelActivity> = new Map();
  private startedAt: number;
  private lastReport: number;

  constructor(config: ProgressConfig) {
    this.verbose = config.verbose;
    this.heartbeatMs = config.heartbeatIntervalMs ?? DEFAULT_HEARTBEAT_MS;
    this.startedAt = Date.now();
    this.lastReport = Date.now();
  }

  /**
   * Start the progress reporter with heartbeat timer.
   */
  start(): void {
    this.startedAt = Date.now();
    this.report("preflight", "Starting multi-model review pipeline...");

    if (this.verbose) {
      this.heartbeatTimer = setInterval(() => {
        this.heartbeat();
      }, this.heartbeatMs);
    }
  }

  /**
   * Stop the progress reporter and clear heartbeat timer.
   */
  stop(): void {
    if (this.heartbeatTimer) {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = null;
    }
  }

  /**
   * Update the current phase.
   */
  setPhase(phase: ProgressPhase): void {
    this.currentPhase = phase;
    this.report(phase, `Phase: ${phase}`);
  }

  /**
   * Register a model for tracking.
   */
  registerModel(provider: string, model: string): void {
    const key = `${provider}/${model}`;
    this.models.set(key, {
      provider,
      model,
      phase: "pending",
    });
    if (this.verbose) {
      this.report("config", `Registered model: ${key}`);
    }
  }

  /**
   * Update model activity status.
   */
  updateModel(
    provider: string,
    model: string,
    update: Partial<ModelActivity>,
  ): void {
    const key = `${provider}/${model}`;
    const current = this.models.get(key);
    if (current) {
      Object.assign(current, update);
      this.models.set(key, current);
    }

    if (this.verbose && update.phase) {
      const details: string[] = [];
      if (update.latencyMs) details.push(`${update.latencyMs}ms`);
      if (update.inputTokens) details.push(`${update.inputTokens} in`);
      if (update.outputTokens) details.push(`${update.outputTokens} out`);
      const detailStr = details.length > 0 ? ` (${details.join(", ")})` : "";
      this.report("review", `${key}: ${update.phase}${detailStr}`);
    }
  }

  /**
   * Report scoring progress.
   */
  reportScoring(stats: {
    total: number;
    highConsensus: number;
    disputed: number;
    blocker: number;
  }): void {
    this.report(
      "scoring",
      `Consensus: ${stats.total} findings — ${stats.highConsensus} consensus, ${stats.disputed} disputed, ${stats.blocker} blocker`,
    );
  }

  /**
   * Report posting progress.
   */
  reportPosting(model: string, success: boolean): void {
    this.report(
      "posting",
      `${model}: ${success ? "posted" : "failed to post"}`,
    );
  }

  /**
   * Report completion.
   */
  reportComplete(totalMs: number, modelsCompleted: number): void {
    this.report(
      "complete",
      `Done in ${Math.round(totalMs / 1000)}s — ${modelsCompleted} model(s) completed`,
    );
  }

  /**
   * Heartbeat — ensures no output gap > 30s in verbose mode.
   */
  private heartbeat(): void {
    const now = Date.now();
    const gapMs = now - this.lastReport;

    // Only emit heartbeat if it's been quiet for a while
    if (gapMs > this.heartbeatMs) {
      const activeModels = [...this.models.values()]
        .filter((m) => m.phase === "streaming")
        .map((m) => `${m.provider}/${m.model}`);

      if (activeModels.length > 0) {
        this.report(
          this.currentPhase,
          `Still working... (${activeModels.join(", ")} streaming)`,
        );
      } else {
        this.report(this.currentPhase, "Still working...");
      }
    }
  }

  /**
   * Write a progress line to stderr.
   */
  private report(phase: ProgressPhase, message: string): void {
    const elapsed = Math.round((Date.now() - this.startedAt) / 1000);
    const prefix = `[bridgebuilder:${phase}]`;
    const line = `${prefix} [${elapsed}s] ${message}`;
    process.stderr.write(line + "\n");
    this.lastReport = Date.now();
  }
}
