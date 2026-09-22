#!/usr/bin/env bats
# =============================================================================
# evals/tests/recall-baseline-freshness.bats — cycle-124 Sprint 3 Task 3.2
# (PRD FR-9 A/B protocol; SDD §3.6 "compare.sh refuses drift")
#
# compare.sh freshness rule: a baseline that carries prompt_tree_sha is
# refused (exit 2) when it equals the prompt tree under comparison
# (tautological), when its captured_at_commit predates the suite's
# ab.floor_commit (stale), or when the corpus manifest hash drifted.
# --ab mode compares two arm run dirs on recall / false positives / tokens
# and refuses invalid runs (model skew, dirty trees, identical prompt trees).
# =============================================================================

setup() {
  TESTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$TESTS_DIR/../.." && pwd)"
  COMPARE="$REPO_ROOT/evals/harness/compare.sh"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/bf.XXXXXX")"
  # A prompt tree with two commits: floor (c1) and a later one (c2).
  TREE="$T/tree"; mkdir -p "$TREE/.claude"
  ( cd "$TREE" && git init -q \
    && echo a > "$TREE/.claude/a" && git add -A && git -c user.email=t@t -c user.name=t commit -q -m c1 \
    && echo b > "$TREE/.claude/b" && git add -A && git -c user.email=t@t -c user.name=t commit -q -m c2 )
  C1="$(git -C "$TREE" rev-parse HEAD~1)"; C2="$(git -C "$TREE" rev-parse HEAD)"
  TREE_SHA="$(git -C "$TREE" rev-parse HEAD:.claude)"
  OLD_TREE_SHA="$(git -C "$TREE" rev-parse HEAD~1:.claude)"
  # corpus manifest + suite with ab block
  mkdir -p "$T/corpus" "$T/suites"
  echo "abc  pr-01/head.diff" > "$T/corpus/SHA256SUMS"
  CORPUS_SHA="$(sha256sum "$T/corpus/SHA256SUMS" | cut -d' ' -f1)"
  cat > "$T/suites/rr.yaml" <<YAML
name: rr
ab:
  floor_commit: "$C1"
  corpus_manifest: "$T/corpus/SHA256SUMS"
YAML
  cat > "$T/results.jsonl" <<'JSONL'
{"run_id":"r","task_id":"review-pr-01","trial":1,"timestamp":"2026-01-01T00:00:00Z","duration_ms":1,"model_version":"m1","status":"completed","graders":[],"composite":{"strategy":"all_must_pass","pass":true,"score":100},"error":null,"schema_version":1}
JSONL
}

teardown() { find "$T" -mindepth 1 -delete 2>/dev/null || true; rmdir "$T" 2>/dev/null || true; }

baseline() {  # baseline <prompt_tree_sha> <captured_at_commit> <corpus_sha256>
  cat > "$T/rr.baseline.yaml" <<YAML
version: 1
suite: rr
model_version: "m1"
recorded_at: "2026-01-01"
prompt_tree_sha: "$1"
captured_at_commit: "$2"
corpus_sha256: "$3"
tasks:
  review-pr-01:
    pass_rate: 1.0
    trials: 1
    mean_score: 100
    status: active
YAML
}

@test "BF-1 a baseline whose prompt_tree_sha equals the current prompt tree is refused as tautological" {
  baseline "$TREE_SHA" "$C2" "$CORPUS_SHA"
  run "$COMPARE" --results "$T/results.jsonl" --baseline "$T/rr.baseline.yaml" --suite-file "$T/suites/rr.yaml" --prompt-tree "$TREE"
  [ "$status" -eq 2 ]
  grep -qi 'tautological' <<<"$output"
}

@test "BF-2 a baseline captured on a commit that is not a descendant of the suite floor is refused as stale" {
  local root; root="$(git -C "$TREE" rev-list --max-parents=0 HEAD)"
  baseline "$OLD_TREE_SHA" "$root" "$CORPUS_SHA"
  cat > "$T/suites/rr.yaml" <<YAML
name: rr
ab:
  floor_commit: "$C2"
  corpus_manifest: "$T/corpus/SHA256SUMS"
YAML
  run "$COMPARE" --results "$T/results.jsonl" --baseline "$T/rr.baseline.yaml" --suite-file "$T/suites/rr.yaml" --prompt-tree "$TREE"
  [ "$status" -eq 2 ]
  grep -qi 'predates' <<<"$output"
}

@test "BF-3 corpus manifest drift is refused" {
  baseline "$OLD_TREE_SHA" "$C1" "0000000000000000000000000000000000000000000000000000000000000000"
  run "$COMPARE" --results "$T/results.jsonl" --baseline "$T/rr.baseline.yaml" --suite-file "$T/suites/rr.yaml" --prompt-tree "$TREE"
  [ "$status" -eq 2 ]
  grep -qi 'corpus' <<<"$output"
}

@test "BF-4 a fresh baseline (older prompt tree, at/after the floor, same corpus) compares normally" {
  baseline "$OLD_TREE_SHA" "$C1" "$CORPUS_SHA"
  run "$COMPARE" --results "$T/results.jsonl" --baseline "$T/rr.baseline.yaml" --suite-file "$T/suites/rr.yaml" --prompt-tree "$TREE" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.summary.passes')" = "1" ]
}

@test "BF-5 legacy baselines without prompt_tree_sha are untouched by the freshness rule" {
  cat > "$T/legacy.baseline.yaml" <<'YAML'
version: 1
suite: rr
model_version: "m1"
tasks:
  review-pr-01:
    pass_rate: 1.0
    trials: 1
    mean_score: 100
    status: active
YAML
  run "$COMPARE" --results "$T/results.jsonl" --baseline "$T/legacy.baseline.yaml" --json
  [ "$status" -eq 0 ]
}

# ---- --ab mode -------------------------------------------------------------

mk_arm() {  # mk_arm <dir> <model> <tree_sha> <dirty> <recall_pr01> <fp_clean> <tokens>
  mkdir -p "$1"
  local m="$2" sha="$3" dirty="$4" rc="$5" fp="$6" tk="$7"
  {
    jq -cn --arg m "$m" --arg sha "$sha" --argjson dirty "$dirty" --argjson rc "$rc" --argjson tk "$tk" \
      '{run_id:"r",task_id:"review-pr-01",trial:1,status:"completed",model_version:$m,
        executor:{model_id:$m,prompt_tree_sha:$sha,prompt_tree_dirty:$dirty,usage:{input_tokens:$tk,output_tokens:0}},
        graders:[{name:"recall-vs-defects.sh",pass:true,score:100,details:{recall:$rc,planted:3,detected:(if $rc==1 then ["D1","D2","D3"] else ["D1"] end),false_positives:0,tokens:$tk}}],
        composite:{strategy:"all_must_pass",pass:true,score:100}}'
    jq -cn --arg m "$m" --arg sha "$sha" --argjson dirty "$dirty" --argjson fp "$fp" --argjson tk "$tk" \
      '{run_id:"r",task_id:"review-pr-09",trial:1,status:"completed",model_version:$m,
        executor:{model_id:$m,prompt_tree_sha:$sha,prompt_tree_dirty:$dirty,usage:{input_tokens:$tk,output_tokens:0}},
        graders:[{name:"recall-vs-defects.sh",pass:($fp==0),score:100,details:{recall:null,planted:0,detected:[],false_positives:$fp,tokens:$tk}}],
        composite:{strategy:"all_must_pass",pass:($fp==0),score:100}}'
  } > "$1/results.jsonl"
}

@test "BF-6 --ab passes when recall holds, false positives do not rise and (audit) tokens halve" {
  mk_arm "$T/a" m1 "$OLD_TREE_SHA" false 0.3333 1 1000
  mk_arm "$T/b" m1 "$TREE_SHA" false 1 0 400
  run "$COMPARE" --ab --arm-a "$T/a" --arm-b "$T/b" --metric audit --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.valid')" = "true" ]
  [ "$(echo "$output" | jq -r '[.gates[].pass] | all')" = "true" ]
  [ "$(echo "$output" | jq -r '.gates[] | select(.name=="recall") | .b == 1')" = "true" ]
  [ "$(echo "$output" | jq -r '.gates[] | select(.name=="tokens_ratio") | .pass')" = "true" ]
}

@test "BF-7 --ab fails the recall gate when arm B drops more than 0.1 below arm A" {
  mk_arm "$T/a" m1 "$OLD_TREE_SHA" false 1 0 1000
  mk_arm "$T/b" m1 "$TREE_SHA" false 0.3333 0 1000
  run "$COMPARE" --ab --arm-a "$T/a" --arm-b "$T/b" --metric recall --json
  [ "$status" -eq 1 ]
  [ "$(echo "$output" | jq -r '.gates[] | select(.name=="recall") | .pass')" = "false" ]
  [ "$(echo "$output" | jq -r '.gates[] | select(.name=="false_positives") | .pass')" = "true" ]
}

@test "BF-8 --ab is invalid on model skew, a dirty prompt tree, or identical prompt trees" {
  mk_arm "$T/a" m1 "$OLD_TREE_SHA" false 1 0 1000
  mk_arm "$T/b" m2 "$TREE_SHA" false 1 0 1000
  run "$COMPARE" --ab --arm-a "$T/a" --arm-b "$T/b" --metric recall --json
  [ "$status" -eq 2 ]
  [ "$(echo "$output" | jq -r '.valid')" = "false" ]
  mk_arm "$T/b" m1 "$TREE_SHA" true 1 0 1000
  run "$COMPARE" --ab --arm-a "$T/a" --arm-b "$T/b" --metric recall --json
  [ "$status" -eq 2 ]
  mk_arm "$T/b" m1 "$OLD_TREE_SHA" false 1 0 1000
  run "$COMPARE" --ab --arm-a "$T/a" --arm-b "$T/b" --metric recall --json
  [ "$status" -eq 2 ]
}

@test "BF-9 --update-baseline records prompt_tree_sha, captured_at_commit, executor_model and corpus_sha256" {
  mk_arm "$T/a" m1 "$TREE_SHA" false 1 0 1000
  run "$COMPARE" --results "$T/a/results.jsonl" --suite rr --suite-file "$T/suites/rr.yaml" --prompt-tree "$TREE" --update-baseline --reason "test" --baseline-out "$T/out.yaml"
  [ "$status" -eq 0 ]
  [ "$(yq -r '.prompt_tree_sha' "$T/out.yaml")" = "$TREE_SHA" ]
  [ "$(yq -r '.captured_at_commit' "$T/out.yaml")" = "$C2" ]
  [ "$(yq -r '.executor_model' "$T/out.yaml")" = "m1" ]
  [ "$(yq -r '.corpus_sha256' "$T/out.yaml")" = "$CORPUS_SHA" ]
  [ "$(yq -r '.tasks."review-pr-01".recall == 1' "$T/out.yaml")" = "true" ]
  [ "$(yq -r '.tasks."review-pr-09".false_positives' "$T/out.yaml")" = "0" ]
  # results.jsonl is JSONL, not an array: the first-row reads must slurp
  [ "$(yq -r '.model_version' "$T/out.yaml")" = "m1" ]
  [ "$(yq -r '.recorded_from_run' "$T/out.yaml")" = "r" ]
}
