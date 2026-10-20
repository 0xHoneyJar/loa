# Task 1.9 — versioned re-grade of the 36 cycle-130 review-catch runs (grader 1.3.0, curated manifests) — 2026-10-19T07:25:46Z

Integrated tree: 7600bd7d + Sprint 263 patches A/B/C/D (uncommitted at the time of the run). Driver: `~/.cache/loa/cycle-131/scripts/regrade-c131.sh 1` (step 1, regression) and `regrade-c131-step2.sh` (rows). Scratch grades: `~/.cache/loa/cycle-131/regrade/<run_id>.grade.json`; no stored grade.json or runs.jsonl touched.

## Step 1 — regression: recall_pm3_v1 == stored recall on 36/36 runs (0 mismatches, 0 grade failures)

```
priority-v2-p1-a0_bare-review-01-t1            stored=1.0 v1=1.0 pm3=1.0 new=1.0 OK
priority-v2-p1b-a1_full-review-01-t1           stored=1.0 v1=1.0 pm3=1.0 new=1.0 OK
priority-v2-p1-a0_bare-review-01-t2            stored=1.0 v1=1.0 pm3=1.0 new=1.0 OK
priority-v2-p1b-a1_full-review-01-t2           stored=1.0 v1=1.0 pm3=1.0 new=1.0 OK
priority-v2-p1-a0_bare-review-01-t3            stored=1.0 v1=1.0 pm3=1.0 new=1.0 OK
priority-v2-p1b-a1_full-review-01-t3           stored=1.0 v1=1.0 pm3=1.0 new=1.0 OK
priority-v2-p1-a0_bare-review-02-t1            stored=0.6667 v1=0.6667 pm3=0.6667 new=1.0 OK
priority-v2-p1b-a1_full-review-02-t1           stored=1.0 v1=1.0 pm3=1.0 new=1.0 OK
priority-v2-p1-a0_bare-review-02-t2            stored=1.0 v1=1.0 pm3=1.0 new=1.0 OK
priority-v2-p1b-a1_full-review-02-t2           stored=1.0 v1=1.0 pm3=1.0 new=1.0 OK
priority-v2-p1-a0_bare-review-02-t3            stored=1.0 v1=1.0 pm3=1.0 new=1.0 OK
priority-v2-p1b-a1_full-review-02-t3           stored=1.0 v1=1.0 pm3=1.0 new=1.0 OK
priority-v2-p1-a0_bare-review-03-t1            stored=0.0 v1=0.0 pm3=0.5 new=0.5 OK
priority-v2-p1b-a1_full-review-03-t1           stored=0.625 v1=0.625 pm3=0.875 new=0.875 OK
priority-v2-p1-a0_bare-review-03-t2            stored=0.375 v1=0.375 pm3=0.75 new=0.75 OK
priority-v2-p1b-a1_full-review-03-t2           stored=0.875 v1=0.875 pm3=1.0 new=1.0 OK
priority-v2-p1-a0_bare-review-03-t3            stored=0.375 v1=0.375 pm3=0.75 new=0.75 OK
priority-v2-p1b-a1_full-review-03-t3           stored=0.75 v1=0.75 pm3=0.875 new=1.0 OK
priority-v2-p1-a0_bare-review-04-t1            stored=0.4 v1=0.4 pm3=0.6 new=0.6 OK
priority-v2-p1-a1_full-review-04-t1            stored=0.4 v1=0.4 pm3=0.4 new=0.6 OK
priority-v2-p1-a0_bare-review-04-t2            stored=0.6 v1=0.6 pm3=0.8 new=1.0 OK
priority-v2-p1-a1_full-review-04-t2            stored=1.0 v1=1.0 pm3=1.0 new=1.0 OK
priority-v2-p1-a0_bare-review-04-t3            stored=0.6 v1=0.6 pm3=0.8 new=1.0 OK
priority-v2-p1-a1_full-review-04-t3            stored=0.6 v1=0.6 pm3=1.0 new=1.0 OK
replication-01-a0_bare-review-r17-t1           stored=0.15 v1=0.15 pm3=0.25 new=0.3 OK
replication-01-a0_bare-review-r17-t2           stored=0.25 v1=0.25 pm3=0.6 new=0.6 OK
replication-01-a0_bare-review-r17-t3           stored=0.25 v1=0.25 pm3=0.5 new=0.5 OK
replication-01-a0_bare-review-r18-t1           stored=0.0 v1=0.0 pm3=0.0 new=0.125 OK
replication-01-a0_bare-review-r18-t2           stored=0.5 v1=0.5 pm3=0.5 new=0.5 OK
replication-01-a0_bare-review-r18-t3           stored=0.375 v1=0.375 pm3=0.375 new=0.375 OK
replication-01-a1_full-review-r17-t1           stored=0.75 v1=0.75 pm3=0.75 new=0.75 OK
replication-01-a1_full-review-r17-t2           stored=0.85 v1=0.85 pm3=0.85 new=0.85 OK
replication-01-a1_full-review-r17-t3           stored=0.65 v1=0.65 pm3=0.8 new=0.8 OK
replication-01-a1_full-review-r18-t1           stored=0.5 v1=0.5 pm3=0.75 new=0.75 OK
replication-01-a1_full-review-r18-t2           stored=0.5 v1=0.5 pm3=0.5 new=0.5 OK
replication-01-a1_full-review-r18-t3           stored=0.625 v1=0.625 pm3=0.875 new=0.875 OK
graded 36; failures/mismatches 0
exit=0
```

## Step 2 — rows: `grimoires/loa/reports/ablation-2.0/regrade-c131/rows.jsonl` (36 rows, row writer 1.4, `--validate` OK)

Columns: run_id, arm, grader_version, grader_rule, recall (new), recall_pm3, recall_pm3_v1, oracle-exposed defects (diff+read union, curated anchors).

```
priority-v2-p1-a0_bare-review-01-t1   a0_bare  1.3.0  pm3_or_same_function  1.0    1.0     1.0     0
priority-v2-p1b-a1_full-review-01-t1  a1_full  1.3.0  pm3_or_same_function  1.0    1.0     1.0     0
priority-v2-p1-a0_bare-review-01-t2   a0_bare  1.3.0  pm3_or_same_function  1.0    1.0     1.0     0
priority-v2-p1b-a1_full-review-01-t2  a1_full  1.3.0  pm3_or_same_function  1.0    1.0     1.0     1
priority-v2-p1-a0_bare-review-01-t3   a0_bare  1.3.0  pm3_or_same_function  1.0    1.0     1.0     0
priority-v2-p1b-a1_full-review-01-t3  a1_full  1.3.0  pm3_or_same_function  1.0    1.0     1.0     1
priority-v2-p1-a0_bare-review-02-t1   a0_bare  1.3.0  pm3_or_same_function  1.0    0.6667  0.6667  0
priority-v2-p1b-a1_full-review-02-t1  a1_full  1.3.0  pm3_or_same_function  1.0    1.0     1.0     0
priority-v2-p1-a0_bare-review-02-t2   a0_bare  1.3.0  pm3_or_same_function  1.0    1.0     1.0     0
priority-v2-p1b-a1_full-review-02-t2  a1_full  1.3.0  pm3_or_same_function  1.0    1.0     1.0     1
priority-v2-p1-a0_bare-review-02-t3   a0_bare  1.3.0  pm3_or_same_function  1.0    1.0     1.0     0
priority-v2-p1b-a1_full-review-02-t3  a1_full  1.3.0  pm3_or_same_function  1.0    1.0     1.0     1
priority-v2-p1-a0_bare-review-03-t1   a0_bare  1.3.0  pm3_or_same_function  0.5    0.5     0.0     0
priority-v2-p1b-a1_full-review-03-t1  a1_full  1.3.0  pm3_or_same_function  0.875  0.875   0.625   0
priority-v2-p1-a0_bare-review-03-t2   a0_bare  1.3.0  pm3_or_same_function  0.75   0.75    0.375   0
priority-v2-p1b-a1_full-review-03-t2  a1_full  1.3.0  pm3_or_same_function  1.0    1.0     0.875   1
priority-v2-p1-a0_bare-review-03-t3   a0_bare  1.3.0  pm3_or_same_function  0.75   0.75    0.375   0
priority-v2-p1b-a1_full-review-03-t3  a1_full  1.3.0  pm3_or_same_function  1.0    0.875   0.75    0
priority-v2-p1-a0_bare-review-04-t1   a0_bare  1.3.0  pm3_or_same_function  0.6    0.6     0.4     0
priority-v2-p1-a1_full-review-04-t1   a1_full  1.3.0  pm3_or_same_function  0.6    0.4     0.4     1
priority-v2-p1-a0_bare-review-04-t2   a0_bare  1.3.0  pm3_or_same_function  1.0    0.8     0.6     0
priority-v2-p1-a1_full-review-04-t2   a1_full  1.3.0  pm3_or_same_function  1.0    1.0     1.0     5
priority-v2-p1-a0_bare-review-04-t3   a0_bare  1.3.0  pm3_or_same_function  1.0    0.8     0.6     0
priority-v2-p1-a1_full-review-04-t3   a1_full  1.3.0  pm3_or_same_function  1.0    1.0     0.6     1
replication-01-a0_bare-review-r17-t1  a0_bare  1.3.0  pm3_or_same_function  0.3    0.25    0.15    0
replication-01-a0_bare-review-r17-t2  a0_bare  1.3.0  pm3_or_same_function  0.6    0.6     0.25    0
replication-01-a0_bare-review-r17-t3  a0_bare  1.3.0  pm3_or_same_function  0.5    0.5     0.25    0
replication-01-a0_bare-review-r18-t1  a0_bare  1.3.0  pm3_or_same_function  0.125  0.0     0.0     0
replication-01-a0_bare-review-r18-t2  a0_bare  1.3.0  pm3_or_same_function  0.5    0.5     0.5     0
replication-01-a0_bare-review-r18-t3  a0_bare  1.3.0  pm3_or_same_function  0.375  0.375   0.375   0
replication-01-a1_full-review-r17-t1  a1_full  1.3.0  pm3_or_same_function  0.75   0.75    0.75    9
replication-01-a1_full-review-r17-t2  a1_full  1.3.0  pm3_or_same_function  0.85   0.85    0.85    6
replication-01-a1_full-review-r17-t3  a1_full  1.3.0  pm3_or_same_function  0.8    0.8     0.65    14
replication-01-a1_full-review-r18-t1  a1_full  1.3.0  pm3_or_same_function  0.75   0.75    0.5     2
replication-01-a1_full-review-r18-t2  a1_full  1.3.0  pm3_or_same_function  0.5    0.5     0.5     1
replication-01-a1_full-review-r18-t3  a1_full  1.3.0  pm3_or_same_function  0.875  0.875   0.625   0
```

Notes: recall_pm3 differs from recall_pm3_v1 wherever the curated multi-site anchors (DEC-0626) add a cited line inside ±3; recall differs from recall_pm3 where the same-enclosing-definition rule credits (e.g. a0 r18-t1 0.0 → 0.125, a1 review-04-t1 0.4 → 0.6, a0 r17-t1 0.25 → 0.3). The oracle detector under the curated anchors flags r17-t1 on nine diff-form sites (d10 added by a curated anchor inside the REVIEW:314 hunk) versus eight under v1; the read form and the two newly found r17-t2/r17-t3 diffs (KF-049 rec 4, DEC-0632) account for the remaining exposure counts. Reads of these rows wait for Task 1.10's adjudication (rule adoption) and Sprint 3.
