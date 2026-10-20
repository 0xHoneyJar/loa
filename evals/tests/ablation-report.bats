#!/usr/bin/env bats
# =============================================================================
# evals/tests/ablation-report.bats — cycle-130 Sprint 260 Task 3.8 (AC-3.10; PRD AC-8.1–8.3;
# SDD §5.12; DEC-0393, DEC-0399, DEC-0400, DEC-0416, DEC-0417, DEC-0434, DEC-0435)
#
# ablation-report.py on planted rows: fixtures/ablation-report/gen-fixtures.py writes four
# scenarios (main, boundary, exclusions, partial; the header there lists every planted
# number) into the file tmpdir; setup_file builds the full reports once against the
# real suite file evals/suites/ablation-2.0.yaml. AR-23 … AR-30 (Sprint 262): the suite_version
# partition, the not-testable / not-yet-decidable states (bd-wqbz3), the degradation guard on
# the H1 and A4 lines, and the degenerate single-task rate-fallback pair. AR-31 … AR-35 (Sprint 262
# R3, presentation only): the sensitivity H1/A4 lines, the batch record, precision and cost per true
# defect, the budget-matched baseline. AR-36 … AR-39 (Sprint 262 R4, report 1.2.1): the type-stable
# grader-version sort and the never-fatal batch record, one run directory per row, float suite_version
# keys, and version-less rows that never reach a decision. AR-40 … AR-42 (Sprint 262 R5, report 1.2.2): the
# arm_map provenance check before any listing decision, the never-fatal batch-record computation, and
# run-directory attribution by numeric trial with the rerun fallback; AR-38 also asserts the JSON type of
# every version value. AR-43 … AR-47 (Sprint 262 audit, report 1.2.3): inconsistent defects_missed ids read
# as the rate, the sanitized never-fatal text, a non-numeric or NaN cost_usd read as 0 with a note, the
# loud allow_nan=False failure naming the key, and the arm / task_id grammar before any path is built.
# =============================================================================

setup_file() {
  TESTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$TESTS_DIR/../.." && pwd)"
  export REPO_ROOT
  export REPORT="$REPO_ROOT/evals/harness/ablation-report.py"
  export SUITE="$REPO_ROOT/evals/suites/ablation-2.0.yaml"
  export FX="$BATS_FILE_TMPDIR/fx"
  mkdir -p "$FX"
  python3 -I "$TESTS_DIR/fixtures/ablation-report/gen-fixtures.py" "$FX"
  for s in main boundary exclusions versions degraded degraded-a4 degenerate-1 degenerate-2 degenerate-ids present ids-bad c131 c131-mixed; do
    python3 -I "$REPORT" --runs "$FX/$s/runs.jsonl" --manifests "$FX/$s/manifests" --suite "$SUITE" \
      --out "$FX/$s/report.md" --json "$FX/$s/report.json" >/dev/null
  done
}

setup() {
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/ar.XXXXXX")"
}

teardown() {
  find "$T" -mindepth 1 -delete 2>/dev/null || true
  rmdir "$T" 2>/dev/null || true
}

dec() {  # dec <scenario> <arm> <jq path under the decision>
  jq -r --arg a "$2" ".decisions[] | select(.arm == \$a) | $3" "$FX/$1/report.json"
}

cmp_of() {  # cmp_of <scenario> <arm> <metric> <jq path under the comparison>
  jq -r --arg a "$2" --arg m "$3" ".decisions[] | select(.arm == \$a) | .comparisons[] | select(.metric == \$m) | $4" "$FX/$1/report.json"
}

report() {  # report <scenario> <out-prefix> [extra args]
  local s="$1" o="$2"; shift 2
  run python3 -I "$REPORT" --runs "$FX/$s/runs.jsonl" --manifests "$FX/$s/manifests" --suite "$SUITE" \
    --out "$o.md" --json "$o.json" "$@"
}

@test "AR-1 each rule branch on planted rows: -0.05 tight Keep, 0.00 at -20 % cost Remove, 0.00 similar cost Simplify, wide Inconclusive, +0.04 Investigate" {
  [ "$(dec main a2_no_sprint_plan .state)" = "keep" ]
  [ "$(cmp_of main a2_no_sprint_plan hidden_test_pass_rate .d)" = "-0.05" ]
  [ "$(cmp_of main a2_no_sprint_plan hidden_test_pass_rate '.hi < 0')" = "true" ]
  [ "$(dec main a3_one_voice .state)" = "remove" ]
  [ "$(dec main a3_one_voice '.c == -20')" = "true" ]
  [ "$(dec main a5_no_flatline .state)" = "simplify" ]
  [ "$(dec main a5_no_flatline '.c == -5')" = "true" ]
  [ "$(dec main a6_one_window .state)" = "inconclusive" ]
  [ "$(cmp_of main a6_one_window hidden_test_pass_rate '.lo < 0 and .hi > 0')" = "true" ]
  [ "$(dec main a7_effort_medium .state)" = "investigate" ]
  [ "$(cmp_of main a7_effort_medium hidden_test_pass_rate .lo)" = "0.04" ]
  grep -qF '| A2 | `a2_no_sprint_plan` | 12 tasks | -0.050 [-0.052, -0.048] | n/a (build-only) |' "$FX/main/report.md"
  grep -qF '**Investigate** | investigate: any applicable primary has lo > 0 (hidden_test_pass_rate)' "$FX/main/report.md"
}

@test "AR-2 exactly at threshold: d = -0.03 is not Keep and is Remove at c = -15 (inclusive) or Simplify; hi = 0 is not Keep (strict); w = -15 is Remove" {
  [ "$(cmp_of boundary a2_no_sprint_plan hidden_test_pass_rate .d)" = "-0.03" ]
  [ "$(cmp_of boundary a2_no_sprint_plan hidden_test_pass_rate .hi)" = "-0.03" ]
  [ "$(dec boundary a2_no_sprint_plan '.c == -15')" = "true" ]
  [ "$(dec boundary a2_no_sprint_plan .state)" = "remove" ]
  [ "$(dec boundary a5_no_flatline .state)" = "simplify" ]
  [ "$(cmp_of boundary a6_one_window hidden_test_pass_rate '.hi == 0')" = "true" ]
  [ "$(cmp_of boundary a6_one_window hidden_test_pass_rate .d)" = "-0.04" ]
  [ "$(dec boundary a6_one_window .state)" = "inconclusive" ]
  [ "$(dec boundary a6_one_window .rule)" = "inconclusive: d < -0.03 (hidden_test_pass_rate)" ]
  [ "$(dec boundary a3_one_voice '.w == -15')" = "true" ]
  [ "$(dec boundary a3_one_voice .state)" = "remove" ]
}

@test "AR-3 a cap failure scores 0 on the primary, is listed, and the labelled sensitivity figure (cap failures excluded) differs" {
  [ "$(jq -r '.cap_failures | join(",")' "$FX/exclusions/report.json")" = "excl-1-a2_no_sprint_plan-fb-01-t1" ]
  # fb-01: trials 0 (cap, the row says 0.9), 0.40, 0.40 → 0.266667 against a1's 0.40
  [ "$(cmp_of exclusions a2_no_sprint_plan hidden_test_pass_rate '.pairs[] | select(.task_id == "fb-01") | .arm_value')" = "0.266667" ]
  [ "$(cmp_of exclusions a2_no_sprint_plan hidden_test_pass_rate .d)" = "-0.011111" ]
  [ "$(jq -r '.sensitivity.rows[] | select(.arm == "a2_no_sprint_plan") | .comparisons[0].d == 0' "$FX/exclusions/report.json")" = "true" ]
  [ "$(jq -r '.sensitivity.label' "$FX/exclusions/report.json")" = "sensitivity (cap failures excluded) — no decision uses this" ]
  grep -qF '## Sensitivity figure: sensitivity (cap failures excluded) — no decision uses this' "$FX/exclusions/report.md"
  grep -qF -- '- `excl-1-a2_no_sprint_plan-fb-01-t1` (`a2_no_sprint_plan`, fb-01 t1, cap_phase IMPLEMENT, USD 12.00)' "$FX/exclusions/report.md"
}

@test "AR-4 a degraded cell is dropped from both arms (pairwise); --exclude-degraded false counts it" {
  [ "$(cmp_of exclusions a3_one_voice hidden_test_pass_rate '.pairs[] | select(.task_id == "fb-02") | .diff == 0')" = "true" ]
  [ "$(cmp_of exclusions a3_one_voice hidden_test_pass_rate '.pairs[] | select(.task_id == "fb-02") | .control_runs | join(",")')" = "excl-1-a1_full-fb-02-t1,excl-1-a1_full-fb-02-t3" ]
  [ "$(cmp_of exclusions a3_one_voice hidden_test_pass_rate '.dropped[] | .run_id')" = "excl-1-a1_full-fb-02-t2" ]
  [ "$(jq -r '.exclusions[] | select(.run_id == "excl-1-a3_one_voice-fb-02-t2") | .reason' "$FX/exclusions/report.json")" = "degraded: IMPLEMENT models_used global.anthropic.claude-sonnet-5-5" ]
  report exclusions "$T/nodeg" --exclude-degraded false
  [ "$status" -eq 0 ]
  [ "$(jq -r '.decisions[] | select(.arm == "a3_one_voice") | .comparisons[0].pairs[] | select(.task_id == "fb-02") | .diff' "$T/nodeg.json")" = "-0.243333" ]
}

@test "AR-5 an arm with 11 of 36 cells excluded (30.6 %) reads Inconclusive-by-degradation although its valid cells read +0.05 with lo > 0 (guard first, DEC-0393); excluded rows are listed" {
  [ "$(cmp_of exclusions a5_no_flatline hidden_test_pass_rate .d)" = "0.05" ]
  [ "$(cmp_of exclusions a5_no_flatline hidden_test_pass_rate '.lo > 0')" = "true" ]
  [ "$(dec exclusions a5_no_flatline .state)" = "inconclusive" ]
  [ "$(dec exclusions a5_no_flatline .label)" = "Inconclusive-by-degradation" ]
  [ "$(dec exclusions a5_no_flatline .excluded_share)" = "0.305556" ]
  [ "$(dec exclusions a5_no_flatline .rule)" = "inconclusive (degradation guard, evaluated first): excluded share 0.306 > 0.25" ]
  [ "$(jq '[.exclusions[] | select(.arm == "a5_no_flatline")] | length' "$FX/exclusions/report.json")" -eq 11 ]
  grep -qF '| `excl-1-a5_no_flatline-fb-01-t1` | `a5_no_flatline` | fb-01 | 1 | contaminated | contaminated |' "$FX/exclusions/report.md"
  grep -qF '| `excl-1-a2_no_sprint_plan-rf-01-t3` | `a2_no_sprint_plan` | rf-01 | 3 | transport_error | transport_error |' "$FX/exclusions/report.md"
}

@test "AR-6 build-only arms (A2, A4, A5, A6) are decided on the pass rate alone; all-type arms on both; a refused review-catch row is listed, never counted" {
  for a in a2_no_sprint_plan a4_no_gates a5_no_flatline a6_one_window; do
    [ "$(dec exclusions "$a" '.primaries | join(",")')" = "hidden_test_pass_rate" ]
    [ "$(dec exclusions "$a" '[.comparisons[].metric] | join(",")')" = "hidden_test_pass_rate" ]
  done
  for a in a3_one_voice a7_effort_medium; do
    [ "$(dec exclusions "$a" '.primaries | join(",")')" = "hidden_test_pass_rate,defect_catch_rate" ]
  done
  [ "$(jq -r '.listed[] | select(.run_id == "excl-1-a4_no_gates-rc-02-t1") | .reason' "$FX/exclusions/report.json")" = "not applicable: a4_no_gates does not run review-catch tasks" ]
  [ "$(dec exclusions a4_no_gates .cells_seen)" -eq 36 ]
  [ "$(dec exclusions a4_no_gates .state)" = "keep" ]
}

@test "AR-7 defects are the catch-rate unit: rc-01's 8 defects weigh 8 in the decision interval and 1 in also_report" {
  [ "$(cmp_of exclusions a7_effort_medium defect_catch_rate .unit)" = "defects" ]
  [ "$(cmp_of exclusions a7_effort_medium defect_catch_rate .n)" -eq 18 ]
  [ "$(cmp_of exclusions a7_effort_medium defect_catch_rate '.pairs[] | select(.task_id == "rc-01") | .defects')" -eq 8 ]
  [ "$(cmp_of exclusions a7_effort_medium defect_catch_rate .d)" = "-0.222222" ]
  [ "$(cmp_of exclusions a7_effort_medium defect_catch_rate .task_level.n)" -eq 4 ]
  [ "$(cmp_of exclusions a7_effort_medium defect_catch_rate .task_level.d)" = "-0.125" ]
  [ "$(cmp_of exclusions a7_effort_medium defect_catch_rate '.defect_identity | join(",")')" = "ids,rate" ]
  [ "$(dec exclusions a7_effort_medium .state)" = "keep" ]
  grep -qF 'also_report (tasks, decides nothing): d [lo, hi] = -0.125' "$FX/exclusions/report.md"
}

@test "AR-8 agent_error scores what its tree earns (DEC-0417)" {
  # bf-01: 0.50 (agent_error), 0.52, 0.52
  [ "$(cmp_of exclusions a7_effort_medium hidden_test_pass_rate '.pairs[] | select(.task_id == "bf-01") | .arm_value')" = "0.513333" ]
  [ "$(jq -r '.arms.a7_effort_medium.by_status.agent_error' "$FX/exclusions/report.json")" -eq 1 ]
}

@test "AR-9 Not run (cut) from --cuts and --not-run, a pre-declared Inconclusive-by-power, each with its figure" {
  printf '%s\n' '[{"arm":"A5","reason":"ladder rung 1","figure":"spent 1270.00 of max 1270"},' \
    '{"arm":"a6_one_window","state":"inconclusive_by_power","reason":"smoke variance","figure":"MDE 0.14 > 0.10"}]' > "$T/cuts.json"
  report main "$T/r" --cuts "$T/cuts.json" --not-run a7_effort_medium
  [ "$status" -eq 0 ]
  [ "$(jq -r '.decisions[] | select(.arm == "a5_no_flatline") | .state' "$T/r.json")" = "not_run_cut" ]
  [ "$(jq -r '.decisions[] | select(.arm == "a6_one_window") | .state' "$T/r.json")" = "inconclusive_by_power" ]
  [ "$(jq -r '.decisions[] | select(.arm == "a7_effort_medium") | .state' "$T/r.json")" = "not_run_cut" ]
  grep -qF '**Not run (cut) — spent 1270.00 of max 1270**' "$T/r.md"
  grep -qF '**Inconclusive-by-power — MDE 0.14 > 0.10**' "$T/r.md"
  grep -qF -- '- `a5_no_flatline`: Not run (cut) — reason: ladder rung 1; figure: spent 1270.00 of max 1270 (--cuts)' "$T/r.md"
  echo '[{"arm":"a9_nope","reason":"x"}]' > "$T/bad.json"
  report main "$T/r2" --cuts "$T/bad.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"cut names unknown arm a9_nope"* ]]
}

@test "AR-10 a high-variance arm whose predicates read Simplify reads Inconclusive-by-power with the MDE figure" {
  [ "$(dec exclusions a6_one_window .predicate_state)" = "simplify" ]
  [ "$(dec exclusions a6_one_window .state)" = "inconclusive_by_power" ]
  [ "$(cmp_of exclusions a6_one_window hidden_test_pass_rate '.mde > 0.10')" = "true" ]
  grep -qF '**Inconclusive-by-power — MDE 0.221 > 0.1 on hidden_test_pass_rate (n = 12 tasks)**' "$FX/exclusions/report.md"
}

@test "AR-11 H1 established and A4 holds (main); H1 not established and A4 fails (boundary)" {
  [ "$(jq -r '.h1.line' "$FX/main/report.json")" = "H1: established" ]
  [ "$(jq -r '.a4.line' "$FX/main/report.json")" = "A4 sensitivity: holds" ]
  grep -qF '**H1: established** — a1_full − a0_bare: hidden_test_pass_rate +0.200 [+0.200, +0.200] (n = 12 tasks)' "$FX/main/report.md"
  [ "$(jq -r '.h1.line' "$FX/boundary/report.json")" = "H1: not established — halt before promotion" ]
  [ "$(jq -r '.a4.line' "$FX/boundary/report.json")" = "A4 sensitivity: fails — harden tasks before acting on other arms" ]
  grep -qF 'Rule (rules.h1): "a1_full beats a0_bare on at least one primary with the interval excluding zero, else halt before promotion"' "$FX/boundary/report.md"
}

@test "AR-12 the expected-false-positive sentence and the Method section quoting the suite rules block verbatim" {
  grep -qF 'Expected false positives at level 0.90 over 9 components: 9 × (1 − 0.90) / 2 = 0.45 one-sided per direction (0.90 in either direction); no multiple-comparison correction is applied (multiple_comparisons: none).' "$FX/main/report.md"   # 9 = a2 … a7 + the three cycle-131 control arms; a1_full_openmount is eval_only and not a component
  grep -qF 'Evaluation-only arms (not components): a1_full_openmount (0 rows) — read by their own pre-registered contrast, never by a decision here.' "$FX/main/report.md"   # review r1 DISS-C-004
  python3 -I - "$SUITE" "$FX/main/report.md" <<'PY'
import re, sys
suite = open(sys.argv[1], encoding="utf-8").read().splitlines()
start = next(i for i, l in enumerate(suite) if l.startswith("rules:"))
end = next((i for i in range(start + 1, len(suite)) if suite[i].strip() and not suite[i][0].isspace() and not suite[i].startswith("#")), len(suite))
block = "\n".join(suite[start:end]).rstrip()
md = open(sys.argv[2], encoding="utf-8").read()
method = md[md.index("## Method"):]
assert "```yaml\n" + block + "\n```" in method, "rules block not quoted verbatim"
PY
}

@test "AR-13 smoke rows (manifest smoke: true) are listed and never decided" {
  [ "$(jq '[.listed[] | select(.reason == "smoke batch smoke-260")] | length' "$FX/main/report.json")" -eq 24 ]
  [ "$(jq -r '.arms.a2_no_sprint_plan.rows' "$FX/main/report.json")" -eq 36 ]
  [ "$(dec main a2_no_sprint_plan .state)" = "keep" ]
  grep -qF '`smoke-260` (smoke: listed, never decided)' "$FX/main/report.md"
}

@test "AR-14 --partial prints the PARTIAL header (exit 0 when a comparison is decidable, 1 with none; the report is still written)" {
  report main "$T/p" --partial
  [ "$status" -eq 0 ]
  grep -qxF '**PARTIAL — rows so far, no decision is final**' "$T/p.md"
  [ "$(jq -r .partial "$T/p.json")" = "true" ]
  report partial "$T/q" --partial
  [ "$status" -eq 1 ]
  [ -s "$T/q.md" ]
  grep -qF 'PARTIAL — rows so far, no decision is final' "$T/q.md"
  run python3 -I "$REPORT" --runs "$FX/partial/runs.jsonl" --manifests "$FX/partial/manifests" --suite "$SUITE" --out "$T/q2.md"
  [ "$status" -eq 0 ]
  ! grep -qF 'PARTIAL' "$T/q2.md" || false
  grep -qF 'H1: not yet decidable (no pair)' "$T/q2.md"
}

@test "AR-15 schema_version 2, a missing schema_version or a non-JSON line stops the report (exit 2, naming the row); nothing is written" {
  { head -3 "$FX/main/runs.jsonl"; head -1 "$FX/main/runs.jsonl" | jq -c '.schema_version = 2 | .run_id = "planted-v2"'; } > "$T/v2.jsonl"
  run python3 -I "$REPORT" --runs "$T/v2.jsonl" --manifests "$FX/main/manifests" --suite "$SUITE" --out "$T/v2.md"
  [ "$status" -eq 2 ]
  [[ "$output" == *"$T/v2.jsonl:4: row planted-v2 has schema_version 2"* ]]
  [ ! -e "$T/v2.md" ]
  head -1 "$FX/main/runs.jsonl" | jq -c 'del(.schema_version)' > "$T/nov.jsonl"
  run python3 -I "$REPORT" --runs "$T/nov.jsonl" --manifests "$FX/main/manifests" --suite "$SUITE" --out "$T/nov.md"
  [ "$status" -eq 2 ]
  [[ "$output" == *"has no schema_version (1 required)"* ]]
  echo '{not json' > "$T/bad.jsonl"
  run python3 -I "$REPORT" --runs "$T/bad.jsonl" --manifests "$FX/main/manifests" --suite "$SUITE" --out "$T/bad.md"
  [ "$status" -eq 2 ]
  [[ "$output" == *"$T/bad.jsonl:1: line is not valid JSON"* ]]
}

@test "AR-16 deterministic for a seed: two runs are byte-identical; another seed moves an interval" {
  report main "$T/a"
  [ "$status" -eq 0 ]
  report main "$T/b"
  [ "$status" -eq 0 ]
  cmp "$T/a.md" "$T/b.md"
  cmp "$T/a.json" "$T/b.json"
  cmp "$T/a.md" "$FX/main/report.md"
  report main "$T/c" --seed 7
  [ "$status" -eq 0 ]
  [ "$(jq -r '.h1.comparisons[1].hi' "$T/c.json")" != "$(jq -r '.h1.comparisons[1].hi' "$FX/main/report.json")" ]
}

@test "AR-17 A8 reads component-absent with the suite's evidence text" {
  ev="$(yq -r '.arms[] | select(.id == "a8_no_ceremonies") | .evidence' "$SUITE")"
  [ -n "$ev" ]
  [ "$(jq -r '.absent[0].state' "$FX/main/report.json")" = "component_absent" ]
  [ "$(jq -r '.absent[0].evidence' "$FX/main/report.json")" = "$ev" ]
  grep -qF "| A8 | \`a8_no_ceremonies\` | — | — | — | — | — | — | **component-absent** | $ev | 0 |" "$FX/main/report.md"
}

@test "AR-18 the header cites suite_version, source commit, suite manifest sha256, batch seed and pre-registration; cells name their rows collapsed" {
  # the suite file's own suite_version (1 for suite v1, 2 since Sprint 261)
  grep -qF -- '- suite: `'"$SUITE"'` (name ablation-2.0, suite_version '"$(yq -r .suite_version "$SUITE")"')' "$FX/main/report.md"
  grep -qF -- '- source commit(s): 1111111111111111111111111111111111111111' "$FX/main/report.md"
  grep -qF -- '- suite manifest sha256: 30e1f2ad' "$FX/main/report.md"
  grep -qF 'shuffle_seed 20261015, pre_registration_ref NOTES.md § Decision Log 2026-10-15T09:00:00Z' "$FX/main/report.md"
  grep -qF '| fb-01 | 0.345 | 0.400 | -0.055 | `priority-1-a2_no_sprint_plan-fb-01-t1…t3` | `priority-1-a1_full-fb-01-t1…t3` |' "$FX/main/report.md"
  grep -qF '`excl-1-a3_one_voice-fb-02-t1,t3`' "$FX/exclusions/report.md"
}

@test "AR-19 usage and provenance errors exit 2; only --out and --json are written" {
  run python3 -I "$REPORT" --runs "$FX/main/runs.jsonl" --manifests "$FX/main/manifests" --out "$T/x.md"
  [ "$status" -eq 2 ]
  run python3 -I "$REPORT" --runs "$FX/main/runs.jsonl" --manifests "$T/none" --suite "$SUITE" --out "$T/x.md"
  [ "$status" -eq 2 ]
  mkdir -p "$T/mm/priority-1"
  jq '.arm_map["priority-1-a2_no_sprint_plan-fb-01-t1"] = "a3_one_voice"' "$FX/main/manifests/priority-1/MANIFEST.json" > "$T/mm/priority-1/MANIFEST.json"
  run python3 -I "$REPORT" --runs "$FX/main/runs.jsonl" --manifests "$T/mm" --suite "$SUITE" --out "$T/x.md"
  [ "$status" -eq 2 ]
  [[ "$output" == *"arm a2_no_sprint_plan disagrees with"* ]]
  jq '.schema_version = 2' "$FX/main/manifests/priority-1/MANIFEST.json" > "$T/mm/priority-1/MANIFEST.json"
  run python3 -I "$REPORT" --runs "$FX/main/runs.jsonl" --manifests "$T/mm" --suite "$SUITE" --out "$T/x.md"
  [ "$status" -eq 2 ]
  [[ "$output" == *"has schema_version 2"* ]]
  ln -s "$T/target" "$T/link.md"
  run python3 -I "$REPORT" --runs "$FX/main/runs.jsonl" --manifests "$FX/main/manifests" --suite "$SUITE" --out "$T/link.md"
  [ "$status" -eq 2 ]
  [ ! -e "$T/target" ]
  mkdir "$T/w"
  before="$(cd "$FX" && find . | LC_ALL=C sort)"
  (cd "$T/w" && python3 -I "$REPORT" --runs "$FX/main/runs.jsonl" --manifests "$FX/main/manifests" --suite "$SUITE" --out "$T/w/o.md" --json "$T/w/o.json" >/dev/null)
  [ "$(cd "$T/w" && find . -type f | LC_ALL=C sort | tr '\n' ' ')" = "./o.json ./o.md " ]
  [ "$(cd "$FX" && find . | LC_ALL=C sort)" = "$before" ]
}

@test "AR-20 the planted rows hold the real row shape (ablation-row.sh --validate)" {
  for s in main boundary exclusions partial versions degraded degraded-a4 degenerate-1 degenerate-2 degenerate-ids; do
    run bash "$REPO_ROOT/evals/harness/ablation-row.sh" --validate "$FX/$s/runs.jsonl" --allow-ungraded
    [ "$status" -eq 0 ]
  done
}

@test "AR-21 a rerun supersedes an excluded row in the same cell (the cell stays valid, the row is listed)" {
  cp -R "$FX/exclusions" "$T/ex"
  grep -F '"run_id": "excl-1-a4_no_gates-fb-03-t2"' "$FX/exclusions/runs.jsonl" \
    | jq -c '.run_id = "excl-1-a4_no_gates-fb-03-t2-first" | .status = "infrastructure_error" | .hidden_test_pass_rate = null' > "$T/first.jsonl"
  cat "$T/first.jsonl" "$FX/exclusions/runs.jsonl" > "$T/ex/runs.jsonl"
  run python3 -I "$REPORT" --runs "$T/ex/runs.jsonl" --manifests "$T/ex/manifests" --suite "$SUITE" --out "$T/r.md" --json "$T/r.json"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.exclusions[] | select(.run_id == "excl-1-a4_no_gates-fb-03-t2-first") | .reason' "$T/r.json")" = "infrastructure_error; superseded by excl-1-a4_no_gates-fb-03-t2" ]
  [ "$(jq -r '.decisions[] | select(.arm == "a4_no_gates") | .excluded_cells' "$T/r.json")" -eq 0 ]
  [ "$(jq -r '.decisions[] | select(.arm == "a4_no_gates") | .comparisons[0].d' "$T/r.json")" = "-0.1" ]
}

@test "AR-22 the degradation guard also preempts Keep: the same 30.6 % excluded arm at -0.10 (hi < 0) reads Inconclusive-by-degradation" {
  cp -R "$FX/exclusions" "$T/ex"
  jq -c 'if .arm == "a5_no_flatline" and .status == "completed" then .hidden_test_pass_rate -= 0.15 else . end' \
    "$FX/exclusions/runs.jsonl" > "$T/ex/runs.jsonl"
  run python3 -I "$REPORT" --runs "$T/ex/runs.jsonl" --manifests "$T/ex/manifests" --suite "$SUITE" --out "$T/r.md" --json "$T/r.json"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.decisions[] | select(.arm == "a5_no_flatline") | .comparisons[0] | (.d | . * 1000 | round) == -100 and .hi < 0' "$T/r.json")" = "true" ]
  [ "$(jq -r '.decisions[] | select(.arm == "a5_no_flatline") | .label' "$T/r.json")" = "Inconclusive-by-degradation" ]
  grep -qF 'degradation guard first' "$T/r.md"
}

@test "AR-23 two suite_versions are never pooled: main sections on v2 (catch-rate H1, pass rate and A4 not testable), v1 in its own section; --suite-version 1 flips the primary" {
  J="$FX/versions/report.json"; M="$FX/versions/report.md"
  [ "$(jq -r .primary_suite_version "$J")" = "2" ]
  [ "$(jq -r '.by_suite_version | keys | join(",")' "$J")" = "1,2" ]
  [ "$(jq -r .h1.line "$J")" = "H1: established" ]
  [ "$(jq -r '.h1.comparisons[] | select(.metric == "hidden_test_pass_rate") | .read' "$J")" = "not_testable" ]
  [ "$(jq -r '.h1.comparisons[] | select(.metric == "defect_catch_rate") | .d' "$J")" = "0.444444" ]
  [ "$(jq -r .a4.line "$J")" = "A4 sensitivity: not testable on suite_version 2 — no admissible build task" ]
  [ "$(jq -r .a4.state "$J")" = "not_testable" ]
  # the same task ids and trials in both versions: no duplicate-cell collision, no pooled rows
  [ "$(jq '.exclusions | length' "$J")" -eq 0 ]
  [ "$(jq -r .arms.a1_full.rows "$J")" -eq 12 ]
  [ "$(jq -r '.by_suite_version["1"].arms.a1_full.rows' "$J")" -eq 48 ]
  [ "$(jq -r '.by_suite_version["1"].h1.line' "$J")" = "H1: established" ]
  [ "$(jq -r '.by_suite_version["1"].a4.line' "$J")" = "A4 sensitivity: holds" ]
  [ "$(jq -r '.by_suite_version["2"].h1.line' "$J")" = "$(jq -r .h1.line "$J")" ]
  [ "$(jq -r '.by_suite_version["1"].decisions | length' "$J")" -eq 9 ]   # the nine components (cycle-131 arms included; eval_only excluded)
  grep -qF 'hidden_test_pass_rate: not testable on suite_version 2 — no admissible task' "$M"
  grep -qxF '## Suite version 1 (batches: ver-v1) — reported separately, never pooled' "$M"
  grep -qF -- '  - suite_version 2 (primary: the main sections): 24 rows; batches ver-v2; suite manifest sha256 ddd200b3' "$M"
  grep -qF -- '  - suite_version 1 (reported separately, never pooled): 132 rows; batches ver-v1; suite manifest sha256 30e1f2ad' "$M"
  ! grep -qF 'DRIFT' "$M" || false
  # the v1 section carries its own H1 and A4 lines after the main sections
  awk '/^## Suite version 1 /{f=1} f' "$M" | grep -qF '**H1: established** — a1_full − a0_bare: hidden_test_pass_rate +0.200 [+0.200, +0.200] (n = 12 tasks)'
  awk '/^## Suite version 1 /{f=1} f' "$M" | grep -qF '**A4 sensitivity: holds**'
  report versions "$T/v1" --suite-version 1
  [ "$status" -eq 0 ]
  [ "$(jq -r .primary_suite_version "$T/v1.json")" = "1" ]
  [ "$(jq -r .a4.line "$T/v1.json")" = "A4 sensitivity: holds" ]
  [ "$(jq -r .arms.a1_full.rows "$T/v1.json")" -eq 48 ]
  grep -qxF '## Suite version 2 (batches: ver-v2) — reported separately, never pooled' "$T/v1.md"
  report versions "$T/v3" --suite-version 3
  [ "$status" -eq 2 ]
  [[ "$output" == *"--suite-version 3: no row has that suite_version (present: 1, 2)"* ]]
}

@test "AR-24 a row without suite_version among two versions stops the report (exit 2); a single-version input without the field works as before" {
  jq -c 'if .run_id == "ver-v2-a1_full-rc-01-t1" then del(.suite_version) else . end' "$FX/versions/runs.jsonl" > "$T/miss.jsonl"
  run python3 -I "$REPORT" --runs "$T/miss.jsonl" --manifests "$FX/versions/manifests" --suite "$SUITE" --out "$T/miss.md"
  [ "$status" -eq 2 ]
  [[ "$output" == *"row ver-v2-a1_full-rc-01-t1 has no suite_version while the rows hold suite_version 1, 2"* ]]
  [ ! -e "$T/miss.md" ]
  jq -c 'del(.suite_version)' "$FX/main/runs.jsonl" > "$T/one.jsonl"
  run python3 -I "$REPORT" --runs "$T/one.jsonl" --manifests "$FX/main/manifests" --suite "$SUITE" --out "$T/one.md" --json "$T/one.json"
  [ "$status" -eq 0 ]
  [ "$(jq -r .h1.line "$T/one.json")" = "H1: established" ]
  [ "$(jq -c '[.decisions[] | .state]' "$T/one.json")" = "$(jq -c '[.decisions[] | .state]' "$FX/main/report.json")" ]
}

@test "AR-25 --partial with no pair reads 'not yet decidable (no pair)', exits 1 and prints no halt phrase (bd-wqbz3)" {
  report partial "$T/p" --partial
  [ "$status" -eq 1 ]
  [ "$(jq -r .h1.line "$T/p.json")" = "H1: not yet decidable (no pair)" ]
  [ "$(jq -r .h1.state "$T/p.json")" = "not_yet_decidable" ]
  ! grep -qF 'halt before promotion**' "$T/p.md" || false
  ! grep -qF 'harden tasks before acting on other arms**' "$T/p.md" || false
  # a4 rows without a1 rows: the A4 line has a task but no pair
  cp -R "$FX/partial" "$T/pa"
  jq -c '.arm = "a4_no_gates" | .run_id = (.run_id | sub("a0_bare"; "a4_no_gates"))' "$FX/partial/runs.jsonl" >> "$T/pa/runs.jsonl"
  run python3 -I "$REPORT" --runs "$T/pa/runs.jsonl" --manifests "$T/pa/manifests" --suite "$SUITE" --out "$T/pa.md" --json "$T/pa.json" --partial
  [ "$status" -eq 1 ]
  [ "$(jq -r .a4.line "$T/pa.json")" = "A4 sensitivity: not yet decidable (no pair)" ]
  [ "$(jq -r .h1.line "$T/pa.json")" = "H1: not yet decidable (no pair)" ]
}

@test "AR-26 the degradation guard governs H1: 9 of 12 a1 review rows degraded read inconclusive by degradation; --exclude-degraded false lets the same rows establish H1" {
  J="$FX/degraded/report.json"
  [ "$(jq -r .h1.line "$J")" = "H1: inconclusive by degradation — not established" ]
  [ "$(jq -r .h1.established "$J")" = "false" ]
  [ "$(jq -r '.h1.comparisons[] | select(.metric == "defect_catch_rate") | .read' "$J")" = "inconclusive_by_degradation" ]
  grep -qF 'defect_catch_rate inconclusive by degradation (a1_full excluded share 0.750 > 0.25)' "$FX/degraded/report.md"
  ! grep -qF '**H1: established**' "$FX/degraded/report.md" || false
  report degraded "$T/nd" --exclude-degraded false
  [ "$status" -eq 0 ]
  [ "$(jq -r .h1.line "$T/nd.json")" = "H1: established" ]
  [ "$(jq -r '.h1.comparisons[] | select(.metric == "defect_catch_rate") | .read' "$T/nd.json")" = "tested" ]
}

@test "AR-27 the degradation guard governs the A4 line and H1's pass rate (a1 12 of 36 build cells degraded, share 0.333); --exclude-degraded false: A4 holds, H1 established" {
  J="$FX/degraded-a4/report.json"
  [ "$(jq -r .a4.line "$J")" = "A4 sensitivity: inconclusive by degradation (a1_full excluded share 0.333 > 0.25) — not decided" ]
  [ "$(jq -r .a4.holds "$J")" = "false" ]
  [ "$(jq -r .h1.line "$J")" = "H1: inconclusive by degradation — not established" ]
  [ "$(jq -r '.h1.comparisons[] | select(.metric == "defect_catch_rate") | .read' "$J")" = "not_testable" ]
  report degraded-a4 "$T/nd" --exclude-degraded false
  [ "$status" -eq 0 ]
  [ "$(jq -r .a4.line "$T/nd.json")" = "A4 sensitivity: holds" ]
  [ "$(jq -r .h1.line "$T/nd.json")" = "H1: established" ]
}

@test "AR-28 a single-task rate-fallback catch pair is degenerate: flagged, and read as no valid pair by H1 and by the component decision" {
  J="$FX/degenerate-1/report.json"
  [ "$(jq -r '.h1.comparisons[] | select(.metric == "defect_catch_rate") | .degenerate' "$J")" = "true" ]
  [ "$(jq -r '.h1.comparisons[] | select(.metric == "defect_catch_rate") | .lo > 0' "$J")" = "true" ]
  [[ "$(jq -r '.h1.comparisons[] | select(.metric == "defect_catch_rate") | .degenerate_reason' "$J")" == "valid pairs on one task (rc-04) with no per-defect ids"* ]]
  [ "$(jq -r .h1.line "$J")" = "H1: not yet decidable (no pair)" ]
  [ "$(cmp_of degenerate-1 a3_one_voice defect_catch_rate .degenerate)" = "true" ]
  [ "$(dec degenerate-1 a3_one_voice .rule)" = "inconclusive: no valid pair (hidden_test_pass_rate, defect_catch_rate: degenerate)" ]
  [ "$(dec degenerate-1 a3_one_voice .decidable)" = "false" ]
  grep -qF 'defect_catch_rate +0.500 [+0.500, +0.500] (degenerate) (n = 4 defects) — read as no valid pair' "$FX/degenerate-1/report.md"
  grep -qF '  - degenerate (read as no valid pair): valid pairs on one task (rc-04)' "$FX/degenerate-1/report.md"
}

@test "AR-29 not degenerate with pairs on two tasks, or with per-defect ids on one task (report 1.3: three valid cells read insufficient)" {
  [ "$(jq -r '.h1.comparisons[] | select(.metric == "defect_catch_rate") | .degenerate' "$FX/degenerate-2/report.json")" = "false" ]
  [ "$(jq -r .h1.line "$FX/degenerate-2/report.json")" = "H1: established" ]
  [ "$(jq -r '.h1.comparisons[] | select(.metric == "defect_catch_rate") | .degenerate' "$FX/degenerate-ids/report.json")" = "false" ]
  # report 1.3 (FR-6): one task × 3 trials is 3 valid cells < 4 — insufficient (1.2.x read it tested)
  [ "$(jq -r '.h1.comparisons[] | select(.metric == "defect_catch_rate") | .read' "$FX/degenerate-ids/report.json")" = "insufficient" ]
  [ "$(jq -r .h1.line "$FX/degenerate-ids/report.json")" = "H1: insufficient — fewer than 4 valid cells" ]
  ! grep -qF '(degenerate)' "$FX/degenerate-2/report.md" || false
  # a build primary is never degenerate (one task, one value per task)
  [ "$(jq '[.. | objects | select(.metric == "hidden_test_pass_rate") | select(.degenerate == true)] | length' "$FX/main/report.json")" -eq 0 ]
}

@test "AR-30 --not-run still applies where A4 is not testable; --partial exits 0 when H1 is decided on the remaining primary" {
  report versions "$T/c" --not-run a4_no_gates --partial
  [ "$status" -eq 0 ]
  [ "$(jq -r '.decisions[] | select(.arm == "a4_no_gates") | .state' "$T/c.json")" = "not_run_cut" ]
  [ "$(jq -r .a4.line "$T/c.json")" = "A4 sensitivity: not testable on suite_version 2 — no admissible build task" ]
  [ "$(jq -r '.by_suite_version["1"].decisions[] | select(.arm == "a4_no_gates") | .state' "$T/c.json")" = "not_run_cut" ]
}

@test "AR-31 the sensitivity figure prints the H1 and A4 lines per suite version, prefixed and labelled as deciding nothing" {
  J="$FX/versions/report.json"; M="$FX/versions/report.md"
  [ "$(jq -r .sensitivity.h1.state "$J")" = "established" ]
  [ "$(jq -r .sensitivity.h1.line "$J")" = "sensitivity (decides nothing): H1: established" ]
  [ "$(jq -r .sensitivity.a4.state "$J")" = "not_testable" ]
  [ "$(jq -r .sensitivity.treatment "$J")" = "cap failures excluded, degraded rows included" ]
  [ "$(jq -r '.sensitivity.h1 | keys | join(",")' "$J")" = "$(jq -r '.h1 | keys | join(",")' "$J")" ]
  [ "$(jq -r '.by_suite_version["1"].sensitivity.a4.state' "$J")" = "holds" ]
  awk '/^## Sensitivity figure/{f=1} /^## Budget-matched/{f=0} f' "$M" | grep -qF '**sensitivity (decides nothing): H1: established** — a1_full − a0_bare: hidden_test_pass_rate: not testable on suite_version 2'
  awk '/^## Suite version 1 /{f=1} f' "$M" | grep -qF '**sensitivity (decides nothing): A4 sensitivity: holds** — a4_no_gates − a1_full: hidden_test_pass_rate -0.100 [-0.100, -0.100] (n = 12 tasks) (cap failures excluded, degraded rows included)'
  awk '/^## Suite version 1 /{f=1} f' "$M" | grep -qF '#### H1 and A4 lines, sensitivity (cap failures excluded, degraded rows included; decides nothing)'
  # degraded rows included: the main H1 is inconclusive by degradation, the sensitivity H1 is established
  [ "$(jq -r .h1.state "$FX/degraded/report.json")" = "inconclusive_by_degradation" ]
  [ "$(jq -r .sensitivity.h1.state "$FX/degraded/report.json")" = "established" ]
  [ "$(jq -r '.sensitivity.h1.comparisons[] | select(.metric == "defect_catch_rate") | .read' "$FX/degraded/report.json")" = "tested" ]
}

@test "AR-32 the batch record reads STATUS.json beside MANIFEST.json and grade.json grader versions; a batch without STATUS.json and missing run dirs are tolerated" {
  J="$FX/present/report.json"; M="$FX/present/report.md"
  b() { jq -r --arg b "$1" ".batches[] | select(.batch == \$b) | $2" "$J"; }
  [ "$(b pr-2 .state)" = "complete" ]
  [ "$(b pr-2 .trials_planned)" = "20" ]
  [ "$(b pr-2 .trials_rowed)" = "18" ]
  [ "$(b pr-2 .spend.spent_usd)" = "70.5" ]
  [ "$(b pr-2 .rerowed)" = "3" ]
  [ "$(b pr-2 '.rerowed_tally["contaminated→cap_failure"]')" = "1" ]
  [ "$(b pr-2 '.rerun_tally["transport_error→completed"]')" = "1" ]
  [ "$(b pr-2 .outage_history)" = "2" ]
  [ "$(b pr-2 .drift_cleared)" = "1" ]
  [ "$(b pr-2 '.paused_arms | join(",")')" = "a3_one_voice" ]
  [ "$(b pr-2 '.grader_versions | to_entries | map("\(.key)=\(.value)") | join(",")')" = "1.2.11=1,1.2.5=1,n/a=16" ]
  [ "$(b pr-2 .run_dirs_missing)" = "15" ]
  [ "$(b pr-1 .status_note)" = "no STATUS.json" ]
  [ "$(b pr-1 .suite_version)" = "1" ]
  grep -qF '## Batch record' "$M"
  grep -qF '| `pr-2` | complete | 20 / 18 | 69.00 / 1.50 / 70.50 / 100.00 | global.anthropic.claude-haiku-4-5-20251001-v1:0: runs 2, output tokens 900 | 3 (completed→completed ×2, contaminated→cap_failure ×1) | 1 (transport_error→completed ×1) | 1 | 2 |' "$M"
  grep -qF '| a3_one_voice | 1.2.5 ×1, 1.2.11 ×1, n/a ×16; no run dir ×15 |' "$M"
  grep -qF '| `pr-1` | no STATUS.json | — / 72 |' "$M"
  awk '/^## Batch record/{f=1} /^## Method/{f=0} f' "$M" | grep -qF '### suite_version 1'
  # the report reads, never writes, beside the manifests
  [ ! -e "$FX/present/manifests/pr-1/STATUS.json" ]
}

@test "AR-33 precision and cost per true defect per review-catch arm (informational): false positives, none, and zero caught → null" {
  J="$FX/present/report.json"
  [ "$(jq -r '.arms.a0_bare | "\(.precision) \(.usd_per_true_defect) \(.true_defects) \(.flagged_regions)"' "$J")" = "0.647059 0.545455 11 17" ]
  [ "$(jq -r '.arms.a1_full | "\(.precision) \(.usd_per_true_defect) \(.true_defects) \(.flagged_regions)"' "$J")" = "1.0 2.222222 27 27" ]
  [ "$(jq -r '.arms.a3_one_voice | "\(.precision) \(.usd_per_true_defect) \(.true_defects)"' "$J")" = "null null 0" ]
  [ "$(jq -r '.arms.a2_no_sprint_plan.precision' "$J")" = "null" ]
  grep -qF -- '- precision (informational, decides nothing): 0.647 = true defects 11 / flagged regions 17 (defects caught + false positives over 6 valid review-catch rows); cost per true defect caught: USD 0.55' "$FX/present/report.md"
  grep -qF 'cost per true defect caught: n/a' "$FX/present/report.md"
}

@test "AR-34 budget-matched baseline: the a0 union beats every single a0 trial; rate fallback without ids; a version without review rows reads not available" {
  J="$FX/present/report.json"; M="$FX/present/report.md"
  t() { jq -r --arg t "$1" ".budget_matched.tasks[] | select(.task_id == \$t) | $2" "$J"; }
  [ "$(jq -r .budget_matched.suite_version "$J")" = "2" ]
  [ "$(t rc-01 '"\(.a0_union) \(.a0_cost_sum) \(.a1_mean) \(.a1_cost_mean) \(.diff) \(.method)"')" = "1.0 3.0 0.875 10.0 -0.125 defect union" ]
  # no single a0 trial of rc-01 caught more than half
  [ "$(jq -r '[.[] | select(.arm == "a0_bare" and .task_id == "rc-01") | .defect_catch_rate] | max' <(jq -s . "$FX/present/runs.jsonl"))" = "0.5" ]
  [ "$(t rc-02 .method)" = "rate fallback" ]
  [ "$(t rc-02 .a0_union)" = "0.5" ]
  [ "$(jq -r '"\(.budget_matched.a0_union_mean) \(.budget_matched.a1_mean)"' "$J")" = "0.75 0.9375" ]
  [ "$(jq -r .budget_matched.note "$J")" = "3 a0_bare trials cost USD 3.00 vs one a1_full trial USD 10.00 (task means over 2 tasks)" ]
  grep -qF '## Budget-matched baseline (suite_version 2; informational, decides nothing)' "$M"
  grep -qF '| rc-01 | 3 | 1.000 | 3.00 | 3 | 0.875 | 10.00 | -0.125 | defect union |' "$M"
  grep -qF '| rc-02 | 3 | 0.500 | 3.00 | 3 | 1.000 | 10.00 | +0.500 | rate fallback |' "$M"
  [ "$(jq -r '.by_suite_version["1"].budget_matched.available' "$J")" = "false" ]
  awk '/^## Suite version 1 /{f=1} f' "$M" | grep -qF -- '- not available on suite_version 1 — no valid a0_bare and a1_full review-catch rows'
}

@test "AR-35 the presentation items change no decision, H1/A4 state or existing number" {
  for s in main boundary exclusions versions degraded; do
    python3 -I - "$FX/$s/report.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for k in ("budget_matched", "batches"):
    assert k in d, k
assert d["sensitivity"]["h1"]["state"] and d["sensitivity"]["a4"]["state"]
PY
  done
  # the main H1 line ignores the sensitivity read: degraded stays inconclusive by degradation
  [ "$(jq -r .h1.line "$FX/degraded/report.json")" = "H1: inconclusive by degradation — not established" ]
  [ "$(jq -r '.decisions[] | select(.arm == "a3_one_voice") | .state' "$FX/present/report.json")" = "keep" ]
}

@test "AR-36 grader versions 1.2.0, 1.2.0-rc1 and an ungraded run dir: the report is written, the tally lists all three (n/a last), no traceback" {
  report graders "$T/g"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Traceback"* ]]
  [ -s "$T/g.md" ] && [ -s "$T/g.json" ]
  b() { jq -r --arg b "$1" ".batches[] | select(.batch == \$b) | $2" "$T/g.json"; }
  [ "$(b gr-mixed '.grader_versions | to_entries | map("\(.key)=\(.value)") | join(",")')" = "1.2.0=1,1.2.0-rc1=1,n/a=1" ]
  [ "$(b gr-mixed .run_dirs_missing)" = "0" ]
  [ "$(b gr-mixed .note)" = "null" ]
  grep -qF '| `gr-mixed` | no STATUS.json | — / 3 | — | — | — | — | — | — | — | — | 1.2.0 ×1, 1.2.0-rc1 ×1, n/a ×1 |' "$T/g.md"
}

@test "AR-37 one run directory per row: a rerun row reads its own -r<k> once (run_id match beats a higher graded sibling); a row without a directory is n/a ×1 and run_dirs_missing 1" {
  report graders "$T/g"
  [ "$status" -eq 0 ]
  b() { jq -r --arg b "$1" ".batches[] | select(.batch == \$b) | $2" "$T/g.json"; }
  [ "$(b gr-rerun '.grader_versions | to_entries | map("\(.key)=\(.value)") | join(",")')" = "1.2.11=1" ]
  [ "$(b gr-rerun .run_dirs_missing)" = "0" ]
  [ "$(b gr-missing '.grader_versions | to_entries | map("\(.key)=\(.value)") | join(",")')" = "n/a=1" ]
  [ "$(b gr-missing .run_dirs_missing)" = "1" ]
  # every tally sums to the batch's rows
  [ "$(jq '[.batches[] | ([.grader_versions[]] | add) == .trials_rowed] | all' "$T/g.json")" = "true" ]
  # without a run_id match the highest graded rerun is read
  jq -c 'select(.batch == "gr-rerun")' "$FX/graders/runs.jsonl" > "$T/rr.jsonl"
  cp -R "$FX/graders/manifests" "$T/man"
  printf '{"run_id": "elsewhere"}\n' > "$T/man/gr-rerun/a0_bare/rc-01-t1-r2/meta/pipeline.json"
  run python3 -I "$REPORT" --runs "$T/rr.jsonl" --manifests "$T/man" --suite "$SUITE" --out "$T/rr.md" --json "$T/rr.json"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.batches[] | select(.batch == "gr-rerun") | .grader_versions | to_entries | map("\(.key)=\(.value)") | join(",")' "$T/rr.json")" = "9.9.9=1" ]
}

@test "AR-38 suite_version 2 and 2.1 are two versions (keys 2 and 2.1, never pooled, 2.1 primary); --suite-version 2.0 selects 2; true and \"\" are absent" {
  report versions-float "$T/f"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.by_suite_version | keys | join(",")' "$T/f.json")" = "2,2.1" ]
  [ "$(jq -r .primary_suite_version "$T/f.json")" = "2.1" ]
  [ "$(jq -r .arms.a1_full.rows "$T/f.json")" -eq 12 ]
  [ "$(jq -r '.by_suite_version["2"].arms.a1_full.rows' "$T/f.json")" -eq 12 ]
  [ "$(jq -r '.h1.comparisons[] | select(.metric == "defect_catch_rate") | .d' "$T/f.json")" = "0.222222" ]
  [ "$(jq -r '.by_suite_version["2"].h1.comparisons[] | select(.metric == "defect_catch_rate") | .d' "$T/f.json")" = "0.444444" ]
  grep -qxF '## Suite version 2 (batches: vf-2) — reported separately, never pooled' "$T/f.md"
  report versions-float "$T/f20" --suite-version 2.0
  [ "$status" -eq 0 ]
  [ "$(jq -r .primary_suite_version "$T/f20.json")" = "2" ]
  report versions-float "$T/f21" --suite-version 2.1
  [ "$status" -eq 0 ]
  [ "$(jq -r .primary_suite_version "$T/f21.json")" = "2.1" ]
  report versions-float "$T/f22" --suite-version 2.2
  [ "$status" -eq 2 ]
  [[ "$output" == *"--suite-version 2.2: no row has that suite_version (present: 2, 2.1)"* ]]
  for v in true '""' '"  "'; do
    jq -c --argjson v "$v" 'if .run_id == "vf-2-a1_full-rc-01-t1" then .suite_version = $v else . end' \
      "$FX/versions-float/runs.jsonl" > "$T/abs.jsonl"
    run python3 -I "$REPORT" --runs "$T/abs.jsonl" --manifests "$FX/versions-float/manifests" --suite "$SUITE" --out "$T/abs.md"
    [ "$status" -eq 2 ]
    [[ "$output" == *"row vf-2-a1_full-rc-01-t1 has no suite_version while the rows hold suite_version 2, 2.1"* ]]
  done
  # report 1.2.2: every JSON version value is typed like primary_suite_version (int / float / string / null)
  [ "$(jq -r '.primary_suite_version | type' "$T/f.json")" = "number" ]
  [ "$(jq -r '[.h1.suite_version, .a4.suite_version, .sensitivity.h1.suite_version, .budget_matched.suite_version,
      .by_suite_version["2.1"].suite_version, .by_suite_version["2.1"].h1.suite_version] | map(type) | unique | join(",")' "$T/f.json")" = "number" ]
  [ "$(jq -c '[.h1.suite_version, .by_suite_version["2.1"].suite_version, .by_suite_version["2"].suite_version,
      .by_suite_version["2"].h1.suite_version, .by_suite_version["2"].a4.suite_version]' "$T/f.json")" = "[2.1,2.1,2,2,2]" ]
  [ "$(jq -c '[.batches[] | .suite_version]' "$T/f.json")" = "[2,2.1]" ]
  [ "$(jq -r '.primary_suite_version | type' "$T/f20.json")" = "number" ]
  [ "$(jq -c '[.h1.suite_version, .batches[0].suite_version]' "$T/f20.json")" = "[2,2]" ]
  # a non-numeric key is a string
  jq -c 'if .batch == "vf-2" then .suite_version = "v2" else . end' "$FX/versions-float/runs.jsonl" > "$T/nn.jsonl"
  cp -R "$FX/versions-float/manifests" "$T/nnm"
  jq '.suite_version = "v2"' "$FX/versions-float/manifests/vf-2/MANIFEST.json" > "$T/nnm/vf-2/MANIFEST.json"
  run python3 -I "$REPORT" --runs "$T/nn.jsonl" --manifests "$T/nnm" --suite "$SUITE" --out "$T/nn.md" --json "$T/nn.json"
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.primary_suite_version, .h1.suite_version, .by_suite_version.v2.suite_version, .by_suite_version["2.1"].suite_version,
      (.batches[] | select(.batch == "vf-2") | .suite_version)]' "$T/nn.json")" = '["v2","v2","v2",2.1,"v2"]' ]
  # no suite_version at all: n/a is null
  jq -c 'del(.suite_version)' "$FX/versions-float/runs.jsonl" | jq -c 'select(.batch == "vf-2")' > "$T/na.jsonl"
  cp -R "$FX/versions-float/manifests" "$T/nam"
  jq 'del(.suite_version)' "$FX/versions-float/manifests/vf-2/MANIFEST.json" > "$T/nam/vf-2/MANIFEST.json"
  run python3 -I "$REPORT" --runs "$T/na.jsonl" --manifests "$T/nam" --suite "$SUITE" --out "$T/na.md" --json "$T/na.json"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.by_suite_version | keys | join(",")' "$T/na.json")" = "n/a" ]
  [ "$(jq -c '[.primary_suite_version, .h1.suite_version, .a4.suite_version, .by_suite_version["n/a"].suite_version,
      .budget_matched.suite_version, (.batches[] | select(.batch == "vf-2") | .suite_version)]' "$T/na.json")" = "[null,null,null,null,null,null]" ]
}

@test "AR-39 version-less rows that never reach a decision (smoke, unbatched) are listed under the primary version; a version-less row that would be scored still exits 2" {
  report legacy "$T/l"
  [ "$status" -eq 0 ]
  [ "$(jq -r .primary_suite_version "$T/l.json")" = "2" ]
  [ "$(jq -r '.listed[] | select(.run_id == "leg-smoke-a1_full-fb-01-t1") | .reason' "$T/l.json")" = "no suite_version; smoke batch leg-smoke" ]
  [ "$(jq -r '.listed[] | select(.run_id == "leg-loose-a0_bare-fb-01-t1") | .reason' "$T/l.json")" = "no suite_version; no manifest for batch leg-loose" ]
  [ "$(jq '.by_suite_version["1"].listed | length' "$T/l.json")" -eq 0 ]
  grep -qF -- '- `leg-smoke-a1_full-fb-01-t1` (`a1_full`, fb-01, completed): no suite_version; smoke batch leg-smoke' "$T/l.md"
  # the decisions are those of the versions scenario
  for k in h1 a4 decisions; do
    [ "$(jq -c ".$k" "$T/l.json")" = "$(jq -c ".$k" "$FX/versions/report.json")" ]
  done
  [ "$(jq -c '.by_suite_version["1"].decisions' "$T/l.json")" = "$(jq -c '.by_suite_version["1"].decisions' "$FX/versions/report.json")" ]
  jq -c 'if .run_id == "ver-v2-a0_bare-rc-02-t2" then del(.suite_version) else . end' "$FX/legacy/runs.jsonl" > "$T/sc.jsonl"
  run python3 -I "$REPORT" --runs "$T/sc.jsonl" --manifests "$FX/legacy/manifests" --suite "$SUITE" --out "$T/sc.md"
  [ "$status" -eq 2 ]
  [[ "$output" == *"row ver-v2-a0_bare-rc-02-t2 has no suite_version while the rows hold suite_version 1, 2"* ]]
}

@test "AR-40 a version-less listed row (among two versions) passes the manifest arm_map check first: another arm exits 2 as a provenance conflict; the matching arm is listed as in AR-39" {
  report legacy-conflict "$T/c"
  [ "$status" -eq 2 ]
  [[ "$output" == *"row leg-smoke-a1_full-fb-01-t1 arm a1_full disagrees with "*"/leg-smoke/MANIFEST.json arm_map (a0_bare)"* ]]
  [ ! -e "$T/c.md" ]
  report legacy-match "$T/m"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.listed[] | select(.run_id == "leg-smoke-a1_full-fb-01-t1") | .reason' "$T/m.json")" = "no suite_version; smoke batch leg-smoke" ]
  [ "$(jq -r '.listed[] | select(.run_id == "leg-loose-a0_bare-fb-01-t1") | .reason' "$T/m.json")" = "no suite_version; no manifest for batch leg-loose" ]
  report legacy "$T/l"
  [ "$status" -eq 0 ]
  for k in h1 a4 decisions listed by_suite_version; do
    [ "$(jq -c ".$k" "$T/m.json")" = "$(jq -c ".$k" "$T/l.json")" ]
  done
}

@test "AR-41 an exception while computing the batch record (a manifest suite_version int() refuses) leaves the report written: exit 0, decisions present, Not rendered with a note" {
  report batch-broken "$T/b"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Traceback"* ]]
  grep -qxF '## Decisions' "$T/b.md"
  grep -qxF '## Batch record' "$T/b.md"
  # report 1.2.3 (audit DISS-C-002): the class and the stage only, never the exception text
  grep -qxF 'Not rendered (ValueError while reading the batch record of ver-v2); it decides nothing.' "$T/b.md"
  grep -qxF '## Method' "$T/b.md"
  [ "$(jq -c .batches "$T/b.json")" = "[]" ]
  [ "$(jq -r .batches_note "$T/b.json")" = "batch record not computed (ValueError while reading the batch record of ver-v2); it decides nothing" ]
  for k in h1 a4 decisions by_suite_version; do
    [ "$(jq -c ".$k" "$T/b.json")" = "$(jq -c ".$k" "$FX/versions/report.json")" ]
  done
  [ "$(jq -r .batches_note "$FX/versions/report.json")" = "null" ]
}

@test "AR-42 run directories: zero-padded rc-01-t01 is trial 1; a trial with only a graded-less rerun is n/a x1 and not missing; a zero-padded rerun is read" {
  report rundirs "$T/r"
  [ "$status" -eq 0 ]
  b() { jq -r --arg b "$1" ".batches[] | select(.batch == \$b) | $2" "$T/r.json"; }
  [ "$(b rd-1 '.grader_versions | to_entries | map("\(.key)=\(.value)") | join(",")')" = "1.2.11=1,1.2.5=1,n/a=1" ]
  [ "$(b rd-1 .run_dirs_missing)" = "0" ]
  [ "$(b rd-1 '([.grader_versions[]] | add) == .trials_rowed')" = "true" ]
  grep -qF '| `rd-1` | no STATUS.json | — / 3 | — | — | — | — | — | — | — | — | 1.2.5 ×1, 1.2.11 ×1, n/a ×1 |' "$T/r.md"
  # the graded-less rerun is the only directory of t2: removing it makes t2 missing
  cp -R "$FX/rundirs/manifests" "$T/rm"
  rmdir "$T/rm/rd-1/a1_full/rc-01-t2-r2"
  run python3 -I "$REPORT" --runs "$FX/rundirs/runs.jsonl" --manifests "$T/rm" --suite "$SUITE" --out "$T/rm.md" --json "$T/rm.json"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.batches[0].run_dirs_missing' "$T/rm.json")" = "1" ]
}

@test "AR-43 inconsistent defects_missed ids (outside d1 … dN, a duplicate, a count against defects_caught, outside the grammar) read as the rate; H1 unchanged in state" {
  c() { jq -r --arg m defect_catch_rate ".h1.comparisons[] | select(.metric == \$m) | $2" "$FX/$1/report.json"; }
  [ "$(c ids-bad '.defect_identity | join(",")')" = "ids,rate" ]
  [ "$(c versions '.defect_identity | join(",")')" = "ids" ]
  [ "$(jq -r .h1.state "$FX/ids-bad/report.json")" = "$(jq -r .h1.state "$FX/versions/report.json")" ]
  [ "$(jq -r .h1.state "$FX/ids-bad/report.json")" = "established" ]
  # the rate spreads the same per-task share over the defects: d is the versions d (1.2.2 read 0.222)
  [ "$(c ids-bad .d)" = "$(c versions .d)" ]
  [ "$(c ids-bad .d)" = "0.444444" ]
  # the budget-matched union refuses the ids too
  [ "$(jq -r '[.budget_matched.tasks[].method] | unique | join(",")' "$FX/ids-bad/report.json")" = "rate fallback" ]
  [ "$(jq -r '[.budget_matched.tasks[].method] | unique | join(",")' "$FX/versions/report.json")" = "defect union" ]
}

@test "AR-44 a non-numeric and a NaN cost_usd: the report is written, each cost read as 0 with one note, report.json is valid JSON, no traceback" {
  report costs-bad "$T/c"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Traceback"* ]]
  [[ "$output" == *"note: row ver-v1-a4_no_gates-fb-01-t1 cost_usd is a str, not a number; read as 0"* ]]
  [[ "$output" == *"note: row ver-v2-a0_bare-rc-01-t1 cost_usd is NaN or an infinity; read as 0"* ]]
  [ "$(grep -c 'note: row ver-v2-a0_bare-rc-01-t1 cost_usd' <<<"$output")" -eq 1 ]
  ! grep -qE 'NaN|Infinity' "$T/c.json" || false
  python3 -I -c 'import json,sys; json.loads(open(sys.argv[1]).read(), parse_constant=lambda c: sys.exit(1))' "$T/c.json"
  for k in h1 a4 decisions; do
    [ "$(jq -c "[.$k | .. | .state? // empty]" "$T/c.json")" = "$(jq -c "[.$k | .. | .state? // empty]" "$FX/versions/report.json")" ]
  done
  # each bad cost reads 0: a0 (v2) 1.0 → 11/12, a4 (v1) 3.0 → 105/36
  jq -e '.arms.a0_bare.cost_per_run == 1' "$FX/versions/report.json"
  jq -e '.arms.a0_bare.cost_per_run == 0.916667' "$T/c.json"
  jq -e '.by_suite_version["1"].arms.a4_no_gates.cost_per_run == 2.916667' "$T/c.json"
}

@test "AR-45 a non-finite number that reaches the JSON twin fails loudly naming the key; nothing is written" {
  cp -R "$FX/present/manifests" "$T/m"
  python3 -I -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["spend"]["max_usd"]=float("nan"); json.dump(d, open(p,"w"))' \
    "$T/m/pr-2/STATUS.json"
  run python3 -I "$REPORT" --runs "$FX/present/runs.jsonl" --manifests "$T/m" --suite "$SUITE" --out "$T/n.md" --json "$T/n.json"
  [ "$status" -eq 2 ]
  [[ "$output" != *"Traceback"* ]]
  [[ "$output" == *'refusing to write a non-finite number to the JSON report at $.batches[1].spend.max_usd'* ]]
  [ ! -e "$T/n.md" ] && [ ! -e "$T/n.json" ]
}

@test "AR-46 an arm \"../..\" and a task_id \"../x\" never build a path: the canary outside the batch directory is not read; a symlinked meta/ is refused" {
  report escape "$T/e"
  [ "$status" -eq 0 ]
  b() { jq -r ".batches[] | select(.batch == \"esc-1\") | $1" "$T/e.json"; }
  # 1.2.2 read the canary through arm ../.. (6.6.6-canary ×1) and matched rc-01-t3-r2 through its symlinked meta/
  [ "$(b '.grader_versions | to_entries | map("\(.key)=\(.value)") | join(",")')" = "1.2.11=1,1.2.5=2,n/a=2" ]
  [ "$(b .run_dirs_missing)" = "2" ]
  [ "$(b .note)" = "2 rows with an arm or task_id outside the grammar (no attributable directory)" ]
  ! grep -q 'canary' "$T/e.md" "$T/e.json" || false
  [ "$(b '([.grader_versions[]] | add) == .trials_rowed')" = "true" ]
  # the canary is still there, untouched, and outside the manifests root
  [ "$(jq -r .grader_version "$FX/escape/rc-01-t1/grade.json")" = "6.6.6-canary" ]
}

@test "AR-47 the sanitized never-fatal text: an exception in one batch's grader tally names the class and the stage, never the exception text" {
  cp -R "$FX/present/manifests" "$T/m"
  # "²" passes str.isdigit() and int() refuses it: grader_key raises ValueError("invalid literal … '²'")
  printf '{"grader_version": "SECRETVALUE.\\u00b2"}\n' > "$T/m/pr-2/a0_bare/rc-01-t1/grade.json"
  run python3 -I "$REPORT" --runs "$FX/present/runs.jsonl" --manifests "$T/m" --suite "$SUITE" --out "$T/s.md" --json "$T/s.json"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Traceback"* ]]
  # the full text goes to stderr once
  [ "$(grep -c "ValueError while tallying the grader versions of pr-2: invalid literal" <<<"$output")" -eq 1 ]
  [ "$(jq -r '.batches[] | select(.batch == "pr-2") | .note' "$T/s.json")" = \
    "grader tally incomplete (ValueError while tallying the grader versions of pr-2)" ]
  grep -qF 'grader tally incomplete (ValueError while tallying the grader versions of pr-2)' "$T/s.md"
  ! grep -q 'invalid literal' "$T/s.md" "$T/s.json" || false
  ! grep -qF "$T" "$T/s.md" || false
}

# --- report 1.3 (cycle-131 Sprint 263 Task 1.6): the decision statistic and its beside figures, the labelled
# sensitivities, pin/rule partitions, the 4-cell minimum, finding volume ----------------------------------------

@test "AR-48 the decision statistic is defect_catch_rate with defect_catch_rate_pm3 and _pm3_v1 printed beside every catch read (H1 and components), deciding nothing" {
  J="$FX/c131/report.json" M="$FX/c131/report.md"
  [ "$(jq -r '.decision_statistic + " " + (.beside | join(","))' "$J")" = "defect_catch_rate defect_catch_rate_pm3,defect_catch_rate_pm3_v1" ]
  [ "$(jq -r .h1.line "$J")" = "H1: established" ]
  [ "$(jq -r '.h1.comparisons[] | select(.metric == "defect_catch_rate") | "\(.d) \(.beside.defect_catch_rate_pm3.d) \(.beside.defect_catch_rate_pm3_v1.d)"' "$J")" = "0.444444 0.388889 0.388889" ]
  [ "$(jq -r '.decisions[] | select(.arm == "a3_one_voice") | .comparisons[] | select(.metric == "defect_catch_rate") | .beside.defect_catch_rate_pm3.n' "$J")" = 18 ]
  grep -qF -- '- decision statistic: defect_catch_rate (grader rule pm3_or_same_function); defect_catch_rate_pm3 and defect_catch_rate_pm3_v1 are printed beside it and decide nothing' "$M"
  grep -qF 'Beside the decision statistic (decides nothing): defect_catch_rate_pm3 +0.389 [' "$M"
  grep -qF -- '- A3 `a3_one_voice`: defect_catch_rate_pm3 0.000 [0.000, 0.000] (n = 18 defects)' "$M"
  # rows without the beside fields (a 1.2.x grade) print n/a, never a figure
  [ "$(jq -r '.h1.comparisons[] | select(.metric == "defect_catch_rate") | .beside.defect_catch_rate_pm3' "$FX/versions/report.json")" = null ]
  grep -qF 'defect_catch_rate_pm3 n/a (rows without the field)' "$FX/versions/report.md"
}

@test "AR-49 sensitivities: oracle-exposed cells excluded (exposed_unknown counts; an oracle_open arm is reported, not excluded) and dissent-absent gates excluded (budget yes, disabled never), with the counts per arm beside each read" {
  J="$FX/c131/report.json" M="$FX/c131/report.md"
  [ "$(jq -c '.sensitivities.oracle_exposed_excluded | [.excluded_rows_per_arm, .reported_open_rows_per_arm]' "$J")" = '[{"a1_full":1,"a7_effort_medium":1},{"a3_one_voice":1}]' ]
  [ "$(jq -c '.sensitivities.dissent_absent_excluded.excluded_rows_per_arm' "$J")" = '{"a1_full":1}' ]
  # the oracle rule drops a1_full rc-01 t1 pairwise from H1: a0_bare's rc-01 t1 leaves too
  [ "$(jq -r '.sensitivities.oracle_exposed_excluded.h1.comparisons[] | select(.metric == "defect_catch_rate") | .dropped | map("\(.arm) \(.task_id) t\(.trial)") | join(",")' "$J")" = "a0_bare rc-01 t1" ]
  [ "$(jq -r '.sensitivities.dissent_absent_excluded.h1.comparisons[] | select(.metric == "defect_catch_rate") | .dropped | map("\(.task_id) t\(.trial)") | join(",")' "$J")" = "rc-02 t2" ]
  # the main reads keep every cell (the labelled sensitivities decide nothing)
  [ "$(jq -r '.h1.comparisons[] | select(.metric == "defect_catch_rate") | .dropped | length' "$J")" = 0 ]
  [ "$(jq -r .oracle_exposed_in_main "$J")" = included ]
  grep -qF '## Sensitivity: oracle-exposed cells excluded — decides nothing' "$M"
  grep -qF '## Sensitivity: dissent-absent gates excluded — decides nothing' "$M"
  grep -qF -- '- rows this rule excluded, per arm: `a1_full` 1, `a7_effort_medium` 1' "$M"
  grep -qF -- '- oracle-exposed rows of an oracle_open arm (reported, not excluded): `a3_one_voice` 1' "$M"
  grep -qF '**sensitivity (dissent-absent gates excluded; decides nothing): H1: established**' "$M"
  # --exclude-oracle-exposed true moves the oracle rule into the main reads (a pre-registration that names it)
  report c131 "$T/x" --exclude-oracle-exposed true
  [ "$status" -eq 0 ]
  [ "$(jq -r .oracle_exposed_in_main "$T/x.json")" = excluded ]
  [ "$(jq -r '[.exclusions[] | select(.reason | startswith("oracle-exposed"))] | map(.run_id) | join(",")' "$T/x.json")" = "c131-b-a1_full-rc-01-t1,c131-b-a7_effort_medium-rc-04-t2" ]
}

@test "AR-50 rows of different source_commit or grader_rule are never pooled: two partitions in one suite_version; --pin selects one; a bad or unmatched --pin exits 2" {
  J="$FX/c131-mixed/report.json"
  [ "$(jq -r '.by_suite_version | keys | join(" | ")' "$J")" = "2 · pin 111111111111 · rule pm3 | 2 · pin 222222222222 · rule pm3_or_same_function" ]
  [ "$(jq -r .primary_suite_version "$J")" = "2 · pin 222222222222 · rule pm3_or_same_function" ]
  [ "$(jq -r '.by_suite_version["2 · pin 111111111111 · rule pm3"].rows' "$J")" = 24 ]
  grep -qF '## Suite version 2 · pin 111111111111 · rule pm3 (batches: ver-v2) — reported separately, never pooled' "$FX/c131-mixed/report.md"
  report c131-mixed "$T/p" --pin 1111111
  [ "$status" -eq 0 ]
  [ "$(jq -r '"\(.primary_suite_version) \(.pin_dropped_rows) \(.by_suite_version | keys | length)"' "$T/p.json")" = "2 48 1" ]
  grep -qF -- '--pin 1111111: 48 row(s) of other source commits not read' "$T/p.md"
  report c131-mixed "$T/q" --pin XYZ
  [ "$status" -eq 2 ]
  [[ "$output" == *"--pin XYZ: want 4 to 40 lowercase hex characters"* ]]
  report c131-mixed "$T/q" --pin 9999999
  [ "$status" -eq 2 ]
  [[ "$output" == *"no row has a source_commit starting with it"* ]]
}

@test "AR-51 a contrast with fewer than 4 valid cells reads insufficient: H1, the component decision and the interval text say so" {
  J="$FX/degenerate-ids/report.json"
  [ "$(jq -r '.h1.comparisons[] | select(.metric == "defect_catch_rate") | "\(.valid_cells) \(.insufficient)"' "$J")" = "3 true" ]
  [ "$(dec degenerate-ids a3_one_voice .rule)" = "inconclusive: no valid pair (hidden_test_pass_rate, defect_catch_rate: insufficient, 3 valid cells < 4)" ]
  grep -qF '(insufficient: 3 valid cells)' "$FX/degenerate-ids/report.md"
  # twelve valid cells (four tasks × three trials) are enough
  [ "$(jq -r '.h1.comparisons[] | select(.metric == "defect_catch_rate") | "\(.valid_cells) \(.insufficient)"' "$FX/c131/report.json")" = "12 false" ]
}

@test "AR-52 finding volume and precision as planted ÷ flagged per review-catch arm (informational); the c131 rows validate as row writer 1.4 rows" {
  J="$FX/c131/report.json"
  [ "$(jq -r '.arms.a0_bare | .finding_volume_per_run == 3 and .precision_planted_per_flag == 0.833333 and .flag_rows == 12' "$J")" = true ]
  [ "$(jq -r '.arms.a1_full | .finding_volume_per_run == 3 and .precision_planted_per_flag == 1.5' "$J")" = true ]
  grep -qF 'finding volume (informational, decides nothing): 3.000 flagged findings per run; precision as planted ÷ flagged: 0.833' "$FX/c131/report.md"
  run "$REPO_ROOT/evals/harness/ablation-row.sh" --validate "$FX/c131/runs.jsonl"
  [ "$status" -eq 0 ]
}
