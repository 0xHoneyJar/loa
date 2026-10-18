# Sprint 261 — Task 4.6: suite v2 calibration smoke (decides nothing; DEC-0428)

**Pre-registration:** NOTES § "Sprints 261/262 re-scoped (Step B); suite v2 hardness criterion and per-type caps PRE-REGISTERED" — 2026-10-16T22:00:49Z (DEC-0566 criterion, DEC-0567 caps). Written before any v2 task file. **Criterion:** a build task enters suite v2 only if a0_bare's pass rate over two calibration trials is ≤ 0.5 on it; the twelve together a0_bare mean ≤ 0.75 with at least six tasks below 1.0; a failing task is swapped (new id), at most two authoring rounds; the a0 smoke is repeated on the swapped tasks only; the suite is re-frozen after every swap; `suite_version` stays 2 until the first priority-v2-p1 row. **Cap-fit:** a1_full's median cost per run on the smoke ≤ 0.75 × the type's cap (build 11.25, review-catch 15.00), else the tasks shrink or the cap rises before the re-pre-registration.

Results root `evals/results/ablation-2.0/` (rows in `runs.jsonl` there, never the tracked file). Harness: runner at `b5cf34cf` (per-type caps, `--types` fix), grader 1.2.9, image `loa-ablation:258`, arms pinned at `ba11b860`.

## Round 1 — `calib-v2-01a` (a0_bare × twelve v2 build tasks × 2 trials)

Launched 2026-10-17T00:28Z, complete 00:42Z; 24 rows, all `completed`, took-effect OK, USD 6.48 (USD 0.16–0.50 and about one minute per run). Suite v2 round 1 = `MANIFEST.sha256` `7bc1b538f742e44ae35122928626db8d4254e5eeb40e80b36d67a9189caaec9a` (215 files; commit `c817acd0`).

| task | a0 pass rate t1 / t2 | mean | cost t1 / t2 (USD) | criterion (i) ≤ 0.5 |
|---|---|---|---|---|
| bugfix-v2-01 | 1.0 / 1.0 | 1.000 | 0.21 / 0.21 | fail |
| bugfix-v2-02 | 0.0 / 1.0 | **0.500** | 0.18 / 0.21 | **pass** |
| bugfix-v2-03 | 1.0 / 1.0 | 1.000 | 0.20 / 0.16 | fail |
| bugfix-v2-04 | 1.0 / 1.0 | 1.000 | 0.17 / 0.18 | fail |
| feature-v2-01 | 1.0 / 1.0 | 1.000 | 0.41 / 0.48 | fail |
| feature-v2-02 | 1.0 / 1.0 | 1.000 | 0.41 / 0.50 | fail |
| feature-v2-03 | 1.0 / 1.0 | 1.000 | 0.46 / 0.50 | fail |
| feature-v2-04 | 1.0 / 1.0 | 1.000 | 0.25 / 0.29 | fail |
| refactor-v2-01 | 1.0 / 1.0 | 1.000 | 0.16 / 0.16 | fail |
| refactor-v2-02 | 1.0 / 1.0 | 1.000 | 0.28 / 0.30 | fail |
| refactor-v2-03 | 1.0 / 1.0 | 1.000 | 0.19 / 0.17 | fail |
| refactor-v2-04 | 1.0 / 1.0 | 1.000 | 0.20 / 0.20 | fail |

Set read: mean **0.958** (≤ 0.75 fails); tasks below 1.0: **1 of 12** (≥ 6 fails); tasks ≤ 0.5: 1. **The criterion fails; eleven tasks are swapped (round 1 of 2), bugfix-v2-02 is kept.** DEC-0584.

Reading (decides nothing): the round-1 tasks (150–600-line packages, 3–8 files, 8–16 hidden cases on behaviours the brief names, references 82–341 changed lines) sit far inside Opus 5.5's reach — the bare agent reads the brief and the package and fixes it in a handful of turns. Interaction depth did not slow it. The replacement design (`~/.cache/loa/cycle-130/prompt-s4-r2-common.md`): specification conformance at scale — a complete, citable spec of a known-shape component with documented edge semantics; 600–1,500-line fixtures over 8–15 modules; 30–60 hidden cases including oracle-conformance cases over generated inputs against a hidden reference implementation; refactor structural checks of 20–40 independent constraints; an author self-solve check (a task the author solves to 1.0 in ten minutes without the tests is hardened before delivery).

## Round 1 — `calib-v2-01b` (a1_full × refactor-v2-02, feature-v2-01, review-03, review-04 × 1 trial; concurrency 1)

Launched 2026-10-17T00:29Z, complete 02:51Z; 4 rows, all `completed`, no cap failure under the per-type caps, USD 54.14.

| task | type | A1 outcome | cost (USD) | wall | phases (USD) |
|---|---|---|---|---|---|
| review-03 (pr-12, 8 defects) | review-catch | catch 7/8 = 0.875 | **17.31** | 38.8 min | REVIEW 6.01, AUDIT 8.04 |
| review-04 (pr-13, 5 defects) | review-catch | catch 3/5 = 0.6 | **11.93** | 29.4 min | REVIEW 5.55, AUDIT 5.25 |
| feature-v2-01 (round 1) | feature-build | pass 1.0 | **10.91** | 30.9 min | PLAN 0.56, IMPLEMENT 0.55, REVIEW 3.65, FIX1 0.68, AUDIT 2.68 |
| refactor-v2-02 (round 1) | refactor | pass 1.0 | **13.99** | 42.7 min | PLAN 0.59, IMPLEMENT 0.49, REVIEW 4.57, FIX1 0.62, AUDIT 4.06 |

Cap-fit reads: review-catch median **14.62 ≤ 15.00 — fits** (both PRs that P1 had cut at USD 12 completed under the 20 cap); build median **12.45 > 11.25 — fails on round-1 tasks** (A1's build cost sits in the gates: REVIEW + AUDIT ≈ 6–9 of 11–14). The build read is repeated on two round-2 tasks (`calib-v2-02b`); if it fails there too the build cap rises (the pre-registered remedy; the tasks are not shrunk). DEC-0586.

## Round 2 — `calib-v2-02a` (a0_bare × the ten swapped tasks × 2) and `calib-v2-02b` (a1_full cost read on two round-2 build tasks)

Swap round 1 of 2 (DEC-0584): three Opus authors (D3, E3, F3) under `prompt-s4-r2-common.md` — specification conformance at scale. Delivered ten of eleven (feature-v2-06 did not converge; round-1 feature-v2-01 kept as the fourth feature task, DEC-0588). Sixteen fairness reviews PASS (per-task reviewers; bugfix-v2-07 failed once on a brief/oracle contradiction and was corrected, DEC-0587). Frozen at `bde0c22e`, `MANIFEST.sha256` `ddd200b313c5c02353abdc829d3a3a6c78f52b9118da2cf0da8c1eb21ae788c7` (282 files), grader 1.2.11 (DEC-0589), image self-check 36/36.

Authors' blind self-solves (fresh Opus 5.5 subagents given only TASK.md and the fixture) before the smoke: F3's four refactors 1.0, 1.0, 0.975, 0.975 in 3–4 minutes; E3's three features 1.0, 1.0, 1.0 in 3–7 minutes; D3's three bug-fixes 0.47 / 1.0 (two framings), 1.0, 0.57 — the 0.57 traced to the brief contradiction the fairness review then found. D3 also discarded four fully built designs after blind solves of 1.0.

`calib-v2-02a`: launched 2026-10-17T17:45Z, 20 rows, USD 20.38, about 3–10 minutes and USD 0.5–2.1 per run.

| task | component | a0 t1 / t2 | mean | cost t1 / t2 (USD) |
|---|---|---|---|---|
| bugfix-v2-05 | cron with a DST table | 1.0 / 1.0 | 1.000 | 0.60 / 0.51 |
| bugfix-v2-06 | semver + npm ranges + VersionIndex | 1.0 / 1.0 | 1.000 | 0.55 / 0.60 |
| bugfix-v2-07 | CommonMark block structure | 1.0 / 1.0 | 1.000 | 0.63 / 0.62 |
| feature-v2-05 | JSON Pointer/Patch + canonical diff | 1.0 / 1.0 | 1.000 | 0.85 / 0.88 |
| feature-v2-07 | cron on wall time, POSIX-TZ rule zones | 1.0 / 1.0 | 1.000 | 1.63 / 2.05 |
| feature-v2-08 | glob ignore rules, extglob, brace expansion | 1.0 / 1.0 | 1.000 | 1.16 / 1.10 |
| refactor-v2-05 | semver re-layering, 40 constraints | 1.0 / 1.0 | 1.000 | 1.42 / 1.37 |
| refactor-v2-06 | cron re-layering | 1.0 / 1.0 | 1.000 | 1.11 / 1.10 |
| refactor-v2-07 | JSON patch re-layering | 1.0 (contaminated, false positive) / 1.0 | 1.000 | 1.06 / 1.09 |
| refactor-v2-08 | task scheduler re-layering | 0.975 / 0.975 | 0.975 | 0.96 / 1.11 |

With bugfix-v2-02 (0.5) and feature-v2-01 (1.0) from round 1 the twelve give a0 mean **0.956**, **two** tasks below 1.0, **one** at or below 0.5. **The criterion fails after the second and last authoring round (DEC-0590): no build task enters the batch.** The one contaminated row is a KF-046 false positive (JSON Pointer literals `/a/1` passed as CLI arguments; recurrence 8).

Metric note: for bug-fix and feature tasks `hidden_test_pass_rate` is the share of the whole `test_command` run (hidden cases plus the fixture suite, green at base), so a no-op already scores 0.31–0.56 on the round-2 bug-fix and feature tasks; refactor tasks score the structural fraction only. The read above is on that pre-registered metric.

`calib-v2-02b` (a1_full, concurrency 1; complete 19:19Z, USD 30.79; the runner ends a batch in which no trial `completed` as `failed` — both rows are cap failures, nothing else went wrong): refactor-v2-05 **cap_failure** in AUDIT at USD **15.75** (48.8 min; PLAN 0.64, IMPLEMENT 2.28, REVIEW 5.45, FIX1 0.64, AUDIT at the stop); feature-v2-08 **cap_failure** in FIX1 at USD **15.04** (45.4 min). Both implement trees pass the hidden suite 1.0. The build cost read decides nothing now that no build task runs; it is reported (A1's gates cost USD 6–11 per build run on these tasks; the build cap of 15 would bind).

**Consequence (DEC-0591):** batch `priority-v2-p1` runs a0_bare and a1_full on the four review-catch tasks at 3 trials per cell under the review cap USD 20 (cap fit passed); H1 is read on the catch rate; the pass-rate primary and A4 are not testable on suite v2. Re-pre-registration NOTES 2026-10-17T18:40:55Z; launched 18:41:24Z.
