#!/usr/bin/env bats
# =============================================================================
# evals/tests/eval-recall-grader.bats — cycle-124 Sprint 3 Task 3.2 (PRD FR-9)
#
# evals/graders/recall-vs-defects.sh is deterministic: a planted defect counts
# as detected when the review names the defect's file and a line within ±3 of
# the manifest anchor (no fuzzy adjudication). Clean fixtures measure false
# positives from the LOA-VERDICT trailer's critical+high counts.
# =============================================================================

setup() {
  TESTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$TESTS_DIR/../.." && pwd)"
  GRADER="$REPO_ROOT/evals/graders/recall-vs-defects.sh"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/rg.XXXXXX")"
  WS="$T/ws"; mkdir -p "$WS/.eval" "$T/manifests"
  export EVAL_MANIFEST_DIR="$T/manifests"
  cat > "$T/manifests/pr-x.json" <<'JSON'
{"fixture":"pr-x","defects":[
 {"id":"D1","file":".claude/scripts/a.sh","anchor_line":40,"severity":"critical","category":"authz","source_commit":"deadbeef","synthetic":false},
 {"id":"D2","file":".claude/adapters/loa_cheval/b.py","anchor_line":120,"severity":"high","category":"error-handling","source_commit":"deadbeef","synthetic":false},
 {"id":"D3","file":".claude/scripts/c.sh","anchor_line":7,"severity":"low","category":"logic","source_commit":"deadbeef","synthetic":false}
]}
JSON
  cat > "$T/manifests/pr-clean.json" <<'JSON'
{"fixture":"pr-clean","defects":[]}
JSON
  echo '{"model_id":"claude-sonnet-5-20260401","effort":"xhigh","usage":{"input_tokens":30,"cache_creation_input_tokens":170,"cache_read_input_tokens":800,"output_tokens":200}}' > "$WS/.eval/executor.json"
}

teardown() { find "$T" -mindepth 1 -delete 2>/dev/null || true; rmdir "$T" 2>/dev/null || true; }

review() {  # review <body> — writes review.md with a trailer
  printf '%s\n\n<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":1,"high":1,"medium":0,"low":0},"sprint_id":"sprint-0","ts":"2026-01-01T00:00:00Z"} -->\n' "$1" > "$WS/review.md"
}

@test "RG-1 exact anchor with head/ prefix is detected; recall is detected/planted" {
  review '- **CRITICAL** `head/.claude/scripts/a.sh:40` — decoy flag re-anchors'
  run "$GRADER" "$WS" pr-x
  [ "$(echo "$output" | jq -r '.details.detected | join(",")')" = "D1" ]
  [ "$(echo "$output" | jq -r '.details.recall')" = "0.3333" ]
  [ "$(echo "$output" | jq -r '.details.planted')" = "3" ]
  [ "$(echo "$output" | jq -r '.pass')" = "false" ]
}

@test "RG-2 a citation 3 lines away counts, 4 lines away does not" {
  review '`.claude/scripts/a.sh:43` and `.claude/adapters/loa_cheval/b.py:116`'
  run "$GRADER" "$WS" pr-x
  [ "$(echo "$output" | jq -r '.details.detected | join(",")')" = "D1" ]
}

@test "RG-3 a line range covering the anchor counts" {
  review 'See .claude/adapters/loa_cheval/b.py:110-125 for the missing except clause'
  run "$GRADER" "$WS" pr-x
  [ "$(echo "$output" | jq -r '.details.detected | join(",")')" = "D2" ]
}

@test "RG-4 basename-only and repo-relative citations both match the manifest file" {
  review 'a.sh:39 is wrong; also b.py:120 and c.sh:7'
  run "$GRADER" "$WS" pr-x
  [ "$(echo "$output" | jq -r '.details.detected | join(",")')" = "D1,D2,D3" ]
  [ "$(echo "$output" | jq -r '.details.recall == 1')" = "true" ]
  [ "$(echo "$output" | jq -r '.pass')" = "true" ]
  [ "$(echo "$output" | jq -r '.score')" = "100" ]
}

@test "RG-5 a different file at the anchor line is not a detection" {
  review '`.claude/scripts/zzz.sh:40` looks off'
  run "$GRADER" "$WS" pr-x
  [ "$(echo "$output" | jq -r '.details.detected | length')" = "0" ]
}

@test "RG-6 clean fixture: false positives come from the trailer's critical+high; zero passes" {
  review 'Nothing wrong here.'
  run "$GRADER" "$WS" pr-clean
  [ "$(echo "$output" | jq -r '.details.false_positives')" = "2" ]
  [ "$(echo "$output" | jq -r '.pass')" = "false" ]
  printf 'All good\n\n<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":1,"low":0},"sprint_id":"sprint-0","ts":"2026-01-01T00:00:00Z"} -->\n' > "$WS/review.md"
  run "$GRADER" "$WS" pr-clean
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.details.false_positives')" = "0" ]
  [ "$(echo "$output" | jq -r '.pass')" = "true" ]
}

@test "RG-7 clean fixture without a trailer: every file:line citation is a false positive" {
  printf 'Problems: src/a.sh:3 and src/b.sh:9\n' > "$WS/review.md"
  run "$GRADER" "$WS" pr-clean
  [ "$(echo "$output" | jq -r '.details.false_positives')" = "2" ]
}

@test "RG-8 missing review file fails with score 0 and an error detail" {
  run "$GRADER" "$WS" pr-x
  [ "$status" -eq 1 ]
  [ "$(echo "$output" | jq -r '.pass')" = "false" ]
  [ "$(echo "$output" | jq -r '.score')" = "0" ]
  [ "$(echo "$output" | jq -r '.details.error')" != "null" ]
}

@test "RG-9 details carry model, effort and tokens from .eval/executor.json; review file name is an argument" {
  printf -- '- head/.claude/scripts/c.sh:8 nit\n\n<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":1},"sprint_id":"sprint-0","ts":"2026-01-01T00:00:00Z"} -->\n' > "$WS/audit.md"
  run "$GRADER" "$WS" pr-x audit.md
  [ "$(echo "$output" | jq -r '.details.model')" = "claude-sonnet-5-20260401" ]
  [ "$(echo "$output" | jq -r '.details.effort')" = "xhigh" ]
  [ "$(echo "$output" | jq -r '.details.tokens')" = "1200" ]
  [ "$(echo "$output" | jq -r '.details.detected | join(",")')" = "D3" ]
  [ "$(echo "$output" | jq -r '.details.severity_counts.low')" = "1" ]
}

@test "RG-10 unknown fixture id is a grader error (exit 2)" {
  review 'x'
  run "$GRADER" "$WS" pr-nope
  [ "$status" -eq 2 ]
}
