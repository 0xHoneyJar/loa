# Hunks — pr-26

The later fix changed 54 region(s) in 5 of the change's 5 file(s). Line numbers are head-side (the code under review). Each entry shows up to 12 head lines before and after the region; `>` marks a head line the fix changed.

## H01 — evals/harness/ablation-report.py — head line 62

Head context (head/evals/harness/ablation-report.py, lines 50–74):

~~~~text
    50 | #                       arm is an id (a5_no_flatline) or a label (A5); state is not_run_cut
    51 | #                       (default) or inconclusive_by_power (a pre-declared power cut)
    52 | #   --not-run CSV       arm ids or labels read as Not run (cut) with figure "--not-run"
    53 | #   --suite-version N   the suite_version the main sections report (default: the highest
    54 | #                       present); a version no row holds → exit 2
    55 | #
    56 | # Suite versions (Sprint 262): rows of different suite_version values are never pooled. The
    57 | # main sections (Decisions, Per-arm detail, Exclusions, Cuts, Sensitivity, Rows per cell) read
    58 | # the primary version only; every other version gets "## Suite version N (batches: …) —
    59 | # reported separately, never pooled" with its own decision table, H1 and A4 lines, per-arm
    60 | # figures and exclusions. The header lists each version with its batches and manifest sha256
    61 | # (DRIFT is more than one sha256 within one version). A row without suite_version among rows of
>   62 | # two or more versions → exit 2; when one version (or none) is present, such rows join it.
    63 | # JSON: primary_suite_version and by_suite_version {"N": {suite_version, rows, batches,
    64 | # suite_manifest_sha256, decidable, h1, a4, decisions, arms, exclusions, listed, cap_failures}};
    65 | # the top-level keys describe the primary version.
    66 | #
    67 | # Row treatment (DEC-0393, DEC-0417):
    68 | #   not decided, listed  rows of a smoke batch (manifest smoke: true), rows whose batch has
    69 | #                        no manifest, rows of an arm the suite does not run (absent or
    70 | #                        unknown), rows on a task type outside the arm's task_types
    71 | #                        (applicability refusals; not counted in the excluded share)
    72 | #   excluded pairwise    status in rules.exclusion.statuses plus transport_error and
    73 | #                        infrastructure_error (DEC-0417), degraded: true (with
    74 | #                        --exclude-degraded true), and a scoring status whose primary is
~~~~

The change from head to the fix:

~~~~diff
@@ -62 +62,15 @@
-# two or more versions → exit 2; when one version (or none) is present, such rows join it.
+# two or more versions → exit 2 when it would enter a cell; one that would be listed anyway (no
+# manifest, smoke batch, arm not run, unknown or inapplicable task type) is listed under the primary
+# version as never decided, reason "no suite_version; <the listing reason>" (report 1.2.1); when one
+# version (or none) is present, such rows join it. Every row passes the manifest arm_map provenance
+# check (DEC-0407, exit 2) before any partition or listing decision, a version-less row included (1.2.2).
+# Version keys (report 1.2.1): an integer-valued number or numeric string keys to the integer ("2",
+# 2, 2.0 and "2.0" are one version "2"); another finite number keys to its shortest round-trip form
+# (2.1 and "2.10" → "2.1"); another string keys to itself, stripped; absent = null, a boolean, an
+# empty or blank string, or a non-number non-string. --suite-version is keyed by the same rule.
+# Numeric keys sort numerically, every other key after them, lexically; the primary is the last.
+# JSON primary_suite_version is an int for an integer key, a float for another numeric key. Since 1.2.2 every
+# JSON version value has that type: primary_suite_version, by_suite_version[N].suite_version, h1/a4
+# .suite_version (top level, per version, sensitivity), budget_matched.suite_version and
+# batches[].suite_version (a string for a non-numeric key or a "1, 2" list, null for n/a); the
+# by_suite_version object keys stay strings.
~~~~

## H02 — evals/harness/ablation-report.py — head lines 87–88

Head context (head/evals/harness/ablation-report.py, lines 75–100):

~~~~text
    75 | #                        null (ungraded); the task-trial cell leaves BOTH arms of every
    76 | #                        comparison it is in; a cell holding a valid row (a rerun) is valid
    77 | #   cap_failure          0 on every applicable primary (pass rate 0, every defect missed)
    78 | #   completed, agent_error  score what the row holds (hidden_test_pass_rate; defects)
    79 | #   The sensitivity figure repeats the comparison with cap_failure excluded pairwise
    80 | #   instead of scored 0; no decision reads it.
    81 | #
    82 | # Statistics (pre-registered in the suite's rules block; formulas in the Method section):
    83 | #   pass rate unit  the task: per task, the mean over its valid trials, arm minus a1_full
    84 | #   catch-rate unit the defect: per review-catch task and defect dK, the share of the
    85 | #                   arm's valid trials that caught it, arm minus a1_full; per-defect ids
    86 | #                   come from the row's `defects_missed` (or `recall.missed`) list of dK
>   87 | #                   ids when present, else each defect of the task takes the row's
>   88 | #                   defect_catch_rate (aggregate rows); the task-level figure is also
    89 | #                   reported (rules.bootstrap.also_report) and decides nothing
    90 | #   interval        percentile bootstrap of the mean paired difference: `resamples`
    91 | #                   resamples with replacement, linear interpolation between order
    92 | #                   statistics, [lo, hi] = the (1-level)/2 and 1-(1-level)/2 quantiles
    93 | #   d               the mean of the paired differences (not the bootstrap mean)
    94 | #   c, w            cost and wall-clock delta in percent against a1_full,
    95 | #                   (mean_arm − mean_a1) / mean_a1 × 100, over the per-task means of the
    96 | #                   cells the primaries paired
    97 | #   MDE             (z(1−(1−level)/2) + z(0.90)) × sd(paired diffs) / sqrt(n): the smallest
    98 | #                   true mean difference a paired test at the report level detects with 0.90
    99 | #                   power at the available n; n < 2 → n/a
   100 | #   comparisons     every predicate compares values rounded to 9 decimals, so a planted
~~~~

The change from head to the fix:

~~~~diff
@@ -87,2 +101,5 @@
-#                   ids when present, else each defect of the task takes the row's
-#                   defect_catch_rate (aggregate rows); the task-level figure is also
+#                   ids when present and consistent, else each defect of the task takes the row's
+#                   defect_catch_rate (aggregate rows; report 1.2.3: a list with an id outside
+#                   d1 … dN of the task, a duplicate id, or N − len(ids) ≠ a numeric defects_caught
+#                   is inconsistent and reads as the rate, "rate" in defect_identity, never
+#                   "ids"; the row writer 1.3 rules); the task-level figure is also
~~~~

## H03 — evals/harness/ablation-report.py — head lines 126–127

Head context (head/evals/harness/ablation-report.py, lines 114–139):

~~~~text
   114 | #   admissible task") → inconclusive_by_degradation (either arm's excluded share over its cells
   115 | #   on that primary's task types > rules.exclusion.inconclusive_above_share) → degenerate (a
   116 | #   defect_catch_rate comparison whose pairs come from one task and whose rows carry no
   117 | #   per-defect ids: the interval is zero-variance by construction; flagged degenerate: true with
   118 | #   degenerate_reason and read as no valid pair, also by the component decisions) → no_pair →
   119 | #   tested. H1: established (a tested primary with lo > 0) | not established — halt before
   120 | #   promotion (a tested primary, none with lo > 0) | inconclusive by degradation — not
   121 | #   established (every testable primary inconclusive by degradation) | not yet decidable (no
   122 | #   pair). A4: holds | fails — harden tasks … | inconclusive by degradation (…) — not decided |
   123 | #   not testable on suite_version N — no admissible build task | not yet decidable (no pair).
   124 | #   JSON h1/a4 carry state and suite_version; each comparison carries read and read_text.
   125 | #
>  126 | # Presentation items (Sprint 262 R3, report 1.2.0; none of them changes a decision, an H1/A4 state or
>  127 | # an existing number):
   128 | #   sensitivity H1/A4  the sensitivity figure prints the H1 and A4 lines, read the same way as the main
   129 | #                   lines on a third Analysis with cap failures excluded and degraded rows included,
   130 | #                   prefixed "sensitivity (decides nothing): "; per suite version. JSON sensitivity.h1 /
   131 | #                   sensitivity.a4 (the shape of the top-level h1 / a4) and sensitivity.treatment; also
   132 | #                   by_suite_version[N].sensitivity.
   133 | #   ## Batch record one table row per manifest's batch, grouped by suite version, from STATUS.json beside
   134 | #                   MANIFEST.json (read-only; absent → "no STATUS.json"; a symlink is not read): state,
   135 | #                   trials planned / rowed, spend (rows_usd, ledger_usd, spent_usd, max_usd), extra_models,
   136 | #                   rerowed[] and rerun[] counts with from→to tallies, drift_cleared[] and outage_history[]
   137 | #                   counts, cuts[], paused_arms, and the grade.json grader_version tally of the rows' run
   138 | #                   directories <batch dir>/<arm>/<task>-t<n>[-r<k>] ("n/a" without grade.json; a missing
   139 | #                   directory is counted, never fatal). JSON batches[].
~~~~

The change from head to the fix:

~~~~diff
@@ -126,2 +143,2 @@
-# Presentation items (Sprint 262 R3, report 1.2.0; none of them changes a decision, an H1/A4 state or
-# an existing number):
+# Presentation items (Sprint 262 R3, report 1.2.0; fixes in 1.2.1 and 1.2.2; none of them changes a decision, an
+# H1/A4 state or an existing number):
~~~~

## H04 — evals/harness/ablation-report.py — head lines 138–139

Head context (head/evals/harness/ablation-report.py, lines 126–151):

~~~~text
   126 | # Presentation items (Sprint 262 R3, report 1.2.0; none of them changes a decision, an H1/A4 state or
   127 | # an existing number):
   128 | #   sensitivity H1/A4  the sensitivity figure prints the H1 and A4 lines, read the same way as the main
   129 | #                   lines on a third Analysis with cap failures excluded and degraded rows included,
   130 | #                   prefixed "sensitivity (decides nothing): "; per suite version. JSON sensitivity.h1 /
   131 | #                   sensitivity.a4 (the shape of the top-level h1 / a4) and sensitivity.treatment; also
   132 | #                   by_suite_version[N].sensitivity.
   133 | #   ## Batch record one table row per manifest's batch, grouped by suite version, from STATUS.json beside
   134 | #                   MANIFEST.json (read-only; absent → "no STATUS.json"; a symlink is not read): state,
   135 | #                   trials planned / rowed, spend (rows_usd, ledger_usd, spent_usd, max_usd), extra_models,
   136 | #                   rerowed[] and rerun[] counts with from→to tallies, drift_cleared[] and outage_history[]
   137 | #                   counts, cuts[], paused_arms, and the grade.json grader_version tally of the rows' run
>  138 | #                   directories <batch dir>/<arm>/<task>-t<n>[-r<k>] ("n/a" without grade.json; a missing
>  139 | #                   directory is counted, never fatal). JSON batches[].
   140 | #   precision       per-arm detail of review-catch arms: precision = Σ defects_caught ÷ (Σ defects_caught +
   141 | #                   Σ false_positives) over the arm's valid review-catch rows with a numeric defects_caught
   142 | #                   (cap_failure counts 0 caught; a null false_positives counts 0), null when 0; cost per
   143 | #                   true defect = Σ cost_usd ÷ Σ defects_caught, null when 0 caught. JSON arms.<arm>.
   144 | #                   {precision, usd_per_true_defect, true_defects, flagged_regions, precision_rows}.
   145 | #   budget-matched  per suite version, per review-catch task: the union of a0_bare's valid trials' caught
   146 | #                   defects (ids d1 … dN from defects_missed, as defect_vector reads them; a task whose a0
   147 | #                   rows carry none → max over trials of the rate, "rate fallback") against a1_full's mean
   148 | #                   per-trial catch rate, with the summed a0 cost and the mean a1 cost; "not available" when
   149 | #                   the version has no valid a0_bare or a1_full review-catch rows. JSON budget_matched
   150 | #                   {suite_version, available, tasks[], a0_union_mean, a1_mean, diff_mean, note} (primary
   151 | #                   version; by_suite_version[N].budget_matched for each).
~~~~

The change from head to the fix:

~~~~diff
@@ -138,2 +155,11 @@
-#                   directories <batch dir>/<arm>/<task>-t<n>[-r<k>] ("n/a" without grade.json; a missing
-#                   directory is counted, never fatal). JSON batches[].
+#                   directories. Attribution (report 1.2.1): each row is resolved to its own directory
+#                   once — the highest <batch dir>/<arm>/<task>-t<n>-r<k> whose meta/pipeline.json run_id
+#                   equals the row's, else the highest -r<k> holding a grade.json, else <task>-t<n>, else
+#                   the highest -r<k> (1.2.2); n compares numerically, so rc-01-t01 is trial 1 (1.2.2) — and
+#                   counted once ("n/a" when the directory or its grade is absent), so the tally sums
+#                   to the batch's rows; run_dirs_missing counts the rows with no attributable directory.
+#                   Tally order: dotted segments numeric before text, "n/a" last. Never fatal: an exception
+#                   in one batch's STATUS.json or tally leaves that tally unsorted or partial with a note in
+#                   the row (JSON batches[].note); an exception anywhere else in computing or rendering the
+#                   batch record (1.2.2) prints "Not rendered (…)" with JSON batches [] and batches_note set
+#                   (null otherwise); neither aborts the report. JSON batches[].
~~~~

## H05 — evals/harness/ablation-report.py — insertion after head line 152

Head context (head/evals/harness/ablation-report.py, lines 141–164):

~~~~text
   141 | #                   Σ false_positives) over the arm's valid review-catch rows with a numeric defects_caught
   142 | #                   (cap_failure counts 0 caught; a null false_positives counts 0), null when 0; cost per
   143 | #                   true defect = Σ cost_usd ÷ Σ defects_caught, null when 0 caught. JSON arms.<arm>.
   144 | #                   {precision, usd_per_true_defect, true_defects, flagged_regions, precision_rows}.
   145 | #   budget-matched  per suite version, per review-catch task: the union of a0_bare's valid trials' caught
   146 | #                   defects (ids d1 … dN from defects_missed, as defect_vector reads them; a task whose a0
   147 | #                   rows carry none → max over trials of the rate, "rate fallback") against a1_full's mean
   148 | #                   per-trial catch rate, with the summed a0 cost and the mean a1 cost; "not available" when
   149 | #                   the version has no valid a0_bare or a1_full review-catch rows. JSON budget_matched
   150 | #                   {suite_version, available, tasks[], a0_union_mean, a1_mean, diff_mean, note} (primary
   151 | #                   version; by_suite_version[N].budget_matched for each).
   152 | #
   153 | # Exit codes:
   154 | #   0  report written
   155 | #   1  --partial and no decidable comparison in the primary version (the report is still
   156 | #      written); H1 or A4 counts as decided when it reads established / not established /
   157 | #      holds / fails / inconclusive by degradation
   158 | #   2  usage error, unreadable input, unknown schema major, provenance conflict, a row without
   159 | #      suite_version among two versions, --suite-version naming no row's version
   160 | #
   161 | # Tested by evals/tests/ablation-report.bats (planted rows generated by
   162 | # evals/tests/fixtures/ablation-report/gen-fixtures.py).
   163 | # =============================================================================
   164 | import argparse
~~~~

The change from head to the fix:

~~~~diff
@@ -152,0 +179,22 @@
+# Input guards (report 1.2.3, the Sprint 262 audit; none changes a decision, an H1/A4 state or a number
+# on rows that ablation-row.sh --validate accepts):
+#   numbers         every cost read goes through usd_of(row) (and wall-clock through num_of): a finite
+#                   int/float that is not a bool, else 0 with one stderr note per row and key ("note: row
+#                   <run_id> cost_usd is a str, not a number; read as 0"); the per-arm means skip a
+#                   non-finite value. The JSON twin is serialised with allow_nan=False before any file is
+#                   written: a NaN or an infinity that still reaches it exits 2 with "refusing to write a
+#                   non-finite number to the JSON report at $.<key path>" and writes neither file.
+#   exception text  a never-fatal guard of the batch record renders the exception class and a fixed
+#                   phrase naming the stage and the batch ("Not rendered (ValueError while reading the
+#                   batch record of pr-2)", "grader tally incomplete (ValueError while tallying the grader
+#                   versions of pr-2)"); str(exception), which can carry a file's content or a host path,
+#                   goes to stderr once and never into report.md or report.json.
+#   paths           before a row's run directory is looked up, its arm must fullmatch ^[a-z][a-z0-9_]{0,63}$
+#                   and its task_id ^[a-z0-9][a-z0-9-]{0,63}$; a row outside either counts in
+#                   run_dirs_missing (n/a) with the note "<n> row(s) with an arm or task_id outside the
+#                   grammar (no attributable directory)" and is never used in a path. Every file read
+#                   below a batch directory (the arm directory, meta/pipeline.json, grade.json) is refused
+#                   when a component below the batch directory is a symlink or its realpath leaves the
+#                   realpath of that batch's manifest directory. The run-directory names themselves come
+#                   from os.listdir and are matched with GRADE_DIR.fullmatch.
+#
~~~~

## H06 — evals/harness/ablation-report.py — head line 159

Head context (head/evals/harness/ablation-report.py, lines 147–171):

~~~~text
   147 | #                   rows carry none → max over trials of the rate, "rate fallback") against a1_full's mean
   148 | #                   per-trial catch rate, with the summed a0 cost and the mean a1 cost; "not available" when
   149 | #                   the version has no valid a0_bare or a1_full review-catch rows. JSON budget_matched
   150 | #                   {suite_version, available, tasks[], a0_union_mean, a1_mean, diff_mean, note} (primary
   151 | #                   version; by_suite_version[N].budget_matched for each).
   152 | #
   153 | # Exit codes:
   154 | #   0  report written
   155 | #   1  --partial and no decidable comparison in the primary version (the report is still
   156 | #      written); H1 or A4 counts as decided when it reads established / not established /
   157 | #      holds / fails / inconclusive by degradation
   158 | #   2  usage error, unreadable input, unknown schema major, provenance conflict, a row without
>  159 | #      suite_version among two versions, --suite-version naming no row's version
   160 | #
   161 | # Tested by evals/tests/ablation-report.bats (planted rows generated by
   162 | # evals/tests/fixtures/ablation-report/gen-fixtures.py).
   163 | # =============================================================================
   164 | import argparse
   165 | import json
   166 | import math
   167 | import os
   168 | import random
   169 | import re
   170 | import statistics
   171 | import subprocess
~~~~

The change from head to the fix:

~~~~diff
@@ -159 +207,2 @@
-#      suite_version among two versions, --suite-version naming no row's version
+#      suite_version among two versions that would enter a cell, --suite-version naming no row's
+#      version
~~~~

## H07 — evals/harness/ablation-report.py — head line 174

Head context (head/evals/harness/ablation-report.py, lines 162–186):

~~~~text
   162 | # evals/tests/fixtures/ablation-report/gen-fixtures.py).
   163 | # =============================================================================
   164 | import argparse
   165 | import json
   166 | import math
   167 | import os
   168 | import random
   169 | import re
   170 | import statistics
   171 | import subprocess
   172 | import sys
   173 | 
>  174 | VERSION = "1.2.0"
   175 | REPORT_SCHEMA = 1
   176 | ROW_SCHEMA_MAJOR = 1
   177 | MANIFEST_SCHEMA_MAJOR = 1
   178 | CONTROL = "a1_full"
   179 | BARE = "a0_bare"
   180 | SENSITIVITY_ARM = "a4_no_gates"
   181 | BUILD_TYPES = ("feature-build", "bug-fix", "refactor")
   182 | REVIEW = "review-catch"
   183 | PASS = "hidden_test_pass_rate"
   184 | CATCH = "defect_catch_rate"
   185 | DEC0417_EXCLUDED = ("transport_error", "infrastructure_error")
   186 | SCORING = ("completed", "agent_error", "cap_failure")
~~~~

The change from head to the fix:

~~~~diff
@@ -174 +223 @@
-VERSION = "1.2.0"
+VERSION = "1.2.3"
~~~~

## H08 — evals/harness/ablation-report.py — insertion after head line 197

Head context (head/evals/harness/ablation-report.py, lines 186–209):

~~~~text
   186 | SCORING = ("completed", "agent_error", "cap_failure")
   187 | POWER = 0.90
   188 | DISPLAY = {"investigate": "Investigate", "keep": "Keep", "inconclusive": "Inconclusive",
   189 |            "remove": "Remove", "simplify": "Simplify", "not_run_cut": "Not run (cut)",
   190 |            "inconclusive_by_power": "Inconclusive-by-power", "component_absent": "component-absent",
   191 |            "no_rows": "no rows"}
   192 | PARTIAL_LINE = "PARTIAL — rows so far, no decision is final"
   193 | SENS_LABEL = "sensitivity (cap failures excluded) — no decision uses this"
   194 | SENS_PREFIX = "sensitivity (decides nothing): "
   195 | SENS_H_TREATMENT = "cap failures excluded, degraded rows included"
   196 | BUDGET_LABEL = "informational, decides nothing"
   197 | GRADE_DIR = re.compile(r"(.+)-t(\d+)(?:-r(\d+))?")
   198 | 
   199 | 
   200 | class Fail(Exception):
   201 |     pass
   202 | 
   203 | 
   204 | # --------------------------------------------------------------------------- small helpers
   205 | def r9(x):
   206 |     return None if x is None else round(x, 9)
   207 | 
   208 | 
   209 | def mean(xs):
~~~~

The change from head to the fix:

~~~~diff
@@ -197,0 +247,2 @@
+ARM_GRAMMAR = re.compile(r"[a-z][a-z0-9_]{0,63}")       # ablation-row.sh / execute-agent.sh (fullmatch)
+TASK_GRAMMAR = re.compile(r"[a-z0-9][a-z0-9-]{0,63}")    # a task id as a path component (fullmatch)
~~~~

## H09 — evals/harness/ablation-report.py — insertion after head line 229

Head context (head/evals/harness/ablation-report.py, lines 218–241):

~~~~text
   218 | def u3(x):
   219 |     return "n/a" if x is None else f"{x:.3f}"
   220 | 
   221 | 
   222 | def pct(x):
   223 |     return "n/a" if x is None else f"{x:+.1f} %"
   224 | 
   225 | 
   226 | def j6(x):
   227 |     return None if x is None else round(x, 6)
   228 | 
   229 | 
   230 | def schema_major(v):
   231 |     if isinstance(v, bool):
   232 |         return None
   233 |     if isinstance(v, int):
   234 |         return v
   235 |     if isinstance(v, float) and v.is_integer():
   236 |         return int(v)
   237 |     if isinstance(v, str) and re.fullmatch(r"\d+(\.\d+)*", v):
   238 |         return int(v.split(".")[0])
   239 |     return None
   240 | 
   241 | 
~~~~

The change from head to the fix:

~~~~diff
@@ -229,0 +281,43 @@
+def is_num(v):
+    """A finite int/float that is not a bool."""
+    return isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v)
+
+
+MISSED_ID = re.compile(r"d([1-9][0-9]*)")
+
+
+def missed_consistent(missed, n, caught):
+    """The report 1.2.3 id rules (audit DISS-C-001, the row writer 1.3 rules against the task's N): every
+    id is d1 … dN, no duplicate, and N − len(ids) == defects_caught when defects_caught is a number."""
+    ks = []
+    for x in missed:
+        mm = MISSED_ID.fullmatch(x)
+        if not mm or int(mm.group(1)) > n:
+            return False
+        ks.append(x)
+    if len(set(ks)) != len(ks):
+        return False
+    return not is_num(caught) or n - len(ks) == caught
+
+
+_NOTED = set()
+
+
+def num_of(row, key):
+    """A row's numeric field: a finite int/float that is not a bool, else 0 with one stderr note per row
+    and key (report 1.2.3, audit DISS-C-003); an absent or null field is 0 without a note."""
+    v = row.get(key)
+    if is_num(v):
+        return v
+    if v is not None and (row.get("run_id"), key) not in _NOTED:
+        _NOTED.add((row.get("run_id"), key))
+        kind = "NaN or an infinity" if isinstance(v, float) else f"a {type(v).__name__}, not a number"
+        sys.stderr.write(f"ablation-report.py: note: row {row.get('run_id')} {key} is {kind}; read as 0\n")
+    return 0
+
+
+def usd_of(row):
+    """The row's cost_usd as a finite number (0 with a stderr note otherwise); every cost read uses it."""
+    return num_of(row, "cost_usd")
+
+
~~~~

## H10 — evals/harness/ablation-report.py — insertion after head line 443

Head context (head/evals/harness/ablation-report.py, lines 432–455):

~~~~text
   432 |     for a in [x for x in (not_run or "").split(",") if x.strip()]:
   433 |         cuts.setdefault(resolve(a), {"state": "not_run_cut", "reason": "--not-run", "figure": "--not-run",
   434 |                                      "source": "--not-run"})
   435 |     return cuts
   436 | 
   437 | 
   438 | # --------------------------------------------------------------------------- the analysis
   439 | def usable(p):
   440 |     """A comparison with a valid pair that is not degenerate."""
   441 |     return p["n"] > 0 and not p.get("degenerate")
   442 | 
   443 | 
   444 | class Analysis:
   445 |     def __init__(self, suite, rows, mans, args, cap_excluded, include_degraded=False):
   446 |         self.suite, self.rules, self.args = suite, suite["rules"], args
   447 |         self.cap_excluded = cap_excluded
   448 |         # include_degraded (Sprint 262 R3): the sensitivity H1/A4 lines read degraded rows as scored
   449 |         self.exclude_degraded = bool(args.exclude_degraded) and not include_degraded
   450 |         self.arms = {a["id"]: a for a in suite["arms"] if isinstance(a, dict) and a.get("id")}
   451 |         ex = self.rules.get("exclusion") or {}
   452 |         self.ex_statuses = set(ex.get("statuses") or []) | set(DEC0417_EXCLUDED)
   453 |         self.guard = float(ex.get("inconclusive_above_share", 0.25))
   454 |         self.listed = []        # rows that never enter a decision, with the reason
   455 |         self.excluded = []      # excluded rows (status/reason), superseded included
~~~~

The change from head to the fix:

~~~~diff
@@ -443,0 +538,5 @@
+def applies_to(arm_def, ttype):
+    types = arm_def.get("task_types") or []
+    return "all" in types or ttype in types or ("build" in types and ttype in BUILD_TYPES)
+
+
~~~~

## H11 — evals/harness/ablation-report.py — head lines 484–485

Head context (head/evals/harness/ablation-report.py, lines 472–497):

~~~~text
   472 |                         self.excluded.append(self._exrow(x, f"duplicate cell; superseded by {cell['valid']['run_id']}",
   473 |                                                          counted=False))
   474 |                     elif not x["_valid"]:
   475 |                         sup = f"; superseded by {cell['valid']['run_id']}" if cell["valid"] else ""
   476 |                         self.excluded.append(self._exrow(x, x["_reason"] + sup, counted=not cell["valid"]))
   477 | 
   478 |     @staticmethod
   479 |     def _exrow(x, reason, counted):
   480 |         return {"run_id": x["run_id"], "arm": x["arm"], "task_id": x["task_id"], "trial": x["trial"],
   481 |                 "status": x["status"], "reason": reason, "cell_excluded": counted}
   482 | 
   483 |     def applies(self, arm, ttype):
>  484 |         types = self.arms[arm].get("task_types") or []
>  485 |         return "all" in types or ttype in types or ("build" in types and ttype in BUILD_TYPES)
   486 | 
   487 |     def primaries(self, arm):
   488 |         types = self.arms[arm].get("task_types") or []
   489 |         pba = self.rules.get("primaries_by_arm") or {}
   490 |         if "all" in types or REVIEW in types:
   491 |             return list(pba.get("all_types") or [PASS, CATCH])
   492 |         return list(pba.get("build_only") or [PASS])
   493 | 
   494 |     def _classify(self, row, mans):
   495 |         arm, task, ttype = row["arm"], row["task_id"], row["task_type"]
   496 |         m = mans.get(row["batch"])
   497 |         if m is None:
~~~~

The change from head to the fix:

~~~~diff
@@ -484,2 +583 @@
-        types = self.arms[arm].get("task_types") or []
-        return "all" in types or ttype in types or ("build" in types and ttype in BUILD_TYPES)
+        return applies_to(self.arms[arm], ttype)
~~~~

## H12 — evals/harness/ablation-report.py — head lines 496–510

Head context (head/evals/harness/ablation-report.py, lines 484–522):

~~~~text
   484 |         types = self.arms[arm].get("task_types") or []
   485 |         return "all" in types or ttype in types or ("build" in types and ttype in BUILD_TYPES)
   486 | 
   487 |     def primaries(self, arm):
   488 |         types = self.arms[arm].get("task_types") or []
   489 |         pba = self.rules.get("primaries_by_arm") or {}
   490 |         if "all" in types or REVIEW in types:
   491 |             return list(pba.get("all_types") or [PASS, CATCH])
   492 |         return list(pba.get("build_only") or [PASS])
   493 | 
   494 |     def _classify(self, row, mans):
   495 |         arm, task, ttype = row["arm"], row["task_id"], row["task_type"]
>  496 |         m = mans.get(row["batch"])
>  497 |         if m is None:
>  498 |             return self.listed.append((row, "no manifest for batch " + row["batch"]))
>  499 |         amap = m.get("arm_map") or {}
>  500 |         if isinstance(amap, dict) and row["run_id"] in amap and amap[row["run_id"]] != arm:
>  501 |             raise Fail(f"{row['_where']}: row {row['run_id']} arm {arm} disagrees with "
>  502 |                        f"{m['_path']} arm_map ({amap[row['run_id']]})")
>  503 |         if m.get("smoke") is True:
>  504 |             return self.listed.append((row, "smoke batch " + row["batch"]))
>  505 |         if arm not in self.arms or self.arms[arm].get("absent"):
>  506 |             return self.listed.append((row, f"arm {arm} is not run by the suite"))
>  507 |         if ttype not in BUILD_TYPES and ttype != REVIEW:
>  508 |             return self.listed.append((row, f"unknown task_type {ttype}"))
>  509 |         if not self.applies(arm, ttype):
>  510 |             return self.listed.append((row, f"not applicable: {arm} does not run {ttype} tasks"))
   511 |         self.task_type[task] = ttype
   512 |         self.arm_rows.setdefault(arm, []).append(row)
   513 |         st = row["status"]
   514 |         reason = None
   515 |         if st in self.ex_statuses:
   516 |             reason = st
   517 |         elif self.exclude_degraded and row.get("degraded") is True:
   518 |             reason = "degraded: " + str(row.get("degraded_reason") or "no reason recorded")
   519 |         elif st not in SCORING:
   520 |             reason = "status " + st
   521 |         elif st == "cap_failure" and self.cap_excluded:
   522 |             reason = "cap_failure (sensitivity figure)"
~~~~

The change from head to the fix:

~~~~diff
@@ -496,15 +594,4 @@
-        m = mans.get(row["batch"])
-        if m is None:
-            return self.listed.append((row, "no manifest for batch " + row["batch"]))
-        amap = m.get("arm_map") or {}
-        if isinstance(amap, dict) and row["run_id"] in amap and amap[row["run_id"]] != arm:
-            raise Fail(f"{row['_where']}: row {row['run_id']} arm {arm} disagrees with "
-                       f"{m['_path']} arm_map ({amap[row['run_id']]})")
-        if m.get("smoke") is True:
-            return self.listed.append((row, "smoke batch " + row["batch"]))
-        if arm not in self.arms or self.arms[arm].get("absent"):
-            return self.listed.append((row, f"arm {arm} is not run by the suite"))
-        if ttype not in BUILD_TYPES and ttype != REVIEW:
-            return self.listed.append((row, f"unknown task_type {ttype}"))
-        if not self.applies(arm, ttype):
-            return self.listed.append((row, f"not applicable: {arm} does not run {ttype} tasks"))
+        provenance_check(row, mans)
+        why = list_reason(row, mans, self.arms)
+        if why is not None:
+            return self.listed.append((row, why))
~~~~

## H13 — evals/harness/ablation-report.py — head line 549

Head context (head/evals/harness/ablation-report.py, lines 537–561):

~~~~text
   537 |     def catch_task_score(self, row):
   538 |         return 0.0 if row["status"] == "cap_failure" else float(row[CATCH])
   539 | 
   540 |     def defect_vector(self, row):
   541 |         n = self.task_defects.get(row["task_id"], 0)
   542 |         if n <= 0:
   543 |             return None, "none"
   544 |         if row["status"] == "cap_failure":
   545 |             return [0.0] * n, "cap"
   546 |         missed = row.get("defects_missed")
   547 |         if missed is None and isinstance(row.get("recall"), dict):
   548 |             missed = row["recall"].get("missed")
>  549 |         if isinstance(missed, list) and all(isinstance(x, str) for x in missed):
   550 |             ms = set(missed)
   551 |             return [0.0 if f"d{k}" in ms else 1.0 for k in range(1, n + 1)], "ids"
   552 |         return [float(row[CATCH])] * n, "rate"
   553 | 
   554 |     # -- shares
   555 |     def excluded_share(self, arm, types=None):
   556 |         """Excluded cells over the arm's cells (on tasks of `types` when given: the H1/A4 guard)."""
   557 |         cells = [c for (a, t), trials in self.cells.items() if a == arm
   558 |                  and (types is None or self.task_type.get(t) in types) for c in trials.values()]
   559 |         if not cells:
   560 |             return None, 0, 0
   561 |         ex = sum(1 for c in cells if c["valid"] is None)
~~~~

The change from head to the fix:

~~~~diff
@@ -549 +636,2 @@
-        if isinstance(missed, list) and all(isinstance(x, str) for x in missed):
+        if isinstance(missed, list) and all(isinstance(x, str) for x in missed) \
+                and missed_consistent(missed, n, row.get("defects_caught")):
~~~~

## H14 — evals/harness/ablation-report.py — head lines 595–598

Head context (head/evals/harness/ablation-report.py, lines 583–610):

~~~~text
   583 |                 for side, cs, vs in ((arm, ca, va), (ctrl, cc, vc)):
   584 |                     if vs:
   585 |                         continue
   586 |                     if not cs:
   587 |                         why.append(f"no row in {side}")
   588 |                     elif all(cs[t]["valid"] is None for t in cs):
   589 |                         why.append(f"every cell of {side} excluded")
   590 |                     else:
   591 |                         why.append(f"the cells of {side} dropped pairwise")
   592 |                 res["unpaired"].append({"task_id": task, "reason": "; ".join(why)})
   593 |                 continue
   594 |             pair = {"task_id": task, "arm_runs": [r["run_id"] for r in va], "control_runs": [r["run_id"] for r in vc],
>  595 |                     "arm_cost": mean([float(r.get("cost_usd") or 0) for r in va]),
>  596 |                     "control_cost": mean([float(r.get("cost_usd") or 0) for r in vc]),
>  597 |                     "arm_wall": mean([float(r.get("wall_clock_ms") or 0) for r in va]),
>  598 |                     "control_wall": mean([float(r.get("wall_clock_ms") or 0) for r in vc])}
   599 |             if metric == PASS:
   600 |                 ma, mc = mean([self.pass_score(r) for r in va]), mean([self.pass_score(r) for r in vc])
   601 |                 pair.update(arm_value=ma, control_value=mc, diff=ma - mc)
   602 |                 res["diffs"].append(ma - mc)
   603 |                 res["task_diffs"].append(ma - mc)
   604 |             else:
   605 |                 ma, mc = mean([self.catch_task_score(r) for r in va]), mean([self.catch_task_score(r) for r in vc])
   606 |                 pair.update(arm_value=ma, control_value=mc, diff=ma - mc)
   607 |                 res["task_diffs"].append(ma - mc)
   608 |                 vecs_a = [self.defect_vector(r) for r in va]
   609 |                 vecs_c = [self.defect_vector(r) for r in vc]
   610 |                 for _, how in vecs_a + vecs_c:
~~~~

The change from head to the fix:

~~~~diff
@@ -595,4 +683,4 @@
-                    "arm_cost": mean([float(r.get("cost_usd") or 0) for r in va]),
-                    "control_cost": mean([float(r.get("cost_usd") or 0) for r in vc]),
-                    "arm_wall": mean([float(r.get("wall_clock_ms") or 0) for r in va]),
-                    "control_wall": mean([float(r.get("wall_clock_ms") or 0) for r in vc])}
+                    "arm_cost": mean([float(usd_of(r)) for r in va]),
+                    "control_cost": mean([float(usd_of(r)) for r in vc]),
+                    "arm_wall": mean([float(num_of(r, "wall_clock_ms")) for r in va]),
+                    "control_wall": mean([float(num_of(r, "wall_clock_ms")) for r in vc])}
~~~~

## H15 — evals/harness/ablation-report.py — head lines 757–758

Head context (head/evals/harness/ablation-report.py, lines 745–770):

~~~~text
   745 | 
   746 |         def task_mean(rs_by_task, f):
   747 |             return mean([mean([f(r) for r in rs]) for rs in rs_by_task.values()])
   748 | 
   749 |         build = {t: rs for t, rs in by_task.items() if self.task_type[t] in BUILD_TYPES}
   750 |         rc = {t: rs for t, rs in by_task.items() if self.task_type[t] == REVIEW}
   751 | 
   752 |         def bools(key):
   753 |             vs = [r.get(key) for r in valid if isinstance(r.get(key), bool)]
   754 |             return None if not vs else sum(1 for v in vs if v) / len(vs)
   755 | 
   756 |         def nums(key, rs=None):
>  757 |             vs = [r.get(key) for r in (valid if rs is None else rs)
>  758 |                   if isinstance(r.get(key), (int, float)) and not isinstance(r.get(key), bool)]
   759 |             return mean(vs)
   760 | 
   761 |         # precision and cost per true defect (Sprint 262 R3, informational): the arm's valid review-catch
   762 |         # rows with a numeric defects_caught (a cap_failure counts 0 caught); false_positives null → 0
   763 |         prec = {"precision": None, "usd_per_true_defect": None, "true_defects": None, "flagged_regions": None,
   764 |                 "precision_rows": 0}
   765 |         if rc:
   766 |             caught = fp = usd = 0.0
   767 |             nrows = 0
   768 |             for rs in rc.values():
   769 |                 for r in rs:
   770 |                     c = r.get("defects_caught")
~~~~

The change from head to the fix:

~~~~diff
@@ -757,2 +845 @@
-            vs = [r.get(key) for r in (valid if rs is None else rs)
-                  if isinstance(r.get(key), (int, float)) and not isinstance(r.get(key), bool)]
+            vs = [r.get(key) for r in (valid if rs is None else rs) if is_num(r.get(key))]
~~~~

## H16 — evals/harness/ablation-report.py — head lines 773–778

Head context (head/evals/harness/ablation-report.py, lines 761–790):

~~~~text
   761 |         # precision and cost per true defect (Sprint 262 R3, informational): the arm's valid review-catch
   762 |         # rows with a numeric defects_caught (a cap_failure counts 0 caught); false_positives null → 0
   763 |         prec = {"precision": None, "usd_per_true_defect": None, "true_defects": None, "flagged_regions": None,
   764 |                 "precision_rows": 0}
   765 |         if rc:
   766 |             caught = fp = usd = 0.0
   767 |             nrows = 0
   768 |             for rs in rc.values():
   769 |                 for r in rs:
   770 |                     c = r.get("defects_caught")
   771 |                     if r["status"] == "cap_failure":
   772 |                         c = 0
>  773 |                     if isinstance(c, bool) or not isinstance(c, (int, float)):
>  774 |                         continue
>  775 |                     f = r.get("false_positives")
>  776 |                     f = f if isinstance(f, (int, float)) and not isinstance(f, bool) else 0
>  777 |                     caught, fp, nrows = caught + c, fp + f, nrows + 1
>  778 |                     usd += float(r.get("cost_usd") or 0)
   779 |             prec = {"precision": caught / (caught + fp) if caught + fp > 0 else None,
   780 |                     "usd_per_true_defect": usd / caught if caught > 0 else None,
   781 |                     "true_defects": int(caught) if float(caught).is_integer() else caught,
   782 |                     "flagged_regions": int(caught + fp) if float(caught + fp).is_integer() else caught + fp,
   783 |                     "precision_rows": nrows}
   784 |         return {
   785 |             **prec,
   786 |             "rows": len(rows), "by_status": dict(sorted(status.items())),
   787 |             "degraded_rows": sum(1 for r in rows if r.get("degraded") is True),
   788 |             "valid_cells": len(valid),
   789 |             PASS: task_mean(build, self.pass_score) if build else None,
   790 |             CATCH: task_mean(rc, self.catch_task_score) if rc else None,
~~~~

The change from head to the fix:

~~~~diff
@@ -773,6 +860,6 @@
-                    if isinstance(c, bool) or not isinstance(c, (int, float)):
+                    if not is_num(c):
                         continue
                     f = r.get("false_positives")
-                    f = f if isinstance(f, (int, float)) and not isinstance(f, bool) else 0
+                    f = f if is_num(f) else 0
                     caught, fp, nrows = caught + c, fp + f, nrows + 1
-                    usd += float(r.get("cost_usd") or 0)
+                    usd += usd_of(r)
~~~~

## H17 — evals/harness/ablation-report.py — head lines 797–798

Head context (head/evals/harness/ablation-report.py, lines 785–810):

~~~~text
   785 |             **prec,
   786 |             "rows": len(rows), "by_status": dict(sorted(status.items())),
   787 |             "degraded_rows": sum(1 for r in rows if r.get("degraded") is True),
   788 |             "valid_cells": len(valid),
   789 |             PASS: task_mean(build, self.pass_score) if build else None,
   790 |             CATCH: task_mean(rc, self.catch_task_score) if rc else None,
   791 |             "verdict_accuracy": bools("verdict_accuracy"),
   792 |             "verdict_accuracy_review": bools("verdict_accuracy_review"),
   793 |             "verdict_accuracy_audit": bools("verdict_accuracy_audit"),
   794 |             "false_positives_per_task": {t: nums("false_positives", rs) for t, rs in sorted(rc.items())},
   795 |             "regressions_per_run": nums("regressions"),
   796 |             "diff_lines_per_run": nums("diff_lines"), "files_changed_per_run": nums("files_changed"),
>  797 |             "cost_per_task": task_mean(by_task, lambda r: float(r.get("cost_usd") or 0)) if by_task else None,
>  798 |             "cost_per_run": nums("cost_usd"),
   799 |             "wall_clock_ms_per_run": nums("wall_clock_ms"),
   800 |             "tokens_in_per_run": nums("tokens_in"), "tokens_out_per_run": nums("tokens_out"),
   801 |         }
   802 | 
   803 | 
   804 | # --------------------------------------------------------------------------- rendering
   805 | def interval(p):
   806 |     if p is None or p["n"] == 0:
   807 |         return "no pair"
   808 |     return f"{f3(p['d'])} [{f3(p['lo'])}, {f3(p['hi'])}]" + (" (degenerate)" if p.get("degenerate") else "")
   809 | 
   810 | 
~~~~

The change from head to the fix:

~~~~diff
@@ -797,2 +884,2 @@
-            "cost_per_task": task_mean(by_task, lambda r: float(r.get("cost_usd") or 0)) if by_task else None,
-            "cost_per_run": nums("cost_usd"),
+            "cost_per_task": task_mean(by_task, lambda r: float(usd_of(r))) if by_task else None,
+            "cost_per_run": mean([usd_of(r) for r in valid]),
~~~~

## H18 — evals/harness/ablation-report.py — head lines 825–851

Head context (head/evals/harness/ablation-report.py, lines 813–863):

~~~~text
   813 |     out.update({k: j6(p[k]) for k in ("d", "lo", "hi", "mde", "half_width")})
   814 |     out["pairs"] = [{"task_id": x["task_id"], "arm_value": j6(x["arm_value"]), "control_value": j6(x["control_value"]),
   815 |                      "diff": j6(x["diff"]), "defects": x.get("defects"),
   816 |                      "arm_runs": x["arm_runs"], "control_runs": x["control_runs"]} for x in p["pairs"]]
   817 |     out["degenerate"] = bool(p.get("degenerate"))
   818 |     if p.get("degenerate"):
   819 |         out["degenerate_reason"] = p["degenerate_reason"]
   820 |     if "task_level" in p:
   821 |         out["task_level"] = {k: (j6(v) if isinstance(v, float) else v) for k, v in p["task_level"].items()}
   822 |     return out
   823 | 
   824 | 
>  825 | def version_key(v):
>  826 |     """The partition key of a row's suite_version: 1, 1.0 and "1" are one version; None = absent."""
>  827 |     if v is None or isinstance(v, bool):
>  828 |         return None
>  829 |     if isinstance(v, int):
>  830 |         return str(v)
>  831 |     if isinstance(v, float) and v.is_integer():
>  832 |         return str(int(v))
>  833 |     if isinstance(v, str) and v.strip():
>  834 |         s = v.strip()
>  835 |         return str(int(s)) if re.fullmatch(r"\d+", s) else s
>  836 |     return None
>  837 | 
>  838 | 
>  839 | def version_order(k):
>  840 |     return (0, int(k), "") if k.isdigit() else (1, 0, k)
>  841 | 
>  842 | 
>  843 | def partition(rows, wanted):
>  844 |     """Rows by suite_version, never pooled; returns ({key: rows}, primary key)."""
>  845 |     keys = sorted({k for k in (version_key(r.get("suite_version")) for r in rows) if k is not None}, key=version_order)
>  846 |     missing = [r for r in rows if version_key(r.get("suite_version")) is None]
>  847 |     if len(keys) > 1 and missing:
>  848 |         r = missing[0]
>  849 |         raise Fail(f"{r['_where']}: row {r['run_id']} has no suite_version while the rows hold suite_version "
>  850 |                    f"{', '.join(keys)}; rows of different suite versions are never pooled, so every row must "
>  851 |                    f"name its suite_version")
   852 |     if len(keys) <= 1:
   853 |         groups = {(keys[0] if keys else "n/a"): list(rows)}
   854 |     else:
   855 |         groups = {k: [r for r in rows if version_key(r.get("suite_version")) == k] for k in keys}
   856 |     if wanted is not None:
   857 |         w = version_key(wanted)
   858 |         if w not in groups:
   859 |             raise Fail(f"--suite-version {wanted}: no row has that suite_version (present: {', '.join(groups)})")
   860 |         return groups, w
   861 |     return groups, max(groups, key=version_order)
   862 | 
   863 | 
~~~~

The change from head to the fix:

~~~~diff
@@ -825,27 +912,100 @@
+NUMERIC = re.compile(r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?")
+
+
 def version_key(v):
-    """The partition key of a row's suite_version: 1, 1.0 and "1" are one version; None = absent."""
+    """The partition key of a row's suite_version (report 1.2.1): 2, 2.0 and "2" are one version ("2");
+    a non-integer number keys to its shortest round-trip form (2.1 and "2.10" → "2.1"); any other
+    string keys to itself, stripped. Absent (None) = None, a boolean, an empty or blank string, or a
+    value that is neither a number nor a string."""
     if v is None or isinstance(v, bool):
         return None
+    if isinstance(v, str):
+        s = v.strip()
+        if not s:
+            return None
+        if not NUMERIC.fullmatch(s):
+            return s
+        v = int(s) if re.fullmatch(r"[+-]?\d+", s) else float(s)
+        if isinstance(v, float) and not math.isfinite(v):
+            return s
     if isinstance(v, int):
         return str(v)
-    if isinstance(v, float) and v.is_integer():
-        return str(int(v))
-    if isinstance(v, str) and v.strip():
-        s = v.strip()
-        return str(int(s)) if re.fullmatch(r"\d+", s) else s
+    if isinstance(v, float):
+        if not math.isfinite(v):
+            return repr(v)
+        return str(int(v)) if v.is_integer() else repr(v)
     return None
 
 
+def version_value(k):
+    """A version key as a JSON value: an integer key → int, another numeric key → float, "n/a" (or None) →
+    null, any other key → the string. Every JSON emitter of a version key goes through it (report 1.2.2)."""
+    if k is None or k == "n/a":
+        return None
+    if not isinstance(k, str):
+        return k
+    if re.fullmatch(r"[+-]?\d+", k):
+        return int(k)
+    o = version_order(k)
+    return o[1] if o[0] == 0 else k
+
+
 def version_order(k):
-    return (0, int(k), "") if k.isdigit() else (1, 0, k)
+    """Sort key over version keys: numeric keys numerically, every other key after them, lexically."""
+    if NUMERIC.fullmatch(k):
+        f = float(k)
+        if math.isfinite(f):
+            return (0, f, k)
+    return (1, 0.0, k)
 
 
-def partition(rows, wanted):
-    """Rows by suite_version, never pooled; returns ({key: rows}, primary key)."""
+def provenance_check(row, mans):
+    """DEC-0407: a row whose batch manifest arm_map names another arm for its run_id stops the report
+    (exit 2). Run on every row by partition() before any listing decision and again by
+    Analysis._classify (report 1.2.2)."""
+    m = mans.get(row.get("batch"))
+    if m is None:
+        return
+    amap = m.get("arm_map") or {}
+    if isinstance(amap, dict) and row["run_id"] in amap and amap[row["run_id"]] != row["arm"]:
+        raise Fail(f"{row['_where']}: row {row['run_id']} arm {row['arm']} disagrees with "
+                   f"{m['_path']} arm_map ({amap[row['run_id']]})")
+
+
+def list_reason(row, mans, arms):
+    """Why a row is listed and never decided, or None when it enters a cell (the first checks of
+    Analysis._classify, after provenance_check); partition() reuses it (report 1.2.1)."""
+    m = mans.get(row.get("batch"))
+    if m is None:
+        return "no manifest for batch " + str(row.get("batch"))
+    if m.get("smoke") is True:
+        return "smoke batch " + str(row.get("batch"))
+    arm, ttype = row.get("arm"), row.get("task_type")
+    if arm not in arms or arms[arm].get("absent"):
+        return f"arm {arm} is not run by the suite"
+    if ttype not in BUILD_TYPES and ttype != REVIEW:
+        return f"unknown task_type {ttype}"
+    if not applies_to(arms[arm], ttype):
+        return f"not applicable: {arm} does not run {ttype} tasks"
+    return None
+
+
+def partition(rows, wanted, mans=None, arms=None):
+    """Rows by suite_version, never pooled; returns ({key: rows}, primary key, version-less rows listed
+    under the primary). Among two or more versions a version-less row that would enter a cell stops the
+    report; one that would be listed anyway (no manifest, smoke batch, arm not run, unknown or
+    inapplicable task type) is returned with its reason, never pooled into a version. Every row passes
+    provenance_check first (report 1.2.2), so no listing decision bypasses the arm_map check."""
+    for r in rows:
+        provenance_check(r, mans or {})
     keys = sorted({k for k in (version_key(r.get("suite_version")) for r in rows) if k is not None}, key=version_order)
     missing = [r for r in rows if version_key(r.get("suite_version")) is None]
+    unversioned = []
     if len(keys) > 1 and missing:
-        r = missing[0]
-        raise Fail(f"{r['_where']}: row {r['run_id']} has no suite_version while the rows hold suite_version "
-                   f"{', '.join(keys)}; rows of different suite versions are never pooled, so every row must "
-                   f"name its suite_version")
+        for r in missing:
+            why = list_reason(r, mans or {}, arms or {}) if arms is not None else None
+            if why is None:
+                raise Fail(f"{r['_where']}: row {r['run_id']} has no suite_version while the rows hold suite_version "
+                           f"{', '.join(keys)}; rows of different suite versions are never pooled, so every row must "
+                           f"name its suite_version")
+            unversioned.append((r, "no suite_version; " + why))
~~~~

## H19 — evals/harness/ablation-report.py — head lines 860–861

Head context (head/evals/harness/ablation-report.py, lines 848–873):

~~~~text
   848 |         r = missing[0]
   849 |         raise Fail(f"{r['_where']}: row {r['run_id']} has no suite_version while the rows hold suite_version "
   850 |                    f"{', '.join(keys)}; rows of different suite versions are never pooled, so every row must "
   851 |                    f"name its suite_version")
   852 |     if len(keys) <= 1:
   853 |         groups = {(keys[0] if keys else "n/a"): list(rows)}
   854 |     else:
   855 |         groups = {k: [r for r in rows if version_key(r.get("suite_version")) == k] for k in keys}
   856 |     if wanted is not None:
   857 |         w = version_key(wanted)
   858 |         if w not in groups:
   859 |             raise Fail(f"--suite-version {wanted}: no row has that suite_version (present: {', '.join(groups)})")
>  860 |         return groups, w
>  861 |     return groups, max(groups, key=version_order)
   862 | 
   863 | 
   864 | def assess(an, arm, ctrl, p):
   865 |     """How H1/A4 reads one comparison: not_testable | inconclusive_by_degradation | degenerate | no_pair | tested."""
   866 |     types = (REVIEW,) if p["metric"] == CATCH else BUILD_TYPES
   867 |     if not p["pairs"] and not p["unpaired"]:
   868 |         return "not_testable", None
   869 |     over = []
   870 |     for a in (arm, ctrl):
   871 |         s, _, _ = an.excluded_share(a, types)
   872 |         if s is not None and r9(s) > an.guard:
   873 |             over.append(f"{a} excluded share {s:.3f} > {an.guard:g}")
~~~~

The change from head to the fix:

~~~~diff
@@ -860,2 +1020,2 @@
-        return groups, w
-    return groups, max(groups, key=version_order)
+        return groups, w, unversioned
+    return groups, max(groups, key=version_order), unversioned
~~~~

## H20 — evals/harness/ablation-report.py — head lines 965–968

Head context (head/evals/harness/ablation-report.py, lines 953–980):

~~~~text
   953 |     for t in tasks:
   954 |         a0, a1 = valid(BARE, t), valid(CONTROL, t)
   955 |         e = {"task_id": t, "a0_trials": len(a0), "a1_trials": len(a1), "a0_union": None, "a0_cost_sum": None,
   956 |              "a1_mean": None, "a1_cost_mean": None, "diff": None, "method": None, "reason": None}
   957 |         if a0:
   958 |             vecs = [an.defect_vector(r) for r in a0]
   959 |             if all(vv is not None and how in ("ids", "cap") for vv, how in vecs):
   960 |                 e["a0_union"] = mean([max(vv[k] for vv, _ in vecs) for k in range(len(vecs[0][0]))])
   961 |                 e["method"] = "defect union"
   962 |             else:
   963 |                 e["a0_union"] = max(an.catch_task_score(r) for r in a0)
   964 |                 e["method"] = "rate fallback"
>  965 |             e["a0_cost_sum"] = sum(float(r.get("cost_usd") or 0) for r in a0)
>  966 |         if a1:
>  967 |             e["a1_mean"] = mean([an.catch_task_score(r) for r in a1])
>  968 |             e["a1_cost_mean"] = mean([float(r.get("cost_usd") or 0) for r in a1])
   969 |         if a0 and a1:
   970 |             e["diff"] = e["a1_mean"] - e["a0_union"]
   971 |         else:
   972 |             e["reason"] = "; ".join(f"no valid {a} trial" for a, rs in ((BARE, a0), (CONTROL, a1)) if not rs)
   973 |         out["tasks"].append(e)
   974 |     both = [e for e in out["tasks"] if e["diff"] is not None]
   975 |     if not both:
   976 |         out["available"] = False
   977 |         out["note"] = f"not available on suite_version {v} — no review-catch task has valid trials in both arms"
   978 |         return out
   979 |     out["a0_union_mean"] = mean([e["a0_union"] for e in both])
   980 |     out["a1_mean"] = mean([e["a1_mean"] for e in both])
~~~~

The change from head to the fix:

~~~~diff
@@ -965,4 +1125,4 @@
-            e["a0_cost_sum"] = sum(float(r.get("cost_usd") or 0) for r in a0)
+            e["a0_cost_sum"] = sum(float(usd_of(r)) for r in a0)
         if a1:
             e["a1_mean"] = mean([an.catch_task_score(r) for r in a1])
-            e["a1_cost_mean"] = mean([float(r.get("cost_usd") or 0) for r in a1])
+            e["a1_cost_mean"] = mean([float(usd_of(r)) for r in a1])
~~~~

## H21 — evals/harness/ablation-report.py — head lines 992–996

Head context (head/evals/harness/ablation-report.py, lines 980–1008):

~~~~text
   980 |     out["a1_mean"] = mean([e["a1_mean"] for e in both])
   981 |     out["diff_mean"] = out["a1_mean"] - out["a0_union_mean"]
   982 |     k = sorted({e["a0_trials"] for e in both})
   983 |     kk = str(k[0]) if len(k) == 1 else "the"
   984 |     x = mean([e["a0_cost_sum"] for e in both])
   985 |     y = mean([e["a1_cost_mean"] for e in both])
   986 |     out["a0_cost_sum_mean"], out["a1_cost_mean"] = x, y
   987 |     out["note"] = (f"{kk} a0_bare trials cost USD {x:.2f} vs one a1_full trial USD {y:.2f} "
   988 |                    f"(task means over {len(both)} task{'' if len(both) == 1 else 's'})")
   989 |     return out
   990 | 
   991 | 
>  992 | def batch_record(mans, rows):
>  993 |     """Each batch's STATUS.json (beside its MANIFEST.json, read-only) and the grader versions of its rows'
>  994 |     run directories (Sprint 262 R3); a missing file or directory is reported, never fatal."""
>  995 |     out = []
>  996 |     for b, m in sorted(mans.items()):
   997 |         d = os.path.dirname(m["_path"])
   998 |         brows = [r for r in rows if r["batch"] == b]
   999 |         vks = sorted({k for k in (version_key(r.get("suite_version")) for r in brows) if k is not None},
  1000 |                      key=version_order)
  1001 |         sv = version_key(m.get("suite_version")) or (", ".join(vks) if vks else "n/a")
  1002 |         e = {"batch": b, "suite_version": sv, "smoke": m.get("smoke") is True, "status_file": None,
  1003 |              "status_note": None, "state": None, "trials_planned": None, "trials_rowed": len(brows),
  1004 |              "spend": None, "extra_models": {}, "rerowed": 0, "rerowed_tally": {}, "rerun": 0,
  1005 |              "rerun_tally": {}, "drift_cleared": 0, "outage_history": 0, "cuts": [], "paused_arms": [],
  1006 |              "grader_versions": {}, "run_dirs_missing": 0}
  1007 |         sp = os.path.join(d, "STATUS.json")
  1008 |         st = None
~~~~

The change from head to the fix:

~~~~diff
@@ -992,5 +1152,16 @@
-def batch_record(mans, rows):
+def stage_note(x, stage):
+    """The sanitized text of a never-fatal exception (report 1.2.3, audit DISS-C-002): the exception class
+    and a fixed phrase naming the stage, never str(x) (which can carry a value from a file or a host path);
+    the full text goes to stderr once."""
+    sys.stderr.write(f"ablation-report.py: {type(x).__name__} while {stage}: {x}\n")
+    return f"{type(x).__name__} while {stage}"
+
+
+def batch_record(mans, rows, where=None):
     """Each batch's STATUS.json (beside its MANIFEST.json, read-only) and the grader versions of its rows'
-    run directories (Sprint 262 R3); a missing file or directory is reported, never fatal."""
+    run directories (Sprint 262 R3); a missing file or directory is reported, never fatal. `where` (a
+    dict) holds the current stage for the caller's sanitized "Not rendered" text."""
+    where = {} if where is None else where
     out = []
     for b, m in sorted(mans.items()):
+        where["stage"] = f"reading the batch record of {b}"
~~~~

## H22 — evals/harness/ablation-report.py — head lines 1006–1084

Head context (head/evals/harness/ablation-report.py, lines 994–1096):

~~~~text
   994 |     run directories (Sprint 262 R3); a missing file or directory is reported, never fatal."""
   995 |     out = []
   996 |     for b, m in sorted(mans.items()):
   997 |         d = os.path.dirname(m["_path"])
   998 |         brows = [r for r in rows if r["batch"] == b]
   999 |         vks = sorted({k for k in (version_key(r.get("suite_version")) for r in brows) if k is not None},
  1000 |                      key=version_order)
  1001 |         sv = version_key(m.get("suite_version")) or (", ".join(vks) if vks else "n/a")
  1002 |         e = {"batch": b, "suite_version": sv, "smoke": m.get("smoke") is True, "status_file": None,
  1003 |              "status_note": None, "state": None, "trials_planned": None, "trials_rowed": len(brows),
  1004 |              "spend": None, "extra_models": {}, "rerowed": 0, "rerowed_tally": {}, "rerun": 0,
  1005 |              "rerun_tally": {}, "drift_cleared": 0, "outage_history": 0, "cuts": [], "paused_arms": [],
> 1006 |              "grader_versions": {}, "run_dirs_missing": 0}
> 1007 |         sp = os.path.join(d, "STATUS.json")
> 1008 |         st = None
> 1009 |         if os.path.islink(sp):
> 1010 |             e["status_note"] = "STATUS.json is a symlink (not read)"
> 1011 |         elif not os.path.isfile(sp):
> 1012 |             e["status_note"] = "no STATUS.json"
> 1013 |         else:
> 1014 |             try:
> 1015 |                 with open(sp, encoding="utf-8") as fh:
> 1016 |                     st = json.load(fh)
> 1017 |             except (OSError, ValueError):
> 1018 |                 st = None
> 1019 |             if not isinstance(st, dict):
> 1020 |                 st, e["status_note"] = None, "STATUS.json unreadable"
> 1021 |         if st is not None:
> 1022 |             e["status_file"] = sp
> 1023 | 
> 1024 |             def lst(k):
> 1025 |                 x = st.get(k)
> 1026 |                 return x if isinstance(x, list) else []
> 1027 | 
> 1028 |             def tally(k):
> 1029 |                 t = {}
> 1030 |                 for x in lst(k):
> 1031 |                     if isinstance(x, dict):
> 1032 |                         key = f"{x.get('from', '?')}→{x.get('to', '?')}"
> 1033 |                         t[key] = t.get(key, 0) + 1
> 1034 |                 return dict(sorted(t.items()))
> 1035 | 
> 1036 |             sd = st.get("spend") if isinstance(st.get("spend"), dict) else {}
> 1037 |             e.update(state=st.get("state"), trials_planned=st.get("trials_planned"),
> 1038 |                      spend={k: sd.get(k) for k in ("rows_usd", "ledger_usd", "spent_usd", "max_usd")},
> 1039 |                      rerowed=len(lst("rerowed")), rerowed_tally=tally("rerowed"),
> 1040 |                      rerun=len(lst("rerun")), rerun_tally=tally("rerun"),
> 1041 |                      drift_cleared=len(lst("drift_cleared")), outage_history=len(lst("outage_history")),
> 1042 |                      cuts=[{k: c.get(k) for k in ("reason", "at_trial", "spent", "max") if k in c}
> 1043 |                            for c in lst("cuts") if isinstance(c, dict)])
> 1044 |             em = st.get("extra_models")
> 1045 |             if isinstance(em, dict):
> 1046 |                 e["extra_models"] = {str(k): {"runs": (x or {}).get("runs"), "output_tokens": (x or {}).get("output_tokens")}
> 1047 |                                      for k, x in sorted(em.items()) if isinstance(x, dict) or x is None}
> 1048 |             pa = st.get("paused_arms")
> 1049 |             e["paused_arms"] = sorted(str(x) for x in (pa if isinstance(pa, (dict, list)) else []))
> 1050 |         # grader versions: <batch dir>/<arm>/<task>-t<n>[-r<k>]/grade.json
> 1051 |         listing = {}
> 1052 |         gv = {}
> 1053 |         for r in brows:
> 1054 |             ad = os.path.join(d, r["arm"])
> 1055 |             if ad not in listing:
> 1056 |                 try:
> 1057 |                     listing[ad] = sorted(x for x in os.listdir(ad) if not os.path.islink(os.path.join(ad, x))
> 1058 |                                          and os.path.isdir(os.path.join(ad, x))) \
> 1059 |                         if os.path.isdir(ad) and not os.path.islink(ad) else []
> 1060 |                 except OSError:
> 1061 |                     listing[ad] = []
> 1062 |             dirs = []
> 1063 |             for x in listing[ad]:
> 1064 |                 mm = GRADE_DIR.fullmatch(x)
> 1065 |                 if mm and mm.group(1) == r["task_id"] and int(mm.group(2)) == r["trial"]:
> 1066 |                     dirs.append(x)
> 1067 |             if not dirs:
> 1068 |                 e["run_dirs_missing"] += 1
> 1069 |             for x in dirs:
> 1070 |                 gp = os.path.join(ad, x, "grade.json")
> 1071 |                 ver = "n/a"
> 1072 |                 if os.path.isfile(gp) and not os.path.islink(gp):
> 1073 |                     try:
> 1074 |                         with open(gp, encoding="utf-8") as fh:
> 1075 |                             g = json.load(fh)
> 1076 |                         if isinstance(g, dict) and g.get("grader_version") not in (None, ""):
> 1077 |                             ver = str(g["grader_version"])
> 1078 |                     except (OSError, ValueError):
> 1079 |                         pass
> 1080 |                 gv[ver] = gv.get(ver, 0) + 1
> 1081 |         e["grader_versions"] = dict(sorted(gv.items(), key=lambda kv: (
> 1082 |             kv[0] == "n/a", [int(p) if p.isdigit() else p for p in re.split(r"[.]", kv[0])])))
> 1083 |         out.append(e)
> 1084 |     return out
  1085 | 
  1086 | 
  1087 | def render_budget(L, B, h):
  1088 |     L(f"{h} Budget-matched baseline (suite_version {B['suite_version']}; {BUDGET_LABEL})")
  1089 |     L("")
  1090 |     if not B["available"]:
  1091 |         L(f"- {B['note']}")
  1092 |         L("")
  1093 |         return
  1094 |     L("Per review-catch task: the union of the defects any valid a0_bare trial caught (a defect counts once "
  1095 |       "caught by any trial; \"rate fallback\" is the best trial's rate where the rows carry no per-defect ids), "
  1096 |       "against a1_full's mean per-trial catch rate. Nothing here feeds a decision.")
~~~~

The change from head to the fix:

~~~~diff
@@ -1006,79 +1177,171 @@
-             "grader_versions": {}, "run_dirs_missing": 0}
-        sp = os.path.join(d, "STATUS.json")
-        st = None
-        if os.path.islink(sp):
-            e["status_note"] = "STATUS.json is a symlink (not read)"
-        elif not os.path.isfile(sp):
-            e["status_note"] = "no STATUS.json"
+             "grader_versions": {}, "run_dirs_missing": 0, "note": None}
+        try:
+            batch_status(e, d)
+        except Exception as x:  # never fatal: a presentation-only section
+            e["note"] = f"STATUS.json record incomplete ({stage_note(x, f'reading the STATUS.json of {b}')})"
+        # grader versions (report 1.2.1): each row's own run directory, counted once
+        try:
+            grader_tally(e, d, brows)
+        except Exception as x:  # never fatal: a presentation-only section
+            note = f"grader tally incomplete ({stage_note(x, f'tallying the grader versions of {b}')})"
+            e["note"] = note if e["note"] is None else e["note"] + "; " + note
+        out.append(e)
+    where["stage"] = "rendering the batch record"
+    return out
+
+
+def batch_status(e, d):
+    """Fill one batch record from the STATUS.json in d (read-only; a symlink is not read)."""
+    sp = os.path.join(d, "STATUS.json")
+    st = None
+    if os.path.islink(sp):
+        e["status_note"] = "STATUS.json is a symlink (not read)"
+    elif not os.path.isfile(sp):
+        e["status_note"] = "no STATUS.json"
+    else:
+        try:
+            with open(sp, encoding="utf-8") as fh:
+                st = json.load(fh)
+        except (OSError, ValueError):
+            st = None
+        if not isinstance(st, dict):
+            st, e["status_note"] = None, "STATUS.json unreadable"
+    if st is not None:
+        e["status_file"] = sp
+
+        def lst(k):
+            x = st.get(k)
+            return x if isinstance(x, list) else []
+
+        def tally(k):
+            t = {}
+            for x in lst(k):
+                if isinstance(x, dict):
+                    key = f"{x.get('from', '?')}→{x.get('to', '?')}"
+                    t[key] = t.get(key, 0) + 1
+            return dict(sorted(t.items()))
+
+        sd = st.get("spend") if isinstance(st.get("spend"), dict) else {}
+        e.update(state=st.get("state"), trials_planned=st.get("trials_planned"),
+                 spend={k: sd.get(k) for k in ("rows_usd", "ledger_usd", "spent_usd", "max_usd")},
+                 rerowed=len(lst("rerowed")), rerowed_tally=tally("rerowed"),
+                 rerun=len(lst("rerun")), rerun_tally=tally("rerun"),
+                 drift_cleared=len(lst("drift_cleared")), outage_history=len(lst("outage_history")),
+                 cuts=[{k: c.get(k) for k in ("reason", "at_trial", "spent", "max") if k in c}
+                       for c in lst("cuts") if isinstance(c, dict)])
+        em = st.get("extra_models")
+        if isinstance(em, dict):
+            e["extra_models"] = {str(k): {"runs": (x or {}).get("runs"), "output_tokens": (x or {}).get("output_tokens")}
+                                 for k, x in sorted(em.items()) if isinstance(x, dict) or x is None}
+        pa = st.get("paused_arms")
+        e["paused_arms"] = sorted(str(x) for x in (pa if isinstance(pa, (dict, list)) else []))
+
+
+def contained(root, base, *parts):
+    """base joined with parts, or None unless no component below base is a symlink and the realpath stays
+    inside realpath(root), the batch's manifest directory (report 1.2.3, audit DISS-C-004)."""
+    p = base
+    for part in parts:
+        p = os.path.join(p, part)
+        if os.path.islink(p):
+            return None
+    rr = os.path.realpath(root)
+    rp = os.path.realpath(p)
+    return p if rp == rr or rp.startswith(rr + os.sep) else None
+
+
+def run_dir_of(ad, names, r, root=None):
+    """The row's own run directory under the arm directory ad (names: its subdirectories): the highest
+    <task>-t<n>-r<k> whose meta/pipeline.json run_id equals the row's, else the highest -r<k> holding a
+    grade.json, else <task>-t<n>, else the highest -r<k> (its grade absent: n/a); None when the row has
+    none of them. The trial n compares numerically, so rc-01-t01 is trial 1 (report 1.2.2). root: the batch's
+    manifest directory; every file read below ad stays inside it (report 1.2.3)."""
+    root = ad if root is None else root
+    task, trial = r["task_id"], r["trial"]
+    reruns, bases = [], []
+    for x in names:
+        mm = GRADE_DIR.fullmatch(x)
+        if not mm or mm.group(1) != task or int(mm.group(2)) != trial:
+            continue
+        if mm.group(3) is not None:
+            reruns.append((int(mm.group(3)), x))
         else:
-            try:
-                with open(sp, encoding="utf-8") as fh:
-                    st = json.load(fh)
-            except (OSError, ValueError):
-                st = None
-            if not isinstance(st, dict):
-                st, e["status_note"] = None, "STATUS.json unreadable"
-        if st is not None:
-            e["status_file"] = sp
+            bases.append(x)
+    reruns.sort(reverse=True)
+    for _, x in reruns:
+        pj = read_json_file(contained(root, ad, x, "meta", "pipeline.json"))
+        if isinstance(pj, dict) and pj.get("run_id") == r["run_id"]:
+            return x
+    for _, x in reruns:
+        gp = contained(root, ad, x, "grade.json")
+        if gp is not None and os.path.isfile(gp):
+            return x
+    if bases:  # the canonical <task>-t<n> first, else the lexically first zero-padded form
+        canon = f"{task}-t{trial}"
+        return canon if canon in bases else sorted(bases)[0]
+    return reruns[0][1] if reruns else None
 
-            def lst(k):
-                x = st.get(k)
-                return x if isinstance(x, list) else []
 
-            def tally(k):
-                t = {}
-                for x in lst(k):
-                    if isinstance(x, dict):
-                        key = f"{x.get('from', '?')}→{x.get('to', '?')}"
-                        t[key] = t.get(key, 0) + 1
-                return dict(sorted(t.items()))
+def read_json_file(p):
+    """A JSON file's content, None when p is None, absent, a symlink, unreadable or not JSON."""
+    if p is None or not os.path.isfile(p) or os.path.islink(p):
+        return None
+    try:
+        with open(p, encoding="utf-8") as fh:
+            return json.load(fh)
+    except (OSError, ValueError):
+        return None
 
-            sd = st.get("spend") if isinstance(st.get("spend"), dict) else {}
-            e.update(state=st.get("state"), trials_planned=st.get("trials_planned"),
-                     spend={k: sd.get(k) for k in ("rows_usd", "ledger_usd", "spent_usd", "max_usd")},
-                     rerowed=len(lst("rerowed")), rerowed_tally=tally("rerowed"),
-                     rerun=len(lst("rerun")), rerun_tally=tally("rerun"),
-                     drift_cleared=len(lst("drift_cleared")), outage_history=len(lst("outage_history")),
-                     cuts=[{k: c.get(k) for k in ("reason", "at_trial", "spent", "max") if k in c}
-                           for c in lst("cuts") if isinstance(c, dict)])
-            em = st.get("extra_models")
-            if isinstance(em, dict):
-                e["extra_models"] = {str(k): {"runs": (x or {}).get("runs"), "output_tokens": (x or {}).get("output_tokens")}
-                                     for k, x in sorted(em.items()) if isinstance(x, dict) or x is None}
-            pa = st.get("paused_arms")
-            e["paused_arms"] = sorted(str(x) for x in (pa if isinstance(pa, (dict, list)) else []))
-        # grader versions: <batch dir>/<arm>/<task>-t<n>[-r<k>]/grade.json
-        listing = {}
-        gv = {}
+
+def grader_key(kv):
+    """Type-stable sort key of a grader-version tally entry: "n/a" last; dotted segments compare
+    numerically when digits, lexically otherwise, digits first (1.2.0 < 1.2.0-rc1 < 1.2.1)."""
+    return (kv[0] == "n/a", [(0, int(p), "") if p.isdigit() else (1, 0, p) for p in kv[0].split(".")])
+
+
+def grader_tally(e, d, brows):
+    """The grade.json grader_version of each row's own run directory, counted once per row ("n/a" when
+    the directory or its grade is absent); run_dirs_missing counts the rows with no attributable
+    directory (run_dir_of returns None)."""
+    listing, gv, off_grammar = {}, {}, 0
+    try:
         for r in brows:
-            ad = os.path.join(d, r["arm"])
+            # report 1.2.3 (audit DISS-C-004): the arm and task_id grammars before any path is built; a row
+            # outside them has no attributable directory and is never used in a path
+            if not (isinstance(r.get("arm"), str) and ARM_GRAMMAR.fullmatch(r["arm"])
+                    and isinstance(r.get("task_id"), str) and TASK_GRAMMAR.fullmatch(r["task_id"])):
+                off_grammar += 1
+                e["run_dirs_missing"] += 1
+                gv["n/a"] = gv.get("n/a", 0) + 1
+                continue
+            ad = contained(d, d, r["arm"])
+            if ad is None:  # the arm directory is a symlink or resolves outside the batch directory
+                e["run_dirs_missing"] += 1
+                gv["n/a"] = gv.get("n/a", 0) + 1
+                continue
             if ad not in listing:
                 try:
-                    listing[ad] = sorted(x for x in os.listdir(ad) if not os.path.islink(os.path.join(ad, x))
-                                         and os.path.isdir(os.path.join(ad, x))) \
-                        if os.path.isdir(ad) and not os.path.islink(ad) else []
+                    listing[ad] = set(x for x in os.listdir(ad) if not os.path.islink(os.path.join(ad, x))
+                                      and os.path.isdir(os.path.join(ad, x))) \
+                        if os.path.isdir(ad) and not os.path.islink(ad) else set()
                 except OSError:
-                    listing[ad] = []
-            dirs = []
-            for x in listing[ad]:
-                mm = GRADE_DIR.fullmatch(x)
-                if mm and mm.group(1) == r["task_id"] and int(mm.group(2)) == r["trial"]:
-                    dirs.append(x)
-            if not dirs:
+                    listing[ad] = set()
+            x = run_dir_of(ad, listing[ad], r, d)
+            ver = "n/a"
+            if x is None:
                 e["run_dirs_missing"] += 1
-            for x in dirs:
-                gp = os.path.join(ad, x, "grade.json")
-                ver = "n/a"
-                if os.path.isfile(gp) and not os.path.islink(gp):
-                    try:
-                        with open(gp, encoding="utf-8") as fh:
-                            g = json.load(fh)
-                        if isinstance(g, dict) and g.get("grader_version") not in (None, ""):
-                            ver = str(g["grader_version"])
-                    except (OSError, ValueError):
-                        pass
-                gv[ver] = gv.get(ver, 0) + 1
-        e["grader_versions"] = dict(sorted(gv.items(), key=lambda kv: (
-            kv[0] == "n/a", [int(p) if p.isdigit() else p for p in re.split(r"[.]", kv[0])])))
-        out.append(e)
-    return out
+            else:
+                g = read_json_file(contained(d, ad, x, "grade.json"))
+                if isinstance(g, dict) and g.get("grader_version") not in (None, ""):
+                    ver = str(g["grader_version"])
+            gv[ver] = gv.get(ver, 0) + 1
+    finally:
+        if off_grammar:
+            note = (f"{off_grammar} row{'' if off_grammar == 1 else 's'} with an arm or task_id outside the "
+                    f"grammar (no attributable directory)")
+            e["note"] = note if e["note"] is None else e["note"] + "; " + note
+        try:
+            e["grader_versions"] = dict(sorted(gv.items(), key=grader_key))
+        except Exception:
+            e["grader_versions"] = dict(gv)
+            raise
~~~~

## H23 — evals/harness/ablation-report.py — head line 1117

Head context (head/evals/harness/ablation-report.py, lines 1105–1129):

~~~~text
  1105 |     for e in B["tasks"]:
  1106 |         L(f"| {e['task_id']} | {e['a0_trials']} | {u3(e['a0_union'])} | {usd(e['a0_cost_sum'])} | {e['a1_trials']} | "
  1107 |           f"{u3(e['a1_mean'])} | {usd(e['a1_cost_mean'])} | {f3(e['diff'])} | "
  1108 |           f"{md_cell(e['method'] or 'n/a')}{'; ' + md_cell(e['reason']) if e['reason'] else ''} |")
  1109 |     L("")
  1110 |     L(f"- task mean (tasks with both arms): a0_bare union {u3(B['a0_union_mean'])}, a1_full per-trial "
  1111 |       f"{u3(B['a1_mean'])}, a1 − a0 union {f3(B['diff_mean'])}")
  1112 |     L(f"- matched cost: {B['note']}")
  1113 |     L("")
  1114 | 
  1115 | 
  1116 | def budget_json(B):
> 1117 |     return {k: (j6(x) if isinstance(x, float) else
  1118 |                 [{kk: (j6(y) if isinstance(y, float) else y) for kk, y in t.items()} for t in x] if k == "tasks" else x)
  1119 |             for k, x in B.items()}
  1120 | 
  1121 | 
  1122 | def render_batches(L, recs):
  1123 |     L("## Batch record")
  1124 |     L("")
  1125 |     L("From each batch's STATUS.json beside its MANIFEST.json (read-only) and the `grade.json` grader_version "
  1126 |       "of its rows' run directories (`<batch>/<arm>/<task>-t<n>[-r<k>]`); a tally is `from→to ×n`.")
  1127 |     L("")
  1128 | 
  1129 |     def usd(x):
~~~~

The change from head to the fix:

~~~~diff
@@ -1117 +1380 @@
-    return {k: (j6(x) if isinstance(x, float) else
+    return {k: (version_value(x) if k == "suite_version" else j6(x) if isinstance(x, float) else
~~~~

## H24 — evals/harness/ablation-report.py — insertion after head line 1145

Head context (head/evals/harness/ablation-report.py, lines 1134–1157):

~~~~text
  1134 | 
  1135 |     for v in sorted({e["suite_version"] for e in recs}, key=lambda k: version_order(k) if k else (2, 0, "")):
  1136 |         L(f"### suite_version {v}")
  1137 |         L("")
  1138 |         L("| batch | state | trials planned / rowed | spend USD rows / ledger / spent / max | extra models | rerowed | "
  1139 |           "rerun | drift cleared | outages | cuts | paused arms | grader versions |")
  1140 |         L("|---|---|---|---|---|---|---|---|---|---|---|---|")
  1141 |         for e in [x for x in recs if x["suite_version"] == v]:
  1142 |             name = f"`{e['batch']}`" + (" (smoke)" if e["smoke"] else "")
  1143 |             gv = ", ".join(f"{k} ×{n}" for k, n in e["grader_versions"].items()) or "n/a"
  1144 |             if e["run_dirs_missing"]:
  1145 |                 gv += f"; no run dir ×{e['run_dirs_missing']}"
  1146 |             if e["status_note"]:
  1147 |                 L(f"| {name} | {md_cell(e['status_note'])} | — / {e['trials_rowed']} | — | — | — | — | — | — | — | — | "
  1148 |                   f"{md_cell(gv)} |")
  1149 |                 continue
  1150 |             sp = e["spend"] or {}
  1151 |             em = ", ".join(f"{k}: runs {x.get('runs')}, output tokens {x.get('output_tokens')}"
  1152 |                            for k, x in e["extra_models"].items()) or "none"
  1153 |             cuts = "; ".join(", ".join(f"{k} {c[k]}" for k in c) for c in e["cuts"]) or "none"
  1154 |             rr = f"{e['rerowed']}" + (f" ({tl(e['rerowed_tally'])})" if e["rerowed"] else "")
  1155 |             rn = f"{e['rerun']}" + (f" ({tl(e['rerun_tally'])})" if e["rerun"] else "")
  1156 |             L(f"| {name} | {md_cell(e['state'] or 'n/a')} | {e['trials_planned'] if e['trials_planned'] is not None else 'n/a'}"
  1157 |               f" / {e['trials_rowed']} | {usd(sp.get('rows_usd'))} / {usd(sp.get('ledger_usd'))} / "
~~~~

The change from head to the fix:

~~~~diff
@@ -1145,0 +1409,2 @@
+            if e.get("note"):
+                gv += f"; {e['note']}"
~~~~

## H25 — evals/harness/ablation-report.py — head line 1321

Head context (head/evals/harness/ablation-report.py, lines 1309–1333):

~~~~text
  1309 |     if main.excluded:
  1310 |         L("| run_id | arm | task | trial | status | reason |")
  1311 |         L("|---|---|---|---|---|---|")
  1312 |         for e in sorted(main.excluded, key=lambda e: (e["arm"], e["task_id"], e["trial"], e["run_id"])):
  1313 |             L(f"| `{e['run_id']}` | `{e['arm']}` | {e['task_id']} | {e['trial']} | {e['status']} | {md_cell(e['reason'])} |")
  1314 |     else:
  1315 |         L("No row was excluded.")
  1316 |     L("")
  1317 |     L(f"{sub} Cap failures (scored 0 on every applicable primary; the sensitivity figure excludes them)")
  1318 |     L("")
  1319 |     for r in V["caps"]:
  1320 |         L(f"- `{r['run_id']}` (`{r['arm']}`, {r['task_id']} t{r['trial']}, cap_phase {r.get('cap_phase') or 'n/a'}, "
> 1321 |           f"USD {float(r.get('cost_usd') or 0):.2f})")
  1322 |     if not V["caps"]:
  1323 |         L("- none")
  1324 |     L("")
  1325 |     L(f"{sub} Rows listed, never decided")
  1326 |     L("")
  1327 |     if main.listed or dups:
  1328 |         for r, why in main.listed:
  1329 |             L(f"- `{r['run_id']}` (`{r['arm']}`, {r['task_id']}, {r['status']}): {why}")
  1330 |         for dd in dups:
  1331 |             L(f"- `{dd['run_id']}` at {dd['dropped']}: duplicate run_id, the row at {dd['kept']} is used")
  1332 |     else:
  1333 |         L("None.")
~~~~

The change from head to the fix:

~~~~diff
@@ -1321 +1586 @@
-          f"USD {float(r.get('cost_usd') or 0):.2f})")
+          f"USD {float(usd_of(r)):.2f})")
~~~~

## H26 — evals/harness/ablation-report.py — head line 1339

Head context (head/evals/harness/ablation-report.py, lines 1327–1351):

~~~~text
  1327 |     if main.listed or dups:
  1328 |         for r, why in main.listed:
  1329 |             L(f"- `{r['run_id']}` (`{r['arm']}`, {r['task_id']}, {r['status']}): {why}")
  1330 |         for dd in dups:
  1331 |             L(f"- `{dd['run_id']}` at {dd['dropped']}: duplicate run_id, the row at {dd['kept']} is used")
  1332 |     else:
  1333 |         L("None.")
  1334 |     L("")
  1335 | 
  1336 | 
  1337 | def h1_json(V, rules):
  1338 |     return {"line": V["h1_line"], "established": V["h1_ok"], "state": V["h1_state"], "rule": rules.get("h1"),
> 1339 |             "suite_version": V["version"],
  1340 |             "comparisons": [dict(comp_json(p), read=s, read_text=read_text(p, s, why, V["version"]))
  1341 |                             for p, (s, why) in zip(V["h1_comps"], V["h1_reads"])]}
  1342 | 
  1343 | 
  1344 | def a4_json(V, rules):
  1345 |     a4 = V["a4"]
  1346 |     comp = None
  1347 |     if a4 is not None:
  1348 |         s, why = V["a4_read"]
  1349 |         comp = dict(comp_json(a4), read=s, read_text=read_text(a4, s, why, V["version"]))
  1350 |     return {"line": V["a4_line"], "holds": V["a4_ok"], "state": V["a4_state"], "rule": rules.get("a4_sensitivity"),
  1351 |             "suite_version": V["version"], "comparison": comp}
~~~~

The change from head to the fix:

~~~~diff
@@ -1339 +1604 @@
-            "suite_version": V["version"],
+            "suite_version": version_value(V["version"]),
~~~~

## H27 — evals/harness/ablation-report.py — head line 1351

Head context (head/evals/harness/ablation-report.py, lines 1339–1363):

~~~~text
  1339 |             "suite_version": V["version"],
  1340 |             "comparisons": [dict(comp_json(p), read=s, read_text=read_text(p, s, why, V["version"]))
  1341 |                             for p, (s, why) in zip(V["h1_comps"], V["h1_reads"])]}
  1342 | 
  1343 | 
  1344 | def a4_json(V, rules):
  1345 |     a4 = V["a4"]
  1346 |     comp = None
  1347 |     if a4 is not None:
  1348 |         s, why = V["a4_read"]
  1349 |         comp = dict(comp_json(a4), read=s, read_text=read_text(a4, s, why, V["version"]))
  1350 |     return {"line": V["a4_line"], "holds": V["a4_ok"], "state": V["a4_state"], "rule": rules.get("a4_sensitivity"),
> 1351 |             "suite_version": V["version"], "comparison": comp}
  1352 | 
  1353 | 
  1354 | def decisions_json(ds):
  1355 |     return [{"arm": d["arm"], "arm_label": d["arm_label"], "label": d["label"], "state": d["state"], "rule": d["rule"],
  1356 |              "figure": d["figure"], "predicate_state": d["predicate_state"],
  1357 |              "predicate_rule": d["predicate_rule"], "primaries": d["primaries"],
  1358 |              "c": j6(d["c"]), "w": j6(d["w"]), "cost_tasks": d["cost_tasks"],
  1359 |              "excluded_share": j6(d["excluded_share"]), "excluded_cells": d["excluded_cells"],
  1360 |              "cells_seen": d["cells_seen"], "mde_flag": d["mde_flag"], "decidable": d["decidable"],
  1361 |              "comparisons": [comp_json(p) for p in d["comparisons"]]} for d in ds]
  1362 | 
  1363 | 
~~~~

The change from head to the fix:

~~~~diff
@@ -1351 +1616 @@
-            "suite_version": V["version"], "comparison": comp}
+            "suite_version": version_value(V["version"]), "comparison": comp}
~~~~

## H28 — evals/harness/ablation-report.py — head lines 1403–1406

Head context (head/evals/harness/ablation-report.py, lines 1391–1418):

~~~~text
  1391 |     mans = load_manifests(args.manifests)
  1392 |     arms = [a for a in suite["arms"] if isinstance(a, dict) and a.get("id")]
  1393 |     arm_ids = [a["id"] for a in arms]
  1394 |     labels = {str(a.get("label", a["id"])).upper(): a["id"] for a in arms}
  1395 |     cuts = load_cuts(args.cuts, args.not_run, set(arm_ids), labels)
  1396 |     for need in (CONTROL, BARE):
  1397 |         if need not in arm_ids:
  1398 |             raise Fail(f"suite has no arm {need}")
  1399 | 
  1400 |     components = [a["id"] for a in arms if a["id"] not in (CONTROL, BARE) and not a.get("absent")]
  1401 |     absent = [a for a in arms if a.get("absent")]
  1402 |     seed = args.seed
> 1403 |     groups, primary = partition(rows, args.suite_version)
> 1404 |     versions = sorted(groups, key=version_order, reverse=True)
> 1405 |     others = [v for v in versions if v != primary]
> 1406 |     VS = {v: analyse(suite, groups[v], mans, args, cuts, components, v) for v in versions}
  1407 |     P = VS[primary]
  1408 |     main, decisions, sens_rows = P["main"], P["decisions"], P["sens_rows"]
  1409 |     h1_comps, a4 = P["h1_comps"], P["a4"]
  1410 | 
  1411 |     k = len(components)
  1412 |     efp = k * (1.0 - args.level) / 2.0
  1413 |     efp_line = (f"Expected false positives at level {args.level:.2f} over {k} components: "
  1414 |                 f"{k} × (1 − {args.level:.2f}) / 2 = {efp:.1f} one-sided per direction "
  1415 |                 f"({2 * efp:.1f} in either direction); no multiple-comparison correction is applied "
  1416 |                 f"(multiple_comparisons: {rules.get('multiple_comparisons', 'none')}).")
  1417 | 
  1418 |     # provenance
~~~~

The change from head to the fix:

~~~~diff
@@ -1403,4 +1668,7 @@
-    groups, primary = partition(rows, args.suite_version)
+    groups, primary, unversioned = partition(rows, args.suite_version, mans,
+                                             {a["id"]: a for a in arms})
     versions = sorted(groups, key=version_order, reverse=True)
     others = [v for v in versions if v != primary]
     VS = {v: analyse(suite, groups[v], mans, args, cuts, components, v) for v in versions}
+    # version-less rows that never reach a decision: listed under the primary version (report 1.2.1)
+    VS[primary]["main"].listed.extend(unversioned)
~~~~

## H29 — evals/harness/ablation-report.py — head lines 1552–1553

Head context (head/evals/harness/ablation-report.py, lines 1540–1565):

~~~~text
  1540 |         L(f"### Decisions (suite_version {v})")
  1541 |         L("")
  1542 |         render_decisions(L, V, absent, rules)
  1543 |         L(f"### Per-arm detail (suite_version {v})")
  1544 |         L("")
  1545 |         other_metrics[v] = render_per_arm(L, V, detail_arms, "####")
  1546 |         render_exclusions(L, V, [], "###", "####")
  1547 |         L(f"### Sensitivity figure (suite_version {v}): {SENS_LABEL}")
  1548 |         L("")
  1549 |         render_sens(L, V, rules, "####")
  1550 |         render_budget(L, V["budget"], "###")
  1551 | 
> 1552 |     recs = batch_record(mans, rows)
> 1553 |     render_batches(L, recs)
  1554 | 
  1555 |     L("## Method")
  1556 |     L("")
  1557 |     L(f"The pre-registered rules block of `{args.suite}`, quoted verbatim:")
  1558 |     L("")
  1559 |     L("```yaml")
  1560 |     L(rules_text)
  1561 |     L("```")
  1562 |     L("")
  1563 |     L("- Pass rate: the unit is the task; a cell is one task-trial; a task's value is the mean of its valid "
  1564 |       "trials (cap_failure scores 0); a trial excluded in either arm leaves both arms of that comparison "
  1565 |       "(pairwise); a task with no valid cell in either arm leaves the pair and is listed.")
~~~~

The change from head to the fix:

~~~~diff
@@ -1552,2 +1820,16 @@
-    recs = batch_record(mans, rows)
-    render_batches(L, recs)
+    # never fatal: the batch record is presentation only; its computation (grouping rows by batch, the
+    # manifest and path lookups, each batch's suite_version and directory), its JSON form and its rendering
+    # all degrade to "Not rendered (…)" with a note (report 1.2.2; rendering alone since 1.2.1)
+    # report 1.2.3 (audit DISS-C-002): the text names the exception class and the stage only; str(x) goes to
+    # stderr (it can carry a file's content or a host path)
+    blines, recs_json, recs_note = [], [], None
+    where = {"stage": "grouping the batch record"}
+    try:
+        recs = batch_record(mans, rows, where)
+        recs_json = [dict(e, suite_version=version_value(e["suite_version"])) for e in recs]
+        render_batches(blines.append, recs)
+    except Exception as x:
+        why = stage_note(x, where["stage"])
+        recs_json, recs_note = [], f"batch record not computed ({why}); it decides nothing"
+        blines = ["## Batch record", "", f"Not rendered ({why}); it decides nothing.", ""]
+    lines.extend(blines)
~~~~

## H30 — evals/harness/ablation-report.py — head line 1592

Head context (head/evals/harness/ablation-report.py, lines 1580–1604):

~~~~text
  1580 |       "investigate, keep, inconclusive (d < -0.03 or no valid pair), remove, simplify; Inconclusive-by-degradation is the "
  1581 |       "inconclusive outcome whose excluded-share clause matched.")
  1582 |     L("- Suite versions: rows of different suite_version values are never pooled; the main sections read the "
  1583 |       "highest suite_version present (or --suite-version), every other version has its own section.")
  1584 |     L(f"- H1 and A4 read each primary in order: not testable (no task of its type in either arm) → inconclusive "
  1585 |       f"by degradation (either arm's excluded share on that primary's task types > {main.guard:g}) → degenerate "
  1586 |       "(a catch-rate pair from one task with no per-defect ids: zero variance by construction, read as no valid "
  1587 |       "pair, also for the component decisions) → no pair → the interval. H1 is decided on the primaries left; "
  1588 |       "with none, H1 reads inconclusive by degradation when every testable primary is, else not yet decidable.")
  1589 |     L("")
  1590 | 
  1591 |     def version_json(V, ms):
> 1592 |         return {"suite_version": V["version"], "rows": len(V["rows"]), "batches": V["batches"],
  1593 |                 "suite_manifest_sha256": V["shas"], "decidable": V["decidable"],
  1594 |                 "h1": h1_json(V, rules), "a4": a4_json(V, rules), "decisions": decisions_json(V["decisions"]),
  1595 |                 "arms": arms_json(ms), "exclusions": exclusions_json(V), "listed": listed_json(V),
  1596 |                 "cap_failures": [r["run_id"] for r in V["caps"]],
  1597 |                 "sensitivity": sens_json(V), "budget_matched": budget_json(V["budget"])}
  1598 | 
  1599 |     def sens_json(V):
  1600 |         return {"treatment": SENS_H_TREATMENT,
  1601 |                 "h1": dict(h1_json(V["sens_h"], rules), line=SENS_PREFIX + V["sens_h"]["h1_line"]),
  1602 |                 "a4": dict(a4_json(V["sens_h"], rules), line=SENS_PREFIX + V["sens_h"]["a4_line"]),
  1603 |                 "rows": [{"arm": d["arm"], "predicate_state": d["predicate_state"], "c": j6(d["c"]),
  1604 |                           "w": j6(d["w"]), "excluded_share": j6(d["excluded_share"]),
~~~~

The change from head to the fix:

~~~~diff
@@ -1592 +1874 @@
-        return {"suite_version": V["version"], "rows": len(V["rows"]), "batches": V["batches"],
+        return {"suite_version": version_value(V["version"]), "rows": len(V["rows"]), "batches": V["batches"],
~~~~

## H31 — evals/harness/ablation-report.py — head line 1611

Head context (head/evals/harness/ablation-report.py, lines 1599–1623):

~~~~text
  1599 |     def sens_json(V):
  1600 |         return {"treatment": SENS_H_TREATMENT,
  1601 |                 "h1": dict(h1_json(V["sens_h"], rules), line=SENS_PREFIX + V["sens_h"]["h1_line"]),
  1602 |                 "a4": dict(a4_json(V["sens_h"], rules), line=SENS_PREFIX + V["sens_h"]["a4_line"]),
  1603 |                 "rows": [{"arm": d["arm"], "predicate_state": d["predicate_state"], "c": j6(d["c"]),
  1604 |                           "w": j6(d["w"]), "excluded_share": j6(d["excluded_share"]),
  1605 |                           "comparisons": [comp_json(p) for p in d["comparisons"]]} for d in V["sens_rows"]]}
  1606 | 
  1607 |     other_metrics[primary] = metrics
  1608 |     data = {
  1609 |         "schema_version": REPORT_SCHEMA, "generator": f"ablation-report.py {VERSION}", "partial": bool(args.partial),
  1610 |         "suite": {"path": args.suite, "name": suite.get("name"), "suite_version": suite.get("suite_version")},
> 1611 |         "primary_suite_version": int(primary) if primary.isdigit() else (None if primary == "n/a" else primary),
  1612 |         "by_suite_version": {v: version_json(VS[v], other_metrics[v]) for v in versions},
  1613 |         "provenance": {"source_commits": distinct("source_commit"), "suite_manifest_sha256": shas,
  1614 |                        "suite_versions": distinct("suite_version"), "image_digests": distinct("image_digest"),
  1615 |                        "batches": [{"batch": b, "smoke": m.get("smoke") is True, "shuffle_seed": m.get("shuffle_seed"),
  1616 |                                     "pre_registration_ref": m.get("pre_registration_ref"),
  1617 |                                     "source_commit": m.get("source_commit"), "image_digest": m.get("image_digest"),
  1618 |                                     "cli_version": cli(m), "manifest": m["_path"]} for b, m in sorted(mans.items())]},
  1619 |         "bootstrap": {"resamples": args.resamples, "level": args.level, "seed": seed},
  1620 |         "exclude_degraded": bool(args.exclude_degraded),
  1621 |         "decisions": decisions_json(decisions),
  1622 |         "absent": [{"arm": a["id"], "label": a.get("label"), "state": "component_absent",
  1623 |                     "evidence": a.get("evidence")} for a in absent],
~~~~

The change from head to the fix:

~~~~diff
@@ -1611 +1893 @@
-        "primary_suite_version": int(primary) if primary.isdigit() else (None if primary == "n/a" else primary),
+        "primary_suite_version": version_value(primary),
~~~~

## H32 — evals/harness/ablation-report.py — head line 1635

Head context (head/evals/harness/ablation-report.py, lines 1623–1647):

~~~~text
  1623 |                     "evidence": a.get("evidence")} for a in absent],
  1624 |         "h1": h1_json(P, rules),
  1625 |         "a4": a4_json(P, rules),
  1626 |         "expected_false_positives": {"components": k, "per_direction": j6(efp), "line": efp_line},
  1627 |         "arms": arms_json(metrics),
  1628 |         "exclusions": exclusions_json(P),
  1629 |         "listed": listed_json(P),
  1630 |         "duplicates": dups,
  1631 |         "cap_failures": [r["run_id"] for r in P["caps"]],
  1632 |         "cuts": [dict(arm=a, **cuts[a]) for a in sorted(cuts)],
  1633 |         "sensitivity": dict(sens_json(P), label=SENS_LABEL),
  1634 |         "budget_matched": budget_json(P["budget"]),
> 1635 |         "batches": recs,
  1636 |     }
  1637 |     return "\n".join(lines) + "\n", data, P["decidable"]
  1638 | 
  1639 | 
  1640 | def write_out(path, text):
  1641 |     if os.path.islink(path):
  1642 |         raise Fail(f"refusing to write through the symlink {path}")
  1643 |     parent = os.path.dirname(os.path.abspath(path))
  1644 |     if not os.path.isdir(parent):
  1645 |         raise Fail(f"the directory of {path} does not exist")
  1646 |     with open(path, "w", encoding="utf-8") as fh:
  1647 |         fh.write(text)
~~~~

The change from head to the fix:

~~~~diff
@@ -1635 +1917,2 @@
-        "batches": recs,
+        "batches": recs_json,
+        "batches_note": recs_note,
~~~~

## H33 — evals/harness/ablation-report.py — insertion after head line 1649

Head context (head/evals/harness/ablation-report.py, lines 1638–1661):

~~~~text
  1638 | 
  1639 | 
  1640 | def write_out(path, text):
  1641 |     if os.path.islink(path):
  1642 |         raise Fail(f"refusing to write through the symlink {path}")
  1643 |     parent = os.path.dirname(os.path.abspath(path))
  1644 |     if not os.path.isdir(parent):
  1645 |         raise Fail(f"the directory of {path} does not exist")
  1646 |     with open(path, "w", encoding="utf-8") as fh:
  1647 |         fh.write(text)
  1648 | 
  1649 | 
  1650 | class Parser(argparse.ArgumentParser):
  1651 |     def error(self, message):
  1652 |         sys.stderr.write(f"ablation-report.py: {message}\n")
  1653 |         sys.exit(2)
  1654 | 
  1655 | 
  1656 | def main(argv):
  1657 |     ap = Parser(prog="ablation-report.py", description="cycle-130 ablation report (see the header)")
  1658 |     ap.add_argument("--runs", action="append", required=True)
  1659 |     ap.add_argument("--manifests", action="append", required=True)
  1660 |     ap.add_argument("--suite", required=True)
  1661 |     ap.add_argument("--out", required=True)
~~~~

The change from head to the fix:

~~~~diff
@@ -1649,0 +1933,27 @@
+def non_finite_key(x, path="$"):
+    """The JSON path of the first non-finite float in x (sorted keys), None when there is none."""
+    if isinstance(x, float) and not math.isfinite(x):
+        return path
+    if isinstance(x, dict):
+        for k in sorted(x, key=str):
+            hit = non_finite_key(x[k], f"{path}.{k}")
+            if hit:
+                return hit
+    elif isinstance(x, (list, tuple)):
+        for i, v in enumerate(x):
+            hit = non_finite_key(v, f"{path}[{i}]")
+            if hit:
+                return hit
+    return None
+
+
+def json_text(data):
+    """The JSON twin; allow_nan=False (report 1.2.3, audit DISS-C-003): a NaN or an infinity fails loudly
+    (exit 2, naming the key) instead of writing the non-standard NaN/Infinity tokens."""
+    try:
+        return json.dumps(data, indent=2, sort_keys=True, ensure_ascii=False, allow_nan=False) + "\n"
+    except ValueError:
+        raise Fail(f"refusing to write a non-finite number to the JSON report at {non_finite_key(data)} "
+                   f"(NaN or Infinity is not JSON); nothing was written")
+
+
~~~~

## H34 — evals/harness/ablation-report.py — head lines 1675–1677

Head context (head/evals/harness/ablation-report.py, lines 1663–1689):

~~~~text
  1663 |     ap.add_argument("--seed", type=int, default=20261015)
  1664 |     ap.add_argument("--resamples", type=int)
  1665 |     ap.add_argument("--level", type=float)
  1666 |     ap.add_argument("--exclude-degraded", choices=("true", "false"), default="true")
  1667 |     ap.add_argument("--partial", action="store_true")
  1668 |     ap.add_argument("--cuts")
  1669 |     ap.add_argument("--not-run")
  1670 |     ap.add_argument("--suite-version")
  1671 |     args = ap.parse_args(argv)
  1672 |     args.exclude_degraded = args.exclude_degraded == "true"
  1673 |     try:
  1674 |         text, data, decidable = build(args)
> 1675 |         write_out(args.out, text)
> 1676 |         if args.json_out:
> 1677 |             write_out(args.json_out, json.dumps(data, indent=2, sort_keys=True, ensure_ascii=False) + "\n")
  1678 |     except Fail as e:
  1679 |         sys.stderr.write(f"ablation-report.py: {e}\n")
  1680 |         return 2
  1681 |     if args.partial and not decidable:
  1682 |         sys.stderr.write("ablation-report.py: --partial: no comparison has a valid pair yet (report written)\n")
  1683 |         return 1
  1684 |     print(f"ablation-report.py: wrote {args.out}" + (f" and {args.json_out}" if args.json_out else ""))
  1685 |     return 0
  1686 | 
  1687 | 
  1688 | if __name__ == "__main__":
  1689 |     sys.exit(main(sys.argv[1:]))
~~~~

The change from head to the fix:

~~~~diff
@@ -1675,3 +1985,4 @@
+        jtext = json_text(data) if args.json_out else None  # before any write: a non-finite value writes nothing
         write_out(args.out, text)
         if args.json_out:
-            write_out(args.json_out, json.dumps(data, indent=2, sort_keys=True, ensure_ascii=False) + "\n")
+            write_out(args.json_out, jtext)
~~~~

## H35 — evals/harness/ablation-row.sh — head line 56

Head context (head/evals/harness/ablation-row.sh, lines 44–68):

~~~~text
    44 | #                   sed -n, …) never match. A heuristic that obfuscation can evade: the
    45 | #                   authoritative after-the-fact checks are pipeline.json mount_integrity
    46 | #                   and took-effect.sh integrity_clean; mount_changed: the pipeline.json mount_integrity keys that
    47 | #                   read `changed` (claude_md, loa_config; audit LOW-A2); envelope_mismatch:
    48 | #                   the gates (review, audit) whose eval/ envelope and sandbox envelope both
    49 | #                   exist and differ byte for byte (audit MEDIUM-A1)
    50 | #   cost_usd        Σ phase cost_usd (result.total_cost_usd) + Σ phase ledger_cost_usd
    51 | #   stalls          number of phases that timed out
    52 | #   defects_missed  grade.json `recall.missed` (the seeded defect ids the review did not
    53 | #                   catch, e.g. ["d2","d5"]; [] when every defect was caught) on a
    54 | #                   review-catch row; null on a build row, with no grade.json, when
    55 | #                   `recall` is null or absent, or when `missed` is not a list of
>   56 | #                   non-empty strings (row writer 1.2, bd-yz1rd)
    57 | #   regressions_final_green  grade.json `regressions.final_green` (boolean: the task's
    58 | #                   own regression suite was green on the final tree); null when
    59 | #                   `regressions` is null or absent (review-catch rows, ungraded rows)
    60 | #                   or `final_green` is not a boolean (row writer 1.2, bd-m0hw7)
    61 | #   Both are optional for --validate (rows written before 1.2 lack them); when present
    62 | #   defects_missed is a list of non-empty strings or null and regressions_final_green
    63 | #   is a boolean or null. schema_version stays 1: the fields are additive and
    64 | #   ablation-report.py refuses any other schema_version.
    65 | #
    66 | # Row writer version: 1.2 (1.0 Sprint 258; 1.1 the Sprint 258 audit round 1 fields —
    67 | # envelope_mismatch, bash_mount_refs, mount_changed; 1.2 defects_missed and
    68 | # regressions_final_green, Sprint 262).
~~~~

The change from head to the fix:

~~~~diff
@@ -56 +56,2 @@
-#                   non-empty strings (row writer 1.2, bd-yz1rd)
+#                   non-empty strings (row writer 1.2, bd-yz1rd), or when the list breaks
+#                   an id rule below (row writer 1.3: null, every other field unchanged)
~~~~

## H36 — evals/harness/ablation-row.sh — head lines 65–68

Head context (head/evals/harness/ablation-row.sh, lines 53–80):

~~~~text
    53 | #                   catch, e.g. ["d2","d5"]; [] when every defect was caught) on a
    54 | #                   review-catch row; null on a build row, with no grade.json, when
    55 | #                   `recall` is null or absent, or when `missed` is not a list of
    56 | #                   non-empty strings (row writer 1.2, bd-yz1rd)
    57 | #   regressions_final_green  grade.json `regressions.final_green` (boolean: the task's
    58 | #                   own regression suite was green on the final tree); null when
    59 | #                   `regressions` is null or absent (review-catch rows, ungraded rows)
    60 | #                   or `final_green` is not a boolean (row writer 1.2, bd-m0hw7)
    61 | #   Both are optional for --validate (rows written before 1.2 lack them); when present
    62 | #   defects_missed is a list of non-empty strings or null and regressions_final_green
    63 | #   is a boolean or null. schema_version stays 1: the fields are additive and
    64 | #   ablation-report.py refuses any other schema_version.
>   65 | #
>   66 | # Row writer version: 1.2 (1.0 Sprint 258; 1.1 the Sprint 258 audit round 1 fields —
>   67 | # envelope_mismatch, bash_mount_refs, mount_changed; 1.2 defects_missed and
>   68 | # regressions_final_green, Sprint 262).
    69 | #
    70 | # Usage:
    71 | #   ablation-row.sh --run-dir D --task-yaml F [--grade grade.json] [--manifest MANIFEST.json]
    72 | #                   [--status S] [--attempts N] [--retry-reason R] [--out runs.jsonl]
    73 | #   ablation-row.sh --validate runs.jsonl [--allow-ungraded]
    74 | #
    75 | # Options:
    76 | #   --run-dir D        the run directory (meta/, sandbox/, transcripts/, eval/)
    77 | #   --task-yaml F      the task's task.yaml (id, type)
    78 | #   --grade F          grade.json (default <run-dir>/grade.json when present; absent →
    79 | #                      every grade field null, a smoke row)
    80 | #   --manifest F       batch MANIFEST.json (arm_map, batch, fingerprint, image_digest,
~~~~

The change from head to the fix:

~~~~diff
@@ -65,4 +66,10 @@
+#   defects_missed id rules (row writer 1.3; checked by --validate on a review-catch row with
+#   a non-null list, and by the row program, which writes null instead of a violating list):
+#   every id matches ^d[1-9][0-9]*$; the ids are unique; at most defects_seeded ids and each
+#   id within d1 … d<defects_seeded> when defects_seeded is a number; defects_seeded − the
+#   number of ids == defects_caught when both are numbers. --validate names the rule:
+#   "defects_missed [...] violates the rule: <rule>".
 #
-# Row writer version: 1.2 (1.0 Sprint 258; 1.1 the Sprint 258 audit round 1 fields —
+# Row writer version: 1.3 (1.0 Sprint 258; 1.1 the Sprint 258 audit round 1 fields —
 # envelope_mismatch, bash_mount_refs, mount_changed; 1.2 defects_missed and
-# regressions_final_green, Sprint 262).
+# regressions_final_green, Sprint 262; 1.3 the defects_missed id rules, Sprint 262 audit).
~~~~

## H37 — evals/harness/ablation-row.sh — head line 123

Head context (head/evals/harness/ablation-row.sh, lines 111–135):

~~~~text
   111 | while [[ $# -gt 0 ]]; do
   112 |   case "$1" in
   113 |     --run-dir)        RUN_DIR="${2:-}"; shift 2 ;;
   114 |     --task-yaml)      TASK_YAML="${2:-}"; shift 2 ;;
   115 |     --grade)          GRADE="${2:-}"; shift 2 ;;
   116 |     --manifest)       MANIFEST="${2:-}"; shift 2 ;;
   117 |     --status)         STATUS_OVERRIDE="${2:-}"; shift 2 ;;
   118 |     --attempts)       ATTEMPTS="${2:-}"; shift 2 ;;
   119 |     --retry-reason)   RETRY_REASON="${2:-}"; shift 2 ;;
   120 |     --out)            OUT="${2:-}"; shift 2 ;;
   121 |     --validate)       VALIDATE="${2:-}"; shift 2 ;;
   122 |     --allow-ungraded) ALLOW_UNGRADED=true; shift ;;
>  123 |     -h|--help)        sed -n '2,101p' "$0"; exit 0 ;;
   124 |     *) usage "unknown argument: $1" ;;
   125 |   esac
   126 | done
   127 | 
   128 | STATUSES='["completed","cap_failure","agent_error","transport_error","infrastructure_error","interrupted","contaminated"]'
   129 | 
   130 | # --- validate ----------------------------------------------------------------------
   131 | if [[ -n "$VALIDATE" ]]; then
   132 |   [[ -f "$VALIDATE" && -r "$VALIDATE" ]] || usage "cannot read $VALIDATE"
   133 |   n=0 bad=0
   134 |   while IFS= read -r line || [[ -n "$line" ]]; do
   135 |     n=$((n + 1))
~~~~

The change from head to the fix:

~~~~diff
@@ -123 +130 @@
-    -h|--help)        sed -n '2,101p' "$0"; exit 0 ;;
+    -h|--help)        sed -n '2,108p' "$0"; exit 0 ;;
~~~~

## H38 — evals/harness/ablation-row.sh — insertion after head line 129

Head context (head/evals/harness/ablation-row.sh, lines 118–141):

~~~~text
   118 |     --attempts)       ATTEMPTS="${2:-}"; shift 2 ;;
   119 |     --retry-reason)   RETRY_REASON="${2:-}"; shift 2 ;;
   120 |     --out)            OUT="${2:-}"; shift 2 ;;
   121 |     --validate)       VALIDATE="${2:-}"; shift 2 ;;
   122 |     --allow-ungraded) ALLOW_UNGRADED=true; shift ;;
   123 |     -h|--help)        sed -n '2,101p' "$0"; exit 0 ;;
   124 |     *) usage "unknown argument: $1" ;;
   125 |   esac
   126 | done
   127 | 
   128 | STATUSES='["completed","cap_failure","agent_error","transport_error","infrastructure_error","interrupted","contaminated"]'
   129 | 
   130 | # --- validate ----------------------------------------------------------------------
   131 | if [[ -n "$VALIDATE" ]]; then
   132 |   [[ -f "$VALIDATE" && -r "$VALIDATE" ]] || usage "cannot read $VALIDATE"
   133 |   n=0 bad=0
   134 |   while IFS= read -r line || [[ -n "$line" ]]; do
   135 |     n=$((n + 1))
   136 |     [[ -n "${line//[[:space:]]/}" ]] || continue
   137 |     err="$(jq -r --argjson st "$STATUSES" --argjson ungraded "$ALLOW_UNGRADED" '
   138 |       def t(v; ts): (v | type) as $ty | (ts | index($ty)) != null;
   139 |       def need(k; ts): if has(k) | not then "missing field \(k)"
   140 |                        elif t(.[k]; ts) | not then "field \(k) has type \(.[k] | type), want \(ts | join("|"))"
   141 |                        else empty end;
~~~~

The change from head to the fix:

~~~~diff
@@ -129,0 +137,14 @@
+# The defects_missed id rules (row writer 1.3, Sprint 262 audit DISS-C-001): one jq definition
+# prepended to both the --validate program and the row program, so the writer never emits a list
+# --validate rejects. Input: the id list (an array of strings); $s defects_seeded, $c defects_caught.
+# Emits the first violated rule's name, nothing when the list is consistent.
+MISSED_RULES='
+  def missed_rule($s; $c):
+    if any(.[]; (type != "string") or (test("^d[1-9][0-9]*$") | not)) then "id grammar ^d[1-9][0-9]*$"
+    elif length != (unique | length) then "unique ids"
+    elif ($s | type) == "number" and length > $s then "at most defects_seeded ids"
+    elif ($s | type) == "number" and any(.[]; (.[1:] | tonumber) > $s) then "ids within d1 … d<defects_seeded>"
+    elif ($s | type) == "number" and ($c | type) == "number" and ($s - length) != $c
+      then "defects_seeded − ids == defects_caught"
+    else empty end;'
+
~~~~

## H39 — evals/harness/ablation-row.sh — head line 137

Head context (head/evals/harness/ablation-row.sh, lines 125–149):

~~~~text
   125 |   esac
   126 | done
   127 | 
   128 | STATUSES='["completed","cap_failure","agent_error","transport_error","infrastructure_error","interrupted","contaminated"]'
   129 | 
   130 | # --- validate ----------------------------------------------------------------------
   131 | if [[ -n "$VALIDATE" ]]; then
   132 |   [[ -f "$VALIDATE" && -r "$VALIDATE" ]] || usage "cannot read $VALIDATE"
   133 |   n=0 bad=0
   134 |   while IFS= read -r line || [[ -n "$line" ]]; do
   135 |     n=$((n + 1))
   136 |     [[ -n "${line//[[:space:]]/}" ]] || continue
>  137 |     err="$(jq -r --argjson st "$STATUSES" --argjson ungraded "$ALLOW_UNGRADED" '
   138 |       def t(v; ts): (v | type) as $ty | (ts | index($ty)) != null;
   139 |       def need(k; ts): if has(k) | not then "missing field \(k)"
   140 |                        elif t(.[k]; ts) | not then "field \(k) has type \(.[k] | type), want \(ts | join("|"))"
   141 |                        else empty end;
   142 |       def num: ["number"]; def numn: ["number","null"]; def str: ["string"]; def strn: ["string","null"];
   143 |       def objn: ["object","null"]; def booln: ["boolean","null"];
   144 |       if type != "object" then "row is not a JSON object" else (.) as $row |
   145 |       [ need("schema_version"; num), need("run_id"; str), need("batch"; str), need("arm"; str),
   146 |         need("task_id"; str), need("task_type"; str), need("trial"; num), need("source_commit"; str),
   147 |         need("suite_manifest_sha256"; strn), need("suite_version"; ["number","string","null"]),
   148 |         need("host_fingerprint"; strn), need("image_digest"; strn), need("agy_opt_in"; ["boolean"]),
   149 |         need("started"; str), need("finished"; strn), need("phases"; ["array"]),
~~~~

The change from head to the fix:

~~~~diff
@@ -137 +158 @@
-    err="$(jq -r --argjson st "$STATUSES" --argjson ungraded "$ALLOW_UNGRADED" '
+    err="$(jq -r --argjson st "$STATUSES" --argjson ungraded "$ALLOW_UNGRADED" "$MISSED_RULES"'
~~~~

## H40 — evals/harness/ablation-row.sh — insertion after head line 168

Head context (head/evals/harness/ablation-row.sh, lines 157–180):

~~~~text
   157 |         need("degraded"; ["boolean"]), need("degraded_reason"; strn), need("status"; str),
   158 |         need("snapshots"; ["object"]), need("contaminated"; objn), need("zone_violations"; ["object"]) ][0]
   159 |       // (if (["feature-build","bug-fix","refactor","review-catch"] | index($row.task_type)) == null
   160 |            then "task_type \(.task_type) is not one of feature-build|bug-fix|refactor|review-catch" else empty end)
   161 |       // (if ($st | index($row.status)) == null then "status \(.status) is not one of \($st | join("|"))" else empty end)
   162 |       // (if ($row.arm | test("^[a-z][a-z0-9_]{0,63}$")) | not then "arm \(.arm) does not match the arm grammar" else empty end)
   163 |       // ([("dot_claude_writes", "bash_mount_refs", "mount_changed", "envelope_mismatch") as $k
   164 |            | select((($row.zone_violations | objects)[$k] | type) != "array") | "zone_violations.\($k) is not an array"][0])
   165 |       // (if has("defects_missed") and .defects_missed != null
   166 |              and ((.defects_missed | type) != "array"
   167 |                   or any(.defects_missed[]; (type != "string") or (length == 0)))
   168 |            then "field defects_missed has type \(.defects_missed | type), want a list of non-empty strings|null" else empty end)
   169 |       // (if has("regressions_final_green") and ((.regressions_final_green | type) as $ty | ["boolean","null"] | index($ty)) == null
   170 |            then "field regressions_final_green has type \(.regressions_final_green | type), want boolean|null" else empty end)
   171 |       // (if (.degraded == true) and (.degraded_reason == null) then "degraded without degraded_reason" else empty end)
   172 |       // (if .verdict != null and ((["APPROVED","CHANGES_REQUIRED"] | index($row.verdict)) == null)
   173 |            then "verdict \(.verdict) is not APPROVED|CHANGES_REQUIRED" else empty end)
   174 |       // ([.snapshots | to_entries[] | select((.value | type) != "string" and (.value | type) != "null")
   175 |            | "snapshots.\(.key) is not a string"][0])
   176 |       // ([.phases | to_entries[] | .key as $i | .value as $p
   177 |            | ( if ($p | type) != "object" then "phases[\($i)] is not an object" else
   178 |                ([ ($p | need("name"; str)), ($p | need("session_id"; strn)), ($p | need("model_requested"; str)),
   179 |                   ($p | need("models_used"; ["object"])), ($p | need("effort_requested"; strn)),
   180 |                   ($p | need("effort_effective"; strn)), ($p | need("tokens_in"; num)), ($p | need("tokens_out"; num)),
~~~~

The change from head to the fix:

~~~~diff
@@ -168,0 +190,4 @@
+      // (if .task_type == "review-catch" and (.defects_missed | type) == "array"
+           then ([.defects_missed | missed_rule($row.defects_seeded; $row.defects_caught)][0]
+                 | if . == null then empty else "defects_missed \($row.defects_missed | tojson) violates the rule: \(.)" end)
+           else empty end)
~~~~

## H41 — evals/harness/ablation-row.sh — head line 313

Head context (head/evals/harness/ablation-row.sh, lines 301–325):

~~~~text
   301 |                      and test("(^|[;&|(][[:space:]]*|\\bthen[[:space:]]+|\\bdo[[:space:]]+)(sed[[:space:]]+-[a-zA-Z]*i|cp|mv|rm|ln|tee|truncate|install|patch|chmod|chown|git[[:space:]]+(checkout|apply|restore)|yq[[:space:]]+-i|python3?|perl)\\b")))
   302 |         | {phase: $ph, excerpt: .[0:160]}' "$f" 2>/dev/null || true
   303 |     done | jq -s -c '.' > "$WORK/bashref.json"
   304 | fi
   305 | 
   306 | # Each --slurpfile binds an array of the file's values; [0] is the one value.
   307 | ROW="$(jq -n -c \
   308 |   --slurpfile p_f "$WORK/pipe.json" --slurpfile task_f "$WORK/task.json" --slurpfile g_f "$WORK/grade.json" \
   309 |   --slurpfile m_f "$WORK/manifest.json" --slurpfile minv_f "$WORK/minv.json" \
   310 |   --slurpfile er_f "$WORK/env-review.json" --slurpfile ea_f "$WORK/env-audit.json" --slurpfile dot_f "$WORK/dot.json" \
   311 |   --slurpfile bash_f "$WORK/bashref.json" --slurpfile mm_f "$WORK/mismatch.json" \
   312 |   --arg arm "$ARM" --arg status_override "$STATUS_OVERRIDE" --argjson attempts "$ATTEMPTS" \
>  313 |   --arg retry_reason "$RETRY_REASON" '
   314 |   def norm_model: tostring | sub("^([a-z]+\\.)?anthropic\\."; "") | sub("-v[0-9]+(:[0-9]+)?$"; "");
   315 |   # an unparseable timestamp (empty, an offset other than Z, not a string) is null, never an abort
   316 |   def ms(ts): if ts == null or ts == "" then null
   317 |               else (try (ts | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601 * 1000) catch null) end;
   318 |   def obj: if type == "object" then . else {} end;
   319 |   def boolish: if type == "boolean" then . else null end;
   320 |   def voices(e): if e == null then null else
   321 |       (e.verdict_quality | obj) as $vq
   322 |       | {planned: ($vq.voices_planned // e.voices_planned // null),
   323 |          completed: ($vq.voices_succeeded // e.voices_succeeded // null),
   324 |          quality: ($vq.status // e.status // null),
   325 |          companion_planned: first((e.metadata | objects | .companion_voice | objects | .planned), null)} end;
~~~~

The change from head to the fix:

~~~~diff
@@ -313 +338 @@
-  --arg retry_reason "$RETRY_REASON" '
+  --arg retry_reason "$RETRY_REASON" "$MISSED_RULES"'
~~~~

## H42 — evals/harness/ablation-row.sh — head line 412

Head context (head/evals/harness/ablation-row.sh, lines 400–424):

~~~~text
   400 |       flags: ($rc.flags // $g.flags // null),
   401 |       false_positives: ($g.false_positives // null | if type == "array" then length else . end),
   402 |       verdict: ($g.verdict | if type == "object" then .value else . end // null),
   403 |       verdict_accuracy: ($g.verdict_accuracy | if type == "object" then .value else . end | boolish),
   404 |       verdict_accuracy_review: (if ($g.verdict_accuracy_review | type) == "boolean" then $g.verdict_accuracy_review
   405 |                                 else first(($g.verdict_accuracy_per_gate | objects | .review), null) | boolish end),
   406 |       verdict_accuracy_audit: (if ($g.verdict_accuracy_audit | type) == "boolean" then $g.verdict_accuracy_audit
   407 |                                else first(($g.verdict_accuracy_per_gate | objects | .audit), null) | boolish end),
   408 |       regressions: ($g.regressions // null | if type == "object" then ((.newly_failing // []) | length)
   409 |                                             elif type == "array" then length else . end),
   410 |       defects_missed: (if ($task.type // $p.task_type // "") != "review-catch" or $rc == null then null
   411 |                        else first(($rc | objects | .missed), null) as $ms
>  412 |                        | if ($ms | type) == "array" and all($ms[]; type == "string" and length > 0) then $ms
   413 |                          else null end end),
   414 |       regressions_final_green: first(($g.regressions | objects | .final_green | boolish), null),
   415 |       diff_lines: ($g.diff_lines // null),
   416 |       files_changed: ($g.files_changed // null),
   417 |       cost_usd: ([$phases[] | (.cost_usd // 0) + (.ledger_cost_usd // 0)] | add // 0),
   418 |       wall_clock_ms: (if $t0 != null and $t1 != null then ($t1 - $t0)
   419 |                       else ([$phases[] | .wall_ms // .duration_ms // 0] | add // 0) end),
   420 |       tokens_in: ([$phases[] | .tokens_in // 0] | add // 0),
   421 |       tokens_out: ([$phases[] | .tokens_out // 0] | add // 0),
   422 |       stalls: ([$phases[] | select(.timed_out == true)] | length),
   423 |       attempts: $attempts,
   424 |       retry_reason: (if $retry_reason == "" then null else $retry_reason end),
~~~~

The change from head to the fix:

~~~~diff
@@ -412 +437,2 @@
-                       | if ($ms | type) == "array" and all($ms[]; type == "string" and length > 0) then $ms
+                       | if ($ms | type) == "array" and all($ms[]; type == "string" and length > 0)
+                            and ([$ms | missed_rule($seeded; $caught)] | length) == 0 then $ms
~~~~

## H43 — evals/tests/ablation-report.bats — head line 13

Head context (head/evals/tests/ablation-report.bats, lines 1–25):

~~~~text
     1 | #!/usr/bin/env bats
     2 | # =============================================================================
     3 | # evals/tests/ablation-report.bats — cycle-130 Sprint 260 Task 3.8 (AC-3.10; PRD AC-8.1–8.3;
     4 | # SDD §5.12; DEC-0393, DEC-0399, DEC-0400, DEC-0416, DEC-0417, DEC-0434, DEC-0435)
     5 | #
     6 | # ablation-report.py on planted rows: fixtures/ablation-report/gen-fixtures.py writes four
     7 | # scenarios (main, boundary, exclusions, partial; the header there lists every planted
     8 | # number) into the file tmpdir; setup_file builds the full reports once against the
     9 | # real suite file evals/suites/ablation-2.0.yaml. AR-23 … AR-30 (Sprint 262): the suite_version
    10 | # partition, the not-testable / not-yet-decidable states (bd-wqbz3), the degradation guard on
    11 | # the H1 and A4 lines, and the degenerate single-task rate-fallback pair. AR-31 … AR-35 (Sprint 262
    12 | # R3, presentation only): the sensitivity H1/A4 lines, the batch record, precision and cost per true
>   13 | # defect, the budget-matched baseline.
    14 | # =============================================================================
    15 | 
    16 | setup_file() {
    17 |   TESTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    18 |   REPO_ROOT="$(cd "$TESTS_DIR/../.." && pwd)"
    19 |   export REPO_ROOT
    20 |   export REPORT="$REPO_ROOT/evals/harness/ablation-report.py"
    21 |   export SUITE="$REPO_ROOT/evals/suites/ablation-2.0.yaml"
    22 |   export FX="$BATS_FILE_TMPDIR/fx"
    23 |   mkdir -p "$FX"
    24 |   python3 -I "$TESTS_DIR/fixtures/ablation-report/gen-fixtures.py" "$FX"
    25 |   for s in main boundary exclusions versions degraded degraded-a4 degenerate-1 degenerate-2 degenerate-ids present; do
~~~~

The change from head to the fix:

~~~~diff
@@ -13 +13,8 @@
-# defect, the budget-matched baseline.
+# defect, the budget-matched baseline. AR-36 … AR-39 (Sprint 262 R4, report 1.2.1): the type-stable
+# grader-version sort and the never-fatal batch record, one run directory per row, float suite_version
+# keys, and version-less rows that never reach a decision. AR-40 … AR-42 (Sprint 262 R5, report 1.2.2): the
+# arm_map provenance check before any listing decision, the never-fatal batch-record computation, and
+# run-directory attribution by numeric trial with the rerun fallback; AR-38 also asserts the JSON type of
+# every version value. AR-43 … AR-47 (Sprint 262 audit, report 1.2.3): inconsistent defects_missed ids read
+# as the rate, the sanitized never-fatal text, a non-numeric or NaN cost_usd read as 0 with a note, the
+# loud allow_nan=False failure naming the key, and the arm / task_id grammar before any path is built.
~~~~

## H44 — evals/tests/ablation-report.bats — head line 25

Head context (head/evals/tests/ablation-report.bats, lines 13–37):

~~~~text
    13 | # defect, the budget-matched baseline.
    14 | # =============================================================================
    15 | 
    16 | setup_file() {
    17 |   TESTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    18 |   REPO_ROOT="$(cd "$TESTS_DIR/../.." && pwd)"
    19 |   export REPO_ROOT
    20 |   export REPORT="$REPO_ROOT/evals/harness/ablation-report.py"
    21 |   export SUITE="$REPO_ROOT/evals/suites/ablation-2.0.yaml"
    22 |   export FX="$BATS_FILE_TMPDIR/fx"
    23 |   mkdir -p "$FX"
    24 |   python3 -I "$TESTS_DIR/fixtures/ablation-report/gen-fixtures.py" "$FX"
>   25 |   for s in main boundary exclusions versions degraded degraded-a4 degenerate-1 degenerate-2 degenerate-ids present; do
    26 |     python3 -I "$REPORT" --runs "$FX/$s/runs.jsonl" --manifests "$FX/$s/manifests" --suite "$SUITE" \
    27 |       --out "$FX/$s/report.md" --json "$FX/$s/report.json" >/dev/null
    28 |   done
    29 | }
    30 | 
    31 | setup() {
    32 |   T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/ar.XXXXXX")"
    33 | }
    34 | 
    35 | teardown() {
    36 |   find "$T" -mindepth 1 -delete 2>/dev/null || true
    37 |   rmdir "$T" 2>/dev/null || true
~~~~

The change from head to the fix:

~~~~diff
@@ -25 +32 @@
-  for s in main boundary exclusions versions degraded degraded-a4 degenerate-1 degenerate-2 degenerate-ids present; do
+  for s in main boundary exclusions versions degraded degraded-a4 degenerate-1 degenerate-2 degenerate-ids present ids-bad; do
~~~~

## H45 — evals/tests/ablation-report.bats — head line 471

Head context (head/evals/tests/ablation-report.bats, lines 459–483):

~~~~text
   459 |   J="$FX/present/report.json"; M="$FX/present/report.md"
   460 |   b() { jq -r --arg b "$1" ".batches[] | select(.batch == \$b) | $2" "$J"; }
   461 |   [ "$(b pr-2 .state)" = "complete" ]
   462 |   [ "$(b pr-2 .trials_planned)" = "20" ]
   463 |   [ "$(b pr-2 .trials_rowed)" = "18" ]
   464 |   [ "$(b pr-2 .spend.spent_usd)" = "70.5" ]
   465 |   [ "$(b pr-2 .rerowed)" = "3" ]
   466 |   [ "$(b pr-2 '.rerowed_tally["contaminated→cap_failure"]')" = "1" ]
   467 |   [ "$(b pr-2 '.rerun_tally["transport_error→completed"]')" = "1" ]
   468 |   [ "$(b pr-2 .outage_history)" = "2" ]
   469 |   [ "$(b pr-2 .drift_cleared)" = "1" ]
   470 |   [ "$(b pr-2 '.paused_arms | join(",")')" = "a3_one_voice" ]
>  471 |   [ "$(b pr-2 '.grader_versions | to_entries | map("\(.key)=\(.value)") | join(",")')" = "1.2.11=1,1.2.5=1,n/a=1" ]
   472 |   [ "$(b pr-2 .run_dirs_missing)" = "15" ]
   473 |   [ "$(b pr-1 .status_note)" = "no STATUS.json" ]
   474 |   [ "$(b pr-1 .suite_version)" = "1" ]
   475 |   grep -qF '## Batch record' "$M"
   476 |   grep -qF '| `pr-2` | complete | 20 / 18 | 69.00 / 1.50 / 70.50 / 100.00 | global.anthropic.claude-haiku-4-5-20251001-v1:0: runs 2, output tokens 900 | 3 (completed→completed ×2, contaminated→cap_failure ×1) | 1 (transport_error→completed ×1) | 1 | 2 |' "$M"
   477 |   grep -qF '| a3_one_voice | 1.2.5 ×1, 1.2.11 ×1, n/a ×1; no run dir ×15 |' "$M"
   478 |   grep -qF '| `pr-1` | no STATUS.json | — / 72 |' "$M"
   479 |   awk '/^## Batch record/{f=1} /^## Method/{f=0} f' "$M" | grep -qF '### suite_version 1'
   480 |   # the report reads, never writes, beside the manifests
   481 |   [ ! -e "$FX/present/manifests/pr-1/STATUS.json" ]
   482 | }
   483 | 
~~~~

The change from head to the fix:

~~~~diff
@@ -471 +478 @@
-  [ "$(b pr-2 '.grader_versions | to_entries | map("\(.key)=\(.value)") | join(",")')" = "1.2.11=1,1.2.5=1,n/a=1" ]
+  [ "$(b pr-2 '.grader_versions | to_entries | map("\(.key)=\(.value)") | join(",")')" = "1.2.11=1,1.2.5=1,n/a=16" ]
~~~~

## H46 — evals/tests/ablation-report.bats — head line 477

Head context (head/evals/tests/ablation-report.bats, lines 465–489):

~~~~text
   465 |   [ "$(b pr-2 .rerowed)" = "3" ]
   466 |   [ "$(b pr-2 '.rerowed_tally["contaminated→cap_failure"]')" = "1" ]
   467 |   [ "$(b pr-2 '.rerun_tally["transport_error→completed"]')" = "1" ]
   468 |   [ "$(b pr-2 .outage_history)" = "2" ]
   469 |   [ "$(b pr-2 .drift_cleared)" = "1" ]
   470 |   [ "$(b pr-2 '.paused_arms | join(",")')" = "a3_one_voice" ]
   471 |   [ "$(b pr-2 '.grader_versions | to_entries | map("\(.key)=\(.value)") | join(",")')" = "1.2.11=1,1.2.5=1,n/a=1" ]
   472 |   [ "$(b pr-2 .run_dirs_missing)" = "15" ]
   473 |   [ "$(b pr-1 .status_note)" = "no STATUS.json" ]
   474 |   [ "$(b pr-1 .suite_version)" = "1" ]
   475 |   grep -qF '## Batch record' "$M"
   476 |   grep -qF '| `pr-2` | complete | 20 / 18 | 69.00 / 1.50 / 70.50 / 100.00 | global.anthropic.claude-haiku-4-5-20251001-v1:0: runs 2, output tokens 900 | 3 (completed→completed ×2, contaminated→cap_failure ×1) | 1 (transport_error→completed ×1) | 1 | 2 |' "$M"
>  477 |   grep -qF '| a3_one_voice | 1.2.5 ×1, 1.2.11 ×1, n/a ×1; no run dir ×15 |' "$M"
   478 |   grep -qF '| `pr-1` | no STATUS.json | — / 72 |' "$M"
   479 |   awk '/^## Batch record/{f=1} /^## Method/{f=0} f' "$M" | grep -qF '### suite_version 1'
   480 |   # the report reads, never writes, beside the manifests
   481 |   [ ! -e "$FX/present/manifests/pr-1/STATUS.json" ]
   482 | }
   483 | 
   484 | @test "AR-33 precision and cost per true defect per review-catch arm (informational): false positives, none, and zero caught → null" {
   485 |   J="$FX/present/report.json"
   486 |   [ "$(jq -r '.arms.a0_bare | "\(.precision) \(.usd_per_true_defect) \(.true_defects) \(.flagged_regions)"' "$J")" = "0.647059 0.545455 11 17" ]
   487 |   [ "$(jq -r '.arms.a1_full | "\(.precision) \(.usd_per_true_defect) \(.true_defects) \(.flagged_regions)"' "$J")" = "1.0 2.222222 27 27" ]
   488 |   [ "$(jq -r '.arms.a3_one_voice | "\(.precision) \(.usd_per_true_defect) \(.true_defects)"' "$J")" = "null null 0" ]
   489 |   [ "$(jq -r '.arms.a2_no_sprint_plan.precision' "$J")" = "null" ]
~~~~

The change from head to the fix:

~~~~diff
@@ -477 +484 @@
-  grep -qF '| a3_one_voice | 1.2.5 ×1, 1.2.11 ×1, n/a ×1; no run dir ×15 |' "$M"
+  grep -qF '| a3_one_voice | 1.2.5 ×1, 1.2.11 ×1, n/a ×16; no run dir ×15 |' "$M"
~~~~

## H47 — evals/tests/ablation-report.bats — insertion after head line 525

Head context (head/evals/tests/ablation-report.bats, lines 514–525):

~~~~text
   514 |     python3 -I - "$FX/$s/report.json" <<'PY'
   515 | import json, sys
   516 | d = json.load(open(sys.argv[1]))
   517 | for k in ("budget_matched", "batches"):
   518 |     assert k in d, k
   519 | assert d["sensitivity"]["h1"]["state"] and d["sensitivity"]["a4"]["state"]
   520 | PY
   521 |   done
   522 |   # the main H1 line ignores the sensitivity read: degraded stays inconclusive by degradation
   523 |   [ "$(jq -r .h1.line "$FX/degraded/report.json")" = "H1: inconclusive by degradation — not established" ]
   524 |   [ "$(jq -r '.decisions[] | select(.arm == "a3_one_voice") | .state' "$FX/present/report.json")" = "keep" ]
   525 | }
~~~~

The change from head to the fix:

~~~~diff
@@ -525,0 +533,226 @@
+
+@test "AR-36 grader versions 1.2.0, 1.2.0-rc1 and an ungraded run dir: the report is written, the tally lists all three (n/a last), no traceback" {
+  report graders "$T/g"
+  [ "$status" -eq 0 ]
+  [[ "$output" != *"Traceback"* ]]
+  [ -s "$T/g.md" ] && [ -s "$T/g.json" ]
+  b() { jq -r --arg b "$1" ".batches[] | select(.batch == \$b) | $2" "$T/g.json"; }
+  [ "$(b gr-mixed '.grader_versions | to_entries | map("\(.key)=\(.value)") | join(",")')" = "1.2.0=1,1.2.0-rc1=1,n/a=1" ]
+  [ "$(b gr-mixed .run_dirs_missing)" = "0" ]
+  [ "$(b gr-mixed .note)" = "null" ]
+  grep -qF '| `gr-mixed` | no STATUS.json | — / 3 | — | — | — | — | — | — | — | — | 1.2.0 ×1, 1.2.0-rc1 ×1, n/a ×1 |' "$T/g.md"
+}
+
+@test "AR-37 one run directory per row: a rerun row reads its own -r<k> once (run_id match beats a higher graded sibling); a row without a directory is n/a ×1 and run_dirs_missing 1" {
+  report graders "$T/g"
+  [ "$status" -eq 0 ]
+  b() { jq -r --arg b "$1" ".batches[] | select(.batch == \$b) | $2" "$T/g.json"; }
+  [ "$(b gr-rerun '.grader_versions | to_entries | map("\(.key)=\(.value)") | join(",")')" = "1.2.11=1" ]
+  [ "$(b gr-rerun .run_dirs_missing)" = "0" ]
+  [ "$(b gr-missing '.grader_versions | to_entries | map("\(.key)=\(.value)") | join(",")')" = "n/a=1" ]
+  [ "$(b gr-missing .run_dirs_missing)" = "1" ]
+  # every tally sums to the batch's rows
+  [ "$(jq '[.batches[] | ([.grader_versions[]] | add) == .trials_rowed] | all' "$T/g.json")" = "true" ]
+  # without a run_id match the highest graded rerun is read
+  jq -c 'select(.batch == "gr-rerun")' "$FX/graders/runs.jsonl" > "$T/rr.jsonl"
+  cp -R "$FX/graders/manifests" "$T/man"
+  printf '{"run_id": "elsewhere"}\n' > "$T/man/gr-rerun/a0_bare/rc-01-t1-r2/meta/pipeline.json"
+  run python3 -I "$REPORT" --runs "$T/rr.jsonl" --manifests "$T/man" --suite "$SUITE" --out "$T/rr.md" --json "$T/rr.json"
+  [ "$status" -eq 0 ]
+  [ "$(jq -r '.batches[] | select(.batch == "gr-rerun") | .grader_versions | to_entries | map("\(.key)=\(.value)") | join(",")' "$T/rr.json")" = "9.9.9=1" ]
+}
+
+@test "AR-38 suite_version 2 and 2.1 are two versions (keys 2 and 2.1, never pooled, 2.1 primary); --suite-version 2.0 selects 2; true and \"\" are absent" {
+  report versions-float "$T/f"
+  [ "$status" -eq 0 ]
+  [ "$(jq -r '.by_suite_version | keys | join(",")' "$T/f.json")" = "2,2.1" ]
+  [ "$(jq -r .primary_suite_version "$T/f.json")" = "2.1" ]
+  [ "$(jq -r .arms.a1_full.rows "$T/f.json")" -eq 12 ]
+  [ "$(jq -r '.by_suite_version["2"].arms.a1_full.rows' "$T/f.json")" -eq 12 ]
+  [ "$(jq -r '.h1.comparisons[] | select(.metric == "defect_catch_rate") | .d' "$T/f.json")" = "0.222222" ]
+  [ "$(jq -r '.by_suite_version["2"].h1.comparisons[] | select(.metric == "defect_catch_rate") | .d' "$T/f.json")" = "0.444444" ]
+  grep -qxF '## Suite version 2 (batches: vf-2) — reported separately, never pooled' "$T/f.md"
+  report versions-float "$T/f20" --suite-version 2.0
+  [ "$status" -eq 0 ]
+  [ "$(jq -r .primary_suite_version "$T/f20.json")" = "2" ]
+  report versions-float "$T/f21" --suite-version 2.1
+  [ "$status" -eq 0 ]
+  [ "$(jq -r .primary_suite_version "$T/f21.json")" = "2.1" ]
+  report versions-float "$T/f22" --suite-version 2.2
+  [ "$status" -eq 2 ]
+  [[ "$output" == *"--suite-version 2.2: no row has that suite_version (present: 2, 2.1)"* ]]
+  for v in true '""' '"  "'; do
+    jq -c --argjson v "$v" 'if .run_id == "vf-2-a1_full-rc-01-t1" then .suite_version = $v else . end' \
+      "$FX/versions-float/runs.jsonl" > "$T/abs.jsonl"
+    run python3 -I "$REPORT" --runs "$T/abs.jsonl" --manifests "$FX/versions-float/manifests" --suite "$SUITE" --out "$T/abs.md"
+    [ "$status" -eq 2 ]
+    [[ "$output" == *"row vf-2-a1_full-rc-01-t1 has no suite_version while the rows hold suite_version 2, 2.1"* ]]
+  done
+  # report 1.2.2: every JSON version value is typed like primary_suite_version (int / float / string / null)
+  [ "$(jq -r '.primary_suite_version | type' "$T/f.json")" = "number" ]
+  [ "$(jq -r '[.h1.suite_version, .a4.suite_version, .sensitivity.h1.suite_version, .budget_matched.suite_version,
+      .by_suite_version["2.1"].suite_version, .by_suite_version["2.1"].h1.suite_version] | map(type) | unique | join(",")' "$T/f.json")" = "number" ]
+  [ "$(jq -c '[.h1.suite_version, .by_suite_version["2.1"].suite_version, .by_suite_version["2"].suite_version,
+      .by_suite_version["2"].h1.suite_version, .by_suite_version["2"].a4.suite_version]' "$T/f.json")" = "[2.1,2.1,2,2,2]" ]
+  [ "$(jq -c '[.batches[] | .suite_version]' "$T/f.json")" = "[2,2.1]" ]
+  [ "$(jq -r '.primary_suite_version | type' "$T/f20.json")" = "number" ]
+  [ "$(jq -c '[.h1.suite_version, .batches[0].suite_version]' "$T/f20.json")" = "[2,2]" ]
+  # a non-numeric key is a string
+  jq -c 'if .batch == "vf-2" then .suite_version = "v2" else . end' "$FX/versions-float/runs.jsonl" > "$T/nn.jsonl"
+  cp -R "$FX/versions-float/manifests" "$T/nnm"
+  jq '.suite_version = "v2"' "$FX/versions-float/manifests/vf-2/MANIFEST.json" > "$T/nnm/vf-2/MANIFEST.json"
+  run python3 -I "$REPORT" --runs "$T/nn.jsonl" --manifests "$T/nnm" --suite "$SUITE" --out "$T/nn.md" --json "$T/nn.json"
+  [ "$status" -eq 0 ]
+  [ "$(jq -c '[.primary_suite_version, .h1.suite_version, .by_suite_version.v2.suite_version, .by_suite_version["2.1"].suite_version,
+      (.batches[] | select(.batch == "vf-2") | .suite_version)]' "$T/nn.json")" = '["v2","v2","v2",2.1,"v2"]' ]
+  # no suite_version at all: n/a is null
+  jq -c 'del(.suite_version)' "$FX/versions-float/runs.jsonl" | jq -c 'select(.batch == "vf-2")' > "$T/na.jsonl"
+  cp -R "$FX/versions-float/manifests" "$T/nam"
+  jq 'del(.suite_version)' "$FX/versions-float/manifests/vf-2/MANIFEST.json" > "$T/nam/vf-2/MANIFEST.json"
+  run python3 -I "$REPORT" --runs "$T/na.jsonl" --manifests "$T/nam" --suite "$SUITE" --out "$T/na.md" --json "$T/na.json"
+  [ "$status" -eq 0 ]
+  [ "$(jq -r '.by_suite_version | keys | join(",")' "$T/na.json")" = "n/a" ]
+  [ "$(jq -c '[.primary_suite_version, .h1.suite_version, .a4.suite_version, .by_suite_version["n/a"].suite_version,
+      .budget_matched.suite_version, (.batches[] | select(.batch == "vf-2") | .suite_version)]' "$T/na.json")" = "[null,null,null,null,null,null]" ]
+}
+
+@test "AR-39 version-less rows that never reach a decision (smoke, unbatched) are listed under the primary version; a version-less row that would be scored still exits 2" {
+  report legacy "$T/l"
+  [ "$status" -eq 0 ]
+  [ "$(jq -r .primary_suite_version "$T/l.json")" = "2" ]
+  [ "$(jq -r '.listed[] | select(.run_id == "leg-smoke-a1_full-fb-01-t1") | .reason' "$T/l.json")" = "no suite_version; smoke batch leg-smoke" ]
+  [ "$(jq -r '.listed[] | select(.run_id == "leg-loose-a0_bare-fb-01-t1") | .reason' "$T/l.json")" = "no suite_version; no manifest for batch leg-loose" ]
+  [ "$(jq '.by_suite_version["1"].listed | length' "$T/l.json")" -eq 0 ]
+  grep -qF -- '- `leg-smoke-a1_full-fb-01-t1` (`a1_full`, fb-01, completed): no suite_version; smoke batch leg-smoke' "$T/l.md"
+  # the decisions are those of the versions scenario
+  for k in h1 a4 decisions; do
+    [ "$(jq -c ".$k" "$T/l.json")" = "$(jq -c ".$k" "$FX/versions/report.json")" ]
+  done
+  [ "$(jq -c '.by_suite_version["1"].decisions' "$T/l.json")" = "$(jq -c '.by_suite_version["1"].decisions' "$FX/versions/report.json")" ]
+  jq -c 'if .run_id == "ver-v2-a0_bare-rc-02-t2" then del(.suite_version) else . end' "$FX/legacy/runs.jsonl" > "$T/sc.jsonl"
+  run python3 -I "$REPORT" --runs "$T/sc.jsonl" --manifests "$FX/legacy/manifests" --suite "$SUITE" --out "$T/sc.md"
+  [ "$status" -eq 2 ]
+  [[ "$output" == *"row ver-v2-a0_bare-rc-02-t2 has no suite_version while the rows hold suite_version 1, 2"* ]]
+}
+
+@test "AR-40 a version-less listed row (among two versions) passes the manifest arm_map check first: another arm exits 2 as a provenance conflict; the matching arm is listed as in AR-39" {
+  report legacy-conflict "$T/c"
+  [ "$status" -eq 2 ]
+  [[ "$output" == *"row leg-smoke-a1_full-fb-01-t1 arm a1_full disagrees with "*"/leg-smoke/MANIFEST.json arm_map (a0_bare)"* ]]
+  [ ! -e "$T/c.md" ]
+  report legacy-match "$T/m"
+  [ "$status" -eq 0 ]
+  [ "$(jq -r '.listed[] | select(.run_id == "leg-smoke-a1_full-fb-01-t1") | .reason' "$T/m.json")" = "no suite_version; smoke batch leg-smoke" ]
+  [ "$(jq -r '.listed[] | select(.run_id == "leg-loose-a0_bare-fb-01-t1") | .reason' "$T/m.json")" = "no suite_version; no manifest for batch leg-loose" ]
+  report legacy "$T/l"
+  [ "$status" -eq 0 ]
+  for k in h1 a4 decisions listed by_suite_version; do
+    [ "$(jq -c ".$k" "$T/m.json")" = "$(jq -c ".$k" "$T/l.json")" ]
+  done
+}
+
+@test "AR-41 an exception while computing the batch record (a manifest suite_version int() refuses) leaves the report written: exit 0, decisions present, Not rendered with a note" {
+  report batch-broken "$T/b"
+  [ "$status" -eq 0 ]
+  [[ "$output" != *"Traceback"* ]]
+  grep -qxF '## Decisions' "$T/b.md"
+  grep -qxF '## Batch record' "$T/b.md"
+  # report 1.2.3 (audit DISS-C-002): the class and the stage only, never the exception text
+  grep -qxF 'Not rendered (ValueError while reading the batch record of ver-v2); it decides nothing.' "$T/b.md"
+  grep -qxF '## Method' "$T/b.md"
+  [ "$(jq -c .batches "$T/b.json")" = "[]" ]
+  [ "$(jq -r .batches_note "$T/b.json")" = "batch record not computed (ValueError while reading the batch record of ver-v2); it decides nothing" ]
+  for k in h1 a4 decisions by_suite_version; do
+    [ "$(jq -c ".$k" "$T/b.json")" = "$(jq -c ".$k" "$FX/versions/report.json")" ]
+  done
+  [ "$(jq -r .batches_note "$FX/versions/report.json")" = "null" ]
+}
+
+@test "AR-42 run directories: zero-padded rc-01-t01 is trial 1; a trial with only a graded-less rerun is n/a x1 and not missing; a zero-padded rerun is read" {
+  report rundirs "$T/r"
+  [ "$status" -eq 0 ]
+  b() { jq -r --arg b "$1" ".batches[] | select(.batch == \$b) | $2" "$T/r.json"; }
+  [ "$(b rd-1 '.grader_versions | to_entries | map("\(.key)=\(.value)") | join(",")')" = "1.2.11=1,1.2.5=1,n/a=1" ]
+  [ "$(b rd-1 .run_dirs_missing)" = "0" ]
+  [ "$(b rd-1 '([.grader_versions[]] | add) == .trials_rowed')" = "true" ]
+  grep -qF '| `rd-1` | no STATUS.json | — / 3 | — | — | — | — | — | — | — | — | 1.2.5 ×1, 1.2.11 ×1, n/a ×1 |' "$T/r.md"
+  # the graded-less rerun is the only directory of t2: removing it makes t2 missing
+  cp -R "$FX/rundirs/manifests" "$T/rm"
+  rmdir "$T/rm/rd-1/a1_full/rc-01-t2-r2"
+  run python3 -I "$REPORT" --runs "$FX/rundirs/runs.jsonl" --manifests "$T/rm" --suite "$SUITE" --out "$T/rm.md" --json "$T/rm.json"
+  [ "$status" -eq 0 ]
+  [ "$(jq -r '.batches[0].run_dirs_missing' "$T/rm.json")" = "1" ]
+}
+
+@test "AR-43 inconsistent defects_missed ids (outside d1 … dN, a duplicate, a count against defects_caught, outside the grammar) read as the rate; H1 unchanged in state" {
+  c() { jq -r --arg m defect_catch_rate ".h1.comparisons[] | select(.metric == \$m) | $2" "$FX/$1/report.json"; }
+  [ "$(c ids-bad '.defect_identity | join(",")')" = "ids,rate" ]
+  [ "$(c versions '.defect_identity | join(",")')" = "ids" ]
+  [ "$(jq -r .h1.state "$FX/ids-bad/report.json")" = "$(jq -r .h1.state "$FX/versions/report.json")" ]
+  [ "$(jq -r .h1.state "$FX/ids-bad/report.json")" = "established" ]
+  # the rate spreads the same per-task share over the defects: d is the versions d (1.2.2 read 0.222)
+  [ "$(c ids-bad .d)" = "$(c versions .d)" ]
+  [ "$(c ids-bad .d)" = "0.444444" ]
+  # the budget-matched union refuses the ids too
+  [ "$(jq -r '[.budget_matched.tasks[].method] | unique | join(",")' "$FX/ids-bad/report.json")" = "rate fallback" ]
+  [ "$(jq -r '[.budget_matched.tasks[].method] | unique | join(",")' "$FX/versions/report.json")" = "defect union" ]
+}
+
+@test "AR-44 a non-numeric and a NaN cost_usd: the report is written, each cost read as 0 with one note, report.json is valid JSON, no traceback" {
+  report costs-bad "$T/c"
+  [ "$status" -eq 0 ]
+  [[ "$output" != *"Traceback"* ]]
+  [[ "$output" == *"note: row ver-v1-a4_no_gates-fb-01-t1 cost_usd is a str, not a number; read as 0"* ]]
+  [[ "$output" == *"note: row ver-v2-a0_bare-rc-01-t1 cost_usd is NaN or an infinity; read as 0"* ]]
+  [ "$(grep -c 'note: row ver-v2-a0_bare-rc-01-t1 cost_usd' <<<"$output")" -eq 1 ]
+  ! grep -qE 'NaN|Infinity' "$T/c.json" || false
+  python3 -I -c 'import json,sys; json.loads(open(sys.argv[1]).read(), parse_constant=lambda c: sys.exit(1))' "$T/c.json"
+  for k in h1 a4 decisions; do
+    [ "$(jq -c "[.$k | .. | .state? // empty]" "$T/c.json")" = "$(jq -c "[.$k | .. | .state? // empty]" "$FX/versions/report.json")" ]
+  done
+  # each bad cost reads 0: a0 (v2) 1.0 → 11/12, a4 (v1) 3.0 → 105/36
+  jq -e '.arms.a0_bare.cost_per_run == 1' "$FX/versions/report.json"
+  jq -e '.arms.a0_bare.cost_per_run == 0.916667' "$T/c.json"
+  jq -e '.by_suite_version["1"].arms.a4_no_gates.cost_per_run == 2.916667' "$T/c.json"
+}
+
+@test "AR-45 a non-finite number that reaches the JSON twin fails loudly naming the key; nothing is written" {
+  cp -R "$FX/present/manifests" "$T/m"
+  python3 -I -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["spend"]["max_usd"]=float("nan"); json.dump(d, open(p,"w"))' \
+    "$T/m/pr-2/STATUS.json"
+  run python3 -I "$REPORT" --runs "$FX/present/runs.jsonl" --manifests "$T/m" --suite "$SUITE" --out "$T/n.md" --json "$T/n.json"
+  [ "$status" -eq 2 ]
+  [[ "$output" != *"Traceback"* ]]
+  [[ "$output" == *'refusing to write a non-finite number to the JSON report at $.batches[1].spend.max_usd'* ]]
+  [ ! -e "$T/n.md" ] && [ ! -e "$T/n.json" ]
+}
+
+@test "AR-46 an arm \"../..\" and a task_id \"../x\" never build a path: the canary outside the batch directory is not read; a symlinked meta/ is refused" {
+  report escape "$T/e"
+  [ "$status" -eq 0 ]
+  b() { jq -r ".batches[] | select(.batch == \"esc-1\") | $1" "$T/e.json"; }
+  # 1.2.2 read the canary through arm ../.. (6.6.6-canary ×1) and matched rc-01-t3-r2 through its symlinked meta/
+  [ "$(b '.grader_versions | to_entries | map("\(.key)=\(.value)") | join(",")')" = "1.2.11=1,1.2.5=2,n/a=2" ]
+  [ "$(b .run_dirs_missing)" = "2" ]
+  [ "$(b .note)" = "2 rows with an arm or task_id outside the grammar (no attributable directory)" ]
+  ! grep -q 'canary' "$T/e.md" "$T/e.json" || false
+  [ "$(b '([.grader_versions[]] | add) == .trials_rowed')" = "true" ]
+  # the canary is still there, untouched, and outside the manifests root
+  [ "$(jq -r .grader_version "$FX/escape/rc-01-t1/grade.json")" = "6.6.6-canary" ]
+}
+
+@test "AR-47 the sanitized never-fatal text: an exception in one batch's grader tally names the class and the stage, never the exception text" {
+  cp -R "$FX/present/manifests" "$T/m"
+  # "²" passes str.isdigit() and int() refuses it: grader_key raises ValueError("invalid literal … '²'")
+  printf '{"grader_version": "SECRETVALUE.\\u00b2"}\n' > "$T/m/pr-2/a0_bare/rc-01-t1/grade.json"
+  run python3 -I "$REPORT" --runs "$FX/present/runs.jsonl" --manifests "$T/m" --suite "$SUITE" --out "$T/s.md" --json "$T/s.json"
+  [ "$status" -eq 0 ]
+  [[ "$output" != *"Traceback"* ]]
+  # the full text goes to stderr once
+  [ "$(grep -c "ValueError while tallying the grader versions of pr-2: invalid literal" <<<"$output")" -eq 1 ]
+  [ "$(jq -r '.batches[] | select(.batch == "pr-2") | .note' "$T/s.json")" = \
+    "grader tally incomplete (ValueError while tallying the grader versions of pr-2)" ]
+  grep -qF 'grader tally incomplete (ValueError while tallying the grader versions of pr-2)' "$T/s.md"
+  ! grep -q 'invalid literal' "$T/s.md" "$T/s.json" || false
+  ! grep -qF "$T" "$T/s.md" || false
+}
~~~~

## H48 — evals/tests/ablation-row.bats — head line 409

Head context (head/evals/tests/ablation-row.bats, lines 397–421):

~~~~text
   397 |   run row a1-build "$BUILD_TASK"
   398 |   [ "$status" -eq 2 ]
   399 |   [[ "$output" == *"row build failed for abl-fixture-a1_full-bf-01-t1"* ]]
   400 |   [ ! -s "$T/rows.jsonl" ]
   401 | }
   402 | 
   403 | # --- row writer 1.2: defects_missed (bd-yz1rd) and regressions_final_green (bd-m0hw7) ---
   404 | edit_grade() {  # edit_grade <run> <jq filter>
   405 |   jq "$2" "$T/runs/$1/grade.json" > "$T/g.json" && mv "$T/g.json" "$T/runs/$1/grade.json"
   406 | }
   407 | 
   408 | @test "defects_missed: a review-catch row copies recall.missed; regressions_final_green is null" {
>  409 |   edit_grade a3-review '.recall.missed = ["d2","d5"]'
   410 |   row a3-review "$REVIEW_TASK"
   411 |   run "$ROW" --validate "$T/rows.jsonl"
   412 |   [ "$status" -eq 0 ]
   413 |   [ "$(jq -c '[.defects_missed, .regressions_final_green]' <<<"$(last)")" = '[["d2","d5"],null]' ]
   414 | }
   415 | 
   416 | @test "defects_missed: an empty recall.missed is [], an absent one or a null recall is null" {
   417 |   edit_grade a3-review '.recall.missed = []'
   418 |   row a3-review "$REVIEW_TASK"
   419 |   [ "$(jq -c '.defects_missed' <<<"$(last)")" = '[]' ]
   420 |   edit_grade a3-review 'del(.recall.missed)'
   421 |   row a3-review "$REVIEW_TASK"
~~~~

The change from head to the fix:

~~~~diff
@@ -409 +409,2 @@
-  edit_grade a3-review '.recall.missed = ["d2","d5"]'
+  # row writer 1.3: the list must agree with the counts (8 seeded − 2 missed = 6 caught)
+  edit_grade a3-review '.recall.defects_seeded = 8 | .recall.defects_caught = 6 | .recall.missed = ["d2","d5"]'
~~~~

## H49 — evals/tests/ablation-row.bats — head line 417

Head context (head/evals/tests/ablation-row.bats, lines 405–429):

~~~~text
   405 |   jq "$2" "$T/runs/$1/grade.json" > "$T/g.json" && mv "$T/g.json" "$T/runs/$1/grade.json"
   406 | }
   407 | 
   408 | @test "defects_missed: a review-catch row copies recall.missed; regressions_final_green is null" {
   409 |   edit_grade a3-review '.recall.missed = ["d2","d5"]'
   410 |   row a3-review "$REVIEW_TASK"
   411 |   run "$ROW" --validate "$T/rows.jsonl"
   412 |   [ "$status" -eq 0 ]
   413 |   [ "$(jq -c '[.defects_missed, .regressions_final_green]' <<<"$(last)")" = '[["d2","d5"],null]' ]
   414 | }
   415 | 
   416 | @test "defects_missed: an empty recall.missed is [], an absent one or a null recall is null" {
>  417 |   edit_grade a3-review '.recall.missed = []'
   418 |   row a3-review "$REVIEW_TASK"
   419 |   [ "$(jq -c '.defects_missed' <<<"$(last)")" = '[]' ]
   420 |   edit_grade a3-review 'del(.recall.missed)'
   421 |   row a3-review "$REVIEW_TASK"
   422 |   [ "$(jq -c '.defects_missed' <<<"$(last)")" = 'null' ]
   423 |   edit_grade a3-review '.recall = null'
   424 |   row a3-review "$REVIEW_TASK"
   425 |   [ "$(jq -c '.defects_missed' <<<"$(last)")" = 'null' ]
   426 |   edit_grade a3-review '.recall = {defects_seeded: 3, missed: "d2"}'
   427 |   row a3-review "$REVIEW_TASK"
   428 |   [ "$(jq -c '.defects_missed' <<<"$(last)")" = 'null' ]
   429 | }
~~~~

The change from head to the fix:

~~~~diff
@@ -417 +418 @@
-  edit_grade a3-review '.recall.missed = []'
+  edit_grade a3-review '.recall.defects_caught = 3 | .recall.missed = []'
~~~~

## H50 — evals/tests/ablation-row.bats — insertion after head line 479

Head context (head/evals/tests/ablation-row.bats, lines 468–479):

~~~~text
   468 |   [ "$status" -eq 1 ] && [[ "$output" == *"field defects_missed has type array"* ]]
   469 |   jq -c '.defects_missed = [""]' <<<"$good" > "$T/one.jsonl"
   470 |   run "$ROW" --validate "$T/one.jsonl"
   471 |   [ "$status" -eq 1 ]
   472 |   jq -c '.regressions_final_green = "yes"' <<<"$good" > "$T/one.jsonl"
   473 |   run "$ROW" --validate "$T/one.jsonl"
   474 |   [ "$status" -eq 1 ] && [[ "$output" == *"field regressions_final_green has type string, want boolean|null"* ]]
   475 |   { jq -c '.defects_missed = null | .regressions_final_green = true' <<<"$good"
   476 |     jq -c 'del(.defects_missed) | del(.regressions_final_green)' <<<"$good"; } > "$T/two.jsonl"
   477 |   run "$ROW" --validate "$T/two.jsonl"
   478 |   [ "$status" -eq 0 ] && [[ "$output" == *"2 rows valid"* ]]
   479 | }
~~~~

The change from head to the fix:

~~~~diff
@@ -479,0 +481,76 @@
+
+# --- row writer 1.3: the defects_missed id rules (Sprint 262 audit DISS-C-001) ---
+vrow() {  # vrow <missed json> <seeded> <caught> → $T/one.jsonl: the a3-review row with those fields
+  jq -c --argjson ms "$1" --argjson s "$2" --argjson c "$3" \
+    '.defects_missed = $ms | .defects_seeded = $s | .defects_caught = $c' <<<"$GOOD" > "$T/one.jsonl"
+}
+
+@test "--validate rejects defects_missed outside the id rules, naming the rule and the line" {
+  edit_grade a3-review '.recall.missed = ["d2"]'
+  row a3-review "$REVIEW_TASK"
+  GOOD="$(last)"
+  vrow '["x1"]' 3 2
+  run "$ROW" --validate "$T/one.jsonl"
+  [ "$status" -eq 1 ] && [[ "$output" == *'one.jsonl:1: defects_missed ["x1"] violates the rule: id grammar ^d[1-9][0-9]*$'* ]]
+  vrow '["d2","d2"]' 3 1
+  run "$ROW" --validate "$T/one.jsonl"
+  [ "$status" -eq 1 ] && [[ "$output" == *'one.jsonl:1: defects_missed ["d2","d2"] violates the rule: unique ids'* ]]
+  vrow '["d1","d2","d3","d4"]' 3 0
+  run "$ROW" --validate "$T/one.jsonl"
+  [ "$status" -eq 1 ] && [[ "$output" == *'one.jsonl:1: defects_missed ["d1","d2","d3","d4"] violates the rule: at most defects_seeded ids'* ]]
+  vrow '["d2"]' 3 1
+  run "$ROW" --validate "$T/one.jsonl"
+  [ "$status" -eq 1 ] && [[ "$output" == *'one.jsonl:1: defects_missed ["d2"] violates the rule: defects_seeded − ids == defects_caught'* ]]
+  vrow '["d4"]' 3 2
+  run "$ROW" --validate "$T/one.jsonl"
+  [ "$status" -eq 1 ] && [[ "$output" == *'violates the rule: ids within d1 … d<defects_seeded>'* ]]
+  vrow '["d0"]' 3 2
+  run "$ROW" --validate "$T/one.jsonl"
+  [ "$status" -eq 1 ] && [[ "$output" == *'violates the rule: id grammar'* ]]
+  # the line number is the bad row's: a good row first, the bad one second
+  { printf '%s\n' "$GOOD"; cat "$T/one.jsonl"; } > "$T/two.jsonl"
+  run "$ROW" --validate "$T/two.jsonl"
+  [ "$status" -eq 1 ] && [[ "$output" == *"two.jsonl:2: defects_missed"* ]]
+}
+
+@test "--validate accepts consistent defects_missed: [d2,d5] on 8 seeded with 6 caught, [] with caught == seeded, null counts unchecked" {
+  edit_grade a3-review '.recall.missed = ["d2"]'
+  row a3-review "$REVIEW_TASK"
+  GOOD="$(last)"
+  vrow '["d2","d5"]' 8 6
+  run "$ROW" --validate "$T/one.jsonl"
+  [ "$status" -eq 0 ]
+  vrow '[]' 3 3
+  run "$ROW" --validate "$T/one.jsonl"
+  [ "$status" -eq 0 ]
+  vrow '["d2"]' null null
+  run "$ROW" --validate "$T/one.jsonl"
+  [ "$status" -eq 0 ]
+  # the rules apply to review-catch rows only: a build row is not checked
+  jq -c '.task_type = "bug-fix" | .defects_missed = ["x1"]' <<<"$GOOD" > "$T/one.jsonl"
+  run "$ROW" --validate "$T/one.jsonl" --allow-ungraded
+  [ "$status" -eq 0 ]
+}
+
+@test "the row program writes defects_missed null for an inconsistent recall.missed, every other field unchanged" {
+  edit_grade a3-review '.recall.missed = ["d2"]'
+  row a3-review "$REVIEW_TASK"
+  local good; good="$(last)"
+  [ "$(jq -c .defects_missed <<<"$good")" = '["d2"]' ]
+  for ms in '["x1"]' '["d2","d2"]' '["d1","d2","d3","d4"]' '["d1","d2"]' '["d4"]'; do
+    edit_grade a3-review ".recall.missed = $ms"
+    row a3-review "$REVIEW_TASK"
+    [ "$(jq -c .defects_missed <<<"$(last)")" = null ]
+    [ "$(jq -c 'del(.defects_missed, .started, .finished, .wall_clock_ms)' <<<"$(last)")" = "$(jq -c 'del(.defects_missed, .started, .finished, .wall_clock_ms)' <<<"$good")" ]
+  done
+  run "$ROW" --validate "$T/rows.jsonl"
+  [ "$status" -eq 0 ]
+}
+
+@test "the 165 tracked runs.jsonl rows still validate under row writer 1.3 (read-only copy)" {
+  local real="$REPO_ROOT/grimoires/loa/reports/ablation-2.0/runs.jsonl"
+  [ -f "$real" ] || skip "no tracked runs.jsonl"
+  cp "$real" "$T/real.jsonl"
+  run "$ROW" --validate "$T/real.jsonl"
+  [ "$status" -eq 0 ] && [[ "$output" == *"real.jsonl: 165 rows valid"* ]]
+}
~~~~

## H51 — evals/tests/fixtures/ablation-report/gen-fixtures.py — insertion after head line 66

Head context (head/evals/tests/fixtures/ablation-report/gen-fixtures.py, lines 55–78):

~~~~text
    55 | #                 without defects_missed at 0.5 → "rate fallback" (0.500); a1_full (USD 10.00, 0
    56 | #                 false positives) rc-01 misses d1 each trial (0.875), rc-02 misses nothing (1.000);
    57 | #                 a3_one_voice rc-01/rc-02 catches nothing with 0 false positives (precision and cost
    58 | #                 per true defect null). a0 precision 11 / 17 = 0.647059, USD 6 / 11 = 0.545455; a1
    59 | #                 precision 1.0, USD 60 / 27 = 2.222222. Budget-matched: a0 union mean 0.75, a1 mean
    60 | #                 0.9375; "3 a0_bare trials cost USD 3.00 vs one a1_full trial USD 10.00".
    61 | #                 manifests/pr-2/STATUS.json holds rerowed (2 completed→completed, 1 contaminated→
    62 | #                 cap_failure), rerun (1 transport_error→completed), drift_cleared 1, outage_history 2,
    63 | #                 extra_models, a cut and a paused arm; run dirs a0_bare/rc-01-t1 (grade.json grader
    64 | #                 1.2.5), rc-01-t2-r2 (1.2.11), rc-01-t3 (no grade.json). Batch pr-1 (suite_version 1,
    65 | #                 build rows of a0/a1 only, no STATUS.json, no run dirs): the budget-matched section of
    66 | #                 suite_version 1 reads "not available".
    67 | # =============================================================================
    68 | import json
    69 | import os
    70 | import sys
    71 | 
    72 | BUILD = [("fb-%02d" % k, "feature-build") for k in range(1, 5)] + \
    73 |         [("bf-%02d" % k, "bug-fix") for k in range(1, 5)] + \
    74 |         [("rf-%02d" % k, "refactor") for k in range(1, 5)]
    75 | RC = [("rc-01", 8), ("rc-02", 2), ("rc-03", 4), ("rc-04", 4)]
    76 | TRIALS = (1, 2, 3)
    77 | SRC = "1111111111111111111111111111111111111111"
    78 | SHA = "30e1f2ad" + "0" * 56
~~~~

The change from head to the fix:

~~~~diff
@@ -66,0 +67,41 @@
+#
+# Sprint 262 R4 (report 1.2.1: version keys, the batch-record grader tally, version-less listed rows):
+#   graders       batch gr-mixed (suite_version 2): a1_full rc-01 t1..t3 with run dirs rc-01-t1 (grader
+#                 1.2.0), rc-01-t2 (1.2.0-rc1), rc-01-t3 (no grade.json) → tally 1.2.0 ×1, 1.2.0-rc1 ×1,
+#                 n/a ×1 (1.2.0 aborted on the mixed int/str sort key); batch gr-rerun: a0_bare rc-01 t1
+#                 with rc-01-t1 (meta/pipeline.json run_id = the row's, interrupted, no grade), rc-01-t1-r2
+#                 (the same run_id, grader 1.2.11) and rc-01-t1-r3 (another run_id, grader 9.9.9) → the
+#                 row reads r2 once: 1.2.11 ×1, run_dirs_missing 0; batch gr-missing: a0_bare rc-01 t2
+#                 with no run dir → n/a ×1, run_dirs_missing 1
+#   versions-float  batch vf-2 (suite_version 2) and vf-21 (suite_version 2.1, a float): a1/a0 on the
+#                 review tasks as in versions' v2 (a0 misses d1, d2); vf-21's a0 misses d1 only → the two
+#                 versions are never pooled, keys "2" and "2.1", 2.1 primary
+#   legacy        the versions scenario plus version-less rows that never reach a decision: a smoke batch
+#                 leg-smoke (manifest suite_version null) with an a1_full row and an unbatched row (batch
+#                 leg-loose, no manifest) → listed under the primary version 2 as "no suite_version; …"
+#
+# Sprint 262 R5 (report 1.2.2: provenance before listing, never-fatal batch record, run-dir attribution):
+#   legacy-conflict  legacy with leg-smoke's manifest arm_map naming a0_bare for the version-less a1_full
+#                 row → exit 2 as a provenance conflict (1.2.1 listed it); legacy-match: the arm_map names
+#                 a1_full → listed as in legacy
+#   batch-broken  the versions scenario with ver-v2's manifest suite_version a 5,000-digit numeric string
+#                 (int() refuses it past 4,300 digits; only the batch record reads a manifest's
+#                 suite_version) → the batch record is not computed, the decisions are those of versions
+#   rundirs       batch rd-1 (suite_version 2): a1_full rc-01 t1..t3; run dirs rc-01-t01 (zero-padded,
+#                 grader 1.2.11), rc-01-t2-r2 only (no grade.json, no meta/pipeline.json), rc-01-t03-r02
+#                 only (zero-padded rerun, grader 1.2.5) → 1.2.11 ×1, 1.2.5 ×1, n/a ×1, run_dirs_missing 0
+#
+# Sprint 262 audit (report 1.2.3: id rules, numeric guards, path grammar):
+#   ids-bad       the versions scenario with ver-v2's a0_bare defects_missed inconsistent on every task
+#                 (rc-01 ["d1","d9"]: d9 outside d1 … d8; rc-02 ["d1","d1"]: a duplicate; rc-03 ["d1"]:
+#                 2 caught contradicts 4 − 1; rc-04 ["x1","d2"]: outside the grammar), defects_caught and
+#                 the rate unchanged → those rows read "rate"; d is the versions d (the rate spreads the
+#                 same per-task share), H1 established as in versions
+#   costs-bad     the versions scenario with one ver-v1 a4_no_gates row's cost_usd "12.5x" (a string) and
+#                 one ver-v2 a0_bare row's cost_usd NaN (written as the NaN token) → both read 0 with a
+#                 stderr note; report.json stays valid JSON
+#   escape        batch esc-1 (suite_version 2): a1_full rc-01 t1..t3 (rc-01-t1 grader 1.2.11; rc-01-t2
+#                 grader 1.2.5; rc-01-t3-r1 grader 1.2.5 and rc-01-t3-r2 whose meta/ is a symlink to
+#                 OUTDIR/escape/outside/meta holding the row's run_id) plus a row with arm "../.." (trial
+#                 1 of rc-01) and one with task_id "../x"; OUTDIR/escape/rc-01-t1/grade.json (outside the
+#                 batch directory, the target of arm "../..") holds the canary grader 6.6.6-canary
~~~~

## H52 — evals/tests/fixtures/ablation-report/gen-fixtures.py — head line 326

Head context (head/evals/tests/fixtures/ablation-report/gen-fixtures.py, lines 314–338):

~~~~text
   314 |                           {"run_id": "x3", "from": "completed", "to": "completed"}],
   315 |               "rerun": [{"run_id": "x4", "from": "transport_error", "to": "completed", "old_cost_usd": 0}],
   316 |               "drift_cleared": [{"run_id": "x5"}], "outage_history": [{"at": "a"}, {"at": "b"}],
   317 |               "cuts": [{"reason": "max_usd", "at_trial": 19, "spent": 99.5, "max": 100}],
   318 |               "paused_arms": {"a3_one_voice": "took_effect miss"}}
   319 |     extras = {f"{b2}/STATUS.json": status,
   320 |               f"{b2}/a0_bare/rc-01-t1/grade.json": {"grader_version": "1.2.5"},
   321 |               f"{b2}/a0_bare/rc-01-t2-r2/grade.json": {"grader_version": "1.2.11"},
   322 |               f"{b2}/a0_bare/rc-01-t3": None}
   323 |     return rows, {b2: manifest(b2, **V2), b1: manifest(b1)}, extras
   324 | 
   325 | 
>  326 | def write(out, name, rows, mans, extras=None):
   327 |     d = os.path.join(out, name)
   328 |     os.makedirs(d, exist_ok=True)
   329 |     with open(os.path.join(d, "runs.jsonl"), "w", encoding="utf-8") as fh:
   330 |         for r in rows:
   331 |             fh.write(json.dumps(r, sort_keys=True) + "\n")
   332 |     for b, m in mans.items():
   333 |         md = os.path.join(d, "manifests", b)
   334 |         os.makedirs(md, exist_ok=True)
   335 |         with open(os.path.join(md, "MANIFEST.json"), "w", encoding="utf-8") as fh:
   336 |             json.dump(m, fh, indent=2, sort_keys=True)
   337 |             fh.write("\n")
   338 |     for rel, data in sorted((extras or {}).items()):
~~~~

The change from head to the fix:

~~~~diff
@@ -326 +367,95 @@
-def write(out, name, rows, mans, extras=None):
+def graders_scenario():
+    bm, br, bx = "gr-mixed", "gr-rerun", "gr-missing"
+    rows = [rc_row(bm, "a1_full", "rc-01", 8, k, [], **V2) for k in TRIALS]
+    rows.append(rc_row(br, "a0_bare", "rc-01", 8, 1, ["d1", "d2"], cost=1.0, **V2))
+    rows.append(rc_row(bx, "a0_bare", "rc-01", 8, 2, ["d1", "d2"], cost=1.0, **V2))
+    rid = f"{br}-a0_bare-rc-01-t1"
+    extras = {f"{bm}/a1_full/rc-01-t1/grade.json": {"grader_version": "1.2.0"},
+              f"{bm}/a1_full/rc-01-t2/grade.json": {"grader_version": "1.2.0-rc1"},
+              f"{bm}/a1_full/rc-01-t3": None,
+              f"{br}/a0_bare/rc-01-t1/meta/pipeline.json": {"run_id": rid, "status": "interrupted"},
+              f"{br}/a0_bare/rc-01-t1-r2/meta/pipeline.json": {"run_id": rid, "status": "completed"},
+              f"{br}/a0_bare/rc-01-t1-r2/grade.json": {"grader_version": "1.2.11"},
+              f"{br}/a0_bare/rc-01-t1-r3/meta/pipeline.json": {"run_id": "another-run", "status": "completed"},
+              f"{br}/a0_bare/rc-01-t1-r3/grade.json": {"grader_version": "9.9.9"}}
+    return rows, {bm: manifest(bm, **V2), br: manifest(br, **V2), bx: manifest(bx, **V2)}, extras
+
+
+def versions_float_scenario():
+    b2, b21 = "vf-2", "vf-21"
+    v21 = {"sv": 2.1, "sha": SHA2}
+    rows = rc_rows(b2, "a1_full", NONE, **V2) + rc_rows(b2, "a0_bare", A0_MISS_D12, cost=1.0, **V2)
+    rows += rc_rows(b21, "a1_full", NONE, **v21)
+    rows += rc_rows(b21, "a0_bare", {t: ["d1"] for t, _ in RC}, cost=1.0, **v21)
+    return rows, {b2: manifest(b2, **V2), b21: manifest(b21, **v21)}
+
+
+def legacy_scenario():
+    rows, mans = versions_scenario()
+    smoke = row("leg-smoke", "a1_full", "fb-01", "feature-build", 1, rate=0.5, sv=None)
+    loose = row("leg-loose", "a0_bare", "fb-01", "feature-build", 1, rate=0.5, sv=None)
+    mans = dict(mans)
+    mans["leg-smoke"] = manifest("leg-smoke", smoke=True, sv=None)
+    return rows + [smoke, loose], mans
+
+
+def legacy_arm_map_scenario(arm):
+    def f():
+        rows, mans = legacy_scenario()
+        mans = dict(mans)
+        mans["leg-smoke"] = dict(mans["leg-smoke"], arm_map={"leg-smoke-a1_full-fb-01-t1": arm})
+        return rows, mans
+    return f
+
+
+def batch_broken_scenario():
+    rows, mans = versions_scenario()
+    mans = dict(mans)
+    mans["ver-v2"] = dict(mans["ver-v2"], suite_version="1" * 5000)
+    return rows, mans
+
+
+def rundirs_scenario():
+    b = "rd-1"
+    rows = [rc_row(b, "a1_full", "rc-01", 8, k, [], **V2) for k in TRIALS]
+    extras = {f"{b}/a1_full/rc-01-t01/grade.json": {"grader_version": "1.2.11"},
+              f"{b}/a1_full/rc-01-t2-r2": None,
+              f"{b}/a1_full/rc-01-t03-r02/grade.json": {"grader_version": "1.2.5"}}
+    return rows, {b: manifest(b, **V2)}, extras
+
+
+def ids_bad_scenario():
+    rows, mans = versions_scenario()
+    bad = {"rc-01": ["d1", "d9"], "rc-02": ["d1", "d1"], "rc-03": ["d1"], "rc-04": ["x1", "d2"]}
+    for r in rows:
+        if r["batch"] == "ver-v2" and r["arm"] == "a0_bare":
+            r["defects_missed"] = list(bad[r["task_id"]])
+    return rows, mans
+
+
+def costs_bad_scenario():
+    rows, mans = versions_scenario()
+    for r in rows:
+        if r["run_id"] == "ver-v1-a4_no_gates-fb-01-t1":
+            r["cost_usd"] = "12.5x"
+        if r["run_id"] == "ver-v2-a0_bare-rc-01-t1":
+            r["cost_usd"] = float("nan")
+    return rows, mans
+
+
+def escape_scenario():
+    b = "esc-1"
+    rows = [rc_row(b, "a1_full", "rc-01", 8, k, [], **V2) for k in TRIALS]
+    rows.append(rc_row(b, "../..", "rc-01", 8, 1, [], run_id="esc-1-up-rc-01-t1", **V2))
+    rows.append(rc_row(b, "a1_full", "../x", 8, 1, [], run_id="esc-1-a1_full-x-t1", status="infrastructure_error", **V2))
+    extras = {f"{b}/a1_full/rc-01-t1/grade.json": {"grader_version": "1.2.11"},
+              f"{b}/a1_full/rc-01-t2/grade.json": {"grader_version": "1.2.5"},
+              f"{b}/a1_full/rc-01-t3-r1/grade.json": {"grader_version": "1.2.5"},
+              f"{b}/a1_full/rc-01-t3-r2": None,
+              "../rc-01-t1/grade.json": {"grader_version": "6.6.6-canary"},
+              "../outside/meta/pipeline.json": {"run_id": f"{b}-a1_full-rc-01-t3", "status": "completed"}}
+    links = {f"{b}/a1_full/rc-01-t3-r2/meta": "../../../../outside/meta"}
+    return rows, {b: manifest(b, **V2)}, extras, links
+
+
+def write(out, name, rows, mans, extras=None, links=None):
~~~~

## H53 — evals/tests/fixtures/ablation-report/gen-fixtures.py — insertion after head line 346

Head context (head/evals/tests/fixtures/ablation-report/gen-fixtures.py, lines 335–358):

~~~~text
   335 |         with open(os.path.join(md, "MANIFEST.json"), "w", encoding="utf-8") as fh:
   336 |             json.dump(m, fh, indent=2, sort_keys=True)
   337 |             fh.write("\n")
   338 |     for rel, data in sorted((extras or {}).items()):
   339 |         path = os.path.join(d, "manifests", rel)
   340 |         if data is None:
   341 |             os.makedirs(path, exist_ok=True)
   342 |             continue
   343 |         os.makedirs(os.path.dirname(path), exist_ok=True)
   344 |         with open(path, "w", encoding="utf-8") as fh:
   345 |             json.dump(data, fh, indent=2, sort_keys=True)
   346 |             fh.write("\n")
   347 | 
   348 | 
   349 | def main(argv):
   350 |     if len(argv) != 1:
   351 |         sys.stderr.write("usage: gen-fixtures.py OUTDIR\n")
   352 |         return 2
   353 |     for name, fn in (("main", main_scenario), ("boundary", boundary_scenario),
   354 |                      ("exclusions", exclusions_scenario), ("partial", partial_scenario),
   355 |                      ("versions", versions_scenario), ("degraded", degraded_scenario),
   356 |                      ("degraded-a4", degraded_a4_scenario),
   357 |                      ("degenerate-1", degenerate_scenario("dg-1", ("rc-04",), False)),
   358 |                      ("degenerate-2", degenerate_scenario("dg-2", ("rc-03", "rc-04"), False)),
~~~~

The change from head to the fix:

~~~~diff
@@ -346,0 +482,4 @@
+    for rel, target in sorted((links or {}).items()):
+        path = os.path.join(d, "manifests", rel)
+        os.makedirs(os.path.dirname(path), exist_ok=True)
+        os.symlink(target, path)
~~~~

## H54 — evals/tests/fixtures/ablation-report/gen-fixtures.py — head line 360

Head context (head/evals/tests/fixtures/ablation-report/gen-fixtures.py, lines 348–366):

~~~~text
   348 | 
   349 | def main(argv):
   350 |     if len(argv) != 1:
   351 |         sys.stderr.write("usage: gen-fixtures.py OUTDIR\n")
   352 |         return 2
   353 |     for name, fn in (("main", main_scenario), ("boundary", boundary_scenario),
   354 |                      ("exclusions", exclusions_scenario), ("partial", partial_scenario),
   355 |                      ("versions", versions_scenario), ("degraded", degraded_scenario),
   356 |                      ("degraded-a4", degraded_a4_scenario),
   357 |                      ("degenerate-1", degenerate_scenario("dg-1", ("rc-04",), False)),
   358 |                      ("degenerate-2", degenerate_scenario("dg-2", ("rc-03", "rc-04"), False)),
   359 |                      ("degenerate-ids", degenerate_scenario("dg-ids", ("rc-04",), True)),
>  360 |                      ("present", present_scenario)):
   361 |         write(argv[0], name, *fn())
   362 |     return 0
   363 | 
   364 | 
   365 | if __name__ == "__main__":
   366 |     sys.exit(main(sys.argv[1:]))
~~~~

The change from head to the fix:

~~~~diff
@@ -360 +499,7 @@
-                     ("present", present_scenario)):
+                     ("present", present_scenario), ("graders", graders_scenario),
+                     ("versions-float", versions_float_scenario), ("legacy", legacy_scenario),
+                     ("legacy-conflict", legacy_arm_map_scenario("a0_bare")),
+                     ("legacy-match", legacy_arm_map_scenario("a1_full")),
+                     ("batch-broken", batch_broken_scenario), ("rundirs", rundirs_scenario),
+                     ("ids-bad", ids_bad_scenario), ("costs-bad", costs_bad_scenario),
+                     ("escape", escape_scenario)):
~~~~
