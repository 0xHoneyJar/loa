#!/usr/bin/env bats
# =============================================================================
# tests/unit/cycle-124-live-scaffold.bats
#
# cycle-124 Sprint 1 Task 1.8: the live floor scaffold is inert without a
# credential — every case skips (exit 0), the skip count is pinned so a new
# live case cannot be added without updating the expectation, and the
# ceiling probe refuses to run without ANTHROPIC_API_KEY.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    if [[ -x "$PROJECT_ROOT/.venv/bin/python" ]]; then
        PYTHON_BIN="$PROJECT_ROOT/.venv/bin/python"
    else
        PYTHON_BIN="$(command -v python3)"
    fi
    export LOA_MODELINV_LOG_PATH="$BATS_TEST_TMPDIR/model-invoke.jsonl"
    export LOA_COST_LEDGER_PATH="$BATS_TEST_TMPDIR/cost-ledger.jsonl"
}

# 1 models + 4 thinking + 1 cache + 1 schema (Sprint 2) + 1 probe = 8 cases.
EXPECTED_SKIPS=8

@test "c124-1.8-1: without LOA_RUN_LIVE_TESTS the scaffold skips every case cleanly (pinned count)" {
    "$PYTHON_BIN" -c "import pytest" 2>/dev/null || skip "pytest not available"
    run env -u LOA_RUN_LIVE_TESTS -u ANTHROPIC_API_KEY "$PYTHON_BIN" -m pytest \
        "$PROJECT_ROOT/tests/replay/test_cycle124_live_floor.py" -rs -q -p no:cacheprovider
    [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
    [[ "$output" == *"${EXPECTED_SKIPS} skipped"* ]] || { echo "$output" >&2; return 1; }
    [[ "$output" == *"set LOA_RUN_LIVE_TESTS=1 and ANTHROPIC_API_KEY"* ]]
}

@test "c124-1.8-2: LOA_RUN_LIVE_TESTS=1 without a key still skips (no accidental spend)" {
    "$PYTHON_BIN" -c "import pytest" 2>/dev/null || skip "pytest not available"
    run env -u ANTHROPIC_API_KEY LOA_RUN_LIVE_TESTS=1 "$PYTHON_BIN" -m pytest \
        "$PROJECT_ROOT/tests/replay/test_cycle124_live_floor.py" -q -p no:cacheprovider
    [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
    [[ "$output" == *"${EXPECTED_SKIPS} skipped"* ]]
}

@test "c124-1.8-3: ceiling-probe.py refuses to run without ANTHROPIC_API_KEY (exit 2)" {
    run env -u ANTHROPIC_API_KEY "$PYTHON_BIN" "$PROJECT_ROOT/tools/ceiling-probe.py" --model claude-opus-5
    [ "$status" -eq 2 ]
    [[ "$output" == *"ANTHROPIC_API_KEY is required"* ]]
}

@test "c124-1.8-4: live-floor-check.yml gates every credentialed step on HAS_KEY and names the merge precondition" {
    local wf="$PROJECT_ROOT/.github/workflows/live-floor-check.yml"
    [ -f "$wf" ]
    grep -q "HAS_KEY: \${{ secrets.ANTHROPIC_API_KEY != '' }}" "$wf"
    grep -q "tests/replay/test_cycle124_live_floor.py" "$wf"
    grep -q "LOA_RUN_LIVE_TESTS: '1'" "$wf"
    grep -q "MERGE" "$wf"
    # every step that touches the key is gated
    [ "$(grep -c "if: env.HAS_KEY == 'true'" "$wf")" -ge 3 ]
}

@test "c124-1.8-5: live-floor-check.yml is manual-only and targets the live-floor environment (no secret over PR-controlled code)" {
    local wf="$PROJECT_ROOT/.github/workflows/live-floor-check.yml"
    run "$PYTHON_BIN" - "$wf" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
on = d.get("on", d.get(True))
triggers = set(on) if isinstance(on, dict) else {on}
assert triggers == {"workflow_dispatch"}, f"triggers: {sorted(triggers)}"
job = d["jobs"]["live-floor"]
assert job.get("environment") == "live-floor", job.get("environment")
PY
    [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
}
