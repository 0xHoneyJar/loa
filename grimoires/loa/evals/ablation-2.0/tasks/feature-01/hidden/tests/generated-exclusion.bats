#!/usr/bin/env bats
# Generated artefacts never become fix regions; real files, lookalikes and labels stay.

load corpus-helper

setup() {
  C="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/ge.XXXXXX")/corpus"
  M="$C/manifests/pr-01.json"
}

regions() { jq -c '[.fix_regions[].file]' "$M"; }

@test "fix rows under a dist directory at any depth are not fix regions" {
  make_corpus "$C" "$(fix_row F001 dist/x.js 1 4)" "$(fix_row F002 tools/bb/resources/dist/main.js 2 3)" \
    "$(fix_row F003 scripts/a.sh 5 6)"
  run "$SEED" --build-manifest pr-01 --corpus "$C"
  [ "$status" -eq 0 ]
  [ "$(regions)" = '["scripts/a.sh"]' ]
}

@test "source maps and type declarations are not fix regions" {
  make_corpus "$C" "$(fix_row F001 web/app.js.map 1 2)" "$(fix_row F002 types/index.d.ts 3 4)" \
    "$(fix_row F003 web/app.js 5 6)"
  run "$SEED" --build-manifest pr-01 --corpus "$C"
  [ "$status" -eq 0 ]
  [ "$(regions)" = '["web/app.js"]' ]
}

@test "checksum, repo-map and build-manifest files are not fix regions at any depth" {
  make_corpus "$C" "$(fix_row F001 .checksum 1 1)" "$(fix_row F002 skills/x/.checksum 1 1)" \
    "$(fix_row F003 checksums.json 2 2)" "$(fix_row F004 .claude/checksums.json 3 3)" \
    "$(fix_row F005 REPO-MAP.md 4 4)" "$(fix_row F006 grimoires/loa/REPO-MAP.md 5 5)" \
    "$(fix_row F007 .build-manifest.json 6 6)" "$(fix_row F008 tools/bb/.build-manifest.json 7 7)" \
    "$(fix_row F009 lib/b.py 8 9)"
  run "$SEED" --build-manifest pr-01 --corpus "$C"
  [ "$status" -eq 0 ]
  [ "$(regions)" = '["lib/b.py"]' ]
}

@test "real fix regions keep their ids, lines and order" {
  make_corpus "$C" "$(fix_row F001 scripts/a.sh 4 9)" "$(fix_row F002 dist/x.js 1 2)" \
    "$(fix_row F003 lib/b.py 12 12)" "$(fix_row F004 x.map 1 1)" "$(fix_row F005 scripts/a.sh 20 22)"
  run "$SEED" --build-manifest pr-01 --corpus "$C"
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.fix_regions[] | [.id, .file, .start, .end, .source]]' "$M")" = \
    '[["F001","scripts/a.sh",4,9,"fix/abcdef12:4-9"],["F003","lib/b.py",12,12,"fix/abcdef12:12-12"],["F005","scripts/a.sh",20,22,"fix/abcdef12:20-22"]]' ]
}

@test "paths that only resemble generated ones stay fix regions" {
  make_corpus "$C" "$(fix_row F001 distribution/a.sh 1 2)" "$(fix_row F002 src/redist.sh 1 2)" \
    "$(fix_row F003 docs/map.md 1 2)" "$(fix_row F004 scripts/roadmap.sh 1 2)" \
    "$(fix_row F005 my-checksums.json 1 2)" "$(fix_row F006 REPO-MAP.md.txt 1 2)" \
    "$(fix_row F007 src/types.ts 1 2)" "$(fix_row F008 dist.sh 1 2)"
  run "$SEED" --build-manifest pr-01 --corpus "$C"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.fix_regions | length' "$M")" = "8" ]
}

@test "review and audit labels on generated files are still defects" {
  make_corpus "$C" "$(review_row F001 dist/x.js row-004 high)" \
    "$(printf 'F002\tlow\tlogic\tchecksums.json\trow-009\taudit\tauditor-sprint-feedback.md')" \
    "$(fix_row F003 dist/x.js 4 4)"
  run "$SEED" --build-manifest pr-01 --corpus "$C"
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.defects[] | [.id, .file, .anchor_line]]' "$M")" = '[["F001","dist/x.js",4],["F002","checksums.json",9]]' ]
  [ "$(jq -r '.fix_regions | length' "$M")" = "0" ]
}

@test "the summary line counts only the kept fix regions" {
  make_corpus "$C" "$(review_row F001 scripts/a.sh row-003)" "$(fix_row F002 scripts/a.sh 4 9)" \
    "$(fix_row F003 dist/x.js 1 2)" "$(fix_row F004 REPO-MAP.md 1 2)"
  run "$SEED" --build-manifest pr-01 --corpus "$C"
  [ "$status" -eq 0 ]
  [[ "$output" == *"pr-01: 1 label(s), 1 fix region(s); approved=False"* ]]
}
