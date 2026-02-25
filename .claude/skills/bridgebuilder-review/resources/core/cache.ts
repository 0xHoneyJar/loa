import { mkdir, readFile, writeFile, rm } from "node:fs/promises";
import { join } from "node:path";
import type { IHasher } from "../ports/hasher.js";
import type { PassTokenMetrics } from "./types.js";

/**
 * Cached Pass 1 output entry.
 * Stores the raw findings JSON, parsed object, token metrics, and access metadata.
 */
export interface CacheEntry {
  findings: {
    raw: string;
    parsed: object;
  };
  tokens: PassTokenMetrics;
  timestamp: string;
  hitCount: number;
}

/**
 * Compute a deterministic cache key from the three dimensions that affect Pass 1 output.
 * Key = sha256(headSha + ":" + truncationLevel + ":" + sha256(convergenceSystemPrompt))
 *
 * Any change to the diff (headSha), truncation strategy (level), or prompt (hash)
 * produces a different key, invalidating the cache (AC-6).
 */
export async function computeCacheKey(
  hasher: IHasher,
  headSha: string,
  truncationLevel: number,
  convergencePromptHash: string,
): Promise<string> {
  const input = `${headSha}:${truncationLevel}:${convergencePromptHash}`;
  return hasher.sha256(input);
}

/**
 * Content-hash-based cache for Pass 1 convergence output (AC-1, AC-2, AC-3).
 *
 * In iterative bridge reviews, Pass 1 is near-deterministic for a given diff.
 * When the diff hasn't changed between iterations, caching halves LLM cost.
 *
 * Storage: JSON files in `.run/bridge-cache/{key}.json`.
 * All I/O errors are swallowed — cache is advisory, never required (graceful degradation).
 */
export class Pass1Cache {
  private dirCreated = false;

  constructor(private readonly cacheDir: string) {}

  /**
   * Retrieve a cached entry by key. Returns null on miss or any I/O error.
   */
  async get(key: string): Promise<CacheEntry | null> {
    try {
      const filePath = join(this.cacheDir, `${key}.json`);
      const raw = await readFile(filePath, "utf-8");
      const entry: CacheEntry = JSON.parse(raw);

      // Increment hitCount on read (best-effort, swallow write errors)
      entry.hitCount = (entry.hitCount ?? 0) + 1;
      try {
        await writeFile(filePath, JSON.stringify(entry, null, 2), "utf-8");
      } catch {
        // Best-effort hitCount update — swallow
      }

      return entry;
    } catch {
      return null;
    }
  }

  /**
   * Store a cache entry. Creates the cache directory lazily on first write (AC-9).
   * All errors are swallowed — cache is advisory.
   */
  async set(key: string, entry: CacheEntry): Promise<void> {
    try {
      if (!this.dirCreated) {
        await mkdir(this.cacheDir, { recursive: true });
        this.dirCreated = true;
      }
      const filePath = join(this.cacheDir, `${key}.json`);
      await writeFile(filePath, JSON.stringify(entry, null, 2), "utf-8");
    } catch {
      // Advisory cache — swallow all errors
    }
  }

  /**
   * Remove all cached entries (AC-9: cleaned on bridge finalization).
   * All errors are swallowed.
   */
  async clear(): Promise<void> {
    try {
      await rm(this.cacheDir, { recursive: true, force: true });
      this.dirCreated = false;
    } catch {
      // Advisory cache — swallow all errors
    }
  }
}
