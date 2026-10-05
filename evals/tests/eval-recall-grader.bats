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

# --- bd-ewrc (cycle-126 sprint-250 Task 4.8): citation-parser defects -------
@test "RG-11 a leading ( is not part of the cited path: (head/a.sh:40) and (a.sh:40 both detect D1" {
  review 'the decoy flag (head/.claude/scripts/a.sh:40) re-anchors'
  run "$GRADER" "$WS" pr-x
  [ "$(echo "$output" | jq -r '.details.detected | join(",")')" = "D1" ]
  review 'see (a.sh:40, a recent change'
  run "$GRADER" "$WS" pr-x
  [ "$(echo "$output" | jq -r '.details.detected | join(",")')" = "D1" ]
}

@test "RG-12 comma continuations bind to the cited path: b.py:10,120 and b.py:10, 118-121 detect D2" {
  review '`.claude/adapters/loa_cheval/b.py:10,120` both drop the error'
  run "$GRADER" "$WS" pr-x
  [ "$(echo "$output" | jq -r '.details.detected | join(",")')" = "D2" ]
  review 'b.py:10, 118-121'
  run "$GRADER" "$WS" pr-x
  [ "$(echo "$output" | jq -r '.details.detected | join(",")')" = "D2" ]
}

@test "RG-13 a bare :N or head:N binds to the most recent cited path, not an earlier one" {
  review 'In `.claude/scripts/c.sh:1` the guard … then `:7` returns early'
  run "$GRADER" "$WS" pr-x
  [ "$(echo "$output" | jq -r '.details.detected | join(",")')" = "D3" ]
  review 'a.sh:1 is fine. c.sh:100 is odd, and head:40 too'
  run "$GRADER" "$WS" pr-x
  [ "$(echo "$output" | jq -r '.details.detected | length')" = "0" ]
  review 'c.sh:100 is odd, head:7 too'
  run "$GRADER" "$WS" pr-x
  [ "$(echo "$output" | jq -r '.details.detected | join(",")')" = "D3" ]
}

@test "RG-14 a bare :N with no preceding path, or one glued to a word (10:40, note:40), credits nothing" {
  review 'At :40 the decoy re-anchors; meeting at 10:40; note:40'
  run "$GRADER" "$WS" pr-x
  [ "$(echo "$output" | jq -r '.details.detected | length')" = "0" ]
}

@test "RG-15 anchors[] lists every site of a multi-site defect; anchor_line alone still works" {
  cat > "$T/manifests/pr-y.json" <<'JSON'
{"fixture":"pr-y","defects":[
 {"id":"M1","file":".claude/hooks/x.sh","anchor_line":807,"anchors":[776,807],"severity":"critical","category":"authz","source_commit":"deadbeef","synthetic":false},
 {"id":"M2","file":".claude/scripts/s.sh","anchor_line":83,"severity":"low","category":"logic","source_commit":"deadbeef","synthetic":false}
]}
JSON
  review 'x.sh:776 group 3 captures one root; s.sh:57 lists tags'
  run "$GRADER" "$WS" pr-y
  [ "$(echo "$output" | jq -r '.details.detected | join(",")')" = "M1" ]
  [ "$(echo "$output" | jq -r '.details.missed | join(",")')" = "M2" ]
  review 'x.sh:807 and s.sh:83'
  run "$GRADER" "$WS" pr-y
  [ "$(echo "$output" | jq -r '.details.recall == 1')" = "true" ]
}

@test "RG-16 the two real multi-site manifests carry anchors[] (pr-05 D13 776/807, pr-02 D06 57/83), each a real site" {
  local M="$REPO_ROOT/evals/fixtures/review-prs/manifests" F="$REPO_ROOT/evals/fixtures/review-prs"
  [ "$(jq -c '.defects[] | select(.id=="D13-find-exec-multi-root") | .anchors' "$M/pr-05.json")" = "[776,807]" ]
  [ "$(jq -c '.defects[] | select(.id=="D06-prerelease-tags-rejected") | .anchors' "$M/pr-02.json")" = "[57,83]" ]
  sed -n 776p "$F/pr-05/head/.claude/hooks/safety/block-destructive-bash.sh" | grep -q '_re_find_exec_prefix='
  sed -n 57p "$F/pr-02/head/.claude/scripts/semver-bump.sh" | grep -q "tag -l 'v\[0-9\]\*"
  # every anchors[] list contains its anchor_line, so the field only ever widens detection
  for f in "$M"/*.json; do
    jq -e '[.defects[] | select(has("anchors")) | . as $d | .anchors | index($d.anchor_line) != null] | all' "$f" >/dev/null
  done
}

@test "RG-17 grader_version is 1.1.0 (the bd-ewrc parser); the manifest corpus checksum list matches the manifests" {
  review 'a.sh:40'
  run "$GRADER" "$WS" pr-x
  [ "$(echo "$output" | jq -r '.grader_version')" = "1.1.0" ]
  ( cd "$REPO_ROOT/evals/fixtures/review-prs" && grep ' manifests/' SHA256SUMS | sha256sum -c --quiet - )
}
