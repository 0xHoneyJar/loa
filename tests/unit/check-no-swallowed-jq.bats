#!/usr/bin/env bats
# Unit tests for tools/check-no-swallowed-jq.sh.

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    SCANNER="$PROJECT_ROOT/tools/check-no-swallowed-jq.sh"
    [[ -x "$SCANNER" ]] || skip "scanner not executable: $SCANNER"
    FIXTURE_ROOT="$BATS_TEST_TMPDIR/fixture-root"
    mkdir -p "$FIXTURE_ROOT"
}

teardown() {
    rm -rf "$FIXTURE_ROOT"
}

@test "clean script exits 0" {
    cat > "$FIXTURE_ROOT/clean.sh" <<'SH'
#!/usr/bin/env bash
value="$(jq -r '.value' data.json)"
echo "$value"
SH
    run "$SCANNER" --root "$FIXTURE_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "jq default fallback is flagged" {
    cat > "$FIXTURE_ROOT/bad.sh" <<'SH'
#!/usr/bin/env bash
count="$(jq -r '.count' report.json 2>/dev/null || echo 0)"
SH
    run "$SCANNER" --root "$FIXTURE_ROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"bad.sh"* ]]
    [[ "$output" == *"jq -r"* ]]
}

@test "suppression marker bypasses only its line" {
    cat > "$FIXTURE_ROOT/suppressed.sh" <<'SH'
#!/usr/bin/env bash
ok="$(jq -r '.legacy' report.json || echo legacy)" # check-no-swallowed-jq: ok legacy fixture
bad="$(jq -r '.count' report.json || printf '0')"
SH
    run "$SCANNER" --root "$FIXTURE_ROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"bad="* ]]
    [[ "$output" != *"legacy"* ]]
}

@test "heredoc fixture text is not flagged" {
    cat > "$FIXTURE_ROOT/heredoc-fixture.bats" <<'SH'
#!/usr/bin/env bats
@test "plants a bad example" {
    cat > "$BATS_TEST_TMPDIR/bad.sh" <<'SCRIPT'
#!/usr/bin/env bash
count="$(jq -r '.count' report.json 2>/dev/null || echo 0)"
SCRIPT
    true
}
SH
    run "$SCANNER" --root "$FIXTURE_ROOT"
    [ "$status" -eq 0 ]
}

@test "extensionless bash shebang scripts are scanned" {
    cat > "$FIXTURE_ROOT/no-ext" <<'SH'
#!/usr/bin/env bash
count="$(jq -r '.count' report.json || echo 0)"
SH
    run "$SCANNER" --root "$FIXTURE_ROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"no-ext"* ]]
}
