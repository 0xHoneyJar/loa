#!/usr/bin/env bats
# =============================================================================
# Cycle-108 sprint-1 T1.G — rollback trace-comparison integration test
# =============================================================================
# Closes:
#   - SDD §7 (FR-7 IMP-010 trace-comparison rollback test)
#   - SDD §21.3 (Flatline IMP-009 golden-pins operational spec)
#
# Tests verify:
#   1. tools/cycle108-update-golden-pins.sh produces a well-shaped pins file
#   2. The golden trace fixture's sha matches the pin entry
#   3. `--check` mode succeeds when pin and trace agree, fails on tamper
#   4. Pins file conforms to the SDD §21.3 schema (required fields present)
#
# Note: full rollback trace-comparison (running a mini-cycle under
# advisor_strategy.enabled=false and asserting MODELINV trace matches
# golden) requires a baseline replay artifact that the operator generates
# during T3.A.OP. This integration test validates the SUBSTRATE (script +
# pin file + verification flow) is correct; the canonical signed pin lands
# in T3.A.OP.
# =============================================================================

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    SCRIPT="$REPO_ROOT/tools/cycle108-update-golden-pins.sh"
    PINS_JSON="$REPO_ROOT/tests/fixtures/cycle-108/golden-pins.json"
    TRACE_FILE="$REPO_ROOT/tests/fixtures/cycle-108/golden-rollback-trace.modelinv"
    export PROJECT_ROOT="$REPO_ROOT"
}

@test "T1.G: cycle108-update-golden-pins.sh exists and is executable" {
    [ -x "$SCRIPT" ]
}

@test "T1.G: trace fixture exists" {
    [ -f "$TRACE_FILE" ]
}

@test "T1.G: --check mode succeeds when pins file matches trace" {
    run "$SCRIPT" --check
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "OK"
}

@test "T1.G: pins file has required schema_version field" {
    [ -f "$PINS_JSON" ]
    version=$(jq -r '.schema_version' "$PINS_JSON")
    [ "$version" = "1" ]
}

@test "T1.G: rollback-trace pin entry has required fields" {
    pin=$(jq -r '.pins."rollback-trace"' "$PINS_JSON")
    [ "$pin" != "null" ]
    # Each pin must have these fields per SDD §21.3
    for field in fixture_path sha256 signed_by_key_id signed_at rotation_policy last_verified_at; do
        value=$(jq -r --arg f "$field" '.pins."rollback-trace"[$f]' "$PINS_JSON")
        [ "$value" != "null" ]
        [ -n "$value" ]
    done
}

@test "T1.G: pin sha256 matches trace file actual sha" {
    pin_sha=$(jq -r '.pins."rollback-trace".sha256' "$PINS_JSON")
    actual_sha=$(sha256sum "$TRACE_FILE" | awk '{print $1}')
    [ "$pin_sha" = "$actual_sha" ]
}

@test "T1.G: --check mode FAILS on trace-file tamper" {
    # Make a temporary backup, mutate, run --check, restore
    cp "$TRACE_FILE" "$TRACE_FILE.bak"
    echo '{"tampered": true}' >> "$TRACE_FILE"
    run "$SCRIPT" --check
    [ "$status" -ne 0 ]
    mv "$TRACE_FILE.bak" "$TRACE_FILE"
}

@test "T1.G: --check mode FAILS when pins file missing" {
    # Move pins file aside
    if [[ -f "$PINS_JSON" ]]; then
        mv "$PINS_JSON" "$PINS_JSON.bak"
    fi
    run "$SCRIPT" --check
    [ "$status" -ne 0 ]
    # Restore
    if [[ -f "$PINS_JSON.bak" ]]; then
        mv "$PINS_JSON.bak" "$PINS_JSON"
    fi
}

@test "T1.G: --pin-id <unknown> fails verification" {
    run "$SCRIPT" --check --pin-id nonexistent-pin-zzz
    [ "$status" -ne 0 ]
}

@test "T1.G: re-running update is idempotent (same sha on stable trace)" {
    sha1=$(jq -r '.pins."rollback-trace".sha256' "$PINS_JSON")
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    sha2=$(jq -r '.pins."rollback-trace".sha256' "$PINS_JSON")
    [ "$sha1" = "$sha2" ]
}

# -----------------------------------------------------------------------------
# Sprint 2 T2.M / sprint-1 reviewer C3 closure:
# LOA_GOLDEN_PINS_REQUIRE_SIGNED=1 refuses to validate UNSIGNED pins.
# -----------------------------------------------------------------------------

@test "T2.M C3: --check with LOA_GOLDEN_PINS_REQUIRE_SIGNED=1 rejects unsigned pin" {
    # The committed pin may be either signed or unsigned depending on whether
    # an operator key was available at last update. Force-unsign for the test
    # by rewriting the field, then restore.
    cp "$PINS_JSON" "$PINS_JSON.bak"
    tmp_unsigned=$(mktemp)
    jq '.pins."rollback-trace".signed = false' "$PINS_JSON" > "$tmp_unsigned"
    mv "$tmp_unsigned" "$PINS_JSON"
    LOA_GOLDEN_PINS_REQUIRE_SIGNED=1 run "$SCRIPT" --check
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "REFUSED\|UNSIGNED"
    mv "$PINS_JSON.bak" "$PINS_JSON"
}

@test "T2.M C3: --check WITHOUT require-signed accepts unsigned pin (back-compat)" {
    cp "$PINS_JSON" "$PINS_JSON.bak"
    tmp_unsigned=$(mktemp)
    jq '.pins."rollback-trace".signed = false' "$PINS_JSON" > "$tmp_unsigned"
    mv "$tmp_unsigned" "$PINS_JSON"
    unset LOA_GOLDEN_PINS_REQUIRE_SIGNED
    run "$SCRIPT" --check
    [ "$status" -eq 0 ]
    mv "$PINS_JSON.bak" "$PINS_JSON"
}
