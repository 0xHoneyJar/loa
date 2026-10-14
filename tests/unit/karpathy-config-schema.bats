#!/usr/bin/env bats
# =============================================================================
# Issue #961 K-1 — Karpathy config schema (yq read + backward-compat defaults)
# =============================================================================
# Pins that `.loa.config.yaml.example` ships with the 7-key karpathy_principles
# block, and that the hook reads each key correctly with sensible defaults.
# =============================================================================

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    EXAMPLE="$REPO_ROOT/.loa.config.yaml.example"
    [[ -f "$EXAMPLE" ]] || skip ".loa.config.yaml.example not found"
    command -v yq >/dev/null 2>&1 || skip "yq not available"
}

@test "#961 K-1: .loa.config.yaml.example contains karpathy_principles block" {
    grep -q "^karpathy_principles:" "$EXAMPLE"
}

@test "#961 K-1: example exposes all 7 keys (two as commented, profile-governed lines since cycle-129 FR-9)" {
    for key in surface_assumptions diff_lines_per_task simplicity_check max_abstraction_depth enforce; do
        run yq eval ".karpathy_principles.${key}" "$EXAMPLE"
        [ "$status" -eq 0 ]
        [ "$output" != "null" ]
    done
    # surgical_diff_warning and require_success_criteria are loa.profile keys: the
    # example documents them as commented lines so a copied example follows the
    # profile (sprint-256 review r256-2 HIGH-2); the raw key must be absent.
    for key in surgical_diff_warning require_success_criteria; do
        grep -qE "^  # ${key}: (true|false)" "$EXAMPLE"
        run yq eval ".karpathy_principles.${key}" "$EXAMPLE"
        [ "$status" -eq 0 ]
        [ "$output" = "null" ]
    done
}

@test "#961 K-1: hook defaults to 100 lines when threshold missing" {
    HOOK="$REPO_ROOT/.claude/hooks/quality/karpathy-surgical-diff-check.sh"
    [[ -x "$HOOK" ]] || skip "hook not executable"

    local tmp
    tmp="$(mktemp -d)"
    export LOA_CONFIG_OVERRIDE="$tmp/cfg.yaml"
    export KARPATHY_TASK_STATE="$tmp/state.jsonl"
    # cycle-129 Task 2.3: per-task state lives under KARPATHY_STATE_DIR; without this
    # seam the test reads the repository's live accumulator and inherits its lines.
    export KARPATHY_STATE_DIR="$tmp/state"
    export KARPATHY_TRAJECTORY_DIR="$tmp/traj"

    # Config with master switch on but threshold UNSET — should default to 100
    cat > "$LOA_CONFIG_OVERRIDE" <<EOF
karpathy_principles:
  surgical_diff_warning: true
EOF

    # 50-line content: under default-100 threshold, no warn should fire
    local content
    content=$(yes line | head -50)
    local input
    input=$(jq -nc --arg c "$content" '{tool_name:"Write", tool_input:{file_path:"/tmp/x", content:$c}}')

    run bash -c "echo '$input' | '$HOOK' 2>&1"
    [ "$status" -eq 0 ]
    ! [[ "$output" == *"[karpathy-surgical-warn]"* ]]
}
