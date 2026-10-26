# Fairness review — bugfix-v3-06

**Reviewer:** codex gpt-6.1-sol, non-author session (subscription) · **Author:** seed-bugfix-tasks.sh --fixture-scope roots over Loa's history, lead edits by the branch session · **Verdict:** PASS

## 1. No solution leak

**PASS.** The brief identifies the symptom: “only the one class-9 non-repository class can be re-included” (`TASK.md:5`). Lines 8–11 give a detailed output contract, including `reincluded_family(cells, reg, seed)`. They prescribe an interface and behaviour, but do not supply the implementation.

I searched `TASK.md` and all fixture files for `hidden`, `reference.patch`, `manifest.json`, `grader_protected`, `ContaminationFamilyTest`, the added test names, `contaminated_reincluded_per_class`, `reincluded_family`, `only_contamination`, and `network_egress:unstated`. The new interface and class names occur only in the brief. No grader-location marker or new test name occurs in the fixture.

There is ordinary base-test overlap. The fixture contains `evals/analysis/c132/tests/test_reads.py`, the destination later overlaid by the grader (`hidden/manifest.json:1`). It also contains `test_detail` (`fixture/evals/analysis/c132/tests/test_reads.py:365`). These are existing public tests, not disclosures of the new assertions.

The fixture does not contain the fixed implementation. Its classifier still maps missing `repo_named` to `network_egress:repo` (`fixture/evals/analysis/c132/common.py:199–211`). Its default order and sensitivity dispatcher still use the single legacy name (`fixture/evals/analysis/c132/reads.py:84,615`). The family implementation appears in `hidden/reference.patch:80–112`.

## 2. Hidden assertions against the brief

**PASS.** The hidden overlay replaces `NonRepoEgressTest` with `ContaminationFamilyTest`. The first 332 lines and the suffix beginning at the partition tests are unchanged. The following are the added or changed cases. Hidden line citations below refer to `hidden/tests/evals/analysis/c132/tests/test_reads.py`.

- **`ContaminationFamilyTest.test_per_class_and_all_classes`** (`:360–388`). **Stated.** It checks sorted observed classes, arbitrary new patterns, individual and combined re-inclusion, pair counts, keys, recall presence, group counts, exclusion of an oracle-exposed cell, sensitivity order, unchanged missingness, and Markdown output. `TASK.md:9` specifies “every class seen on a contaminated cell,” “one such cell brings back one pair,” and that a second invalidity “never comes back.” It also specifies the fields, ordering, and unchanged primary filter and missingness. `TASK.md:11` specifies the checked Markdown labels and count format. The concrete totals of 7, 8, and 15 follow from the synthetic batch and its nine contaminated cells (`:333–358`). An agent can reasonably satisfy the entire check.

- **`ContaminationFamilyTest.test_round4_name_still_runs_its_member`** (`:390–411`). **Stated.** It explicitly registers the old sensitivity name and checks that only the non-repository member returns. `TASK.md:10` says the legacy name, “when registered, still produces its member: the `network_egress:nonrepo` read.” The entire assertion is foreseeable.

- **`ContaminationFamilyTest.test_detail`** (`:413–419`). **Stated.** This replaces the base classifier test. It checks false, true, and absent `repo_named`, fallback to another object, and `unknown`. `TASK.md:8` explicitly specifies all five outcomes, including “`network_egress:unstated` when the record does not say.” An agent can satisfy the entire check.

- **`ContaminationFamilyTest.test_no_contamination`** (`:421–428`). **Stated.** `TASK.md:9` says: “With no contaminated cell the family is `status` `no_contaminated_cells` with `observed` `[]`.” Those are exactly the assertions.

No additional brief sentence is needed for these assertions. The remaining tests are visible regression checks inherited from the fixture.

## 3. Criterion mechanical

**PASS.** `success_criterion` gives one mechanical acceptance condition: the named overlay must pass “39 of 39” under the specified pytest command (`task.yaml:8`). The base-red and reference-green statements provide supporting expectations.

`criterion` describes behaviour without naming a file or test (`task.yaml:7`).

`grader_protected` covers `_path.py`, `synth.py`, and the supplied fixture data (`task.yaml:12`). The hidden tests directly rely on `_path` and `synth` (`hidden/tests/evals/analysis/c132/tests/test_reads.py:11–13`). Production modules remain editable.

The command resolves from the fixture root. The test file exists, and `_path.py:5–7` adds `evals/analysis` to the import path. The relevant code uses standard-library imports. I did not execute pytest because the tests create temporary files and outputs.

## Notes

**PASS.** This is a moderately scoped extension with a precise brief. The existing legacy implementation supplies selection, grouping, contrast, and rendering examples. The supplied layout contains the relevant modules and tests without requiring the wider repository.

Likely misses are changing primary validity globally, restoring cells with another invalidity, hard-coding known contamination patterns, dropping legacy registration support, or omitting Markdown rendering. The brief explicitly addresses each of these. The hidden checks test integration across those behaviours without requiring an undisclosed algorithm.