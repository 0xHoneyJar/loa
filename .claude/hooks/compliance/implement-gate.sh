#!/usr/bin/env bash
# =============================================================================
# implement-gate.sh — Dual-mode compliance hook for App Zone writes (FR-7)
# =============================================================================
# Checks whether Write/Edit to App Zone files occurs within an active
# /implement or /bug skill invocation.
#
# Modes (cycle-129 D-4.1, DEC-0163; .loa.config.yaml implement_gate.mode):
#   ask (default; unset or any other value): an unsanctioned App-Zone write asks,
#       exactly as before, and now logs one row (decision "ask").
#   telemetry: an unsanctioned App-Zone write logs one row (action "telemetry",
#       decision "outside_run") and is allowed silently.
#   deny: an unsanctioned App-Zone write is DENIED when the run position is
#       known: .run/sprint-plan-state.json parses and its derived_at is within
#       run_mode.stale_hours (12). The gate is a fence only in this mode. An
#       unknown position (cache missing, not derived, stale or unparseable)
#       falls back to ask (decision "unknown_position"), never to allow.
# Sanction (any mode; first match wins; one row each, action "allow"):
#   sanctioned_run    — the heuristic below: a fresh RUNNING cache, and its
#                       derived_at (when present) within run_mode.stale_hours
#   sanctioned_marker — .run/implement-active.json {skill: implement|bug, sprint,
#                       started_at} with started_at within two hours (written by
#                       `run-checkpoint.sh mark`, removed by `unmark`); a stale or
#                       malformed marker logs decision "stale_marker" and does not sanction
#   override          — LOA_IMPLEMENT_GATE_OVERRIDE=1 in the hook's environment
# Rows go to .run/audit.jsonl as {ts, hook: "implement-gate", action, decision,
# mode, path} with path control-stripped and cut to 256 bytes; LOA_AUDIT_REPLAY=1
# adds replay: true to every row this gate writes (DEC-0167).
#
# Claims modifier (implement_gate.claims: authoritative; the legacy
# implement_gate.mode: authoritative means mode ask + claims authoritative):
#   reads tool_input.active_skill from hook stdin. The PreToolUse
#      payload carries no harness-set skill field (cycle-126 D-4.4) and tool_input
#      is model-authored, so nothing in .run/ selects this modifier.
#      TIGHTEN-ONLY (sprint-250 audit n17/n18): the model-authored claim can only
#      add an ask, never grant an allow. A claimed implementation skill falls
#      through to the heuristic exactly like an absent field; a claimed
#      non-implementation skill asks (or, under deny with a known position and no
#      sanction, is denied) and logs compliance.mode.model_signal to
#      .run/audit.jsonl (plain hook log, not the signed audit_emit chain). Every
#      claim leaves one row per invocation: decision "ask"/"deny" for a non-implementation
#      claim, decision "heuristic" for an implementation claim (run-2 finding 6).
#
# `implement-gate.sh --effective-mode [CONFIG]` prints the effective mode (and the
# claims modifier) without reading stdin — the /loa Gate line.
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
# .run/simstim-state.json, .run/platform-features.json, .run/audit.jsonl,
# .run/implement-active.json or .loa.config.yaml asks in every mode and under
# every sanction, and logs compliance.state_write (run-3 finding 3).
# Other non-App-Zone writes always allowed.
#
# Output (Claude Code PreToolUse contract, sprint-250 audit n20): allow = silent
# exit 0 with empty stdout; ask = exit 0 with
#   {"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"…"}}
# deny = the same shape with "permissionDecision":"deny".
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

# Read tool input from stdin (not for --effective-mode, which reads no payload)
input=""
if [[ "${1:-}" != "--effective-mode" ]]; then
    input=$(cat 2>/dev/null) || input=""
fi

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
# byte, so a byte-wise match never lands inside another character
# printf -v keeps this portable (no GNU-sed \x); built on first use, not on every Write/Edit (BB-008)
_IG_STRIP_SEQS=()
_ig_strip_seqs_init() {
    local _ig_i _ig_hex _ig_seq
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
}

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
    (( ${#_IG_STRIP_SEQS[@]} )) || _ig_strip_seqs_init
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

# ---------------------------------------------------------------------------
# Mode and claims (cycle-129 D-4.1): one yq call, read only when a decision
# needs it. Unset, unreadable or unknown values are ask; the legacy
# mode: authoritative is ask + claims: authoritative. run_mode.stale_hours
# bounds derived_at (positive integer, default 12).
# ---------------------------------------------------------------------------
gate_mode="ask"
gate_claims="plain"
gate_stale_hours=12
load_gate_config() {
    local cfg="${1:-$PROJECT_ROOT/.loa.config.yaml}" raw m c s
    command -v yq &>/dev/null && command -v jq &>/dev/null && [[ -f "$cfg" ]] || return 0
    # mikefarah yq v4 first; the python yq wrapper (jq syntax, JSON out) second
    raw=$(yq -o json -I 0 '{"m": .implement_gate.mode, "c": .implement_gate.claims, "s": .run_mode.stale_hours}' "$cfg" 2>/dev/null) \
        || raw=$(yq -c '{"m": .implement_gate.mode, "c": .implement_gate.claims, "s": .run_mode.stale_hours}' "$cfg" 2>/dev/null) \
        || return 0
    m=$(jq -r '.m | strings' <<<"$raw" 2>/dev/null) || m=""
    c=$(jq -r '.c | strings' <<<"$raw" 2>/dev/null) || c=""
    s=$(jq -r '.s | numbers | tostring' <<<"$raw" 2>/dev/null) || s=""
    case "$m" in
        ask|telemetry|deny) gate_mode="$m" ;;
        authoritative) gate_claims="authoritative" ;;
    esac
    [[ "$c" == "authoritative" ]] && gate_claims="authoritative"
    if [[ "$s" =~ ^[0-9]{1,4}$ ]] && (( 10#$s > 0 && 10#$s <= 8760 )); then gate_stale_hours=$(( 10#$s )); fi
    return 0
}

if [[ "${1:-}" == "--effective-mode" ]]; then
    load_gate_config "${2:-}"
    if [[ "$gate_claims" == "authoritative" ]]; then echo "$gate_mode (claims: authoritative)"; else echo "$gate_mode"; fi
    exit 0
fi

# Row helpers: LOA_AUDIT_REPLAY=1 marks every row this gate writes (DEC-0167)
_ig_replay_json='{}'
[[ "${LOA_AUDIT_REPLAY:-}" == "1" ]] && _ig_replay_json='{"replay":true}'

# One jq pass over the payload yields every field the gate reads from it: the parse verdict, the recorder's lead-session
# test, tool_input.file_path (else notebook_path) and cwd, each NUL-terminated so a value keeps its newlines (read -d ''
# keeps them; a $(...) would not). _ig_mode: F = one parsed value and plain-string fields (use them), U = one value jq -e .
# calls unparsable (null or false), anything else (no jq, parse error, none or several values, a non-string path, a NUL in
# the path or cwd) = L: the separate jq calls below decide exactly as before.
_ig_mode="" _ig_lead="" _ig_path="" _ig_cwd=""
if command -v jq &>/dev/null; then
    { IFS= read -r -d '' _ig_mode; IFS= read -r -d '' _ig_lead; IFS= read -r -d '' _ig_path; IFS= read -r -d '' _ig_cwd; } < <(
        jq -nj 'def nul: any(explode[]; . == 0);
            [inputs] as $a
            | (if ($a | length) != 1 then null else $a[0] end) as $p
            | if ($a | length) != 1 then ["L", "", "", ""]
              elif ($p == null or $p == false) then ["U", "0", "", ""]
              else
                ([$p | .tool_input.file_path // .tool_input.notebook_path // empty]) as $f
                | ([$p | .cwd // empty | strings]) as $c
                | if ($f | length) > 1 or ($f | any(type != "string" or nul)) or ($c | any(nul)) then ["L", "", "", ""]
                  else ["F",
                        ($p | if (.tool_input.active_skill // "") != "" and (.agent_id // "") == "" then "1" else "0" end),
                        ($f[0] // ""), ($c[0] // "")]
                  end
              end
            | .[] | ., ([0] | implode)' <<<"$input" 2>/dev/null
    )
fi

# True when the payload is a lead-session claim: tool_input.active_skill set and no subagent agent_id
_ig_lead_claim() {
    if [[ "$_ig_mode" == [FU] ]]; then [[ "$_ig_lead" == 1 ]]; return; fi
    jq -e '(.tool_input.active_skill // "") != "" and (.agent_id // "") == ""' <<<"$input" >/dev/null 2>&1
}

# Evidence recorder: lead session only (no teammate role, no subagent agent_id), once, atomic.
if [[ -z "${LOA_TEAM_MEMBER:-}" && -d "$RUN_DIR" ]] \
    && _ig_lead_claim \
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
if ! command -v jq &>/dev/null || [[ "$_ig_mode" == U ]] \
    || { [[ "$_ig_mode" != F ]] && ! jq -e . <<<"$input" >/dev/null 2>&1; }; then
    echo "[GATE] could not evaluate tool_input (jq missing or payload unparsable)." >&2
    emit_ask "[GATE] could not evaluate tool_input. Verify this write is intentional."
    exit 0
fi

# Extract the path: Write/Edit/MultiEdit carry file_path, NotebookEdit carries notebook_path. jq -j plus a sentinel
# byte keeps a trailing newline, which $(...) would otherwise strip from the raw value (run-3 finding 4)
if [[ "$_ig_mode" == F ]]; then
    file_path=$_ig_path
elif ! file_path=$(jq -j '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$input" 2>/dev/null && printf x); then
    echo "[GATE] could not evaluate tool_input (path not readable)." >&2
    emit_ask "[GATE] could not evaluate tool_input. Verify this write is intentional."
    exit 0
else
    file_path=${file_path%x}
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
if [[ "$_ig_mode" == F ]]; then
    payload_cwd=$_ig_cwd
    while [[ "$payload_cwd" == *$'\n' ]]; do payload_cwd=${payload_cwd%$'\n'}; done   # as $(...) strips them
else
    payload_cwd=$(jq -r '.cwd // empty | strings' <<<"$input" 2>/dev/null) || payload_cwd=""
fi
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
# bash 3.2 has no lowercase parameter expansion (BB-001: a bad substitution there left rel_forms empty and the hook exited 0); LC_ALL=C so a
# BSD tr never stops at a byte that is not valid UTF-8 ("Illegal byte sequence") — the patterns are ASCII
_ig_lower() { printf '%s' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]'; }
rel_forms=()
if rel=$(_ig_under_root "$canonical_path" "$canonical_root"); then rel_forms+=("$(_ig_lower "$rel")"); fi
if rel=$(_ig_under_root "$logical_path" "$logical_root"); then rel_forms+=("$(_ig_lower "$rel")"); fi

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
        .run/state.json|.run/sprint-plan-state.json|.run/simstim-state.json|.run/platform-features.json|.run/audit.jsonl|.run/implement-active.json|.loa.config.yaml)
            echo "[GATE] write to an implement-gate trust input '$(strip_controls "$file_path")'." >&2
            # Asks in every mode and under every sanction; the row is counted as an ask by the register
            load_gate_config
            jq -nca \
                --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)" \
                --arg path "$audit_file_path" \
                --arg mode "$gate_mode" \
                --argjson replay "$_ig_replay_json" \
                '{timestamp: $ts, event: "compliance.state_write", file_path: $path,
                  hook: "implement-gate", action: "ask", decision: "trust_input", mode: $mode} + $replay' \
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
# Mode and claims from .loa.config.yaml (cycle-129 D-4.1; cycle-126 D-4.4)
# ---------------------------------------------------------------------------
load_gate_config

# One decision row per App-Zone write: {ts, hook, action, decision, mode, path}; path is the display copy
# (control-stripped, at most 256 bytes) and jq -a escapes any non-ASCII left in it
log_gate_row() {
    jq -nca \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)" \
        --arg action "$1" \
        --arg decision "$2" \
        --arg mode "$gate_mode" \
        --arg claims "$gate_claims" \
        --arg path "$safe_file_path" \
        --argjson replay "$_ig_replay_json" \
        '{ts: $ts, hook: "implement-gate", action: $action, decision: $decision, mode: $mode, path: $path}
         + (if $claims == "authoritative" then {claims: $claims} else {} end) + $replay' \
        >> "$RUN_DIR/audit.jsonl" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Claims modifier: read active_skill from hook input (tighten-only)
# ---------------------------------------------------------------------------
claim_ask=0
if [[ "$gate_claims" == "authoritative" ]]; then
    active_skill=$(jq -j '.tool_input.active_skill // empty' <<<"$input" 2>/dev/null && printf x) || active_skill="x"
    active_skill=${active_skill%x}

    if [[ -n "$active_skill" ]]; then
        safe_skill=$(strip_controls "$active_skill")
        cut_utf8_256 audit_skill "$active_skill"
        # One model_signal row per invocation that carries a claim; the harness never sets the field,
        # so a row means a model wrote it (run-2 finding 6). The row holds the raw claim, ASCII-escaped (run-3 finding 4).
        # An ask or deny row also carries hook/action so the register counts it as the write's decision row
        log_model_signal() {
            jq -nca \
                --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)" \
                --arg skill "$audit_skill" \
                --arg path "$audit_file_path" \
                --arg decision "$1" \
                --arg gmode "$gate_mode" \
                --argjson replay "$_ig_replay_json" \
                '{timestamp: $ts, event: "compliance.mode.model_signal", mode: "authoritative", active_skill: $skill, file_path: $path, decision: $decision}
                 + (if $decision == "ask" or $decision == "deny" then {hook: "implement-gate", action: $decision, gate_mode: $gmode} else {} end) + $replay' \
                >> "$RUN_DIR/audit.jsonl" 2>/dev/null || true
        }
        case "$active_skill" in
            implement|/implement|bug|/bug|run|/run|simstim|/simstim)
                # Tighten-only (n17/n18): a model-authored implementation claim never
                # allows by itself — log it, then fall through to the heuristic check below
                log_model_signal heuristic
                ;;
            *)
                # Non-implementation skill: asks whatever the sanction (decided below, where deny can still apply)
                claim_ask=1
                ;;
        esac
    else
        # active_skill field absent despite the claims modifier — fall back to heuristic
        # Log the downgrade
        log_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || log_ts="unknown"
        jq -nc \
            --arg ts "$log_ts" \
            --arg from "authoritative" \
            --arg to "heuristic" \
            --arg reason "active_skill field absent in hook input" \
            --argjson replay "$_ig_replay_json" \
            '{timestamp: $ts, event: "compliance.mode.fallback", from_mode: $from, to_mode: $to, reason: $reason} + $replay' \
            >> "$RUN_DIR/audit.jsonl" 2>/dev/null || true
    fi
    # Fall through to heuristic check below
fi

# ---------------------------------------------------------------------------
# Heuristic mode: Is an /implement or /bug skill currently active?
# Check .run/sprint-plan-state.json, .run/simstim-state.json, .run/state.json
# ---------------------------------------------------------------------------
# True when the ISO-8601 timestamp $1 parses and is within 24 h (86400 s) of now, either side; empty or unparsable is stale
# (sprint-250 audit LOW-004: tighten-only; LOW-006: a future-dated stamp is not fresh forever)
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
    (( last_epoch > 0 && now - last_epoch <= 86400 && last_epoch - now <= 86400 ))
}

# True when the ISO-8601 timestamp $2 parses, is at most $1 seconds old and at most 300 s ahead (clock skew);
# jq's fromdateiso8601 keeps it portable (no GNU date -d). Fractional seconds are dropped first
_ig_within() {
    [[ -n "$2" && "$1" =~ ^[0-9]+$ ]] || return 1
    jq -en --arg t "$2" --argjson w "$1" \
        '($t | sub("\\.[0-9]+Z$"; "Z") | try fromdateiso8601 catch null) as $e | $e != null and (now - $e) <= $w and ($e - now) <= 300' \
        >/dev/null 2>&1
}

# derived_at, when a cache carries one, must be within run_mode.stale_hours (cycle-129 D-4.1)
_ig_derived_ok() {
    local da
    da=$(jq -r '.derived_at // empty | strings' "$1" 2>/dev/null) || da=""
    [[ -z "$da" ]] && return 0
    _ig_within $(( gate_stale_hours * 3600 )) "$da"
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

        # Integrity: check staleness (within 24 h either side, via _ig_fresh); an absent or unparsable
        # last_activity is stale too (sprint-250 audit LOW-006: the check was skipped, so RUNNING + plan_id allowed)
        last_activity=$(jq -r '.timestamps.last_activity // empty' "$RUN_DIR/sprint-plan-state.json" 2>/dev/null) || last_activity=""
        if ! _ig_fresh "$last_activity"; then
            return 1  # Stale, future-dated or unstamped state
        fi

        # A derived cache older than run_mode.stale_hours is not a run position (cycle-129 D-4.1)
        if ! _ig_derived_ok "$RUN_DIR/sprint-plan-state.json"; then
            return 1
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
        if [[ "$run_state" == "RUNNING" ]] && _ig_fresh "$run_activity" && _ig_derived_ok "$RUN_DIR/state.json"; then
            return 0
        fi
    fi

    return 1
}

# The implementing skills' marker (run-checkpoint.sh mark): 0 fresh and well-formed, 1 absent, 2 stale or malformed
check_implement_marker() {
    local f="$RUN_DIR/implement-active.json" started
    [[ -f "$f" ]] || return 1
    jq -e '(.skill == "implement" or .skill == "bug") and (.sprint | type == "string" and test("^[A-Za-z0-9._-]{1,64}$"))' "$f" >/dev/null 2>&1 || return 2
    started=$(jq -r '.started_at // empty | strings' "$f" 2>/dev/null) || started=""
    _ig_within 7200 "$started" || return 2
    return 0
}

# The derived run position for deny: known only when .run/sprint-plan-state.json parses and carries a derived_at
# within run_mode.stale_hours; sets position_state (display copy) or position_why
position_state=""
position_why=""
read_position() {
    local f="$RUN_DIR/sprint-plan-state.json" da st
    if [[ ! -f "$f" ]]; then position_why="cache missing"; return 1; fi
    if ! jq -e 'type == "object"' "$f" >/dev/null 2>&1; then position_why="cache unparseable"; return 1; fi
    da=$(jq -r '.derived_at // empty | strings' "$f" 2>/dev/null) || da=""
    if [[ -z "$da" ]]; then position_why="cache not derived"; return 1; fi
    if ! _ig_within $(( gate_stale_hours * 3600 )) "$da"; then position_why="cache older than run_mode.stale_hours"; return 1; fi
    st=$(jq -r '.state // .status // empty | strings' "$f" 2>/dev/null) || st=""
    position_state=$(strip_controls "${st:-unknown}")
    [[ -n "$position_state" ]] || position_state="unknown"
    return 0
}

emit_deny() {
    jq -nc --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
}
deny_reason() {
    printf 'App Zone write with no active implementation run (derived position: %s); run /implement or /bug, or set implement_gate.mode: ask' "$position_state"
}

# ---------------------------------------------------------------------------
# Sanction: a fresh RUNNING cache, a fresh implementing-skill marker, or the
# operator's override, in that order — one row for the path that sanctioned
# ---------------------------------------------------------------------------
sanction=""
if check_implementation_active; then
    sanction="sanctioned_run"
else
    check_implement_marker
    marker_rc=$?
    if (( marker_rc == 0 )); then
        sanction="sanctioned_marker"
    elif [[ "${LOA_IMPLEMENT_GATE_OVERRIDE:-}" == "1" ]]; then
        sanction="override"
    fi
    (( marker_rc == 2 )) && log_gate_row note stale_marker
fi

# ---------------------------------------------------------------------------
# A non-implementation claim asks whatever the sanction; under deny with a
# known position and no sanction it is denied (tighten-only: never looser)
# ---------------------------------------------------------------------------
if (( claim_ask )); then
    if [[ "$gate_mode" == "deny" && -z "$sanction" ]] && read_position; then
        echo "[AUTHORITATIVE] App Zone write to '$safe_file_path' denied during /$safe_skill (not an implementation skill; derived position: $position_state)." >&2
        log_model_signal deny
        emit_deny "$(deny_reason)"
        exit 0
    fi
    echo "[AUTHORITATIVE] App Zone write to '$safe_file_path' detected during /$safe_skill (not an implementation skill)." >&2
    log_model_signal ask
    emit_ask "[AUTHORITATIVE] App Zone write outside implementation skill. Verify this is intentional."
    exit 0
fi

# ---------------------------------------------------------------------------
# Decision
# ---------------------------------------------------------------------------
if [[ -n "$sanction" ]]; then
    # Implementation is active (or the operator overrode) — allow the write, one row
    log_gate_row allow "$sanction"
    exit 0
fi

case "$gate_mode" in
    telemetry)
        # Log and allow, silently
        log_gate_row telemetry outside_run
        exit 0
        ;;
    deny)
        if read_position; then
            echo "[GATE] App Zone write to '$safe_file_path' denied: no active implementation run (derived position: $position_state)." >&2
            log_gate_row deny deny
            emit_deny "$(deny_reason)"
            exit 0
        fi
        # Unknown position: ask, never allow
        echo "[GATE] App Zone write to '$safe_file_path' outside an active run; run position unknown ($position_why), asking instead of denying." >&2
        log_gate_row ask unknown_position
        emit_ask "[ADVISORY] App Zone write outside active implementation; run position unknown ($position_why). Verify this is intentional."
        exit 0
        ;;
    *)
        # No active implementation detected — ADVISORY ask (unchanged), now counted
        echo "[ADVISORY] App Zone write to '$safe_file_path' detected outside active /implement or /bug." >&2
        echo "No RUNNING state found in .run/ state files. This may bypass review gates." >&2
        log_gate_row ask ask
        echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"[ADVISORY] App Zone write outside active implementation. Verify this is intentional."}}'
        exit 0
        ;;
esac
