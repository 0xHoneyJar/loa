# Pass 2 report: repo_map.py PageRank, hoist sorted() out of the iteration loop

## Opportunity matrix
Impact 4 (about 25% of wall time), Confidence 5, Effort 1 -> Score 20 (>= 2.0).

## Change
.claude/scripts/lib/repo_map.py (PageRank block, ~lines 160-175): precompute `sorted_edges` once
(list of (node, out_weight, sorted(out_edges[node].items())) for non-dangling nodes, in `nodes` order);
the 50-iteration loop iterates that list. The old loop sorted `out_edges[a].items()` every iteration,
but out_edges is loop-invariant (only `rank`/`new` change), so the sort was pure recomputation.

## Hotspot evidence
cProfile (before): 3.217 s total, build_map own 1.326 s, 213,996 sorted() calls = 0.635 s (~20% of profiled time).
After: 4,962 sorted() calls = 0.020 s; total 2.567 s.

## Timing (hyperfine -N, warmup 3, 10 runs, --emit md on live tree)
before 2324 ms +- 30 ; after 1703 ms +- 19 (-26.7%). Remaining build_map own time (1.28 s) is the
scan/regex/xref code, out of scope (pass 3).

## Isomorphism proof
- Ordering preserved: yes. `nodes` order and per-node `sorted(items())` order are identical, just computed once; skipped-dangling filter keeps relative order.
- Tie-breaking unchanged: yes. Final `ranked` sort key (-score, name) untouched; edge sort keys (b, w) unchanged.
- Floating-point: identical. Same expression `DAMPING * ra * w / ow` with the same operand values, same accumulation order into new[b].
- RNG / hash seeds: N/A (PYTHONHASHSEED=0 still set by callers; no set/dict-order dependence introduced).
- Trust-boundary sanitisation: unchanged, no emitter/scanner code touched.
- Error/degraded paths: unchanged; empty-tree (/nonexistent) run exit code and stderr identical to golden.
- Golden outputs: fixture tree (ties, collision dup, .py+.sh, mutual refs): md/json stdout, --out-md/--out-json files, rc, stderr all byte-identical (21/25 OK by
  sha256sum -c; the 4 mismatches are live-tree files, see below).
  Live tree: the engine scans .claude/ including repo_map.py itself, so the edit changes the input_hash and the symbol line numbers; a pre-edit golden cannot match.
  Equivalent proof: original engine (git show HEAD:...) vs new engine on the same current tree -> identical sha256 for --emit md (ab3d23fa...) and --emit json (8f85db26...).

## Tests
`npx --no-install bats tests/unit/repo-map-gen.bats`: file contains 6 tests, not 11. 5 pass; test 3 (`--validate` against committed REPO-MAP.md) FAILS only because
the committed grimoires/loa/REPO-MAP.md embeds the input hash of the pre-edit .claude/ tree (REPO-MAP-DRIFT). Orchestrator must regenerate (`bash .claude/scripts/repo-map-gen.sh`) with the commit, as for any .claude/ edit. I did not touch grimoires/.

## Not fixed / out of scope
- `defs_in_f = [d for d in known_names if rel in def_files[d]]` is O(files x names) and iterates a set: pass 3 territory (scan/xref).
- Remaining per-iteration cost: dict `new` init and edge loop; further wins would need restructuring float accumulation (risky), not done.

## Checked and found correct / already optimal
1. dangling list and out_weight are computed once already outside the loop.
2. `ranked` final sort runs once; fine.
3. walk_files sorting runs once; fine.
4. No dependence of the edge sort on per-iteration state (verified by reading all writes in the loop: only `new`, `rank`, `dangling_mass`).

git status: only .claude/scripts/lib/repo_map.py modified by this pass.
