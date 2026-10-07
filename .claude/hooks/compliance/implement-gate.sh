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
# NotebookEdit; a relative path resolves from the payload's cwd, else PROJECT_ROOT
# (run-3 finding 6). The zone test ORs a physical form (symlinks followed) and a
# logical form (symlinks kept) and matches a lowercased copy (run-3 findings 1/2).
# Root: PROJECT_ROOT, else CLAUDE_PROJECT_DIR, else this script's location
# (<root>/.claude/hooks/compliance/), never the process cwd, which follows
# Claude's `cd` (audit MED-001); RUN_DIR defaults to <root>/.run.
# Trust inputs: a write to .run/state.json, .run/sprint-plan-state.json,
# .run/simstim-state.json, .run/platform-features.json, .run/audit.jsonl or
# .loa.config.yaml asks and logs compliance.state_write (run-3 finding 3).
# Other non-App-Zone writes always allowed.
#
# Output (Claude Code PreToolUse contract, sprint-250 audit n20): allow = silent
# exit 0 with empty stdout; ask = exit 0 with
#   {"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"…"}}
# A top-level "decision" accepts approve|block only, so "ask" never goes there.
# file_path and active_skill reach stderr only through strip_controls (n21;
# run-2 findings 3/12; run-3 finding 5): cut to 256 bytes without splitting a
# character, then C0 and DEL, UTF-8 C1 controls and the Unicode format/bidi/tag
# code points are removed to a fixed point. Audit rows record the RAW values cut
# the same way and written with jq -a, so every non-ASCII code point is \uXXXX:
# faithful (implement+U+200B logs as implement\u200b) and terminal-safe (run-3 finding 4).
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

# The ask reply; jq builds it so any reason is a well-formed JSON string (run-3 finding 7); the printf literal is only
# for the jq-missing branch, whose reason is a fixed string
emit_ask() {
    if command -v jq &>/dev/null; then
        jq -nc --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'
    else
        printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"%s"}}\n' "$1"
    fi
}

# Byte sequences strip_controls removes: UTF-8 C1 controls (C2 80..C2 9F) and the format/bidi code points
# U+200B-U+200F, U+2028-U+202E, U+2060-U+2064, U+2066-U+206F, U+FEFF, U+00AD, U+061C, U+180E, U+FE00-U+FE0F,
# U+FFF9-U+FFFB and the tag characters U+E0001, U+E0020-U+E007F (run-3 finding 5); each sequence starts with a lead
# byte, so a byte-wise match never lands inside another character; printf -v keeps this portable (no GNU-sed \x)
_IG_STRIP_SEQS=()
for (( _ig_i = 128; _ig_i < 160; _ig_i++ )); do
    printf -v _ig_hex '%02x' "$_ig_i"; printf -v _ig_seq "\\xc2\\x${_ig_hex}"; _IG_STRIP_SEQS+=("$_ig_seq")
done
for _ig_hex in 8b 8c 8d 8e 8f a8 a9 aa ab ac ad ae; do
    printf -v _ig_seq "\\xe2\\x80\\x${_ig_hex}"; _IG_STRIP_SEQS+=("$_ig_seq")
done
for _ig_hex in a0 a1 a2 a3 a4 a6 a7 a8 a9 aa ab ac ad ae af; do
    printf -v _ig_seq "\\xe2\\x81\\x${_ig_hex}"; _IG_STRIP_SEQS+=("$_ig_seq")
done
for _ig_seq in '\xef\xbb\xbf' '\xc2\xad' '\xd8\x9c' '\xe1\xa0\x8e' '\xef\xbf\xb9' '\xef\xbf\xba' '\xef\xbf\xbb' '\xf3\xa0\x80\x81'; do
    printf -v _ig_seq "$_ig_seq"; _IG_STRIP_SEQS+=("$_ig_seq")
done
for (( _ig_i = 128; _ig_i < 144; _ig_i++ )); do   # U+FE00-U+FE0F = EF B8 80..EF B8 8F
    printf -v _ig_hex '%02x' "$_ig_i"; printf -v _ig_seq "\\xef\\xb8\\x${_ig_hex}"; _IG_STRIP_SEQS+=("$_ig_seq")
done
for (( _ig_i = 160; _ig_i < 192; _ig_i++ )); do   # U+E0020-U+E003F = F3 A0 80 A0..F3 A0 80 BF
    printf -v _ig_hex '%02x' "$_ig_i"; printf -v _ig_seq "\\xf3\\xa0\\x80\\x${_ig_hex}"; _IG_STRIP_SEQS+=("$_ig_seq")
done
for (( _ig_i = 128; _ig_i < 192; _ig_i++ )); do   # U+E0040-U+E007F = F3 A0 81 80..F3 A0 81 BF
    printf -v _ig_hex '%02x' "$_ig_i"; printf -v _ig_seq "\\xf3\\xa0\\x81\\x${_ig_hex}"; _IG_STRIP_SEQS+=("$_ig_seq")
done

# Sets the variable named $1 to at most 256 bytes of $2, never ending inside a UTF-8 character: a trailing lead byte
# whose sequence the cut left short, or stray continuation bytes, are dropped (run-3 finding 5; jq would read a split
# character as U+FFFD). printf -v, not $(...), so a trailing newline in a raw value survives into the audit row
cut_utf8_256() {
    local LC_ALL=C
    local _c_s=${2:0:256} _c_n _c_i _c_b _c_need
    _c_n=${#_c_s}
    for (( _c_i = _c_n - 1; _c_i >= 0 && _c_i >= _c_n - 4; _c_i-- )); do
        printf -v _c_b '%d' "'${_c_s:_c_i:1}"
        (( _c_b >= 128 && _c_b < 192 )) && continue   # continuation byte: keep walking back to its lead
        if (( _c_b < 128 )); then _c_need=1; elif (( _c_b < 224 )); then _c_need=2; elif (( _c_b < 240 )); then _c_need=3; else _c_need=4; fi
        if (( _c_n - _c_i < _c_need )); then _c_s=${_c_s:0:_c_i}          # the cut left this character short
        elif (( _c_n - _c_i > _c_need )); then _c_s=${_c_s:0:_c_i+_c_need}   # continuation bytes after a complete character are stray
        fi
        printf -v "$1" '%s' "$_c_s"
        return 0
    done
    printf -v "$1" '%s' "${_c_s:0:_c_i+1}"   # only continuation bytes at the end: drop them
}

# Display copy of a model-authored string: cut to 256 bytes first (the fixed point below then costs at most a few
# passes over a short string), then C0 and DEL, then the sequences above byte-wise until nothing changes (deleting
# one sequence can join its neighbours into another: C2 C2 9B 9B)
strip_controls() {
    local LC_ALL=C s prev seq
    cut_utf8_256 s "$1"
    s=$(printf '%s' "$s" | tr -d '\000-\037\177')
    while :; do
        prev=$s
        for seq in "${_IG_STRIP_SEQS[@]}"; do s=${s//"$seq"/}; done
        [[ "$s" == "$prev" ]] && break
    done
    printf '%s' "$s"
}

# The root never follows the process cwd, which follows Claude's `cd` (sprint-250 audit MED-001): PROJECT_ROOT, then
# the harness's CLAUDE_PROJECT_DIR (it stays at the session's project root), then this script's own location
# (<root>/.claude/hooks/compliance/)
PROJECT_ROOT="${PROJECT_ROOT:-${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." 2>/dev/null && pwd)}}"
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

# Extract the path: Write/Edit/MultiEdit carry file_path, NotebookEdit carries notebook_path. jq -j plus a sentinel
# byte keeps a trailing newline, which $(...) would otherwise strip from the raw value (run-3 finding 4)
if ! file_path=$(jq -j '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$input" 2>/dev/null && printf x); then
    echo "[GATE] could not evaluate tool_input (path not readable)." >&2
    emit_ask "[GATE] could not evaluate tool_input. Verify this write is intentional."
    exit 0
fi
file_path=${file_path%x}

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
# reach an App-Zone file unseen. Two forms are tested and either one matching
# counts (run-3 finding 1): the PHYSICAL form follows symlinks (realpath -m,
# else readlink -f) against pwd -P of the root; the LOGICAL form keeps them
# (realpath -m -s, else a pure-bash ./../// normaliser) against pwd -L, so a
# src/ that is itself a symlink out of the root still asks. A relative path
# resolves from the payload's cwd when it carries one (the harness resolves it
# there and cwd follows `cd` in the Bash tool), else from PROJECT_ROOT (run-3
# finding 6). Only the part under the root is matched, so parent directory
# names never count (e.g., /home/user/src-projects/loa/grimoires/file.md is not src/*).
# ---------------------------------------------------------------------------
# Lexical normaliser for an absolute path: drops empty and . components, resolves .. textually, follows no symlink
_ig_lexical_norm() {
    local rest=$1 part
    local -a out=()
    while [[ -n "$rest" ]]; do
        part=${rest%%/*}
        if [[ "$rest" == */* ]]; then rest=${rest#*/}; else rest=""; fi
        case "$part" in
            ''|.) ;;
            ..) (( ${#out[@]} )) && unset 'out[${#out[@]}-1]' ;;
            *) out+=("$part") ;;
        esac
    done
    local IFS=/
    printf '/%s' "${out[*]}"
}

# $1 relative to the root $2, or failure when $1 is not under $2
_ig_under_root() {
    [[ "$1" == "${2%/}/"* ]] || return 1
    printf '%s' "${1#"${2%/}"/}"
}

canonical_root=$(cd "$PROJECT_ROOT" 2>/dev/null && pwd -P) || canonical_root=""
logical_root=$(cd "$PROJECT_ROOT" 2>/dev/null && pwd -L) || logical_root=""
payload_cwd=$(jq -r '.cwd // empty | strings' <<<"$input" 2>/dev/null) || payload_cwd=""
if [[ "$file_path" == /* ]]; then
    abs_path=$file_path
else
    base_dir=${payload_cwd:-$logical_root}
    [[ "$base_dir" == /* ]] || base_dir="$logical_root/$base_dir"
    abs_path="${base_dir%/}/$file_path"
fi
canonical_path=""
logical_path=""
if [[ -n "$canonical_root" && -n "$logical_root" ]]; then
    # GNU realpath -m first (no component needs to exist), then readlink -f
    canonical_path=$(cd "$PROJECT_ROOT" 2>/dev/null \
        && { realpath -m -- "$abs_path" 2>/dev/null || readlink -f -- "$abs_path" 2>/dev/null; }) || canonical_path=""
    logical_path=$(realpath -m -s -- "$abs_path" 2>/dev/null) || logical_path=""
    [[ "$logical_path" == /* ]] || logical_path=$(_ig_lexical_norm "$abs_path")
fi
if [[ -z "$canonical_root" || -z "$canonical_path" ]]; then
    echo "[GATE] could not canonicalise tool_input.file_path; asking." >&2
    emit_ask "[GATE] could not canonicalise tool_input.file_path. Verify this write is intentional."
    exit 0
fi

# The root-relative forms, lowercased: on a case-insensitive filesystem (macOS default, ext4 casefold) Src/ is src/,
# and on a case-sensitive one this only adds asks for a directory literally named Src/ — tighten-only (run-3 finding 2)
rel_forms=()
if rel=$(_ig_under_root "$canonical_path" "$canonical_root"); then rel_forms+=("${rel,,}"); fi
if rel=$(_ig_under_root "$logical_path" "$logical_root"); then rel_forms+=("${rel,,}"); fi

# Audit-row copy of a model-authored value: raw, cut to 256 bytes on a character boundary; jq -a escapes the rest
cut_utf8_256 audit_file_path "$file_path"

# ---------------------------------------------------------------------------
# Trust inputs (run-3 finding 3): the files this gate and the run state read are
# writable through the same tool, so a write to one asks and leaves one
# compliance.state_write row — evaluated before the App-Zone test, since they
# are not App Zone. Everything else under .run/ and grimoires/ stays allow.
# ---------------------------------------------------------------------------
for rel in "${rel_forms[@]}"; do
    case "$rel" in
        .run/state.json|.run/sprint-plan-state.json|.run/simstim-state.json|.run/platform-features.json|.run/audit.jsonl|.loa.config.yaml)
            echo "[GATE] write to an implement-gate trust input '$(strip_controls "$file_path")'." >&2
            jq -nca \
                --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)" \
                --arg path "$audit_file_path" \
                '{timestamp: $ts, event: "compliance.state_write", file_path: $path}' \
                >> "$RUN_DIR/audit.jsonl" 2>/dev/null || true
            emit_ask "[GATE] write to an implement-gate trust input. Verify this write is intentional."
            exit 0
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Zone check: Is this an App Zone write?
# App Zone: src/, lib/, app/ in either root-relative form; a path whose two
# forms both fall outside the root is not App Zone
# ---------------------------------------------------------------------------
is_app_zone=false
for normalized_path in "${rel_forms[@]}"; do
    case "$normalized_path" in
        src/*|lib/*|app/*|*/src/*|*/lib/*|*/app/*)
            is_app_zone=true
            ;;
    esac
done

# Non-App-Zone writes always allowed
if [[ "$is_app_zone" == "false" ]]; then
    exit 0
fi

# Display copy only: control and format characters never reach stderr (n21, run-2 finding 3)
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
    active_skill=$(jq -j '.tool_input.active_skill // empty' <<<"$input" 2>/dev/null && printf x) || active_skill="x"
    active_skill=${active_skill%x}

    if [[ -n "$active_skill" ]]; then
        safe_skill=$(strip_controls "$active_skill")
        cut_utf8_256 audit_skill "$active_skill"
        # One model_signal row per invocation that carries a claim; the harness never sets the field,
        # so a row means a model wrote it (run-2 finding 6). The row holds the raw claim, ASCII-escaped (run-3 finding 4)
        log_model_signal() {
            jq -nca \
                --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)" \
                --arg skill "$audit_skill" \
                --arg path "$audit_file_path" \
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
# True when the ISO-8601 timestamp $1 parses and is at most 24 h (86400 s) old; empty or unparsable is stale
# (sprint-250 audit LOW-004: tighten-only)
_ig_fresh() {
    [[ -n "$1" ]] || return 1
    local now last_epoch
    now=$(date +%s 2>/dev/null) || return 1
    if type _date_to_epoch &>/dev/null; then
        last_epoch=$(_date_to_epoch "$1" 2>/dev/null) || last_epoch=""
    else
        last_epoch=$(date -d "$1" +%s 2>/dev/null || date -jf '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null) || last_epoch=""
    fi
    [[ "$last_epoch" =~ ^[0-9]+$ && "$now" =~ ^[0-9]+$ ]] || return 1
    (( last_epoch > 0 && now - last_epoch <= 86400 ))
}

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

    # Check simstim state; its writers (simstim-state.sh, simstim-orchestrator.sh) stamp .timestamps.last_activity,
    # and a stale or unstamped file falls through (LOW-004)
    if [[ -f "$RUN_DIR/simstim-state.json" ]]; then
        local phase simstim_activity
        phase=$(jq -r '.phase // empty' "$RUN_DIR/simstim-state.json" 2>/dev/null) || return 1
        simstim_activity=$(jq -r '.timestamps.last_activity // empty | strings' "$RUN_DIR/simstim-state.json" 2>/dev/null) || simstim_activity=""
        if [[ "$phase" == "implementation" ]] && _ig_fresh "$simstim_activity"; then
            return 0
        fi
    fi

    # Check run state; run-mode stamps .timestamps.last_activity (state-schemas.md), .updated_at is the fallback
    # run-preflight.sh reads too; a stale or unstamped file falls through (LOW-004)
    if [[ -f "$RUN_DIR/state.json" ]]; then
        local run_state run_activity
        run_state=$(jq -r '.state // empty' "$RUN_DIR/state.json" 2>/dev/null) || return 1
        run_activity=$(jq -r '.timestamps.last_activity // .updated_at // empty | strings' "$RUN_DIR/state.json" 2>/dev/null) || run_activity=""
        if [[ "$run_state" == "RUNNING" ]] && _ig_fresh "$run_activity"; then
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
