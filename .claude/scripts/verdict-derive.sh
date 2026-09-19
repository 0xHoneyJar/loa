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
#   5. FR-9 coverage-first (additive): `excluded` counts the HIGH findings
#      demoted to '## Observations' as speculative + confidence: low; critical
#      is never excludable; an audit's `excluded_confirmed` must match the
#      review's `excluded` (--review-file)
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
REVIEW_FILE=""

show_help() {
    cat <<EOF
Usage: $SCRIPT_NAME --file <feedback.md> --gate review|audit [--json] [--require-trailer]
       [--review-file <engineer-feedback.md>]

Derive and validate the LOA-VERDICT machine trailer (C6) on a review/audit
feedback file.

Options:
  --file PATH         Feedback file to check (required)
  --gate review|audit Which gate this file belongs to (required)
  --json              Emit a JSON result object to stdout
  --require-trailer   Treat a missing trailer as a violation (exit 1) instead
                       of the default legacy-file pass (exit 2)
  --review-file PATH  Audit gate only: cross-check the audit trailer's
                       excluded_confirmed against the review trailer's excluded
  -h, --help          Show this help message

Coverage-first rule (FR-9, additive): the trailer may carry "excluded": N —
the number of HIGH findings the reviewer demoted to "## Observations" because
they are tagged speculative with confidence: low. critical is never excludable;
a HIGH under ## Observations needs both markers; N must equal what the section
holds. An audit trailer carries "excluded_confirmed": N and must match.

Exit codes:
  0  trailer present and consistent
  1  trailer present but inconsistent (repair text on stderr), a usage
     error, or a missing trailer with --require-trailer set
  2  no trailer found (legacy file — pass unless --require-trailer)
EOF
}

# ≤ 6 digits: bash arithmetic wraps at 2^64, so an absurd count like
# 18446744073709551616 would sum to 0 and read as consistent (audit, slice C).
is_num() { [[ "$1" =~ ^[0-9]{1,6}$ ]]; }
# Detection is loose (tab/NBSP/U+2010 variants are still "a trailer"); the
# canonical form is enforced below — a malformed marker is a violation, never a
# silent fall-through to the legacy prose heuristic.
TRAILER_DETECT='<!--[^A-Za-z0-9]{0,4}LOA[^A-Za-z0-9]{0,4}VERDICT'
TRAILER_CANON='^<!-- LOA-VERDICT \{.*\} -->$'

while [[ $# -gt 0 ]]; do
    case "$1" in
        --file) FILE="${2:-}"; shift 2 ;;
        --gate) GATE="${2:-}"; shift 2 ;;
        --json) JSON_OUTPUT=true; shift ;;
        --require-trailer) REQUIRE_TRAILER=true; shift ;;
        --review-file) REVIEW_FILE="${2:-}"; shift 2 ;;
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

if [[ -n "$REVIEW_FILE" ]]; then
    if [[ "$GATE" != "audit" ]]; then
        echo "Error: --review-file applies to --gate audit only" >&2
        exit 2
    fi
    if [[ ! -f "$REVIEW_FILE" ]]; then
        echo "Error: review file not found: $REVIEW_FILE" >&2
        exit 2
    fi
fi

violations=()
warnings=()
t_verdict=""
counts_json="null"
t_excluded=0
t_excluded_confirmed=0

# FR-9: scan the "## Observations" section (from that heading to the next
# "## " heading) for finding entries — a list item, table row or bold-led line
# whose first line carries an uppercase severity word (CRITICAL/HIGH/MEDIUM/LOW)
# or `severity: <level>`. Prints three integers: critical entries, HIGH entries
# carrying both `speculative` and `confidence: low`, HIGH entries missing one.
observations_scan() {
    awk '
        /^## / { in_obs = ($0 ~ /^## Observations/) ; next }
        in_obs && ($0 ~ /^[[:space:]]*([-*+]|[0-9]+\.)[[:space:]]/ || $0 ~ /^\|/ || $0 ~ /^\*\*/) {
            lc = tolower($0)
            crit = ($0 ~ /(^|[^A-Za-z])CRITICAL([^A-Za-z]|$)/ || lc ~ /severity:[[:space:]]*critical/)
            high = ($0 ~ /(^|[^A-Za-z])HIGH([^A-Za-z]|$)/ || lc ~ /severity:[[:space:]]*high/)
            if (crit) { c++ }
            else if (high) {
                if (lc ~ /speculative/ && lc ~ /confidence:[[:space:]]*low/) ok++; else bad++
            }
        }
        END { printf "%d %d %d\n", c + 0, ok + 0, bad + 0 }
    ' "$1"
}

# FR-9: an integer field from a trailer JSON payload — "0" when absent,
# "invalid" when present but not a 0..999999 integer.
trailer_int() {
    local payload="$1" field="$2" v
    v=$(printf '%s' "$payload" | jq -r --arg f "$field" \
        'if has($f) then (if (.[$f]|type)=="number" and (.[$f]|floor)==.[$f] and .[$f] >= 0 and ((.[$f]|tostring|length) <= 6) then (.[$f]|tostring) else "invalid" end) else "0" end' 2>/dev/null) || v="invalid"
    printf '%s' "$v"
}

# Emit the JSON result object (only used when --json is set).
emit_json() {
    local exit_code="$1" trailer_found="$2" consistent="$3"
    local viol_json="[]"
    local v
    for v in ${violations[@]+"${violations[@]}"}; do
        viol_json=$(echo "$viol_json" | jq --arg v "$v" '. + [$v]')
    done
    local warn_json="[]"
    for v in ${warnings[@]+"${warnings[@]}"}; do
        warn_json=$(echo "$warn_json" | jq --arg v "$v" '. + [$v]')
    done
    local verdict_arg="$t_verdict"
    jq -n \
        --arg file "$FILE" \
        --arg gate "$GATE" \
        --argjson trailer_found "$trailer_found" \
        --arg verdict "$verdict_arg" \
        --argjson counts "$counts_json" \
        --argjson excluded "$t_excluded" \
        --argjson excluded_confirmed "$t_excluded_confirmed" \
        --argjson consistent "$consistent" \
        --argjson violations "$viol_json" \
        --argjson warnings "$warn_json" \
        --argjson exit_code "$exit_code" \
        '{file: $file, gate: $gate, trailer_found: $trailer_found,
          verdict: (if $verdict == "" then null else $verdict end),
          counts: $counts, excluded: $excluded, excluded_confirmed: $excluded_confirmed,
          consistent: $consistent, violations: $violations, warnings: $warnings,
          exit_code: $exit_code}'
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

trailer_count=$(grep -cE "$TRAILER_DETECT" -- "$FILE" 2>/dev/null || true)
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
    trailer_line=$(grep -E "$TRAILER_DETECT" -- "$FILE" | head -1)
    trailer_line="${trailer_line%$'\r'}"
    if [[ ! "$trailer_line" =~ $TRAILER_CANON ]]; then
        violations+=("LOA-VERDICT marker is malformed — the exact form is '<!-- LOA-VERDICT {json} -->' (single ASCII spaces, ASCII hyphen)")
    fi
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

        # --- FR-9 coverage-first: excluded / Observations / excluded_confirmed ---
        ex_val=$(trailer_int "$json_payload" excluded)
        if [[ "$ex_val" == "invalid" ]]; then
            violations+=("trailer excluded must be a non-negative integer of at most six digits — it counts the HIGH findings demoted to ## Observations as speculative with confidence: low")
        else
            t_excluded=$ex_val
        fi
        exc_val=$(trailer_int "$json_payload" excluded_confirmed)
        if [[ "$exc_val" == "invalid" ]]; then
            violations+=("trailer excluded_confirmed must be a non-negative integer of at most six digits")
        else
            t_excluded_confirmed=$exc_val
        fi
        read -r obs_crit obs_ok obs_bad < <(observations_scan "$FILE")
        if (( obs_crit > 0 )); then
            violations+=("$obs_crit critical finding(s) under ## Observations — critical is never excludable; move them under ## Changes Required and count them")
        fi
        if (( obs_bad > 0 )); then
            violations+=("$obs_bad HIGH finding(s) under ## Observations without both 'speculative' and 'confidence: low' — confidence never demotes; move them under ## Changes Required and count them, or mark them speculative with confidence: low and record them under excluded")
        fi
        if [[ "$ex_val" != "invalid" ]] && (( obs_ok != t_excluded )); then
            violations+=("trailer excluded=$t_excluded but ## Observations holds $obs_ok speculative low-confidence HIGH finding(s) — the two must match so every demotion is visible")
        fi
        if [[ "$t_verdict" == "APPROVED" ]] && (( t_excluded > 0 )); then
            warnings+=("WARN: APPROVED with excluded=$t_excluded speculative low-confidence HIGH finding(s) demoted — the audit gate must confirm each one (excluded_confirmed)")
        fi
        if [[ "$GATE" == "audit" && -n "$REVIEW_FILE" ]]; then
            rev_line=$(grep -E "$TRAILER_DETECT" -- "$REVIEW_FILE" 2>/dev/null | tail -1)
            rev_line="${rev_line%$'\r'}"
            rev_payload=$(printf '%s' "$rev_line" | sed -E 's/^<!--[^A-Za-z0-9]{0,4}LOA[^A-Za-z0-9]{0,4}VERDICT[[:space:]]*//; s/[[:space:]]*-->[[:space:]]*$//')
            rev_ex="0"
            if [[ -n "$rev_payload" ]] && printf '%s' "$rev_payload" | jq empty >/dev/null 2>&1; then
                rev_ex=$(trailer_int "$rev_payload" excluded)
            fi
            if [[ "$rev_ex" == "invalid" ]]; then
                violations+=("review trailer in $REVIEW_FILE carries a non-integer excluded field")
            elif (( rev_ex != t_excluded_confirmed )); then
                violations+=("audit trailer excluded_confirmed=$t_excluded_confirmed but the review trailer says excluded=$rev_ex — confirm each demoted high independently and record the count")
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
for v in ${warnings[@]+"${warnings[@]}"}; do
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
