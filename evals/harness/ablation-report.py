#!/usr/bin/env python3
# =============================================================================
# ablation-report.py — the cycle-130 ablation report (PRD FR-8, SDD §5.12, §4.2)
#
# Reads runs.jsonl rows (SDD §3.1, ablation-row.sh), the batch MANIFEST.json files
# (SDD §3.4, run-ablation.sh) and the suite file (evals/suites/ablation-2.0.yaml:
# arms[], trials, cut_ladder, priority and the pre-registered `rules` block, D-A5),
# applies the pre-registered rules to every component arm (A2 … A7) against the
# control a1_full, checks H1 (a1_full vs a0_bare) and the A4 sensitivity rule, and
# writes report.md (and a --json twin with the same numbers). Reads, never writes, each batch's
# STATUS.json and its run directories' grade.json (the batch record).
#
# Usage:
#   ablation-report.py --runs F [--runs F ...] --manifests DIR [--manifests DIR ...]
#                      --suite F --out report.md [--json report.json]
#                      [--seed 20261015] [--resamples N] [--level L]
#                      [--exclude-degraded true|false] [--partial]
#                      [--cuts F] [--not-run CSV] [--suite-version N]
#                      [--pin SHA] [--exclude-oracle-exposed true|false]
#
# Options:
#   --runs F            a runs.jsonl file (repeatable). Every non-blank line is one row
#                       and must carry schema_version 1 (an integer, or a "1.x" string);
#                       a row with another major, no schema_version, or a line that is not
#                       a JSON object stops the report (exit 2, naming file:line and run_id).
#                       A run_id seen twice keeps its last row (the earlier one is listed).
#   --manifests DIR     a directory searched recursively (symlinks not followed) for
#                       MANIFEST.json files (repeatable). Each gives a batch's provenance:
#                       batch, arm_map, shuffle_seed, source_commit, suite_manifest_sha256,
#                       suite_version, pre_registration_ref, cli_version (top level or
#                       executor.cli_version), image_digest, smoke. A manifest with an
#                       unknown schema_version major, two manifests claiming one batch, or
#                       an arm_map entry disagreeing with a row's arm → exit 2.
#   --suite F           the suite file: YAML read through `yq -o=json` (mikefarah yq v4,
#                       as arms-report.py does), or JSON when the file parses as JSON.
#                       The Method section quotes its `rules:` block verbatim.
#   --out F             report.md (the only files written are --out and --json; a symlink
#                       at either path is refused)
#   --json F            the JSON twin (schema_version 1)
#   --seed N            bootstrap seed (default 20261015); every interval uses its own
#                       random.Random(seed), so a figure does not depend on which other
#                       arms are present
#   --resamples N       default rules.bootstrap.resamples (10,000); a value other than the
#                       pre-registered one is marked in the header
#   --level L           default rules.bootstrap.level (0.90); same marking
#   --exclude-degraded  true (default) | false: rows with degraded: true are excluded
#                       pairwise (rules.exclusion.statuses names `degraded`)
#   --partial           prints "PARTIAL — rows so far, no decision is final"; exit 1 when no
#                       comparison (A2–A7, H1, A4) has a valid pair on every primary it uses
#   --cuts F            a JSON list of {arm, reason, figure[, state]} the lead recorded;
#                       arm is an id (a5_no_flatline) or a label (A5); state is not_run_cut
#                       (default) or inconclusive_by_power (a pre-declared power cut)
#   --not-run CSV       arm ids or labels read as Not run (cut) with figure "--not-run"
#   --suite-version N   the suite_version the main sections report (default: the highest
#                       present); a version no row holds → exit 2. When that version is split
#                       by pin or rule (report 1.3), its largest partition is the primary
#   --pin SHA           read only the rows whose source_commit starts with SHA (4–40 lowercase
#                       hex); the header counts the rows left out; no row left → exit 2
#   --exclude-oracle-exposed true|false  (default false) true applies the oracle-exposed rule
#                       below in the main reads too (a pre-registration that names it, FR-6);
#                       false keeps it in its labelled sensitivity only
#
# Report 1.3 (cycle-131 Sprint 263 Task 1.6, SDD §3.5, D-2.3, D-3.3):
#   decision statistic  defect_catch_rate (row writer 1.4: grader 1.3's rule, the row's
#                   grader_rule); every catch read (H1 and each component) prints
#                   defect_catch_rate_pm3 and defect_catch_rate_pm3_v1 beside it, with the same
#                   pairs, unit and bootstrap, deciding nothing ("n/a" when a paired row lacks the
#                   field: a 1.2.x grade). JSON comparisons[].beside {metric: {n, unit, d, lo, hi,
#                   valid_cells, insufficient} | null}; decision_statistic, beside.
#   partitions      rows are partitioned by suite_version and, within a version holding more than
#                   one source_commit or grader_rule (a review-catch row without one reads "pm3",
#                   the 1.2.x rule), by "<version> · pin <12 hex> · rule <rule>" keys — never pooled;
#                   each partition is a version section as before, the primary the highest version's
#                   largest partition.
#   valid cells     a contrast's valid cells are, per paired task, the smaller of the two arms' valid
#                   trial counts; fewer than rules.min_valid_cells (default 4) reads "insufficient":
#                   not usable by a component decision ("no valid pair (…: insufficient, k valid
#                   cells < 4)"), H1 "H1: insufficient — fewer than 4 valid cells", A4 likewise; the
#                   degenerate check is read first. JSON valid_cells, insufficient.
#   sensitivities   two labelled analyses per partition, deciding nothing, each with the rows its rule
#                   excluded per arm printed beside the reads: "oracle-exposed cells excluded" (a row
#                   whose oracle_exposed_defects or oracle_exposed_unknown is non-empty leaves its cell
#                   pairwise; a row whose oracle_open is true is reported, never excluded) and
#                   "dissent-absent gates excluded" (a row whose dissent_absent_reason names budget,
#                   preflight or error; a planned absence, disabled, never). JSON sensitivities
#                   {oracle_exposed_excluded, dissent_absent_excluded: {label, excluded_rows_per_arm,
#                   reported_open_rows_per_arm, h1, a4, rows}}.
#   finding volume  per review-catch arm: flags per valid row (finding_volume_per_run) and planted
#                   defects caught ÷ findings flagged (precision_planted_per_flag), informational.
#
# Suite versions (Sprint 262): rows of different suite_version values are never pooled. The
# main sections (Decisions, Per-arm detail, Exclusions, Cuts, Sensitivity, Rows per cell) read
# the primary version only; every other version gets "## Suite version N (batches: …) —
# reported separately, never pooled" with its own decision table, H1 and A4 lines, per-arm
# figures and exclusions. The header lists each version with its batches and manifest sha256
# (DRIFT is more than one sha256 within one version). A row without suite_version among rows of
# two or more versions → exit 2 when it would enter a cell; one that would be listed anyway (no
# manifest, smoke batch, arm not run, unknown or inapplicable task type) is listed under the primary
# version as never decided, reason "no suite_version; <the listing reason>" (report 1.2.1); when one
# version (or none) is present, such rows join it. Every row passes the manifest arm_map provenance
# check (DEC-0407, exit 2) before any partition or listing decision, a version-less row included (1.2.2).
# Version keys (report 1.2.1): an integer-valued number or numeric string keys to the integer ("2",
# 2, 2.0 and "2.0" are one version "2"); another finite number keys to its shortest round-trip form
# (2.1 and "2.10" → "2.1"); another string keys to itself, stripped; absent = null, a boolean, an
# empty or blank string, or a non-number non-string. --suite-version is keyed by the same rule.
# Numeric keys sort numerically, every other key after them, lexically; the primary is the last.
# JSON primary_suite_version is an int for an integer key, a float for another numeric key. Since 1.2.2 every
# JSON version value has that type: primary_suite_version, by_suite_version[N].suite_version, h1/a4
# .suite_version (top level, per version, sensitivity), budget_matched.suite_version and
# batches[].suite_version (a string for a non-numeric key or a "1, 2" list, null for n/a); the
# by_suite_version object keys stay strings.
# JSON: primary_suite_version and by_suite_version {"N": {suite_version, rows, batches,
# suite_manifest_sha256, decidable, h1, a4, decisions, arms, exclusions, listed, cap_failures}};
# the top-level keys describe the primary version.
#
# Row treatment (DEC-0393, DEC-0417):
#   not decided, listed  rows of a smoke batch (manifest smoke: true), rows whose batch has
#                        no manifest, rows of an arm the suite does not run (absent or
#                        unknown), rows on a task type outside the arm's task_types
#                        (applicability refusals; not counted in the excluded share)
#   excluded pairwise    status in rules.exclusion.statuses plus transport_error and
#                        infrastructure_error (DEC-0417), degraded: true (with
#                        --exclude-degraded true), and a scoring status whose primary is
#                        null (ungraded); the task-trial cell leaves BOTH arms of every
#                        comparison it is in; a cell holding a valid row (a rerun) is valid
#   cap_failure          0 on every applicable primary (pass rate 0, every defect missed)
#   completed, agent_error  score what the row holds (hidden_test_pass_rate; defects)
#   The sensitivity figure repeats the comparison with cap_failure excluded pairwise
#   instead of scored 0; no decision reads it.
#
# Statistics (pre-registered in the suite's rules block; formulas in the Method section):
#   pass rate unit  the task: per task, the mean over its valid trials, arm minus a1_full
#   catch-rate unit the defect: per review-catch task and defect dK, the share of the
#                   arm's valid trials that caught it, arm minus a1_full; per-defect ids
#                   come from the row's `defects_missed` (or `recall.missed`) list of dK
#                   ids when present and consistent, else each defect of the task takes the row's
#                   defect_catch_rate (aggregate rows; report 1.2.3: a list with an id outside
#                   d1 … dN of the task, a duplicate id, or N − len(ids) ≠ a numeric defects_caught
#                   is inconsistent and reads as the rate, "rate" in defect_identity, never
#                   "ids"; the row writer 1.3 rules); the task-level figure is also
#                   reported (rules.bootstrap.also_report) and decides nothing
#   interval        percentile bootstrap of the mean paired difference: `resamples`
#                   resamples with replacement, linear interpolation between order
#                   statistics, [lo, hi] = the (1-level)/2 and 1-(1-level)/2 quantiles
#   d               the mean of the paired differences (not the bootstrap mean)
#   c, w            cost and wall-clock delta in percent against a1_full,
#                   (mean_arm − mean_a1) / mean_a1 × 100, over the per-task means of the
#                   cells the primaries paired
#   MDE             (z(1−(1−level)/2) + z(0.90)) × sd(paired diffs) / sqrt(n): the smallest
#                   true mean difference a paired test at the report level detects with 0.90
#                   power at the available n; n < 2 → n/a
#   comparisons     every predicate compares values rounded to 9 decimals, so a planted
#                   −0.03 reads −0.03 and not −0.030000000000000027
#
# Decision per arm (rules.predicates, first match, DEC-0416, with DEC-0393's guard first):
#   the degradation guard (excluded share > rules.exclusion.inconclusive_above_share →
#   inconclusive, labelled Inconclusive-by-degradation, whatever the interval) →
#   investigate → keep → inconclusive (d < -0.03 or no valid pair) → remove → simplify. Then: an arm named by --cuts / --not-run reads
#   Not run (cut) or Inconclusive-by-power with the lead's figure; an arm whose MDE on an
#   applicable primary exceeds rules.mde_cut and whose predicate outcome is remove or
#   simplify reads Inconclusive-by-power with the figure (a null result the sample could
#   not have detected); A8 (absent: true) reads component-absent with the suite evidence.
#
# H1 and A4 lines (Sprint 262): each comparison is read, first match: not_testable (no task of
#   the primary's types in either arm: "<metric>: not testable on suite_version N — no
#   admissible task") → inconclusive_by_degradation (either arm's excluded share over its cells
#   on that primary's task types > rules.exclusion.inconclusive_above_share) → degenerate (a
#   defect_catch_rate comparison whose pairs come from one task and whose rows carry no
#   per-defect ids: the interval is zero-variance by construction; flagged degenerate: true with
#   degenerate_reason and read as no valid pair, also by the component decisions) → no_pair →
#   tested. H1: established (a tested primary with lo > 0) | not established — halt before
#   promotion (a tested primary, none with lo > 0) | inconclusive by degradation — not
#   established (every testable primary inconclusive by degradation) | not yet decidable (no
#   pair). A4: holds | fails — harden tasks … | inconclusive by degradation (…) — not decided |
#   not testable on suite_version N — no admissible build task | not yet decidable (no pair).
#   JSON h1/a4 carry state and suite_version; each comparison carries read and read_text.
#
# Presentation items (Sprint 262 R3, report 1.2.0; fixes in 1.2.1 and 1.2.2; none of them changes a decision, an
# H1/A4 state or an existing number):
#   sensitivity H1/A4  the sensitivity figure prints the H1 and A4 lines, read the same way as the main
#                   lines on a third Analysis with cap failures excluded and degraded rows included,
#                   prefixed "sensitivity (decides nothing): "; per suite version. JSON sensitivity.h1 /
#                   sensitivity.a4 (the shape of the top-level h1 / a4) and sensitivity.treatment; also
#                   by_suite_version[N].sensitivity.
#   ## Batch record one table row per manifest's batch, grouped by suite version, from STATUS.json beside
#                   MANIFEST.json (read-only; absent → "no STATUS.json"; a symlink is not read): state,
#                   trials planned / rowed, spend (rows_usd, ledger_usd, spent_usd, max_usd), extra_models,
#                   rerowed[] and rerun[] counts with from→to tallies, drift_cleared[] and outage_history[]
#                   counts, cuts[], paused_arms, and the grade.json grader_version tally of the rows' run
#                   directories. Attribution (report 1.2.1): each row is resolved to its own directory
#                   once — the highest <batch dir>/<arm>/<task>-t<n>-r<k> whose meta/pipeline.json run_id
#                   equals the row's, else the highest -r<k> holding a grade.json, else <task>-t<n>, else
#                   the highest -r<k> (1.2.2); n compares numerically, so rc-01-t01 is trial 1 (1.2.2) — and
#                   counted once ("n/a" when the directory or its grade is absent), so the tally sums
#                   to the batch's rows; run_dirs_missing counts the rows with no attributable directory.
#                   Tally order: dotted segments numeric before text, "n/a" last. Never fatal: an exception
#                   in one batch's STATUS.json or tally leaves that tally unsorted or partial with a note in
#                   the row (JSON batches[].note); an exception anywhere else in computing or rendering the
#                   batch record (1.2.2) prints "Not rendered (…)" with JSON batches [] and batches_note set
#                   (null otherwise); neither aborts the report. JSON batches[].
#   precision       per-arm detail of review-catch arms: precision = Σ defects_caught ÷ (Σ defects_caught +
#                   Σ false_positives) over the arm's valid review-catch rows with a numeric defects_caught
#                   (cap_failure counts 0 caught; a null false_positives counts 0), null when 0; cost per
#                   true defect = Σ cost_usd ÷ Σ defects_caught, null when 0 caught. JSON arms.<arm>.
#                   {precision, usd_per_true_defect, true_defects, flagged_regions, precision_rows}.
#   budget-matched  per suite version, per review-catch task: the union of a0_bare's valid trials' caught
#                   defects (ids d1 … dN from defects_missed, as defect_vector reads them; a task whose a0
#                   rows carry none → max over trials of the rate, "rate fallback") against a1_full's mean
#                   per-trial catch rate, with the summed a0 cost and the mean a1 cost; "not available" when
#                   the version has no valid a0_bare or a1_full review-catch rows. JSON budget_matched
#                   {suite_version, available, tasks[], a0_union_mean, a1_mean, diff_mean, note} (primary
#                   version; by_suite_version[N].budget_matched for each).
#
# Input guards (report 1.2.3, the Sprint 262 audit; none changes a decision, an H1/A4 state or a number
# on rows that ablation-row.sh --validate accepts):
#   numbers         every cost read goes through usd_of(row) (and wall-clock through num_of): a finite
#                   int/float that is not a bool, else 0 with one stderr note per row and key ("note: row
#                   <run_id> cost_usd is a str, not a number; read as 0"); the per-arm means skip a
#                   non-finite value. The JSON twin is serialised with allow_nan=False before any file is
#                   written: a NaN or an infinity that still reaches it exits 2 with "refusing to write a
#                   non-finite number to the JSON report at $.<key path>" and writes neither file.
#   exception text  a never-fatal guard of the batch record renders the exception class and a fixed
#                   phrase naming the stage and the batch ("Not rendered (ValueError while reading the
#                   batch record of pr-2)", "grader tally incomplete (ValueError while tallying the grader
#                   versions of pr-2)"); str(exception), which can carry a file's content or a host path,
#                   goes to stderr once and never into report.md or report.json.
#   paths           before a row's run directory is looked up, its arm must fullmatch ^[a-z][a-z0-9_]{0,63}$
#                   and its task_id ^[a-z0-9][a-z0-9-]{0,63}$; a row outside either counts in
#                   run_dirs_missing (n/a) with the note "<n> row(s) with an arm or task_id outside the
#                   grammar (no attributable directory)" and is never used in a path. Every file read
#                   below a batch directory (the arm directory, meta/pipeline.json, grade.json) is refused
#                   when a component below the batch directory is a symlink or its realpath leaves the
#                   realpath of that batch's manifest directory. The run-directory names themselves come
#                   from os.listdir and are matched with GRADE_DIR.fullmatch.
#
# Exit codes:
#   0  report written
#   1  --partial and no decidable comparison in the primary version (the report is still
#      written); H1 or A4 counts as decided when it reads established / not established /
#      holds / fails / inconclusive by degradation
#   2  usage error, unreadable input, unknown schema major, provenance conflict, a row without
#      suite_version among two versions that would enter a cell, --suite-version naming no row's
#      version
#
# Tested by evals/tests/ablation-report.bats (planted rows generated by
# evals/tests/fixtures/ablation-report/gen-fixtures.py).
# =============================================================================
import argparse
import json
import math
import os
import random
import re
import statistics
import subprocess
import sys

VERSION = "1.3.0"
REPORT_SCHEMA = 1
ROW_SCHEMA_MAJOR = 1
MANIFEST_SCHEMA_MAJOR = 1
CONTROL = "a1_full"
BARE = "a0_bare"
SENSITIVITY_ARM = "a4_no_gates"
BUILD_TYPES = ("feature-build", "bug-fix", "refactor")
REVIEW = "review-catch"
PASS = "hidden_test_pass_rate"
CATCH = "defect_catch_rate"
CATCH_PM3 = "defect_catch_rate_pm3"          # report 1.3: the 1.2.0 rule on the current anchors (beside)
CATCH_PM3_V1 = "defect_catch_rate_pm3_v1"    # report 1.3: the 1.2.0 rule on manifests/v1/ (beside)
CATCH_METRICS = (CATCH, CATCH_PM3, CATCH_PM3_V1)
MISSED_KEY = {CATCH: "defects_missed", CATCH_PM3: "defects_missed_pm3", CATCH_PM3_V1: "defects_missed_pm3_v1"}
MIN_VALID_CELLS = 4                          # report 1.3 (FR-6): a contrast needs this many valid cells
UNPLANNED_ABSENCE = ("budget", "preflight", "error")
ORACLE_LABEL = "oracle-exposed cells excluded"
DISSENT_LABEL = "dissent-absent gates excluded"
PIN_GRAMMAR = re.compile(r"[0-9a-f]{4,40}")
DEC0417_EXCLUDED = ("transport_error", "infrastructure_error")
SCORING = ("completed", "agent_error", "cap_failure")
POWER = 0.90
DISPLAY = {"investigate": "Investigate", "keep": "Keep", "inconclusive": "Inconclusive",
           "remove": "Remove", "simplify": "Simplify", "not_run_cut": "Not run (cut)",
           "inconclusive_by_power": "Inconclusive-by-power", "component_absent": "component-absent",
           "no_rows": "no rows"}
PARTIAL_LINE = "PARTIAL — rows so far, no decision is final"
SENS_LABEL = "sensitivity (cap failures excluded) — no decision uses this"
SENS_PREFIX = "sensitivity (decides nothing): "
SENS_H_TREATMENT = "cap failures excluded, degraded rows included"
BUDGET_LABEL = "informational, decides nothing"
GRADE_DIR = re.compile(r"(.+)-t(\d+)(?:-r(\d+))?")
ARM_GRAMMAR = re.compile(r"[a-z][a-z0-9_]{0,63}")       # ablation-row.sh / execute-agent.sh (fullmatch)
TASK_GRAMMAR = re.compile(r"[a-z0-9][a-z0-9-]{0,63}")    # a task id as a path component (fullmatch)


class Fail(Exception):
    pass


# --------------------------------------------------------------------------- small helpers
def r9(x):
    return None if x is None else round(x, 9)


def mean(xs):
    xs = [x for x in xs if x is not None]
    return sum(xs) / len(xs) if xs else None


def f3(x):
    return "n/a" if x is None else f"{x:+.3f}" if x != 0 else "0.000"


def u3(x):
    return "n/a" if x is None else f"{x:.3f}"


def pct(x):
    return "n/a" if x is None else f"{x:+.1f} %"


def j6(x):
    return None if x is None else round(x, 6)


def is_num(v):
    """A finite int/float that is not a bool."""
    return isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v)


MISSED_ID = re.compile(r"d([1-9][0-9]*)")


def missed_consistent(missed, n, caught):
    """The report 1.2.3 id rules (audit DISS-C-001, the row writer 1.3 rules against the task's N): every
    id is d1 … dN, no duplicate, and N − len(ids) == defects_caught when defects_caught is a number."""
    ks = []
    for x in missed:
        mm = MISSED_ID.fullmatch(x)
        if not mm or int(mm.group(1)) > n:
            return False
        ks.append(x)
    if len(set(ks)) != len(ks):
        return False
    return not is_num(caught) or n - len(ks) == caught


_NOTED = set()


def num_of(row, key):
    """A row's numeric field: a finite int/float that is not a bool, else 0 with one stderr note per row
    and key (report 1.2.3, audit DISS-C-003); an absent or null field is 0 without a note."""
    v = row.get(key)
    if is_num(v):
        return v
    if v is not None and (row.get("run_id"), key) not in _NOTED:
        _NOTED.add((row.get("run_id"), key))
        kind = "NaN or an infinity" if isinstance(v, float) else f"a {type(v).__name__}, not a number"
        sys.stderr.write(f"ablation-report.py: note: row {row.get('run_id')} {key} is {kind}; read as 0\n")
    return 0


def usd_of(row):
    """The row's cost_usd as a finite number (0 with a stderr note otherwise); every cost read uses it."""
    return num_of(row, "cost_usd")


def schema_major(v):
    if isinstance(v, bool):
        return None
    if isinstance(v, int):
        return v
    if isinstance(v, float) and v.is_integer():
        return int(v)
    if isinstance(v, str) and re.fullmatch(r"\d+(\.\d+)*", v):
        return int(v.split(".")[0])
    return None


def percentile(sorted_xs, q):
    """Linear interpolation between order statistics (numpy's default 'linear')."""
    n = len(sorted_xs)
    if n == 0:
        return None
    pos = q * (n - 1)
    lo = int(math.floor(pos))
    hi = min(lo + 1, n - 1)
    frac = pos - lo
    return sorted_xs[lo] + (sorted_xs[hi] - sorted_xs[lo]) * frac


def bootstrap(diffs, resamples, level, seed):
    if not diffs:
        return None, None
    rng = random.Random(seed)
    n = len(diffs)
    means = sorted(sum(rng.choices(diffs, k=n)) / n for _ in range(resamples))
    a = (1.0 - level) / 2.0
    return percentile(means, a), percentile(means, 1.0 - a)


def mde(diffs, level):
    if len(diffs) < 2:
        return None
    nd = statistics.NormalDist()
    z = nd.inv_cdf(1.0 - (1.0 - level) / 2.0) + nd.inv_cdf(POWER)
    return z * statistics.stdev(diffs) / math.sqrt(len(diffs))


def collapse(run_ids):
    """batch-arm-task-t1, -t2, -t3 → batch-arm-task-t1…t3 (non-contiguous: t1,t3)."""
    groups, other = {}, []
    for rid in run_ids:
        m = re.fullmatch(r"(.*-t)(\d+)", rid)
        if m:
            groups.setdefault(m.group(1), []).append(int(m.group(2)))
        else:
            other.append(rid)
    out = []
    for prefix in sorted(groups):
        ns = sorted(set(groups[prefix]))
        if len(ns) == 1:
            out.append(f"{prefix}{ns[0]}")
        elif len(ns) >= 3 and ns == list(range(ns[0], ns[-1] + 1)):
            out.append(f"{prefix}{ns[0]}…t{ns[-1]}")
        else:
            out.append(prefix + ",t".join(str(n) for n in ns))
    return out + sorted(other)


def md_cell(s):
    return str(s).replace("|", "\\|").replace("\n", " ")


# --------------------------------------------------------------------------- inputs
def load_suite(path):
    try:
        with open(path, encoding="utf-8") as fh:
            raw = fh.read()
    except OSError as e:
        raise Fail(f"cannot read suite {path}: {e.strerror}")
    try:
        suite = json.loads(raw)
    except ValueError:
        try:
            out = subprocess.run(["yq", "-o=json", ".", path], check=True, capture_output=True, text=True).stdout
            suite = json.loads(out)
        except (OSError, subprocess.CalledProcessError, ValueError):
            raise Fail(f"cannot parse suite {path} (YAML needs yq v4 on PATH)")
    if not isinstance(suite, dict) or not isinstance(suite.get("arms"), list) or not isinstance(suite.get("rules"), dict):
        raise Fail(f"suite {path} has no arms[] or rules block")
    lines, inside = [], False
    for line in raw.splitlines():
        if re.match(r"^rules:", line):
            inside = True
        elif inside and line.strip() and not line[0].isspace() and not line.startswith("#"):
            break
        if inside:
            lines.append(line)
    while lines and not lines[-1].strip():
        lines.pop()
    rules_text = "\n".join(lines) if lines else json.dumps({"rules": suite["rules"]}, indent=2, sort_keys=True)
    return suite, rules_text


def load_rows(paths):
    rows, dup = [], []
    seen = {}
    for path in paths:
        try:
            fh = open(path, encoding="utf-8")
        except OSError as e:
            raise Fail(f"cannot read --runs {path}: {e.strerror}")
        with fh:
            for n, line in enumerate(fh, 1):
                if not line.strip():
                    continue
                where = f"{path}:{n}"
                try:
                    row = json.loads(line)
                except ValueError:
                    raise Fail(f"{where}: line is not valid JSON")
                if not isinstance(row, dict):
                    raise Fail(f"{where}: row is not a JSON object")
                rid = row.get("run_id")
                if "schema_version" not in row:
                    raise Fail(f"{where}: row {rid} has no schema_version (1 required)")
                major = schema_major(row.get("schema_version"))
                if major != ROW_SCHEMA_MAJOR:
                    raise Fail(f"{where}: row {rid} has schema_version {row.get('schema_version')!r}; "
                               f"this reader knows major {ROW_SCHEMA_MAJOR} only")
                for k, ty in (("run_id", str), ("batch", str), ("arm", str), ("task_id", str),
                              ("task_type", str), ("status", str)):
                    if not isinstance(row.get(k), ty) or not row.get(k):
                        raise Fail(f"{where}: row {rid} has no {k}")
                if isinstance(row.get("trial"), bool) or not isinstance(row.get("trial"), int):
                    raise Fail(f"{where}: row {rid} has no integer trial")
                row = dict(row)
                row["_where"] = where
                if rid in seen:
                    dup.append({"run_id": rid, "kept": where, "dropped": seen[rid]["_where"]})
                    rows.remove(seen[rid])
                seen[rid] = row
                rows.append(row)
    return rows, dup


def load_manifests(dirs):
    mans = {}
    for d in dirs:
        if not os.path.isdir(d):
            raise Fail(f"--manifests {d} is not a directory")
        for root, subdirs, files in os.walk(d, followlinks=False):
            subdirs.sort()
            if "MANIFEST.json" not in files:
                continue
            p = os.path.join(root, "MANIFEST.json")
            if os.path.islink(p):
                raise Fail(f"{p} is a symlink")
            try:
                with open(p, encoding="utf-8") as fh:
                    m = json.load(fh)
            except (OSError, ValueError):
                raise Fail(f"cannot read manifest {p}")
            if not isinstance(m, dict):
                raise Fail(f"manifest {p} is not a JSON object")
            if "schema_version" in m and schema_major(m["schema_version"]) != MANIFEST_SCHEMA_MAJOR:
                raise Fail(f"manifest {p} has schema_version {m['schema_version']!r}; "
                           f"this reader knows major {MANIFEST_SCHEMA_MAJOR} only")
            batch = m.get("batch") or m.get("batch_name")
            if not isinstance(batch, str) or not batch:
                raise Fail(f"manifest {p} names no batch")
            if batch in mans:
                raise Fail(f"two manifests claim batch {batch}: {mans[batch]['_path']} and {p}")
            m = dict(m)
            m["_path"] = p
            mans[batch] = m
    if not mans:
        raise Fail("no MANIFEST.json under " + ", ".join(dirs))
    return mans


def load_cuts(path, not_run, arm_ids, labels):
    cuts = {}

    def resolve(a):
        a = str(a).strip()
        if a in arm_ids:
            return a
        if a.upper() in labels:
            return labels[a.upper()]
        raise Fail(f"cut names unknown arm {a}")

    if path:
        try:
            with open(path, encoding="utf-8") as fh:
                data = json.load(fh)
        except (OSError, ValueError):
            raise Fail(f"cannot read --cuts {path}")
        if not isinstance(data, list):
            raise Fail(f"--cuts {path} is not a JSON list")
        for c in data:
            if not isinstance(c, dict) or "arm" not in c:
                raise Fail(f"--cuts {path}: an entry has no arm")
            state = c.get("state", "not_run_cut")
            if state not in ("not_run_cut", "inconclusive_by_power"):
                raise Fail(f"--cuts {path}: state {state} is not not_run_cut|inconclusive_by_power")
            cuts[resolve(c["arm"])] = {"state": state, "reason": str(c.get("reason", "")),
                                       "figure": str(c.get("figure", "")), "source": "--cuts"}
    for a in [x for x in (not_run or "").split(",") if x.strip()]:
        cuts.setdefault(resolve(a), {"state": "not_run_cut", "reason": "--not-run", "figure": "--not-run",
                                     "source": "--not-run"})
    return cuts


# --------------------------------------------------------------------------- the analysis
def usable(p):
    """A comparison with a valid pair that is neither degenerate nor insufficient (report 1.3)."""
    return p["n"] > 0 and not p.get("degenerate") and not p.get("insufficient")


def oracle_reason(row):
    """report 1.3: why a row leaves the oracle-exposed sensitivity (non-empty oracle_exposed_defects or
    oracle_exposed_unknown); None for a clean row and for an arm whose evidence says oracle_open (reported,
    never excluded)"""
    ex = [x for x in (row.get("oracle_exposed_defects") or []) if isinstance(x, str)]
    unk = [x for x in (row.get("oracle_exposed_unknown") or []) if isinstance(x, str)]
    if not (ex or unk) or row.get("oracle_open") is True:
        return None
    return "oracle-exposed: " + (", ".join(ex) or "none") + (f"; exposed_unknown {', '.join(unk)}" if unk else "")


def dissent_reason(row):
    """report 1.3: why a row leaves the dissent-absent sensitivity — a gate whose dissent was absent for an
    unplanned reason (budget, preflight, error); a planned absence (disabled) never excludes"""
    r = row.get("dissent_absent_reason")
    bad = sorted((g, v) for g, v in (r.items() if isinstance(r, dict) else []) if v in UNPLANNED_ABSENCE)
    return ("dissent absent: " + ", ".join(f"{g}={v}" for g, v in bad)) if bad else None


def applies_to(arm_def, ttype):
    types = arm_def.get("task_types") or []
    return "all" in types or ttype in types or ("build" in types and ttype in BUILD_TYPES)


class Analysis:
    def __init__(self, suite, rows, mans, args, cap_excluded, include_degraded=False, extra=None):
        self.suite, self.rules, self.args = suite, suite["rules"], args
        self.cap_excluded = cap_excluded
        # extra (report 1.3): a further exclusion rule row → reason | None (the labelled sensitivities)
        self.extra = extra
        self.extra_excluded = {}    # arm -> rows the extra rule excluded
        self.open_reported = {}     # arm -> oracle-exposed rows of an oracle_open arm (reported, kept)
        self.min_cells = int(self.rules.get("min_valid_cells", MIN_VALID_CELLS))
        # include_degraded (Sprint 262 R3): the sensitivity H1/A4 lines read degraded rows as scored
        self.exclude_degraded = bool(args.exclude_degraded) and not include_degraded
        self.arms = {a["id"]: a for a in suite["arms"] if isinstance(a, dict) and a.get("id")}
        ex = self.rules.get("exclusion") or {}
        self.ex_statuses = set(ex.get("statuses") or []) | set(DEC0417_EXCLUDED)
        self.guard = float(ex.get("inconclusive_above_share", 0.25))
        self.listed = []        # rows that never enter a decision, with the reason
        self.excluded = []      # excluded rows (status/reason), superseded included
        self.cells = {}         # (arm, task) -> {trial: {"valid": row|None, "rows": [...]}}
        self.task_type = {}
        self.task_defects = {}
        self.arm_rows = {}
        for row in rows:
            seeded = row.get("defects_seeded")
            if isinstance(seeded, int) and not isinstance(seeded, bool) and seeded > 0:
                self.task_defects[row["task_id"]] = max(self.task_defects.get(row["task_id"], 0), seeded)
        for row in rows:
            self._classify(row, mans)
        for (arm, task), trials in self.cells.items():
            for t, cell in trials.items():
                valid = [x for x in cell["rows"] if x["_valid"]]
                cell["valid"] = valid[-1] if valid else None
                for x in cell["rows"]:
                    if x["_valid"] and x is not cell["valid"]:
                        self.excluded.append(self._exrow(x, f"duplicate cell; superseded by {cell['valid']['run_id']}",
                                                         counted=False))
                    elif not x["_valid"]:
                        sup = f"; superseded by {cell['valid']['run_id']}" if cell["valid"] else ""
                        self.excluded.append(self._exrow(x, x["_reason"] + sup, counted=not cell["valid"]))

    @staticmethod
    def _exrow(x, reason, counted):
        return {"run_id": x["run_id"], "arm": x["arm"], "task_id": x["task_id"], "trial": x["trial"],
                "status": x["status"], "reason": reason, "cell_excluded": counted}

    def applies(self, arm, ttype):
        return applies_to(self.arms[arm], ttype)

    def primaries(self, arm):
        types = self.arms[arm].get("task_types") or []
        pba = self.rules.get("primaries_by_arm") or {}
        if "all" in types or REVIEW in types:
            return list(pba.get("all_types") or [PASS, CATCH])
        return list(pba.get("build_only") or [PASS])

    def _classify(self, row, mans):
        arm, task, ttype = row["arm"], row["task_id"], row["task_type"]
        provenance_check(row, mans)
        why = list_reason(row, mans, self.arms)
        if why is not None:
            return self.listed.append((row, why))
        self.task_type[task] = ttype
        self.arm_rows.setdefault(arm, []).append(row)
        st = row["status"]
        reason = None
        if st in self.ex_statuses:
            reason = st
        elif self.exclude_degraded and row.get("degraded") is True:
            reason = "degraded: " + str(row.get("degraded_reason") or "no reason recorded")
        elif st not in SCORING:
            reason = "status " + st
        elif st == "cap_failure" and self.cap_excluded:
            reason = "cap_failure (sensitivity figure)"
        elif st != "cap_failure":
            if ttype == REVIEW and not isinstance(row.get(CATCH), (int, float)):
                reason = "ungraded (defect_catch_rate null)"
            elif ttype != REVIEW and not isinstance(row.get(PASS), (int, float)):
                reason = "ungraded (hidden_test_pass_rate null)"
        if reason is None and self.extra is not None:
            reason = self.extra(row)
            if reason is not None:
                self.extra_excluded[arm] = self.extra_excluded.get(arm, 0) + 1
        if self.extra is oracle_reason and row.get("oracle_open") is True and \
                (row.get("oracle_exposed_defects") or row.get("oracle_exposed_unknown")):
            self.open_reported[arm] = self.open_reported.get(arm, 0) + 1
        row = dict(row)     # per-Analysis validity (the sensitivities classify the same rows)
        row["_valid"] = reason is None
        row["_reason"] = reason
        cell = self.cells.setdefault((arm, task), {}).setdefault(row["trial"], {"valid": None, "rows": []})
        cell["rows"].append(row)

    # -- scores
    def pass_score(self, row):
        return 0.0 if row["status"] == "cap_failure" else float(row[PASS])

    def catch_task_score(self, row, metric=CATCH):
        return 0.0 if row["status"] == "cap_failure" else float(row[metric])

    def defect_vector(self, row, metric=CATCH):
        n = self.task_defects.get(row["task_id"], 0)
        if n <= 0:
            return None, "none"
        if row["status"] == "cap_failure":
            return [0.0] * n, "cap"
        missed = row.get(MISSED_KEY[metric])
        if missed is None and metric == CATCH and isinstance(row.get("recall"), dict):
            missed = row["recall"].get("missed")
        # the beside metrics carry their own rate; defects_caught counts the decision rule's catches
        caught = row.get("defects_caught") if metric == CATCH else None
        if isinstance(missed, list) and all(isinstance(x, str) for x in missed) \
                and missed_consistent(missed, n, caught):
            ms = set(missed)
            return [0.0 if f"d{k}" in ms else 1.0 for k in range(1, n + 1)], "ids"
        return [float(row[metric])] * n, "rate"

    # -- shares
    def excluded_share(self, arm, types=None):
        """Excluded cells over the arm's cells (on tasks of `types` when given: the H1/A4 guard)."""
        cells = [c for (a, t), trials in self.cells.items() if a == arm
                 and (types is None or self.task_type.get(t) in types) for c in trials.values()]
        if not cells:
            return None, 0, 0
        ex = sum(1 for c in cells if c["valid"] is None)
        return ex / len(cells), ex, len(cells)

    # -- one paired comparison of `arm` against `ctrl` on one primary
    def compare(self, arm, ctrl, metric, seed):
        types = (REVIEW,) if metric in CATCH_METRICS else BUILD_TYPES
        tasks = sorted({t for (a, t) in self.cells if a in (arm, ctrl) and self.task_type.get(t) in types})
        res = {"metric": metric, "arm": arm, "control": ctrl, "unit": "tasks", "pairs": [], "unpaired": [],
               "dropped": [], "diffs": [], "task_diffs": [], "defect_identity": set(), "valid_cells": 0,
               "unavailable": False}
        for task in tasks:
            ca, cc = self.cells.get((arm, task), {}), self.cells.get((ctrl, task), {})
            drop = sorted(t for t in set(ca) | set(cc)
                          if (t in ca and ca[t]["valid"] is None) or (t in cc and cc[t]["valid"] is None))
            for t in drop:
                for side, cs in ((arm, ca), (ctrl, cc)):
                    if t in cs and cs[t]["valid"] is not None:
                        res["dropped"].append({"task_id": task, "trial": t, "arm": side,
                                               "run_id": cs[t]["valid"]["run_id"]})
            va = [ca[t]["valid"] for t in sorted(ca) if t not in drop]
            vc = [cc[t]["valid"] for t in sorted(cc) if t not in drop]
            if not va or not vc:
                why = []
                for side, cs, vs in ((arm, ca, va), (ctrl, cc, vc)):
                    if vs:
                        continue
                    if not cs:
                        why.append(f"no row in {side}")
                    elif all(cs[t]["valid"] is None for t in cs):
                        why.append(f"every cell of {side} excluded")
                    else:
                        why.append(f"the cells of {side} dropped pairwise")
                res["unpaired"].append({"task_id": task, "reason": "; ".join(why)})
                continue
            if metric in (CATCH_PM3, CATCH_PM3_V1) and not all(
                    r["status"] == "cap_failure" or is_num(r.get(metric)) for r in va + vc):
                res["unavailable"] = True      # a row without the beside field (a 1.2.x grade): no figure
                continue
            # report 1.3: a valid cell is a trial valid in both arms of the pair (per task, the smaller count)
            res["valid_cells"] += min(len(va), len(vc))
            pair = {"task_id": task, "arm_runs": [r["run_id"] for r in va], "control_runs": [r["run_id"] for r in vc],
                    "arm_cost": mean([float(usd_of(r)) for r in va]),
                    "control_cost": mean([float(usd_of(r)) for r in vc]),
                    "arm_wall": mean([float(num_of(r, "wall_clock_ms")) for r in va]),
                    "control_wall": mean([float(num_of(r, "wall_clock_ms")) for r in vc])}
            if metric == PASS:
                ma, mc = mean([self.pass_score(r) for r in va]), mean([self.pass_score(r) for r in vc])
                pair.update(arm_value=ma, control_value=mc, diff=ma - mc)
                res["diffs"].append(ma - mc)
                res["task_diffs"].append(ma - mc)
            else:
                ma = mean([self.catch_task_score(r, metric) for r in va])
                mc = mean([self.catch_task_score(r, metric) for r in vc])
                pair.update(arm_value=ma, control_value=mc, diff=ma - mc)
                res["task_diffs"].append(ma - mc)
                vecs_a = [self.defect_vector(r, metric) for r in va]
                vecs_c = [self.defect_vector(r, metric) for r in vc]
                for _, how in vecs_a + vecs_c:
                    res["defect_identity"].add(how)
                if all(v is not None for v, _ in vecs_a + vecs_c):
                    n = len(vecs_a[0][0])
                    dd = [mean([v[k] for v, _ in vecs_a]) - mean([v[k] for v, _ in vecs_c]) for k in range(n)]
                    pair["defects"] = n
                    pair["defect_diffs"] = dd
                    res["diffs"].extend(dd)
                else:
                    pair["defects"] = 0
            res["pairs"].append(pair)
        if metric in CATCH_METRICS:
            res["unit"] = "defects"
        if res["unavailable"]:
            res["pairs"], res["diffs"], res["task_diffs"], res["valid_cells"] = [], [], [], 0
        res["defect_identity"] = sorted(res["defect_identity"] - {"cap"})
        n = len(res["diffs"])
        res["n"] = n
        res["n_tasks"] = len(res["pairs"])
        res["d"] = mean(res["diffs"]) if n else None
        res["lo"], res["hi"] = bootstrap(res["diffs"], self.args.resamples, self.args.level, seed)
        res["mde"] = mde(res["diffs"], self.args.level)
        res["half_width"] = None if res["lo"] is None else (res["hi"] - res["lo"]) / 2.0
        # A catch-rate comparison whose pairs come from one task and whose defect vectors are the
        # row's rate (no per-defect ids) has a zero-variance interval by construction: degenerate,
        # read as no valid pair by H1 and by the component decision (Sprint 262).
        res["degenerate"] = bool(metric in CATCH_METRICS and n > 0 and res["n_tasks"] == 1
                                 and "ids" not in res["defect_identity"])
        # report 1.3 (FR-6): fewer than min_valid_cells valid cells reads "insufficient" (no decision)
        res["insufficient"] = bool(n > 0 and res["valid_cells"] < self.min_cells)
        if res["degenerate"]:
            res["degenerate_reason"] = (
                f"valid pairs on one task ({res['pairs'][0]['task_id']}) with no per-defect ids: every "
                f"defect takes the row's {CATCH}, so the bootstrap interval has zero variance by construction")
        if metric in CATCH_METRICS:
            td = res["task_diffs"]
            lo, hi = bootstrap(td, self.args.resamples, self.args.level, seed)
            res["task_level"] = {"unit": "tasks", "n": len(td), "d": mean(td) if td else None, "lo": lo, "hi": hi}
        if metric == CATCH:
            # report 1.3: the 1.2.0-rule figures printed beside the decision statistic, deciding nothing
            res["beside"] = {}
            for m in (CATCH_PM3, CATCH_PM3_V1):
                b = self.compare(arm, ctrl, m, seed)
                res["beside"][m] = None if b["unavailable"] or b["n"] == 0 else b
        return res

    def deltas(self, comps):
        """c and w over the per-task means of the cells the primaries paired."""
        per_task = {}
        for comp in comps:
            for p in comp["pairs"]:
                per_task.setdefault(p["task_id"], p)
        if not per_task:
            return None, None, 0
        ps = [per_task[t] for t in sorted(per_task)]

        def delta(a, c):
            ma, mc = mean([p[a] for p in ps]), mean([p[c] for p in ps])
            return None if not mc else (ma - mc) / mc * 100.0

        return delta("arm_cost", "control_cost"), delta("arm_wall", "control_wall"), len(ps)

    def decide(self, arm, comps, c, w, share):
        T = float(self.rules.get("threshold_points", 0.03))
        C = float(self.rules.get("cost_lower_pct", 15))
        P = [p for p in comps if usable(p)]
        nopair = len(P) < len(comps)
        name = lambda p: p["metric"]  # noqa: E731

        def why_not(p):
            if p.get("degenerate"):
                return ": degenerate"
            if p.get("insufficient"):
                return f": insufficient, {p['valid_cells']} valid cells < {self.min_cells}"
            return ""
        if share is not None and r9(share) > self.guard:
            # DEC-0393: the degradation guard reads first, whatever the interval (lead's ruling, Sprint 260)
            clause = f"excluded share {share:.3f} > {self.guard:g}"
            return "inconclusive", f"inconclusive (degradation guard, evaluated first): {clause}", [clause]
        hits = [name(p) for p in P if r9(p["lo"]) > 0]
        if hits:
            return "investigate", f"investigate: any applicable primary has lo > 0 ({', '.join(hits)})", []
        hits = [name(p) for p in P if r9(p["d"]) < -T and r9(p["hi"]) < 0]
        if hits:
            return "keep", f"keep: any applicable primary has d < -{T:g} and hi < 0 ({', '.join(hits)})", []
        clauses = []
        hits = [name(p) for p in P if r9(p["d"]) < -T]
        if hits:
            clauses.append(f"d < -{T:g} ({', '.join(hits)})")
        if nopair:
            clauses.append("no valid pair (" + ", ".join(
                name(p) + why_not(p) for p in comps if not usable(p)) + ")")
        if clauses:
            return "inconclusive", "inconclusive: " + "; ".join(clauses), clauses
        cost_ok = (c is not None and r9(c) <= -C) or (w is not None and r9(w) <= -C)
        if all(r9(p["d"]) >= -T for p in comps) and cost_ok:
            which = []
            if c is not None and r9(c) <= -C:
                which.append(f"c = {c:+.1f}")
            if w is not None and r9(w) <= -C:
                which.append(f"w = {w:+.1f}")
            return "remove", (f"remove: every applicable primary has d >= -{T:g} and "
                              f"(c <= -{C:g} or w <= -{C:g}) ({', '.join(which)})"), []
        return "simplify", f"simplify: every applicable primary within -{T:g}, cost similar", []

    def arm_report(self, arm, cuts, seed):
        prims = self.primaries(arm)
        comps = [self.compare(arm, CONTROL, m, seed) for m in prims]
        c, w, n_cost = self.deltas(comps)
        share, ex, seen = self.excluded_share(arm)
        out = {"arm": arm, "arm_label": self.arms[arm].get("label", arm), "primaries": prims,
               "comparisons": comps, "c": c, "w": w, "cost_tasks": n_cost,
               "excluded_share": share, "excluded_cells": ex, "cells_seen": seen}
        if not seen:
            state, rule, clauses = "no_rows", "no rows for this arm", []
        else:
            state, rule, clauses = self.decide(arm, comps, c, w, share)
        out["predicate_state"] = state
        out["predicate_rule"] = rule
        label = DISPLAY.get(state, state)
        if state == "inconclusive" and any(cl.startswith("excluded share") for cl in clauses):
            label = "Inconclusive-by-degradation"
        out["predicate_label"] = label
        figure = None
        mde_cut = self.rules.get("mde_cut")
        over = [p for p in comps if p["mde"] is not None and mde_cut is not None and r9(p["mde"]) > float(mde_cut)]
        if arm in cuts:
            cut = cuts[arm]
            state, label = cut["state"], DISPLAY[cut["state"]]
            rule = f"{cut['source']}: {cut['reason']}".rstrip(": ")
            figure = cut["figure"]
        elif state in ("remove", "simplify") and over:
            figure = "; ".join(f"MDE {p['mde']:.3f} > {float(mde_cut):g} on {p['metric']} (n = {p['n']} {p['unit']})"
                               for p in over)
            rule = f"inconclusive_by_power: {figure} (predicate read {DISPLAY[out['predicate_state']]})"
            state, label = "inconclusive_by_power", DISPLAY["inconclusive_by_power"]
        out.update(state=state, label=label, rule=rule, figure=figure,
                   mde_flag=[p["metric"] for p in over])
        out["decidable"] = bool(seen) and all(usable(p) for p in comps)
        return out

    def arm_metrics(self, arm):
        """Unpaired per-arm figures (AC-8.2): task-mean of trial means and the secondaries."""
        rows = self.arm_rows.get(arm, [])
        valid = [c["valid"] for (a, _), trials in sorted(self.cells.items()) if a == arm
                 for _, c in sorted(trials.items()) if c["valid"] is not None]
        by_task = {}
        for r in valid:
            by_task.setdefault(r["task_id"], []).append(r)
        status = {}
        for r in rows:
            status[r["status"]] = status.get(r["status"], 0) + 1

        def task_mean(rs_by_task, f):
            return mean([mean([f(r) for r in rs]) for rs in rs_by_task.values()])

        build = {t: rs for t, rs in by_task.items() if self.task_type[t] in BUILD_TYPES}
        rc = {t: rs for t, rs in by_task.items() if self.task_type[t] == REVIEW}

        def bools(key):
            vs = [r.get(key) for r in valid if isinstance(r.get(key), bool)]
            return None if not vs else sum(1 for v in vs if v) / len(vs)

        def nums(key, rs=None):
            vs = [r.get(key) for r in (valid if rs is None else rs) if is_num(r.get(key))]
            return mean(vs)

        # precision and cost per true defect (Sprint 262 R3, informational): the arm's valid review-catch
        # rows with a numeric defects_caught (a cap_failure counts 0 caught); false_positives null → 0
        prec = {"precision": None, "usd_per_true_defect": None, "true_defects": None, "flagged_regions": None,
                "precision_rows": 0, "finding_volume_per_run": None, "precision_planted_per_flag": None, "flag_rows": 0}
        if rc:
            caught = fp = usd = 0.0
            nrows = 0
            for rs in rc.values():
                for r in rs:
                    c = r.get("defects_caught")
                    if r["status"] == "cap_failure":
                        c = 0
                    if not is_num(c):
                        continue
                    f = r.get("false_positives")
                    f = f if is_num(f) else 0
                    caught, fp, nrows = caught + c, fp + f, nrows + 1
                    usd += usd_of(r)
            prec = {"precision": caught / (caught + fp) if caught + fp > 0 else None,
                    "usd_per_true_defect": usd / caught if caught > 0 else None,
                    "true_defects": int(caught) if float(caught).is_integer() else caught,
                    "flagged_regions": int(caught + fp) if float(caught + fp).is_integer() else caught + fp,
                    "precision_rows": nrows}
        # report 1.3: finding volume (flags = distinct cited findings per run) and precision as planted
        # defects caught over findings flagged, over the valid review-catch rows with a numeric flags
        caught_f = flags = 0.0
        frows = 0
        for rs in rc.values():
            for r in rs:
                f, c = r.get("flags"), (0 if r["status"] == "cap_failure" else r.get("defects_caught"))
                if is_num(f) and is_num(c):
                    caught_f, flags, frows = caught_f + c, flags + f, frows + 1
        prec.update(finding_volume_per_run=(flags / frows) if frows else None,
                    precision_planted_per_flag=(caught_f / flags) if flags > 0 else None, flag_rows=frows)
        return {
            **prec,
            "rows": len(rows), "by_status": dict(sorted(status.items())),
            "degraded_rows": sum(1 for r in rows if r.get("degraded") is True),
            "valid_cells": len(valid),
            PASS: task_mean(build, self.pass_score) if build else None,
            CATCH: task_mean(rc, self.catch_task_score) if rc else None,
            "verdict_accuracy": bools("verdict_accuracy"),
            "verdict_accuracy_review": bools("verdict_accuracy_review"),
            "verdict_accuracy_audit": bools("verdict_accuracy_audit"),
            "false_positives_per_task": {t: nums("false_positives", rs) for t, rs in sorted(rc.items())},
            "regressions_per_run": nums("regressions"),
            "diff_lines_per_run": nums("diff_lines"), "files_changed_per_run": nums("files_changed"),
            "cost_per_task": task_mean(by_task, lambda r: float(usd_of(r))) if by_task else None,
            "cost_per_run": mean([usd_of(r) for r in valid]),
            "wall_clock_ms_per_run": nums("wall_clock_ms"),
            "tokens_in_per_run": nums("tokens_in"), "tokens_out_per_run": nums("tokens_out"),
        }


# --------------------------------------------------------------------------- rendering
def interval(p):
    if p is None or p["n"] == 0:
        return "no pair"
    return f"{f3(p['d'])} [{f3(p['lo'])}, {f3(p['hi'])}]" + (" (degenerate)" if p.get("degenerate") else "") + \
        (f" (insufficient: {p['valid_cells']} valid cells)" if p.get("insufficient") and not p.get("degenerate") else "")


def beside_text(p):
    """report 1.3: the _pm3 and _pm3_v1 figures of a defect_catch_rate comparison (decide nothing)"""
    if p is None or "beside" not in p:
        return ""
    parts = []
    for m in (CATCH_PM3, CATCH_PM3_V1):
        b = p["beside"].get(m)
        parts.append(f"{m} " + ("n/a (rows without the field)" if b is None else f"{interval(b)} (n = {b['n']} {b['unit']})"))
    return "; ".join(parts)


def comp_json(p):
    out = {k: p[k] for k in ("metric", "control", "unit", "n", "n_tasks", "unpaired", "dropped", "defect_identity")}
    out.update({k: j6(p[k]) for k in ("d", "lo", "hi", "mde", "half_width")})
    out["pairs"] = [{"task_id": x["task_id"], "arm_value": j6(x["arm_value"]), "control_value": j6(x["control_value"]),
                     "diff": j6(x["diff"]), "defects": x.get("defects"),
                     "arm_runs": x["arm_runs"], "control_runs": x["control_runs"]} for x in p["pairs"]]
    out["degenerate"] = bool(p.get("degenerate"))
    if p.get("degenerate"):
        out["degenerate_reason"] = p["degenerate_reason"]
    out["valid_cells"] = p.get("valid_cells", 0)
    out["insufficient"] = bool(p.get("insufficient"))
    if "beside" in p:
        out["beside"] = {m: (None if b is None else {"n": b["n"], "unit": b["unit"], "d": j6(b["d"]), "lo": j6(b["lo"]),
                                                     "hi": j6(b["hi"]), "valid_cells": b["valid_cells"],
                                                     "insufficient": bool(b.get("insufficient"))})
                         for m, b in p["beside"].items()}
    if "task_level" in p:
        out["task_level"] = {k: (j6(v) if isinstance(v, float) else v) for k, v in p["task_level"].items()}
    return out


NUMERIC = re.compile(r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?")


def version_key(v):
    """The partition key of a row's suite_version (report 1.2.1): 2, 2.0 and "2" are one version ("2");
    a non-integer number keys to its shortest round-trip form (2.1 and "2.10" → "2.1"); any other
    string keys to itself, stripped. Absent (None) = None, a boolean, an empty or blank string, or a
    value that is neither a number nor a string."""
    if v is None or isinstance(v, bool):
        return None
    if isinstance(v, str):
        s = v.strip()
        if not s:
            return None
        if not NUMERIC.fullmatch(s):
            return s
        v = int(s) if re.fullmatch(r"[+-]?\d+", s) else float(s)
        if isinstance(v, float) and not math.isfinite(v):
            return s
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        if not math.isfinite(v):
            return repr(v)
        return str(int(v)) if v.is_integer() else repr(v)
    return None


def version_value(k):
    """A version key as a JSON value: an integer key → int, another numeric key → float, "n/a" (or None) →
    null, any other key → the string. Every JSON emitter of a version key goes through it (report 1.2.2)."""
    if k is None or k == "n/a":
        return None
    if not isinstance(k, str):
        return k
    if re.fullmatch(r"[+-]?\d+", k):
        return int(k)
    o = version_order(k)
    return o[1] if o[0] == 0 else k


def version_order(k):
    """Sort key over version keys: numeric keys numerically, every other key after them, lexically."""
    if NUMERIC.fullmatch(k):
        f = float(k)
        if math.isfinite(f):
            return (0, f, k)
    return (1, 0.0, k)


def provenance_check(row, mans):
    """DEC-0407: a row whose batch manifest arm_map names another arm for its run_id stops the report
    (exit 2). Run on every row by partition() before any listing decision and again by
    Analysis._classify (report 1.2.2)."""
    m = mans.get(row.get("batch"))
    if m is None:
        return
    amap = m.get("arm_map") or {}
    if isinstance(amap, dict) and row["run_id"] in amap and amap[row["run_id"]] != row["arm"]:
        raise Fail(f"{row['_where']}: row {row['run_id']} arm {row['arm']} disagrees with "
                   f"{m['_path']} arm_map ({amap[row['run_id']]})")


def list_reason(row, mans, arms):
    """Why a row is listed and never decided, or None when it enters a cell (the first checks of
    Analysis._classify, after provenance_check); partition() reuses it (report 1.2.1)."""
    m = mans.get(row.get("batch"))
    if m is None:
        return "no manifest for batch " + str(row.get("batch"))
    if m.get("smoke") is True:
        return "smoke batch " + str(row.get("batch"))
    arm, ttype = row.get("arm"), row.get("task_type")
    if arm not in arms or arms[arm].get("absent"):
        return f"arm {arm} is not run by the suite"
    if ttype not in BUILD_TYPES and ttype != REVIEW:
        return f"unknown task_type {ttype}"
    if not applies_to(arms[arm], ttype):
        return f"not applicable: {arm} does not run {ttype} tasks"
    return None


PART_VERSION = {}   # report 1.3: partition key -> its suite_version key (a key differs from it when split)


def part_rule(r):
    """the grader rule a row's catch figures follow: grader_rule, "pm3" for a review-catch row without one
    (a 1.2.x grade), None for a build row (no catch figure)"""
    if r.get("task_type") != REVIEW:
        return None
    v = r.get("grader_rule")
    return v if isinstance(v, str) and v else "pm3"


def part_split(v, rows):
    """report 1.3: one suite version's rows split by source_commit and grader_rule when either takes more
    than one value — rows of different pins or rules are never pooled; the key names the pin (12
    characters) and the rule ("n/a" for build rows when review rows hold two rules)"""
    commits = sorted({str(r.get("source_commit") or "") for r in rows})
    rules = sorted({x for x in (part_rule(r) for r in rows) if x is not None})
    if len(commits) <= 1 and len(rules) <= 1:
        PART_VERSION[v] = v
        return {v: list(rows)}
    out = {}
    for r in rows:
        k = v
        if len(commits) > 1:
            k += f" · pin {str(r.get('source_commit') or '')[:12] or 'n/a'}"
        if len(rules) > 1:
            k += f" · rule {part_rule(r) or 'n/a'}"
        PART_VERSION[k] = v
        out.setdefault(k, []).append(r)
    return out


def part_order(groups):
    """sort key over partition keys: the version, then the larger group, then the key"""
    return lambda k: (version_order(PART_VERSION.get(k, k)), len(groups[k]), k)


def partition(rows, wanted, mans=None, arms=None):
    """Rows by suite_version, never pooled; returns ({key: rows}, primary key, version-less rows listed
    under the primary). Among two or more versions a version-less row that would enter a cell stops the
    report; one that would be listed anyway (no manifest, smoke batch, arm not run, unknown or
    inapplicable task type) is returned with its reason, never pooled into a version. Every row passes
    provenance_check first (report 1.2.2), so no listing decision bypasses the arm_map check."""
    for r in rows:
        provenance_check(r, mans or {})
    keys = sorted({k for k in (version_key(r.get("suite_version")) for r in rows) if k is not None}, key=version_order)
    missing = [r for r in rows if version_key(r.get("suite_version")) is None]
    unversioned = []
    if len(keys) > 1 and missing:
        for r in missing:
            why = list_reason(r, mans or {}, arms or {}) if arms is not None else None
            if why is None:
                raise Fail(f"{r['_where']}: row {r['run_id']} has no suite_version while the rows hold suite_version "
                           f"{', '.join(keys)}; rows of different suite versions are never pooled, so every row must "
                           f"name its suite_version")
            unversioned.append((r, "no suite_version; " + why))
    if len(keys) <= 1:
        vgroups = {(keys[0] if keys else "n/a"): list(rows)}
    else:
        vgroups = {k: [r for r in rows if version_key(r.get("suite_version")) == k] for k in keys}
    groups = {}
    for v, rs in vgroups.items():
        groups.update(part_split(v, rs))
    order = part_order(groups)
    if wanted is not None:
        w = version_key(wanted)
        cands = [k for k in groups if PART_VERSION.get(k, k) == w]
        if not cands:
            raise Fail(f"--suite-version {wanted}: no row has that suite_version (present: {', '.join(vgroups)})")
        return groups, max(cands, key=order), unversioned
    return groups, max(groups, key=order), unversioned


def assess(an, arm, ctrl, p):
    """How H1/A4 reads one comparison: not_testable | inconclusive_by_degradation | degenerate | no_pair | tested."""
    types = (REVIEW,) if p["metric"] == CATCH else BUILD_TYPES
    if not p["pairs"] and not p["unpaired"]:
        return "not_testable", None
    over = []
    for a in (arm, ctrl):
        s, _, _ = an.excluded_share(a, types)
        if s is not None and r9(s) > an.guard:
            over.append(f"{a} excluded share {s:.3f} > {an.guard:g}")
    if over:
        return "inconclusive_by_degradation", "; ".join(over)
    if p.get("degenerate"):
        return "degenerate", p["degenerate_reason"]
    if p.get("insufficient"):
        return "insufficient", f"{p['valid_cells']} valid cells < {an.min_cells}"
    if p["n"] == 0:
        return "no_pair", None
    return "tested", None


def read_text(p, state, why, v):
    base = f"{p['metric']} {interval(p)} (n = {p['n']} {p['unit']})"
    if state == "not_testable":
        return f"{p['metric']}: not testable on suite_version {v} — no admissible task"
    if state == "inconclusive_by_degradation":
        return f"{p['metric']} inconclusive by degradation ({why}); remaining pairs {interval(p)} (n = {p['n']} {p['unit']})"
    if state == "degenerate":
        return base + " — read as no valid pair"
    if state == "insufficient":
        return f"{p['metric']} insufficient ({why}); {interval(p)} (n = {p['n']} {p['unit']})"
    return base


H1_DECIDED = ("established", "not_established", "inconclusive_by_degradation")
A4_DECIDED = ("holds", "fails", "inconclusive_by_degradation")


def h1a4(main, v, seed):
    """The H1 and A4 reads of one Analysis (the main one, or the sensitivity one with cap failures
    excluded and degraded rows included, Sprint 262 R3)."""
    h1_comps = [main.compare(CONTROL, BARE, m, seed) for m in main.primaries(CONTROL)]
    h1_reads = [assess(main, CONTROL, BARE, p) for p in h1_comps]
    states = [s for s, _ in h1_reads]
    if any(s == "tested" and r9(p["lo"]) > 0 for p, (s, _) in zip(h1_comps, h1_reads)):
        h1_state, h1_line = "established", "H1: established"
    elif "tested" in states:
        h1_state, h1_line = "not_established", "H1: not established — halt before promotion"
    else:
        live = [s for s in states if s != "not_testable"]
        if live and all(s == "inconclusive_by_degradation" for s in live):
            h1_state, h1_line = "inconclusive_by_degradation", "H1: inconclusive by degradation — not established"
        elif "insufficient" in states:
            h1_state, h1_line = "insufficient", f"H1: insufficient — fewer than {main.min_cells} valid cells"
        else:
            h1_state, h1_line = "not_yet_decidable", "H1: not yet decidable (no pair)"

    a4, a4_read = None, (None, None)
    if SENSITIVITY_ARM in main.arms:
        a4 = main.compare(SENSITIVITY_ARM, CONTROL, PASS, seed)
        a4_read = assess(main, SENSITIVITY_ARM, CONTROL, a4)
        s, why = a4_read
        if s == "not_testable":
            a4_state, a4_line = "not_testable", f"A4 sensitivity: not testable on suite_version {v} — no admissible build task"
        elif s == "inconclusive_by_degradation":
            a4_state, a4_line = s, f"A4 sensitivity: inconclusive by degradation ({why}) — not decided"
        elif s == "insufficient":
            a4_state, a4_line = "insufficient", f"A4 sensitivity: insufficient — fewer than {main.min_cells} valid cells"
        elif s in ("no_pair", "degenerate"):
            a4_state, a4_line = "not_yet_decidable", "A4 sensitivity: not yet decidable (no pair)"
        elif r9(a4["hi"]) < 0:
            a4_state, a4_line = "holds", "A4 sensitivity: holds"
        else:
            a4_state, a4_line = "fails", "A4 sensitivity: fails — harden tasks before acting on other arms"
    else:
        a4_state, a4_line = "no_arm", "A4 sensitivity: fails — harden tasks before acting on other arms"
    return {"version": v, "h1_comps": h1_comps, "h1_reads": h1_reads, "h1_state": h1_state, "h1_line": h1_line,
            "h1_ok": h1_state == "established", "a4": a4, "a4_read": a4_read, "a4_state": a4_state,
            "a4_line": a4_line, "a4_ok": a4_state == "holds"}


def budget_matched(an, v):
    """The budget-matched baseline (Sprint 262 R3, informational, decides nothing): per review-catch task,
    the union of a0_bare's valid trials' caught defects against a1_full's mean per-trial catch rate."""
    out = {"suite_version": v, "available": False, "tasks": [], "a0_union_mean": None, "a1_mean": None,
           "diff_mean": None, "note": None, "label": BUDGET_LABEL}

    def valid(arm, task):
        return [c["valid"] for _, c in sorted(an.cells.get((arm, task), {}).items()) if c["valid"] is not None]

    tasks = sorted({t for (a, t) in an.cells if a in (BARE, CONTROL) and an.task_type.get(t) == REVIEW})
    have = {a: any(valid(a, t) for t in tasks) for a in (BARE, CONTROL)}
    if not (have[BARE] and have[CONTROL]):
        missing = " and ".join(a for a in (BARE, CONTROL) if not have[a])
        out["note"] = f"not available on suite_version {v} — no valid {missing} review-catch rows"
        return out
    out["available"] = True
    for t in tasks:
        a0, a1 = valid(BARE, t), valid(CONTROL, t)
        e = {"task_id": t, "a0_trials": len(a0), "a1_trials": len(a1), "a0_union": None, "a0_cost_sum": None,
             "a1_mean": None, "a1_cost_mean": None, "diff": None, "method": None, "reason": None}
        if a0:
            vecs = [an.defect_vector(r) for r in a0]
            if all(vv is not None and how in ("ids", "cap") for vv, how in vecs):
                e["a0_union"] = mean([max(vv[k] for vv, _ in vecs) for k in range(len(vecs[0][0]))])
                e["method"] = "defect union"
            else:
                e["a0_union"] = max(an.catch_task_score(r) for r in a0)
                e["method"] = "rate fallback"
            e["a0_cost_sum"] = sum(float(usd_of(r)) for r in a0)
        if a1:
            e["a1_mean"] = mean([an.catch_task_score(r) for r in a1])
            e["a1_cost_mean"] = mean([float(usd_of(r)) for r in a1])
        if a0 and a1:
            e["diff"] = e["a1_mean"] - e["a0_union"]
        else:
            e["reason"] = "; ".join(f"no valid {a} trial" for a, rs in ((BARE, a0), (CONTROL, a1)) if not rs)
        out["tasks"].append(e)
    both = [e for e in out["tasks"] if e["diff"] is not None]
    if not both:
        out["available"] = False
        out["note"] = f"not available on suite_version {v} — no review-catch task has valid trials in both arms"
        return out
    out["a0_union_mean"] = mean([e["a0_union"] for e in both])
    out["a1_mean"] = mean([e["a1_mean"] for e in both])
    out["diff_mean"] = out["a1_mean"] - out["a0_union_mean"]
    k = sorted({e["a0_trials"] for e in both})
    kk = str(k[0]) if len(k) == 1 else "the"
    x = mean([e["a0_cost_sum"] for e in both])
    y = mean([e["a1_cost_mean"] for e in both])
    out["a0_cost_sum_mean"], out["a1_cost_mean"] = x, y
    out["note"] = (f"{kk} a0_bare trials cost USD {x:.2f} vs one a1_full trial USD {y:.2f} "
                   f"(task means over {len(both)} task{'' if len(both) == 1 else 's'})")
    return out


def stage_note(x, stage):
    """The sanitized text of a never-fatal exception (report 1.2.3, audit DISS-C-002): the exception class
    and a fixed phrase naming the stage, never str(x) (which can carry a value from a file or a host path);
    the full text goes to stderr once."""
    sys.stderr.write(f"ablation-report.py: {type(x).__name__} while {stage}: {x}\n")
    return f"{type(x).__name__} while {stage}"


def batch_record(mans, rows, where=None):
    """Each batch's STATUS.json (beside its MANIFEST.json, read-only) and the grader versions of its rows'
    run directories (Sprint 262 R3); a missing file or directory is reported, never fatal. `where` (a
    dict) holds the current stage for the caller's sanitized "Not rendered" text."""
    where = {} if where is None else where
    out = []
    for b, m in sorted(mans.items()):
        where["stage"] = f"reading the batch record of {b}"
        d = os.path.dirname(m["_path"])
        brows = [r for r in rows if r["batch"] == b]
        vks = sorted({k for k in (version_key(r.get("suite_version")) for r in brows) if k is not None},
                     key=version_order)
        sv = version_key(m.get("suite_version")) or (", ".join(vks) if vks else "n/a")
        e = {"batch": b, "suite_version": sv, "smoke": m.get("smoke") is True, "status_file": None,
             "status_note": None, "state": None, "trials_planned": None, "trials_rowed": len(brows),
             "spend": None, "extra_models": {}, "rerowed": 0, "rerowed_tally": {}, "rerun": 0,
             "rerun_tally": {}, "drift_cleared": 0, "outage_history": 0, "cuts": [], "paused_arms": [],
             "grader_versions": {}, "run_dirs_missing": 0, "note": None}
        try:
            batch_status(e, d)
        except Exception as x:  # never fatal: a presentation-only section
            e["note"] = f"STATUS.json record incomplete ({stage_note(x, f'reading the STATUS.json of {b}')})"
        # grader versions (report 1.2.1): each row's own run directory, counted once
        try:
            grader_tally(e, d, brows)
        except Exception as x:  # never fatal: a presentation-only section
            note = f"grader tally incomplete ({stage_note(x, f'tallying the grader versions of {b}')})"
            e["note"] = note if e["note"] is None else e["note"] + "; " + note
        out.append(e)
    where["stage"] = "rendering the batch record"
    return out


def batch_status(e, d):
    """Fill one batch record from the STATUS.json in d (read-only; a symlink is not read)."""
    sp = os.path.join(d, "STATUS.json")
    st = None
    if os.path.islink(sp):
        e["status_note"] = "STATUS.json is a symlink (not read)"
    elif not os.path.isfile(sp):
        e["status_note"] = "no STATUS.json"
    else:
        try:
            with open(sp, encoding="utf-8") as fh:
                st = json.load(fh)
        except (OSError, ValueError):
            st = None
        if not isinstance(st, dict):
            st, e["status_note"] = None, "STATUS.json unreadable"
    if st is not None:
        e["status_file"] = sp

        def lst(k):
            x = st.get(k)
            return x if isinstance(x, list) else []

        def tally(k):
            t = {}
            for x in lst(k):
                if isinstance(x, dict):
                    key = f"{x.get('from', '?')}→{x.get('to', '?')}"
                    t[key] = t.get(key, 0) + 1
            return dict(sorted(t.items()))

        sd = st.get("spend") if isinstance(st.get("spend"), dict) else {}
        e.update(state=st.get("state"), trials_planned=st.get("trials_planned"),
                 spend={k: sd.get(k) for k in ("rows_usd", "ledger_usd", "spent_usd", "max_usd")},
                 rerowed=len(lst("rerowed")), rerowed_tally=tally("rerowed"),
                 rerun=len(lst("rerun")), rerun_tally=tally("rerun"),
                 drift_cleared=len(lst("drift_cleared")), outage_history=len(lst("outage_history")),
                 cuts=[{k: c.get(k) for k in ("reason", "at_trial", "spent", "max") if k in c}
                       for c in lst("cuts") if isinstance(c, dict)])
        em = st.get("extra_models")
        if isinstance(em, dict):
            e["extra_models"] = {str(k): {"runs": (x or {}).get("runs"), "output_tokens": (x or {}).get("output_tokens")}
                                 for k, x in sorted(em.items()) if isinstance(x, dict) or x is None}
        pa = st.get("paused_arms")
        e["paused_arms"] = sorted(str(x) for x in (pa if isinstance(pa, (dict, list)) else []))


def contained(root, base, *parts):
    """base joined with parts, or None unless no component below base is a symlink and the realpath stays
    inside realpath(root), the batch's manifest directory (report 1.2.3, audit DISS-C-004)."""
    p = base
    for part in parts:
        p = os.path.join(p, part)
        if os.path.islink(p):
            return None
    rr = os.path.realpath(root)
    rp = os.path.realpath(p)
    return p if rp == rr or rp.startswith(rr + os.sep) else None


def run_dir_of(ad, names, r, root=None):
    """The row's own run directory under the arm directory ad (names: its subdirectories): the highest
    <task>-t<n>-r<k> whose meta/pipeline.json run_id equals the row's, else the highest -r<k> holding a
    grade.json, else <task>-t<n>, else the highest -r<k> (its grade absent: n/a); None when the row has
    none of them. The trial n compares numerically, so rc-01-t01 is trial 1 (report 1.2.2). root: the batch's
    manifest directory; every file read below ad stays inside it (report 1.2.3)."""
    root = ad if root is None else root
    task, trial = r["task_id"], r["trial"]
    reruns, bases = [], []
    for x in names:
        mm = GRADE_DIR.fullmatch(x)
        if not mm or mm.group(1) != task or int(mm.group(2)) != trial:
            continue
        if mm.group(3) is not None:
            reruns.append((int(mm.group(3)), x))
        else:
            bases.append(x)
    reruns.sort(reverse=True)
    for _, x in reruns:
        pj = read_json_file(contained(root, ad, x, "meta", "pipeline.json"))
        if isinstance(pj, dict) and pj.get("run_id") == r["run_id"]:
            return x
    for _, x in reruns:
        gp = contained(root, ad, x, "grade.json")
        if gp is not None and os.path.isfile(gp):
            return x
    if bases:  # the canonical <task>-t<n> first, else the lexically first zero-padded form
        canon = f"{task}-t{trial}"
        return canon if canon in bases else sorted(bases)[0]
    return reruns[0][1] if reruns else None


def read_json_file(p):
    """A JSON file's content, None when p is None, absent, a symlink, unreadable or not JSON."""
    if p is None or not os.path.isfile(p) or os.path.islink(p):
        return None
    try:
        with open(p, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return None


def grader_key(kv):
    """Type-stable sort key of a grader-version tally entry: "n/a" last; dotted segments compare
    numerically when digits, lexically otherwise, digits first (1.2.0 < 1.2.0-rc1 < 1.2.1)."""
    return (kv[0] == "n/a", [(0, int(p), "") if p.isdigit() else (1, 0, p) for p in kv[0].split(".")])


def grader_tally(e, d, brows):
    """The grade.json grader_version of each row's own run directory, counted once per row ("n/a" when
    the directory or its grade is absent); run_dirs_missing counts the rows with no attributable
    directory (run_dir_of returns None)."""
    listing, gv, off_grammar = {}, {}, 0
    try:
        for r in brows:
            # report 1.2.3 (audit DISS-C-004): the arm and task_id grammars before any path is built; a row
            # outside them has no attributable directory and is never used in a path
            if not (isinstance(r.get("arm"), str) and ARM_GRAMMAR.fullmatch(r["arm"])
                    and isinstance(r.get("task_id"), str) and TASK_GRAMMAR.fullmatch(r["task_id"])):
                off_grammar += 1
                e["run_dirs_missing"] += 1
                gv["n/a"] = gv.get("n/a", 0) + 1
                continue
            ad = contained(d, d, r["arm"])
            if ad is None:  # the arm directory is a symlink or resolves outside the batch directory
                e["run_dirs_missing"] += 1
                gv["n/a"] = gv.get("n/a", 0) + 1
                continue
            if ad not in listing:
                try:
                    listing[ad] = set(x for x in os.listdir(ad) if not os.path.islink(os.path.join(ad, x))
                                      and os.path.isdir(os.path.join(ad, x))) \
                        if os.path.isdir(ad) and not os.path.islink(ad) else set()
                except OSError:
                    listing[ad] = set()
            x = run_dir_of(ad, listing[ad], r, d)
            ver = "n/a"
            if x is None:
                e["run_dirs_missing"] += 1
            else:
                g = read_json_file(contained(d, ad, x, "grade.json"))
                if isinstance(g, dict) and g.get("grader_version") not in (None, ""):
                    ver = str(g["grader_version"])
            gv[ver] = gv.get(ver, 0) + 1
    finally:
        if off_grammar:
            note = (f"{off_grammar} row{'' if off_grammar == 1 else 's'} with an arm or task_id outside the "
                    f"grammar (no attributable directory)")
            e["note"] = note if e["note"] is None else e["note"] + "; " + note
        try:
            e["grader_versions"] = dict(sorted(gv.items(), key=grader_key))
        except Exception:
            e["grader_versions"] = dict(gv)
            raise


def render_budget(L, B, h):
    L(f"{h} Budget-matched baseline (suite_version {B['suite_version']}; {BUDGET_LABEL})")
    L("")
    if not B["available"]:
        L(f"- {B['note']}")
        L("")
        return
    L("Per review-catch task: the union of the defects any valid a0_bare trial caught (a defect counts once "
      "caught by any trial; \"rate fallback\" is the best trial's rate where the rows carry no per-defect ids), "
      "against a1_full's mean per-trial catch rate. Nothing here feeds a decision.")
    L("")
    L("| task | a0_bare trials | a0_bare union catch rate | a0_bare summed cost USD | a1_full trials | "
      "a1_full mean per-trial catch rate | a1_full mean cost USD | a1 − a0 union | method |")
    L("|---|---|---|---|---|---|---|---|---|")

    def usd(x):
        return "n/a" if x is None else f"{x:.2f}"

    for e in B["tasks"]:
        L(f"| {e['task_id']} | {e['a0_trials']} | {u3(e['a0_union'])} | {usd(e['a0_cost_sum'])} | {e['a1_trials']} | "
          f"{u3(e['a1_mean'])} | {usd(e['a1_cost_mean'])} | {f3(e['diff'])} | "
          f"{md_cell(e['method'] or 'n/a')}{'; ' + md_cell(e['reason']) if e['reason'] else ''} |")
    L("")
    L(f"- task mean (tasks with both arms): a0_bare union {u3(B['a0_union_mean'])}, a1_full per-trial "
      f"{u3(B['a1_mean'])}, a1 − a0 union {f3(B['diff_mean'])}")
    L(f"- matched cost: {B['note']}")
    L("")


def budget_json(B):
    return {k: (version_value(x) if k == "suite_version" else j6(x) if isinstance(x, float) else
                [{kk: (j6(y) if isinstance(y, float) else y) for kk, y in t.items()} for t in x] if k == "tasks" else x)
            for k, x in B.items()}


def render_batches(L, recs):
    L("## Batch record")
    L("")
    L("From each batch's STATUS.json beside its MANIFEST.json (read-only) and the `grade.json` grader_version "
      "of its rows' run directories (`<batch>/<arm>/<task>-t<n>[-r<k>]`); a tally is `from→to ×n`.")
    L("")

    def usd(x):
        return "n/a" if not isinstance(x, (int, float)) or isinstance(x, bool) else f"{x:.2f}"

    def tl(t):
        return ", ".join(f"{k} ×{n}" for k, n in t.items())

    for v in sorted({e["suite_version"] for e in recs}, key=lambda k: version_order(k) if k else (2, 0, "")):
        L(f"### suite_version {v}")
        L("")
        L("| batch | state | trials planned / rowed | spend USD rows / ledger / spent / max | extra models | rerowed | "
          "rerun | drift cleared | outages | cuts | paused arms | grader versions |")
        L("|---|---|---|---|---|---|---|---|---|---|---|---|")
        for e in [x for x in recs if x["suite_version"] == v]:
            name = f"`{e['batch']}`" + (" (smoke)" if e["smoke"] else "")
            gv = ", ".join(f"{k} ×{n}" for k, n in e["grader_versions"].items()) or "n/a"
            if e["run_dirs_missing"]:
                gv += f"; no run dir ×{e['run_dirs_missing']}"
            if e.get("note"):
                gv += f"; {e['note']}"
            if e["status_note"]:
                L(f"| {name} | {md_cell(e['status_note'])} | — / {e['trials_rowed']} | — | — | — | — | — | — | — | — | "
                  f"{md_cell(gv)} |")
                continue
            sp = e["spend"] or {}
            em = ", ".join(f"{k}: runs {x.get('runs')}, output tokens {x.get('output_tokens')}"
                           for k, x in e["extra_models"].items()) or "none"
            cuts = "; ".join(", ".join(f"{k} {c[k]}" for k in c) for c in e["cuts"]) or "none"
            rr = f"{e['rerowed']}" + (f" ({tl(e['rerowed_tally'])})" if e["rerowed"] else "")
            rn = f"{e['rerun']}" + (f" ({tl(e['rerun_tally'])})" if e["rerun"] else "")
            L(f"| {name} | {md_cell(e['state'] or 'n/a')} | {e['trials_planned'] if e['trials_planned'] is not None else 'n/a'}"
              f" / {e['trials_rowed']} | {usd(sp.get('rows_usd'))} / {usd(sp.get('ledger_usd'))} / "
              f"{usd(sp.get('spent_usd'))} / {usd(sp.get('max_usd'))} | {md_cell(em)} | {md_cell(rr)} | {md_cell(rn)} | "
              f"{e['drift_cleared']} | {e['outage_history']} | {md_cell(cuts)} | "
              f"{md_cell(', '.join(e['paused_arms']) or 'none')} | {md_cell(gv)} |")
        L("")


def render_extra_sens(L, V, rules, h):
    """report 1.3: the oracle-exposed and dissent-absent sensitivities, with the cells each rule excluded
    per arm printed beside every read"""
    for key in ("oracle_exposed_excluded", "dissent_absent_excluded"):
        X = V["extra_sens"][key]
        L(f"{h} Sensitivity: {X['label']} — decides nothing")
        L("")
        counts = ", ".join(f"`{a}` {n}" for a, n in X["counts"].items()) or "none"
        L(f"- rows this rule excluded, per arm: {counts}")
        if key == "oracle_exposed_excluded":
            rep_ = ", ".join(f"`{a}` {n}" for a, n in X["reported"].items()) or "none"
            L(f"- oracle-exposed rows of an oracle_open arm (reported, not excluded): {rep_}")
        else:
            L("- a planned absence (dissent_absent_reason disabled) is never excluded; budget, preflight and error are")
        L("")
        L("| component | arm | n pairs | pass-rate Δ [90 % CI] | catch-rate Δ [90 % CI] (defects) | excluded by the rule | "
          "predicate outcome (not used) |")
        L("|---|---|---|---|---|---|---|")
        for d in X["rows"]:
            cp = {p["metric"]: p for p in d["comparisons"]}
            npairs = ", ".join(f"{p['n']} {p['unit']}" for p in d["comparisons"])
            catch = interval(cp.get(CATCH)) if CATCH in cp else "n/a (build-only)"
            L(f"| {d['arm_label']} | `{d['arm']}` | {npairs} | {interval(cp.get(PASS))} | {catch} | "
              f"{X['counts'].get(d['arm'], 0)} (control {X['counts'].get(CONTROL, 0)}) | {d['predicate_label']} |")
        L("")
        render_h1a4(L, X["h"], rules, prefix=f"sensitivity ({X['label']}; decides nothing): ",
                    suffix=f" (excluded: a1_full {X['counts'].get(CONTROL, 0)}, a0_bare {X['counts'].get(BARE, 0)})")


def render_sens(L, V, rules, h):
    L("| component | arm | n pairs | pass-rate Δ [90 % CI] | catch-rate Δ [90 % CI] (defects) | cost Δ % | "
      "wall-clock Δ % | excluded share | predicate outcome (not used) |")
    L("|---|---|---|---|---|---|---|---|---|")
    for d in V["sens_rows"]:
        cp = {p["metric"]: p for p in d["comparisons"]}
        npairs = ", ".join(f"{p['n']} {p['unit']}" for p in d["comparisons"])
        catch = interval(cp.get(CATCH)) if CATCH in cp else "n/a (build-only)"
        share = "n/a" if d["excluded_share"] is None else f"{d['excluded_share']:.3f}"
        L(f"| {d['arm_label']} | `{d['arm']}` | {npairs} | {interval(cp.get(PASS))} | {catch} | {pct(d['c'])} | "
          f"{pct(d['w'])} | {share} | {d['predicate_label']} |")
    L("")
    L(f"{h} H1 and A4 lines, sensitivity ({SENS_H_TREATMENT}; decides nothing)")
    L("")
    render_h1a4(L, V["sens_h"], rules, prefix=SENS_PREFIX, suffix=f" ({SENS_H_TREATMENT})")


def analyse(suite, vrows, mans, args, cuts, components, v):
    """Every figure of one suite_version (the rows of no other version enter)."""
    seed = args.seed
    main_extra = oracle_reason if getattr(args, "exclude_oracle_exposed", "false") == "true" else None
    main = Analysis(suite, vrows, mans, args, cap_excluded=False, extra=main_extra)
    sens = Analysis(suite, vrows, mans, args, cap_excluded=True, extra=main_extra)
    decisions = [main.arm_report(a, cuts, seed) for a in components]
    sens_rows = [sens.arm_report(a, {}, seed) for a in components]

    H = h1a4(main, v, seed)
    h1_state, a4_state = H["h1_state"], H["a4_state"]
    sens_h = h1a4(Analysis(suite, vrows, mans, args, cap_excluded=True, include_degraded=True), v, seed)
    decidable = any(d["decidable"] for d in decisions) or h1_state in H1_DECIDED or a4_state in A4_DECIDED
    caps = [c["valid"] for (_, _), trials in sorted(main.cells.items()) for _, c in sorted(trials.items())
            if c["valid"] is not None and c["valid"]["status"] == "cap_failure"]
    batches = sorted({r["batch"] for r in vrows})
    shas = sorted({str(mans[b].get("suite_manifest_sha256")) for b in batches
                   if b in mans and mans[b].get("suite_manifest_sha256") not in (None, "")}
                  | {str(r.get("suite_manifest_sha256")) for r in vrows if r.get("suite_manifest_sha256") not in (None, "")})
    # report 1.3: the two labelled sensitivities (decide nothing); planned dissent absence never excludes
    extra = {}
    for key, label, fn in (("oracle_exposed_excluded", ORACLE_LABEL, oracle_reason),
                           ("dissent_absent_excluded", DISSENT_LABEL, dissent_reason)):
        an = Analysis(suite, vrows, mans, args, cap_excluded=False, extra=fn)
        extra[key] = {"label": label, "an": an, "rows": [an.arm_report(a, {}, seed) for a in components],
                      "h": h1a4(an, v, seed), "counts": dict(sorted(an.extra_excluded.items())),
                      "reported": dict(sorted(an.open_reported.items()))}
    return dict(H, rows=vrows, main=main, sens=sens, decisions=decisions, sens_rows=sens_rows,
                decidable=decidable, caps=caps, batches=batches, shas=shas, sens_h=sens_h,
                budget=budget_matched(main, v), extra_sens=extra)


def render_decisions(L, V, absent, rules):
    main = V["main"]
    L("| component | arm | n pairs | pass-rate Δ [90 % CI] | catch-rate Δ [90 % CI] (defects) | cost Δ % | "
      "wall-clock Δ % | excluded share | decision | rule matched | rows |")
    L("|---|---|---|---|---|---|---|---|---|---|---|")
    for d in V["decisions"]:
        cp = {p["metric"]: p for p in d["comparisons"]}
        npairs = ", ".join(f"{p['n']} {p['unit']}" for p in d["comparisons"])
        catch = interval(cp.get(CATCH)) if CATCH in cp else "n/a (build-only)"
        share = "n/a" if d["excluded_share"] is None else \
            f"{d['excluded_share']:.3f} ({d['excluded_cells']}/{d['cells_seen']})"
        dec = d["label"] + (f" — {d['figure']}" if d["figure"] else "")
        nrows = len(main.arm_rows.get(d["arm"], []))
        L(f"| {d['arm_label']} | `{d['arm']}` | {npairs} | {interval(cp.get(PASS))} | {catch} | {pct(d['c'])} | "
          f"{pct(d['w'])} | {share} | **{md_cell(dec)}** | {md_cell(d['rule'])} | {nrows} (§ Rows per cell) |")
    for a in absent:
        L(f"| {a.get('label', a['id'])} | `{a['id']}` | — | — | — | — | — | — | **component-absent** | "
          f"{md_cell(a.get('evidence', 'absent: true'))} | 0 |")
    L("")
    besides = [(d, p) for d in V["decisions"] for p in d["comparisons"] if p["metric"] == CATCH and p["n"] > 0]
    if besides:
        L(f"Beside the decision statistic ({CATCH}; decide nothing):")
        L("")
        for d, p in besides:
            L(f"- {d['arm_label']} `{d['arm']}`: {beside_text(p)}")
        L("")
    render_h1a4(L, V, rules)


def render_h1a4(L, H, rules, prefix="", suffix=""):
    """The H1 and A4 lines of one h1a4() read; the sensitivity lines carry SENS_PREFIX."""
    h1p = ", ".join(read_text(p, s, why, H["version"]) for p, (s, why) in zip(H["h1_comps"], H["h1_reads"]))
    L(f"**{prefix}{H['h1_line']}** — a1_full − a0_bare: {h1p}{suffix}. Rule (rules.h1): \"{rules.get('h1', '')}\"")
    L("")
    for p in H["h1_comps"]:
        if p["metric"] == CATCH and p["n"] > 0:
            L(f"{prefix}Beside the decision statistic (decides nothing): {beside_text(p)}")
            L("")
    a4 = H["a4"]
    if a4 is None:
        a4p = "no arm a4_no_gates"
    elif H["a4_state"] in ("not_testable", "inconclusive_by_degradation"):
        a4p = read_text(a4, H["a4_read"][0], H["a4_read"][1], H["version"])
    else:
        a4p = f"{PASS} {interval(a4)} (n = {a4['n']} {a4['unit']})"
    L(f"**{prefix}{H['a4_line']}** — a4_no_gates − a1_full: {a4p}{suffix}. Rule (rules.a4_sensitivity): "
      f"\"{rules.get('a4_sensitivity', '')}\"")
    L("")


def render_per_arm(L, V, detail_arms, h):
    main = V["main"]
    metrics = {a: main.arm_metrics(a) for a in detail_arms if a in main.arms}
    by_arm = {d["arm"]: d for d in V["decisions"]}
    for a in detail_arms:
        if a not in main.arms:
            continue
        m = metrics[a]
        L(f"{h} {main.arms[a].get('label', a)} `{a}`")
        L("")
        L(f"- runs: {m['rows']} ({', '.join(f'{k} {v}' for k, v in m['by_status'].items()) or 'none'}); "
          f"degraded rows {m['degraded_rows']}; valid cells {m['valid_cells']}")
        share, ex, seen = main.excluded_share(a)
        L(f"- excluded cells: {ex} of {seen}" + ("" if share is None else f" (share {share:.3f})"))
        exl = [e for e in main.excluded if e["arm"] == a]
        for e in exl:
            L(f"  - `{e['run_id']}` {e['task_id']} t{e['trial']}: {e['reason']}")
        L(f"- applicable primaries: {', '.join(main.primaries(a))}")
        L(f"- {PASS} (task-mean of trial means, cap failures 0): {u3(m[PASS])}; "
          f"{CATCH}: {u3(m[CATCH])}")
        if a in by_arm:
            d = by_arm[a]
            for p in d["comparisons"]:
                L(f"- {p['metric']} vs a1_full: d [lo, hi] = {interval(p)}; n = {p['n']} {p['unit']} over "
                  f"{p['n_tasks']} tasks; MDE {u3(p['mde'])}; bootstrap half-width {u3(p['half_width'])}")
                if p.get("degenerate"):
                    L(f"  - degenerate (read as no valid pair): {p['degenerate_reason']}")
                if "task_level" in p:
                    tl = p["task_level"]
                    L(f"  - also_report (tasks, decides nothing): d [lo, hi] = "
                      f"{interval(dict(tl, n=tl['n']))}; n = {tl['n']} tasks")
                if p["defect_identity"]:
                    L(f"  - defect identity: {', '.join(p['defect_identity'])}")
                for u in p["unpaired"]:
                    L(f"  - left the pair: {u['task_id']} ({u['reason']})")
                for x in p["dropped"]:
                    L(f"  - pairwise drop: `{x['run_id']}` ({x['arm']}, {x['task_id']} t{x['trial']})")
            L(f"- cost Δ {pct(d['c'])}, wall-clock Δ {pct(d['w'])} over {d['cost_tasks']} paired tasks")
            L(f"- decision: **{d['label']}**" + (f" — {d['figure']}" if d["figure"] else "") + f"; rule: {d['rule']}")
            if d["state"] != d["predicate_state"]:
                L(f"- predicate outcome before the cut/power state: {d['predicate_label']}; "
                  f"{d['predicate_rule']}")
        L(f"- secondaries: verdict accuracy {u3(m['verdict_accuracy'])} (review {u3(m['verdict_accuracy_review'])}, "
          f"audit {u3(m['verdict_accuracy_audit'])}); regressions per run {u3(m['regressions_per_run'])}; "
          f"churn diff_lines {u3(m['diff_lines_per_run'])}, files_changed {u3(m['files_changed_per_run'])} per run")
        if m["false_positives_per_task"]:
            L("- false positives per review-catch task: " + ", ".join(
                f"{t} {u3(v)}" for t, v in m["false_positives_per_task"].items()))
            usd = m["usd_per_true_defect"]
            L(f"- precision ({BUDGET_LABEL}): {u3(m['precision'])} = true defects {m['true_defects']} / flagged "
              f"regions {m['flagged_regions']} (defects caught + false positives over {m['precision_rows']} valid "
              f"review-catch rows); cost per true defect caught: {'n/a' if usd is None else f'USD {usd:.2f}'}")
            L(f"- finding volume ({BUDGET_LABEL}): {u3(m['finding_volume_per_run'])} flagged findings per run; "
              f"precision as planted ÷ flagged: {u3(m['precision_planted_per_flag'])} (over {m['flag_rows']} valid "
              f"review-catch rows with flags)")
        wall, tin, tout = m["wall_clock_ms_per_run"], m["tokens_in_per_run"], m["tokens_out_per_run"]
        wall_s = "n/a" if wall is None else f"{wall / 60000.0:.1f} min"
        tin_s = "n/a" if tin is None else f"{tin:.0f}"
        tout_s = "n/a" if tout is None else f"{tout:.0f}"
        L(f"- cost per task USD {u3(m['cost_per_task'])}, per run USD {u3(m['cost_per_run'])}; wall-clock per run "
          f"{wall_s}; tokens in/out per run {tin_s} / {tout_s}")
        L("")
    return metrics


def render_exclusions(L, V, dups, h, sub):
    main = V["main"]
    L(f"{h} Exclusions")
    L("")
    if main.excluded:
        L("| run_id | arm | task | trial | status | reason |")
        L("|---|---|---|---|---|---|")
        for e in sorted(main.excluded, key=lambda e: (e["arm"], e["task_id"], e["trial"], e["run_id"])):
            L(f"| `{e['run_id']}` | `{e['arm']}` | {e['task_id']} | {e['trial']} | {e['status']} | {md_cell(e['reason'])} |")
    else:
        L("No row was excluded.")
    L("")
    L(f"{sub} Cap failures (scored 0 on every applicable primary; the sensitivity figure excludes them)")
    L("")
    for r in V["caps"]:
        L(f"- `{r['run_id']}` (`{r['arm']}`, {r['task_id']} t{r['trial']}, cap_phase {r.get('cap_phase') or 'n/a'}, "
          f"USD {float(usd_of(r)):.2f})")
    if not V["caps"]:
        L("- none")
    L("")
    L(f"{sub} Rows listed, never decided")
    L("")
    if main.listed or dups:
        for r, why in main.listed:
            L(f"- `{r['run_id']}` (`{r['arm']}`, {r['task_id']}, {r['status']}): {why}")
        for dd in dups:
            L(f"- `{dd['run_id']}` at {dd['dropped']}: duplicate run_id, the row at {dd['kept']} is used")
    else:
        L("None.")
    L("")


def h1_json(V, rules):
    return {"line": V["h1_line"], "established": V["h1_ok"], "state": V["h1_state"], "rule": rules.get("h1"),
            "suite_version": version_value(V["version"]),
            "comparisons": [dict(comp_json(p), read=s, read_text=read_text(p, s, why, V["version"]))
                            for p, (s, why) in zip(V["h1_comps"], V["h1_reads"])]}


def a4_json(V, rules):
    a4 = V["a4"]
    comp = None
    if a4 is not None:
        s, why = V["a4_read"]
        comp = dict(comp_json(a4), read=s, read_text=read_text(a4, s, why, V["version"]))
    return {"line": V["a4_line"], "holds": V["a4_ok"], "state": V["a4_state"], "rule": rules.get("a4_sensitivity"),
            "suite_version": version_value(V["version"]), "comparison": comp}


def decisions_json(ds):
    return [{"arm": d["arm"], "arm_label": d["arm_label"], "label": d["label"], "state": d["state"], "rule": d["rule"],
             "figure": d["figure"], "predicate_state": d["predicate_state"],
             "predicate_rule": d["predicate_rule"], "primaries": d["primaries"],
             "c": j6(d["c"]), "w": j6(d["w"]), "cost_tasks": d["cost_tasks"],
             "excluded_share": j6(d["excluded_share"]), "excluded_cells": d["excluded_cells"],
             "cells_seen": d["cells_seen"], "mde_flag": d["mde_flag"], "decidable": d["decidable"],
             "comparisons": [comp_json(p) for p in d["comparisons"]]} for d in ds]


def arms_json(metrics):
    return {a: {kk: (j6(v) if isinstance(v, float) else
                     ({t: j6(x) for t, x in v.items()} if kk == "false_positives_per_task" else v))
                for kk, v in metrics[a].items()} for a in metrics}


def exclusions_json(V):
    return sorted(V["main"].excluded, key=lambda e: (e["arm"], e["task_id"], e["trial"], e["run_id"]))


def listed_json(V):
    return [{"run_id": r["run_id"], "arm": r["arm"], "task_id": r["task_id"], "status": r["status"],
             "reason": why} for r, why in V["main"].listed]


def build(args):
    suite, rules_text = load_suite(args.suite)
    rules = suite["rules"]
    bs = rules.get("bootstrap") or {}
    pre_res, pre_lvl = bs.get("resamples", 10000), bs.get("level", 0.90)
    if args.resamples is None:
        args.resamples = int(pre_res)
    if args.level is None:
        args.level = float(pre_lvl)
    if args.resamples < 1 or not (0.0 < args.level < 1.0):
        raise Fail("--resamples must be >= 1 and --level in (0, 1)")
    rows, dups = load_rows(args.runs)
    pin_dropped = 0
    if args.pin is not None:
        pin = args.pin.strip().lower()
        if not PIN_GRAMMAR.fullmatch(pin):
            raise Fail(f"--pin {args.pin}: want 4 to 40 lowercase hex characters (a commit sha or its prefix)")
        kept = [r for r in rows if str(r.get("source_commit") or "").lower().startswith(pin)]
        pin_dropped = len(rows) - len(kept)
        if not kept:
            raise Fail(f"--pin {args.pin}: no row has a source_commit starting with it")
        rows = kept
    mans = load_manifests(args.manifests)
    arms = [a for a in suite["arms"] if isinstance(a, dict) and a.get("id")]
    arm_ids = [a["id"] for a in arms]
    labels = {str(a.get("label", a["id"])).upper(): a["id"] for a in arms}
    cuts = load_cuts(args.cuts, args.not_run, set(arm_ids), labels)
    for need in (CONTROL, BARE):
        if need not in arm_ids:
            raise Fail(f"suite has no arm {need}")

    # components: every runnable arm but the two baselines; an eval_only arm (cycle-131 FR-5: the open-mount
    # oracle A/B) is an evaluation control, never a shipped-default decision, so it is not a component here
    def is_eval_only(a):   # the flag, or the property it protects (audit r1 DISS-C-002)
        return a.get("eval_only") is True or (a.get("toggles") or {}).get("oracle_open") is True
    for a in arms:
        if not a.get("absent") and (a.get("toggles") or {}).get("oracle_open") is True and a.get("eval_only") is not True:
            raise Fail(f"suite arm {a.get('id')} opens the oracle (toggles.oracle_open: true) without eval_only: true")
    components = [a["id"] for a in arms if a["id"] not in (CONTROL, BARE) and not a.get("absent") and not is_eval_only(a)]
    absent = [a for a in arms if a.get("absent")]
    seed = args.seed
    groups, primary, unversioned = partition(rows, args.suite_version, mans,
                                             {a["id"]: a for a in arms})
    versions = sorted(groups, key=part_order(groups), reverse=True)
    others = [v for v in versions if v != primary]
    VS = {v: analyse(suite, groups[v], mans, args, cuts, components, v) for v in versions}
    # version-less rows that never reach a decision: listed under the primary version (report 1.2.1)
    VS[primary]["main"].listed.extend(unversioned)
    P = VS[primary]
    main, decisions, sens_rows = P["main"], P["decisions"], P["sens_rows"]
    h1_comps, a4 = P["h1_comps"], P["a4"]

    k = len(components)
    eval_only_arms = [a["id"] for a in arms if is_eval_only(a) and not a.get("absent")]
    eval_only_counts = {aid: sum(1 for r in P.get("rows", []) if r.get("arm") == aid) for aid in eval_only_arms}
    eval_only_line = ("Evaluation-only arms (not components): " +
                      (", ".join(f"{aid} ({n} rows)" for aid, n in eval_only_counts.items()) if eval_only_counts else "none") +
                      " — read by their own pre-registered contrast, never by a decision here.")
    efp = k * (1.0 - args.level) / 2.0
    efp_line = (f"Expected false positives at level {args.level:.2f} over {k} components: "
                f"{k} × (1 − {args.level:.2f}) / 2 = {efp:.2f} one-sided per direction "
                f"({2 * efp:.2f} in either direction); no multiple-comparison correction is applied "
                f"(multiple_comparisons: {rules.get('multiple_comparisons', 'none')}).")

    # provenance
    used = [m for b, m in sorted(mans.items()) if any(r["batch"] == b for r in rows)] or \
        [m for _, m in sorted(mans.items())]

    def distinct(key, rowkey=None):
        vals = {str(m.get(key)) for m in used if m.get(key) not in (None, "")}
        vals |= {str(r.get(rowkey or key)) for r in rows if r.get(rowkey or key) not in (None, "")}
        return sorted(vals)

    def cli(m):
        return m.get("cli_version") or (m.get("executor") or {}).get("cli_version")

    lines = []
    L = lines.append
    L("# Loa 2.0 component ablation — report")
    L("")
    if args.partial:
        L(f"**{PARTIAL_LINE}**")
        L("")
    L(f"- report schema_version {REPORT_SCHEMA}; ablation-report.py {VERSION}")
    L(f"- suite: `{args.suite}` (name {suite.get('name', 'n/a')}, suite_version {suite.get('suite_version', 'n/a')})")
    L(f"- row suite_version: {', '.join(distinct('suite_version')) or 'n/a'}")
    for v in versions:
        V = VS[v]
        role = "primary: the main sections" if v == primary else "reported separately, never pooled"
        L(f"  - suite_version {v} ({role}): {len(V['rows'])} rows; batches {', '.join(V['batches']) or 'none'}; "
          f"suite manifest sha256 {', '.join(V['shas']) or 'n/a'}")
    L(f"- source commit(s): {', '.join(distinct('source_commit')) or 'n/a'}"
      + (f"; --pin {args.pin}: {pin_dropped} row(s) of other source commits not read" if args.pin is not None else ""))
    rules_seen = sorted({x for x in (part_rule(r) for r in rows) if x is not None})
    L(f"- decision statistic: {CATCH} (grader rule {', '.join(rules_seen) or 'n/a'}); {CATCH_PM3} and {CATCH_PM3_V1} "
      f"are printed beside it and decide nothing; rows of different suite_version, source_commit or grader_rule "
      f"are never pooled (partitions: {', '.join(versions)})")
    L(f"- a contrast needs at least {main.min_cells} valid cells (a trial valid in both arms) or reads insufficient; "
      f"oracle-exposed cells in the main reads: "
      f"{'excluded (--exclude-oracle-exposed true)' if args.exclude_oracle_exposed == 'true' else 'included (the labelled sensitivity excludes them)'}")
    shas = distinct("suite_manifest_sha256")
    drift = [v for v in versions if len(VS[v]["shas"]) > 1]
    L(f"- suite manifest sha256: {', '.join(shas) or 'n/a'}" + (
        " — DRIFT: more than one" + ("" if len(versions) == 1 else f" within suite_version {', '.join(drift)}")
        if drift else ""))
    L(f"- image digest(s): {', '.join(distinct('image_digest')) or 'n/a'}")
    L(f"- cli_version(s): {', '.join(sorted({str(cli(m)) for m in used if cli(m)})) or 'n/a'}")
    L("- batches:")
    for b, m in sorted(mans.items()):
        n = sum(1 for r in rows if r["batch"] == b)
        L(f"  - `{b}`{' (smoke: listed, never decided)' if m.get('smoke') is True else ''}: {n} rows, "
          f"shuffle_seed {m.get('shuffle_seed', 'n/a')}, pre_registration_ref {m.get('pre_registration_ref', 'n/a')}, "
          f"source_commit {m.get('source_commit', 'n/a')}, image_digest {m.get('image_digest', 'n/a')}, "
          f"cli_version {cli(m) or 'n/a'}")
    n_listed = sum(len(VS[v]["main"].listed) for v in versions)
    L(f"- rows read: {len(rows)} from {', '.join('`' + p + '`' for p in args.runs)}; "
      f"{n_listed} listed and never decided; {len(dups)} duplicate run_id rows dropped")

    def mark(v, pre):
        return "" if v == pre else f" (NOT the pre-registered {pre})"

    L(f"- bootstrap: {args.resamples} resamples{mark(args.resamples, int(pre_res))}, level {args.level:.2f}"
      f"{mark(args.level, float(pre_lvl))}, seed {seed}; exclusion statuses "
      f"{', '.join(sorted(main.ex_statuses))}; degraded rows excluded: {str(args.exclude_degraded).lower()}")
    L("")
    L("## Decisions")
    L("")
    render_decisions(L, P, absent, rules)
    L(efp_line)
    L(eval_only_line)
    L("")

    L("## Per-arm detail")
    L("")
    detail_arms = [BARE, CONTROL] + components
    metrics = render_per_arm(L, P, detail_arms, "###")

    render_exclusions(L, P, dups, "##", "###")

    L("## Cuts")
    L("")
    pw = [d for d in decisions if d["state"] == "inconclusive_by_power" and d["arm"] not in cuts]
    if not cuts and not pw:
        L("- none recorded")
    for a in sorted(cuts):
        c = cuts[a]
        L(f"- `{a}`: {DISPLAY[c['state']]} — reason: {c['reason']}; figure: {c['figure']} ({c['source']})")
    for d in pw:
        L(f"- `{d['arm']}`: Inconclusive-by-power from the rows — {d['figure']}")
    L(f"- cut ladder (suite): {'; '.join(suite.get('cut_ladder') or []) or 'n/a'}")
    L("")

    L(f"## Sensitivity figure: {SENS_LABEL}")
    L("")
    render_sens(L, P, rules, "###")
    render_extra_sens(L, P, rules, "##")

    render_budget(L, P["budget"], "##")

    L("## Rows per cell")
    L("")
    for d in decisions:
        for p in d["comparisons"]:
            if not p["pairs"]:
                continue
            L(f"### {d['arm_label']} `{d['arm']}` — {p['metric']}")
            L("")
            L("| task | arm value | a1_full value | diff | arm rows | a1_full rows |")
            L("|---|---|---|---|---|---|")
            for x in p["pairs"]:
                L(f"| {x['task_id']} | {u3(x['arm_value'])} | {u3(x['control_value'])} | {f3(x['diff'])} | "
                  f"{', '.join('`' + s + '`' for s in collapse(x['arm_runs']))} | "
                  f"{', '.join('`' + s + '`' for s in collapse(x['control_runs']))} |")
            L("")
    for title, comps in (("H1 a1_full − a0_bare", h1_comps), ("A4 a4_no_gates − a1_full", [a4] if a4 else [])):
        for p in comps:
            if not p["pairs"]:
                continue
            L(f"### {title} — {p['metric']}")
            L("")
            L("| task | diff | arm rows | control rows |")
            L("|---|---|---|---|")
            for x in p["pairs"]:
                L(f"| {x['task_id']} | {f3(x['diff'])} | {', '.join('`' + s + '`' for s in collapse(x['arm_runs']))} | "
                  f"{', '.join('`' + s + '`' for s in collapse(x['control_runs']))} |")
            L("")

    other_metrics = {}
    for v in others:
        V = VS[v]
        L(f"## Suite version {v} (batches: {', '.join(V['batches']) or 'none'}) — reported separately, never pooled")
        L("")
        L(f"The rows of suite_version {v} only ({len(V['rows'])} rows; suite manifest sha256 "
          f"{', '.join(V['shas']) or 'n/a'}); the same rules, cuts and seed; no figure here is pooled with "
          f"suite_version {primary}.")
        L("")
        L(f"### Decisions (suite_version {v})")
        L("")
        render_decisions(L, V, absent, rules)
        L(f"### Per-arm detail (suite_version {v})")
        L("")
        other_metrics[v] = render_per_arm(L, V, detail_arms, "####")
        render_exclusions(L, V, [], "###", "####")
        L(f"### Sensitivity figure (suite_version {v}): {SENS_LABEL}")
        L("")
        render_sens(L, V, rules, "####")
        render_extra_sens(L, V, rules, "###")
        render_budget(L, V["budget"], "###")

    # never fatal: the batch record is presentation only; its computation (grouping rows by batch, the
    # manifest and path lookups, each batch's suite_version and directory), its JSON form and its rendering
    # all degrade to "Not rendered (…)" with a note (report 1.2.2; rendering alone since 1.2.1)
    # report 1.2.3 (audit DISS-C-002): the text names the exception class and the stage only; str(x) goes to
    # stderr (it can carry a file's content or a host path)
    blines, recs_json, recs_note = [], [], None
    where = {"stage": "grouping the batch record"}
    try:
        recs = batch_record(mans, rows, where)
        recs_json = [dict(e, suite_version=version_value(e["suite_version"])) for e in recs]
        render_batches(blines.append, recs)
    except Exception as x:
        why = stage_note(x, where["stage"])
        recs_json, recs_note = [], f"batch record not computed ({why}); it decides nothing"
        blines = ["## Batch record", "", f"Not rendered ({why}); it decides nothing.", ""]
    lines.extend(blines)

    L("## Method")
    L("")
    L(f"The pre-registered rules block of `{args.suite}`, quoted verbatim:")
    L("")
    L("```yaml")
    L(rules_text)
    L("```")
    L("")
    L("- Pass rate: the unit is the task; a cell is one task-trial; a task's value is the mean of its valid "
      "trials (cap_failure scores 0); a trial excluded in either arm leaves both arms of that comparison "
      "(pairwise); a task with no valid cell in either arm leaves the pair and is listed.")
    L("- Catch rate: the unit is the defect (task × dK); a defect's value is the share of the arm's valid trials "
      "that caught it (ids from the row's defects_missed / recall.missed, else the row's defect_catch_rate for "
      "every defect of the task); the task-level figure is also reported and decides nothing.")
    L(f"- Interval: percentile bootstrap of the mean paired difference, {args.resamples} resamples with "
      f"replacement from random.Random({seed}) (one generator per interval), linear interpolation between "
      f"order statistics, [lo, hi] at the {(1 - args.level) / 2:.2f} and {1 - (1 - args.level) / 2:.2f} quantiles; "
      "d is the mean of the paired differences.")
    L("- c and w: (mean_arm − mean_a1) / mean_a1 × 100 over the per-task means of the paired cells (cost_usd, "
      "wall_clock_ms).")
    L(f"- MDE: (z({1 - (1 - args.level) / 2:.2f}) + z({POWER:.2f})) × sd(paired diffs) / sqrt(n); an arm whose "
      f"predicates read remove or simplify with an MDE above mde_cut ({rules.get('mde_cut', 'n/a')}) reads "
      "Inconclusive-by-power.")
    L("- Predicates are evaluated in order on values rounded to 9 decimals, the degradation guard first "
      f"(excluded share > {main.guard:g} reads Inconclusive-by-degradation whatever the interval, DEC-0393), then "
      "investigate, keep, inconclusive (d < -0.03 or no valid pair), remove, simplify; Inconclusive-by-degradation is the "
      "inconclusive outcome whose excluded-share clause matched.")
    L("- Suite versions: rows of different suite_version values are never pooled; the main sections read the "
      "highest suite_version present (or --suite-version), every other version has its own section.")
    L(f"- H1 and A4 read each primary in order: not testable (no task of its type in either arm) → inconclusive "
      f"by degradation (either arm's excluded share on that primary's task types > {main.guard:g}) → degenerate "
      "(a catch-rate pair from one task with no per-defect ids: zero variance by construction, read as no valid "
      "pair, also for the component decisions) → no pair → the interval. H1 is decided on the primaries left; "
      "with none, H1 reads inconclusive by degradation when every testable primary is, else not yet decidable.")
    L("")

    def version_json(V, ms):
        return {"suite_version": version_value(V["version"]), "rows": len(V["rows"]), "batches": V["batches"],
                "suite_manifest_sha256": V["shas"], "decidable": V["decidable"],
                "h1": h1_json(V, rules), "a4": a4_json(V, rules), "decisions": decisions_json(V["decisions"]),
                "arms": arms_json(ms), "exclusions": exclusions_json(V), "listed": listed_json(V),
                "cap_failures": [r["run_id"] for r in V["caps"]],
                "sensitivity": sens_json(V), "budget_matched": budget_json(V["budget"]),
                "sensitivities": extra_json(V)}

    def extra_json(V):
        return {k: {"label": X["label"], "excluded_rows_per_arm": X["counts"], "reported_open_rows_per_arm": X["reported"],
                    "h1": dict(h1_json(X["h"], rules)), "a4": dict(a4_json(X["h"], rules)),
                    "rows": [{"arm": d["arm"], "predicate_state": d["predicate_state"],
                              "comparisons": [comp_json(p) for p in d["comparisons"]]} for d in X["rows"]]}
                for k, X in V["extra_sens"].items()}

    def sens_json(V):
        return {"treatment": SENS_H_TREATMENT,
                "h1": dict(h1_json(V["sens_h"], rules), line=SENS_PREFIX + V["sens_h"]["h1_line"]),
                "a4": dict(a4_json(V["sens_h"], rules), line=SENS_PREFIX + V["sens_h"]["a4_line"]),
                "rows": [{"arm": d["arm"], "predicate_state": d["predicate_state"], "c": j6(d["c"]),
                          "w": j6(d["w"]), "excluded_share": j6(d["excluded_share"]),
                          "comparisons": [comp_json(p) for p in d["comparisons"]]} for d in V["sens_rows"]]}

    other_metrics[primary] = metrics
    data = {
        "schema_version": REPORT_SCHEMA, "generator": f"ablation-report.py {VERSION}", "partial": bool(args.partial),
        "suite": {"path": args.suite, "name": suite.get("name"), "suite_version": suite.get("suite_version")},
        "primary_suite_version": version_value(primary),
        "by_suite_version": {v: version_json(VS[v], other_metrics[v]) for v in versions},
        "provenance": {"source_commits": distinct("source_commit"), "suite_manifest_sha256": shas,
                       "suite_versions": distinct("suite_version"), "image_digests": distinct("image_digest"),
                       "batches": [{"batch": b, "smoke": m.get("smoke") is True, "shuffle_seed": m.get("shuffle_seed"),
                                    "pre_registration_ref": m.get("pre_registration_ref"),
                                    "source_commit": m.get("source_commit"), "image_digest": m.get("image_digest"),
                                    "cli_version": cli(m), "manifest": m["_path"]} for b, m in sorted(mans.items())]},
        "bootstrap": {"resamples": args.resamples, "level": args.level, "seed": seed},
        "exclude_degraded": bool(args.exclude_degraded),
        "decisions": decisions_json(decisions),
        "absent": [{"arm": a["id"], "label": a.get("label"), "state": "component_absent",
                    "evidence": a.get("evidence")} for a in absent],
        "h1": h1_json(P, rules),
        "a4": a4_json(P, rules),
        "expected_false_positives": {"components": k, "per_direction": j6(efp), "line": efp_line,
                                     "eval_only_arms": eval_only_counts},
        "arms": arms_json(metrics),
        "exclusions": exclusions_json(P),
        "listed": listed_json(P),
        "duplicates": dups,
        "cap_failures": [r["run_id"] for r in P["caps"]],
        "cuts": [dict(arm=a, **cuts[a]) for a in sorted(cuts)],
        "sensitivity": dict(sens_json(P), label=SENS_LABEL),
        "sensitivities": extra_json(P),
        "decision_statistic": CATCH, "beside": [CATCH_PM3, CATCH_PM3_V1], "min_valid_cells": main.min_cells,
        "pin": args.pin, "pin_dropped_rows": pin_dropped,
        "oracle_exposed_in_main": "excluded" if args.exclude_oracle_exposed == "true" else "included",
        "budget_matched": budget_json(P["budget"]),
        "batches": recs_json,
        "batches_note": recs_note,
    }
    return "\n".join(lines) + "\n", data, P["decidable"]


def write_out(path, text):
    if os.path.islink(path):
        raise Fail(f"refusing to write through the symlink {path}")
    parent = os.path.dirname(os.path.abspath(path))
    if not os.path.isdir(parent):
        raise Fail(f"the directory of {path} does not exist")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)


def non_finite_key(x, path="$"):
    """The JSON path of the first non-finite float in x (sorted keys), None when there is none."""
    if isinstance(x, float) and not math.isfinite(x):
        return path
    if isinstance(x, dict):
        for k in sorted(x, key=str):
            hit = non_finite_key(x[k], f"{path}.{k}")
            if hit:
                return hit
    elif isinstance(x, (list, tuple)):
        for i, v in enumerate(x):
            hit = non_finite_key(v, f"{path}[{i}]")
            if hit:
                return hit
    return None


def json_text(data):
    """The JSON twin; allow_nan=False (report 1.2.3, audit DISS-C-003): a NaN or an infinity fails loudly
    (exit 2, naming the key) instead of writing the non-standard NaN/Infinity tokens."""
    try:
        return json.dumps(data, indent=2, sort_keys=True, ensure_ascii=False, allow_nan=False) + "\n"
    except ValueError:
        raise Fail(f"refusing to write a non-finite number to the JSON report at {non_finite_key(data)} "
                   f"(NaN or Infinity is not JSON); nothing was written")


class Parser(argparse.ArgumentParser):
    def error(self, message):
        sys.stderr.write(f"ablation-report.py: {message}\n")
        sys.exit(2)


def main(argv):
    ap = Parser(prog="ablation-report.py", description="cycle-130 ablation report (see the header)")
    ap.add_argument("--runs", action="append", required=True)
    ap.add_argument("--manifests", action="append", required=True)
    ap.add_argument("--suite", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--json", dest="json_out")
    ap.add_argument("--seed", type=int, default=20261015)
    ap.add_argument("--resamples", type=int)
    ap.add_argument("--level", type=float)
    ap.add_argument("--exclude-degraded", choices=("true", "false"), default="true")
    ap.add_argument("--partial", action="store_true")
    ap.add_argument("--cuts")
    ap.add_argument("--not-run")
    ap.add_argument("--suite-version")
    ap.add_argument("--pin")
    ap.add_argument("--exclude-oracle-exposed", choices=("true", "false"), default="false")
    args = ap.parse_args(argv)
    args.exclude_degraded = args.exclude_degraded == "true"
    try:
        text, data, decidable = build(args)
        jtext = json_text(data) if args.json_out else None  # before any write: a non-finite value writes nothing
        write_out(args.out, text)
        if args.json_out:
            write_out(args.json_out, jtext)
    except Fail as e:
        sys.stderr.write(f"ablation-report.py: {e}\n")
        return 2
    if args.partial and not decidable:
        sys.stderr.write("ablation-report.py: --partial: no comparison has a valid pair yet (report written)\n")
        return 1
    print(f"ablation-report.py: wrote {args.out}" + (f" and {args.json_out}" if args.json_out else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
