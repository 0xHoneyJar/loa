#!/usr/bin/env bash
# karpathy-surgical-diff-check.sh — Karpathy enforcement v1
# (#961 K-1 / FR-1)
#
# PostToolUse:Write|Edit|NotebookEdit hook. Reads tool_input JSON from stdin,
# accumulates session diff lines at .run/karpathy-task-state.jsonl, and emits
# a `[karpathy-surgical-warn]` stderr line + trajectory event when the running
# total exceeds `karpathy_principles.diff_lines_per_task` (default 100).
#
# Non-blocking by design — returns 0 regardless. The `enforce: block` config
# semantic is RESERVED for v2; v1 honors `warn` only to avoid surprise breakage
# during initial rollout. See grimoires/loa/sdd.md §3.3 + §7 R-3.
#
# Safety invariants (NFR-Sec-1):
#   - tool_input.content / tool_input.new_string NEVER written to state or
#     trajectory. Only line counts + file paths are recorded.
#   - file_path is JSON-escaped via `jq --arg` — no shell-injection vector.
#   - Hook MUST exit 0 even when yq/jq are missing or config is malformed
#     (graceful degradation; never break Write/Edit due to hook env issues).

set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CONFIG="${LOA_CONFIG_OVERRIDE:-$REPO_ROOT/.loa.config.yaml}"
TASK_STATE="${KARPATHY_TASK_STATE:-$REPO_ROOT/.run/karpathy-task-state.jsonl}"
TRAJ_DIR="${KARPATHY_TRAJECTORY_DIR:-$REPO_ROOT/grimoires/loa/a2a/trajectory}"

# Graceful degradation: missing tools or config → no-op.
command -v jq >/dev/null 2>&1 || exit 0
command -v yq >/dev/null 2>&1 || exit 0
[[ -f "$CONFIG" ]] || exit 0

# Fast-path: master switch off → no-op (<10ms target).
# NOTE: yq's `// true` defaults trip on explicit `false` values (`false` is
# treated as null by the alternative operator). Read raw, then test for the
# specific false-equivalents.
ENABLED=$(yq eval '.karpathy_principles.surgical_diff_warning' "$CONFIG" 2>/dev/null || echo "null")
case "$ENABLED" in
    false|False|FALSE|0|no|No|NO|off|Off|OFF)
        exit 0
        ;;
esac

THRESHOLD=$(yq eval '.karpathy_principles.diff_lines_per_task' "$CONFIG" 2>/dev/null || echo "null")
[[ "$THRESHOLD" == "null" || -z "$THRESHOLD" ]] && THRESHOLD=100
# Validate threshold is a positive integer; default to 100 on parse failure.
[[ "$THRESHOLD" =~ ^[0-9]+$ ]] || THRESHOLD=100

# Read stdin tool_input. If empty or non-JSON, no-op.
INPUT=$(cat 2>/dev/null || echo "")
[[ -n "$INPUT" ]] || exit 0
echo "$INPUT" | jq empty 2>/dev/null || exit 0

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[[ -n "$TOOL_NAME" ]] || exit 0

# Compute lines_changed based on tool shape. Conservative — counts new content
# only (doesn't subtract removed lines from Edit; that's the v1 simplification
# documented in SDD §0.3).
LINES=0
case "$TOOL_NAME" in
    Write)
        LINES=$(echo "$INPUT" | jq -r '.tool_input.content // empty' 2>/dev/null | wc -l | tr -d ' ')
        ;;
    Edit|NotebookEdit)
        LINES=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty' 2>/dev/null | wc -l | tr -d ' ')
        ;;
    *)
        # Unrecognized tool — no-op (defensive: settings.json matcher should
        # prevent this, but the hook stays safe even if matcher widens).
        exit 0
        ;;
esac

[[ "$LINES" =~ ^[0-9]+$ ]] || exit 0

FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // "<unknown>"' 2>/dev/null)
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
SESSION_ID="${LOA_SESSION_ID:-${USER:-unknown}-$(date -u +%Y%m%d)}"

mkdir -p "$(dirname "$TASK_STATE")"

# Running total: sum lines_changed across existing state entries + this call.
# Awk parse is intentionally tolerant of malformed lines (skips them).
RUNNING=$(awk -F'"lines_changed":' '
    /"lines_changed":/ {
        n = $2 + 0  # extract leading integer
        sum += n
    }
    END { print sum + 0 }
' "$TASK_STATE" 2>/dev/null || echo 0)
RUNNING=$((RUNNING + LINES))

# Append entry to state.
jq -nc \
    --arg ts "$TS" \
    --arg tool "$TOOL_NAME" \
    --arg file "$FILE" \
    --arg session "$SESSION_ID" \
    --argjson lines "$LINES" \
    --argjson total "$RUNNING" \
    '{ts:$ts, tool:$tool, file:$file, lines_changed:$lines, running_total:$total, session_id:$session}' \
    >> "$TASK_STATE" 2>/dev/null || exit 0

# Threshold check.
if (( RUNNING > THRESHOLD )); then
    echo "[karpathy-surgical-warn] Session diff total ${RUNNING} lines exceeds threshold ${THRESHOLD}. Karpathy principle 3 (Surgical Changes): verify every changed line traces to the stated task. State: $TASK_STATE" >&2

    # Trajectory event (#961 K-2 FR-3 schema).
    mkdir -p "$TRAJ_DIR"
    TRAJ_FILE="$TRAJ_DIR/karpathy-$(date -u +%Y-%m-%d).jsonl"
    TOOL_CALLS=$(wc -l < "$TASK_STATE" 2>/dev/null | tr -d ' ' || echo 0)
    [[ "$TOOL_CALLS" =~ ^[0-9]+$ ]] || TOOL_CALLS=0
    # files_modified = unique file paths in state (best-effort jq aggregation
    # over JSONL; tolerates malformed lines).
    FILES_MOD=$(jq -rs '[.[].file // empty] | unique | length' "$TASK_STATE" 2>/dev/null || echo 0)
    [[ "$FILES_MOD" =~ ^[0-9]+$ ]] || FILES_MOD=0

    jq -nc \
        --arg ts "$TS" \
        --arg session "$SESSION_ID" \
        --argjson lines "$RUNNING" \
        --argjson thresh "$THRESHOLD" \
        --argjson files "$FILES_MOD" \
        --argjson calls "$TOOL_CALLS" \
        '{phase:"karpathy_check", principle:"surgical_changes", timestamp:$ts, files_modified:$files, lines_total:$lines, threshold:$thresh, verdict:"warn", tool_call_count:$calls, session_id:$session}' \
        >> "$TRAJ_FILE" 2>/dev/null || true
fi

# v1 invariant: hook always returns 0 (non-blocking). BLOCK semantics are
# RESERVED for v2 — see SDD §7 R-3.
exit 0
