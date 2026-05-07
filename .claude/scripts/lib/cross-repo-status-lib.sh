#!/usr/bin/env bash
# =============================================================================
# cross-repo-status-lib.sh — L5 cross-repo-status-reader (cycle-098 Sprint 5)
#
# Per RFC #657, PRD FR-L5 (7 ACs), SDD §1.4.2 + §5.7.
#
# Composition (does NOT reinvent):
#   - 1A audit envelope: audit_emit (one cross_repo.read event per invocation)
#   - existing `gh` CLI (operator-installed, authenticated)
#
# Public API:
#   cross_repo_read <repos_json>            # returns CrossRepoState JSON; logs cross_repo.read event
#   cross_repo_cache_get <repo>             # prints cached repoState JSON or empty
#   cross_repo_cache_invalidate <repo>      # removes cached file for repo (or all if "all")
#
# repos_json shape:
#   ["owner/name", "owner/name", ...]
#
# Environment variables:
#   LOA_CROSS_REPO_CACHE_DIR              cache dir (default .run/cache/cross-repo-status)
#   LOA_CROSS_REPO_CACHE_TTL_SECONDS      fresh-cache TTL (default 300 = 5min)
#   LOA_CROSS_REPO_FALLBACK_STALE_MAX     stale-fallback ceiling (default 900 = 15min)
#   LOA_CROSS_REPO_PARALLEL               max parallel gh-api workers (default 5)
#   LOA_CROSS_REPO_TIMEOUT_SECONDS        per-repo timeout (default 25)
#   LOA_CROSS_REPO_NOTES_TAIL_LINES       NOTES.md tail line count (default 50)
#   LOA_CROSS_REPO_GH_CMD                 override gh path (test-mode escape)
#   LOA_CROSS_REPO_LOG                    audit log path (default .run/cross-repo-status.jsonl)
#   LOA_CROSS_REPO_TEST_NOW               test-only "now" override (gated on bats env)
#   LOA_CROSS_REPO_TEST_MODE              "1" enables LOA_CROSS_REPO_TEST_NOW outside bats
#
# Exit codes:
#   0  read succeeded (may include partial failures inside response)
#   1  systemic failure (gh missing, cache dir un-writable, etc.)
#   2  invalid arguments
# =============================================================================

set -euo pipefail

if [[ "${_LOA_L5_LIB_SOURCED:-0}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi
_LOA_L5_LIB_SOURCED=1

_L5_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_L5_REPO_ROOT="$(cd "${_L5_DIR}/../../.." && pwd)"
_L5_AUDIT_ENVELOPE="${_L5_REPO_ROOT}/.claude/scripts/audit-envelope.sh"

# shellcheck source=../audit-envelope.sh
source "${_L5_AUDIT_ENVELOPE}"

_l5_log() { echo "[cross-repo-status] $*" >&2; }

# Defaults.
_L5_DEFAULT_CACHE_DIR=".run/cache/cross-repo-status"
_L5_DEFAULT_CACHE_TTL_SECONDS="300"
_L5_DEFAULT_FALLBACK_STALE_MAX="900"
_L5_DEFAULT_PARALLEL="5"
_L5_DEFAULT_TIMEOUT_SECONDS="25"
_L5_DEFAULT_NOTES_TAIL_LINES="50"
_L5_DEFAULT_LOG=".run/cross-repo-status.jsonl"   # name pinned to .claude/data/audit-retention-policy.yaml line 49 (general-purpose review H1)

# Repo identifier validation. owner/name; conservative charset to defend
# against shell metacharacter injection into `gh api` arguments.
_L5_REPO_RE='^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$'
_L5_INT_RE='^[0-9]+$'

# -----------------------------------------------------------------------------
# _l5_save_shell_opts / _l5_restore_shell_opts
#
# Cypherpunk MED-1 / general-purpose M1: `set +e` and `set +o pipefail`
# inside a function persist into the caller's shell after the function
# returns. When this lib is sourced into an operator script that runs
# `set -euo pipefail`, the first call to cross_repo_read would silently
# disable strict-mode for the rest of the script. These helpers save the
# caller's option state at function entry and restore it before return.
#
# Caller pattern:
#   local _saved_opts; _saved_opts="$(_l5_save_shell_opts)"
#   set +e; set +o pipefail
#   ...function body...
#   _l5_restore_shell_opts "$_saved_opts"
# -----------------------------------------------------------------------------
_l5_save_shell_opts() {
    local e=0 pf=0
    case "$-" in *e*) e=1 ;; esac
    if [[ -o pipefail ]]; then pf=1; fi
    echo "${e}:${pf}"
}
_l5_restore_shell_opts() {
    local saved="$1" e pf
    e="${saved%%:*}"
    pf="${saved##*:}"
    [[ "$e" == "1" ]] && set -e
    [[ "$pf" == "1" ]] && set -o pipefail
    return 0
}

_l5_validate_repo() {
    local v="$1"
    if [[ -z "$v" ]] || ! [[ "$v" =~ $_L5_REPO_RE ]]; then
        _l5_log "ERROR: repo '$v' does not match $_L5_REPO_RE"
        return 1
    fi
    # Defense against `..` repo-traversal even if regex permits a dot in the
    # owner or name (which it does for legitimate repos like loa.git);
    # explicit `..` substring rejection.
    if [[ "$v" == *..* ]]; then
        _l5_log "ERROR: repo '$v' contains '..' (path-traversal sentinel rejected)"
        return 1
    fi
    # Cypherpunk MED-5: GitHub itself rejects leading dots/dashes. Tighten
    # at the lib boundary so an attacker cannot use `--/--` (CLI arg-end-
    # marker pattern) or `./foo` (cwd-relative interpretations) to slip
    # through downstream consumers.
    local owner="${v%%/*}"
    local name="${v#*/}"
    case "$owner" in [.-]*) _l5_log "ERROR: repo owner '$owner' starts with '.' or '-'"; return 1 ;; esac
    case "$owner" in *[.-]) _l5_log "ERROR: repo owner '$owner' ends with '.' or '-'";   return 1 ;; esac
    case "$name"  in [.-]*) _l5_log "ERROR: repo name '$name' starts with '.' or '-'";   return 1 ;; esac
    case "$name"  in *[.-]) _l5_log "ERROR: repo name '$name' ends with '.' or '-'";     return 1 ;; esac
    return 0
}

_l5_validate_int() {
    local v="$1" field="$2"
    if [[ -z "$v" ]] || ! [[ "$v" =~ $_L5_INT_RE ]]; then
        _l5_log "ERROR: $field='$v' is not a non-negative integer"
        return 1
    fi
}

_l5_cache_dir() {
    local d
    d="${LOA_CROSS_REPO_CACHE_DIR:-${_L5_REPO_ROOT}/${_L5_DEFAULT_CACHE_DIR}}"
    # Refuse paths under a few obviously-dangerous roots (best-effort
    # defense if an operator misconfigures LOA_CROSS_REPO_CACHE_DIR).
    case "$d" in
        /etc|/etc/*|/usr|/usr/*|/var/log|/var/log/*|/proc|/proc/*|/sys|/sys/*|/dev|/dev/*|/boot|/boot/*)
            _l5_log "ERROR: refusing to use cache_dir='$d' (system path)"
            return 1
            ;;
    esac
    echo "$d"
}

# -----------------------------------------------------------------------------
# _l5_cache_invalidate_pattern
#
# Cypherpunk HIGH-2: cache_invalidate must not delete files outside the
# cache file shape. We use `*__*.json` as the shape pin (since cache files
# are owner__name.json). Misconfigured cache_dir + invalidate-all therefore
# only deletes files matching the L5 shape — a bare /etc/passwd cannot be
# clobbered even if cache_dir was set to /etc.
# -----------------------------------------------------------------------------
_l5_cache_invalidate_glob='*__*.json'

_l5_log_path() {
    local p
    p="${LOA_CROSS_REPO_LOG:-${_L5_REPO_ROOT}/${_L5_DEFAULT_LOG}}"
    echo "$p"
}

_l5_cache_ttl() {
    local v
    v="${LOA_CROSS_REPO_CACHE_TTL_SECONDS:-$_L5_DEFAULT_CACHE_TTL_SECONDS}"
    if ! _l5_validate_int "$v" "cache_ttl_seconds" >/dev/null 2>&1; then
        v="$_L5_DEFAULT_CACHE_TTL_SECONDS"
    fi
    echo "$v"
}

_l5_fallback_stale_max() {
    local v
    v="${LOA_CROSS_REPO_FALLBACK_STALE_MAX:-$_L5_DEFAULT_FALLBACK_STALE_MAX}"
    if ! _l5_validate_int "$v" "fallback_stale_max" >/dev/null 2>&1; then
        v="$_L5_DEFAULT_FALLBACK_STALE_MAX"
    fi
    echo "$v"
}

_l5_timeout_seconds() {
    local v
    v="${LOA_CROSS_REPO_TIMEOUT_SECONDS:-$_L5_DEFAULT_TIMEOUT_SECONDS}"
    if ! _l5_validate_int "$v" "timeout_seconds" >/dev/null 2>&1; then
        v="$_L5_DEFAULT_TIMEOUT_SECONDS"
    fi
    echo "$v"
}

_l5_parallel() {
    local v
    v="${LOA_CROSS_REPO_PARALLEL:-$_L5_DEFAULT_PARALLEL}"
    if ! _l5_validate_int "$v" "parallel" >/dev/null 2>&1; then
        v="$_L5_DEFAULT_PARALLEL"
    fi
    if (( v < 1 )); then v=1; fi
    if (( v > 20 )); then v=20; fi
    echo "$v"
}

_l5_notes_tail_lines() {
    local v
    v="${LOA_CROSS_REPO_NOTES_TAIL_LINES:-$_L5_DEFAULT_NOTES_TAIL_LINES}"
    if ! _l5_validate_int "$v" "notes_tail_lines" >/dev/null 2>&1; then
        v="$_L5_DEFAULT_NOTES_TAIL_LINES"
    fi
    echo "$v"
}

_l5_gh_cmd() {
    if [[ -n "${LOA_CROSS_REPO_GH_CMD:-}" ]]; then
        echo "$LOA_CROSS_REPO_GH_CMD"
    else
        echo "gh"
    fi
}

# Cypherpunk MED-6: surface the override boolean in the audit payload so
# operators auditing trajectory can SEE that an alternate gh binary was
# used. We don't write to stderr (pollutes consumers parsing stdout); the
# audit log entry is the operator-visibility surface.
_l5_gh_override_active() {
    if [[ -n "${LOA_CROSS_REPO_GH_CMD:-}" ]]; then
        echo "true"
    else
        echo "false"
    fi
}

# now() honoring LOA_CROSS_REPO_TEST_NOW only under test mode (mirrors L4 MED-4 fix).
_l5_now_iso8601() {
    if [[ -n "${LOA_CROSS_REPO_TEST_NOW:-}" ]] \
        && { [[ "${LOA_CROSS_REPO_TEST_MODE:-0}" == "1" ]] || [[ -n "${BATS_TEST_DIRNAME:-}" ]]; }; then
        echo "$LOA_CROSS_REPO_TEST_NOW"
        return 0
    fi
    python3 -c 'from datetime import datetime, timezone; print(datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z")'
}

_l5_now_epoch() {
    if [[ -n "${LOA_CROSS_REPO_TEST_NOW:-}" ]] \
        && { [[ "${LOA_CROSS_REPO_TEST_MODE:-0}" == "1" ]] || [[ -n "${BATS_TEST_DIRNAME:-}" ]]; }; then
        python3 -c '
import sys
from datetime import datetime
s = sys.argv[1]
if s.endswith("Z"):
    s = s[:-1] + "+00:00"
print(int(datetime.fromisoformat(s).timestamp()))
' "$LOA_CROSS_REPO_TEST_NOW"
        return 0
    fi
    date -u +%s
}

# -----------------------------------------------------------------------------
# _l5_cache_path <repo> — cache file path for a repo. Slashes -> double-underscore
# so cache files are flat. Mode is enforced 0600 by writers.
# -----------------------------------------------------------------------------
_l5_cache_path() {
    local repo="$1"
    local cache_dir
    cache_dir="$(_l5_cache_dir)"
    echo "${cache_dir}/${repo//\//__}.json"
}

# -----------------------------------------------------------------------------
# cross_repo_cache_get <repo>
# Print the cached repoState JSON for the given repo, or empty if no cache.
# Cache files contain {"state": <repoState>, "cached_at_epoch": N}.
# -----------------------------------------------------------------------------
cross_repo_cache_get() {
    local repo="${1:-}"
    _l5_validate_repo "$repo" || return 2
    local path
    path="$(_l5_cache_path "$repo")"
    [[ -f "$path" ]] || { echo ""; return 0; }
    if ! jq -e '.state' "$path" >/dev/null 2>&1; then
        echo ""; return 0
    fi
    # Cypherpunk HIGH-1: shape-validate the cached state before serving.
    # Reject any cache with unexpected field shape — defends against the
    # cache-poisoning class where an attacker who can write .run/cache
    # injects arbitrary fields. We strip _latency_seconds (number-only)
    # at this gate to prevent it from re-entering the heredoc path
    # (defense-in-depth pairing with CRIT-1's interpolation fix).
    jq -ec '
        .state
        | select(
            (.repo | type == "string") and
            (.fetched_at | type == "string") and
            (.cache_age_seconds | type == "number") and
            (.fetch_outcome | type == "string") and
            ((._latency_seconds | type) // "number")
        )
        | .recent_commits = (.recent_commits // []) | select(.recent_commits | type == "array")
        | .open_prs       = (.open_prs       // []) | select(.open_prs       | type == "array")
        | .ci_runs        = (.ci_runs        // []) | select(.ci_runs        | type == "array")
        | .blockers       = (.blockers       // []) | select(.blockers       | type == "array")
        | (._latency_seconds // 0) as $lat
        | if ($lat | type) == "number" and $lat >= 0 and $lat < 86400
            then ._latency_seconds = $lat
            else ._latency_seconds = 0
          end
    ' "$path" 2>/dev/null
}

cross_repo_cache_invalidate() {
    local target="${1:-}"
    if [[ -z "$target" ]]; then
        _l5_log "cross_repo_cache_invalidate: missing argument (repo or 'all')"
        return 2
    fi
    local cache_dir
    cache_dir="$(_l5_cache_dir)"
    if [[ "$target" == "all" ]]; then
        if [[ -d "$cache_dir" ]]; then
            # Shape-pin glob: only files matching the lib's owner__name.json
            # convention are eligible for delete. Defends against the
            # operator-typo cache_dir=/etc + invalidate-all DoS.
            find "$cache_dir" -maxdepth 1 -name "$_l5_cache_invalidate_glob" -type f -delete 2>/dev/null || true
        fi
        return 0
    fi
    _l5_validate_repo "$target" || return 2
    local path
    path="$(_l5_cache_path "$target")"
    [[ -f "$path" ]] && rm -f "$path"
    return 0
}

# -----------------------------------------------------------------------------
# _l5_cache_age_seconds <repo>
# Returns seconds since cached_at_epoch; non-zero exit if no cache.
# -----------------------------------------------------------------------------
_l5_cache_age_seconds() {
    local repo="$1"
    local path
    path="$(_l5_cache_path "$repo")"
    [[ -f "$path" ]] || return 1
    local cached_at now
    cached_at="$(jq -r '.cached_at_epoch // empty' "$path" 2>/dev/null || true)"
    if [[ -z "$cached_at" ]]; then return 1; fi
    if ! [[ "$cached_at" =~ $_L5_INT_RE ]]; then return 1; fi
    # Sanity bound: reject epochs in the future or wildly far in the past.
    # An attacker who can write the cache could otherwise pin cached_at_epoch
    # to year 9999 (cache-forever DoS) or 0 (force-stale signal).
    # Lower bound: 2020-01-01 (1577836800). Upper bound: now + 60s tolerance.
    now="$(_l5_now_epoch)"
    if (( cached_at < 1577836800 )); then return 1; fi
    if (( cached_at > now + 60 )); then return 1; fi
    # Cypherpunk MED-4: future-dated cached_at_epoch was previously echoing 0
    # (interpreted as "fresh") which would pin a poisoned cache forever. The
    # bounds above already reject future-dated entries; this branch retained
    # for clock-skew tolerance (now slightly behind cached_at by <=60s).
    if (( now < cached_at )); then
        echo 0
    else
        echo $(( now - cached_at ))
    fi
}

# -----------------------------------------------------------------------------
# _l5_cache_write <repo> <state_json>
# Atomically write the cached repoState JSON, mode 0600, with cached_at_epoch.
# -----------------------------------------------------------------------------
_l5_cache_write() {
    local repo="$1"
    local state="$2"
    local cache_dir path tmp now
    cache_dir="$(_l5_cache_dir)"
    mkdir -p "$cache_dir"
    chmod 0700 "$cache_dir" 2>/dev/null || true
    path="$(_l5_cache_path "$repo")"
    # Use mktemp (O_EXCL semantics) instead of ${path}.tmp.$$ to defend
    # against tmp-path symlink TOCTOU. A pre-Sprint-5 cypherpunk-style probe
    # showed `> "${path}.tmp.<pid>"` follows a planted symlink; mktemp's
    # exclusive open prevents that vector.
    if ! tmp="$(mktemp "${cache_dir}/.tmp.XXXXXX")"; then
        return 1
    fi
    chmod 0600 "$tmp" 2>/dev/null || true
    now="$(_l5_now_epoch)"
    if ! jq -nc --argjson state "$state" --argjson now "$now" \
        '{state: $state, cached_at_epoch: $now}' > "$tmp"; then
        rm -f "$tmp"
        return 1
    fi
    mv -f "$tmp" "$path"
}

# -----------------------------------------------------------------------------
# _l5_extract_blockers <notes_md_tail>
#
# Scan the NOTES.md tail for BLOCKER:/WARN: markers, emit a JSON array of
# {line, severity, context}. The matching is line-oriented; severity is
# uppercase.
#
# Trust boundary (per Sprint 5 SecCons): NOTES.md content is untrusted; we
# treat it as opaque text, never interpret as instructions.
# -----------------------------------------------------------------------------
_l5_extract_blockers() {
    local tail_text="$1"
    if [[ -z "$tail_text" ]]; then
        echo '[]'
        return 0
    fi
    # NOTE: pass text via argv (not stdin) — `python3 - <<'PY'` consumes stdin
    # for the script body, so a `<<<"$tail_text"` redirection would replace
    # the script. argv is unambiguous and trust-boundary-clean (Python receives
    # the bytes verbatim; we never interpret them as instructions).
    python3 - "$tail_text" <<'PY'
import json, sys, re
text = sys.argv[1]
out = []
# BLOCKER: or WARN: markers; line-anchored. Permit leading whitespace and
# bullet/list markers ('-', '*', '#', '>').
pat = re.compile(r'^[ \t]*[\-\*\#>]*[ \t]*(BLOCKER|WARN)[ \t]*:[ \t]*(.+?)[ \t]*$', re.MULTILINE)
# Cypherpunk MED-2: cap total emitted entries at 100 to defend against a
# pathological NOTES.md (e.g., 64KB of "BLOCKER:x") causing JSON-blowup
# multiplied across all repos in the cross_repo_read response.
MAX_ENTRIES = 100
for m in pat.finditer(text):
    if len(out) >= MAX_ENTRIES:
        out.append({"line": "[TRUNCATED]", "severity": "WARN",
                    "context": f"more than {MAX_ENTRIES} BLOCKER/WARN markers in NOTES.md tail; truncated"})
        break
    sev = m.group(1).upper()
    line = m.group(0).strip()
    context = m.group(2).strip()
    if len(line) > 4096:
        line = line[:4093] + "..."
    if len(context) > 4096:
        context = context[:4093] + "..."
    out.append({"line": line, "severity": sev, "context": context})
print(json.dumps(out))
PY
}

# -----------------------------------------------------------------------------
# _l5_gh_call <args...>
#
# Invoke gh with timeout. Returns body on stdout; exits non-zero on failure
# (including 429 / rate-limit). The caller routes timeouts and errors to
# error_diagnostic.
# -----------------------------------------------------------------------------
_l5_gh_call() {
    local timeout_s
    timeout_s="$(_l5_timeout_seconds)"
    local gh
    gh="$(_l5_gh_cmd)"
    timeout "${timeout_s}s" "$gh" "$@"
}

# -----------------------------------------------------------------------------
# _l5_fetch_repo <repo>
#
# Fetch one repo's state via parallel gh api calls. Emits a repoState JSON
# object on stdout, fetch_outcome=success|partial|error.
#
# Per-source error capture: each gh call's failure is logged into
# error_diagnostic but does not abort the full fetch (FR-L5-5).
# -----------------------------------------------------------------------------
_l5_fetch_repo() {
    # Relax errexit/pipefail inside this function — gh-call failures are
    # expected and explicitly captured into errors[]; we never want to abort
    # mid-fetch and leave the caller without a state JSON. Save+restore so
    # the caller's option state is preserved (cypherpunk MED-1 fix).
    local _saved_opts
    _saved_opts="$(_l5_save_shell_opts)"
    set +e
    set +o pipefail

    local repo="$1"
    local fetched_at started_epoch ended_epoch latency
    started_epoch="$(_l5_now_epoch)"
    fetched_at="$(_l5_now_iso8601)"

    local commits_json prs_json runs_json notes_text
    local fetch_outcome="success"
    local errors=()

    # Recent commits (last 5).
    if ! commits_json="$(_l5_gh_call api "repos/${repo}/commits?per_page=5" \
        --jq 'map({sha: .sha, message: (.commit.message // "" | split("\n")[0]), author: (.commit.author.name // ""), date: .commit.author.date})' 2>&1)"; then
        errors+=("commits: ${commits_json}")
        commits_json="[]"
        fetch_outcome="partial"
    fi
    # Validate JSON shape.
    if ! echo "$commits_json" | jq -e 'type == "array"' >/dev/null 2>&1; then
        commits_json="[]"
    fi

    # Open PRs.
    if ! prs_json="$(_l5_gh_call api "repos/${repo}/pulls?state=open&per_page=10" \
        --jq 'map({number: .number, title: .title, author: .user.login, draft: .draft})' 2>&1)"; then
        errors+=("pulls: ${prs_json}")
        prs_json="[]"
        fetch_outcome="partial"
    fi
    if ! echo "$prs_json" | jq -e 'type == "array"' >/dev/null 2>&1; then
        prs_json="[]"
    fi

    # CI runs (latest 5).
    if ! runs_json="$(_l5_gh_call api "repos/${repo}/actions/runs?per_page=5" \
        --jq '.workflow_runs | map({workflow: .name, status: .status, conclusion: .conclusion, started_at: .run_started_at})' 2>&1)"; then
        errors+=("runs: ${runs_json}")
        runs_json="[]"
        fetch_outcome="partial"
    fi
    if ! echo "$runs_json" | jq -e 'type == "array"' >/dev/null 2>&1; then
        runs_json="[]"
    fi

    # NOTES.md tail (best-effort; absence is not a partial failure).
    local notes_b64
    notes_text=""
    if notes_b64="$(_l5_gh_call api "repos/${repo}/contents/grimoires/loa/NOTES.md" \
        --jq '.content // empty' 2>/dev/null)"; then
        if [[ -n "$notes_b64" ]]; then
            local tail_lines
            tail_lines="$(_l5_notes_tail_lines)"
            # gh content is base64 with newlines; decode + tail.
            notes_text="$(echo "$notes_b64" | tr -d '\n' | base64 -d 2>/dev/null \
                | tail -n "$tail_lines" 2>/dev/null || true)"
        fi
    fi

    local blockers_json
    blockers_json="$(_l5_extract_blockers "$notes_text")"

    ended_epoch="$(_l5_now_epoch)"
    latency=$(( ended_epoch - started_epoch ))

    # If all three primary endpoints (commits, pulls, runs) failed, this is a
    # systemic error rather than partial — the caller should treat it as an
    # outage signal, not a degraded result.
    if (( ${#errors[@]} >= 3 )); then
        fetch_outcome="error"
    fi

    local diag
    if (( ${#errors[@]} > 0 )); then
        diag="$(printf '%s\n' "${errors[@]}" | head -c 4090)"
    else
        diag=""
    fi

    # Truncate notes_text to schema cap. Cypherpunk MED-3: byte-slicing
    # bash parameter expansion can land mid-UTF-8-codepoint, producing
    # invalid UTF-8 that jq --arg would reject. Use Python to find a safe
    # boundary at <= 65530 bytes when encoded as UTF-8.
    if (( ${#notes_text} > 65530 )); then
        notes_text="$(python3 - "$notes_text" <<'PY'
import sys
s = sys.argv[1]
b = s.encode('utf-8', errors='replace')
if len(b) <= 65530:
    print(s, end='')
else:
    truncated = b[:65530]
    while truncated:
        try:
            print(truncated.decode('utf-8'), end='')
            break
        except UnicodeDecodeError:
            truncated = truncated[:-1]
            if not truncated:
                break
PY
)"
    fi

    local state
    if [[ -n "$diag" ]]; then
        state="$(jq -nc \
            --arg repo "$repo" \
            --arg fetched_at "$fetched_at" \
            --arg outcome "$fetch_outcome" \
            --arg diag "$diag" \
            --arg notes "$notes_text" \
            --argjson commits "$commits_json" \
            --argjson prs "$prs_json" \
            --argjson runs "$runs_json" \
            --argjson blockers "$blockers_json" \
            --argjson latency "$latency" \
            '{
                repo: $repo,
                fetched_at: $fetched_at,
                cache_age_seconds: 0,
                fetch_outcome: $outcome,
                error_diagnostic: $diag,
                notes_md_tail: (if $notes == "" then null else $notes end),
                blockers: $blockers,
                sprint_state: null,
                recent_commits: $commits,
                open_prs: $prs,
                ci_runs: $runs,
                _latency_seconds: $latency
            }')"
    else
        state="$(jq -nc \
            --arg repo "$repo" \
            --arg fetched_at "$fetched_at" \
            --arg outcome "$fetch_outcome" \
            --arg notes "$notes_text" \
            --argjson commits "$commits_json" \
            --argjson prs "$prs_json" \
            --argjson runs "$runs_json" \
            --argjson blockers "$blockers_json" \
            --argjson latency "$latency" \
            '{
                repo: $repo,
                fetched_at: $fetched_at,
                cache_age_seconds: 0,
                fetch_outcome: $outcome,
                error_diagnostic: null,
                notes_md_tail: (if $notes == "" then null else $notes end),
                blockers: $blockers,
                sprint_state: null,
                recent_commits: $commits,
                open_prs: $prs,
                ci_runs: $runs,
                _latency_seconds: $latency
            }')"
    fi

    echo "$state"
    _l5_restore_shell_opts "$_saved_opts"
}

# -----------------------------------------------------------------------------
# _l5_serve_from_cache_or_fetch <repo>
#
# Cache decision tree:
#   - fresh (age < ttl): serve from cache
#   - stale within fallback_stale_max: try fetch; on failure, serve cache
#       with cache_age_seconds populated and fetch_outcome=stale_fallback
#   - stale beyond fallback_stale_max OR no cache: fetch; on failure,
#       return error state (no fallback available)
# -----------------------------------------------------------------------------
_l5_serve_from_cache_or_fetch() {
    # cypherpunk MED-1 / general-purpose M1: save+restore caller's option
    # state so `set +e` / `set +o pipefail` here don't leak.
    local _saved_opts
    _saved_opts="$(_l5_save_shell_opts)"
    set +e
    set +o pipefail
    local repo="$1"
    local ttl stale_max age cached state
    ttl="$(_l5_cache_ttl)"
    stale_max="$(_l5_fallback_stale_max)"

    if age="$(_l5_cache_age_seconds "$repo" 2>/dev/null)"; then
        if (( age < ttl )); then
            cached="$(cross_repo_cache_get "$repo")"
            if [[ -n "$cached" ]]; then
                # Update cache_age_seconds to reflect age.
                echo "$cached" | jq -c \
                    --argjson age "$age" \
                    '. + {cache_age_seconds: $age}'
                _l5_restore_shell_opts "$_saved_opts"; return 0
            fi
        fi
        # Stale but within fallback; try fetch first.
        state="$(_l5_fetch_repo "$repo" 2>/dev/null)"
        if [[ -n "$state" ]]; then
            local outcome
            outcome="$(echo "$state" | jq -r '.fetch_outcome' 2>/dev/null)"
            if [[ "$outcome" == "success" || "$outcome" == "partial" ]]; then
                _l5_cache_write "$repo" "$state" || true
                echo "$state"
                _l5_restore_shell_opts "$_saved_opts"; return 0
            fi
            # outcome=error AND we have a cache within fallback window: prefer
            # the cache (operator-visibility primitive should serve last-known
            # state during transient outages).
            if [[ "$outcome" == "error" ]] && (( age <= stale_max )); then
                cached="$(cross_repo_cache_get "$repo")"
                if [[ -n "$cached" ]]; then
                    echo "$cached" | jq -c \
                        --argjson age "$age" \
                        '. + {cache_age_seconds: $age, fetch_outcome: "stale_fallback", error_diagnostic: "live fetch failed; serving stale cache (within fallback window)"}'
                    _l5_restore_shell_opts "$_saved_opts"; return 0
                fi
            fi
            # outcome=error and beyond stale-fallback OR no cache: emit error.
            echo "$state"
            _l5_restore_shell_opts "$_saved_opts"; return 0
        fi
        # Fetch produced no state at all; if within stale-fallback, serve cache
        if (( age <= stale_max )); then
            cached="$(cross_repo_cache_get "$repo")"
            if [[ -n "$cached" ]]; then
                echo "$cached" | jq -c \
                    --argjson age "$age" \
                    '. + {cache_age_seconds: $age, fetch_outcome: "stale_fallback", error_diagnostic: "live fetch failed; serving stale cache (within fallback window)"}'
                _l5_restore_shell_opts "$_saved_opts"; return 0
            fi
        fi
    fi

    # No usable cache; fetch.
    state="$(_l5_fetch_repo "$repo")"
    if [[ -n "$state" ]]; then
        local outcome
        outcome="$(echo "$state" | jq -r '.fetch_outcome' 2>/dev/null)"
        if [[ "$outcome" == "success" || "$outcome" == "partial" ]]; then
            _l5_cache_write "$repo" "$state" || true
        fi
        echo "$state"
        _l5_restore_shell_opts "$_saved_opts"; return 0
    fi

    # Total failure with no cache: emit an error repoState.
    local fetched_at
    fetched_at="$(_l5_now_iso8601)"
    jq -nc \
        --arg repo "$repo" \
        --arg fetched_at "$fetched_at" \
        --arg diag "fetch failed and no cached state available" \
        '{
            repo: $repo,
            fetched_at: $fetched_at,
            cache_age_seconds: 0,
            fetch_outcome: "error",
            error_diagnostic: $diag,
            notes_md_tail: null,
            blockers: [],
            sprint_state: null,
            recent_commits: [],
            open_prs: [],
            ci_runs: [],
            _latency_seconds: 0
        }'
    _l5_restore_shell_opts "$_saved_opts"
}

# -----------------------------------------------------------------------------
# cross_repo_read <repos_json>
#
# repos_json: JSON array of "owner/name" strings.
#
# Output: CrossRepoState JSON on stdout (matches cross-repo-state.schema.json).
# Side effect: emits cross_repo.read audit event with summary metrics.
#
# Concurrency: spawns up to LOA_CROSS_REPO_PARALLEL workers; each writes its
# state to a temp file under a private working dir. Aggregation reads all
# temp files in declared input order (preserves caller-specified ordering).
# -----------------------------------------------------------------------------
cross_repo_read() {
    # Disable errexit/pipefail: per-repo failures are explicitly captured
    # into the response shape (FR-L5-5). A bats test or operator script with
    # `set -e` must not kill this function mid-aggregation.
    # Cypherpunk MED-1 / general-purpose M1: save+restore caller's option
    # state so set +e doesn't leak into a sourced operator script.
    local _saved_opts
    _saved_opts="$(_l5_save_shell_opts)"
    set +e
    set +o pipefail

    local repos_arg="${1:-}"
    if [[ -z "$repos_arg" ]]; then
        _l5_log "cross_repo_read: missing repos_json argument"
        _l5_restore_shell_opts "$_saved_opts"; return 2
    fi
    if ! echo "$repos_arg" | jq -e 'type == "array"' >/dev/null 2>&1; then
        _l5_log "cross_repo_read: repos_json must be a JSON array"
        _l5_restore_shell_opts "$_saved_opts"; return 2
    fi
    local count
    count="$(echo "$repos_arg" | jq 'length')"
    if (( count == 0 )); then
        _l5_log "cross_repo_read: empty repos array"
        _l5_restore_shell_opts "$_saved_opts"; return 2
    fi
    if (( count > 50 )); then
        _l5_log "cross_repo_read: too many repos ($count); cap is 50"
        _l5_restore_shell_opts "$_saved_opts"; return 2
    fi

    # Validate every repo identifier up front to defend against shell-injection
    # via gh-args.
    local repo
    for repo in $(echo "$repos_arg" | jq -r '.[]'); do
        _l5_validate_repo "$repo" || {
            _l5_log "cross_repo_read: invalid repo identifier"
            _l5_restore_shell_opts "$_saved_opts"; return 2
        }
    done

    local gh
    gh="$(_l5_gh_cmd)"
    if ! command -v "$gh" >/dev/null 2>&1; then
        _l5_log "cross_repo_read: gh CLI not found at '$gh'"
        _l5_restore_shell_opts "$_saved_opts"; return 1
    fi

    local work
    work="$(mktemp -d)"
    chmod 0700 "$work" 2>/dev/null || true
    # NOTE: no RETURN trap — under bash, RETURN can fire when this function is
    # called via command substitution (`$(...)`) and exits the substitution
    # subshell, racing the still-running workers spawned by `(...) &`. Cleanup
    # is performed explicitly at the END of the function after aggregation.

    # Spawn workers with bounded parallelism.
    local parallel
    parallel="$(_l5_parallel)"
    local pids=() repos=() i=0
    while IFS= read -r repo; do
        repos+=("$repo")
    done < <(echo "$repos_arg" | jq -r '.[]')

    local started_overall_epoch
    started_overall_epoch="$(_l5_now_epoch)"

    for repo in "${repos[@]}"; do
        # Bounded parallelism: wait if at limit.
        while (( ${#pids[@]} >= parallel )); do
            local newpids=()
            local pid
            for pid in "${pids[@]}"; do
                if kill -0 "$pid" 2>/dev/null; then
                    newpids+=("$pid")
                fi
            done
            pids=(${newpids[@]+"${newpids[@]}"})
            (( ${#pids[@]} < parallel )) && break
            sleep 0.1
        done

        local idx="$i"
        i=$((i + 1))
        local out_file="${work}/${idx}.json"
        (
            # Workers must ALWAYS produce $out_file even on internal failure.
            # Relax set -e so a hidden non-zero (e.g., from gh-call within the
            # serve_from_cache_or_fetch chain) doesn't kill the subshell
            # without writing the fallback state.
            set +e
            state="$(_l5_serve_from_cache_or_fetch "$repo" 2>/dev/null)"
            if [[ -n "$state" ]]; then
                echo "$state" > "$out_file"
            else
                jq -nc --arg repo "$repo" --arg ts "$(_l5_now_iso8601)" \
                    '{repo: $repo, fetched_at: $ts, cache_age_seconds: 0, fetch_outcome: "error", error_diagnostic: "worker produced no state", notes_md_tail: null, blockers: [], sprint_state: null, recent_commits: [], open_prs: [], ci_runs: [], _latency_seconds: 0}' \
                    > "$out_file"
            fi
        ) &
        pids+=("$!")
    done

    # Wait for all workers.
    local p
    for p in ${pids[@]+"${pids[@]}"}; do
        wait "$p" 2>/dev/null || true
    done

    local ended_overall_epoch overall_seconds
    ended_overall_epoch="$(_l5_now_epoch)"
    overall_seconds=$(( ended_overall_epoch - started_overall_epoch ))

    # Aggregate.
    local repos_array="[]"
    for ((idx=0; idx<i; idx++)); do
        local f="${work}/${idx}.json"
        if [[ -f "$f" ]]; then
            local state
            state="$(cat "$f")"
            # Strip the internal _latency_seconds field; it's used only for p95.
            local cleaned
            cleaned="$(echo "$state" | jq -c 'del(._latency_seconds)')"
            repos_array="$(echo "$repos_array" | jq -c --argjson item "$cleaned" '. + [$item]')"
        fi
    done

    # p95 latency computation across per-repo _latency_seconds.
    #
    # CRIT-1 (cypherpunk): the previous implementation interpolated
    # $latencies into a Python heredoc via `<<PY` (unquoted delimiter), which
    # was a shell-parameter expansion. Worker output files include a
    # _latency_seconds field that is preserved verbatim through the cache
    # round-trip — an attacker with .run/cache write access could inject
    # `1\n"""\n<arbitrary python>\n"""` and trigger RCE in the operator
    # shell on the next stale-fallback. Fix: route latency values through
    # stdin (NOT shell-interpolation), and validate each value as numeric
    # via Python before use.
    local latencies
    latencies="$(for ((idx=0; idx<i; idx++)); do
        local f="${work}/${idx}.json"
        if [[ -f "$f" ]]; then
            jq -r '._latency_seconds // 0' "$f"
        fi
    done | sort -n)"
    local p95
    p95="$(printf '%s\n' "$latencies" | python3 - <<'PY'
import sys, math, re
raw = sys.stdin.read().split()
NUMERIC = re.compile(r'^[0-9]+(\.[0-9]+)?$')
data = []
for x in raw:
    if NUMERIC.match(x):
        data.append(float(x))
if not data:
    print("null")
else:
    data.sort()
    # ceil-index p95 (cypherpunk MED-5 / general-purpose M5 fix:
    # math.ceil over int() so small-N samples produce the correct p95).
    idx = max(0, math.ceil(len(data) * 0.95) - 1)
    if idx >= len(data):
        idx = len(data) - 1
    print(data[idx])
PY
)"

    # Counts.
    local success_n stale_n error_n partial_n blockers_total
    success_n="$(echo "$repos_array" | jq '[.[] | select(.fetch_outcome == "success")] | length')"
    partial_n="$(echo "$repos_array" | jq '[.[] | select(.fetch_outcome == "partial")] | length')"
    stale_n="$(echo "$repos_array"   | jq '[.[] | select(.fetch_outcome == "stale_fallback")] | length')"
    error_n="$(echo "$repos_array"   | jq '[.[] | select(.fetch_outcome == "error")] | length')"
    blockers_total="$(echo "$repos_array" | jq '[.[] | (.blockers | length)] | add // 0')"

    local fetched_at
    fetched_at="$(_l5_now_iso8601)"

    # Final CrossRepoState. rate_limit_remaining intentionally null (would
    # require a final gh api call /rate_limit; we capture only on demand to
    # not double the budget). Operators can inspect via gh api /rate_limit
    # directly; we surface it as null + document.
    local response
    response="$(jq -nc \
        --argjson repos "$repos_array" \
        --arg fetched_at "$fetched_at" \
        --argjson p95 "$p95" \
        --argjson partial "$((partial_n + stale_n + error_n))" \
        '{
            repos: $repos,
            fetched_at: $fetched_at,
            p95_latency_seconds: $p95,
            rate_limit_remaining: null,
            partial_failures: $partial
        }')"

    # Audit event (best-effort).
    local payload log_path
    log_path="$(_l5_log_path)"
    # general-purpose M2: emit partial_count separately from error_count so
    # the audit trail distinguishes "some endpoints failed" from "all failed".
    # Cypherpunk MED-6: gh_override_active surfaces in audit payload.
    local gh_override
    gh_override="$(_l5_gh_override_active)"
    payload="$(jq -nc \
        --argjson repos_count "$count" \
        --argjson success_count "$success_n" \
        --argjson stale_fallback_count "$stale_n" \
        --argjson partial_count "$partial_n" \
        --argjson error_count "$error_n" \
        --argjson p95 "$p95" \
        --argjson blockers_total "$blockers_total" \
        --argjson gh_override "$gh_override" \
        '{
            repos_count: $repos_count,
            success_count: $success_count,
            stale_fallback_count: $stale_fallback_count,
            partial_count: $partial_count,
            error_count: $error_count,
            p95_latency_seconds: $p95,
            rate_limit_remaining: null,
            blockers_total: $blockers_total,
            gh_override_active: $gh_override
        }')"
    audit_emit "L5" "cross_repo.read" "$payload" "$log_path" \
        || _l5_log "cross_repo_read: audit_emit failed (non-fatal)"

    echo "$response"

    # Explicit cleanup of work dir (replacing the previous RETURN trap which
    # raced workers under command substitution).
    if [[ -n "${work:-}" && -d "$work" ]]; then
        find "$work" -type f -delete 2>/dev/null || true
        rmdir "$work" 2>/dev/null || true
    fi

    _l5_restore_shell_opts "$_saved_opts"
}
