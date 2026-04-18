#!/usr/bin/env bash
# .claude/scripts/search-orchestrator.sh
#
# Search Orchestration Layer
# Routes search requests to ck or grep based on availability
#
# Usage:
#   search-orchestrator.sh <search_type> <query> [path] [top_k] [threshold]
#
# Search Types:
#   semantic  - Find code by meaning using embeddings
#   hybrid    - Combined semantic + keyword (RRF)
#   regex     - Traditional grep-style patterns

set -euo pipefail

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

# Pre-flight check (mandatory)
if [[ -f "${PROJECT_ROOT}/.claude/scripts/preflight.sh" ]]; then
    "${PROJECT_ROOT}/.claude/scripts/preflight.sh" || exit 1
fi

# Parse arguments.
# NOTE: use ${2:-} (with default fallback) rather than ${2} — under
# `set -u` above, accessing $2 when only one arg was passed crashes with
# "unbound variable" BEFORE the required-arg check below can produce the
# user-friendly "Error: Query is required" message. With the default
# fallback, $2 expands to empty string and the -z check handles it
# gracefully. Same treatment below for other positional args that
# already use ${N:-DEFAULT} — only $2 was missing its fallback.
SEARCH_TYPE="${1:-semantic}"  # semantic|hybrid|regex
QUERY="${2:-}"
SEARCH_PATH="${3:-${PROJECT_ROOT}/src}"
TOP_K="${4:-20}"
THRESHOLD="${5:-0.4}"

# Validate arguments
if [[ -z "${QUERY}" ]]; then
    echo "Error: Query is required" >&2
    echo "Usage: search-orchestrator.sh <search_type> <query> [path] [top_k] [threshold]" >&2
    exit 1
fi

# SECURITY: Validate search type
case "${SEARCH_TYPE}" in
    semantic|hybrid|regex) ;;
    *)
        echo "Error: Invalid search type '${SEARCH_TYPE}'. Must be: semantic, hybrid, regex" >&2
        exit 1
        ;;
esac

# SECURITY: Validate numeric parameters
if ! [[ "${TOP_K}" =~ ^[0-9]+$ ]]; then
    echo "Error: top_k must be a positive integer" >&2
    exit 1
fi
if ! [[ "${THRESHOLD}" =~ ^[0-9]*\.?[0-9]+$ ]]; then
    echo "Error: threshold must be a number (e.g., 0.4)" >&2
    exit 1
fi

# Validate regex syntax for regex search type.
# grep exit codes: 0 = match, 1 = no match (regex valid), >=2 = error (bad
# regex). The previous check used `! grep -E "$QUERY" ...` on empty input,
# which treated "no match in empty string" as failure — rejecting every
# valid regex that doesn't match "". We only want to reject SYNTAX errors.
#
# NOTE: this is NOT ReDoS prevention (the prior comment incorrectly claimed
# that). Syntactically valid regexes can still be catastrophic-backtracking
# patterns like `(a+)+$`. Real ReDoS mitigation would require a timeout
# wrapper or pattern-complexity analysis; tracked as follow-up.
if [[ "${SEARCH_TYPE}" == "regex" ]]; then
    regex_check_exit=0
    echo "" | grep -E "${QUERY}" >/dev/null 2>&1 || regex_check_exit=$?
    if [[ "${regex_check_exit}" -ge 2 ]]; then
        echo "Error: Invalid regex pattern" >&2
        exit 1
    fi
fi

# Normalize path to absolute
if [[ ! "${SEARCH_PATH}" =~ ^/ ]]; then
    SEARCH_PATH="${PROJECT_ROOT}/${SEARCH_PATH}"
fi

# SECURITY: Validate path is within project root (prevent path traversal)
REAL_SEARCH_PATH=$(realpath -m "${SEARCH_PATH}" 2>/dev/null || echo "${SEARCH_PATH}")
REAL_PROJECT_ROOT=$(realpath -m "${PROJECT_ROOT}" 2>/dev/null || echo "${PROJECT_ROOT}")
if [[ ! "${REAL_SEARCH_PATH}" =~ ^"${REAL_PROJECT_ROOT}" ]]; then
    echo "Error: Search path must be within project root" >&2
    exit 1
fi

# Detect search mode (cached in session)
if [[ -z "${LOA_SEARCH_MODE:-}" ]]; then
    if command -v ck >/dev/null 2>&1; then
        export LOA_SEARCH_MODE="ck"
    else
        export LOA_SEARCH_MODE="grep"
    fi
fi

# Trajectory log entry (intent phase)
TRAJECTORY_DIR="${PROJECT_ROOT}/grimoires/loa/a2a/trajectory"
TRAJECTORY_FILE="${TRAJECTORY_DIR}/$(date +%Y-%m-%d).jsonl"
mkdir -p "${TRAJECTORY_DIR}"

# Log intent BEFORE search
jq -cn \
    --arg ts "$(date -Iseconds)" \
    --arg agent "${LOA_AGENT_NAME:-unknown}" \
    --arg phase "intent" \
    --arg search_type "${SEARCH_TYPE}" \
    --arg query "${QUERY}" \
    --arg path "${SEARCH_PATH}" \
    --arg mode "${LOA_SEARCH_MODE}" \
    --argjson top_k "${TOP_K}" \
    --argjson threshold "${THRESHOLD}" \
    '{ts: $ts, agent: $agent, phase: $phase, search_type: $search_type, query: $query, path: $path, mode: $mode, top_k: $top_k, threshold: $threshold}' \
    >> "${TRAJECTORY_FILE}"

# Execute search based on mode
if [[ "${LOA_SEARCH_MODE}" == "ck" ]]; then
    # Semantic search using ck (v0.7.0+ syntax)
    # Note: ck uses positional path argument, --limit (not --top-k), --threshold
    case "${SEARCH_TYPE}" in
        semantic)
            SEARCH_RESULTS=$(ck --sem "${QUERY}" \
                --limit "${TOP_K}" \
                --threshold "${THRESHOLD}" \
                --jsonl \
                "${SEARCH_PATH}" 2>/dev/null || echo "")
            RESULT_COUNT=$(printf '%s' "${SEARCH_RESULTS}" | awk '/^{/{c++} END{print c+0}')
            RESULT_COUNT="${RESULT_COUNT:-0}"
            echo "${SEARCH_RESULTS}"
            ;;
        hybrid)
            SEARCH_RESULTS=$(ck --hybrid "${QUERY}" \
                --limit "${TOP_K}" \
                --threshold "${THRESHOLD}" \
                --jsonl \
                "${SEARCH_PATH}" 2>/dev/null || echo "")
            RESULT_COUNT=$(printf '%s' "${SEARCH_RESULTS}" | awk '/^{/{c++} END{print c+0}')
            RESULT_COUNT="${RESULT_COUNT:-0}"
            echo "${SEARCH_RESULTS}"
            ;;
        regex)
            SEARCH_RESULTS=$(ck --regex "${QUERY}" \
                --jsonl \
                "${SEARCH_PATH}" 2>/dev/null || echo "")
            RESULT_COUNT=$(printf '%s' "${SEARCH_RESULTS}" | awk '/^{/{c++} END{print c+0}')
            RESULT_COUNT="${RESULT_COUNT:-0}"
            echo "${SEARCH_RESULTS}"
            ;;
        *)
            echo "Error: Unknown search type: ${SEARCH_TYPE}" >&2
            echo "Valid types: semantic, hybrid, regex" >&2
            exit 1
            ;;
    esac
else
    # Grep fallback — emits JSONL with {file, line, snippet} fields so the
    # output schema matches ck mode and the downstream jq consumers.
    # Previously emitted raw `file:line:content` which broke JSONL parsing.
    _emit_grep_jsonl() {
        # Converts `file:line:content` stream on stdin to JSONL on stdout.
        # Uses jq --arg for safe interpolation (no injection via filename/content).
        # `read || [[ -n "$raw" ]]` processes the final line even when command
        # substitution strips the trailing newline. `raw=""` init keeps the
        # guard safe under `set -u` on empty input.
        local raw=""
        while IFS= read -r raw || [[ -n "$raw" ]]; do
            [[ -z "$raw" ]] && continue
            local file line snippet
            file="${raw%%:*}"
            local rest="${raw#*:}"
            line="${rest%%:*}"
            snippet="${rest#*:}"
            [[ -z "$file" || -z "$line" ]] && continue
            jq -cn \
                --arg f "$file" \
                --argjson l "${line}" \
                --arg s "$snippet" \
                '{file: $f, line: $l, snippet: $s}' 2>/dev/null || true
        done
    }

    case "${SEARCH_TYPE}" in
        semantic|hybrid)
            # Convert semantic query to keyword patterns
            # Extract words, OR them together
            KEYWORDS=$(echo "${QUERY}" | tr '[:space:]' '\n' | grep -v '^$' | sort -u | paste -sd '|' -)

            if [[ -n "${KEYWORDS}" ]]; then
                RAW_RESULTS=$(grep -rn -E "${KEYWORDS}" \
                    --include="*.js" --include="*.ts" --include="*.py" --include="*.go" \
                    --include="*.rs" --include="*.java" --include="*.cpp" --include="*.c" \
                    --include="*.sh" --include="*.bash" --include="*.md" --include="*.yaml" \
                    --include="*.yml" --include="*.json" --include="*.toml" \
                    "${SEARCH_PATH}" 2>/dev/null | head -n "${TOP_K}" || echo "")
                SEARCH_RESULTS=$(printf '%s' "${RAW_RESULTS}" | _emit_grep_jsonl)
                RESULT_COUNT=$(printf '%s' "${SEARCH_RESULTS}" | awk 'NF{c++} END{print c+0}')
                echo "${SEARCH_RESULTS}"
            else
                echo "" # Empty query
                RESULT_COUNT=0
            fi
            ;;
        regex)
            RAW_RESULTS=$(grep -rn -E "${QUERY}" \
                --include="*.js" --include="*.ts" --include="*.py" --include="*.go" \
                --include="*.rs" --include="*.java" --include="*.cpp" --include="*.c" \
                --include="*.sh" --include="*.bash" --include="*.md" --include="*.yaml" \
                --include="*.yml" --include="*.json" --include="*.toml" \
                "${SEARCH_PATH}" 2>/dev/null | head -n "${TOP_K}" || echo "")
            SEARCH_RESULTS=$(printf '%s' "${RAW_RESULTS}" | _emit_grep_jsonl)
            RESULT_COUNT=$(printf '%s' "${SEARCH_RESULTS}" | awk 'NF{c++} END{print c+0}')
            echo "${SEARCH_RESULTS}"
            ;;
        *)
            echo "Error: Unknown search type: ${SEARCH_TYPE}" >&2
            echo "Valid types: semantic, hybrid, regex" >&2
            exit 1
            ;;
    esac
fi

# Log execution result
jq -cn \
    --arg ts "$(date -Iseconds)" \
    --arg agent "${LOA_AGENT_NAME:-unknown}" \
    --arg phase "execute" \
    --argjson result_count "${RESULT_COUNT}" \
    --arg mode "${LOA_SEARCH_MODE}" \
    '{ts: $ts, agent: $agent, phase: $phase, result_count: $result_count, mode: $mode}' \
    >> "${TRAJECTORY_FILE}"

exit 0
