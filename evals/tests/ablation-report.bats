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
# the H1 and A4 lines, and the degenerate single-task rate-fallback pair.
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
  for s in main boundary exclusions versions degraded degraded-a4 degenerate-1 degenerate-2 degenerate-ids; do
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
  grep -qF 'Expected false positives at level 0.90 over 6 components: 6 × (1 − 0.90) / 2 = 0.3 one-sided per direction (0.6 in either direction); no multiple-comparison correction is applied (multiple_comparisons: none).' "$FX/main/report.md"
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
  [ "$(jq -r '.by_suite_version["1"].decisions | length' "$J")" -eq 6 ]
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
  ! grep -qF 'H1: established' "$FX/degraded/report.md" || false
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

@test "AR-29 not degenerate with pairs on two tasks, or with per-defect ids on one task" {
  [ "$(jq -r '.h1.comparisons[] | select(.metric == "defect_catch_rate") | .degenerate' "$FX/degenerate-2/report.json")" = "false" ]
  [ "$(jq -r .h1.line "$FX/degenerate-2/report.json")" = "H1: established" ]
  [ "$(jq -r '.h1.comparisons[] | select(.metric == "defect_catch_rate") | .degenerate' "$FX/degenerate-ids/report.json")" = "false" ]
  [ "$(jq -r '.h1.comparisons[] | select(.metric == "defect_catch_rate") | .read' "$FX/degenerate-ids/report.json")" = "tested" ]
  [ "$(jq -r .h1.line "$FX/degenerate-ids/report.json")" = "H1: not established — halt before promotion" ]
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
