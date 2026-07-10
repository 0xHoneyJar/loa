#!/usr/bin/env bash
# =============================================================================
# .claude/hooks/safety/zone-write-guard.sh
# =============================================================================
# cycle-106 sprint-1 T1.3 — PreToolUse hook for Write/Edit. Enforces the
# framework-zone vs project-zone boundary declared in
# grimoires/loa/zones.yaml. Blocks zone-violating writes with an
# operator-readable diagnostic.
#
# Decision matrix (SDD §3.1):
#   framework zone + project-work    → BLOCK
#   framework zone + update-loa      → ALLOW
#   framework zone + other actor     → BLOCK + log
#   project zone   + project-work    → ALLOW
#   project zone   + update-loa      → BLOCK
#   project zone   + other actor     → ALLOW
#   shared zone    + any actor       → ALLOW
#   unclassified path                → ALLOW (positive-declaration only)
#
# Actor identification (LOA_ACTOR env var):
#   - "project-work" — default (operator's day-to-day)
#   - "update-loa"   — set by .claude/scripts/update-loa.sh
#   - "sync-constructs" — set by sync-constructs.sh
#   - unset / other  — treated as "project-work"
#
# Escape hatches:
#   LOA_ZONE_GUARD_BYPASS=1  → ALLOW + stderr WARN + trajectory log
#   LOA_ZONE_GUARD_DISABLE=1 → ALLOW with no diagnostic (framework bootstrap only)
#   .run/zone-guard-authorization.json (cycle-119) → framework-zone ALLOW with
#       per-write audit when marker is valid (scope=framework, non-empty
#       reason, unexpired RFC3339-Z expires_at, mtime ≤24h). The agent-usable
#       equivalent of BYPASS for operator-directed framework self-development;
#       env override for tests: LOA_ZONE_GUARD_AUTH_FILE.
#
# Path input (Claude Code PreToolUse hook contract):
#   $CLAUDE_TOOL_FILE_PATH — the path being written
#   Falls back to $1 when run as a CLI for testing.
#
# Exit codes (bug-1002 review iter-2 — Claude Code blocks PreToolUse on
# exit 2; exit 1 is a NON-blocking hook error, so the old 1=BLOCK contract
# reported BLOCKED while the write proceeded):
#   0 = ALLOW
#   2 = BLOCK (policy violation, or strict-config failure under
#       LOA_REQUIRE_ZONES=1 — fail-closed)
#
# perf pass-2 (2026-07-05, skill-loop): fork/exec reduction — the two `date`
# spawns per decision collapse to one bash strftime (printf %(…)T, TZ-scoped
# to UTC; the log-file date derives from the same timestamp, which also
# removes a midnight-straddle inconsistency between the two old date calls);
# the $(dirname BASH_SOURCE) spawn is a parameter expansion; the _block
# heredoc `cat` is printf. realpath is KEPT (symlink resolution is
# load-bearing for the traversal/submodule hardening below).
#
# perf pass-3 (2026-07-05, skill-loop): yq single-pass consolidation — the
# per-zone `yq .zones.<name>.tracked_paths[]?` spawns (1-3 per decision, 2 in
# the common project-zone case) collapse into ONE yq invocation that emits
# every pattern as a "<zone><TAB><pattern-line>" row. Isomorphism notes:
#   - The row stream preserves the FIXED evaluation order framework →
#     project → shared (explicit per-zone expressions, NOT to_entries —
#     document order and any extra zones in the yaml are ignored, exactly
#     like the old fixed `for zone_name in ...` loop). First match wins.
#   - Each entry is rendered with tostring and split("\n"), so a multi-line
#     string entry contributes the SAME per-line patterns the old
#     while-read loop saw, and empty lines are skipped by the same
#     [[ -z ]] guard. (Sole reachable divergence: a non-string entry — a
#     map/seq, out of contract with zones.schema.yaml — renders flow-style
#     on one row where the old code saw its block-style lines; both shapes
#     are garbage patterns that classify identically as no-match. A
#     scalar-typed tracked_paths suppresses via []? in both versions —
#     probe-verified.)
#   - TAB delimiting is byte-safe HERE (unlike for arbitrary command
#     strings) because field 1 is from the fixed zone-name set and bash
#     splits on the FIRST tab only: a pattern containing tabs survives
#     byte-identically in field 2. The tab byte is injected from bash
#     ($'\t'), never spelled inside the yq program.
#   - yq failure (malformed yaml) yields zero rows → "unclassified", the
#     same terminal state as the old per-zone `|| continue` cascade.
#
# perf pass-6 (2026-07-05, skill-loop): memoization — the pass-3 yq row
# stream is a PURE function of zones.yaml bytes, re-derived on EVERY
# Write/Edit. It is now cached at .run/perf-cache/zone-write-guard.v1.rows
# (the ONLY additive side effect of this pass; .run/ is State-Zone,
# gitignored). Design + trust notes:
#   - Cache format: line 1 = key "<ns-mtime>:<size>:<abs-path>" of
#     zones.yaml (ONE GNU-first `stat -Lc '%y:%s'` spawn — cheaper than the
#     yq parse it replaces); remaining bytes = the row stream verbatim.
#     %y carries nanosecond mtime, so a same-second edit still rotates the
#     key. The path component is the $PWD-absolutized ZONES_FILE, so two
#     repos/worktrees sharing a relative LOA_ZONES_FILE name cannot
#     cross-contaminate (each hook install also has its own PROJECT_ROOT
#     and therefore its own cache file).
#   - UNCONDITIONAL FAIL-OPEN: missing/unreadable/corrupt cache, key
#     mismatch, stat failure (incl. non-GNU stat — BSD hosts simply never
#     cache), or a torn concurrent state all fall through to the ORIGINAL
#     yq parse verbatim and rewrite the cache. Writes are atomic
#     ($$-suffixed temp + mv -f -T in the same dir; readers see old or new,
#     never partial; concurrent writers: last wins).
#   - Staleness: the key is stat'd BEFORE the parse, so a write racing the
#     parse caches new-content rows under the old key and the NEXT call's
#     stat misses and re-parses — the one-call read race is identical to
#     the uncached hook's. An edit to zones.yaml is therefore reflected in
#     the very next invocation.
#   - Trust argument (this hook is a security fence): the cache adds NO new
#     attacker capability. Anyone who can write .run/perf-cache/ can
#     already write grimoires/loa/zones.yaml itself — grimoires/ and .run/
#     are both operator-writable State-Zone paths, and zones.yaml is the
#     authoritative input this guard trusts today. Forging the cache is
#     strictly harder than editing the policy file it mirrors (key must
#     match zones.yaml's live stat identity). Same accepted-bypass posture
#     as block-destructive-bash.sh (hooks-reference.md).
#   - Accepted divergence (out of contract): a zones.yaml pattern carrying
#     a raw NUL byte made the old $() capture warn "ignored null byte" on
#     EVERY call; the cached path warns only on the cold parse. Rows (and
#     decisions) are unaffected — bash variables never hold NUL either way.
#   - If the yq row-emitting program EVER changes, bump the cache filename
#     version (v1 → v2) — the key deliberately excludes the program text.
#   - realpath stays; the stdin jq stays; `command -v yq` stays (a warm hit
#     could technically serve without yq, but yq-absent behavior must stay
#     byte-identical: WARN + allow).
#
# Tested by tests/unit/zone-write-guard.bats (ZWG-T1..T12).
# =============================================================================

set -uo pipefail
# NB: don't set -e — we need to handle missing files / malformed YAML
# gracefully without aborting the hook.

# ---- early exits ----------------------------------------------------------

if [[ "${LOA_ZONE_GUARD_DISABLE:-}" == "1" ]]; then
    exit 0  # framework bootstrap path
fi

# Resolve target path. Precedence: env (legacy contract) > $1 (bats CLI) >
# stdin JSON (the ACTUAL Claude Code PreToolUse contract — payload arrives
# as {"tool_input":{"file_path":...}} on stdin). bug-1002 review iter-1:
# without the stdin branch, wiring this hook made it INERT — TARGET was
# always empty under real hook execution and every write was allowed.
TARGET="${CLAUDE_TOOL_FILE_PATH:-${1:-}}"
if [[ -z "${TARGET}" ]] && [[ ! -t 0 ]]; then
    # Audit iter: stream stdin straight into jq (no shell-variable copy of
    # potentially large Write payloads); notebook_path covers NotebookEdit.
    TARGET="$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null || true)"
fi
if [[ -z "${TARGET}" ]]; then
    # No path = nothing to guard
    exit 0
fi

# ---- locate zones.yaml ---------------------------------------------------

# perf pass-2: was $(cd "$(dirname BASH_SOURCE)" && pwd). ${p%/*} equals
# dirname for every slash-containing script path; the two unreachable-in-
# production shapes (bare filename via PATH-less invocation → ".", root-level
# script "/x.sh" → "/") are covered explicitly. The cd/pwd canonicalization
# subshell is retained.
_src="${BASH_SOURCE[0]}"
_src_dir="${_src%/*}"
if [[ "${_src_dir}" == "${_src}" ]]; then _src_dir="."; fi
if [[ -z "${_src_dir}" ]]; then _src_dir="/"; fi
SCRIPT_DIR="$(cd "${_src_dir}" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# Audit iter-2 (traversal, hardened): canonicalize ./.. lexically and anchor
# against PROJECT_ROOT — NOT the hook CWD. With a subdirectory CWD,
# `../.claude/x` canonicalized-relative-to-. kept a ..-prefixed raw string
# that matched no framework glob (unclassified -> ALLOW bypass). Absolute
# canon + root-strip classifies it correctly regardless of CWD; absolute
# paths outside the project stay absolute and match no repo glob.
_abs="$(realpath -m "${TARGET}" 2>/dev/null || true)"
if [[ -n "${_abs}" ]]; then
    case "${_abs}" in
        "${PROJECT_ROOT}"/*) TARGET="${_abs#"${PROJECT_ROOT}"/}" ;;
        *) TARGET="${_abs}" ;;
    esac
fi
# Audit iter-3 (submodule mode): realpath resolves the .claude symlink to
# its physical home under .loa/.claude/, which matches no zone glob —
# framework writes fell through unclassified->ALLOW on consumer repos.
# Map the physical prefix back to the logical zone before classification
# (covers both symlink-resolved and direct .loa/.claude/ targets).
case "${TARGET}" in
    .loa/.claude/*) TARGET=".claude/${TARGET#.loa/.claude/}" ;;
esac
ZONES_FILE="${LOA_ZONES_FILE:-${PROJECT_ROOT}/grimoires/loa/zones.yaml}"

if [[ ! -f "${ZONES_FILE}" ]]; then
    if [[ "${LOA_REQUIRE_ZONES:-0}" == "1" ]]; then
        echo "[zone-write-guard] ERROR: zones.yaml required but not found at ${ZONES_FILE}" >&2
        exit 2
    fi
    # Graceful degradation — no manifest means no opinions
    exit 0
fi

if ! command -v yq >/dev/null 2>&1; then
    echo "[zone-write-guard] WARN: yq not available; cannot enforce zones — allowing" >&2
    exit 0
fi

# ---- classify the path ---------------------------------------------------

# Normalize the target to repo-relative for matching.
if [[ "${TARGET}" == /* ]]; then
    case "${TARGET}" in
        ${PROJECT_ROOT}/*) TARGET="${TARGET#${PROJECT_ROOT}/}" ;;
    esac
fi

_path_matches_glob() {
    local path="$1"
    local pattern="$2"
    # Use bash extglob ** support via shopt
    shopt -s extglob globstar nullglob
    # shellcheck disable=SC2053
    [[ "$path" == $pattern ]]
}

_zone_for_path() {
    local path="$1"
    # perf pass-3: ONE yq pass emits "<zone><TAB><pattern-line>" rows in the
    # fixed framework → project → shared order (see header note). First
    # matching row decides the zone.
    # perf pass-6: the row stream is memoized keyed on zones.yaml identity
    # (see header note). Any anomaly falls through to the yq parse verbatim.
    local tab=$'\t'
    local rows="" cache_key="" cache_hit=0
    local cache_file="${PROJECT_ROOT}/.run/perf-cache/zone-write-guard.v1.rows"
    local src_abs="${ZONES_FILE}" src_id=""
    [[ "${src_abs}" != /* ]] && src_abs="${PWD}/${src_abs}"
    src_id=$(stat -Lc '%y:%s' -- "${ZONES_FILE}" 2>/dev/null) || src_id=""
    [[ -n "${src_id}" ]] && cache_key="${src_id}:${src_abs}"
    if [[ -n "${cache_key}" && -f "${cache_file}" ]]; then
        # Slurp via the read builtin, NOT $(<file): a failed $(<file)
        # redirection aborts an errexit shell even inside a || list
        # (host-probed, bash 5.2) and leaks a bash error line; read -rd ''
        # returns empty on missing/unreadable/dir/NUL-torn inputs, exactly
        # the fail-open we need. It also preserves the file bytes verbatim
        # (a valid cache is "<key>\n<rows>", rows carrying no trailing
        # newline by construction of the $()-captured writer below).
        local cached=""
        IFS= read -rd '' cached 2>/dev/null < "${cache_file}" || true
        if [[ "${cached}" == "${cache_key}"$'\n'* ]]; then
            rows="${cached#*$'\n'}"
            cache_hit=1
        fi
    fi
    if [[ "${cache_hit}" -eq 0 ]]; then
        rows=$(yq -r '(.zones.framework.tracked_paths[]? | tostring | split("\n") | .[] | "framework'"${tab}"'" + .),
                      (.zones.project.tracked_paths[]? | tostring | split("\n") | .[] | "project'"${tab}"'" + .),
                      (.zones.shared.tracked_paths[]? | tostring | split("\n") | .[] | "shared'"${tab}"'" + .)' \
            "${ZONES_FILE}" 2>/dev/null) || rows=""
        if [[ -n "${cache_key}" ]]; then
            local cache_dir="${cache_file%/*}" cache_tmp="${cache_file}.$$"
            {
                [[ -d "${cache_dir}" ]] || mkdir -p "${cache_dir}"
                printf '%s\n%s' "${cache_key}" "${rows}" > "${cache_tmp}" &&
                    mv -f -T "${cache_tmp}" "${cache_file}"
            } 2>/dev/null || rm -f -- "${cache_tmp}" 2>/dev/null || true
        fi
    fi
    local row zone_name pattern
    while IFS= read -r row; do
        zone_name="${row%%"${tab}"*}"
        pattern="${row#*"${tab}"}"
        [[ -z "$pattern" ]] && continue
        if _path_matches_glob "$path" "$pattern"; then
            echo "$zone_name"
            return 0
        fi
    done <<< "$rows"
    echo "unclassified"
}

ZONE="$(_zone_for_path "${TARGET}")"
ACTOR="${LOA_ACTOR:-project-work}"

# ---- decision ------------------------------------------------------------

_emit_decision() {
    local decision="$1"
    local reason="$2"
    # cycle-119 audit: test-mode override so bats suites don't pollute the
    # production trajectory log (the marker's audit trail must stay clean).
    local trajectory_dir="${LOA_ZONE_GUARD_TRAJECTORY_DIR:-${PROJECT_ROOT}/grimoires/loa/a2a/trajectory}"
    if [[ -d "${trajectory_dir}" ]]; then
        # perf pass-2: one bash strftime replaces two `date -u` spawns; the
        # log-file date is the timestamp's date field (identical format,
        # single clock read).
        local ts
        TZ=UTC0 printf -v ts '%(%Y-%m-%dT%H:%M:%SZ)T' -1
        local log_file="${trajectory_dir}/zone-guard-${ts:0:10}.jsonl"
        printf '{"timestamp":"%s","decision":"%s","actor":"%s","zone":"%s","path":"%s","reason":"%s"}\n' \
            "$ts" "$decision" "$ACTOR" "$ZONE" "$TARGET" "$reason" >> "${log_file}" 2>/dev/null || true
    fi
}

_block() {
    local reason="$1"
    # perf pass-2: printf replaces the heredoc `cat` spawn — byte-identical.
    printf '%s\n' \
        "[zone-write-guard] BLOCKED: actor=${ACTOR} path=${TARGET} zone=${ZONE}" \
        "  Reason: ${reason}" \
        "  Override: LOA_ZONE_GUARD_BYPASS=1 <retry command>" \
        "  Reference: grimoires/loa/runbooks/zone-hygiene.md" >&2
    _emit_decision "BLOCK" "${reason}"
    exit 2
}

_allow() {
    _emit_decision "ALLOW" "${1:-default}"
    exit 0
}

# Bypass escape hatch
if [[ "${LOA_ZONE_GUARD_BYPASS:-}" == "1" ]]; then
    echo "[zone-write-guard] WARNING: LOA_ZONE_GUARD_BYPASS=1; allowing actor=${ACTOR} path=${TARGET} zone=${ZONE}" >&2
    _emit_decision "BYPASS" "operator-override-via-env"
    exit 0
fi

# cycle-119: file-based framework-dev authorization marker. Sanctioned path
# for UPSTREAM (framework-repo) self-development sessions: agent tool calls
# cannot deliver LOA_ZONE_GUARD_BYPASS into PreToolUse hook subprocesses (env
# does not propagate from Bash tool calls into the harness), so the env hatch
# documented in zones.yaml ("agents use LOA_ZONE_GUARD_BYPASS=1 when an
# operator explicitly directs a change") was unreachable for exactly the
# sessions it was written for. Trust argument (same as the perf pass-6 cache):
# the marker lives in .run/ (State Zone) — anyone who can write it can already
# edit zones.yaml, the policy file this guard trusts. Unlike the env hatch it
# is AUDITED (reason logged per allowed write) and BOUNDED (expires_at
# required, RFC3339 UTC "Z" form; plus a 24h file-mtime staleness cap).
# Malformed / expired / stale / wrong-scope markers fall through to the
# normal decision matrix — fail-closed. Tested by ZWG-T20..T24.
if [[ "${ZONE}" == "framework" ]]; then
    AUTH_FILE="${LOA_ZONE_GUARD_AUTH_FILE:-${PROJECT_ROOT}/.run/zone-guard-authorization.json}"
    if [[ -f "${AUTH_FILE}" ]] && command -v jq >/dev/null 2>&1; then
        _auth_row="$(jq -r 'select(type=="object"
                              and .scope=="framework"
                              and (.reason|type=="string") and ((.reason|length)>0)
                              and (.expires_at|type=="string")
                              and (.expires_at|test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")))
                            | [.expires_at, .reason] | @tsv' "${AUTH_FILE}" 2>/dev/null)" || _auth_row=""
        if [[ -n "${_auth_row}" ]]; then
            _auth_expires="${_auth_row%%$'\t'*}"
            _auth_reason="${_auth_row#*$'\t'}"
            _auth_reason="$(printf '%s' "${_auth_reason}" | tr -d '"\\' | tr '\n\t' '  ')"
            TZ=UTC0 printf -v _auth_now '%(%Y-%m-%dT%H:%M:%SZ)T' -1
            printf -v _auth_epoch '%(%s)T' -1
            _auth_mtime="$(stat -Lc '%Y' -- "${AUTH_FILE}" 2>/dev/null || stat -Lf '%m' -- "${AUTH_FILE}" 2>/dev/null || echo 0)"
            if [[ "${_auth_mtime}" =~ ^[0-9]+$ ]] \
               && (( _auth_epoch - _auth_mtime <= 86400 )) \
               && [[ "${_auth_now}" < "${_auth_expires}" ]]; then
                echo "[zone-write-guard] AUTHORIZED: framework-dev marker (${_auth_reason}) actor=${ACTOR} path=${TARGET}" >&2
                _emit_decision "AUTHORIZED-MARKER" "${_auth_reason}"
                exit 0
            fi
        fi
    fi
fi

case "${ZONE}" in
    framework)
        case "${ACTOR}" in
            update-loa)        _allow "update-loa writes framework zone" ;;
            project-work)      _block "framework-zone is upstream-managed; use overrides or file upstream" ;;
            *)                 _block "actor=${ACTOR} not authorized to write framework zone" ;;
        esac
        ;;
    project)
        case "${ACTOR}" in
            update-loa)        _block "/update-loa MUST NOT write project-zone paths (cycle-106)" ;;
            *)                 _allow "actor=${ACTOR} writes project zone" ;;
        esac
        ;;
    shared)
        _allow "shared zone accepts any actor"
        ;;
    unclassified)
        # zones.yaml is a positive declaration. Unclassified = no opinion.
        _allow "path not declared in zones.yaml; no opinion"
        ;;
    *)
        _allow "unknown zone classification — defaulting to ALLOW"
        ;;
esac
