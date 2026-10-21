/**
 * Progress reporter for multi-model review pipeline.
 * Outputs to stderr with per-phase and per-model activity tracking.
 * Configurable verbosity. No gaps > 30s in verbose mode.
 */
const DEFAULT_HEARTBEAT_MS = 15_000; // 15 seconds
export class ProgressReporter {
    verbose;
    heartbeatMs;
    heartbeatTimer = null;
    currentPhase = "preflight";
    models = new Map();
    startedAt;
    lastReport;
    constructor(config) {
        this.verbose = config.verbose;
        this.heartbeatMs = config.heartbeatIntervalMs ?? DEFAULT_HEARTBEAT_MS;
        this.startedAt = Date.now();
        this.lastReport = Date.now();
    }
    /**
     * Start the progress reporter with heartbeat timer.
     */
    start() {
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
    stop() {
        if (this.heartbeatTimer) {
            clearInterval(this.heartbeatTimer);
            this.heartbeatTimer = null;
        }
    }
    /**
     * Update the current phase.
     */
    setPhase(phase) {
        this.currentPhase = phase;
        this.report(phase, `Phase: ${phase}`);
    }
    /**
     * Register a model for tracking.
     */
    registerModel(provider, model) {
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
    updateModel(provider, model, update) {
        const key = `${provider}/${model}`;
        const current = this.models.get(key);
        if (current) {
            Object.assign(current, update);
            this.models.set(key, current);
        }
        if (this.verbose && update.phase) {
            const details = [];
            if (update.latencyMs)
                details.push(`${update.latencyMs}ms`);
            if (update.inputTokens)
                details.push(`${update.inputTokens} in`);
            if (update.outputTokens)
                details.push(`${update.outputTokens} out`);
            const detailStr = details.length > 0 ? ` (${details.join(", ")})` : "";
            this.report("review", `${key}: ${update.phase}${detailStr}`);
        }
    }
    /**
     * Report scoring progress.
     */
    reportScoring(stats) {
        this.report("scoring", `Consensus: ${stats.total} findings — ${stats.highConsensus} consensus, ${stats.disputed} disputed, ${stats.blocker} blocker`);
    }
    /**
     * Report posting progress.
     */
    reportPosting(model, success) {
        this.report("posting", `${model}: ${success ? "posted" : "failed to post"}`);
    }
    /**
     * Report completion.
     */
    reportComplete(totalMs, modelsCompleted) {
        this.report("complete", `Done in ${Math.round(totalMs / 1000)}s — ${modelsCompleted} model(s) completed`);
    }
    /**
     * Heartbeat — ensures no output gap > 30s in verbose mode.
     */
    heartbeat() {
        const now = Date.now();
        const gapMs = now - this.lastReport;
        // Only emit heartbeat if it's been quiet for a while
        if (gapMs > this.heartbeatMs) {
            const activeModels = [...this.models.values()]
                .filter((m) => m.phase === "streaming")
                .map((m) => `${m.provider}/${m.model}`);
            if (activeModels.length > 0) {
                this.report(this.currentPhase, `Still working... (${activeModels.join(", ")} streaming)`);
            }
            else {
                this.report(this.currentPhase, "Still working...");
            }
        }
    }
    /**
     * Write a progress line to stderr.
     */
    report(phase, message) {
        const elapsed = Math.round((Date.now() - this.startedAt) / 1000);
        const prefix = `[bridgebuilder:${phase}]`;
        const line = `${prefix} [${elapsed}s] ${message}`;
        process.stderr.write(line + "\n");
        this.lastReport = Date.now();
    }
}
//# sourceMappingURL=progress.js.map