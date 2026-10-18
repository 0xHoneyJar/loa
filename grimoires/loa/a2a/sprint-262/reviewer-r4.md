# Sprint 262 R4 report: ablation-report.py 1.2.1 (five dissent findings)

Worktree `/home/merlin/Documents/thj/code/loa-wt-s5r4` at `82c5cd7d`. Patch `~/.cache/loa/cycle-130/patches/s5-r4.patch` (+ `.stat`). Files: `evals/harness/ablation-report.py`, `evals/tests/ablation-report.bats`, `evals/tests/fixtures/ablation-report/gen-fixtures.py`, this copy at `grimoires/loa/a2a/sprint-262/reviewer-r4.md`. No commit, no docker, no model call. The lead's checkout was only read.

## What was built (evals/harness/ablation-report.py, 1.2.0 → 1.2.1)
- `:191` VERSION 1.2.1. Header `:61-75` (version keys, version-less listed rows), `:147-156` (batch-record attribution, tally order, never-fatal), exit 2 wording `:170`.
- Finding 3: `version_key()` `:843` never returns None for a real number. `version_order()` `:878` sorts numeric keys numerically, the rest after, lexically. `version_value()` `:868` gives the JSON `primary_suite_version`.
- Finding 4: `list_reason()` `:887` holds the listing checks of `Analysis._classify` (which now calls it, `:498`). `applies_to()` `:461` is shared. `partition()` `:905` returns version-less rows that would be listed. `build()` appends them to the primary version's listed rows `:1531`.
- Findings 1 and 2: `batch_record()` `:1061` wraps `batch_status()` `:1090` (the former inline STATUS.json code, unchanged) and `grader_tally()` `:1176` in `try/except Exception`, with a note in `batches[].note`. `run_dir_of()` `:1137` resolves one directory per row. `grader_key()` `:1170` is type-stable. The tally keeps an unsorted copy when the sort fails. Rendering goes through a buffer `:1679` and prints "Not rendered (…)" on failure. The grader cell shows the note.

## Rules as built
- **Version key.** `2`, `2.0`, `"2"` and `" 2.0 "` key to `"2"`. A non-integer finite number keys to its shortest round-trip form, so `2.1` and `"2.10"` key to `"2.1"`. Another string keys to itself, stripped (`"v2"`). Absent means None, a boolean, an empty or blank string, or a non-number non-string. `--suite-version` uses the same rule.
- **Order.** Numeric keys go by value, the rest after, lexically. The primary is the maximum.
- **Version-less rows among two or more versions.** A row `list_reason` would list (no manifest, smoke batch, arm not run, unknown or inapplicable type) is listed under the primary version with the reason `no suite_version; <reason>`. It never joins a group, so it touches no figure. Any other version-less row still exits 2 with the same message. With one version or none, the behaviour is unchanged.
- **Run directory per row.** The choice goes in this order:
  1. The highest `<task>-t<n>-r<k>` whose `meta/pipeline.json` run_id equals the row's.
  2. Else the highest `-r<k>` that has a `grade.json`.
  3. Else `<task>-t<n>`.
  4. Else none: counted `n/a` and in `run_dirs_missing`.
  Each row counts once, so a tally sums to `trials_rowed`.
- **Tally order.** `(name == "n/a", [(0,int,"") | (1,0,text) per dotted segment])`. This gives 1.2.0 < 1.2.0-rc1 < 1.2.11, with dev and n/a last.

## Real-data proof (165 rows, snapshot `/tmp/r4real/runs.jsonl`, `--manifests …/ablation-2.0/batches --cuts …/cuts.json`)
Old 1.2.0 vs new 1.2.1 `report.json`:
```
h1 a4 decisions sensitivity arms exclusions cap_failures cuts listed absent budget_matched
by_suite_version primary_suite_version expected_false_positives provenance: identical
batches[]: identical except grader_versions (below) and the new key note (null everywhere)
```
Grader tally before/after:
```
priority-p1     before 1.2.2 ×7, 1.2.3 ×38, 1.2.4 ×85, 1.2.5 ×2, n/a ×134   after 1.2.2 ×7, 1.2.3 ×38, 1.2.4 ×85, 1.2.5 ×2 (132), missing 0
priority-v2-p1  before 1.2.11 ×24                                           after 1.2.11 ×24, missing 0
priority-v2-p1b before 1.2.11 ×9, n/a ×3                                    after 1.2.11 ×9, missing 0
```
The markdown diff covers only the version line and those two table cells.

## Tests added (`ablation-report.bats`; scenarios in gen-fixtures.py `:68`, `:341-375`)
All four new cases fail on 1.2.0 and pass on 1.2.1. This was checked by running the new bats file against the 1.2.0 script.
- **AR-36** (graders, gr-mixed). The report is written with no traceback. The tally reads `1.2.0=1,1.2.0-rc1=1,n/a=1`, and the table cell matches. On 1.2.0 the run aborts with a TypeError.
- **AR-37** (graders, gr-rerun and gr-missing).
  - The rerun row reads r2 (run_id match) once, as `1.2.11=1` with 0 missing. It beats r3, which has a higher grade (9.9.9) under another run_id.
  - The row without a directory reads `n/a=1` with 1 missing.
  - Every tally sums to its rows.
  - With the r2 run_id changed, the highest graded rerun is read (`9.9.9=1`).
- **AR-38** (versions-float).
  - Keys are `2,2.1` and the primary is 2.1. Each version has 12 a1 rows, and the catch d is 0.222 for 2.1 and 0.444 for 2.
  - `--suite-version 2.0` selects 2, and `2.1` selects 2.1. `2.2` exits 2.
  - A suite_version of `true`, `""` or `"  "` on a scored row exits 2 as "has no suite_version".
- **AR-39** (legacy, which is the versions scenario plus a version-less smoke row and an unbatched row).
  - The run exits 0. Both rows are listed under the primary version with `no suite_version; smoke batch leg-smoke` and `no suite_version; no manifest for batch leg-loose`.
  - h1, a4, decisions and the v1 decisions are byte-equal to the versions report.
  - A version-less scored row exits 2.
- **AR-32 literals changed.** These literals encoded the old rule. Rows without a directory now count `n/a`. `pr-2` changes from `1.2.11=1,1.2.5=1,n/a=1` to `n/a=16`, and the cell from `n/a ×1; no run dir ×15` to `n/a ×16; no run dir ×15`. The other 15 rows have no directory. `run_dirs_missing` stays 15. No other AR literal changed.

## bats counts
| run | before | after |
|---|---|---|
| ablation-report.bats | 35/35 | 39/39 |
| evals/tests/ | 431/431 | 435/435 |

## DECISION bullets
- DECISION: a row whose run directory is absent counts `n/a` in the tally and also in run_dirs_missing, so the tally sums to the rows. The brief's test asks for "n/a ×1 and run_dirs_missing 1". This changes AR-32's `pr-2` literal from n/a=1 to n/a=16.
- DECISION: a non-integer number keys to `repr(float)`, the shortest round-trip form, not `format(v, "g")`. The two agree on every short version, and `g` would merge 2.1234567 with 2.1234568. A numeric string goes through the same rule, so `"2.10"` keys to `"2.1"` and `"1e3"` to `"1000"`. A non-finite value keeps its text.
- DECISION: a value that is neither a number nor a string (a list, a dict) stays absent, as in 1.2.0.
- DECISION: JSON `primary_suite_version` is an int for an integer key and a float for another numeric key (2.1). A non-numeric key stays a string, and "n/a" stays null. The integer case is unchanged.
- DECISION: the listing test reuses `_classify`'s own listing logic, moved into `list_reason`. Excluded-status rows enter cells and weigh on the excluded share, so a version-less excluded row still exits 2. The listing reason reads `no suite_version; <the listing reason>`, so the original cause stays visible.
- DECISION: version-less listed rows go only into the primary version's main listed rows. They are not added to that version's row list, which keeps the row count, batches, sha drift and task_defects of the version unchanged.
- DECISION: the never-fatal wrapper catches `Exception` per batch around the STATUS.json part and the grader tally separately, and around rendering. A failure leaves a note in `batches[].note` and in the grader cell. An unsorted partial tally is kept.

## Could not do / limitations
- The never-fatal wrapper has no bats case, because after the fixes no planted input reaches it. It was checked ad hoc by patching `grader_tally` to raise; the result was a note and no abort.
- A rerun directory whose pipeline.json run_id matches but has no grade reads n/a, even when the base dir is graded. This is by the brief's order.

## Handoff notes
- Apply the patch, then regenerate the real report. Only the version line and the priority-p1 and priority-v2-p1b grader cells move.
