#!/usr/bin/env bats
# =============================================================================
# evals/tests/seed-corpus.bats — cycle-129 Sprint 1 Task 1.5 (FR-2, SDD D-2.2)
#
# seed-corpus-from-record.sh over a tiny record tree built from
# evals/tests/fixtures/seed-record/: a throwaway repo with base, head and fix
# commits and a record branch carrying one round-1 review file. Proves: a
# finding whose fix touches its file is kept; a finding whose file the fix
# never touches is dropped by the rule; fix rows come from the fix hunks; a
# finding carrying a secret is rejected; the approved-by header is required;
# the labels stay out of the sandbox-copied fixture dir; SHA256SUMS covers it.
# =============================================================================

setup() {
  TESTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$TESTS_DIR/../.." && pwd)"
  SEED="$REPO_ROOT/evals/harness/seed-corpus-from-record.sh"
  GRADER="$REPO_ROOT/evals/graders/recall-vs-defects.sh"
  FX="$TESTS_DIR/fixtures/seed-record"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/sc.XXXXXX")"
  G="$T/repo"; C="$T/corpus"; K="$T/tasks"
  mkdir -p "$G" "$C/pr-01" "$C/labels" "$K"
  # the fake key is assembled here so no literal key shape is ever committed
  FAKE_KEY="AKIA$(printf 'QZ%.0s' 1 2 3 4 5 6 7 8)"
  gc() { git -C "$G" -c user.email=t@t -c user.name=t "$@"; }
  git -C "$G" init -q -b main
  cp -R "$FX/base/." "$G/"; gc add -A; gc commit -q -m "base"
  cp -R "$FX/head/." "$G/"; gc add -A; gc commit -q -m "feat: sprint-901 the input helper (round 1)"
  cp -R "$FX/fix/." "$G/"; gc add -A; gc commit -q -m "fix: sprint-901 review round 1"
  BASE="$(git -C "$G" rev-parse HEAD~2)"; HEAD_C="$(git -C "$G" rev-parse HEAD~1)"; FIX="$(git -C "$G" rev-parse HEAD)"
  gc checkout -q --orphan record/cycle-901-a2a
  git -C "$G" rm -rq --cached . ; find "$G" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
  mkdir -p "$G/grimoires/loa/a2a/sprint-901"
  sed "s/@SECRET@/$FAKE_KEY/" "$FX/engineer-feedback-r1.md.in" > "$G/grimoires/loa/a2a/sprint-901/engineer-feedback-r1.md"
  gc add -A; gc commit -q -m "record"; gc checkout -q main
  # a minimal corpus: the instruction templates and the corpus spec header
  echo "# Review instructions" > "$C/pr-01/REVIEW-INSTRUCTIONS.md"
  echo "# Audit instructions" > "$C/pr-01/AUDIT-INSTRUCTIONS.md"
  printf 'fixture\tkind\tcommit\tfile\tdefect_id\tseverity\tcategory\tmust_match\n' > "$C/corpus.tsv"
  ARGS=(--repo "$G" --corpus "$C" --tasks-dir "$K" --base "$BASE" --head "$HEAD_C" --fix "$FIX" --feedback engineer-feedback-r1.md --out "$C/pr-90")
}

teardown() { find "$T" -mindepth 1 -delete 2>/dev/null || true; rmdir "$T" 2>/dev/null || true; }

@test "SC-1 seeding builds the fixture; labels stay hidden; the fix-touches-file rule keeps a.sh and drops b.sh; fix rows come from the fix hunks" {
  run "$SEED" 901 record/cycle-901-a2a "${ARGS[@]}"
  [ "$status" -eq 0 ]
  for f in fixture.yaml head.diff PR.md REVIEW-INSTRUCTIONS.md AUDIT-INSTRUCTIONS.md head/scripts/a.sh head/scripts/b.sh base/scripts/a.sh; do
    [ -f "$C/pr-90/$f" ]
  done
  grep -q '^sprint: 901$' "$C/pr-90/fixture.yaml"
  grep -q "^head_commit: \"$HEAD_C\"$" "$C/pr-90/fixture.yaml"
  grep -q "^fix_commit: \"$FIX\"$" "$C/pr-90/fixture.yaml"
  grep -q '^record_ref: "record/cycle-901-a2a"$' "$C/pr-90/fixture.yaml"
  grep -q 'grimoires/loa/a2a/sprint-901/engineer-feedback-r1.md' "$C/pr-90/fixture.yaml"
  # the labels never sit in the directory the sandbox copies
  [ -z "$(find "$C/pr-90" -name 'labels*' -o -name '*.dropped.txt')" ]
  L="$C/labels/pr-90.tsv"
  [ "$(head -1 "$L")" = "# approved-by: pending" ]
  grep -qx "$(printf 'defect_id\tseverity\tcategory\tfile\tmust_match\tlabel_source\tsource')" "$L"
  # kept: the a.sh finding (its fix touches a.sh), anchored where the fix inserts
  # the missing check (after `local v="$1"`) and on the short function's definition
  [ "$(awk -F'\t' '$1 ~ /^L/ {print $4 "|" $6}' "$L" | sort -u)" = "scripts/a.sh|review" ]
  awk -F'\t' '$1 ~ /^L01-/ {print $5}' "$L" | grep -qxF 'local v="$1"'
  awk -F'\t' '$1 ~ /^L01-/ {print $5}' "$L" | grep -qxF 'check_input() {'
  # dropped by the rule: b.sh (the fix never touches it); the prose finding; the previous-round section is never read
  grep -q 'fix commit does not touch scripts/b.sh' "$C/labels/pr-90.dropped.txt"
  grep -q 'no code locus' "$C/labels/pr-90.dropped.txt"
  ! grep -q 'must never be read' "$L" "$C/labels/pr-90.dropped.txt"
  # fix rows: one per fix hunk, on a.sh and c.sh, sourced fix/<sha>:<start>-<end>
  [ "$(awk -F'\t' '$6 == "fix" {print $4}' "$L" | sort | tr '\n' ,)" = "scripts/a.sh,scripts/c.sh," ]
  awk -F'\t' '$6 == "fix" {print $7}' "$L" | grep -qE "^fix/${FIX:0:12}:[0-9]+-[0-9]+$"
  # the hidden manifest, the tasks, the corpus row and the freeze
  M="$C/manifests/pr-90.json"
  [ "$(jq -r '.approved' "$M")" = "false" ]
  [ "$(jq -r '.defects | length' "$M")" = "1" ]
  [ "$(jq -r '.fix_regions | length' "$M")" = "2" ]
  [ "$(jq -r '.defects[0].label_source' "$M")" = "review" ]
  [ -f "$K/review-recall/review-pr-90.yaml" ] && [ -f "$K/audit-recall/audit-pr-90.yaml" ]
  [ "$(yq -r '.graders[0].args[0]' "$K/review-recall/review-pr-90.yaml")" = "pr-90" ]
  grep -q "^pr-90	record	${HEAD_C:0:8}	labels/pr-90.tsv" "$C/corpus.tsv"
  run "$SEED" --check --corpus "$C"
  [ "$status" -eq 0 ]
}

@test "SC-2 a finding carrying a secret is rejected without its text; nothing written carries the key and every file passes no-secrets.sh" {
  run "$SEED" 901 record/cycle-901-a2a "${ARGS[@]}"
  [ "$status" -eq 0 ]
  grep -q 'secret pattern in the finding text' "$C/labels/pr-90.dropped.txt"
  ! grep -rqF "$FAKE_KEY" "$C"
  ! awk -F'\t' '$1 ~ /^L/ {print $4}' "$C/labels/pr-90.tsv" | grep -q 'c.sh'
  run bash "$REPO_ROOT/evals/graders/no-secrets.sh" "$C"
  [ "$status" -eq 0 ]
}

@test "SC-3 recall-vs-defects.sh grades the seeded label: the anchor detects it, a fix region is not refuted, an unrelated line is" {
  run "$SEED" 901 record/cycle-901-a2a "${ARGS[@]}"
  [ "$status" -eq 0 ]
  local at; at="$(jq -r '.defects[0].anchor_line' "$C/manifests/pr-90.json")"
  W="$T/ws"; mkdir -p "$W"
  printf '%s\n' "- HIGH head/scripts/a.sh:$at accepts an empty value" "- LOW head/scripts/c.sh:3 prints the token" \
    "- LOW head/scripts/b.sh:2 loops forever" > "$W/review.md"
  EVAL_MANIFEST_DIR="$C/manifests" run "$GRADER" "$W" pr-90 review.md
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.details.recall == 1')" = "true" ]
  [ "$(echo "$output" | jq -r '.details.findings_cited')" = "3" ]
  [ "$(echo "$output" | jq -r '.details.findings_refuted')" = "1" ]
}

@test "SC-4 the approved-by header is required; --approve records the approver, marks the manifest approved and refreezes" {
  run "$SEED" 901 record/cycle-901-a2a "${ARGS[@]}"
  [ "$status" -eq 0 ]
  L="$C/labels/pr-90.tsv"
  cp "$L" "$T/keep.tsv"
  tail -n +2 "$T/keep.tsv" > "$L"
  run "$SEED" --build-manifest pr-90 --corpus "$C"
  [ "$status" -eq 1 ]
  grep -q 'approved-by' <<<"$output"
  cp "$T/keep.tsv" "$L"
  run "$SEED" --approve pr-90 --by "lead 2026-10-14" --corpus "$C"
  [ "$status" -eq 0 ]
  [ "$(head -1 "$L")" = "# approved-by: lead 2026-10-14" ]
  [ "$(jq -r '.approved' "$C/manifests/pr-90.json")" = "true" ]
  [ "$(jq -r '.approved_by' "$C/manifests/pr-90.json")" = "lead 2026-10-14" ]
  run "$SEED" --check --corpus "$C"
  [ "$status" -eq 0 ]
  run "$SEED" --approve pr-90 --by 'x;$(id)' --corpus "$C"
  [ "$status" -eq 2 ]
}

@test "SC-5 curation.tsv drops or re-anchors a label on every re-seed" {
  printf 'fixture\tlabel\taction\tvalue\treason\npr-90\tL01\tanchors\treturn 0\ttest re-anchor\n' > "$C/labels/curation.tsv"
  run "$SEED" 901 record/cycle-901-a2a "${ARGS[@]}"
  [ "$status" -eq 0 ]
  [ "$(awk -F'\t' '$1 ~ /^L01-/ {print $5}' "$C/labels/pr-90.tsv")" = "return 0" ]
  # dropping the only label leaves a gap: nothing stale survives, the reason is kept
  printf 'fixture\tlabel\taction\tvalue\treason\npr-90\tL01\tdrop\t-\ttest drop\n' > "$C/labels/curation.tsv"
  run "$SEED" 901 record/cycle-901-a2a "${ARGS[@]}"
  [ "$status" -eq 0 ]
  grep -q 'curated out (test drop)' "$C/labels/pr-90.dropped.txt"
  [ ! -e "$C/pr-90" ] && [ ! -e "$C/labels/pr-90.tsv" ] && [ ! -e "$C/manifests/pr-90.json" ] && [ ! -e "$K/review-recall/review-pr-90.yaml" ]
  grep -q '^# pr-90 sprint-901: no record fixture' "$C/corpus.tsv"
  ! grep -q '^pr-90	' "$C/corpus.tsv"
  # a curation row that names no seeded label is an error, not a silent no-op
  printf 'fixture\tlabel\taction\tvalue\treason\npr-90\tL09\tdrop\t-\tnothing\n' > "$C/labels/curation.tsv"
  run "$SEED" 901 record/cycle-901-a2a "${ARGS[@]}"
  [ "$status" -eq 1 ]
}

@test "SC-6 --dry-run writes nothing; a missing commit, a missing record ref and a non-record fixture are refused" {
  run "$SEED" 901 record/cycle-901-a2a "${ARGS[@]}" --dry-run
  [ "$status" -eq 0 ]
  grep -q 'KEEP L01' <<<"$output"
  [ ! -e "$C/pr-90" ] && [ ! -e "$C/labels/pr-90.tsv" ] && [ ! -e "$C/manifests" ]
  run "$SEED" 901 record/cycle-901-a2a --repo "$G" --corpus "$C" --tasks-dir "$K" --base "$BASE" --head deadbeefdeadbeef --fix "$FIX" --feedback engineer-feedback-r1.md --out "$C/pr-90"
  [ "$status" -eq 1 ]; grep -q 'missing commit' <<<"$output"
  run "$SEED" 901 record/nope "${ARGS[@]}"
  [ "$status" -eq 1 ]; grep -q 'record ref not found' <<<"$output"
  run "$SEED" 901 record/cycle-901-a2a --repo "$G" --corpus "$C" --tasks-dir "$K" --base "$BASE" --head "$HEAD_C" --fix "$FIX" --feedback engineer-feedback-r1.md --out "$C/pr-01"
  [ "$status" -eq 1 ]
  [ ! -e "$C/pr-01/fixture.yaml" ]
}

# --- bd-8o5rx (cycle-130 Sprint 259 Task 2.8, PRD AC-10.1): generated artefacts are never fix regions ---

@test "SC-7 --build-manifest keeps generated paths out of fix_regions and prints each exclusion; defect labels are untouched" {
  local fx="$C/pr-91" L="$C/labels/pr-91.tsv" p
  local gen=(dist/x.js lib/y.map types/z.d.ts conf/model.yaml.checksum checksums.json REPO-MAP.md .build-manifest.json)
  mkdir -p "$fx/head"
  printf 'sprint: 991\nhead_commit: "%s"\nfix_commit: "%s"\nrecord_ref: "record/cycle-991-a2a"\n' "$HEAD_C" "$FIX" > "$fx/fixture.yaml"
  for p in "${gen[@]}" src/real.sh; do mkdir -p "$fx/head/$(dirname "$p")"; printf 'line one\nline two\nline three\n' > "$fx/head/$p"; done
  {
    echo "# approved-by: pending"
    printf 'defect_id\tseverity\tcategory\tfile\tmust_match\tlabel_source\tsource\n'
    printf 'L01-real\thigh\tlogic\tsrc/real.sh\tline two\treview\treview:engineer-feedback.md\n'
    printf 'L02-in-dist\tlow\tlogic\tdist/x.js\tline one\treview\treview:engineer-feedback.md\n'
    local n=1
    for p in "${gen[@]}" src/real.sh; do
      printf 'F%03d\t-\tfix\t%s\tline one\tfix\tfix/%s:1-2\n' "$n" "$p" "${FIX:0:12}"; n=$((n + 1))
    done
  } > "$L"
  run "$SEED" --corpus "$C" --build-manifest pr-91
  [ "$status" -eq 0 ]
  M="$C/manifests/pr-91.json"
  [ "$(jq -r '[.fix_regions[].file] | join(",")' "$M")" = "src/real.sh" ]
  for p in "${gen[@]}"; do
    [ "$(grep -cxF "excluded generated path: $p" <<<"$output")" -eq 1 ]
  done
  ! grep -qF 'excluded generated path: src/real.sh' <<<"$output"
  # the key defects are not filtered: both labels survive with their ids
  [ "$(jq -r '[.defects[].id] | join(",")' "$M")" = "L01-real,L02-in-dist" ]
}

@test "SC-8 seeding writes no fix row for a generated path the fix touched and prints the exclusion" {
  local gen=(dist/x.js lib/y.js.map types/z.d.ts conf/m.yaml.checksum tools/checksums.json web/.build-manifest.json)
  local p HEAD2 FIX2
  for p in "${gen[@]}"; do mkdir -p "$G/$(dirname "$p")"; printf 'one\ntwo\n' > "$G/$p"; done
  printf '#!/usr/bin/env bash\ncheck_input() {\n  local v="$1"\n  echo "accepted: $v"\n}\n# head2\n' > "$G/scripts/a.sh"
  gc add -A; gc commit -q -m "feat: sprint-901 generated outputs (round 1)"; HEAD2="$(git -C "$G" rev-parse HEAD)"
  for p in "${gen[@]}"; do printf 'one\nTWO\n' > "$G/$p"; done
  printf '#!/usr/bin/env bash\ncheck_input() {\n  local v="$1"\n  [[ -n "$v" ]] || return 1\n  echo "accepted: $v"\n}\n# head2\n' > "$G/scripts/a.sh"
  gc add -A; gc commit -q -m "fix: sprint-901 generated outputs review round 1"; FIX2="$(git -C "$G" rev-parse HEAD)"
  run "$SEED" 901 record/cycle-901-a2a --repo "$G" --corpus "$C" --tasks-dir "$K" --base "$FIX" --head "$HEAD2" \
    --fix "$FIX2" --feedback engineer-feedback-r1.md --out "$C/pr-92"
  [ "$status" -eq 0 ]
  # the generated files are part of the fixture (scope is unchanged) but carry no fix row
  [ -f "$C/pr-92/head/dist/x.js" ]
  [ "$(awk -F'\t' '$6 == "fix" {print $4}' "$C/labels/pr-92.tsv" | sort -u | tr '\n' ,)" = "scripts/a.sh," ]
  [ "$(jq -r '[.fix_regions[].file] | unique | join(",")' "$C/manifests/pr-92.json")" = "scripts/a.sh" ]
  for p in "${gen[@]}"; do
    [ "$(grep -cxF "excluded generated path: $p" <<<"$output")" -eq 1 ]
  done
}
