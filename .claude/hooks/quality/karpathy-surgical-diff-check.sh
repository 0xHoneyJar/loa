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
# malformed payload is a silent no-op. A symlinked or foreign-owned state
# directory, a symlinked state file, a summary directory that is not a real
# uid-owned directory, or a planted entry at the summary's temp name is not
# written through (Sprint 286 audit, bd-ooymp).
#
# Seams (tests): LOA_CONFIG_OVERRIDE (config), KARPATHY_STATE_DIR,
# KARPATHY_SUMMARY_FILE, KARPATHY_LEGACY_STATE, KARPATHY_TRAJECTORY_DIR,
# KARPATHY_CHECKPOINT_CMD (honoured only under a bats marker, BATS_TEST_FILENAME
# or BATS_VERSION; otherwise .claude/scripts/run-checkpoint.sh, which itself
# honours LOA_RUN_DIR), KARPATHY_STATE_KEEP (default 20).
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
CHECKPOINT="$REPO_ROOT/.claude/scripts/run-checkpoint.sh"
# KARPATHY_CHECKPOINT_CMD redirects the command this hook runs, so it is honoured only under a bats marker;
# outside bats it is ignored silently (no stderr: the output stays byte-identical) — cycle-138 FR-5, DEC-1158.
# The marker is a footgun guard for test fixtures, not a security boundary: the same uid already owns the
# session (DEC-1168).
[[ -n "${BATS_TEST_FILENAME:-}${BATS_VERSION:-}" && -n "${KARPATHY_CHECKPOINT_CMD:-}" ]] && CHECKPOINT="$KARPATHY_CHECKPOINT_CMD"
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
# Spawn diet: an id made only of [A-Za-z0-9._-] (every UUID) needs no JSON
# decode or encode — its JSON form is the bytes between two quotes — so the
# decode jq runs only for other payload ids and the encode jq only for other
# SESSION values (payload id, LOA_SESSION_ID or the USER-date fallback).
if [[ "${PAYLOAD_SID_JSON:-\"\"}" =~ ^\"([A-Za-z0-9._-]*)\"$ ]]; then
    payload_sid="${BASH_REMATCH[1]}"
else
    payload_sid="$(printf '%s' "${PAYLOAD_SID_JSON:-\"\"}" | jq -r '.' 2>/dev/null)" || payload_sid=""
fi
SESSION="${payload_sid:-${LOA_SESSION_ID:-}}"
[[ -n "$SESSION" ]] || SESSION="${USER:-unknown}-${TS:0:4}${TS:5:2}${TS:8:2}"
if [[ "$SESSION" =~ ^[A-Za-z0-9._-]+$ ]]; then
    SESSION_JSON="\"$SESSION\""
else
    SESSION_JSON="$(jq -cn --arg s "$SESSION" '$s')"
fi

task_raw=""
if [[ -f "$CHECKPOINT" ]]; then
    task_raw="$(bash "$CHECKPOINT" read --json 2>/dev/null \
        | jq -r '[.checkpoint.task?, .checkpoint.sprint?, .sprint?] | map(select(type == "string" and . != ""))
                  | .[0] // empty | gsub("[^A-Za-z0-9._-]"; "_")' 2>/dev/null)" || task_raw=""
    task_raw="${task_raw%%$'\n'*}"   # first line only (the former `| head -1`, without the fork)
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
# The state directory must be OURS (Sprint 286 audit DISS-C-002, bd-ooymp): a directory owned by another uid — however
# writable — is refused before anything is read or appended (one builtin stat; the file keeps its -L guard below). The
# same-directory check→`>>` race inside a writable uid-owned directory stays with bd-ooymp (the Task 3.6 fd pattern).
[[ -O "$STATE_DIR" ]] || exit 0
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
# Sprint 286 audit DISS-C-001 (bd-ooymp). The temp file was opened with `>` — open(O_WRONLY|O_CREAT|O_TRUNC), which
# follows a symlink at the name — after a `-d` test on its directory alone, so a symlink planted at the predictable
# `<summary>.tmp.<pid>` was truncated, overwritten with the JSON and then renamed over the summary path (rename(2)
# renames the link itself). The root cause is the open's flags and the directory's trust, not the name: an
# unpredictable name would only hide the window. Builtins only, no spawn added, in `_summary_write`:
#   (1) the directory is a real, uid-owned, non-symlink directory and the summary path is not a directory (`mv` would
#       move the temp INTO one);
#   (2) the temp name is truly absent — lstat (`-L`) and stat (`-e`): a dangling symlink, a FIFO, a device or a
#       regular file already there is not ours and is left alone;
#   (3) the open runs under noclobber: bash's noclobber_open (redir.c) stat()s the name and, when nothing is there,
#       opens O_WRONLY|O_CREAT|O_EXCL — open(2): with O_CREAT|O_EXCL a symbolic link at the name fails the open
#       "regardless of where the symbolic link points" — and refuses a regular file that appeared in between;
#   (4) the bytes go through the descriptor we hold, and before the rename the path must still be the regular
#       non-symlink uid-owned file we created (a swap in the write→rename window is refused and the temp removed);
#   (5) `mv -f` is rename(2): a symlink at the summary path is replaced by our file, never followed.
# Any refusal skips the summary write silently (exit 0: the warning below still prints and the state append above has
# already happened). Residual, as for the trajectory guard (Task 3.6): noclobber adds O_EXCL only when bash's own stat
# fails, so a symlink to a FIFO or a device planted INSIDE the lstat→open window is opened without O_EXCL (pure bash
# has no O_NOFOLLOW); step (2) refuses one present before it, step (4) refuses the rename after it.
_summary_write() {
    local tmp="$SUMMARY.tmp.$$" nc=0 rc=1 fd=""
    [[ -d "$sum_dir" && ! -L "$sum_dir" && -O "$sum_dir" && ! -d "$SUMMARY" ]] || return 1
    [[ ! -L "$tmp" && ! -e "$tmp" ]] || return 1
    [[ -o noclobber ]] && nc=1
    set -o noclobber; { exec {fd}>"$tmp"; } 2>/dev/null; rc=$?; (( nc )) || set +o noclobber
    (( rc == 0 )) || return 1
    if printf '{"task":"%s","lines":%s,"threshold":%s,"over":%s,"updated_at":"%s"}\n' \
            "$KEY" "$RUNNING" "$THRESHOLD" "$OVER" "$TS" >&"$fd" 2>/dev/null \
       && [[ -f "$tmp" && ! -L "$tmp" && -O "$tmp" ]]; then
        { exec {fd}>&-; } 2>/dev/null
        mv -f -- "$tmp" "$SUMMARY" 2>/dev/null || rm -f -- "$tmp" 2>/dev/null
    else
        { exec {fd}>&-; } 2>/dev/null
        rm -f -- "$tmp" 2>/dev/null
    fi
    return 0
}
if [[ -d "$sum_dir" ]] || mkdir -p "$sum_dir" 2>/dev/null; then
    _summary_write
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
    # The append goes only through a trusted path (cycle-138 FR-6, SDD § 5.5, DEC-1168): TRAJ_DIR inside the
    # checkout and anchored at the canonical root (no `.`/`..`/empty component in the relative path; no symlinked
    # component below the root — `cd` + `pwd -P` on the two existing directories, builtins; a failing cd → refuse, no
    # fallback); every directory below the root and the day file read by ONE stat (rows keyed by %n, rc
    # ignored: `stat -L` prints a row for each path that exists); each component a uid-owned non-symlink
    # directory (its mode is not tested: a checkout's directories inherit the clone umask, and the checkout
    # root is the trust root — DEC-1166); the day file is opened FIRST (O_APPEND, or O_CREAT|O_EXCL under noclobber
    # when truly absent) and the OPENED descriptor verified — uid-owned regular file, one link, no group/other write,
    # same device:inode as the path's lstat row (Sprint 285 audit DISS-001). Otherwise the append is skipped silently
    # — the warning above is printed regardless. Warn path only: two cd/pwd -P subshells (builtins) + stat x3 (the
    # component chain; the descriptor; the path lstat) (+ mkdir once when the directory is absent).
    # The state directory and task file keep their -L guards above (out of FR-6's scope).
    _traj_trusted() {
        local rel root_real real comp st row name uid mode links i n ftype ino pathrow pt rc nc
        local -a comps=() rows=()
        [[ "$TRAJ_DIR" == "$REPO_ROOT/"* ]] || return 1
        rel="${TRAJ_DIR#"$REPO_ROOT/"}"
        # No `.`, `..` or empty component below the root (Sprint 285 review round 2, DISS-C-002): a `..` passes the
        # prefix test above and would let the mkdir below create a directory OUTSIDE the checkout before the canonical
        # check refused the append.
        case "/$rel/" in *//*|*/./*|*/../*) return 1 ;; esac
        comp="$REPO_ROOT"
        while [[ -n "$rel" ]]; do
            comp="$comp/${rel%%/*}"
            comps+=("$comp")
            [[ "$rel" == */* ]] && rel="${rel#*/}" || rel=""
        done
        if [[ ! -d "$TRAJ_DIR" ]]; then
            # the existing ancestors first (builtins; their modes are read by the stat below): a real directory owned by us
            for comp in "${comps[@]}"; do
                [[ -e "$comp" || -L "$comp" ]] || break
                [[ -d "$comp" && ! -L "$comp" && -O "$comp" ]] || return 1
            done
            ( umask 077; mkdir -p -- "$TRAJ_DIR" ) 2>/dev/null || return 1
        fi
        # Canonical path of the two EXISTING directories with the shell's own `cd` + `pwd -P` (builtins — no realpath(1)
        # at all: `realpath -m` was GNU-only, plain `realpath --` fails on busybox and realpath is absent on older
        # macOS; Sprint 285 review DISS-C-003, rounds 1 and 2). Both paths are absolute, so CDPATH never applies; a
        # failing cd (a component without search permission) still refuses.
        root_real=$(cd -- "$REPO_ROOT" 2>/dev/null && pwd -P) || return 1
        real=$(cd -- "$TRAJ_DIR" 2>/dev/null && pwd -P) || return 1
        [[ -n "$root_real" && -n "$real" && "$real" == "$root_real/${TRAJ_DIR#"$REPO_ROOT/"}" ]] || return 1   # (rel was consumed by the component loop above)
        TRAJ_FILE="$TRAJ_DIR/karpathy-${TS:0:10}.jsonl"
        # (1) The directory chain FIRST — ONE `stat -L` over the components; nothing is opened or created unless every
        #     component is a uid-owned real directory (rows keyed by %n, in argument order).
        st=$(stat -Lc '%n|%u|%a|%h|%d:%i|%F' -- "${comps[@]}" 2>/dev/null)
        [[ -n "$st" ]] || st=$(stat -Lf '%N|%u|%Lp|%l|%d:%i|%HT' -- "${comps[@]}" 2>/dev/null)
        while IFS= read -r row; do rows+=("$row"); done <<< "$st"
        n=${#comps[@]}
        (( ${#rows[@]} == n )) || return 1
        i=0
        for row in "${rows[@]}"; do
            _traj_row "$row" || return 1
            [[ "$uid" == "$EUID" && "$name" == "${comps[i]}" && -d "$name" && ! -L "$name" ]] || return 1
            i=$((i + 1))
        done
        # (2) Open FIRST, verify the OPENED file after (Sprint 285 audit DISS-001, bd-7ihly, DEC-1192): a check-then-`>>`
        #     pair let a party able to write the directory swap the checked file for a symlink in between. Builtin
        #     pre-checks (lstat semantics) choose the open: an existing regular non-symlink file is opened O_APPEND; a
        #     truly absent path is created under noclobber (O_CREAT|O_EXCL — never follows a symlink planted in the
        #     window), 0600 under the hook's umask 077; anything else (symlink, dangling symlink, FIFO, directory) is
        #     refused unopened. The exclusive create has no O_APPEND (`>`), so after it the descriptor is CLOSED and
        #     the now-existing regular file is reopened O_APPEND — otherwise a sibling hook's `>>` event written between
        #     our create and our write would be overwritten at offset zero (Sprint 286 review DISS-001); step (3) still
        #     verifies what was reopened. A creator that loses the O_EXCL race (EEXIST) takes the append branch on the
        #     file it lost to instead of dropping its event (DISS-C-002).
        if [[ ! -e "$TRAJ_FILE" && ! -L "$TRAJ_FILE" ]]; then
            nc=0; [[ -o noclobber ]] && nc=1
            set -o noclobber; { exec {TRAJ_FD}>"$TRAJ_FILE"; } 2>/dev/null; rc=$?; (( nc )) || set +o noclobber
            if (( rc == 0 )); then { exec {TRAJ_FD}>&-; } 2>/dev/null; TRAJ_FD=""; fi
            # rc != 0: EEXIST from a sibling's create, or a planted entry — the append branch below decides
        fi
        if [[ -f "$TRAJ_FILE" && ! -L "$TRAJ_FILE" ]]; then
            { exec {TRAJ_FD}>>"$TRAJ_FILE"; } 2>/dev/null || return 1
        else
            return 1
        fi
        # (3) The DESCRIPTOR's row (/dev/fd/N — the fstat of what we hold: uid, regular, one link, no g/o write) and an
        #     lstat of the path, which must still name a regular file on the same device:inode — so the bytes go to the
        #     file the path names and never to something a swap substituted. Residuals, for a party already able to
        #     write inside the trust root (DEC-1166 / DEC-1185) who wins the pre-check→open window: a planted symlink makes
        #     the O_APPEND open create its (empty) 0600 target before the mismatch refuses; a planted FIFO (or a symlink
        #     to one) BLOCKS the open until the hook timeout — bash's noclobber adds O_EXCL only when its own stat fails,
        #     and `>>` never has it; pure bash has no O_NONBLOCK / O_NOFOLLOW open, so the window itself cannot be closed
        #     here (Sprint 286 review DISS-C-001). A FIFO present BEFORE the pre-check is refused unopened (KT-9).
        row=$(stat -Lc '%n|%u|%a|%h|%d:%i|%F' -- "/dev/fd/$TRAJ_FD" 2>/dev/null) || row=$(stat -Lf '%N|%u|%Lp|%l|%d:%i|%HT' -- "/dev/fd/$TRAJ_FD" 2>/dev/null) || return 1
        pathrow=$(stat -c '%d:%i|%F' -- "$TRAJ_FILE" 2>/dev/null) || pathrow=$(stat -f '%d:%i|%HT' -- "$TRAJ_FILE" 2>/dev/null) || return 1
        _traj_row "$row" || return 1
        # GNU stat prints "regular empty file" for a 0-byte file (the one we just created), BSD "Regular File"
        [[ "$name" == "/dev/fd/$TRAJ_FD" && "$uid" == "$EUID" && "${ftype,,}" == regular*file && "$links" == 1 ]] || return 1
        (( (8#$mode & 8#022) == 0 )) || return 1
        pt="${pathrow##*|}"
        [[ "$pathrow" == "$ino|"* && "${pt,,}" == regular*file ]] || return 1
        return 0
    }
    # _traj_row <row>: split `name|uid|mode|links|dev:ino|type` from the right (a name may hold `|`) into the caller's
    # name uid mode links ino ftype; validates the numeric fields. Dynamic scoping: the caller's locals receive them.
    _traj_row() {
        local r="$1"
        ftype="${r##*|}"; r="${r%|*}"
        ino="${r##*|}"; r="${r%|*}"
        links="${r##*|}"; r="${r%|*}"
        mode="${r##*|}"; r="${r%|*}"
        uid="${r##*|}"; name="${r%|*}"
        [[ "$uid" =~ ^[0-9]+$ && "$mode" =~ ^[0-7]+$ && "$links" =~ ^[0-9]+$ && "$ino" =~ ^[0-9]+:[0-9]+$ ]]
    }
    TRAJ_FILE=""; TRAJ_FD=""
    if _traj_trusted; then
        printf '{"phase":"karpathy_check","principle":"surgical_changes","timestamp":"%s","files_modified":%s,"lines_total":%s,"threshold":%s,"verdict":"warn","tool_call_count":%s,"session_id":%s}\n' \
            "$TS" "$FILES_MOD" "$RUNNING" "$THRESHOLD" "$TOOL_CALLS" "$SESSION_JSON" \
            >&"$TRAJ_FD" 2>/dev/null || true
    fi
    [[ -n "$TRAJ_FD" ]] && { exec {TRAJ_FD}>&-; } 2>/dev/null
fi

exit 0
