#!/usr/bin/env bats
# =============================================================================
# tests/unit/cost-report.bats — cycle-125 Sprint 4 (PRD FR-5 AC 3–4, SDD §1.6)
# cost-report.sh: totals against a hand computation, the unpriced line and JSON
# fields, --include-legacy (de-duplicated by request_id), --migrate-legacy
# through the resolver-validated writer with a receipt, idempotence, and
# ledger isolation (every test passes explicit --ledger paths under a temp
# dir; the repository's own ledgers are never read or written).
# =============================================================================

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  CR="$PROJECT_ROOT/.claude/scripts/cost-report.sh"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/cr.XXXXXX")"
  export LOA_RUN_DIR="$T/run"
  unset LOA_COST_LEDGER_PATH
  CUR="$T/cur.jsonl"; LEG="$T/legacy.jsonl"
  # hand computation: current = 8000 + 0 + 2500 = 10500 micro-USD; 1 of 3 unpriced
  cat > "$CUR" <<'EOF'
{"ts":"2026-09-20T10:00:00.000Z","request_id":"r1","agent":"a","provider":"openai","model":"gpt-5.5","tokens_in":1000,"tokens_out":100,"cost_micro_usd":8000,"pricing_source":"config","pricing_resolution":"exact"}
{"ts":"2026-09-21T10:00:00.000Z","request_id":"r2","agent":"a","provider":"openai","model":"codex-headless","tokens_in":1000,"tokens_out":100,"cost_micro_usd":0,"pricing_source":"unknown"}
{"ts":"2026-09-22T10:00:00.000Z","request_id":"r3","agent":"b","provider":"anthropic","model":"claude-headless","tokens_in":500,"tokens_out":50,"cost_micro_usd":2500,"pricing_source":"config","pricing_resolution":"hop","cost_estimated":true}
EOF
  # legacy = one new row (1500) + one duplicate of r1 (must not double count)
  cat > "$LEG" <<'EOF'
{"ts":"2026-08-01T10:00:00.000Z","request_id":"L1","agent":"b","provider":"anthropic","model":"claude-opus-5","tokens_in":10,"tokens_out":1,"cost_micro_usd":1500,"pricing_source":"config"}
{"ts":"2026-08-02T10:00:00.000Z","request_id":"r1","agent":"a","provider":"openai","model":"gpt-5.5","tokens_in":1000,"tokens_out":100,"cost_micro_usd":8000,"pricing_source":"config"}
EOF
  REPO_CUR_SHA=$(sha256sum "$PROJECT_ROOT/.run/cost-ledger.jsonl" 2>/dev/null | cut -d' ' -f1 || true)
  REPO_LEG_SHA=$(sha256sum "$PROJECT_ROOT/grimoires/loa/a2a/cost-ledger.jsonl" 2>/dev/null | cut -d' ' -f1 || true)
}

teardown() {
  # ledger isolation (FR-5 AC 4): the repository's ledgers are byte-identical after every test
  [ "$(sha256sum "$PROJECT_ROOT/.run/cost-ledger.jsonl" 2>/dev/null | cut -d' ' -f1 || true)" = "$REPO_CUR_SHA" ]
  [ "$(sha256sum "$PROJECT_ROOT/grimoires/loa/a2a/cost-ledger.jsonl" 2>/dev/null | cut -d' ' -f1 || true)" = "$REPO_LEG_SHA" ]
  find "$T" -mindepth 1 -delete 2>/dev/null || true; rmdir "$T" 2>/dev/null || true
}

@test "CR-1 totals match the hand computation; unpriced rows and share are reported in JSON and markdown" {
  run bash "$CR" --ledger "$CUR" --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.total_micro_usd == 10500 and .entry_count == 3 and .unpriced_rows == 1 and .estimated_rows == 1 and .legacy_rows == 0' >/dev/null
  [ "$(echo "$output" | jq -r '.unpriced_share')" = "0.333333" ]
  echo "$output" | jq -e '.pricing_resolution == {"exact":1,"unknown":1,"hop":1}' >/dev/null
  run bash "$CR" --ledger "$CUR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '^Unpriced rows: 1 (33.3 %) — recorded as cost 0, not as a price; estimated rows: 1$'
  echo "$output" | grep -q '^Pricing resolution: exact 1, hop 1, unknown 1$'
  echo "$output" | grep -q '| All time | \$0.01 |'
}

@test "CR-2 --include-legacy adds the legacy rows once (duplicate request_id skipped) and tags them; the files are unchanged" {
  before_cur=$(sha256sum "$CUR" | cut -d' ' -f1); before_leg=$(sha256sum "$LEG" | cut -d' ' -f1)
  run bash "$CR" --ledger "$CUR" --include-legacy --legacy-ledger "$LEG" --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.total_micro_usd == 12000 and .entry_count == 4 and .legacy_rows == 1 and .unpriced_rows == 1' >/dev/null
  [ "$(echo "$output" | jq -r '.unpriced_share')" = "0.25" ]
  [ "$(sha256sum "$CUR" | cut -d' ' -f1)" = "$before_cur" ]
  [ "$(sha256sum "$LEG" | cut -d' ' -f1)" = "$before_leg" ]
}

@test "CR-3 --migrate-legacy appends only the new legacy rows through the writer, tags them, writes a receipt with counts and hashes, and is idempotent" {
  run bash "$CR" --ledger "$CUR" --migrate-legacy --legacy-ledger "$LEG" --json
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$CUR")" -eq 4 ]
  tail -n1 "$CUR" | jq -e '.request_id == "L1" and .legacy == true and .legacy_source == "legacy.jsonl"' >/dev/null
  receipt=$(ls "$T/run"/cost-ledger-migration-*.json | head -1)
  [ -n "$receipt" ]
  jq -e '.rows_legacy == 2 and .rows_migrated == 1 and .rows_skipped_duplicate == 1 and (.sha256_source|length) == 64 and (.sha256_target_after|length) == 64 and .sha256_target_before != .sha256_target_after and .writer == "loa_cheval.metering.ledger.append_ledger"' "$receipt" >/dev/null
  ! grep -q '"tokens_in"' "$receipt"   # never row contents
  # the report after migration sees the migrated row once, not twice (stderr carries the migration log line)
  echo "$output" | grep -v '^cost-report:' | jq -e '.total_micro_usd == 12000 and .entry_count == 4' >/dev/null
  # idempotent: a second run migrates 0 and the ledger keeps 4 rows
  run bash "$CR" --ledger "$CUR" --migrate-legacy --legacy-ledger "$LEG" --json
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$CUR")" -eq 4 ]
  [ "$(ls "$T/run"/cost-ledger-migration-*.json | wc -l)" -ge 2 ]
  jq -e '.rows_migrated == 0 and .rows_skipped_duplicate == 2' "$(ls -t "$T/run"/cost-ledger-migration-*.json | head -1)" >/dev/null
}

@test "CR-1b a pre-metadata row (no pricing_source) with a cost is unclassified, not unpriced; with cost 0 it is unpriced (BB #1269 FIND-004)" {
  printf '{"ts":"2026-06-01T10:00:00.000Z","request_id":"old1","agent":"a","provider":"openai","model":"gpt-4o","tokens_in":1,"tokens_out":1,"cost_micro_usd":900}\n{"ts":"2026-06-01T11:00:00.000Z","request_id":"old2","agent":"a","provider":"openai","model":"gpt-4o","tokens_in":1,"tokens_out":1,"cost_micro_usd":0}\n' > "$T/old.jsonl"
  run bash "$CR" --ledger "$T/old.jsonl" --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.entry_count == 2 and .unpriced_rows == 1 and .unclassified_rows == 1 and .unpriced_share == 0.5 and .total_micro_usd == 900' >/dev/null
  run bash "$CR" --ledger "$T/old.jsonl"
  echo "$output" | grep -q 'Unpriced rows: 1 (50.0 %) — recorded as cost 0, not as a price; unclassified (pre-metadata, priced by their writer): 1'
}

@test "CR-3b legacy rows WITHOUT a request_id migrate exactly once (content key), in --include-legacy and --migrate-legacy alike" {
  printf '{"ts":"2026-07-01T10:00:00.000Z","trace_id":"t0","agent":"c","provider":"openai","model":"gpt-5.2","tokens_in":5,"tokens_out":1,"cost_micro_usd":700,"pricing_source":"config"}\n' > "$LEG"
  run bash "$CR" --ledger "$CUR" --include-legacy --legacy-ledger "$LEG" --json
  echo "$output" | jq -e '.entry_count == 4 and .legacy_rows == 1' >/dev/null
  bash "$CR" --ledger "$CUR" --migrate-legacy --legacy-ledger "$LEG" --json >/dev/null 2>&1
  bash "$CR" --ledger "$CUR" --migrate-legacy --legacy-ledger "$LEG" --json >/dev/null 2>&1
  [ "$(wc -l < "$CUR")" -eq 4 ]
  [ "$(grep -c '"trace_id":"t0"' "$CUR")" -eq 1 ]
  run bash "$CR" --ledger "$CUR" --include-legacy --legacy-ledger "$LEG" --json
  echo "$output" | jq -e '.entry_count == 4 and .legacy_rows == 0' >/dev/null
}

@test "CR-4 --migrate-legacy refuses a symlinked target (the writer's O_NOFOLLOW) and a missing legacy file" {
  ln -s "$T/elsewhere.jsonl" "$T/link.jsonl"; : > "$T/elsewhere.jsonl"
  run bash "$CR" --ledger "$T/link.jsonl" --migrate-legacy --legacy-ledger "$LEG" --json
  [ "$status" -ne 0 ]
  [ ! -s "$T/elsewhere.jsonl" ]
  run bash "$CR" --ledger "$CUR" --migrate-legacy --legacy-ledger "$T/nope.jsonl"
  [ "$status" -eq 2 ]
}

@test "CR-5 a missing current ledger with a legacy file still reports when --include-legacy is given; without it the empty envelope carries unpriced fields" {
  run bash "$CR" --ledger "$T/none.jsonl" --include-legacy --legacy-ledger "$LEG" --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.entry_count == 2 and .legacy_rows == 2' >/dev/null
  run bash "$CR" --ledger "$T/none.jsonl" --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.entry_count == 0 and .unpriced_rows == 0 and .unpriced_share == 0' >/dev/null
}
