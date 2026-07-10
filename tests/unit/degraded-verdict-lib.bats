#!/usr/bin/env bats
# =============================================================================
# tests/unit/degraded-verdict-lib.bats
#
# cycle-117 item D (#1177) — direct unit tests of the shared
# degraded-verdict-lib.sh helper (degraded_verdict_emit /
# degraded_verdict_maybe_emit). Every test installs a fresh copy of the lib
# (+ push-notify-lib.sh where needed) under an isolated fake project root
# ($BATS_TMP/.claude/scripts/lib/...) so PROJECT_ROOT resolution (derived
# from BASH_SOURCE[0]) never touches the real repo's
# grimoires/loa/a2a/trajectory/ — mirrors the isolation pattern in
# post-pr-bridgebuilder.bats.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    LIB_SRC="$PROJECT_ROOT/.claude/scripts/lib/degraded-verdict-lib.sh"
    PUSH_LIB_SRC="$PROJECT_ROOT/.claude/scripts/lib/push-notify-lib.sh"
    [[ -f "$LIB_SRC" ]] || skip "degraded-verdict-lib.sh not found (pre-implementation)"

    BATS_TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/dvl.XXXXXX")"
    FAKE_ROOT="$BATS_TMP/fake-root"
    mkdir -p "$FAKE_ROOT/.claude/scripts/lib"
    cp "$LIB_SRC" "$FAKE_ROOT/.claude/scripts/lib/"
    [[ -f "$PUSH_LIB_SRC" ]] && cp "$PUSH_LIB_SRC" "$FAKE_ROOT/.claude/scripts/lib/"
}

teardown() {
    rm -rf "$BATS_TMP" 2>/dev/null || true
}

_traj_dir() {
    echo "$FAKE_ROOT/grimoires/loa/a2a/trajectory"
}

_traj_glob() {
    echo "$(_traj_dir)/degraded-verdict-"*.jsonl
}

# =============================================================================
# DVL1: DEGRADED band writes exactly one jsonl line matching the schema
# =============================================================================

@test "DVL1: DEGRADED band writes exactly one trajectory record" {
    cd "$FAKE_ROOT"
    run bash -c '
        source .claude/scripts/lib/degraded-verdict-lib.sh
        degraded_verdict_maybe_emit "adversarial-review:audit" "DEGRADED" "api_failure" "sprint-1" "3" "gpt-5.5-pro"
    '
    [ "$status" -eq 0 ]
    local f
    f=$(_traj_glob)
    [ -f "$f" ]
    [ "$(wc -l < "$f")" -eq 1 ]
    [ "$(jq -r '.gate' "$f")" = "adversarial-review:audit" ]
    [ "$(jq -r '.verdict_band' "$f")" = "DEGRADED" ]
    [ "$(jq -r '.degradation_reason' "$f")" = "api_failure" ]
    [ "$(jq -r '.sprint_id' "$f")" = "sprint-1" ]
    [ "$(jq -r '.model_exit_code' "$f")" = "3" ]
    [ "$(jq -c '.degraded_legs' "$f")" = '["gpt-5.5-pro"]' ]
    [ -n "$(jq -r '.ts' "$f")" ]
}

# =============================================================================
# DVL2: FAILED band writes exactly one jsonl line
# =============================================================================

@test "DVL2: FAILED band writes exactly one trajectory record" {
    cd "$FAKE_ROOT"
    run bash -c '
        source .claude/scripts/lib/degraded-verdict-lib.sh
        degraded_verdict_maybe_emit "red-team:code-vs-design" "FAILED" "model_invocation_failed" "sprint-2" "12" "opus"
    '
    [ "$status" -eq 0 ]
    local f
    f=$(_traj_glob)
    [ -f "$f" ]
    [ "$(wc -l < "$f")" -eq 1 ]
    [ "$(jq -r '.verdict_band' "$f")" = "FAILED" ]
}

# =============================================================================
# DVL3/4: APPROVED / UNKNOWN bands write nothing
# =============================================================================

@test "DVL3: APPROVED band writes no trajectory record" {
    cd "$FAKE_ROOT"
    run bash -c '
        source .claude/scripts/lib/degraded-verdict-lib.sh
        degraded_verdict_maybe_emit "adversarial-review:audit" "APPROVED" "n/a" "sprint-3" "-"
    '
    [ "$status" -eq 0 ]
    [ ! -d "$(_traj_dir)" ] || [ -z "$(ls "$(_traj_dir)" 2>/dev/null)" ]
}

@test "DVL4: UNKNOWN band writes no trajectory record" {
    cd "$FAKE_ROOT"
    run bash -c '
        source .claude/scripts/lib/degraded-verdict-lib.sh
        degraded_verdict_maybe_emit "flatline:prd" "UNKNOWN" "n/a" "prd" "-"
    '
    [ "$status" -eq 0 ]
    [ ! -d "$(_traj_dir)" ] || [ -z "$(ls "$(_traj_dir)" 2>/dev/null)" ]
}

# =============================================================================
# DVL5/6: push_notify is called exactly once for DEGRADED, zero times for
# APPROVED/UNKNOWN. Stubbed AFTER sourcing — bash resolves functions at call
# time, so the stub (defined after source) wins over the lib's real
# push-notify-lib.sh definition.
# =============================================================================

@test "DVL5: DEGRADED band calls a stubbed push_notify exactly once" {
    cd "$FAKE_ROOT"
    run bash -c '
        source .claude/scripts/lib/degraded-verdict-lib.sh
        push_notify() { echo "PUSH|$1|$2|$3|$4" >> pushlog.txt; return 0; }
        degraded_verdict_maybe_emit "adversarial-review:review" "DEGRADED" "api_failure" "sprint-5" "3" "gpt-5.5-pro"
        [[ -f pushlog.txt ]] && wc -l < pushlog.txt || echo 0
    '
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | tail -1 | tr -d '[:space:]')" = "1" ]
}

@test "DVL6: APPROVED band calls a stubbed push_notify zero times" {
    cd "$FAKE_ROOT"
    run bash -c '
        source .claude/scripts/lib/degraded-verdict-lib.sh
        push_notify() { echo "PUSH|$1|$2|$3|$4" >> pushlog.txt; return 0; }
        degraded_verdict_maybe_emit "adversarial-review:review" "APPROVED" "n/a" "sprint-6" "-"
        [[ -f pushlog.txt ]] && wc -l < pushlog.txt || echo 0
    '
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | tail -1 | tr -d '[:space:]')" = "0" ]
}

# =============================================================================
# DVL7: push_notify unavailable (lib file absent) -> fail-soft stderr skip,
# never a non-zero exit or thrown error.
# =============================================================================

@test "DVL7: missing push-notify-lib.sh fails soft (stderr skip line, exit 0)" {
    local bare_root="$BATS_TMP/bare-root"
    mkdir -p "$bare_root/.claude/scripts/lib"
    cp "$LIB_SRC" "$bare_root/.claude/scripts/lib/"
    cd "$bare_root"
    run bash -c '
        source .claude/scripts/lib/degraded-verdict-lib.sh
        degraded_verdict_maybe_emit "red-team:code-vs-design" "DEGRADED" "model_invocation_failed" "sprint-7" "12" "opus"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"push skipped"* || "$output" == *"push_notify unavailable"* ]]
    local f
    f="$bare_root/grimoires/loa/a2a/trajectory/degraded-verdict-"*.jsonl
    [ -f $f ]
}

# =============================================================================
# DVL8: model_exit_code "-" sentinel -> null in the record
# =============================================================================

@test "DVL8: model_exit_code '-' sentinel emits null" {
    cd "$FAKE_ROOT"
    run bash -c '
        source .claude/scripts/lib/degraded-verdict-lib.sh
        degraded_verdict_maybe_emit "flatline:sdd" "DEGRADED" "empty_or_invalid_model_output" "sdd" "-" "gemini-3.1-pro"
    '
    [ "$status" -eq 0 ]
    local f
    f=$(_traj_glob)
    [ "$(jq -r '.model_exit_code' "$f")" = "null" ]
}

# =============================================================================
# DVL9: no leg args -> degraded_legs key omitted entirely (schema forbids [])
# =============================================================================

@test "DVL9: no leg args omits degraded_legs from the record" {
    cd "$FAKE_ROOT"
    run bash -c '
        source .claude/scripts/lib/degraded-verdict-lib.sh
        degraded_verdict_maybe_emit "flatline:sprint" "FAILED" "unknown" "sprint" "-"
    '
    [ "$status" -eq 0 ]
    local f
    f=$(_traj_glob)
    [ "$(jq 'has("degraded_legs")' "$f")" = "false" ]
}

# =============================================================================
# DVL10: concurrent-append safety smoke test — N parallel DEGRADED emits
# produce exactly N well-formed jsonl lines (no interleaved partial lines).
# =============================================================================

@test "DVL10: concurrent appends produce N well-formed lines (flock smoke test)" {
    command -v flock >/dev/null 2>&1 || skip "flock not available"
    cd "$FAKE_ROOT"
    local n=8
    local i
    for ((i = 0; i < n; i++)); do
        bash -c '
            source .claude/scripts/lib/degraded-verdict-lib.sh
            degraded_verdict_maybe_emit "adversarial-review:audit" "DEGRADED" "api_failure" "sprint-concurrent" "1" "voice-'"$i"'"
        ' &
    done
    wait
    local f
    f=$(_traj_glob)
    [ -f "$f" ]
    [ "$(wc -l < "$f")" -eq "$n" ]
    # Every line must be valid JSON (no torn/interleaved writes).
    while IFS= read -r line; do
        echo "$line" | jq -e . >/dev/null
    done < "$f"
}
