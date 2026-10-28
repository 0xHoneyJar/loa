# ESO pass 18 - round-2 re-profile of the per-tool-call hook chains

## Re-baseline (hyperfine -N, warmup 3, 20 runs, ms mean +- sd; scratch mirror /tmp/eso18-base, LOA_RUN_DIR pinned; PreToolUse through hook-guard.sh)
| Event | Hook | ms |
|---|---|---|
| Bash Pre | block-destructive-bash | 15.15 +-0.49 |
| Bash Pre | team-role-guard | 3.43 +-0.24 |
| **Bash Pre chain** | | **18.6** |
| Write/Edit Pre | team-role-guard-write | 3.67 |
| | spiral-dispatch-guard | 3.50 |
| | zone-write-guard | 12.55 |
| | implement-gate | 17.91 |
| | notes-size-guard | 20.72 +-2.16 |
| | adversarial-review-gate | 4.10 |
| **Write/Edit Pre chain** | | **62.5** |
| Skill Pre | team-skill-guard / spiral-skill-sentinel | 3.77 / 4.27 -> **8.0** |
| Post Bash | mutation-logger | 7.22 |
| Post Write/Edit | write-mutation-logger | 4.89 |
| | karpathy-surgical-diff-check | 83.67 +-4.68 |
| **Post Write/Edit chain** | | **88.6** |
| Stop | run-mode-stop-guard | 22.87 (A/B run: 22.19) |
| | settings-cleanup | 2.90 |
| **Stop chain** | | **25.8 -> 15.8 after this pass** |
| UserPromptSubmit | post-compact-reminder / post-session-limit-reminder | 1.42 / 1.84 -> **3.3** |
| (floor) | hook-guard.sh /bin/true | 2.75 |
| (parse) | `bash -n block-destructive-bash.sh` | 4.0 +-0.2 ms (the 2,839-line parse is ~27% of that hook; hook-guard's bash -n; not removable without changing the fence) |

Raw JSON in before/*.json; bench.sh, tab.sh reproduce.

## Hotspots profiled (PS4 EPOCHREALTIME)
- karpathy (84 ms here): 35.6 ms is `run-checkpoint.sh read --json`, of which 21.9 ms is `br show <task>` (live .run/sprint-plan-state.json still names task bd-447u3, so beads must confirm "closed" to pick the task key; the key (task vs sprint) depends on the result -> NOT removable). Next: loa_knob threshold 10.3 ms (non-profile key: stat + cache jq miss + live yq + jq) and switch knob 5.5 ms; 2-3 jq spawns for sid/SESSION_JSON (~4.4 ms). The threshold knob cannot go in the profile cache (cache holds only profiles.yaml keys; adding it would change loa_knob semantics for every caller). Not done: needs profile-lib change (shared, wide blast radius) or duplicating its stale-id logic.
- run-mode-stop-guard (19.7 ms traced): three consecutive `yq eval` spawns in push-notify-lib `_push_load_config`, 4.5+4.3+4.1 = 12.9 ms = 65% of traced time. Chosen.
- notes-size-guard (18.8 traced): 3 jq (3.3/2.9/2.8) + stat + realpath = floor after pass 10. block-destructive-bash: 10.6 ms traced, 4 ms bash -n; already literal-pre-filtered; no regression.

## Lever (ONE): collapse the three yq spawns in `_push_load_config` into one
Opportunity: Impact 4 (-9.3 ms, -42% of the Stop hook; also helps degraded-verdict-lib callers) x Confidence 4 / Effort 2 = 8.0.
File: .claude/scripts/lib/push-notify-lib.sh `_push_load_config` (fast-path block inserted before the three original reads, which are kept verbatim as the fallback).
One `yq eval '(a // false), (b // ""), (c // 5)'` prints each node as its own call would. Accepted only when yq rc=0 AND exactly three lines (every node prints >=1 line, so 3 lines = 1 line each, byte-identical to the separate reads); otherwise (failure, multi-line value, empty trailing value) the original three reads run unchanged. `"null"` -> "" normalisation kept.

| | before | after |
|---|---|---|
| run-mode-stop-guard, terminal state + live config (hyperfine 30 runs) | 22.19 +-1.54 ms | 12.91 +-0.82 ms |
| Stop chain (+ settings-cleanup 2.9) | ~25.1 | ~15.8 |

## Isomorphism proof
- Ordering preserved: yes (same three globals, same order of assignment, one yq reads them in expression order)
- Tie-breaking unchanged: yes (N/A)
- Floating-point: N/A. RNG / hash seeds: N/A
- Trust-boundary sanitisation: unchanged. Config text only ever lands in PUSH_* globals exactly as before; the command is still executed only by push_notify's `bash -c`; no new parsing of untrusted bodies.
- Error/degraded paths: missing file, missing yq -> early returns untouched (golden incl. PATH=/nonexistent); unparseable YAML, scalar/array `push_command`, multi-line/empty values -> fallback to the original reads (4 yq spawns, verified by trace), outputs identical.
- Golden: 32 configs (basic, hex/exp/leading-zero numbers, string "true", yes, null/"null" command, block scalars, escapes, arrays/maps, anchors, comments, CRLF, multidoc, unicode/control, empty file, missing file, no yq) through push_notify_active, od -c of rc and the three globals: old vs new IDENTICAL. Fast path taken for 23/32, fallback for 9/32 (trace-confirmed).
- Hook-level golden: run-mode-stop-guard with old vs new lib across 5 configs x {JACKED_OUT, RUNNING} x {valid, empty, malformed stdin}: stdout, stderr, rc, pushed-command output and push-last-state.json IDENTICAL (9 real pushes). golden_checksums.txt: 4/4 OK.

## Tests
bats: cycle-117-push-gate, cycle-117-stop-guard-zombie-exemption, cycle-114-stop-guard-bg-tasks, degraded-verdict-lib, adversarial-review-verdict-quality, red-team-code-vs-design: 65/65 pass.

## Notes / not fixed
- .claude/checksums.json lists the lib's sha256 (3aebffb4...); earlier passes did not touch it, so left for the orchestrator's regen.
- karpathy candidates (not done, separate lever each): fold the two `jq` sid/SESSION_JSON spawns behind a plain-charset regex fast path (~4.4 ms); read the threshold with one yq when the raw scalar is plain decimal (~5 ms); both need their own golden.
- Edit tool is blocked by zone-write-guard on .claude/ here; applied via python3 rewrite as instructed.

## Checked and found already optimal
- notes-size-guard, zone-write-guard, implement-gate: remaining spawns are the jq/realpath/stat floor (passes 9/10).
- hook-guard.sh: 2.75 ms floor; `bash -n` of block-destructive-bash 4.0 ms, no regression from the 2026-07 literal pre-filters (hook total 10.6 ms traced).
- run-checkpoint cmd_read fast path (pass 7) is single-jq; the remaining cost is the mandatory `br show`.
- Skill, UserPromptSubmit, settings-cleanup, mutation-loggers: 1.4-7 ms, at the spawn floor.
