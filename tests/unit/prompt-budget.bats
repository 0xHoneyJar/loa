#!/usr/bin/env bats
# =============================================================================
# tests/unit/prompt-budget.bats — cycle-124 FR-8 / AC-8.1
#
# tools/check-prompt-budget.sh enforces the byte budgets of the always-loaded
# prompt surface: SKILL.md ≤ 16,384 B (charged with unconditionally-read
# resources), CLAUDE.loa.md ≤ 10,240 B, protocols total ≤ 200,000 B (warn
# above 143,360 B). Passes at exactly the limit, fails one byte over.
# PB-9 is the live gate: red until the Sprint 3 audit lands.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    TOOL="$PROJECT_ROOT/tools/check-prompt-budget.sh"
    T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/pb.XXXXXX")"
    mkdir -p "$T/.claude/skills/s1/resources" "$T/.claude/loa" "$T/.claude/protocols"
    P="$T/.claude/protocols"
    fill "$T/.claude/loa/CLAUDE.loa.md" 100
    fill "$P/a.md" 100
}

teardown() { find "$T" -mindepth 1 -delete 2>/dev/null || true; rmdir "$T" 2>/dev/null || true; }

fill() {  # fill <path> <bytes> — exactly <bytes> bytes of text
    head -c "$2" /dev/zero | tr '\0' 'x' > "$1"
}

@test "PB-1 a SKILL.md of exactly 16,384 bytes passes" {
    fill "$T/.claude/skills/s1/SKILL.md" 16384
    run "$TOOL" --root "$T" --quiet
    [ "$status" -eq 0 ]
}

@test "PB-2 a SKILL.md of 16,385 bytes fails and the breach names the skill and the byte count" {
    fill "$T/.claude/skills/s1/SKILL.md" 16385
    run "$TOOL" --root "$T"
    [ "$status" -eq 1 ]
    [[ "$output" == *"skill s1: 16385 B > 16384 B"* ]]
}

@test "PB-3 an unguarded read imperative charges the resource; a guarded pointer does not" {
    fill "$T/.claude/skills/s1/resources/REFERENCE.md" 1000
    { fill /dev/stdout 15500; printf '\nRead `resources/REFERENCE.md` before starting.\n'; } > "$T/.claude/skills/s1/SKILL.md"
    run "$TOOL" --root "$T" --json
    [ "$status" -eq 1 ]
    [ "$(echo "$output" | jq -r '.skills[0].charged_resources | length')" = "1" ]
    [ "$(echo "$output" | jq -r '.skills[0].charged_resources[0].bytes')" = "1000" ]
    { fill /dev/stdout 15500; printf '\nSee `resources/REFERENCE.md` §Security if you need the checklist.\n'; } > "$T/.claude/skills/s1/SKILL.md"
    run "$TOOL" --root "$T" --json
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.skills[0].charged_resources | length')" = "0" ]
}

@test "PB-4 CLAUDE.loa.md passes at 10,240 bytes and fails at 10,241" {
    fill "$T/.claude/skills/s1/SKILL.md" 100
    fill "$T/.claude/loa/CLAUDE.loa.md" 10240
    run "$TOOL" --root "$T" --quiet
    [ "$status" -eq 0 ]
    fill "$T/.claude/loa/CLAUDE.loa.md" 10241
    run "$TOOL" --root "$T"
    [ "$status" -eq 1 ]
    [[ "$output" == *"CLAUDE.loa.md: 10241 B > 10240 B"* ]]
}

@test "PB-5 protocols: above 143,360 warns but passes; above 200,000 fails" {
    fill "$T/.claude/skills/s1/SKILL.md" 100
    fill "$P/a.md" 100000
    fill "$P/b.md" 50000
    run "$TOOL" --root "$T" --json
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.protocols.warn')" = "true" ]
    [ "$(echo "$output" | jq -r '.protocols.total')" = "150000" ]
    fill "$P/c.md" 50001
    run "$TOOL" --root "$T"
    [ "$status" -eq 1 ]
    [[ "$output" == *"protocols total: 200001 B > 200000 B"* ]]
}

@test "PB-6 --json carries per-skill totals, limits, history token counts and the violation list" {
    fill "$T/.claude/skills/s1/SKILL.md" 20000
    printf 'see cycle-119 and #1177 and KF-004\n' >> "$T/.claude/skills/s1/SKILL.md"
    run "$TOOL" --root "$T" --json
    [ "$status" -eq 1 ]
    [ "$(echo "$output" | jq -r '.ok')" = "false" ]
    [ "$(echo "$output" | jq -r '.skills[0].limit')" = "16384" ]
    [ "$(echo "$output" | jq -r '.skills[0].history_tokens')" = "3" ]
    [ "$(echo "$output" | jq -r '.violations | length')" = "1" ]
    [ "$(echo "$output" | jq -r '.claude_loa.limit')" = "10240" ]
    [ "$(echo "$output" | jq -r '.protocols.fail_limit')" = "200000" ]
}

@test "PB-7 a root without .claude/ is a usage error (2)" {
    run "$TOOL" --root "$T/nope" --quiet
    [ "$status" -eq 2 ]
}

@test "PB-8 CI sentinel fixtures: the over tree fails with 1, the under tree passes" {
    run "$TOOL" --root "$PROJECT_ROOT/tests/fixtures/prompt-budget/over" --quiet
    [ "$status" -eq 1 ]
    run "$TOOL" --root "$PROJECT_ROOT/tests/fixtures/prompt-budget/under" --quiet
    [ "$status" -eq 0 ]
}

@test "PB-9 live gate: the repository's prompt surface fits every budget" {
    run "$TOOL" --root "$PROJECT_ROOT"
    echo "$output"
    [ "$status" -eq 0 ]
}
