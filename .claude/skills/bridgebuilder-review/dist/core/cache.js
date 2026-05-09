import { mkdir, readFile, writeFile, rm } from "node:fs/promises";
import { join } from "node:path";
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
export async function computeCacheKey(hasher, headSha, truncationLevel, convergencePromptHash, selfReview = false) {
    const input = `${headSha}:${truncationLevel}:self-review=${selfReview}:${convergencePromptHash}`;
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
    cacheDir;
    dirCreated = false;
    constructor(cacheDir) {
        this.cacheDir = cacheDir;
    }
    /**
     * Retrieve a cached entry by key. Returns null on miss or any I/O error.
     */
    async get(key) {
        try {
            const filePath = join(this.cacheDir, `${key}.json`);
            const raw = await readFile(filePath, "utf-8");
            const entry = JSON.parse(raw);
            // Increment hitCount on read (best-effort, swallow write errors)
            entry.hitCount = (entry.hitCount ?? 0) + 1;
            try {
                await writeFile(filePath, JSON.stringify(entry, null, 2), "utf-8");
            }
            catch {
                // Best-effort hitCount update — swallow
            }
            return entry;
        }
        catch {
            return null;
        }
    }
    /**
     * Store a cache entry. Creates the cache directory lazily on first write (AC-9).
     * All errors are swallowed — cache is advisory.
     */
    async set(key, entry) {
        try {
            if (!this.dirCreated) {
                await mkdir(this.cacheDir, { recursive: true });
                this.dirCreated = true;
            }
            const filePath = join(this.cacheDir, `${key}.json`);
            await writeFile(filePath, JSON.stringify(entry, null, 2), "utf-8");
        }
        catch {
            // Advisory cache — swallow all errors
        }
    }
    /**
     * Remove all cached entries (AC-9: cleaned on bridge finalization).
     * All errors are swallowed.
     */
    async clear() {
        try {
            await rm(this.cacheDir, { recursive: true, force: true });
            this.dirCreated = false;
        }
        catch {
            // Advisory cache — swallow all errors
        }
    }
}
//# sourceMappingURL=cache.js.map