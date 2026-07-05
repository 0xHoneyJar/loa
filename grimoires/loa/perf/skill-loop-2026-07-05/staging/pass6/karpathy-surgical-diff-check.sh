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
#   - file_path is JSON-escaped inside jq (tojson — the same encoder the old
#     `jq --arg` path used) — no shell-injection vector.
#   - Hook MUST exit 0 even when yq/jq are missing or config is malformed
#     (graceful degradation; never break Write/Edit due to hook env issues).
#
# perf pass-3 (2026-07-05, skill-loop): jq/yq single-pass consolidation.
# Was (warn regime, the production steady state): yq x2 + jq x7 + wc x2 +
# tr x2 + cat + date x3 + awk. Now: yq x1 + jq x1 + awk + mkdir/dirname.
# Design + isomorphism notes:
#   - ONE yq derives two guaranteed-single-line decision tokens: (1) whether
#     the master switch renders as an explicit false-equivalent (the same
#     ten-token list the old bash `case` matched against the $()-stripped
#     rendering — tostring + sub("\n+$";"") reproduces that stripping), and
#     (2) the threshold rendering when it matches ^[0-9]+$, else "DEFAULT"
#     (the old bash regex guard, applied inside yq so multi-line values
#     cannot pollute line-based token reads). A grep-style "config lacks the
#     key" pre-check was REJECTED: YAML double-quoted keys can be spelled
#     with escape sequences, so textual absence does not prove key absence.
#   - ONE jq (slurp) replaces: `jq empty` validation, tool_name extraction,
#     the content/new_string line count (jq|wc -l|tr), file_path extraction,
#     the files_modified jq -rs aggregation and the wc -l tool_call_count.
#     Line counts replicate `jq -r ... | wc -l` byte semantics exactly:
#     strings count split("\n") segments (empty string = 1, matching the
#     old raw-output trailing newline), null/false vanish via `// empty`
#     (0), other scalars are 1 line, and containers use a recursive
#     pretty-print line-count (def jl) that matches jq's pretty renderer
#     (host-verified against wc -l on nested fixtures).
#   - files_modified/tool_call_count are computed analytically PRE-append
#     ([state files] + current file | unique; NL-count + 1) — provably equal
#     to the old POST-append `jq -rs`/`wc -l` reads for every hook-written
#     state file, including the unterminated-final-line case. The jq -rs
#     wholesale-failure semantic (ANY malformed state line -> 0) is
#     replicated with a try/catch around a per-line fromjson parse.
#     (Out-of-contract shapes an external writer could create — multi-line
#     pretty JSON docs or whitespace-only lines — count as malformed here
#     where the old stream parser tolerated them; state is hook-written.)
#   - The state line and trajectory event are printf-assembled from
#     jq-pre-encoded pieces (tojson == the old jq -nc --arg encoder, key
#     order preserved) — byte-identical output, zero builder spawns.
#   - Timestamps: now|todate == date -u +%Y-%m-%dT%H:%M:%SZ (host-verified);
#     the trajectory filename date is the timestamp's date field (single
#     clock read — removes a midnight-straddle inconsistency, same as the
#     pass-2 zone-guard change). The session-id date (LOA_SESSION_ID unset)
#     uses gmtime|strftime("%Y%m%d") — same UTC day.
#   - Field transport is NUL-delimited ("[0] | implode" builds the NUL;
#     no escape literal appears in this file): file paths and tool names
#     can contain tabs/newlines, which @tsv would rewrite. Embedded JSON
#     NUL escapes (backslash-u-0000) are stripped via string division AND
#     trailing newlines are stripped (scap) — byte-identical to the old $()
#     substitution (minus bash's cosmetic "ignored null byte" warning).
#     Non-string tool_name/file_path values (out of hook contract) render
#     via tojson (compact) where the old jq -r pretty-printed containers;
#     scalars are byte-identical and every non-Write/Edit/NotebookEdit
#     rendering exits 0 through the same case fall-through as before.
#   - Error-shape parity: jq parse failure (invalid JSON stdin) exits 0
#     exactly like the old `jq empty || exit 0`; a post-validation
#     extraction error (e.g. non-object top-level doc) surfaces as an
#     in-band __KARPATHY_EVAL_ERR__ marker and exits 5, the code the old
#     set -e death propagated from the failing extraction pipeline.
#     Multi-document stdin (not producible by Claude Code) keeps the old
#     concatenated-rendering semantics via slurp+join("\n").
#
# perf pass-4 (2026-07-05, skill-loop): redundant-spawn elimination — the
# remaining dirname x2 + mkdir x2 drop out of the steady state: SCRIPT_DIR
# uses the pass-2 parameter-expansion idiom; the state-dir mkdir is skipped
# when a [[ -d ]] probe proves the parent exists (guard passing ⇒ dirname's
# target exists ⇒ mkdir -p is a no-op; ANY other shape — no slash, trailing
# slash, missing parent — falls back to the old dirname+mkdir command
# unchanged); the warn-path trajectory mkdir gets the same [[ -d ]] guard.
# The running-total awk read was NOT merged into the jq pass (deliberate
# skip): awk's tolerant textual parse counts lines_changed from lines that
# are not valid JSON (e.g. a crash-truncated final line), which the jq
# fromjson path cannot replicate without reimplementing strtod-prefix
# numeric parsing — behavior on truncated state files would diverge.
#
# perf pass-6 (2026-07-05, skill-loop): memoization — the pass-3 two-token
# yq derivation is a PURE function of the config file's bytes, re-derived on
# EVERY Write/Edit. The token array is now cached at
# .run/perf-cache/karpathy-config.v1.tokens (the ONLY additive side effect
# of this pass; .run/ is State-Zone, gitignored). Design notes:
#   - Cache format: line 1 = key "<ns-mtime>:<size>:<abs-path>" of the
#     config (ONE GNU-first `stat -Lc '%y:%s'` spawn — cheaper than the yq
#     it replaces; non-GNU stat ⇒ no key ⇒ never cache, always parse);
#     remaining lines = the _cfg_tokens array joined by newlines. %y is
#     nanosecond mtime (same-second edits rotate the key); the abs-path
#     component keeps two repos/worktrees sharing a relative
#     LOA_CONFIG_OVERRIDE name from cross-contaminating.
#   - COLD path is the ORIGINAL procsub mapfile verbatim (byte-identical
#     behavior including yq-failure partial output); the cache write is
#     atomic ($$-temp + mv -f -T, same dir; readers see old or new file,
#     never a torn one; concurrent writers: last wins) and any write
#     failure is swallowed. WARM path reconstructs the exact token array;
#     ANY anomaly (missing/corrupt/unreadable cache, key mismatch, stat
#     failure) falls through to the cold path and rewrites the cache. An
#     edit to the config is reflected in the very next invocation (key is
#     stat'd BEFORE the parse — a racing write self-heals next call).
#   - Token round-trip is exact for every yq-emittable stream here: both
#     tokens are guaranteed single-line and non-empty by the yq program
#     (bool literal / digits-or-DEFAULT). TRAILING empty tokens would not
#     survive the $(<cache) trailing-newline strip — unreachable, and even
#     if reached the downstream defaults coincide ("" and unset both yield
#     THRESHOLD=100; "" != "true" for the switch either way). Mid-stream
#     empty tokens round-trip exactly. Cached tokens are NUL-free by
#     construction (bash variables cannot hold NUL).
#   - Trust: config is already attacker-equivalent to the cache — anyone
#     who can write .run/perf-cache/ can write .loa.config.yaml (same
#     operator-writable trust domain), and this hook is non-blocking
#     (warn-only) by design.
#   - If the two-token yq program EVER changes, bump the cache filename
#     version (v1 → v2). jq/yq availability checks stay unconditional so
#     tool-absent behavior is unchanged.

set -euo pipefail
umask 077

# perf pass-4: was $(cd "$(dirname BASH_SOURCE)" && pwd). ${p%/*} equals
# dirname for every slash-containing script path; the two unreachable-in-
# production shapes (bare filename via PATH-less invocation → ".", root-level
# script "/x.sh" → "/") are covered explicitly. The cd/pwd canonicalization
# subshell is retained. (Idiom copied from the pass-2 zone-write-guard.)
_src="${BASH_SOURCE[0]}"
_src_dir="${_src%/*}"
if [[ "${_src_dir}" == "${_src}" ]]; then _src_dir="."; fi
if [[ -z "${_src_dir}" ]]; then _src_dir="/"; fi
SCRIPT_DIR="$(cd "${_src_dir}" && pwd)"
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
# specific false-equivalents (token 1). Token 2 carries the threshold.
# perf pass-6: token array memoized keyed on config identity (header note);
# any cache anomaly falls through to the original yq parse below.
_KP_CACHE_FILE="$REPO_ROOT/.run/perf-cache/karpathy-config.v1.tokens"
_kp_src="$CONFIG"
[[ "$_kp_src" != /* ]] && _kp_src="$PWD/$_kp_src"
_kp_id=$(stat -Lc '%y:%s' -- "$CONFIG" 2>/dev/null) || _kp_id=""
_kp_key=""
[[ -n "$_kp_id" ]] && _kp_key="${_kp_id}:${_kp_src}"
_cfg_tokens=()
_kp_hit=0
if [[ -n "$_kp_key" && -f "$_KP_CACHE_FILE" ]]; then
    # Slurp via the read builtin, NOT $(<file): a failed $(<file) redirection
    # aborts an errexit shell even inside a || list (host-probed, bash 5.2)
    # and leaks a bash error line; read -rd '' returns empty on missing/
    # unreadable/dir/NUL-torn inputs — exactly the fail-open we need — and
    # preserves the file bytes verbatim ("<key>\n<tokens...>", the payload
    # carrying no trailing newline by construction of the writer below; an
    # empty payload means a validly-cached EMPTY token stream = yq failure).
    _kp_cached=""
    IFS= read -rd '' _kp_cached 2>/dev/null < "$_KP_CACHE_FILE" || true
    if [[ "$_kp_cached" == "$_kp_key"$'\n'* ]]; then
        _kp_payload="${_kp_cached#*$'\n'}"
        [[ -n "$_kp_payload" ]] && mapfile -t _cfg_tokens <<< "$_kp_payload"
        _kp_hit=1
    fi
fi
if [[ "$_kp_hit" -eq 0 ]]; then
    mapfile -t _cfg_tokens < <(
        yq -r '(.karpathy_principles.surgical_diff_warning | tostring | sub("\n+$"; "") | (. == "false" or . == "False" or . == "FALSE" or . == "0" or . == "no" or . == "No" or . == "NO" or . == "off" or . == "Off" or . == "OFF")),
               (.karpathy_principles.diff_lines_per_task | tostring | sub("\n+$"; "") | (with(select(test("^[0-9]+$") | not); . = "DEFAULT")))' \
            "$CONFIG" 2>/dev/null
    )
    if [[ -n "$_kp_key" ]]; then
        _kp_payload=""
        if [[ "${#_cfg_tokens[@]}" -gt 0 ]]; then
            printf -v _kp_payload '%s\n' "${_cfg_tokens[@]}"
            _kp_payload="${_kp_payload%$'\n'}"
        fi
        {
            [[ -d "${_KP_CACHE_FILE%/*}" ]] || mkdir -p "${_KP_CACHE_FILE%/*}"
            printf '%s\n%s' "$_kp_key" "$_kp_payload" > "$_KP_CACHE_FILE.$$" &&
                mv -f -T "$_KP_CACHE_FILE.$$" "$_KP_CACHE_FILE"
        } 2>/dev/null || rm -f -- "$_KP_CACHE_FILE.$$" 2>/dev/null || true
    fi
fi
[[ "${_cfg_tokens[0]-}" == "true" ]] && exit 0

THRESHOLD="${_cfg_tokens[1]-DEFAULT}"
[[ "$THRESHOLD" == "null" || -z "$THRESHOLD" ]] && THRESHOLD=100
# Validate threshold is a positive integer; default to 100 on parse failure.
[[ "$THRESHOLD" =~ ^[0-9]+$ ]] || THRESHOLD=100

# ONE jq over stdin (+ the state file when present) — see header note.
# Output stream: tn NUL lines NUL ts NUL file-json NUL session-json NUL
# files-mod NUL tool-calls NUL, then the jq exit code as a final in-band
# chunk (the procsub group neutralizes set -e around the jq).
_state_args=(--arg state "")
[[ -f "$TASK_STATE" && -r "$TASK_STATE" ]] && _state_args=(--rawfile state "$TASK_STATE")

mapfile -d '' -t _kf < <(
    { _jrc=0
      jq -sj "${_state_args[@]}" \
         --arg sid "${LOA_SESSION_ID:-}" \
         --arg user "${USER:-unknown}" '
        def denul($z): . / $z | join("");
        def scap($z): denul($z) | sub("\n+$"; "");
        def slines: if . == "" then 1 else (split("\n") | length) end;
        def jl: if type == "array" or type == "object"
                then (if length == 0 then 1 else 2 + ([.[] | jl] | add) end)
                else 1 end;
        ([0] | implode) as $z |
        try (
          (map(.tool_name // empty | if type == "string" then . else tojson end) | join("\n") | scap($z)) as $tn |
          now as $now |
          ($sid | if . == "" then $user + "-" + ($now | gmtime | strftime("%Y%m%d")) else . end) as $session |
          (if $tn == "Write"
           then (map(.tool_input.content // empty) | map(if type == "string" then slines else jl end) | add // 0)
           elif ($tn == "Edit" or $tn == "NotebookEdit")
           then (map(.tool_input.new_string // empty) | map(if type == "string" then slines else jl end) | add // 0)
           else 0 end) as $lines |
          (if ($tn == "Write" or $tn == "Edit" or $tn == "NotebookEdit")
           then (map((.tool_input.file_path // "<unknown>") | (if type == "string" then . else tojson end)) | join("\n") | scap($z))
           else "" end) as $file |
          (try ($state | split("\n") | map(select(length > 0) | fromjson)
                | ([.[].file // empty] + [$file] | unique | length))
           catch 0) as $files_mod |
          (if $state == "" then 1 else ($state | split("\n") | length) end) as $tool_calls |
          ([$tn, ($lines | tostring), ($now | todate), ($file | tojson),
            ($session | tojson), ($files_mod | tostring), ($tool_calls | tostring)]
           | join($z) + $z)
        ) catch ("__KARPATHY_EVAL_ERR__" + $z)
      ' 2>/dev/null || _jrc=$?
      printf '%s' "$_jrc"
    }
)
[[ "${#_kf[@]}" -ge 1 ]] || exit 0
_jqrc="${_kf[-1]}"
# Invalid JSON on stdin — the old `jq empty 2>/dev/null || exit 0` path.
[[ "$_jqrc" == "0" ]] || exit 0
# Post-validation extraction error — the old unguarded-extraction set -e
# death (pipefail propagated jq's exit code 5).
if [[ "${#_kf[@]}" -eq 2 && "${_kf[0]}" == "__KARPATHY_EVAL_ERR__" ]]; then
    exit 5
fi
[[ "${#_kf[@]}" -eq 8 ]] || exit 0  # defensive: unexpected field count

TOOL_NAME="${_kf[0]}"
LINES="${_kf[1]}"
TS="${_kf[2]}"
FILE_JSON="${_kf[3]}"
SESSION_JSON="${_kf[4]}"
FILES_MOD="${_kf[5]}"
TOOL_CALLS="${_kf[6]}"

[[ -n "$TOOL_NAME" ]] || exit 0

# Tool dispatch. Lines were computed for the matching shape inside jq
# (Write → content, Edit/NotebookEdit → new_string — conservative, counts
# new content only; the v1 simplification documented in SDD §0.3).
case "$TOOL_NAME" in
    Write|Edit|NotebookEdit)
        ;;
    *)
        # Unrecognized tool — no-op (defensive: settings.json matcher should
        # prevent this, but the hook stays safe even if matcher widens).
        exit 0
        ;;
esac

[[ "$LINES" =~ ^[0-9]+$ ]] || exit 0

# perf pass-4: skip the dirname+mkdir spawns when the parent dir already
# exists (the steady state). The guard passing proves dirname's target
# exists (e.g. "a/b" being a dir ⇒ "a" exists), so mkdir -p would be a
# no-op; every other shape (no slash, trailing slash, missing parent) takes
# the old command unchanged.
if [[ "${TASK_STATE%/*}" == "$TASK_STATE" || ! -d "${TASK_STATE%/*}" ]]; then
    mkdir -p "$(dirname "$TASK_STATE")"
fi

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

# Append entry to state — printf-assembled from jq-pre-encoded pieces;
# byte-identical to the old jq -nc output (see header note).
printf '{"ts":"%s","tool":"%s","file":%s,"lines_changed":%s,"running_total":%s,"session_id":%s}\n' \
    "$TS" "$TOOL_NAME" "$FILE_JSON" "$LINES" "$RUNNING" "$SESSION_JSON" \
    >> "$TASK_STATE" 2>/dev/null || exit 0

# Threshold check.
if (( RUNNING > THRESHOLD )); then
    echo "[karpathy-surgical-warn] Session diff total ${RUNNING} lines exceeds threshold ${THRESHOLD}. Karpathy principle 3 (Surgical Changes): verify every changed line traces to the stated task. State: $TASK_STATE" >&2

    # Trajectory event (#961 K-2 FR-3 schema).
    # perf pass-4: [[ -d ]] guard — mkdir -p only when the dir is missing.
    [[ -d "$TRAJ_DIR" ]] || mkdir -p "$TRAJ_DIR"
    TRAJ_FILE="$TRAJ_DIR/karpathy-${TS:0:10}.jsonl"
    [[ "$TOOL_CALLS" =~ ^[0-9]+$ ]] || TOOL_CALLS=0
    [[ "$FILES_MOD" =~ ^[0-9]+$ ]] || FILES_MOD=0

    # A leading-zero THRESHOLD (e.g. config "007") passed the ^[0-9]+$ guard;
    # the old `jq -nc --argjson thresh "007"` PARSED it leniently and wrote
    # the decimal-normalized number (007 -> 7) — corpus-verified. Replicate
    # with a textual leading-zero strip (identical to jq's integer rendering
    # for every warn-reachable threshold).
    THRESHOLD_JSON="$THRESHOLD"
    while [[ "$THRESHOLD_JSON" == 0?* ]]; do THRESHOLD_JSON="${THRESHOLD_JSON#0}"; done

    printf '{"phase":"karpathy_check","principle":"surgical_changes","timestamp":"%s","files_modified":%s,"lines_total":%s,"threshold":%s,"verdict":"warn","tool_call_count":%s,"session_id":%s}\n' \
        "$TS" "$FILES_MOD" "$RUNNING" "$THRESHOLD_JSON" "$TOOL_CALLS" "$SESSION_JSON" \
        >> "$TRAJ_FILE" 2>/dev/null || true
fi

# v1 invariant: hook always returns 0 (non-blocking). BLOCK semantics are
# RESERVED for v2 — see SDD §7 R-3.
exit 0
