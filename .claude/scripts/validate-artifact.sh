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
#   translation: citation-resolution anti-fabrication gate (C-D5, cycle-120).
#               --file may be a single .md or a directory (validates every
#               *.md under it). Every `(path:L##[-L##])` or bare table-cell
#               `path:L##` citation must resolve to a real file under
#               repo-root, grimoires/loa/, or grimoires/loa/reality/, with
#               the cited start line within the target file's line count.
#               WARN: translation-audit.md missing its grounding-audit
#               section; Phase-4 Health Score >2pt off a recompute. info:
#               [ASSUMPTION] tag count.
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
Usage: $SCRIPT_NAME --type prd|sdd|sprint|bug-triage|translation --file <path> [--json]

Validate a Loa planning artifact against its skill-defined structural
contract (grep-based, fail-closed).

Options:
  --type TYPE   Artifact type: prd | sdd | sprint | bug-triage | translation (required)
  --file PATH   Artifact file to validate (required). For --type translation,
                may also be a directory (validates every *.md under it).
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
    prd|sdd|sprint|bug-triage|translation) ;;
    *) echo "Error: --type must be one of prd|sdd|sprint|bug-triage|translation (got: $TYPE)" >&2; exit 2 ;;
esac

if [[ "$TYPE" == "translation" ]]; then
    # translation accepts a single .md file OR a directory of them.
    if [[ ! -e "$FILE" ]]; then
        echo "Error: file not found: $FILE" >&2
        exit 2
    fi
elif [[ ! -f "$FILE" ]]; then
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
            # R2 review (cycle-119): accept both the plain form ('> Sources:')
            # and the bold form ('> **Sources**:') — discovering-requirements'
            # <output_format> prescribes the bold form while its Phase-8
            # example uses the plain one.
            if ! printf '%s' "$body" | grep -qE '^> (\*\*)?Sources(\*\*)?:'; then
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
# R2 review (cycle-119): 'Security Considerations' appears only in the
# template's Sprint-1 example (Sprint 2 omits it) — WARN-only, not required.
SPRINT_REQUIRED_SECTIONS=(
    "Sprint Goal"
    "Deliverables"
    "Acceptance Criteria"
    "Technical Tasks"
    "Dependencies"
    "Risks & Mitigation"
    "Success Metrics"
)
SPRINT_WARN_SECTIONS=(
    "Security Considerations"
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
        for sec in "${SPRINT_WARN_SECTIONS[@]}"; do
            if ! printf '%s' "$block" | grep -qE "^### ($sec)\$"; then
                warnings+=("sprint block '${heading# }' (line $lineno) has no '### $sec' section — recommended for security-relevant sprints")
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

# =============================================================================
# translation (C-D5, cycle-120)
# =============================================================================
# Resolution bases, in order — hygiene-report.md lives under reality/, other
# /ride artifacts live directly under grimoires/loa/, and a citation may
# already be qualified with either prefix (in which case the repo-root base
# resolves it directly).
_translation_find_report() {
    local name="$1" base
    for base in "$PROJECT_ROOT" "$PROJECT_ROOT/grimoires/loa" "$PROJECT_ROOT/grimoires/loa/reality"; do
        if [[ -f "$base/$name" ]]; then
            echo "$base/$name"
            return 0
        fi
    done
    return 1
}

# Citation-resolution scan for one file. Matches both `(path:L##[-L##])`
# and bare table-cell `path:L##` with a single regex — the surrounding
# parens/pipes are not part of the match, so one pass covers both forms.
_validate_translation_citations() {
    local f="$1" in_fence=false lineno=0 line
    # Held in a single-quoted variable (never a bare literal in a =~/== RHS)
    # so the parser never treats the backticks as command substitution.
    local fence='```'
    while IFS= read -r line || [[ -n "$line" ]]; do
        lineno=$((lineno + 1))

        if [[ "$line" == "$fence"* || "$line" =~ ^[[:space:]]+${fence} ]]; then
            [[ "$in_fence" == true ]] && in_fence=false || in_fence=true
            continue
        fi
        [[ "$in_fence" == true ]] && continue

        # markdown-link / bare-URL forms — skip wholesale to avoid false
        # positives (a URL's "domain.tld/path:L##"-shaped substring is not
        # a citation into this repo).
        [[ "$line" == *'](http'* || "$line" == *'://'* ]] && continue

        # R2 review (cycle-120): the incremental `while [[ =~ ]]` scan below is
        # superlinear on a single very long path-dense line (LLM translation
        # docs routinely carry wide tables / pasted logs on one unwrapped line),
        # which would hang this MUST gate with no output. Cap line length; a
        # citation the gate must resolve never needs 2000+ chars on one line.
        # WARN rather than silently skip so an over-long line is visible.
        if (( ${#line} > 2000 )); then
            warnings+=("line ${lineno} exceeds 2000 chars — citation scan skipped for this line (wrap long tables/logs)")
            continue
        fi

        local rest="$line"
        while [[ "$rest" =~ ([A-Za-z0-9_./-]+\.[A-Za-z0-9]{1,6}):L([0-9]+)(-L[0-9]+)? ]]; do
            local cited_path="${BASH_REMATCH[1]}"
            local cited_startline="${BASH_REMATCH[2]}"
            local match_full="${BASH_REMATCH[0]}"
            rest="${rest#*"$match_full"}"

            # {...}-placeholder citations (e.g. `{file}:L{N}`) never reach
            # here — the regex requires a real dotted extension and real
            # digits — but guard explicitly in case a brace rides along a
            # real-looking path.
            [[ "$cited_path" == *'{'* || "$cited_path" == *'}'* ]] && continue

            local resolved="" base
            for base in "$PROJECT_ROOT" "$PROJECT_ROOT/grimoires/loa" "$PROJECT_ROOT/grimoires/loa/reality"; do
                if [[ -f "$base/$cited_path" ]]; then
                    resolved="$base/$cited_path"
                    break
                fi
            done

            if [[ -z "$resolved" ]]; then
                violations+=("CITATION UNRESOLVED: '$cited_path:L$cited_startline' cited at $f:$lineno does not resolve under repo-root, grimoires/loa/, or grimoires/loa/reality/ — fix the path or remove the citation")
                continue
            fi

            local total_lines
            total_lines=$(wc -l < "$resolved" | tr -d ' ')
            if [[ "$total_lines" =~ ^[0-9]+$ ]] && (( cited_startline > total_lines )); then
                violations+=("CITATION LINE OUT OF RANGE: '$cited_path:L$cited_startline' cited at $f:$lineno but $resolved has only $total_lines lines — fix the cited line number")
            fi
        done
    done < "$f"
}

# translation-audit.md required-sections (WARN only): the grounding-audit
# table (rendered as '## Grounding Summary' / '## Grounding Audit' per the
# skill's template) must be present.
_validate_translation_audit_sections() {
    local f
    for f in "$@"; do
        [[ "$(basename -- "$f")" == "translation-audit.md" ]] || continue
        if ! grep -qiE '^## Grounding (Summary|Audit)' -- "$f"; then
            warnings+=("$f: no '## Grounding Summary' / '## Grounding Audit' section found — translation-audit.md must include the grounding-audit table")
        fi
    done
}

# Phase-4 Health Score recompute (WARN only, best-effort): only fires when
# a stated 'Health Score' AND all three input reports (drift/consistency/
# hygiene) are extractable — per SKILL.md:344-348's official formula.
_validate_translation_health_score() {
    local files=("$@")
    (( ${#files[@]} == 0 )) && return 0

    local combined
    combined=$(cat "${files[@]}" 2>/dev/null || true)

    local stated
    stated=$(printf '%s\n' "$combined" | grep -oiE 'health score[^0-9]{0,10}[0-9]+(\.[0-9]+)?' | head -1 | grep -oE '[0-9]+(\.[0-9]+)?$' || true)
    [[ -z "$stated" ]] && return 0

    local drift_file consistency_file hygiene_file
    drift_file=$(_translation_find_report "drift-report.md" || true)
    consistency_file=$(_translation_find_report "consistency-report.md" || true)
    hygiene_file=$(_translation_find_report "hygiene-report.md" || true)
    [[ -z "$drift_file" || -z "$consistency_file" || -z "$hygiene_file" ]] && return 0

    local drift consistency hygiene
    drift=$(grep -oiE 'drift score:?[[:space:]]*[0-9]+(\.[0-9]+)?%' -- "$drift_file" | head -1 | grep -oE '[0-9]+(\.[0-9]+)?' || true)
    consistency=$(grep -oiE 'consistency score:?[[:space:]]*[0-9]+(\.[0-9]+)?[[:space:]]*/[[:space:]]*10' -- "$consistency_file" | grep -oE '[0-9]+(\.[0-9]+)?[[:space:]]*/[[:space:]]*10' | head -1 | grep -oE '^[0-9]+(\.[0-9]+)?' || true)
    hygiene=$(grep -oiE 'hygiene items:?[[:space:]]*[0-9]+' -- "$hygiene_file" | head -1 | grep -oE '[0-9]+$' || true)
    [[ -z "$drift" || -z "$consistency" || -z "$hygiene" ]] && return 0

    local recomputed diff
    recomputed=$(awk -v d="$drift" -v c="$consistency" -v h="$hygiene" 'BEGIN {
        hyg_capped = (h*5 > 100) ? 100 : h*5
        printf "%.2f", (100-d)*0.5 + (c*10)*0.3 + (100-hyg_capped)*0.2
    }')
    diff=$(awk -v a="$stated" -v b="$recomputed" 'BEGIN { d=a-b; if (d<0) d=-d; printf "%.2f", d }')

    if awk -v d="$diff" 'BEGIN { exit !(d > 2) }'; then
        warnings+=("HEALTH SCORE MISMATCH: stated Health Score $stated differs from recomputed $recomputed (drift=$drift%, consistency=$consistency/10, hygiene=$hygiene items — Phase 4 formula) by more than 2 points")
    fi
}

validate_translation() {
    local target_files=()
    if [[ -d "$FILE" ]]; then
        while IFS= read -r f; do
            target_files+=("$f")
        done < <(find "$FILE" -type f -name '*.md' | sort)
    else
        target_files=("$FILE")
    fi

    if [[ ${#target_files[@]} -eq 0 ]]; then
        violations+=("no *.md files found under $FILE")
        return
    fi

    local f
    for f in "${target_files[@]}"; do
        _validate_translation_citations "$f"
    done
    _validate_translation_audit_sections "${target_files[@]}"
    _validate_translation_health_score "${target_files[@]}"

    local assumption_total=0 c
    for f in "${target_files[@]}"; do
        c=$(grep -oE '\[ASSUMPTION\]' -- "$f" | wc -l | tr -d ' ' || true)
        [[ -z "$c" ]] && c=0
        assumption_total=$((assumption_total + c))
    done
    info_lines+=("[ASSUMPTION] tags: $assumption_total")
}

case "$TYPE" in
    prd) validate_prd ;;
    sdd) validate_sdd ;;
    sprint) validate_sprint ;;
    bug-triage) validate_bug_triage ;;
    translation) validate_translation ;;
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
