/**
 * cycle-129 D-7.7 (DEC-0150): the multi-model run's voice outcome — the completion banner's completed/planned count, the
 * DEGRADED decision, the WARN line naming the voices, and the exit code under `bridgebuilder.exit_on_degraded`.
 *
 * Pure functions so the exit paths are testable without running main.ts (which executes on import).
 */
import { computeVerdictBand, type MultiModelReviewResult } from "./multi-model-pipeline.js";

// cycle-133 C-1/C-2: the degraded_reason enumeration lives in a dependency-free module (review-verdict.ts and the
// pipeline import it without an import cycle through this file) and is exported from here as the SDD names it.
export {
  DEGRADED_REASONS, DegradedReason, FETCH_DEGRADED_REASONS, isDegradedReason, primaryDegradedReason,
} from "./degraded-reason.js";

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
export function summarizeVoices(result: OutcomeInput): VoiceOutcome {
  const completedLabels = result.modelResults
    .filter((r) => r.response !== undefined && r.error === undefined)
    .map((r) => `${r.provider}/${r.model}`);
  // (an older pipeline result without voicesPlanned: every attempted voice was planned)
  const plannedLabels = result.voicesPlanned ?? result.modelResults.map((r) => `${r.provider}/${r.model}`);
  const remaining = [...completedLabels];
  const incomplete: string[] = [];
  for (const label of plannedLabels) {
    const i = remaining.indexOf(label);
    if (i >= 0) remaining.splice(i, 1);
    else incomplete.push(label);
  }
  const band = computeVerdictBand(result.modelResults.map((r) => ({ verdictQuality: r.response?.verdictQuality })));
  const completed = completedLabels.length;
  const planned = plannedLabels.length;
  return {
    planned,
    completed,
    band,
    incomplete,
    degraded: completed < planned || band === "DEGRADED" || band === "FAILED",
  };
}

/** The run-level totals across every reviewed item (the banner prints these). */
export function totalVoices(outcomes: VoiceOutcome[]): { completed: number; planned: number; degraded: boolean; incomplete: string[] } {
  const incomplete: string[] = [];
  for (const o of outcomes) for (const v of o.incomplete) if (!incomplete.includes(v)) incomplete.push(v);
  return {
    completed: outcomes.reduce((n, o) => n + o.completed, 0),
    planned: outcomes.reduce((n, o) => n + o.planned, 0),
    degraded: outcomes.some((o) => o.degraded),
    incomplete,
  };
}

/** The process exit code for a completed multi-model run: `exitOnDegraded` when DEGRADED, else 0. */
export function decideExitCode(degraded: boolean, exitOnDegraded: number): number {
  return degraded ? exitOnDegraded : 0;
}

/** The one WARN line a DEGRADED run prints to stderr (callers grep `DEGRADED`; the voices are named). */
export function degradedWarnLine(
  totals: { completed: number; planned: number; incomplete: string[] },
  bands: Array<VoiceOutcome["band"]>,
  exitCode: number,
): string {
  const worst = bands.includes("FAILED") ? "FAILED" : bands.includes("DEGRADED") ? "DEGRADED" : null;
  const voices = totals.incomplete.length > 0 ? `; incomplete voices: ${totals.incomplete.join(", ")}` : "";
  const bandNote = worst !== null ? `; verdict quality: ${worst}` : "";
  return `[bridgebuilder] WARN: DEGRADED — ${totals.completed}/${totals.planned} voices completed${voices}${bandNote} ` +
    `(exit ${exitCode}; bridgebuilder.exit_on_degraded)`;
}
