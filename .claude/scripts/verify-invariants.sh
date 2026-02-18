#!/usr/bin/env bash
# verify-invariants.sh - Verify cross-repository invariant declarations
# Version: 1.0.0
#
# Reads grimoires/loa/invariants.yaml, locates each verified_in reference,
# and confirms the referenced function/class exists in the codebase.
#
# Usage:
#   .claude/scripts/verify-invariants.sh [OPTIONS]
#
# Exit Codes:
#   0 - All local invariants verified
#   1 - One or more local invariants failed verification
#   2 - Configuration error (missing file, bad YAML)

export LC_ALL=C
export TZ=UTC

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# =============================================================================
# Defaults
# =============================================================================

INVARIANTS_FILE="${REPO_ROOT}/grimoires/loa/invariants.yaml"
JSON_OUT="false"
QUIET="false"

PASSES=0
FAILURES=0
SKIPS=0
CHECKS=()

# =============================================================================
# Logging (compatible with butterfreezone-validate.sh pattern)
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

log_skip() {
    SKIPS=$((SKIPS + 1))
    local detail="${3:-}"
    if [[ -n "$detail" ]]; then
        CHECKS+=("$(jq -nc --arg name "$1" --arg status "skip" --arg detail "$detail" '{name: $name, status: $status, detail: $detail}')")
    else
        CHECKS+=("$(jq -nc --arg name "$1" --arg status "skip" '{name: $name, status: $status}')")
    fi
    [[ "$QUIET" == "true" ]] && return 0
    echo "  SKIP: $2"
}

# =============================================================================
# Usage
# =============================================================================

usage() {
    cat <<'USAGE'
Usage: verify-invariants.sh [OPTIONS]

Verify cross-repository invariant declarations against the codebase.

Options:
  --file PATH        Invariants file (default: grimoires/loa/invariants.yaml)
  --json             Output results as JSON
  --quiet            Suppress output, exit code only
  --help             Show usage

Exit codes:
  0  All local invariants verified
  1  One or more local invariants failed
  2  Configuration error
USAGE
}

# =============================================================================
# Argument Parsing
# =============================================================================

while [[ $# -gt 0 ]]; do
    case "$1" in
        --file)   INVARIANTS_FILE="$2"; shift 2 ;;
        --json)   JSON_OUT="true"; QUIET="true"; shift ;;
        --quiet)  QUIET="true"; shift ;;
        --help)   usage; exit 0 ;;
        *)        echo "Unknown option: $1"; usage; exit 2 ;;
    esac
done

# =============================================================================
# Pre-flight
# =============================================================================

if [[ ! -f "$INVARIANTS_FILE" ]]; then
    if [[ "$JSON_OUT" == "true" ]]; then
        jq -nc '{"status": "error", "message": "Invariants file not found", "checks": []}'
    else
        echo "ERROR: Invariants file not found: $INVARIANTS_FILE"
    fi
    exit 2
fi

# Check yq availability
if ! command -v yq &>/dev/null; then
    echo "ERROR: yq (mikefarah/yq) is required but not installed"
    exit 2
fi

# =============================================================================
# Validate YAML structure
# =============================================================================

SCHEMA_VERSION=$(yq '.schema_version // 0' "$INVARIANTS_FILE")
if [[ "$SCHEMA_VERSION" != "1" ]]; then
    echo "ERROR: Unsupported schema_version: $SCHEMA_VERSION (expected 1)"
    exit 2
fi

INVARIANT_COUNT=$(yq '.invariants | length' "$INVARIANTS_FILE")
if [[ "$INVARIANT_COUNT" == "0" ]]; then
    if [[ "$JSON_OUT" == "true" ]]; then
        jq -nc '{"status": "pass", "message": "No invariants declared", "passes": 0, "failures": 0, "skips": 0, "checks": []}'
    else
        echo "No invariants declared in $INVARIANTS_FILE"
    fi
    exit 0
fi

[[ "$QUIET" != "true" ]] && echo "Verifying $INVARIANT_COUNT invariants from $INVARIANTS_FILE"
[[ "$QUIET" != "true" ]] && echo ""

# =============================================================================
# Verify each invariant
# =============================================================================

for i in $(seq 0 $((INVARIANT_COUNT - 1))); do
    INV_ID=$(yq ".invariants[$i].id" "$INVARIANTS_FILE")
    INV_DESC=$(yq ".invariants[$i].description" "$INVARIANTS_FILE" | head -c 80)
    INV_SEVERITY=$(yq ".invariants[$i].severity" "$INVARIANTS_FILE")

    [[ "$QUIET" != "true" ]] && echo "[$INV_ID] ($INV_SEVERITY) $INV_DESC..."

    REF_COUNT=$(yq ".invariants[$i].verified_in | length" "$INVARIANTS_FILE")

    for j in $(seq 0 $((REF_COUNT - 1))); do
        REF_REPO=$(yq ".invariants[$i].verified_in[$j].repo" "$INVARIANTS_FILE")
        REF_FILE=$(yq ".invariants[$i].verified_in[$j].file" "$INVARIANTS_FILE")
        REF_SYMBOL=$(yq ".invariants[$i].verified_in[$j].symbol" "$INVARIANTS_FILE")

        CHECK_NAME="${INV_ID}:${REF_REPO}:${REF_FILE}:${REF_SYMBOL}"

        # Cross-repo references: skip (verified in external CI)
        if [[ "$REF_REPO" != "loa" ]]; then
            log_skip "$CHECK_NAME" \
                "$INV_ID ref $REF_REPO:$REF_FILE:$REF_SYMBOL — external repo (verified in $REF_REPO CI)" \
                "Cross-repo reference: $REF_REPO"
            continue
        fi

        # Verify file exists
        FULL_PATH="${REPO_ROOT}/${REF_FILE}"
        if [[ ! -f "$FULL_PATH" ]]; then
            log_fail "$CHECK_NAME" \
                "$INV_ID ref $REF_FILE:$REF_SYMBOL — file not found" \
                "File not found: $REF_FILE"
            continue
        fi

        # Verify symbol exists in file
        # Handle different definition patterns:
        #   - Python: def symbol( / class symbol( / class symbol:
        #   - YAML: key: symbol (top-level key)
        #   - Shell: symbol() {
        if [[ "$REF_FILE" == *.py ]]; then
            # Python: match def/class followed by symbol name
            if grep -qE "(def |class )${REF_SYMBOL}[^a-zA-Z_]" "$FULL_PATH"; then
                log_pass "$CHECK_NAME" \
                    "$INV_ID ref $REF_FILE:$REF_SYMBOL — found"
            else
                log_fail "$CHECK_NAME" \
                    "$INV_ID ref $REF_FILE:$REF_SYMBOL — symbol not found in file" \
                    "Symbol '$REF_SYMBOL' not found in $REF_FILE"
            fi
        elif [[ "$REF_FILE" == *.yaml || "$REF_FILE" == *.yml ]]; then
            # YAML: match top-level key
            if grep -qE "^${REF_SYMBOL}:" "$FULL_PATH"; then
                log_pass "$CHECK_NAME" \
                    "$INV_ID ref $REF_FILE:$REF_SYMBOL — found"
            else
                log_fail "$CHECK_NAME" \
                    "$INV_ID ref $REF_FILE:$REF_SYMBOL — key not found in YAML" \
                    "Key '$REF_SYMBOL' not found in $REF_FILE"
            fi
        elif [[ "$REF_FILE" == *.sh ]]; then
            # Shell: match function definition
            if grep -qE "(function ${REF_SYMBOL}|${REF_SYMBOL}\(\))" "$FULL_PATH"; then
                log_pass "$CHECK_NAME" \
                    "$INV_ID ref $REF_FILE:$REF_SYMBOL — found"
            else
                log_fail "$CHECK_NAME" \
                    "$INV_ID ref $REF_FILE:$REF_SYMBOL — function not found in script" \
                    "Function '$REF_SYMBOL' not found in $REF_FILE"
            fi
        else
            # Generic: grep for the symbol name
            if grep -q "$REF_SYMBOL" "$FULL_PATH"; then
                log_pass "$CHECK_NAME" \
                    "$INV_ID ref $REF_FILE:$REF_SYMBOL — found"
            else
                log_fail "$CHECK_NAME" \
                    "$INV_ID ref $REF_FILE:$REF_SYMBOL — not found" \
                    "Symbol '$REF_SYMBOL' not found in $REF_FILE"
            fi
        fi
    done

    [[ "$QUIET" != "true" ]] && echo ""
done

# =============================================================================
# Output
# =============================================================================

if [[ "$JSON_OUT" == "true" ]]; then
    STATUS="pass"
    [[ "$FAILURES" -gt 0 ]] && STATUS="fail"

    # Build JSON array of checks
    CHECKS_JSON="["
    for idx in "${!CHECKS[@]}"; do
        [[ $idx -gt 0 ]] && CHECKS_JSON+=","
        CHECKS_JSON+="${CHECKS[$idx]}"
    done
    CHECKS_JSON+="]"

    jq -nc \
        --arg status "$STATUS" \
        --argjson passes "$PASSES" \
        --argjson failures "$FAILURES" \
        --argjson skips "$SKIPS" \
        --argjson checks "$CHECKS_JSON" \
        '{status: $status, passes: $passes, failures: $failures, skips: $skips, checks: $checks}'
else
    echo "────────────────────────────────────────"
    echo "Results: $PASSES passed, $FAILURES failed, $SKIPS skipped"
    if [[ "$FAILURES" -gt 0 ]]; then
        echo "Status: FAIL"
    else
        echo "Status: PASS"
    fi
fi

# Exit code
if [[ "$FAILURES" -gt 0 ]]; then
    exit 1
else
    exit 0
fi
