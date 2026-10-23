/**
 * Progress reporter for multi-model review pipeline.
 * Outputs to stderr with per-phase and per-model activity tracking.
 * Configurable verbosity. No gaps > 30s in verbose mode.
 */
export interface ProgressConfig {
    verbose: boolean;
    heartbeatIntervalMs?: number;
}
export type ProgressPhase = "preflight" | "config" | "review" | "scoring" | "posting" | "complete";
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
export declare class ProgressReporter {
    private readonly verbose;
    private readonly heartbeatMs;
    private heartbeatTimer;
    private currentPhase;
    private models;
    private startedAt;
    private lastReport;
    constructor(config: ProgressConfig);
    /**
     * Start the progress reporter with heartbeat timer.
     */
    start(): void;
    /**
     * Stop the progress reporter and clear heartbeat timer.
     */
    stop(): void;
    /**
     * Update the current phase.
     */
    setPhase(phase: ProgressPhase): void;
    /**
     * Register a model for tracking.
     */
    registerModel(provider: string, model: string): void;
    /**
     * Update model activity status.
     */
    updateModel(provider: string, model: string, update: Partial<ModelActivity>): void;
    /**
     * Report scoring progress.
     */
    reportScoring(stats: {
        total: number;
        highConsensus: number;
        disputed: number;
        blocker: number;
    }): void;
    /**
     * Report posting progress.
     */
    reportPosting(model: string, success: boolean): void;
    /**
     * Report completion.
     */
    reportComplete(totalMs: number, modelsCompleted: number): void;
    /**
     * Heartbeat — ensures no output gap > 30s in verbose mode.
     */
    private heartbeat;
    /**
     * Write a progress line to stderr.
     */
    private report;
}
//# sourceMappingURL=progress.d.ts.map