/**
 * cycle-129 D-7.7 (DEC-0150): the multi-model run's voice outcome — the completion banner's completed/planned count, the
 * DEGRADED decision, the WARN line naming the voices, and the exit code under `bridgebuilder.exit_on_degraded`.
 *
 * Pure functions so the exit paths are testable without running main.ts (which executes on import).
 */
import { type MultiModelReviewResult } from "./multi-model-pipeline.js";
export { DEGRADED_REASONS, DegradedReason, FETCH_DEGRADED_REASONS, isDegradedReason, primaryDegradedReason, } from "./degraded-reason.js";
export interface VoiceOutcome {
    /** Voices this review was expected to run. */
    planned: number;
    /** Voices whose result completed (a response and no error). */
    completed: number;
    /** The aggregate verdict-quality band (null when no voice carried an envelope). */
    band: "APPROVED" | "DEGRADED" | "FAILED" | null;
    /** Planned voices without a completed result, as `provider/model`. */
    incomplete: string[];
    /** completed < planned, or the band is DEGRADED or FAILED. */
    degraded: boolean;
}
type OutcomeInput = Pick<MultiModelReviewResult, "modelResults" | "voicesPlanned">;
/** The outcome of one item's multi-model review. */
export declare function summarizeVoices(result: OutcomeInput): VoiceOutcome;
/** The run-level totals across every reviewed item (the banner prints these). */
export declare function totalVoices(outcomes: VoiceOutcome[]): {
    completed: number;
    planned: number;
    degraded: boolean;
    incomplete: string[];
};
/** The process exit code for a completed multi-model run: `exitOnDegraded` when DEGRADED, else 0. */
export declare function decideExitCode(degraded: boolean, exitOnDegraded: number): number;
/** The one WARN line a DEGRADED run prints to stderr (callers grep `DEGRADED`; the voices are named). */
export declare function degradedWarnLine(totals: {
    completed: number;
    planned: number;
    incomplete: string[];
}, bands: Array<VoiceOutcome["band"]>, exitCode: number): string;
//# sourceMappingURL=run-outcome.d.ts.map