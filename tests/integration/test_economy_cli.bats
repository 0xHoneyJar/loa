#!/usr/bin/env bats
# cycle-112 Sprint 1 (#166) T1.6 — model-economy CLI integration tests.
#
# Covers (PRD §4 FR-1 + FR-2 acceptance criteria):
#   - text mode + JSON mode default behavior
#   - --window argument
#   - --skill / --model substring filters
#   - --json schema validation
#   - exit codes per SDD §5.1
#   - missing-log graceful path (exit 0, "0 envelopes")

setup() {
    export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export TMP="$(mktemp -d -t loa-economy-cli-XXXXXX)"
    export CLI="$PROJECT_ROOT/tools/model-economy-roll-up.sh"
    export FIXTURES="$PROJECT_ROOT/tests/fixtures/model-economy"
    export MODEL_CONFIG="$PROJECT_ROOT/.claude/defaults/model-config.yaml"
}

teardown() {
    rm -rf "$TMP"
}

# ---------------------------------------------------------------------------
# Text mode
# ---------------------------------------------------------------------------

@test "T1.6.cli: text mode emits coverage line + table" {
    run "$CLI" --log-path "$FIXTURES/fully-attributed.jsonl" \
        --model-config "$MODEL_CONFIG" --window 9999d
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Model-Economy Roll-Up"
    echo "$output" | grep -q "Coverage:"
    echo "$output" | grep -q "/review-sprint"
    echo "$output" | grep -q "anthropic:claude-opus-4-7"
}

@test "T1.6.cli: text mode surfaces D-6 follow-up disclosure on (unattributed) data" {
    run "$CLI" --log-path "$FIXTURES/no-attribution.jsonl" \
        --model-config "$MODEL_CONFIG" --window 9999d
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "(unattributed)"
    echo "$output" | grep -q "D-6 follow-up"
}

@test "T1.6.cli: text mode shows — for unpriced rows" {
    run "$CLI" --log-path "$FIXTURES/malformed-lines.jsonl" \
        --model-config "$MODEL_CONFIG" --window 9999d
    [ "$status" -eq 0 ]
    # Gemini row in malformed-lines has no pricing/capability → "—"
    echo "$output" | grep -q "gemini"
    echo "$output" | grep -q "—"
}

# ---------------------------------------------------------------------------
# JSON mode
# ---------------------------------------------------------------------------

@test "T1.6.cli: --json emits well-formed JSON" {
    run "$CLI" --log-path "$FIXTURES/no-attribution.jsonl" \
        --model-config "$MODEL_CONFIG" --window 9999d --json
    [ "$status" -eq 0 ]
    # Validate JSON parseability + key presence
    echo "$output" | python3 -c "import json, sys; d=json.loads(sys.stdin.read()); assert 'coverage' in d and 'per_skill_model' in d and 'footer' in d, d.keys()"
}

@test "T1.6.cli: --json output validates against schema" {
    run "$CLI" --log-path "$FIXTURES/fully-attributed.jsonl" \
        --model-config "$MODEL_CONFIG" --window 9999d --json
    [ "$status" -eq 0 ]
    schema="$PROJECT_ROOT/.claude/data/schemas/model-economy-rollup.schema.json"
    echo "$output" | python3 -c "
import json, sys, jsonschema
d = json.loads(sys.stdin.read())
s = json.load(open('$schema'))
jsonschema.Draft202012Validator(s).validate(d)
print('schema OK')
"
}

# ---------------------------------------------------------------------------
# Filters
# ---------------------------------------------------------------------------

@test "T1.6.cli: --skill substring filter" {
    run "$CLI" --log-path "$FIXTURES/fully-attributed.jsonl" \
        --model-config "$MODEL_CONFIG" --window 9999d --skill review --json
    [ "$status" -eq 0 ]
    # Every row's skill should contain "review"
    echo "$output" | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
for k, row in d['per_skill_model'].items():
    assert 'review' in row['skill'], 'unexpected skill: %s' % row
print('%d rows, all contain review' % len(d['per_skill_model']))
"
}

@test "T1.6.cli: --model substring filter" {
    run "$CLI" --log-path "$FIXTURES/fully-attributed.jsonl" \
        --model-config "$MODEL_CONFIG" --window 9999d --model anthropic --json
    [ "$status" -eq 0 ]
    echo "$output" | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
for k, row in d['per_skill_model'].items():
    assert 'anthropic' in row['model'], f'unexpected model: {row}'
"
}

# ---------------------------------------------------------------------------
# Exit codes (SDD §5.1)
# ---------------------------------------------------------------------------

@test "T1.6.cli: invalid --window → exit 2" {
    run "$CLI" --log-path "$FIXTURES/empty.jsonl" \
        --model-config "$MODEL_CONFIG" --window NOPE
    [ "$status" -eq 2 ]
}

@test "T1.6.cli: missing model-config → exit 3" {
    run "$CLI" --log-path "$FIXTURES/no-attribution.jsonl" \
        --model-config /nonexistent/path.yaml --window 7d
    [ "$status" -eq 3 ]
}

@test "T1.6.cli: invalid --cost-snapshot ref → exit 5" {
    run "$CLI" --log-path "$FIXTURES/no-attribution.jsonl" \
        --model-config "$MODEL_CONFIG" --window 7d \
        --cost-snapshot deadbeef-never-existed
    [ "$status" -eq 5 ]
}

@test "T1.6.cli: missing log → exit 0 with 0 envelopes" {
    # SDD §6: missing log is graceful, not an error.
    run "$CLI" --log-path "$TMP/does-not-exist.jsonl" \
        --model-config "$MODEL_CONFIG" --window 24h
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "0 envelopes"
}

# ---------------------------------------------------------------------------
# Empty fixture
# ---------------------------------------------------------------------------

@test "T1.6.cli: empty fixture → no rows, no crash" {
    run "$CLI" --log-path "$FIXTURES/empty.jsonl" \
        --model-config "$MODEL_CONFIG" --window 9999d
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "0 envelopes"
    echo "$output" | grep -q "No envelopes matched"
}
