#!/usr/bin/env bats

setup() {
    SOURCE_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    TEST_REPO="$(mktemp -d)"
    mkdir -p "$TEST_REPO/.claude/scripts" "$TEST_REPO/grimoires/loa"
    cp "$SOURCE_ROOT/.claude/scripts/update-ledger-compound.sh" "$TEST_REPO/.claude/scripts/"
    SCRIPT="$TEST_REPO/.claude/scripts/update-ledger-compound.sh"
    LEDGER="$TEST_REPO/grimoires/loa/ledger.json"
}

teardown() {
    rm -rf "$TEST_REPO"
}

@test "compound: blank ledger fails without replacing its bytes" {
    printf '\n' > "$LEDGER"
    cp "$LEDGER" "$TEST_REPO/before"
    run bash "$SCRIPT" --cycle 1
    [ "$status" -ne 0 ]
    cmp "$LEDGER" "$TEST_REPO/before"
}

@test "compound: successful jq with empty transformed output cannot blank ledger" {
    printf '{"cycles":[{"id":"cycle-1","number":1}]}\n' > "$LEDGER"
    cp "$LEDGER" "$TEST_REPO/before"
    mkdir "$TEST_REPO/bin"
    export REAL_JQ="$(command -v jq)"
    cat > "$TEST_REPO/bin/jq" <<'SH'
#!/usr/bin/env bash
for arg in "$@"; do
    if [[ "$arg" == *'.cycles |='* ]]; then
        exit 0
    fi
done
exec "$REAL_JQ" "$@"
SH
    chmod +x "$TEST_REPO/bin/jq"
    run env PATH="$TEST_REPO/bin:$PATH" bash "$SCRIPT" --cycle 1
    [ "$status" -ne 0 ]
    cmp "$LEDGER" "$TEST_REPO/before"
}

@test "compound: malformed and wrong-shaped ledger fail without replacement" {
    for input in '{broken' 'null' '[]' '{"cycles":null}' '{"cycles":[]}\n{"cycles":[]}'; do
        printf '%b' "$input" > "$LEDGER"
        cp "$LEDGER" "$TEST_REPO/before"
        run bash "$SCRIPT" --cycle 1
        [ "$status" -ne 0 ]
        cmp "$LEDGER" "$TEST_REPO/before"
    done
}

@test "compound: dry-run never initializes a missing ledger" {
    run bash "$SCRIPT" --cycle 1 --dry-run
    [ "$status" -eq 0 ]
    [ ! -e "$LEDGER" ]
}

@test "compound: invalid cycle and negative metrics cannot mutate ledger" {
    printf '{"cycles":[]}\n' > "$LEDGER"
    cp "$LEDGER" "$TEST_REPO/before"
    for args in '--cycle 0' '--cycle nope' '--learnings -1' '--patterns 1.5' '--skills-promoted null'; do
        run bash "$SCRIPT" $args
        [ "$status" -ne 0 ]
        cmp "$LEDGER" "$TEST_REPO/before"
    done
}

@test "compound: concurrent cycle updates retain both results" {
    printf '{"cycles":[{"id":"cycle-1"},{"id":"cycle-2"}]}\n' > "$LEDGER"
    bash "$SCRIPT" --cycle 1 --learnings 3 > "$TEST_REPO/one.log" &
    one=$!
    bash "$SCRIPT" --cycle 2 --learnings 7 > "$TEST_REPO/two.log" &
    two=$!
    wait "$one"
    wait "$two"
    [ "$(jq -r '.cycles[0].compound_metrics.learnings_extracted' "$LEDGER")" = 3 ]
    [ "$(jq -r '.cycles[1].compound_metrics.learnings_extracted' "$LEDGER")" = 7 ]
}

@test "compound: initialization produces one valid cycle with requested metrics" {
    run bash "$SCRIPT" --cycle 2 --learnings 3 --patterns 4 --skills-promoted 1
    [ "$status" -eq 0 ]
    jq -e '.cycles | length == 1' "$LEDGER"
    jq -e '.cycles[0] | .number == 2 and .compound_metrics.learnings_extracted == 3 and .compound_metrics.patterns_detected == 4' "$LEDGER"
}
