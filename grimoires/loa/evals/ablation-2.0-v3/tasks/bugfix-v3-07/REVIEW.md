# Fairness review — bugfix-v3-07

**Reviewer:** codex gpt-6.1-sol, non-author session (subscription) · **Author:** seed-bugfix-tasks.sh --fixture-scope roots over Loa's history, lead edits by the branch session · **Verdict:** PASS

## 1. No solution leak

**PASS.** The brief states the observed symptom: non-repository egress is excluded “exactly like one that fetched the repository under review” (`TASK.md:5`). Lines 8–10 specify the required API and output contract. They do not disclose the reference implementation.

I searched `TASK.md` and all fixture files, including dotfiles, for `hidden`, `reference.patch`, `NonRepoEgressTest`, both added test names, `contamination_detail`, `only_nonrepo_egress`, `class9_nonrepo_egress_reincluded`, `network_egress:nonrepo`, and the Markdown reporting phrase. The required API and output strings occur only in the brief. No hidden identifiers or fixed implementation occur in the fixture.

The fixture contains the base `evals/analysis/c132/tests/test_reads.py`. Its filename necessarily matches the overlay destination; it does not identify hidden additions. Searches for `grader` find ordinary application terminology, including `grader_version` (`fixture/evals/analysis/c132/tests/synth.py:54`), not disclosures of evaluation files.

The base cell records only the generic contamination reason (`fixture/evals/analysis/c132/common.py:208–209`). The sensitivity registry lacks the new entry (`fixture/evals/analysis/c132/reads.py:80`). The corresponding implementation appears in `hidden/reference.patch:18–36` and `78–98`.

## 2. Hidden assertions against the brief

**PASS.** Comparison with the base file shows exactly two added tests. Existing tests are unchanged.

- **`NonRepoEgressTest.test_class9_nonrepo_cell_reincluded_only_in_the_sensitivity`** (`hidden/tests/evals/analysis/c132/tests/test_reads.py:334`). Fully stated. The test contaminates two matched-bare cells, one with `repo_named: false` and one with `true`. It asserts primary/sensitivity pair counts of 14/15, grouped counts, cell keys, `recall_matched`, registry order, unchanged missingness, and the Markdown line (`:352–363`). `TASK.md:9` requires the nonrepo-only relaxation, every asserted JSON field, placement “right after `degraded_contaminated_excluded`,” and unchanged primary and missingness. `TASK.md:10` supplies the reporting format. The numeric expectations follow from the visible synthetic batch’s eight tasks and two trials (`fixture/evals/analysis/c132/tests/synth.py:22–28`). An agent can reasonably satisfy the entire check.

- **`NonRepoEgressTest.test_detail`** (`hidden/tests/evals/analysis/c132/tests/test_reads.py:365`). Fully stated. It checks explicit false, absent `repo_named`, fallback to an `outside_path` record, and absent records (`:366–369`). `TASK.md:8` explicitly requires “when `repo_named` is explicitly false,” “true or absent,” “else the pattern itself,” and “`unknown` when none does.” An agent can reasonably satisfy all four assertions.

No added assertion requires unstated behaviour. No additional brief sentence is needed.

## 3. Criterion mechanical

**PASS.** `success_criterion` is one mechanical statement identifying the overlaid file, 37-of-37 requirement, and exact pytest command (`task.yaml:8`). Its red/green clause records the claimed calibration.

`criterion` describes cell detail, selective reinclusion, and unchanged primary/missingness behaviour. It names no file or test (`task.yaml:7`).

`grader_protected` covers `_path.py`, `synth.py`, and the listed supporting fixtures (`task.yaml:12`). The hidden file imports both helpers (`hidden/tests/evals/analysis/c132/tests/test_reads.py:11–13`). The manifest supplies the test overlay (`hidden/manifest.json:1`).

The command targets an existing path relative to the fixture root (`task.yaml:9`). `_path.py` establishes the package import path (`fixture/evals/analysis/c132/tests/_path.py:5–7`). It is structurally runnable with Python and pytest installed. I did not execute tests because they create temporary files.

## Notes

**PASS.** This is a tightly specified task in a small Python fixture. The main trap is that contaminated status produces both `status:contaminated` and `contaminated` reasons (`fixture/evals/analysis/c132/common.py:203–209`). A bare agent may relax only one reason, alter the primary filter, or omit registry ordering and Markdown reporting.

The hidden additions provide limited coverage of other invalidities, row/grade precedence, and multiple reincluded keys. Those are coverage limits, not unstated requirements.