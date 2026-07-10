#!/usr/bin/env bash
# =============================================================================
# verdict-derive.sh — Derive & validate the LOA-VERDICT machine trailer (C7)
# =============================================================================
# Part of cycle-119 "mechanical floor" (structured-first gate consumption).
#
# Validates a reviewing-code/auditing-security feedback file's LOA-VERDICT
# trailer (C6: `<!-- LOA-VERDICT {json} -->` as the LAST LINE of the file):
#   1. trailer present, parses as JSON, is the last line
#   2. prose<->trailer agreement (review: first line "All good" iff APPROVED;
#      audit: exact ritual string "APPROVED - LET'S FUCKING GO" iff APPROVED)
#   3. one-way severity rule: counts.critical + counts.high > 0 => verdict
#      MUST be CHANGES_REQUIRED (zero does NOT force APPROVED)
#   4. an APPROVED review file carries no '## Changes Required' / 'Findings'
#      / 'Issues' heading
#
# Usage:
#   verdict-derive.sh --file <feedback.md> --gate review|audit [--json] [--require-trailer]
#
# Exit codes:
#   0 = trailer present and consistent
#   1 = trailer present but a violation was found (repair text on stderr),
#       OR a usage error, OR trailer missing with --require-trailer
#   2 = no trailer found (legacy file) — success unless --require-trailer
# =============================================================================

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"

JSON_OUTPUT=false
REQUIRE_TRAILER=false
FILE=""
GATE=""

show_help() {
    cat <<EOF
Usage: $SCRIPT_NAME --file <feedback.md> --gate review|audit [--json] [--require-trailer]

Derive and validate the LOA-VERDICT machine trailer (C6) on a review/audit
feedback file.

Options:
  --file PATH         Feedback file to check (required)
  --gate review|audit Which gate this file belongs to (required)
  --json              Emit a JSON result object to stdout
  --require-trailer   Treat a missing trailer as a violation (exit 1) instead
                       of the default legacy-file pass (exit 2)
  -h, --help          Show this help message

Exit codes:
  0  trailer present and consistent
  1  trailer present but inconsistent (repair text on stderr), a usage
     error, or a missing trailer with --require-trailer set
  2  no trailer found (legacy file — pass unless --require-trailer)
EOF
}

is_num() { [[ "$1" =~ ^[0-9]+$ ]]; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --file) FILE="${2:-}"; shift 2 ;;
        --gate) GATE="${2:-}"; shift 2 ;;
        --json) JSON_OUTPUT=true; shift ;;
        --require-trailer) REQUIRE_TRAILER=true; shift ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "Unknown option: $1" >&2; show_help >&2; exit 2 ;;
    esac
done

if [[ -z "$FILE" || -z "$GATE" ]]; then
    echo "Error: --file and --gate are required" >&2
    show_help >&2
    exit 2
fi

if [[ "$GATE" != "review" && "$GATE" != "audit" ]]; then
    echo "Error: --gate must be 'review' or 'audit' (got: $GATE)" >&2
    exit 2
fi

if [[ ! -f "$FILE" ]]; then
    echo "Error: file not found: $FILE" >&2
    exit 2
fi

violations=()
t_verdict=""
counts_json="null"

# Emit the JSON result object (only used when --json is set).
emit_json() {
    local exit_code="$1" trailer_found="$2" consistent="$3"
    local viol_json="[]"
    local v
    for v in ${violations[@]+"${violations[@]}"}; do
        viol_json=$(echo "$viol_json" | jq --arg v "$v" '. + [$v]')
    done
    local verdict_arg="$t_verdict"
    jq -n \
        --arg file "$FILE" \
        --arg gate "$GATE" \
        --argjson trailer_found "$trailer_found" \
        --arg verdict "$verdict_arg" \
        --argjson counts "$counts_json" \
        --argjson consistent "$consistent" \
        --argjson violations "$viol_json" \
        --argjson exit_code "$exit_code" \
        '{file: $file, gate: $gate, trailer_found: $trailer_found,
          verdict: (if $verdict == "" then null else $verdict end),
          counts: $counts, consistent: $consistent,
          violations: $violations, exit_code: $exit_code}'
}

emit_plain() {
    local trailer_found="$1" consistent="$2"
    if [[ "$trailer_found" == "false" ]]; then
        echo "NO_TRAILER: legacy file, no LOA-VERDICT trailer found: $FILE"
    elif [[ "$consistent" == "true" ]]; then
        echo "CONSISTENT: gate=$GATE verdict=$t_verdict"
    else
        echo "INCONSISTENT: gate=$GATE verdict=${t_verdict:-unknown}"
    fi
}

trailer_count=$(grep -c '<!-- LOA-VERDICT ' -- "$FILE" 2>/dev/null || true)
[[ -z "$trailer_count" ]] && trailer_count=0

# --- No trailer at all: legacy file ---
if [[ "$trailer_count" -eq 0 ]]; then
    if [[ "$REQUIRE_TRAILER" == "true" ]]; then
        violations+=("no LOA-VERDICT trailer found but --require-trailer was set — add one as the last line: <!-- LOA-VERDICT {\"gate\":\"$GATE\",\"verdict\":\"APPROVED\",\"counts\":{\"critical\":0,\"high\":0,\"medium\":0,\"low\":0},\"sprint_id\":\"sprint-N\",\"ts\":\"<ISO8601>\"} -->")
        for v in "${violations[@]}"; do echo "$v" >&2; done
        [[ "$JSON_OUTPUT" == "true" ]] && emit_json 1 false false
        exit 1
    fi
    [[ "$JSON_OUTPUT" == "true" ]] && emit_json 2 false true
    [[ "$JSON_OUTPUT" == "false" ]] && emit_plain false true
    exit 2
fi

last_line=$(tail -n 1 -- "$FILE")
# R2 review (cycle-119): tolerate CRLF files — strip one trailing \r before
# every exact-string comparison below (first/last/trailer lines).
last_line="${last_line%$'\r'}"

if [[ "$trailer_count" -gt 1 ]]; then
    violations+=("multiple LOA-VERDICT trailers found ($trailer_count) — keep exactly one trailer, as the last line of the file")
else
    trailer_line=$(grep '<!-- LOA-VERDICT ' -- "$FILE" | head -1)
    trailer_line="${trailer_line%$'\r'}"
    if [[ "$trailer_line" != "$last_line" ]]; then
        violations+=("LOA-VERDICT trailer is not the last line of the file — move it to be the final line with nothing after it")
    fi

    json_payload=$(printf '%s' "$trailer_line" | sed -E 's/^<!-- LOA-VERDICT (.*) -->[[:space:]]*$/\1/')
    if ! printf '%s' "$json_payload" | jq empty >/dev/null 2>&1; then
        violations+=("LOA-VERDICT trailer content is not valid JSON — fix trailer syntax (must be a single JSON object)")
    else
        t_gate=$(printf '%s' "$json_payload" | jq -r '.gate // empty')
        t_verdict=$(printf '%s' "$json_payload" | jq -r '.verdict // empty')
        t_critical=$(printf '%s' "$json_payload" | jq -r '.counts.critical // empty')
        t_high=$(printf '%s' "$json_payload" | jq -r '.counts.high // empty')
        t_medium=$(printf '%s' "$json_payload" | jq -r '.counts.medium // empty')
        t_low=$(printf '%s' "$json_payload" | jq -r '.counts.low // empty')
        counts_json=$(printf '%s' "$json_payload" | jq -c '.counts // null')

        if [[ "$t_gate" != "review" && "$t_gate" != "audit" ]]; then
            violations+=("trailer gate '$t_gate' is not one of review|audit")
        elif [[ "$t_gate" != "$GATE" ]]; then
            violations+=("trailer gate '$t_gate' does not match requested --gate '$GATE'")
        fi

        if [[ "$t_verdict" != "APPROVED" && "$t_verdict" != "CHANGES_REQUIRED" ]]; then
            violations+=("trailer verdict '$t_verdict' is not one of APPROVED|CHANGES_REQUIRED")
        fi

        if ! is_num "$t_critical" || ! is_num "$t_high" || ! is_num "$t_medium" || ! is_num "$t_low"; then
            violations+=("trailer counts.critical/high/medium/low missing or non-numeric — trailer must include integer counts for all four severities")
        else
            severity_sum=$((t_critical + t_high))
            if (( severity_sum > 0 )) && [[ "$t_verdict" != "CHANGES_REQUIRED" ]]; then
                violations+=("trailer says $t_verdict but counts.critical=$t_critical counts.high=$t_high (sum>0) — set verdict CHANGES_REQUIRED or re-triage the HIGH/CRITICAL findings")
            fi
        fi

        first_line=$(head -n 1 -- "$FILE")
        first_line="${first_line%$'\r'}"
        if [[ "$GATE" == "review" ]]; then
            if [[ "$t_verdict" == "APPROVED" && "$first_line" != "All good" ]]; then
                violations+=("trailer says APPROVED but first line is not exactly 'All good' — set the first line to 'All good' or change verdict to CHANGES_REQUIRED")
            fi
            if [[ "$t_verdict" == "CHANGES_REQUIRED" && "$first_line" == "All good" ]]; then
                violations+=("first line is 'All good' but trailer verdict is CHANGES_REQUIRED — remove 'All good' as the first line or change verdict to APPROVED")
            fi
            if [[ "$t_verdict" == "APPROVED" ]] && grep -qE '^## (Changes Required|Findings|Issues)' -- "$FILE" 2>/dev/null; then
                violations+=("trailer says APPROVED but file contains a '## Changes Required'/'## Findings'/'## Issues' heading — remove the heading or change verdict to CHANGES_REQUIRED")
            fi
        else
            ritual="APPROVED - LET'S FUCKING GO"
            if [[ "$t_verdict" == "APPROVED" ]] && ! grep -qF "$ritual" -- "$FILE" 2>/dev/null; then
                violations+=("trailer says APPROVED but prose is missing the exact string \"$ritual\" — add it or change verdict to CHANGES_REQUIRED")
            fi
            if [[ "$t_verdict" == "CHANGES_REQUIRED" ]] && grep -qF "$ritual" -- "$FILE" 2>/dev/null; then
                violations+=("prose contains \"$ritual\" but trailer verdict is CHANGES_REQUIRED — remove it or change verdict to APPROVED")
            fi
        fi
    fi
fi

consistent=true
if [[ ${#violations[@]} -gt 0 ]]; then
    consistent=false
fi

for v in ${violations[@]+"${violations[@]}"}; do
    echo "$v" >&2
done

if [[ "$consistent" == "true" ]]; then
    [[ "$JSON_OUTPUT" == "true" ]] && emit_json 0 true true
    [[ "$JSON_OUTPUT" == "false" ]] && emit_plain true true
    exit 0
else
    [[ "$JSON_OUTPUT" == "true" ]] && emit_json 1 true false
    [[ "$JSON_OUTPUT" == "false" ]] && emit_plain true false
    exit 1
fi
