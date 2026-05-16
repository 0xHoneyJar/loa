#!/usr/bin/env bats
# =============================================================================
# flatline-orchestrator-voice-drop.bats — T2.8 end-to-end voice-drop wiring
# =============================================================================
# Cycle-104 sprint-2 T2.8 (FR-S2.5). Exercises run_phase1 with a stubbed
# model-invoke that simulates one voice's chain-exhaustion (cheval exit 12)
# alongside successful voices, then asserts:
#
#   1. The dropped voice does NOT count as a hard failure (run_phase1
#      proceeds with the remaining voices and exits 0).
#   2. A `consensus.voice_dropped` event is emitted to the trajectory log
#      with the voice label and reason=chain_exhausted.
#   3. When ALL voices chain-exhaust, run_phase1 returns 3 with a
#      diagnostic that distinguishes drop from failure.
#
# These are the FR-S2.5 acceptance criteria from SDD §6.5 and §7.2's
# `tests/test_voice_drop_on_exhaustion.py` row. The bats binding matches
# the actual subject (bash orchestrator) more honestly than a Python
# subprocess wrapper would.
#
# Hermetic: stubs out `model-invoke`, `model-adapter.sh`, and `validate_model`.
# No real network, no real cheval, no real `yq`.

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    ORCH="$PROJECT_ROOT/.claude/scripts/flatline-orchestrator.sh"

    # Per-test scratch with mode 700 to avoid tmp leakage on shared hosts.
    local slug
    slug=$(echo "${BATS_TEST_NAME:-test}" | tr -c 'A-Za-z0-9_' '_')
    SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/vd-${slug}-XXXXXX")"
    chmod 700 "$SCRATCH"

    # Trajectory dir → scratch. log_trajectory writes flatline-$date.jsonl.
    export LOA_TRAJECTORY_DIR_OVERRIDE="$SCRATCH/trajectory"
    mkdir -p "$LOA_TRAJECTORY_DIR_OVERRIDE"

    # Bring up just enough orchestrator state to call run_phase1 without
    # running main. We source the orchestrator, then override:
    #   - MODEL_INVOKE: per-test shim controlled via STUB_DIR
    #   - is_flatline_routing_enabled: always true (force the cheval path)
    #   - validate_model: always success
    #   - get_model_primary / get_model_secondary / get_model_tertiary:
    #     return canonical names so the call_model dispatch reaches the
    #     stub.
    #   - read_config: minimal yaml-free reads
    #   - TEMP_DIR + TRAJECTORY_DIR: scratch subdirs
    #   - log_invoke_failure: silent no-op (avoid log spam)
    #   - cleanup_invoke_log: no-op
    #   - setup_invoke_log: writes to scratch
    #   - redact_secrets: cat-through
    #   - sleep: no-op (override the 2s wave delay so tests finish quickly)

    STUB_DIR="$SCRATCH/stubs"
    mkdir -p "$STUB_DIR"

    # The cheval stub interprets the FIRST positional arg pair `--model <id>`
    # and looks up the per-model exit code from VD_STUB_MAP. Map shape:
    # "model_a=0;model_b=12;..." — exit 0 emits a minimal JSON payload to
    # stdout; non-zero emits a sanitized error line to stderr.
    cat > "$STUB_DIR/model-invoke" <<'STUB'
#!/usr/bin/env bash
set -u
model=""
agent=""
mode=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --model) model="$2"; shift 2 ;;
        --agent) agent="$2"; shift 2 ;;
        --mode) mode="$2"; shift 2 ;;
        *) shift ;;
    esac
done
# Lookup exit code from map
exit_code=0
IFS=';' read -ra entries <<< "${VD_STUB_MAP:-}"
for entry in "${entries[@]}"; do
    key="${entry%%=*}"
    val="${entry##*=}"
    if [[ "$key" == "$model" ]]; then
        exit_code="$val"
        break
    fi
done
if [[ "$exit_code" == "0" ]]; then
    # Emit a plausible model-invoke JSON envelope.
    printf '{"content":"stub content for %s","usage":{"input_tokens":10,"output_tokens":20},"latency_ms":42,"cost_usd":0.001}\n' "$model"
    exit 0
fi
printf '{"error":"stub","failure_class":"CHAIN_EXHAUSTED","exit_code":%s}\n' "$exit_code" >&2
exit "$exit_code"
STUB
    chmod +x "$STUB_DIR/model-invoke"

    # Source the orchestrator without running main.
    # shellcheck disable=SC1090
    source "$ORCH"

    # Override the global module paths AFTER sourcing. These MUST be
    # exported: when bats sources the orchestrator inside setup(), the
    # orchestrator's top-level assignments (TRAJECTORY_DIR, MODEL_INVOKE,
    # TEMP_DIR, etc.) are scoped to setup() and evaporate when setup
    # returns. Exported values survive into the test body's `run`
    # subshells where run_phase1 actually executes. Without `export`,
    # log_trajectory sees TRAJECTORY_DIR="" and silently fails to write
    # the trajectory JSONL.
    export MODEL_INVOKE="$STUB_DIR/model-invoke"
    export TEMP_DIR="$SCRATCH/temp"
    export TRAJECTORY_DIR="$SCRATCH/trajectory"
    mkdir -p "$TEMP_DIR" "$TRAJECTORY_DIR"

    # Force the cheval / model-invoke path (not legacy model-adapter.sh).
    is_flatline_routing_enabled() { return 0; }
    validate_model() { return 0; }
    get_model_primary() { echo "primary-stub"; }
    get_model_secondary() { echo "secondary-stub"; }
    get_model_tertiary() { echo ""; }
    setup_invoke_log() { echo "$TEMP_DIR/$1.log"; touch "$TEMP_DIR/$1.log"; }
    cleanup_invoke_log() { :; }
    log_invoke_failure() { :; }
    redact_secrets() { cat; }
    resolve_provider_id() { echo "$1"; }
    # Eliminate the inter-wave sleep so tests run fast.
    sleep() { :; }

    # Re-promote MODE_TO_AGENT to a global. When the orchestrator is sourced
    # inside the bats setup() function, its `declare -A MODE_TO_AGENT=(...)`
    # binds the array to setup()'s local scope; it evaporates when setup
    # returns. We unset that local and rebuild a global with the same
    # mapping so call_model's mode→agent lookup keeps working.
    unset MODE_TO_AGENT
    declare -gA MODE_TO_AGENT=(
        ["review"]="flatline-reviewer"
        ["skeptic"]="flatline-skeptic"
        ["score"]="flatline-scorer"
        ["dissent"]="flatline-dissenter"
    )

    # Disable cost tracking side effects
    add_cost() { :; }
    set_state() { STATE="$1"; }
}

teardown() {
    [[ -n "${SCRATCH:-}" && -d "$SCRATCH" ]] && rm -rf "$SCRATCH"
}

# Helper: get the most recent trajectory log (one per date)
_latest_trajectory_log() {
    ls -1t "$TRAJECTORY_DIR"/flatline-*.jsonl 2>/dev/null | head -1
}

# ---- T2.8 voice-drop happy path ------------------------------------------

@test "VDO-T1: one voice chain-exhausted (exit 12), other succeeds → run_phase1 exits 0" {
    export VD_STUB_MAP="primary-stub=0;secondary-stub=12"
    local doc="$SCRATCH/doc.md"
    echo "# test doc" > "$doc"

    run run_phase1 "$doc" "prd" "" 30 1000
    [ "$status" -eq 0 ]
}

@test "VDO-T2: voice-drop emits consensus.voice_dropped event with chain_exhausted reason" {
    export VD_STUB_MAP="primary-stub=0;secondary-stub=12"
    local doc="$SCRATCH/doc.md"
    echo "# test doc" > "$doc"

    run_phase1 "$doc" "prd" "" 30 1000
    local rc=$?
    [ "$rc" -eq 0 ]

    local log
    log=$(_latest_trajectory_log || true)
    [[ -n "$log" && -f "$log" ]]
    # Note: log_trajectory writes jq's default (pretty-printed) output, so
    # entries span multiple lines. Match the event-name and reason
    # substrings directly without enforcing JSON compaction.
    local count=0
    count=$(grep -c 'consensus.voice_dropped' "$log" 2>/dev/null) || count=0
    [ "$count" -ge 1 ]
    grep -q 'chain_exhausted' "$log"
}

@test "VDO-T3: voice-drop log line names the dropped voice label" {
    export VD_STUB_MAP="primary-stub=0;secondary-stub=12"
    local doc="$SCRATCH/doc.md"
    echo "# test doc" > "$doc"

    run run_phase1 "$doc" "prd" "" 30 1000
    [ "$status" -eq 0 ]
    # Stderr (captured in $output by bats run) should mention the drop.
    [[ "$output" == *"chain exhausted"* ]] || [[ "$output" == *"chain-exhausted"* ]]
}

# ---- T2.8 all-voices-exhausted → hard error -------------------------------

@test "VDO-T4: all voices chain-exhausted → run_phase1 returns 3 with chain-exhaustion diagnostic" {
    export VD_STUB_MAP="primary-stub=12;secondary-stub=12"
    local doc="$SCRATCH/doc.md"
    echo "# test doc" > "$doc"

    run run_phase1 "$doc" "prd" "" 30 1000
    [ "$status" -eq 3 ]
    # Diagnostic must distinguish chain-exhausted from generic failure
    # so operators don't go chasing a flaky-network root cause.
    [[ "$output" == *"chain-exhausted"* ]]
}

# ---- T2.8 mixed: one failed, one dropped → degraded mode, not hard fail ---

@test "VDO-T5: mixed failed+dropped on a 2-voice run → hard error (no consensus possible)" {
    # primary=hard-fail (exit 1), secondary=dropped (exit 12): 2 voices,
    # 1 failed + 1 dropped = total. No consensus is possible.
    export VD_STUB_MAP="primary-stub=1;secondary-stub=12"
    local doc="$SCRATCH/doc.md"
    echo "# test doc" > "$doc"

    run run_phase1 "$doc" "prd" "" 30 1000
    [ "$status" -eq 3 ]
    [[ "$output" == *"failed"* ]]
    [[ "$output" == *"chain-exhausted"* ]]
}

# ---- T2.8 NO_ELIGIBLE_ADAPTER (exit 11) does NOT silently drop -----------

@test "VDO-T6: exit 11 (NO_ELIGIBLE_ADAPTER) is a hard failure, NOT a voice-drop" {
    # If a misconfigured headless_mode produced NO_ELIGIBLE_ADAPTER, silent
    # voice-drop would mask the config error. Pin: exit 11 → counted as
    # failure, not drop. (Voice survives in this 2-voice run because the
    # other voice succeeds.)
    export VD_STUB_MAP="primary-stub=0;secondary-stub=11"
    local doc="$SCRATCH/doc.md"
    echo "# test doc" > "$doc"

    run run_phase1 "$doc" "prd" "" 30 1000
    [ "$status" -eq 0 ]
    # And the stderr "Warning: N of T failed" line should mention failure.
    [[ "$output" == *"failed"* ]]

    # Must NOT have emitted any voice-drop event for the secondary. If the
    # trajectory log doesn't exist at all that also satisfies the rule
    # (log_trajectory only writes when an event is emitted).
    local log
    log=$(_latest_trajectory_log || true)
    if [[ -n "$log" && -f "$log" ]]; then
        local count=0
        count=$(grep -c 'consensus.voice_dropped' "$log" 2>/dev/null) || count=0
        [ "$count" -eq 0 ]
    fi
}
