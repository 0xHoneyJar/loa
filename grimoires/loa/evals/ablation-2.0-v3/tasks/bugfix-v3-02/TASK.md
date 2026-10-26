# Task: the grader-vs-judge report takes its title from the rows' grader version

`evals/analysis/c132/judge_agree.py` renders the agreement read between the grader and the blind judge as Markdown (`render_md`), which `main` writes after `run(...)` has built the document from the rows file.

**Bug (observed):** the report's first line is the fixed text `# Grader 1.3.2 vs the blind judge`, whatever grader version produced the rows; rows graded by grader 1.3.8 are reported under 1.3.2.

**Expected:** `render_md(doc, rows=None)` builds the title from the rows: the distinct `grader_version` values found on them, sorted as text and joined by `, `, as `# Grader <versions> vs the blind judge` — `# Grader 1.3.8 vs the blind judge` for rows all graded by 1.3.8, `# Grader 1.3.10, 1.3.8 vs the blind judge` when both occur, and `# Grader vs the blind judge` when no row carries a version or no rows are given. Everything after the title line is unchanged, `render_md(doc)` keeps working, and `main` passes the rows it read.

Fix the bug in place and add a regression test of your own. Run the tests under `evals/analysis/c132/tests` that cover the code you change, with `python3 -m pytest -q <file>`.
