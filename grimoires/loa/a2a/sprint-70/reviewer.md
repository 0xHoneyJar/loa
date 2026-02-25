# Sprint 70 Implementation Report

**Sprint**: Pass 1 Convergence Cache — Cost Intelligence
**Global ID**: sprint-70 (local sprint-8, cycle-039)
**Status**: IMPLEMENTED

## Summary

Implemented content-hash-based caching for Pass 1 output in iterative bridge reviews. When the diff hasn't changed between bridge iterations (same headSha, truncation level, and convergence prompt), Pass 1 findings are near-deterministic and can be served from cache, skipping the LLM call entirely. This halves LLM cost for unchanged iterations. The cache is opt-in (default: false), advisory (all errors swallowed), and uses filesystem-based JSON storage in `.run/bridge-cache/`.

## Tasks Completed

### Task 8.1: Create `Pass1Cache` class
- **File**: `.claude/skills/bridgebuilder-review/resources/core/cache.ts` (NEW, 103 lines)
- `Pass1Cache` class with `get(key)`, `set(key, entry)`, `clear()` methods (line 46)
- `CacheEntry` interface: `{ findings: { raw: string; parsed: object }; tokens: PassTokenMetrics; timestamp: string; hitCount: number }` (line 11)
- `computeCacheKey(hasher, headSha, truncationLevel, convergencePromptHash)` -> sha256 hex (line 27)
- Storage: JSON files in `.run/bridge-cache/{key}.json`
- Lazy directory creation via `mkdir({ recursive: true })` on first `set()` (line 83)
- All I/O errors caught and swallowed -- cache is advisory, never throws
- Uses `IHasher` port for sha256 computation (dependency injection)

### Task 8.2: Add cache configuration
- **File**: `.claude/skills/bridgebuilder-review/resources/core/types.ts` (line 35)
  - Added `pass1Cache?: { enabled: boolean }` to `BridgebuilderConfig`
- **File**: `.claude/skills/bridgebuilder-review/resources/config.ts`
  - Added `pass1_cache_enabled` to `YamlConfig` interface
  - Added `BRIDGEBUILDER_PASS1_CACHE` to `EnvVars` interface
  - Added `resolvePass1Cache()` helper function for config resolution
  - Added YAML parsing case for `pass1_cache_enabled` key
  - Config precedence: env (`BRIDGEBUILDER_PASS1_CACHE`) > yaml (`pass1_cache_enabled`) > default (not set = disabled)
  - Default: not set (opt-in for safety)

### Task 8.3: Integrate cache into `processItemTwoPass()`
- **File**: `.claude/skills/bridgebuilder-review/resources/core/reviewer.ts`
  - Added `Pass1Cache` and `IHasher` imports and class properties (lines 83-84)
  - Constructor initializes `pass1Cache` when `config.pass1Cache?.enabled && hasher` (line 100)
  - Added hasher as optional constructor parameter (line 97)
  - Cache check before Pass 1 LLM call at line 845:
    - Computes cache key from `sha256(headSha + ":" + truncationLevel + ":" + sha256(convergenceSystemPrompt))`
    - On HIT: logs info, uses cached findings, skips LLM call, sets `pass1CacheHit: true`
    - On MISS: proceeds with LLM call, stores result in cache after successful extraction
  - `pass1CacheHit` passed through to all result paths (success, fallback, error)

### Task 8.4: Add `pass1CacheHit` to `ReviewResult`
- **File**: `.claude/skills/bridgebuilder-review/resources/core/types.ts` (line 84)
  - Added `pass1CacheHit?: boolean` to `ReviewResult`
  - Set to `true` on cache hit, `false` on cache miss, propagated through all two-pass result paths

### Task 8.5: Comprehensive cache tests
- **File**: `.claude/skills/bridgebuilder-review/resources/__tests__/cache.test.ts` (NEW, 492 lines)
- 14 tests across 6 describe blocks:
  1. Core operations (3 tests): cache miss returns null, set/get roundtrip with hitCount increment, clear removes all entries
  2. Cache key computation (4 tests): different headSha produces different key, different truncation produces different key, different prompt hash produces different key, same inputs produce same key
  3. Graceful degradation (2 tests): I/O error on get returns null, unwritable directory swallows error
  4. Lazy directory creation (1 test): directory created on first set()
  5. Pipeline integration -- cache disabled (1 test): LLM always called when cache not configured
  6. Pipeline integration -- cache enabled (3 tests): cache hit skips Pass 1 LLM, cache miss makes 2 LLM calls, cached findings flow correctly to Pass 2

## Test Results

```
tests 433
suites 110
pass 433
fail 0
cancelled 0
skipped 0
```

- **419 existing tests**: All pass with zero modification (AC-10)
- **14 new tests**: All pass (AC-11 -- exceeds minimum of 8)

## Files Changed

| File | Action | Lines |
|------|--------|-------|
| `resources/core/cache.ts` | NEW | 103 |
| `resources/core/types.ts` | MODIFIED | +3 |
| `resources/core/reviewer.ts` | MODIFIED | +70, -20 |
| `resources/config.ts` | MODIFIED | +20 |
| `resources/__tests__/cache.test.ts` | NEW | 492 |

## Acceptance Criteria Status

- [x] AC-1: `Pass1Cache` interface: `get(key)` returns `CacheEntry | null`, `set(key, entry)` returns void -- cache.ts:56,82
- [x] AC-2: Cache key computed from `sha256(headSha + ":" + truncationLevel + ":" + sha256(convergenceSystemPrompt))` -- cache.ts:27-34
- [x] AC-3: `CacheEntry`: `{ findings: { raw, parsed }, tokens: PassTokenMetrics, timestamp, hitCount }` -- cache.ts:11-19
- [x] AC-4: In `processItemTwoPass()`, check cache BEFORE Pass 1 LLM call -- reviewer.ts:845-879
- [x] AC-5: On cache miss, store Pass 1 result after successful extraction -- reviewer.ts:948-958
- [x] AC-6: Cache invalidated when diff changes (headSha), truncation changes, or prompt changes -- verified by tests 3-6
- [x] AC-7: `ReviewResult` includes `pass1CacheHit?: boolean` -- types.ts:84
- [x] AC-8: Cache is opt-in via config (default: not set = disabled) -- types.ts:35, config.ts
- [x] AC-9: Cache directory created lazily on first write, cleaned via `clear()` -- cache.ts:83,95
- [x] AC-10: All 419 existing tests pass -- confirmed (433 total = 419 + 14 new)
- [x] AC-11: 14 new tests (exceeds minimum 8) -- confirmed

## Provenance

| Finding | Source | Status |
|---------|--------|--------|
| Pass 1 caching by content hash | iter-1 speculation-1 | ADDRESSED |
| LLM cost halving for unchanged diffs | iter-1 speculation-1 detail | ADDRESSED |
| Advisory cache pattern (graceful degradation) | defensive design principle | APPLIED |
