#!/usr/bin/env bats
# =============================================================================
# flatline-locality.bats — cycle-129 Sprint 3 Task 3.5 (PRD FR-8 AC-8.1, SDD D-8.1, DEC-0146).
#
# Under hounfour.locality: local_voices, flatline-orchestrator.sh plans its voices — and so its scorers, which are the
# same voices cross-scoring — only on providers whose model entry says dispatch_group: local; each hosted voice is
# refused by name at plan time (a hosted primary or secondary refuses the run, a hosted tertiary is not planned), the
# advisor_strategy scorer route is refused, red-team mode is refused, and the default (hosted) is unchanged.
# No model is called: call_model is a stub where a phase runs.
# =============================================================================

bats_require_minimum_version 1.5.0

setup() {
    umask 022
    REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    source "$REPO/.claude/scripts/flatline-orchestrator.sh"
    CONFIG_FILE="$BATS_TEST_TMPDIR/loa.config.yaml"
    unset LOA_HEADLESS_MODE LOA_MODEL_CONFIG
}

_cfg() {  # <locality | absent> <primary> <secondary> [tertiary] [extra top-level yaml]
    {
        printf 'hounfour:\n'
        [[ "$1" == absent ]] || printf '  locality: %s\n' "$1"
        printf '  providers:\n    localbox:\n      type: openai_compat\n      endpoint: "http://127.0.0.1:8000/v1"\n      models:\n'
        printf '        qwen-local:\n          dispatch_group: local\n        qwen-local-b:\n          dispatch_group: local\n'
        printf '  aliases:\n    lq: "localbox:qwen-local"\n    lqb: "localbox:qwen-local-b"\n'
        printf 'flatline_protocol:\n  enabled: true\n  models:\n    primary: %s\n    secondary: %s\n' "$2" "$3"
        [[ -z "${4:-}" ]] || printf '    tertiary: %s\n' "$4"
        [[ -z "${5:-}" ]] || printf '%s\n' "$5"
    } > "$CONFIG_FILE"
    _FLATLINE_LOCALITY_RESULT=""; _CACHED_TERTIARY_MODEL_SET=false; _CACHED_STAGE_ROUTING_SCORER_SET=false
}

@test "FLL-1 hosted primary and secondary voices are refused by name; the run is refused" {
    _cfg local_voices opus gpt-5.5
    run --separate-stderr flatline_locality_gate
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"locality: local_voices refuses hosted hop opus (anthropic)"* ]] || { echo "$stderr"; return 1; }
    [[ "$stderr" == *"locality: local_voices refuses hosted hop gpt-5.5 (openai)"* ]]
    [[ "$stderr" == *"refuses a hosted Flatline primary or secondary voice — nothing was dispatched"* ]]
    # one hosted voice is enough to refuse
    _cfg local_voices lq gpt-5.5
    run --separate-stderr flatline_locality_gate
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"refuses hosted hop gpt-5.5 (openai)"* ]]
    [[ "$stderr" != *"refuses hosted hop lq "* ]]
}

@test "FLL-2 local primary and secondary are planned; a hosted tertiary is refused by name and not planned (2-model)" {
    _cfg local_voices lq lqb gemini-2.5-pro
    flatline_locality_gate 2> "$BATS_TEST_TMPDIR/err"
    grep -qF "locality: local_voices refuses hosted hop gemini-2.5-pro (google)" "$BATS_TEST_TMPDIR/err"
    [ "$(get_model_tertiary)" = "" ]
    ! grep -q "refuses hosted hop lq" "$BATS_TEST_TMPDIR/err" || { echo "a local voice was refused"; return 1; }
}

@test "FLL-3 Phase 1 under local_voices dispatches only the local voices (no tertiary); the skeptic and review calls stay on them" {
    _cfg local_voices lq lqb gemini-2.5-pro
    TEMP_DIR="$BATS_TEST_TMPDIR/tmp"; mkdir -p "$TEMP_DIR"
    CALLS="$BATS_TEST_TMPDIR/calls"; : > "$CALLS"
    set_state() { :; }; log_trajectory() { :; }
    validate_model() { return 0; }   # (name validation reads the repository config; not under test here)
    call_model() { echo "$1 $2" >> "$CALLS"; printf '{"content":"{\\"improvements\\":[]}","cost_usd":0}\n'; }
    log() { echo "$*" >&2; }
    printf '# doc\n' > "$BATS_TEST_TMPDIR/doc.md"
    run --separate-stderr run_phase1 "$BATS_TEST_TMPDIR/doc.md" prd "" 30 100
    [ "$status" -eq 0 ] || { echo "$stderr" | tail -20; return 1; }
    [ "$(cut -d' ' -f1 "$CALLS" | sort -u | tr '\n' ' ')" = "lq lqb " ]
    [ "$(grep -c '' "$CALLS")" = "4" ]
    [[ "$stderr" == *"refuses hosted hop gemini-2.5-pro (google)"* ]]
}

@test "FLL-4 the advisor_strategy scorer route is refused under local_voices; the scorers stay on the pinned local voices" {
    _cfg local_voices lq lqb "" "advisor_strategy:
  stage_routing:
    flatline_scorer: true"
    is_stage_routing_scorer_enabled
    _CACHED_STAGE_ROUTING_SCORER_SET=false
    flatline_locality_gate 2> "$BATS_TEST_TMPDIR/err"
    grep -qF "locality: local_voices refuses the advisor_strategy scorer route" "$BATS_TEST_TMPDIR/err"
    ! is_stage_routing_scorer_enabled || { echo "the scorer route stayed on"; return 1; }
}

@test "FLL-5 the default (no key) and hounfour.locality: hosted are unchanged: hosted voices planned, nothing refused" {
    local v
    for v in absent hosted; do
        _cfg "$v" opus gpt-5.5 gemini-2.5-pro
        run --separate-stderr flatline_locality_gate
        [ "$status" -eq 0 ]
        [[ "$stderr" != *"locality"* ]] || { echo "$stderr"; return 1; }
        export GOOGLE_API_KEY="fixture-not-a-key"
        [ "$(get_model_tertiary)" = "gemini-2.5-pro" ]
    done
}

@test "FLL-6 an unknown locality value is refused by name" {
    _cfg local opus gpt-5.5
    run --separate-stderr flatline_locality_gate
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"hounfour.locality='local' is neither hosted nor local_voices"* ]]
}

@test "FLL-7 main refuses at plan time, before any dispatch (dry run too), and refuses red-team mode under local_voices" {
    _cfg local_voices opus gpt-5.5
    local doc="$REPO/grimoires/loa/prd.md"
    [ -f "$doc" ] || skip "no prd.md in this checkout"
    run --separate-stderr bash -c 'source "$1/.claude/scripts/flatline-orchestrator.sh"; CONFIG_FILE="$2"; main --doc "$3" --phase prd --dry-run --json' _ "$REPO" "$CONFIG_FILE" "$doc"
    [ "$status" -eq 1 ]
    [ "$(jq -r '.status' <<<"$output")" = "locality_refused" ]
    [[ "$stderr" == *"refuses hosted hop opus (anthropic)"* ]]
    _cfg local_voices lq lqb
    run --separate-stderr bash -c 'source "$1/.claude/scripts/flatline-orchestrator.sh"; CONFIG_FILE="$2"; main --doc "$3" --phase prd --mode red-team --dry-run --json' _ "$REPO" "$CONFIG_FILE" "$doc"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"does not cover the red-team pipeline"* ]]
    # the local plan passes the gate and reaches the dry run
    run --separate-stderr bash -c 'source "$1/.claude/scripts/flatline-orchestrator.sh"; CONFIG_FILE="$2"; main --doc "$3" --phase prd --dry-run --json' _ "$REPO" "$CONFIG_FILE" "$doc"
    [ "$status" -eq 0 ] || { echo "$stderr" | tail; return 1; }
    [ "$(jq -r '.status' <<<"$output")" = "dry_run" ]
}
