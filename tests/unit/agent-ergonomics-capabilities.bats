#!/usr/bin/env bats
# =============================================================================
# tests/unit/agent-ergonomics-capabilities.bats
# agent-ergonomics pass 1 (bd-m1o6) R-006 — loa-capabilities.sh contract
# surface + DRIFT GATE: every listed script must exist, and every
# help:"true" claim must hold (bash <script> --help → exit 0). If you add,
# move, or de-help a script, update the table in loa-capabilities.sh.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    CAP="$PROJECT_ROOT/.claude/scripts/loa-capabilities.sh"
}

@test "R-006: --json emits one valid JSON doc with schema_version + scripts" {
    run timeout 15 bash "$CAP" --json
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -s 'length')" -eq 1 ]
    echo "$output" | jq -e '.schema_version == "1" and (.scripts | length) >= 15' >/dev/null
}

@test "R-006: human mode renders the table without ANSI escapes" {
    run timeout 15 bash "$CAP"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "loa capabilities" ]]
    [[ "$output" != *$'\033'* ]]
}

@test "R-006: unknown flag rejected with exit 2 + usage" {
    run timeout 15 bash "$CAP" --jsno
    [ "$status" -eq 2 ]
    [[ "$output" =~ "Unknown option" ]]
}

@test "R-006 DRIFT GATE: every listed script exists" {
    run timeout 15 bash "$CAP" --json
    [ "$status" -eq 0 ]
    local missing=0
    while IFS= read -r p; do
        if [[ ! -f "$PROJECT_ROOT/$p" ]]; then
            echo "MISSING: $p"
            missing=1
        fi
    done < <(echo "$output" | jq -r '.scripts[].path')
    [ "$missing" -eq 0 ]
}

@test "R-006 DRIFT GATE: every help:true claim holds (--help exits 0)" {
    run timeout 15 bash "$CAP" --json
    [ "$status" -eq 0 ]
    local bad=0
    while IFS= read -r p; do
        if ! timeout 20 bash "$PROJECT_ROOT/$p" --help >/dev/null 2>&1; then
            echo "HELP CLAIM BROKEN: $p (--help did not exit 0)"
            bad=1
        fi
    done < <(echo "$output" | jq -r '.scripts[] | select(.help == "true") | .path')
    [ "$bad" -eq 0 ]
}

@test "R-006: version field matches .loa-version.json" {
    run timeout 15 bash "$CAP" --json
    [ "$status" -eq 0 ]
    local want
    want=$(jq -r '.framework_version' "$PROJECT_ROOT/.loa-version.json")
    echo "$output" | jq -e --arg w "$want" '.framework_version == $w' >/dev/null
}
