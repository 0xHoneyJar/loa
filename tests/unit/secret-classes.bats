#!/usr/bin/env bats
# =============================================================================
# secret-classes.bats — .claude/scripts/lib/secret-classes.sh (cycle-133 Sprint 3
# Task 3.3, SDD C-12 "the same scanner as C-4"): the credential classes and the
# placeholder filter extracted from record-branch.sh into one sourced library
# that record-branch.sh and evals/harness/seed-corpus-from-external.sh share.
#
# The golden hit lists under tests/fixtures/secret-classes/ were produced by the
# pre-extraction record-branch.sh helper (commit de366cc63) on the planted tree
# that plant.sh writes; the library must reproduce them byte for byte.
# =============================================================================

setup() {
  BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO="$(cd "$BATS_TEST_DIR/../.." && pwd)"
  LIB="$REPO/.claude/scripts/lib/secret-classes.sh"
  FX="$REPO/tests/fixtures/secret-classes"
  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
  W="$BATS_TEST_TMPDIR"
  bash "$FX/plant.sh" "$W/scan" > "$W/list"
}

@test "secret-classes: credscan reproduces the pre-extraction hit list byte for byte" {
  run bash -c 'source "$1" && secret_classes_py credscan "$2" "$3"' _ "$LIB" "$W/scan" "$W/list"
  [ "$status" -eq 0 ]
  [ "$output" = "$(cat "$FX/expected-cred.hits")" ]
}

@test "secret-classes: secret_classes_scan writes both hit lists identical to the goldens; no matched text is printed" {
  run bash -c 'source "$1" && secret_classes_scan "$2" "$3" "$4/cred" "$4/other"' _ "$LIB" "$W/scan" "$W/list" "$W"
  [ "$status" -eq 0 ]
  cmp "$W/cred" "$FX/expected-cred.hits"
  cmp "$W/other" "$FX/expected-other.hits"
  [[ "$output" != *"Ab1Cd2Ef3Gh4"* ]]
}

@test "secret-classes: every class the record branch refuses is named, and the placeholder filter holds" {
  run bash -c 'source "$1" && secret_classes_names' _ "$LIB"
  [ "$status" -eq 0 ]
  [ "$output" = "private-key anthropic-key openai-key github-token aws-access-key google-api-key slack-token bearer-token" ]
  # placeholders (x…, 0…) and prose after Bearer are not hits
  ! grep -q '^b/c/placeholders.md:[1245]:' "$FX/expected-cred.hits"
}

@test "secret-classes: a clean tree gives two empty lists and exit 0" {
  mkdir -p "$W/clean"; printf 'nothing here\n' > "$W/clean/f.txt"; printf 'f.txt\n' > "$W/clean.list"
  run bash -c 'source "$1" && secret_classes_scan "$2" "$3" "$4/c1" "$4/c2"' _ "$LIB" "$W/clean" "$W/clean.list" "$W"
  [ "$status" -eq 0 ]
  [ ! -s "$W/c1" ] && [ ! -s "$W/c2" ]
}

@test "secret-classes: record-branch.sh sources the library and keeps no copy of the class regexes" {
  grep -q 'lib/secret-classes.sh' "$REPO/.claude/scripts/record-branch.sh"
  ! grep -q 'def secretish' "$REPO/.claude/scripts/record-branch.sh"
  grep -q 'lib/secret-classes.sh' "$REPO/evals/harness/seed-corpus-from-external.sh"
}

@test "secret-classes: executed (not sourced) it is a CLI for Python callers: scan writes both lists, a bad call exits 2" {
  run bash "$LIB" scan "$W/scan" "$W/list" "$W/cli-cred" "$W/cli-other"
  [ "$status" -eq 0 ]
  cmp "$W/cli-cred" "$FX/expected-cred.hits"
  cmp "$W/cli-other" "$FX/expected-other.hits"
  run bash "$LIB" names
  [ "$status" -eq 0 ]
  [[ "$output" == "private-key "* ]]
  run bash "$LIB" scan "$W/scan"
  [ "$status" -eq 2 ]
  run bash "$LIB"
  [ "$status" -eq 2 ]
}
