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

# --- bd-y4pqj (bug 20261021-7240bc, sprint-bug-268): the labels files reproduce the curated manifests ---

# a scratch copy of one tracked record fixture holding only what --build-manifest reads:
# labels/, manifests/, pr-NN/fixture.yaml and the head files the labels name (never whole head/ trees)
scratch_record_fixture() {
  local n="$1" dst="$2" src="$REPO_ROOT/evals/fixtures/review-prs" f
  mkdir -p "$dst/pr-$n/head"
  cp -R "$src/labels" "$src/manifests" "$dst/"
  # cycle-132 D-2.3: the frozen review-derived set lives in labels/review/ and manifests/c131/; the builder reads
  # labels/pr-NN.tsv and writes manifests/pr-NN.json, so the scratch copy lays the frozen pair out there
  cp "$src/labels/review/pr-$n.tsv" "$dst/labels/pr-$n.tsv"
  cp "$src/manifests/c131/pr-$n.json" "$dst/manifests/pr-$n.json"
  cp "$src/pr-$n/fixture.yaml" "$dst/pr-$n/fixture.yaml"
  awk -F'\t' '$0 !~ /^#/ && $1 != "defect_id" && NF == 7 {print $4}' "$src/labels/review/pr-$n.tsv" | sort -u |
    while IFS= read -r f; do
      mkdir -p "$dst/pr-$n/head/$(dirname "$f")"
      cp "$src/pr-$n/head/$f" "$dst/pr-$n/head/$f"
    done
}

# a five-line synthetic fixture pr-93 whose `}` lines are not unique; one primary row per label plus a fix row
synthetic_at_fixture() {
  mkdir -p "$C/pr-93/head/src"
  printf 'sprint: 993\nhead_commit: "%s"\nfix_commit: "%s"\nrecord_ref: "record/cycle-993-a2a"\n' "$HEAD_C" "$FIX" > "$C/pr-93/fixture.yaml"
  printf 'alpha one() {\n}\nbeta two() {\n}\ngamma three\n' > "$C/pr-93/head/src/x.sh"
  {
    echo "# approved-by: pending"
    echo "# a comment the sync must keep"
    printf 'defect_id\tseverity\tcategory\tfile\tmust_match\tlabel_source\tsource\n'
    printf 'L01-first\thigh\tlogic\tsrc/x.sh\talpha one\treview\treview:engineer-feedback.md\n'
    printf 'L02-second\tlow\tstyle\tsrc/x.sh\tbeta two\taudit\taudit:auditor-sprint-feedback.md\n'
    printf 'F001\t-\tfix\tsrc/x.sh\tgamma three\tfix\tfix/%s:4-5\n' "${FIX:0:12}"
  } > "$C/labels/pr-93.tsv"
}

# curate a manifest the way cycle-131 Task 1.5 did: set approved_by and one defect's anchors,
# keeping the builder's key order (anchors right after anchor_line) and json.dump(indent=2) form
curate_manifest() {
  python3 -I -c 'import json, sys
m = json.load(open(sys.argv[1]))
if sys.argv[2] != "-":
    m["approved"], m["approved_by"] = True, sys.argv[2]
i, a = int(sys.argv[3]), json.loads(sys.argv[4])
d = {}
for k, v in m["defects"][i].items():
    if k != "anchors":
        d[k] = v
    if k == "anchor_line":
        d["anchors"] = a
m["defects"][i] = d
json.dump(m, open(sys.argv[1], "w"), indent=2)' "$@"
}

@test "SC-9 --build-manifest reproduces every frozen record manifest (manifests/c131/pr-11 … pr-18) byte for byte from its labels (labels/review/)" {
  local n S bad=""
  for n in 11 12 13 14 15 16 17 18; do
    S="$T/rebuild-$n"
    scratch_record_fixture "$n" "$S"
    run "$SEED" --build-manifest "pr-$n" --corpus "$S"
    [ "$status" -eq 0 ] || bad="$bad pr-$n(exit $status: ${output:0:200})"
    cmp -s "$S/manifests/pr-$n.json" "$REPO_ROOT/evals/fixtures/review-prs/manifests/c131/pr-$n.json" || bad="$bad pr-$n"
  done
  echo "differs:$bad"
  [ -z "$bad" ]
}

@test "SC-10 a must_match of @L<n> anchors head line n; @L0, a line past the end and a non-integer are refused naming the row" {
  synthetic_at_fixture
  printf 'L01-first\thigh\tlogic\tsrc/x.sh\t@L4\treview\treview:engineer-feedback.md\n' >> "$C/labels/pr-93.tsv"
  run "$SEED" --build-manifest pr-93 --corpus "$C"
  [ "$status" -eq 0 ]
  M="$C/manifests/pr-93.json"
  [ "$(jq -c '.defects[0].anchors' "$M")" = "[1,4]" ]
  [ "$(jq -r '.defects[0].anchor_line' "$M")" = "1" ]
  [ "$(jq -r '.defects[0].must_match' "$M")" = "alpha one" ]
  [ "$(jq -r '.defects[1] | has("anchors")' "$M")" = "false" ]
  cp "$C/labels/pr-93.tsv" "$T/ok.tsv"
  local bad
  for bad in '@L0' '@L6' '@Lx' '@L-1' '@L4x'; do
    { cat "$T/ok.tsv"; printf 'L02-second\tlow\tstyle\tsrc/x.sh\t%s\taudit\taudit:auditor-sprint-feedback.md\n' "$bad"; } > "$C/labels/pr-93.tsv"
    run "$SEED" --build-manifest pr-93 --corpus "$C"
    [ "$status" -eq 1 ]
    [[ "$output" == *"L02-second: must_match '$bad'"* ]]
  done
  # text rows keep the exactly-one-line rule: a bare `}` is still refused
  { cat "$T/ok.tsv"; printf 'L02-second\tlow\tstyle\tsrc/x.sh\t}\taudit\taudit:auditor-sprint-feedback.md\n'; } > "$C/labels/pr-93.tsv"
  run "$SEED" --build-manifest pr-93 --corpus "$C"
  [ "$status" -eq 1 ]
  [[ "$output" == *"is not on exactly one line"* ]]
}

@test "SC-11 --sync-labels appends one row per manifest anchor without a row (text when unique, else @L<n>), copies approved_by, is idempotent and never writes the manifest" {
  synthetic_at_fixture
  run "$SEED" --build-manifest pr-93 --corpus "$C"
  [ "$status" -eq 0 ]
  M="$C/manifests/pr-93.json"
  # the curated manifest: L01 gains anchors 4 (`}`, not unique) and 5 (unique text); a new approval line
  curate_manifest "$M" "lead 2026-10-19 (multi-site anchors; curated)" 0 '[1, 4, 5]'
  cp "$M" "$T/curated.json"
  cp "$C/labels/pr-93.tsv" "$T/before.tsv"
  run "$SEED" --sync-labels pr-93 --corpus "$C"
  [ "$status" -eq 0 ]
  L="$C/labels/pr-93.tsv"
  [ "$(head -1 "$L")" = "# approved-by: lead 2026-10-19 (multi-site anchors; curated)" ]
  [ "$(awk -F'\t' '$1 == "L01-first" {print $5}' "$L" | tr '\n' ,)" = "alpha one,@L4,gamma three," ]
  [ "$(awk -F'\t' '$1 == "L01-first" && $5 == "@L4" {print $2 "|" $3 "|" $4 "|" $6 "|" $7}' "$L")" = "high|logic|src/x.sh|review|review:engineer-feedback.md" ]
  # every other line is kept byte for byte, in order
  [ "$(tail -n +2 "$T/before.tsv")" = "$(tail -n +2 "$L" | grep -vxF "$(printf 'L01-first\thigh\tlogic\tsrc/x.sh\t@L4\treview\treview:engineer-feedback.md')" | grep -vxF "$(printf 'L01-first\thigh\tlogic\tsrc/x.sh\tgamma three\treview\treview:engineer-feedback.md')")" ]
  [[ "$output" == *"pr-93: added 2 row(s)"* ]]
  cmp -s "$M" "$T/curated.json"
  # idempotent: a second run adds nothing and leaves the file unchanged
  cp "$L" "$T/after1.tsv"
  run "$SEED" --sync-labels pr-93 --corpus "$C"
  [ "$status" -eq 0 ]
  [[ "$output" == *"pr-93: added 0 row(s)"* ]]
  cmp -s "$L" "$T/after1.tsv"
  # the synced labels rebuild the curated manifest byte for byte
  run "$SEED" --build-manifest pr-93 --corpus "$C"
  [ "$status" -eq 0 ]
  cmp -s "$M" "$T/curated.json"
}

@test "SC-12 after --sync-labels and --freeze, --check passes; the tracked record labels are already in sync" {
  synthetic_at_fixture
  run "$SEED" --build-manifest pr-93 --corpus "$C"
  [ "$status" -eq 0 ]
  M="$C/manifests/pr-93.json"
  curate_manifest "$M" - 1 '[2, 3]'
  run "$SEED" --sync-labels pr-93 --corpus "$C"
  [ "$status" -eq 0 ]
  run "$SEED" --check --corpus "$C"
  [ "$status" -eq 1 ]
  run "$SEED" --freeze --corpus "$C"
  [ "$status" -eq 0 ]
  run "$SEED" --check --corpus "$C"
  [ "$status" -eq 0 ]
  # the tracked corpus: syncing a scratch copy of every record fixture adds nothing
  local n S
  for n in 11 12 13 14 15 16 17 18; do
    S="$T/sync-$n"
    scratch_record_fixture "$n" "$S"
    run "$SEED" --sync-labels "pr-$n" --corpus "$S"
    [ "$status" -eq 0 ]
    [[ "$output" == *"pr-$n: added 0 row(s)"* ]]
    cmp -s "$S/labels/pr-$n.tsv" "$REPO_ROOT/evals/fixtures/review-prs/labels/review/pr-$n.tsv"
  done
  run "$SEED" --check
  [ "$status" -eq 0 ]
}

# --- review round 1 (DISS-001 / DISS-C-001 / DISS-C-002 / DISS-C-003) ---

@test "SC-13 a --sync-labels whose rebuild fails (missing fixture.yaml, an invalid fix row) exits 1 and leaves the labels byte-identical" {
  synthetic_at_fixture
  run "$SEED" --build-manifest pr-93 --corpus "$C"
  [ "$status" -eq 0 ]
  curate_manifest "$C/manifests/pr-93.json" "lead 2026-10-19 (curated)" 0 '[1, 4, 5]'
  L="$C/labels/pr-93.tsv"
  cp "$L" "$T/before.tsv"
  mv "$C/pr-93/fixture.yaml" "$T/fixture.yaml"
  run "$SEED" --sync-labels pr-93 --corpus "$C"
  [ "$status" -eq 1 ]
  [[ "$output" == *"labels left unchanged"* ]]
  cmp -s "$L" "$T/before.tsv"
  mv "$T/fixture.yaml" "$C/pr-93/fixture.yaml"
  sed -i "s|fix/${FIX:0:12}:4-5|fix/not-a-region|" "$L"
  cp "$L" "$T/before.tsv"
  run "$SEED" --sync-labels pr-93 --corpus "$C"
  [ "$status" -eq 1 ]
  [[ "$output" == *"labels left unchanged"* ]]
  cmp -s "$L" "$T/before.tsv"
}

@test "SC-14 a no-op --sync-labels still proves the rebuild: a changed severity on a synced row exits 1 naming the mismatch, labels unchanged" {
  synthetic_at_fixture
  run "$SEED" --build-manifest pr-93 --corpus "$C"
  [ "$status" -eq 0 ]
  run "$SEED" --sync-labels pr-93 --corpus "$C"
  [ "$status" -eq 0 ]
  [[ "$output" == *"pr-93: added 0 row(s)"* ]]
  L="$C/labels/pr-93.tsv"
  sed -i 's/^L02-second\tlow\t/L02-second\tcritical\t/' "$L"
  grep -q "^L02-second	critical	" "$L"
  cp "$L" "$T/before.tsv"
  run "$SEED" --sync-labels pr-93 --corpus "$C"
  [ "$status" -eq 1 ]
  [[ "$output" == *"L02-second"*"severity"* ]]
  cmp -s "$L" "$T/before.tsv"
}

@test "SC-15 a head line starting with @L but not @L<digits> (\`@Lazy foo\`) is anchored by text, and --sync-labels writes it as text" {
  synthetic_at_fixture
  printf 'class A {\n  @Lazy foo\n  @Lob bar\n}\n' > "$C/pr-93/head/src/A.kt"
  printf 'L03-kotlin\tmedium\tlogic\tsrc/A.kt\t@Lazy foo\treview\treview:engineer-feedback.md\n' >> "$C/labels/pr-93.tsv"
  run "$SEED" --build-manifest pr-93 --corpus "$C"
  [ "$status" -eq 0 ]
  M="$C/manifests/pr-93.json"
  [ "$(jq -r '.defects[2].anchor_line' "$M")" = "2" ]
  [ "$(jq -r '.defects[2].must_match' "$M")" = "@Lazy foo" ]
  curate_manifest "$M" - 2 '[2, 3]'
  run "$SEED" --sync-labels pr-93 --corpus "$C"
  [ "$status" -eq 0 ]
  [ "$(awk -F'\t' '$1 == "L03-kotlin" {print $5}' "$C/labels/pr-93.tsv" | tr '\n' ,)" = "@Lazy foo,@Lob bar," ]
}

# --- audit round (MEDIUM-1 / LOW-1 / LOW-2) ---

@test "SC-16 a labels file column outside head/ (../.., absolute, a symlink out) is refused by --build-manifest and --sync-labels, nothing written" {
  synthetic_at_fixture
  run "$SEED" --build-manifest pr-93 --corpus "$C"
  [ "$status" -eq 0 ]
  M="$C/manifests/pr-93.json"; L="$C/labels/pr-93.tsv"
  mkdir -p "$C/etc"; printf 'outside dotdot line\n' > "$C/etc/hostname"
  printf 'outside absolute line\n' > "$T/outside.txt"
  ln -s "$T/outside.txt" "$C/pr-93/head/src/link.txt"
  cp "$L" "$T/ok.tsv"; cp "$M" "$T/ok.json"
  local f mm
  for f in '../../etc/hostname' "$T/outside.txt" 'src/link.txt'; do
    case "$f" in ../*) mm='outside dotdot line' ;; *) mm='outside absolute line' ;; esac
    { cat "$T/ok.tsv"; printf 'L02-second\tlow\tstyle\t%s\t%s\taudit\taudit:auditor-sprint-feedback.md\n' "$f" "$mm"; } > "$L"
    cp "$L" "$T/bad.tsv"
    run "$SEED" --build-manifest pr-93 --corpus "$C"
    [ "$status" -eq 1 ]
    [[ "$output" == *"L02-second: file '$f' is not a path inside head/"* ]]
    cmp -s "$M" "$T/ok.json"
    run "$SEED" --sync-labels pr-93 --corpus "$C"
    [ "$status" -eq 1 ]
    [[ "$output" == *"L02-second: file '$f' is not a path inside head/"* ]]
    cmp -s "$L" "$T/bad.tsv"
    cmp -s "$M" "$T/ok.json"
  done
}

@test "SC-17 --sync-labels refuses an approved_by holding a Unicode line separator (U+2028) and leaves the labels unchanged" {
  synthetic_at_fixture
  run "$SEED" --build-manifest pr-93 --corpus "$C"
  [ "$status" -eq 0 ]
  curate_manifest "$C/manifests/pr-93.json" $'lead 2026-10-19 # forged' 0 '[1, 4]'
  L="$C/labels/pr-93.tsv"; cp "$L" "$T/before.tsv"
  run "$SEED" --sync-labels pr-93 --corpus "$C"
  [ "$status" -eq 1 ]
  [[ "$output" == *"approved_by must be a one-line"* ]]
  cmp -s "$L" "$T/before.tsv"
}

@test "SC-18 --sync-labels replaces the labels file atomically (a new inode, no temp file left behind)" {
  synthetic_at_fixture
  run "$SEED" --build-manifest pr-93 --corpus "$C"
  [ "$status" -eq 0 ]
  curate_manifest "$C/manifests/pr-93.json" "lead 2026-10-19 (curated)" 0 '[1, 4]'
  L="$C/labels/pr-93.tsv"
  local before; before="$(stat -c %i "$L")"
  run "$SEED" --sync-labels pr-93 --corpus "$C"
  [ "$status" -eq 0 ]
  [ "$(stat -c %i "$L")" != "$before" ]
  [ "$(ls -A "$C/labels" | tr '\n' ,)" = "pr-93.tsv," ]
}

# --- cycle-132 Task 1.5 (FR-2, SDD D-2.3, implementer B): labels header v2, manifest v2 ---------------------------
V2_HEADER="$(printf 'defect_id\tseverity\tcategory\tfile\tmust_match\tlabel_source\tsource\tannotators\tagreement\tadjudication\treview_driven')"
# pr-94: the five-line head of pr-93 with annotated (v2) rows — a two-anchor hunk defect, an adjudicated
# hunk+incident defect, an incident-only defect, and a fix row
synthetic_v2_fixture() {
  mkdir -p "$C/pr-94/head/src"
  printf 'sprint: 994\nhead_commit: "%s"\nfix_commit: "%s"\nrecord_ref: "record/cycle-994-a2a"\n' "$HEAD_C" "$FIX" > "$C/pr-94/fixture.yaml"
  printf 'alpha one() {\n}\nbeta two() {\n}\ngamma three\n' > "$C/pr-94/head/src/x.sh"
  {
    echo "# approved-by: pending"
    echo "$V2_HEADER"
    printf 'D1\thigh\tlogic\tsrc/x.sh\talpha one\tfix-commit\thunk:H01\tA,B\tagreed\t-\ttrue\n'
    printf 'D1\thigh\tlogic\tsrc/x.sh\t@L2\tfix-commit\thunk:H01\tA,B\tagreed\t-\ttrue\n'
    printf 'D2\tmedium\terror-handling\tsrc/x.sh\tbeta two\tfix-commit+incident\thunk:H02;incident:I01\tA,B\tadjudicated\tB read H02 as a refactor; I01 shows the failure\tfalse\n'
    printf 'D3\tlow\tlogic\tsrc/x.sh\tgamma three\tincident\tincident:I02\tA,B\tagreed\t-\tfalse\n'
    printf 'F001\t-\tfix\tsrc/x.sh\tgamma three\tfix\tfix/%s:4-5\t-\t-\t-\t-\n' "${FIX:0:12}"
  } > "$C/labels/pr-94.tsv"
}

@test "SC-V2-1 --build-manifest on a v2 labels file: label_set v2 and the four v2 columns in defects[]; the rebuild is byte-identical" {
  synthetic_v2_fixture
  run "$SEED" --build-manifest pr-94 --corpus "$C"
  [ "$status" -eq 0 ]
  M="$C/manifests/pr-94.json"
  [ "$(jq -r 'keys_unsorted | join(",")' "$M")" = "fixture,label_set,approved,approved_by,record,defects,fix_regions" ]
  [ "$(jq -r '.label_set' "$M")" = v2 ]
  [ "$(jq -c '[.defects[] | [.id, .label_source, .annotators, .agreement, .adjudication, .review_driven]]' "$M")" = \
    '[["D1","fix-commit",["A","B"],"agreed",null,true],["D2","fix-commit+incident",["A","B"],"adjudicated","B read H02 as a refactor; I01 shows the failure",false],["D3","incident",["A","B"],"agreed",null,false]]' ]
  [ "$(jq -c '.defects[0].anchors' "$M")" = "[1,2]" ]
  [ "$(jq -r '.defects[0] | keys_unsorted | join(",")' "$M")" = "id,file,anchor_line,anchors,must_match,severity,category,label_source,source,source_commit,synthetic,annotators,agreement,adjudication,review_driven" ]
  [ "$(jq -r '.fix_regions | length' "$M")" = 1 ]
  cp "$M" "$T/first.json"
  run "$SEED" --build-manifest pr-94 --corpus "$C"
  [ "$status" -eq 0 ]
  cmp -s "$M" "$T/first.json"
}

@test "SC-V2-2 a v2 header over review-derived rows only builds today's manifest (no label_set, no v2 fields)" {
  synthetic_at_fixture
  run "$SEED" --build-manifest pr-93 --corpus "$C"
  [ "$status" -eq 0 ]
  cp "$C/manifests/pr-93.json" "$T/v1hdr.json"
  awk -v h="$V2_HEADER" 'BEGIN{FS=OFS="\t"} /^#/ {print; next} $1 == "defect_id" {print h; next} {print $0, "-", "-", "-", "-"}' \
    "$C/labels/pr-93.tsv" > "$T/v2.tsv" && mv "$T/v2.tsv" "$C/labels/pr-93.tsv"
  [ "$(awk -F'\t' '!/^#/ {print NF}' "$C/labels/pr-93.tsv" | sort -u)" = 11 ]
  run "$SEED" --build-manifest pr-93 --corpus "$C"
  [ "$status" -eq 0 ]
  cmp -s "$C/manifests/pr-93.json" "$T/v1hdr.json"
}

@test "SC-V2-3 v2 rows are refused naming the row: an annotated source under the 7-column header, a bad agreement, review_driven or annotators, an unknown source, a short row" {
  synthetic_v2_fixture
  cp "$C/labels/pr-94.tsv" "$T/ok.tsv"
  try() {  # try <file> <expected message part>
    cp "$1" "$C/labels/pr-94.tsv"
    run "$SEED" --build-manifest pr-94 --corpus "$C"
    echo "$output"
    [ "$status" -eq 1 ]
    [[ "$output" == *"$2"* ]]
    [ ! -e "$C/manifests/pr-94.json" ]
  }
  { echo "# approved-by: pending"; printf 'defect_id\tseverity\tcategory\tfile\tmust_match\tlabel_source\tsource\n'
    printf 'D1\thigh\tlogic\tsrc/x.sh\talpha one\tfix-commit\thunk:H01\n'; } > "$T/b1.tsv"
  try "$T/b1.tsv" "D1: label_source 'fix-commit' needs the v2 header"
  sed 's/\tagreed\t-\ttrue$/\tmaybe\t-\ttrue/' "$T/ok.tsv" > "$T/b2.tsv";      try "$T/b2.tsv" "D1: agreement 'maybe'"
  sed 's/\tagreed\t-\tfalse$/\tagreed\t-\tyes/' "$T/ok.tsv" > "$T/b3.tsv";     try "$T/b3.tsv" "D3: review_driven 'yes'"
  sed 's/^D3\(.*\)\tA,B\tagreed/D3\1\t-\tagreed/' "$T/ok.tsv" > "$T/b4.tsv";   try "$T/b4.tsv" "D3: annotators '-'"
  sed 's/^D3\(.*\)\tagreed\t-\tfalse$/D3\1\t-\t-\tfalse/' "$T/ok.tsv" > "$T/b5.tsv"; try "$T/b5.tsv" "D3: agreement '-'"
  sed 's/\tincident\tincident:I02/\tincident+review\tincident:I02/' "$T/ok.tsv" > "$T/b6.tsv"; try "$T/b6.tsv" "D3: label_source 'incident+review'"
  sed 's/\tagreed\t-\tfalse$//' "$T/ok.tsv" > "$T/b7.tsv";                     try "$T/b7.tsv" "has 8 columns, want 11"
  sed 's/\tA,B\t/\tA,,B\t/' "$T/ok.tsv" > "$T/b8.tsv";                         try "$T/b8.tsv" "annotators 'A,,B'"
}

@test "SC-V2-4 --sync-labels on v2 rows copies all eleven columns from the defect's primary row; the rebuild stays byte-identical and a second run adds nothing" {
  synthetic_v2_fixture
  run "$SEED" --build-manifest pr-94 --corpus "$C"
  [ "$status" -eq 0 ]
  M="$C/manifests/pr-94.json"
  curate_manifest "$M" "lead 2026-10-21 (annotated)" 1 '[3, 4]'
  cp "$M" "$T/curated.json"
  run "$SEED" --sync-labels pr-94 --corpus "$C"
  [ "$status" -eq 0 ]
  L="$C/labels/pr-94.tsv"
  [ "$(awk -F'\t' '$1 == "D2" && $5 == "@L4"' "$L")" = "$(printf 'D2\tmedium\terror-handling\tsrc/x.sh\t@L4\tfix-commit+incident\thunk:H02;incident:I01\tA,B\tadjudicated\tB read H02 as a refactor; I01 shows the failure\tfalse')" ]
  cmp -s "$M" "$T/curated.json"
  cp "$L" "$T/after1.tsv"
  run "$SEED" --sync-labels pr-94 --corpus "$C"
  [ "$status" -eq 0 ]
  [[ "$output" == *"pr-94: added 0 row(s)"* ]]
  cmp -s "$L" "$T/after1.tsv"
  run "$SEED" --build-manifest pr-94 --corpus "$C"
  [ "$status" -eq 0 ]
  cmp -s "$M" "$T/curated.json"
}

@test "SC-V2-5 a v2 manifest records the incident scan's main_sha (incidents/pr-NN.meta.json) as record.incidents_meta; nothing else from the meta; absent without the file" {
  synthetic_v2_fixture
  run "$SEED" --build-manifest pr-94 --corpus "$C"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.record | has("incidents_meta")' "$C/manifests/pr-94.json")" = false ]
  mkdir -p "$C/incidents"
  printf '{"main_sha": "%s", "scanned_at": "2026-10-21T00:00:00Z", "gh_queries": []}\n' "$FIX" > "$C/incidents/pr-94.meta.json"
  run "$SEED" --build-manifest pr-94 --corpus "$C"
  [ "$status" -eq 0 ]
  [ "$(jq -c '.record.incidents_meta' "$C/manifests/pr-94.json")" = "{\"main_sha\":\"$FIX\"}" ]
  # a review-derived manifest never reads it
  synthetic_at_fixture
  printf '{"main_sha": "%s"}\n' "$FIX" > "$C/incidents/pr-93.meta.json"
  run "$SEED" --build-manifest pr-93 --corpus "$C"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.record | has("incidents_meta")' "$C/manifests/pr-93.json")" = false ]
}

# --- cycle-132 Sprint 1 Task 1.1 (FR-1, SDD D-1.1): --feedback paths, --paths scope, exposure provenance ---

# a record branch whose feedback sits outside a2a/sprint-<N>/ (the cycle-131 layout: a2a/sprint-1/ for sprint 901)
record_with_local_label_dir() {
  gc checkout -q record/cycle-901-a2a
  mkdir -p "$G/grimoires/loa/a2a/sprint-1"
  git -C "$G" mv grimoires/loa/a2a/sprint-901/engineer-feedback-r1.md grimoires/loa/a2a/sprint-1/engineer-feedback.md
  gc commit -q -m "record: local sprint label"; gc checkout -q main
}

@test "SC-P1 --feedback takes record-branch paths outside a2a/sprint-<N>/; the bare-name shorthand still works; unsafe paths are refused" {
  record_with_local_label_dir
  local A=(--repo "$G" --corpus "$C" --tasks-dir "$K" --base "$BASE" --head "$HEAD_C" --fix "$FIX" --out "$C/pr-90")
  run "$SEED" 901 record/cycle-901-a2a "${A[@]}" --feedback grimoires/loa/a2a/sprint-1/engineer-feedback.md
  [ "$status" -eq 0 ]
  [ "$(yq -r '.feedback_files[0]' "$C/pr-90/fixture.yaml")" = "grimoires/loa/a2a/sprint-1/engineer-feedback.md" ]
  awk -F'\t' '$1 ~ /^L01-/ {print $6 "|" $7}' "$C/labels/pr-90.tsv" | grep -q '^review|record/cycle-901-a2a:grimoires/loa/a2a/sprint-1/engineer-feedback.md#L'
  # the a2a/ shorthand resolves under grimoires/loa/
  run "$SEED" 901 record/cycle-901-a2a "${A[@]}" --feedback a2a/sprint-1/engineer-feedback.md --dry-run
  [ "$status" -eq 0 ]; grep -q 'KEEP L01' <<<"$output"
  # a bare name still means grimoires/loa/a2a/sprint-<N>/<name>: here it is absent, so nothing is labelled
  run "$SEED" 901 record/cycle-901-a2a "${A[@]}" --feedback engineer-feedback.md --dry-run
  [ "$status" -eq 0 ]; grep -q 'engineer-feedback.md: not on record/cycle-901-a2a' <<<"$output"
  local bad
  for bad in ../x/engineer-feedback.md /etc/engineer-feedback.md grimoires/loa/a2a/sprint-1/../../x.md grimoires/loa/a2a/sprint-1/notes.txt; do
    run "$SEED" 901 record/cycle-901-a2a "${A[@]}" --feedback "$bad" --dry-run
    [ "$status" -eq 2 ]
  done
}

@test "SC-P2 a seeded fixture carries the exposure block and contamination_note; the fields parse" {
  run "$SEED" 901 record/cycle-901-a2a "${ARGS[@]}"
  [ "$status" -eq 0 ]
  local y="$C/pr-90/fixture.yaml" hd
  hd="$(TZ=UTC git -C "$G" log -1 --date=format-local:%Y-%m-%d --format=%cd "$HEAD_C")"
  [ "$(yq -r '.exposure.fable_5_1' "$y")" = "post-cutoff" ]
  [ "$(yq -r '.exposure.opus_5_5' "$y")" = "unverified" ]
  [ "$(yq -r '.exposure.retrieval' "$y")" = "public-repository" ]
  [ "$(yq -r '.contamination_note' "$y")" = "fix commits on main since $hd; sandbox has network; egress scanned (grader class 9)" ]
  # the provenance fields leave the existing keys intact
  [ "$(yq -r '.head_commit' "$y")" = "$HEAD_C" ]
  run "$SEED" --check --corpus "$C"
  [ "$status" -eq 0 ]
}

@test "SC-P3 --stamp-exposure adds the block to an older fixture, is idempotent, replaces a stale block and touches no other line" {
  local OLD y="$C/pr-92/fixture.yaml"
  # a head committed before the Fable 5.1 knowledge cutoff (2026-06) is pre-cutoff
  printf 'old\n' > "$G/old.txt"; gc add -A
  GIT_COMMITTER_DATE="2026-03-01T12:00:00Z" GIT_AUTHOR_DATE="2026-03-01T12:00:00Z" gc commit -q -m "old head"
  OLD="$(git -C "$G" rev-parse HEAD)"
  mkdir -p "$C/pr-92/head"
  printf 'name: pr-92\nsprint: 902\nhead_commit: "%s"\nfix_commit: "%s"\nrecord_ref: "record/cycle-901-a2a"\nfeedback_files:\n  - "grimoires/loa/a2a/sprint-902/engineer-feedback.md"\n' "$OLD" "$FIX" > "$y"
  cp "$y" "$T/orig.yaml"
  run "$SEED" --stamp-exposure pr-92 --repo "$G" --corpus "$C"
  [ "$status" -eq 0 ]
  [ "$(yq -r '.exposure.fable_5_1' "$y")" = "pre-cutoff" ]
  [ "$(yq -r '.contamination_note' "$y")" = "fix commits on main since 2026-03-01; sandbox has network; egress scanned (grader class 9)" ]
  # every original line is kept, in order, before the added block
  [ "$(head -n "$(wc -l < "$T/orig.yaml")" "$y")" = "$(cat "$T/orig.yaml")" ]
  cp "$y" "$T/once.yaml"
  run "$SEED" --stamp-exposure pr-92 --repo "$G" --corpus "$C"
  [ "$status" -eq 0 ]
  cmp -s "$y" "$T/once.yaml"
  # a stale block is replaced in place, never duplicated
  sed -i 's/fable_5_1: pre-cutoff/fable_5_1: post-cutoff/; s/^contamination_note: .*/contamination_note: "stale"/' "$y"
  run "$SEED" --stamp-exposure pr-92 --repo "$G" --corpus "$C"
  [ "$status" -eq 0 ]
  cmp -s "$y" "$T/once.yaml"
  [ "$(grep -c '^exposure:' "$y")" -eq 1 ] && [ "$(grep -c '^contamination_note:' "$y")" -eq 1 ]
  # refusals: a fixture without head_commit, an unknown fixture, a bad id
  printf 'name: pr-93\n' > "$T/x.yaml"; mkdir -p "$C/pr-93"; cp "$T/x.yaml" "$C/pr-93/fixture.yaml"
  run "$SEED" --stamp-exposure pr-93 --repo "$G" --corpus "$C"
  [ "$status" -eq 1 ]; cmp -s "$C/pr-93/fixture.yaml" "$T/x.yaml"
  run "$SEED" --stamp-exposure pr-94 --repo "$G" --corpus "$C"
  [ "$status" -eq 1 ]
  run "$SEED" --stamp-exposure ../pr-92 --repo "$G" --corpus "$C"
  [ "$status" -eq 2 ]
}

@test "SC-P4 --paths scopes the fixture (an excluded file is in neither head/, base/ nor head.diff) and fixture.yaml records the scope" {
  run "$SEED" 901 record/cycle-901-a2a "${ARGS[@]}" --paths '!scripts/c.sh'
  [ "$status" -eq 0 ]
  [ ! -e "$C/pr-90/head/scripts/c.sh" ]
  ! grep -q 'scripts/c.sh' "$C/pr-90/head.diff"
  [ -f "$C/pr-90/head/scripts/a.sh" ]
  [ "$(yq -r '.scope_paths' "$C/pr-90/fixture.yaml")" = "!scripts/c.sh" ]
  ! awk -F'\t' '{print $4}' "$C/labels/pr-90.tsv" | grep -qx 'scripts/c.sh'
  # an include list keeps only matching paths
  run "$SEED" 901 record/cycle-901-a2a "${ARGS[@]}" --paths 'scripts/a.sh'
  [ "$status" -eq 0 ]
  [ "$(cd "$C/pr-90/head" && find . -type f | sort | tr '\n' ,)" = "./scripts/a.sh," ]
  # a scope that leaves nothing is refused
  run "$SEED" 901 record/cycle-901-a2a "${ARGS[@]}" --paths 'nothing/*' --dry-run
  [ "$status" -eq 1 ]
}

@test "SC-P5 findings written as '### HIGH-1 — …' headings or '**MEDIUM-A1 — ….**' paragraphs (cycle-129/130 feedback) are parsed; a Refuted section is not" {
  gc checkout -q record/cycle-901-a2a
  cat > "$G/grimoires/loa/a2a/sprint-901/engineer-feedback-r2style.md" <<'MD'
# Sprint 901 review — round 1

## Findings

### HIGH-1 — the input check accepts an empty value (dissent DISS-C-001, confirmed)

`scripts/a.sh:check_input` reports an empty value as accepted.

**MEDIUM-A1 — the read loop never ends on a closed pipe (DISS-C-002, confirmed).** `scripts/b.sh:2` keeps reading.

## Refuted or accepted without action

### LOW-1 — a refuted item that must never be read

`scripts/a.sh:check_input` is fine.
MD
  gc add -A; gc commit -q -m "record: heading-style feedback"; gc checkout -q main
  run "$SEED" 901 record/cycle-901-a2a --repo "$G" --corpus "$C" --tasks-dir "$K" --base "$BASE" --head "$HEAD_C" --fix "$FIX" \
    --feedback engineer-feedback-r2style.md --out "$C/pr-90" --dry-run
  [ "$status" -eq 0 ]
  grep -q 'KEEP L01-the-input-check-accepts-an-empty-value[-a-z]* \[high/review\] scripts/a.sh' <<<"$output"
  grep -q 'DROP .*\[medium\] fix commit does not touch scripts/b.sh: the read loop never ends on a closed pipe' <<<"$output"
  ! grep -q 'must never be read' <<<"$output"
}

@test "SC-P6 --allow-no-labels builds a fixture whose review-derived set is empty (manifest with no defect, fix regions kept); without it the gap is recorded" {
  printf 'fixture\tlabel\taction\tvalue\treason\npr-90\tL01\tdrop\t-\ttest drop\n' > "$C/labels/curation.tsv"
  run "$SEED" 901 record/cycle-901-a2a "${ARGS[@]}" --allow-no-labels
  [ "$status" -eq 0 ]
  [ -f "$C/pr-90/fixture.yaml" ] && [ -f "$C/pr-90/head.diff" ]
  M="$C/manifests/pr-90.json"
  [ "$(jq -r '.defects | length' "$M")" = "0" ]
  [ "$(jq -r '.fix_regions | length' "$M")" = "2" ]
  [ "$(jq -r '.approved' "$M")" = "false" ]
  grep -q 'curated out (test drop)' "$C/labels/pr-90.dropped.txt"
  grep -q "^pr-90	record	${HEAD_C:0:8}	labels/pr-90.tsv" "$C/corpus.tsv"
  run "$SEED" --check --corpus "$C"
  [ "$status" -eq 0 ]
}
