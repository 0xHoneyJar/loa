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
  cp "$src/pr-$n/fixture.yaml" "$dst/pr-$n/fixture.yaml"
  awk -F'\t' '$0 !~ /^#/ && $1 != "defect_id" && NF == 7 {print $4}' "$src/labels/pr-$n.tsv" | sort -u |
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

@test "SC-9 --build-manifest reproduces every tracked record manifest (pr-11 … pr-18) byte for byte from its labels" {
  local n S bad=""
  for n in 11 12 13 14 15 16 17 18; do
    S="$T/rebuild-$n"
    scratch_record_fixture "$n" "$S"
    run "$SEED" --build-manifest "pr-$n" --corpus "$S"
    [ "$status" -eq 0 ] || bad="$bad pr-$n(exit $status: ${output:0:200})"
    cmp -s "$S/manifests/pr-$n.json" "$REPO_ROOT/evals/fixtures/review-prs/manifests/pr-$n.json" || bad="$bad pr-$n"
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
    cmp -s "$S/labels/pr-$n.tsv" "$REPO_ROOT/evals/fixtures/review-prs/labels/pr-$n.tsv"
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
