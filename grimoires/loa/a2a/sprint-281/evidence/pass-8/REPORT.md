# Pass 8 - compat-lib.sh lazy capability probes

Matrix row: Impact 4 (every hook/script source), Confidence 5, Effort 2 -> score 10.

## Hotspot
`bash -c 'source compat-lib.sh'`: 8.2 ms vs 1.1 ms for `bash -c true`. ~7 ms (85%) is six probe forks
(uname 1.2, sed --version 1.2, find -printf 1.2, readlink -f 1.1, stat -c 0.9, sort -V 0.9 ms).

## Change (.claude/scripts/compat-lib.sh, Platform Detection block + 6 call sites)
- Six forking probes (_COMPAT_OS, _COMPAT_HAS_SORT_V, _COMPAT_SED_STYLE, _COMPAT_HAS_READLINK_F,
  _COMPAT_HAS_FIND_PRINTF, _COMPAT_STAT_STYLE) now start as "" (still defined: set -u safe) and are filled by
  `_compat_need_*` guards called at the top of the helper that reads them (sed_inplace, get_canonical_path,
  version_sort, get_file_mtime, find_sorted_by_time, _date_to_epoch). A pre-set value is never re-probed.
- _COMPAT_SHA256_CMD stays eager (command -v is a builtin, no fork; read directly by cache-manager.sh and bats).
- LOA_COMPAT_DEBUG=1 probes everything at source time, output identical to before.
- Probe commands and fallbacks themselves are unchanged. Re-sourcing after `unset _COMPAT_LIB_LOADED` re-initialises to "" so it re-probes (run-with-timeout.bats pattern).

## Consumers audited
Direct reads outside the lib: `_COMPAT_SHA256_CMD` (cache-manager.sh, bats; eager, unchanged) and tests that assign
`_COMPAT_OS=darwin` after sourcing (compat-date-utc.bats; non-empty so honoured). No export of any probe var; no other reader.
Probe vars now empty until first use (declare -p differs only for these six): _COMPAT_OS, _COMPAT_HAS_SORT_V,
_COMPAT_SED_STYLE, _COMPAT_HAS_READLINK_F, _COMPAT_HAS_FIND_PRINTF, _COMPAT_STAT_STYLE.

## Numbers (hyperfine -N, warmup 3)
| target | before | after |
|---|---|---|
| source compat-lib.sh | 8.2 +- 0.6 ms | 2.1 +- 0.2 ms |
| implement-gate.sh, Write payload (mirror trees, same layout, old vs new lib) | 30.8 +- 6.0 ms | 21.4 +- 1.7 ms |
Gate trace after: zero probe processes.

## Isomorphism proof
- Ordering preserved: yes, no output path touched. Tie-breaking unchanged: yes.
- Floating-point: N/A. RNG/hash seeds: N/A.
- Trust-boundary sanitisation: unchanged, lib has none; helpers' bodies untouched apart from the guard line.
- Error/degraded paths: sed_inplace arg-count error, sha256_portable rc 127, missing paths verified identical (matrix below).
- Golden: function matrix (get_canonical_path x6 incl. spaces/symlink/missing/empty, get_file_mtime ok+missing, version_sort
  plain+-r, find_sorted_by_time both orders, _date_to_epoch ok/empty/garbage, sed_inplace ok+bad args, sha256_portable
  stdin/file/missing, version, ucfirst, make_temp): old vs new stdout, stderr, rc byte-identical (cmp). LOA_COMPAT_DEBUG=1 output
  identical. set -euo pipefail with subshell-first call identical. Implement-gate hook: 6 payloads (bash, postbash, postwrite,
  session, skill, write) old vs new lib stdout+stderr+rc identical. grimoire-index.sh --tsv identical; repo-map-gen.sh --validate
  identical (modulo mktemp name/timestamp in the diff header; both report drift because the mirror layout is not the repo).
  Old-lib runs used mirror trees under /tmp/eso8 with the old lib copy.

## Tests
bats: compat-date-utc 4, compat-lib-jq-strict 8, compat-lib-sha256 6, run-with-timeout 13, butterfreezone-gen-sha256-portability 6:
37 tests, no `not ok`. (A run of all 46 files mentioning compat-lib was started but is slow; not awaited.)

## Known trade-off / not fixed
A first helper call inside `$(...)` cannot memoise into the parent, so a script that calls e.g. get_canonical_path
only through `$(...)` pays one ~1 ms probe per call (old: 0 per call, 7 ms once). Existing in-tree uses are a few calls per run
(loa-eject, constructs-install, loa-learnings-index); find_sorted_by_time's fallback pre-probes before its subshell pipeline.
Consumers that need many such calls can invoke `_compat_need_<x>` once first. Probe PATH is now the PATH at first use, not at source.

## Checked and already optimal
- sha256 detection is `command -v` (builtin), no fork; left eager.
- Helper bodies/run_with_timeout already detect at call time; unchanged.
- ucfirst/jq_strict/make_temp read no probe vars.
