#!/usr/bin/env bats
# =============================================================================
# session-cap-fanout.bats — cycle-117 Wave-2 item B (bd-c117-b-fanout-5ggb)
#
# Covers: jitter determinism (independently recomputed via sha256_portable),
# off-:00/:30 nudge property, register() success for every generated YAML,
# dry-run invoke (cycle.start only), full invoke vs stub contracts (7
# records incl. budget_pre_check field), install/uninstall against a
# stubbed crontab (marker-delimited, pre-existing lines untouched),
# enabled:false short-circuit, and the TZ= group + system-TZ reset shape.
#
# Never touches the operator's real crontab — a fake `crontab` shim on PATH
# backed by FAKE_CRONTAB_FILE intercepts every call.
# =============================================================================

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    SCRIPT="${REPO_ROOT}/.claude/scripts/session-cap-fanout.sh"
    LIB="${REPO_ROOT}/.claude/scripts/lib/scheduled-cycle-lib.sh"
    # shellcheck source=/dev/null
    source "${REPO_ROOT}/.claude/scripts/compat-lib.sh"

    TEST_DIR="$(mktemp -d)"
    SCHEDULES_DIR="${TEST_DIR}/schedules"
    CONFIG_FILE="${TEST_DIR}/session-cap.yaml"
    FAKE_CRONTAB_FILE="${TEST_DIR}/fake-crontab.txt"
    : > "$FAKE_CRONTAB_FILE"

    # Fake crontab shim — never touches the real crontab.
    mkdir -p "${TEST_DIR}/bin"
    cat > "${TEST_DIR}/bin/crontab" <<'SHIM'
#!/usr/bin/env bash
FILE="${FAKE_CRONTAB_FILE:?FAKE_CRONTAB_FILE not set}"
case "${1:-}" in
    -l)
        if [[ ! -s "$FILE" ]]; then
            echo "no crontab for $(whoami)" >&2
            exit 1
        fi
        cat "$FILE"
        ;;
    -)
        cat > "$FILE"
        ;;
    *)
        echo "fake crontab: unsupported args: $*" >&2
        exit 2
        ;;
esac
SHIM
    chmod +x "${TEST_DIR}/bin/crontab"

    export FAKE_CRONTAB_FILE
    export PATH="${TEST_DIR}/bin:${PATH}"
    export LOA_SESSION_CAP_CONFIG_FILE="$CONFIG_FILE"
    export LOA_SESSION_CAP_SCHEDULES_DIR="$SCHEDULES_DIR"
    unset LOA_AUDIT_SIGNING_KEY_ID
    export LOA_AUDIT_VERIFY_SIGS=0
    export REPO_ROOT SCRIPT LIB TEST_DIR SCHEDULES_DIR CONFIG_FILE
}

teardown() {
    rm -rf "$TEST_DIR"
}

# -----------------------------------------------------------------------------
# Jitter determinism — recompute independently via the same sha256_portable
# formula (never hardcode a magic minute that could silently drift).
# -----------------------------------------------------------------------------

_expected_offset() {
    local jitter_min="$1" h dec
    h="$(printf '%s' "$REPO_ROOT" | sha256_portable | awk '{print $1}' | cut -c1-8)"
    dec=$((16#$h))
    echo $(( (dec % jitter_min) + 1 ))
}

_expected_final_minute() {
    local base="$1" offset="$2" m
    m=$(( (base + offset) % 60 ))
    while (( m == 0 || m == 30 )); do
        m=$(( (m + 1) % 60 ))
    done
    echo "$m"
}

@test "jitter: _jitter_offset matches independently-recomputed sha256_portable formula" {
    local expected
    expected="$(_expected_offset 7)"
    run bash -c "source '$SCRIPT'; _jitter_offset 7"
    [ "$status" -eq 0 ]
    [ "$output" = "$expected" ]
}

@test "jitter: offset is always in [1, jitter_min], never 0" {
    for jm in 1 3 7 30 59; do
        run bash -c "source '$SCRIPT'; _jitter_offset $jm"
        [ "$status" -eq 0 ]
        [ "$output" -ge 1 ]
        [ "$output" -le "$jm" ]
    done
}

@test "jitter: _final_minute never lands on :00 or :30 across many base minutes" {
    for base in 0 1 15 28 29 30 31 45 58 59; do
        run bash -c "source '$SCRIPT'; _final_minute $base 2"
        [ "$status" -eq 0 ]
        [ "$output" -ne 0 ]
        [ "$output" -ne 30 ]
        local expected
        expected="$(_expected_final_minute "$base" 2)"
        [ "$output" = "$expected" ]
    done
}

@test "jitter: cron_jitter_min out-of-range or non-integer defaults to 7" {
    cat > "$CONFIG_FILE" <<'EOF'
session_cap:
  post_reset_fanout:
    cron_jitter_min: 0
EOF
    run bash -c "source '$SCRIPT'; read_cron_jitter_min"
    [ "$status" -eq 0 ]
    [ "$output" = "7" ]

    cat > "$CONFIG_FILE" <<'EOF'
session_cap:
  post_reset_fanout:
    cron_jitter_min: "not-a-number"
EOF
    run bash -c "source '$SCRIPT'; read_cron_jitter_min"
    [ "$status" -eq 0 ]
    [ "$output" = "7" ]

    cat > "$CONFIG_FILE" <<'EOF'
session_cap:
  post_reset_fanout:
    cron_jitter_min: 90
EOF
    run bash -c "source '$SCRIPT'; read_cron_jitter_min"
    [ "$status" -eq 0 ]
    [ "$output" = "7" ]
}

# -----------------------------------------------------------------------------
# register() success for every generated YAML
# -----------------------------------------------------------------------------

@test "install: generates a YAML per (window x phase) and registers every one" {
    cat > "$CONFIG_FILE" <<'EOF'
session_cap:
  reset_windows:
    - "02:00 Australia/Melbourne"
    - "14:37 UTC"
  post_reset_fanout:
    enabled: true
    phases:
      - flatline
      - bridgebuilder
    cron_jitter_min: 7
EOF
    run "$SCRIPT" install
    [ "$status" -eq 0 ]

    for f in "$SCHEDULES_DIR"/*.yaml; do
        [ -f "$f" ]
        run "$LIB" register "$f"
        [ "$status" -eq 0 ]
    done
    # 2 windows x 2 phases = 4 schedules
    run bash -c "ls '$SCHEDULES_DIR'/*.yaml | wc -l"
    [ "$output" -eq 4 ]
}

@test "install: default phases (flatline, bridgebuilder, red_team) apply when phases: omitted" {
    cat > "$CONFIG_FILE" <<'EOF'
session_cap:
  reset_windows:
    - "03:00 UTC"
  post_reset_fanout:
    enabled: true
EOF
    run "$SCRIPT" install
    [ "$status" -eq 0 ]
    [ -f "${SCHEDULES_DIR}/session-cap-fanout-w0-flatline.yaml" ]
    [ -f "${SCHEDULES_DIR}/session-cap-fanout-w0-bridgebuilder.yaml" ]
    [ -f "${SCHEDULES_DIR}/session-cap-fanout-w0-red_team.yaml" ]
}

# -----------------------------------------------------------------------------
# dry-run invoke (cycle.start only) + full invoke (7 records)
# -----------------------------------------------------------------------------

@test "AC: dry-run invoke against a generated schedule emits cycle.start only" {
    cat > "$CONFIG_FILE" <<'EOF'
session_cap:
  reset_windows:
    - "02:00 Australia/Melbourne"
  post_reset_fanout:
    enabled: true
    phases: [flatline]
EOF
    run "$SCRIPT" install
    [ "$status" -eq 0 ]

    local yaml="${SCHEDULES_DIR}/session-cap-fanout-w0-flatline.yaml"
    local cyclog="${TEST_DIR}/cycles.jsonl"
    local lockdir="${TEST_DIR}/lockdir"
    mkdir -p "$lockdir"

    export LOA_CYCLES_LOG="$cyclog" LOA_L3_LOCK_DIR="$lockdir" LOA_AUDIT_VERIFY_SIGS=0
    run "$LIB" invoke "$yaml" --cycle-id test-dry --dry-run
    [ "$status" -eq 0 ]

    run jq -sr '. | length' "$cyclog"
    [ "$output" = "1" ]
    run jq -sr '.[0].event_type' "$cyclog"
    [ "$output" = "cycle.start" ]
    # budget_pre_check field present (compose-when-available; null when L2 off)
    run jq -sr '.[0].payload | has("budget_pre_check")' "$cyclog"
    [ "$output" = "true" ]
}

@test "AC: full invoke against stub contracts produces 7 records incl. budget_pre_check field" {
    cat > "$CONFIG_FILE" <<'EOF'
session_cap:
  reset_windows:
    - "02:00 Australia/Melbourne"
  post_reset_fanout:
    enabled: true
    phases: [flatline]
EOF
    run "$SCRIPT" install
    [ "$status" -eq 0 ]

    local yaml="${SCHEDULES_DIR}/session-cap-fanout-w0-flatline.yaml"
    local cyclog="${TEST_DIR}/cycles-full.jsonl"
    local lockdir="${TEST_DIR}/lockdir-full"
    mkdir -p "$lockdir"

    export LOA_CYCLES_LOG="$cyclog" LOA_L3_LOCK_DIR="$lockdir" LOA_AUDIT_VERIFY_SIGS=0
    run "$LIB" invoke "$yaml" --cycle-id test-full
    [ "$status" -eq 0 ]

    run jq -sr '. | length' "$cyclog"
    [ "$output" = "7" ]
    run jq -sr '[.[] | select(.event_type == "cycle.complete")] | length' "$cyclog"
    [ "$output" = "1" ]
    run jq -sr '[.[] | select(.event_type == "cycle.phase")] | length' "$cyclog"
    [ "$output" = "5" ]
    run jq -sr '[.[] | select(.event_type == "cycle.start")][0].payload | has("budget_pre_check")' "$cyclog"
    [ "$output" = "true" ]
}

# -----------------------------------------------------------------------------
# install / uninstall against the stubbed crontab
# -----------------------------------------------------------------------------

@test "install: writes a marker-delimited crontab block, preserves unrelated lines" {
    printf 'unrelated-preexisting-line\n' > "$FAKE_CRONTAB_FILE"
    cat > "$CONFIG_FILE" <<'EOF'
session_cap:
  reset_windows:
    - "02:00 Australia/Melbourne"
  post_reset_fanout:
    enabled: true
    phases: [flatline]
EOF
    run "$SCRIPT" install
    [ "$status" -eq 0 ]

    run grep -qF 'unrelated-preexisting-line' "$FAKE_CRONTAB_FILE"
    [ "$status" -eq 0 ]
    run grep -qF '# loa-cycle117-session-cap-fanout BEGIN' "$FAKE_CRONTAB_FILE"
    [ "$status" -eq 0 ]
    run grep -qF '# loa-cycle117-session-cap-fanout END' "$FAKE_CRONTAB_FILE"
    [ "$status" -eq 0 ]
    run grep -c 'w0:flatline' "$FAKE_CRONTAB_FILE"
    [ "$output" -eq 1 ]
}

@test "uninstall: removes exactly its own marker block, leaves unrelated lines" {
    printf 'unrelated-preexisting-line\n' > "$FAKE_CRONTAB_FILE"
    cat > "$CONFIG_FILE" <<'EOF'
session_cap:
  reset_windows:
    - "02:00 Australia/Melbourne"
  post_reset_fanout:
    enabled: true
    phases: [flatline]
EOF
    run "$SCRIPT" install
    [ "$status" -eq 0 ]

    run "$SCRIPT" uninstall
    [ "$status" -eq 0 ]

    run grep -qF 'loa-cycle117-session-cap-fanout' "$FAKE_CRONTAB_FILE"
    [ "$status" -ne 0 ]
    run grep -qF 'unrelated-preexisting-line' "$FAKE_CRONTAB_FILE"
    [ "$status" -eq 0 ]
}

@test "uninstall: --off alias works identically" {
    cat > "$CONFIG_FILE" <<'EOF'
session_cap:
  reset_windows:
    - "02:00 UTC"
  post_reset_fanout:
    enabled: true
    phases: [flatline]
EOF
    run "$SCRIPT" install
    [ "$status" -eq 0 ]
    run "$SCRIPT" --off
    [ "$status" -eq 0 ]
    run grep -qF 'loa-cycle117-session-cap-fanout' "$FAKE_CRONTAB_FILE"
    [ "$status" -ne 0 ]
}

@test "uninstall: runs cleanly (exit 0) even when nothing is installed" {
    run "$SCRIPT" uninstall
    [ "$status" -eq 0 ]
}

@test "status: reflects INSTALLED / NOT-INSTALLED accurately" {
    run "$SCRIPT" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"NOT-INSTALLED"* ]]

    cat > "$CONFIG_FILE" <<'EOF'
session_cap:
  reset_windows:
    - "02:00 UTC"
  post_reset_fanout:
    enabled: true
    phases: [flatline]
EOF
    run "$SCRIPT" install
    [ "$status" -eq 0 ]

    run "$SCRIPT" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"INSTALLED"* ]]
}

@test "install: idempotent re-install replaces the block (no duplicate entries)" {
    cat > "$CONFIG_FILE" <<'EOF'
session_cap:
  reset_windows:
    - "02:00 UTC"
  post_reset_fanout:
    enabled: true
    phases: [flatline]
EOF
    run "$SCRIPT" install
    [ "$status" -eq 0 ]
    run "$SCRIPT" install
    [ "$status" -eq 0 ]

    run grep -c 'w0:flatline' "$FAKE_CRONTAB_FILE"
    [ "$output" -eq 1 ]
    run grep -c '# loa-cycle117-session-cap-fanout BEGIN' "$FAKE_CRONTAB_FILE"
    [ "$output" -eq 1 ]
}

# -----------------------------------------------------------------------------
# enabled:false short-circuit
# -----------------------------------------------------------------------------

@test "AC: enabled:false short-circuits install — no YAMLs, no crontab writes" {
    cat > "$CONFIG_FILE" <<'EOF'
session_cap:
  reset_windows:
    - "02:00 Australia/Melbourne"
  post_reset_fanout:
    enabled: false
EOF
    run "$SCRIPT" install
    [ "$status" -eq 0 ]
    [[ "$output" == *"not true"* ]]

    [ ! -d "$SCHEDULES_DIR" ]
    run grep -qF 'loa-cycle117-session-cap-fanout' "$FAKE_CRONTAB_FILE"
    [ "$status" -ne 0 ]
}

@test "install: empty reset_windows is a no-op, exit 0" {
    cat > "$CONFIG_FILE" <<'EOF'
session_cap:
  reset_windows: []
  post_reset_fanout:
    enabled: true
EOF
    run "$SCRIPT" install
    [ "$status" -eq 0 ]
    run grep -qF 'loa-cycle117-session-cap-fanout' "$FAKE_CRONTAB_FILE"
    [ "$status" -ne 0 ]
}

# -----------------------------------------------------------------------------
# --dry-run: zero side effects
# -----------------------------------------------------------------------------

@test "AC: install --dry-run writes nothing to schedules dir or crontab" {
    cat > "$CONFIG_FILE" <<'EOF'
session_cap:
  reset_windows:
    - "02:00 Australia/Melbourne"
  post_reset_fanout:
    enabled: true
    phases: [flatline]
EOF
    run "$SCRIPT" install --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"schedule_id: session-cap-fanout-w0-flatline"* ]]
    [[ "$output" == *"loa-cycle117-session-cap-fanout BEGIN"* ]]

    [ ! -d "$SCHEDULES_DIR" ]
    run grep -qF 'loa-cycle117-session-cap-fanout' "$FAKE_CRONTAB_FILE"
    [ "$status" -ne 0 ]
}

@test "show: prints YAMLs + crontab block without side effects, ignores enabled flag" {
    cat > "$CONFIG_FILE" <<'EOF'
session_cap:
  reset_windows:
    - "02:00 Australia/Melbourne"
  post_reset_fanout:
    enabled: false
    phases: [flatline]
EOF
    run "$SCRIPT" show
    [ "$status" -eq 0 ]
    [[ "$output" == *"schedule_id: session-cap-fanout-w0-flatline"* ]]

    [ ! -d "$SCHEDULES_DIR" ]
    run grep -qF 'loa-cycle117-session-cap-fanout' "$FAKE_CRONTAB_FILE"
    [ "$status" -ne 0 ]
}

# -----------------------------------------------------------------------------
# TZ= group lines + final system-TZ reset line
# -----------------------------------------------------------------------------

@test "AC: crontab block groups by TZ and ends with a system-TZ reset line" {
    cat > "$CONFIG_FILE" <<'EOF'
session_cap:
  reset_windows:
    - "02:00 Australia/Melbourne"
    - "14:37 UTC"
  post_reset_fanout:
    enabled: true
    phases: [flatline]
EOF
    run "$SCRIPT" install
    [ "$status" -eq 0 ]

    # Exactly one TZ=Australia/Melbourne and one TZ=UTC group line, plus the
    # final system-TZ reset (which on this host also happens to be a TZ=
    # line — so at least 2 distinct TZ= occurrences for the 2 window TZs).
    run grep -c '^TZ=Australia/Melbourne$' "$FAKE_CRONTAB_FILE"
    [ "$output" -ge 1 ]
    run grep -c '^TZ=UTC$' "$FAKE_CRONTAB_FILE"
    [ "$output" -ge 1 ]

    # The line immediately before the END marker must be a TZ= reset line
    # (last line of the managed block).
    run awk '/# loa-cycle117-session-cap-fanout END/{print prev} {prev=$0}' "$FAKE_CRONTAB_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == TZ=* ]]
}

@test "AC: v1 placeholder note appears in both install stdout and the crontab block" {
    cat > "$CONFIG_FILE" <<'EOF'
session_cap:
  reset_windows:
    - "02:00 UTC"
  post_reset_fanout:
    enabled: true
    phases: [flatline]
EOF
    run "$SCRIPT" install
    [ "$status" -eq 0 ]
    [[ "$output" == *"ARMED with placeholder phases"* ]]
    [[ "$output" == *"bd-fanout-real-dispatch-9jv6"* ]]

    run grep -qF 'ARMED with placeholder phases' "$FAKE_CRONTAB_FILE"
    [ "$status" -eq 0 ]
}
