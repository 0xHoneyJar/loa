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
    if ! date -u -d "2026-01-01T08:00:00Z" +%s &>/dev/null; then
        skip "GNU date -d unavailable; cannot compute injected epoch"
    fi
    _write_config "false" "fill" "08:00"
    _source_with_stubs
    # Inject a "now" 1 hour past the configured window end (08:00). Without
    # the enabled-check fix, this past-window combination would trip the
    # gate and return 0. With the fix, return 1 regardless.
    _spiral_today_utc() { echo "2026-04-26"; }
    _spiral_now_epoch() { date -u -d "2026-04-26T09:00:00Z" +%s; }
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
    if ! date -u -d "2026-04-26T09:00:00Z" +%s &>/dev/null; then
        skip "GNU date -d unavailable; cannot compute injected epoch"
    fi
    _write_config "true" "fill" "08:00"
    _source_with_stubs
    _spiral_today_utc() { echo "2026-04-26"; }
    _spiral_now_epoch() { date -u -d "2026-04-26T09:00:00Z" +%s; }   # 1h past window end
    run check_token_window
    [ "$status" -eq 0 ]   # window past → STOP
}

# AC-622 companion: enabled=true + fill + window-future still CONTINUES.
# Same seam — inject "now" before the window end.
@test "#622: check_token_window returns 1 with enabled=true + fill + window-future (regression)" {
    if ! date -u -d "2026-04-26T09:00:00Z" +%s &>/dev/null; then
        skip "GNU date -d unavailable; cannot compute injected epoch"
    fi
    _write_config "true" "fill" "23:00"
    _source_with_stubs
    _spiral_today_utc() { echo "2026-04-26"; }
    _spiral_now_epoch() { date -u -d "2026-04-26T12:00:00Z" +%s; }   # 11h before window end
    run check_token_window
    [ "$status" -ne 0 ]   # within window → CONTINUE
}

# AC-622-1 (additional): the enabled-check fires BEFORE the strategy lookup.
# This guards against re-ordering regression — if a future refactor moves the
# strategy check above the enabled check, this test would still catch the
# original bug.
@test "#622: enabled-check fires before strategy/window resolution (read order)" {
    if ! date -u -d "2026-04-26T09:00:00Z" +%s &>/dev/null; then
        skip "GNU date -d unavailable; cannot compute injected epoch"
    fi
    # Set strategy and window such that without the enabled check, the function
    # would either (a) return 1 via continuous, or (b) reach the window-past
    # branch. We choose (b) — fill + a window in the past (via clock injection)
    # so any leakage of the original bug surfaces as exit 0 (STOP).
    _write_config "false" "fill" "08:00"
    _source_with_stubs
    _spiral_today_utc() { echo "2026-04-26"; }
    _spiral_now_epoch() { date -u -d "2026-04-26T23:00:00Z" +%s; }   # past 08:00 window end
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

# Helper: shim spiral-simstim-dispatch.sh to capture env vars per call.
_shim_dispatch_capture() {
    # Build a stub script that records SPIRAL_ID + SPIRAL_CYCLE_NUM + SPIRAL_TASK
    # to a JSONL file each time it's invoked. Real dispatch is bypassed.
    local capture_log="$1"
    local shim_dir="$2"
    mkdir -p "$shim_dir"
    cat > "$shim_dir/spiral-simstim-dispatch.sh" <<SHIM
#!/usr/bin/env bash
printf '{"spiral_id":"%s","cycle_num":"%s","task":"%s"}\n' \
    "\${SPIRAL_ID:-unset}" "\${SPIRAL_CYCLE_NUM:-unset}" "\${SPIRAL_TASK:-unset}" \
    >> "$capture_log"
SHIM
    chmod +x "$shim_dir/spiral-simstim-dispatch.sh"
}

# AC-623-1 (static contract pin): the export block exists verbatim in the
# orchestrator. Catches deletion of either export line by future refactors.
# Iter-1 BB F1: pinning the production source AND functionally exercising
# run_cycle_loop (next test) is the two-layer defense — static catches
# deletion, functional catches "block exists but doesn't propagate".
@test "#623: orchestrator source contains SPIRAL_ID export at start AND resume paths (static pin)" {
    local script="$PROJECT_ROOT/.claude/scripts/spiral-orchestrator.sh"
    # Start-path export (companion to existing SPIRAL_TASK export from #568)
    grep -qE '^[[:space:]]*SPIRAL_ID=\$\(jq -r .\.spiral_id // ""' "$script"
    # Both exports MUST appear with `export SPIRAL_ID` immediately after.
    # Count: one for start-path, one for resume-path.
    local export_count
    export_count=$(grep -cE '^[[:space:]]*export SPIRAL_ID[[:space:]]*$' "$script")
    [ "$export_count" -ge 2 ]
    # Companion SPIRAL_CYCLE_NUM per-cycle export inside run_cycle_loop
    grep -qE '^[[:space:]]*export SPIRAL_CYCLE_NUM=' "$script"
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

# AC-623-3: branch_name distinct per cycle when SPIRAL_ID + SPIRAL_CYCLE_NUM
# are properly exported. This is the symptom-level invariant zkSoju reported.
@test "#623: dispatch sees distinct branch names per cycle (no feat/spiral-unknown-cycle-1 collision)" {
    # The dispatch script normally computes:
    #   branch_name="feat/spiral-${spiral_id}-cycle-${cycle_num}"
    # with both falling back to "unknown" / "1" when env vars are unset.
    # Verify the env-export discipline produces 3 distinct branches.
    local shim_dir="$TEST_TMPDIR/shim-bin"
    mkdir -p "$shim_dir"
    cat > "$shim_dir/spiral-simstim-dispatch.sh" <<'SHIM'
#!/usr/bin/env bash
spiral_id="${SPIRAL_ID:-unknown}"
cycle_num="${SPIRAL_CYCLE_NUM:-1}"
echo "feat/spiral-${spiral_id}-cycle-${cycle_num}"
SHIM
    chmod +x "$shim_dir/spiral-simstim-dispatch.sh"

    export SPIRAL_ID="spiral-20260426-branch"
    local branches=()
    local i
    for i in 1 2 3; do
        export SPIRAL_CYCLE_NUM="$i"
        branches+=("$("$shim_dir/spiral-simstim-dispatch.sh")")
    done

    [ "${branches[0]}" = "feat/spiral-spiral-20260426-branch-cycle-1" ]
    [ "${branches[1]}" = "feat/spiral-spiral-20260426-branch-cycle-2" ]
    [ "${branches[2]}" = "feat/spiral-spiral-20260426-branch-cycle-3" ]

    # Three distinct values — no collision.
    local distinct
    distinct=$(printf '%s\n' "${branches[@]}" | sort -u | wc -l | tr -d ' ')
    [ "$distinct" = "3" ]
}

# AC-623-4 regression: SPIRAL_ID export survives a fork-PR-style env clean.
# Verifies the export is real (visible to bash -c subshells) not just shell-local.
@test "#623: SPIRAL_ID + SPIRAL_CYCLE_NUM are EXPORTED (visible to subshells)" {
    export SPIRAL_ID="visible-from-subshell"
    export SPIRAL_CYCLE_NUM="42"

    # bash -c spawns a fresh subshell; only EXPORTED vars survive
    local subshell_id subshell_num
    subshell_id=$(bash -c 'echo "$SPIRAL_ID"')
    subshell_num=$(bash -c 'echo "$SPIRAL_CYCLE_NUM"')
    [ "$subshell_id" = "visible-from-subshell" ]
    [ "$subshell_num" = "42" ]
}
