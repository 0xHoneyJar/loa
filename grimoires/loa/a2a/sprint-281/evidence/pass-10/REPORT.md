# ESO pass 10 — notes-size-guard.sh: fuse `jq -e .` + target read into one jq

## Opportunity matrix
| Lever | Impact | Confidence | Effort | Score |
|---|---|---|---|---|
| notes-size-guard: one jq for validate+extract (saves 1 of 2 jq spawns on every non-NOTES edit) | 3 | 5 | 2 | 7.5 |
Next lever (not done): zone-write-guard (13 ms, already cached yq) and notes-size-guard's remaining 2 realpath + `$(cd; pwd)` subshell spawns; for the NOTES.md path also tool/content jq calls could fold into the first jq.

## Hotspot evidence
Profile (bash -x, non-NOTES Write, 13 ms total): bash startup + 2x `cd;pwd` subshells (~3 ms), `cat` 1.8 ms, `jq -e .` 2.6 ms (~20%), `jq -r target` 2.6 ms (~20%), 2x realpath ~1 ms each. Two jq spawns over the same payload = ~40% of wall time; one is redundant.
Zone-write-guard: 10.2 ms, 12 ms baseline; its cache is already hit, nothing cheap left.

## Before / after (hyperfine -N -i, warmup 3, 30 runs, --input)
| payload | old | new |
|---|---|---|
| live write.json (NOTES.md, tiny) | 18.2 ± 1.3 ms | 15.8 ± 0.6 ms |
| Write to src/a.ts | 11.9 ± 1.3 | 9.7 ± 0.8 |
| 300 KB content to src/a.ts | 28.1 ± 1.8 | 18.1 ± 0.9 (one parse instead of two) |
Through hook-guard.sh: 21.7 ± 4.8 -> 19.2 ± 0.7 ms.
Six-hook Write chain via hook-guard (after): team-role-guard-write 3.9, spiral-dispatch 3.8, zone-write 13.0, implement-gate 23.6 (live NOTES payload hits its slow path), notes-size 19.8, adversarial-review 4.2 = 68.3 ms; before ~ 70.8 ms (notes-size -2.5 ms).

## Change
.claude/hooks/safety/notes-size-guard.sh (~lines 36-43): removed `jq -e . >/dev/null` gate and the separate target `jq -r`; replaced with one `jq -rn` using `reduce inputs` that reproduces the old semantics exactly: unparseable input -> rc!=0 -> exit 0; final document null/false -> no output -> exit 0; runtime error on a non-final document skipped (jq continues), on the final document yields nothing; multi-document streams emit one target line per document as before. Threshold (BLOCK_BYTES=204800, `size+delta >= BLOCK_BYTES`, delta>0), notes-guard.sh delegation, messages and fail-open behaviour untouched.

## Isomorphism proof
- Ordering preserved: yes (per-document outputs emitted in input order)    - Tie-breaking unchanged: yes (N/A)
- Floating-point: N/A    - RNG / hash seeds: N/A
- Trust-boundary sanitisation unchanged: yes — hook still only reads file_path/notebook_path and compares realpaths; no output text changed.
- Error/degraded paths (empty stdin, whitespace, malformed, null/false/array/string/number payloads, truncated multi-doc): exit codes and stderr identical, verified by matrix.
- Golden outputs: 58-case old-vs-new matrix (rc+stdout+stderr, mirrors /tmp/eso10-old and /tmp/eso10-new, script ~/.cache/loa/eso-loop/pass-10/matrix.py, golden-notes.json): 0 differences. An earlier simpler draft (`[., inputs]`) DID differ on 2 multi-doc cases ('[1]' or 'false' as first document) and was replaced by the reduce form. Cases include Write under/at/over 204800 (204799 allowed, 204800 and 204801 blocked rc 2), multibyte at threshold, shrink, Edit/MultiEdit grow/shrink/replace_all, relative and `..` paths, other grimoire files, .claude/ and src/ paths, newline/quote/control-byte/pipe/unicode paths, non-string and object file_path, notebook_path, missing cwd, missing tool_name, non-matching tool, LOA_GRIMOIRE_DIR set / pointing elsewhere.

## Tests
npx --no-install bats tests/unit/notes-size-guard.bats zone-write-guard.bats hook-wiring.bats guard-yield.bats: 51/51 ok.

## Checked and found already optimal
- zone-write-guard: yq-derived values come from .run/perf-cache (hit), 13 ms is mostly bash+jq+realpath; no cheap lever.
- notes-size-guard NOTES.md path: `stat -c%s` is a single spawn, `_occurrences` uses pure-bash string ops, no loa_knob/yq anywhere in the hook.
- Early-exit order already puts the cheapest rejections first; non-Write tools exit before any content jq.
- The 4 ms hooks are at the bash+jq floor.

## Not fixed
- NOTES.md-targeted path still runs jq 3 more times (tool, content size, ...) — could fold into one jq; left as next lever (same hook, different technique scope).
- Two realpath spawns could be replaced by bash string compare when both paths are already absolute and normalised, but symlink semantics make that unsafe.
