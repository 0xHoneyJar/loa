# Sprint 260 (local sprint-3) — implementation report (lead)

**Sprint:** sprint-260 · **Cycle:** cycle-130-ablation-2.0 · **Branch:** feature/cycle-130-ablation-2.0 · **Base:** ba11b860 (Sprint 259 complete; the arms' pin) · **Implementers:** G (Opus 5.5, `../loa-wt-s3g`, Task 3.2 `run-ablation.sh` + `lib/arms-common.sh`), H (Opus 5.5, `../loa-wt-s3h`, Task 3.8 `ablation-report.py`), I (Opus 5.5, `../loa-wt-s3i`, the P1 drift/degraded narrowing, `--clear-drift`, `--rerow`), J (Opus 5.5, `../loa-wt-s3j`, `--rerun`/`--rerun-status`, the outage breaker), s3fix (Opus 5.5, `../loa-wt-s3fix`, the review fix round: grader 1.2.6, the post-run deadlines); lead: Tasks 3.1, 3.3–3.7, grader 1.2.1–1.2.5, the reads, the halt. Implementer reports: `reviewer-g.md`, `reviewer-h.md`, `reviewer-i.md`, `reviewer-j.md`, `reviewer-fix.md`.

## Executive Summary

Sprint 260 ran the ablation on suite v1 and halted on its own rules. The runner (`evals/harness/run-ablation.sh`) plans a batch trial-major with a seeded shuffle, refuses by applicability, enforces the DEC-0435 hard gate, dispatches to `pipeline-run.sh` under the per-run cap and a `--max-usd` reservation, checks took-effect evidence and drift per trial, grades, rows under `flock`, resumes without duplicates, re-rows and re-runs in place, stops on an outage, and writes `MANIFEST.json`/`STATUS.json` (SDD §3.4). The analysis script (`evals/harness/ablation-report.py`) turns rows into one decision per component by the pre-registered predicates with the degradation guard first (DEC-0530). Pre-registration preceded every run (NOTES 2026-10-15T07:13:29Z + addendum 08:03:32Z before the frozen-suite smoke at 08:33Z; the batch-plan entry 10:26:23Z before the first priority row at 10:26:28Z).

Batch `priority-p1` (A0, A1, A4; 132 trials) completed at 2026-10-16T09:09:27Z after a drift false positive (DEC-0545, 9 rows), six contamination-scan false-positive classes (grader 1.2.3 → 1.2.5, KF-046 recurrence 6, every flagged row read by hand) and a six-hour DNS outage (67 transport rows rerun on resume under DEC-0553; the outage breaker DEC-0554). Batch spend USD 614.13. The pre-registered reads (`reads.md`): H1 not established (a1_full − a0_bare pass −0.028 [−0.083, 0.000], catch −0.096 [−0.188, +0.007]); A4 not worse than A1 (+0.028 [0.000, +0.083]). Both halt conditions fired: no pruning, P2 and A5–A7 not launched, the run HALTED (DEC-0558). The cause is in the suite, not the arms: the twelve v1 build tasks saturate at 1.000 on every arm and the USD 12 cap stopped five of A1's twelve review runs in AUDIT after REVIEW had finished (raw catch a1_full 44/57 vs a0_bare 26/57). The operator chose option 1, harden before acting (DEC-0559); Sprints 261/262 were re-scoped (DEC-0564, DEC-0565).

The review round (dissent run 1, two voices; `engineer-feedback-r1.md` CHANGES_REQUIRED 0/0/2/4) found two mechanical defects and three gaps in the grader's contamination scan plus a missing deadline in the runner, all fixed by s3fix as grader 1.2.6 and the post-run `timeout` wrappers (commit de77522a; `evals/tests/` 378/378). The 1.2.6 scan over all 132 graded P1 run directories changes no `contaminated` field; it counts 391 interpreter heredocs (the documented DISS-C-003 gap, telemetry).

Commits: c44b32ff, 9ad48150 (suite pin, DEC-0529); c02d12bb (runner + report, 366/366); 2ef83aa8, ae9df520 (grader 1.2.1, 1.2.2); b0c1830a (P1 MANIFEST); f6487a31 (CHANGELOG); d8bb0bbe (grader 1.2.3); eec592d5 (implementer I, 369/369); ff4edc35, 151e87ed, 84de21df, 19731570, 3f8c2d37, e303a99d, f71f0543, 4c279606 (records); 6c454de7 (grader 1.2.4); 41a71297 (implementer J, 372/372); f8fbd330 (CHANGELOG); bf155cc7 (grader 1.2.5); c2d51e9b (P1 rows and STATUS); 8b319db2 (records, re-scope); de77522a (review fix round, 378/378). Decisions DEC-0529 … DEC-0563, DEC-0568 … DEC-0570.

## Calibration smoke (Task 3.3) and the batch plan (Task 3.4)

See `smoke.md` and `batch-plan.md`. Twelve trials on `bugfix-01` + `review-02` across eight arms, USD 66.28, took-effect 12/12 OK, cap fit held (A1 build USD 8.63 < 9), gate model answered on every gated run; the planning rung did not fit the DEC-0429 ceiling (USD 1,078 vs 1,039), so rung 2 of the cut ladder was pre-applied as two batches (P1: A0, A1, A4 at 3/3; P2: A2, A3 at 2 build / 3 review; DEC-0542) and A5–A7 pre-declared `Not run (cut)` at the smoke unit costs unless actuals or the reserve allow (DEC-0543); MDE deferred to P1's paired variance (DEC-0544).

## Batches (Task 3.5) and the reads (Task 3.6, Task 3.7)

`priority-p1`: launched 2026-10-15T10:26:28Z (`--max-usd 1039 --concurrency 3`, seed 20261015, 132 trials, 4 applicability refusals for A4 on review-catch); stopped 11:27:46Z (drift false positive, 9 rows, USD 42.90); resumed 11:53:35Z under eec592d5 (`--clear-drift`, two `--rerow`); cut 21:04:40Z by the assumed-cap accounting of 67 outage transport rows (DEC-0552); resumed 2026-10-16T02:40:18Z under f8fbd330 (`--rerun-status transport_error`, seven `--rerow`, `--max-usd 799`); complete 09:09:27Z. Rows: a0_bare 48 completed (USD 12.09); a1_full 42 completed + 6 cap_failure (USD 476.68; all six AUDIT-phase stops at USD 12.1–14.1: review-03 ×3, review-04 ×2, bugfix-03 t2); a4_no_gates 36 completed (USD 103.66). Retries: 67 transport first attempts (ledger USD 21.70), 11 re-rows, 1 drift cleared, 1 cut record kept, extra model Haiku 516 tokens once. Reads: `reads.md` / `partial-report-p1.{md,json}` — H1 not established, A4 not worse → halt (DEC-0558). Task 3.7: A5, A6, A7 `Not run (cut)` (DEC-0543 figures); P2 not launched; bd-2riyg closed as halted.

## AC Verification

### AC-3.1
- Criterion: AC-3.1 The NOTES pre-registration entry (rules, predicates, applicability, cut ladder, caps, reserve, contingencies, drift guard, `suite_version` protocol, H1 / A4 fail path, manifest hash) is timestamped before the Sprint 3 smoke; the batch-plan entry (chosen rung, trial counts, MDE, concurrency, `--max-usd`) is timestamped before the first priority-batch row; smoke rows live in the smoke batch and decide nothing (PRD AC-7.1; DEC-0428)
- Status: ✓ Met
- Evidence: grimoires/loa/NOTES.md § "Pre-registration — cycle-130 ablation (Task 3.1, lead) — 2026-10-15T07:13:29Z" (+ addendum 08:03:32Z, DEC-0530) precedes the frozen-suite smoke (`calib-frozen-01` started 08:33Z; `a2a/sprint-260/calib-frozen-01/MANIFEST.json` `created`); § "Batch plan — cycle-130 ablation (Task 3.4) — 2026-10-15T10:26:23Z" precedes the first P1 launch 10:26:28Z (`batches/priority-p1/run.log:1`) and is the manifest's `pre_registration_ref`; smoke rows live in `evals/results/ablation-2.0/` (ignored; copy under `a2a/sprint-260/calib-frozen-01/`), never in the tracked `runs.jsonl`.

### AC-3.2
- Criterion: AC-3.2 `run-ablation.sh --dry-run` prints the randomised plan with its shuffle seed and writes `MANIFEST.json` with source commit, model ids, fingerprint, `agy_opt_in: false`, arms, tasks, trials, caps, `pre_registration_ref` (PRD AC-7.2)
- Status: ✓ Met
- Evidence: evals/harness/run-ablation.sh `write_manifest`; dry run 10:26Z printed `plan: 3 arms, 16 tasks, 132 trials, shuffle seed 20261015, est USD 948 (cap 1039, run cap 12, reserve 250)` and four `refused:` lines; grimoires/loa/reports/ablation-2.0/batches/priority-p1/MANIFEST.json carries `source_commit ba11b860…`, `phase_models` (Opus 5.5 PLAN/IMPLEMENT/FIX/BARE, Fable 5.1 REVIEW/AUDIT), `fingerprint fp:fdd72f05…`, `agy_opt_in false`, `arms`, 16 `tasks`, `trials_per_type {build 3, review-catch 3}`, `trials_planned 132`, `caps {cycle 1500, run 12, reserve 250, max 1039}`, `pre_registration_ref`, `shuffle_seed 20261015`, `cli_version 2.1.299`, `image_digest`, `suite_manifest_sha256 30e1f2ad…`, `gate` hashes; evals/tests/run-ablation.bats RAB-1, RAB-2.

### AC-3.3
- Criterion: AC-3.3 `smoke.md` lists every runnable arm with took-effect evidence and A1's cost per build task; the cap-fit read is recorded (median vs USD 9) and acted on (PRD AC-7.3)
- Status: ✓ Met
- Evidence: grimoires/loa/a2a/sprint-260/smoke.md (rows table for eight arms, took-effect 12 × OK, A1 build USD 8.63, cap-fit read "fits, 4 % headroom; no shrinking", contamination calibration 10 → 0, difficulty note, gate-model contingency not needed). The P1 actuals later showed the smoke's single build task under-estimated A1's review-catch cost (REVIEW ≈ 5 + AUDIT 4–9 USD on the 5–8-defect PRs); the per-type caps of Sprint 261 (DEC-0567) answer that.

### AC-3.4
- Criterion: AC-3.4 `batch-plan.md` projects the priority batch from smoke actuals, states the trial counts and the arms beyond A0–A4 that fit; the batch command shows `--max-usd`
- Status: ✓ Met
- Evidence: grimoires/loa/a2a/sprint-260/batch-plan.md (unit-cost table, projection USD 1,077.7 vs ceiling 1,039.21, rung 2 with trial counts per arm, P1/P2 commands with `--max-usd 1039` and the recomputation rule, A5–A7 figures and the `Not run (cut)` pre-declaration, MDE deferral); NOTES batch-plan entry 10:26:23Z; DEC-0542 … DEC-0544.

### AC-3.5
- Criterion: AC-3.5 Every row carries `attempts`/`retry_reason`; model failures are `agent_error` and never retried; cap failures are `cap_failure`; a trial with no row after twice its phase-sum timeout is killed and recorded `interrupted` (PRD AC-7.4; DEC-0429)
- Status: ✓ Met
- Evidence: every one of the 132 P1 rows carries `attempts` and `retry_reason` (`jq '{attempts, retry_reason}' runs.jsonl`); the 67 outage rows carried `attempts 2` with `retry_reason transport: …` before their reruns replaced them (DEC-0553; `STATUS.rerun[]` 67 entries, `retries[]`); six rows are `cap_failure` with `cap_phase AUDIT` (`priority-p1-a1_full-review-03-t{1,2,3}`, `review-04-t{1,3}`, `bugfix-03-t2`); no P1 row is `agent_error` or `interrupted`, so the mechanism is evidenced by the bats: evals/tests/run-ablation.bats RAB-5 (agent_error never retried, transport retried once, the cap charge), RAB-8 (watchdog at 2 × phase-sum: `interrupted` row with and without a record), RAB-14 (transport classifier), RAB-21 (the post-run deadlines added in the fix round); evals/harness/run-ablation.sh `run_trial`, `post_run`, `watchdog_tick`.

### AC-3.6
- Criterion: AC-3.6 Spend posted in NOTES after every batch from `spend.sh`; the cycle total never exceeds USD 1,500; every cut names its reason and figure (PRD G-4)
- Status: ✓ Met
- Evidence: NOTES spend posts after the calibration smoke (batch-plan entry 10:26:23Z: USD 174.79), at the P1 stop (11:30Z: 217.69), after the outage (2026-10-16T01:58Z: ≈ 415 incl. the first-attempt ledger) and at P1 complete (09:10:43Z: USD 788.92 = spend.sh 767.22 + first-attempt ledger 21.70; 791.94 at the operator decision 21:24Z); the cycle total ≈ USD 792 of 1,500. Cuts named with reason and figure: DEC-0543 (A5–A7 `Not run (cut)`: ≈ 208 / 275 / 275 vs ≈ 147 remaining), DEC-0552 (the resumed ceiling 799 after the assumed-cap cut at 1,044.67 ≥ 1,039; `STATUS.cuts[0]`), DEC-0558 (P2 not launched: the halt). `batches/priority-p1/spend.txt`.

### AC-3.7
- Criterion: AC-3.7 `run-ablation.bats`: plan shape, applicability refusal, shuffle seed, freeze refusal, the hard gate (a non-smoke batch refuses without the manifest hash, the self-check output and sixteen `REVIEW.md` files, and records their hashes in `MANIFEST.json`), `--resume` reconciliation, a took-effect miss pauses the arm and `--clear-arm` resumes it, `STATUS.json` carries the §3.4 fields incl. `paused_arms` and `cuts[].in_flight_reserved` (DEC-0435)
- Status: ✓ Met
- Evidence: evals/tests/run-ablation.bats RAB-1 (plan shape, `refused:` line, MANIFEST fields), RAB-2 (seeded shuffle), RAB-3 (hard gate refusals, REFUSED.txt, gate hashes), RAB-4 (smoke keeps the freeze), RAB-6 (took-effect pause and `--clear-arm`), RAB-9 (`--max-usd` cut with `cuts[]` incl. `in_flight_reserved`), RAB-10 (`--resume` reconciliation, no duplicate run_id), RAB-16 … RAB-21 (extra models, `--clear-drift`, `--rerow`, `--rerun`/`--rerun-status`, the outage breaker, the post-run deadlines); 22/22 at de77522a; `evals/tests/` 378/378.

### AC-3.10
- Criterion: AC-3.10 `ablation-report.bats` on planted rows: each rule branch incl. exactly-at-threshold rows (−0.03 inclusive for Remove and Simplify, `hi < 0` strict for Keep, −15 % inclusive for cost), `Not run (cut)` and `Inconclusive-by-power` states, H1 and A4 lines, cap failure as 0, pairwise exclusion, the 25 % guard, build-only arms on the pass rate alone, defects as the catch-rate unit, the labelled sensitivity figure (PRD AC-8.1; DEC-0434)
- Status: ✓ Met
- Evidence: evals/tests/ablation-report.bats (22 cases over `evals/tests/fixtures/ablation-report/gen-fixtures.py`'s four planted scenarios: rule branches and boundary rows AR-1/AR-2, `Not run (cut)` AR-9, `Inconclusive-by-power` with the MDE AR-10, H1/A4 lines AR-11, cap failure as 0 and the sensitivity label AR-3, pairwise exclusion AR-4, the 25 % guard first AR-5/AR-22, build-only arms AR-6, defects as the unit AR-7); `reviewer-h.md`; `ablation-report.py --partial` produced `partial-report-p1.{md,json}` on the real 132 rows (bd-wqbz3 filed for the n = 0 wording; the sensitivity H1/A4 lines are Sprint 262 report hardening).

### AC-3.8
- Criterion: AC-3.8 The A4 sensitivity and H1 reads are recorded with their intervals and the resulting action (continue, harden, or halt before promotion)
- Status: ✓ Met
- Evidence: grimoires/loa/a2a/sprint-260/reads.md (2026-10-16T09:30Z): H1 a1_full − a0_bare pass −0.028 [−0.083, 0.000] (n = 12 tasks), catch −0.096 [−0.188, +0.007] (n = 19 defects) → not established → halt before promotion; A4 a4_no_gates − a1_full pass +0.028 [0.000, +0.083] (n = 12) → fails → harden tasks before acting on other arms; the action recorded as DEC-0558 (halt; no pruning; P2 and A5–A7 not launched; the operator decides) and executed (run HALTED 09:20:17Z, draft PR #1283 `[INCOMPLETE]`); the operator's choice DEC-0559.

### AC-3.9
- Criterion: AC-3.9 No dissent run started while a batch was running (log timestamps in the sprint report)
- Status: ✓ Met
- Evidence: batch windows — `calib-frozen-01` 2026-10-15T08:33–09:52Z; `priority-p1` 10:26:28Z–11:27:46Z, 11:53:35Z–21:04:40Z (16 Oct), 2026-10-16T02:40:18Z–09:09:27Z. Dissent runs — run 1 (review) started 09:12Z on 16 Oct (`adversarial-review-r1.json` `metadata.timestamp 2026-10-16T09:12:07Z`; `~/.cache/loa/cycle-130/logs/dissent-s260.log`), after P1 completed 09:09:27Z; run 2 (review, the fix diff) started 2026-10-16T23:4xZ with no batch running (the suite v2 calibration smoke `calib-v2-01` is a Sprint 261 batch and had not started); the audit run follows run 2 in the same window. No batch of Sprint 260 overlapped a dissent run.

## Review fix round (engineer-feedback-r1.md → de77522a)

- MEDIUM-1 closed: `HEREDOC` keeps the operator line (`(<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\2)([^\n]*\n)(?:[^\n]*\n)*?[ \t]*\3[ \t]*(?=\n|$)`, the remainder re-emitted); AG-29.
- MEDIUM-2 closed: no `re.S`, one line per body iteration; an 80-line command with `$((1<<n))`, `<<<"word"` and no terminator grades in 0.7 s (the pre-fix grader hit a 20 s timeout); AG-30.
- LOW-1 closed: `in_quotes` is a quote state machine; `cd "/root"`, `ls '/home'`, `cd '/root'`, `echo "don't" && ls /root` are hits; `grep -E ' /tmp | /home '`, `awk '/start/,/end/'` stay clean; AG-31.
- LOW-2 closed: `HIDDEN_TOKEN` = `HIDDEN|(?i:(?<=[/._=*?-])hidden\b|\bhidden(?=[/_=*?-]|\.[A-Za-z0-9]))|\bhidden(?=[A-Z])`; `pytest -k hidden` stays clean (refactor-03 precedent in the header); AG-32.
- LOW-3 closed: the interpreter-heredoc gap documented; `grade.json heredoc_interpreters` (391 over the 132 P1 runs); AG-33.
- LOW-4 closed: `LOA_ABLATION_GRADE_TIMEOUT_S` (1800) and `LOA_ABLATION_TOOK_EFFECT_TIMEOUT_S` (300) wrap the post-run calls; 124/137 → `infrastructure_error`; MANIFEST `watchdog.grade_timeout_s`/`took_effect_timeout_s`; RAB-21.
- Verification: `evals/tests/` 378/378 (372 + 6); `~/.cache/loa/cycle-130/rescan-p1-126.py` ran the real 1.2.6 `contamination()` over all 132 graded P1 run directories: 0 changes against the stored `grade.json`. Grader versions inside P1 stay 1.2.2 … 1.2.5 in the inline grades; Sprint 262 Task 5.1 re-grades every run directory under one grader.

## Lead's own corrections (surgical)
- grader 1.2.1/1.2.2 (DEC-0540/0541, calibration), 1.2.3 (DEC-0546), 1.2.4 (DEC-0551), 1.2.5 (DEC-0557): contamination-scan exemptions for shell idioms; AG-10 extended each time.
- AT-13 expectation after the predicate reorder (DEC-0530).
- The run-halt protocol by hand (state files, the draft PR) and the resume by hand (`halt-resume.md` § run-resume) — the run-mode skill is not loaded through the Skill tool in this lead session.

## Follow-ups (beads)
- bd-yz1rd, bd-m0hw7, bd-wqbz3 (report hardening, Sprint 262 Task 5.2); the sensitivity figure's H1/A4 lines and a batch-record section (reads.md § Secondary observations, Sprint 262).
- Suite v2 (Sprint 261, DEC-0559): the saturation and the cap fit are suite problems, answered there.
