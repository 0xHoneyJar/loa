#!/usr/bin/env bash
# butterfreezone-validate.sh - Validate BUTTERFREEZONE.md structure and content
# Version: 1.0.0
#
# Validates provenance tags, AGENT-CONTEXT, references, word budget,
# ground-truth-meta, and freshness. Used by RTFM gate and /butterfreezone skill.
#
# Usage:
#   .claude/scripts/butterfreezone-validate.sh [OPTIONS]
#
# Exit Codes:
#   0 - All checks pass
#   1 - Failures detected
#   2 - Warnings only (advisory)

export LC_ALL=C
export TZ=UTC

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_VERSION="1.0.0"

# =============================================================================
# Defaults
# =============================================================================

FILE="BUTTERFREEZONE.md"
CONFIG_FILE=".loa.config.yaml"
STRICT="false"
JSON_OUT="false"
QUIET="false"

FAILURES=0
WARNINGS=0
PASSES=0
CHECKS=()

# =============================================================================
# Logging
# =============================================================================

log_pass() {
    PASSES=$((PASSES + 1))
    CHECKS+=("$(jq -nc --arg name "$1" --arg status "pass" '{name: $name, status: $status}')")
    [[ "$QUIET" == "true" ]] && return 0
    echo "  PASS: $2"
}

log_fail() {
    FAILURES=$((FAILURES + 1))
    local detail="${3:-}"
    if [[ -n "$detail" ]]; then
        CHECKS+=("$(jq -nc --arg name "$1" --arg status "fail" --arg detail "$detail" '{name: $name, status: $status, detail: $detail}')")
    else
        CHECKS+=("$(jq -nc --arg name "$1" --arg status "fail" '{name: $name, status: $status}')")
    fi
    [[ "$QUIET" == "true" ]] && return 0
    echo "  FAIL: $2"
}

log_warn() {
    if [[ "$STRICT" == "true" ]]; then
        log_fail "$@"
        return
    fi
    WARNINGS=$((WARNINGS + 1))
    local detail="${3:-}"
    if [[ -n "$detail" ]]; then
        CHECKS+=("$(jq -nc --arg name "$1" --arg status "warn" --arg detail "$detail" '{name: $name, status: $status, detail: $detail}')")
    else
        CHECKS+=("$(jq -nc --arg name "$1" --arg status "warn" '{name: $name, status: $status}')")
    fi
    [[ "$QUIET" == "true" ]] && return 0
    echo "  WARN: $2"
}

# =============================================================================
# Usage
# =============================================================================

usage() {
    cat <<'USAGE'
Usage: butterfreezone-validate.sh [OPTIONS]

Validate BUTTERFREEZONE.md structure and content.

Options:
  --file PATH        File to validate (default: BUTTERFREEZONE.md)
  --strict           Treat advisory warnings as failures
  --json             Output results as JSON
  --quiet            Suppress output, exit code only
  --help             Show usage

Exit codes:
  0  All checks pass
  1  Failures detected
  2  Warnings only (advisory)
USAGE
    exit "${1:-0}"
}

# =============================================================================
# Argument Parsing
# =============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --file)
                FILE="$2"
                shift 2
                ;;
            --strict)
                STRICT="true"
                shift
                ;;
            --json)
                JSON_OUT="true"
                shift
                ;;
            --quiet)
                QUIET="true"
                shift
                ;;
            --help)
                usage 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                usage 2
                ;;
        esac
    done
}

# =============================================================================
# Configuration
# =============================================================================

get_config_value() {
    local key="$1"
    local default="$2"

    if [[ -f "$CONFIG_FILE" ]] && command -v yq &>/dev/null; then
        local val
        val=$(yq ".$key // \"\"" "$CONFIG_FILE" 2>/dev/null) || true
        if [[ -n "$val" && "$val" != "null" ]]; then
            echo "$val"
            return
        fi
    fi
    echo "$default"
}

# =============================================================================
# Validation Checks (SDD 3.2.2)
# =============================================================================

# Check 1: Existence
validate_existence() {
    if [[ ! -f "$FILE" ]]; then
        log_fail "existence" "BUTTERFREEZONE.md not found at $FILE" "file not found"
        return 1
    fi
    log_pass "existence" "BUTTERFREEZONE.md exists"
    return 0
}

# Check 2: AGENT-CONTEXT block
validate_agent_context() {
    if ! grep -q "<!-- AGENT-CONTEXT" "$FILE" 2>/dev/null; then
        log_fail "agent_context" "Missing AGENT-CONTEXT metadata block" "block missing"
        return 1
    fi

    local context_block
    context_block=$(sed -n '/<!-- AGENT-CONTEXT/,/-->/p' "$FILE" 2>/dev/null)

    for field in name type purpose version; do
        if ! echo "$context_block" | grep -q "^${field}:" 2>/dev/null; then
            log_fail "agent_context" "AGENT-CONTEXT missing required field: $field" "missing field: $field"
            return 1
        fi
    done

    log_pass "agent_context" "AGENT-CONTEXT block valid (all required fields present)"
    return 0
}

# Check 3: Provenance tags
validate_provenance() {
    local sections
    sections=$(grep -c "^## " "$FILE" 2>/dev/null) || sections=0
    local tagged
    tagged=$(grep -c "<!-- provenance:" "$FILE" 2>/dev/null) || tagged=0

    if (( sections == 0 )); then
        log_pass "provenance" "No sections to validate"
        return 0
    fi

    if (( tagged < sections )); then
        log_fail "provenance" "Missing provenance tags: $tagged/$sections sections tagged" "$tagged of $sections tagged"
        return 1
    fi

    # Validate tag values
    local invalid=0
    while IFS= read -r line; do
        local tag
        tag=$(echo "$line" | sed 's/.*provenance: *\([A-Z_-]*\).*/\1/')
        case "$tag" in
            CODE-FACTUAL|DERIVED|OPERATIONAL) ;;
            *) invalid=$((invalid + 1)) ;;
        esac
    done < <(grep "<!-- provenance:" "$FILE" 2>/dev/null)

    if (( invalid > 0 )); then
        log_fail "provenance" "$invalid invalid provenance tag values" "$invalid invalid tags"
        return 1
    fi

    log_pass "provenance" "All sections have valid provenance tags ($tagged/$sections)"
    return 0
}

# Check 4: File references
validate_references() {
    local failures=0
    local checked=0

    # Only scan backtick-fenced references (SDD 3.1.15)
    local refs
    refs=$(grep -oE '`[a-zA-Z0-9_./-]+:[a-zA-Z_L][a-zA-Z0-9_]*`' "$FILE" 2>/dev/null \
        | sed 's/`//g' | sort -u) || true

    while IFS= read -r ref; do
        [[ -z "$ref" ]] && continue

        local file="${ref%%:*}"
        local symbol="${ref#*:}"

        # Skip non-file references (URLs, timestamps, meta fields)
        [[ "$file" == *"http"* ]] && continue
        [[ "$file" == *"//"* ]] && continue
        [[ "$file" == "head_sha" ]] && continue
        [[ "$file" == "generated_at" ]] && continue
        [[ "$file" == "generator" ]] && continue

        checked=$((checked + 1))

        if [[ ! -f "$file" ]]; then
            log_fail "references" "Referenced file missing: $file (in \`$ref\`)" "file missing: $file"
            failures=$((failures + 1))
        elif [[ "$symbol" == L* ]]; then
            # Line reference — just validate file exists (done above)
            :
        elif ! grep -q "$symbol" "$file" 2>/dev/null; then
            log_warn "references" "Symbol not found: $symbol in $file (advisory)" "symbol not found: $ref"
        fi
    done <<< "$refs"

    if (( failures == 0 )); then
        log_pass "references" "All file references valid ($checked checked)"
    fi

    return $(( failures > 0 ? 1 : 0 ))
}

# Check 5: Word budget
validate_word_budget() {
    local total_words
    total_words=$(wc -w < "$FILE" 2>/dev/null | tr -d ' ')
    local budget
    budget=$(get_config_value "butterfreezone.word_budget.total" "3200")

    if (( total_words > budget )); then
        log_warn "word_budget" "Word budget exceeded: $total_words / $budget (advisory)" "exceeded: $total_words > $budget"
    else
        log_pass "word_budget" "Word budget: $total_words / $budget"
    fi
}

# Check 6: ground-truth-meta
validate_meta() {
    if ! grep -q "<!-- ground-truth-meta" "$FILE" 2>/dev/null; then
        log_fail "meta" "Missing ground-truth-meta block" "block missing"
        return 1
    fi

    local meta_sha
    meta_sha=$(sed -n '/<!-- ground-truth-meta/,/-->/p' "$FILE" 2>/dev/null \
        | grep "head_sha:" | awk '{print $2}') || true
    local current_sha
    current_sha=$(git rev-parse HEAD 2>/dev/null || echo "unknown")

    if [[ -z "$meta_sha" ]]; then
        log_fail "meta" "ground-truth-meta missing head_sha field" "head_sha missing"
        return 1
    fi

    if [[ "$meta_sha" != "$current_sha" ]]; then
        log_warn "meta" "Stale: head_sha mismatch (generated: ${meta_sha:0:8}, current: ${current_sha:0:8})" "head_sha mismatch"
    else
        log_pass "meta" "ground-truth-meta SHA matches HEAD"
    fi
    return 0
}

# Check 7: Freshness
validate_freshness() {
    local generated_at
    generated_at=$(sed -n '/<!-- ground-truth-meta/,/-->/p' "$FILE" 2>/dev/null \
        | grep "generated_at:" | awk '{print $2}') || true

    if [[ -z "$generated_at" ]]; then
        log_warn "freshness" "No generated_at timestamp found" "timestamp missing"
        return 0
    fi

    local staleness_days
    staleness_days=$(get_config_value "butterfreezone.staleness_days" "7")

    # Parse the timestamp and compare with current time
    local gen_epoch
    gen_epoch=$(date -d "$generated_at" +%s 2>/dev/null || echo 0)
    local now_epoch
    now_epoch=$(date +%s)
    local diff_days=$(( (now_epoch - gen_epoch) / 86400 ))

    if (( diff_days > staleness_days )); then
        log_warn "freshness" "BUTTERFREEZONE.md is $diff_days days old (threshold: $staleness_days)" "stale: $diff_days days"
    else
        log_pass "freshness" "Freshness check passed ($diff_days days old, threshold: $staleness_days)"
    fi
}

# =============================================================================
# JSON Output (SDD 4.3)
# =============================================================================

emit_json() {
    local status="pass"
    if (( FAILURES > 0 )); then
        status="fail"
    elif (( WARNINGS > 0 )); then
        status="warn"
    fi

    local checks_json=""
    for check in "${CHECKS[@]}"; do
        [[ -n "$checks_json" ]] && checks_json="${checks_json}, "
        checks_json="${checks_json}${check}"
    done

    cat <<EOF
{
  "status": "$status",
  "validator": "butterfreezone-validate",
  "version": "${SCRIPT_VERSION}",
  "file": "$FILE",
  "passed": $PASSES,
  "failed": $FAILURES,
  "warnings": $WARNINGS,
  "checks": [$checks_json],
  "errors": [],
  "strict_mode": $STRICT
}
EOF
}

# =============================================================================
# Main
# =============================================================================

main() {
    parse_args "$@"

    [[ "$QUIET" != "true" ]] && echo "Validating: $FILE"
    [[ "$QUIET" != "true" ]] && echo ""

    # Run all checks
    validate_existence || true

    # Only run remaining checks if file exists
    if [[ -f "$FILE" ]]; then
        validate_agent_context || true
        validate_provenance || true
        validate_references || true
        validate_word_budget || true
        validate_meta || true
        validate_freshness || true
    fi

    # Summary
    [[ "$QUIET" != "true" ]] && echo ""
    [[ "$QUIET" != "true" ]] && echo "Results: $PASSES passed, $FAILURES failed, $WARNINGS warnings"

    # JSON output
    if [[ "$JSON_OUT" == "true" ]]; then
        emit_json
    fi

    # Exit code
    if (( FAILURES > 0 )); then
        exit 1
    elif (( WARNINGS > 0 )); then
        exit 2
    fi
    exit 0
}

main "$@"
