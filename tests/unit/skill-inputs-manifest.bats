#!/usr/bin/env bats
# OKF/ICM cycle Sprint 6 — ICM Layer-2 advisory inputs manifest + WARN-only rot-lint
# in validate-skill-capabilities.sh. The lint is glass-box (drift signal), NEVER a gate.

setup() {
  BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO="$(cd "$BATS_TEST_DIR/../.." && pwd)"
  VAL="$REPO/.claude/scripts/validate-skill-capabilities.sh"
}

@test "inputs-manifest: the representative skills each declare an inputs: manifest" {
  for s in implementing-tasks reviewing-code auditing-security bug-triaging; do
    grep -qE '^inputs:' "$REPO/.claude/skills/$s/SKILL.md"
  done
}

@test "inputs-manifest: a skill whose declared inputs all exist passes with no advisory" {
  run bash "$VAL" --skill implementing-tasks --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.errors==0' >/dev/null
  echo "$output" | jq -e '[.results[]|select(.level=="advisory")]|length == 0' >/dev/null
}

@test "inputs-manifest: a skill WITHOUT a manifest emits no advisory (absence is fine)" {
  run bash "$VAL" --skill designing-architecture --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '[.results[]|select(.level=="advisory")]|length == 0' >/dev/null
}

@test "inputs-manifest: a declared-but-missing input emits an advisory WARN but does NOT fail" {
  local tmp; tmp="$(mktemp -d)"
  mkdir -p "$tmp/.claude/skills/fixture"
  cp "$REPO/.claude/skills/bug-triaging/SKILL.md" "$tmp/.claude/skills/fixture/SKILL.md"
  # PROJECT_ROOT=tmp → the declared grimoires/loa/known-failures.md path is absent → drift WARN
  run env PROJECT_ROOT="$tmp" SKILLS_DIR="$tmp/.claude/skills" bash "$VAL" --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '[.results[]|select(.level=="advisory")]|length >= 1' >/dev/null
  echo "$output" | jq -e '[.results[]|select(.level=="advisory" and (.message|test("known-failures.md")))]|length >= 1' >/dev/null
  rm -rf "$tmp"
}

@test "inputs-manifest: --strict does NOT promote the inputs advisory to an error (no fail-closed gate)" {
  local tmp; tmp="$(mktemp -d)"
  mkdir -p "$tmp/.claude/skills/fixture"
  cp "$REPO/.claude/skills/bug-triaging/SKILL.md" "$tmp/.claude/skills/fixture/SKILL.md"
  run env PROJECT_ROOT="$tmp" SKILLS_DIR="$tmp/.claude/skills" bash "$VAL" --strict --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '[.results[]|select(.level=="advisory")]|length >= 1' >/dev/null
  # the advisory must NOT have become an error
  echo "$output" | jq -e '[.results[]|select(.level=="error" and (.message|test("declared input not found")))]|length == 0' >/dev/null
  rm -rf "$tmp"
}
