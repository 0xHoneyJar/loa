import type { LoreEntry } from "./template.js";
import type { ILogger } from "../ports/logger.js";
/** Default location of the lore patterns file (relative to repo root). */
export declare const DEFAULT_LORE_PATH = "grimoires/loa/lore/patterns.yaml";
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
export declare function loadLoreEntries(path?: string, logger?: ILogger): Promise<LoreEntry[]>;
//# sourceMappingURL=lore-loader.d.ts.map