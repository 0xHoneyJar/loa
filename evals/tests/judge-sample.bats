#!/usr/bin/env bats
# =============================================================================
# evals/tests/judge-sample.bats — cycle-132 Sprint 1 Task 1.8 (FR-4, SDD §1.4, SKP-007/SKP-023)
#
# judge-sample.sh over a synthetic repo (one PR fixture, a manifest with three defects, a suite
# task) and synthetic run directories (gates-combined.md + review.md): the universe classes and
# strata counts, the inclusion probabilities, the min-total raise, determinism by seed, packets
# without provenance (a provenance-bearing finding refuses with nothing written), the
# grader-consistency count, the valid-cells universe, usage; PR-native arm ids and field lines
# exempt (recorded in key.json provenance_exempt), batch names and run ids never.
# =============================================================================

setup() {
  TESTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$TESTS_DIR/../.." && pwd)"
  JS="$REPO_ROOT/evals/harness/judge-sample.sh"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/js.XXXXXX")"
  R="$T/repo"; RES="$T/results"
  mkdir -p "$R/evals/fixtures/review-prs/pr-90/head" "$R/evals/fixtures/review-prs/manifests" \
           "$R/grimoires/loa/evals/ablation-test/tasks/review-x"
  for i in $(seq 1 60); do printf 'echo f line %d\n' "$i"; done > "$R/evals/fixtures/review-prs/pr-90/head/f.sh"
  for i in $(seq 1 60); do printf 'echo g line %d\n' "$i"; done > "$R/evals/fixtures/review-prs/pr-90/head/g.sh"
  cat > "$R/evals/fixtures/review-prs/manifests/pr-90.json" <<'J'
{"fixture": "pr-90", "defects": [
 {"id": "D01-off-by-one-in-the-loop", "file": "f.sh", "anchor_line": 10, "must_match": "echo f line 10", "severity": "high"},
 {"id": "D02-unquoted-expansion", "file": "f.sh", "anchor_line": 30, "anchors": [30], "description": "the expansion is unquoted", "severity": "medium"},
 {"id": "D03-missing-guard", "file": "g.sh", "anchor_line": 5, "severity": "low"}]}
J
  printf 'id: review-x\ntype: review-catch\nreview_catch: {fixture: review-prs/pr-90, manifest: evals/fixtures/review-prs/manifests/pr-90.json}\n' \
    > "$R/grimoires/loa/evals/ablation-test/tasks/review-x/task.yaml"
  cell a1_full 1 head/f.sh:11 head/f.sh:22 head/f.sh:55
  cell a1_full 2 head/f.sh:11 head/f.sh:22 head/f.sh:55
  cell a0_bare 1 head/f.sh:31 head/g.sh:40
  { row a1_full 1 '["d2","d3"]'; row a1_full 2 '["d2","d3"]'; row a0_bare 1 '["d1","d3"]'; } > "$T/rows.jsonl"
  ARGS=(--rows "$T/rows.jsonl" --results-root "$RES" --repo-root "$R" --seed 20261021)
}

cell() {  # cell <arm> <trial> <gates lines…>
  local d="$RES/b1/$1/review-x-t$2"; shift 2
  mkdir -p "$d/grading" "$d/sandbox"
  printf '%s\n' "$@" > "$d/grading/gates-combined.md"
  printf '# Review\n\nThe loop at `head/f.sh:11` is off by one.\n\nThe guard at head/g.sh:40 is never reached.\n\nUnquoted at head/f.sh:31 and head/f.sh:22.\n' > "$d/sandbox/review.md"
}

row() {  # row <arm> <trial> <missed json>
  printf '{"batch":"b1","arm":"%s","task_id":"review-x","task_type":"review-catch","trial":%s,"run_id":"b1-%s-review-x-t%s","status":"completed","defects_seeded":3,"defects_missed_pm3":%s}\n' \
    "$1" "$2" "$1" "$2" "$3"
}

@test "JS-1 strata: universe classes, N and n per arm × task × class, inclusion probability" {
  run bash "$JS" "${ARGS[@]}" --out "$T/o" --per-stratum 1 --min-total 0
  [ "$status" -eq 0 ]
  [[ "$output" == *$'a0_bare|review-x|credited\t1\t1\t1.0000'* ]]
  [[ "$output" == *$'a0_bare|review-x|far-miss\t2\t1\t0.5000'* ]]
  [[ "$output" == *$'a0_bare|review-x|stray\t1\t1\t1.0000'* ]]
  [[ "$output" == *$'a1_full|review-x|credited\t2\t1\t0.5000'* ]]
  [[ "$output" == *$'a1_full|review-x|near-miss\t2\t1\t0.5000'* ]]
  [[ "$output" == *$'a1_full|review-x|stray\t2\t1\t0.5000'* ]]
  [[ "$output" == *$'a1_full|review-x|far-miss\t2\t1\t0.5000'* ]]
  [[ "$output" == *$'total\t12\t7'* ]]
  [[ "$output" != *grader-consistency* ]]
  [ "$(ls "$T/o/packets" | wc -l)" -eq 7 ]
  run jq -r '.universe | length' "$T/o/key.json"
  [ "$output" = 12 ]
  run jq -r '[.universe[] | select(.class == "near-miss")][0].defect' "$T/o/key.json"
  [ "$output" = d2 ]
}

@test "JS-2 the per-stratum cap rises uniformly until the minimum total is met" {
  run bash "$JS" "${ARGS[@]}" --out "$T/o" --per-stratum 1 --min-total 12
  [ "$status" -eq 0 ]
  [[ "$output" == *$'total\t12\t12'* ]]
  run jq -r '.per_stratum_used' "$T/o/key.json"
  [ "$output" = 2 ]
}

@test "JS-3 deterministic by seed; another seed changes the draw" {
  bash "$JS" "${ARGS[@]}" --out "$T/a" --per-stratum 1 --min-total 0 >/dev/null
  bash "$JS" "${ARGS[@]}" --out "$T/b" --per-stratum 1 --min-total 0 >/dev/null
  diff -r "$T/a" "$T/b"
  bash "$JS" --rows "$T/rows.jsonl" --results-root "$RES" --repo-root "$R" --seed 7 --out "$T/c" --per-stratum 1 --min-total 0 >/dev/null
  run diff -q "$T/a/key.json" "$T/c/key.json"
  [ "$status" -eq 1 ]
}

@test "JS-4 packets carry no provenance; the key stays outside the packets" {
  run bash "$JS" "${ARGS[@]}" --out "$T/o" --per-stratum 5 --min-total 0
  [ "$status" -eq 0 ]
  run grep -rlE 'a1_full|a0_bare|b1-|b1/|review-x|credited|near-miss|far-miss|stray|^[[:space:]]*(arm|trial|batch|run_id)[[:space:]]*:' "$T/o/packets"
  [ "$status" -eq 1 ]
  [ ! -e "$T/o/packets/key.json" ]
  grep -q 'The loop at `head/f.sh:11` is off by one.' "$T"/o/packets/*.md
  grep -q 'the expansion is unquoted' "$T"/o/packets/*.md
  grep -q '    11  echo f line 11' "$T"/o/packets/*.md
}

@test "JS-5 a finding that names an arm refuses with exit 1 and writes nothing" {
  printf '# Review\n\nArm a1_full saw the loop at `head/f.sh:11` off by one.\n' > "$RES/b1/a1_full/review-x-t1/sandbox/review.md"
  run bash "$JS" "${ARGS[@]}" --out "$T/o" --per-stratum 5 --min-total 0
  [ "$status" -eq 1 ]
  [[ "$output" == *"provenance field"* ]]
  [ ! -e "$T/o" ]
}

@test "JS-6 a row whose missed set disagrees with the ±3 credits is counted" {
  { row a1_full 1 '["d1","d2","d3"]'; row a1_full 2 '["d2","d3"]'; row a0_bare 1 '["d1","d3"]'; } > "$T/rows.jsonl"
  run bash "$JS" "${ARGS[@]}" --out "$T/o"
  [ "$status" -eq 0 ]
  [[ "$output" == *"grader-consistency: 1 cell(s)"* ]]
  run jq -r '.grader_mismatch_cells' "$T/o/key.json"
  [ "$output" = 1 ]
}

@test "JS-7 usage errors exit 2; a task without task.yaml exits 1" {
  run bash "$JS" --rows "$T/rows.jsonl" --results-root "$RES" --out "$T/o"
  [ "$status" -eq 2 ]
  run bash "$JS" "${ARGS[@]}" --out "$T/o" --per-stratum 0
  [ "$status" -eq 2 ]
  rm "$R/grimoires/loa/evals/ablation-test/tasks/review-x/task.yaml"
  run bash "$JS" "${ARGS[@]}" --out "$T/o"
  [ "$status" -eq 1 ]
  [ ! -e "$T/o" ]
}

@test "JS-8 the universe holds valid cells only; --all-cells enumerates the rest" {
  { row a1_full 1 '["d2","d3"]'; row a1_full 2 '["d2","d3"]' | sed 's/"completed"/"agent_error"/'; row a0_bare 1 '["d1","d3"]'; } > "$T/rows.jsonl"
  run bash "$JS" "${ARGS[@]}" --out "$T/o" --per-stratum 1 --min-total 0
  [ "$status" -eq 0 ]
  [[ "$output" == *$'a1_full|review-x|credited\t1\t1\t1.0000'* ]]
  [[ "$output" == *$'total\t8\t7'* ]]
  run jq -r '.invalid_cells_skipped' "$T/o/key.json"
  [ "$output" = 1 ]
  run bash "$JS" "${ARGS[@]}" --out "$T/o2" --per-stratum 1 --min-total 0 --all-cells
  [ "$status" -eq 0 ]
  [[ "$output" == *$'total\t12\t7'* ]]
}

review_t1() {  # review_t1 <text appended to the cited paragraph>
  printf '# Review\n\nThe loop at `head/f.sh:11` is off by one. %s\n' "$1" > "$RES/b1/a1_full/review-x-t1/sandbox/review.md"
}

@test "JS-9 an arm id the PR fixture itself carries is exempt and recorded; packets unchanged" {
  printf '# PR\n\nAdds the a1_full arm to the harness.\n' > "$R/evals/fixtures/review-prs/pr-90/PR.md"
  review_t1 'The new a1_full arm label is hard-coded.'
  run bash "$JS" "${ARGS[@]}" --out "$T/o" --per-stratum 5 --min-total 0
  [ "$status" -eq 0 ]
  [[ "$output" == *"provenance exemptions: 1 (pr_native)"* ]]
  run jq -c '.provenance_exempt | map([.token, .reason])' "$T/o/key.json"
  [ "$output" = '[["a1_full","pr_native"]]' ]
  jid="$(jq -r '.provenance_exempt[0].item' "$T/o/key.json")"
  grep -q 'The new a1_full arm label is hard-coded.' "$T/o/packets/$jid.md"
}

@test "JS-10 an exemption from a file under head/ counts too; absent from the PR, the same id refuses" {
  echo '# a0_bare a1_full' > "$R/evals/fixtures/review-prs/pr-90/head/arms.txt"
  review_t1 'The a1_full arm label is hard-coded.'
  run bash "$JS" "${ARGS[@]}" --out "$T/o" --per-stratum 5 --min-total 0
  [ "$status" -eq 0 ]
  rm "$R/evals/fixtures/review-prs/pr-90/head/arms.txt"
  ln -s /dev/null "$R/evals/fixtures/review-prs/pr-90/PR.md"
  run bash "$JS" "${ARGS[@]}" --out "$T/o2" --per-stratum 5 --min-total 0
  [ "$status" -eq 1 ]
  [[ "$output" == *"provenance field (a1_full)"* ]]
  [ ! -e "$T/o2" ]
}

@test "JS-11 a batch name or run id refuses even when the PR fixture carries it" {
  printf 'b1 b1-a1_full-review-x-t1 a1_full\n' > "$R/evals/fixtures/review-prs/pr-90/head.diff"
  review_t1 'Seen in run b1-a1_full-review-x-t1.'
  run bash "$JS" "${ARGS[@]}" --out "$T/o" --per-stratum 5 --min-total 0
  [ "$status" -eq 1 ]
  [[ "$output" == *"provenance field (b1"* ]]
  [ ! -e "$T/o" ]
  review_t1 'From batch b1 only.'
  run bash "$JS" "${ARGS[@]}" --out "$T/o" --per-stratum 5 --min-total 0
  [ "$status" -eq 1 ]
  [[ "$output" == *"provenance field (b1)"* ]]
  [ ! -e "$T/o" ]
}

@test "JS-12 a field line is exempt only when the whole line occurs verbatim in the PR" {
  printf '# PR\n\n  arm: a1_full\n' > "$R/evals/fixtures/review-prs/pr-90/PR.md"
  printf '# Review\n\nThe loop at `head/f.sh:11` is off by one; the config says\narm: a1_full\n' > "$RES/b1/a1_full/review-x-t1/sandbox/review.md"
  run bash "$JS" "${ARGS[@]}" --out "$T/o" --per-stratum 5 --min-total 0
  [ "$status" -eq 0 ]
  [[ "$output" == *"provenance exemptions: 2 (pr_native)"* ]]
  run jq -c '[.provenance_exempt[].token]' "$T/o/key.json"
  [ "$output" = '["a1_full","arm: a1_full"]' ]
  printf '# PR\n\narm = a1_full\n' > "$R/evals/fixtures/review-prs/pr-90/PR.md"
  run bash "$JS" "${ARGS[@]}" --out "$T/o2" --per-stratum 5 --min-total 0
  [ "$status" -eq 1 ]
  [[ "$output" == *"provenance field (arm:)"* ]]
  [ ! -e "$T/o2" ]
}

@test "JS-13 exemptions are deterministic: two runs byte-identical" {
  printf '# PR\n\narm: a1_full\n' > "$R/evals/fixtures/review-prs/pr-90/PR.md"
  printf '# Review\n\nThe loop at `head/f.sh:11` is off by one (a1_full).\narm: a1_full\n' | tee "$RES/b1/a1_full/review-x-t1/sandbox/review.md" > "$RES/b1/a1_full/review-x-t2/sandbox/review.md"
  bash "$JS" "${ARGS[@]}" --out "$T/a" --per-stratum 5 --min-total 0 >/dev/null
  bash "$JS" "${ARGS[@]}" --out "$T/b" --per-stratum 5 --min-total 0 >/dev/null
  diff -r "$T/a" "$T/b"
  run jq -r '.provenance_exempt | length' "$T/a/key.json"
  [ "$output" = 4 ]
  run jq -c '.provenance_exempt == (.provenance_exempt | sort_by(.item, .token))' "$T/a/key.json"
  [ "$output" = true ]
}
