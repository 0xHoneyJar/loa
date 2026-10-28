# ESO pass 7 — karpathy-surgical-diff-check.sh

## Result
Applied a small lever: skip two jq spawns for the session id when it is plain [A-Za-z0-9._-].
Live-state hook: 93 -> 88 ms (-5 ms, ~5%). With a scratch state: 65±4 -> 60±6 ms (30 runs, hyperfine -N, warmup 3).
This is below the mission's 96 ms framing: the large sub-costs cannot be removed by an isomorphic change inside this file (see below).

## Opportunity matrix
| Lever | Impact | Conf | Effort | Score | Decision |
|---|---|---|---|---|---|
| (c) session-id fast path (2 jq spawns) | 1.5 | 5 | 1 | ~7 on a 3-point scale basis | DONE |
| (b) skip `run-checkpoint.sh read` when its state file is absent | ~0 | 5 | 1 | rejected | measured: absent-file case only costs ~3 ms (script exits 2 at once); live repo HAS the file; couples hook to the script's default path |
| (a) merge the two loa_knob calls | 4-5 ms | 3 | 3 | ~1 | not done: diff_lines_per_task is not in the profile cache (always MISS -> yq+jq), so the merge would re-implement loa_knob's cache/stale/live semantics in the hook |

## Hotspot evidence (bash -x trace, 84 ms traced run; isolated hyperfine in ms)
- `bash run-checkpoint.sh read --json | jq`: ~44-51 ms = ~50% of wall. Inside it: `br show <task> --json` 23 ms (cannot be avoided: it verifies the task is closed), ~28 ms of 7 sequential jq spawns in cmd_read.
- loa_knob x2: ~20 ms (switch 7 ms, threshold 13 ms: cache lookup miss + yq + jq).
- the two session-id jq spawns: ~5 ms (this pass).
- source of profile-lib 2 ms; payload jq ~3 ms; rest is bash builtins/ls/awk/mv.

## Change
.claude/hooks/quality/karpathy-surgical-diff-check.sh (key section): payload_sid decoded in pure bash when PAYLOAD_SID_JSON matches ^"[A-Za-z0-9._-]*"$ (no escapes possible, so decoded == inner text); SESSION_JSON built as "\"$SESSION\"" when SESSION matches ^[A-Za-z0-9._-]+$ (jq -cn would print identical bytes). Any other value (escapes, control bytes, non-ASCII, numbers, NUL) takes the original jq path unchanged.

## Isomorphism proof
- Ordering preserved: yes, no reordering; same statements, two substitutions.
- Tie-breaking unchanged: yes (N/A; pruning ls -1t untouched).
- Floating-point: N/A. RNG/hash seeds: N/A.
- Trust-boundary sanitisation unchanged: yes. _sanitise (tr -c / cut / leading dot) still runs on SESSION; the fast path only admits the safe charset, everything else goes through jq as before. Content never reaches state.
- Error/degraded paths: unchanged (missing jq/yq/config exits precede the edit; malformed/empty/bash payloads exit before the edit). Verified in the matrix (empty, malformed, bash, off, none).
- Golden: 67 cases (payload matrix x {no ckpt, sprint ckpt}; 6 checkpoint kinds [none, sprint, task closed in beads, task unknown, schema v1, unparseable] x 4 configs [default, threshold 5 -> over, switch off, knob absent]; prior-sum, prune with KEEP=2, legacy delete, symlinked dir; KARPATHY_CHECKPOINT_CMD seams; LOA_SESSION_ID env ascii/odd/unicode; session ids: plain, absent, empty, number, quote/backslash, unicode, NUL, control bytes, 5000-line content). Compared stdout, stderr, rc, full state tree (state JSONL, summary, trajectory, legacy removal), ls -t order.
  Normalisation (documented): timestamps -> TS, date-stamped names -> DATE, and bash's `<hook path>: line N` prefix in the one NUL-byte warning (path/line differ between old and new mirrors). Old vs new: diff -r IDENTICAL; sha256sum -c golden_checksums.txt -> 335/335 OK.
- Mirror: old = git show HEAD copy at m-old/a/b/c/hook.sh, new = live file at m-new; LOA_RUN_DIR pinned so both read the same scratch run state (the .claude symlink makes run-checkpoint resolve to the real checkout otherwise).

## Tests
`npx --no-install bats $(grep -rl karpathy tests/unit/*.bats)`: 58 ok, 0 not ok (re-run after the edit).

## Checked and found already optimal / correct
- Config cache hit path of loa_knob for the switch: one stat + one jq, already minimal.
- Payload extraction is one jq already; awk PRIOR sum and the pruning loop are builtin-only on small dirs.
- run-checkpoint `read` with absent state file returns in ~3 ms, so the "skip when absent" idea is worthless.
- br show (23 ms) is a required trust check ("task closed"), not removable.

## Next levers (not done)
1. run-checkpoint.sh cmd_read: replace the 7 sequential jq spawns (parse check, schema_version, checkpoint, sprint, task, phase, ts) with one jq (~10-14 ms, ~12%); needs care with newline/NUL in fields and command-substitution trimming — different file, own pass.
2. Hook: when the checkpoint has no task or is null, avoid the second jq by reading `.checkpoint` fields from the same output; or cache the resolved key keyed on the state file mtime.
3. Knobs: one jq over the profile cache returning switch plus a miss flag for the threshold (~4-5 ms), or add diff_lines_per_task to the profile cache so it is a hit.
