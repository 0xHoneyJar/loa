VERDICT: CHANGES_REQUIRED

Code parity is clean. The blocking items are small: two stale comments that now contradict the design, plus one throughput regression in looping batch scripts that should get a cheap mitigation or an explicit accepted-trade-off note.

Findings:

1. LOW (blocking under contract check 5: comments must describe the new implementation). .claude/scripts/compat-lib.sh:12-15 still says "Design principle: Detect once at source time, dispatch per-call ... cache the platform detection result so every subsequent call is a single branch, not a fork+exec of `uname`". .claude/scripts/compat-lib.sh:49-51 (the "Like Chromium's build/detect_host_arch.py — detect early, cache globally ... Every function below reads these cached flags instead of forking a subprocess" paragraph) is also stale. Detection is now lazy, and inside $(...) it forks per call. Verified by reading the file. Fix: reword both to "detect lazily on first use, cache in the calling shell".

2. MEDIUM (non-hot path, throughput regression). A first call inside $(...) re-probes every time. Measured per call, with the lib already sourced and 200 iterations each:
   - x=$(get_file_mtime /): old 1.63 ms, new 3.24 ms (+1.6 ms per call)
   - x=$(_date_to_epoch ...): old 1.54 ms, new 3.19 ms (+1.6 ms per call)
   About 6.4 ms of source cost is saved, so break-even is about 4 subshell calls per process. Files whose new cost exceeds the old cost for N above that threshold:
   - .claude/scripts/qmd-sync.sh:175,196. needs_reindex plus update_mtime_cache run per file in the collection loop (line 321), so 2 calls per file. That is +3.2 ms per file, or roughly +0.6 s on 200 files.
   - .claude/scripts/red-team-retention.sh:192. One call per result file in the retention loop.
   - .claude/scripts/archetype-resolver.sh:500. One call per open thread line.
   - .claude/scripts/lib/dec-write-lib.sh:162. marker_state is itself called in $(...) per run dir (lines 177, 778), so it re-probes every time. That is a small N, net about neutral.
   None of these are hooks or per-tool-call. Hot paths all win:
   - implement-gate.sh:465 makes 1 call. Measured below.
   - loa-decisions-surface.sh:122 sources the lib inside a subshell once, so it is cheaper than the old full probe.
   - loa-eject.sh, loa-learnings-index.sh and constructs-install.sh make 1 or 2 calls, which is a net win.
   Mitigation options: call `_compat_need_stat_style` / `_compat_need_os` once after sourcing in qmd-sync, red-team-retention and archetype-resolver. That widens scope by three one-liners. Alternatively, record this as an accepted trade-off in the lib comment and in the pass REPORT. In-lib, find_sorted_by_time's fallback pre-probe (compat-lib.sh:392) is the only internal pipeline or subshell that calls a helper. Verified by grepping the lib for helper calls.

No other findings:
- Every in-lib reader of the six variables is preceded by its guard in the same function: sed_inplace:179, get_canonical_path:220, version_sort:278, get_file_mtime:352, find_sorted_by_time:381/392, _date_to_epoch:492. The DEBUG block at 138-139 also calls the guards.
- The only external reader is dx-utils.sh:429, and it is now guarded. `git grep` repo-wide, excluding evals results and fixtures, found nothing else. No `declare -p`, `env|grep` or `compgen` readers exist.
- A pre-set before sourcing (`_COMPAT_OS=darwin; source lib`, or an env-exported `_COMPAT_STAT_STYLE=bsd`) is overwritten in both old and new code. Old prints linux/gnu, new prints linux/gnu. No behaviour change. compat-date-utc.bats sets the value after sourcing, and that is honoured in both versions.
- Re-sourcing after `unset _COMPAT_LIB_LOADED` resets to "" and re-probes on use, giving [] then [gnu].
- No bash-4-only syntax was added.

Parity: function matrix of 25 cases × {plain, set -euo pipefail} old-vs-new in fresh bash gave 48/50 identical stdout, stderr and rc. The cases covered:
- sed_inplace ok, no-args and 1-arg
- get_canonical_path on a file with spaces, a symlink, a missing path and an empty string
- version_sort plain and -r
- get_file_mtime ok and missing
- find_sorted_by_time both orders, plus a forced no-printf fallback with gnu and bsd stat style
- _date_to_epoch ok, empty and garbage
- sha256_portable on stdin, a file and a missing file
- make_temp, ucfirst, and a post-source _COMPAT_OS=darwin override
The 2 diffs are the designed case: reading $_COMPAT_OS directly after the only helper call was in $(...) prints "" instead of linux. No in-tree consumer does this.
`env | grep _COMPAT` is identical (empty in both). LOA_COMPAT_DEBUG=1 stderr is identical by md5. dx-utils `_dx_install_hint jq/yq` output is identical old vs new.
implement-gate mirror old vs new: 12/12 identical stdout, stderr and rc. That is 6 payloads × {default env, LOA_IMPLEMENT_GATE_TEST=1}.
grimoire-index --tsv rc 0 with 1195 rows. --validate rc 0.
Bats: 88/88 ok (TAP) across compat-date-utc, compat-lib-jq-strict, compat-lib-sha256, run-with-timeout, implement-gate, integration/butterfreezone-gen-sha256-portability, .claude/scripts/tests/test-eject-portability, bash32-portability and portable-realpath. The butterfreezone "exited with code 127" text is bats warning BW01 on P3, which expects 127. It is not a failure, and that file is 6/6 on 3 reruns.
Hyperfine:
- source: old 8.3±0.7 ms, new 1.9±0.2 ms (4.3x, -N, 30 runs)
- implement-gate Write payload: old 27.1±1.2 ms, new 21.0±0.9 ms (10 runs)
Both gaps are more than 3σ.
UNVERIFIED: macOS/BSD and Windows hosts. Probe-order behaviour there is only reasoned, not executed; the fallback branches were exercised by forcing the flags. bats suites beyond the 9 listed were not run.
