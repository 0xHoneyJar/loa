#!/usr/bin/env bash
# =============================================================================
# bridge-mediums-summary.sh — MEDIUM-finding visibility for post-PR Bridgebuilder
# =============================================================================
# Issue #665. The post-PR Bridgebuilder triage auto-routes MEDIUM findings to
# `log_only` in autonomous mode. The kaironic convergence calculus only looks
# at HIGH/BLOCKER counts, so MEDIUMs never enter the convergence picture and
# are silently sunk into the trajectory log. Iron-grip discipline framing is
# undermined when MEDIUMs are invisible to operators.
#
# This lib provides a non-invasive visibility surface: tally MEDIUMs and
# emit a structured WARN line + a JSON summary file for downstream HITL
# consumers. Convergence semantics and log_only routing are NOT changed.
#
# Usage:
#   source bridge-mediums-summary.sh
#   tally_mediums "<trajectory_dir>"  # echoes "<count>:<latest_file>"
#   emit_mediums_warning "<count>" "<latest_file>" "<summary_path>"
# =============================================================================

# tally_mediums — count MEDIUM-severity findings auto-routed to log_only
# Args:
#   $1 — trajectory directory containing bridge-triage-*.jsonl files
# Output:
#   "<count>:<latest_trajectory_file>" — count is 0 when no findings exist;
#   latest_trajectory_file is empty when no matching files are present.
tally_mediums() {
    local traj_dir="${1:-}"
    local count=0
    local latest_file=""

    if [[ -z "$traj_dir" || ! -d "$traj_dir" ]]; then
        echo "0:"
        return 0
    fi

    # Find latest bridge-triage-*.jsonl file (by mtime)
    local f
    for f in "$traj_dir"/bridge-triage-*.jsonl; do
        [[ -f "$f" ]] || continue
        if [[ -z "$latest_file" || "$f" -nt "$latest_file" ]]; then
            latest_file="$f"
        fi
    done

    if [[ -z "$latest_file" ]]; then
        echo "0:"
        return 0
    fi

    # Tally MEDIUM-severity findings with log_only action.
    # We only count log_only MEDIUMs (not dispatch_bug ones), per the issue:
    # those are the ones that disappear from operator visibility.
    count=$(awk '
        /"severity":"MEDIUM"/ && /"action":"log_only"/ { c++ }
        END { print c+0 }
    ' "$latest_file" 2>/dev/null || echo "0")

    echo "${count}:${latest_file}"
    return 0
}

# emit_mediums_warning — emit operator-visible WARN line + structured summary
# Args:
#   $1 — count of MEDIUM findings
#   $2 — trajectory file path
#   $3 — output path for structured JSON summary (e.g., .run/post-pr-mediums-summary.json)
# Output:
#   - Writes WARN line to stderr if count > 0 (zero-count is silent)
#   - Writes structured JSON to $3 (always — even when count is 0, for downstream consumers)
emit_mediums_warning() {
    local count="${1:-0}"
    local traj_file="${2:-}"
    local summary_path="${3:-}"

    if [[ -z "$summary_path" ]]; then
        echo "[bridge-mediums-summary] ERROR: summary_path required" >&2
        return 1
    fi

    # Always write the structured summary, even on zero count.
    # Use jq for finding_id extraction (trajectory files are JSONL — one
    # finding per line, schema-stable per bridge-triage.schema.json).
    mkdir -p "$(dirname "$summary_path")"
    local finding_ids="[]"
    if [[ "$count" -gt 0 && -f "$traj_file" ]]; then
        finding_ids=$(jq -sr '
            [.[] | select(.severity == "MEDIUM" and .action == "log_only") | .finding_id // empty]
        ' "$traj_file" 2>/dev/null || echo "[]")
    fi

    # Validate JSON shape; default to [] if invalid
    if ! echo "$finding_ids" | jq empty 2>/dev/null; then
        finding_ids="[]"
    fi

    jq -n \
        --argjson count "$count" \
        --arg trajectory "$traj_file" \
        --argjson finding_ids "$finding_ids" \
        --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        '{timestamp: $ts, count: $count, trajectory_path: $trajectory, finding_ids: $finding_ids}' \
        > "$summary_path"

    # Emit operator-visible WARN line only when there are MEDIUMs
    if [[ "$count" -gt 0 ]]; then
        echo "[WARN] ${count} MEDIUM findings logged (trajectory=${traj_file}); see ${summary_path} for finding IDs" >&2
        return 0
    fi

    return 0
}

# Allow direct invocation for shell-script integration
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    cmd="${1:-}"
    shift || true
    case "$cmd" in
        tally) tally_mediums "$@" ;;
        emit)  emit_mediums_warning "$@" ;;
        *)
            echo "Usage: bridge-mediums-summary.sh tally <trajectory_dir>" >&2
            echo "       bridge-mediums-summary.sh emit <count> <traj_file> <summary_path>" >&2
            exit 2 ;;
    esac
fi
