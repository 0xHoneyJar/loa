#!/usr/bin/env bash
# =============================================================================
# migrate-skill-roles.sh — Cycle-108 T1.A skill-role migration
# =============================================================================
# Adds `role:` (and `primary_role:` for multi-role) frontmatter to every
# SKILL.md per SDD §4.3 classification rules. Designed to land in ONE
# atomic commit alongside the schema enum seed (T1.A acceptance).
#
# Classification rules (SDD §4.3, deterministic):
#   1. planning pattern  -> role: planning
#   2. review pattern    -> role: review
#   3. implementation    -> role: implementation
#   4. multi-role        -> role: review, primary_role: review (advisor-wins)
#   5. unmatched         -> role: implementation (cheapest tier acceptable
#                           for utility skills per SDD §4.3 row 5)
#
# Modes:
#   --dry-run    Print classification table; do NOT modify files
#   --apply      Modify SKILL.md files (idempotent — skips files that already
#                have a `role:` field)
#   --emit-enum  Print the audited_review_skills enum (review-class skills
#                excluding multi-role) for schema seeding
#
# Cycle-108 sprint-1 T1.A. Required by T1.D validator (LOA_VALIDATE_ROLE=1).
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
SKILLS_DIR="${SKILLS_DIR:-$PROJECT_ROOT/.claude/skills}"

source "$SCRIPT_DIR/yq-safe.sh"

# --- CLI ----------------------------------------------------------------------
MODE="dry-run"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)    MODE="dry-run"; shift ;;
        --apply)      MODE="apply"; shift ;;
        --emit-enum)  MODE="emit-enum"; shift ;;
        -h|--help)
            cat <<EOF
Usage: migrate-skill-roles.sh [--dry-run | --apply | --emit-enum]

  --dry-run    Print classification table; do not modify files (DEFAULT)
  --apply      Modify SKILL.md files (idempotent)
  --emit-enum  Print the audited_review_skills enum for schema seeding

Cycle-108 sprint-1 T1.A. See grimoires/loa/cycles/cycle-108-advisor-strategy/sdd.md §4.3.
EOF
            exit 0
            ;;
        *) echo "Unknown arg: $1" >&2; exit 2 ;;
    esac
done

# --- Skip-list (mirrors validate-skill-capabilities.sh::SKIP_SKILLS) ----------
SKIP_SKILLS=("flatline-reviewer" "flatline-scorer" "flatline-skeptic" "gpt-reviewer")

should_skip() {
    local name="$1"
    for skip in "${SKIP_SKILLS[@]}"; do
        [[ "$name" == "$skip" ]] && return 0
    done
    return 1
}

# --- Classification rules (SDD §4.3) ------------------------------------------
# Order matters: first match wins. Multi-role pattern checked first because
# advisor-wins-ties demands they get the most-restrictive role.

# Multi-role skills: get role=review (advisor-wins-ties)
MULTI_ROLE_PATTERN='^(run-bridge|spiraling|run|run-mode|run-resume|run-halt|loa|compound|autonomous|autonomous-agent)$'

# Planning skills
PLANNING_PATTERN='^(plan-and-analyze|architect|sprint-plan|discovering-requirements|designing-architecture|planning-sprints|riding-codebase|loa-setup|mounting-framework)$'

# Review skills (NOT multi-role): these populate audited_review_skills enum
REVIEW_PATTERN='^(review-sprint|audit-sprint|reviewing-code|auditing-security|bridgebuilder-review|flatline-review|red-team|red-teaming|gpt-review|post-pr-validation|rtfm-testing|validating-construct-manifest|eval-running|flatline-attacker|flatline-knowledge)$'

# Implementation skills
IMPLEMENTATION_PATTERN='^(implement|implementing-tasks|bug|bug-triaging|simstim|simstim-workflow|continuous-learning|build|deploying-infrastructure|managing-credentials|enhancing-prompts|translating-for-executives|butterfreezone-gen|browsing-constructs|soul-identity-doc|cost-budget-enforcer|cross-repo-status-reader|graduated-trust|hitl-jury-panel|scheduled-cycle-template|structured-handoff)$'

classify_skill() {
    local name="$1"
    if [[ "$name" =~ $MULTI_ROLE_PATTERN ]]; then
        echo "review:multi-role"
        return 0
    fi
    if [[ "$name" =~ $PLANNING_PATTERN ]]; then
        echo "planning:single"
        return 0
    fi
    if [[ "$name" =~ $REVIEW_PATTERN ]]; then
        echo "review:single"
        return 0
    fi
    if [[ "$name" =~ $IMPLEMENTATION_PATTERN ]]; then
        echo "implementation:single"
        return 0
    fi
    # Default fallback per SDD §4.3 row 5
    echo "implementation:default"
}

# --- Frontmatter operations ---------------------------------------------------
has_role_field() {
    local skill_md="$1"
    local frontmatter
    frontmatter=$(awk '/^---$/{if(n++) exit; next} n' "$skill_md") || frontmatter=""
    [[ -z "$frontmatter" ]] && return 1
    local role
    role=$(echo "$frontmatter" | yq eval '.role // ""' - 2>/dev/null) || role=""
    [[ -n "$role" ]]
}

# Insert role: (and primary_role: if multi-role) into the frontmatter block.
# Strategy: insert immediately AFTER the `description:` field (preferred) or
# right after the opening `---` line if no description.
insert_role_fields() {
    local skill_md="$1"
    local role="$2"
    local primary_role="$3"  # empty string = single-role; non-empty = multi-role

    # Build the field-insertion block
    local insert_block="role: $role"
    if [[ -n "$primary_role" ]]; then
        insert_block="$insert_block"$'\n'"primary_role: $primary_role"
    fi

    # Try to insert after `description:` first
    # We need to find the `description:` line BEFORE the closing `---` of frontmatter.
    local desc_line frontmatter_end
    frontmatter_end=$(awk '/^---$/{n++; if(n==2){print NR; exit}}' "$skill_md")
    if [[ -z "$frontmatter_end" ]]; then
        echo "WARN: $skill_md has no closing frontmatter --- (skipping migration; add frontmatter manually)" >&2
        return 2  # distinct from hard error
    fi

    desc_line=$(awk -v end="$frontmatter_end" 'NR>1 && NR<end && /^description:/{print NR; exit}' "$skill_md")

    local insert_after
    if [[ -n "$desc_line" ]]; then
        insert_after="$desc_line"
    else
        # No description: — insert immediately after the opening `---` (line 1)
        insert_after=1
    fi

    # Use awk for atomic in-place insertion
    awk -v line="$insert_after" -v block="$insert_block" '
        { print }
        NR == line { print block }
    ' "$skill_md" > "$skill_md.tmp" && mv "$skill_md.tmp" "$skill_md"
}

# --- Main loop ---------------------------------------------------------------
declare -A classification_table
declare -A primary_role_table
audited_review_skills=()

for skill_dir in "$SKILLS_DIR"/*/; do
    [[ -d "$skill_dir" ]] || continue
    skill_name=$(basename "$skill_dir")
    skill_md="$skill_dir/SKILL.md"

    [[ -f "$skill_md" ]] || continue
    if should_skip "$skill_name"; then continue; fi

    classification=$(classify_skill "$skill_name")
    role="${classification%%:*}"
    flavor="${classification##*:}"

    classification_table["$skill_name"]="$role:$flavor"

    # Build audited_review_skills enum: ONLY single-role review skills
    # (multi-role review skills are NOT eligible for audit-tier; they need
    # narrower scrutiny — operator approves via schema PR per SDD §3.7).
    if [[ "$role" == "review" && "$flavor" == "single" ]]; then
        audited_review_skills+=("$skill_name")
    fi

    # primary_role:
    # - multi-role review skills get primary_role: review (advisor-wins-ties)
    # - single-role skills do NOT need primary_role (omitted)
    if [[ "$flavor" == "multi-role" ]]; then
        primary_role_table["$skill_name"]="review"
    fi
done

case "$MODE" in
    dry-run)
        printf "%-40s %-16s %-12s %s\n" "SKILL" "ROLE" "FLAVOR" "PRIMARY_ROLE"
        printf "%-40s %-16s %-12s %s\n" "$(printf '=%.0s' {1..40})" "$(printf '=%.0s' {1..16})" "$(printf '=%.0s' {1..12})" "$(printf '=%.0s' {1..16})"
        for skill in $(echo "${!classification_table[@]}" | tr ' ' '\n' | sort); do
            role_flavor="${classification_table[$skill]}"
            role="${role_flavor%%:*}"
            flavor="${role_flavor##*:}"
            primary="${primary_role_table[$skill]:-}"
            printf "%-40s %-16s %-12s %s\n" "$skill" "$role" "$flavor" "$primary"
        done
        echo ""
        echo "Audited review skills (will seed schema enum):"
        for s in "${audited_review_skills[@]}"; do
            echo "  - $s"
        done
        ;;

    apply)
        modified=0
        skipped=0
        no_frontmatter=()
        for skill in "${!classification_table[@]}"; do
            skill_md="$SKILLS_DIR/$skill/SKILL.md"
            role_flavor="${classification_table[$skill]}"
            role="${role_flavor%%:*}"
            primary="${primary_role_table[$skill]:-}"

            if has_role_field "$skill_md"; then
                skipped=$((skipped + 1))
                continue
            fi

            if insert_role_fields "$skill_md" "$role" "$primary"; then
                modified=$((modified + 1))
            else
                # Return code 2 = no frontmatter (warn-and-skip)
                if [[ "$?" -eq 2 ]]; then
                    no_frontmatter+=("$skill")
                fi
            fi
        done
        echo "Migration complete: $modified modified, $skipped already-had-role"
        if [[ ${#no_frontmatter[@]} -gt 0 ]]; then
            echo ""
            echo "WARNING: ${#no_frontmatter[@]} skills have no frontmatter and were SKIPPED:"
            for s in "${no_frontmatter[@]}"; do
                echo "  - $s (.claude/skills/$s/SKILL.md needs frontmatter block manually)"
            done
        fi
        ;;

    emit-enum)
        # Output as a JSON array suitable for schema-injection
        printf '['
        for i in "${!audited_review_skills[@]}"; do
            [[ "$i" -gt 0 ]] && printf ', '
            printf '"%s"' "${audited_review_skills[$i]}"
        done
        printf ']\n'
        ;;
esac
