#!/usr/bin/env bash
# =============================================================================
# validate-skill-capabilities.sh — Validate skill capabilities + cost profiles
# =============================================================================
# Checks all SKILL.md files for:
# - capabilities: field presence (deny-all if missing)
# - schema_version: 1
# - capabilities vs allowed-tools consistency (SDD §3.3)
# - No capabilities: all sentinel (Flatline SKP-003)
# - Strict execute_commands grammar (Flatline IMP-003/SKP-004)
# - cost-profile: field presence and valid values
# - cost-profile vs capabilities correlation (SDD §3.4)
#
# Part of cycle-050: Multi-Model Permission Architecture
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
SKILLS_DIR="${SKILLS_DIR:-$PROJECT_ROOT/.claude/skills}"

# Source safe yq
# shellcheck source=yq-safe.sh
source "$SCRIPT_DIR/yq-safe.sh"

# --- CLI flags ---
STRICT=false
JSON_OUTPUT=false
SINGLE_SKILL=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --strict) STRICT=true; shift ;;
        --json) JSON_OUTPUT=true; shift ;;
        --skill) SINGLE_SKILL="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: validate-skill-capabilities.sh [--strict] [--json] [--skill NAME]"
            echo "  --strict   Promote warnings to errors"
            echo "  --json     Output as JSON"
            echo "  --skill    Validate single skill"
            exit 0
            ;;
        *) echo "Unknown arg: $1" >&2; exit 2 ;;
    esac
done

# --- Internal sub-skills to skip ---
SKIP_SKILLS=("flatline-reviewer" "flatline-scorer" "flatline-skeptic" "gpt-reviewer")

# --- Cycle-108 T1.D: role/primary_role validation constants ---
# Valid role enum (PRD §5 FR-3, SDD §4.1)
VALID_ROLES=("planning" "review" "implementation")

# Review-class keywords for heuristic linter (SDD §20.5 ATK-A13)
# Skills declaring role: review|audit MUST have >=2 of these in body
REVIEW_CLASS_KEYWORDS=(
    "review" "audit" "validate" "verify" "score"
    "consensus" "adversarial" "inspect" "findings" "regression"
)
REVIEW_KEYWORD_MIN=2

# Advisor-wins-ties tiebreaker (SDD §4.1, IMP-012):
# When primary_role != role, only these downgrades are permitted (most-restrictive wins).
# review beats planning beats implementation. Permitted primary_role:role pairs:
ADVISOR_WINS_PAIRS=(
    "review:planning"
    "review:implementation"
    "planning:implementation"
)

should_skip() {
    local name="$1"
    for skip in "${SKIP_SKILLS[@]}"; do
        [[ "$name" == "$skip" ]] && return 0
    done
    return 1
}

# --- Agent types that include Write/Edit in their tool allowlist (Issue #553) ---
# When a skill declares write capability (capabilities.write_files: true OR
# allowed-tools lists Write/Edit), its agent: frontmatter key MUST be unset
# or set to one of these. See .claude/rules/skill-invariants.md.
WRITE_CAPABLE_AGENTS=("general-purpose")

is_write_capable_agent() {
    local agent="$1"
    for a in "${WRITE_CAPABLE_AGENTS[@]}"; do
        [[ "$agent" == "$a" ]] && return 0
    done
    return 1
}

# --- Cycle-108 T1.D helpers ---

is_valid_role() {
    local role="$1"
    for r in "${VALID_ROLES[@]}"; do
        [[ "$role" == "$r" ]] && return 0
    done
    return 1
}

is_permitted_role_pair() {
    # Args: primary_role role
    # Returns 0 if the (primary_role:role) combination is allowed under advisor-wins-ties
    local pair="$1:$2"
    for p in "${ADVISOR_WINS_PAIRS[@]}"; do
        [[ "$pair" == "$p" ]] && return 0
    done
    return 1
}

count_review_keywords_in_body() {
    # Count occurrences of review-class keywords in the SKILL.md body (after frontmatter)
    # Args: path-to-SKILL.md
    # Output: integer count of UNIQUE keywords matched
    local skill_md="$1"
    local body
    # Strip first frontmatter block to get body
    body=$(awk '/^---$/{n++; next} n>=2' "$skill_md")
    if [[ -z "$body" ]]; then
        echo 0
        return 0
    fi
    local hits=0
    for kw in "${REVIEW_CLASS_KEYWORDS[@]}"; do
        # Word-boundary, case-insensitive match
        if echo "$body" | grep -qiwF "$kw"; then
            hits=$((hits + 1))
        fi
    done
    echo "$hits"
}

has_review_exempt_comment() {
    # Returns 0 if SKILL.md body contains a # REVIEW-EXEMPT: comment
    local skill_md="$1"
    grep -qE '^[[:space:]]*#[[:space:]]*REVIEW-EXEMPT:[[:space:]]+\S+' "$skill_md"
}

has_role_change_authorization() {
    # Returns 0 if SKILL.md body contains a valid # ROLE-CHANGE-AUTHORIZED-BY: comment.
    # Format: # ROLE-CHANGE-AUTHORIZED-BY: <operator> ON <YYYY-MM-DD>
    local skill_md="$1"
    grep -qE '^[[:space:]]*#[[:space:]]*ROLE-CHANGE-AUTHORIZED-BY:[[:space:]]+\S+[[:space:]]+ON[[:space:]]+[0-9]{4}-[0-9]{2}-[0-9]{2}' "$skill_md"
}

# Reads previous role from git for diff-aware role-change rule.
# Output: previous role value, or empty string if file is untracked / no prior role.
previous_role_from_git() {
    local skill_md="$1"
    # Only attempt git lookup if we're inside a git repo
    if ! git -C "$PROJECT_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
        echo ""
        return 0
    fi
    # If file is untracked (first commit), no previous role exists
    if ! git -C "$PROJECT_ROOT" ls-files --error-unmatch "$skill_md" >/dev/null 2>&1; then
        echo ""
        return 0
    fi
    # Extract previous role from HEAD version of the file
    local prev_content prev_role
    prev_content=$(git -C "$PROJECT_ROOT" show "HEAD:$skill_md" 2>/dev/null) || prev_content=""
    if [[ -z "$prev_content" ]]; then
        echo ""
        return 0
    fi
    local prev_frontmatter
    prev_frontmatter=$(echo "$prev_content" | awk '/^---$/{if(n++) exit; next} n')
    prev_role=$(echo "$prev_frontmatter" | yq eval '.role // ""' - 2>/dev/null) || prev_role=""
    echo "$prev_role"
}

# Cycle-108 T1.D: validate role/primary_role/review-keyword/diff-aware rules
# Args: skill_name skill_md frontmatter
# Returns 0 if all checks pass; sets has_error=true in caller scope on failure
# (mirrors the rest of this script's error-propagation convention).
validate_skill_role() {
    local skill_name="$1"
    local skill_md="$2"
    local frontmatter="$3"

    local role primary_role
    role=$(echo "$frontmatter" | yq eval '.role // ""' - 2>/dev/null) || role=""
    primary_role=$(echo "$frontmatter" | yq eval '.primary_role // ""' - 2>/dev/null) || primary_role=""

    # 1. role field is REQUIRED
    if [[ -z "$role" || "$role" == "null" ]]; then
        log_error "$skill_name" "Missing required 'role' field (one of: ${VALID_ROLES[*]}) — cycle-108 T1.D"
        return 1
    fi

    # 2. role is a valid enum value
    if ! is_valid_role "$role"; then
        log_error "$skill_name" "Invalid role '$role' (must be one of: ${VALID_ROLES[*]}) — cycle-108 T1.D"
        return 1
    fi

    # 3. primary_role consistency check (advisor-wins-ties)
    if [[ -n "$primary_role" && "$primary_role" != "null" ]]; then
        if ! is_valid_role "$primary_role"; then
            log_error "$skill_name" "Invalid primary_role '$primary_role' (must be one of: ${VALID_ROLES[*]}) — cycle-108 T1.D"
            return 1
        fi
        # primary_role == role is always fine
        if [[ "$primary_role" != "$role" ]]; then
            # Disagreement permitted only under advisor-wins-ties rule
            if ! is_permitted_role_pair "$primary_role" "$role"; then
                log_error "$skill_name" "primary_role '$primary_role' does not satisfy advisor-wins-ties rule against role '$role' (permitted: ${ADVISOR_WINS_PAIRS[*]}) — cycle-108 T1.D"
                return 1
            fi
        fi
    fi

    # 4. Heuristic linter for role=review skills (ATK-A13)
    # (SDD §20.5: role: review|audit must have >=2 review-class keywords in body
    # unless REVIEW-EXEMPT magic comment is present.)
    if [[ "$role" == "review" ]]; then
        if ! has_review_exempt_comment "$skill_md"; then
            local kw_count
            kw_count=$(count_review_keywords_in_body "$skill_md")
            if [[ "$kw_count" -lt "$REVIEW_KEYWORD_MIN" ]]; then
                # Soft warning per SDD §20.5 step 1 (failure produces a soft warning unless REVIEW-EXEMPT)
                log_warning "$skill_name" "role: review but body has only $kw_count review-class keyword(s) (>=$REVIEW_KEYWORD_MIN expected from: ${REVIEW_CLASS_KEYWORDS[*]}). Add '# REVIEW-EXEMPT: <rationale>' to opt out. — cycle-108 T1.D" || return 1
            fi
        fi
    fi

    # 5. Diff-aware role-change rule (SDD §20.10 ATK-A2 + §4.2 step 3)
    # When role: changes on an existing SKILL.md (detected via git), require
    # # ROLE-CHANGE-AUTHORIZED-BY: <operator> ON <YYYY-MM-DD> comment.
    # In particular: review|audit -> implementation transitions MUST be co-signed.
    local prev_role
    prev_role=$(previous_role_from_git "$skill_md")
    if [[ -n "$prev_role" && "$prev_role" != "$role" ]]; then
        # Role change detected — check authorization
        if ! has_role_change_authorization "$skill_md"; then
            # Stricter for downgrades from review/audit
            if [[ "$prev_role" == "review" && "$role" != "review" ]]; then
                log_error "$skill_name" "role changed from '$prev_role' to '$role' without '# ROLE-CHANGE-AUTHORIZED-BY: <operator> ON <YYYY-MM-DD>' comment (cycle-108 T1.D ATK-A2: review->non-review downgrade requires explicit co-sign)"
                return 1
            else
                # Softer warning for other changes
                log_warning "$skill_name" "role changed from '$prev_role' to '$role' without '# ROLE-CHANGE-AUTHORIZED-BY: <operator> ON <YYYY-MM-DD>' comment — cycle-108 T1.D" || return 1
            fi
        fi
    fi

    return 0
}

# --- Counters ---
total=0
errors=0
warnings=0
passed=0
results_json="[]"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_error() {
    local skill="$1" msg="$2"
    errors=$((errors + 1))
    if [[ "$JSON_OUTPUT" == "false" ]]; then
        echo -e "  ${RED}ERROR${NC}: $msg"
    fi
    results_json=$(echo "$results_json" | jq --arg s "$skill" --arg m "$msg" '. + [{"skill": $s, "level": "error", "message": $m}]')
}

log_warning() {
    local skill="$1" msg="$2"
    if [[ "$STRICT" == "true" ]]; then
        log_error "$skill" "$msg (strict: promoted from warning)"
        return 1  # Signal to caller that this became an error
    fi
    warnings=$((warnings + 1))
    if [[ "$JSON_OUTPUT" == "false" ]]; then
        echo -e "  ${YELLOW}WARN${NC}: $msg"
    fi
    results_json=$(echo "$results_json" | jq --arg s "$skill" --arg m "$msg" '. + [{"skill": $s, "level": "warning", "message": $m}]')
}

log_pass() {
    local skill="$1"
    passed=$((passed + 1))
    if [[ "$JSON_OUTPUT" == "false" ]]; then
        echo -e "  ${GREEN}PASS${NC}"
    fi
}

# --- Capability-to-tool mapping (SDD §3.3) ---
# Returns 0 if tool is in allowed-tools
has_tool() {
    local allowed="$1" tool="$2"
    # Use word-boundary matching to prevent substring false positives
    # (e.g., "WriteConfig" should not match "Write")
    echo "$allowed" | grep -qiwF "$tool"
}

validate_skill() {
    local skill_dir="$1"
    local skill_name
    skill_name=$(basename "$skill_dir")
    local skill_md="$skill_dir/SKILL.md"

    if should_skip "$skill_name"; then
        return 0
    fi

    if [[ ! -f "$skill_md" ]]; then
        return 0
    fi

    total=$((total + 1))
    local has_error=false

    if [[ "$JSON_OUTPUT" == "false" ]]; then
        echo -n "[$skill_name] "
    fi

    # Extract frontmatter (first --- block only, not greedy)
    local frontmatter
    frontmatter=$(awk '/^---$/{if(n++) exit; next} n' "$skill_md") || frontmatter=""

    if [[ -z "$frontmatter" ]]; then
        log_error "$skill_name" "No frontmatter found"
        return 0
    fi

    # --- Check capabilities field ---
    local caps
    caps=$(echo "$frontmatter" | yq eval '.capabilities' - 2>/dev/null) || caps="null"

    if [[ "$caps" == "null" || -z "$caps" ]]; then
        log_error "$skill_name" "Missing capabilities field (deny-all default)"
        has_error=true
    elif [[ "$caps" == "all" ]]; then
        log_error "$skill_name" "capabilities: all sentinel prohibited (Flatline SKP-003) — use explicit expanded map"
        has_error=true
    else
        # Check schema_version
        local sv
        sv=$(echo "$frontmatter" | yq eval '.capabilities.schema_version' - 2>/dev/null) || sv="null"
        if [[ "$sv" == "null" || -z "$sv" ]]; then
            log_error "$skill_name" "Missing capabilities.schema_version"
            has_error=true
        elif [[ "$sv" != "1" ]]; then
            log_error "$skill_name" "Unknown capabilities.schema_version: $sv (expected: 1)"
            has_error=true
        fi

        # Check execute_commands format (strict grammar)
        local exec_cmds
        exec_cmds=$(echo "$frontmatter" | yq eval '.capabilities.execute_commands' - 2>/dev/null) || exec_cmds="null"
        if [[ "$exec_cmds" != "null" && "$exec_cmds" != "false" && "$exec_cmds" != "true" ]]; then
            # Should be an object with 'allowed' array
            local has_allowed
            has_allowed=$(echo "$frontmatter" | yq eval '.capabilities.execute_commands.allowed' - 2>/dev/null) || has_allowed="null"
            if [[ "$has_allowed" == "null" ]]; then
                # Check if it looks like old-style pattern list
                local first_pattern
                first_pattern=$(echo "$frontmatter" | yq eval '.capabilities.execute_commands[0].pattern // ""' - 2>/dev/null) || first_pattern=""
                if [[ -n "$first_pattern" ]]; then
                    log_error "$skill_name" "execute_commands uses raw pattern format — must use strict grammar (command + args)"
                    has_error=true
                fi
            fi
        fi
    fi

    # --- Check cost-profile ---
    local cp
    cp=$(echo "$frontmatter" | yq eval '.cost-profile' - 2>/dev/null) || cp="null"

    if [[ "$cp" == "null" || -z "$cp" ]]; then
        log_error "$skill_name" "Missing cost-profile field (deny default)"
        has_error=true
    else
        case "$cp" in
            lightweight|moderate|heavy|unbounded) ;; # valid
            *) log_error "$skill_name" "Invalid cost-profile: $cp (expected: lightweight|moderate|heavy|unbounded)"
               has_error=true ;;
        esac
    fi

    # --- Check capabilities vs allowed-tools consistency ---
    local allowed_tools
    allowed_tools=$(echo "$frontmatter" | yq eval '.allowed-tools // ""' - 2>/dev/null) || allowed_tools=""

    if [[ -n "$allowed_tools" && "$caps" != "null" && "$caps" != "all" ]]; then
        # Security check: capabilities.write_files: false but Write/Edit in allowed-tools → ERROR
        local write_cap
        write_cap=$(echo "$frontmatter" | yq eval '.capabilities.write_files' - 2>/dev/null) || write_cap="null"
        if [[ "$write_cap" == "false" ]]; then
            if has_tool "$allowed_tools" "Write" || has_tool "$allowed_tools" "Edit"; then
                log_error "$skill_name" "capabilities.write_files: false but Write/Edit in allowed-tools (security violation)"
                has_error=true
            fi
        fi

        # Warning: capabilities.write_files: true but no Write/Edit in allowed-tools → benign overestimate
        if [[ "$write_cap" == "true" ]]; then
            if ! has_tool "$allowed_tools" "Write" && ! has_tool "$allowed_tools" "Edit"; then
                log_warning "$skill_name" "capabilities.write_files: true but no Write/Edit in allowed-tools (overestimate)" || has_error=true
            fi
        fi

        # Security check: capabilities.web_access: false but WebFetch/WebSearch in allowed-tools → ERROR
        local web_cap
        web_cap=$(echo "$frontmatter" | yq eval '.capabilities.web_access' - 2>/dev/null) || web_cap="null"
        if [[ "$web_cap" == "false" ]]; then
            if has_tool "$allowed_tools" "WebFetch" || has_tool "$allowed_tools" "WebSearch"; then
                log_error "$skill_name" "capabilities.web_access: false but WebFetch/WebSearch in allowed-tools (security violation)"
                has_error=true
            fi
        fi
    fi

    # --- Cost-profile correlation check (SDD §3.4) ---
    if [[ "$cp" == "lightweight" && "$caps" != "null" && "$caps" != "all" ]]; then
        local wf
        wf=$(echo "$frontmatter" | yq eval '.capabilities.write_files' - 2>/dev/null) || wf="null"
        if [[ "$wf" == "true" ]]; then
            log_warning "$skill_name" "cost-profile: lightweight but capabilities.write_files: true (correlation mismatch)" || has_error=true
        fi
    fi

    # --- Agent type vs write-capability invariant (Issue #553) ---
    # When agent: is set to a restricted type (e.g. Plan, Explore) but the skill
    # declares write capability via capabilities.write_files: true OR allowed-tools
    # containing Write/Edit, the agent-type allowlist wins and silently blocks
    # the skill from persisting its output. See .claude/rules/skill-invariants.md.
    local agent_type
    agent_type=$(echo "$frontmatter" | yq eval '.agent' - 2>/dev/null) || agent_type="null"
    if [[ "$agent_type" != "null" && -n "$agent_type" ]] && ! is_write_capable_agent "$agent_type"; then
        local needs_write=false
        local wf_check
        wf_check=$(echo "$frontmatter" | yq eval '.capabilities.write_files' - 2>/dev/null) || wf_check="null"
        if [[ "$wf_check" == "true" ]]; then
            needs_write=true
        fi
        if [[ -n "$allowed_tools" ]] && { has_tool "$allowed_tools" "Write" || has_tool "$allowed_tools" "Edit"; }; then
            needs_write=true
        fi
        if [[ "$needs_write" == "true" ]]; then
            log_error "$skill_name" "agent type '$agent_type' excludes Write/Edit tools but skill declares write capability (capabilities.write_files: true or allowed-tools contains Write/Edit) — remove agent: key or use a write-capable agent type (${WRITE_CAPABLE_AGENTS[*]})"
            has_error=true
        fi
    fi

    # --- Cycle-108 T1.D: role/primary_role validation ---
    # Run only if cycle-108 role validation is opt-in (LOA_VALIDATE_ROLE=1)
    # OR if the skill already declares a role: field (forward-compat: once a
    # skill opts in, the validator enforces).
    local declared_role
    declared_role=$(echo "$frontmatter" | yq eval '.role // ""' - 2>/dev/null) || declared_role=""
    if [[ "${LOA_VALIDATE_ROLE:-0}" == "1" || -n "$declared_role" ]]; then
        if ! validate_skill_role "$skill_name" "$skill_md" "$frontmatter"; then
            has_error=true
        fi
    fi

    if [[ "$has_error" == "false" ]]; then
        log_pass "$skill_name"
    fi
}

# --- Main ---
if [[ "$JSON_OUTPUT" == "false" ]]; then
    echo "Skill Capabilities Validation"
    echo "=============================="
    echo ""
fi

if [[ -n "$SINGLE_SKILL" ]]; then
    skill_path="$SKILLS_DIR/$SINGLE_SKILL"
    if [[ -d "$skill_path" ]]; then
        validate_skill "$skill_path"
    else
        echo "Skill not found: $SINGLE_SKILL" >&2
        exit 2
    fi
else
    for skill_dir in "$SKILLS_DIR"/*/; do
        [[ -d "$skill_dir" ]] || continue
        validate_skill "$skill_dir"
    done
fi

if [[ "$JSON_OUTPUT" == "false" ]]; then
    echo ""
    echo "Results: $total skills checked, $passed passed, $errors errors, $warnings warnings"
fi

if [[ "$JSON_OUTPUT" == "true" ]]; then
    jq -n \
        --argjson results "$results_json" \
        --argjson total "$total" \
        --argjson passed "$passed" \
        --argjson errors "$errors" \
        --argjson warnings "$warnings" \
        --arg strict "$STRICT" \
        '{total: $total, passed: $passed, errors: $errors, warnings: $warnings, strict: ($strict == "true"), results: $results}'
fi

if [[ $errors -gt 0 ]]; then
    exit 1
fi
exit 0
