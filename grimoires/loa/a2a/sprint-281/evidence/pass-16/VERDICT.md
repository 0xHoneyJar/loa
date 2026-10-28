VERDICT: APPROVE

Findings
- LOW (cosmetic), .claude/scripts/upgrade-health-check.sh:~260: the fallback block leaves a stray blank line before its closing `fi`. No behavior impact.
- INFO, fixtures 9/16/18 (sequence recursive_jit, top-level sequence, invalid YAML): the one-shot yq exits nonzero, so the per-key fallback runs. Output is identical to old.
- INFO, fixture 15 (multi-document): the one-shot emits 9 lines and the p_extra guard forces the fallback. Output is identical.
- INFO, fixture 8 (`recursive_jit: 5`): the fast path is taken with 4 lines, and its result matches old (continuous_synthesis reported, recursive_jit not reported).
- INFO, fixture 3 (`recursive_jit: {}`): `yq -e '.x' <<< 'x: {}'` gives rc 0, so the empty map counts as present on both paths. The result is identical.
- Comments are accurate. The change is one lever (four probes collapsed into one call, with a verbatim fallback). bash -n OK. check-no-swallowed-jq rc 0.

parity: 20/20 default + 20/20 --json (stdout+stderr+rc cmp, CONFIG_FILE env override; fixture 20 used a PATH with no yq and both took the "yq not available" branch)
bats: tests/unit/guard-yield.bats 11/11 ok
hyperfine (load ~4.6): first run 10 runs old 251.1±18.3 vs new 264.9±20.6 ms (noise, overlapping); rerun 25 runs old 215.3±5.2 vs new 203.2±6.8 ms (-5.6%); function alone x5 on live config 127 ms vs 53 ms
UNVERIFIED: other yq versions (tested on mikefarah v4.44.1 only); --quiet mode not in this harness (orchestrator covered it)
