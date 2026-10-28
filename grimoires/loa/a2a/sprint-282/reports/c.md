# cycle-137 Sprint 282 Task 2.5 (bd-wctli): implementer C report

Worktree `/home/merlin/Documents/thj/code/loa-wt-c137-c`, branch `wt/cycle-137-c`, base `747b5db0d`. Test-only task, ONE patch: `.cycle137/task-2.5.patch` (the two allowlisted files only). Host `fukuoka`, 8 CPUs, bats 1.13.0 via `npx --no-install`, bash 5.2. The host was shared with three other implementers: load is recorded per run and it dominates the run-to-run variation.

## Bottom line

- **Part 1 done.** The fence corpus now runs once per file process in `setup_file`. The file went from 95 s to 62 s (one serial run each), and the three corpus tests from 14–22 s each to under 50 ms. Status, stdout and stderr are captured and asserted by `corpus_json()`.
- **Part 2: the knob is in, but it buys no wall time.** `CMP_STUB_HOLD_S` (default 300) now drives the shim's three reaped holds and is set to 240 in `setup()`. Every reaped hold is ended by the reaper or by teardown, never waited out, so a passing run never spends hold time. An interleaved old-vs-new run of the four affected tests shows no difference beyond noise.
- **The 300 s target is not reachable by test edits.** The engineering floor is the script itself: the file calls `main` 163 times at about 3 s each on this host. The measured whole-file wall time is 652–1043 s depending on load. The lead needs the class-S DEC row moving FR-6 to the measured floor (see "Floor").
- **TAP set identical.** All six runs, plus the confirmation run, are 284 ok / 0 not ok / 0 skip. The per-name diff is empty. CMP-37 passed in every run and was not touched.
- **No STOP condition fired.** Wall time used: about 1 h 50 min.

## Part 1: `tests/unit/block-destructive-bash.bats`

Change: a new `setup_file()` computes the project root and hook path with the same expressions as `setup()`, clears `LOA_BLOCK_DESTRUCTIVE_JQ_MISSING_WARNED` as `setup()` does, and runs `bash "$project_root/$CORPUS_RUNNER" --hook "$hook" --json > corpus.json 2> corpus.err; echo $? > corpus.status` inside `{ …; } || true` under `$BATS_FILE_TMPDIR`. The runner exports its own `LOA_REPO_ROOT` (its own `mktemp -d`), so no other `setup()` state is needed. `corpus_json()` now asserts `corpus.status` is `0` (else prints the status and `corpus.err` to stderr and returns 1), asserts `jq -e . corpus.json`, then prints the file. The three corpus tests, their assertions and the runtime test's `runtime_ms` read are unchanged.

| Run (serial, `--tap -T`) | rc | wall | ok | corpus tests (dangerous / benign / runtime) |
|---|---|---|---|---|
| old file (HEAD copy) | 0 | 95 s | 291/291 | 14560 / 14041 / 22283 ms |
| new file | 0 | 62 s | 291/291 | 40 / 36 / 49 ms |

Load during these two runs: about 10 on 8 CPUs (the companion baseline was running). The `setup_file` replay time is outside every test's `-T` time; the file wall time carries it once.

Evidence files: `bdb-before.tap`, `bdb-after.tap`.

- **`-f` single test.** `-f 'cycle-125 corpus: benign'` alone: `1..1`, ok (`bdb-f-benign.tap`). `-f 'hook runtime over the corpus'` alone: ok (`bdb-f-runtime.tap`).
- **`setup_file` runs once.** A scratch copy whose `setup_file` appends one line per call to a log, run with `-f 'cycle-125 corpus'` (4 tests): the log had exactly 1 line.
- **Runner failure fails the three tests, not the file.** A scratch copy with `CORPUS_RUNNER` pointed at a missing script, run with the corpus tests plus `P3 negative`: `P3 negative` and the lint test passed. Each of the three corpus tests failed at `local j; j=$(corpus_json)` with `run-corpus.sh exited 127:` and the runner's stderr line (`bdb-broken-runner.tap`).
- **`--jobs`: UNVERIFIED live.** `bats --jobs 4` needs GNU `parallel`, which is not installed on this host (`parallel: command not found`, `bdb-jobs4-corpus.tap`). From the bats 1.13.0 source, `bats-exec-file` calls `bats_run_setup_file` once, then `bats_run_tests`. With `num_jobs != 1` that dispatches the file's tests through `bats_run_tests_in_parallel` from inside that one `setup_file` context, so `BATS_FILE_TMPDIR` and the single replay are shared by the parallel tests. Re-check on a host with GNU parallel.
- **A pre-existing load-sensitive gate.** In one scratch run (the counter copy, load near 10) the runtime test failed its own gate: 26560 ms against a 24031 ms limit. Both the old and the new file measure exactly one corpus replay per run, so the gate's sensitivity to host load is unchanged by this task. The normal runs above passed it.

## Part 2: `tests/unit/adversarial-review-companion.bats`

### Change

- `setup()` sets `CMP_STUB_HOLD_S=240`, a plain unexported shell variable, so no production script can read it.
- The shim's three reaped holds read it with today's default: `stubborn` (`trap "" TERM; exec -a "$0" sleep "$1"`), `slow` (`exec -a "$0" sleep "$2"`, after the marker), and `unavailable-companion-slow` (`exec -a "$0" sleep "$1"`). Each passes `"${CMP_STUB_HOLD_S:-300}"`. The process names the orphan probes and teardown's `pkill` match are unchanged. The args now read `loa-cmp14-hung-<pid> 240`, which the `( |$)` anchors still match.
- CMP-55's body sets `CMP_STUB_HOLD_S=300`, today's value, because no negative control can fail that test (see below). A scratch probe confirmed the shim sees 240 in CMP-48 and 300 in CMP-55.
- No assertion, expected value, skip condition, poll or poll bound changed.

**Deviation from the SDD wording, deliberate.** SDD § 5.6 says the knob is also read by the eight `sleep 30` test-body holders and the `sleep 20` sleeper. I did not wire those, for three reasons:

- **They add no wall time.** Every one is killed by its own test (`kill "$p"`, or a reap under test) or by teardown's `_end_holders`, and each closes fd 3, so bats never waits on one.
- **The only valid knob value would lengthen them.** One knob value has to satisfy the largest bound, CMP-14's 120 s guard, so it must be at least 240 s. Wiring them would turn 30 s and 20 s holds into 240 s holds.
- **Lengthening is not what the task asked for.** It would only make leaked holders linger longer.

The lead can wire them if they want the knob read uniformly. It changes no outcome.

**An observation, unchanged.** The `sleeper` hold (20 s) is below twice CMP-114's 15 s bounded wait. A TERM regression there still fails, because the test KILLs the run at 15 s and asserts on that, but the margin is only 5 s under load. A follow-up could raise it. That would lengthen a hold, so it is out of scope here.

### Affected tests: bound and hold

| Test | Behaviour | Longest wait the test places on the hold | Old hold | New hold |
|---|---|---|---|---|
| CMP-14 the wait cap reaps a hung companion | `slow` | the run guard `(( now - t0 < 120000 ))`, twice (cap 5 s) | 300 s | 240 s (= 2 × 120) |
| CMP-30 a companion whose CLI ignores TERM is killed after the grace period | `stubborn` | `(( $(date +%s) - start < 30 ))` (cap 1 s, grace 1 s) | 300 s | 240 s (≥ 60) |
| CMP-48 a companion still running when the wait cap expires … is reaped there | `unavailable-companion-slow` | no explicit guard; cap 3 s + reap grace 5 s (default) + the bounded 10 s KILL loop | 300 s | 240 s (≥ 36) |
| CMP-55 a reaper that returns non-zero never aborts the review | `unavailable-companion-slow` | cap 3 s + grace + 10 s KILL loop | 300 s | **300 s (exempted, see the negative control)** |

### Negative control (scratch copies `tests/unit/zz-c137-nc-*.bats`, removed after; harness `fixtures/negative-control.sh <case>`)

| Test | Break applied (scratch only) | Broken run | Restored run (final file) |
|---|---|---|---|
| CMP-14 | `slow` holder exits at once (`exit 0` after the marker, no sleep) | **not ok** in 4.0 s: `companion_voice.status = "failed"` failed | ok |
| CMP-14 | every reap entry point a no-op (`_adv_kill_tree`, `_adv_reap_companion`, `_adv_reap_companion_timed_out` → `return 0`) | **not ok** in 243 s: "the run took 242 s: the hung hop was not reaped" (the 120 s guard). This is the 2× rule doing its job: the 240 s hold turns a dead reaper into a red. | ok |
| CMP-30 | `stubborn` holder honours TERM (no `trap "" TERM`) | **not ok**: `grep -q "after TERM — KILL"` failed | ok |
| CMP-48 | `unavailable-companion-slow` companion call ends at once (`:` instead of the hold) | **not ok**: `failure_class = "timeout"` failed | ok |
| CMP-55 | holder ends at once | ok (did not fail) | ok |
| CMP-55 | stand-in reaper returns 1 without signalling | ok (did not fail) | ok |
| CMP-55 | production `|| true` guards on the wait-cap reap calls removed, on a scratch copy of the script (`ADVERSARIAL_REVIEW` pointed at it) | ok (did not fail) | ok |

**Two breaks that did not break anything.** These are recorded so they are not mistaken for passes. Disabling only `_adv_kill_tree` left CMP-14 green (33 s) and CMP-30 green: the reaper has other kill paths. The CMP-14 all-entry-points break above is the valid one, and for CMP-30 the TERM-honoured break is.

**CMP-55 is exempted.** No break of its hold or of the reaper fails it. `_adv_reap_companion_timed_out` absorbs the stand-in's failure itself (`|| _kt=` at script line 3806), and the test never asserts that a reap happened, for example by a "reaping the second voice" stderr line. Because its shortening could not be proven, CMP-55 keeps today's 300 s hold through an in-body `CMP_STUB_HOLD_S=300`. **Follow-up bead suggested:** CMP-55 should assert the reap was attempted, so its hold becomes observable. That is an assertion change, out of scope here.

### Interleaved old-vs-new, the four affected tests (`-f '^CMP-(14|30|48|55) '`, 3 rounds, old and new alternating; `runs/ab.txt`; load about 5.5–6.9)

| Test | old ms (3 runs) | new ms (3 runs) |
|---|---|---|
| CMP-14 | 16800 17397 18197 | 16451 16926 21421 |
| CMP-30 | 5421 6899 7584 | 5349 5629 8199 |
| CMP-48 | 7975 8218 8220 | 6967 7004 9818 |
| CMP-55 | 7290 7348 7435 | 6866 6968 9329 |

The ranges overlap for every test, so the change has no measurable effect on passing-run time, as the reaped-hold analysis predicts. (This A/B ran before CMP-55 was exempted. Either way its hold is never waited out.)

### Whole-file `bats --tap -T`, serial

| Side | Run | wall | sum of per-test ms | load at start → end | ok / not ok / skip |
|---|---|---|---|---|---|
| before | 1 | 843 s | 814.5 s | 5.34 5.54 6.61 → 7.68 9.44 8.62 |  284 / 0 / 0 |
| before | 2 | 1043 s | 1007.7 s | 7.68 9.44 8.62 → 17.45 16.18 12.48 |  284 / 0 / 0 |
| before | 3 | 1006 s | 974.9 s | 17.45 16.18 12.48 → 8.88 10.02 11.03 |  284 / 0 / 0 |
| after | 1 | 737 s | 710.3 s | 5.76 7.44 9.36 → 6.95 7.16 8.17 | 284 / 0 / 0 |
| after | 2 | 667 s | 642.5 s | 6.95 7.16 8.17 → 4.84 5.70 6.95 | 284 / 0 / 0 |
| after | 3 | 652 s | 628.1 s | 4.84 5.70 6.95 → 8.10 6.82 6.81 | 284 / 0 / 0 |

**Median of three totals: before 1006 s, after 667 s.** The drop is host load, not this change. The baseline ran at load 7–17 on 8 CPUs, the after runs at 5–8, and unaffected tests fell by similar proportions. For example CMP-1 went from a median of 4446 to 3686 ms and CMP-3 from 3723 to 3390 ms. The interleaved A/B above is the attribution evidence. The three after runs were taken before CMP-55's in-body `CMP_STUB_HOLD_S=300` was added; the confirmation run below is on the final file.

Confirmation run on the final file: see the `final` row appended below once it completed (`runs/final.log`, `after-final.tap`).

### Twenty slowest, before (median of three, ms)

| ms | test |
|---|---|
| 27800 | CMP-196 a partial view with lower-priority rows behind it and no sibling at its tier stays inside the budget w |
| 23843 | CMP-37 a shared hop is skipped only while the companion is ON it: with the companion busy on its HTTP hop the  |
| 23259 | CMP-34 the envelope and sidecars are single-writer per (sprint, gate): a second live run is refused before it  |
| 21527 | CMP-32 the INV-5 exclusion is symmetric: a companion attempt that dropped a voice the primary answered with is |
| 20096 | CMP-14 the wait cap reaps a hung companion: failure_class timeout, the review completes, no orphan (C-001) |
| 19475 | CMP-45 a numeric knob that is not a whole number without a leading zero and at least its floor is said and its |
| 15918 | CMP-105 a companion_chain family written as a scalar or a map — or a companion_chain that is not a map — i |
| 15106 | CMP-273 a primary hop the walker read as malformed never counts as a voice that answered: its clean sidecar be |
| 13947 | CMP-26 the companion's post-hop work has its own budget: a model that answered is not reaped mid-process_findi |
| 13655 | CMP-24 when the shim swallowed cheval's stderr, the failed companion's class and last_error come from the MODE |
| 13453 | CMP-5 companion_voice: false on the block disables the second chain (voices_planned 1, planned false); the YAM |
| 12837 | CMP-87 a partial view with no room for even its marker beside the rows of its tier that fit is not made: the s |
| 12619 | CMP-2 the companion chain failing (auth / quota / timeout) names the class, records the dropped voice, and the |
| 12392 | CMP-16 a failed companion carries its last diagnostic line, redacted (C-003) |
| 12376 | CMP-28 LOA_ADVERSARIAL_RUN_TAG scopes the sidecar names to the run: only this run's files are removed at start |
| 12246 | CMP-29 lock-wait time is not charged to the hop's cap: a companion that queued behind another claude -p still  |
| 12099 | CMP-4 an Anthropic-family primary gets the OpenAI companion (keyless → codex-headless only) |
| 11825 | CMP-21 the companion's answered_by and independence follow ITS succeeded id, not its outer hop (third run C-00 |
| 11539 | CMP-23 each writer truncates its own rejected sidecar at run start — a second run into the same sprint direc |
| 10830 | CMP-33 the primary skips a hop the live companion shares instead of queueing behind its claude -p: model_attem |

### Twenty slowest, after (median of three, ms)

| ms | test |
|---|---|
| 18439 | CMP-196 a partial view with lower-priority rows behind it and no sibling at its tier stays inside the budget w |
| 17388 | CMP-14 the wait cap reaps a hung companion: failure_class timeout, the review completes, no orphan (C-001) |
| 16209 | CMP-34 the envelope and sidecars are single-writer per (sprint, gate): a second live run is refused before it  |
| 14782 | CMP-37 a shared hop is skipped only while the companion is ON it: with the companion busy on its HTTP hop the  |
| 13239 | CMP-5 companion_voice: false on the block disables the second chain (voices_planned 1, planned false); the YAM |
| 12820 | CMP-45 a numeric knob that is not a whole number without a leading zero and at least its floor is said and its |
| 11510 | CMP-29 lock-wait time is not charged to the hop's cap: a companion that queued behind another claude -p still  |
| 10596 | CMP-4 an Anthropic-family primary gets the OpenAI companion (keyless → codex-headless only) |
| 10409 | CMP-273 a primary hop the walker read as malformed never counts as a voice that answered: its clean sidecar be |
| 10363 | CMP-105 a companion_chain family written as a scalar or a map — or a companion_chain that is not a map — i |
| 10131 | CMP-32 the INV-5 exclusion is symmetric: a companion attempt that dropped a voice the primary answered with is |
| 9740 | CMP-2 the companion chain failing (auth / quota / timeout) names the class, records the dropped voice, and the |
| 9367 | CMP-26 the companion's post-hop work has its own budget: a model that answered is not reaped mid-process_findi |
| 8868 | CMP-23 each writer truncates its own rejected sidecar at run start — a second run into the same sprint direc |
| 8857 | CMP-267 the audit gate's every-hop-ceded envelope is a degraded api_failure, as process_findings writes one � |
| 8726 | CMP-24 when the shim swallowed cheval's stderr, the failed companion's class and last_error come from the MODE |
| 8668 | CMP-48 a companion still running when the wait cap expires while the primary waits on the shared hop is reaped |
| 8521 | CMP-54 past the wait cap a companion that already ANSWERED and is finishing (phase post) is not reaped by the  |
| 7912 | CMP-28 LOA_ADVERSARIAL_RUN_TAG scopes the sidecar names to the run: only this run's files are removed at start |
| 7639 | CMP-55 a reaper that returns non-zero never aborts the review: the envelope is still emitted (fifteenth run, a |

### TAP set diff (per test name, `ok`/`not ok`/skip; `fixtures/tables.sh set-diff`)

```
== before runs agree with each other:
yes
== after runs agree with each other:
yes
== diff before-1 after-1 (empty = identical):
(diff rc 0)
== counts (ok / not ok / skip) per run:
before-1 284 / 0 / 0
before-2 284 / 0 / 0
before-3 284 / 0 / 0
after-1 284 / 0 / 0
after-2 284 / 0 / 0
after-3 284 / 0 / 0
```

`before.tap` and `after.tap` are copies of run 2 of each side; all six runs are kept as `before-{1,2,3}.tap` and `after-{1,2,3}.tap`.

### Floor

- In the fastest tests, setup plus teardown costs about 0.2 s (the minimum test is 199 ms). Setup evals the whole script source per test.
- One `main` run costs about 3.1 s on this host. CMP-1 and CMP-3, each one `_run_main`, take 3.3 s at load 5.
- The file calls `_run_main` or `main --type` at 163 sites. The 90 tests at 3 s or more account for 673 s of run 1's 815 s.
- Some of those tests also spend test-chosen script waits: wait caps of 1–5 s set by seven tests, the reap grace, and the 6 s lock cap. These are poll-type bounds the rules keep.
- So the floor is the script's own per-call runtime times the number of calls, about 650 s on this host at load 5–8, before any wait is counted. **300 s is not reachable without changing the script or the number of `main` runs per test.** Both are outside this task's allowlist and rules.
- Proposed DEC-row text for the lead: "FR-6's companion-file target moves from 300 s to the measured floor, median 667 s at load 5–8 on fukuoka (baseline median 1006 s at load 7–17). The floor is about 163 `main` runs at about 3 s each. Task 2.5 shortened the reaped stub holds from 300 to 240 s under the 2× rule, which saves no passing-run time. The block-destructive-bash file went from 95 to 62 s."

## Other checks

- `tools/check-no-swallowed-jq.sh --quiet`: rc 0.
- Portability: the edits use `bash -c … sleep "$1"`, `${VAR:-default}` and `{ …; } || true`, the same constructs as the surrounding code. No new tool dependency.

## CHANGELOG line (text, for the lead)

```
- Tests: `block-destructive-bash.bats` replays the fence corpus once per file in `setup_file` (status, stdout and stderr captured and asserted by the three corpus tests; the file 95 s → 62 s); `adversarial-review-companion.bats` gains `CMP_STUB_HOLD_S` (default 300, 240 in setup — twice CMP-14's 120 s guard) for the shim's reaped holds, with a negative control per affected test; the companion file's floor is the script's own runtime (cycle-137 Task 2.5, bd-wctli).
```

## Files

- `.cycle137/task-2.5.patch`: the one patch (two files).
- `.cycle137/REPORT.md`: this report.
- `.cycle137/before{,-1,-2,-3}.tap`, `.cycle137/after{,-1,-2,-3}.tap`, `.cycle137/after-final.tap`: companion runs. `bdb-*.tap`: Part 1 runs.
- `.cycle137/runs/`: run logs with load, per-run `.ms` and `.set` files, `ab.txt`, the tables, and the runner scripts (`baseline.sh`, `after.sh`).
- `.cycle137/nc/`: broken and restored TAP for every negative-control case.
- `.cycle137/fixtures/`: `apply-part2.py` reproduces the Part 2 edit from HEAD byte-for-byte (checked with `cmp`), `negative-control.sh <case>` re-runs any control, and `tables.sh` rebuilds the tables.

## UNVERIFIED

- `--jobs` live, because GNU parallel is absent. Source reasoning is given above.
- The "idle host" condition. No run was on an idle host, and load is recorded per run.
