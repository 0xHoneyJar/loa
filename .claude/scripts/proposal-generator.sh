#!/usr/bin/env bash
# =============================================================================
# proposal-generator.sh - Generate Upstream Learning Proposals
# =============================================================================
# Sprint 2, Task T2.2: Create proposal generator with deduplication
# Goal Contribution: G-1 (Silent detection with opt-in), G-6 (Maintainer workflow)
#
# Generates a GitHub Issue proposal for an eligible learning:
#   1. Validates learning exists and is eligible
#   2. Checks for duplicate proposals via jaccard-similarity.sh (threshold 0.7)
#   3. Anonymizes content via anonymize-proposal.sh
#   4. Generates GitHub Issue body from template
#   5. Creates Issue via gh-label-handler.sh with learning-proposal label
#   6. Updates learning entry with proposal status
#
# Usage:
#   ./proposal-generator.sh --learning <ID>
#   ./proposal-generator.sh --learning <ID> --dry-run
#   ./proposal-generator.sh --learning <ID> --force
#
# Options:
#   --learning ID       Learning ID to propose (required)
#   --dry-run           Preview proposal without creating Issue
#   --force             Skip eligibility check
#   --skip-dedup        Skip duplicate detection
#   --output FILE       Write proposal body to file instead of creating Issue
#   --help              Show this help
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/.loa.config.yaml"

# Dependency scripts
UPSTREAM_SCORE_SCRIPT="$SCRIPT_DIR/upstream-score-calculator.sh"
ANONYMIZE_SCRIPT="$SCRIPT_DIR/anonymize-proposal.sh"
JACCARD_SCRIPT="$SCRIPT_DIR/jaccard-similarity.sh"
GH_LABEL_HANDLER="$SCRIPT_DIR/gh-label-handler.sh"
REDACT_EXPORT_SCRIPT="$SCRIPT_DIR/redact-export.sh"
EXCHANGE_SCHEMA="$PROJECT_ROOT/.claude/schemas/learning-exchange.schema.json"

# Learnings file
PROJECT_LEARNINGS_FILE="$PROJECT_ROOT/grimoires/loa/a2a/compound/learnings.json"

# Defaults (configurable via .loa.config.yaml)
TARGET_REPO="0xHoneyJar/loa"
PROPOSAL_LABEL="learning-proposal"
SIMILARITY_THRESHOLD="0.7"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# Parameters
LEARNING_ID=""
DRY_RUN=false
FORCE=false
SKIP_DEDUP=false
OUTPUT_FILE=""

usage() {
    sed -n '/^# Usage:/,/^# =====/p' "$0" | grep -v "^# =====" | sed 's/^# //'
    exit 0
}

# Read config value with yq, fallback to default
read_config() {
    local path="$1"
    local default="$2"
    if [[ -f "$CONFIG_FILE" ]] && command -v yq &> /dev/null; then
        local value
        value=$(yq -r "$path // \"\"" "$CONFIG_FILE" 2>/dev/null)
        if [[ -n "$value" && "$value" != "null" ]]; then
            echo "$value"
            return
        fi
    fi
    echo "$default"
}

# Load configuration
load_config() {
    TARGET_REPO=$(read_config '.upstream_proposals.target_repo' '0xHoneyJar/loa')
    PROPOSAL_LABEL=$(read_config '.upstream_proposals.label' 'learning-proposal')
    SIMILARITY_THRESHOLD=$(read_config '.upstream_detection.novelty_threshold' '0.7')
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --learning)
                LEARNING_ID="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --skip-dedup)
                SKIP_DEDUP=true
                shift
                ;;
            --output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            --help|-h)
                usage
                ;;
            *)
                echo "[ERROR] Unknown option: $1" >&2
                exit 1
                ;;
        esac
    done

    if [[ -z "$LEARNING_ID" ]]; then
        echo "[ERROR] --learning ID is required" >&2
        exit 1
    fi

    # MEDIUM-001 FIX: Validate learning ID format (alphanumeric, hyphens, underscores)
    if [[ ! "$LEARNING_ID" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "[ERROR] Invalid learning ID format: must be alphanumeric with hyphens/underscores only" >&2
        exit 1
    fi
}

# Get learning from project learnings file
get_learning() {
    local id="$1"

    if [[ ! -f "$PROJECT_LEARNINGS_FILE" ]]; then
        echo ""
        return 1
    fi

    jq --arg id "$id" '.learnings[] | select(.id == $id)' "$PROJECT_LEARNINGS_FILE" 2>/dev/null || echo ""
}

# Check if learning is eligible for upstream
check_eligibility() {
    local learning_id="$1"

    if [[ "$FORCE" == "true" ]]; then
        return 0
    fi

    if [[ ! -x "$UPSTREAM_SCORE_SCRIPT" ]]; then
        echo -e "${YELLOW}[WARN] Upstream score calculator not found, skipping eligibility check${NC}" >&2
        return 0
    fi

    if "$UPSTREAM_SCORE_SCRIPT" --learning "$learning_id" --check-eligibility; then
        return 0
    else
        return 1
    fi
}

# Check for existing proposals with similar content
check_duplicates() {
    local learning="$1"

    if [[ "$SKIP_DEDUP" == "true" ]]; then
        echo "skipped"
        return
    fi

    if [[ ! -x "$JACCARD_SCRIPT" ]]; then
        echo -e "${YELLOW}[WARN] Jaccard similarity script not found, skipping deduplication${NC}" >&2
        echo "skipped"
        return
    fi

    # Extract text from current learning
    local title trigger solution
    title=$(echo "$learning" | jq -r '.title // ""')
    trigger=$(echo "$learning" | jq -r '.trigger // ""')
    solution=$(echo "$learning" | jq -r '.solution // ""')
    local learning_text="$title $trigger $solution"

    # Check against other learnings with proposal status
    local existing_proposals
    existing_proposals=$(jq -r '.learnings[] | select(.proposal.status != null and .proposal.status != "none" and .proposal.status != "rejected")' "$PROJECT_LEARNINGS_FILE" 2>/dev/null || true)

    if [[ -z "$existing_proposals" ]]; then
        echo "unique"
        return
    fi

    # Compare against each existing proposal
    while IFS= read -r proposal; do
        [[ -z "$proposal" ]] && continue

        local prop_id prop_title prop_trigger prop_solution
        prop_id=$(echo "$proposal" | jq -r '.id // ""')
        prop_title=$(echo "$proposal" | jq -r '.title // ""')
        prop_trigger=$(echo "$proposal" | jq -r '.trigger // ""')
        prop_solution=$(echo "$proposal" | jq -r '.solution // ""')

        # Skip self
        local current_id
        current_id=$(echo "$learning" | jq -r '.id')
        [[ "$prop_id" == "$current_id" ]] && continue

        local proposal_text="$prop_title $prop_trigger $prop_solution"

        # Calculate similarity
        local similarity
        similarity=$("$JACCARD_SCRIPT" --text-a "$learning_text" --text-b "$proposal_text" 2>/dev/null || echo "0")

        # Check if above threshold
        local is_duplicate
        is_duplicate=$(awk "BEGIN {print ($similarity >= $SIMILARITY_THRESHOLD) ? 1 : 0}")

        if [[ "$is_duplicate" == "1" ]]; then
            echo "duplicate:$prop_id:$similarity"
            return
        fi
    done <<< "$(echo "$existing_proposals" | jq -c '.')"

    echo "unique"
}

# Generate anonymized proposal body
generate_proposal_body() {
    local learning="$1"

    # Extract learning fields
    local id title context trigger solution verified tags
    id=$(echo "$learning" | jq -r '.id // "Unknown"')
    title=$(echo "$learning" | jq -r '.title // "Untitled Learning"')
    context=$(echo "$learning" | jq -r '.context // "Not specified"')
    trigger=$(echo "$learning" | jq -r '.trigger // "Not specified"')
    solution=$(echo "$learning" | jq -r '.solution // "Not specified"')
    verified=$(echo "$learning" | jq -r '.verified // false')
    tags=$(echo "$learning" | jq -r '.tags // [] | join(", ")')

    # Get effectiveness data
    local app_count successes success_rate
    app_count=$(echo "$learning" | jq '[.applications // [] | .[]] | length')
    successes=$(echo "$learning" | jq '[.applications // [] | .[] | select(.outcome == "success")] | length')
    if [[ "$app_count" -gt 0 ]]; then
        success_rate=$(echo "scale=1; $successes / $app_count * 100" | bc)
    else
        success_rate="0"
    fi

    # Get upstream score
    local upstream_score="N/A"
    if [[ -x "$UPSTREAM_SCORE_SCRIPT" ]]; then
        local score_result
        score_result=$("$UPSTREAM_SCORE_SCRIPT" --learning "$id" --format json 2>/dev/null || echo '{}')
        upstream_score=$(echo "$score_result" | jq -r '.upstream_score // "N/A"')
    fi

    # Generate Issue body
    local body
    body=$(cat <<EOF
## Learning Proposal

**ID:** $id
**Category:** $(echo "$learning" | jq -r '.type // "pattern"')

### Title

$title

### Context

$context

### Trigger

When to apply this learning:

$trigger

### Solution

$solution

### Effectiveness

| Metric | Value |
|--------|-------|
| Applications | $app_count |
| Success Rate | ${success_rate}% |
| Verified | $verified |
| Upstream Score | $upstream_score |

### Tags

$tags

---

### Quality Gates

$(echo "$learning" | jq -r 'if .quality_gates then
"| Gate | Score |
|------|-------|
| Discovery Depth | \(.quality_gates.discovery_depth // "N/A") |
| Reusability | \(.quality_gates.reusability // "N/A") |
| Trigger Clarity | \(.quality_gates.trigger_clarity // "N/A") |
| Verification | \(.quality_gates.verification // "N/A") |"
else
"Quality gates not assessed."
end')

---

*This proposal was automatically generated from a project learning that met the upstream eligibility criteria.*

*Submitted via Loa Learning Flow*
EOF
)

    # Anonymize if script available
    if [[ -x "$ANONYMIZE_SCRIPT" ]]; then
        body=$(echo "$body" | "$ANONYMIZE_SCRIPT" --stdin)
    fi

    echo "$body"
}

# Create GitHub Issue
# CRITICAL-001 FIX: Use temp file for body to prevent command injection
create_proposal_issue() {
    local learning_id="$1"
    local title="$2"
    local body="$3"

    if [[ ! -x "$GH_LABEL_HANDLER" ]]; then
        echo -e "${RED}[ERROR] gh-label-handler.sh not found${NC}" >&2
        return 1
    fi

    # CRITICAL-001 FIX: Write body to temp file to prevent shell metacharacter injection
    # User content in $body could contain $(cmd), `cmd`, or other shell metacharacters
    # MEDIUM-002 FIX: Set umask before mktemp to eliminate race condition window
    local body_file
    body_file=$(umask 077 && mktemp)
    printf '%s' "$body" > "$body_file"

    # Use body-file approach to avoid command injection
    local issue_url
    issue_url=$("$GH_LABEL_HANDLER" create-issue \
        --repo "$TARGET_REPO" \
        --title "[Learning Proposal] $title" \
        --body-file "$body_file" \
        --labels "$PROPOSAL_LABEL" \
        --graceful)

    rm -f "$body_file"
    echo "$issue_url"
}

# Update learning with proposal status
update_learning_proposal_status() {
    local learning_id="$1"
    local status="$2"
    local issue_ref="${3:-}"

    if [[ ! -f "$PROJECT_LEARNINGS_FILE" ]]; then
        return 1
    fi

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Get current upstream score
    local upstream_score=0
    if [[ -x "$UPSTREAM_SCORE_SCRIPT" ]]; then
        local score_result
        score_result=$("$UPSTREAM_SCORE_SCRIPT" --learning "$learning_id" --format json 2>/dev/null || echo '{}')
        upstream_score=$(echo "$score_result" | jq -r '.upstream_score // 0')
    fi

    # MEDIUM-002 FIX: Set umask before mktemp to eliminate race condition window
    local temp_file
    temp_file=$(umask 077 && mktemp)

    # Update the learning entry
    jq --arg id "$learning_id" \
       --arg status "$status" \
       --arg issue_ref "$issue_ref" \
       --arg timestamp "$timestamp" \
       --argjson score "$upstream_score" \
       '(.learnings[] | select(.id == $id)) |= . + {
           proposal: {
               status: $status,
               submitted_at: $timestamp,
               upstream_score_at_submission: $score,
               anonymized: true,
               issue_ref: (if $issue_ref != "" then $issue_ref else null end)
           }
       }' "$PROJECT_LEARNINGS_FILE" > "$temp_file"

    mv "$temp_file" "$PROJECT_LEARNINGS_FILE"
}

# Extract Issue number from URL
extract_issue_ref() {
    local url="$1"

    # Extract #NNN from URL like https://github.com/owner/repo/issues/123
    local issue_num
    issue_num=$(echo "$url" | grep -oE '/issues/[0-9]+' | grep -oE '[0-9]+' || echo "")

    if [[ -n "$issue_num" ]]; then
        echo "#$issue_num"
    else
        echo ""
    fi
}

# Check learning exchange quality gates
# Returns 0 if gates pass, 1 if below threshold
check_exchange_quality_gates() {
    local learning="$1"

    local depth reusability trigger_clarity verification
    depth=$(echo "$learning" | jq -r '.quality_gates.discovery_depth // .quality_gates.depth // 0')
    reusability=$(echo "$learning" | jq -r '.quality_gates.reusability // 0')
    trigger_clarity=$(echo "$learning" | jq -r '.quality_gates.trigger_clarity // 0')
    verification=$(echo "$learning" | jq -r '.quality_gates.verification // 0')

    local failed=false
    if [[ "$depth" -lt 7 ]]; then
        echo -e "  ${RED}✗ depth ($depth) below threshold (7)${NC}" >&2
        failed=true
    fi
    if [[ "$reusability" -lt 7 ]]; then
        echo -e "  ${RED}✗ reusability ($reusability) below threshold (7)${NC}" >&2
        failed=true
    fi
    if [[ "$trigger_clarity" -lt 6 ]]; then
        echo -e "  ${RED}✗ trigger_clarity ($trigger_clarity) below threshold (6)${NC}" >&2
        failed=true
    fi
    if [[ "$verification" -lt 6 ]]; then
        echo -e "  ${RED}✗ verification ($verification) below threshold (6)${NC}" >&2
        failed=true
    fi

    if [[ "$failed" == "true" ]]; then
        return 1
    fi
    return 0
}

# Generate learning exchange file in schema-compliant format
# Runs content through redact-export.sh and validates against schema
generate_exchange_file() {
    local learning="$1"
    local output_path="$2"

    # Extract fields
    local id title category context trigger solution confidence
    id=$(echo "$learning" | jq -r '.id // "Unknown"')
    title=$(echo "$learning" | jq -r '.title // "Untitled Learning"')
    category=$(echo "$learning" | jq -r '.type // "pattern"')
    context=$(echo "$learning" | jq -r '.context // ""')
    trigger=$(echo "$learning" | jq -r '.trigger // ""')
    solution=$(echo "$learning" | jq -r '.solution // ""')
    confidence=$(echo "$learning" | jq -r '.confidence // 0.5')

    # Extract quality gates
    local depth reusability trigger_clarity verification
    depth=$(echo "$learning" | jq -r '.quality_gates.discovery_depth // .quality_gates.depth // 5')
    reusability=$(echo "$learning" | jq -r '.quality_gates.reusability // 5')
    trigger_clarity=$(echo "$learning" | jq -r '.quality_gates.trigger_clarity // 5')
    verification=$(echo "$learning" | jq -r '.quality_gates.verification // 5')

    # Extract tags
    local tags_json
    tags_json=$(echo "$learning" | jq -c '.tags // []')

    # Generate learning exchange ID: LX-YYYYMMDD-hexhash
    local date_part hash_part learning_id
    date_part=$(date +%Y%m%d)
    hash_part=$(printf '%s' "$id$title" | sha256sum | cut -c1-10)
    learning_id="LX-${date_part}-${hash_part}"

    # Run content through redact-export.sh
    local redacted_trigger redacted_solution redacted_context
    local audit_file rules_applied items_redacted items_blocked

    audit_file=$(mktemp)

    if [[ -x "$REDACT_EXPORT_SCRIPT" ]]; then
        redacted_trigger=$(printf '%s' "$trigger" | "$REDACT_EXPORT_SCRIPT" --audit-file "$audit_file" --quiet 2>/dev/null)
        local trigger_exit=$?
        if [[ $trigger_exit -eq 1 ]]; then
            echo -e "  ${RED}✗ Trigger content BLOCKED by redaction pipeline${NC}" >&2
            rm -f "$audit_file"
            return 1
        fi

        redacted_solution=$(printf '%s' "$solution" | "$REDACT_EXPORT_SCRIPT" --quiet 2>/dev/null)
        local solution_exit=$?
        if [[ $solution_exit -eq 1 ]]; then
            echo -e "  ${RED}✗ Solution content BLOCKED by redaction pipeline${NC}" >&2
            rm -f "$audit_file"
            return 1
        fi

        redacted_context=$(printf '%s' "$context" | "$REDACT_EXPORT_SCRIPT" --quiet 2>/dev/null)
        if [[ $? -eq 1 ]]; then
            echo -e "  ${RED}✗ Context content BLOCKED by redaction pipeline${NC}" >&2
            rm -f "$audit_file"
            return 1
        fi

        # Parse audit report
        if [[ -f "$audit_file" && -s "$audit_file" ]]; then
            rules_applied=$(jq -r '(.findings.block + .findings.redact + .findings.flag) // 0' "$audit_file" 2>/dev/null || echo "0")
            items_redacted=$(jq -r '.findings.redact // 0' "$audit_file" 2>/dev/null || echo "0")
            items_blocked=$(jq -r '.findings.block // 0' "$audit_file" 2>/dev/null || echo "0")
        else
            rules_applied=0
            items_redacted=0
            items_blocked=0
        fi
        rm -f "$audit_file"
    else
        # Fallback: use anonymize-proposal.sh
        redacted_trigger="$trigger"
        redacted_solution="$solution"
        redacted_context="$context"
        if [[ -x "$ANONYMIZE_SCRIPT" ]]; then
            redacted_trigger=$(echo "$trigger" | "$ANONYMIZE_SCRIPT" --stdin 2>/dev/null || echo "$trigger")
            redacted_solution=$(echo "$solution" | "$ANONYMIZE_SCRIPT" --stdin 2>/dev/null || echo "$solution")
            redacted_context=$(echo "$context" | "$ANONYMIZE_SCRIPT" --stdin 2>/dev/null || echo "$context")
        fi
        rules_applied=0
        items_redacted=0
        items_blocked=0
    fi

    # Build exchange JSON
    local exchange_json
    exchange_json=$(jq -cn \
        --argjson schema_version 1 \
        --arg learning_id "$learning_id" \
        --arg source_learning_id "$id" \
        --arg category "$category" \
        --arg title "$title" \
        --arg context "$redacted_context" \
        --arg trigger "$redacted_trigger" \
        --arg solution "$redacted_solution" \
        --argjson tags "$tags_json" \
        --argjson confidence "$confidence" \
        --argjson depth "$depth" \
        --argjson reusability "$reusability" \
        --argjson trigger_clarity "$trigger_clarity" \
        --argjson verification "$verification" \
        --argjson rules_applied "$rules_applied" \
        --argjson items_redacted "$items_redacted" \
        --argjson items_blocked "$items_blocked" \
        --arg created_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{
            schema_version: $schema_version,
            learning_id: $learning_id,
            source_learning_id: $source_learning_id,
            category: $category,
            title: $title,
            content: {
                context: $context,
                trigger: $trigger,
                solution: $solution,
                tags: $tags
            },
            confidence: $confidence,
            quality_gates: {
                depth: $depth,
                reusability: $reusability,
                trigger_clarity: $trigger_clarity,
                verification: $verification
            },
            privacy: {
                contains_file_paths: false,
                contains_secrets: false,
                contains_pii: false
            },
            redaction_report: {
                rules_applied: $rules_applied,
                items_redacted: $items_redacted,
                items_blocked: $items_blocked
            },
            metadata: {
                created_at: $created_at
            }
        }')

    # Validate against schema if jq has schema validation capability
    # (Basic validation: check required fields are present and correct types)
    local valid=true
    if ! echo "$exchange_json" | jq -e '.schema_version == 1' >/dev/null 2>&1; then
        valid=false
    fi
    if ! echo "$exchange_json" | jq -e '.learning_id | test("^LX-[0-9]{8}-[a-f0-9]{8,12}$")' >/dev/null 2>&1; then
        valid=false
    fi
    if ! echo "$exchange_json" | jq -e '.category | IN("pattern", "anti-pattern", "decision", "troubleshooting", "architecture", "security")' >/dev/null 2>&1; then
        valid=false
    fi
    if ! echo "$exchange_json" | jq -e '.privacy.contains_file_paths == false and .privacy.contains_secrets == false and .privacy.contains_pii == false' >/dev/null 2>&1; then
        valid=false
    fi

    if [[ "$valid" != "true" ]]; then
        echo -e "  ${RED}✗ Exchange file failed schema validation${NC}" >&2
        return 1
    fi

    # Write exchange file
    echo "$exchange_json" | jq . > "$output_path"
    return 0
}

main() {
    parse_args "$@"
    load_config

    echo -e "${BOLD}${CYAN}Proposal Generator${NC}"
    echo "─────────────────────────────────────────"
    echo ""

    # Get the learning
    local learning
    learning=$(get_learning "$LEARNING_ID")

    if [[ -z "$learning" || "$learning" == "null" ]]; then
        echo -e "${RED}[ERROR] Learning not found: $LEARNING_ID${NC}" >&2
        exit 1
    fi

    local title
    title=$(echo "$learning" | jq -r '.title // "Untitled"')
    echo -e "  Learning: ${BLUE}$LEARNING_ID${NC}"
    echo -e "  Title: $title"
    echo ""

    # Check existing proposal status
    local existing_status
    existing_status=$(echo "$learning" | jq -r '.proposal.status // "none"')
    if [[ "$existing_status" != "none" && "$existing_status" != "rejected" ]]; then
        echo -e "${YELLOW}[WARN] Learning already has proposal status: $existing_status${NC}"
        if [[ "$FORCE" != "true" ]]; then
            echo "Use --force to override"
            exit 1
        fi
    fi

    # Check eligibility
    echo -e "  Checking eligibility..."
    if ! check_eligibility "$LEARNING_ID"; then
        echo -e "  ${RED}✗ Not eligible for upstream proposal${NC}"

        if [[ -x "$UPSTREAM_SCORE_SCRIPT" ]]; then
            local score_result
            score_result=$("$UPSTREAM_SCORE_SCRIPT" --learning "$LEARNING_ID" --format json 2>/dev/null || echo '{}')
            local reason
            reason=$(echo "$score_result" | jq -r '.eligibility.reason // "Unknown"')
            echo -e "  Reason: ${YELLOW}$reason${NC}"
        fi

        exit 1
    fi
    echo -e "  ${GREEN}✓ Eligible${NC}"
    echo ""

    # Check for duplicates
    echo -e "  Checking for duplicates..."
    local dedup_result
    dedup_result=$(check_duplicates "$learning")

    if [[ "$dedup_result" == duplicate:* ]]; then
        local dup_id dup_sim
        dup_id=$(echo "$dedup_result" | cut -d':' -f2)
        dup_sim=$(echo "$dedup_result" | cut -d':' -f3)
        echo -e "  ${RED}✗ Duplicate detected${NC}"
        echo -e "  Similar to: ${YELLOW}$dup_id${NC} (similarity: $dup_sim)"
        exit 1
    elif [[ "$dedup_result" == "skipped" ]]; then
        echo -e "  ${YELLOW}⊘ Skipped${NC}"
    else
        echo -e "  ${GREEN}✓ Unique${NC}"
    fi
    echo ""

    # Check exchange quality gates
    echo -e "  Checking exchange quality gates..."
    if ! check_exchange_quality_gates "$learning"; then
        echo -e "  ${RED}✗ Learning does not meet exchange quality thresholds${NC}"
        if [[ "$FORCE" != "true" ]]; then
            exit 1
        fi
        echo -e "  ${YELLOW}⊘ Bypassed (--force)${NC}"
    else
        echo -e "  ${GREEN}✓ Quality gates passed${NC}"
    fi
    echo ""

    # Generate learning exchange file
    echo -e "  Generating exchange file..."
    local exchange_output="${OUTPUT_FILE:-.loa-learning-proposal.yaml}"
    if generate_exchange_file "$learning" "$exchange_output"; then
        echo -e "  ${GREEN}✓ Exchange file: $exchange_output${NC}"
    else
        echo -e "  ${YELLOW}[WARN] Exchange file generation failed (continuing with proposal)${NC}"
    fi
    echo ""

    # Generate proposal body
    echo -e "  Generating proposal..."
    local proposal_body
    proposal_body=$(generate_proposal_body "$learning")
    echo -e "  ${GREEN}✓ Generated${NC}"
    echo ""

    # Output to file if requested
    if [[ -n "$OUTPUT_FILE" ]]; then
        echo "$proposal_body" > "$OUTPUT_FILE"
        echo -e "  ${GREEN}Proposal written to: $OUTPUT_FILE${NC}"
        exit 0
    fi

    # Dry run - show preview
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "─────────────────────────────────────────"
        echo -e "${BOLD}Proposal Preview${NC}"
        echo "─────────────────────────────────────────"
        echo ""
        echo -e "${BLUE}Title:${NC} [Learning Proposal] $title"
        echo -e "${BLUE}Repository:${NC} $TARGET_REPO"
        echo -e "${BLUE}Labels:${NC} $PROPOSAL_LABEL"
        echo ""
        echo -e "${BLUE}Body:${NC}"
        echo "─────────────────────────────────────────"
        echo "$proposal_body"
        echo "─────────────────────────────────────────"
        echo ""
        echo -e "${YELLOW}[DRY RUN] No Issue created${NC}"
        exit 0
    fi

    # Create the Issue
    echo -e "  Creating GitHub Issue..."
    local issue_url
    issue_url=$(create_proposal_issue "$LEARNING_ID" "$title" "$proposal_body")

    if [[ -z "$issue_url" ]]; then
        echo -e "  ${RED}✗ Failed to create Issue${NC}"
        exit 1
    fi

    echo -e "  ${GREEN}✓ Issue created${NC}"
    echo ""

    # Extract issue reference
    local issue_ref
    issue_ref=$(extract_issue_ref "$issue_url")

    # Update learning status
    echo -e "  Updating learning status..."
    update_learning_proposal_status "$LEARNING_ID" "submitted" "$issue_ref"
    echo -e "  ${GREEN}✓ Updated${NC}"
    echo ""

    echo "─────────────────────────────────────────"
    echo -e "${GREEN}${BOLD}Proposal Submitted Successfully${NC}"
    echo ""
    echo -e "  Issue: ${BLUE}$issue_url${NC}"
    echo -e "  Reference: ${CYAN}$issue_ref${NC}"
    echo ""
}

main "$@"
