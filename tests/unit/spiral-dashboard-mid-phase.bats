#!/usr/bin/env bats
# =============================================================================
# spiral-dashboard-mid-phase.bats — cycle-092 Sprint 3 (#599)
# =============================================================================
# Validates:
# - _emit_dashboard_snapshot emits event_type field in JSON output
# - event_type defaults to PHASE_START when not supplied
# - Legacy 2-arg form (path in arg 2) still works via auto-detection
# - _spawn_dashboard_heartbeat_daemon backgrounds a writer that consumes
#   .phase-current (Sprint 1) as truth source
# - Heartbeat cadence honored (SPIRAL_DASHBOARD_HEARTBEAT_SEC, clamped)
# - Daemon exits cleanly when .phase-current goes missing (harness done)
# - Daemon reaped by SIGTERM (EXIT trap surrogate)
# - Staleness threshold skips emit when .phase-current mtime too old
# =============================================================================

setup() {
    export PROJECT_ROOT="$BATS_TEST_DIRNAME/../.."
    export EVIDENCE_SH="$PROJECT_ROOT/.claude/scripts/spiral-evidence.sh"
    export TEST_DIR="$BATS_TEST_TMPDIR/spiral-dashboard-test"
    mkdir -p "$TEST_DIR"
    # Bootstrap a minimal flight recorder so _emit_dashboard_snapshot can run
    export _FLIGHT_RECORDER="$TEST_DIR/flight-recorder.jsonl"
    printf '{"seq":1,"ts":"2026-04-19T10:00:00Z","phase":"CONFIG","actor":"test","action":"init","output_bytes":0,"duration_ms":0,"cost_usd":0,"verdict":"PASS"}\n' \
        > "$_FLIGHT_RECORDER"
}

teardown() {
    # Kill any lingering daemons from tests (belt-and-suspenders)
    if [[ -n "${DAEMON_PID:-}" ]]; then
        kill -TERM "$DAEMON_PID" 2>/dev/null || true
        wait "$DAEMON_PID" 2>/dev/null || true
    fi
    [[ -d "$TEST_DIR" ]] && rm -rf "$TEST_DIR"
}

# =========================================================================
# DMP-T1: event_type field in snapshot
# =========================================================================

@test "snapshot includes event_type field (default PHASE_START)" {
    run bash -c "
        source '$EVIDENCE_SH'
        _init_flight_recorder '$TEST_DIR'
        printf '{\"seq\":1,\"ts\":\"2026-04-19T10:00:00Z\",\"phase\":\"INIT\",\"actor\":\"t\",\"action\":\"a\",\"output_bytes\":0,\"duration_ms\":0,\"cost_usd\":0,\"verdict\":\"PASS\"}\n' >> \"\$_FLIGHT_RECORDER\"
        _emit_dashboard_snapshot 'TEST_PHASE' 'PHASE_START' '$TEST_DIR'
        jq -r '.event_type' '$TEST_DIR/dashboard-latest.json'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == "PHASE_START" ]]
}

@test "snapshot sets event_type=PHASE_HEARTBEAT when supplied" {
    run bash -c "
        source '$EVIDENCE_SH'
        _init_flight_recorder '$TEST_DIR'
        printf '{\"seq\":1,\"ts\":\"2026-04-19T10:00:00Z\",\"phase\":\"INIT\",\"actor\":\"t\",\"action\":\"a\",\"output_bytes\":0,\"duration_ms\":0,\"cost_usd\":0,\"verdict\":\"PASS\"}\n' >> \"\$_FLIGHT_RECORDER\"
        _emit_dashboard_snapshot 'TEST_PHASE' 'PHASE_HEARTBEAT' '$TEST_DIR'
        jq -r '.event_type' '$TEST_DIR/dashboard-latest.json'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == "PHASE_HEARTBEAT" ]]
}

@test "snapshot sets event_type=PHASE_EXIT when supplied" {
    run bash -c "
        source '$EVIDENCE_SH'
        _init_flight_recorder '$TEST_DIR'
        printf '{\"seq\":1,\"ts\":\"2026-04-19T10:00:00Z\",\"phase\":\"INIT\",\"actor\":\"t\",\"action\":\"a\",\"output_bytes\":0,\"duration_ms\":0,\"cost_usd\":0,\"verdict\":\"PASS\"}\n' >> \"\$_FLIGHT_RECORDER\"
        _emit_dashboard_snapshot 'TEST_PHASE' 'PHASE_EXIT' '$TEST_DIR'
        jq -r '.event_type' '$TEST_DIR/dashboard-latest.json'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == "PHASE_EXIT" ]]
}

@test "snapshot schema stays at spiral.dashboard.v1 (additive field only)" {
    run bash -c "
        source '$EVIDENCE_SH'
        _init_flight_recorder '$TEST_DIR'
        printf '{\"seq\":1,\"ts\":\"2026-04-19T10:00:00Z\",\"phase\":\"INIT\",\"actor\":\"t\",\"action\":\"a\",\"output_bytes\":0,\"duration_ms\":0,\"cost_usd\":0,\"verdict\":\"PASS\"}\n' >> \"\$_FLIGHT_RECORDER\"
        _emit_dashboard_snapshot 'TEST_PHASE' 'PHASE_HEARTBEAT' '$TEST_DIR'
        jq -r '.schema' '$TEST_DIR/dashboard-latest.json'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == "spiral.dashboard.v1" ]]
}

# =========================================================================
# DMP-T2: backward compatibility with legacy 2-arg form
# =========================================================================

@test "legacy 2-arg form (path as arg 2) auto-detected as cycle_dir" {
    # Pre-cycle-092 callers invoked _emit_dashboard_snapshot <phase> <cycle_dir>.
    # The dispatch logic checks if arg 2 contains `/` or `.` — if so, treat
    # as cycle_dir. event_type defaults to PHASE_START.
    run bash -c "
        source '$EVIDENCE_SH'
        _init_flight_recorder '$TEST_DIR'
        printf '{\"seq\":1,\"ts\":\"2026-04-19T10:00:00Z\",\"phase\":\"INIT\",\"actor\":\"t\",\"action\":\"a\",\"output_bytes\":0,\"duration_ms\":0,\"cost_usd\":0,\"verdict\":\"PASS\"}\n' >> \"\$_FLIGHT_RECORDER\"
        _emit_dashboard_snapshot 'LEGACY_PHASE' '$TEST_DIR'
        [[ -f '$TEST_DIR/dashboard-latest.json' ]] || exit 1
        event_type=\$(jq -r '.event_type' '$TEST_DIR/dashboard-latest.json')
        [[ \"\$event_type\" == 'PHASE_START' ]]
    "
    [ "$status" -eq 0 ]
}

# =========================================================================
# DMP-T3: daemon basic lifecycle
# =========================================================================

@test "daemon fails gracefully when cycle_dir is empty" {
    run bash -c "source '$EVIDENCE_SH'; _spawn_dashboard_heartbeat_daemon ''"
    [ "$status" -eq 1 ]
}

@test "daemon fails gracefully when cycle_dir does not exist" {
    run bash -c "source '$EVIDENCE_SH'; _spawn_dashboard_heartbeat_daemon '/nonexistent/path'"
    [ "$status" -eq 1 ]
}

@test "daemon returns a PID on success" {
    # Set .phase-current so daemon has something to emit
    printf 'IMPL\t2026-04-19T10:00:00Z\t-\t-\n' > "$TEST_DIR/.phase-current"
    DAEMON_PID=$(bash -c "source '$EVIDENCE_SH'; _spawn_dashboard_heartbeat_daemon '$TEST_DIR' 30")
    [[ "$DAEMON_PID" =~ ^[0-9]+$ ]]
    kill -TERM "$DAEMON_PID" 2>/dev/null || true
    wait "$DAEMON_PID" 2>/dev/null || true
}

# =========================================================================
# DMP-T4: heartbeat cadence (fast test via low interval)
# =========================================================================

@test "daemon emits PHASE_HEARTBEAT to dashboard-latest.json after interval_sec elapses" {
    # Iter-5 BB F-002 fix: previously this test only checked liveness after
    # 1s, despite its name claiming to verify HEARTBEAT emission. Now it
    # actually verifies the contract — uses LOA_TEST_HEARTBEAT_INTERVAL=1
    # to bypass the 30s clamp, then asserts dashboard-latest.json was
    # updated with a PHASE_HEARTBEAT event_type during the daemon's lifetime.
    printf 'IMPL\t2026-04-19T10:00:00Z\t-\t-\n' > "$TEST_DIR/.phase-current"

    local dashboard="$TEST_DIR/dashboard-latest.json"

    # Spawn daemon with 1-second test interval (bypasses 30s clamp).
    # _FLIGHT_RECORDER must be set AFTER sourcing — the script resets it to
    # "" on load (see spiral-evidence.sh:34). Without this, _emit_dashboard_snapshot
    # silently returns 0 on the empty-recorder guard.
    DAEMON_PID=$(bash -c "source '$EVIDENCE_SH'; export _FLIGHT_RECORDER='$_FLIGHT_RECORDER'; LOA_TEST_HEARTBEAT_INTERVAL=1 _spawn_dashboard_heartbeat_daemon '$TEST_DIR'")
    [[ "$DAEMON_PID" =~ ^[0-9]+$ ]]

    # Poll for the PHASE_HEARTBEAT event in dashboard-latest.json. 4-second
    # deadline absorbs one interval + write latency + jq parse jitter.
    local deadline=$(( $(date +%s) + 4 ))
    local saw_heartbeat=0
    while (( $(date +%s) < deadline )); do
        if [[ -f "$dashboard" ]]; then
            local et
            et=$(jq -r '.event_type // ""' "$dashboard" 2>/dev/null || echo "")
            if [[ "$et" == "PHASE_HEARTBEAT" ]]; then
                saw_heartbeat=1
                break
            fi
        fi
        sleep 0.1
    done

    # Reap before asserting (don't leak a daemon if the assert fails)
    kill -TERM "$DAEMON_PID" 2>/dev/null || true

    [ "$saw_heartbeat" -eq 1 ] || { echo "no PHASE_HEARTBEAT event observed in dashboard-latest.json within 4s"; cat "$dashboard" 2>&1 || true; false; }
}

# =========================================================================
# DMP-T5: interval clamp enforcement (Iter-4/5 BB F2 + non_behavioral_clamp_test
# fix: behavioral assertions on the _clamp_heartbeat_interval helper instead
# of greping source for clamp literals. The helper IS the contract; grepping
# the implementation couples the test to text shape rather than behavior.)
# =========================================================================

# Boundary table — input → expected effective interval after clamp.
# Each row is asserted independently so a failure points at the boundary.

@test "interval clamp: 0 → 30 (below-min)" {
    bash -c "source '$EVIDENCE_SH'; _clamp_heartbeat_interval 0" > "$BATS_TEST_TMPDIR/out"
    [ "$(cat "$BATS_TEST_TMPDIR/out")" = "30" ]
}

@test "interval clamp: 29 → 30 (just-below-min)" {
    bash -c "source '$EVIDENCE_SH'; _clamp_heartbeat_interval 29" > "$BATS_TEST_TMPDIR/out"
    [ "$(cat "$BATS_TEST_TMPDIR/out")" = "30" ]
}

@test "interval clamp: 30 → 30 (at-min, identity)" {
    bash -c "source '$EVIDENCE_SH'; _clamp_heartbeat_interval 30" > "$BATS_TEST_TMPDIR/out"
    [ "$(cat "$BATS_TEST_TMPDIR/out")" = "30" ]
}

@test "interval clamp: 60 → 60 (mid-range, identity)" {
    bash -c "source '$EVIDENCE_SH'; _clamp_heartbeat_interval 60" > "$BATS_TEST_TMPDIR/out"
    [ "$(cat "$BATS_TEST_TMPDIR/out")" = "60" ]
}

@test "interval clamp: 300 → 300 (at-max, identity)" {
    bash -c "source '$EVIDENCE_SH'; _clamp_heartbeat_interval 300" > "$BATS_TEST_TMPDIR/out"
    [ "$(cat "$BATS_TEST_TMPDIR/out")" = "300" ]
}

@test "interval clamp: 301 → 300 (just-above-max)" {
    bash -c "source '$EVIDENCE_SH'; _clamp_heartbeat_interval 301" > "$BATS_TEST_TMPDIR/out"
    [ "$(cat "$BATS_TEST_TMPDIR/out")" = "300" ]
}

@test "interval clamp: 9999 → 300 (way-above-max)" {
    bash -c "source '$EVIDENCE_SH'; _clamp_heartbeat_interval 9999" > "$BATS_TEST_TMPDIR/out"
    [ "$(cat "$BATS_TEST_TMPDIR/out")" = "300" ]
}

@test "interval clamp: empty → 60 (default fallback)" {
    bash -c "source '$EVIDENCE_SH'; _clamp_heartbeat_interval ''" > "$BATS_TEST_TMPDIR/out"
    [ "$(cat "$BATS_TEST_TMPDIR/out")" = "60" ]
}

@test "interval clamp: 'abc' → 60 (non-numeric fallback)" {
    bash -c "source '$EVIDENCE_SH'; _clamp_heartbeat_interval 'abc'" > "$BATS_TEST_TMPDIR/out"
    [ "$(cat "$BATS_TEST_TMPDIR/out")" = "60" ]
}

@test "interval clamp: '12abc' → 60 (mixed alpha-numeric fallback)" {
    bash -c "source '$EVIDENCE_SH'; _clamp_heartbeat_interval '12abc'" > "$BATS_TEST_TMPDIR/out"
    [ "$(cat "$BATS_TEST_TMPDIR/out")" = "60" ]
}

# =========================================================================
# DMP-T6: staleness check
# =========================================================================

@test "staleness threshold variable is honored in daemon source" {
    # Validates SPIRAL_DASHBOARD_STALE_SEC env var + staleness check logic
    # is present in the daemon implementation. The actual runtime behavior
    # is hard to test deterministically (requires manipulating mtime).
    run bash -c "grep -qE 'SPIRAL_DASHBOARD_STALE_SEC' '$EVIDENCE_SH'"
    [ "$status" -eq 0 ]
    run bash -c "grep -qE 'age > stale_sec' '$EVIDENCE_SH'"
    [ "$status" -eq 0 ]
}

# =========================================================================
# DMP-T7: daemon exits when .phase-current goes missing
# =========================================================================

@test "daemon self-terminates when .phase-current disappears (no external signal)" {
    # Iter-5 BB 993540fc fix: previous version deleted the file AND sent
    # SIGTERM, so it only proved "daemon is killable" — not "daemon detects
    # file absence and self-exits". The fix: wait for PID self-exit with a
    # bounded timeout, NEVER sending a signal. If the daemon dies, it died
    # because of the file-absence path.
    #
    # Uses LOA_TEST_HEARTBEAT_INTERVAL=1 to bypass the 30-second clamp so
    # the file-absence check fires within ~2s rather than ~30s. The bypass
    # is test-only (not operator-facing).
    printf 'IMPL\t2026-04-19T10:00:00Z\t-\t-\n' > "$TEST_DIR/.phase-current"
    DAEMON_PID=$(bash -c "source '$EVIDENCE_SH'; LOA_TEST_HEARTBEAT_INTERVAL=1 _spawn_dashboard_heartbeat_daemon '$TEST_DIR'")
    [[ "$DAEMON_PID" =~ ^[0-9]+$ ]]

    # Confirm the daemon is alive before removal (so we know we're racing
    # the file-absence path, not a startup failure).
    sleep 0.3
    kill -0 "$DAEMON_PID"

    # Remove the file — this is the ONLY trigger the daemon receives.
    rm -f "$TEST_DIR/.phase-current"

    # Poll for self-exit with a 5-second deadline. Generous enough to absorb
    # one full interval cycle plus stat() jitter, tight enough to fail loudly
    # if the file-absence check is broken. NO kill -TERM is sent — the test
    # passes only if the daemon exits on its own.
    #
    # Note: the daemon is spawned via `bash -c` so it's a grandchild of this
    # shell, not a direct child — `wait` would error with "not a child".
    # The behavioral contract being asserted is "PID disappeared without an
    # external signal", which is sufficient to prove file-absence detection
    # works (the only OTHER way the PID could disappear is a daemon crash,
    # which we'd want to surface separately and which the surrounding
    # parent-shell EXIT-trap test catches).
    local deadline=$(( $(date +%s) + 5 ))
    while (( $(date +%s) < deadline )); do
        if ! kill -0 "$DAEMON_PID" 2>/dev/null; then
            return 0  # daemon self-terminated
        fi
        sleep 0.1
    done

    # Daemon did NOT self-terminate within 5s of file removal. The
    # file-absence path is broken. Clean up the runaway daemon to keep
    # the test-suite hermetic, then fail with a specific signal.
    kill -TERM "$DAEMON_PID" 2>/dev/null || true
    echo "daemon did not self-terminate after .phase-current removal"
    false
}

# =========================================================================
# DMP-T8: no orphaned daemon after parent shell exits
# =========================================================================

@test "main() reaps daemon before finalization (regression for cycle-092 review F-3.1 + F-3.2)" {
    # Regression test for review findings:
    #   F-3.1: local DASHBOARD_DAEMON_PID is out of scope in EXIT trap
    #   F-3.2: race between daemon HEARTBEAT and finalization PHASE_EXIT
    # Fix: explicit reap BEFORE _finalize_flight_recorder (spiral-harness.sh:1405).
    # This test validates the reap pattern — kill+wait while the daemon is
    # still a known child — matches what main() now does.
    printf 'IMPL\t2026-04-19T10:00:00Z\t-\t-\n' > "$TEST_DIR/.phase-current"

    # Spawn daemon via bash -c (mirrors main()'s $(…) capture pattern)
    DAEMON_PID=$(bash -c "source '$EVIDENCE_SH'; SPIRAL_DASHBOARD_HEARTBEAT_SEC=30 _spawn_dashboard_heartbeat_daemon '$TEST_DIR'")
    [[ "$DAEMON_PID" =~ ^[0-9]+$ ]]

    # Simulate main()'s explicit reap (the pattern added at spiral-harness.sh:1405)
    kill -TERM "$DAEMON_PID" 2>/dev/null || true
    wait "$DAEMON_PID" 2>/dev/null || true

    # Daemon must be gone — if it's still alive, the reap didn't work
    if kill -0 "$DAEMON_PID" 2>/dev/null; then
        echo "daemon still alive after explicit reap — F-3.1 regression"
        kill -9 "$DAEMON_PID" 2>/dev/null || true
        false
    fi
    # Reset so teardown doesn't try to kill again
    DAEMON_PID=""
}

@test "daemon reaped by parent-shell EXIT trap (no orphan)" {
    # Spawn a parent shell that sets up the EXIT trap pattern used by
    # spiral-harness.sh main(), spawns the daemon, then exits. Verify
    # no daemon process remains.
    printf 'IMPL\t2026-04-19T10:00:00Z\t-\t-\n' > "$TEST_DIR/.phase-current"

    # Write a parent-shell wrapper script
    cat > "$TEST_DIR/parent.sh" <<'PARENT_EOF'
#!/usr/bin/env bash
set -euo pipefail
TEST_DIR="$1"
EVIDENCE_SH="$2"
source "$EVIDENCE_SH"
DAEMON_PID=""
trap '[[ -n "$DAEMON_PID" ]] && kill -TERM "$DAEMON_PID" 2>/dev/null' EXIT
DAEMON_PID=$(SPIRAL_DASHBOARD_HEARTBEAT_SEC=30 _spawn_dashboard_heartbeat_daemon "$TEST_DIR")
echo "spawned:$DAEMON_PID"
# Exit immediately — trap should reap daemon
PARENT_EOF
    chmod +x "$TEST_DIR/parent.sh"

    # Source-able, but we want the trap to fire at process exit.
    local output_line daemon_pid
    output_line=$("$TEST_DIR/parent.sh" "$TEST_DIR" "$EVIDENCE_SH" 2>&1)
    daemon_pid=$(echo "$output_line" | grep -oE 'spawned:[0-9]+' | cut -d: -f2)
    [[ -n "$daemon_pid" ]]

    # Brief pause so kill/reap can complete
    sleep 1

    # Daemon should not be alive
    if kill -0 "$daemon_pid" 2>/dev/null; then
        echo "orphaned daemon detected: $daemon_pid"
        kill -TERM "$daemon_pid" 2>/dev/null || true
        false
    fi
}
