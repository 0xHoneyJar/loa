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

fixture_y() {  # a second PR whose defect file is nested; review-y's cell cites partial paths
  local h="$R/evals/fixtures/review-prs/pr-91/head"
  mkdir -p "$h/lib" "$h/a" "$h/b" "$h/docs" "$R/grimoires/loa/evals/ablation-test/tasks/review-y"
  for i in $(seq 1 60); do printf 'echo h line %d\n' "$i"; done > "$h/lib/h.sh"
  for i in $(seq 1 60); do printf 'doc line %d\n' "$i"; done > "$h/docs/only.md"
  for i in $(seq 1 9); do printf 'echo k line %d\n' "$i"; done | tee "$h/a/k.sh" > "$h/b/k.sh"
  printf '# PR 91\n\nSummary line two.\nThe PR description line three.\n' > "$R/evals/fixtures/review-prs/pr-91/PR.md"
  printf '{"fixture": "pr-91", "defects": [{"id": "D01-nested", "file": "lib/h.sh", "anchor_line": 10, "description": "the nested defect", "severity": "high"}]}\n' \
    > "$R/evals/fixtures/review-prs/manifests/pr-91.json"
  printf 'id: review-y\ntype: review-catch\nreview_catch: {fixture: review-prs/pr-91, manifest: evals/fixtures/review-prs/manifests/pr-91.json}\n' \
    > "$R/grimoires/loa/evals/ablation-test/tasks/review-y/task.yaml"
  local d="$RES/b1/a1_full/review-y-t1"
  mkdir -p "$d/grading" "$d/sandbox"
  printf '%s\n' h.sh:10 only.md:20 k.sh:5 pr/PR.md:3 lib/h.sh:40 > "$d/grading/gates-combined.md"
  printf '# Review\n\nOff by one at h.sh:10.\n\nStale doc at only.md:20.\n\nBad k at k.sh:5.\n\nPR text at PR.md:3.\n\nDead code at lib/h.sh:40.\n' > "$d/sandbox/review.md"
  row a1_full 1 '[]' | sed 's/review-x/review-y/g; s/"defects_seeded":3/"defects_seeded":1/'
}

item_for() {  # item_for <dir> <cited path> → the item id whose region cites it
  jq -r --arg p "$2" '.items | to_entries[] | select(.value.region[0] == $p) | .key' "$1/key.json"
}

@test "JS-14 cited paths resolve the way the grader credits them" {
  fixture_y > "$T/rows-y.jsonl"
  run bash "$JS" --rows "$T/rows-y.jsonl" --results-root "$RES" --repo-root "$R" --seed 20261021 --out "$T/o" --per-stratum 5 --min-total 0
  [ "$status" -eq 0 ]
  [[ "$output" == *"cited paths: exact=1 defect_suffix=1 unique_suffix=1 pr_file=1 unresolved=1 no_region=0"* ]]
  # a credited unit citing its defect file's basename → the defect file's lines
  j="$(item_for "$T/o" h.sh)"
  [ "$(jq -r --arg j "$j" '.items[$j] | .class + " " + .cited_path_resolution' "$T/o/key.json")" = "credited defect_suffix" ]
  grep -qF '## Cited lines: head/lib/h.sh:10-10 (±5; cited as h.sh)' "$T/o/packets/$j.md"
  grep -qF '    10  echo h line 10' "$T/o/packets/$j.md"
  # a stray with exactly one suffix match → printed
  j="$(item_for "$T/o" only.md)"
  [ "$(jq -r --arg j "$j" '.items[$j] | .class + " " + .cited_path_resolution' "$T/o/key.json")" = "stray unique_suffix" ]
  grep -qF '## Cited lines: head/docs/only.md:20-20 (±5; cited as only.md)' "$T/o/packets/$j.md"
  grep -qF '    20  doc line 20' "$T/o/packets/$j.md"
  # two suffix matches → today's text
  j="$(item_for "$T/o" k.sh)"
  [ "$(jq -r --arg j "$j" '.items[$j].cited_path_resolution' "$T/o/key.json")" = unresolved ]
  grep -qF '## Cited lines: head/k.sh:5-5 (±5)' "$T/o/packets/$j.md"
  grep -qF "(the file is not in the PR's head tree)" "$T/o/packets/$j.md"
  run grep -q 'echo k line' "$T/o/packets/$j.md"
  [ "$status" -eq 1 ]
  # pr/PR.md → the fixture's PR.md
  j="$(item_for "$T/o" pr/PR.md)"
  [ "$(jq -r --arg j "$j" '.items[$j].cited_path_resolution' "$T/o/key.json")" = pr_file ]
  grep -qF '## Cited lines: PR.md:3-3 (±5; cited as pr/PR.md)' "$T/o/packets/$j.md"
  grep -qF '     3  Summary line two.' "$T/o/packets/$j.md"
  # an exact path is unchanged
  j="$(item_for "$T/o" lib/h.sh)"
  [ "$(jq -r --arg j "$j" '.items[$j].cited_path_resolution' "$T/o/key.json")" = exact ]
  grep -qF '## Cited lines: head/lib/h.sh:40-40 (±5)' "$T/o/packets/$j.md"
}

@test "JS-15 resolution leaves the sampling untouched: universe, strata, π, items and order match the pre-change key" {
  { cat "$T/rows.jsonl"; fixture_y; } > "$T/rows-xy.jsonl"
  bash "$JS" --rows "$T/rows-xy.jsonl" --results-root "$RES" --repo-root "$R" --seed 20261021 --out "$T/o" --per-stratum 1 --min-total 0 >/dev/null
  # sampling-baseline.json = the key.json judge-sample.sh wrote before cited-path resolution
  # (base 9f5746b3) on this same fixture and these arguments
  diff <(jq -S 'del(.items[].cited_path_resolution, .items[].description_source)' "$T/o/key.json") \
       <(jq -S . "$TESTS_DIR/fixtures/judge-sample/sampling-baseline.json")
  run jq -r '[.items[] | select(.cited_path_resolution == null and .region != null)] | length' "$T/o/key.json"
  [ "$output" = 0 ]
}

@test "JS-16 resolution is deterministic: two runs byte-identical" {
  { cat "$T/rows.jsonl"; fixture_y; } > "$T/rows-xy.jsonl"
  bash "$JS" --rows "$T/rows-xy.jsonl" --results-root "$RES" --repo-root "$R" --seed 20261021 --out "$T/a" --per-stratum 5 --min-total 0 > "$T/a.out"
  bash "$JS" --rows "$T/rows-xy.jsonl" --results-root "$RES" --repo-root "$R" --seed 20261021 --out "$T/b" --per-stratum 5 --min-total 0 > "$T/b.out"
  diff -r "$T/a" "$T/b"
  diff "$T/a.out" "$T/b.out"
}

descriptions() {  # a defect-descriptions.py output naming pr-90's D01 and D03 (D02 absent)
  cat > "$T/descs.json" <<'J'
{"schema_version": 1, "fixtures": {"pr-90": {
 "D01-off-by-one-in-the-loop": {"text": "Fixing change H01 — the loop bound runs one past the end (category: logic; severity: high)", "sources": ["hunk:H01"], "n_descriptions": 1},
 "D03-missing-guard": {"text": "Incident I01 — the guard is missing", "sources": ["incident:I01"], "n_descriptions": 1}}}}
J
}

@test "JS-17 --descriptions: the packet carries the annotators' text; key.json records description_source; sampling identical" {
  descriptions
  bash "$JS" "${ARGS[@]}" --out "$T/a" --per-stratum 5 --min-total 0 > "$T/a.out"
  run bash "$JS" "${ARGS[@]}" --out "$T/b" --per-stratum 5 --min-total 0 --descriptions "$T/descs.json"
  [ "$status" -eq 0 ]
  counts="$output"
  grep -qF 'Description: Fixing change H01 — the loop bound runs one past the end (category: logic; severity: high)' "$T"/b/packets/*.md
  grep -qF 'Description: Incident I01 — the guard is missing' "$T"/b/packets/*.md
  grep -qF 'Description: the expansion is unquoted' "$T"/b/packets/*.md
  run grep -rF 'Description: off by one in the loop' "$T/b/packets"
  [ "$status" -eq 1 ]
  run jq -r '[.items[] | select(.defect == "d1" or .defect == "d3") | .description_source] | unique | join(",")' "$T/b/key.json"
  [ "$output" = annotators ]
  run jq -r '[.items[] | select(.defect == "d2") | .description_source] | unique | join(",")' "$T/b/key.json"
  [ "$output" = manifest ]
  run jq -r '[.items[] | select(.class == "stray") | .description_source] | unique | map(tostring) | join(",")' "$T/b/key.json"
  [ "$output" = null ]
  n_ann="$(jq '[.items[] | select(.description_source == "annotators")] | length' "$T/b/key.json")"
  n_man="$(jq '[.items[] | select(.description_source == "manifest")] | length' "$T/b/key.json")"
  n_str="$(jq '[.items[] | select(.description_source == null)] | length' "$T/b/key.json")"
  [[ "$counts" == *"descriptions: annotators=$n_ann manifest=$n_man id_fallback=0 stray=$n_str"* ]]
  [ "$n_ann" -gt 0 ]
  # universe, strata, π, items and order identical with and without the flag
  diff <(jq -S 'del(.items[].description_source)' "$T/a/key.json") <(jq -S 'del(.items[].description_source)' "$T/b/key.json")
  # only the Description lines differ between the two packet sets
  for f in "$T"/a/packets/*.md; do
    diff <(grep -v '^Description: ' "$f") <(grep -v '^Description: ' "$T/b/packets/$(basename "$f")")
  done
}

@test "JS-18 without --descriptions: today's fallback text, id_fallback/manifest sources, no counts line" {
  run bash "$JS" "${ARGS[@]}" --out "$T/o" --per-stratum 5 --min-total 0
  [ "$status" -eq 0 ]
  [[ "$output" != *"descriptions:"* ]]
  grep -qF 'Description: off by one in the loop' "$T"/o/packets/*.md
  run jq -r '[.items[] | select(.defect == "d1" or .defect == "d3") | .description_source] | unique | join(",")' "$T/o/key.json"
  [ "$output" = id_fallback ]
}

@test "JS-19 --descriptions: an arm id in the text refuses unless the PR carries it; a bad file exits 1" {
  descriptions
  sed -i 's/the guard is missing/the a0_bare guard is missing/' "$T/descs.json"
  run bash "$JS" "${ARGS[@]}" --out "$T/o" --per-stratum 5 --min-total 0 --descriptions "$T/descs.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"provenance field (a0_bare)"* ]]
  [ ! -e "$T/o" ]
  printf '# PR\n\nAdds the a0_bare arm.\n' > "$R/evals/fixtures/review-prs/pr-90/PR.md"
  run bash "$JS" "${ARGS[@]}" --out "$T/o" --per-stratum 5 --min-total 0 --descriptions "$T/descs.json"
  [ "$status" -eq 0 ]
  echo '{"fixtures": {}}' > "$T/bad.json"
  run bash "$JS" "${ARGS[@]}" --out "$T/o2" --per-stratum 5 --min-total 0 --descriptions "$T/bad.json"
  [ "$status" -eq 1 ]
  [ ! -e "$T/o2" ]
  run bash "$JS" "${ARGS[@]}" --out "$T/o2" --per-stratum 5 --min-total 0 --descriptions "$T/none.json"
  [ "$status" -eq 1 ]
}

# --- loa-smol judge-v2 addendum 1: the citing-bullet rule replaces the 1,500-character cut -------------------------
item_at() {  # item_at <dir> <cell key> <cited path> <start line> → the item id of that cell's unit citing the region
  jq -r --arg c "$2" --arg p "$3" --argjson a "$4" '.items | to_entries[] | select(.value.cell == $c and .value.region[0] == $p and .value.region[1] == $a) | .key' "$1/key.json"
}

@test "JS-20 a citing paragraph over 1,500 chars shows the citing bullet(s) under the list note; a long paragraph without list structure is shown whole; 6,000 chars cap" {
  # t1: a 12-bullet list, the citing bullet last and past 1,500 chars — the cycle-132 cut hid it
  { printf '# Review\n\n'; for i in $(seq 1 11); do printf -- '- Bullet %d: %s head/g.sh:%d.\n' "$i" "$(printf 'filler %.0s' $(seq 1 20))" "$((40 + i % 3))"; done
    printf -- '- The loop at `head/f.sh:11` is off by one: THE CITING BULLET.\n'; } > "$RES/b1/a1_full/review-x-t1/sandbox/review.md"
  # t2: one 1,700-char paragraph with no bullet structure citing the region → shown whole
  printf '# Review\n\nThe loop at `head/f.sh:11` is off by one. %s END OF PARAGRAPH\n' "$(printf 'words %.0s' $(seq 1 280))" > "$RES/b1/a1_full/review-x-t2/sandbox/review.md"
  run bash "$JS" "${ARGS[@]}" --out "$T/o" --per-stratum 5 --min-total 0
  [ "$status" -eq 0 ]
  j="$(item_at "$T/o" b1/a1_full/review-x/1 head/f.sh 11)"
  [ -n "$j" ]
  grep -qF '(the citing bullet(s) of a 12-line list; ' "$T/o/packets/$j.md"
  grep -qF 'THE CITING BULLET' "$T/o/packets/$j.md"
  run grep -c 'Bullet 1:' "$T/o/packets/$j.md"
  [ "$output" = 0 ]
  run grep -c ' …' "$T/o/packets/$j.md"
  [ "$output" = 0 ]
  # the note's counts are the shown and the whole paragraph's characters
  run python3 -I - "$T/o/packets/$j.md" "$RES/b1/a1_full/review-x-t1/sandbox/review.md" <<'PY'
import re, sys
pk, rv = open(sys.argv[1]).read(), open(sys.argv[2]).read()
para = [p.strip() for p in re.split(r"\n\s*\n", rv) if p.strip()][1]
m = re.search(r"\(the citing bullet\(s\) of a (\d+)-line list; (\d+) of (\d+) chars shown\)\n(.*?)\n```", pk, re.S)
assert m, pk
assert int(m.group(1)) == 12 and int(m.group(3)) == len(para) and int(m.group(2)) == len(m.group(4)) < 1500, m.groups()[:3]
print("ok")
PY
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  j="$(item_at "$T/o" b1/a1_full/review-x/2 head/f.sh 11)"
  grep -qF 'END OF PARAGRAPH' "$T/o/packets/$j.md"
  run grep -c 'citing bullet(s)\| …' "$T/o/packets/$j.md"
  [ "$output" = 0 ]
  # the cap: a citing bullet of 7,000 chars in a two-bullet list is cut at 6,000 with " …"
  { printf '# Review\n\n- Other at head/g.sh:40.\n- The loop at `head/f.sh:11` is off by one. %s\n' "$(printf 'x%.0s' $(seq 1 7000))"; } > "$RES/b1/a1_full/review-x-t1/sandbox/review.md"
  bash "$JS" "${ARGS[@]}" --out "$T/o2" --per-stratum 5 --min-total 0 >/dev/null
  j="$(item_at "$T/o2" b1/a1_full/review-x/1 head/f.sh 11)"
  run python3 -I - "$T/o2/packets/$j.md" <<'PY'
import re, sys
pk = open(sys.argv[1]).read()
m = re.search(r"## Finding\n\n`{3,} text\n(.*?)\n`{3,}\n", pk, re.S)
t = m.group(1)
assert t.startswith("(the citing bullet(s) of a 2-line list; ") and t.endswith(" …") and len(t) == 6002, (len(t), t[:80])
print("ok")
PY
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}
