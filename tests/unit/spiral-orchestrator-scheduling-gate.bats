#!/usr/bin/env bats
# =============================================================================
# Tests for spiral-orchestrator.sh — sprint-bug-622-623
# =============================================================================
# Closes:
#   #622 — check_token_window doesn't gate on spiral.scheduling.enabled
#   #623 — SPIRAL_ID + SPIRAL_CYCLE_NUM not exported per cycle
#
# These bugs were reported by zkSoju with full repro + suggested fixes.
# Tests source the REAL orchestrator (main-guard prevents execution on source).
# =============================================================================

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    ORCHESTRATOR="$PROJECT_ROOT/.claude/scripts/spiral-orchestrator.sh"
    TEST_TMPDIR="$(mktemp -d)"

    # Hermetic config + state file paths
    CONFIG="$TEST_TMPDIR/loa.config.yaml"
    STATE_FILE="$TEST_TMPDIR/spiral-state.json"
    export CONFIG STATE_FILE PROJECT_ROOT

    # Iter-2 BB F3/F-001 fix: hardcoded epoch constants for clock injection.
    # Pre-cycle-094 these tests used `date -u -d "<iso>" +%s` which is GNU-only;
    # macOS BSD date silently skipped, weakening regression coverage on dev
    # machines. Hardcoding the epochs makes the tests fully portable and
    # eliminates the GNU-date dependency. Values computed once via:
    #   date -u -d "2026-04-26T08:00:00Z" +%s  → 1777190400 (window-end 08:00)
    #   date -u -d "2026-04-26T09:00:00Z" +%s  → 1777194000 (1h past 08:00)
    #   date -u -d "2026-04-26T12:00:00Z" +%s  → 1777204800 (4h past 08:00)
    #   date -u -d "2026-04-26T23:00:00Z" +%s  → 1777244400 (15h past 08:00)
    EPOCH_2026_04_26_08_00_UTC=1777190400
    EPOCH_2026_04_26_09_00_UTC=1777194000
    EPOCH_2026_04_26_12_00_UTC=1777204800
    EPOCH_2026_04_26_23_00_UTC=1777244400

    # Stubs the orchestrator's read_config will look for
    # (the real read_config reads .loa.config.yaml; we override the path
    # via $CONFIG and re-define read_config in the sourced shell)
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

# Helper: write a config file with the requested scheduling shape.
_write_config() {
    local enabled="$1"          # spiral.scheduling.enabled
    local strategy="$2"         # spiral.scheduling.strategy
    local end_utc="$3"          # spiral.scheduling.windows[0].end_utc (empty = no window)
    cat > "$CONFIG" <<YAML
spiral:
  enabled: true
  scheduling:
    enabled: $enabled
    strategy: $strategy
YAML
    if [[ -n "$end_utc" ]]; then
        cat >> "$CONFIG" <<YAML
    windows:
      - start_utc: "00:00"
        end_utc: "$end_utc"
YAML
    fi
}

# Helper: source orchestrator with stubbed dependencies for direct
# function-level tests of check_token_window.
_source_with_stubs() {
    # Re-define read_config to read from $CONFIG instead of .loa.config.yaml.
    # The orchestrator's own read_config helper takes (key, default) and reads
    # .loa.config.yaml at $LOA_CONFIG. Override it after sourcing.
    # shellcheck disable=SC1090
    source "$ORCHESTRATOR"

    # Override read_config to use our test config
    read_config() {
        local key="$1" default="${2:-}"
        local value
        value=$(yq eval ".$key // null" "$CONFIG" 2>/dev/null || echo "null")
        [[ "$value" == "null" || -z "$value" ]] && { echo "$default"; return 0; }
        echo "$value"
    }
    # Suppress logging side effects
    log() { :; }
    log_trajectory() { :; }
}

# =============================================================================
# #622 — check_token_window honors spiral.scheduling.enabled
# =============================================================================

# AC-622-1: enabled=false short-circuits, regardless of window state.
# Iter-1 BB F2 fix: use the clock-injection seam (_spiral_now_epoch /
# _spiral_today_utc) to pin a deterministic "after-the-window-end" time
# instead of depending on wall-clock + skip-if-edge.
@test "#622: check_token_window returns 1 (continue) when scheduling.enabled=false (default)" {
    _write_config "false" "fill" "08:00"
    _source_with_stubs
    # Inject a "now" 1 hour past the configured window end (08:00). Without
    # the enabled-check fix, this past-window combination would trip the
    # gate and return 0. With the fix, return 1 regardless.
    _spiral_today_utc() { echo "2026-04-26"; }
    _spiral_now_epoch() { echo 1777194000; }   # 09:00 UTC, 1h past 08:00 window end
    run check_token_window
    [ "$status" -ne 0 ]   # return 1 = continue, NOT stop
}

# AC-622-1: explicit no-window also short-circuits when disabled
@test "#622: check_token_window returns 1 when scheduling.enabled=false even with no window configured" {
    _write_config "false" "fill" ""
    _source_with_stubs
    run check_token_window
    [ "$status" -ne 0 ]
}

# AC-622-2 regression: continuous strategy still short-circuits (no regression)
@test "#622: check_token_window returns 1 with enabled=true + strategy=continuous (regression)" {
    _write_config "true" "continuous" "08:00"
    _source_with_stubs
    run check_token_window
    [ "$status" -ne 0 ]   # continuous always returns 1
}

# AC-622-3 regression: enabled=true + fill + window-past still STOPS (no regression).
# Iter-1 BB F2 fix: use clock-injection seam — pin the test against an
# injected "now" past the window end. Eliminates the wall-clock skip path.
@test "#622: check_token_window returns 0 with enabled=true + fill + window-past (regression)" {
    _write_config "true" "fill" "08:00"
    _source_with_stubs
    _spiral_today_utc() { echo "2026-04-26"; }
    _spiral_now_epoch() { echo 1777194000; }   # 09:00 UTC, 1h past 08:00 window end
    run check_token_window
    [ "$status" -eq 0 ]   # window past → STOP
}

# AC-622 companion: enabled=true + fill + window-future still CONTINUES.
# Same seam — inject "now" before the window end.
@test "#622: check_token_window returns 1 with enabled=true + fill + window-future (regression)" {
    _write_config "true" "fill" "23:00"
    _source_with_stubs
    _spiral_today_utc() { echo "2026-04-26"; }
    _spiral_now_epoch() { echo 1777204800; }   # 12:00 UTC, 11h before 23:00 window end
    run check_token_window
    [ "$status" -ne 0 ]   # within window → CONTINUE
}

# AC-622-1 (additional): the enabled-check fires BEFORE the strategy lookup.
# This guards against re-ordering regression — if a future refactor moves the
# strategy check above the enabled check, this test would still catch the
# original bug.
@test "#622: enabled-check fires before strategy/window resolution (read order)" {
    # Set strategy and window such that without the enabled check, the function
    # would either (a) return 1 via continuous, or (b) reach the window-past
    # branch. We choose (b) — fill + a window in the past (via clock injection)
    # so any leakage of the original bug surfaces as exit 0 (STOP).
    _write_config "false" "fill" "08:00"
    _source_with_stubs
    _spiral_today_utc() { echo "2026-04-26"; }
    _spiral_now_epoch() { echo 1777244400; }   # 23:00 UTC, 15h past 08:00 window end
    run check_token_window
    [ "$status" -ne 0 ]   # enabled-gate must short-circuit BEFORE the date logic
}

# =============================================================================
# #623 — SPIRAL_ID + SPIRAL_CYCLE_NUM exported per cycle
# =============================================================================
#
# Strategy: source the orchestrator, init state, then verify the env vars
# are exported by walking the dispatch path. We use a stub
# spiral-simstim-dispatch.sh that captures the env and writes it to a file
# we can inspect — same pattern as the existing #568 SPIRAL_TASK fix.
# =============================================================================

# AC-623-1 (static contract pin, iter-3 BB F-002 fix): the export lines must
# live INSIDE the right functions, not in dead code or unrelated scopes.
# Iter-1 BB F1: pinning the production source AND functionally exercising
# run_cycle_loop (next test) is the two-layer defense — static catches
# deletion, functional catches "block exists but doesn't propagate".
# Iter-2 BB F4: assert intent (assignment + export) over literal jq tokens.
# Iter-3 BB F-002: previous version ran grep over the whole file, so an
# export accidentally moved to a dead helper would still pass. Now we use
# awk to extract each function body and assert the export occurs WITHIN
# its scope. Closes the "fire extinguisher in the closet" failure mode.
_extract_fn() {
    # Print body of function "$1" from "$2", from `<name>() {` line through
    # the matching closing `}` at column 0. Bash convention in this
    # orchestrator: every top-level function uses that exact closing form.
    awk -v fn="$1" '
        $0 ~ "^"fn"\\(\\) \\{" { in_fn = 1 }
        in_fn { print }
        in_fn && /^\}$/ { exit }
    ' "$2"
}

@test "#623: SPIRAL_ID + SPIRAL_CYCLE_NUM exports anchored within correct functions (static pin)" {
    local script="$PROJECT_ROOT/.claude/scripts/spiral-orchestrator.sh"

    # cmd_start MUST contain both the SPIRAL_ID assignment AND export
    local start_body
    start_body=$(_extract_fn "cmd_start" "$script")
    [ -n "$start_body" ]
    echo "$start_body" | grep -qE '^[[:space:]]*SPIRAL_ID='
    echo "$start_body" | grep -qE '^[[:space:]]*export SPIRAL_ID[[:space:]]*$'

    # cmd_resume MUST contain both the SPIRAL_ID assignment AND export
    local resume_body
    resume_body=$(_extract_fn "cmd_resume" "$script")
    [ -n "$resume_body" ]
    echo "$resume_body" | grep -qE '^[[:space:]]*SPIRAL_ID='
    echo "$resume_body" | grep -qE '^[[:space:]]*export SPIRAL_ID[[:space:]]*$'

    # run_cycle_loop MUST contain the per-cycle SPIRAL_CYCLE_NUM export
    local loop_body
    loop_body=$(_extract_fn "run_cycle_loop" "$script")
    [ -n "$loop_body" ]
    echo "$loop_body" | grep -qE '^[[:space:]]*export SPIRAL_CYCLE_NUM='
}

# AC-623-2 (functional, iter-1 BB F1 fix): invoke the REAL run_cycle_loop
# with run_single_cycle stubbed to a no-op that captures env vars. This
# exercises the production export-per-cycle code path instead of reproducing
# it inline in the test.
@test "#623: run_cycle_loop exports SPIRAL_CYCLE_NUM per cycle (functional, exercises production code)" {
    local capture_log="$TEST_TMPDIR/cycle-capture.jsonl"
    : > "$capture_log"

    # Pre-state: the orchestrator's run_cycle_loop reads max_cycles from STATE_FILE.
    local test_state_file="$STATE_FILE"
    cat > "$test_state_file" <<'JSON'
{
  "spiral_id": "spiral-functional-1",
  "task": "functional test",
  "state": "RUNNING",
  "phase": "SEED",
  "max_cycles": 3,
  "cycle_index": 0,
  "cycles": []
}
JSON

    _source_with_stubs
    STATE_FILE="$test_state_file"

    # Stub run_single_cycle to capture the env vars at call-site and return
    # an empty stop_reason / cycle_dir pair (so the loop continues until
    # max_cycles). This is the seam: run_cycle_loop is the function being
    # tested; everything inside run_single_cycle is irrelevant for this AC.
    run_single_cycle() {
        printf '{"i_arg":"%s","cycle_num_env":"%s","spiral_id_env":"%s","task_env":"%s"}\n' \
            "$1" "${SPIRAL_CYCLE_NUM:-unset}" "${SPIRAL_ID:-unset}" "${SPIRAL_TASK:-unset}" \
            >> "$capture_log"
        # Two-line output: empty stop_reason on line 1, cycle_dir on line 2
        echo ""
        echo "$TEST_TMPDIR/dummy-cycle-$1"
    }
    coalesce_spiral_terminal_state() { :; }   # stub the terminal state hook

    # Set the upstream exports the way cmd_start would (we test that
    # run_cycle_loop *propagates* SPIRAL_CYCLE_NUM each iteration).
    export SPIRAL_ID="spiral-functional-1"
    export SPIRAL_TASK="functional test"
    unset SPIRAL_CYCLE_NUM

    run_cycle_loop

    # 3 entries captured (one per cycle)
    [ "$(wc -l < "$capture_log")" = "3" ]
    # cycle_num env var increments 1, 2, 3 — proves run_cycle_loop performed the export
    [ "$(jq -r '.cycle_num_env' < "$capture_log" | sed -n '1p')" = "1" ]
    [ "$(jq -r '.cycle_num_env' < "$capture_log" | sed -n '2p')" = "2" ]
    [ "$(jq -r '.cycle_num_env' < "$capture_log" | sed -n '3p')" = "3" ]
    # The i argument matches the env var (proves the export tracks the loop counter)
    [ "$(jq -r '.i_arg' < "$capture_log" | sed -n '1p')" = "1" ]
    [ "$(jq -r '.i_arg' < "$capture_log" | sed -n '2p')" = "2" ]
    [ "$(jq -r '.i_arg' < "$capture_log" | sed -n '3p')" = "3" ]
    # SPIRAL_ID + SPIRAL_TASK survive across cycles
    local distinct_ids distinct_tasks
    distinct_ids=$(jq -r '.spiral_id_env' < "$capture_log" | sort -u)
    distinct_tasks=$(jq -r '.task_env' < "$capture_log" | sort -u)
    [ "$distinct_ids" = "spiral-functional-1" ]
    [ "$distinct_tasks" = "functional test" ]
}

# Iter-2 BB F-003 + F5 (Amazon "Bar Raiser"-style cleanup): the pre-iter-2
# AC-623-3 ("dispatch sees distinct branch names") and AC-623-4 ("vars are
# EXPORTED visible to subshells") were testing bash language semantics +
# a hand-rolled shim, not orchestrator code. AC-623-2 (functional, exercises
# run_cycle_loop directly) and AC-623-1 (static pin on the export lines)
# already cover both the structural and behavioral contract. Removed.
# The unused _shim_dispatch_capture helper was deleted with them.
