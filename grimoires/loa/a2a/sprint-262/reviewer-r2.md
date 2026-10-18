# Sprint 262 R2 — ablation-report.py decision hardening (report)

Worktree `/home/merlin/Documents/thj/code/loa-wt-s5r2` at `d80c5c32`. Patch `~/.cache/loa/cycle-130/patches/s5-r2.patch` (+ `.stat`). Files: `evals/harness/ablation-report.py`, `evals/tests/ablation-report.bats`, `evals/tests/fixtures/ablation-report/gen-fixtures.py`, this report's copy at `grimoires/loa/a2a/sprint-262/reviewer-r2.md`. No commit, no docker, no model call; the lead's checkout was only read.

## What was built (evals/harness/ablation-report.py, 1.0.0 → 1.1.0)
- **Partition** `version_key` / `version_order` / `partition` (:767–804): rows grouped by `suite_version` (1, 1.0, "1" are one key); primary = `--suite-version` (:1343) or the highest; a row without the field among two or more versions → exit 2 naming file:line and run_id; with one version (or none) such rows join it (key `n/a` when no row carries it).
- **Per-version analysis** `analyse` (:840): its own `Analysis` pair, component decisions, H1, A4, cap failures, batches, manifest sha256s. `build` (:1059) renders the primary in the existing sections and every other version as `## Suite version N (batches: …) — reported separately, never pooled` with its own decision table, H1/A4 lines, per-arm detail and exclusions, before Method. Rendering moved into `render_decisions` (:893), `render_per_arm` (:927), `render_exclusions` (:985); output for a single version is unchanged except the header line below and two Method bullets.
- **Header**: one line per version (role, rows, batches, manifest sha256); DRIFT now means more than one sha256 within one version.
- **Read states** `assess` (:806) / `read_text` (:825): per comparison, first match: not_testable (no task of the primary's types in either arm) → inconclusive_by_degradation (either arm's excluded share over its cells on that primary's task types > `rules.exclusion.inconclusive_above_share`) → degenerate → no_pair → tested. H1 and A4 lines derive from them (:849–880). This closes bd-wqbz3.
- **Degenerate pair** in `compare` (:600): catch rate, n > 0, one paired task, no `ids` among the defect-identity modes → `degenerate: true` + `degenerate_reason`. `usable()` (:407) excludes it in `decide` (:631, clause `no valid pair (…, defect_catch_rate: degenerate)`) and in `decidable` (:697). Intervals print `(degenerate)`; the per-arm detail prints the reason.
- **Docs**: header comment covers `--suite-version`, the partition, read states, JSON keys and exit codes.

## Interface as built
- New flag `--suite-version N` (unknown version → exit 2: `--suite-version 3: no row has that suite_version (present: 1, 2)`).
- H1 lines: `H1: established` | `H1: not established — halt before promotion` | `H1: inconclusive by degradation — not established` | `H1: not yet decidable (no pair)`.
- A4 lines: `holds` | `fails — harden tasks before acting on other arms` | `inconclusive by degradation (a1_full excluded share 0.333 > 0.25) — not decided` | `not testable on suite_version N — no admissible build task` | `not yet decidable (no pair)`.
- Primary text: `hidden_test_pass_rate: not testable on suite_version 2 — no admissible task`; `defect_catch_rate inconclusive by degradation (a1_full excluded share 0.750 > 0.25); remaining pairs …`.
- Exit codes unchanged in meaning; 2 adds the two suite_version errors; `--partial` exit 1 when nothing in the primary version is decided.

## JSON schema additions (report schema_version stays 1)
- top level: `primary_suite_version` (int, or string for a non-numeric key, null for `n/a`); `by_suite_version: {"N": {suite_version, rows, batches, suite_manifest_sha256, decidable, h1, a4, decisions, arms, exclusions, listed, cap_failures}}`. Existing top-level keys describe the primary version.
- `h1`: + `state` (established | not_established | inconclusive_by_degradation | not_yet_decidable), `suite_version`; each `h1.comparisons[]` + `read`, `read_text`.
- `a4`: + `state` (holds | fails | inconclusive_by_degradation | not_testable | not_yet_decidable | no_arm), `suite_version`; `a4.comparison` + `read`, `read_text`.
- every comparison (decisions, sensitivity, h1, a4): + `degenerate` (bool), + `degenerate_reason` when true.

## Item 5: the real v1 rows alone, old vs new
`jq 'select(.suite_version==1)'` on the 132 v1 rows; both scripts with `--partial`; the JSON keys h1, a4, decisions, sensitivity, arms, exclusions, listed, cap_failures, absent, cuts, expected_false_positives are diffed after removing only the new keys:
```
v1 decision JSON identical (h1, a4, decisions, sensitivity, arms, exclusions, listed, cap_failures, absent, cuts, efp)
```
The markdown diff is the version string, the new per-version header line and the two new Method bullets.

## Real-data smoke (all 156 rows, read-only, output under /tmp/r2)
Exit 0 with `--partial`. Primary suite_version 2.
```
v2: H1: inconclusive by degradation — not established
  hidden_test_pass_rate: not testable on suite_version 2 — no admissible task
  defect_catch_rate inconclusive by degradation (a1_full excluded share 0.750 > 0.25); remaining pairs +0.133 [+0.133, +0.133] (degenerate) (n = 5 defects)
v2: A4 sensitivity: not testable on suite_version 2 — no admissible build task
v1: H1: not established — halt before promotion
  hidden_test_pass_rate -0.028 [-0.083, 0.000] (n = 12 tasks)
  defect_catch_rate -0.096 [-0.188, +0.007] (n = 19 defects)
v1: A4 sensitivity: fails — harden tasks before acting on other arms
```

## Tests added (ablation-report.bats; fixtures gen-fixtures.py scenarios versions, degraded, degraded-a4, degenerate-1, degenerate-2, degenerate-ids)
All eight fail on the old script (run in a copy of `evals/` with `git show HEAD:` of the script) and pass now.
- AR-23 two versions never pooled (same task ids and trials in both: no duplicate-cell exclusion; a1 rows 12 vs 48); v2 H1 on the catch rate, pass rate and A4 not testable; v1 section's own H1/A4; `by_suite_version` 1,2; `--suite-version 1` flips; `--suite-version 3` exit 2.
- AR-24 a row without suite_version among two versions → exit 2, nothing written; the main rows without the field → same decisions.
- AR-25 `--partial` with no pair → `H1: not yet decidable (no pair)`, exit 1, no halt phrase; a4 rows without a1 → `A4 sensitivity: not yet decidable (no pair)` (bd-wqbz3).
- AR-26 9 of 12 a1 review rows degraded → H1 inconclusive by degradation, primary text pinned; `--exclude-degraded false` → established.
- AR-27 a1 12 of 36 build cells degraded → A4 and H1 pass rate inconclusive by degradation; false → A4 holds, H1 established.
- AR-28 one task, no ids → `degenerate: true`, reason, H1 not yet decidable, a3 decision `inconclusive: no valid pair (hidden_test_pass_rate, defect_catch_rate: degenerate)`.
- AR-29 two tasks → not degenerate (established); one task with ids → not degenerate, read tested; no build comparison ever degenerate.
- AR-30 `--not-run a4_no_gates` still reads Not run (cut) in both versions while the A4 line reads not testable; `--partial` exit 0 when H1 is decided on the remaining primary.
- Literal updated: AR-14 line 210 now expects `H1: not yet decidable (no pair)` for the a0-only rows (was the halt phrase, the bd-wqbz3 defect). AR-20 validates the six new scenarios with `ablation-row.sh --validate`. No other AR-1 … AR-22 literal changed.

## bats counts
- ablation-report.bats: 22/22 before → 30/30 after.
- evals/tests/: 386/386 before → 394/394 after.

## DECISION bullets
- DECISION: the H1/A4 degradation guard uses each arm's excluded share over its cells on the primary's task types (review-catch for the catch rate, build for the pass rate and A4), not the arm-wide share the component guard uses; on today's rows both give 0.750 for v2 and change nothing on v1.
- DECISION: read order is not testable → degradation guard → degenerate → no pair → interval; a primary with tasks but every cell degraded reads inconclusive by degradation, not "no pair".
- DECISION: H1 is established by any tested primary with lo > 0 even when another primary is inconclusive by degradation; "inconclusive by degradation — not established" needs every testable primary to be inconclusive by degradation; any other no-tested case reads "not yet decidable (no pair)", including all-not-testable.
- DECISION: the A4 degradation line ends "— not decided" (neither holds nor fails, so it triggers no hardening action); a degenerate or empty A4 reads "not yet decidable (no pair)"; a suite without an a4 arm keeps the old "fails" line (state no_arm).
- DECISION: a no-pair state is never the halt phrase, with or without `--partial` (AR-14's no-flag literal moved with it).
- DECISION: `--partial` decidability is taken on the primary version only; inconclusive by degradation counts as decided (it is a pre-registered outcome), so today's real rows exit 0.
- DECISION: degenerate = catch rate, n > 0, exactly one paired task, and no row of the pair contributing per-defect ids (cap-failure vectors are ignored, as in defect_identity); its d/lo/hi stay in the JSON and the text, flagged.
- DECISION: the per-version JSON calls the component comparisons `decisions` (same shape as the top-level key) rather than a new `comparisons` key, so one parser reads both.
- DECISION: rows without suite_version in a single-version input join that version; with no version anywhere the key is `n/a` and `primary_suite_version` is null.
- DECISION: DRIFT in the header is more than one manifest sha256 within one suite_version; two versions with two hashes is not drift.
- DECISION: the secondary-version sections sit after "Rows per cell" and before Method; Cuts, the sensitivity table and Rows per cell stay primary-only (the presentation implementer may extend them).
- DECISION: VERSION bumped to 1.1.0 (the generator string changes; nothing tests it).

## Could not do / limitations
- A row whose suite_version disagrees with its batch manifest's suite_version is not checked.
- The secondary-version sections do not repeat the sensitivity table, Rows per cell or the expected-false-positive sentence.
- The degraded H1 text for v2 shows "(degenerate)" inside the remaining-pairs interval; the guard decides first, so the flag is informational there.

## Handoff notes for the lead
- Apply the patch to the main checkout; regenerate REPO-MAP if the CI asks (the script grew; no new file under `.claude/`).
- The presentation implementer builds on `analyse()` / the `VS` dict in `build()` and the render helpers; sensitivity H1/A4 lines can call `assess` on the `sens` Analysis in each version.
- Once bd-yz1rd re-rows the v2 runs with `defects_missed`, the degenerate flag on review-04 disappears by itself.
