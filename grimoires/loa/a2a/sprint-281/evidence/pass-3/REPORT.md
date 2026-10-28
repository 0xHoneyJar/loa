# ESO pass 3 - repo_map.py build_map scan/xref own-time

## Result
Files changed: .claude/scripts/lib/repo_map.py (3 insertions, 1 deletion, in build_map: a file_defs index declared next to def_files, filled where def_files is filled, and the `defs_in_f` comprehension replaced by `file_defs.get(rel, ())`).
Lever: replace the per-file O(names) scan `[d for d in known_names if rel in def_files[d]]` with an inverse index (file -> names) built once during def collection.

## Hotspot evidence (scratch copy with perf_counter blocks, 3 runs, no profiler)
The mission premise ("per-name regexes") does not match the code: tokenisation is already once per file (TOKEN_RE.findall into a count dict). No per-name regex exists.
| sub-block | time | share of ~1.7 s wall |
|---|---|---|
| read + tokenise + extract (ast) | ~0.5 s | ~30% (ast.walk and compile dominate; out of scope, extractors forbidden) |
| xref block total | 0.19-0.21 s | ~12% |
|  - defs_in_f comprehension (534 files x 4266 names ~ 2.3M membership tests) | 0.155-0.176 s | ~9-10% (chosen) |
|  - edge accumulation | 0.013 s | <1% |
| per-token `counts.get(tok,0)+1` loop (the 1M dict.get calls under cProfile) | ~0.13 s vs Counter 0.09 s, saves ~0.04 s | ~2% (rejected: below threshold, second lever) |
cProfile own time of build_map (1.33 s) is inflated by profiler overhead on the inline loops; real xref cost is the above.

## Matrix
Impact 2 (~160 ms, 9%), Confidence 5 (pure index inversion), Effort 1 -> Score ~10 (>= 2.0).

## Before/after (hyperfine -N, warmup 3, 10 runs, `--emit md` on live tree)
before 1726 ms +- 20   after 1562 ms +- 16   (-164 ms, -9.5%)

## Isomorphism proof
- Ordering preserved: yes. defs_in_f is now a set in different iteration order, but each defining symbol `a` mutates only its own out_edges[a], and the sequence of updates to out_edges[a] is determined by the file loop and `refs` order, both unchanged. Pass 2 also sorts edges before use.
- Tie-breaking unchanged: yes. ranked sort key and sorted(known_names) untouched.
- Floating-point: identical. Integer weights, same per-node summation order; PageRank untouched.
- RNG / hash seeds: unchanged (PYTHONHASHSEED=0 still set; no output depends on set order).
- Trust-boundary sanitisation: unchanged. Emitters/_md_escape untouched.
- Error/degraded paths: unchanged. Files failing ast.parse add no defs, so they get no file_defs entry; `.get(rel, ())` yields empty exactly as the old comprehension (no names with rel in def_files). Fixture includes two unparseable files; stderr and exit code identical (cmp).
- Equivalence: file_defs[rel] = {name : rel in def_files[name]}, both filled at the same statement, and known_names = defs.keys() = def_files.keys(), so the sets are equal.
- Golden: fixture tree (overlapping names log/log_error/log_error_x, metacharacter name a.b which is not a valid def token, names only in string/comment, self-reference, name defined in own file, Unicode text and identifiers, .sh and .py defining dup/main_py, stopword def `if`, syntax-error file, invalid-UTF-8 file) x json,md: stdout, stderr, rc all cmp-identical to the old engine. Live tree: old engine (HEAD copy) run on the SAME current tree vs new engine: cmp identical for json and md (stdout/stderr/rc, 12/12 files). Note the original pre-edit live goldens differ only in "Input content hash" because repo_map.py itself lives under the scanned .claude tree and was edited; that is expected, not a behaviour change. Fixture goldens 6/6 OK under sha256sum -c, live 4/4 OK against the old engine rerun.

## Tests
npx --no-install bats tests/unit/repo-map-gen.bats: 5/6 pass. Test 3 (--validate passes against committed REPO-MAP.md) fails as expected until the orchestrator regenerates REPO-MAP.md (input hash changed because the engine file is part of the mapped tree).

## Not fixed / out of scope
- Biggest remaining cost: ast.walk in extract_python (~0.5 s with tokenising); a single-pass node visitor or compile-skipping would be the next lever (extractors forbidden this pass).
- Token counting loop could use collections.Counter (about 40 ms, identical dict order verified on live tree); left as a separate lever.
- Python startup + emit not examined.

## Checked and found correct / already optimal
- Tokenisation already once per file via a single compiled TOKEN_RE; no per-name regex scan exists.
- Edge accumulation (13 ms) and the xref sum loop are cheap; walk_files 8 ms.
- input-hash loop uses precomputed bytes; no re-read of files.
- Counter(findall) yields identical dict contents and first-occurrence order (verified on live files), so that later lever is also safe.
Scratch: ~/.cache/loa/eso-loop/pass-3/ (cap.sh, fixture, golden, after, oldnow, before.json, after.json).
