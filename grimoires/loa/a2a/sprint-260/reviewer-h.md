# Sprint 260 implementer H — Task 3.8 `ablation-report.py` (AC-3.10)

Worktree `/home/merlin/Documents/thj/code/loa-wt-s3h` at `ba11b860`. Patch `~/.cache/loa/cycle-130/patches/s3-h.patch` (3 new files plus this report's copy).

## What was built
- `evals/harness/ablation-report.py` (new; stdlib plus `yq` for the YAML suite, as `arms-report.py` does; header doc at lines 1–104). Key points: `load_rows` :265 is the schema gate, `_classify` :424 sorts rows, `bootstrap` :191 and `mde` :201 hold the statistics, `compare` :493 does the pairing, `decide` :581 applies the predicates in order, `arm_report` :614 adds cuts and the power state, `build` :714 renders both outputs.
- `evals/tests/ablation-report.bats` (new, 21 cases) and `evals/tests/fixtures/ablation-report/gen-fixtures.py` (new; four planted scenarios, every planted number listed in its header).

## Interface as built
```
ablation-report.py --runs F [--runs F ...] --manifests DIR [--manifests DIR ...] --suite F --out report.md
                   [--json report.json] [--seed 20261015] [--resamples N] [--level L]
                   [--exclude-degraded true|false] [--partial] [--cuts F] [--not-run CSV]
```
- **`--resamples` and `--level`** default to `rules.bootstrap` (10000 and 0.90). Any other value is marked `NOT the pre-registered …` in the header.
- **`--cuts F`** takes a JSON list of `{arm, reason, figure[, state]}`. `arm` is an id or a label. `state` is `not_run_cut` (the default) or `inconclusive_by_power`.
- **`--not-run`** takes a comma list of ids or labels and marks each one Not run (cut).
- **Exit codes:**
  - 0: written.
  - 1: `--partial` and no comparison among A2–A7, H1 and A4 has a valid pair on every primary it uses. The report is still written.
  - 2: usage error, unreadable input, a row or manifest with an unknown schema major, a missing `schema_version`, a non-JSON line, two manifests for one batch, an `arm_map` disagreeing with a row, a cut naming an unknown arm, an output path that is a symlink, or no MANIFEST.json under the directories.
- **report.md sections:** a header with suite_version, source commits, suite manifest sha256 (`DRIFT` when several), image digests, cli_version, the batches with shuffle_seed, pre_registration_ref and smoke flag, and the PARTIAL line under `--partial`. Then Decisions (A2–A7 rows, the A8 `component-absent` row, the H1 and A4 lines, the false-positive sentence), Per-arm detail for A0–A7 (AC-8.2), Exclusions with cap failures and never-decided rows, Cuts, the labelled Sensitivity figure, Rows per cell with collapsed run_ids, and Method quoting the `rules:` block verbatim.
- **`--json`** is the same numbers, `schema_version: 1`, rounded to 6 decimals.
- The copy at `grimoires/loa/a2a/sprint-260/reviewer-h.md` is gitignored (`grimoires/loa/a2a/*`), so it is in the worktree but not in the patch.

## Tests added (`evals/tests/ablation-report.bats`, 21 new cases; none existed before)
- AR-1 the five rule branches. AR-2 the threshold rows: d −0.03 is Remove at c −15 and Simplify at similar cost; hi = 0 is not Keep; w −15 is Remove.
- AR-3 a cap failure scores 0 although its row holds 0.9, is listed, and the sensitivity figure differs. AR-4 a degraded cell leaves both arms; `--exclude-degraded false` counts it.
- AR-5 11/36 excluded reads Inconclusive-by-degradation. AR-6 the primary list per arm; a refused A4 review-catch row is listed, not counted.
- AR-7 rc-01's 8 defects weigh 8 (n 18, d −0.222) and 1 in also_report (n 4, d −0.125). AR-8 agent_error scores its tree.
- AR-9 Not run (cut) from `--cuts` and `--not-run`, and a pre-declared power cut. AR-10 Inconclusive-by-power from a high-variance arm.
- AR-11 H1 established and not; A4 holds and fails. AR-12 the false-positive sentence; the Method block equals the suite text byte for byte.
- AR-13 smoke rows never decided. AR-14 `--partial` header with exits 0 and 1. AR-15 a schema_version 2 row, a missing one or a non-JSON line exits 2 naming file:line.
- AR-16 byte-identical for one seed. AR-17 A8 evidence. AR-18 header citations and collapsed run_ids. AR-19 usage and provenance errors; only `--out`/`--json` written.
- AR-20 the planted rows pass `ablation-row.sh --validate`. AR-21 a rerun supersedes an excluded row in its cell.
- Mutation check (script edited, then restored): Keep inclusive, no rounding and a strict cost test each fail AR-2; cap not 0 fails AR-3; no control drop fails AR-4; one weight per task fails AR-7.

## bats counts
| | `evals/tests/` |
|---|---|
| before (ba11b860) | 328/328 |
| after | 349/349 (328 + 21) |

## DECISION bullets
- DECISION: Bootstrap: percentile bootstrap of the mean paired difference, 10000 resamples via `random.Random(seed).choices`, a fresh generator per interval so partial and final reads agree; [lo, hi] = 5th/95th percentiles with linear interpolation; d = mean of the paired differences.
- DECISION: MDE = (z(0.95) + z(0.90)) × sd / sqrt(n) ≈ 2.926 sd/√n (sample sd; n < 2 → n/a), the textbook paired formula rather than the brief's 3.29 approximation; the bootstrap half-width is printed too.
- DECISION: A computed MDE > mde_cut overrides only Remove/Simplify (null results) to Inconclusive-by-power; a pre-declared power cut comes via `--cuts` with `state: inconclusive_by_power`.
- DECISION: Predicates run in the suite's literal order, so the 25 % guard cannot preempt Investigate/Keep (DEC-0393 says "whatever its interval"; lead's call).
- DECISION: "No valid pair" = any applicable primary with zero pairs, checked after Investigate/Keep on the paired ones.
- DECISION: Predicates compare values rounded to 9 decimals (−0.030000000000000027 reads −0.03).
- DECISION: Excluded = rules.exclusion.statuses + transport_error + infrastructure_error (DEC-0417), the `degraded: true` flag (`--exclude-degraded`, default true), ungraded scoring rows and unknown statuses.
- DECISION: Pairwise drop is per task-trial index; trials absent in one arm (cut ladder) are not dropped from the other.
- DECISION: A cell with several rows uses the last valid row; superseded and duplicate rows are listed; a run_id repeated across files keeps its last row.
- DECISION: Excluded share = fully excluded cells / cells seen (not planned); refusals, smoke and unmanifested rows do not count.
- DECISION: Rows with no batch manifest, and rows of a `smoke: true` manifest, are listed and never decided; an `arm_map` conflict exits 2.
- DECISION: Defect identity comes from a row's `defects_missed`/`recall.missed` when present, else every defect takes the row's catch rate (weight kept, within-task variance lost); the defect count is the task's largest `defects_seeded`.
- DECISION: c and w use per-task means over the cells the primaries paired; cap-failure runs keep their cost.
- DECISION: Expected false positives print as 0.3 per direction (0.6 two-sided, DEC-0399's figure).
- DECISION: The suite YAML is read with `yq -o=json` (as `arms-report.py`); Method quotes the raw `rules:` text.
- DECISION: The sensitivity table excludes cap failures pairwise (counted in its share) and shows the unused predicate outcome.

## Could not do / limitations
- The per-defect bootstrap is exact only when rows carry `defects_missed`. Today's row writer does not emit it, so on real rows it uses the rate fallback described above.
- The excluded share is over seen cells, not planned cells.
- Real smoke rows were run as a sanity check through a temporary manifest with `batch: unbatched`. All of them are ungraded, so they are excluded as `ungraded`, and with `--partial` the run exits 1.

## Handoff notes for the lead
- Partial read after the priority batch (Task 3.6):
```
python3 -I evals/harness/ablation-report.py --runs grimoires/loa/reports/ablation-2.0/runs.jsonl \
  --manifests evals/results/ablation-2.0 --suite evals/suites/ablation-2.0.yaml --partial \
  --out grimoires/loa/a2a/sprint-260/partial-report.md --json grimoires/loa/a2a/sprint-260/partial-report.json
```
  Point `--manifests` at the directory that holds the priority batch's MANIFEST.json, and add `--cuts F` once cuts are recorded. Read the `H1:` and `A4 sensitivity:` lines and their intervals.
- Final report:
```
python3 -I evals/harness/ablation-report.py --runs grimoires/loa/reports/ablation-2.0/runs.jsonl \
  --manifests evals/results/ablation-2.0 --suite evals/suites/ablation-2.0.yaml --cuts <cuts.json> \
  --out grimoires/loa/reports/ablation-2.0/report.md --json grimoires/loa/reports/ablation-2.0/report.json
```
  `--seed 20261015`, `--resamples 10000` and `--level 0.90` are the defaults.
- Suggested Sprint 261 follow-up: `ablation-row.sh` should carry grade.json `recall.missed` as a `defects_missed` row field. The report already reads it.
- Whether the excluded-share guard should preempt Investigate and Keep, per DEC-0393's "whatever its interval", is the lead's call. Changing it is a two-line move in `decide`.

## Addendum: degradation guard first
- `decide` now applies the degradation guard first, ahead of investigate, keep, inconclusive, remove and simplify. An excluded share above `rules.exclusion.inconclusive_above_share` (0.25) returns `inconclusive`, labelled Inconclusive-by-degradation, whatever the interval. The rule line reads `inconclusive (degradation guard, evaluated first): excluded share … > 0.25`. "No valid pair" stays in the inconclusive step. The header's "Decision per arm" paragraph and the Method text say the same.
- The fixture's A5 in the exclusions scenario now plants +0.05 with lo > 0 on its valid cells and 11 of 36 cells excluded. AR-5 asserts Inconclusive-by-degradation. The new AR-22 shifts the same arm to −0.10 with hi < 0, a Keep interval, and asserts Inconclusive-by-degradation. AR-1 still passes.
- bats: `ablation-report.bats` 22/22; `evals/tests/` 350/350.
- Delta over the applied patch: `~/.cache/loa/cycle-130/patches/s3-h2.patch` (stat `s3-h2.stat`).
- DECISION: The degradation guard (excluded share > 0.25 → Inconclusive-by-degradation) is evaluated before investigate and keep, per DEC-0393 and the lead's Sprint 260 ruling. This supersedes the earlier bullet on the suite's literal order. The suite's `rules.predicates` text and NOTES are amended by the lead.
