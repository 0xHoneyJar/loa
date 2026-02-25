import { readFile, writeFile, rename } from "node:fs/promises";
import type { EcosystemPattern, EcosystemContext } from "./types.js";
import type { ValidatedFinding } from "./schemas.js";
import type { ILogger } from "../ports/logger.js";

/** Maximum patterns retained per repository (AC-4). */
const PER_REPO_CAP = 20;

/** Maximum length for a connection string (first sentence). */
const MAX_CONNECTION_LENGTH = 200;

/**
 * Extract the first sentence from a description string.
 * Splits on period (.) and takes the first segment, bounded at MAX_CONNECTION_LENGTH characters.
 * If no period is found, takes the entire string up to the max length.
 */
export function firstSentence(text: string): string {
  if (!text) return "";

  // Split on period followed by whitespace or end of string
  const dotIndex = text.indexOf(".");
  const sentence = dotIndex >= 0 ? text.slice(0, dotIndex + 1) : text;

  if (sentence.length <= MAX_CONNECTION_LENGTH) {
    return sentence;
  }
  return sentence.slice(0, MAX_CONNECTION_LENGTH);
}

/**
 * Extract ecosystem patterns from bridge findings (AC-1, AC-2).
 *
 * Qualifying findings:
 * - PRAISE with confidence > 0.8
 * - All SPECULATION findings (any confidence)
 *
 * Each extracted pattern includes repo, pr, pattern (title), connection (first sentence
 * of description), extractedFrom (finding id), and confidence.
 */
export function extractEcosystemPatterns(
  findings: ValidatedFinding[],
  repo: string,
  prNumber: number,
): EcosystemPattern[] {
  const patterns: EcosystemPattern[] = [];

  for (const finding of findings) {
    const severity = (finding.severity ?? "").toUpperCase();

    const isPraiseHighConfidence =
      severity === "PRAISE" &&
      typeof finding.confidence === "number" &&
      finding.confidence > 0.8;

    const isSpeculation = severity === "SPECULATION";

    if (!isPraiseHighConfidence && !isSpeculation) {
      continue;
    }

    // Extract title and description — passthrough fields from zod schema
    const title = typeof (finding as Record<string, unknown>).title === "string"
      ? (finding as Record<string, unknown>).title as string
      : finding.id;
    const description = typeof (finding as Record<string, unknown>).description === "string"
      ? (finding as Record<string, unknown>).description as string
      : "";

    patterns.push({
      repo,
      pr: prNumber,
      pattern: title,
      connection: firstSentence(description),
      extractedFrom: finding.id,
      confidence: finding.confidence,
    });
  }

  return patterns;
}

/**
 * Update the ecosystem context file with new patterns (AC-3, AC-4).
 *
 * - Reads existing file (or creates empty context if missing)
 * - Deduplicates: skips patterns where repo + pattern already exists
 * - Per-repo cap: if a repo exceeds PER_REPO_CAP patterns after merge, evicts oldest (by insertion order)
 * - Writes atomically: writes to temp file then renames
 * - Updates lastUpdated to ISO timestamp
 * - All I/O errors are handled gracefully (log warning, don't throw)
 */
export async function updateEcosystemContext(
  contextPath: string,
  newPatterns: EcosystemPattern[],
  logger?: ILogger,
): Promise<void> {
  try {
    // Read existing context or create empty
    let context: EcosystemContext;
    try {
      const raw = await readFile(contextPath, "utf-8");
      context = JSON.parse(raw) as EcosystemContext;
      if (!Array.isArray(context.patterns)) {
        context = { patterns: [], lastUpdated: "" };
      }
    } catch {
      // File missing or unreadable — create empty context
      context = { patterns: [], lastUpdated: "" };
    }

    // Build a set of existing repo+pattern keys for deduplication
    const existingKeys = new Set(
      context.patterns.map((p) => `${p.repo}::${p.pattern}`),
    );

    // Append only new unique patterns
    for (const pattern of newPatterns) {
      const key = `${pattern.repo}::${pattern.pattern}`;
      if (!existingKeys.has(key)) {
        context.patterns.push({
          repo: pattern.repo,
          pr: pattern.pr,
          pattern: pattern.pattern,
          connection: pattern.connection,
        });
        existingKeys.add(key);
      }
    }

    // Per-repo cap: if any repo exceeds PER_REPO_CAP, evict oldest (by insertion order)
    const repoGroups = new Map<string, number[]>();
    for (let i = 0; i < context.patterns.length; i++) {
      const repo = context.patterns[i].repo;
      if (!repoGroups.has(repo)) {
        repoGroups.set(repo, []);
      }
      repoGroups.get(repo)!.push(i);
    }

    const indicesToRemove = new Set<number>();
    for (const [, indices] of repoGroups) {
      if (indices.length > PER_REPO_CAP) {
        // Evict oldest entries (earliest indices) to get down to cap
        const evictCount = indices.length - PER_REPO_CAP;
        for (let i = 0; i < evictCount; i++) {
          indicesToRemove.add(indices[i]);
        }
      }
    }

    if (indicesToRemove.size > 0) {
      context.patterns = context.patterns.filter(
        (_, idx) => !indicesToRemove.has(idx),
      );
    }

    // Update timestamp
    context.lastUpdated = new Date().toISOString();

    // Atomic write: temp file then rename
    const tmpPath = `${contextPath}.tmp`;
    await writeFile(tmpPath, JSON.stringify(context, null, 2), "utf-8");
    await rename(tmpPath, contextPath);
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    if (logger) {
      logger.warn("Failed to update ecosystem context", {
        contextPath,
        error: message,
      });
    }
    // Graceful degradation: don't throw
  }
}
