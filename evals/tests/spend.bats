#!/usr/bin/env bats
# =============================================================================
# evals/tests/spend.bats — cycle-130 Sprint 258 Task 1.5 (PRD FR-2 AC-2.3, SDD §5.11)
#
# spend.sh sums run rows (cost_usd, each run_id once across files) and the cost
# ledger (cost_micro_usd, ts >= since) and prints total, components, cap,
# headroom and reserve. Fixtures: evals/tests/fixtures/ablation/spend/ —
# runs.jsonl 6.41 + 3.59, rows.jsonl 3.59 (same run_id, counted once at its larger cost) + 2.00,
# ledger 1.00 before the kickoff, 2.50 and 0.50 after it.
# =============================================================================

setup() {
  TESTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$TESTS_DIR/../.." && pwd)"
  SPEND="$REPO_ROOT/evals/harness/spend.sh"
  FX="$TESTS_DIR/fixtures/ablation/spend"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/sp.XXXXXX")"
}

teardown() {
  find "$T" -mindepth 1 -delete 2>/dev/null || true
  rmdir "$T" 2>/dev/null || true
}

@test "SP-1 rows (deduplicated by run_id) plus ledger rows since the default kickoff: the summary line" {
  run "$SPEND" --runs "$FX/runs.jsonl" "$FX/rows.jsonl" --ledger "$FX/cost-ledger.jsonl"
  [ "$status" -eq 0 ]
  [ "$output" = "cycle spend USD 15.00 (runs 12.00 + ledger 3.00 since 2026-10-14T13:50:00Z); cap 1,500; headroom 1,485.00; reserve 250" ]
}

@test "SP-2 --json carries the same fields" {
  run "$SPEND" --runs "$FX/runs.jsonl" --runs "$FX/rows.jsonl" --ledger "$FX/cost-ledger.jsonl" --json
  [ "$status" -eq 0 ]
  [ "$(jq -r '.total_usd' <<<"$output")" = "15" ]
  [ "$(jq -r '.runs_usd' <<<"$output")" = "12" ]
  [ "$(jq -r '.ledger_usd' <<<"$output")" = "3" ]
  [ "$(jq -r '.since' <<<"$output")" = "2026-10-14T13:50:00Z" ]
  [ "$(jq -r '.cap_usd' <<<"$output")" = "1500" ]
  [ "$(jq -r '.headroom_usd' <<<"$output")" = "1485" ]
  [ "$(jq -r '.reserve_usd' <<<"$output")" = "250" ]
  [ "$(jq -r '.runs_rows' <<<"$output")" = "3" ]
  [ "$(jq -r '.runs_rows_deduped' <<<"$output")" = "1" ]
  [ "$(jq -r '.ledger_rows' <<<"$output")" = "2" ]
  [ "$(jq -r '.runs_files | length' <<<"$output")" = "2" ]
}

@test "SP-3 --since filters the ledger (a date, a timestamp, the full history); --cap and --reserve override; headroom goes negative" {
  run "$SPEND" --since 2026-10-15 --runs "$FX/runs.jsonl" --ledger "$FX/cost-ledger.jsonl" --json
  [ "$status" -eq 0 ]
  [ "$(jq -r '.ledger_usd' <<<"$output")" = "0.5" ]
  [ "$(jq -r '.runs_usd' <<<"$output")" = "10" ]
  run "$SPEND" --since 2026-10-01T00:00:00Z --ledger "$FX/cost-ledger.jsonl" --runs "$FX/runs.jsonl" --cap 12 --reserve 3
  [ "$status" -eq 0 ]
  [ "$output" = "cycle spend USD 14.00 (runs 10.00 + ledger 4.00 since 2026-10-01T00:00:00Z); cap 12; headroom -2.00; reserve 3" ]
}

@test "SP-4 a malformed line is skipped and counted; the rest still sums, marked incomplete (exit 1)" {
  { cat "$FX/cost-ledger.jsonl"; echo '{not json'; echo '{"ts":"2026-10-15T02:00:00Z"}'; } > "$T/ledger.jsonl"
  run "$SPEND" --runs "$FX/runs.jsonl" --ledger "$T/ledger.jsonl" --json
  [ "$status" -eq 1 ]
  json="$(grep '^{' <<<"$output")"
  [ "$(jq -r '.skipped_lines' <<<"$json")" = "1" ]
  [ "$(jq -r '.complete' <<<"$json")" = "false" ]
  [ "$(jq -r '.ledger_usd' <<<"$json")" = "3" ]
  [ "$(jq -r '.ledger_rows' <<<"$json")" = "3" ]
}

@test "SP-7 a skipped ledger line makes the text total INCOMPLETE and exits 1; a clean read says complete" {
  { cat "$FX/cost-ledger.jsonl"; echo '{not json'; } > "$T/ledger.jsonl"
  run "$SPEND" --runs "$FX/runs.jsonl" --ledger "$T/ledger.jsonl"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cycle spend USD 13.00 (runs 10.00 + ledger 3.00 since 2026-10-14T13:50:00Z); cap 1,500; headroom 1,487.00; reserve 250 INCOMPLETE (1 skipped)"* ]]
  run "$SPEND" --runs "$FX/runs.jsonl" --ledger "$FX/cost-ledger.jsonl" --json
  [ "$status" -eq 0 ]
  [ "$(jq -r '.complete' <<<"$output")" = "true" ]
}

@test "SP-8 a run rowed twice counts its larger cost, whichever row comes first" {
  printf '%s\n' '{"run_id":"r1","cost_usd":3,"started":"2026-10-15T01:00:00Z"}' '{"run_id":"r1","cost_usd":5,"started":"2026-10-15T01:00:00Z"}' > "$T/a.jsonl"
  printf '%s\n' '{"run_id":"r1","cost_usd":5,"started":"2026-10-15T01:00:00Z"}' '{"run_id":"r1","cost_usd":3,"started":"2026-10-15T01:00:00Z"}' > "$T/b.jsonl"
  for f in a b; do
    run "$SPEND" --runs "$T/$f.jsonl" --ledger "$FX/cost-ledger.jsonl" --json
    [ "$status" -eq 0 ]
    [ "$(jq -r '.runs_usd' <<<"$output")" = "5" ]
    [ "$(jq -r '.runs_rows' <<<"$output")" = "1" ]
    [ "$(jq -r '.runs_rows_deduped' <<<"$output")" = "1" ]
  done
}

@test "SP-9 rows without a run_id each count once, with one warning naming the file" {
  printf '%s\n' '{"cost_usd":1,"started":"2026-10-15T01:00:00Z"}' '{"run_id":"","cost_usd":2,"started":"2026-10-15T01:00:00Z"}' '{"run_id":"r1","cost_usd":4,"started":"2026-10-15T01:00:00Z"}' > "$T/anon.jsonl"
  run "$SPEND" --runs "$T/anon.jsonl" --ledger "$FX/cost-ledger.jsonl" --json
  [ "$status" -eq 0 ]
  json="$(grep '^{' <<<"$output")"
  [ "$(jq -r '.runs_usd' <<<"$json")" = "7" ]
  [ "$(jq -r '.runs_rows' <<<"$json")" = "3" ]
  [ "$(jq -r '.runs_rows_no_run_id' <<<"$json")" = "2" ]
  [ "$(grep -c "anon.jsonl: 2 row(s) without a run_id" <<<"$output")" -eq 1 ]
}

@test "SP-5 exit 1 on an unreadable file; exit 2 on usage errors" {
  run "$SPEND" --runs "$T/absent.jsonl" --ledger "$FX/cost-ledger.jsonl"
  [ "$status" -eq 1 ]
  grep -q 'unreadable' <<<"$output"
  run "$SPEND" --runs "$FX/runs.jsonl" --ledger "$T/absent-ledger.jsonl"
  [ "$status" -eq 1 ]
  run "$SPEND" --since yesterday --runs "$FX/runs.jsonl" --ledger "$FX/cost-ledger.jsonl"
  [ "$status" -eq 2 ]
  run "$SPEND" --cap -5 --runs "$FX/runs.jsonl" --ledger "$FX/cost-ledger.jsonl"
  [ "$status" -eq 2 ]
  run "$SPEND" --runs
  [ "$status" -eq 2 ]
  run "$SPEND" --bogus
  [ "$status" -eq 2 ]
}

@test "SP-6 the default cap and reserve come from the suite file's caps block (1500, 250)" {
  [ "$(yq -r '.caps.cycle_usd' "$REPO_ROOT/evals/suites/ablation-2.0.yaml")" = "1500" ]
  run "$SPEND" --runs "$FX/runs.jsonl" --ledger "$FX/cost-ledger.jsonl" --json
  [ "$status" -eq 0 ]
  [ "$(jq -r '.reserve_usd' <<<"$output")" = "250" ]
}

@test "SP-10 (cycle-132) --since applies to run rows too: a row started before it is excluded, one with only finished after it counts, one without a timestamp counts with a note" {
  printf '%s\n' '{"run_id":"old","cost_usd":100,"started":"2026-10-20T23:00:00Z","finished":"2026-10-21T01:00:00Z"}' \
    '{"run_id":"new","cost_usd":3,"started":"2026-10-21T00:30:00Z"}' '{"run_id":"fin","cost_usd":2,"finished":"2026-10-21T02:00:00Z"}' \
    '{"run_id":"nodate","cost_usd":5}' '{"run_id":"bad","cost_usd":7,"started":"yesterday"}' > "$T/r.jsonl"
  : > "$T/ledger.jsonl"
  run "$SPEND" --since 2026-10-21T00:23:00Z --runs "$T/r.jsonl" --ledger "$T/ledger.jsonl" --json
  [ "$status" -eq 0 ]
  json="$(grep '^{' <<<"$output")"
  [ "$(jq -r '"\(.runs_usd) \(.runs_rows) \(.runs_rows_before_since) \(.runs_rows_undated) \(.complete)"' <<<"$json")" = "17 4 1 2 true" ]
  [ "$(grep -c 'r.jsonl: 2 row(s) with no started/finished timestamp counted' <<<"$output")" -eq 1 ]
  # an earlier kickoff counts the old row again
  run "$SPEND" --since 2026-10-20T00:00:00Z --runs "$T/r.jsonl" --ledger "$T/ledger.jsonl" --json
  [ "$(grep '^{' <<<"$output" | jq -r '.runs_usd')" = "117" ]
}

@test "SP-11 (cycle-132 dissent DISS-002) a row's all_spend_usd is what counts when it is numeric (a matched cell's every session, a trial's earlier attempts), else cost_usd; the larger figure per run_id still wins" {
  printf '%s\n' '{"run_id":"cell","cost_usd":5,"all_spend_usd":12.5,"started":"2026-10-21T01:00:00Z"}' \
    '{"run_id":"trial","cost_usd":3,"all_spend_usd":5.5,"started":"2026-10-21T01:00:00Z"}' \
    '{"run_id":"old-row","cost_usd":2,"started":"2026-10-21T01:00:00Z"}' \
    '{"run_id":"weird","cost_usd":4,"all_spend_usd":"n/a","started":"2026-10-21T01:00:00Z"}' > "$T/r.jsonl"
  : > "$T/ledger.jsonl"
  run "$SPEND" --since 2026-10-21T00:00:00Z --runs "$T/r.jsonl" --ledger "$T/ledger.jsonl" --json
  [ "$status" -eq 0 ]
  [ "$(jq -r '.runs_usd' <<<"$output")" = "24" ]   # 12.5 + 5.5 + 2 + 4
  printf '%s\n' '{"run_id":"cell","cost_usd":5,"all_spend_usd":20,"started":"2026-10-21T02:00:00Z"}' >> "$T/r.jsonl"
  run "$SPEND" --since 2026-10-21T00:00:00Z --runs "$T/r.jsonl" --ledger "$T/ledger.jsonl" --json
  [ "$(jq -r '.runs_usd, .runs_rows_deduped' <<<"$output" | tr '\n' ' ')" = "31.5 1 " ]
}

# a copy of spend.sh in a throwaway repository layout, so its DEFAULT run-row files can be exercised
spend_tree() {
  R="$T/repo"; mkdir -p "$R/evals/harness" "$R/evals/results/ablation-2.0/smoke-x" "$R/grimoires/loa/reports/ablation-2.0" "$R/.run"
  cp "$SPEND" "$R/evals/harness/spend.sh"
  : > "$R/.run/cost-ledger.jsonl"
}

@test "SP-12 (cycle-132 addendum 3) the default run-row files include the live evals/results/ablation-2.0/runs.jsonl: a row only there counts; a row in it and in the tracked copy counts once at the larger cost" {
  spend_tree
  printf '%s\n' '{"run_id":"live-1","cost_usd":7.3,"started":"2026-10-21T08:00:00Z"}' \
    '{"run_id":"both","cost_usd":10,"started":"2026-10-21T08:00:00Z"}' > "$R/evals/results/ablation-2.0/runs.jsonl"
  printf '%s\n' '{"run_id":"both","cost_usd":4,"started":"2026-10-21T08:00:00Z"}' > "$R/grimoires/loa/reports/ablation-2.0/runs.jsonl"
  printf '%s\n' '{"run_id":"smoke-1","cost_usd":1,"started":"2026-10-21T08:00:00Z"}' > "$R/evals/results/ablation-2.0/smoke-x/rows.jsonl"
  run "$R/evals/harness/spend.sh" --since 2026-10-21T00:23:00Z --json
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(jq -r '.runs_usd' <<<"$output")" = "18.3" ]   # 7.3 + max(10, 4) + 1
  [ "$(jq -r '"\(.runs_rows) \(.runs_rows_deduped) \(.runs_files | length)"' <<<"$output")" = "3 1 3" ]
  jq -e '.runs_files | any(endswith("evals/results/ablation-2.0/runs.jsonl"))' <<<"$output" >/dev/null
  # absent, the live file is simply not read (no error)
  rm "$R/evals/results/ablation-2.0/runs.jsonl"
  run "$R/evals/harness/spend.sh" --since 2026-10-21T00:23:00Z --json
  [ "$status" -eq 0 ]
  [ "$(jq -r '"\(.runs_usd) \(.runs_files | length)"' <<<"$output")" = "5 2" ]
}
