#!/usr/bin/env bash
# =============================================================================
# validate-artifact.sh — Parameterized planning-artifact validator (C10)
# =============================================================================
# Part of cycle-119 "mechanical floor". One grep-based, fail-closed validator
# for the four planning artifact types, wired as a final-phase MUST step in
# discovering-requirements / designing-architecture / planning-sprints /
# bug-triaging.
#
# Usage:
#   validate-artifact.sh --type prd|sdd|sprint|bug-triage --file <path> [--json]
#
# Per-type checks (see designing-architecture/planning-sprints/bug-triaging
# SKILL.md + their resources/templates/*.md for the source-of-truth shapes):
#   prd:        every '## ' section has a '> Sources:' line in its body;
#               counts [ASSUMPTION] tags (info only, never fails)
#   sdd:        the 10 required numbered H2 sections are present (derived
#               from designing-architecture/SKILL.md Phase 4 + its
#               sdd-template.md); WARN (never fails) on bare framework names
#               with no version-shaped token nearby
#   sprint:     every '## Sprint N' block has its 8 required sections; every
#               goal ID (G-N) referenced in the plan appears in the '##
#               Appendix' goal table; WARN if the final sprint has no
#               E2E/end-to-end task
#   bug-triage: bug_id matches the bug-triaging ID grammar; its sibling
#               .run/bugs/<id>/state.json has a schema_version; a PII scan
#               via pii-filter.sh (skipped if unavailable)
#
# Exit codes: 0 = pass, 1 = fail (repair text on stderr), 2 = usage error
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
SCRIPT_NAME="$(basename "$0")"

TYPE=""
FILE=""
JSON_OUTPUT=false

show_help() {
    cat <<EOF
Usage: $SCRIPT_NAME --type prd|sdd|sprint|bug-triage --file <path> [--json]

Validate a Loa planning artifact against its skill-defined structural
contract (grep-based, fail-closed).

Options:
  --type TYPE   Artifact type: prd | sdd | sprint | bug-triage (required)
  --file PATH   Artifact file to validate (required)
  --json        Emit a JSON result object to stdout
  -h, --help    Show this help message

Exit codes:
  0  pass (WARN-level info may still be printed)
  1  fail (exact repair text on stderr)
  2  usage error (missing arguments, unknown type, file not found)
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --type) TYPE="${2:-}"; shift 2 ;;
        --file) FILE="${2:-}"; shift 2 ;;
        --json) JSON_OUTPUT=true; shift ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "Unknown option: $1" >&2; show_help >&2; exit 2 ;;
    esac
done

if [[ -z "$TYPE" || -z "$FILE" ]]; then
    echo "Error: --type and --file are required" >&2
    show_help >&2
    exit 2
fi

case "$TYPE" in
    prd|sdd|sprint|bug-triage) ;;
    *) echo "Error: --type must be one of prd|sdd|sprint|bug-triage (got: $TYPE)" >&2; exit 2 ;;
esac

if [[ ! -f "$FILE" ]]; then
    echo "Error: file not found: $FILE" >&2
    exit 2
fi

violations=()
warnings=()
info_lines=()

# =============================================================================
# prd
# =============================================================================
validate_prd() {
    local sections
    sections=$(grep -nE '^## ' -- "$FILE" || true)

    if [[ -n "$sections" ]]; then
        while IFS=: read -r lineno heading; do
            [[ -z "$lineno" ]] && continue
            local body
            body=$(awk -v start="$lineno" '
                NR > start && /^## / { exit }
                NR > start { print }
            ' < "$FILE")
            if ! printf '%s' "$body" | grep -qE '^> Sources:'; then
                violations+=("PRD section '${heading# }' (line $lineno) has no '> Sources:' line in its body — add one per discovering-requirements Phase 8 template")
            fi
        done <<< "$sections"
    fi

    local assumption_count
    assumption_count=$(grep -oE '\[ASSUMPTION\]' -- "$FILE" | wc -l | tr -d ' ' || true)
    [[ -z "$assumption_count" ]] && assumption_count=0
    info_lines+=("[ASSUMPTION] tags: $assumption_count")
}

# =============================================================================
# sdd
# =============================================================================
# Derived verbatim from designing-architecture/SKILL.md Phase 4 "Required
# sections" list + resources/templates/sdd-template.md's numbered H2s.
SDD_REQUIRED_SECTIONS=(
    "1. Project Architecture"
    "2. Software Stack"
    "3. Database Design"
    "4. UI Design"
    "5. API Specifications"
    "6. Error Handling Strategy"
    "7. Testing Strategy"
    "8. Development Phases"
    "9. Known Risks and Mitigation"
    "10. Open Questions"
)

SDD_FRAMEWORK_NAMES=(
    "React" "Vue" "Angular" "Express" "Django" "Flask" "Rails" "Spring"
    "Next.js" "NextJS" "FastAPI" "PostgreSQL" "Postgres" "MySQL" "MongoDB"
    "Redis" "Docker" "Kubernetes" "Node.js" "NodeJS" "TypeScript" "Ruby" "Go"
)

validate_sdd() {
    local section
    for section in "${SDD_REQUIRED_SECTIONS[@]}"; do
        if ! grep -qF "## $section" -- "$FILE"; then
            violations+=("SDD is missing required section '## $section' — see designing-architecture/SKILL.md Phase 4 / resources/templates/sdd-template.md")
        fi
    done

    local name
    for name in "${SDD_FRAMEWORK_NAMES[@]}"; do
        local hits
        hits=$(grep -inw -- "$name" "$FILE" || true)
        [[ -z "$hits" ]] && continue
        while IFS= read -r hitline; do
            [[ -z "$hitline" ]] && continue
            if ! printf '%s' "$hitline" | grep -qE '[0-9]+\.[0-9]+'; then
                local lineno
                lineno=$(printf '%s' "$hitline" | cut -d: -f1)
                warnings+=("$FILE:$lineno: bare framework name '$name' with no version-shaped token (e.g. 18.2) on the same line")
            fi
        done <<< "$hits"
    done
}

# =============================================================================
# sprint
# =============================================================================
# Derived verbatim from planning-sprints/resources/templates/sprint-template.md.
SPRINT_REQUIRED_SECTIONS=(
    "Sprint Goal"
    "Deliverables"
    "Acceptance Criteria"
    "Technical Tasks"
    "Dependencies"
    "Security Considerations"
    "Risks & Mitigation"
    "Success Metrics"
)

validate_sprint() {
    local sprint_headings
    sprint_headings=$(grep -nE '^## Sprint [0-9]' -- "$FILE" || true)

    if [[ -z "$sprint_headings" ]]; then
        violations+=("no '## Sprint N' blocks found — sprint.md must contain at least one sprint block")
        return
    fi

    local last_sprint_heading="" last_sprint_lineno=0
    while IFS=: read -r lineno heading; do
        [[ -z "$lineno" ]] && continue
        last_sprint_heading="$heading"
        last_sprint_lineno="$lineno"
        local block
        block=$(awk -v start="$lineno" '
            NR > start && /^## Sprint [0-9]/ { exit }
            NR > start { print }
        ' < "$FILE")
        local sec
        for sec in "${SPRINT_REQUIRED_SECTIONS[@]}"; do
            if ! printf '%s' "$block" | grep -qE "^### ($sec)\$"; then
                violations+=("sprint block '${heading# }' (line $lineno) is missing required section '### $sec' — see planning-sprints/resources/templates/sprint-template.md")
            fi
        done
    done <<< "$sprint_headings"

    # Goal ID coverage: every G-N referenced in the plan body must appear in
    # the '## Appendix' goal-mapping table.
    local appendix_body
    appendix_body=$(awk '
        /^## Appendix/ { found=1; next }
        found && /^## / { exit }
        found { print }
    ' < "$FILE")

    local body_goal_ids
    body_goal_ids=$(grep -oE 'G-[0-9]+' -- "$FILE" | sort -u || true)
    if [[ -n "$body_goal_ids" ]]; then
        while IFS= read -r gid; do
            [[ -z "$gid" ]] && continue
            if ! printf '%s' "$appendix_body" | grep -qF "$gid"; then
                violations+=("goal ID $gid appears in the plan but not in the '## Appendix' goal table — add a row for $gid")
            fi
        done <<< "$body_goal_ids"
    fi

    # Final sprint E2E/validation task (WARN only).
    local last_block
    last_block=$(awk -v start="$last_sprint_lineno" 'NR > start { print }' < "$FILE")
    if ! printf '%s' "$last_block" | grep -qiE 'E2E|end-to-end'; then
        warnings+=("final sprint block '${last_sprint_heading# }' has no E2E/end-to-end validation task")
    fi
}

# =============================================================================
# bug-triage
# =============================================================================
BUG_ID_REGEX='^[0-9]{8}-(i[0-9]+-)?[0-9a-f]{6}$'

validate_bug_triage() {
    local bug_id
    bug_id=$(grep -m1 -E '^\s*-\s*\*\*bug_id\*\*:' -- "$FILE" | sed -E 's/^\s*-\s*\*\*bug_id\*\*:\s*//' | xargs || true)

    if [[ -z "$bug_id" ]]; then
        violations+=("no '**bug_id**:' line found in $FILE — see bug-triaging/resources/templates/triage.md")
        return
    fi

    if ! [[ "$bug_id" =~ $BUG_ID_REGEX ]]; then
        violations+=("bug_id '$bug_id' does not match the bug-triaging ID grammar (YYYYMMDD[-iN]-6hex, e.g. 20260211-a3f2b1 or 20260211-i42-a3f2b1) — see bug-triaging/SKILL.md Bug ID Generation")
    fi

    local state_file="${PROJECT_ROOT}/.run/bugs/${bug_id}/state.json"
    if [[ ! -f "$state_file" ]]; then
        violations+=("sibling state.json not found at $state_file — bug-triaging Phase 4 must create it")
    else
        local sv
        sv=$(jq -r '.schema_version // empty' "$state_file" 2>/dev/null) || sv=""
        if [[ -z "$sv" ]]; then
            violations+=("$state_file has no schema_version field")
        fi
    fi

    local pii_filter="${SCRIPT_DIR}/pii-filter.sh"
    if [[ -x "$pii_filter" ]]; then
        local pii_result redactions
        pii_result=$("$pii_filter" --file "$FILE" 2>/dev/null) || pii_result=""
        if [[ -n "$pii_result" ]]; then
            redactions=$(echo "$pii_result" | jq -r '.redactions // 0' 2>/dev/null) || redactions=0
            if [[ "$redactions" =~ ^[0-9]+$ ]] && [[ "$redactions" -gt 0 ]]; then
                violations+=("pii-filter.sh detected $redactions likely PII pattern(s) in $FILE — remove or redact sensitive data before triage")
            fi
        fi
    else
        info_lines+=("pii-filter.sh not available — PII scan skipped")
    fi
}

case "$TYPE" in
    prd) validate_prd ;;
    sdd) validate_sdd ;;
    sprint) validate_sprint ;;
    bug-triage) validate_bug_triage ;;
esac

if [[ "$JSON_OUTPUT" == "true" ]]; then
    viol_json="[]"; for v in ${violations[@]+"${violations[@]}"}; do viol_json=$(echo "$viol_json" | jq --arg v "$v" '. + [$v]'); done
    warn_json="[]"; for w in ${warnings[@]+"${warnings[@]}"}; do warn_json=$(echo "$warn_json" | jq --arg w "$w" '. + [$w]'); done
    info_json="[]"; for i in ${info_lines[@]+"${info_lines[@]}"}; do info_json=$(echo "$info_json" | jq --arg i "$i" '. + [$i]'); done
    passfail="true"
    [[ ${#violations[@]} -gt 0 ]] && passfail="false"
    jq -n \
        --arg type "$TYPE" \
        --arg file "$FILE" \
        --argjson pass "$passfail" \
        --argjson violations "$viol_json" \
        --argjson warnings "$warn_json" \
        --argjson info "$info_json" \
        '{type: $type, file: $file, pass: $pass, violations: $violations, warnings: $warnings, info: $info}'
else
    for i in ${info_lines[@]+"${info_lines[@]}"}; do
        echo "INFO: $i"
    done
    for w in ${warnings[@]+"${warnings[@]}"}; do
        echo "WARN: $w"
    done
fi

if [[ ${#violations[@]} -gt 0 ]]; then
    for v in "${violations[@]}"; do
        echo "$v" >&2
    done
    exit 1
fi

exit 0
