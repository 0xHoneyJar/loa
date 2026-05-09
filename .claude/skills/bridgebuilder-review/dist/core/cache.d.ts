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
 * Compute a deterministic cache key from the dimensions that affect Pass 1 output.
 *
 * Key = sha256(headSha + ":" + truncationLevel + ":" + selfReview + ":" + sha256(convergenceSystemPrompt))
 *
 * Any change to the diff (headSha), truncation strategy (level), the self-review
 * opt-in state, or the system prompt (hash) produces a different key, invalidating
 * the cache (AC-6 + BB-003-cache).
 *
 * BB-003-cache (PR #797 iter-2): the system-prompt hash alone does NOT change
 * with selfReview — but the USER prompt content (truncated diffs) DOES, because
 * the self-review label admits framework files. Without selfReview in the key,
 * adding or removing the label would serve a cached review computed under the
 * other regime. Adding the boolean to the key segment makes the toggle a
 * cache-distinct dimension.
 */
export declare function computeCacheKey(hasher: IHasher, headSha: string, truncationLevel: number, convergencePromptHash: string, selfReview?: boolean): Promise<string>;
/**
 * Content-hash-based cache for Pass 1 convergence output (AC-1, AC-2, AC-3).
 *
 * In iterative bridge reviews, Pass 1 is near-deterministic for a given diff.
 * When the diff hasn't changed between iterations, caching halves LLM cost.
 *
 * Storage: JSON files in `.run/bridge-cache/{key}.json`.
 * All I/O errors are swallowed — cache is advisory, never required (graceful degradation).
 */
export declare class Pass1Cache {
    private readonly cacheDir;
    private dirCreated;
    constructor(cacheDir: string);
    /**
     * Retrieve a cached entry by key. Returns null on miss or any I/O error.
     */
    get(key: string): Promise<CacheEntry | null>;
    /**
     * Store a cache entry. Creates the cache directory lazily on first write (AC-9).
     * All errors are swallowed — cache is advisory.
     */
    set(key: string, entry: CacheEntry): Promise<void>;
    /**
     * Remove all cached entries (AC-9: cleaned on bridge finalization).
     * All errors are swallowed.
     */
    clear(): Promise<void>;
}
//# sourceMappingURL=cache.d.ts.map