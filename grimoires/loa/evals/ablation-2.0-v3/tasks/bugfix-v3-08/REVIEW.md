# Fairness review — bugfix-v3-08

**Reviewer:** codex gpt-6.1-sol, non-author session (subscription) · **Author:** seed-bugfix-tasks.sh --fixture-scope roots over Loa's history, lead edits by the branch session · **Verdict:** FAIL

## 1. No solution leak

**FAIL.** The brief describes the patch as well as the symptom. `TASK.md:8` supplies the complete function signature, specifies that “`delta` is the new first argument,” and gives the ordered decision branches. `TASK.md:9` supplies the exact new dictionary keys and Markdown column. These correspond directly to `hidden/reference.patch:26–47`, `57–66`, and `119–134`. This fails the requested symptom-versus-patch check.

I searched `TASK.md` and all fixture files with `rg -n --hidden -i` for `hidden`, `reference\.patch`, `test_power\.py`, `test_reads\.py`, all seven new test names, `NEGATIVE`, `negative_at_null`, `negative_at_mde`, `PARTITION_LEGEND`, and `OUTCOMES`. No hidden path, new test name, or grader-file marker appeared. The fixture contains base files with the same test filenames, as expected for overlays. Their contents do not disclose the added assertions.

The fixture does not contain the fixed implementation. Its `reads.py:163–176` retains the old signature and decision branches. Its `power.py:351` omits the negative counter, and `power.py:382` calls the old signature. The other fixture matches for “negative” concern unrelated validation, variance, and positive-control wording.

## 2. Hidden assertions against the brief

**PASS.** Both hidden files have base versions. The reads overlay replaces `PartitionTest.test_partition` with six cases. The power overlay adds one case and changes two existing cases.

In `hidden/tests/evals/analysis/c132/tests/test_reads.py`:

- `test_rule1_negative` (`342–347`): **Stated.** Checks NEGATIVE before NO on interim and final looks, and NO for a negative estimate below the significance boundary. `TASK.md:8` says “this wins even when `z_no` also crosses” and explicitly states the below-boundary fallback.
- `test_rule2_yes_and_its_boundary_with_small` (`349–353`): **Stated.** Checks positive significant estimates with the interval reaching MDE. `TASK.md:8` gives the YES conditions.
- `test_rule3_small` (`355–362`): **Stated.** Checks both SMALL routes and equality at MDE. `TASK.md:8` says “exactly at the MDE is YES” and specifies `rci_hi < mde` for SMALL.
- `test_rule4_to_6` (`364–368`): **Stated.** Checks NO, FUTILE, CONTINUE, and final-look INCONCLUSIVE precedence. `TASK.md:8` states these branches and the conditional-power threshold.
- `test_exhaustive_and_ordered` (`370–383`): **Stated.** Checks outcome membership, reachability, and sign restrictions across a grid. `TASK.md:8` calls the table “ordered, exhaustive” and says YES and SMALL “only ever fire with Δ̂ ≥ 0.”
- `test_legend_in_look_output` (`385–386`): **Stated.** Checks that the legend contains NEGATIVE. `TASK.md:8` says “`PARTITION_LEGEND` explains it.” Despite its name, the test does not inspect rendered look output.

In `hidden/tests/evals/analysis/c132/tests/test_power.py`:

- `test_evaluate_partition_single_look` (`131–140`), changed: **Stated.** Adds a zero negative-share assertion for studies without significant negative estimates. `TASK.md:9` requires a `negative` outcome share.
- `test_negative_outcome_is_tallied` (`142–149`), added: **Stated.** Checks negative share 0.5, positive share 0.25, and normalization under both existing interval modes. `TASK.md:9` explicitly gives “two of four” and requires shares other than `void` to sum to 1. The fixture already exposes both interval modes (`fixture/evals/analysis/c132/tests/test_power.py:141–158`).
- `test_seeded_reproducible_and_frozen_chosen_n` (`178–213`), changed: **Stated.** Adds checks for `negative_at_null`, `negative_at_mde`, nested `null.negative`, and `| NEGATIVE |`. `TASK.md:9` names each requirement.

An agent reading only the brief and fixture could reasonably satisfy every added assertion. No additional behavioral sentence is needed.

## 3. Criterion mechanical

**PASS.** `success_criterion` specifies the two overlaid files, a 51-of-51 target, and one pytest command (`task.yaml:8`). Its base-red/reference-green clause is additional validation context.

`criterion` describes decision ordering, sign restrictions, and negative-share reporting. It names no file or test (`task.yaml:7`).

`grader_protected` covers the import helper, synthetic-data helper, schema, and miniature power-study inputs (`task.yaml:12`). These match the tests’ infrastructure dependencies: `_path` and `synth` in the reads tests, and `_path.FIXTURES` plus the miniature input paths in the power tests.

The command uses paths present beneath the fixture root (`task.yaml:9`). `_path.py:5–8` establishes the package import path. It is structurally runnable from that root with Python and pytest installed. I did not execute it because the tests create temporary files.

## Notes

**PASS.** The implementation is narrow and the brief makes it comparatively easy. The main work is propagating the new argument through both callers, adding the counter, carrying the summary fields, and updating rendered columns.

Likely misses are updating only `reads.decide`, forgetting the simulation caller, omitting summary keys, or mishandling equality at MDE. The exhaustive branch specification substantially reduces discovery work.

The symptom description also overstates the base bug. It says negative estimates can reach YES and SMALL (`TASK.md:5`), but the fixture uses signed `z_yes >= b_yes` (`fixture/evals/analysis/c132/reads.py:164`). The demonstrated base defect is the missing NEGATIVE outcome and reporting.