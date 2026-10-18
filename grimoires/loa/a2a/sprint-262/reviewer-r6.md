# Sprint 262 audit-fix R6 report: row writer 1.3 and ablation-report.py 1.2.3

Worktree `/home/merlin/Documents/thj/code/loa-wt-s5r6` (branch `wt/cycle-130-s5r6`) at `dad13df1`. Patch `~/.cache/loa/cycle-130/patches/s5-r6.patch` (+ `.stat`). Files: `evals/harness/ablation-row.sh`, `evals/tests/ablation-row.bats`, `evals/harness/ablation-report.py`, `evals/tests/ablation-report.bats`, `evals/tests/fixtures/ablation-report/gen-fixtures.py`, and this copy at `grimoires/loa/a2a/sprint-262/reviewer-r6.md`. No commit, no docker, no model call. The lead's checkout was only read (its `git status` is unchanged).

## What was built
- **Finding 1, row writer 1.3.** `ablation-row.sh:137-151` defines one jq function `missed_rule($s; $c)` in the bash variable `MISSED_RULES`. It is prepended to both jq programs, so the writer and `--validate` share one rule set. `--validate` applies it at `:189-193` on a review-catch row with a non-null list. The row program applies it at `:436-439` and writes null for a violating list. Header `:57-75` documents the rules and "Row writer version: 1.3". The `--help` range moved to `2,108p` (same end point).
- **Finding 1, report.** `missed_consistent()` `ablation-report.py:289` and its use in `defect_vector()` `:637`. An inconsistent list returns the `"rate"` vector, never `"ids"`. The budget-matched union reads `defect_vector()`, so it falls back too.
- **Finding 2.** `stage_note()` `:1152` writes `str(x)` to stderr once and returns `<Class> while <stage>`. Used by the STATUS.json and tally guards in `batch_record()` and the outer handler `:1826-1834`. `batch_record()` keeps the current stage in a dict the caller reads.
- **Finding 3.** `is_num()` `:281`, `num_of()` `:306` and `usd_of()` `:319`. Every cost read uses `usd_of`: pair costs, precision, cost_per_task, cost_per_run, the budget-matched sums and the cap-failure line. Wall-clock in pairs uses `num_of`. `nums()` skips non-finite values. `json_text()` `:1950` serialises with `allow_nan=False`. On failure it raises Fail naming the key path found by `non_finite_key()` `:1933`. `main()` builds the JSON text before writing either file `:1985`.
- **Finding 4.** `ARM_GRAMMAR` and `TASK_GRAMMAR` `:247-248`. `contained()` `:1240` refuses a symlinked component below the base and any realpath outside the batch's manifest directory. `grader_tally()` checks both grammars before a path is built. It resolves the arm directory through `contained()`, and every read in `run_dir_of()` and the tally goes through it too.
- `VERSION = "1.2.3"` `:223`. The header section "Input guards" `:179-201` and the catch-rate unit text `:98-104` document the rules.

## Rules as built
- **defects_missed (row writer 1.3).** These apply when the task is review-catch and the list is non-null. The first violated rule is named:
  1. `id grammar ^d[1-9][0-9]*$`
  2. `unique ids`
  3. `at most defects_seeded ids`
  4. `ids within d1 … d<defects_seeded>`
  5. `defects_seeded − ids == defects_caught`
  Rules 3 and 4 apply when defects_seeded is a number. Rule 5 applies when both counts are numbers. The message is `<file>:<line>: defects_missed <list> violates the rule: <rule>`.
- **Report defect identity.** Ids must be `d1 … dN` with N the task's defects. There must be no duplicate. When defects_caught is a number, N − len(ids) must equal it. Otherwise the row reads "rate".
- **Numbers.** A finite int or float that is not a bool counts. Anything else reads 0 with one stderr note per row and key. Absent or null reads 0 silently. A non-finite value reaching the JSON twin exits 2 and writes neither file.
- **Exception text.** The class plus a fixed stage phrase naming the batch, for example `Not rendered (ValueError while reading the batch record of ver-v2)`.
- **Paths.** The arm must fullmatch `^[a-z][a-z0-9_]{0,63}$` and the task_id `^[a-z0-9][a-z0-9-]{0,63}$`. A row outside either counts as `n/a`, adds to run_dirs_missing, and adds the note "N row(s) with an arm or task_id outside the grammar (no attributable directory)". No symlink is followed below the batch directory, and the realpath must stay inside it.
- **GRADE_DIR.** It is already `fullmatch` in `run_dir_of()`, its only use, so the finding's "unanchored" claim is stale. A `rc-01-t1-r2.bak` does not match. Every other regex use is anchored: `fullmatch`, or `re.match(r"^rules:")`. In 1.2.2 a task_id `../x` could not escape either, because candidate names come from `os.listdir` and contain no `/`. The task grammar is defence in depth. The arm was the real escape.

## Real-data proof
The input was the 165 tracked rows, copied to `/tmp/r6/runs.jsonl`, with `--manifests …/ablation-2.0/batches --cuts …/cuts.json`. 1.2.2 and 1.2.3 were compared on `report.json` with `jq -S 'del(.generator)'`:
```
json identical but generator   (ablation-report.py 1.2.2 -> 1.2.3)
report.md: only line 3 (the version) differs; stderr empty
ablation-row.sh (1.3) --validate: 165 rows valid
```
Every real review-catch id list already satisfies the five rules.

## Tests (each new case fails on the old script and passes on the new; checked by running the new bats files against copies of the old scripts)
- **Row cases 34 to 37:**
  - Case 34: `--validate` rejects `["x1"]`, `["d2","d2"]`, four ids on 3 seeded, `["d2"]` with 1 caught on 3, `["d4"]` on 3 and `["d0"]`, naming the rule and the line.
  - Case 35: it accepts `["d2","d5"]` on 8 seeded with 6 caught, `[]` with 3 of 3, null counts, and a build row.
  - Case 36: the row program writes null for five inconsistent lists, with every other field unchanged apart from the timestamps.
  - Case 37: the 165 tracked rows validate.
  - Fails before: 34 and 36. Cases 35 and 37 are acceptance checks and also pass on 1.2.
- **Row literals changed:** cases 29 and 30 planted `["d2","d5"]` and `[]` on a fixture grade with 3 seeded and 2 caught, which 1.3 now refuses. Their grade counts are now consistent (8 seeded and 6 caught; 3 caught). The expected values are unchanged.
- **Report AR-43:** the ids-bad scenario reads `defect_identity` `ids,rate`. H1 is established as in versions, d is 0.444444 (1.2.2 read 0.222222), and budget-matched reads "rate fallback".
- **Report AR-44:** the costs-bad scenario exits 0 with no traceback. Each bad cost gets one note. report.json has no NaN token and parses strictly. The states equal versions. a0 cost_per_run is 0.916667 and a4 (v1) is 2.916667. 1.2.2 aborted with a traceback.
- **Report AR-45:** a NaN `max_usd` in STATUS.json exits 2 with `…at $.batches[1].spend.max_usd`. Neither file is written.
- **Report AR-46:** the escape scenario tallies `1.2.11=1,1.2.5=2,n/a=2` with 2 missing and the grammar note. The canary is never read and is unchanged. The symlinked `meta/` is refused. 1.2.2 read `6.6.6-canary`.
- **Report AR-47:** a grader_version containing "²" makes the tally raise. The note is `grader tally incomplete (ValueError while tallying the grader versions of pr-2)`, and the full text appears only on stderr, once.
- **AR-41 literal changed:** it now expects the exact sanitized text `Not rendered (ValueError while reading the batch record of ver-v2); it decides nothing.`
- **AR-1 … AR-40 and AR-42:** unchanged and passing.

## bats counts
| run | before | after |
|---|---|---|
| ablation-row.bats | 33/33 | 37/37 |
| ablation-report.bats | 42/42 | 47/47 |
| evals/tests/ | 438/438 | 447/447 (one run, rc 0) |

## DECISION bullets
- DECISION: the validator and the row program share one jq definition, prepended from a bash variable. This guarantees by construction that the writer never emits a list `--validate` rejects. There is no bash `eval` and no `source`.
- DECISION: added a fifth rule, "ids within d1 … d<defects_seeded>", beside the four in the brief. Without it `["d4"]` on a 3-defect task passes the writer while the report rejects it as outside d1 … dN. The 165 real rows pass it.
- DECISION: the report checks against the task's N, the max defects_seeded over its rows, which is the vector length defect_vector builds. The defects_caught cross-check uses N too.
- DECISION: the non-number note goes to stderr, not the report. The real report then stays byte-identical, and a note naming the run_id is enough to act on. `num_of` also guards pair wall-clock, the same unguarded `float()` shape.
- DECISION: cost_per_run is now the mean of `usd_of` over the valid rows, so a bad cost counts 0 as the brief says. `nums()` dropped non-numbers. Real rows always carry a numeric cost, so the number is unchanged.
- DECISION: the JSON text is built before report.md is written. With allow_nan=False the loud failure writes no half-pair, and it exits 2 through the existing Fail path.
- DECISION: an arm directory that is a symlink, or whose realpath leaves the batch directory, also counts as missing. In 1.2.2 it counted the same way through an empty listing.
- DECISION: the Method paragraph of report.md was left as is so the markdown diff stays the version line. The header documents the consistency rule.

## Limitations
- `batches[].status_file` still carries the STATUS.json path, absolute when `--manifests` is absolute, and `provenance.manifests[].manifest` carries manifest paths. Neither comes through an exception and both predate this sprint. Changing them would change the shipped report.json. They are left for the lead to decide.
- A NaN `hidden_test_pass_rate` or `defect_catch_rate` still passes `_classify`'s isinstance check. With `--json` it now fails loudly at write time. Without `--json` a NaN could reach the markdown. This is outside the brief's cost scope.
