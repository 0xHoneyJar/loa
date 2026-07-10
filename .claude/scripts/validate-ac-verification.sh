#!/usr/bin/env bash
# =============================================================================
# validate-ac-verification.sh — Validate the '## AC Verification' gate (C9)
# =============================================================================
# Part of cycle-119 "mechanical floor". Companion to implementing-tasks'
# AC Verification Gate (cycle-057, Issue #475): before writing a sprint's
# COMPLETED marker, mechanically confirm the implementation report actually
# walked every acceptance criterion from sprint.md.
#
# HONEST SCOPING: this script proves an AC was NOT skipped (absent evidence)
# and that a claimed file:line reference exists in the report's text. It does
# NOT verify the evidence is truthful, that the referenced file:line actually
# contains what is claimed, or that tests pass — it prevents ABSENT evidence,
# not FABRICATED evidence. A human/reviewer still owns fabrication risk.
#
# Usage:
#   validate-ac-verification.sh --report <reviewer.md> --sprint <sprint.md> [--json] [--notes <NOTES.md>]
#
# Checks:
#   1. report has a '## AC Verification' section
#   2. every acceptance-criteria bullet in sprint.md appears verbatim inside
#      that section
#   3. every AC block whose Status is '✓ Met' carries an Evidence: line
#      matching [A-Za-z0-9_./-]+:[0-9]+ (extensionless allowed, e.g. Makefile:12)
#   4. every AC block whose Status is '⏸ [ACCEPTED-DEFERRED]' has a matching
#      mention in NOTES.md's '## Decision Log' section
#
# Exit codes: 0 = pass, 1 = fail (repair text on stderr), 2 = usage error
# =============================================================================

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"

JSON_OUTPUT=false
REPORT=""
SPRINT=""
NOTES=""

show_help() {
    cat <<EOF
Usage: $SCRIPT_NAME --report <reviewer.md> --sprint <sprint.md> [--json] [--notes <NOTES.md>]

Validate the '## AC Verification' section of an implementation report against
the acceptance criteria declared in sprint.md.

HONEST SCOPING: this prevents ABSENT evidence (a criterion nobody walked, or
a "Met" claim with no file:line), not FABRICATED evidence — it cannot verify
that a cited file:line actually proves the claim, only that a citation exists.

Options:
  --report PATH   Implementation report to validate (required)
  --sprint PATH   sprint.md to source acceptance criteria from (required)
  --notes PATH    NOTES.md to check ACCEPTED-DEFERRED entries against
                  (default: <report>/../../../NOTES.md, i.e.
                  grimoires/loa/NOTES.md relative to a standard
                  grimoires/loa/a2a/sprint-N/reviewer.md report path)
  --json          Emit a JSON result object to stdout
  -h, --help      Show this help message

Exit codes:
  0  all acceptance criteria walked, Met evidence present, deferrals logged
  1  a violation was found (exact repair text on stderr)
  2  usage error (missing arguments, file not found)
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --report) REPORT="${2:-}"; shift 2 ;;
        --sprint) SPRINT="${2:-}"; shift 2 ;;
        --notes) NOTES="${2:-}"; shift 2 ;;
        --json) JSON_OUTPUT=true; shift ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "Unknown option: $1" >&2; show_help >&2; exit 2 ;;
    esac
done

if [[ -z "$REPORT" || -z "$SPRINT" ]]; then
    echo "Error: --report and --sprint are required" >&2
    show_help >&2
    exit 2
fi

if [[ ! -f "$REPORT" ]]; then
    echo "Error: report file not found: $REPORT" >&2
    exit 2
fi

if [[ ! -f "$SPRINT" ]]; then
    echo "Error: sprint file not found: $SPRINT" >&2
    exit 2
fi

if [[ -z "$NOTES" ]]; then
    # Standard layout: grimoires/loa/a2a/sprint-N/reviewer.md -> grimoires/loa/NOTES.md
    report_dir=$(dirname -- "$REPORT")
    NOTES="$(dirname -- "$(dirname -- "$report_dir")")/NOTES.md"
fi

violations=()
ac_count=0

# --- Check 1: '## AC Verification' section present ---
if ! grep -qE '^## AC Verification' -- "$REPORT" 2>/dev/null; then
    violations+=("report is missing the required '## AC Verification' section — add it per .claude/skills/implementing-tasks/resources/templates/implementation-report.md")
fi

# Extract the AC Verification section body (from the heading to the next
# top-level '## ' heading, or EOF).
ac_section=$(awk '
    /^## AC Verification/ { found=1; next }
    found && /^## / { exit }
    found { print }
' < "$REPORT")

# --- Extract acceptance-criteria bullets from sprint.md ---
# Bullets appear under a "### Acceptance Criteria" heading or an inline
# "**Acceptance Criteria:**" bold label (see resources/templates/sprint-template.md).
# A block ends at the next heading or a new bold "**Label:**" line.
sprint_acs=$(awk '
    /^### +Acceptance Criteria/ || /^\*\*Acceptance Criteria:\*\*/ { in_ac=1; next }
    in_ac && /^#{1,6} / { in_ac=0 }
    in_ac && /^\*\*[A-Za-z][^*]*:\*\*/ { in_ac=0 }
    in_ac && /^[[:space:]]*-[[:space:]]*\[[ xX]\]/ {
        line=$0
        sub(/^[[:space:]]*-[[:space:]]*\[[ xX]\][[:space:]]*/, "", line)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
        if (length(line) > 0) print line
    }
' < "$SPRINT")

missing_acs=()
if [[ -n "$sprint_acs" ]]; then
    while IFS= read -r ac_text; do
        [[ -z "$ac_text" ]] && continue
        ac_count=$((ac_count + 1))
        if ! printf '%s' "$ac_section" | grep -qF -- "$ac_text"; then
            missing_acs+=("$ac_text")
        fi
    done <<< "$sprint_acs"
fi

for ac in ${missing_acs[@]+"${missing_acs[@]}"}; do
    violations+=("sprint.md acceptance criterion not walked verbatim in report's '## AC Verification' section: \"$ac\" — quote it verbatim under '## AC Verification'")
done

# --- Parse per-AC blocks inside the AC Verification section for checks 3/4 ---
# Each block starts at a line matching **AC-...**: and runs to the next such
# line (or end of section). Emits one tagged result line per finding:
#   MET_NO_EVIDENCE<TAB>AC-id
#   DEFERRED<TAB>AC-id
ac_block_findings=$(awk '
    function flush() {
        if (id == "") { return }
        if (status ~ /✓ Met/ && evidence !~ /[A-Za-z0-9_.\/-]+:[0-9]+/) {
            print "MET_NO_EVIDENCE\t" id
        }
        if (status ~ /⏸/ || status ~ /\[ACCEPTED-DEFERRED\]/) {
            print "DEFERRED\t" id
        }
    }
    /^\*\*AC-[^*]+\*\*:/ {
        flush()
        id = $0
        sub(/^\*\*/, "", id); sub(/\*\*:.*/, "", id)
        status = ""; evidence = ""
        next
    }
    /^-[[:space:]]*Status:/ && status == "" { status = $0 }
    /^-[[:space:]]*Evidence:/ { evidence = evidence "\n" $0 }
    END { flush() }
' <<< "$ac_section")

met_no_evidence=()
deferred_unlogged=()

if [[ -n "$ac_block_findings" ]]; then
    while IFS=$'\t' read -r kind ac_id; do
        [[ -z "$kind" ]] && continue
        case "$kind" in
            MET_NO_EVIDENCE)
                met_no_evidence+=("$ac_id")
                ;;
            DEFERRED)
                logged=false
                if [[ -f "$NOTES" ]]; then
                    decision_log=$(awk '
                        /^## Decision Log/ { found=1; next }
                        found && /^## / { exit }
                        found { print }
                    ' < "$NOTES")
                    if printf '%s' "$decision_log" | grep -qF -- "$ac_id"; then
                        logged=true
                    fi
                fi
                [[ "$logged" == "false" ]] && deferred_unlogged+=("$ac_id")
                ;;
        esac
    done <<< "$ac_block_findings"
fi

for ac in ${met_no_evidence[@]+"${met_no_evidence[@]}"}; do
    violations+=("AC row $ac has Status: ✓ Met but no Evidence: line matching <file>:<line> — add file:line evidence or change the status")
done

for ac in ${deferred_unlogged[@]+"${deferred_unlogged[@]}"}; do
    violations+=("AC row $ac is ⏸ [ACCEPTED-DEFERRED] but has no matching entry in $NOTES under '## Decision Log' — add an entry referencing $ac")
done

if [[ "$JSON_OUTPUT" == "true" ]]; then
    viol_json="[]"
    for v in ${violations[@]+"${violations[@]}"}; do
        viol_json=$(echo "$viol_json" | jq --arg v "$v" '. + [$v]')
    done
    passfail="true"
    [[ ${#violations[@]} -gt 0 ]] && passfail="false"
    jq -n \
        --arg report "$REPORT" \
        --arg sprint "$SPRINT" \
        --argjson ac_count "$ac_count" \
        --argjson pass "$passfail" \
        --argjson violations "$viol_json" \
        '{report: $report, sprint: $sprint, ac_count: $ac_count, pass: $pass, violations: $violations}'
fi

if [[ ${#violations[@]} -gt 0 ]]; then
    for v in "${violations[@]}"; do
        echo "$v" >&2
    done
    exit 1
fi

exit 0
