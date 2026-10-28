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
    # (r251-4: the suite sources adversarial-review.sh — its CLI lock resolves under this suite's own runtime dir, never
    # the per-user one a live dissent holds; adversarial-review-companion.bats CMP-121)
    mkdir -p "$BATS_TEST_TMPDIR/xdg"; chmod 700 "$BATS_TEST_TMPDIR/xdg"
    export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/xdg"
    # (r251-5 U1/U2: every reader refuses a group- or world-writable config, so the fixtures are written owner-only —
    # under a host umask of 002 a `>` redirect makes 0664; AGC-19/20 set the modes they test explicitly)
    umask 022
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
deep-research-pro cli-only True
google:deep-research-pro cli-only True
researcher cli-only True
deep-research-pro prefer-api False
deep-research-pro prefer-cli False
opus cli-only False
claude-opus-5-5 cli-only False
anthropic:claude-opus-5-5 cli-only False
TABLE
}

@test "AGC-2 the bash predicate and the Python twin agree on every row" {
    source "$LIB"
    local rows m mode b p
    rows=$'gemini-headless prefer-api\ngoogle:gemini-headless cli-only\ngemini-2.5-pro cli-only\ngemini-2.5-pro prefer-cli\ngemini-2.5-pro prefer-api\ngoogle:gemini-3.1-pro cli-only\nclaude-headless cli-only\ncodex-headless prefer-cli\ngpt-5.5 cli-only\ndeep-research-pro cli-only\ngoogle:deep-research-pro cli-only\nresearcher cli-only\ndeep-research-pro prefer-api\nopus cli-only\nclaude-opus-5-5 cli-only'
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
    local t0=$SECONDS
    # (r251-5 U4, audit LOW-004: the batch flake was workflow-state.sh's cache MISS — cache-manager's "v Cached result"
    # line led its --json stdout and loa-status's jq merge exited 5. A fresh CACHE_DIR makes this call the miss every time,
    # and keeps the suite out of the checkout's .claude/cache)
    run --separate-stderr env CACHE_DIR="$T/wscache" LOA_STATUS_RUN_DIR="$T/run" LOA_STATUS_ENV_DIR="$T/env" LOA_STATUS_CONFIG_FILE="$CFG" PATH="$T/bin:$PATH" \
        timeout 180 bash "$REPO/.claude/scripts/loa-status.sh" --no-stale-check --json
    # (r251-4 S9, review round-2 Obs 2: on failure say WHICH failure — a `timeout 180` expiry (status 124, elapsed ≈ 180 s)
    # is not a gate mismatch (status 0 and a google block that disagrees))
    echo "$output" | jq -e '.providers.providers.google.cli_hop == null and .providers.providers.google.cli_hop_note == "agy: opt-in (disabled; hounfour.headless.agy_opt_in)"' >/dev/null || {
        echo "status=$status elapsed=$(( SECONDS - t0 ))s ($([[ $status == 124 ]] && echo 'timeout 180 expired' || echo 'gate mismatch or loa-status failure'))"
        echo "--- stderr (full)"; printf '%s\n' "$stderr"
        echo "--- google block"; jq -c '.providers.providers.google' <<<"$output" 2>/dev/null || echo "(not JSON)"
        echo "--- stdout (last 20 lines)"; printf '%s\n' "$output" | tail -20
        return 1
    }
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
        run --separate-stderr env CACHE_DIR="$T/wscache" LOA_STATUS_RUN_DIR="$T/run" LOA_STATUS_ENV_DIR="$T/env" LOA_STATUS_CONFIG_FILE="$CFG" \
            timeout 120 bash "$REPO/.claude/scripts/loa-status.sh" --no-stale-check --json
        if [[ "$w" == bool ]]; then
            jq -e '.providers.providers.google | has("cli_hop_note") | not' >/dev/null <<<"$output" || { echo "loa-status bool"; return 1; }
        else
            jq -e '.providers.providers.google.cli_hop_note == "agy: opt-in (disabled; hounfour.headless.agy_opt_in)"' >/dev/null <<<"$output" || { echo "loa-status $w"; return 1; }
        fi
        # (--json keeps stderr quiet for callers that merge the streams; the human Providers block says it once)
        ! grep -Eq 'not a YAML boolean|agy route is available here|agy_opt_in: true' <<<"$stderr" || { echo "loa-status --json $w warned: $stderr"; return 1; }
        run --separate-stderr env CACHE_DIR="$T/wscache" LOA_STATUS_RUN_DIR="$T/run" LOA_STATUS_ENV_DIR="$T/env" LOA_STATUS_CONFIG_FILE="$CFG" \
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

# --- review r251-4 (the audit dissent) ---------------------------------------------------------------------------------

_shape() {  # <label> → writes $CFG with one of the r251-4 S3 shapes
    case "$1" in
        foreign_tag) printf 'hounfour:\n  headless:\n    agy_opt_in: !<x:bool> true\n' ;;
        local_tag)   printf 'hounfour:\n  headless:\n    agy_opt_in: !bool true\n' ;;
        alias)       printf 'x: &t true\nhounfour:\n  headless:\n    agy_opt_in: *t\n' ;;
        merge_key)   printf 'b: &b\n  agy_opt_in: true\nhounfour:\n  headless:\n    <<: *b\n' ;;
        alias_map)   printf 'h: &h\n  agy_opt_in: true\nhounfour:\n  headless: *h\n' ;;
        full_tag)    printf 'hounfour:\n  headless:\n    agy_opt_in: !<tag:yaml.org,2002:bool> true\n' ;;
        anchored)    printf 'hounfour:\n  headless:\n    agy_opt_in: &a true\n' ;;
    esac > "$CFG"
}

@test "AGC-13 (r251-4 S3) the exact bool tag, an alias and a merge key: the go-yq lib, the python-yq lib and Python agree (only full_tag / anchored opt in)" {
    python3 -c 'import yaml' 2>/dev/null || skip "PyYAML not installed"
    _fake_yq 'yq 3.4.3' true   # (the python-yq flavour shim: the lib takes its PyYAML node path)
    local w want go pyq py
    for w in foreign_tag local_tag alias merge_key alias_map full_tag anchored; do
        _shape "$w"; want=off; [[ "$w" == full_tag || "$w" == anchored ]] && want=on
        go=$(bash -c 'source "$1"; agy_opted_in "$2" && echo on || echo off' _ "$LIB" "$CFG")
        pyq=$(env PATH="$BATS_TEST_TMPDIR/fyq:$PATH" bash -c 'source "$1"; agy_opted_in "$2" && echo on || echo off' _ "$LIB" "$CFG")
        cp -- "$CFG" "$BATS_TEST_TMPDIR/.loa.config.yaml"
        py=$(python3 -I -c 'import sys; sys.path.insert(0, sys.argv[1]); from loa_cheval.config.loader import agy_opt_in_enabled; print("on" if agy_opt_in_enabled(sys.argv[2]) else "off")' "$REPO/.claude/adapters" "$BATS_TEST_TMPDIR" 2>/dev/null)
        [ "$go" = "$want" ] && [ "$pyq" = "$want" ] && [ "$py" = "$want" ] || { echo "$w: go-yq=$go python-yq=$pyq python=$py want=$want"; return 1; }
    done
}

@test "AGC-14 (r251-4 S4) an exported include-guard variable never skips loading the lib, and an exported said-once flag never silences the WARN" {
    _cfg cli-only '"true"'
    run --separate-stderr env _LOA_AGY_GATE_LIB_LOADED=1 _LOA_AGY_GATE_WARNED=1 \
        bash -c 'source "$1"; declare -F routes_to_agy agy_opted_in agy_route_planned >/dev/null || exit 9; agy_gate_warn_once "$2"; routes_to_agy gemini-2.5-pro cli-only && echo routed' _ "$LIB" "$CFG"
    [ "$status" -eq 0 ] || { echo "status=$status (9 = lib skipped) stderr=$stderr"; return 1; }
    [ "$output" = routed ]
    [ "$(grep -c 'not a YAML boolean' <<<"$stderr")" = 1 ] || { echo "stderr=$stderr"; return 1; }
    # sourcing twice is still a no-op: the said-once flag survives a re-source
    run --separate-stderr bash -c 'source "$1"; agy_gate_warn_once "$2"; source "$1"; agy_gate_warn_once "$2"' _ "$LIB" "$CFG"
    [ "$(grep -c 'not a YAML boolean' <<<"$stderr")" = 1 ] || { echo "stderr=$stderr"; return 1; }
}

@test "AGC-15 (r251-4 S5, audit run-2 n7) a hostile model string never executes — with the real maps and with maps that declare no arrays" {
    local pwn="$BATS_TEST_TMPDIR/pwned" m
    local -a hostile=("x\$(touch $pwn)" "a[\$(touch $pwn)]" ']' '[' 'x`touch '"$pwn"'`' "a[\`touch $pwn\`]")
    for m in "${hostile[@]}"; do
        bash -c 'source "$1"; routes_to_agy "$2" cli-only; agy_catalog_provider "$2" >/dev/null' _ "$LIB" "$m" 2>/dev/null || true
    done
    [ ! -e "$pwn" ] || { echo "a hostile model string executed (real maps)"; return 1; }
    # a lib copy whose maps file declares nothing (an old or broken install): the arrays would be indexed, not associative
    local L="$BATS_TEST_TMPDIR/fake/scripts"; mkdir -p "$L/lib"
    cp -- "$LIB" "$L/lib/agy-gate-lib.sh"; printf '# no arrays here\ntrue\n' > "$L/generated-model-maps.sh"
    for m in "${hostile[@]}"; do
        bash -c 'source "$1"; routes_to_agy "$2" cli-only; agy_catalog_provider "$2" >/dev/null' _ "$L/lib/agy-gate-lib.sh" "$m" 2>/dev/null || true
    done
    [ ! -e "$pwn" ] || { echo "a hostile model string executed (undeclared maps)"; return 1; }
}

@test "AGC-16 (r251-4 S5, review Obs 4) unreadable maps: routes_to_agy falls back to the name rule and says so ONCE per shell; readable maps are silent" {
    local L="$BATS_TEST_TMPDIR/fake2/scripts"; mkdir -p "$L/lib"
    cp -- "$LIB" "$L/lib/agy-gate-lib.sh"; printf 'exit_with_error() { return 1; }\nfalse\n' > "$L/generated-model-maps.sh"
    run --separate-stderr bash -c 'source "$1"; routes_to_agy deep-research-pro cli-only && echo dr; routes_to_agy gemini-2.5-pro cli-only && echo g; routes_to_agy researcher cli-only && echo r' _ "$L/lib/agy-gate-lib.sh"
    [ "$output" = g ] || { echo "out=$output"; return 1; }
    [ "$(grep -c 'generated model maps .* could not be read' <<<"$stderr")" = 1 ] || { echo "stderr=$stderr"; return 1; }
    run --separate-stderr bash -c 'source "$1"; routes_to_agy deep-research-pro cli-only && echo dr' _ "$LIB"
    [ "$output" = dr ] && [ -z "$stderr" ] || { echo "out=$output stderr=$stderr"; return 1; }
}

@test "AGC-17 (r251-4 S8, audit n14) a project-config alias is resolved before the rule, as cheval resolves the hop: an alias of gemini-headless is agy-routed on any mode" {
    source "$LIB"
    {
        printf 'hounfour:\n  headless:\n    mode: prefer-api\n  aliases:\n'
        printf '    myg: "google:gemini-headless"\n    myh:\n      target: gemini-headless\n'
        printf '    myr: "google:gemini-2.5-pro"\n    myo: "openai:gpt-5.5"\n'
    } > "$CFG"
    local m mode want got
    while read -r m mode want; do
        if routes_to_agy "$m" "$mode" "$CFG"; then got=True; else got=False; fi
        [ "$got" = "$want" ] || { echo "routes_to_agy $m $mode <cfg> → $got, want $want"; return 1; }
    done <<'TABLE'
myg prefer-api True
myh prefer-cli True
myr prefer-api False
myr cli-only True
myo cli-only False
gemini-headless prefer-api True
gpt-5.5 cli-only False
TABLE
    # without the config the bash rule cannot see the project alias (the old behaviour, kept for config-less callers)
    ! routes_to_agy myg prefer-api || { echo "myg routed without a config"; return 1; }
    # agy_route_planned reads the config itself: opt-in off → the aliased hop is not planned
    ! agy_route_planned myg "$CFG" || { echo "myg planned with the opt-in off"; return 1; }
    agy_route_planned myo "$CFG"
}

@test "AGC-18 (r251-4 S8, audit n14) the planners resolve project aliases: the Flatline tertiary and the dissent companion chain" {
    PROJECT_ROOT="$REPO"
    printf 'hounfour:\n  headless:\n    mode: prefer-api\n  aliases:\n    myg: "google:gemini-headless"\nflatline_protocol:\n  models:\n    tertiary: myg\n' > "$CFG"
    run bash -c 'source "$1/.claude/scripts/flatline-orchestrator.sh"; CONFIG_FILE="$2"; get_tertiary_status' _ "$REPO" "$CFG"
    [ "$output" = disabled_by_opt_in ] || { echo "flatline → $output"; return 1; }
    run --separate-stderr bash -c 'PROJECT_ROOT="$1"; source "$1/.claude/scripts/adversarial-review.sh"; CONFIG_FILE="$2"; log() { echo "$*" >&2; }; _adv_agy_filter_chain code_review anthropic myg claude-headless' _ "$REPO" "$CFG"
    [ "$output" = claude-headless ] || { echo "dissent → $output ($stderr)"; return 1; }
}

# --- review r251-5 U1/U2 (audit MED-001, LOW-001): ONE permission rule in all three readers -------------------------------
# The opt-in config must be owned by the current user and be neither group- nor world-writable; otherwise the opt-in reads
# OFF in the bash lib, in cheval's Python loader and in Bridgebuilder's readAgyGate, and each says so once naming the key and
# the reason. The mode half is asserted on real files (0666 0646 0664 0660 and a symlink to a 0666 target); the owner half
# cannot be faked without root — the bash leg shims `stat` to report a foreign uid, the Python leg is
# test_agy_opt_in_r251_4.py (geteuid monkeypatched), the TS leg multi-model-agy-opt-in.test.ts (process.getuid mocked).

_ts_gate() {  # <config>... → one "on|off<TAB><typeWarning>" line per config from Bridgebuilder's readAgyGate (one tsx run)
    local bb="$REPO/.claude/skills/bridgebuilder-review/resources"
    # the BB skill's pinned tsx (devDependency) — never `npx tsx`, which on a bare runner asks to fetch a release and prints nothing
    local tsx="$REPO/.claude/skills/bridgebuilder-review/node_modules/.bin/tsx"
    (cd "$bb" && "$tsx" -e '
import { readAgyGate } from "./config.ts";
for (const p of process.argv.slice(1)) { const g = readAgyGate(p); console.log(`${g.optIn ? "on" : "off"}\t${g.typeWarning ?? ""}`); }
' "$@")
}

_py_gate() {  # <project root> → "on|off" from cheval's loader; its stderr to $BATS_TEST_TMPDIR/py.err
    python3 -I -c 'import sys; sys.path.insert(0, sys.argv[1]); from loa_cheval.config.loader import agy_opt_in_enabled; agy_opt_in_enabled(sys.argv[2]); print("on" if agy_opt_in_enabled(sys.argv[2]) else "off")' \
        "$REPO/.claude/adapters" "$1" 2>"$BATS_TEST_TMPDIR/py.err"
}

@test "AGC-19 (r251-5 U1/U2) a group- or world-writable \`true\` config reads off in the lib, Python and Bridgebuilder, one WARN each naming the key and the reason; 0644 / 0600 opt in" {
    [ -x "$REPO/.claude/skills/bridgebuilder-review/node_modules/.bin/tsx" ] || skip "the TS leg needs the BB skill's pinned tsx — run npm ci in .claude/skills/bridgebuilder-review (BB-1275 #7)"
    local m root want reason out err py tsv=() roots=() ms=(0666 0646 0664 0660 0620 symlink 0644 0600)
    for m in "${ms[@]}"; do
        root="$BATS_TEST_TMPDIR/perm-$m"; mkdir -p "$root"; roots+=("$root")
        if [[ "$m" == symlink ]]; then
            printf 'hounfour:\n  headless:\n    agy_opt_in: true\n' > "$root/target.yaml"; chmod 0666 "$root/target.yaml"
            ln -s target.yaml "$root/.loa.config.yaml"
        else
            printf 'hounfour:\n  headless:\n    agy_opt_in: true\n' > "$root/.loa.config.yaml"; chmod "$m" "$root/.loa.config.yaml"
        fi
    done
    # (r251-6 V1: the group-writable rows are judged against a SHARED group `users` — the same fake account database for
    # the three legs; the user-private-group exception has its own rows, AGC-22..24)
    _getent_shim users ""
    local shim="$BATS_TEST_TMPDIR/getent-shim"
    mapfile -t tsv < <(PATH="$shim:$PATH" _ts_gate "${roots[@]/%//.loa.config.yaml}")
    [ "${#tsv[@]}" = "${#ms[@]}" ] || { echo "TS leg printed ${#tsv[@]} lines: ${tsv[*]}"; return 1; }
    local i
    for i in "${!ms[@]}"; do
        m="${ms[$i]}"; root="${roots[$i]}"
        case "$m" in 0644|0600) want=on; reason="" ;; 0664|0660|0620) want=off; reason=group-writable ;; *) want=off; reason=world-writable ;; esac
        run --separate-stderr env PATH="$shim:$PATH" bash -c 'source "$1"; agy_gate_warn_once "$2"; agy_gate_warn_once "$2"; agy_opted_in "$2" && echo on || echo off' _ "$LIB" "$root/.loa.config.yaml"
        py=$(_py_gate_db "$root"); err=$(cat "$BATS_TEST_TMPDIR/py.err")
        [ "$output" = "$want" ] && [ "$py" = "$want" ] && [ "${tsv[$i]%%$'\t'*}" = "$want" ] || { echo "$m: bash=$output python=$py ts=${tsv[$i]} want=$want"; return 1; }
        if [[ -n "$reason" ]]; then
            [ "$(grep -c "hounfour.headless.agy_opt_in.*$reason" <<<"$stderr")" = 1 ] || { echo "$m bash stderr=$stderr"; return 1; }
            [ "$(grep -c 'hounfour.headless.agy_opt_in' <<<"$stderr")" = 1 ] || { echo "$m bash said it more than once: $stderr"; return 1; }
            [ "$(grep -c "hounfour.headless.agy_opt_in.*$reason" <<<"$err")" = 1 ] || { echo "$m python stderr=$err"; return 1; }
            [[ "${tsv[$i]#*$'\t'}" == *hounfour.headless.agy_opt_in*"$reason"* ]] || { echo "$m ts warning=${tsv[$i]}"; return 1; }
        else
            [ -z "$stderr" ] || { echo "$m bash warned: $stderr"; return 1; }
            ! grep -q 'agy_opt_in' <<<"$err" || { echo "$m python warned: $err"; return 1; }
            [ -z "${tsv[$i]#*$'\t'}" ] || { echo "$m ts warned: ${tsv[$i]}"; return 1; }
        fi
    done
}

@test "AGC-20 (r251-5 U1) the bash lib refuses a config the current user does not own (stat shimmed: GNU and BSD shapes), and a stat failure reads off" {
    _cfg prefer-api true
    local shim="$BATS_TEST_TMPDIR/statshim" form
    mkdir -p "$shim"
    for form in gnu bsd fail; do
        case "$form" in
            gnu)  printf '#!/usr/bin/env bash\n[[ "$*" == *" -c "* ]] && { echo "%s 644"; exit 0; }\nexit 1\n' "$(( $(id -u) + 1 ))" > "$shim/stat" ;;
            bsd)  printf '#!/usr/bin/env bash\n[[ "$*" == *" -c "* ]] && exit 1\n[[ "$*" == *" -f "* ]] && { echo "%s 644"; exit 0; }\nexit 1\n' "$(( $(id -u) + 1 ))" > "$shim/stat" ;;
            fail) printf '#!/usr/bin/env bash\nexit 1\n' > "$shim/stat" ;;
        esac
        chmod +x "$shim/stat"
        run --separate-stderr env PATH="$shim:$PATH" bash -c 'source "$1"; agy_gate_warn_once "$2"; agy_opted_in "$2" && echo on || echo off' _ "$LIB" "$CFG"
        [ "$output" = off ] || { echo "$form: a foreign-owned config opted in"; return 1; }
        if [[ "$form" == fail ]]; then
            grep -q 'hounfour.headless.agy_opt_in.*could not be stat' <<<"$stderr" || { echo "$form stderr=$stderr"; return 1; }
        else
            grep -q "hounfour.headless.agy_opt_in.*not owned by the current user" <<<"$stderr" || { echo "$form stderr=$stderr"; return 1; }
        fi
    done
    # and the real stat on an owned 0644 file: on
    run bash -c 'source "$1"; agy_opted_in "$2" && echo on || echo off' _ "$LIB" "$CFG"
    [ "$output" = on ]
}

@test "AGC-21 (r251-5 U1) the permission rule judges only a value that would opt in: a 0664 config with the key absent, false or \"true\" is never flagged as writable by others" {
    [ -x "$REPO/.claude/skills/bridgebuilder-review/node_modules/.bin/tsx" ] || skip "the TS leg needs the BB skill's pinned tsx — run npm ci in .claude/skills/bridgebuilder-review (BB-1275 #7)"
    local w root roots=() tsv=() i
    for w in absent false '"true"'; do
        root="$BATS_TEST_TMPDIR/quiet-${#roots[@]}"; mkdir -p "$root"; roots+=("$root")
        { printf 'hounfour:\n  headless:\n    mode: prefer-api\n'; [[ "$w" == absent ]] || printf '    agy_opt_in: %s\n' "$w"; } > "$root/.loa.config.yaml"
        chmod 0664 "$root/.loa.config.yaml"
    done
    mapfile -t tsv < <(_ts_gate "${roots[@]/%//.loa.config.yaml}")
    for i in "${!roots[@]}"; do
        root="${roots[$i]}"
        run --separate-stderr bash -c 'source "$1"; agy_gate_warn_once "$2"; agy_opted_in "$2" && echo on || echo off' _ "$LIB" "$root/.loa.config.yaml"
        [ "$output" = off ] && [ "$(_py_gate "$root")" = off ] && [ "${tsv[$i]%%$'\t'*}" = off ] || { echo "row $i: bash=$output ts=${tsv[$i]}"; return 1; }
        ! grep -q 'writable' <<<"$stderr" || { echo "row $i bash flagged: $stderr"; return 1; }
        ! grep -q 'writable' "$BATS_TEST_TMPDIR/py.err" || { echo "row $i python flagged: $(cat "$BATS_TEST_TMPDIR/py.err")"; return 1; }
        [[ "${tsv[$i]}" != *writable* ]] || { echo "row $i ts flagged: ${tsv[$i]}"; return 1; }
    done
}

# --- review r251-6 (the Bridgebuilder pass on PR #1275) ---------------------------------------------------------------
# V1 (BB #1): a group-writable config is trusted only for the owner's USER-PRIVATE group — gid = the owner's primary gid, the
# group named for the owner, no other member, no other account with it as its primary group, no ACL (the group bits would be
# the mask). Ubuntu's umask 002 makes every checkout 0664. The account database is faked ONCE per row (a `getent` shim the
# bash and TS legs find on PATH; the Python leg's pwd/grp answer from the same shim).

_getent_shim() {  # <group name> <members> [others] → $BATS_TEST_TMPDIR/getent-shim/getent: this user is `loa-me` (the real uid
    # and primary gid), the process's gid is the group <name> with <members>; [others] adds `staffer`, whose primary group it is
    local d="$BATS_TEST_TMPDIR/getent-shim" uid gid other=""
    uid=$(id -u); gid=$(id -g)
    [[ -n "${3:-}" ]] && other="echo 'staffer:x:$(( uid + 1 )):$gid::/nonexistent:/bin/sh';"
    mkdir -p "$d"
    cat > "$d/getent" <<SHIM
#!/bin/sh
case "\$1" in
  passwd) if [ -n "\$2" ]; then [ "\$2" = "$uid" ] && echo 'loa-me:x:$uid:$gid::/nonexistent:/bin/sh' || exit 2
          else echo 'loa-me:x:$uid:$gid::/nonexistent:/bin/sh'; $other fi ;;
  group) [ "\$2" = "$gid" ] && echo '$1:x:$gid:$2' || exit 2 ;;
  *) exit 1 ;;
esac
SHIM
    chmod +x "$d/getent"
}

_py_gate_db() {  # <project root> → as _py_gate, with pwd / grp answered by the getent shim (the bash and TS legs' database)
    python3 -I -c '
import subprocess, sys, types, grp, pwd
shim = sys.argv[3]
def ge(*a):
    r = subprocess.run([shim, *a], capture_output=True, text=True)
    if r.returncode:
        raise KeyError(a)
    return [l.split(":") for l in r.stdout.splitlines() if l]
acct = lambda f: types.SimpleNamespace(pw_name=f[0], pw_uid=int(f[2]), pw_gid=int(f[3]))
pwd.getpwuid = lambda u: acct(ge("passwd", str(u))[0])
pwd.getpwall = lambda: [acct(f) for f in ge("passwd")]
def getgrgid(g):
    f = ge("group", str(g))[0]
    return types.SimpleNamespace(gr_name=f[0], gr_gid=int(f[2]), gr_mem=[m for m in f[3].split(",") if m])
grp.getgrgid = getgrgid
sys.path.insert(0, sys.argv[1])
from loa_cheval.config.loader import agy_opt_in_enabled
agy_opt_in_enabled(sys.argv[2]); print("on" if agy_opt_in_enabled(sys.argv[2]) else "off")' \
        "$REPO/.claude/adapters" "$1" "$BATS_TEST_TMPDIR/getent-shim/getent" 2>"$BATS_TEST_TMPDIR/py.err"
}

_tsx_present() { [ -x "$REPO/.claude/skills/bridgebuilder-review/node_modules/.bin/tsx" ]; }

_three_legs() {  # <config dir> → "bash=<on|off> py=<on|off> ts=<on|off>" with the getent shim on PATH; WARNs to $BATS_TEST_TMPDIR/{bash,py,ts}.err
    local root="$1" shim="$BATS_TEST_TMPDIR/getent-shim" b p t
    b=$(PATH="$shim:$PATH" bash -c 'source "$1"; agy_gate_warn_once "$2"; agy_gate_warn_once "$2"; agy_opted_in "$2" && echo on || echo off' _ "$LIB" "$root/.loa.config.yaml" 2>"$BATS_TEST_TMPDIR/bash.err")
    p=$(_py_gate_db "$root")
    t=$(PATH="$shim:$PATH" _ts_gate "$root/.loa.config.yaml")
    printf '%s\n' "${t#*$'\t'}" > "$BATS_TEST_TMPDIR/ts.err"
    echo "bash=$b py=$p ts=${t%%$'\t'*}"
}

@test "AGC-22 (r251-6 V1) a 0664 / 0660 \`true\` config of the owner's user-private group opts in on every reader, silently" {
    _tsx_present || skip "the TS leg needs the BB skill's pinned tsx — run npm ci in .claude/skills/bridgebuilder-review"
    _getent_shim loa-me ""
    local m root got
    for m in 0664 0660; do
        root="$BATS_TEST_TMPDIR/upg-$m"; mkdir -p "$root"
        printf 'hounfour:\n  headless:\n    agy_opt_in: true\n' > "$root/.loa.config.yaml"; chmod "$m" "$root/.loa.config.yaml"
        got=$(_three_legs "$root")
        [ "$got" = "bash=on py=on ts=on" ] || { echo "$m: $got"; cat "$BATS_TEST_TMPDIR"/{bash,py,ts}.err; return 1; }
        ! grep -q 'agy_opt_in' "$BATS_TEST_TMPDIR/bash.err" "$BATS_TEST_TMPDIR/py.err" "$BATS_TEST_TMPDIR/ts.err" || { echo "$m warned"; cat "$BATS_TEST_TMPDIR"/{bash,py,ts}.err; return 1; }
    done
    # the owner listed as its own member is still private
    _getent_shim loa-me "loa-me"
    got=$(_three_legs "$BATS_TEST_TMPDIR/upg-0664")
    [ "$got" = "bash=on py=on ts=on" ] || { echo "self-member: $got"; return 1; }
}

@test "AGC-23 (r251-6 V1) 0664 + a group with another member / named differently / another account's primary group, and 0666: off on every reader, one WARN naming the group" {
    _tsx_present || skip "the TS leg needs the BB skill's pinned tsx — run npm ci in .claude/skills/bridgebuilder-review"
    local root="$BATS_TEST_TMPDIR/shared" row name members others mode needle got f
    mkdir -p "$root"
    printf 'hounfour:\n  headless:\n    agy_opt_in: true\n' > "$root/.loa.config.yaml"
    while IFS='|' read -r name members others mode needle; do
        _getent_shim "$name" "$members" "$others"
        chmod "$mode" "$root/.loa.config.yaml"
        got=$(_three_legs "$root")
        [ "$got" = "bash=off py=off ts=off" ] || { echo "$name/$members/$others/$mode: $got"; return 1; }
        for f in bash py ts; do
            [ "$(grep -c 'hounfour.headless.agy_opt_in' "$BATS_TEST_TMPDIR/$f.err")" = 1 ] || { echo "$f ($name $mode): $(cat "$BATS_TEST_TMPDIR/$f.err")"; return 1; }
            grep -qF -- "$needle" "$BATS_TEST_TMPDIR/$f.err" || { echo "$f ($name $mode) lacks [$needle]: $(cat "$BATS_TEST_TMPDIR/$f.err")"; return 1; }
        done
    done <<'ROWS'
loa-me|bob||0664|group-writable (mode 0664) and its group 'loa-me' has other members (bob)
users|||0664|group-writable (mode 0664) and its group 'users' is not named for the owner 'loa-me'
loa-me||x|0664|group-writable (mode 0664) and its group 'loa-me' is the primary group of another account (staffer)
loa-me|||0666|world-writable (mode 0666)
ROWS
}

@test "AGC-24 (r251-6 V1) the real account database: the three readers agree on a 0664 \`true\` config; an ACL grant is refused everywhere" {
    _tsx_present || skip "the TS leg needs the BB skill's pinned tsx — run npm ci in .claude/skills/bridgebuilder-review"
    local root="$BATS_TEST_TMPDIR/real" b p t
    mkdir -p "$root"
    printf 'hounfour:\n  headless:\n    agy_opt_in: true\n' > "$root/.loa.config.yaml"; chmod 0664 "$root/.loa.config.yaml"
    b=$(bash -c 'source "$1"; agy_opted_in "$2" && echo on || echo off' _ "$LIB" "$root/.loa.config.yaml")
    p=$(_py_gate "$root"); t=$(_ts_gate "$root/.loa.config.yaml"); t="${t%%$'\t'*}"
    [ "$b" = "$p" ] && [ "$p" = "$t" ] || { echo "real database: bash=$b python=$p ts=$t"; return 1; }
    command -v setfacl >/dev/null 2>&1 || skip "setfacl not installed (the ACL row)"
    chmod 0600 "$root/.loa.config.yaml"
    setfacl -m u:nobody:rw "$root/.loa.config.yaml" 2>/dev/null || skip "setfacl refused here"
    _getent_shim loa-me ""   # (a private group on every leg — only the ACL can refuse)
    b=$(_three_legs "$root")
    [ "$b" = "bash=off py=off ts=off" ] || { echo "ACL: $b"; return 1; }
    grep -q 'extended ACL' "$BATS_TEST_TMPDIR/bash.err" && grep -q 'extended ACL' "$BATS_TEST_TMPDIR/py.err" && grep -q 'extended ACL' "$BATS_TEST_TMPDIR/ts.err" || { cat "$BATS_TEST_TMPDIR"/{bash,py,ts}.err; return 1; }
}

@test "AGC-25 (r251-6 V3) the bash lib judges the file it read: a world-writable \`true\` config swapped for an owned 0644 one mid-read stays off" {
    local real; real=$(command -v yq) || skip "yq not installed"
    local d="$BATS_TEST_TMPDIR/swapyq"; mkdir -p "$d"
    printf 'hounfour:\n  headless:\n    agy_opt_in: true\n' > "$CFG"; chmod 0666 "$CFG"
    printf 'hounfour:\n  headless:\n    agy_opt_in: true\n' > "$BATS_TEST_TMPDIR/repl.yaml"; chmod 0644 "$BATS_TEST_TMPDIR/repl.yaml"
    # (every yq call runs the real yq, then moves the owned replacement over the config path — before the trust check)
    printf '#!/bin/sh\n"%s" "$@"; rc=$?\n[ -e "%s" ] && mv "%s" "%s"\nexit $rc\n' "$real" "$BATS_TEST_TMPDIR/repl.yaml" "$BATS_TEST_TMPDIR/repl.yaml" "$CFG" > "$d/yq"
    chmod +x "$d/yq"
    # (ONE read: the first yq call of this read performs the swap; a later read would rightly see the owned replacement)
    run env PATH="$d:$PATH" bash -c 'source "$1"; agy_opted_in "$2" && echo on || echo off' _ "$LIB" "$CFG"
    [ ! -e "$BATS_TEST_TMPDIR/repl.yaml" ] || { echo "the swap never happened"; return 1; }
    [ "$output" = off ] || { echo "judged the replacement: $output"; return 1; }
    [ "$(stat -L -c '%a' -- "$CFG")" = 644 ]   # (the path now holds the owned replacement)
    run --separate-stderr bash -c 'source "$1"; agy_gate_warn_once "$2"; agy_opted_in "$2" && echo on || echo off' _ "$LIB" "$CFG"
    [ "$output" = on ] && [ -z "$stderr" ] || { echo "the replacement itself: $output ($stderr)"; return 1; }
}

@test "AGC-26 (r251-6 V5) an alias / non-mapping ancestor of the key: off on every reader (go-yq lib, python-yq lib, Python, Bridgebuilder), ONE WARN naming the path" {
    python3 -c 'import yaml' 2>/dev/null || skip "PyYAML not installed"
    _tsx_present || skip "the TS leg needs the BB skill's pinned tsx — run npm ci in .claude/skills/bridgebuilder-review"
    _fake_yq 'yq 3.4.3' true
    local body path what root out f
    while IFS='|' read -r body path what; do
        root="$BATS_TEST_TMPDIR/anc-$RANDOM"; mkdir -p "$root"
        printf '%b' "$body" > "$root/.loa.config.yaml"
        run --separate-stderr bash -c 'source "$1"; agy_gate_warn_once "$2"; agy_gate_warn_once "$2"; agy_opted_in "$2" && echo on || echo off' _ "$LIB" "$root/.loa.config.yaml"
        [ "$output" = off ] || { echo "go-yq $path: $output"; return 1; }
        printf '%s\n' "$stderr" > "$BATS_TEST_TMPDIR/go.err"
        run --separate-stderr env PATH="$BATS_TEST_TMPDIR/fyq:$PATH" bash -c 'source "$1"; agy_gate_warn_once "$2"; agy_opted_in "$2" && echo on || echo off' _ "$LIB" "$root/.loa.config.yaml"
        [ "$output" = off ] || { echo "python-yq $path: $output"; return 1; }
        printf '%s\n' "$stderr" > "$BATS_TEST_TMPDIR/pyq.err"
        [ "$(_py_gate "$root")" = off ] || { echo "python $path on"; return 1; }
        out=$(_ts_gate "$root/.loa.config.yaml")
        [ "${out%%$'\t'*}" = off ] || { echo "ts $path: $out"; return 1; }
        printf '%s\n' "${out#*$'\t'}" > "$BATS_TEST_TMPDIR/ts.err"
        for f in go pyq py ts; do
            [ "$(grep -c "$path is $what — hounfour.headless.agy_opt_in cannot be read" "$BATS_TEST_TMPDIR/$f.err")" = 1 ] || { echo "$f $path: $(cat "$BATS_TEST_TMPDIR/$f.err")"; return 1; }
        done
    done <<'ROWS'
h: &h\n  agy_opt_in: true\nhounfour:\n  headless: *h\n|hounfour.headless|a YAML alias
h: &h\n  headless:\n    agy_opt_in: true\nhounfour: *h\n|hounfour|a YAML alias
hounfour:\n  headless: [1]\n|hounfour.headless|not a mapping (seq)
hounfour: foo\n|hounfour|not a mapping (str)
ROWS
    # an absent or null ancestor stays silent everywhere
    printf 'hounfour:\n  headless:\n' > "$CFG"
    run --separate-stderr bash -c 'source "$1"; agy_gate_warn_once "$2"' _ "$LIB" "$CFG"
    ! grep -q 'cannot be read' <<<"$stderr" || { echo "null headless warned: $stderr"; return 1; }
}

# ---- cycle-137 FR-3 (Task 2.3b, bd-gv5jf): the opt-in node read is memoised in the calling shell, keyed on the file's identity ----
_agc27_count() {  # source the lib, wrap the node reader so each real read appends a line to $BATS_TEST_TMPDIR/node-calls
    source "$LIB"
    : > "$BATS_TEST_TMPDIR/node-calls"
    eval "$(declare -f _agy_opt_in_node | sed '1s/^_agy_opt_in_node/_agc27_orig_node/')"
    _agy_opt_in_node() { echo x >> "$BATS_TEST_TMPDIR/node-calls"; _agc27_orig_node "$@"; }
}
_agc27_calls() { wc -l < "$BATS_TEST_TMPDIR/node-calls" | tr -d ' '; }
_agc27_ns_mtime() {  # 0 when a fresh write in this directory keeps a sub-second mtime (GNU stat), else 1
    local p="$BATS_TEST_TMPDIR/ns-probe" t; printf x > "$p"
    t=$(stat -c '%.9Y' -- "$p" 2>/dev/null) || return 1
    [[ "$t" == *.* && "${t#*.}" != 000000000 ]]
}
_agc_settle() {  # <file>: wait until the clock is two seconds past the file's ctime — a touch or chmod stamps ctime NOW, and
    # the lib never memoises a file whose mtime or ctime is within one second of the clock (review r2); GNU stat, else sleep 2
    local c; c=$(stat -c %Z -- "$1" 2>/dev/null) || { sleep 2; return 0; }
    [[ "$c" =~ ^[0-9]+$ ]] || { sleep 2; return 0; }
    while (( $(date +%s) < c + 2 )); do sleep 0.1; done
}

@test "AGC-27 (cycle-137 FR-3) the node is read ONCE per shell for an unchanged config: two agy_opted_in calls, and agy_gate_warn_once + agy_opted_in" {
    _agc27_count
    _cfg cli-only true
    touch -d "@$(( $(date +%s) - 60 ))" "$CFG"; _agc_settle "$CFG"   # an aged, settled config: a file modified within a second of the clock is never memoised (review r1 DISS-001, r2)
    agy_opted_in "$CFG" || { echo "first call read off"; return 1; }
    agy_opted_in "$CFG" || { echo "memo hit read off"; return 1; }
    [ "$(_agc27_calls)" = 1 ] || { echo "node reads: $(_agc27_calls)"; return 1; }
    _cfg cli-only '"true"'; touch -d "@$(( $(date +%s) - 60 ))" "$CFG"; _agc_settle "$CFG"; : > "$BATS_TEST_TMPDIR/node-calls"   # aged and settled again (same rule)
    run --separate-stderr agy_gate_warn_once "$CFG"   # (run: a subshell — the warn and its own agy_opted_in share one memo there)
    [ "$status" -eq 0 ]
    [ "$(_agc27_calls)" = 1 ] || { echo "node reads in warn_once: $(_agc27_calls)"; return 1; }
}

@test "AGC-28 (cycle-137 FR-3) a same-length in-place rewrite is a miss: with a distinct mtime, and twice within one second" {
    _agc27_count
    _cfg cli-only 'true '   # (same length as `false`; the trailing space is not part of the scalar)
    local t; t=$(( $(date +%s) - 60 ))   # aged stamps: each read below is a KEY MISS, not the current-second bypass (review r2 DISS-C-005)
    touch -d "@$t" "$CFG"
    agy_opted_in "$CFG" || { echo "true read off"; return 1; }
    _cfg cli-only false; touch -d "@$(( t + 1 ))" "$CFG"
    ! agy_opted_in "$CFG" || { echo "stale memo: false read as true"; return 1; }
    _cfg cli-only 'true '; touch -d "@$(( t + 2 ))" "$CFG"
    agy_opted_in "$CFG" || { echo "stale memo: true read as false"; return 1; }
    [ "$(_agc27_calls)" = 3 ] || { echo "node reads: $(_agc27_calls) (expected 3 misses)"; return 1; }
    _agc_settle "$CFG"   # the last touch stamped ctime now; settle, then one read populates the memo and the next is the hit
    agy_opted_in "$CFG" || { echo "settled read off"; return 1; }
    [ "$(_agc27_calls)" = 4 ] || { echo "node reads after settling: $(_agc27_calls) (expected 4)"; return 1; }
    agy_opted_in "$CFG" || { echo "memo hit read off"; return 1; }   # no re-touch: served from the memo
    [ "$(_agc27_calls)" = 4 ] || { echo "node reads after the hit: $(_agc27_calls) (expected still 4)"; return 1; }
    if ! _agc27_ns_mtime; then skip "this filesystem keeps 1 s mtimes: the same-second rewrite case is not decidable here"; fi
    # (no touch: two plain writes back to back, normally inside one second — only the sub-second mtime/ctime tells them apart)
    _cfg cli-only false
    ! agy_opted_in "$CFG" || { echo "rewrite to false not seen"; return 1; }
    _cfg cli-only 'true '
    agy_opted_in "$CFG" || { echo "same-second rewrite to true not seen"; return 1; }
    _cfg cli-only false
    ! agy_opted_in "$CFG" || { echo "same-second rewrite to false not seen"; return 1; }
}

_agc33_shim() {  # a stat shim with BSD argv and WHOLE-SECOND times for the memo's identity read only (review r1/r2)
    # mtime = SHIM_MTIME when set, else now - SHIM_AGE (default 0 = the current second, recomputed per call);
    # ctime = SHIM_CTIME when set (`live` = the current second at every call), else the mtime.
    local shim="$BATS_TEST_TMPDIR/statshim"; mkdir -p "$shim"
    cat > "$shim/stat" <<'EOF'
#!/usr/bin/env bash
# the memo's BSD identity read only; every other stat call (the untrusted-config check) goes to the real binary
if [[ "$1" == "-L" && "$2" == "-f" && "$3" == "%d:%i:%z:%m:%c" ]]; then
    f=""; for a in "$@"; do f=$a; done
    sz=$(/usr/bin/stat -L -c %s -- "$f" 2>/dev/null) || exit 1
    m=${SHIM_MTIME:-$(( $(date +%s) - ${SHIM_AGE:-0} ))}
    case "${SHIM_CTIME:-}" in live) c=$(date +%s) ;; "") c=$m ;; *) c=$SHIM_CTIME ;; esac
    printf '%s\n' "7:${sz}:${sz}:${m}:${c}"; exit 0
fi
exec /usr/bin/stat "$@"
EOF
    chmod +x "$shim/stat"
    PATH="$shim:$PATH"; _AGY_STAT_STYLE=bsd; _AGY_NODE_MEMO_KEY=""; _AGY_NODE_MEMO_VAL=""
}

@test "AGC-33 (cycle-137 review r1 DISS-001) with whole-second stat (the BSD branch) a same-length rewrite within the same second is seen, and an aged file is still memoised" {
    _agc27_count
    _agc33_shim
    # (1) the window: true, then a same-length false in the same second — the second call must read the file again
    _cfg cli-only 'true '
    agy_opted_in "$CFG" || { echo "true read off"; return 1; }
    _cfg cli-only false
    ! agy_opted_in "$CFG" || { echo "stale memo: false read as true under whole-second stat"; return 1; }
    [ "$(_agc27_calls)" = 2 ] || { echo "node reads: $(_agc27_calls) (expected 2: no memo for a file modified in the current second)"; return 1; }
    # (2) an aged file is still memoised: one read for two calls
    : > "$BATS_TEST_TMPDIR/node-calls"; _AGY_NODE_MEMO_KEY=""; _AGY_NODE_MEMO_VAL=""
    _cfg cli-only true
    export SHIM_MTIME=$(( $(date +%s) - 60 ))   # frozen ONCE: a per-call `now - 60` changes across a clock tick (review r2 DISS-C-001)
    agy_opted_in "$CFG" || { echo "aged true read off"; return 1; }
    agy_opted_in "$CFG" || { echo "aged memo hit read off"; return 1; }
    [ "$(_agc27_calls)" = 1 ] || { echo "node reads for an aged file: $(_agc27_calls) (expected 1)"; return 1; }
    unset SHIM_MTIME
}

@test "AGC-34 (cycle-137 review r2 DISS-001) with whole-second stat a permission change within the current second is seen: an aged true config chmod'ed 0600 then 0666 in one second reads off on the second call" {
    _agc27_count
    _agc33_shim
    _cfg cli-only true; chmod 0600 "$CFG"
    export SHIM_MTIME=$(( $(date +%s) - 60 )) SHIM_CTIME=live   # content aged; the chmod stamps ctime in the current second
    agy_opted_in "$CFG" || { echo "0600 true read off"; return 1; }
    chmod 0666 "$CFG"   # others can write now: the permission rule must read it off — same whole second, same key
    ! agy_opted_in "$CFG" || { echo "stale memo: a world-writable config still read as on under whole-second stat"; return 1; }
    [ "$(_agc27_calls)" = 2 ] || { echo "node reads: $(_agc27_calls) (expected 2: no memo while ctime is in the current second)"; return 1; }
    unset SHIM_MTIME SHIM_CTIME
}

@test "AGC-35 (cycle-137 review r2 DISS-C-002) a stamp one second old is still inside the window: a same-length rewrite is seen with the clock one tick ahead of the stamp" {
    _agc27_count
    _agc33_shim
    export SHIM_AGE=1   # every identity read reports mtime = ctime = now - 1 (a coarse-clock stamp lagging the fine clock)
    _cfg cli-only 'true '
    agy_opted_in "$CFG" || { echo "true read off"; return 1; }
    _cfg cli-only false
    ! agy_opted_in "$CFG" || { echo "stale memo: false read as true with a one-second-old stamp"; return 1; }
    [ "$(_agc27_calls)" = 2 ] || { echo "node reads: $(_agc27_calls) (expected 2: a stamp within one second of the clock is never memoised)"; return 1; }
    unset SHIM_AGE
}

@test "AGC-36 (cycle-137 review r2) with frozen AGED stamps each key component is a miss on its own: a changed mtime, a changed ctime, a changed size — and an unchanged key is a hit" {
    _agc27_count
    _agc33_shim
    local t0; t0=$(( $(date +%s) - 120 ))
    export SHIM_MTIME=$t0 SHIM_CTIME=$t0
    _cfg cli-only 'true '
    agy_opted_in "$CFG" || { echo "true read off"; return 1; }
    agy_opted_in "$CFG" || { echo "hit read off"; return 1; }
    [ "$(_agc27_calls)" = 1 ] || { echo "node reads for an unchanged key: $(_agc27_calls) (expected 1)"; return 1; }
    _cfg cli-only false; export SHIM_MTIME=$(( t0 + 1 ))              # same size, mtime moved by one aged second
    ! agy_opted_in "$CFG" || { echo "mtime change not a miss"; return 1; }
    _cfg cli-only 'true '; export SHIM_CTIME=$(( t0 + 1 ))             # same size, same mtime, ctime moved (a chmod)
    agy_opted_in "$CFG" || { echo "ctime change not a miss"; return 1; }
    _cfg cli-only 'false '                                             # size changed, stamps unchanged
    ! agy_opted_in "$CFG" || { echo "size change not a miss"; return 1; }
    [ "$(_agc27_calls)" = 4 ] || { echo "node reads: $(_agc27_calls) (expected 4: one hit, three misses)"; return 1; }
    unset SHIM_MTIME SHIM_CTIME
}

@test "AGC-29 (cycle-137 FR-3) a miss after mv replacement (new inode, same size and mtime), after deletion, and after switching the config path" {
    _agc27_count
    _cfg cli-only 'true '
    agy_opted_in "$CFG" || { echo "true read off"; return 1; }
    printf 'hounfour:\n  headless:\n    mode: cli-only\n    agy_opt_in: false\n' > "$BATS_TEST_TMPDIR/next.yaml"
    touch -r "$CFG" "$BATS_TEST_TMPDIR/next.yaml"
    [ "$(wc -c < "$CFG")" = "$(wc -c < "$BATS_TEST_TMPDIR/next.yaml")" ]
    mv -f "$BATS_TEST_TMPDIR/next.yaml" "$CFG"
    ! agy_opted_in "$CFG" || { echo "stale memo after mv"; return 1; }
    _cfg cli-only true; agy_opted_in "$CFG"
    rm -f "$CFG"
    run --separate-stderr agy_opted_in "$CFG"
    [ "$status" -eq 1 ] && [ -z "$stderr" ] || { echo "deleted: status=$status stderr=$stderr"; return 1; }
    agy_opted_in "$CFG" && { echo "deleted config opted in"; return 1; }
    [ -z "$_AGY_NODE_MEMO_VAL" ] && [ -z "$_AGY_NODE_MEMO_KEY" ] || { echo "stale memo kept for a deleted config: $_AGY_NODE_MEMO_VAL"; return 1; }
    _cfg cli-only true
    printf 'hounfour:\n  headless:\n    agy_opt_in: false\n' > "$BATS_TEST_TMPDIR/other.yaml"
    agy_opted_in "$CFG" || { echo "true read off"; return 1; }
    ! agy_opted_in "$BATS_TEST_TMPDIR/other.yaml" || { echo "path switch returned the other config's value"; return 1; }
    agy_opted_in "$CFG" || { echo "switch back read off"; return 1; }
}

@test "AGC-30 (cycle-137 FR-3) a \$(agy_opted_in …) caller gets the right answer (the memo lives only in the calling shell)" {
    source "$LIB"
    _cfg cli-only true
    agy_opted_in "$CFG"
    _cfg cli-only false; touch -d "@$(( $(date +%s) + 5 ))" "$CFG"
    [ "$(agy_opted_in "$CFG"; echo $?)" = 1 ]
    _cfg cli-only true; touch -d "@$(( $(date +%s) + 9 ))" "$CFG"
    [ "$(agy_opted_in "$CFG"; echo $?)" = 0 ]
}

@test "AGC-31 (cycle-137 FR-3) the memo is never seeded from the environment: a forged key + value for a false config reads off" {
    _cfg cli-only false
    local st; st=$(stat -L -c '%d:%i:%s:%.9Y:%.9Z' -- "$CFG" 2>/dev/null) || skip "GNU stat needed to forge the key"
    run --separate-stderr env _AGY_NODE_MEMO_KEY="$CFG|$st" _AGY_NODE_MEMO_VAL="bool true" _AGY_STAT_STYLE=bsd \
        bash -c 'source "$1"; agy_opted_in "$2"' _ "$LIB" "$CFG"
    [ "$status" -eq 1 ] || { echo "a forged memo opted in: status=$status stderr=$stderr"; return 1; }
}

@test "AGC-32 (cycle-137 FR-3) agy_gate_warn_once prints today's texts: untrusted, ancestor (int, alias), bool True, a string, and the availability WARN" {
    local avail="WARN: the agy route is available here (a Google/Gemini key is set) but not planned: hounfour.headless.agy_opt_in is not true — opt in only knowingly (the prompt travels on the CLI's argv, readable by local users; the CLI must be OAuth-authed)"
    local c want got
    printf 'hounfour:\n  headless:\n    mode: cli-only\n    agy_opt_in: true\n' > "$BATS_TEST_TMPDIR/untrusted.yaml"; chmod 666 "$BATS_TEST_TMPDIR/untrusted.yaml"
    printf 'hounfour:\n  headless: 5\n' > "$BATS_TEST_TMPDIR/ancestor.yaml"
    printf 'base: &b {headless: {agy_opt_in: true}}\nhounfour: *b\n' > "$BATS_TEST_TMPDIR/ancestor-alias.yaml"
    printf 'hounfour:\n  headless:\n    agy_opt_in: True\n' > "$BATS_TEST_TMPDIR/boolTrue.yaml"
    printf 'hounfour:\n  headless:\n    agy_opt_in: "true"\n' > "$BATS_TEST_TMPDIR/str.yaml"
    printf 'hounfour:\n  headless:\n    mode: cli-only\n' > "$BATS_TEST_TMPDIR/absent.yaml"
    for c in untrusted ancestor ancestor-alias boolTrue str absent; do
        case "$c" in
            untrusted) want="WARN: hounfour.headless.agy_opt_in: $BATS_TEST_TMPDIR/untrusted.yaml is world-writable (mode 0666) — a config others can write never opts in (own it and \`chmod go-w\` it); the agy route stays off" ;;
            ancestor) want="WARN: hounfour.headless is not a mapping (int) — hounfour.headless.agy_opt_in cannot be read through an alias or merge node (write the mapping inline); the agy route stays off"$'\n'"$avail" ;;
            ancestor-alias) want="WARN: hounfour is a YAML alias — hounfour.headless.agy_opt_in cannot be read through an alias or merge node (write the mapping inline); the agy route stays off"$'\n'"$avail" ;;
            boolTrue) want="WARN: hounfour.headless.agy_opt_in is True, a boolean spelled other than true/false — only \`agy_opt_in: true\` opts in (the lowercase scalar); the agy route stays off"$'\n'"$avail" ;;
            str) want="WARN: hounfour.headless.agy_opt_in is present but not a YAML boolean (str) — only \`agy_opt_in: true\` opts in (expected true or false); the agy route stays off"$'\n'"$avail" ;;
            absent) want="$avail" ;;
        esac
        got=$(env GOOGLE_API_KEY=x AGY_HEADLESS_BIN=no-such-agy bash -c 'source "$1"; agy_gate_warn_once "$2"; echo "rc=$?" >&2; agy_gate_warn_once "$2"' _ "$LIB" "$BATS_TEST_TMPDIR/$c.yaml" 2>&1 >/dev/null)
        [ "$got" = "$want"$'\n'"rc=0" ] || { printf 'case %s\n--- got\n%s\n--- want\n%s\n' "$c" "$got" "$want"$'\n'"rc=0"; return 1; }
    done
}
