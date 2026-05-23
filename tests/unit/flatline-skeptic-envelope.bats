#!/usr/bin/env bats
# =============================================================================
# flatline-skeptic-envelope.bats
#
# Regression test for the Flatline consensus-shape bug:
#   jq: Cannot index array with string "concerns"
#
# Root cause: flatline-orchestrator.sh wrote skeptic prepared JSON in whatever
# shape extract_json_content produced. scoring-engine.sh's
# `$skeptic_x[0].concerns` access fails when the model emitted a bare
# top-level array instead of {"concerns":[...]}.
#
# Fix: normalize_skeptic_envelope() in flatline-orchestrator.sh wraps bare
# arrays into the object envelope before consensus runs.
# =============================================================================

setup() {
    ORCH="$BATS_TEST_DIRNAME/../../.claude/scripts/flatline-orchestrator.sh"
    [[ -f "$ORCH" ]] || skip "flatline-orchestrator.sh not present"
    command -v jq >/dev/null 2>&1 || skip "jq not present"

    WORK_DIR="$(mktemp -d)"
    HELPER="$WORK_DIR/helper.sh"

    # Extract just the function body (matches the pattern used in
    # tests/unit/flatline-jq-construction.bats:T9).
    awk '/^normalize_skeptic_envelope\(\)/,/^}$/' "$ORCH" > "$HELPER"
    [[ -s "$HELPER" ]] || {
        echo "normalize_skeptic_envelope() not found in orchestrator" >&2
        return 1
    }
}

teardown() {
    [[ -n "${WORK_DIR:-}" && -d "$WORK_DIR" ]] && rm -rf "$WORK_DIR"
    return 0
}

@test "object-shaped skeptic prepared JSON is preserved unchanged" {
    local f="$WORK_DIR/skeptic-object.json"
    cat > "$f" <<'JSON'
{"concerns":[{"id":"c1","concern":"x","severity":"high","severity_score":700}]}
JSON

    run bash -c "source '$HELPER'; normalize_skeptic_envelope '$f'"
    [ "$status" -eq 0 ]

    # Envelope intact, concerns array intact, single concern preserved.
    [[ "$(jq -r '.concerns | length' "$f")" == "1" ]]
    [[ "$(jq -r '.concerns[0].id' "$f")" == "c1" ]]
    [[ "$(jq -r '.concerns[0].severity_score' "$f")" == "700" ]]

    # And the slurpfile access pattern scoring-engine uses now succeeds.
    run jq --slurpfile s "$f" -n '$s[0].concerns | length'
    [ "$status" -eq 0 ]
    [[ "$output" == "1" ]]
}

@test "bare-array skeptic prepared JSON is wrapped to {concerns:[...]}" {
    local f="$WORK_DIR/skeptic-array.json"
    cat > "$f" <<'JSON'
[{"id":"c1","concern":"x","severity":"high","severity_score":700}]
JSON

    # Pre-fix reproduction: bare array breaks scoring-engine's $s[0].concerns.
    run jq --slurpfile s "$f" -n '$s[0].concerns'
    [ "$status" -ne 0 ]
    [[ "$output" == *"Cannot index array with string \"concerns\""* ]]

    run bash -c "source '$HELPER'; normalize_skeptic_envelope '$f'"
    [ "$status" -eq 0 ]

    # Post-fix: envelope present, concerns array carries the original item.
    [[ "$(jq -r 'type' "$f")" == "object" ]]
    [[ "$(jq -r '.concerns | length' "$f")" == "1" ]]
    [[ "$(jq -r '.concerns[0].id' "$f")" == "c1" ]]

    # And the slurpfile access pattern scoring-engine uses now succeeds.
    run jq --slurpfile s "$f" -n '$s[0].concerns | length'
    [ "$status" -eq 0 ]
    [[ "$output" == "1" ]]
}
