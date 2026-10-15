#!/usr/bin/env bats
# build-manifest.bats — seed-corpus-from-record.sh --build-manifest over a tiny corpus.

load corpus-helper

setup() {
  C="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/bm.XXXXXX")/corpus"
  M="$C/manifests/pr-01.json"
}

@test "a review label becomes a defect anchored on the line its must_match sits on" {
  make_corpus "$C" "$(review_row F001 scripts/a.sh row-007 high)"
  run "$SEED" --build-manifest pr-01 --corpus "$C"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.defects | length' "$M")" = "1" ]
  [ "$(jq -r '.defects[0].id' "$M")" = "F001" ]
  [ "$(jq -r '.defects[0].anchor_line' "$M")" = "7" ]
  [ "$(jq -r '.defects[0].severity' "$M")" = "high" ]
  [ "$(jq -r '.approved' "$M")" = "false" ]
  [ "$(jq -r '.record.sprint' "$M")" = "901" ]
}

@test "fix rows become fix regions with their start and end lines" {
  make_corpus "$C" "$(review_row F001 scripts/a.sh row-003)" "$(fix_row F002 scripts/a.sh 4 9)" "$(fix_row F003 lib/b.py 12 12)"
  run "$SEED" --build-manifest pr-01 --corpus "$C"
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.fix_regions[] | [.id, .file, .start, .end]]' "$M")" = '[["F002","scripts/a.sh",4,9],["F003","lib/b.py",12,12]]' ]
  [[ "$output" == *"pr-01: 1 label(s), 2 fix region(s); approved=False"* ]]
}

@test "the manifest build refreshes SHA256SUMS over the corpus" {
  make_corpus "$C" "$(review_row F001 scripts/a.sh row-003)"
  run "$SEED" --build-manifest pr-01 --corpus "$C"
  [ "$status" -eq 0 ]
  grep -q '  manifests/pr-01.json$' "$C/SHA256SUMS"
  run "$SEED" --check --corpus "$C"
  [ "$status" -eq 0 ]
}

@test "a must_match that is not on exactly one line refuses the build" {
  make_corpus "$C" "$(review_row F001 scripts/a.sh row-0)"
  run "$SEED" --build-manifest pr-01 --corpus "$C"
  [ "$status" -eq 1 ]
  [[ "$output" == *"is not on exactly one line"* ]]
}

@test "a fixture id that is not pr-NN is a usage error" {
  make_corpus "$C" "$(review_row F001 scripts/a.sh row-003)"
  run "$SEED" --build-manifest pr-1 --corpus "$C"
  [ "$status" -eq 2 ]
}
