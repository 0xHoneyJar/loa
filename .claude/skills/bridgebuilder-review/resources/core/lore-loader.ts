/**
 * Lore loader — reads `grimoires/loa/lore/patterns.yaml` and returns LoreEntry[].
 *
 * Closes Issue #464 A5: `template.buildEnrichedSystemPrompt()` accepts
 * `loreEntries` but the multi-model path never loaded them, so
 * `lore_active_weaving: true` was effectively a no-op.
 *
 * Implementation note: shells out to `yq` instead of adding a YAML parser
 * dependency. `yq` is a hard prerequisite of the Loa framework and is
 * already used throughout `.claude/scripts/`. This keeps the bridgebuilder
 * skill's dependency surface minimal (currently only `zod`).
 */
import { execFile } from "node:child_process";
import { existsSync, statSync } from "node:fs";
import { promisify } from "node:util";

import type { LoreEntry } from "./template.js";
import type { ILogger } from "../ports/logger.js";

const execFileAsync = promisify(execFile);

/** Default location of the lore patterns file (relative to repo root). */
export const DEFAULT_LORE_PATH = "grimoires/loa/lore/patterns.yaml";

/** Soft timeout for the yq invocation. */
const YQ_TIMEOUT_MS = 5000;

interface RawLoreEntry {
  id?: unknown;
  term?: unknown;
  short?: unknown;
  context?: unknown;
  source?: unknown;
  tags?: unknown;
}

/**
 * Validate that a parsed object matches the LoreEntry contract.
 * Returns `null` for invalid entries (caller logs and skips).
 */
function coerceLoreEntry(raw: unknown, index: number, logger?: ILogger): LoreEntry | null {
  if (!raw || typeof raw !== "object") {
    logger?.warn(`[lore-loader] Entry ${index} is not an object — skipping`);
    return null;
  }
  const r = raw as RawLoreEntry;
  if (typeof r.id !== "string" || typeof r.term !== "string" ||
      typeof r.short !== "string" || typeof r.context !== "string") {
    logger?.warn(
      `[lore-loader] Entry ${index} missing required field(s) (id/term/short/context) — skipping`,
    );
    return null;
  }
  // source can be a string OR an object with bridge_iteration/cycle/date — flatten to string
  let source: string | undefined;
  if (typeof r.source === "string") {
    source = r.source;
  } else if (r.source && typeof r.source === "object") {
    const s = r.source as Record<string, unknown>;
    const bits: string[] = [];
    if (typeof s.cycle === "string") bits.push(s.cycle);
    if (typeof s.bridge_iteration === "string") bits.push(s.bridge_iteration);
    if (typeof s.date === "string") bits.push(s.date);
    source = bits.length > 0 ? bits.join(", ") : undefined;
  }
  // tags must be array of strings
  let tags: string[] | undefined;
  if (Array.isArray(r.tags)) {
    tags = r.tags.filter((t): t is string => typeof t === "string");
  }
  return {
    id: r.id,
    term: r.term,
    short: r.short,
    context: r.context,
    source,
    tags,
  };
}

/**
 * Load lore entries from a YAML file. Returns an empty array (with a
 * warning log) if the file is missing or contains no usable entries.
 *
 * Throws only on truly unexpected conditions (yq invocation failure with
 * a non-empty file present, JSON parse failure on yq's output). Callers
 * should catch and degrade gracefully rather than failing the review.
 *
 * @param path - Path to the lore YAML file (default: DEFAULT_LORE_PATH)
 * @param logger - Optional logger for warnings
 * @returns Validated lore entries
 */
export async function loadLoreEntries(
  path: string = DEFAULT_LORE_PATH,
  logger?: ILogger,
): Promise<LoreEntry[]> {
  if (!existsSync(path)) {
    logger?.warn(`[lore-loader] Lore file not found at ${path} — returning empty entries`);
    return [];
  }

  // Empty file → empty entries (yq would return "null" which parses fine,
  // but we short-circuit to avoid the subprocess overhead).
  let stat;
  try {
    stat = statSync(path);
  } catch (err) {
    logger?.warn(`[lore-loader] Could not stat ${path} — returning empty entries`, {
      error: err instanceof Error ? err.message : String(err),
    });
    return [];
  }
  if (stat.size === 0) {
    logger?.warn(`[lore-loader] Lore file ${path} is empty — returning empty entries`);
    return [];
  }

  // Convert YAML → JSON via yq, then parse. `yq -o json eval '.' file`
  // emits compact JSON.
  let stdout: string;
  try {
    const result = await execFileAsync(
      "yq",
      ["-o", "json", "eval", ".", path],
      { timeout: YQ_TIMEOUT_MS },
    );
    stdout = result.stdout;
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    throw new Error(
      `[lore-loader] Failed to convert YAML at ${path}: ${message}. ` +
      `Ensure 'yq' is installed and the file is valid YAML.`,
    );
  }

  if (!stdout || stdout.trim() === "" || stdout.trim() === "null") {
    logger?.warn(`[lore-loader] Lore file ${path} parsed to null — returning empty entries`);
    return [];
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(stdout);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    throw new Error(
      `[lore-loader] yq produced invalid JSON for ${path}: ${message}`,
    );
  }

  if (!Array.isArray(parsed)) {
    logger?.warn(
      `[lore-loader] Expected top-level YAML array at ${path}, got ${typeof parsed} — returning empty entries`,
    );
    return [];
  }

  const entries: LoreEntry[] = [];
  for (let i = 0; i < parsed.length; i++) {
    const entry = coerceLoreEntry(parsed[i], i, logger);
    if (entry) entries.push(entry);
  }
  return entries;
}
