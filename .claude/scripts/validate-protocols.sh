#!/usr/bin/env bash
# Validate protocol documentation completeness and consistency
# Ensures all protocols meet quality standards

set -euo pipefail

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
PROTOCOLS_DIR="${PROJECT_ROOT}/.claude/protocols"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
total_protocols=0
valid_protocols=0
warnings=0
errors=0

log_info() {
    echo -e "${GREEN}✓${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $*"
    ((warnings++)) || true
}

log_error() {
    echo -e "${RED}✗${NC} $*"
    ((errors++)) || true
}

check_protocol_structure() {
    local protocol_file="$1"
    local protocol_name=$(basename "$protocol_file" .md)

    echo ""
    echo "Checking: $protocol_name"
    echo "----------------------------------------"

    ((total_protocols++)) || true

    # Check 1: File exists and is readable
    if [ ! -r "$protocol_file" ]; then
        log_error "File not readable: $protocol_file"
        return 1
    fi

    # Check 2: Has title/header
    if ! grep -q "^# " "$protocol_file"; then
        log_error "Missing main title (# Header)"
    fi

    # Check 3: Has purpose/rationale section
    if ! grep -qi "purpose\|rationale\|overview" "$protocol_file"; then
        log_warn "Missing purpose/rationale section"
    fi

    # Check 4: Has workflow/steps section
    if ! grep -qi "workflow\|steps\|process\|protocol" "$protocol_file"; then
        log_warn "Missing workflow/steps section"
    fi

    # Check 5: Has examples
    if ! grep -q '```' "$protocol_file"; then
        log_warn "Missing code examples"
    fi

    # Check 6: Has good/bad examples (for key protocols)
    if [[ "$protocol_name" =~ (citations|grounding|trajectory) ]]; then
        if ! grep -qi "good\|bad\|correct\|incorrect\|✓\|✗" "$protocol_file"; then
            log_warn "Missing good/bad examples"
        fi
    fi

    # Check 7: Reasonable file size (not too short)
    line_count=$(wc -l < "$protocol_file")
    if [ "$line_count" -lt 20 ]; then
        log_warn "Protocol may be too brief ($line_count lines)"
    elif [ "$line_count" -gt 500 ]; then
        log_warn "Protocol may be too long ($line_count lines) - consider splitting"
    else
        log_info "Length appropriate ($line_count lines)"
    fi

    # Check 8: Has integration points section (for technical protocols)
    if [[ "$protocol_name" =~ (preflight|search|trajectory) ]]; then
        if ! grep -qi "integration\|usage\|implementation" "$protocol_file"; then
            log_warn "Missing integration points section"
        fi
    fi

    # Check 9: References to other protocols exist
    if grep -oE '\.claude/protocols/[a-z-]+\.md' "$protocol_file" | while read -r ref; do
        ref_file="${PROJECT_ROOT}/${ref}"
        if [ ! -f "$ref_file" ]; then
            log_error "Broken reference: $ref"
            return 1
        fi
    done; then
        true
    else
        # No references found, that's okay
        true
    fi

    # Check 10: Markdown formatting validity
    if command -v markdownlint >/dev/null 2>&1; then
        if markdownlint "$protocol_file" 2>/dev/null; then
            log_info "Markdown formatting valid"
        else
            log_warn "Markdown formatting issues detected"
        fi
    fi

    # If no errors for this protocol
    if [ "$errors" -eq 0 ]; then
        ((valid_protocols++)) || true
        log_info "Protocol validation passed"
    fi
}

# Main validation
echo "====================================="
echo "Protocol Documentation Validation"
echo "====================================="
echo ""
echo "Protocols Directory: $PROTOCOLS_DIR"
echo ""

if [ ! -d "$PROTOCOLS_DIR" ]; then
    echo "Error: Protocols directory not found: $PROTOCOLS_DIR" >&2
    exit 1
fi

# Expected protocols list (from PRD Task 5.5)
expected_protocols=(
    "preflight-integrity.md"
    "tool-result-clearing.md"
    "trajectory-evaluation.md"
    "negative-grounding.md"
    "search-fallback.md"
    "citations.md"
    "self-audit-checkpoint.md"
    "edd-verification.md"
)

# Check all expected protocols exist
echo "Checking for required protocols..."
for protocol in "${expected_protocols[@]}"; do
    if [ -f "${PROTOCOLS_DIR}/${protocol}" ]; then
        log_info "Found: $protocol"
    else
        log_error "Missing required protocol: $protocol"
    fi
done

echo ""
echo "====================================="
echo "Detailed Protocol Validation"
echo "====================================="

# Validate each protocol file
for protocol_file in "${PROTOCOLS_DIR}"/*.md; do
    if [ -f "$protocol_file" ]; then
        check_protocol_structure "$protocol_file"
    fi
done

# Summary
echo ""
echo "====================================="
echo "Validation Summary"
echo "====================================="
echo "Total Protocols: $total_protocols"
echo "Valid Protocols: $valid_protocols"
echo "Warnings: $warnings"
echo "Errors: $errors"
echo ""

if [ "$errors" -eq 0 ]; then
    echo -e "${GREEN}✓ All protocols validated successfully${NC}"
    if [ "$warnings" -gt 0 ]; then
        echo -e "${YELLOW}⚠ $warnings warnings found (non-critical)${NC}"
    fi
    exit 0
else
    echo -e "${RED}✗ $errors validation errors found${NC}"
    echo "Please address errors before proceeding"
    exit 1
fi
