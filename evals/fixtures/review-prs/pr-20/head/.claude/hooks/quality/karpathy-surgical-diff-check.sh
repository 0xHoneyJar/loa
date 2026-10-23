#!/usr/bin/env bash
# karpathy-surgical-diff-check.sh — Karpathy principle 3 (Surgical Changes),
# per-task diff size (#961 K-1 / FR-1; reworked by cycle-129 D-4.3, D-4.2a,
# DEC-0141).
#
# PostToolUse:Write|Edit|NotebookEdit hook. Counts the lines each write adds
# (Write → content, Edit/NotebookEdit → new_string) and keeps a running total
# PER TASK:
#
#   key      the current task from `run-checkpoint.sh read --json`
#            (`.checkpoint.task`, else the sprint), else the session id from
#            the hook payload (`.session_id`, else LOA_SESSION_ID, else
#            <user>-<UTC date>); sanitised to ^[A-Za-z0-9._-]+$ (any other
#            byte becomes `_`, a leading dot becomes `_`, cut to 128 bytes)
#   state    .run/karpathy-surgical/<key>.jsonl — one small file per task, so
#            the total resets when the task changes; the directory keeps the
#            20 most recently written files and deletes older ones
#   summary  .run/karpathy-surgical-summary.json
#            {task, lines, threshold, over, updated_at}, rewritten atomically
#            after each counted write; the review's SURGICAL axis reads it
#   legacy   .run/karpathy-task-state.jsonl (the old session-long total) and
#            its two perf caches are deleted on the first run of this layout
#
# Over `karpathy_principles.diff_lines_per_task` (default 100) it prints the
# `[karpathy-surgical-warn]` stderr line and appends a trajectory event
# (karpathy-check.payload.schema.json). Non-blocking: always exits 0. The
# master switch `karpathy_principles.surgical_diff_warning` is read through
# loa_knob (explicit key, else the loa.profile default; `lean` turns it off).
#
# Safety (NFR-Sec-1): tool_input.content / new_string never reach state,
# summary or trajectory — only line counts, the file path (JSON-encoded by
# jq) and the sanitised key. Missing jq or yq, a missing config or a
# malformed payload is a silent no-op. A symlinked state directory or state
# file is not written through.
#
# Seams (tests): LOA_CONFIG_OVERRIDE (config), KARPATHY_STATE_DIR,
# KARPATHY_SUMMARY_FILE, KARPATHY_LEGACY_STATE, KARPATHY_TRAJECTORY_DIR,
# KARPATHY_CHECKPOINT_CMD (default .claude/scripts/run-checkpoint.sh, which
# itself honours LOA_RUN_DIR), KARPATHY_STATE_KEEP (default 20).
#
# Design note: the session-long state file grew without bound, which is what
# the earlier perf passes (config-token and state-aggregate caches) existed
# to absorb. Per-task files are small and rotated, so the hook reads them in
# full each time and those caches are gone.

set -uo pipefail
umask 077
export LC_ALL=C

_src="${BASH_SOURCE[0]}"
_src_dir="${_src%/*}"
[[ "$_src_dir" == "$_src" ]] && _src_dir="."
SCRIPT_DIR="$(cd "$_src_dir" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
DEFAULT_CONFIG="$REPO_ROOT/.loa.config.yaml"
CONFIG="${LOA_CONFIG_OVERRIDE:-$DEFAULT_CONFIG}"
DEFAULT_STATE_DIR="$REPO_ROOT/.run/karpathy-surgical"
STATE_DIR="${KARPATHY_STATE_DIR:-$DEFAULT_STATE_DIR}"
SUMMARY="${KARPATHY_SUMMARY_FILE:-$REPO_ROOT/.run/karpathy-surgical-summary.json}"
LEGACY="${KARPATHY_LEGACY_STATE:-$REPO_ROOT/.run/karpathy-task-state.jsonl}"
TRAJ_DIR="${KARPATHY_TRAJECTORY_DIR:-$REPO_ROOT/grimoires/loa/a2a/trajectory}"
CHECKPOINT="${KARPATHY_CHECKPOINT_CMD:-$REPO_ROOT/.claude/scripts/run-checkpoint.sh}"
KEEP="${KARPATHY_STATE_KEEP:-20}"
[[ "$KEEP" =~ ^[0-9]{1,4}$ && "$KEEP" -ge 1 ]] || KEEP=20

command -v jq >/dev/null 2>&1 || exit 0
command -v yq >/dev/null 2>&1 || exit 0
[[ -f "$CONFIG" ]] || exit 0

# --- master switch and threshold (loa_knob: explicit key > profile > fallback)
# shellcheck source=../../scripts/lib/profile-lib.sh
source "$REPO_ROOT/.claude/scripts/lib/profile-lib.sh" 2>/dev/null || exit 0
if [[ "$CONFIG" != "$DEFAULT_CONFIG" ]]; then export LOA_PROFILE_CONFIG_FILE="$CONFIG"; fi
switch="$(loa_knob karpathy_principles.surgical_diff_warning true 2>/dev/null)"
case "$switch" in
    false|False|FALSE|0|no|No|NO|off|Off|OFF) exit 0 ;;
esac
THRESHOLD="$(loa_knob karpathy_principles.diff_lines_per_task 100 2>/dev/null)"
[[ "$THRESHOLD" =~ ^[0-9]{1,9}$ ]] || THRESHOLD=100
THRESHOLD=$((10#$THRESHOLD))

# --- payload: one jq, one JSON-encoded field per line (no raw newlines) ---
payload="$(cat)"
[[ -n "$payload" ]] || exit 0
fields="$(printf '%s' "$payload" | jq -r '
    def slines: if . == "" then 1 else (split("\n") | length) end;
    def jl: if type == "array" or type == "object"
            then (if length == 0 then 1 else 2 + ([.[] | jl] | add) end)
            else 1 end;
    def count: if . == null or . == false then 0 elif type == "string" then slines else jl end;
    select(type == "object") |
    (.tool_name // "" | if type == "string" then . else tojson end) as $tn |
    ([($tn | tojson),
      (if $tn == "Write" then (.tool_input.content | count)
       elif ($tn == "Edit" or $tn == "NotebookEdit") then (.tool_input.new_string | count)
       else 0 end | tostring),
      ((.tool_input.file_path // "<unknown>") | (if type == "string" then . else tojson end) | tojson),
      ((.session_id // "") | (if type == "string" then . else "" end) | tojson),
      (now | todate)] | .[])
' 2>/dev/null | head -5)" || exit 0
{
    IFS= read -r TOOL_JSON
    IFS= read -r LINES
    IFS= read -r FILE_JSON
    IFS= read -r PAYLOAD_SID_JSON
    IFS= read -r TS
} <<< "$fields"
case "${TOOL_JSON:-}" in
    '"Write"') TOOL_NAME=Write ;;
    '"Edit"') TOOL_NAME=Edit ;;
    '"NotebookEdit"') TOOL_NAME=NotebookEdit ;;
    *) exit 0 ;;
esac
[[ "${LINES:-}" =~ ^[0-9]{1,12}$ ]] || exit 0
[[ -n "${FILE_JSON:-}" && -n "${TS:-}" ]] || exit 0

# --- the key ------------------------------------------------------------------
_sanitise() {  # stdin-free: $1 → ^[A-Za-z0-9._-]+$ (may print empty)
    local s
    s="$(printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_' | cut -c1-128)"
    [[ "$s" == .* ]] && s="_${s#.}"
    printf '%s' "$s"
}
payload_sid="$(printf '%s' "${PAYLOAD_SID_JSON:-\"\"}" | jq -r '.' 2>/dev/null)" || payload_sid=""
SESSION="${payload_sid:-${LOA_SESSION_ID:-}}"
[[ -n "$SESSION" ]] || SESSION="${USER:-unknown}-${TS:0:4}${TS:5:2}${TS:8:2}"
SESSION_JSON="$(jq -cn --arg s "$SESSION" '$s')"

task_raw=""
if [[ -f "$CHECKPOINT" ]]; then
    task_raw="$(bash "$CHECKPOINT" read --json 2>/dev/null \
        | jq -r '[.checkpoint.task?, .checkpoint.sprint?, .sprint?] | map(select(type == "string" and . != ""))
                  | .[0] // empty | gsub("[^A-Za-z0-9._-]"; "_")' 2>/dev/null \
        | head -1)" || task_raw=""
fi
KEY="$(_sanitise "$task_raw")"
[[ -n "$KEY" ]] || KEY="$(_sanitise "$SESSION")"
[[ -n "$KEY" ]] || KEY="session-unknown"

# --- legacy layout: deleted on the first run under this one -------------------
if [[ -e "$LEGACY" || -L "$LEGACY" ]]; then
    rm -f -- "$LEGACY" 2>/dev/null || true
    if [[ "$STATE_DIR" == "$DEFAULT_STATE_DIR" ]]; then
        rm -f -- "$REPO_ROOT/.run/perf-cache/karpathy-state.v1.agg" \
                 "$REPO_ROOT/.run/perf-cache/karpathy-config.v1.tokens" 2>/dev/null || true
    fi
fi

# --- append to the task's file ------------------------------------------------
[[ -L "$STATE_DIR" ]] && exit 0
[[ -d "$STATE_DIR" ]] || mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
TASK_FILE="$STATE_DIR/$KEY.jsonl"
[[ -L "$TASK_FILE" ]] && exit 0

PRIOR=0
if [[ -f "$TASK_FILE" ]]; then
    # Tolerant of malformed lines: sums every `"lines_changed":<int>` it finds.
    PRIOR="$(awk -F'"lines_changed":' '/"lines_changed":/ { sum += $2 + 0 } END { print sum + 0 }' "$TASK_FILE" 2>/dev/null)" || PRIOR=0
    [[ "$PRIOR" =~ ^[0-9]{1,15}$ ]] || PRIOR=0
fi
RUNNING=$((PRIOR + LINES))

printf '{"ts":"%s","tool":"%s","file":%s,"lines_changed":%s,"running_total":%s,"session_id":%s,"task":"%s"}\n' \
    "$TS" "$TOOL_NAME" "$FILE_JSON" "$LINES" "$RUNNING" "$SESSION_JSON" "$KEY" >> "$TASK_FILE" 2>/dev/null || exit 0

# Keep the KEEP most recently written task files (names are sanitised: no
# whitespace, no leading dot, so the glob and the ls listing are exact).
n=0
while IFS= read -r old; do
    n=$((n + 1))
    if (( n > KEEP )) && [[ "$old" != "$TASK_FILE" && ! -L "$old" ]]; then
        rm -f -- "$old" 2>/dev/null || true
    fi
done < <(ls -1t -- "$STATE_DIR"/*.jsonl 2>/dev/null)

# --- summary (atomic) ---------------------------------------------------------
OVER=false
(( RUNNING > THRESHOLD )) && OVER=true
sum_dir="${SUMMARY%/*}"
[[ "$sum_dir" == "$SUMMARY" ]] && sum_dir="."
if [[ -d "$sum_dir" ]] || mkdir -p "$sum_dir" 2>/dev/null; then
    tmp="$SUMMARY.tmp.$$"
    if printf '{"task":"%s","lines":%s,"threshold":%s,"over":%s,"updated_at":"%s"}\n' \
            "$KEY" "$RUNNING" "$THRESHOLD" "$OVER" "$TS" > "$tmp" 2>/dev/null; then
        mv -f -- "$tmp" "$SUMMARY" 2>/dev/null || rm -f -- "$tmp" 2>/dev/null
    else
        rm -f -- "$tmp" 2>/dev/null
    fi
fi

# --- warning + trajectory event -----------------------------------------------
if [[ "$OVER" == "true" ]]; then
    echo "[karpathy-surgical-warn] Session diff total ${RUNNING} lines exceeds threshold ${THRESHOLD}. Karpathy principle 3 (Surgical Changes): verify every changed line traces to the stated task. State: $TASK_FILE" >&2

    counts="$(jq -nr --rawfile s "$TASK_FILE" '
        ($s | split("\n") | map(select(length > 0))) as $l |
        (try ([$l[] | fromjson | .file // empty] | unique | length) catch 0) as $f |
        "\($f) \($l | length)"' 2>/dev/null)" || counts="0 0"
    FILES_MOD="${counts%% *}"; TOOL_CALLS="${counts##* }"
    [[ "$FILES_MOD" =~ ^[0-9]+$ ]] || FILES_MOD=0
    [[ "$TOOL_CALLS" =~ ^[0-9]+$ ]] || TOOL_CALLS=0
    [[ -d "$TRAJ_DIR" ]] || mkdir -p "$TRAJ_DIR" 2>/dev/null || exit 0
    printf '{"phase":"karpathy_check","principle":"surgical_changes","timestamp":"%s","files_modified":%s,"lines_total":%s,"threshold":%s,"verdict":"warn","tool_call_count":%s,"session_id":%s}\n' \
        "$TS" "$FILES_MOD" "$RUNNING" "$THRESHOLD" "$TOOL_CALLS" "$SESSION_JSON" \
        >> "$TRAJ_DIR/karpathy-${TS:0:10}.jsonl" 2>/dev/null || true
fi

exit 0
