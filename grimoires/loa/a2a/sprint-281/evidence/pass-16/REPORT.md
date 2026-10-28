# Pass 16: upgrade-health-check.sh (Setup hook)

Change: check_new_config_options() now probes the four config keys with ONE yq call instead of five `yq -e` spawns
(.recursive_jit twice, .continuous_synthesis, .continuous_learning, .run_mode). Per-key probes kept verbatim as fallback.
File: .claude/scripts/upgrade-health-check.sh (check_new_config_options, ~lines 218-250).

Matrix: Impact 1.5 (~14 ms, 6.6%), Confidence 0.9, Effort 0.6 => ~2.2 (>= 2.0).

Profile (baseline 221.2 ms +-9.0, 20 runs, -N -i): 203.5 ms (92%) is check-beads.sh -> `br doctor` (162 ms) = floor, same as
pass 15, in a different script and not removable without changing semantics. Remaining: 5 yq spawns ~21 ms (~10%),
grep -q probes ~1.5 ms each, no git/find/python/network calls at all, no marker/cache writes (only --fix edits settings.local.json).

Before/after (hyperfine -N -i, 30 runs, old vs new mirror, same CONFIG_FILE): 217.0 +-8.2 ms -> 202.7 +-4.4 ms (-6.6%).

Isomorphism:
- Ordering preserved: yes; missing_sections appended in the original order (recursive_jit, synthesis, learning, run_mode).
- Tie-breaking: N/A. Floating-point: N/A. RNG/hash: N/A.
- Trust boundary: no untrusted text interpreted; yq output is validated to be exactly four lines each true|false, otherwise fallback.
- Truthiness mirrors `yq -e` (null/false = missing; 0, "", {} = present); synthesis added only when recursive_jit present.
- Error/degraded paths: parse error, array root, empty file, multi-doc (`---`) => combined call fails or output is not 4 clean lines =>
  original per-key code runs unchanged. Missing config / yq absent branches untouched (precede the new code).
- Golden: old vs new mirror, 162 cases (9 configs: 7 yaml fixtures incl. malformed/empty/array/multidoc/string/false, missing, live;
  3 settings states: with bd perms, clean, missing; flags none/--json/--quiet; PATH with and without yq) cmp stdout+stderr+rc: 162/162 identical
  (normalised only the scratch settings filename run_old/run_new). --fix: output, edited settings and .bak identical.
- Tests: no bats file covers this script (only guard-yield.bats mentions the name; 11/11 ok when run).

Checked, already optimal / out of scope:
- check-beads.sh: br doctor 162 ms is the floor (br --version 3 ms, sqlite3 2 ms).
- grep -q probes on settings.local.json: ~1 ms each, 9 total; not worth merging (would change per-pattern semantics).
- No git, find, sha256, python or network calls in this script.
