/**
 * Rating system for Bridgebuilder reviews.
 * Captures human feedback on review quality via 1-5 scale.
 * Non-blocking with configurable timeout.
 */
import { appendFile, mkdir } from "node:fs/promises";
import { createInterface } from "node:readline";
const DEFAULT_RATING_CONFIG = {
    enabled: true,
    timeoutSeconds: 60,
    storagePath: "grimoires/loa/ratings/reviews.jsonl",
    retrospectiveCommand: true,
};
/** Rubric dimensions for structured rating (per SKP-006). */
export const RATING_RUBRIC = {
    depth: "Structural depth — did the review include FAANG parallels, metaphors, teachable moments?",
    accuracy: "Finding accuracy — were the issues identified real and correctly classified?",
    actionability: "Actionability — were suggestions specific enough to implement?",
    overall: "Overall quality — how useful was this review?",
};
/**
 * Build the rating prompt text for display to the user.
 */
export function buildRatingPrompt(runId, model, iteration) {
    const lines = [];
    lines.push(`\nRate the review quality (${model}, iteration ${iteration}):`);
    lines.push("");
    lines.push("Scale: 1 (poor) → 5 (excellent)");
    lines.push("");
    for (const [key, desc] of Object.entries(RATING_RUBRIC)) {
        lines.push(`  ${key}: ${desc}`);
    }
    lines.push("");
    lines.push(`Run ID: ${runId}`);
    lines.push("(Press Enter to skip, or enter a number 1-5 for overall score)");
    return lines.join("\n");
}
/**
 * Parse a rating input string (1-5 or empty for skip).
 */
export function parseRatingInput(input) {
    const trimmed = input.trim();
    if (trimmed === "")
        return null;
    const score = parseInt(trimmed, 10);
    if (isNaN(score) || score < 1 || score > 5)
        return null;
    return score;
}
/**
 * Store a rating entry to JSONL file.
 */
export async function storeRating(entry, storagePath) {
    const path = storagePath ?? DEFAULT_RATING_CONFIG.storagePath;
    // Ensure directory exists
    const dir = path.replace(/\/[^/]+$/, "");
    await mkdir(dir, { recursive: true });
    await appendFile(path, JSON.stringify(entry) + "\n");
}
/**
 * Create a rating entry from input.
 */
export function createRatingEntry(runId, iteration, model, score, options) {
    return {
        timestamp: new Date().toISOString(),
        runId,
        iteration,
        model,
        score,
        provider: options?.provider,
        category: options?.category ?? "overall",
        comment: options?.comment,
    };
}
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
export async function readRatingWithTimeout(options) {
    const input = options.input ?? process.stdin;
    const output = options.output ?? process.stderr;
    return new Promise((resolve) => {
        const rl = createInterface({ input, output, terminal: false });
        let settled = false;
        const finish = (result) => {
            if (settled)
                return;
            settled = true;
            clearTimeout(timer);
            try {
                rl.close();
            }
            catch {
                // ignore close errors — best-effort cleanup
            }
            resolve(result);
        };
        const timer = setTimeout(() => finish({ score: null, timedOut: true }), options.timeoutMs);
        rl.once("line", (line) => {
            finish({ score: parseRatingInput(line), timedOut: false });
        });
        rl.once("close", () => {
            // Stream closed before any input — treat as skip
            finish({ score: null, timedOut: false });
        });
    });
}
//# sourceMappingURL=rating.js.map