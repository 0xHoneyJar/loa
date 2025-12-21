#!/bin/bash
# validate-change-plan.sh - Validate a change plan before applying refactoring
# Usage: .claude/scripts/validate-change-plan.sh <plan.json>
set -e

PLAN_FILE="$1"
ERRORS=0
WARNINGS=0

if [ -z "$PLAN_FILE" ] || [ ! -f "$PLAN_FILE" ]; then
  echo "❌ Usage: validate-change-plan.sh <plan.json>"
  echo ""
  echo "Example: .claude/scripts/validate-change-plan.sh loa-grimoire/plans/change-bd-123.json"
  exit 1
fi

echo "🔍 Validating change plan: $PLAN_FILE"
echo ""

# ============================================================================
# JSON Validation
# ============================================================================

if ! jq empty "$PLAN_FILE" 2>/dev/null; then
  echo "❌ Invalid JSON in plan file"
  exit 1
fi

# ============================================================================
# Required Fields Check
# ============================================================================

echo "Checking required fields..."

REQUIRED_FIELDS=("task_id" "freedom_level" "file" "current_behavior" "proposed_change" "rollback")

for field in "${REQUIRED_FIELDS[@]}"; do
  value=$(jq -r ".$field // empty" "$PLAN_FILE" 2>/dev/null)
  if [ -z "$value" ]; then
    echo "❌ Missing required field: $field"
    ((ERRORS++))
  else
    echo "✅ $field: present"
  fi
done

# ============================================================================
# File Existence Check
# ============================================================================

echo ""
echo "Checking affected files..."

TARGET_FILE=$(jq -r '.file // empty' "$PLAN_FILE" 2>/dev/null)
if [ -n "$TARGET_FILE" ]; then
  if [ -f "$TARGET_FILE" ]; then
    echo "✅ Target file exists: $TARGET_FILE"
  else
    echo "❌ Target file not found: $TARGET_FILE"
    ((ERRORS++))
  fi
fi

# Check additional files if files_affected array exists
if jq -e '.files_affected' "$PLAN_FILE" > /dev/null 2>&1; then
  for file in $(jq -r '.files_affected[].path' "$PLAN_FILE" 2>/dev/null); do
    if [ -f "$file" ]; then
      echo "✅ File exists: $file"
    else
      echo "❌ File not found: $file"
      ((ERRORS++))
    fi
  done
fi

# ============================================================================
# Protected File Check
# ============================================================================

echo ""
echo "Checking for protected files..."

check_protected() {
  local file="$1"
  if [ -f "$file" ]; then
    if grep -q "DO NOT MODIFY\|GENERATED FILE\|AUTO-GENERATED\|@generated" "$file" 2>/dev/null; then
      echo "❌ Protected file detected: $file"
      echo "   Contains protection marker - manual override required"
      ((ERRORS++))
      return 1
    fi
  fi
  return 0
}

if [ -n "$TARGET_FILE" ] && [ -f "$TARGET_FILE" ]; then
  if check_protected "$TARGET_FILE"; then
    echo "✅ No protection markers in target file"
  fi
fi

# ============================================================================
# Freedom Level Validation
# ============================================================================

echo ""
echo "Validating freedom level..."

FREEDOM=$(jq -r '.freedom_level // empty' "$PLAN_FILE" 2>/dev/null)
VALID_LEVELS=("high" "medium" "low" "very_low" "minimal")

if [[ " ${VALID_LEVELS[*]} " =~ " ${FREEDOM} " ]]; then
  echo "✅ Valid freedom level: $FREEDOM"
else
  echo "❌ Invalid freedom level: $FREEDOM"
  echo "   Valid values: ${VALID_LEVELS[*]}"
  ((ERRORS++))
fi

# Warn if low freedom but missing callers analysis
if [[ "$FREEDOM" == "low" || "$FREEDOM" == "very_low" || "$FREEDOM" == "minimal" ]]; then
  CALLERS=$(jq -r '.callers // empty' "$PLAN_FILE" 2>/dev/null)
  if [ -z "$CALLERS" ] || [ "$CALLERS" == "null" ]; then
    echo "⚠️  Warning: Low freedom level but no callers analysis provided"
    ((WARNINGS++))
  fi
fi

# ============================================================================
# Test Files Check
# ============================================================================

echo ""
echo "Checking test coverage..."

if jq -e '.test_files' "$PLAN_FILE" > /dev/null 2>&1; then
  TEST_COUNT=0
  MISSING_TESTS=0

  for test_file in $(jq -r '.test_files[]' "$PLAN_FILE" 2>/dev/null); do
    if [ -f "$test_file" ]; then
      echo "✅ Test file exists: $test_file"
      ((TEST_COUNT++))
    else
      echo "⚠️  Test file not found: $test_file"
      ((MISSING_TESTS++))
    fi
  done

  if [ "$TEST_COUNT" -eq 0 ]; then
    echo "⚠️  Warning: No existing test files found"
    ((WARNINGS++))
  fi
else
  echo "⚠️  Warning: No test_files specified in plan"
  ((WARNINGS++))
fi

# ============================================================================
# Rollback Command Check
# ============================================================================

echo ""
echo "Checking rollback command..."

ROLLBACK=$(jq -r '.rollback // empty' "$PLAN_FILE" 2>/dev/null)
if [ -n "$ROLLBACK" ]; then
  if [[ "$ROLLBACK" == git* ]]; then
    echo "✅ Rollback command: $ROLLBACK"
  else
    echo "⚠️  Warning: Rollback command doesn't use git"
    echo "   Command: $ROLLBACK"
    ((WARNINGS++))
  fi
else
  echo "❌ No rollback command specified"
  ((ERRORS++))
fi

# ============================================================================
# Risk Assessment Check
# ============================================================================

echo ""
echo "Checking risk assessment..."

if jq -e '.risks' "$PLAN_FILE" > /dev/null 2>&1; then
  RISK_COUNT=$(jq '.risks | length' "$PLAN_FILE" 2>/dev/null)
  echo "✅ Risks documented: $RISK_COUNT"

  # Check each risk has mitigation
  UNMITIGATED=0
  for i in $(seq 0 $((RISK_COUNT - 1))); do
    MITIGATION=$(jq -r ".risks[$i].mitigation // empty" "$PLAN_FILE" 2>/dev/null)
    if [ -z "$MITIGATION" ]; then
      ((UNMITIGATED++))
    fi
  done

  if [ "$UNMITIGATED" -gt 0 ]; then
    echo "⚠️  Warning: $UNMITIGATED risk(s) without mitigation"
    ((WARNINGS++))
  fi
else
  if [[ "$FREEDOM" != "high" ]]; then
    echo "⚠️  Warning: No risks documented for non-high freedom change"
    ((WARNINGS++))
  fi
fi

# ============================================================================
# Test Runner Check
# ============================================================================

echo ""
echo "Checking test infrastructure..."

if [ -f "package.json" ]; then
  if jq -e '.scripts.test' package.json > /dev/null 2>&1; then
    echo "✅ npm test configured"
  else
    echo "⚠️  Warning: No test script in package.json"
    ((WARNINGS++))
  fi
fi

if [ -f "pytest.ini" ] || [ -f "pyproject.toml" ]; then
  echo "✅ Python test configuration found"
fi

if [ -f "go.mod" ]; then
  echo "✅ Go module found (use 'go test')"
fi

# ============================================================================
# Summary
# ============================================================================

echo ""
echo "════════════════════════════════════════"
echo "Validation Summary"
echo "════════════════════════════════════════"
echo "Errors:   $ERRORS"
echo "Warnings: $WARNINGS"
echo ""

if [ "$ERRORS" -gt 0 ]; then
  echo "❌ Validation FAILED - fix errors before proceeding"
  exit 1
elif [ "$WARNINGS" -gt 0 ]; then
  echo "⚠️  Validation PASSED with warnings"
  echo "   Review warnings before proceeding"
  exit 0
else
  echo "✅ Validation PASSED"
  echo "   Safe to proceed with change"
  exit 0
fi
