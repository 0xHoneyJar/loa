#!/usr/bin/env bats
# =============================================================================
# dec-write-length.bats — `dec-write new` refuses a long --summary naming the
# measured and the maximum length and the first 160 code points (cycle-133
# Sprint 1 Task 1.5; SDD C-4; PRD FR-4(d); bd-d7dwt). Hermetic temp project,
# as tests/unit/dec-write-lib.bats.
# =============================================================================

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
  command -v yq >/dev/null 2>&1 || skip "yq not installed"
  [[ "$(yq --version 2>&1)" == *mikefarah*"version v4."* ]] || skip "Mike Farah yq v4 not installed"
  unset CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID LOA_UNATTENDED LOA_FLATLINE_MODE CI GITHUB_ACTIONS LOA_HOOK_CONTEXT
  T="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$T/.claude/scripts/lib" "$T/grimoires/loa"
  cp "$REPO/.claude/scripts/lib/dec-write-lib.sh" "$T/.claude/scripts/lib/"
  cp "$REPO/.claude/scripts/compat-lib.sh" "$REPO/.claude/scripts/validate-artifact.sh" "$T/.claude/scripts/"
  [[ -f "$REPO/.claude/scripts/pii-filter.sh" ]] && cp "$REPO/.claude/scripts/pii-filter.sh" "$T/.claude/scripts/"
  { sed '/^schema_version:/,$d' "$REPO/grimoires/loa/decisions.yaml"; printf 'schema_version: 1\ndecisions: []\n'; } > "$T/grimoires/loa/decisions.yaml"
  git -C "$T" init -q
  D="$T/.claude/scripts/lib/dec-write-lib.sh"
  L="$T/grimoires/loa/decisions.yaml"
}

new_with() { bash "$D" new --file "$L" --summary "$1" --phase discovery --category scope --recorded-by plan-and-analyze --source "prd.md#fr-1" --quiet; }

@test "dec-write length: a 170-code-point summary is refused naming 170 and 160 and quoting the first 160 code points" {
  # multi-byte on purpose: 170 code points, 340 bytes
  s="$(printf 'é%.0s' $(seq 1 170))"
  first160="$(printf 'é%.0s' $(seq 1 160))"
  cp "$L" "$BATS_TEST_TMPDIR/before"
  run new_with "$s"
  [ "$status" -eq 1 ]
  [[ "$output" == *"170 code points (limit 160)"* ]] || { echo "$output"; false; }
  [[ "$output" == *": ${first160}…"* ]]
  [[ "$output" != *"${first160}é"* ]]
  [[ "$output" == *"over 160 characters"* ]]
  cmp -s "$L" "$BATS_TEST_TMPDIR/before"
}

@test "dec-write length: exactly 160 code points is accepted" {
  s="$(printf 'a%.0s' $(seq 1 160))"
  run new_with "$s"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}
