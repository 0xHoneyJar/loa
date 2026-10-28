# ESO pass 19 report: round-2 re-profile (SessionStart, Setup, per-turn hooks)

## Lever (ONE): karpathy-surgical-diff-check.sh spawn diet
Files: .claude/hooks/quality/karpathy-surgical-diff-check.sh (session-key block ~L124-145, task_raw block ~L142-146).
- `jq -r .` (decode payload sid) and `jq -cn --arg` (encode SESSION) are skipped when the id is only [A-Za-z0-9._-] (every UUID): pure-bash regex / quoting; any other id takes the ORIGINAL jq path unchanged.
- `| head -1` after the checkpoint jq replaced by `${task_raw%%$'\n'*}` (same first-line semantics, no fork).
Net: 3 forks removed per Write/Edit on the common path.

## Re-baseline (hyperfine -N, warmup 3, 20 runs, ms mean, sd), HEAD 726bd4f46, live state
check-updates                       16.27   0.72
karpathy                            84.68   4.84
loa-context-class                   20.61   0.66
loa-decisions-surface               16.21   3.10
loa-kf-surface                      16.15   1.67
loa-l6-surface-handoffs              9.67   0.67
loa-l7-surface-soul                  9.52   0.71
loa-run-mode-session-title           8.68   0.52
loa-run-state-surface               14.92   0.69
mutation-logger                      7.24   0.59
post-compact-reminder                1.40   0.19
post-session-limit-reminder          1.31   0.16
run-mode-stop-guard                 13.28   0.41
settings-cleanup                     2.89   0.23
upgrade-health                     205.07   6.41
write-mutation-logger                5.15   0.22

Per-event totals (sum, serial; Claude runs hooks of one event concurrently so wall ~ max): 
- SessionStart chain: check-updates 16.3 + l6 9.7 + l7 9.5 + title 8.7 + kf 16.2 + decisions 16.2 + run-state 14.9 + context-class 20.6 = 112.1 ms (pass-11 baseline sum 129.0). Max single: context-class 20.6.
- Setup: upgrade-health 205 ms (floor `br doctor`, pass 16).
- UserPromptSubmit: compact 1.4 + session-limit 1.3 = 2.7 ms (already minimal).
- PostToolUse Bash: mutation-logger 7.2. Write/Edit: write-mutation-logger 5.2 + karpathy 84.7 (concurrent; karpathy is THE per-turn hotspot).
- Stop: run-mode-stop-guard 13.3 (pass 18) + settings-cleanup 2.9.
Note: before.json hyperfine for karpathy ran against the live repo with payload session_id "bench" (appended 36 rows to gitignored .run/karpathy-surgical/bd-447u3.jsonl + rewrote the summary); I removed exactly those rows and restored the summary to its last real values. All later A/B ran in /tmp mirrors.

## Hotspot evidence (PS4 trace of karpathy, 73 ms traced)
- `run-checkpoint.sh read --json` 34.8 ms (48%): of which `br show <task>` 20.8 ms (bead_closed verification: semantic floor, NOT removable) + jq 3.2 + jq 2.2.
- loa_knob #2 (diff_lines_per_task, not a profile key -> cache MISS -> live yq+jq) 9.6 ms; loa_knob #1 4.9 ms. Shared profile-lib (10 callers); live yq|jq cannot be merged into one process without changing scalar rendering (1.0, 0x10, quoting) -> left.
- the removed forks: jq -r . 2.1 + jq -cn 2.0 + head -1 ~0.8 = ~4.9 ms (~6.5%).
Opportunity: Impact 2 (≈5% of the top per-turn hook) x Confidence 5 / Effort 1.5 = 6.7 (>= 2).

## Before/after (karpathy, real-dir mirrors, LOA_RUN_DIR pinned, same payload)
- single pair (30 runs): old 84.59 +-3.25 -> new 78.66 +-3.63 ms
- 2 interleaved pairs (40 runs each): old 81.81 +-5.65 / 87.82 +-6.81, new 81.75 +-10.40 / 79.42 +-3.93 (noisy: br show jitter). Expect ~4-6 ms (about 5%) saved; floor is br show.

## Isomorphism proof
- Ordering preserved: yes (same statements, same order; only the producers of two strings changed).
- Tie-breaking unchanged: yes (N/A, no sorting touched).
- Floating-point: N/A.   RNG / hash seeds: N/A.
- Trust-boundary sanitisation unchanged: yes. The fast path accepts only ^"[A-Za-z0-9._-]*"$ (no escapes, no control/non-ASCII/quote/backslash) and quotes only ^[A-Za-z0-9._-]+$; for those strings jq -r . / jq -cn are the identity / plain quoting. Everything else runs the original jq. Key is still produced by _sanitise; payload content never reaches state.
- Error/degraded paths unchanged: yes (missing config/jq/yq exit paths untouched, they precede the edited block; checkpoint junk/empty/multi-doc covered in golden). NUL-byte sid still takes the jq path and emits the same bash warning (only its line number in the warning text shifts, normalised in the compare).
- Golden: 470 hook invocations (config none/empty/warn1/off/def/bad x checkpoint task/sprint/newline/none/junk/empty x 18 session-id shapes incl. empty, space, quote, UTF-8, trailing newline(s), "..", leading dot, pipe, 200-char, backslash, NUL, tab, non-string, number, array; LOA_SESSION_ID set/odd; USER odd/empty; tools Write/Edit/NotebookEdit/Read; control-byte/pipe/<> file_path; empty/malformed/array/multi-doc payload; 150-line over-threshold with trajectory). Captured stdout, stderr, rc, every file written (state, summary, trajectory, effective-config cache), timestamps/mtimes/pids normalised. Old==new: g-old.n / g-new.n byte-identical (golden_checksums.txt, 2/2 equal hashes; old-vs-old rerun also deterministic).
- Golden outputs: cmp IDENTICAL.

## Tests
bats tests/unit/karpathy-config-schema, karpathy-surgical-diff, karpathy-surgical-diff-hook, karpathy-trajectory-event, guard-yield: 35/35 ok, 0 not ok.

## Checked and found already optimal / not removable
1. run-checkpoint read: `br show` 20.8 ms is the closed-bead verification (pass 7 already one-jq'd the rest).
2. loa-context-class.sh: 18.7 ms traced is ~25 small spawns, none above 3 ms (jq 2.9, tr 2.1, timeout cat 2.1, git rev-parse 2.0); no single lever.
3. loa-decisions-surface.sh (disabled in live config): 12.9 ms = loa_knob 5.6 + `yq --version` 3.1 + source 1.1; the yq probe is needed before the config branch chooses knob vs awk, so no lazy-probe win; the 1,100-row path is not exercised when disabled.
4. post-compact-reminder / post-session-limit-reminder 1.3-1.4 ms: process-start floor.
5. upgrade-health-check 205 ms: br doctor floor (pass 16).

## Not fixed (out of scope / behaviour risk)
- profile-lib loa_knob miss path (live yq|jq, ~7 ms, shared by 10 callers): needs a cache-format change or rendering-equivalent single yq; defer.
- karpathy: ls -1t rotation + awk sum + payload jq (each ~1-3 ms) remain; the payload jq is required.
