#!/usr/bin/env bash
# CI/CD Validation Script for ck Integration
# Verifies integrity and completeness of ck semantic search integration
#
# Exit Codes:
#   0: All checks passed
#   1: Critical failure (missing required files)
#   2: Warning (non-critical issues)
#
# Usage:
#   ./validate-ck-integration.sh [--strict]

set -euo pipefail

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

# Parse arguments
STRICT_MODE=false
if [ "${1:-}" = "--strict" ]; then
    STRICT_MODE=true
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
checks_passed=0
checks_failed=0
checks_warned=0

log_section() {
    echo ""
    echo -e "${BLUE}=== $* ===${NC}"
}

log_check() {
    echo -n "  Checking: $*... "
}

pass() {
    echo -e "${GREEN}✓ PASS${NC}"
    ((checks_passed++)) || true
}

fail() {
    echo -e "${RED}✗ FAIL${NC}"
    echo -e "    ${RED}$*${NC}"
    ((checks_failed++)) || true
}

warn() {
    echo -e "${YELLOW}⚠ WARN${NC}"
    echo -e "    ${YELLOW}$*${NC}"
    ((checks_warned++)) || true
}

# ============================================================================
# Check 1: Required Scripts Exist
# ============================================================================

log_section "Required Scripts"

required_scripts=(
    ".claude/scripts/preflight.sh"
    ".claude/scripts/search-orchestrator.sh"
    ".claude/scripts/search-api.sh"
    ".claude/scripts/filter-search-results.sh"
    ".claude/scripts/compact-trajectory.sh"
    ".claude/scripts/validate-protocols.sh"
)

for script in "${required_scripts[@]}"; do
    log_check "$script"
    if [ -f "${PROJECT_ROOT}/${script}" ]; then
        if [ -x "${PROJECT_ROOT}/${script}" ]; then
            pass
        else
            fail "File exists but not executable"
        fi
    else
        fail "File missing"
    fi
done

# ============================================================================
# Check 2: Required Protocols Documented
# ============================================================================

log_section "Protocol Documentation"

required_protocols=(
    ".claude/protocols/preflight-integrity.md"
    ".claude/protocols/tool-result-clearing.md"
    ".claude/protocols/trajectory-evaluation.md"
    ".claude/protocols/negative-grounding.md"
    ".claude/protocols/search-fallback.md"
    ".claude/protocols/citations.md"
    ".claude/protocols/self-audit-checkpoint.md"
    ".claude/protocols/edd-verification.md"
)

for protocol in "${required_protocols[@]}"; do
    log_check "$(basename "$protocol")"
    if [ -f "${PROJECT_ROOT}/${protocol}" ]; then
        # Check minimum content
        if [ $(wc -l < "${PROJECT_ROOT}/${protocol}") -gt 10 ]; then
            pass
        else
            warn "Protocol too brief (may be incomplete)"
        fi
    else
        fail "Protocol missing"
    fi
done

# ============================================================================
# Check 3: Checksum File Integrity
# ============================================================================

log_section "Integrity Verification"

log_check "Checksums file exists"
if [ -f "${PROJECT_ROOT}/.claude/checksums.json" ]; then
    pass
else
    warn "Checksums file missing (run update.sh to generate)"
fi

log_check "Integrity enforcement configured"
if [ -f "${PROJECT_ROOT}/.loa.config.yaml" ]; then
    if grep -q "integrity_enforcement:" "${PROJECT_ROOT}/.loa.config.yaml"; then
        pass
    else
        warn "integrity_enforcement not configured (defaults to warn)"
    fi
else
    warn ".loa.config.yaml missing"
fi

# ============================================================================
# Check 4: Trajectory Logs Structure
# ============================================================================

log_section "Trajectory Logging"

log_check "Trajectory directory structure"
if [ -d "${PROJECT_ROOT}/loa-grimoire/a2a/trajectory" ]; then
    pass
else
    warn "Trajectory directory missing (will be created on first use)"
fi

log_check ".gitignore excludes trajectory logs"
if [ -f "${PROJECT_ROOT}/.gitignore" ]; then
    if grep -q "loa-grimoire/a2a/trajectory/" "${PROJECT_ROOT}/.gitignore"; then
        pass
    else
        fail "Trajectory logs not in .gitignore"
    fi
else
    warn ".gitignore missing"
fi

# ============================================================================
# Check 5: Search API Functions Exported
# ============================================================================

log_section "Search API"

log_check "Search API functions sourcing"
if source "${PROJECT_ROOT}/.claude/scripts/search-api.sh" 2>/dev/null; then
    # Check function exports
    if type semantic_search >/dev/null 2>&1 && \
       type hybrid_search >/dev/null 2>&1 && \
       type regex_search >/dev/null 2>&1 && \
       type grep_to_jsonl >/dev/null 2>&1; then
        pass
    else
        fail "Not all functions exported"
    fi
else
    fail "Cannot source search-api.sh"
fi

# ============================================================================
# Check 6: .gitignore Updates
# ============================================================================

log_section ".gitignore Configuration"

gitignore_entries=(
    ".beads/"
    ".ck/"
    "loa-grimoire/a2a/trajectory/"
)

for entry in "${gitignore_entries[@]}"; do
    log_check "gitignore: $entry"
    if [ -f "${PROJECT_ROOT}/.gitignore" ]; then
        if grep -qF "$entry" "${PROJECT_ROOT}/.gitignore"; then
            pass
        else
            fail "Missing gitignore entry"
        fi
    else
        fail ".gitignore missing"
    fi
done

# ============================================================================
# Check 7: Test Suite Structure
# ============================================================================

log_section "Test Suite"

log_check "Unit tests directory"
if [ -d "${PROJECT_ROOT}/tests/unit" ]; then
    test_count=$(find "${PROJECT_ROOT}/tests/unit" -name "*.bats" | wc -l)
    if [ "$test_count" -gt 0 ]; then
        pass
        echo "    Found $test_count test files"
    else
        warn "No test files found"
    fi
else
    fail "Unit tests directory missing"
fi

log_check "Integration tests directory"
if [ -d "${PROJECT_ROOT}/tests/integration" ]; then
    pass
else
    warn "Integration tests directory missing"
fi

log_check "Performance tests directory"
if [ -d "${PROJECT_ROOT}/tests/performance" ]; then
    pass
else
    warn "Performance tests directory missing"
fi

log_check "Test runner script"
if [ -f "${PROJECT_ROOT}/tests/run-unit-tests.sh" ]; then
    if [ -x "${PROJECT_ROOT}/tests/run-unit-tests.sh" ]; then
        pass
    else
        warn "Test runner not executable"
    fi
else
    fail "Test runner missing"
fi

# ============================================================================
# Check 8: Optional Enhancements Documentation
# ============================================================================

log_section "Documentation"

log_check "INSTALLATION.md mentions ck"
if [ -f "${PROJECT_ROOT}/INSTALLATION.md" ]; then
    if grep -qi "ck\|semantic search" "${PROJECT_ROOT}/INSTALLATION.md"; then
        pass
    else
        warn "INSTALLATION.md does not mention ck integration"
    fi
else
    warn "INSTALLATION.md missing"
fi

log_check "README.md mentions ck"
if [ -f "${PROJECT_ROOT}/README.md" ]; then
    if grep -qi "ck\|semantic search" "${PROJECT_ROOT}/README.md"; then
        pass
    else
        warn "README.md does not mention ck"
    fi
else
    warn "README.md missing"
fi

# ============================================================================
# Check 9: MCP Registry (Optional)
# ============================================================================

log_section "MCP Integration (Optional)"

log_check "MCP registry script"
if [ -f "${PROJECT_ROOT}/.claude/scripts/mcp-registry.sh" ]; then
    pass
else
    warn "MCP registry script missing"
fi

log_check "MCP validation script"
if [ -f "${PROJECT_ROOT}/.claude/scripts/validate-mcp.sh" ]; then
    pass
else
    warn "MCP validation script missing"
fi

# ============================================================================
# Check 10: Script Consistency
# ============================================================================

log_section "Script Standards"

# Check all scripts use set -euo pipefail
log_check "Scripts use set -euo pipefail"
scripts_without_safeguards=()
for script in "${required_scripts[@]}"; do
    if [ -f "${PROJECT_ROOT}/${script}" ]; then
        if ! grep -q "set -euo pipefail" "${PROJECT_ROOT}/${script}"; then
            scripts_without_safeguards+=("$script")
        fi
    fi
done

if [ ${#scripts_without_safeguards[@]} -eq 0 ]; then
    pass
else
    fail "Scripts without safeguards: ${scripts_without_safeguards[*]}"
fi

# Check all scripts have PROJECT_ROOT
log_check "Scripts define PROJECT_ROOT"
scripts_without_root=()
for script in "${required_scripts[@]}"; do
    if [ -f "${PROJECT_ROOT}/${script}" ]; then
        if ! grep -q "PROJECT_ROOT" "${PROJECT_ROOT}/${script}"; then
            scripts_without_root+=("$script")
        fi
    fi
done

if [ ${#scripts_without_root[@]} -eq 0 ]; then
    pass
else
    warn "Scripts without PROJECT_ROOT: ${scripts_without_root[*]}"
fi

# ============================================================================
# Summary
# ============================================================================

echo ""
echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}Validation Summary${NC}"
echo -e "${BLUE}======================================${NC}"
echo -e "Checks Passed:  ${GREEN}${checks_passed}${NC}"
echo -e "Checks Failed:  ${RED}${checks_failed}${NC}"
echo -e "Checks Warned:  ${YELLOW}${checks_warned}${NC}"
echo ""

# Determine exit code
if [ "$checks_failed" -gt 0 ]; then
    echo -e "${RED}✗ VALIDATION FAILED${NC}"
    echo "Critical issues found. Please fix failures before deploying."
    exit 1
elif [ "$checks_warned" -gt 0 ]; then
    if [ "$STRICT_MODE" = true ]; then
        echo -e "${YELLOW}⚠ VALIDATION WARNINGS (Strict Mode)${NC}"
        echo "Warnings treated as failures in strict mode."
        exit 2
    else
        echo -e "${YELLOW}⚠ VALIDATION PASSED WITH WARNINGS${NC}"
        echo "Non-critical issues found. Consider addressing warnings."
        exit 0
    fi
else
    echo -e "${GREEN}✓ VALIDATION PASSED${NC}"
    echo "All checks passed successfully."
    exit 0
fi
