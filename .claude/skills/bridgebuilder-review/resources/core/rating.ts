/**
 * Rating system for Bridgebuilder reviews.
 * Captures human feedback on review quality via 1-5 scale.
 * Non-blocking with configurable timeout.
 */
import { appendFile, mkdir } from "node:fs/promises";

export interface RatingEntry {
  timestamp: string;
  runId: string;
  iteration: number;
  model: string;
  provider?: string;
  score: number;          // 1-5 scale
  category?: string;      // "depth" | "accuracy" | "actionability" | "overall"
  comment?: string;
}

export interface RatingConfig {
  enabled: boolean;
  timeoutSeconds: number;
  storagePath: string;
  retrospectiveCommand: boolean;
}

const DEFAULT_RATING_CONFIG: RatingConfig = {
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
} as const;

export type RatingDimension = keyof typeof RATING_RUBRIC;

/**
 * Build the rating prompt text for display to the user.
 */
export function buildRatingPrompt(
  runId: string,
  model: string,
  iteration: number,
): string {
  const lines: string[] = [];
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
export function parseRatingInput(input: string): number | null {
  const trimmed = input.trim();
  if (trimmed === "") return null;

  const score = parseInt(trimmed, 10);
  if (isNaN(score) || score < 1 || score > 5) return null;
  return score;
}

/**
 * Store a rating entry to JSONL file.
 */
export async function storeRating(
  entry: RatingEntry,
  storagePath?: string,
): Promise<void> {
  const path = storagePath ?? DEFAULT_RATING_CONFIG.storagePath;

  // Ensure directory exists
  const dir = path.replace(/\/[^/]+$/, "");
  await mkdir(dir, { recursive: true });

  await appendFile(path, JSON.stringify(entry) + "\n");
}

/**
 * Create a rating entry from input.
 */
export function createRatingEntry(
  runId: string,
  iteration: number,
  model: string,
  score: number,
  options?: {
    provider?: string;
    category?: RatingDimension;
    comment?: string;
  },
): RatingEntry {
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
