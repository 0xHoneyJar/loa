VERDICT: APPROVE

## Findings
- None blocking. No differences found between old and new farms in any fixture or error scenario.
- INFO (pre-existing, not a regression), tests/unit/loa-decisions-surface.bats:128-136: the skip list is split with the function-local IFS=":" so a multi-tool call (`_path_without yq jq`) would skip nothing. The old per-file `$(IFS=' '; echo "$*")` had the identical behavior because the substitution is split by the outer IFS. All three callers pass one tool, so no test is affected. Behavior preserved byte-for-byte.

## Method
Old (git show HEAD) and new (working tree) helper bodies extracted by python into standalone scripts (/tmp/eso21r/scripts/{dw,ds,rt}-{old,new}.sh); rt run under `bash -e` to mimic bats errexit. Farms compared with `find -mindepth 2 -printf '%P -> %l\n' | sort`.
Synthetic PATH: d1 : nonexistent : "d 2" (space in path) : d3empty : d4 : tools(ln,mkdir,tr). Fixtures: dup in d1/d2/d4 (d1 wins), jq in d1/d2 (hidden), dangling symlinks in d1/d2 plus a real `dangle` in d4, non-exec file, subdir, "with space", "-dash", timeout/gtimeout, empty dir (literal `*` glob entry).

## Lines
- farm parity dec-write path_without: identical, real PATH 2238 entries, synthetic 13 entries; pre-existing regular file + dangling entry identical (exit 0/0); read-only farm dir identical (exit 0/0, || true kept).
- farm parity decisions-surface _path_without: identical, real 2238, synthetic 13; pre-existing entries identical (exit 0/0); read-only farm identical (exit 0/0).
- farm parity red-test-check RTC-9 shim: identical, real 2232, synthetic 10 (exec-only filter, dir/non-exec/dangling-source drop, timeout|gtimeout skip, d4/dangle wins over d1 dangling source all same); pre-existing entries identical (exit 0/0); read-only shim fails both old and new (exit 1/1 under bash -e), so the failing-ln-fails-the-test semantics hold.
- bats counts: 90 ok, 0 not ok, 0 skip (three files, 1m25s wall, load ~4).
- timing one dec-write helper call, real PATH: old 1.97 / 2.06 / 2.11 s; new 0.088 / 0.091 / 0.098 s.
- lint/scope: diff touches only the three test files; no assertion, skip condition or dependency changed; first-wins comments accurate; bash-3.2-safe (empty-array expansion guarded by the count check).
- UNVERIFIED: BSD/macOS `ln -s -- src... dir/` not run (GNU coreutils only); full-suite 26 s saving not re-measured; ds/rt timing not individually measured (dw only).
