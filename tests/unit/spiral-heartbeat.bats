#!/usr/bin/env bats
# =============================================================================
# spiral-heartbeat.bats — cycle-092 Sprint 4 (#598)
# =============================================================================
# Validates SIMSTIM heartbeat emitter:
# - _emit_heartbeat emits [HEARTBEAT] line with all 11 keys
# - _emit_intent emits [INTENT] line only on phase change
# - _heartbeat_phase_verb maps all declared phases to emoji verb
# - _confidence_cue parses gate/fix state from dispatch.log
# - _heartbeat_pace classifies elapsed vs baseline (on_pace/slow/stuck)
# - E2E cross-sprint: Sprint 2 IMPL_EVIDENCE_MISSING → phase_verb=🔧 fixing
# =============================================================================

setup() {
    export PROJECT_ROOT="$BATS_TEST_DIRNAME/../.."
    export HEARTBEAT_SH="$PROJECT_ROOT/.claude/scripts/spiral-heartbeat.sh"
    export TEST_DIR="$BATS_TEST_TMPDIR/spiral-heartbeat-test"
    mkdir -p "$TEST_DIR"
}

teardown() {
    [[ -d "$TEST_DIR" ]] && rm -rf "$TEST_DIR"
}

# Helper: seed a .phase-current + dashboard-latest.json
_seed_cycle_dir() {
    local phase="${1:-REVIEW}"
    local start_ts="${2:-2026-04-19T10:00:00Z}"
    local attempt="${3:-1}"
    local fix_iter="${4:--}"
    local cost="${5:-0.00}"
    printf '%s\t%s\t%s\t%s\n' "$phase" "$start_ts" "$attempt" "$fix_iter" > "$TEST_DIR/.phase-current"
    printf '{"totals":{"cost_usd":"%s","first_action_ts":"%s"}}\n' "$cost" "$start_ts" \
        > "$TEST_DIR/dashboard-latest.json"
}

# =========================================================================
# HB-T1: _emit_heartbeat — 11-key format
# =========================================================================

@test "heartbeat line contains all 11 required keys" {
    _seed_cycle_dir REVIEW
    run bash -c "source '$HEARTBEAT_SH'; _emit_heartbeat '$TEST_DIR'; cat '$TEST_DIR/dispatch.log'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[HEARTBEAT"* ]]
    for key in phase phase_verb phase_elapsed_sec total_elapsed_sec cost_usd budget_usd files ins del activity confidence pace; do
        [[ "$output" == *"${key}="* ]] || { echo "missing key: $key" >&2; false; }
    done
}

@test "heartbeat line starts with [HEARTBEAT <iso-ts>]" {
    _seed_cycle_dir IMPLEMENT
    run bash -c "source '$HEARTBEAT_SH'; _emit_heartbeat '$TEST_DIR'; cat '$TEST_DIR/dispatch.log'"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^\[HEARTBEAT\ [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\] ]]
}

@test "heartbeat phase_verb reflects current phase" {
    _seed_cycle_dir AUDIT
    run bash -c "source '$HEARTBEAT_SH'; _emit_heartbeat '$TEST_DIR'; cat '$TEST_DIR/dispatch.log'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"phase_verb=🛡️ auditing"* ]]
}

@test "heartbeat fails gracefully when cycle_dir missing" {
    run bash -c "source '$HEARTBEAT_SH'; _emit_heartbeat ''"
    [ "$status" -eq 1 ]
}

# =========================================================================
# HB-T2: _heartbeat_phase_verb mapping (per issue #598)
# =========================================================================

@test "phase_verb: DISCOVERY → 🔍 discovering" {
    run bash -c "source '$HEARTBEAT_SH'; _heartbeat_phase_verb DISCOVERY"
    [[ "$output" == "🔍 discovering" ]]
}

@test "phase_verb: IMPLEMENTATION → 🔨 implementing" {
    run bash -c "source '$HEARTBEAT_SH'; _heartbeat_phase_verb IMPLEMENTATION"
    [[ "$output" == "🔨 implementing" ]]
}

@test "phase_verb: REVIEW → 👁️ reviewing" {
    run bash -c "source '$HEARTBEAT_SH'; _heartbeat_phase_verb REVIEW"
    [[ "$output" == "👁️ reviewing" ]]
}

@test "phase_verb: IMPL_FIX → 🔧 fixing" {
    run bash -c "source '$HEARTBEAT_SH'; _heartbeat_phase_verb IMPL_FIX"
    [[ "$output" == "🔧 fixing" ]]
}

@test "phase_verb: unknown phase → ⚙️ preparing fallback" {
    run bash -c "source '$HEARTBEAT_SH'; _heartbeat_phase_verb UNKNOWN_PHASE"
    [[ "$output" == "⚙️ preparing" ]]
}

# =========================================================================
# HB-T3: _emit_intent — phase change detection
# =========================================================================

@test "intent emits on first invocation (no prior state)" {
    _seed_cycle_dir REVIEW
    run bash -c "source '$HEARTBEAT_SH'; _emit_intent '$TEST_DIR'; cat '$TEST_DIR/dispatch.log' 2>/dev/null"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[INTENT"* ]]
    [[ "$output" == *"phase=REVIEW"* ]]
}

@test "intent does NOT re-emit when phase unchanged" {
    _seed_cycle_dir REVIEW
    run bash -c "
        source '$HEARTBEAT_SH'
        _emit_intent '$TEST_DIR'
        _emit_intent '$TEST_DIR'
        _emit_intent '$TEST_DIR'
        grep -c '^\\[INTENT' '$TEST_DIR/dispatch.log'
    "
    [ "$status" -eq 0 ]
    [[ "${output// /}" == "1" ]]
}

@test "intent re-emits on phase change" {
    _seed_cycle_dir REVIEW
    run bash -c "
        source '$HEARTBEAT_SH'
        _emit_intent '$TEST_DIR'
        # Change phase
        printf 'AUDIT\\t2026-04-19T10:00:00Z\\t1\\t-\\n' > '$TEST_DIR/.phase-current'
        _emit_intent '$TEST_DIR'
        grep -c '^\\[INTENT' '$TEST_DIR/dispatch.log'
    "
    [ "$status" -eq 0 ]
    [[ "${output// /}" == "2" ]]
}

@test "intent for REVIEW phase uses static compliance-checking text" {
    _seed_cycle_dir REVIEW
    run bash -c "source '$HEARTBEAT_SH'; _emit_intent '$TEST_DIR'; cat '$TEST_DIR/dispatch.log'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"checking amendment compliance"* ]]
}

@test "intent for IMPLEMENTATION extracts CRITICAL-Blocking finding from engineer-feedback.md" {
    _seed_cycle_dir IMPLEMENT
    # Create fake engineer-feedback.md in CWD for _heartbeat_intent_text to find
    mkdir -p "$TEST_DIR/grimoires/loa/a2a"
    cat > "$TEST_DIR/grimoires/loa/a2a/engineer-feedback.md" <<'EOF'
# Feedback

## Critical Issues (BLOCKING)

### CRITICAL — Blocking

### 1. Fix the broken authentication flow in src/auth/login.ts

Some more details...
EOF
    run bash -c "cd '$TEST_DIR' && source '$HEARTBEAT_SH' && _emit_intent '$TEST_DIR' && cat '$TEST_DIR/dispatch.log'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[INTENT"* ]]
    [[ "$output" == *"Fix the broken authentication"* ]]
}

# =========================================================================
# HB-T4: _confidence_cue — dispatch.log parser
# =========================================================================

@test "confidence_cue: attempt 1 of 3 (not last)" {
    echo "[harness] Gate: REVIEW (attempt 1/3)" > "$TEST_DIR/dispatch.log"
    run bash -c "source '$HEARTBEAT_SH'; _confidence_cue '$TEST_DIR/dispatch.log'"
    [ "$status" -eq 0 ]
    [[ "$output" == "attempt_1_of_3" ]]
}

@test "confidence_cue: attempt 3 of 3 (last chance)" {
    echo "[harness] Gate: REVIEW (attempt 3/3)" > "$TEST_DIR/dispatch.log"
    run bash -c "source '$HEARTBEAT_SH'; _confidence_cue '$TEST_DIR/dispatch.log'"
    [ "$status" -eq 0 ]
    [[ "$output" == "attempt_3_of_3_last" ]]
}

@test "confidence_cue: fix iteration 2 of 2 (last fix)" {
    echo "[harness] Review fix loop: iteration 2/2" > "$TEST_DIR/dispatch.log"
    run bash -c "source '$HEARTBEAT_SH'; _confidence_cue '$TEST_DIR/dispatch.log'"
    [ "$status" -eq 0 ]
    [[ "$output" == "iteration_2_of_2_last" ]]
}

@test "confidence_cue: no attempt/fix state → steady" {
    echo "[harness] Phase 4: IMPLEMENTATION" > "$TEST_DIR/dispatch.log"
    run bash -c "source '$HEARTBEAT_SH'; _confidence_cue '$TEST_DIR/dispatch.log'"
    [ "$status" -eq 0 ]
    [[ "$output" == "steady" ]]
}

@test "confidence_cue: missing dispatch.log → steady" {
    run bash -c "source '$HEARTBEAT_SH'; _confidence_cue '/nonexistent/path'"
    [ "$status" -eq 0 ]
    [[ "$output" == "steady" ]]
}

# =========================================================================
# HB-T5: _heartbeat_pace — elapsed vs baseline
# =========================================================================

@test "pace: 0 elapsed → advancing" {
    run bash -c "source '$HEARTBEAT_SH'; _heartbeat_pace 0 240"
    [[ "$output" == "advancing" ]]
}

@test "pace: elapsed < baseline → on_pace" {
    run bash -c "source '$HEARTBEAT_SH'; _heartbeat_pace 100 240"
    [[ "$output" == "on_pace" ]]
}

@test "pace: 2× baseline < elapsed < 3× baseline → slow" {
    run bash -c "source '$HEARTBEAT_SH'; _heartbeat_pace 600 240"
    [[ "$output" == "slow" ]]
}

@test "pace: elapsed > 3× baseline → stuck" {
    run bash -c "source '$HEARTBEAT_SH'; _heartbeat_pace 800 240"
    [[ "$output" == "stuck" ]]
}

# =========================================================================
# HB-T6: E2E cross-sprint handshake (Sprint 2 → Sprint 4)
# =========================================================================
# Sprint 2's IMPL_EVIDENCE_MISSING verdict should surface in Sprint 4's
# heartbeat phase_verb when phase=IMPL_FIX. This validates the grammar-spec
# stability contract declared in §Evidence gates.

@test "IMPL_FIX phase (Sprint 2 evidence-gate fix loop) → phase_verb=🔧 fixing" {
    _seed_cycle_dir IMPL_FIX
    run bash -c "source '$HEARTBEAT_SH'; _emit_heartbeat '$TEST_DIR'; cat '$TEST_DIR/dispatch.log'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"phase_verb=🔧 fixing"* ]]
}

# =========================================================================
# HB-T7: CLI --once mode — full emit cycle
# =========================================================================

@test "CLI --once emits one intent + one heartbeat" {
    _seed_cycle_dir REVIEW
    run "$HEARTBEAT_SH" --cycle-dir "$TEST_DIR" --once
    [ "$status" -eq 0 ]
    [[ -f "$TEST_DIR/dispatch.log" ]]
    local intent_count heartbeat_count
    intent_count=$(grep -c '^\[INTENT' "$TEST_DIR/dispatch.log")
    heartbeat_count=$(grep -c '^\[HEARTBEAT' "$TEST_DIR/dispatch.log")
    [[ "$intent_count" -eq 1 ]]
    [[ "$heartbeat_count" -eq 1 ]]
}

@test "CLI --cycle-dir missing → exit 2" {
    run "$HEARTBEAT_SH"
    [ "$status" -eq 2 ]
}

@test "CLI --help shows usage and exits 0" {
    run "$HEARTBEAT_SH" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"spiral-heartbeat.sh"* ]]
    [[ "$output" == *"--cycle-dir"* ]]
}
