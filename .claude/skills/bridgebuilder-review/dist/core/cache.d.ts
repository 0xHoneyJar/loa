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
 * Key = sha256(headSha + ":" + truncationLevel + ":self-review=" + state + ":" + sha256(convergenceSystemPrompt))
 *
 * Any change to the diff (headSha), truncation strategy (level), the self-review
 * tri-state, or the system prompt (hash) produces a different key, invalidating
 * the cache (AC-6 + BB-003-cache).
 *
 * BB-003-cache (iter-2): the system-prompt hash alone does NOT change with
 * selfReview — but the USER prompt content (truncated diffs) DOES.
 *
 * BB-797-002 (iter-5): the previous boolean-keyed signature collided
 * "inactive" (label absent) and "rejected" (label present + .reviewignore
 * unreadable + fail-closed) — both produce different prompts but shared a
 * cache slot. Tri-state ("inactive" | "active" | "rejected") restores
 * input-fingerprint discipline. Backward-compat: the boolean overload is
 * preserved so existing tests keep working; new callers pass the state.
 */
export declare function computeCacheKey(hasher: IHasher, headSha: string, truncationLevel: number, convergencePromptHash: string, selfReviewState?: "inactive" | "active" | "rejected" | boolean): Promise<string>;
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