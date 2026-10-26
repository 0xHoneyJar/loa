# Task: a sensitivity that re-includes the matched-bare cells contaminated only by non-repository egress

`evals/analysis/c132/reads.py` reads the cycle-132 ablation: the primary read (`primary`, with `n_pairs`) excludes every contaminated cell, and the registered sensitivities (`sensitivities.reads`, in `sensitivities.order`) re-read the primary under one relaxation each. The grader marks a contaminated row with `contaminated: {"pattern": ..., ...}`; a class-9 record (`"pattern": "network_egress"`) now also carries `repo_named` (true when the egress named a repository, false when it did not), `host` and `url`. The same record is on the grade (`grade.json`), and a cell (`common.build_cell`) is built from both.

**Bug (observed):** a matched-bare cell that reached, say, a release page on a public host without naming any repository is excluded from every read exactly like one that fetched the repository under review; nothing in the cell records what kind of contamination it was, and no sensitivity shows what the primary read would be with such cells counted valid.

**Expected:**
- `common.contamination_detail(*objs)` returns the contamination's detail string from the first object (the row's record, then the grade's) that carries a `pattern`: `network_egress:nonrepo` when `repo_named` is explicitly false, `network_egress:repo` when it is true or absent, else the pattern itself (`outside_path`, …), and `unknown` when none does. A cell carries that detail; the main filter's reason stays `contaminated`.
- A new registered sensitivity `class9_nonrepo_egress_reincluded`: the primary re-read with the matched-bare cells whose ONLY invalidity is a `network_egress:nonrepo` contamination counted valid; it reports `n_pairs` (the primary's plus the pairs that come back), `reincluded_cells` as `{arm: {group: n}}`, `reincluded_keys` as sorted `<batch>/<arm>/<task>/<trial>`, and `recall_matched`. A cell whose egress named a repository stays out. In `sensitivities.order` it sits right after `degraded_contaminated_excluded`. The primary read and `missingness` (its `excluded.contaminated` count) are unchanged.
- `reads.md` describes it with a line `re-included cells (arm: group n) | <arm>: <group> <n>`.

Fix the bug in place and add a regression test of your own. Run the tests under `evals/analysis/c132/tests` that cover the code you change, with `python3 -m pytest -q <file>`.
