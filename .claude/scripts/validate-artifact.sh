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
#   validate-artifact.sh --type prd|sdd|sprint|bug-triage|translation|decisions|map|spike|glossary --file <path>
#                        [--base-file <path>] [--ledger <path>] [--json]
#
# Per-type checks (see designing-architecture/planning-sprints/bug-triaging
# SKILL.md + their resources/templates/*.md for the source-of-truth shapes):
#   prd:        every '## ' section has a '> Sources:' line in its body;
#               counts [ASSUMPTION fact|decision] and bare [ASSUMPTION] tags
#               (outside code); a bare tag WARNs, and fails for PRDs dated on or
#               after BARE_ASSUMPTION_FAILS_FROM; each [ASSUMPTION decision] line
#               and each **Deferred:** line must cite a DEC row in the ledger
#               (--ledger, default grimoires/loa/decisions.yaml) whose source
#               names the PRD: FAIL in an unattended context, WARN otherwise
#   sdd:        the 10 required numbered H2 sections are present (derived
#               from designing-architecture/SKILL.md Phase 4 + its
#               sdd-template.md); WARN (never fails) on bare framework names
#               with no version-shaped token nearby; WARN on an Open Questions
#               row marked Resolved without a DEC id in its DEC column
#   sprint:     every '## Sprint N' block has its 8 required sections; every
#               goal ID (G-N) referenced in the plan appears in the '##
#               Appendix' goal table; WARN if the final sprint has no
#               E2E/end-to-end task; a plan whose header **Date:** is on or
#               after SEAMS_REQUIRED_FROM needs a '### Seams Under Test' table
#               in every sprint block (older plans WARN; an undated plan WARNs when
#               archived or a fixture and fails when live under grimoires/loa/);
#               from KINDS_REQUIRED_FROM on, every task line under '### Technical
#               Tasks' and '### Task N.E2E' ends with exactly one 'kind:
#               mechanical|judgment|operator' token (same date rules; WARN on a
#               judgment task that names only script files or script/lint/generate)
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
#   decisions:  the decision ledger (grimoires/loa/sdd.md §3.1): schema,
#               enums, duplicate ids, PEND- ids outside a pending file,
#               transition invariants, decided_by consistency, ref grammars,
#               flatline/dissent artifact hashes, append-only content against
#               --base-file (else the merge-base copy), no operator attribution
#               under a live unattended signal, plain-prose free text, PII scan
#   map:        a /chart map doc (grimoires/loa/sdd.md §4.2): Slug, Status
#               (charting|handed-off|closed|abandoned) and Epic headers; exactly
#               the H2s Destination, Decisions so far, Not yet specified, Out of
#               scope in order, then an optional final Closed (any other H2
#               fails: a map carries no execution instructions); each Decisions
#               so far bullet cites a DEC id; no URL; blockquotes <= 2 lines; PII
#               scan. With br and .beads/: every epic child is a question bead
#               with exactly one decision: label, no sprint: label and an
#               external_ref naming a ledger row; a Status/epic disagreement WARNs
#   spike:      a prototype report (grimoires/loa/spikes/TEMPLATE.md): the five
#               H2s Question, What was built, Verdict, Pointer, Decided by,
#               present and non-empty; Pointer names a spike/ branch or a path;
#               Decided by names operator or agent; no URL; PII scan
#   glossary:   the framework .claude/loa/GLOSSARY.md or a project GLOSSARY.md
#               (grimoires/loa/sdd.md §4.5): an H1, a context paragraph before
#               '## Language', then one-line '**Term**: definition' entries of
#               at most two sentences and 300 characters; _Avoid_: and
#               _Aliases_: only directly below an entry; no duplicate term or
#               alias (case, '-', '_' and spaces folded); at most six aliases
#               per entry; WARN on an alias that shares no word with its term
#               or definition and is not the term's initials; WARN on a path or
#               file extension in '## Language'; CommonMark fences
#               (lib/md-fence.awk); PII scan
#   sprint also: with br and .beads/, no question bead carries a sprint: label
#               or sits under a sprint epic (an info line without br)
#
# Exit codes: 0 = pass, 1 = fail (repair text on stderr), 2 = usage error
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
SCRIPT_NAME="$(basename "$0")"

TYPE=""
FILE=""
BASE_FILE=""
LEDGER_FILE=""
JSON_OUTPUT=false
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/compat-lib.sh"

show_help() {
    cat <<EOF
Usage: $SCRIPT_NAME --type prd|sdd|sprint|bug-triage|translation|decisions|map|spike|glossary --file <path>
       [--base-file <path>] [--ledger <path>] [--json]

Validate a Loa planning artifact against its skill-defined structural
contract (grep-based, fail-closed).

Options:
  --type TYPE   Artifact type: prd | sdd | sprint | bug-triage | translation | decisions | map | spike | glossary (required)
  --file PATH   Artifact file to validate (required). For --type translation,
                may also be a directory (validates every *.md under it).
  --base-file PATH
                decisions: the pre-write ledger the append-only check compares
                against (default: the copy at git merge-base origin/main HEAD)
  --ledger PATH prd: the decision ledger the [ASSUMPTION decision] tags cite
                (default: grimoires/loa/decisions.yaml)
  --json        Emit a JSON result object to stdout
  -h, --help    Show this help message

sprint: plans dated from 2026-10-14 end every task line with
  ' · kind: mechanical|judgment|operator' (older plans WARN).

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
        --base-file) BASE_FILE="${2:-}"; shift 2 ;;
        --ledger) LEDGER_FILE="${2:-}"; shift 2 ;;
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
    prd|sdd|sprint|bug-triage|translation|decisions|map|spike|glossary) ;;
    *) echo "Error: --type must be one of prd|sdd|sprint|bug-triage|translation|decisions|map|spike|glossary (got: $TYPE)" >&2; exit 2 ;;
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
    # @guard validator:prd.sections
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
            # @guard validator:prd.sources
            if ! grep -qE '^> (\*\*)?Sources(\*\*)?:' <<< "$body"; then
                violations+=("PRD section '${heading# }' (line $lineno) has no '> Sources:' line in its body — add one per discovering-requirements Phase 8 template")
            fi
        done <<< "$sections"
    fi

    validate_prd_assumptions
}

# =============================================================================
# sdd
# =============================================================================
# Derived verbatim from designing-architecture/SKILL.md Phase 4 "Required
# sections" list + resources/templates/sdd-template.md's numbered H2s.
# @guard validator:sdd.sections
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
            if ! grep -qE '[0-9]+\.[0-9]+' <<< "$hitline"; then
                local lineno
                lineno=$(printf '%s' "$hitline" | cut -d: -f1)
                warnings+=("$FILE:$lineno: bare framework name '$name' with no version-shaped token (e.g. 18.2) on the same line")
            fi
        done <<< "$hits"
    done

    validate_sdd_open_questions
}

# =============================================================================
# sprint
# =============================================================================
# Derived verbatim from planning-sprints/resources/templates/sprint-template.md.
# R2 review (cycle-119): 'Security Considerations' appears only in the
# template's Sprint-1 example (Sprint 2 omits it) — WARN-only, not required.
# @guard validator:sprint.sections
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
            if ! grep -qE "^### ($sec)\$" <<< "$block"; then
                violations+=("sprint block '${heading# }' (line $lineno) is missing required section '### $sec' — see planning-sprints/resources/templates/sprint-template.md")
            fi
        done
        for sec in "${SPRINT_WARN_SECTIONS[@]}"; do
            if ! grep -qE "^### ($sec)\$" <<< "$block"; then
                warnings+=("sprint block '${heading# }' (line $lineno) has no '### $sec' section — recommended for security-relevant sprints")
            fi
        done
    done <<< "$sprint_headings"

    # @guard validator:sprint.goal-ids
    # Goal ID coverage: every G-N referenced in the plan body must appear in
    # a goal-mapping table under any '## Appendix' section.
    local appendix_body
    appendix_body=$(awk '
        /^## Appendix/ { found=1; next }
        found && /^## / { found=0 }
        found { print }
    ' < "$FILE")

    local body_goal_ids
    body_goal_ids=$(grep -oE 'G-[0-9]+' -- "$FILE" | sort -u || true)
    if [[ -n "$body_goal_ids" ]]; then
        while IFS= read -r gid; do
            [[ -z "$gid" ]] && continue
            if ! grep -qwF "$gid" <<< "$appendix_body"; then
                violations+=("goal ID $gid appears in the plan but not in any '## Appendix' goal table — add a row for $gid")
            fi
        done <<< "$body_goal_ids"
    fi

    validate_sprint_deferred
    validate_sprint_seams
    validate_sprint_kinds
    validate_sprint_beads

    # Final sprint E2E/validation task (WARN only).
    local last_block
    last_block=$(awk -v start="$last_sprint_lineno" 'NR > start { print }' < "$FILE")
    if ! grep -qiE 'E2E|end-to-end' <<< "$last_block"; then
        warnings+=("final sprint block '${last_sprint_heading# }' has no E2E/end-to-end validation task")
    fi
}

# =============================================================================
# bug-triage
# =============================================================================
BUG_ID_REGEX='^[0-9]{8}-(i[0-9]+-)?[0-9a-f]{6}$'

# @guard validator:bug-triage.schema
validate_bug_triage() {
    local bug_id
    bug_id=$(grep -m1 -E '^[[:space:]]*-[[:space:]]*\*\*bug_id\*\*:' -- "$FILE" | sed -E 's/^[[:space:]]*-[[:space:]]*\*\*bug_id\*\*:[[:space:]]*//' | xargs || true)

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
# @guard validator:translation.citations
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

# =============================================================================
# decisions (the decision ledger, grimoires/loa/sdd.md §3.1)
# =============================================================================
# Fail-closed schema + append-only check for grimoires/loa/decisions.yaml and the
# per-sprint decisions-pending.yaml files. The writer (.claude/scripts/lib/dec-write-lib.sh)
# runs this on every candidate before its atomic rename, passing the pre-write file as
# --base-file; without --base-file the base is the file at `git merge-base origin/main HEAD`
# when that commit has it, else the content-edit check is skipped (INFO line).
DEC_REF_RE='^(session:[A-Za-z0-9_.-]+#turn-[0-9]+|debrief:[^#[:space:]]+#[A-Za-z0-9_.-]+|transcript:[^#[:space:]]+#L[0-9]+|cli:[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}(:[0-9]{2})?(\.[0-9]+)?(Z|[+-][0-9]{2}:?[0-9]{2})|flatline:[^[:space:]]+|dissent:[^[:space:]]+)$'

_dec_have_yq4() {
    command -v yq >/dev/null 2>&1 || return 1
    local v; v="$(yq --version 2>&1 || true)"
    [[ "$v" == *mikefarah* && "$v" == *"version v4."* ]]
}

# The writer's context (`dec-write-lib.sh context --why`) for THIS validator's PROJECT_ROOT (passed as
# LOA_PROJECT_ROOT, so the probe reads the same tree's .run and prd.md as the artifact); prints its lines.
# The first line is the live verdict. With --prd (the PRD gate), the PRD's own Status line also counts:
# an autonomous PRD is the planning-time default the gate checks, so a prd signal makes it "unattended".
_dec_context_why() {
    local lib="${SCRIPT_DIR}/lib/dec-write-lib.sh" out
    [[ -f "$lib" ]] || return 0
    out="$(LOA_PROJECT_ROOT="$PROJECT_ROOT" bash "$lib" context --why "$@" 2>/dev/null || true)"
    if [[ " $* " == *" --prd "* ]] && grep -q '^signal: prd ' <<< "$out"; then
        out="unattended"$'\n'"$(printf '%s\n' "$out" | tail -n +2)"
    fi
    printf '%s\n' "$out"
}

# @guard validator:decisions.schema
validate_decisions() {
    if ! _dec_have_yq4; then
        violations+=("--type decisions needs Mike Farah yq v4 (https://github.com/mikefarah/yq); install it and re-run")
        return
    fi
    local doc
    if ! doc="$(yq -o=json -I0 '.' "$FILE" 2>/dev/null)" || [[ -z "$doc" ]]; then
        violations+=("$FILE does not parse as YAML")
        return
    fi
    local pending=false
    case "$(basename -- "$FILE")" in decisions-pending.yaml*) pending=true ;; esac

    # @guard validator:decisions.append-only
    local base="null"
    if [[ -n "$BASE_FILE" ]]; then
        if [[ ! -f "$BASE_FILE" ]] || ! base="$(yq -o=json -I0 '.' "$BASE_FILE" 2>/dev/null)" || [[ -z "$base" ]]; then
            violations+=("--base-file $BASE_FILE is missing or does not parse")
            return
        fi
    else
        local abs rel mb
        abs="$(cd "$(dirname -- "$FILE")" && pwd -P)/$(basename -- "$FILE")"
        rel="${abs#"$(cd "$PROJECT_ROOT" && pwd -P)/"}"
        if [[ "$rel" != "$abs" ]] && mb="$(git -C "$PROJECT_ROOT" merge-base origin/main HEAD 2>/dev/null)" \
            && git -C "$PROJECT_ROOT" cat-file -e "${mb}:${rel}" 2>/dev/null; then
            base="$(git -C "$PROJECT_ROOT" show "${mb}:${rel}" | yq -o=json -I0 '.' 2>/dev/null)" || base="null"
            [[ -n "$base" ]] || base="null"
            info_lines+=("append-only base: ${rel} at merge-base ${mb:0:8}")
        else
            info_lines+=("no append-only base (no --base-file, and the merge-base with origin/main has no copy): content-edit check skipped")
        fi
    fi

    # The writer passes --base-file (one write: strict single-write rules); the merge-base copy spans
    # every write on the branch, so only history rules apply to it.
    local strict=false; [[ -n "$BASE_FILE" ]] && strict=true
    local live_unattended=false
    if _dec_context_why | grep -q '^signal: live '; then live_unattended=true; fi

    # Documents go through files (--slurpfile): a large ledger overflows one argv string.
    local out scratch rc=0
    scratch="$(mktemp "${TMPDIR:-/tmp}/va-decisions.XXXXXX")"
    printf '%s' "$doc" > "${scratch}"
    printf '%s' "$base" > "${scratch}.base"
    out="$(jq -rn --slurpfile DOC "$scratch" --slurpfile BASE "${scratch}.base" --argjson pending "$pending" \
        --argjson unatt "$live_unattended" --argjson strict "$strict" --arg refre "$DEC_REF_RE" '
      $DOC[0] as $doc | $BASE[0] as $base |
      def oneof($xs): . as $v | any($xs[]; . == $v);
      def iso: type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?Z$");
      def ne: type == "string" and (gsub("\\s"; "") | length) > 0;
      def byok: type == "string" and test("^(operator|agent|flatline|dissent):[A-Za-z0-9_.-]+$");
      def opref: type == "string" and test("^(session|debrief|transcript|cli):");
      def allowed($f; $t): [[null,"open"],[null,"proposed"],["open","proposed"],["proposed","decided"],["open","rejected"],["proposed","rejected"],["decided","superseded"],["decided","rejected"]] | any(.[]; . == [$f, $t]);
      def free: [ .summary, .decision, .rationale, .rejection_rationale,
                  ((.alternatives_considered // []) | if type == "array" then (.[] | objects | .option, .rejected_because) else empty end),
                  ((.consequences // {}) | if type == "object" then (((.positive // []) | if type == "array" then .[] else empty end), ((.negative // []) | if type == "array" then .[] else empty end)) else empty end)
                ] | map(strings);
      def bqrun: [split("\n")[] | test("^\\s*>")] | reduce .[] as $b ({c: 0, m: 0}; if $b then {c: (.c + 1), m: ([.m, .c + 1] | max)} else {c: 0, m: .m} end) | .m;
      ($doc.decisions // []) as $D
      | (if ($D | type) == "array" then $D else [] end) as $D
      | ($D | map(objects)) as $R
      | ($R | map(select((.id | type) == "string") | {key: .id, value: .}) | from_entries) as $byid
      | [
          (if $doc.schema_version != 1 then "V\tunknown schema_version \($doc.schema_version | tojson) (this validator knows 1)" else empty end),
          (if ($doc.decisions | type) != "array" then "V\tdecisions is not a sequence" else empty end),
          ($R | map(.id) | map(select(. != null)) | group_by(.) | map(select(length > 1) | .[0]) | .[] | "V\tduplicate id \(.)"),
          ($D | to_entries[] | .key as $i | .value as $r
           | (if ($r | type) == "object" and (($r.id // null) | type) == "string" then $r.id else "row \($i)" end) as $L
           | if ($r | type) != "object" then "V\t\($L): not a mapping"
             else (
               (if $pending then
                  (if (($r.id // null) | type) == "string" and ($r.id | test("^PEND-[0-9a-f]{8}$")) then empty else "V\t\($L): id must be PEND-<8 hex> in a pending file" end)
                else
                  (if (($r.id // null) | type) == "string" and ($r.id | test("^DEC-[0-9]{4,}$")) then empty
                   elif (($r.id // null) | type) == "string" and ($r.id | startswith("PEND-")) then "V\t\($L): PEND- id in the live ledger; import it with dec-write-lib.sh import --from <pending file>"
                   else "V\t\($L): id must match ^DEC-[0-9]{4,}$" end)
                end),
               (["id","created_at","updated_at","phase","category","summary","proposed_by","decided_by","recorded_by","commit","source","cycle","status","transitions"][] as $k
                 | select(($r | has($k)) | not) | "V\t\($L): missing field \($k)"),
               (["created_at","updated_at"][] as $k | select($r | has($k)) | select(($r[$k] | iso) | not) | "V\t\($L): \($k) is not an ISO-8601 UTC timestamp"),
               (if ($r | has("phase")) and (($r.phase | oneof(["discovery","architecture","sprint-planning","implementation","review","charting","spike","operations"])) | not) then "V\t\($L): phase \($r.phase | tojson) is not one of discovery|architecture|sprint-planning|implementation|review|charting|spike|operations" else empty end),
               (if ($r | has("category")) and ((($r.category | type) == "string" and ($r.category | test("^[a-z][a-z0-9-]*$"))) | not) then "V\t\($L): category must match [a-z][a-z0-9-]*" else empty end),
               (if ($r | has("summary")) and (($r.summary | ne) | not) then "V\t\($L): summary is empty"
                elif ($r | has("summary")) and (($r.summary | length) > 160 or ($r.summary | test("\n"))) then "V\t\($L): summary must be one line of at most 160 characters" else empty end),
               (if ($r | has("status")) and (($r.status | oneof(["open","proposed","decided","superseded","rejected"])) | not) then "V\t\($L): status \($r.status | tojson) is not one of open|proposed|decided|superseded|rejected" else empty end),
               (if ($r | has("proposed_by")) and (($r.proposed_by | oneof(["agent","flatline","dissent"])) | not) then "V\t\($L): proposed_by must be agent|flatline|dissent" else empty end),
               (if ($r | has("decided_by")) and (($r.decided_by | oneof([null,"operator","agent","flatline","dissent"])) | not) then "V\t\($L): decided_by must be null or operator|agent|flatline|dissent" else empty end),
               (if ($r | has("source")) and (($r.source | ne) | not) then "V\t\($L): source is empty" else empty end),
               (if ($r | has("recorded_by")) and (($r.recorded_by | ne) | not) then "V\t\($L): recorded_by is empty" else empty end),
               (if ($r | has("commit")) and (($r.commit | type) != "string") then "V\t\($L): commit must be a string" else empty end),
               (($r.transitions // null) | if type == "array" then . else [] end) as $T
               | ($T | any(.[]; (type == "object") and .to == "decided")) as $wasdecided
               | (
                   (if ($r.status // null | oneof(["proposed","decided","superseded"])) or ($T | any(.[]; (type == "object") and .to == "proposed")) then
                      (if ($r.decision | ne) | not then "V\t\($L): a row past open needs a decision" else empty end),
                      (if ($r.rationale | ne) | not then "V\t\($L): a row past open needs a rationale" else empty end),
                      (if (($r.alternatives_considered // null) | type) != "array" or ($r.alternatives_considered | length) < 1 then "V\t\($L): a row past open needs at least one alternatives_considered entry"
                       elif ($r.alternatives_considered | all(.[]; (type == "object") and (.option | ne) and (.rejected_because | ne)) | not) then "V\t\($L): each alternative needs an option and a rejected_because"
                       else empty end)
                    else empty end),
                   (if ($r | has("transitions")) and ((($r.transitions | type) != "array") or ($T | length) == 0) then "V\t\($L): transitions must be a non-empty sequence" else empty end),
                   (if ($T | length) > 0 then
                      (if ($T[0] | type) != "object" or $T[0].from != null or (($T[0].to // null) | oneof(["open","proposed"]) | not) then "V\t\($L): the first transition must be null -> open|proposed" else empty end),
                      ($T | to_entries[] | .key as $j | .value as $t
                        | if ($t | type) != "object" then "V\t\($L): transition \($j) is not a mapping" else
                          (if $j > 0 and $t.from != (($T[$j - 1] | objects | .to) // null) then "V\t\($L): transition \($j) starts at \($t.from | tojson) but the previous one ended at \(($T[$j - 1] | objects | .to) // null | tojson)" else empty end),
                          (if allowed($t.from; $t.to) | not then "V\t\($L): illegal transition \($t.from | tojson) -> \($t.to | tojson)" else empty end),
                          (if ($t.at | iso) | not then "V\t\($L): transition \($j) has no ISO-8601 UTC at" else empty end),
                          (if ($t.by | byok) | not then "V\t\($L): transition \($j) by \($t.by | tojson) does not match (operator|agent|flatline|dissent):<name>" else empty end),
                          (if ($t.to == "decided" or ($t.from == "decided" and ($t.to | oneof(["superseded","rejected"])))) and ((($t.by // "") | tostring | startswith("operator:")) | not) then "V\t\($L): transition \($t.from | tojson) -> \($t.to) needs by operator:* (only /decisions makes it)" else empty end),
                          (if $t.to == "decided" and (($t.evidence | ne) | not) then "V\t\($L): the -> decided transition has no evidence" else empty end)
                          end),
                      (if ($r | has("status")) and ((($T[-1] | objects | .to) // null) != $r.status) then "V\t\($L): status \($r.status | tojson) does not equal the last transition (\((($T[-1] | objects | .to) // null) | tojson))" else empty end)
                    else empty end),
                   (if $wasdecided and ($r.decided_by == null) then "V\t\($L): a decided row needs decided_by"
                    elif ($wasdecided | not) and ($r.decided_by != null) then "V\t\($L): decided_by must stay null until /decisions confirm (status \($r.status | tojson))"
                    else empty end)
                 ),
               (if $r.decided_by == "operator" and (($r.decided_by_ref | opref) | not) then "V\t\($L): decided_by operator needs an operator answer reference (decided_by_ref session:|debrief:|transcript:|cli:)" else empty end),
               (if ($r.decided_by_ref // null) != null and ((($r.decided_by_ref | type) == "string" and ($r.decided_by_ref | test($refre))) | not) then "V\t\($L): decided_by_ref \($r.decided_by_ref | tojson) does not match the ref grammar" else empty end),
               (if ($r.evidence_sha256 // null) != null and ((($r.evidence_sha256 | type) == "string" and ($r.evidence_sha256 | test("^[0-9a-f]{64}$"))) | not) then "V\t\($L): evidence_sha256 must be 64 lowercase hex" else empty end),
               (($r.proposed_by // null) as $v | if ($v | oneof(["flatline","dissent"])) then
                  (if ((($r.decided_by_ref // "") | tostring | startswith($v + ":")) and (($r.evidence_sha256 // "") | tostring | test("^[0-9a-f]{64}$"))) then
                     "A\t\($v)\t\($r.decided_by_ref | ltrimstr($v + ":"))\t\($r.evidence_sha256)\t\($L)"
                   else "V\t\($L): a \($v) row needs decided_by_ref \($v):<artifact> and its evidence_sha256" end)
                else empty end),
               (if $r.status == "rejected" and ((($r.rejection_rationale | ne) and ($r.follow_up | ne)) | not) then "V\t\($L): a rejected row needs rejection_rationale and follow_up" else empty end),
               (if ($r.supersedes // null) != null then
                  ($r.supersedes) as $s | (if ($s | type) == "string" then $byid[$s] else null end) as $o
                  | if $o == null then "V\t\($L): supersedes \($s) names no row"
                    elif ($o.status == "superseded") or ($o.status == "decided" and $o.supersede_proposed_by == $r.id) then empty
                    else "V\t\($L): supersedes \($s), which is \($o.status | tojson) and does not name this row in supersede_proposed_by" end
                else empty end),
               (if ($r.supersede_proposed_by // null) != null then
                  ($r.supersede_proposed_by) as $s | if ((if ($s | type) == "string" then $byid[$s] else null end) | (. != null and .supersedes == $r.id)) | not then "V\t\($L): supersede_proposed_by \($s) names no row superseding it" else empty end
                else empty end),
               (if (($r.prior_requests // []) | type) != "array" then "V\t\($L): prior_requests must be a sequence" else empty end),
               ($r | free[] | select(test("https?://"; "i")) | "V\t\($L): a URL in free text (URLs belong only in source and decided_by_ref)"),
               ($r | free[] | select(bqrun > 2) | "V\t\($L): a quoted block longer than two lines in free text (copy at most two lines)")
             ) end),
          (if $base != null then
             (($base.decisions // []) | if type == "array" then map(objects) else [] end) as $B
             | ($B[] as $b
                | (if ($b.id | type) == "string" then $byid[$b.id] else null end) as $r
                | if $r == null then "V\t\($b.id): dropped (rows are append-only)"
                  else
                    (($b.transitions // []) | length) as $bl | (($r.transitions // []) | if type == "array" then length else 0 end) as $rl
                    | (if (($r.transitions // null) | type) != "array" or $rl < $bl or ($r.transitions[0:$bl] != ($b.transitions // [])) then "V\t\($b.id): transitions rewritten (append only)" else empty end),
                      # strict (--base-file, the pre-write file the writer passes): one write appends at most one
                      # transition. History (merge-base): any number, each already checked as a legal step.
                      (if $strict and $rl - $bl > 1 then "V\t\($b.id): more than one transition appended in one write" else empty end),
                      ((if $rl > $bl and (($r.transitions // null) | type) == "array" then $r.transitions[$bl:] | map(objects) else [] end) as $app
                       | ((($b | keys) + ($r | keys)) | unique[]) as $k
                       | if ($k | oneof(["status","updated_at","transitions"])) then empty
                         elif $b[$k] == $r[$k] then empty
                         elif ($k | oneof(["decision","rationale","alternatives_considered","consequences","evidence_sha256"])) and $b[$k] == null and any($app[]; .to == "proposed") then empty
                         elif $k == "decided_by_ref" and $b[$k] == null and any($app[]; .to | oneof(["proposed","decided"])) then empty
                         elif $k == "decided_by" and $b[$k] == null and any($app[]; .to == "decided") then empty
                         elif ($k | oneof(["rejection_rationale","follow_up"])) and $b[$k] == null and any($app[]; .to == "rejected") then empty
                         elif $k == "prior_requests" and (($b[$k] // []) == []) and any($app[]; .to == "rejected") then empty
                         elif $k == "supersede_proposed_by" and $b[$k] == null and $strict and ($app | length) == 0 and $r.status == "decided" then empty
                         elif $k == "supersede_proposed_by" and $b[$k] == null and ($strict | not) and ($r.status | oneof(["decided","superseded"])) then empty
                         else "V\t\($b.id): content edit to \($k) (rows are append-only; supersede the row instead)" end),
                      (if $unatt and $r.decided_by == "operator" and $b.decided_by != "operator" then "V\t\($b.id): decided_by operator written while a live unattended signal holds" else empty end)
                  end),
             ($B | map(select((.id | type) == "string") | {key: .id, value: true}) | from_entries) as $bids
             | ($R[] | select(($bids[.id | tostring] // false) | not) | select($unatt and .decided_by == "operator") | "V\t\(.id): a new row with decided_by operator while a live unattended signal holds")
           else empty end),
          "I\t\($R | length) decision rows"
        ] | .[]' 2>&1)" || rc=$?
    rm -f "$scratch" "${scratch}.base"
    if [[ $rc -ne 0 ]]; then
        violations+=("decisions validator failed to evaluate $FILE: $(printf '%s' "$out" | head -1)")
        return
    fi

    local kind a b c d line
    while IFS=$'\t' read -r kind a b c d; do
        case "$kind" in
            V) violations+=("$a") ;;
            I) info_lines+=("$a") ;;
            A)
                # a=voice b=path c=sha d=row
                local apath="$b"
                [[ "$apath" == /* ]] || apath="${PROJECT_ROOT}/${apath}"
                if [[ "$b" == *".."* || ! -f "$apath" ]]; then
                    violations+=("$d: the ${a} artifact ${b} is missing")
                else
                    local got
                    got="$(sha256_portable "$apath" | cut -d' ' -f1)"
                    [[ "$got" == "$c" ]] || violations+=("$d: the ${a} artifact ${b} hashes to ${got}, not the recorded evidence_sha256 ${c}")
                fi ;;
        esac
    done <<< "$out"

    local pii_filter="${SCRIPT_DIR}/pii-filter.sh"
    if [[ -x "$pii_filter" ]]; then
        local pii_result redactions
        pii_result=$("$pii_filter" --file "$FILE" 2>/dev/null) || pii_result=""
        if [[ -n "$pii_result" ]]; then
            redactions=$(echo "$pii_result" | jq -r '.redactions // 0' 2>/dev/null) || redactions=0
            if [[ "$redactions" =~ ^[0-9]+$ ]] && [[ "$redactions" -gt 0 ]]; then
                violations+=("pii-filter.sh detected $redactions likely PII pattern(s) in $FILE; the ledger is tracked state, remove them")
            fi
        fi
    else
        info_lines+=("pii-filter.sh not available; PII scan skipped")
    fi
}

# =============================================================================
# prd: assumption tag classes and the tag-to-row rule (grimoires/loa/sdd.md D-2.5)
# =============================================================================
# A bare [ASSUMPTION] WARNs for PRDs dated before this date and fails from it on.
BARE_ASSUMPTION_FAILS_FROM="2026-11-13"

# Lines of $FILE outside fenced code, inline code spans removed, prefixed "NR<TAB>".
_prd_prose_lines() {
    awk '
        /^[[:space:]]*(```|~~~)/ { fence = !fence; next }
        fence { next }
        { line = $0; gsub(/`[^`]*`/, "", line); printf "%d\t%s\n", NR, line }
    ' "$FILE"
}

# @guard validator:prd.assumption-tags
validate_prd_assumptions() {
    local prose
    prose="$(_prd_prose_lines)"
    local n_fact n_dec n_bare
    n_fact=$(grep -oE '\[ASSUMPTION fact\]' <<< "$prose" | wc -l | tr -d ' ' || true)
    n_dec=$(grep -oE '\[ASSUMPTION decision\]' <<< "$prose" | wc -l | tr -d ' ' || true)
    n_bare=$(grep -oE '\[ASSUMPTION\]' <<< "$prose" | wc -l | tr -d ' ' || true)
    info_lines+=("[ASSUMPTION] tags: $(( ${n_fact:-0} + ${n_dec:-0} + ${n_bare:-0} ))")
    info_lines+=("assumption tag classes: fact=${n_fact:-0} decision=${n_dec:-0} bare=${n_bare:-0}")

    local prd_date
    prd_date="$(grep -m1 -E '^\*\*Date:?\*\*:?' -- "$FILE" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1 || true)"
    if [[ "${n_bare:-0}" -gt 0 ]]; then
        if [[ -n "$prd_date" && ! "$prd_date" < "$BARE_ASSUMPTION_FAILS_FROM" ]]; then
            violations+=("${n_bare} bare [ASSUMPTION] tag(s): a PRD dated ${prd_date} (on or after ${BARE_ASSUMPTION_FAILS_FROM}) must name the class, [ASSUMPTION fact] or [ASSUMPTION decision] (DEC-NNNN)")
        else
            warnings+=("${n_bare} bare [ASSUMPTION] tag(s): name the class, [ASSUMPTION fact] or [ASSUMPTION decision] (DEC-NNNN); bare tags fail for PRDs dated from ${BARE_ASSUMPTION_FAILS_FROM}")
        fi
    fi

    local tagged deferred
    tagged="$(grep -E $'^[0-9]+\t.*\\[ASSUMPTION decision\\]' <<< "$prose" || true)"
    deferred="$(grep -E $'^[0-9]+\t[[:space:]]*([-*][[:space:]]+)?\\*\\*Deferred:?\\*\\*:?' <<< "$prose" || true)"
    [[ -n "$tagged" || -n "$deferred" ]] || return 0

    local unattended=false
    if _dec_context_why --prd "$FILE" | grep -q '^unattended'; then unattended=true; fi

    local ledger="${LEDGER_FILE:-${PROJECT_ROOT}/grimoires/loa/decisions.yaml}" rows=""
    if [[ -f "$ledger" ]] && _dec_have_yq4; then
        rows="$(yq -o=json -I0 '.' "$ledger" 2>/dev/null | jq -r '(.decisions // [])[] | objects | "\(.id)\t\(.source // "")"' 2>/dev/null || true)"
    else
        info_lines+=("decision ledger unreadable (${ledger}; needs the file and yq v4): every cited DEC row counts as missing")
    fi
    local prd_name; prd_name="$(basename -- "$FILE")"
    local misses=() ln text ids id ok
    while IFS=$'\t' read -r ln text; do
        [[ -n "$ln" ]] || continue
        ids="$(grep -oE 'DEC-[0-9]{4,}' <<< "$text" || true)"
        ok=false
        while IFS= read -r id; do
            [[ -n "$id" ]] || continue
            if awk -F'\t' -v id="$id" -v n="$prd_name" '$1 == id && index($2, n) > 0 { f = 1 } END { exit !f }' <<< "$rows"; then ok=true; break; fi
        done <<< "$ids"
        [[ "$ok" == true ]] || misses+=("$FILE:$ln: [ASSUMPTION decision] cites no DEC row whose source names ${prd_name}; record it with dec-write-lib.sh new --source ${prd_name}#... and cite (DEC-NNNN) on the line")
    done <<< "$tagged"
    while IFS=$'\t' read -r ln text; do
        [[ -n "$ln" ]] || continue
        ids="$(grep -oE 'DEC-[0-9]{4,}' <<< "$text" || true)"
        ok=false
        while IFS= read -r id; do
            [[ -n "$id" ]] || continue
            if awk -F'\t' -v id="$id" '$1 == id { f = 1 } END { exit !f }' <<< "$rows"; then ok=true; break; fi
        done <<< "$ids"
        [[ "$ok" == true ]] || misses+=("$FILE:$ln: **Deferred:** line cites no existing DEC row; the form is **Deferred:** pending prototype <bead> (DEC-NNNN)")
    done <<< "$deferred"

    local m
    for m in ${misses[@]+"${misses[@]}"}; do
        if [[ "$unattended" == true ]]; then violations+=("$m (unattended PRD)"); else warnings+=("$m"); fi
    done
}

# =============================================================================
# sprint: a task citing a PRD requirement marked **Deferred:** (WARN only, D-2.5)
# =============================================================================
# The PRD is the sibling prd.md of the sprint file. A requirement is deferred when its
# '### FR-N' block holds a **Deferred:** line; a task line citing FR-N WARNs.
# @guard validator:sprint.deferred
validate_sprint_deferred() {
    local prd; prd="$(dirname -- "$FILE")/prd.md"
    [[ -f "$prd" ]] || return 0
    local deferred
    deferred="$(awk '
        /^### FR-[0-9]+/ { match($0, /FR-[0-9]+/); fr = substr($0, RSTART, RLENGTH); next }
        /^#{1,3} / { fr = "" }
        fr != "" && /^[[:space:]]*([-*][[:space:]]+)?\*\*Deferred:?\*\*:?/ { print fr; fr = "" }
    ' "$prd" | sort -u)"
    [[ -n "$deferred" ]] || return 0
    local fr hits ln
    while IFS= read -r fr; do
        [[ -n "$fr" ]] || continue
        hits="$(grep -nE "^[[:space:]]*- \[[ xX]\] (.*[^A-Za-z0-9-])?${fr}([^0-9]|\$)" -- "$FILE" | cut -d: -f1 || true)"
        while IFS= read -r ln; do
            [[ -n "$ln" ]] || continue
            warnings+=("$FILE:$ln: this task cites ${fr}, which the PRD marks **Deferred:** pending a prototype; build it only after its DEC row is decided")
        done <<< "$hits"
    done <<< "$deferred"
}

# =============================================================================
# sprint: '### Seams Under Test' per sprint block (grimoires/loa/sdd.md D-7.2)
# =============================================================================
# Gated on the plan header's **Date:** (the first one before the first H2): from
# SEAMS_REQUIRED_FROM on, every '## Sprint N' block (up to the next H2) must carry
# the block with at least one table row below its separator line; older and
# undated plans WARN once, except that a live plan (under grimoires/loa/, not its
# archive/) without a parseable header date fails. Fenced code is tracked by
# lib/md-fence.awk (CommonMark lengths and characters); headings inside it do not count.
SEAMS_REQUIRED_FROM="2026-10-13"

# @guard validator:sprint.seams
validate_sprint_seams() {
    local fence_src
    if ! fence_src="$(cat "${SCRIPT_DIR}/lib/md-fence.awk" 2>/dev/null)" || [[ -z "$fence_src" ]]; then
        violations+=("cannot read ${SCRIPT_DIR}/lib/md-fence.awk; the sprint Seams check needs it (reinstall the framework scripts)")
        return 0
    fi
    local plan_date
    plan_date="$(LC_ALL=C awk "$fence_src"'
        md_fence($0) { next }
        /^## / { exit }
        /^\*\*Date:?\*\*:?/ { if (match($0, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)) print substr($0, RSTART, RLENGTH); exit }
    ' "$FILE")"
    # A live plan (under grimoires/loa/, not its archive) must carry a parseable header date,
    # or the gate below would fail open; archived plans and fixtures keep the WARN.
    local canon="" root=""
    canon="$(cd "$(dirname -- "$FILE")" 2>/dev/null && pwd -P)/$(basename -- "$FILE")" || canon=""
    root="$(cd "$PROJECT_ROOT" 2>/dev/null && pwd -P)" || root=""
    if [[ -z "$plan_date" && -n "$root" ]]; then
        case "$canon" in
            "${root}/grimoires/loa/archive/"*) ;;
            "${root}/grimoires/loa/"*)
                violations+=("a sprint plan carries **Date:** YYYY-MM-DD in its header (before the first '## ' heading); ${FILE} has none that parses, so the Seams gate (from ${SEAMS_REQUIRED_FROM}) cannot be judged")
                return 0 ;;
        esac
    fi
    local missing
    missing="$(LC_ALL=C awk "$fence_src"'
        function emit() { if (insp && rows < 1) printf "%s (line %d)\n", head, hl }
        md_fence($0) { next }
        /^## / {
            emit(); insp = 0
            if ($0 ~ /^## Sprint [0-9]/) { insp = 1; head = substr($0, 4); hl = NR; rows = 0; inseam = 0 }
            next
        }
        !insp { next }
        /^###/ { inseam = ($0 ~ /^### Seams Under Test[[:space:]]*$/); sep = 0; next }
        inseam && /^\|/ {
            if ($0 ~ /^\|[[:space:]:|-]+$/) { sep = 1 } else if (sep) { rows++ }
        }
        END { emit() }
    ' "$FILE")"
    [[ -n "$missing" ]] || return 0
    if [[ -n "$plan_date" && ! "$plan_date" < "$SEAMS_REQUIRED_FROM" ]]; then
        local m
        while IFS= read -r m; do
            [[ -n "$m" ]] || continue
            violations+=("sprint block '${m}' has no '### Seams Under Test' table with at least one row: a plan dated ${plan_date} (on or after ${SEAMS_REQUIRED_FROM}) needs | Seam | Catches | Misses | Prior art | per sprint — see planning-sprints/resources/templates/sprint-template.md")
        done <<< "$missing"
    else
        warnings+=("${plan_date:-undated} plan: $(wc -l <<< "$missing" | tr -d ' ') sprint block(s) without a '### Seams Under Test' table; the block is required for plans dated from ${SEAMS_REQUIRED_FROM}")
    fi
}

# =============================================================================
# sprint: a 'kind:' tag ends every task line (grimoires/loa/sdd.md D-10.1; DEC-0144, DEC-0154)
# =============================================================================
# Gated on the header **Date:** exactly as the Seams rule above: from KINDS_REQUIRED_FROM
# on, every top-level '- [ ]' / '- [x]' line under '### Technical Tasks', and every
# '- [ ] Task ...' line under a '### Task N.E2E' heading, inside a '## Sprint N' block,
# ends with exactly one 'kind: mechanical|judgment|operator' token (whitespace around the
# colon allowed, nothing but whitespace after the value; the ⇐ dependency marker may be
# absent). Older and undated plans WARN once; a live plan without a parseable header date
# fails. Inline code spans are not tokens. A 'judgment' task that names only *.sh, *.py or
# *.ts files, or the verbs script, lint or generate, WARNs (never fails).
# @guard validator:sprint.kinds
KINDS_REQUIRED_FROM="2026-10-14"

validate_sprint_kinds() {
    local fence_src
    if ! fence_src="$(cat "${SCRIPT_DIR}/lib/md-fence.awk" 2>/dev/null)" || [[ -z "$fence_src" ]]; then
        violations+=("cannot read ${SCRIPT_DIR}/lib/md-fence.awk; the sprint kind: check needs it (reinstall the framework scripts)")
        return 0
    fi
    local plan_date
    plan_date="$(LC_ALL=C awk "$fence_src"'
        md_fence($0) { next }
        /^## / { exit }
        /^\*\*Date:?\*\*:?/ { if (match($0, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)) print substr($0, RSTART, RLENGTH); exit }
    ' "$FILE")"
    local enforce=false canon="" root=""
    if [[ -n "$plan_date" ]]; then
        [[ "$plan_date" < "$KINDS_REQUIRED_FROM" ]] || enforce=true
    else
        canon="$(cd "$(dirname -- "$FILE")" 2>/dev/null && pwd -P)/$(basename -- "$FILE")" || canon=""
        root="$(cd "$PROJECT_ROOT" 2>/dev/null && pwd -P)" || root=""
        if [[ -n "$root" ]]; then
            case "$canon" in
                "${root}/grimoires/loa/archive/"*) ;;
                "${root}/grimoires/loa/"*)
                    violations+=("a sprint plan carries **Date:** YYYY-MM-DD in its header (before the first '## ' heading); ${FILE} has none that parses, so the kind: rule (from ${KINDS_REQUIRED_FROM}) cannot be judged")
                    return 0 ;;
            esac
        fi
    fi
    local findings
    findings="$(LC_ALL=C awk "$fence_src"'
        function ntok(s,   n) {
            n = 0
            while (match(s, /(^|[^A-Za-z0-9_])kind[[:space:]]*:/)) { n++; s = substr(s, RSTART + RLENGTH) }
            return n
        }
        md_fence($0) { next }
        /^## / { insp = ($0 ~ /^## Sprint [0-9]/); sec = 0; next }
        !insp { next }
        /^### / {
            sec = 0
            if ($0 ~ /^### Technical Tasks[[:space:]]*$/) sec = 1
            else if ($0 ~ /^### Task [0-9A-Za-z]+\.E2E([^A-Za-z0-9]|$)/) sec = 2
            next
        }
        !sec || $0 !~ /^- \[[ xX]\] / { next }
        sec == 2 && $0 !~ /^- \[[ xX]\] Task / { next }
        {
            raw = $0; t = raw
            gsub(/`[^`]*`/, "", t)
            n = ntok(t)
            if (n == 0) { printf "M\t%d\t0\n", NR; next }
            if (n > 1) { printf "D\t%d\t%d\n", NR, n; next }
            if (raw !~ /(^|[^A-Za-z0-9_])kind[[:space:]]*:[[:space:]]*(mechanical|judgment|operator)[[:space:]]*$/) {
                if (t ~ /(^|[^A-Za-z0-9_])kind[[:space:]]*:[[:space:]]*(mechanical|judgment|operator)([^A-Za-z0-9_]|$)/) printf "T\t%d\t0\n", NR
                else printf "U\t%d\t0\n", NR
                next
            }
            if (raw !~ /judgment[[:space:]]*$/) next
            files = 0; code = 0; s = raw
            while (match(s, /[A-Za-z0-9_.\/*-]+\.(sh|py|ts|js|md|yaml|yml|json|tsv|bats|txt|toml)([^A-Za-z0-9_]|$)/)) {
                tok = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
                files++
                if (tok ~ /\.(sh|py|ts)([^A-Za-z0-9_]|$)/) code++
            }
            v = tolower(t)
            if ((files > 0 && files == code) || v ~ /(^|[^a-z0-9_])(script|lint|generate)([^a-z0-9_]|$)/) printf "J\t%d\t0\n", NR
        }
    ' "$FILE")"
    [[ -n "$findings" ]] || return 0
    local code ln extra
    local -a bad=()
    while IFS=$'\t' read -r code ln extra; do
        case "$code" in
            J) warnings+=("$FILE:$ln: a task tagged kind: judgment names only *.sh/*.py/*.ts files or the verbs script, lint, generate; if a script could do it reliably, tag it kind: mechanical") ;;
            M) bad+=("$FILE:$ln: a task line has no kind: token; end it with ' · kind: mechanical|judgment|operator'") ;;
            D) bad+=("$FILE:$ln: a task line carries ${extra} kind: tokens; keep exactly one, at the end of the line") ;;
            T) bad+=("$FILE:$ln: a task line has text after its kind: value; the kind: token ends the line") ;;
            U) bad+=("$FILE:$ln: a task line's kind: value is not one of mechanical, judgment, operator (lower case)") ;;
        esac
    done <<< "$findings"
    [[ ${#bad[@]} -gt 0 ]] || return 0
    if [[ "$enforce" == "true" ]]; then
        local b
        for b in "${bad[@]}"; do
            violations+=("${b} (a plan dated ${plan_date}, on or after ${KINDS_REQUIRED_FROM}, tags every task; see planning-sprints/resources/templates/sprint-template.md)")
        done
    else
        warnings+=("${plan_date:-undated} plan: ${#bad[@]} task line(s) without a valid kind: tag; the tag is required for plans dated from ${KINDS_REQUIRED_FROM}")
    fi
}

# =============================================================================
# sdd: Open Questions rows marked Resolved name their DEC row (WARN only, D-3.16)
# =============================================================================
# @guard validator:sdd.open-questions
validate_sdd_open_questions() {
    local hits
    hits="$(awk '
        function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
        /^## 10\. Open Questions/ { sec = 1; next }
        sec && /^## / { sec = 0 }
        !sec { next }
        /^\|/ {
            n = split($0, c, "|")
            if (!hdr) {
                hdr = 1
                for (i = 2; i < n; i++) { h = tolower(trim(c[i])); if (h == "status") st = i; if (h == "dec") dc = i }
                next
            }
            if ($0 ~ /^\|[-|: ]+\|?[[:space:]]*$/) next
            # a whole word: "Unresolved" is not Resolved (Bridgebuilder F-007)
            if (st && tolower(c[st]) ~ /(^|[^a-z])resolved([^a-z]|$)/) {
                cell = dc ? c[dc] : $0
                if (cell !~ /DEC-[0-9][0-9][0-9][0-9]/) printf "%d\n", NR
            }
        }
    ' "$FILE")"
    local ln
    while IFS= read -r ln; do
        [[ -n "$ln" ]] || continue
        warnings+=("$FILE:$ln: an Open Questions row is Resolved without a DEC id in its DEC column; cite the decision row (DEC-NNNN)")
    done <<< "$hits"
}

# =============================================================================
# Shared helpers for map and spike documents (grimoires/loa/sdd.md D-3.17)
# =============================================================================
# Lines outside fenced code, prefixed "NR<TAB>" (inline code kept: a URL in
# backticks is still a URL in the document).
_md_unfenced_lines() {
    LC_ALL=C awk '
        /^[[:space:]]*(```|~~~)/ { fence = !fence; next }
        fence { next }
        { printf "%d\t%s\n", NR, $0 }
    ' "$FILE"
}

# D-3.17 plain prose: no URL in the document text, no blockquote run longer
# than two lines (copied external text stays short). $1 names the repair.
_md_prose_rules() {
    local repair="$1" ln text
    while IFS=$'\t' read -r ln text; do
        [[ -n "$ln" ]] || continue
        violations+=("$FILE:$ln: a URL in the document; ${repair}")
    done < <(_md_unfenced_lines | grep -iE $'^[0-9]+\t.*https?://' || true)
    local runs
    runs="$(_md_unfenced_lines | LC_ALL=C awk -F'\t' '
        $2 ~ /^[[:space:]]*>/ { if (!n) s = $1; n++; next }
        { if (n > 2) printf "%d\t%d\n", s, n; n = 0 }
        END { if (n > 2) printf "%d\t%d\n", s, n }
    ')"
    local start count
    while IFS=$'\t' read -r start count; do
        [[ -n "$start" ]] || continue
        violations+=("$FILE:$start: a blockquote of $count lines; quote at most two lines of external text and cite the rest by path")
    done <<< "$runs"
}

# pii-filter.sh over $FILE; $1 is the violation suffix.
_md_pii_scan() {
    local pii_filter="${SCRIPT_DIR}/pii-filter.sh"
    if [[ -x "$pii_filter" ]]; then
        local pii_result redactions
        pii_result=$("$pii_filter" --file "$FILE" 2>/dev/null) || pii_result=""
        if [[ -n "$pii_result" ]]; then
            redactions=$(echo "$pii_result" | jq -r '.redactions // 0' 2>/dev/null) || redactions=0
            if [[ "$redactions" =~ ^[0-9]+$ ]] && [[ "$redactions" -gt 0 ]]; then
                violations+=("pii-filter.sh detected $redactions likely PII pattern(s) in $FILE; $1")
            fi
        fi
    else
        info_lines+=("pii-filter.sh not available; PII scan skipped")
    fi
}

# The value of a '**Key**: value' header line (first match, trimmed).
_md_header() {
    grep -m1 -E "^\*\*$1\*\*:" -- "$FILE" | sed -E "s/^\*\*$1\*\*:[[:space:]]*//; s/[[:space:]]+\$//" || true
}

# The body of the H2 section named $1 (outside fenced code), blank lines dropped.
_md_section_body() {
    LC_ALL=C awk -v want="$1" '
        /^[[:space:]]*(```|~~~)/ { fence = !fence; if (sec) print; next }
        !fence && /^## / { h = $0; sub(/^## +/, "", h); sub(/[[:space:]]+$/, "", h); sec = (h == want); next }
        !fence && /^# / { sec = 0; next }
        sec && $0 ~ /[^[:space:]]/ { print }
    ' "$FILE"
}

# H2 headings outside fenced code, "NR<TAB>title".
_md_h2_list() {
    LC_ALL=C awk '
        /^[[:space:]]*(```|~~~)/ { fence = !fence; next }
        !fence && /^## / { h = $0; sub(/^## +/, "", h); sub(/[[:space:]]+$/, "", h); printf "%d\t%s\n", NR, h }
    ' "$FILE"
}

# Beads cross-checks run against the project's own tracker only: br on PATH,
# a .beads/ directory at the project root, and the validated file inside the
# project (a fixture elsewhere has no relation to this project's beads).
_beads_crosscheck_available() {
    command -v br >/dev/null 2>&1 || return 1
    [[ -d "${PROJECT_ROOT}/.beads" ]] || return 1
    local root dir
    root="$(cd "$PROJECT_ROOT" 2>/dev/null && pwd -P)" || return 1
    dir="$(cd "$(dirname -- "$FILE")" 2>/dev/null && pwd -P)" || return 1
    [[ "$dir/" == "$root/"* ]]
}

# br <args> run at the project root, stdout only; normalised to a JSON array
# of issues ("list" replies are {issues: [...]}, "show" replies are arrays).
_br_json_array() {
    local out
    out="$(cd "$PROJECT_ROOT" && br "$@" 2>/dev/null)" || return 1
    printf '%s' "$out" | jq -c 'if type == "array" then . elif type == "object" then (.issues // [.]) else [] end' 2>/dev/null
}

# =============================================================================
# sprint: no question bead carries a sprint: label or sits under a sprint epic
# (grimoires/loa/sdd.md D-4.7 d, A16)
# =============================================================================
# @guard validator:sprint.beads-crosscheck
validate_sprint_beads() {
    if ! _beads_crosscheck_available; then
        info_lines+=("beads cross-check skipped (needs br, ${PROJECT_ROOT}/.beads and the plan inside the project): question beads were not checked for sprint labels")
        return 0
    fi
    local questions epics
    if ! questions="$(_br_json_array list --type question --limit 0 --json)" \
       || ! epics="$(_br_json_array list --type epic --all --limit 0 --json)"; then
        warnings+=("br list failed; the question-bead sprint cross-check did not run")
        return 0
    fi
    local hits
    hits="$(jq -rn --argjson q "$questions" --argjson e "$epics" '
        def labels: [(.labels // [])[] | if type == "object" then (.name // "") else tostring end];
        ($e | map(select(labels | any(startswith("sprint:")))) | map(.id)) as $sprint_epics
        | $q[]
        | . as $b
        | (labels) as $l
        | ([$l[] | select(startswith("sprint:"))]) as $sl
        | ([(.dependencies // [])[] | select((.type // .dependency_type // "") == "parent-child") | (.depends_on_id // .id // "")]
           + [$l[] | select(startswith("epic:")) | ltrimstr("epic:")]) as $parents
        | ([$parents[] | select(. as $p | $sprint_epics | index([$p]) != null)] | unique) as $sp
        | (if ($sl | length) > 0 then "L\t\($b.id)\t\($sl | join(","))" else empty end),
          (if ($sp | length) > 0 then "E\t\($b.id)\t\($sp | join(","))" else empty end)
    ' 2>/dev/null || true)"
    local kind id what
    while IFS=$'\t' read -r kind id what; do
        [[ -n "$kind" ]] || continue
        case "$kind" in
            L) violations+=("question bead $id carries $what: decision tickets never join a sprint; remove it with br label remove $id <label>") ;;
            E) violations+=("question bead $id sits under sprint epic $what: decision tickets belong to a /chart map; move it with /chart or close it") ;;
        esac
    done <<< "$hits"
}

# =============================================================================
# map: a /chart decision map document (grimoires/loa/sdd.md D-4.8, §4.2)
# =============================================================================
MAP_SECTIONS=("Destination" "Decisions so far" "Not yet specified" "Out of scope")
MAP_STATUSES="charting handed-off closed abandoned"
BEAD_ID_RE='^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'

# @guard validator:map.schema
validate_map() {
    local slug status epic
    slug="$(_md_header Slug)"; status="$(_md_header Status)"; epic="$(_md_header Epic)"
    if [[ -z "$slug" ]]; then
        violations+=("no '**Slug**:' header line; add '**Slug**: <slug>' under the title (see grimoires/loa/sdd.md §4.2)")
    elif ! [[ "$slug" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]]; then
        violations+=("**Slug** '$slug' is not a slug (letters, digits, '.', '_', '-'; 64 characters at most)")
    fi
    if [[ -z "$status" ]]; then
        violations+=("no '**Status**:' header line; add '**Status**: charting' (one of: $MAP_STATUSES)")
    elif [[ " $MAP_STATUSES " != *" $status "* ]]; then
        violations+=("**Status** '$status' is not one of: $MAP_STATUSES")
    fi
    if [[ -z "$epic" ]]; then
        violations+=("no '**Epic**:' header line; add '**Epic**: <bead-id>' naming the map epic")
    elif ! [[ "$epic" =~ $BEAD_ID_RE ]]; then
        violations+=("**Epic** '$epic' is not a bead id")
    fi

    local h1s
    h1s="$(_md_unfenced_lines | grep -cE $'^[0-9]+\t# ' || true)"
    if [[ "${h1s:-0}" -ne 1 ]]; then
        violations+=("a map doc has exactly one H1 ('# Map: <title>'); found ${h1s:-0}")
    fi

    # H2 allowlist, in order, plus an optional final '## Closed'. Any other H2
    # is refused: a map plans and never carries execution instructions.
    local ln title idx=0 seen_closed=false
    while IFS=$'\t' read -r ln title; do
        [[ -n "$ln" ]] || continue
        if [[ "$seen_closed" == true ]]; then
            violations+=("$FILE:$ln: '## $title' after '## Closed'; '## Closed' is the last section of a map doc")
            continue
        fi
        if [[ "$title" == "Closed" ]]; then
            seen_closed=true
            continue
        fi
        if [[ $idx -lt ${#MAP_SECTIONS[@]} && "$title" == "${MAP_SECTIONS[$idx]}" ]]; then
            idx=$((idx + 1))
            continue
        fi
        local known=false s
        for s in "${MAP_SECTIONS[@]}"; do [[ "$title" == "$s" ]] && known=true; done
        if [[ "$known" == true ]]; then
            violations+=("$FILE:$ln: '## $title' is out of order or repeated; the sections are, in order: ${MAP_SECTIONS[*]/#/## }")
        else
            violations+=("$FILE:$ln: '## $title' is not a map section; a map doc has exactly Destination, Decisions so far, Not yet specified and Out of scope (then an optional Closed), and carries no execution instructions")
        fi
    done < <(_md_h2_list)
    if [[ $idx -lt ${#MAP_SECTIONS[@]} ]]; then
        local i
        for (( i = idx; i < ${#MAP_SECTIONS[@]}; i++ )); do
            grep -qxF "## ${MAP_SECTIONS[$i]}" -- "$FILE" || violations+=("missing section '## ${MAP_SECTIONS[$i]}' (see grimoires/loa/sdd.md §4.2)")
        done
    fi
    [[ -n "$(_md_section_body "Destination")" ]] || violations+=("'## Destination' is empty; state what is true when the effort is done (three sentences at most)")

    local bullet
    while IFS= read -r bullet; do
        [[ -n "$bullet" ]] || continue
        [[ "$bullet" =~ ^[[:space:]]*[-*][[:space:]] ]] || continue
        [[ "$bullet" =~ DEC-[0-9]{4,} ]] || violations+=("a 'Decisions so far' bullet cites no DEC row: '${bullet:0:120}'; the form is '- <name> (DEC-NNNN, <bead-id>): <one line>'")
    done < <(_md_section_body "Decisions so far")

    _md_prose_rules "cite a repo path or a grimoires/loa/research/ report instead"
    _md_pii_scan "a map doc is tracked state, remove them"

    [[ -n "$epic" && "$epic" =~ $BEAD_ID_RE ]] || return 0
    if ! _beads_crosscheck_available; then
        warnings+=("beads cross-check skipped (needs br, ${PROJECT_ROOT}/.beads and the map inside the project): the children of $epic were not checked")
        return 0
    fi
    _validate_map_beads "$epic" "$status" "$slug"
}

# @guard validator:map.beads
_validate_map_beads() {
    local epic="$1" status="$2" slug="$3" epic_json all
    if ! epic_json="$(_br_json_array show "$epic" --json)" || [[ "$(jq 'length' <<< "$epic_json" 2>/dev/null)" != "1" ]]; then
        warnings+=("map epic $epic was not found in beads; repair the '**Epic**:' line or create the epic with /chart")
        return 0
    fi
    if ! all="$(_br_json_array list --all --limit 0 --json)"; then
        warnings+=("br list failed; the children of $epic were not checked")
        return 0
    fi
    local ledger="${LEDGER_FILE:-${PROJECT_ROOT}/grimoires/loa/decisions.yaml}" ids="[]"
    if [[ -f "$ledger" ]] && _dec_have_yq4; then
        ids="$(yq -o=json -I0 '.' "$ledger" 2>/dev/null | jq -c '[(.decisions // [])[] | objects | .id]' 2>/dev/null || echo null)"
    else
        ids="null"
        info_lines+=("decision ledger unreadable (${ledger}; needs the file and yq v4): child external_ref values were checked for shape only")
    fi
    local out
    out="$(jq -rn --argjson ep "$epic_json" --argjson all "$all" --argjson ids "$ids" --arg epic "$epic" '
        def labels: [(.labels // [])[] | if type == "object" then (.name // "") else tostring end];
        ($ep[0]) as $e
        | ("S\t\($e.status // "")"),
          (if ($e | labels | any(. == "map")) then empty else "W\t\($epic) has no map label; a map epic carries the label map" end),
          ($all[]
           | select(.id != $epic)
           | select(([(.dependencies // [])[] | select((.type // .dependency_type // "") == "parent-child") | (.depends_on_id // "")] | index([$epic]) != null)
                    or (labels | index(["epic:" + $epic]) != null))
           | . as $c
           | (labels) as $l
           | ([$l[] | select(startswith("decision:"))]) as $dl
           | (if (.issue_type // "") != "question" then "V\t\(.id) is a \(.issue_type // "untyped") bead under map epic \($epic); a map holds question beads only" else empty end),
             (if ($dl | length) != 1 then "V\t\(.id) carries \($dl | length) decision: labels; a ticket carries exactly one of decision:grilling, decision:prototype, decision:research, decision:unblock" else empty end),
             ($dl[] | select(IN("decision:grilling", "decision:prototype", "decision:research", "decision:unblock") | not) | "V\t\($c.id) carries \(.); the four decision labels are decision:grilling, decision:prototype, decision:research, decision:unblock"),
             ($l[] | select(startswith("sprint:")) | "V\t\($c.id) carries \(.); decision tickets never join a sprint"),
             (($c.external_ref // "") as $x
              | if ($x | test("^DEC-[0-9]{4,}$")) | not then "V\t\($c.id) has external_ref \"\($x)\"; a ticket points at its ledger row (br update \($c.id) --external-ref DEC-NNNN)"
                elif $ids != null and ($ids | index([$x]) == null) then "V\t\($c.id) points at \($x), which is not in the decision ledger"
                else empty end))
    ' 2>/dev/null)" || { warnings+=("could not read the beads replies for $epic; the children were not checked"); return 0; }
    local kind msg epic_status=""
    while IFS=$'\t' read -r kind msg; do
        case "$kind" in
            S) epic_status="$msg" ;;
            W) warnings+=("$msg") ;;
            V) violations+=("$msg") ;;
        esac
    done <<< "$out"
    # The doc wins for phase detection; a disagreement is repaired, not fatal.
    case "$status" in
        charting|handed-off)
            [[ "$epic_status" == "closed" ]] && warnings+=("map Status is $status but epic $epic is closed; phase detection follows the doc: run /chart close ${slug} --reason <why>, or br reopen $epic") ;;
        closed|abandoned)
            [[ -n "$epic_status" && "$epic_status" != "closed" ]] && warnings+=("map Status is $status but epic $epic is $epic_status; phase detection follows the doc: run br close $epic --reason \"map ${status}\"") ;;
    esac
    return 0
}

# =============================================================================
# spike: a prototype report (grimoires/loa/sdd.md D-5.5, §4.4)
# =============================================================================
SPIKE_SECTIONS=("Question" "What was built" "Verdict" "Pointer" "Decided by")

# @guard validator:spike.sections
validate_spike() {
    local s body
    for s in "${SPIKE_SECTIONS[@]}"; do
        if ! _md_h2_list | cut -f2 | grep -qxF "$s"; then
            violations+=("missing section '## $s' (see grimoires/loa/spikes/TEMPLATE.md)")
            continue
        fi
        body="$(_md_section_body "$s")"
        [[ -n "$body" ]] || violations+=("'## $s' is empty; a spike report fills all five sections (see grimoires/loa/spikes/TEMPLATE.md)")
    done
    local verdict_lines
    verdict_lines="$(_md_section_body "Verdict" | wc -l | tr -d ' ')"
    [[ "${verdict_lines:-0}" -le 1 ]] || warnings+=("'## Verdict' has ${verdict_lines} lines; the verdict is one line, the reasoning goes in 'What was built'")
    body="$(_md_section_body "Pointer")"
    if [[ -n "$body" ]] && ! grep -qE '(^|[^[:alnum:]_])spike/[^[:space:]`]+|[[:alnum:]_.{}-]+/[[:alnum:]_.{}/-]+' <<< "$body"; then
        violations+=("'## Pointer' names neither a spike/<slug> branch nor a path; give the branch and commit, or the path of what was built")
    fi
    body="$(_md_section_body "Decided by")"
    if [[ -n "$body" ]]; then
        grep -qiE '(^|[^[:alnum:]_])(operator|agent)([^[:alnum:]_]|$)' <<< "$body" \
            || violations+=("'## Decided by' names neither operator nor agent")
        grep -qE 'DEC-[0-9]{4,}' <<< "$body" \
            || warnings+=("'## Decided by' cites no DEC row; the verdict row is written with dec-write-lib.sh decide and cited here (DEC-NNNN)")
    fi
    local branch
    branch="$(_md_header Branch)"
    if [[ -n "$branch" && ! "$branch" =~ (^|[^[:alnum:]_])spike/ ]]; then
        violations+=("**Branch** '$branch' is not a spike/<slug> branch")
    fi
    local cur
    cur="$(git -C "$(dirname -- "$FILE")" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    case "$cur" in
        spike/*) warnings+=("this checkout is on $cur; the spike report and its DEC row are committed on the working branch, never on a spike branch") ;;
    esac
    _md_prose_rules "point at the spike branch or a repo path instead"
    _md_pii_scan "a spike report is tracked state, remove them"
}

# =============================================================================
# glossary: the framework or a project glossary (grimoires/loa/sdd.md D-6.4, §4.5)
# =============================================================================
GLOSSARY_MAX_CHARS=300
GLOSSARY_MAX_ALIASES=6
GLOSSARY_MAX_ALIASES_TOTAL=40

# @guard validator:glossary.entries
validate_glossary() {
    local kind msg fence_src
    # The CommonMark fence tracker shared with tools/check-glossary-terms.sh.
    if ! fence_src="$(cat "${SCRIPT_DIR}/lib/md-fence.awk" 2>/dev/null)" || [[ -z "$fence_src" ]]; then
        violations+=("cannot read ${SCRIPT_DIR}/lib/md-fence.awk; the glossary check needs it (reinstall the framework scripts)")
        return
    fi
    while IFS=$'\t' read -r kind msg; do
        case "$kind" in
            V) violations+=("$msg") ;;
            W) warnings+=("$msg") ;;
        esac
    done < <(LC_ALL=C awk -v f="$FILE" -v max="$GLOSSARY_MAX_CHARS" -v maxal="$GLOSSARY_MAX_ALIASES" -v maxtotal="$GLOSSARY_MAX_ALIASES_TOTAL" "$fence_src"'
        function v(m) { printf "V\t%s:%d: %s\n", f, NR, m }
        function w(m) { printf "W\t%s:%d: %s\n", f, NR, m }
        # names compare as the drift check matches them: case and "-", "_", " " folded
        function norm(x) { x = tolower(x); gsub(/[-_ ]+/, " ", x); gsub(/^ | $/, "", x); return x }
        function claim(x, what) {
            if (x == "") return
            # norm() folds ASCII only, so a look-alike letter from another
            # script (Greek beta in "Beads") would pass the duplicate check
            if (x ~ /[\200-\377]/) w(what " \"" x "\" has a non-ASCII character; glossary names are ASCII so a look-alike letter cannot slip past the duplicate check")
            if (norm(x) in seen) v(what " \"" x "\" duplicates " seen[norm(x)] "; each term and alias names one entry")
            else seen[norm(x)] = what " \"" x "\" (line " NR ")"
        }
        # word sets: a name splits on case-folded "-", "_" and spaces, prose on
        # anything that is not a letter or digit; words under two characters drop
        function words(x, set,   n, i, parts) {
            split("", set); n = split(x, parts, / /)
            for (i = 1; i <= n; i++) if (length(parts[i]) >= 2) set[parts[i]] = 1
        }
        function plural_eq(a, b) { return a == b || a "s" == b || a "es" == b || b "s" == a || b "es" == a }
        # An alias names the same thing as its entry, so it shares a word with
        # the term or the definition, or it is the initials of the term
        # ("KF" for Known failure); anything else is a name the entry never explains.
        function alias_related(al, term, def,   aw, tw, x, y, ini, n, i, parts) {
            words(norm(al), aw)
            words(norm(term), tw)
            for (x in aw) for (y in tw) if (plural_eq(x, y)) return 1
            def = tolower(def); gsub(/[^a-z0-9]+/, " ", def); words(def, tw)
            for (x in aw) for (y in tw) if (plural_eq(x, y)) return 1
            n = split(norm(term), parts, / /); ini = ""
            for (i = 1; i <= n; i++) ini = ini substr(parts[i], 1, 1)
            x = norm(al); gsub(/ /, "", x)
            return n >= 2 && x == ini
        }
        md_fence($0) { prev = "other"; next }
        /^# / {
            if (!h1) { h1 = NR; if ($0 !~ /^# Glossary: [^[:space:]]/) w("the H1 is not \"# Glossary: <name>\"") }
            prev = "other"; next
        }
        /^## / {
            hd = $0; sub(/^## +/, "", hd); sub(/[[:space:]]+$/, "", hd)
            if (hd == "Language") { if (lang_line) v("a second \"## Language\" section (the first is on line " lang_line ")"); else lang_line = NR; lang = 1 }
            else lang = 0
            prev = "other"; next
        }
        !lang_line && h1 && $0 ~ /[^[:space:]]/ { context = 1 }
        !lang { prev = ($0 ~ /[^[:space:]]/) ? "other" : "blank"; next }
        $0 !~ /[^[:space:]]/ { prev = "blank"; next }
        /^### / { prev = "other"; next }
        {
            if ($0 ~ /(^|[^A-Za-z0-9_])[A-Za-z0-9_.~-]+\/[A-Za-z0-9_.-]/ || $0 ~ /\.(md|sh|bash|py|ts|js|json|jsonl|yaml|yml|toml|txt|bats|lock)([^A-Za-z0-9]|$)/)
                w("a path or file extension; glossary definitions are implementation-free")
        }
        /^\*\*[^*]+\*\*: [^[:space:]]/ {
            entries++
            t = $0; sub(/^\*\*/, "", t); sub(/\*\*: .*$/, "", t); gsub(/`/, "", t); gsub(/^[[:space:]]+|[[:space:]]+$/, "", t)
            claim(t, "term")
            d = $0; sub(/^\*\*[^*]+\*\*: /, "", d); sub(/[[:space:]]+$/, "", d)
            c = d; gsub(/[\200-\277]/, "", c)   # count characters, not UTF-8 continuation bytes
            if (length(c) > max) v("the definition of \"" t "\" is " length(c) " characters, over " max "; shorten it")
            s = d " "; n = gsub(/[.!?]+[)"]*[[:space:]]/, "&", s); if (n == 0) n = 1
            if (n > 2) v("the definition of \"" t "\" has " n " sentences; at most two")
            prev = "entry"; seen_avoid = 0; seen_alias = 0; n_alias = 0; next
        }
        /^_(Avoid|Aliases)_:/ {
            k = ($0 ~ /^_Avoid_:/) ? "Avoid" : "Aliases"
            if (prev != "entry" && prev != "annot") { v("_" k "_: is not directly after an entry; put it on the line below the **Term**: line"); prev = "other"; next }
            if ((k == "Avoid" && seen_avoid) || (k == "Aliases" && seen_alias)) v("a second _" k "_: line for \"" t "\"; merge them")
            if (k == "Avoid") seen_avoid = 1; else seen_alias = 1
            a = $0; sub(/^_(Avoid|Aliases)_:[[:space:]]*/, "", a)
            if (a !~ /[^[:space:]]/) v("an empty _" k "_: line")
            if (k == "Aliases") {
                gsub(/`/, "", a); m = split(a, parts, /,/)
                for (i = 1; i <= m; i++) {
                    p = parts[i]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", p)
                    if (p == "") continue
                    n_alias++; total_alias++
                    claim(p, "alias")
                    if (!alias_related(p, t, d)) w("alias \"" p "\" of \"" t "\" shares no word with the term or its definition and is not its initials; name it in the definition, or give it its own entry")
                }
                if (n_alias > maxal) v("\"" t "\" has " n_alias " aliases, over " maxal "; an alias list is not a place to resolve tokens, so define the extra names as entries or allowlist the code identifiers")
            }
            prev = "annot"; next
        }
        /^\*\*[^*]+\*\*:/ { v("an entry needs \"**Term**: definition\" with a space and text after the colon"); prev = "other"; next }
        { v("a line in \"## Language\" that is not an entry, an _Avoid_:/_Aliases_: line or a ### heading; a definition stays on its entry line"); prev = "other" }
        END {
            NR = 1
            if (!h1) v("no H1; start with \"# Glossary: <name>\"")
            if (total_alias > maxtotal) v("the glossary has " total_alias " aliases, over the budget of " maxtotal "; an alias names the same thing as its entry, so define distinct names as entries")
            if (!lang_line) v("no \"## Language\" section")
            else {
                if (!context) v("no context paragraph between the H1 and \"## Language\"; say whose language this is in one paragraph")
                if (!entries) v("\"## Language\" has no **Term**: entries")
            }
        }
    ' "$FILE")
    _md_pii_scan "a glossary is tracked prose, remove them"
}

case "$TYPE" in
    prd) validate_prd ;;
    sdd) validate_sdd ;;
    sprint) validate_sprint ;;
    bug-triage) validate_bug_triage ;;
    translation) validate_translation ;;
    decisions) validate_decisions ;;
    map) validate_map ;;
    spike) validate_spike ;;
    glossary) validate_glossary ;;
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
