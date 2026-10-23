#!/usr/bin/env bats
# =============================================================================
# evals/tests/defect-descriptions.bats — cycle-132 addendum 14
#
# defect-descriptions.py over a tiny synthetic tree (one v2 manifest with a multi-hunk defect and
# an incident defect, two annotators' labels, a lead adjudication; one source id with no record):
# the text per defect, both annotators' descriptions deduplicated A first, the missing-record
# clause and its stderr count, determinism, the refusal on an arm token absent from the PR content
# (and its PR-native whole-token exemption; --forbid tokens never exempt — round 9), a non-object
# manifest defect and unreadable PR content refused, usage.
# =============================================================================

setup() {
  TESTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  DD="$(cd "$TESTS_DIR/../harness" && pwd)/defect-descriptions.py"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/dd.XXXXXX")"
  M="$T/review-prs/manifests"; AN="$T/annotation"
  mkdir -p "$M" "$T/review-prs/pr-90/head" "$AN/pr-90/A" "$AN/pr-90/B"
  printf '# PR 90\n\nA small change.\n' > "$T/review-prs/pr-90/PR.md"
  cat > "$M/pr-90.json" <<'J'
{"fixture": "pr-90", "label_set": "v2", "defects": [
 {"id": "V01", "file": "f.sh", "anchor_line": 10, "severity": "high", "category": "logic", "source": "hunk:H01,H02"},
 {"id": "V02", "file": "f.sh", "anchor_line": 30, "severity": "low", "source": "hunk:H03;incident:I01"}]}
J
  cat > "$AN/pr-90/A/labels.json" <<'J'
{"hunks": {"H01": {"verdict": "defect", "description": "The loop runs   one past the end."},
           "H03": {"verdict": "defect", "description": "The expansion is unquoted."}},
 "incidents": {"I01": {"verdict": "defect-at-head", "description": "Users saw a crash."}}}
J
  cat > "$AN/pr-90/B/labels.json" <<'J'
{"hunks": {"H01": {"verdict": "defect", "description": "The loop runs one past the end."},
           "H03": {"verdict": "defect", "description": "Word splitting on the path."}},
 "incidents": {"I01": {"verdict": "defect-at-head", "description": ""}}}
J
  printf '{"H03": {"base": "A", "reason": "severity: codebook low"}}\n' > "$AN/pr-90/decisions.json"
  ARGS=(--manifests-dir "$M" --annotation-root "$AN" --fixtures pr-90)
}

@test "DD-1 text per defect: multi-hunk clauses, both annotators deduplicated, the missing record, the lead reason" {
  run python3 -I "$DD" "${ARGS[@]}" --out "$T/o.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 fixture(s), 2 defect(s), 4 source id(s); 1 source id(s) without an annotator description"* ]]
  run jq -r '.fixtures["pr-90"].V01.text' "$T/o.json"
  [ "$output" = "Fixing change H01 — The loop runs one past the end. | H02: no annotator description (category: logic; severity: high)" ]
  run jq -r '.fixtures["pr-90"].V02.text' "$T/o.json"
  [ "$output" = "Fixing change H03 — The expansion is unquoted.; Word splitting on the path. | Incident I01 — Users saw a crash. (severity: low)" ]
  run jq -c '[.schema_version, .fixtures["pr-90"].V01.sources, .fixtures["pr-90"].V01.n_descriptions, .fixtures["pr-90"].V02.sources, .fixtures["pr-90"].V02.n_descriptions]' "$T/o.json"
  [ "$output" = '[1,["hunk:H01","hunk:H02"],1,["hunk:H03","incident:I01"],3]' ]
  run grep -cE '"(A|B)"|annotator A|annotator B' "$T/o.json"
  [ "$output" = 0 ]
}

@test "DD-2 deterministic: two runs byte-identical" {
  python3 -I "$DD" "${ARGS[@]}" --out "$T/a.json" 2>/dev/null
  python3 -I "$DD" "${ARGS[@]}" --out "$T/b.json" 2>/dev/null
  cmp "$T/a.json" "$T/b.json"
}

@test "DD-3 a missing annotation directory: every clause reads no annotator description" {
  rm -r "$AN/pr-90"
  run python3 -I "$DD" "${ARGS[@]}" --out "$T/o.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"4 source id(s) without an annotator description; 0 defect(s) with annotator text, 2 without"* ]]
  run jq -r '.fixtures["pr-90"].V01 | "\(.n_descriptions) \(.text)"' "$T/o.json"
  [ "$output" = "0 H01: no annotator description | H02: no annotator description (category: logic; severity: high)" ]
}

@test "DD-4 an arm token absent from the PR content refuses with nothing written; present in the PR, exempt" {
  sed -i 's/Users saw a crash./The a1_full trial crashed./' "$AN/pr-90/A/labels.json"
  run python3 -I "$DD" "${ARGS[@]}" --out "$T/o.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"provenance token (a1_full, trial)"* ]]
  [ ! -e "$T/o.json" ]
  printf 'the a1_full trial\n' > "$T/review-prs/pr-90/head/arms.txt"
  run python3 -I "$DD" "${ARGS[@]}" --out "$T/o.json"
  [ "$status" -eq 0 ]
  run python3 -I "$DD" "${ARGS[@]}" --out "$T/o2.json" --forbid crashed
  [ "$status" -eq 1 ]
  [[ "$output" == *"provenance token (crashed)"* ]]
  [ ! -e "$T/o2.json" ]
}

@test "DD-5 usage exits 2; a missing manifest or a bad source exits 1" {
  run python3 -I "$DD" --manifests-dir "$M" --out "$T/o.json"
  [ "$status" -eq 2 ]
  run python3 -I "$DD" "${ARGS[@]/pr-90/pr-91}" --out "$T/o.json"
  [ "$status" -eq 1 ]
  sed -i 's/"hunk:H01,H02"/"commit:abc"/' "$M/pr-90.json"
  run python3 -I "$DD" "${ARGS[@]}" --out "$T/o.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown source kind"* ]]
  [ ! -e "$T/o.json" ]
}

@test "DD-6 a --forbid token refuses even when the PR content carries it (never exempt, as judge-sample.sh)" {
  printf 'Users saw a crash in batch c132-g1.\n' >> "$T/review-prs/pr-90/PR.md"
  run python3 -I "$DD" "${ARGS[@]}" --out "$T/o.json" --forbid crash
  [ "$status" -eq 1 ]
  [[ "$output" == *"provenance token (crash)"* ]]
  [ ! -e "$T/o.json" ]
}

@test "DD-7 an arm/trial token is exempt only on a whole-token match in the PR content, not a substring" {
  sed -i 's/Users saw a crash./The a1_full trial crashed./' "$AN/pr-90/A/labels.json"
  printf 'data1_full_x and trials\n' > "$T/review-prs/pr-90/head/arms.txt"
  run python3 -I "$DD" "${ARGS[@]}" --out "$T/o.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"provenance token (a1_full, trial)"* ]]
  [ ! -e "$T/o.json" ]
  printf 'x(a1_full) and trials\n' > "$T/review-prs/pr-90/head/arms.txt"
  run python3 -I "$DD" "${ARGS[@]}" --out "$T/o.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"provenance token (trial)"* ]]
  printf 'x(a1_full) and one trial.\n' > "$T/review-prs/pr-90/head/arms.txt"
  run python3 -I "$DD" "${ARGS[@]}" --out "$T/o.json"
  [ "$status" -eq 0 ]
}

@test "DD-8 a non-object manifest defect and unreadable PR content refuse with nothing written" {
  cp "$M/pr-90.json" "$T/orig.json"
  jq -c '.defects += ["V03"]' "$T/orig.json" > "$M/pr-90.json"
  run python3 -I "$DD" "${ARGS[@]}" --out "$T/o.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"manifest defect 3 is not an object"* ]]
  [[ "$output" != *"Traceback"* ]]
  [ ! -e "$T/o.json" ]
  cp "$T/orig.json" "$M/pr-90.json"
  mkdir "$T/review-prs/pr-90/head/sub"; printf 'x\n' > "$T/review-prs/pr-90/head/sub/locked.txt"
  chmod 000 "$T/review-prs/pr-90/head/sub/locked.txt"
  if [ "$(id -u)" -eq 0 ]; then chmod 644 "$T/review-prs/pr-90/head/sub/locked.txt"; skip "root reads mode-000 files"; fi
  run python3 -I "$DD" "${ARGS[@]}" --out "$T/o.json"
  chmod 644 "$T/review-prs/pr-90/head/sub/locked.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"PR content unreadable"* ]]
  [[ "$output" != *"Traceback"* ]]
  [ ! -e "$T/o.json" ]
}
