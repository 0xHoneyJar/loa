# Sprint 262 R5 report: ablation-report.py 1.2.2 (four dissent findings on 1.2.1)

Worktree `/home/merlin/Documents/thj/code/loa-wt-s5r5` at `caf55440`. Patch `~/.cache/loa/cycle-130/patches/s5-r5.patch` (+ `.stat`). Files: `evals/harness/ablation-report.py`, `evals/tests/ablation-report.bats`, `evals/tests/fixtures/ablation-report/gen-fixtures.py`, and this copy at `grimoires/loa/a2a/sprint-262/reviewer-r5.md`. No commit, no docker, no model call. The lead's checkout was only read.

## What was built (evals/harness/ablation-report.py, 1.2.1 to 1.2.2)
- `:198` VERSION 1.2.2. The header documents the provenance order, the typed version values, the rerun fallback and the never-fatal computation.
- Finding 1. `provenance_check()` `:892` is the arm_map check that moved out of `Analysis._classify`, which now calls it. `partition()` runs it on every row first `:930`, before any listing decision.
- Finding 2. `version_value()` `:870` also maps None to null and passes a non-string through. h1_json, a4_json, version_json, budget_json and batches[] emit their suite_version through it. The sensitivity h1/a4 go through h1_json and a4_json.
- Finding 3. `batch_record()`, the typed JSON copy and `render_batches()` sit in one `try` `:1712`. On failure, JSON `batches` is `[]` and the new key `batches_note` `:1801` holds the note. It is null otherwise. The markdown prints "Not rendered (…); it decides nothing."
- Finding 4. `run_dir_of()` `:1158` matches the task and compares `int(trial)` for base and rerun directories. If several base forms exist, the canonical `<task>-t<n>` wins, else the lexically first. The last fallback is the highest `-r<k>`. The grader_tally docstring defines run_dirs_missing as rows with no attributable directory.

## Rules as built
- **Provenance first.** Every row passes the manifest arm_map check before partition or listing. A version-less row whose arm_map names another arm exits 2 with the existing message.
- **Version value types.** An integer key gives an int and another numeric key a float. "n/a" gives null and any other key a string, including a "1, 2" batch list. The by_suite_version object keys stay strings.
- **Run directory order.** The choice goes:
  1. the highest rerun whose run_id matches,
  2. else the highest graded rerun,
  3. else the base directory,
  4. else the highest rerun, read as n/a and not missing,
  5. else none, counted missing.
  The trial compares numerically everywhere.

## Real-data proof (165 rows, snapshot `/tmp/r5/runs.jsonl`, `--manifests …/ablation-2.0/batches --cuts …/cuts.json`)
Old 1.2.1 against new 1.2.2 `report.json`, compared on every changed leaf:
```
1 x batches_note: <absent> -> null
1 x generator: 1.2.1 -> 1.2.2
7 x suite_version: "1" -> 1
13 x suite_version: "2" -> 2
```
- **Raw identical:** decisions, arms, exclusions, cap_failures, cuts, listed, absent, provenance, primary_suite_version, expected_false_positives, duplicates.
- **Identical once suite_version is typed:** h1, a4, sensitivity, by_suite_version, batches, budget_matched. Finding 2 requires exactly this type change.
- **Markdown:** only the version line changes.
- **Grader tallies are unchanged:** priority-p1 132, priority-v2-p1 24, priority-v2-p1b 9, missing 0 everywhere.

## Tests added (each fails on 1.2.1 and passes on 1.2.2; checked by running the new bats file against the 1.2.1 script)
- **AR-38, extended.** These assertions are typed:
  - number for primary, h1, a4, sensitivity.h1, budget_matched and by_suite_version["2.1"],
  - `[2.1,2.1,2,2,2]` across versions and `[2,2.1]` for batches,
  - string for a "v2" key,
  - null for n/a on every emitter.
  On 1.2.1 it fails at the h1 type.
- **AR-40** uses legacy-conflict and legacy-match. A conflicting arm_map exits 2 with "disagrees with …/leg-smoke/MANIFEST.json arm_map (a0_bare)" and writes no md. A matching arm_map is listed, with h1, a4, decisions, listed and by_suite_version equal to legacy. On 1.2.1 it exits 0.
- **AR-41** uses batch-broken: ver-v2's manifest suite_version is a 5,000-digit string, which int() refuses. The test expects exit 0, no traceback, the Decisions and Method sections, "Not rendered (ValueError: …)", `batches` [] and `batches_note`. h1, a4, decisions and by_suite_version must equal versions. On 1.2.1 it aborts with a traceback.
- **AR-42** uses rundirs. rc-01-t01 reads 1.2.11. The graded-less rc-01-t2-r2 reads n/a and is not missing. rc-01-t03-r02 reads 1.2.5. The JSON tally is `1.2.11=1,1.2.5=1,n/a=1` because json.dumps sorts keys. The md cell is `1.2.5 ×1, 1.2.11 ×1, n/a ×1`, and missing is 0. With the rerun removed, missing is 1.
- **AR-1 … AR-39:** no literal changed.

## bats counts
| run | before | after |
|---|---|---|
| ablation-report.bats | 39/39 | 42/42 |
| evals/tests/ | 435/435 | 438/438 |

## DECISION bullets
- DECISION: the arm_map check is a shared `provenance_check()`. `partition()` runs it on every row before partitioning, and `_classify` keeps calling it. When a row both conflicts and lacks a version, the provenance message now comes first. Both exit 2.
- DECISION: the brief's suggested plants, a non-string manifest batch or a null row batch, are rejected at load with exit 2. They never reach `batch_record()`. The bats plant is a manifest suite_version int() refuses, which only the batch record reads.
- DECISION: when the batch record fails, JSON `batches` is `[]` and a new top-level `batches_note` holds the note. It is null otherwise, so the real-data `batches` is unchanged.
- DECISION: the real-data JSON changes type on 20 suite_version fields, from "1"/"2" to 1/2. Finding 2 requires this. The proof compares the keys after typing and lists every changed leaf.
- DECISION: when several base directories match a trial, the canonical `<task>-t<n>` wins, else the lexically first zero-padded form.
- DECISION: the rerun fallback directory without a grade counts n/a and not in run_dirs_missing, as the brief says.
- DECISION: `provenance.suite_versions` stays the list of raw value strings. It is not a version key emitter.

## Could not do / limitations
- A row whose suite_version is a numeric string over 4,300 digits still aborts in partition() with a ValueError traceback. version_key is outside the four findings.
- JSON object keys of the grader tally sort lexically under json.dumps(sort_keys=True). Only the markdown shows the numeric order. This was already true in 1.2.1.

## Handoff notes
- Apply the patch, then regenerate the real report. Only the version line moves in the md. In the JSON, the suite_version values become numbers and `batches_note: null` appears.
