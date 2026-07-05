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
# .run/perf-cache/karpathy-config.v1.tokens (.run/ is State-Zone,
# gitignored). Design notes:
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
#
# perf pass-7 (2026-07-05, skill-loop): O(n) -> O(delta/1) on the growing
# state file via an incremental aggregate cache at
# .run/perf-cache/karpathy-state.v1.agg. FULL DESIGN NOTES are at the very
# BOTTOM of this file, AFTER the final `exit 0` — bash never parses past an
# executed exit, so the commentary costs zero runtime on the per-Write/Edit
# hot path (measured ~0.35ms/KB of pre-exit comment lexing on this host).

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
# perf pass-7: ONE stat now serves both the pass-6 config-cache key (%y:%s,
# reassembled byte-identically from the %s/%y fields) and the pass-7
# state-cache identity — the second stat spawn folds into the first. %n
# prefixes each output line so a missing file cannot shift the mapping (GNU
# stat keeps printing the surviving arguments after a failure). Pathological
# '|'-bearing paths can only make a prefix-match miss or collide, leaving
# fields empty/invalid = fail-open (no cache, original behavior).
_kp7_st=$(stat -Lc '%n|%d|%i|%s|%y' -- "$CONFIG" "$TASK_STATE" 2>/dev/null) || true
_kp_id=""
_kp7_pre=""
while IFS= read -r _kp7_l; do
    case "$_kp7_l" in
        "$CONFIG|"*)
            IFS='|' read -r _kp7_cd _kp7_ci _kp7_cs _kp7_cy <<< "${_kp7_l#"$CONFIG|"}"
            [[ -n "${_kp7_cy:-}" && -n "${_kp7_cs:-}" ]] && _kp_id="${_kp7_cy}:${_kp7_cs}"
            ;;
        "$TASK_STATE|"*)
            _kp7_pre="${_kp7_l#"$TASK_STATE|"}"
            ;;
    esac
done <<< "$_kp7_st"
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

# ---------------------------------------------------------------------------
# perf pass-7: state-aggregate cache — mode decision (header note).
# _kp7_blen: byte length of $1 into _kp7_len (locale-proof: ${#} counts
# characters under multibyte locales; the local LC_ALL=C scope makes it
# count bytes without disturbing the ambient locale of jq/awk children).
# ---------------------------------------------------------------------------
_kp7_blen() { local LC_ALL=C; _kp7_len=${#1}; }

_KP7_CACHE="$REPO_ROOT/.run/perf-cache/karpathy-state.v1.agg"
# Size gate: below this many bytes the ORIGINAL full-scan path is already
# cheaper than the cache machinery's fixed cost (warm jq compile + post-stat
# + atomic mv ≈ 7ms vs ~4.7ms of scan per 1000 entries — measured crossover
# ≈ 1300 entries ≈ 260KB, where the gate sits). Below the gate NO cache is
# written; a valid existing cache is still honored — and since cache writes
# only happen at ≥ gate, offset ≥ gate ⇒ any warm-eligible file is above the
# gate too (no serve-without-write loop). The env override exists for the
# test harness (do not mix gate values against one state file); same trust
# class as KARPATHY_TASK_STATE (hook is warn-only, non-blocking).
_KP7_MIN="${KARPATHY_STATE_CACHE_MIN:-262144}"
[[ "$_KP7_MIN" =~ ^[0-9]{1,15}$ ]] || _KP7_MIN=262144
_kp7_mode="cold"        # cold | fast | delta
_kp7_sum_mode="original" # original | fast | delta
_kp7_write_ok=0          # may attempt a cache write post-append
_kp7_warm=0              # 1 = primary fields sourced from the warm jq
_kp7_dev=""; _kp7_ino=""; _kp7_s0=""; _kp7_mt=""
_kp7_off=""; _kp7_bpois=""; _kp7_bnl=""; _kp7_bsum=""; _kp7_bcount=""
_kp7_bset=""; _kp7_tok=""; _kp7_toklen=0; _kp7_tail_from=1
_kp7_wcount=""; _kp7_snext=""; _kp7_pois2=""; _kp7_nls=""; _kp7_dlen=""
_kp7_endsnl=""; _kp7_allstr=""
_kp7_abs="$TASK_STATE"
[[ "$_kp7_abs" != /* ]] && _kp7_abs="$PWD/$_kp7_abs"

# awk/tail absence would make a FAST hit diverge from the old
# `awk … || echo 0` fallback (cached sum vs 0) — disable the whole feature.
if command -v awk >/dev/null 2>&1 && command -v tail >/dev/null 2>&1; then
    _kp7_write_ok=1
    # _kp7_pre was captured by the combined stat above (config-cache block).
    if [[ -n "$_kp7_pre" ]]; then
        IFS='|' read -r _kp7_dev _kp7_ino _kp7_s0 _kp7_mt <<< "$_kp7_pre"
    elif [[ -e "$TASK_STATE" ]]; then
        _kp7_write_ok=0   # exists but stat failed (non-GNU stat) → fail open
    else
        _kp7_s0=0         # absent: cold with empty base; cacheable post-append
    fi
    if [[ "$_kp7_write_ok" -eq 1 && -n "$_kp7_dev" && -f "$TASK_STATE" && -r "$TASK_STATE" && -f "$_KP7_CACHE" ]]; then
        # Nine line-reads from ONE fd (no herestring temp file; a concurrent
        # cache mv cannot tear the read — the fd pins the inode). Line 9
        # (the set) is slurped with read -rd '' and must contain no newline
        # (exactly-9-lines shape check). Any read failure leaves fields
        # empty and the validation below falls through to cold.
        _kp7_c0=""; _kp7_c2=""; _kp7_c8=""
        _kp7_off=""; _kp7_bpois=""; _kp7_bnl=""; _kp7_bsum=""
        _kp7_bcount=""; _kp7_tok=""
        {
            IFS= read -r _kp7_c0 && IFS= read -r _kp7_off &&
            IFS= read -r _kp7_c2 && IFS= read -r _kp7_bpois &&
            IFS= read -r _kp7_bnl && IFS= read -r _kp7_bsum &&
            IFS= read -r _kp7_bcount && IFS= read -r _kp7_tok &&
            { IFS= read -rd '' _kp7_c8 || [[ -n "$_kp7_c8" ]]; }
        } 2>/dev/null < "$_KP7_CACHE" || _kp7_c0=""
        _kp7_bset="$_kp7_c8"
        _kp7_blen "$_kp7_tok"; _kp7_toklen="$_kp7_len"
        if [[ "$_kp7_c0" == "${_kp7_dev}:${_kp7_ino}:${_kp7_abs}" &&
              "$_kp7_off" =~ ^[0-9]{1,15}$ &&
              "$_kp7_bpois" =~ ^[01]$ &&
              "$_kp7_bnl" =~ ^[0-9]{1,15}$ &&
              "$_kp7_bsum" =~ ^-?[0-9]{1,15}$ &&
              "$_kp7_bcount" =~ ^[0-9]{1,15}$ &&
              "$_kp7_bset" == \[*\] && "$_kp7_bset" != *$'\n'* &&
              "$_kp7_toklen" -ge 1 && "$_kp7_toklen" -le 1024 &&
              "$_kp7_off" -gt "$_kp7_toklen" ]]; then
            if [[ "$_kp7_s0" == "$_kp7_off" && "$_kp7_mt" == "$_kp7_c2" ]]; then
                _kp7_mode="fast"
            elif [[ "$_kp7_s0" =~ ^[0-9]+$ && "$_kp7_s0" -gt "$_kp7_off" ]]; then
                _kp7_mode="delta"
                _kp7_tail_from=$((_kp7_off - _kp7_toklen))
            fi
        fi
    fi
fi

# ---------------------------------------------------------------------------
# WARM paths (fast/delta): one jq computes the payload fields with the
# ORIGINAL expressions plus the state aggregates from cached base + delta.
# Output: 15 NUL-chunks + in-band jq rc. Chunk 8 == "1" flags an anomaly
# (token mismatch / U+FFFD in delta / corrupt cached set): payload fields
# stay valid, aggregates are recomputed by the aux jq below (full rescan).
# The set is parsed/re-serialized ONLY when the current file is not yet a
# member or the delta carried new files (header note: membership shortcut);
# chunk 10 is "=" when the set line is byte-unchanged.
# ---------------------------------------------------------------------------
if [[ "$_kp7_mode" == "fast" || "$_kp7_mode" == "delta" ]]; then
    _KP7_WARM_PROG='
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
          (if $fast == "1" then 0
           elif ($d | contains("�")) then 1
           elif (($d | startswith($tok + "\n")) | not) then 1
           else 0 end) as $anomA |
          (if $anomA == 1 or $fast == "1" then "" else $d[(($tok | length) + 1):] end) as $delta |
          ($delta | split("\n")) as $dsplit |
          (if $anomA == 1 then null
           else (try ($dsplit | map(select(length > 0) | fromjson) | [.[].file // empty]) catch null) end) as $dfiles |
          (if $anomA == 1 then 1 elif ($bpois == "1" or $dfiles == null) then 1 else 0 end) as $pois2 |
          (if $anomA == 1 or $pois2 == 1 then false
           elif ($dfiles | length) > 0 then false
           else (("," + ($bset | .[1:(length - 1)]) + ",")
                 | contains("," + ($file | tojson) + ",")) end) as $hit |
          (if $anomA == 1 or $pois2 == 1 or $hit then null
           else (try ($bset | fromjson) catch null) end) as $bs |
          (if $anomA == 1 or $pois2 == 1 or $hit then $anomA
           elif ($bs | type) != "array" then 1
           else $anomA end) as $anom |
          (if $anom == 1 or $pois2 == 1 or $hit then []
           else (($bs + $dfiles + [$file]) | unique) end) as $snext |
          (if $anom == 1 then "0"
           elif $pois2 == 1 then "0"
           elif $hit then $bcount
           else ($snext | length | tostring) end) as $files_mod |
          (if $anom == 1 then "0"
           elif $pois2 == 1 or $hit then $bcount
           else ($snext | length | tostring) end) as $count_next |
          (if $anom == 1 then ""
           elif $pois2 == 1 or $hit then "="
           else ($snext | tojson) end) as $setout |
          (if $anom == 1 then 0
           else (($bnl | tonumber)
                 + (if $delta == "" then 0 else (($dsplit | length) - 1) end)) end) as $nls |
          (if $anom == 1 then "0" else (($nls + 1) | tostring) end) as $tool_calls |
          ([$tn, ($lines | tostring), ($now | todate), ($file | tojson),
            ($session | tojson), $files_mod, $tool_calls,
            (if $anom == 1 then "1" else "0" end),
            $count_next,
            $setout,
            ($pois2 | tostring),
            ($nls | tostring),
            (if $anom == 1 then "0" else ($delta | utf8bytelength | tostring) end),
            (if $anom == 1 then "0" elif ($delta == "" or ($delta | endswith("\n"))) then "1" else "0" end),
            (if $anom == 1 then "0"
             elif $pois2 == 1 or $hit then "1"
             else (if ($snext | all(type == "string")) then "1" else "0" end) end)]
           | join($z) + $z)
        ) catch ("__KARPATHY_EVAL_ERR__" + $z)
    '
    if [[ "$_kp7_mode" == "delta" ]]; then
        mapfile -d '' -t _kw < <(
            { _wrc=0
              jq -sj --rawfile d <(tail -c +"$_kp7_tail_from" -- "$TASK_STATE" 2>/dev/null) \
                 --arg fast "0" --arg tok "$_kp7_tok" --arg bset "$_kp7_bset" \
                 --arg bpois "$_kp7_bpois" --arg bnl "$_kp7_bnl" --arg bcount "$_kp7_bcount" \
                 --arg sid "${LOA_SESSION_ID:-}" --arg user "${USER:-unknown}" \
                 "$_KP7_WARM_PROG" 2>/dev/null || _wrc=$?
              printf '%s' "$_wrc"
            }
        )
    else
        mapfile -d '' -t _kw < <(
            { _wrc=0
              jq -sj --arg d "" \
                 --arg fast "1" --arg tok "$_kp7_tok" --arg bset "$_kp7_bset" \
                 --arg bpois "$_kp7_bpois" --arg bnl "$_kp7_bnl" --arg bcount "$_kp7_bcount" \
                 --arg sid "${LOA_SESSION_ID:-}" --arg user "${USER:-unknown}" \
                 "$_KP7_WARM_PROG" 2>/dev/null || _wrc=$?
              printf '%s' "$_wrc"
            }
        )
    fi
    [[ "${#_kw[@]}" -ge 1 ]] || exit 0
    # Invalid JSON on stdin — the old `jq empty 2>/dev/null || exit 0` path.
    [[ "${_kw[-1]}" == "0" ]] || exit 0
    # Post-validation extraction error — the old set -e death (exit 5). The
    # warm program's pre-payload bindings cannot error (bash-validated
    # inputs, try-wrapped parses), so this fires iff the original would.
    if [[ "${#_kw[@]}" -eq 2 && "${_kw[0]}" == "__KARPATHY_EVAL_ERR__" ]]; then
        exit 5
    fi
    if [[ "${#_kw[@]}" -eq 16 && "${_kw[7]}" == "0" ]]; then
        TOOL_NAME="${_kw[0]}"
        LINES="${_kw[1]}"
        TS="${_kw[2]}"
        FILE_JSON="${_kw[3]}"
        SESSION_JSON="${_kw[4]}"
        FILES_MOD="${_kw[5]}"
        TOOL_CALLS="${_kw[6]}"
        _kp7_wcount="${_kw[8]}"; _kp7_snext="${_kw[9]}"; _kp7_pois2="${_kw[10]}"
        _kp7_nls="${_kw[11]}"; _kp7_dlen="${_kw[12]}"; _kp7_endsnl="${_kw[13]}"
        _kp7_allstr="${_kw[14]}"
        _kp7_warm=1
        _kp7_sum_mode="$_kp7_mode"
    elif [[ "${#_kw[@]}" -eq 16 ]]; then
        # Anomaly: full rescan. stdin is consumed, so keep the payload
        # fields (extracted with the original expressions) and recompute
        # the state aggregates PRE-append with the original expressions.
        TOOL_NAME="${_kw[0]}"
        LINES="${_kw[1]}"
        TS="${_kw[2]}"
        FILE_JSON="${_kw[3]}"
        SESSION_JSON="${_kw[4]}"
        _kp7_aux_state=(--arg state "")
        [[ -f "$TASK_STATE" && -r "$TASK_STATE" ]] && _kp7_aux_state=(--rawfile state "$TASK_STATE")
        mapfile -d '' -t _ka < <(
            { _arc=0
              jq -nj "${_kp7_aux_state[@]}" --arg fj "$FILE_JSON" '
                ([0] | implode) as $z |
                ($fj | fromjson) as $file |
                ((try ($state | split("\n") | map(select(length > 0) | fromjson)
                      | ([.[].file // empty] + [$file] | unique | length))
                  catch 0) | tostring) as $files_mod |
                ((if $state == "" then 1 else ($state | split("\n") | length) end) | tostring) as $tool_calls |
                ($files_mod + $z + $tool_calls + $z)
              ' 2>/dev/null || _arc=$?
              printf '%s' "$_arc"
            }
        )
        # A state re-read failure here matches the old shape: the original
        # single jq would have failed its --rawfile and exited 0 pre-append.
        [[ "${#_ka[@]}" -eq 3 && "${_ka[-1]}" == "0" ]] || exit 0
        FILES_MOD="${_ka[0]}"
        TOOL_CALLS="${_ka[1]}"
        _kp7_warm=1
        _kp7_sum_mode="original"
        _kp7_mode="cold"
    else
        # Defensive: unexpected field count (same class as the original
        # `-eq 8 || exit 0` guard).
        exit 0
    fi
fi

if [[ "$_kp7_warm" -eq 0 ]]; then
    # -----------------------------------------------------------------------
    # COLD path — the ORIGINAL single-jq code, verbatim (pass-3/4 shape).
    # -----------------------------------------------------------------------
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
fi

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
# perf pass-7: FAST serves the cached total (== the full scan's printed
# value: cache writes require an exact-decimal 15-digit integer); DELTA
# re-runs THE SAME awk program on only the token+delta bytes, seeded with
# the cached total in BEGIN — same association order as the full scan.
if [[ "$_kp7_sum_mode" == "fast" ]]; then
    RUNNING="$_kp7_bsum"
elif [[ "$_kp7_sum_mode" == "delta" ]]; then
    RUNNING=$(awk -F'"lines_changed":' -v init="$_kp7_bsum" '
        BEGIN { sum = init + 0 }
        NR == 1 { next }
        /"lines_changed":/ {
            n = $2 + 0  # extract leading integer
            sum += n
        }
        END { print sum + 0 }
    ' <(tail -c +"$_kp7_tail_from" -- "$TASK_STATE" 2>/dev/null) 2>/dev/null || echo 0)
else
    RUNNING=$(awk -F'"lines_changed":' '
        /"lines_changed":/ {
            n = $2 + 0  # extract leading integer
            sum += n
        }
        END { print sum + 0 }
    ' "$TASK_STATE" 2>/dev/null || echo 0)
fi
RUNNING=$((RUNNING + LINES))

# Append entry to state — printf-assembled from jq-pre-encoded pieces;
# byte-identical to the old jq -nc output (see header note).
# perf pass-7: the line is built in a variable first (printf -v cannot
# fail; identical bytes) so it can double as the cache's prefix-integrity
# token; the append keeps the old failure shape.
printf -v _kp7_entry '{"ts":"%s","tool":"%s","file":%s,"lines_changed":%s,"running_total":%s,"session_id":%s}' \
    "$TS" "$TOOL_NAME" "$FILE_JSON" "$LINES" "$RUNNING" "$SESSION_JSON"
printf '%s\n' "$_kp7_entry" >> "$TASK_STATE" 2>/dev/null || exit 0

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

# ---------------------------------------------------------------------------
# perf pass-7: cache write (header note). Reached only after a successful
# append. Entirely fail-open: any guard miss skips the write and leaves the
# previous cache (stale-but-consistent: its offset still sits on a line
# boundary, so the next call simply processes a wider delta or rescans).
# ---------------------------------------------------------------------------
if [[ "$_kp7_write_ok" -eq 1 ]]; then
    {
        _kp7_blen "$_kp7_entry"
        _kp7_elen="$_kp7_len"
        # Size gate (header note): small files stay on the original path
        # end-to-end — not even the post-append stat is spawned. Gated on
        # the PRE-append size + our entry (a racer pushing the true size
        # past the gate in this sliver merely delays caching one call).
        if [[ "$_kp7_elen" -ge 1 && "$_kp7_elen" -le 1024 &&
              "$RUNNING" =~ ^-?[0-9]{1,15}$ &&
              "$_kp7_s0" =~ ^[0-9]{1,15}$ &&
              "$((_kp7_s0 + _kp7_elen + 1))" -ge "$_KP7_MIN" ]]; then
            _kp7_post=$(stat -Lc '%d|%i|%s|%y' -- "$TASK_STATE" 2>/dev/null) || _kp7_post=""
            if [[ -n "$_kp7_post" ]]; then
                IFS='|' read -r _kp7_dev2 _kp7_ino2 _kp7_s2 _kp7_mt2 <<< "$_kp7_post"
                _kp7_wpois=""; _kp7_wnl=""; _kp7_wset=""; _kp7_wc=""
                if [[ "$_kp7_sum_mode" == "fast" || "$_kp7_sum_mode" == "delta" ]]; then
                    # Warm fold: aggregates from the warm jq + this entry.
                    # "=" = set line byte-unchanged (membership hit).
                    [[ "$_kp7_snext" == "=" ]] && _kp7_snext="$_kp7_bset"
                    if [[ "$_kp7_endsnl" == "1" && "$_kp7_allstr" == "1" &&
                          "$_kp7_pois2" =~ ^[01]$ &&
                          "$_kp7_nls" =~ ^[0-9]{1,15}$ &&
                          "$_kp7_wcount" =~ ^[0-9]{1,15}$ &&
                          "$_kp7_dlen" =~ ^[0-9]{1,12}$ &&
                          "$_kp7_s2" == "$((_kp7_off + _kp7_dlen + _kp7_elen + 1))" ]]; then
                        _kp7_wpois="$_kp7_pois2"
                        _kp7_wnl=$((_kp7_nls + 1))
                        _kp7_wset="$_kp7_snext"
                        _kp7_wc="$_kp7_wcount"
                    fi
                elif [[ "$_kp7_s0" =~ ^[0-9]{1,15}$ &&
                        "$_kp7_s2" == "$((_kp7_s0 + _kp7_elen + 1))" ]]; then
                    # Cold rebuild: full-scan snapshot of the post-append
                    # file (builder guards in header note).
                    mapfile -d '' -t _kb < <(
                        { _brc=0
                          jq -nj --rawfile s "$TASK_STATE" --arg sz "$_kp7_s2" --arg tok "$_kp7_entry" '
                            ([0] | implode) as $z |
                            try (
                              (if ($s | contains("�")) then error("no") else . end) |
                              (if ($s | utf8bytelength) == ($sz | tonumber) then . else error("no") end) |
                              (if (($s | endswith("\n" + $tok + "\n")) or ($s == $tok + "\n")) then . else error("no") end) |
                              (try ($s | split("\n") | map(select(length > 0) | fromjson) | [.[].file // empty]) catch null) as $fs |
                              (if $fs == null then [1, []] else [0, ($fs | unique)] end) as $pv |
                              (if ($pv[1] | all(type == "string")) then . else error("no") end) |
                              ([($pv[0] | tostring),
                                ((($s | split("\n") | length) - 1) | tostring),
                                ($pv[1] | length | tostring),
                                ($pv[1] | tojson)] | join($z) + $z)
                            ) catch ("__NO__" + $z)
                          ' 2>/dev/null || _brc=$?
                          printf '%s' "$_brc"
                        }
                    )
                    if [[ "${#_kb[@]}" -eq 5 && "${_kb[-1]}" == "0" &&
                          "${_kb[0]}" =~ ^[01]$ && "${_kb[1]}" =~ ^[0-9]{1,15}$ &&
                          "${_kb[2]}" =~ ^[0-9]{1,15}$ ]]; then
                        _kp7_wpois="${_kb[0]}"
                        _kp7_wnl="${_kb[1]}"
                        _kp7_wc="${_kb[2]}"
                        _kp7_wset="${_kb[3]}"
                    fi
                fi
                if [[ -n "$_kp7_wpois" && "$_kp7_wset" == \[*\] ]]; then
                    _kp7_blen "$_kp7_wset"
                    if [[ "$_kp7_len" -gt 65536 ]]; then
                        # Oversized unique-file set: permanent full-scan
                        # mode for this file (header note).
                        rm -f -- "$_KP7_CACHE" 2>/dev/null || true
                    else
                        {
                            [[ -d "${_KP7_CACHE%/*}" ]] || mkdir -p "${_KP7_CACHE%/*}"
                            printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s' \
                                "${_kp7_dev2}:${_kp7_ino2}:${_kp7_abs}" \
                                "$_kp7_s2" "$_kp7_mt2" "$_kp7_wpois" \
                                "$_kp7_wnl" "$RUNNING" "$_kp7_wc" \
                                "$_kp7_entry" "$_kp7_wset" \
                                > "$_KP7_CACHE.$$" &&
                                mv -f -T "$_KP7_CACHE.$$" "$_KP7_CACHE"
                        } 2>/dev/null || rm -f -- "$_KP7_CACHE.$$" 2>/dev/null || true
                    fi
                fi
            fi
        fi
    } 2>/dev/null || true
fi

# v1 invariant: hook always returns 0 (non-blocking). BLOCK semantics are
# RESERVED for v2 — see SDD §7 R-3.
exit 0

# perf pass-7 (2026-07-05, skill-loop): O(n) -> O(delta) on the growing
# state file. The per-call cost was O(session length): the single jq
# --rawfile'd ALL of karpathy-task-state.jsonl (files_modified set +
# tool_call_count) and awk re-scanned the whole file for the running total
# — measured 20ms at n=500 entries, 36ms at n=5000, 111ms at n=20000.
# Aggregates are now cached at .run/perf-cache/karpathy-state.v1.agg and
# folded INCREMENTALLY over only the appended bytes. Design notes:
#   - Cache format (9 lines, no trailing newline; the set line is LAST so
#     the bash reader never has to load it — reads stop at line 8):
#       1 key    "<dev>:<ino>:<abs-state-path>" (post-append stat identity;
#                the abs-path component blocks cross-repo/worktree
#                contamination through shared relative KARPATHY_TASK_STATE
#                names; dev:ino rotates on rename/replace rotation)
#       2 offset bytes processed; ALWAYS ends at a '\n' line boundary and
#                always == the file size at the last cache write
#       3 mtime  stat %y (ns) at the last cache write
#       4 pois   1 when any processed line poisons files_modified (the
#                wholesale try/catch -> 0 semantic); append-only files
#                never un-poison, so the flag is monotonic
#       5 nl     newline count through offset (tool_calls == nl + 1)
#       6 sum    mawk running lines_changed total through offset — always a
#                bash-integer product; caching requires ^-?[0-9]{1,15}$ so
#                the decimal round-trips the awk double EXACTLY
#       7 count  |set| (files_modified == count when the current file is
#                already a member — the steady state)
#       8 token  the hook's own last-appended state line (newline-free by
#                construction, 1..1024 bytes) — the prefix-integrity probe
#       9 set    compact JSON array: unique .file values through offset
#                INCLUDING the hook's own appended entry (jq `unique`
#                ordering; all members verified strings at write time)
#   - Set-membership shortcut (the real repo holds 438 unique files across
#     646 entries — ~32KB of set — so parsing + re-unique-ing it per call
#     would eat the win): the warm jq tests membership TEXTUALLY on the
#     compact set line — needle "," + ($file|tojson) + "," against
#     "," + inner + ",". SOUNDNESS: in a compact jq array of strings a
#     quote inside an element is always escaped (backslash-quote), so a
#     bare  ," / ",  pair can only occur at element boundaries — a match
#     PROVES membership. A false NEGATIVE merely takes the exact
#     parse+unique path. On a hit (repeat file, the steady state) the set
#     is never parsed and never re-serialized: the emit uses an "="
#     passthrough sentinel and bash rewrites the bytes it already read
#     (set lines always start with "[", so "=" is unambiguous). All nine
#     lines are read from ONE fd, so a concurrent cache mv cannot tear the
#     read (the fd pins the old inode).
#   - Per call: ONE GNU-first stat. size==offset AND mtime==cached ⇒ FAST
#     path (no state read at all; aggregates are current). size>offset ⇒
#     DELTA path: `tail -c +(offset-len(token))` streams token+delta into
#     the SAME single jq via --rawfile procsub; the token must match
#     byte-for-byte at the recorded boundary or the call falls back to a
#     full rescan. The lines_changed fold reuses THE SAME awk program on a
#     second tail procsub (`NR==1 {next}` skips the token line) seeded with
#     `-v init=<cached sum>` in BEGIN — same left-to-right association as
#     the full-file scan, so the printed total is bit-identical (mawk
#     strtod-prefix semantics on malformed/truncated lines are preserved by
#     construction: it IS the same awk on the same line bytes; line sets
#     decompose exactly because offset always sits on a '\n' boundary).
#     ANY other relation (size<offset, mtime anomaly at equal size, key
#     mismatch, corrupt/short/unreadable cache, token mismatch, U+FFFD in
#     the delta = jq's invalid-UTF-8 replacement marker, non-array cached
#     set) ⇒ full rescan through the ORIGINAL code path.
#   - COLD path (no/invalid cache): the ORIGINAL jq program and ORIGINAL
#     awk command run VERBATIM; the cache is rebuilt by a separate builder
#     jq that re-reads the file POST-append, so cached aggregates are a
#     true full-scan snapshot. Builder guards: no U+FFFD, utf8bytelength ==
#     post-append stat size (raced growth ⇒ skip), content ends with the
#     hook's own entry as a standalone line (a pre-append unterminated
#     final line glues our entry into a hybrid line — computing THIS call
#     stays correct, but the snapshot is only cacheable once the tail of
#     the file is again a clean self-written line), all set members
#     strings. Cold-path sum consistency: cache write additionally
#     requires post-size == pre-size + len(entry)+1 (nothing else appended
#     between the pre-stat and our append).
#   - WARM path token-mismatch/corrupt-set anomalies keep the payload
#     fields already extracted (stdin is consumed) and recompute
#     files_modified/tool_call_count with an auxiliary jq over the full
#     state PRE-append — the exact original expressions — plus the
#     ORIGINAL awk; observable output is full-rescan-identical.
#   - The hook's own append is folded into the cache (offset covers it;
#     set gains the current file; nl+1; sum = the emitted running_total),
#     so the next call's delta contains only genuinely new bytes.
#   - Bounds / permanent fallbacks (silent, output identical): cached-set
#     serialization > 64KiB ⇒ cache deleted, never rewritten while
#     oversized (full-scan mode); own entry > 1024 bytes ⇒ cache write
#     skipped; sum outside ±15 digits ⇒ skipped; awk or tail missing from
#     PATH ⇒ whole feature disabled (a FAST hit would otherwise diverge
#     from the old `awk … || echo 0` fallback total).
#   - Size gate (KARPATHY_STATE_CACHE_MIN, default 262144 bytes): below it
#     the ORIGINAL path runs end-to-end with the ORIGINAL spawn count
#     (census: 3 = stat, jq, awk on both sides — the pre-stat rides the
#     combined config stat) and no cache is written; the machinery engages
#     only where it strictly beats the measured full-scan crossover
#     (~1300 entries). offset >= gate for every written cache, so a
#     warm-served file is always above the gate too (no
#     serve-without-write staleness loop).
#   - Concurrency: cache writes are atomic ($$-temp + mv -f -T; last
#     writer wins; readers never see torn files). A concurrent appender
#     between our read and our append makes the post-append size differ
#     from offset+delta+entry ⇒ cache write skipped; the surviving cache
#     stays stale-but-consistent and the next call re-processes the wider
#     delta. Reads at slightly different instants (stat vs tail vs awk)
#     see prefixes the old two-read code could also have seen — same race
#     envelope, deterministic inputs are byte-identical.
#   - Trust: same posture as pass-6 — anyone who can write
#     .run/perf-cache/ can already write .run/karpathy-task-state.jsonl,
#     the authoritative input this hook trusts today; forging the cache is
#     strictly harder (must match live stat identity + token bytes). The
#     hook is non-blocking (warn-only) by design.
#   - If the warm/aux/builder jq programs or the awk fold EVER change,
#     bump the cache filename version (v1 -> v2); the key deliberately
#     excludes program text.
#   - Known residual divergence (documented, accepted): if the /dev/fd
#     procsub plumbing itself failed (not reproducible on Linux), the warm
#     jq's nonzero rc is indistinguishable from invalid-stdin and the call
#     no-ops (exit 0) where the old code would have processed — one lost
#     warn on a warn-only hook.
