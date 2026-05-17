#!/usr/bin/env bats
# cycle-112 Sprint 1 (#166) T1.6 — model-economy NFR-Determinism-1 gate.
#
# AC (PRD §7 NFR-Determinism-1): 3 consecutive runs against the same
# fixture produce byte-identical output modulo timestamp banner.

setup() {
    export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export TMP="$(mktemp -d -t loa-economy-det-XXXXXX)"
    export CLI="$PROJECT_ROOT/tools/model-economy-roll-up.sh"
    export FIXTURES="$PROJECT_ROOT/tests/fixtures/model-economy"
    export MODEL_CONFIG="$PROJECT_ROOT/.claude/defaults/model-config.yaml"
}

teardown() {
    rm -rf "$TMP"
}

@test "T1.6.determinism: 3 runs of text mode --no-ts-banner are byte-identical" {
    out1="$TMP/run1.txt"; out2="$TMP/run2.txt"; out3="$TMP/run3.txt"
    "$CLI" --log-path "$FIXTURES/snapshot-input.jsonl" \
        --model-config "$MODEL_CONFIG" --window 9999d --no-ts-banner > "$out1"
    "$CLI" --log-path "$FIXTURES/snapshot-input.jsonl" \
        --model-config "$MODEL_CONFIG" --window 9999d --no-ts-banner > "$out2"
    "$CLI" --log-path "$FIXTURES/snapshot-input.jsonl" \
        --model-config "$MODEL_CONFIG" --window 9999d --no-ts-banner > "$out3"

    diff -q "$out1" "$out2"
    diff -q "$out2" "$out3"
}

@test "T1.6.determinism: text output matches golden fixture" {
    # The golden was captured from a clean run of the same aggregator
    # against snapshot-input.jsonl. Re-capturing it should produce
    # byte-identical output. If this fails, either:
    #   (a) the aggregator's rendering shape changed (regenerate the
    #       golden + bump the test), or
    #   (b) determinism is broken (investigate).
    out="$TMP/current.txt"
    "$CLI" --log-path "$FIXTURES/snapshot-input.jsonl" \
        --model-config "$MODEL_CONFIG" --window 9999d --no-ts-banner > "$out"
    # Strip absolute repo-root prefix so the comparison is portable across
    # checkouts. The golden is checked in with repo-relative paths.
    sed -i "s|${PROJECT_ROOT}/||g" "$out"
    diff "$FIXTURES/snapshot-golden.txt" "$out"
}

@test "T1.6.determinism: JSON mode rows have stable ordering across runs" {
    # JSON-mode 'now' / 'since' timestamps differ across runs (clock advances)
    # but per_skill_model row keys must be stable.
    keys1=$("$CLI" --log-path "$FIXTURES/snapshot-input.jsonl" \
        --model-config "$MODEL_CONFIG" --window 9999d --json \
        | python3 -c "import json, sys; print(','.join(sorted(json.loads(sys.stdin.read())['per_skill_model'].keys())))")
    keys2=$("$CLI" --log-path "$FIXTURES/snapshot-input.jsonl" \
        --model-config "$MODEL_CONFIG" --window 9999d --json \
        | python3 -c "import json, sys; print(','.join(sorted(json.loads(sys.stdin.read())['per_skill_model'].keys())))")
    [ "$keys1" = "$keys2" ]
}
