import type { Readable, Writable } from "node:stream";
export interface RatingEntry {
    timestamp: string;
    runId: string;
    iteration: number;
    model: string;
    provider?: string;
    score: number;
    category?: string;
    comment?: string;
}
export interface RatingConfig {
    enabled: boolean;
    timeoutSeconds: number;
    storagePath: string;
    retrospectiveCommand: boolean;
}
/** Rubric dimensions for structured rating (per SKP-006). */
export declare const RATING_RUBRIC: {
    readonly depth: "Structural depth — did the review include FAANG parallels, metaphors, teachable moments?";
    readonly accuracy: "Finding accuracy — were the issues identified real and correctly classified?";
    readonly actionability: "Actionability — were suggestions specific enough to implement?";
    readonly overall: "Overall quality — how useful was this review?";
};
export type RatingDimension = keyof typeof RATING_RUBRIC;
/**
 * Build the rating prompt text for display to the user.
 */
export declare function buildRatingPrompt(runId: string, model: string, iteration: number): string;
/**
 * Parse a rating input string (1-5 or empty for skip).
 */
export declare function parseRatingInput(input: string): number | null;
/**
 * Store a rating entry to JSONL file.
 */
export declare function storeRating(entry: RatingEntry, storagePath?: string): Promise<void>;
/**
 * Create a rating entry from input.
 */
export declare function createRatingEntry(runId: string, iteration: number, model: string, score: number, options?: {
    provider?: string;
    category?: RatingDimension;
    comment?: string;
}): RatingEntry;
/**
 * Non-blocking stdin rating capture with timeout.
 *
 * Addresses bug-20260413-i464-9d4f51 / Issue #464 A1: the multi-model
 * pipeline displayed the rating prompt but never read stdin, leaving
 * FR-5 unimplemented.
 *
 * Resolves when either:
 *   - User enters a value + Enter (score parsed via parseRatingInput)
 *   - Timeout elapses ({ score: null, timedOut: true })
 *
 * Never throws. Never blocks beyond `timeoutMs`. Safe for autonomous mode.
 *
 * @param options.input - Readable stream (default: process.stdin)
 * @param options.output - Writable stream for readline (default: process.stderr)
 * @param options.timeoutMs - Timeout in milliseconds
 */
export declare function readRatingWithTimeout(options: {
    input?: Readable;
    output?: Writable;
    timeoutMs: number;
}): Promise<{
    score: number | null;
    timedOut: boolean;
}>;
//# sourceMappingURL=rating.d.ts.map