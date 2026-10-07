#!/usr/bin/env bats
# =============================================================================
# flatline-tertiary-agy-opt-in.bats — cycle-127 FR-1. The agy (Antigravity) route is opt-in
# (hounfour.headless.agy_opt_in, default false). A Flatline tertiary routed to agy with the opt-in off
# is not planned: skipped as "disabled by opt-in" (2-model mode, tertiary status disabled_by_opt_in),
# never dispatched and never a DEGRADED voice. No model is called.
# =============================================================================

bats_require_minimum_version 1.5.0

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    source "$REPO/.claude/scripts/flatline-orchestrator.sh"
    CONFIG_FILE="$BATS_TEST_TMPDIR/loa.config.yaml"
    unset LOA_HEADLESS_MODE
}

_cfg() {  # <tertiary> [agy_opt_in value|absent] [headless mode]
    {
        printf 'hounfour:\n  headless:\n'
        printf '    mode: %s\n' "${3:-prefer-api}"
        [[ "${2:-absent}" == absent ]] || printf '    agy_opt_in: %s\n' "$2"
        printf 'flatline_protocol:\n  models:\n    primary: opus\n    secondary: gpt-5.5\n    tertiary: %s\n' "$1"
    } > "$CONFIG_FILE"
}

@test "FTA-1 an agy tertiary with the opt-in absent, false or a string is not planned; the reason names the key" {
    local opt t
    for t in gemini-headless google:gemini-headless; do
        for opt in absent false '"true"'; do
            _cfg "$t" "$opt"
            [ "$(get_model_tertiary)" = "" ] || { echo "t=$t opt=$opt planned"; return 1; }
            [ "$(get_tertiary_status)" = "disabled_by_opt_in" ]
            run tertiary_opt_in_skip_reason
            [ "$status" -eq 0 ]
            [[ "$output" == *"$t"*"disabled by opt-in"*"hounfour.headless.agy_opt_in"* ]] || { echo "$output"; return 1; }
        done
    done
}

@test "FTA-2 under hounfour.headless.mode cli-only a Google tertiary is agy-routed and gated too; under prefer-api it is planned" {
    _cfg gemini-3.1-pro absent cli-only
    [ "$(get_model_tertiary)" = "" ]
    [ "$(get_tertiary_status)" = "disabled_by_opt_in" ]
    _cfg gemini-3.1-pro absent prefer-api
    _CACHED_TERTIARY_MODEL_SET=false
    export GOOGLE_API_KEY="fixture-not-a-key"   # (hygiene: a prefer-api Google tertiary is an HTTP voice — it has a key)
    [ "$(get_model_tertiary)" = "gemini-3.1-pro" ]
    [ "$(get_tertiary_status)" = "active" ]
    run tertiary_opt_in_skip_reason
    [ "$status" -eq 1 ]
}

@test "FTA-3 with the opt-in true an agy tertiary is planned as before" {
    _cfg gemini-headless true
    [ "$(get_model_tertiary)" = "gemini-headless" ]
    [ "$(get_tertiary_status)" = "active" ]
    run tertiary_opt_in_skip_reason
    [ "$status" -eq 1 ]
}

@test "FTA-4 a non-agy tertiary and an unset tertiary are unchanged by the gate" {
    _cfg claude-headless
    [ "$(get_model_tertiary)" = "claude-headless" ]
    [ "$(get_tertiary_status)" = "active" ]
    printf 'flatline_protocol:\n  models:\n    primary: opus\n' > "$CONFIG_FILE"
    [ "$(get_model_tertiary)" = "" ]
    [ "$(get_tertiary_status)" = "disabled" ]
}

@test "FTA-5 Phase 1 with a gated agy tertiary runs 2-model: no tertiary dispatch, the skip is logged, not a dropped voice" {
    _cfg gemini-headless
    TEMP_DIR="$BATS_TEST_TMPDIR/tmp"; mkdir -p "$TEMP_DIR"
    CALLS="$BATS_TEST_TMPDIR/calls"; : > "$CALLS"
    set_state() { :; }; log_trajectory() { :; }
    call_model() { echo "$1 $2" >> "$CALLS"; printf '{"content":"{\\"improvements\\":[]}","cost_usd":0}\n'; }
    log() { echo "$*" >&2; }
    printf '# doc\n' > "$BATS_TEST_TMPDIR/doc.md"
    run --separate-stderr run_phase1 "$BATS_TEST_TMPDIR/doc.md" prd "" 30 100
    # (review r251-1 G13: Phase 1 succeeded and wrote its four artefacts; no tertiary artefact)
    [ "$status" -eq 0 ] || { echo "run_phase1 rc=$status"; echo "$stderr" | tail -20; return 1; }
    local f
    for f in gpt-review opus-review gpt-skeptic opus-skeptic; do [ -s "$TEMP_DIR/$f.json" ] || { echo "missing $f.json"; ls "$TEMP_DIR"; return 1; }; done
    [ ! -e "$TEMP_DIR/tertiary-review.json" ] && [ ! -e "$TEMP_DIR/tertiary-skeptic.json" ]
    ! grep -q gemini-headless "$CALLS" || { echo "unexpected: grep -q gemini-headless '$CALLS'"; return 1; }
    [ "$(grep -c '' "$CALLS")" = "4" ]
    [[ "$stderr" == *"disabled by opt-in"*"hounfour.headless.agy_opt_in"* ]] || { echo "$stderr"; return 1; }
    [[ "$stderr" != *"Voice dropped"* ]]
}
