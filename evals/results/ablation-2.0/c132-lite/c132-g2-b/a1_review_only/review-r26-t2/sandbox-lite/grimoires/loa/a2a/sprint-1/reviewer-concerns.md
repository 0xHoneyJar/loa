# Reviewer concerns (Phase 2 notes) — sprint-1 / review-r26

Change: ablation-row.sh 1.2 (defects_missed, regressions_final_green) and ablation-report.py 1.2.0
(suite_version partition, H1/A4 read states, degradation guard, degenerate pair, sensitivity H1/A4,
batch record, precision, budget-matched baseline).

Concerns to probe:
1. version_key(): docstring says 1, 1.0 and "1" are one version, but the string "1.0" is kept verbatim
   (re.fullmatch \d+ fails) so rows with suite_version "1.0" and 1 become two versions.
2. batch_record(): os.path.join(d, r["arm"]) for EVERY row of the batch including listed rows whose arm
   is not a suite arm; arm is not grammar-checked in the report (only ablation-row.sh --validate does),
   so a row with arm "../x" lists directories outside the batch dir (read-only).
3. render_per_arm(): the precision line is printed only inside `if m["false_positives_per_task"]`;
   an arm whose review rows carry false_positives null gets precision in JSON but not in the markdown.
4. AR-20 (ablation-report.bats) validates every fixture scenario with ablation-row.sh --validate except
   "present" — the only scenario that sets false_positives = 0 and plants STATUS.json.
5. analyse() applies the same --cuts/--not-run to every suite version (AR-30 asserts it) — a cut
   pre-registered for one version silently cuts the other version's section too.
6. compare(): degenerate = CATCH and n>0 and n_tasks==1 and "ids" not in identity — when every row
   is cap_failure the identity set is empty and the pair is degenerate too (zero vector); fine, but
   the degenerate_reason text says "no per-defect ids", which is misleading for the all-cap case.
7. budget_matched(): a0_cost_sum_mean / a1_cost_mean keys exist only when available; JSON shape differs.
8. h1a4(): when SENSITIVITY_ARM is not in the suite, a4_state is "no_arm" but the line still reads
   "fails — harden tasks before acting on other arms" (pre-existing wording kept).
9. ablation-row.sh --validate: has("defects_missed") and .defects_missed != null and (type != array or
   any(...)) — jq `or` short-circuits so `.defects_missed[]` on a string is never evaluated; verify.
10. --help sed range 2,101p: head line 101 is the MAX_ARG_STRLEN line; lines 102-104 ("Tested by …")
    are cut, but base 2,84p cut the same lines — pre-existing.
