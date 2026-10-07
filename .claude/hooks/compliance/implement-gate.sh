#!/usr/bin/env bash
# =============================================================================
# implement-gate.sh — Dual-mode compliance hook for App Zone writes (FR-7)
# =============================================================================
# Checks whether Write/Edit to App Zone files occurs within an active
# /implement or /bug skill invocation.
#
# Two detection modes:
#   1. HEURISTIC (ADVISORY, the default): reads .run/ state files for RUNNING state
#   2. AUTHORITATIVE: reads tool_input.active_skill from hook stdin, only when
#      .loa.config.yaml sets implement_gate.mode: authoritative. The PreToolUse
#      payload carries no harness-set skill field (cycle-126 D-4.4) and tool_input
#      is model-authored, so nothing in .run/ selects this mode.
#      TIGHTEN-ONLY (sprint-250 audit n17/n18): the model-authored claim can only
#      add an ask, never grant an allow. A claimed implementation skill falls
#      through to the heuristic exactly like an absent field; a claimed
#      non-implementation skill asks and logs compliance.mode.model_signal to
#      .run/audit.jsonl (plain hook log, not the signed audit_emit chain). Every
#      claim leaves one row per invocation: decision "ask" for a non-implementation
#      claim, decision "heuristic" for an implementation claim (run-2 finding 6).
#
# Evidence recorder (cycle-126 D-4.4): a lead-session payload carrying
# tool_input.active_skill records active_skill_seen_at once in
# .run/platform-features.json. It is evidence only and never changes the mode.
#
# Failure mode: FAIL-ASK for App Zone writes (not fail-open). A payload jq cannot
# parse (or no jq), or a file_path that cannot be canonicalised, asks too (run-2
# findings 1/5). The path is tool_input.file_path, or tool_input.notebook_path for
# NotebookEdit. Non-App-Zone writes always allowed.
#
# Output (Claude Code PreToolUse contract, sprint-250 audit n20): allow = silent
# exit 0 with empty stdout; ask = exit 0 with
#   {"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"…"}}
# A top-level "decision" accepts approve|block only, so "ask" never goes there.
# file_path and active_skill pass through strip_controls before they reach
# stderr or the audit row (n21; run-2 findings 3/12): C0 and DEL, UTF-8 C1
# controls and the Unicode format/bidi code points are removed to a fixed point,
# then the copy is cut to 256 bytes.
#
# IMPORTANT: No set -euo pipefail — hook must never crash-block.
# Parse/read errors on App Zone writes → ask (not allow).
#
# Part of cycle-049/050: Upstream Platform Alignment (FR-7)
# Red Team findings addressed: ATK-005 (state tampering), ATK-006 (fail-open),
#   ATK-007 (prompt injection via file path)
# Sprint-108 T4.4: Dual-mode (authoritative + heuristic)
# Sprint-108 T4.5: Path normalization
# =============================================================================

# Read tool input from stdin
input=$(cat 2>/dev/null) || input=""

# The ask reply; the reason is always a fixed string, never model-authored text
emit_ask() {
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"%s"}}\n' "$1"
}

# Byte sequences strip_controls removes: UTF-8 C1 controls (C2 80..C2 9F) and the format/bidi code points
# U+200B-U+200F, U+2028-U+202E, U+2060-U+2064, U+2066-U+2069, U+FEFF; printf -v keeps this portable (no GNU-sed \x)
_IG_STRIP_SEQS=()
for (( _ig_i = 128; _ig_i < 160; _ig_i++ )); do
    printf -v _ig_hex '%02x' "$_ig_i"; printf -v _ig_seq "\\xc2\\x${_ig_hex}"; _IG_STRIP_SEQS+=("$_ig_seq")
done
for _ig_hex in 8b 8c 8d 8e 8f a8 a9 aa ab ac ad ae; do
    printf -v _ig_seq "\\xe2\\x80\\x${_ig_hex}"; _IG_STRIP_SEQS+=("$_ig_seq")
done
for _ig_hex in a0 a1 a2 a3 a4 a6 a7 a8 a9; do
    printf -v _ig_seq "\\xe2\\x81\\x${_ig_hex}"; _IG_STRIP_SEQS+=("$_ig_seq")
done
printf -v _ig_seq '\xef\xbb\xbf'; _IG_STRIP_SEQS+=("$_ig_seq")

# Display/log copy of a model-authored string: C0 and DEL first, then the sequences above byte-wise until nothing
# changes (deleting one sequence can join its neighbours into another: C2 C2 9B 9B), then at most 256 bytes
strip_controls() {
    local LC_ALL=C s prev seq
    s=$(printf '%s' "$1" | tr -d '\000-\037\177')
    while :; do
        prev=$s
        for seq in "${_IG_STRIP_SEQS[@]}"; do s=${s//"$seq"/}; done
        [[ "$s" == "$prev" ]] && break
    done
    printf '%s' "${s:0:256}"
}

PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
RUN_DIR="${RUN_DIR:-$PROJECT_ROOT/.run}"
FEATURES_FILE="$RUN_DIR/platform-features.json"

# Evidence recorder: lead session only (no teammate role, no subagent agent_id), once, atomic.
if [[ -z "${LOA_TEAM_MEMBER:-}" && -d "$RUN_DIR" ]] \
    && jq -e '(.tool_input.active_skill // "") != "" and (.agent_id // "") == ""' <<<"$input" >/dev/null 2>&1 \
    && ! jq -e '.active_skill_seen_at' "$FEATURES_FILE" >/dev/null 2>&1; then
    _ig_base=$(jq -c 'select(type == "object")' "$FEATURES_FILE" 2>/dev/null | tail -n 1)
    _ig_tmp=$(mktemp "$RUN_DIR/.platform-features.XXXXXX" 2>/dev/null) && {
        jq -nc --argjson b "${_ig_base:-{\}}" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            '$b + {active_skill_available: false, active_skill_seen_at: $ts, active_skill_source: "tool_input"}' > "$_ig_tmp" 2>/dev/null \
            && mv -f "$_ig_tmp" "$FEATURES_FILE" 2>/dev/null
        rm -f "$_ig_tmp" 2>/dev/null
    }
fi

# No jq, or a payload jq cannot parse: the write cannot be evaluated, so ask (run-2 finding 5)
if ! command -v jq &>/dev/null || ! jq -e . <<<"$input" >/dev/null 2>&1; then
    echo "[GATE] could not evaluate tool_input (jq missing or payload unparsable)." >&2
    emit_ask "[GATE] could not evaluate tool_input. Verify this write is intentional."
    exit 0
fi

# Extract the path: Write/Edit/MultiEdit carry file_path, NotebookEdit carries notebook_path
if ! file_path=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$input" 2>/dev/null); then
    echo "[GATE] could not evaluate tool_input (path not readable)." >&2
    emit_ask "[GATE] could not evaluate tool_input. Verify this write is intentional."
    exit 0
fi

# A parsed payload without a path is not a file write the gate can classify: allow
if [[ -z "$file_path" ]]; then
    exit 0
fi

# ---------------------------------------------------------------------------
# Source compat-lib.sh for _date_to_epoch()
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null)" || SCRIPT_DIR=""
COMPAT_LIB="${SCRIPT_DIR}/../../scripts/compat-lib.sh"
# shellcheck source=../../scripts/compat-lib.sh
source "$COMPAT_LIB" 2>/dev/null || true

# ---------------------------------------------------------------------------
# T4.5: Path normalization — canonicalise both sides, then take file_path
# relative to the project root (run-2 finding 1). A textual prefix test let
# /proc/self/cwd/src/x, //ROOT/src/x, ROOT/../<name>/src/x or a symlinked root
# reach an App-Zone file unseen. Relative paths resolve from PROJECT_ROOT.
# Only the part under the root is matched, so parent directory names never
# count (e.g., /home/user/src-projects/loa/grimoires/file.md is not src/*).
# ---------------------------------------------------------------------------
canonical_root=$(cd "$PROJECT_ROOT" 2>/dev/null && pwd -P) || canonical_root=""
canonical_path=""
if [[ -n "$canonical_root" ]]; then
    # GNU realpath -m first (no component needs to exist), then readlink -f
    canonical_path=$(cd "$PROJECT_ROOT" 2>/dev/null \
        && { realpath -m -- "$file_path" 2>/dev/null || readlink -f -- "$file_path" 2>/dev/null; }) || canonical_path=""
fi
if [[ -z "$canonical_root" || -z "$canonical_path" ]]; then
    echo "[GATE] could not canonicalise tool_input.file_path; asking." >&2
    emit_ask "[GATE] could not canonicalise tool_input.file_path. Verify this write is intentional."
    exit 0
fi

# ---------------------------------------------------------------------------
# Zone check: Is this an App Zone write?
# App Zone: src/, lib/, app/ in the path relative to the canonical root;
# a path that canonicalises outside the root is not App Zone
# ---------------------------------------------------------------------------
is_app_zone=false
if [[ "$canonical_path" == "${canonical_root%/}/"* ]]; then
    normalized_path="${canonical_path#"${canonical_root%/}"/}"
    case "$normalized_path" in
        src/*|lib/*|app/*|*/src/*|*/lib/*|*/app/*)
            is_app_zone=true
            ;;
    esac
fi

# Non-App-Zone writes always allowed
if [[ "$is_app_zone" == "false" ]]; then
    exit 0
fi

# Display/log copy only: control and format characters never reach stderr or the audit row (n21, run-2 finding 3)
safe_file_path=$(strip_controls "$file_path")

# ---------------------------------------------------------------------------
# Mode: heuristic unless the operator opts in through .loa.config.yaml (cycle-126 D-4.4)
# ---------------------------------------------------------------------------
compliance_mode="heuristic"
if command -v yq &>/dev/null && [[ -f "$PROJECT_ROOT/.loa.config.yaml" ]]; then
    configured_mode=$(yq '.implement_gate.mode // ""' "$PROJECT_ROOT/.loa.config.yaml" 2>/dev/null) || configured_mode=""
    [[ "${configured_mode//\"/}" == "authoritative" ]] && compliance_mode="authoritative"
fi

# ---------------------------------------------------------------------------
# Authoritative mode: read active_skill from hook input
# ---------------------------------------------------------------------------
if [[ "$compliance_mode" == "authoritative" ]]; then
    active_skill=$(echo "$input" | jq -r '.tool_input.active_skill // empty' 2>/dev/null) || active_skill=""

    if [[ -n "$active_skill" ]]; then
        safe_skill=$(strip_controls "$active_skill")
        # One model_signal row per invocation that carries a claim; the harness never sets the field,
        # so a row means a model wrote it (run-2 finding 6)
        log_model_signal() {
            jq -nc \
                --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)" \
                --arg skill "$safe_skill" \
                --arg path "$safe_file_path" \
                --arg decision "$1" \
                '{timestamp: $ts, event: "compliance.mode.model_signal", mode: "authoritative", active_skill: $skill, file_path: $path, decision: $decision}' \
                >> "$RUN_DIR/audit.jsonl" 2>/dev/null || true
        }
        case "$active_skill" in
            implement|/implement|bug|/bug|run|/run|simstim|/simstim)
                # Tighten-only (n17/n18): a model-authored implementation claim never
                # allows by itself — log it, then fall through to the heuristic check below
                log_model_signal heuristic
                ;;
            *)
                # Non-implementation skill — log the model signal and ask
                echo "[AUTHORITATIVE] App Zone write to '$safe_file_path' detected during /$safe_skill (not an implementation skill)." >&2
                log_model_signal ask
                emit_ask "[AUTHORITATIVE] App Zone write outside implementation skill. Verify this is intentional."
                exit 0
                ;;
        esac
    else
        # active_skill field absent despite authoritative mode — fall back to heuristic
        # Log the downgrade
        log_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || log_ts="unknown"
        if command -v jq &>/dev/null; then
            jq -nc \
                --arg ts "$log_ts" \
                --arg from "authoritative" \
                --arg to "heuristic" \
                --arg reason "active_skill field absent in hook input" \
                '{timestamp: $ts, event: "compliance.mode.fallback", from_mode: $from, to_mode: $to, reason: $reason}' \
                >> "$RUN_DIR/audit.jsonl" 2>/dev/null || true
        else
            echo "{\"timestamp\":\"$log_ts\",\"event\":\"compliance.mode.fallback\",\"from_mode\":\"authoritative\",\"to_mode\":\"heuristic\",\"reason\":\"active_skill field absent in hook input\"}" \
                >> "$RUN_DIR/audit.jsonl" 2>/dev/null || true
        fi
    fi
    # Fall through to heuristic check below
fi

# ---------------------------------------------------------------------------
# Heuristic mode: Is an /implement or /bug skill currently active?
# Check .run/sprint-plan-state.json, .run/simstim-state.json, .run/state.json
# ---------------------------------------------------------------------------
check_implementation_active() {
    # Check sprint-plan state
    if [[ -f "$RUN_DIR/sprint-plan-state.json" ]]; then
        local state plan_id last_activity
        state=$(jq -r '.state // empty' "$RUN_DIR/sprint-plan-state.json" 2>/dev/null) || return 1
        plan_id=$(jq -r '.plan_id // empty' "$RUN_DIR/sprint-plan-state.json" 2>/dev/null) || true

        # Integrity: must have plan_id
        if [[ -z "$plan_id" ]]; then
            return 1
        fi

        # Integrity: check staleness (24h = 86400s)
        # Use _date_to_epoch from compat-lib.sh for portable conversion
        last_activity=$(jq -r '.timestamps.last_activity // empty' "$RUN_DIR/sprint-plan-state.json" 2>/dev/null) || true
        if [[ -n "$last_activity" ]]; then
            local now last_epoch
            now=$(date +%s 2>/dev/null) || now=0
            if type _date_to_epoch &>/dev/null; then
                last_epoch=$(_date_to_epoch "$last_activity" 2>/dev/null) || last_epoch=0
            else
                # Fallback if compat-lib not loaded: try GNU then macOS
                last_epoch=$(date -d "$last_activity" +%s 2>/dev/null ||
                             date -jf '%Y-%m-%dT%H:%M:%SZ' "$last_activity" +%s 2>/dev/null) || last_epoch=0
            fi
            if [[ $now -gt 0 && $last_epoch -gt 0 ]]; then
                local age=$((now - last_epoch))
                if [[ $age -gt 86400 ]]; then
                    return 1  # Stale state (>24h)
                fi
            fi
        fi

        if [[ "$state" == "RUNNING" ]]; then
            return 0
        fi
    fi

    # Check simstim state
    if [[ -f "$RUN_DIR/simstim-state.json" ]]; then
        local phase
        phase=$(jq -r '.phase // empty' "$RUN_DIR/simstim-state.json" 2>/dev/null) || return 1
        if [[ "$phase" == "implementation" ]]; then
            return 0
        fi
    fi

    # Check run state
    if [[ -f "$RUN_DIR/state.json" ]]; then
        local run_state
        run_state=$(jq -r '.state // empty' "$RUN_DIR/state.json" 2>/dev/null) || return 1
        if [[ "$run_state" == "RUNNING" ]]; then
            return 0
        fi
    fi

    return 1
}

# ---------------------------------------------------------------------------
# Decision: allow or ask
# ---------------------------------------------------------------------------
if check_implementation_active; then
    # Implementation is active — allow the write
    exit 0
else
    # No active implementation detected — ADVISORY ask
    echo "[ADVISORY] App Zone write to '$safe_file_path' detected outside active /implement or /bug." >&2
    echo "No RUNNING state found in .run/ state files. This may bypass review gates." >&2
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"[ADVISORY] App Zone write outside active implementation. Verify this is intentional."}}'
    exit 0
fi
