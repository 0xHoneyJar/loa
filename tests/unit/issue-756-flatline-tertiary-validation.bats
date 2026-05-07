#!/usr/bin/env bats
# =============================================================================
# tests/unit/issue-756-flatline-tertiary-validation.bats
#
# Issue #756: hounfour.flatline_tertiary_model silently fails when set to a
# model name instead of an alias. flatline-readiness should eagerly validate
# the configured tertiary against the alias registry and downgrade to
# DEGRADED with a precise error rather than reporting READY.
#
# Tests:
#   T1 — readiness reads hounfour.flatline_tertiary_model first (matching orchestrator order)
#   T2 — readiness falls back to flatline_protocol.models.tertiary when hounfour path is absent
#   T3 — registered alias passes validation (gemini-3.1-pro)
#   T4 — model_id (NOT an alias, e.g. gemini-3.1-pro-preview) FAILS validation with DEGRADED + alias-list hint
#   T5 — provider:model_id pin form passes validation (S1 explicit-pin path)
#   T6 — unknown alias FAILS validation with DEGRADED + alias-list hint
#   T7 — primary + secondary also validated (regression — same defect class on these slots)
# =============================================================================

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    READINESS="$PROJECT_ROOT/.claude/scripts/flatline-readiness.sh"
    [[ -f "$READINESS" ]] || skip "flatline-readiness.sh not present"
    command -v yq >/dev/null 2>&1 || skip "yq not present"
    command -v jq >/dev/null 2>&1 || skip "jq not present"

    WORK_DIR="$(mktemp -d)"
    # Need a .claude/ marker for bootstrap's auto-detect to land on WORK_DIR.
    mkdir -p "$WORK_DIR/.claude"
    # Symlink defaults dir so check_alias_registry can read aliases. (#755 in
    # one — the alias registry would never load otherwise on a fresh repo.)
    ln -sf "$PROJECT_ROOT/.claude/defaults" "$WORK_DIR/.claude/defaults"
    cd "$WORK_DIR"

    # Mock GOOGLE_API_KEY etc. so provider-key checks don't fail us.
    export ANTHROPIC_API_KEY=test-anthro-key
    export OPENAI_API_KEY=test-openai-key
    export GOOGLE_API_KEY=test-google-key

    # Override PROJECT_ROOT so bootstrap reads the test config, not the real one.
    export PROJECT_ROOT="$WORK_DIR"
    export LOA_CONFIG_FILE="$WORK_DIR/.loa.config.yaml"
}

teardown() {
    cd /
    if [[ -n "${WORK_DIR:-}" ]] && [[ -d "$WORK_DIR" ]]; then
        rm -rf "$WORK_DIR"
    fi
    return 0
}

_write_config() {
    cat > "$LOA_CONFIG_FILE" <<YAML
$1
YAML
}

@test "T1 — readiness reads hounfour.flatline_tertiary_model first (matches orchestrator order)" {
    _write_config 'flatline_protocol:
  enabled: true
  models:
    primary: opus
    secondary: gpt-5.3-codex
    tertiary: gemini-2.5-pro
hounfour:
  flatline_tertiary_model: gemini-3.1-pro'
    run env PROJECT_ROOT="$WORK_DIR" "$READINESS" --json
    [[ "$status" -eq 0 || "$status" -eq 3 ]]
    # The reported tertiary should be from hounfour path (gemini-3.1-pro), not flatline_protocol path (gemini-2.5-pro).
    [[ "$output" == *"gemini-3.1-pro"* ]]
    [[ "$output" != *"\"tertiary\":\"gemini-2.5-pro\""* ]]
}

@test "T2 — readiness falls back to flatline_protocol.models.tertiary when hounfour path is absent" {
    _write_config 'flatline_protocol:
  enabled: true
  models:
    primary: opus
    secondary: gpt-5.3-codex
    tertiary: gemini-2.5-pro'
    run env PROJECT_ROOT="$WORK_DIR" "$READINESS" --json
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"gemini-2.5-pro"* ]]
}

@test "T3 — registered alias (gemini-3.1-pro) passes validation" {
    _write_config 'flatline_protocol:
  enabled: true
  models:
    primary: opus
    secondary: gpt-5.3-codex
    tertiary: gemini-2.5-pro
hounfour:
  flatline_tertiary_model: gemini-3.1-pro'
    run env PROJECT_ROOT="$WORK_DIR" "$READINESS" --json
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"\"status\": \"READY\""* ]]
}

@test "T4 — model_id (NOT alias) FAILS validation with DEGRADED + alias-list hint (#756 main repro)" {
    # gemini-3.1-pro-preview is the model_id; the registered alias is gemini-3.1-pro.
    # Operator misuse — readiness MUST surface DEGRADED + actionable error.
    _write_config 'flatline_protocol:
  enabled: true
  models:
    primary: opus
    secondary: gpt-5.3-codex
    tertiary: gemini-2.5-pro
hounfour:
  flatline_tertiary_model: gemini-3.1-pro-preview'
    run env PROJECT_ROOT="$WORK_DIR" "$READINESS" --json
    # Must NOT be 0 (READY); should be 3 (DEGRADED) per the script's existing exit-code contract.
    [[ "$status" -eq 3 ]]
    [[ "$output" == *"\"status\": \"DEGRADED\""* ]]
    # The error message MUST mention 'gemini-3.1-pro-preview' (the operator's value)
    # so they can find their config entry.
    [[ "$output" == *"gemini-3.1-pro-preview"* ]]
    # And MUST suggest a registered alias (e.g., 'gemini-3.1-pro' is the closest match).
    [[ "$output" == *"alias"* ]]
}

@test "T5 — provider:model_id pin form passes validation (S1 explicit-pin)" {
    _write_config 'flatline_protocol:
  enabled: true
  models:
    primary: opus
    secondary: gpt-5.3-codex
    tertiary: gemini-2.5-pro
hounfour:
  flatline_tertiary_model: "google:gemini-3.1-pro-preview"'
    run env PROJECT_ROOT="$WORK_DIR" "$READINESS" --json
    # Pin form is valid.
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"\"status\": \"READY\""* ]]
}

@test "T6 — unknown alias FAILS validation with DEGRADED + alias-list hint" {
    _write_config 'flatline_protocol:
  enabled: true
  models:
    primary: opus
    secondary: gpt-5.3-codex
    tertiary: gemini-2.5-pro
hounfour:
  flatline_tertiary_model: completely-fictional-model-name-xyz'
    run env PROJECT_ROOT="$WORK_DIR" "$READINESS" --json
    [[ "$status" -eq 3 ]]
    [[ "$output" == *"\"status\": \"DEGRADED\""* ]]
    [[ "$output" == *"completely-fictional-model-name-xyz"* ]]
}

@test "T7 — primary + secondary also validated (regression — same defect class)" {
    # If we only validate tertiary, an operator setting an invalid primary
    # would still see READY. The fix should validate ALL three roles.
    _write_config 'flatline_protocol:
  enabled: true
  models:
    primary: completely-fictional-primary-xyz
    secondary: gpt-5.3-codex
    tertiary: gemini-2.5-pro'
    run env PROJECT_ROOT="$WORK_DIR" "$READINESS" --json
    [[ "$status" -eq 3 ]]
    [[ "$output" == *"\"status\": \"DEGRADED\""* ]]
    [[ "$output" == *"completely-fictional-primary-xyz"* ]]
}
