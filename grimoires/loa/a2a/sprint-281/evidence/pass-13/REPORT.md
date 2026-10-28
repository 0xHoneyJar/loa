# ESO pass 13 - workflow-state.sh --json / cache-manager.sh get

Matrix: Impact 2 (-8 ms of 118), Confidence 5, Effort 1 -> 10 (>=2.0).

## Hotspot
workflow-state.sh --json 118.5 +-4.8 ms. In-process the script is ~25 ms; the two children are the cost:
generate-key ~13.5 ms, `cache-manager.sh get` ~65 ms (hit). Inside get (366 trace lines): 4 yq spawns for
config (get_config did `yq .k|type` then `yq .k`, once for is_cache_enabled and once for ttl_days) ~25 ms (~38% of get),
~9 jq spawns over the entry ~27 ms, sha256 + stats. get is NOT read-only on hit (writes hit_count/last_hit to
index.json) - that is stats semantics, left alone.
Not pursued (one lever): sourcing cache-manager into workflow-state (main runs at source time, exit/set -e/global CACHE_DIR clobber risk);
jq-spawn collapse (needs -r/null edge-case proofs); path-lib yq reads (shared).

## Lever
cache-manager.sh get_config(): one `yq -r .key` instead of `.key | type` probe + value read.
Proof of equivalence: yq prints "!!null" for an absent key, never the bare word "null", so the old probe only ever
gated on yq failing (file unreadable/invalid -> "null" -> default). New: yq failure -> default; "null" output -> default;
else echo value. Cases: absent/null/"null"/""/false/0/map/invalid YAML all identical (cfg1-7 tests).
Only theoretical divergence: yq succeeding on the probe then failing on the value read on the same file.

## Numbers (hyperfine -N, warmup 3)
- workflow-state.sh --json: 118.5 +-4.8 -> 109.8 +-5.6 ms (-7%)
- cache-manager get (hit, scratch cache copy): 64.8 +-4.8 -> 57.4 +-5.2 ms (-11%)
- loa-status.sh after: 819 +-13 ms (5 runs; dominated by other work, expect ~-9 ms, not separately baselined)

## Isomorphism
- Ordering/tie-break/FP/RNG: unchanged / N/A. Cache key, location, index schema, entry files: untouched (key code not edited).
- Trust boundary: no input handling touched. Error/degraded paths verified below.
- Old (git HEAD copy) vs new mirrors (/tmp/eso13-{old,new}, scratch .run AND scratch .claude/cache): parity.sh, 181 checks:
  workflow-state --json / human x {warm, corrupt index, truncated entry, bad hash, cold, read-only cache dir, missing result},
  --no-cache, --bogus, --help, PATH without yq; cache-manager get/get --json same states, missing key, stats, set,
  cleanup, LOA_CACHE_ENABLED=false, TTL=0, no yq; 7 config-yaml variants. stdout, rc, resulting cache/.run tree
  (index.json time fields normalised: last_hit/created_at/cached_mtime) all identical. stderr identical after normalising
  mirror dir name and the line number in a bash error message (line shifted by -2). Residual tree diff: .run/audit.jsonl
  is the live hook log appended during the run (not the script under test).
- Note: in the mirror, workflow-state hits the "grimoire escapes workspace" symlink warning (same in old/new); ws-level hit
  path is covered by cache-manager get cases instead.
- bats: cache-manager, agent-ergonomics-workflow-state, loa-status-providers, loa-status-stale-worktree: 56/56 ok.

## Files
.claude/scripts/cache-manager.sh get_config (~line 160-175).

## Checked, found fine
- generate-key is a single sha256 over a short string; cost is bash startup + compat-lib sourcing, no hot loop.
- get on hit writes the index via jq tmp+mv: required stats semantics, not incidental.
- check_dependencies uses cached _COMPAT_SHA256_CMD, no extra spawns.
## Not fixed
Remaining get cost: ~9 jq spawns + 2 yq (enabled, ttl) - candidate for a later pass (single jq extracting all entry fields, ttl+enabled in one yq).
workflow-state main loop ~25 ms in-process, path-lib yq reads untouched.
