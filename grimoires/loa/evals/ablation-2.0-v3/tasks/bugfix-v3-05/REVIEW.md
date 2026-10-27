# Fairness review — bugfix-v3-05

**Reviewer:** codex gpt-6.1-sol, non-author session (subscription) · **Author:** seed-bugfix-tasks.sh --fixture-scope roots over Loa's history, lead edits by the branch session · **Verdict:** PASS

## 1. No solution leak

**PASS.** Searches with `rg -n --hidden` covered TASK.md and fixture/ for `hidden/tests`, `reference.patch`, `grader_protected`, `test_reads.py`, `OracleFamilyTest`, `test_by_form`, `test_form`, `oracle_form`, `only_oracle`, and `oracle_family`. No hidden-test identifiers, grader paths, or fixed implementation appeared in the fixture.

The word `hidden` occurs as an existing contamination class (`fixture/evals/analysis/c132/common.py:201`; `fixture/evals/analysis/c132/tests/test_reads.py:340`). References to “grader” concern the application’s defect grader (`fixture/evals/analysis/c132/tests/synth.py:4`). Neither identifies evaluation infrastructure.

TASK.md:5 states the symptom. Lines 8–10 specify the required API and output contract. They give substantial guidance but no implementation recipe. The fixture still appends only `"oracle_exposed"` (`fixture/evals/analysis/c132/common.py:248`). The reference adds form classification and the new sensitivity family (`hidden/reference.patch:17–42,75–99`). No fixed copy was found.

## 2. Hidden assertions against the brief

**PASS.** The overlay preserves all 39 base cases. It adds two cases and extends one. References below are to `hidden/tests/evals/analysis/c132/tests/test_reads.py`.

- **`ContaminationFamilyTest.test_no_contamination` — changed, fully stated.** Line 429 adds the oracle-family empty-status assertion. TASK.md:9 requires `"no_oracle_exposed_cells"` “when no full-pipeline cell is oracle-exposed.” The synthetic batch has no exposure. The assertion is directly expected.

- **`OracleFamilyTest.test_by_form` — added, fully stated.** Lines 432–478 exercise read-only, diff-only, mixed, unknown, and contaminated exposure. They check primary exclusion, sorted re-included keys, pair counts, recall-field presence, nested counts, contamination isolation, and Markdown output. TASK.md:9 explicitly requires the three reads, including “`unknown` included,” and says a cell with another invalidity “is never re-included, in no member.” It also requires the primary and contamination members to remain unchanged. TASK.md:10 supplies the checked Markdown label and count format. The exact pair counts follow from the fixture’s 16 pairs and the selected exclusions.

- **`OracleFamilyTest.test_form` — added, fully stated.** Lines 480–483 check read-only → `read`, mixed → `diff`, and absent → `unknown`. TASK.md:8 states each mapping explicitly.

An agent reading TASK.md and the fixture can reasonably satisfy every added assertion. No additional brief sentence is needed for these checks. Coverage is weaker than the brief: the new tests do not directly verify that validity reasons carry the form.

## 3. Criterion mechanical

**PASS.** `success_criterion` identifies one mechanical acceptance condition: the overlaid file passes 41 of 41 tests under the specified pytest command (`task.yaml:8`). Static comparison confirms 41 test methods. The red/green clause supplies provenance.

`criterion` describes behavior without naming a path or test (`task.yaml:7`).

The overlay destination matches the command’s relative path (`hidden/manifest.json:1`; `task.yaml:9`). The fixture contains that file. Its imports use `_path` and `synth` (`hidden/tests/evals/analysis/c132/tests/test_reads.py:11–13`). Both helpers are protected (`task.yaml:12`). `_path.py:5–7` makes the package importable from the fixture root. The command is structurally runnable with Python and pytest installed. Tests were not executed because they create temporary files.

## Notes

**PASS.** This is a well-specified task with moderate integration difficulty. The fixture is a small Python analysis package with visible tests and synthetic-data helpers. The brief gives precise field names and output formats.

Likely misses are treating mixed exposure as read-only, dropping unknown exposure, re-including contaminated cells, counting ineligible cells, or omitting Markdown output. The hidden checks cover those main integration risks.

The reference leaves `"oracle_exposed"` in the reasons list and stores the form separately (`hidden/reference.patch:38–42`). “The cell’s validity reason carries the form” could be clearer about that representation. This ambiguity does not impose an unstated hidden assertion.