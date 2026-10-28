# ESO pass 21 - bats unit-suite runtime

## Result
One lever applied: the "PATH without tool X" symlink-farm helper, duplicated in three test files, now makes one `ln -s` per PATH directory instead of one per file (and `loa-decisions-surface.bats` no longer forks a subshell per file for the skip list). Farm contents byte-identical (ls -l of old vs new farms, md5 equal, 2239 entries). Helper cost per call: 4.6 s -> 0.1 s in isolation.

## Opportunity matrix
| Lever | Impact | Confidence | Effort | Score |
|---|---|---|---|---|
| PATH-without symlink farm (3 files, ~7 calls/suite, ~4 s each unloaded) | 2 | 5 | 1 | 10 |
| Per-test `eval` of adversarial-review.sh (setup ~35 ms of ~200 ms per test, ~300 tests) | 1 | 4 | 3 | 1.3 (no) |
| Share block-destructive corpus pass across 3 tests | 3 | 2 | 4 | 1.5 (changes semantics; no) |
| Other top files (adversarial-review-*, run-checkpoint-derive, semver-bump, post-merge-*): cost is the script under test (run-checkpoint.sh, adversarial-review.sh main, ...), not a test helper | - | - | - | none shared |

## Profile (parallel, 6 workers, host load avg 6-10 from other passes, so times are inflated; one file, adversarial-review-companion, hit my 900 s timeout and is a lower bound)
Sum of per-file wall times (contended): 6279 s over 457 files (orchestrator serial baseline 3089 s). 7112 tests parsed.

Top 20 files (s, contended):
| s | file |
|---|---|
| 900.0 | adversarial-review-companion.bats |
| 270.9 | adversarial-review-normalise.bats |
| 183.6 | charting-decisions.bats |
| 152.8 | block-destructive-bash.bats |
| 140.9 | post-merge-publication.bats |
| 137.4 | dec-write-lib.bats |
| 131.7 | scheduled-cycle-lib-3A.bats |
| 118.2 | scheduled-cycle-lib-3B.bats |
| 113.4 | semver-bump.bats |
| 111.3 | run-checkpoint-derive.bats |
| 107.9 | post-merge-orchestrator.bats |
| 87.3 | loa-decisions-surface.bats |
| 84.8 | adversarial-review-advisory.bats |
| 84.2 | implement-gate.bats |
| 73.3 | ledger-lib.bats |
| 64.0 | cycle-124-dispatch-budgets.bats |
| 60.2 | agy-gate-conformance.bats |
| 58.8 | run-preflight.bats |
| 52.4 | profile-floor.bats |
| 51.2 | flatline-scorer-availability.bats |

Top 20 tests (s, contended):
| s | file | test |
|---|---|---|
| 60.9 | cycle-124-dispatch-budgets. | c124-1.4-B9: assemble_dissent_context honours the per-company primary  |
| 50.1 | loa-decisions-surface. | decisions surface F-014: enabled but yq v4 or jq missing prints one WA |
| 44.7 | profile-floor. | PF-6 the fence decides every corpus row and the FR-1.2b / FR-SZ probes |
| 33.5 | loa-decisions-surface. | decisions surface F-014: without yq the real config is read by the pla |
| 30.2 | context-class. | CC-13 without a timeout binary an open stdin that never closes does no |
| 29.7 | adversarial-review-normalise. | NRM-22 the run's repairs share a wall-clock budget: once LOA_ADVERSARI |
| 28.6 | block-destructive-bash. | cycle-125 corpus: hook runtime over the corpus stays within 1.5× the r |
| 28.3 | check-round-independence. | RI-11f a transcript whose rounds total more than 128 KiB is checked, n |
| 28.3 | adversarial-review-companion. | CMP-34 the envelope and sidecars are single-writer per (sprint, gate): |
| 28.0 | adversarial-review-companion. | CMP-37 a shared hop is skipped only while the companion is ON it: with |
| 28.0 | block-destructive-bash. | cycle-125 corpus: every dangerous row still blocks (100 %) |
| 27.5 | adversarial-review-companion. | CMP-5 companion_voice: false on the block disables the second chain (v |
| 27.4 | block-destructive-bash. | cycle-125 corpus: benign rows pass at or above 80 % |
| 27.3 | dec-write-lib. | dec-write preflight: a missing jq or a non-v4 yq fails closed; a missi |
| 25.7 | adversarial-review-companion. | CMP-45 a numeric knob that is not a whole number without a leading zer |
| 23.7 | adversarial-review-companion. | CMP-14 the wait cap reaps a hung companion: failure_class timeout, the |
| 21.7 | adversarial-review-normalise. | NRM-20 an explicit auth (4) or quota (6) exit code retires a repair ho |
| 21.4 | red-test-check. | RTC-9 without timeout/gtimeout on PATH the bash watcher yields TIMEOUT |
| 21.4 | cycle-124-anthropic-catalog. | c124-1.3-12: tools/regen-model-artifacts.sh is idempotent (second run  |
| 21.2 | dec-write-lib. | dec-write: the hostile-string corpus round-trips byte-equal against th |

The distribution is a long tail of tests that each run a full script under test (1-3 s each). Setup/teardown of the heaviest family (adversarial-review companion/normalise): ~200 ms/test, of which source+sed+grep+eval of the 5,030-line script is ~35 ms; sweep in teardown is cheap. No shared per-test repo copy (`cp -r` of .claude only in skill-includes), `git init` fixtures are ~50 ms, real sleeps are mostly background holder processes not waited on.

## Hotspot evidence
`path_without`/`_path_without` loops over every file of every PATH dir (/usr/bin and /bin: 1,982 each, ~2,240 distinct names) forking `ln` per file (plus a `$(...)` subshell per file in loa-decisions-surface). Isolated: 3.7-4.6 s per call. Used by dec-write preflight test (3 calls), decisions-surface F-014 tests (3 calls), RTC-9 (1 call): about 25-30 s serial of the suite (~1%), more under load.

## Before/after (serial, same loaded host)
| test | before | after |
|---|---|---|
| decisions surface F-014 yq/jq missing | 25.5 s | 8.5 s |
| decisions surface F-014 plain-text fallback | 11.7 s | 4.3 s |
| dec-write preflight missing jq/yq | 10.1 s | 5.2 s |
| RTC-9 no timeout binary | 10.4 s | 8.0 s |
| file sums: loa-decisions-surface / dec-write-lib / red-test-check | 38.0 / 52.9 / 20.9 s | 13.4 / 45.9 / 18.5 s |

Suite-time estimate: about -26 s unloaded (-0.9% of 3089 s); per-file sum of 3 touched files 111.8 s -> 77.8 s measured under load.

## Isomorphism / golden
- Pass/fail/skip set per test name identical for all 3 files (diff of normalised TAP empty): loa-decisions-surface 11 ok, dec-write-lib 52 ok, red-test-check 27 ok, 0 not ok, 0 skips, before and after.
- First-PATH-entry-wins preserved by the same `-e "$d/$b"` check (earlier dirs are linked before later ones are scanned); skip list semantic (IFS=: word splitting of the joined names) preserved by hoisting the same command substitution; failure semantics preserved: decisions-surface/dec-write still swallow ln errors (`|| true`), red-test-check still lets a failing `ln` fail the test (no swallow) and keeps its dangling-link and timeout-absent assertions.
- Assertions, expected values, skip conditions untouched.
- tools/check-no-raw-sha256sum.sh and tools/check-no-swallowed-jq.sh --quiet pass.

## Files changed
- tests/unit/loa-decisions-surface.bats (_path_without)
- tests/unit/dec-write-lib.bats (path_without)
- tests/unit/red-test-check.bats (RTC-9 shim loop)

## Not fixed / notes
- No single shared lever beyond this; the suite is dominated by script-under-test cost. block-destructive-bash runs the 100-row-class corpus three times (3 tests x ~28 s contended); merging would change test structure, left alone.
- NRM-22 / PF-6 / CC-13 tests are heavy by design (function-graph walks, real timeout waits).
- The parallel run perturbed nothing visible: the only `not ok` files (block-destructive-bash, panel-disagreement-no-op-default, semver-evidence) were not re-verified against the baseline serially except that semver-evidence is a known pre-existing failure; I did not touch them.
- Skip-list: companion file timed out at 900 s under load, so its true time is higher.

## Checked and found fine
- Teardown stale-sweep (`_sweep_stale_suite_dirs`) scans only marker files, not the 360 a2a entries: cheap.
- Per-test setup eval of adversarial-review.sh: ~35 ms, not worth a cache (would change isolation).
- bats per-test overhead: 2 ms for an empty test.
