#!/usr/bin/env bash
# =============================================================================
# bridge-triage-stats.sh — aggregate bridge-triage JSONL logs into signal
# =============================================================================
# Reads grimoires/loa/a2a/trajectory/bridge-triage-*.jsonl, produces either
# markdown tables (default) or JSON (--json). Aggregates per-PR severity
# mix, global action distribution, FP proxy.
#
# Usage:
#   bridge-triage-stats.sh [GLOB]
#     --json                   Emit JSON summary instead of markdown
#     --pr N                   Restrict to PR number N
#     --since YYYY-MM-DD       Restrict to timestamps on/after this date
#     --comment-issue N        Post markdown output as a comment on issue N
#     --help                   Show this usage text and exit
#
# Default GLOB: grimoires/loa/a2a/trajectory/bridge-triage-*.jsonl
#
# Exit codes:
#   0  Success (including zero-files case with stderr warning)
#   1  Runtime error (jq/gh failure)
#   2  Usage error (unknown flag, invalid --pr / --since)
#
# Cycle: cycle-059 (closes #467 Option B/D decision-gate tooling prerequisite)
# =============================================================================

set -euo pipefail

# Enable nullglob so a zero-match glob expands to nothing (not the literal pattern)
shopt -s nullglob

DEFAULT_GLOB="grimoires/loa/a2a/trajectory/bridge-triage-*.jsonl"

# =============================================================================
# CLI parsing
# =============================================================================

output_format="text"
pr_filter=""
since_filter=""
comment_issue=""
# Respect GH_BIN override for testability; default to real `gh` on PATH.
GH_BIN="${GH_BIN:-gh}"

usage() {
    sed -n '3,22p' "$0" | sed 's/^# \?//'
    exit "${1:-0}"
}

positional=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --json)
            output_format="json"
            shift
            ;;
        --pr)
            if [[ -z "${2:-}" ]]; then
                echo "ERROR: --pr requires a value" >&2
                exit 2
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                echo "ERROR: --pr must be a positive integer, got: $2" >&2
                exit 2
            fi
            pr_filter="$2"
            shift 2
            ;;
        --since)
            if [[ -z "${2:-}" ]]; then
                echo "ERROR: --since requires a value" >&2
                exit 2
            fi
            if ! [[ "$2" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
                echo "ERROR: --since must be YYYY-MM-DD, got: $2" >&2
                exit 2
            fi
            since_filter="$2"
            shift 2
            ;;
        --comment-issue)
            if [[ -z "${2:-}" ]]; then
                echo "ERROR: --comment-issue requires a value" >&2
                exit 2
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                echo "ERROR: --comment-issue must be a positive integer, got: $2" >&2
                exit 2
            fi
            comment_issue="$2"
            shift 2
            ;;
        --help|-h)
            usage 0
            ;;
        -*)
            echo "ERROR: Unknown flag: $1" >&2
            usage 2
            ;;
        *)
            positional="$1"
            shift
            ;;
    esac
done

glob="${positional:-$DEFAULT_GLOB}"

# =============================================================================
# File resolution
# =============================================================================

# shellcheck disable=SC2206  # intentional word-splitting for glob expansion
files=( $glob )
if [[ ${#files[@]} -eq 0 ]]; then
    echo "WARNING: no trajectory files matched: $glob" >&2
    if [[ "$output_format" == "json" ]]; then
        jq -n '{generated_at: now | strftime("%Y-%m-%dT%H:%M:%SZ"), input_files: [], total_decisions: 0, prs: [], severities: {}, actions: {}, fp_proxy: {disputes:0, defers:0, noise:0, total:0, rate:0}}'
    fi
    exit 0
fi

# =============================================================================
# Ingest + filter
# =============================================================================

# Ingestion strategy: the cycle-053 trajectory schema says JSONL (one JSON
# per line) but in practice files may include pretty-printed objects that
# span multiple lines. Use `jq -n 'inputs'` which is whitespace-tolerant
# and parses a stream of JSON values regardless of line boundaries.
# Malformed content makes jq exit non-zero; we swallow that and count
# how many entries parsed vs the raw byte size for a rough health metric.
# shellcheck disable=SC2016  # jq program uses single quotes intentionally
valid_stream=$(cat "${files[@]}" | jq -cn '[inputs][]' 2>/dev/null || true)
valid_lines=$(printf '%s\n' "$valid_stream" | grep -c . || true)
# Skipped-count is best-effort: it's the count of newlines that did NOT
# contribute to a parsed value. For properly-formed JSONL this is 0; for
# pretty-printed input it's the extra newlines within objects (non-zero
# but not indicative of malformed content).
total_lines=$(cat "${files[@]}" | wc -l | tr -d ' ')
skipped=$((total_lines - valid_lines))
if [[ $skipped -gt 0 ]]; then
    echo "INFO: $valid_lines entries parsed; $skipped extra newlines from pretty-printed or blank lines (not malformed)" >&2
fi

# Apply --pr and --since filters via jq. Lexical comparison on ISO-8601
# timestamps works because they sort chronologically.
filter_jq='.'
if [[ -n "$pr_filter" ]]; then
    filter_jq+=" | select(.pr_number == $pr_filter)"
fi
if [[ -n "$since_filter" ]]; then
    # Compare on the date prefix of the timestamp (safe for any ISO-8601 variant).
    filter_jq+=" | select((.timestamp // \"0000-00-00\") >= \"$since_filter\")"
fi

filtered_stream=$(printf '%s\n' "$valid_stream" | jq -c "$filter_jq" 2>/dev/null || true)
filtered_count=$(printf '%s\n' "$filtered_stream" | grep -c . || true)

# =============================================================================
# Aggregation (single jq slurp)
# =============================================================================

# The jq program below groups into the summary shape documented in
# the cycle-059 SDD §2.4. Empty stream returns an empty summary object.
summary=$(printf '%s\n' "$filtered_stream" | jq -s --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson skipped "$skipped" \
    --argjson filtered "$filtered_count" '
    . as $all |
    ($all | group_by(.pr_number)
        | map({
            pr: .[0].pr_number,
            total: length,
            severities: (group_by(.severity) | map({(.[0].severity // "UNKNOWN"): length}) | add),
            actions: (group_by(.action) | map({(.[0].action // "UNKNOWN"): length}) | add)
          })
        | sort_by(-.total)
    ) as $prs |
    ($all | group_by(.severity) | map({(.[0].severity // "UNKNOWN"): length}) | add // {}) as $sevs |
    ($all | group_by(.action) | map({(.[0].action // "UNKNOWN"): length}) | add // {}) as $acts |
    ([$all[] | select((.action // "") == "dispute")] | length) as $disputes |
    ([$all[] | select((.action // "") == "defer")]   | length) as $defers |
    ([$all[] | select((.action // "") == "noise")]   | length) as $noise |
    {
        generated_at: $generated_at,
        total_decisions: length,
        skipped_malformed_lines: $skipped,
        filtered_decisions: $filtered,
        prs: $prs,
        severities: $sevs,
        actions: $acts,
        fp_proxy: {
            disputes: $disputes,
            defers: $defers,
            noise: $noise,
            total: length,
            rate: (if length == 0 then 0 else (($disputes + $defers + $noise) / length) end)
        }
    }
')

# Attach input metadata (jq --arg can't pass arrays cleanly)
summary=$(jq --argjson files "$(printf '%s\n' "${files[@]}" | jq -R . | jq -s .)" \
    --arg pr_filter "$pr_filter" --arg since_filter "$since_filter" \
    '. + {
        input_files: $files,
        filters_applied: {
            pr: (if $pr_filter == "" then null else ($pr_filter | tonumber) end),
            since: (if $since_filter == "" then null else $since_filter end)
        }
    }' <<< "$summary")

# =============================================================================
# Output
# =============================================================================

format_markdown() {
    local js="$1"
    local total
    total=$(jq -r '.total_decisions' <<< "$js")
    local pr_count
    pr_count=$(jq -r '.prs | length' <<< "$js")

    printf '## Bridge Triage Stats\n\n'
    printf '**Generated**: %s\n' "$(jq -r '.generated_at' <<< "$js")"
    printf '**Input files**: %s\n' "$(jq -r '.input_files | length' <<< "$js")"
    printf '**Total decisions**: %s\n' "$total"
    printf '**PRs**: %s\n' "$pr_count"
    local filters_line
    filters_line=$(jq -r '.filters_applied | to_entries | map(select(.value != null)) | map("\(.key)=\(.value)") | join(", ") | if . == "" then "(none)" else . end' <<< "$js")
    printf '**Filters**: %s\n\n' "$filters_line"

    printf '### Per-PR breakdown\n\n'
    printf '| PR | Total | Severity mix | Action mix |\n'
    printf '|---:|------:|--------------|------------|\n'
    jq -r '.prs[] |
        "| \(.pr) | \(.total) | " +
        (.severities | to_entries | map("\(.key)=\(.value)") | join(", ")) + " | " +
        (.actions | to_entries | map("\(.key)=\(.value)") | join(", ")) + " |"' <<< "$js"
    printf '\n'

    printf '### Severity distribution\n\n'
    printf '| Severity | Count |\n|----------|------:|\n'
    jq -r '.severities | to_entries | sort_by(-.value) | .[] | "| \(.key) | \(.value) |"' <<< "$js"
    printf '\n'

    printf '### Action distribution\n\n'
    printf '| Action | Count |\n|--------|------:|\n'
    jq -r '.actions | to_entries | sort_by(-.value) | .[] | "| \(.key) | \(.value) |"' <<< "$js"
    printf '\n'

    printf '### False-positive proxy\n\n'
    printf '| Metric | Value |\n|--------|------:|\n'
    jq -r '.fp_proxy | "| disputes | \(.disputes) |\n| defers | \(.defers) |\n| noise | \(.noise) |\n| total | \(.total) |\n| rate | \((.rate * 10000 | round) / 100)% |"' <<< "$js"
    printf '\n'
    printf '_FP proxy = (disputes + defers + noise) / total. Not a true FP rate — captures decisions that were NOT acted on as BLOCKERs or HIGH findings._\n'
}

output=""
case "$output_format" in
    json)
        output="$summary"
        ;;
    text)
        output=$(format_markdown "$summary")
        ;;
esac

# =============================================================================
# Optional: post to GitHub issue
# =============================================================================

if [[ -n "$comment_issue" ]]; then
    # Always use markdown for issue comments, regardless of --json
    md_body=$(format_markdown "$summary")
    {
        printf '%s\n\n' "$md_body"
        printf '_Generated by `.claude/scripts/bridge-triage-stats.sh` — cycle-059, #467 Option B/D gating_\n'
    } | "$GH_BIN" issue comment "$comment_issue" --body-file - >&2 || {
        echo "ERROR: failed to post comment on issue #$comment_issue" >&2
        exit 1
    }
    # Also echo the output so stdout is non-empty for piping
fi

printf '%s\n' "$output"
