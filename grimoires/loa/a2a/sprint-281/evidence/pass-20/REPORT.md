# Pass 20 - repo_map.py PageRank list-indexing (round-2 re-profile of grimoire-index / repo-map-gen / loa-status)

Re-baselines (hyperfine -N, 10 runs): grimoire-index.sh --json 541 +- 11 ms; repo-map-gen.sh --json 1561 +- 18 ms; loa-status.sh (-i) 776 +- 20 ms.

Ranked hotspots (measured ms):
| # | Cost | ms | Note |
|---|------|----|------|
| 1 | repo_map.build_map PageRank edge loop (4275 nodes, 124k edges x 50 iters) | ~810 of ~1350 engine | dict[str] lookups in inner loop |
| 2 | extract_python ast.parse+walk (102 files) | ~220 total | far below the ~0.5 s predicted; ast.walk is ~0.1 s |
| 3 | TOKEN_RE findall over 534 files | ~94 | |
| 4 | loa-status six per-model yq | ~40 | left |
| 5 | grimoire-index decisions yq/jq chain | ~25-60 | left (parser floor) |
| 6 | extract_bash | ~47 | |
| - | xref/graph build | ~28 | |

Matrix: Impact ~400 ms (26%), Confidence 0.95, Effort 1 -> score ~ 3.8 (>= 2.0).
Lever (one): index the PageRank hot loop by integer node index in lists instead of str-keyed dicts; hoist DAMPING*rank[i]. File: .claude/scripts/lib/repo_map.py build_map PageRank block.
Timing (engine, old vs new, 10 runs): 1552 +- 15 ms -> 1159 +- 18 ms (-25.3%). Wrapper repo-map-gen.sh --json: 1561 -> 1154 +- 14 ms.

Isomorphism proof
- Ordering preserved: yes - sources visited in sorted node order, each source's edges in sorted-target order (same sorted(items())), ranked sort untouched.
- Tie-breaking unchanged: yes - (-score, name) sort untouched.
- Floating-point: identical - same expression ((DAMPING*rank)*w)/out_weight (dr computed once per source = same first op), same accumulation order into each new[b], same dangling sum order, same base+redistributed init, same round(,6). Bit-equal confirmed by cmp of JSON scores.
- RNG / hash seeds: N/A (PYTHONHASHSEED=0 retained; no set iteration added; node list sorted).
- Trust-boundary sanitisation: N/A, no untrusted-body surfacing in this path; extraction/escaping untouched.
- Error/degraded paths: unchanged - n==0 path (empty tree) compared old vs new identical (md+json); syntax-error / NUL-byte / bad-utf8 / latin-1 coding-declaration fixture identical stdout+stderr+rc.
- Golden outputs: sha256sum -c golden_checksums.txt -> 14/14 OK (recorded in golden_checksums.txt; rm_live.* is the pre-edit tree whose input hash differs only by the repo_map.py edit; rm_live_current.* is the apples-to-apples capture).

Golden: old engine (git HEAD copy) vs new engine, `--emit md` and `--emit json`, stdout+stderr+rc, on (a) live .claude tree (compared on the post-edit tree, since repo_map.py is itself scanned so the input hash changes with the edit), (b) fixture tree with decorated/nested/async functions, classes, methods, lambdas, comprehensions, duplicate names, keyword-named defs, syntax error, NUL byte, non-utf8 bash, latin-1 coding declaration, `function kw` form, (c) empty tree: ALL byte-identical (cmp).
Tests: bats tests/unit/repo-map-gen.bats 6/6 ok (test 3 --validate needs the committed REPO-MAP regenerated because the scanned engine changed; regenerated via repo-map-gen.sh itself: grimoires/loa/REPO-MAP.md + .checksum modified, expected). No pytest references repo_map.
Files changed: .claude/scripts/lib/repo_map.py (PageRank block), grimoires/loa/REPO-MAP.md + .checksum (script regeneration, input hash only changes; symbol content identical).
Not fixed: loa-status six yq (~40 ms), agy_gate_warn_once double read (~25 ms), grimoire-index decisions yq floor (~175 ms) and re-parse/final jq (~25 ms), extract_python single-pass visitor (<=~100 ms, higher risk to def order: ast.walk is BFS, a visitor would be DFS and change def order within a file -> would need re-sort; skipped).
Checked and fine: ast.walk BFS order is observable for same-name defs in one file (def_sites order sorted by (rel, lineno) afterwards, but kind of sites[0] on ties) so no change made; walk_files/file reading only ~22 ms; xref/graph build already inverse-indexed (28 ms); hashing negligible.
