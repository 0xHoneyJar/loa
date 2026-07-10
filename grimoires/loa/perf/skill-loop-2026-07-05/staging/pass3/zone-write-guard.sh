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
    local tab=$'\t'
    local rows
    rows=$(yq -r '(.zones.framework.tracked_paths[]? | tostring | split("\n") | .[] | "framework'"${tab}"'" + .),
                  (.zones.project.tracked_paths[]? | tostring | split("\n") | .[] | "project'"${tab}"'" + .),
                  (.zones.shared.tracked_paths[]? | tostring | split("\n") | .[] | "shared'"${tab}"'" + .)' \
        "${ZONES_FILE}" 2>/dev/null) || rows=""
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
    local trajectory_dir="${PROJECT_ROOT}/grimoires/loa/a2a/trajectory"
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
