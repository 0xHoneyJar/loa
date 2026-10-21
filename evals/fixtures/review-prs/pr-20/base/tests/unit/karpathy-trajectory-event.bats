#!/usr/bin/env bats
# =============================================================================
# Issue #961 K-2 — Karpathy trajectory event schema + producer
# =============================================================================
# Pins that the hook writes schema-conforming JSON events to
# grimoires/loa/a2a/trajectory/karpathy-{date}.jsonl, append-only, with no
# raw tool_input content leakage (NFR-Sec-1).
# =============================================================================

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    HOOK="$REPO_ROOT/.claude/hooks/quality/karpathy-surgical-diff-check.sh"
    SCHEMA="$REPO_ROOT/.claude/data/trajectory-schemas/karpathy-check.payload.schema.json"
    [[ -x "$HOOK" ]] || skip "hook not executable"
    [[ -f "$SCHEMA" ]] || skip "schema not found"
    command -v jq >/dev/null 2>&1 || skip "jq not available"
    command -v yq >/dev/null 2>&1 || skip "yq not available"

    TMP_DIR="$(mktemp -d)"
    export KARPATHY_TASK_STATE="$TMP_DIR/task-state.jsonl"
    export KARPATHY_TRAJECTORY_DIR="$TMP_DIR/trajectory"
    export LOA_CONFIG_OVERRIDE="$TMP_DIR/config.yaml"
    cat > "$LOA_CONFIG_OVERRIDE" <<EOF
karpathy_principles:
  surgical_diff_warning: true
  diff_lines_per_task: 3
EOF
}

teardown() {
    rm -rf "$TMP_DIR"
}

_trip_warn() {
    local content="line1
line2
line3
line4
line5
line6"
    local input
    input=$(jq -nc --arg c "$content" '{tool_name:"Write", tool_input:{file_path:"/tmp/x", content:$c}}')
    echo "$input" | "$HOOK" 2>&1
}

@test "#961 K-2: trajectory file path follows convention" {
    _trip_warn >/dev/null
    local today
    today=$(date -u +%Y-%m-%d)
    [ -f "$KARPATHY_TRAJECTORY_DIR/karpathy-${today}.jsonl" ]
}

@test "#961 K-2: event has required fields per schema" {
    _trip_warn >/dev/null
    local today
    today=$(date -u +%Y-%m-%d)
    local event
    event=$(tail -1 "$KARPATHY_TRAJECTORY_DIR/karpathy-${today}.jsonl")

    # Required: phase, principle, verdict, timestamp
    [ "$(echo "$event" | jq -r '.phase')" = "karpathy_check" ]
    [ "$(echo "$event" | jq -r '.principle')" = "surgical_changes" ]
    [ "$(echo "$event" | jq -r '.verdict')" = "warn" ]
    [ "$(echo "$event" | jq -r '.timestamp')" != "null" ]
}

@test "#961 K-2: schema is valid JSON Schema 2020-12" {
    # Light validation: schema parses as JSON and declares 2020-12
    # Use --arg to pass the $-key safely (avoid shell + jq double-escape pain)
    [ "$(jq -r --arg k '$schema' '.[$k]' "$SCHEMA")" = "https://json-schema.org/draft/2020-12/schema" ]
    [ "$(jq -r '.type' "$SCHEMA")" = "object" ]
    [ "$(jq -r '.additionalProperties' "$SCHEMA")" = "false" ]
}

@test "#961 K-2: events are append-only (multiple warns → multiple events)" {
    _trip_warn >/dev/null
    _trip_warn >/dev/null  # second invocation, threshold already crossed
    local today
    today=$(date -u +%Y-%m-%d)
    local n
    n=$(wc -l < "$KARPATHY_TRAJECTORY_DIR/karpathy-${today}.jsonl")
    [ "$n" -ge 2 ]
}
