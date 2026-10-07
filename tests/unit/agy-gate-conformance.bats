#!/usr/bin/env bats
# =============================================================================
# agy-gate-conformance.bats — cycle-127 review r251-1 G2 (SDD D-1.5: ONE predicate).
# The agy route rule lives in .claude/scripts/lib/agy-gate-lib.sh (agy_opted_in, routes_to_agy, agy_route_planned)
# and its Python twin loa_cheval.config.loader (agy_opt_in_enabled, routes_to_agy). Every reader — the dissent
# companion planner, the Flatline tertiary, /loa Providers, run-preflight P3 (run-preflight.bats PF-AGY-2) and cheval —
# sources it and keeps no private copy; fed `hounfour.headless.mode: cli-only` and a `gemini-2.5-pro` voice with the
# opt-in off, every reader says not planned / opt_in_required. No model is called; nothing spawns agy.
# =============================================================================

bats_require_minimum_version 1.5.0

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    LIB="$REPO/.claude/scripts/lib/agy-gate-lib.sh"
    CFG="$BATS_TEST_TMPDIR/loa.config.yaml"
    unset LOA_HEADLESS_MODE
}

_cfg() {  # <mode> [agy_opt_in value|absent]
    {
        printf 'hounfour:\n  headless:\n    mode: %s\n' "$1"
        [[ "${2:-absent}" == absent ]] || printf '    agy_opt_in: %s\n' "$2"
    } > "$CFG"
}

@test "AGC-1 the lib: agy_opted_in is a YAML boolean only; agy_headless_mode lets env win; routes_to_agy follows the shared table" {
    source "$LIB"
    local v
    for v in absent false '"true"' 1 yes; do _cfg prefer-api "$v"; ! agy_opted_in "$CFG" || { echo "opted in on $v"; return 1; }; done
    _cfg prefer-api true; agy_opted_in "$CFG" || { echo "boolean true read off"; return 1; }
    ! agy_opted_in "$BATS_TEST_TMPDIR/missing.yaml" || { echo "a missing config opted in"; return 1; }
    _cfg cli-only; [ "$(agy_headless_mode "$CFG")" = "cli-only" ]
    LOA_HEADLESS_MODE=prefer-cli; [ "$(agy_headless_mode "$CFG")" = "prefer-cli" ]; unset LOA_HEADLESS_MODE
    printf 'hounfour: {}\n' > "$CFG"; [ "$(agy_headless_mode "$CFG")" = "prefer-api" ]
    [ "$(agy_headless_mode "$BATS_TEST_TMPDIR/missing.yaml")" = "prefer-api" ]
    # the table the Python twin is held to (test_agy_opt_in_gate.py::test_routes_to_agy_matches_the_bash_rule)
    while read -r m mode want; do
        [[ "$mode" == - ]] && mode=""
        if routes_to_agy "$m" "$mode"; then got=True; else got=False; fi
        [ "$got" = "$want" ] || { echo "routes_to_agy $m ${mode:-<default>} → $got, want $want"; return 1; }
    done <<'TABLE'
gemini-headless - True
google:gemini-headless - True
gemini-headless:any - True
gemini-headless prefer-api True
gemini-2.5-pro prefer-api False
gemini-2.5-pro - False
gemini-2.5-pro cli-only True
google:gemini-3.1-pro cli-only True
gemini-2.5-pro prefer-cli False
claude-headless cli-only False
gpt-5.5 cli-only False
TABLE
}

@test "AGC-2 the bash predicate and the Python twin agree on every row" {
    source "$LIB"
    local rows m mode b p
    rows=$'gemini-headless prefer-api\ngoogle:gemini-headless cli-only\ngemini-2.5-pro cli-only\ngemini-2.5-pro prefer-cli\ngemini-2.5-pro prefer-api\ngoogle:gemini-3.1-pro cli-only\nclaude-headless cli-only\ncodex-headless prefer-cli\ngpt-5.5 cli-only'
    while read -r m mode; do
        if routes_to_agy "$m" "$mode"; then b=True; else b=False; fi
        p=$(cd "$REPO/.claude/adapters" && python3 -I -c 'import sys; sys.path.insert(0, "."); from loa_cheval.config.loader import routes_to_agy; print(routes_to_agy(sys.argv[1], sys.argv[2]))' "$m" "$mode")
        [ "$b" = "$p" ] || { echo "$m $mode: bash $b python $p"; return 1; }
    done <<<"$rows"
}

@test "AGC-3 every bash reader sources the one lib and keeps no private opt-in expression or agy model test" {
    local f
    for f in adversarial-review.sh flatline-orchestrator.sh run-preflight.sh loa-status.sh; do
        grep -q 'lib/agy-gate-lib.sh' "$REPO/.claude/scripts/$f" || { echo "$f does not source agy-gate-lib.sh"; return 1; }
        ! grep -q 'agy_opt_in | (tag' "$REPO/.claude/scripts/$f" || { echo "$f keeps its own yq opt-in read"; return 1; }
        ! grep -q '== *"gemini-headless"' "$REPO/.claude/scripts/$f" || { echo "$f keeps its own gemini-headless test"; return 1; }
    done
}

@test "AGC-4 cli-only + a gemini-2.5-pro voice + opt-in off: the Flatline tertiary is disabled_by_opt_in" {
    source "$REPO/.claude/scripts/flatline-orchestrator.sh"
    CONFIG_FILE="$CFG"
    _cfg cli-only
    printf 'flatline_protocol:\n  models:\n    tertiary: gemini-2.5-pro\n' >> "$CFG"
    [ "$(get_model_tertiary)" = "" ]
    [ "$(get_tertiary_status)" = "disabled_by_opt_in" ]
    _CACHED_TERTIARY_MODEL_SET=false
    _cfg cli-only true; printf 'flatline_protocol:\n  models:\n    tertiary: gemini-2.5-pro\n' >> "$CFG"
    [ "$(get_model_tertiary)" = "gemini-2.5-pro" ]
}

@test "AGC-5 cli-only + a gemini-2.5-pro companion hop + opt-in off: the dissent planner drops it (opt_in_required); prefer-api keeps it" {
    PROJECT_ROOT="$REPO"
    source "$REPO/.claude/scripts/adversarial-review.sh"
    CONFIG_FILE="$CFG"
    log() { echo "$*" >&2; }
    _cfg cli-only
    run --separate-stderr _adv_agy_filter_chain code_review anthropic gemini-2.5-pro claude-headless
    [ "$output" = "claude-headless" ] || { echo "out=$output"; return 1; }
    [[ "$stderr" == *"gemini-2.5-pro not planned"*"hounfour.headless.agy_opt_in"* ]] || { echo "$stderr"; return 1; }
    run --separate-stderr _adv_agy_filter_chain code_review anthropic gemini-2.5-pro
    [ "$output" = "" ]
    _cfg prefer-api
    run --separate-stderr _adv_agy_filter_chain code_review anthropic gemini-2.5-pro claude-headless
    [ "$output" = "gemini-2.5-pro claude-headless" ]
    _cfg cli-only true
    run --separate-stderr _adv_agy_filter_chain code_review anthropic gemini-2.5-pro claude-headless
    [ "$output" = "gemini-2.5-pro claude-headless" ]
}

@test "AGC-6 /loa Providers: under cli-only with the opt-in off the google hop is the opt-in note, never a usable agy hop" {
    T="$BATS_TEST_TMPDIR/lsp"; mkdir -p "$T/run" "$T/env" "$T/bin"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$T/bin/agy"; chmod +x "$T/bin/agy"
    _cfg cli-only
    run --separate-stderr env LOA_STATUS_RUN_DIR="$T/run" LOA_STATUS_ENV_DIR="$T/env" LOA_STATUS_CONFIG_FILE="$CFG" PATH="$T/bin:$PATH" \
        timeout 120 bash "$REPO/.claude/scripts/loa-status.sh" --no-stale-check --json
    echo "$output" | jq -e '.providers.providers.google.cli_hop == null and .providers.providers.google.cli_hop_note == "agy: opt-in (disabled; hounfour.headless.agy_opt_in)"' >/dev/null || { echo "$output" | tail -5; return 1; }
}

# --- review r251-1 G12/G18, r251-2 K1 ---------------------------------------------------------------------------------
# The configs — absent, boolean true, the string "true", and the YAML 1.1 truthy spellings PyYAML used to accept (yes, on,
# True, TRUE) plus 1 — fed to the lib, the four bash readers and the Python predicate. ONE strict rule: only the scalar
# written exactly `true` opts in; every other present value is off everywhere and every reader says so once, naming the
# key and the accepted spelling.

_three() {  # <which> → writes $CFG with mode cli-only and the opt-in absent | true | "true" | <literal spelling>
    case "$1" in absent) _cfg cli-only ;; bool) _cfg cli-only true ;; string) _cfg cli-only '"true"' ;; *) _cfg cli-only "$1" ;; esac
}

@test "AGC-7 lib + Python: only the scalar written exactly true opts in; \"true\" / yes / on / True / TRUE / 1 read off with one WARN naming the key and the accepted spelling" {
    source "$LIB"
    local w py pyerr
    for w in absent bool string yes on True TRUE 1; do
        _three "$w"
        _LOA_AGY_GATE_WARNED=""
        run --separate-stderr bash -c 'source "$1"; agy_gate_warn_once "$2"; agy_gate_warn_once "$2"; agy_opted_in "$2" && echo on || echo off' _ "$LIB" "$CFG"
        cp -- "$CFG" "$BATS_TEST_TMPDIR/.loa.config.yaml"   # (the Python reader takes a project root and its .loa.config.yaml)
        py=$(cd "$BATS_TEST_TMPDIR" && python3 -I -c 'import sys; sys.path.insert(0, sys.argv[1]); from loa_cheval.config.loader import agy_opt_in_enabled; agy_opt_in_enabled(sys.argv[2]); print("on" if agy_opt_in_enabled(sys.argv[2]) else "off")' "$REPO/.claude/adapters" "$BATS_TEST_TMPDIR" 2>"$BATS_TEST_TMPDIR/py.err")
        pyerr=$(cat "$BATS_TEST_TMPDIR/py.err")
        if [[ "$w" == bool ]]; then
            [ "$output" = on ] && [ "$py" = on ] || { echo "$w: bash=$output py=$py"; return 1; }
        else
            [ "$output" = off ] && [ "$py" = off ] || { echo "$w: bash=$output py=$py"; return 1; }
        fi
        if [[ "$w" == absent || "$w" == bool ]]; then
            ! grep -q 'agy_opt_in: true' <<<"$stderr" || { echo "$w bash warned: $stderr"; return 1; }
            ! grep -q 'agy_opt_in: true' <<<"$pyerr" || { echo "$w python warned: $pyerr"; return 1; }
        else
            [ "$(grep -c 'hounfour.headless.agy_opt_in.*only `agy_opt_in: true` opts in' <<<"$stderr")" = 1 ] || { echo "$w bash stderr=$stderr"; return 1; }
            [ "$(grep -c 'hounfour.headless.agy_opt_in.*only `agy_opt_in: true` opts in' <<<"$pyerr")" = 1 ] || { echo "$w python stderr=$pyerr"; return 1; }
        fi
        if [[ "$w" == string ]]; then
            grep -q 'hounfour.headless.agy_opt_in.*not a YAML boolean' <<<"$stderr" || { echo "stderr=$stderr"; return 1; }
        fi
    done
}

@test "AGC-8 every bash reader: the string \"true\" is off and warns once; boolean true is on; absent is off and silent" {
    PROJECT_ROOT="$REPO"
    local w out err
    for w in absent bool string; do
        _three "$w"
        printf 'flatline_protocol:\n  models:\n    tertiary: gemini-headless\n' >> "$CFG"
        # Flatline: the status the planner reports + its stderr from a top-level planning call
        run --separate-stderr bash -c 'source "$1/.claude/scripts/flatline-orchestrator.sh"; CONFIG_FILE="$2"; agy_gate_warn_once "$CONFIG_FILE"; get_tertiary_status' _ "$REPO" "$CFG"
        case "$w" in bool) [ "$output" = active ] ;; *) [ "$output" = disabled_by_opt_in ] || { echo "flatline $w → $output"; return 1; } ;; esac
        [ "$(grep -c 'not a YAML boolean' <<<"$stderr")" = "$([[ $w == string ]] && echo 1 || echo 0)" ] || { echo "flatline $w stderr=$stderr"; return 1; }
        # dissent planner
        run --separate-stderr bash -c 'PROJECT_ROOT="$1"; source "$1/.claude/scripts/adversarial-review.sh"; CONFIG_FILE="$2"; log() { echo "$*" >&2; }; agy_gate_warn_once "$CONFIG_FILE"; _adv_agy_filter_chain code_review anthropic gemini-headless claude-headless' _ "$REPO" "$CFG"
        case "$w" in bool) [ "$output" = "gemini-headless claude-headless" ] ;; *) [ "$output" = "claude-headless" ] || { echo "dissent $w → $output"; return 1; } ;; esac
        [ "$(grep -c 'not a YAML boolean' <<<"$stderr")" = "$([[ $w == string ]] && echo 1 || echo 0)" ] || { echo "dissent $w stderr=$stderr"; return 1; }
        # /loa Providers
        T="$BATS_TEST_TMPDIR/lsp-$w"; mkdir -p "$T/run" "$T/env"
        run --separate-stderr env LOA_STATUS_RUN_DIR="$T/run" LOA_STATUS_ENV_DIR="$T/env" LOA_STATUS_CONFIG_FILE="$CFG" \
            timeout 120 bash "$REPO/.claude/scripts/loa-status.sh" --no-stale-check --json
        if [[ "$w" == bool ]]; then
            jq -e '.providers.providers.google | has("cli_hop_note") | not' >/dev/null <<<"$output" || { echo "loa-status bool"; return 1; }
        else
            jq -e '.providers.providers.google.cli_hop_note == "agy: opt-in (disabled; hounfour.headless.agy_opt_in)"' >/dev/null <<<"$output" || { echo "loa-status $w"; return 1; }
        fi
        # (--json keeps stderr quiet for callers that merge the streams; the human Providers block says it once)
        ! grep -Eq 'not a YAML boolean|agy route is available here|agy_opt_in: true' <<<"$stderr" || { echo "loa-status --json $w warned: $stderr"; return 1; }
        run --separate-stderr env LOA_STATUS_RUN_DIR="$T/run" LOA_STATUS_ENV_DIR="$T/env" LOA_STATUS_CONFIG_FILE="$CFG" \
            timeout 120 bash "$REPO/.claude/scripts/loa-status.sh" --no-stale-check
        [ "$(grep -c 'not a YAML boolean' <<<"$stderr")" = "$([[ $w == string ]] && echo 1 || echo 0)" ] || { echo "loa-status $w stderr=$stderr"; return 1; }
    done
}

@test "AGC-9 (SDD D-1.7) the opt-in off + agy on PATH or a Gemini key → ONE availability WARN per shell, nothing spawned; opt-in on or nothing available → silent" {
    local bin="$BATS_TEST_TMPDIR/bin" marker="$BATS_TEST_TMPDIR/spawned"
    local rp="/usr/bin:/bin:$(dirname "$(command -v yq)")"   # ONE restricted PATH for the guards and the runs (K6)
    local agy_elsewhere=""; PATH="$rp" command -v agy >/dev/null 2>&1 && agy_elsewhere=1
    mkdir -p "$bin"; printf '#!/bin/sh\necho spawned > %s\n' "$marker" > "$bin/agy"; chmod +x "$bin/agy"
    _cfg prefer-api
    run --separate-stderr env -u GOOGLE_API_KEY -u GEMINI_API_KEY PATH="$bin:$rp" \
        bash -c 'source "$1"; agy_gate_warn_once "$2"; agy_gate_warn_once "$2"; ( agy_gate_warn_once "$2" ); true' _ "$LIB" "$CFG"
    [ "$(grep -c 'agy route is available here' <<<"$stderr")" = 1 ] || { echo "stderr=$stderr"; return 1; }
    grep 'agy route is available here' <<<"$stderr" | grep -q 'agy on PATH.*hounfour.headless.agy_opt_in.*argv' || { echo "stderr=$stderr"; return 1; }
    [ ! -e "$marker" ] || { echo "agy was spawned"; return 1; }
    run --separate-stderr env GEMINI_API_KEY=fixture PATH="$rp" bash -c 'source "$1"; agy_gate_warn_once "$2"' _ "$LIB" "$CFG"
    if [[ -z "$agy_elsewhere" ]]; then
        grep -q 'agy route is available here (a Google/Gemini key is set)' <<<"$stderr" || { echo "stderr=$stderr"; return 1; }
    else
        grep -q 'agy route is available here (.*a Google/Gemini key is set)' <<<"$stderr" || { echo "stderr=$stderr"; return 1; }
    fi
    _cfg prefer-api true
    run --separate-stderr env GEMINI_API_KEY=fixture PATH="$bin:$rp" bash -c 'source "$1"; agy_gate_warn_once "$2"' _ "$LIB" "$CFG"
    [ -z "$stderr" ] || { echo "opt-in on warned: $stderr"; return 1; }
    _cfg prefer-api
    if [[ -z "$agy_elsewhere" ]]; then
        run --separate-stderr env -u GOOGLE_API_KEY -u GEMINI_API_KEY PATH="$rp" bash -c 'source "$1"; agy_gate_warn_once "$2"' _ "$LIB" "$CFG"
        [ -z "$stderr" ] || { echo "nothing available warned: $stderr"; return 1; }
    fi
    [ ! -e "$marker" ] || { echo "agy was spawned"; return 1; }
}

@test "AGC-10 each bash reader calls the once-per-shell WARN from a top-level planning point" {
    local f
    for f in adversarial-review.sh flatline-orchestrator.sh run-preflight.sh loa-status.sh; do
        grep -q 'agy_gate_warn_once' "$REPO/.claude/scripts/$f" || { echo "$f never calls agy_gate_warn_once"; return 1; }
    done
}

# --- review r251-2 K5: the python-yq fallback is chosen by flavour, never by output shape ------------------------------

_fake_yq() {  # <version line> <reply to every other call> → a yq shim on $BATS_TEST_TMPDIR/fyq
    mkdir -p "$BATS_TEST_TMPDIR/fyq"
    cat > "$BATS_TEST_TMPDIR/fyq/yq" <<SHIM
#!/usr/bin/env bash
[[ "\$1" == --version ]] && { echo '$1'; exit 0; }
case "\$*" in *'tag'*) exit 1 ;; esac
echo '$2'
SHIM
    chmod +x "$BATS_TEST_TMPDIR/fyq/yq"
}

@test "AGC-11 (K5) a mikefarah yq whose typed read fails never falls through to the untyped == true form" {
    _fake_yq 'yq (https://github.com/mikefarah/yq/) version v4.44.1' true
    _cfg prefer-api '"true"'
    run env PATH="$BATS_TEST_TMPDIR/fyq:$PATH" bash -c 'source "$1"; agy_opted_in "$2" && echo on || echo off' _ "$LIB" "$CFG"
    [ "$output" = off ] || { echo "a mikefarah yq ran the untyped form: $output"; return 1; }
}

@test "AGC-12 (K1/K5) under a python yq the lib applies the same strict rule (yes / True / \"true\" off, true on)" {
    python3 -c 'import yaml' 2>/dev/null || skip "PyYAML not installed"
    _fake_yq 'yq 3.4.3' true
    local w want
    for w in true yes True '"true"' on; do
        _cfg prefer-api "$w"; want=off; [[ "$w" == true ]] && want=on
        run env PATH="$BATS_TEST_TMPDIR/fyq:$PATH" bash -c 'source "$1"; agy_opted_in "$2" && echo on || echo off' _ "$LIB" "$CFG"
        [ "$output" = "$want" ] || { echo "python-yq $w → $output, want $want"; return 1; }
    done
}
