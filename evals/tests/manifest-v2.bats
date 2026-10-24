#!/usr/bin/env bats
# =============================================================================
# evals/tests/manifest-v2.bats — cycle-132 Sprint 1 Task 1.5 (PRD FR-2; SDD §3.2 manifest v2, §3.4, D-2.3)
#
# The frozen-set migration and the manifest v2 schema:
#   - manifests/c131/pr-11 … pr-18.json are the cycle-131 curated keys (pinned digests; no comparison
#     with main, whose top-level manifests are v2 since Sprint 269); manifests/v1/ is unchanged;
#     labels/review/pr-NN.tsv rebuild manifests/c131/pr-NN.json byte for byte
#   - every suite-root task.yaml review_catch.manifest resolves; the frozen roots name manifests/c131/
#   - evals/harness/schemas/review-manifest.schema.json accepts every tracked manifest and a v2 manifest
#     built end to end (annotation_merge.py rows → --build-manifest), and refuses malformed v2 shapes
#   - SHA256SUMS and every touched suite root's MANIFEST.sha256 verify
# =============================================================================

setup() {
  TESTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$TESTS_DIR/../.." && pwd)"
  SEED="$REPO_ROOT/evals/harness/seed-corpus-from-record.sh"
  MERGE="$REPO_ROOT/evals/analysis/c132/annotation_merge.py"
  SCHEMA="$REPO_ROOT/evals/harness/schemas/review-manifest.schema.json"
  CORPUS="$REPO_ROOT/evals/fixtures/review-prs"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/mv.XXXXXX")"
}

teardown() { find "$T" -mindepth 1 -delete 2>/dev/null || true; rmdir "$T" 2>/dev/null || true; }

sha() { python3 -I -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"; }
validate() { python3 -I "$MERGE" --validate "$SCHEMA" "$@"; }

@test "MV-1 manifests/c131/pr-11 … pr-18 are the cycle-131 curated keys byte for byte (pinned by digest); manifests/v1/ unchanged" {
  local want n bad=""
  while read -r want n; do
    # the digests are the cycle-131 keys; no comparison with main's top-level manifests, which are v2 since Sprint 269
    [ "$(sha "$CORPUS/manifests/c131/pr-$n.json")" = "$want" ] || bad="$bad c131/pr-$n"
  done <<'PINS'
76d7a58d224dd713142d9addcbac11bfc7d588259f582da34f88ace37987341b 11
54d76e13016dcf86cb067c9d96771462ec119f81ae032f6df228f1aa8aabf55a 12
08c208a859db2e291d3119b0b7ba9724692e308cc146e85a25b7283871732d2f 13
677b663a5761eccebf794dd16652104fd8939b00c5a41fe437dd7b39ce20c541 14
76db907b27c111b24e59a28324ea20a8e5f0edd90b08a6fbfea562fda6aa37d8 15
116efcae9d9318939e8e1301eb2c12d2a4e3067d78883fc882813704fdb0e358 16
2fbbf4c91c870c6da46148b9710b395214a0fed19c488f642014c66ce64cc39e 17
f1c347e7e2077659d3927ecfb1172db9e1d4881144ca917d96e74a9e3657a6b8 18
PINS
  echo "differs:$bad"
  [ -z "$bad" ]
  # the v1 snapshot: one digest over the eighteen files' digests, in name order
  [ "$(python3 -I -c 'import hashlib,os,sys
d = sys.argv[1]; h = hashlib.sha256()
for f in sorted(os.listdir(d)): h.update(hashlib.sha256(open(os.path.join(d, f), "rb").read()).hexdigest().encode() + b"\n")
print(len(os.listdir(d)), h.hexdigest())' "$CORPUS/manifests/v1")" = "18 8b5ca1329d8dfab6a228d7eb866fa0f5076bccddab34b606106a65c34c0c849d" ]
  # a manifests/pr-NN.json for a record fixture, once written, is a v2 key (never the frozen one back in place)
  for n in 11 12 13 14 15 16 17 18; do
    [ ! -e "$CORPUS/manifests/pr-$n.json" ] || [ "$(jq -r '.label_set' "$CORPUS/manifests/pr-$n.json")" = v2 ]
  done
}

@test "MV-2 labels/review/pr-NN.tsv are the review-derived labels (pinned) and rebuild manifests/c131/pr-NN.json byte for byte" {
  local want n bad="" S f
  while read -r want n; do
    [ "$(sha "$CORPUS/labels/review/pr-$n.tsv")" = "$want" ] || bad="$bad review/pr-$n"
    S="$T/s-$n"; mkdir -p "$S/labels" "$S/pr-$n/head"
    cp "$CORPUS/labels/review/pr-$n.tsv" "$S/labels/pr-$n.tsv"
    cp "$CORPUS/pr-$n/fixture.yaml" "$S/pr-$n/"
    awk -F'\t' '$0 !~ /^#/ && $1 != "defect_id" {print $4}' "$S/labels/pr-$n.tsv" | sort -u | while IFS= read -r f; do
      mkdir -p "$S/pr-$n/head/$(dirname "$f")"; cp "$CORPUS/pr-$n/head/$f" "$S/pr-$n/head/$f"
    done
    run "$SEED" --build-manifest "pr-$n" --corpus "$S"
    [ "$status" -eq 0 ] || bad="$bad build:pr-$n"
    cmp -s "$S/manifests/pr-$n.json" "$CORPUS/manifests/c131/pr-$n.json" || bad="$bad rebuild:pr-$n"
  done <<'PINS'
eada19d329f76f06e22f8790cac70920c623eb8815f124e05bd03d315c9073ba 11
4a2aa475082bd9fd99c6a7b8f71f15e7417a5e9de441a836e78df95e5c68b465 12
90eceb33fcdc0adc9f89b0e8577be744e0e5e78d2dd42d8f023e5055701b2c9f 13
011eff3e310e4b50d9467e098392374cf5cd5a31fae0334b8b90c001d90793e4 14
24b1902c0ffcfeff0e033b665fb68f1f9bd660ffa5c709b52faa55b43ced0e6a 15
bbb6c92e2af879148eab39554161ebb687e097f0536f44a313814518adaafb98 16
1a21736f9162a8c1db61310142f4af7ef5b6d8ebfc1455e6e887d353691c1fd7 17
8674a3ed26a8bb5ee6848d3d9b4b8e2fdf9863a6bd406b407f4465d6b6598da1 18
PINS
  echo "differs:$bad"
  [ -z "$bad" ]
}

@test "MV-3 every suite-root task.yaml review_catch.manifest resolves; a record fixture's manifests/pr-NN.json is named only as a v2 key; the frozen roots and the record-fixture tasks name manifests/c131/" {
  local f m bad="" n=0
  while IFS= read -r f; do
    m="$(yq -r '.review_catch.manifest // ""' "$f")"
    [ -n "$m" ] || continue
    n=$((n + 1))
    [ -f "$REPO_ROOT/$m" ] || bad="$bad ${f#"$REPO_ROOT/"}($m)"
    # a record fixture's manifests/pr-NN.json is the v2 key once Task 1.6 writes it; pointing there at anything
    # else (the frozen cycle-131 key back at its old path) is the regression this guards
    case "$m" in */manifests/pr-1[1-8].json)
      [ -f "$REPO_ROOT/$m" ] && [ "$(jq -r '.label_set // ""' "$REPO_ROOT/$m")" = v2 ] || bad="$bad ${f#"$REPO_ROOT/"}(old path, not a v2 key)" ;;
    esac
  done < <(find "$REPO_ROOT/grimoires/loa/evals" -name task.yaml | LC_ALL=C sort)
  echo "bad:$bad"
  [ -z "$bad" ]
  [ "$n" -ge 16 ]
  for f in ablation-2.0-c131/tasks/review-r17 ablation-2.0-c131/tasks/review-r18 \
           ablation-2.0-replication/tasks/review-r17 ablation-2.0-replication/tasks/review-r18 \
           ablation-2.0/tasks/review-03 ablation-2.0/tasks/review-04; do
    [[ "$(yq -r '.review_catch.manifest' "$REPO_ROOT/grimoires/loa/evals/$f/task.yaml")" == evals/fixtures/review-prs/manifests/c131/pr-1*.json ]]
  done
}

@test "MV-4 SHA256SUMS and the touched suite roots' MANIFEST.sha256 verify" {
  run "$SEED" --check
  [ "$status" -eq 0 ]
  grep -q '  manifests/c131/pr-17.json$' "$CORPUS/SHA256SUMS"
  grep -q '  labels/review/pr-17.tsv$' "$CORPUS/SHA256SUMS"
  local args
  for args in "ablation-2.0 --smoke" "ablation-2.0-c131 --allow-partial" "ablation-2.0-replication --allow-partial" \
              "ablation-2.0-smoke-c131 --smoke --allow-partial"; do
    set -- $args
    local root="$1"; shift
    run bash "$REPO_ROOT/evals/harness/freeze.sh" --root "$REPO_ROOT/grimoires/loa/evals/$root" --check "$@"
    echo "$root: $output"
    [ "$status" -eq 0 ]
  done
}

@test "MV-5 the review-manifest schema accepts every tracked manifest (hand-built, c131, v1)" {
  run validate "$CORPUS"/manifests/*.json "$CORPUS"/manifests/c131/*.json "$CORPUS"/manifests/v1/*.json
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"0 invalid"* ]]
}

# a v2 key built end to end: two annotators' files and the lead's adjudication → annotation_merge.py rows →
# labels/pr-95.tsv → --build-manifest, in a scratch corpus
build_v2() {
  local C="$T/corpus" P="$T/pkt"
  mkdir -p "$C/labels" "$C/pr-95/head/src" "$P"
  printf 'sprint: 995\nhead_commit: "abcdef12"\nfix_commit: "12abcdef"\nrecord_ref: "record/cycle-995-a2a"\n' > "$C/pr-95/fixture.yaml"
  seq -f 'v_%g=1' 1 30 > "$C/pr-95/head/src/a.sh"
  cat > "$P/A.json" <<'EOF'
{"hunks": {"H01": {"verdict": "defect", "group": "D1", "file": "src/a.sh", "anchor_lines": [4, 5], "description": "x", "severity": "high", "category": "logic"},
           "H02": {"verdict": "not-defect", "not_defect_class": "test", "group": null, "file": null, "anchor_lines": [], "description": null, "severity": null, "category": null}},
 "incidents": {"I01": {"verdict": "defect-at-head", "group": null, "file": "src/a.sh", "anchor_lines": [20], "description": "y", "severity": "medium", "category": "error-handling"}}}
EOF
  jq '.hunks.H01.severity = "medium"' "$P/A.json" > "$P/B.json"
  printf '{"H01": {"review_driven": true}, "H02": {"review_driven": false}}\n' > "$P/hunks.meta.json"
  printf '{"H01": {"verdict": "defect", "group": "D1", "file": "src/a.sh", "anchor_lines": [4, 5], "description": "x", "severity": "high", "category": "logic", "reason": "high: the guard protects a write"}}\n' > "$P/adj.json"
  python3 -I "$MERGE" --fixture pr-95 --a "$P/A.json" --b "$P/B.json" --head-dir "$C/pr-95/head" \
    --schema "$REPO_ROOT/evals/analysis/c132/tests/fixtures/merge/annotation.schema.json" \
    --hunks-meta "$P/hunks.meta.json" --adjudication "$P/adj.json" --out "$P/out" >/dev/null
  cp "$P/out/labels.rows.tsv" "$C/labels/pr-95.tsv"
  "$SEED" --build-manifest pr-95 --corpus "$C" >/dev/null
  M="$C/manifests/pr-95.json"
}

@test "MV-6 a v2 key built end to end (merge rows → --build-manifest) validates, rebuilds byte for byte and needs no --sync-labels row" {
  build_v2
  [ "$(jq -r '.label_set' "$M")" = v2 ]
  [ "$(jq -c '[.defects[] | [.id, .label_source, .agreement, .review_driven, (.anchors // [.anchor_line])]]' "$M")" = \
    '[["V01","fix-commit","adjudicated",true,[4,5]],["V02","incident","agreed",false,[20]]]' ]
  run validate "$M"
  [ "$status" -eq 0 ]
  cp "$M" "$T/first.json"
  run "$SEED" --build-manifest pr-95 --corpus "$T/corpus"
  [ "$status" -eq 0 ]
  cmp -s "$M" "$T/first.json"
  run "$SEED" --sync-labels pr-95 --corpus "$T/corpus"
  [ "$status" -eq 0 ]
  [[ "$output" == *"pr-95: added 0 row(s)"* ]]
}

@test "MV-7 the schema refuses malformed v2 keys: a bad agreement, a v2 defect without review_driven, an annotated source or incidents_meta in a legacy key, an unknown field" {
  build_v2
  local bad
  for bad in '.defects[0].agreement = "maybe"' 'del(.defects[0].review_driven)' '.defects[0].review_driven = null' \
             'del(.label_set)' '.defects[0].annotators = []' '.defects[0].extra = 1' '.record.incidents_meta = {"main_sha": "XYZ"}'; do
    jq "$bad" "$M" > "$T/bad.json"
    run validate "$T/bad.json"
    echo "$bad: $output"
    [ "$status" -eq 1 ]
  done
  jq '.defects[0].label_source = "fix-commit"' "$CORPUS/manifests/c131/pr-17.json" > "$T/legacy-bad.json"
  run validate "$T/legacy-bad.json"
  [ "$status" -eq 1 ]
  jq '.record.incidents_meta = {"main_sha": "abcdef1"}' "$CORPUS/manifests/c131/pr-17.json" > "$T/legacy-meta.json"
  run validate "$T/legacy-meta.json"
  [ "$status" -eq 1 ]
}
