#!/usr/bin/env bash
#
# validate-change-plan.sh - Validate proposed changes against codebase reality
#
# Usage:
#   .claude/scripts/validate-change-plan.sh <plan-file>
#
# Validates that:
#   1. Referenced files exist
#   2. Referenced functions/methods exist
#   3. Referenced dependencies are installed
#   4. No conflicts with existing code
#
# Output:
#   Validation report with warnings and blockers
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

PLAN_FILE="${1:-}"

if [[ -z "$PLAN_FILE" ]]; then
  echo "Usage: validate-change-plan.sh <plan-file>"
  echo ""
  echo "Example:"
  echo "  .claude/scripts/validate-change-plan.sh grimoires/loa/sprint.md"
  exit 1
fi

if [[ ! -f "$PLAN_FILE" ]]; then
  echo -e "${RED}❌ Plan file not found: $PLAN_FILE${NC}"
  exit 1
fi

echo "🔍 Validating Change Plan"
echo "========================="
echo "Plan file: $PLAN_FILE"
echo ""

WARNINGS=0
BLOCKERS=0

# Extract file references from plan
echo -e "${BLUE}📂 Checking file references...${NC}"
echo ""

# Look for file paths in various formats
grep -oE '`[^`]+\.(ts|js|py|go|md|json|yaml|yml)`|src/[^\s]+|lib/[^\s]+|app/[^\s]+' "$PLAN_FILE" 2>/dev/null | \
  sed 's/`//g' | sort -u | while read file; do
  # Remove trailing punctuation
  file="${file%,}"
  file="${file%)}"
  file="${file%.}"

  if [[ -f "$PROJECT_ROOT/$file" ]]; then
    echo -e "  ${GREEN}✓ Found: $file${NC}"
  elif [[ -d "$PROJECT_ROOT/$file" ]]; then
    echo -e "  ${GREEN}✓ Dir exists: $file${NC}"
  else
    echo -e "  ${YELLOW}⚠️ Not found: $file${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi
done

echo ""

# Extract function/method references
echo -e "${BLUE}🔧 Checking function references...${NC}"
echo ""

# Look for function references like functionName() or ClassName.methodName()
grep -oE '\b[a-zA-Z_][a-zA-Z0-9_]*\s*\(' "$PLAN_FILE" 2>/dev/null | \
  sed 's/($//' | sort -u | head -20 | while read func; do
  # Skip common words and built-ins
  case "$func" in
    if|for|while|switch|function|class|interface|type|import|export|return|async|await|const|let|var)
      continue
      ;;
  esac

  # Search for function definition in codebase
  if grep -rq "function $func\|const $func\|def $func\|func $func" \
    --include="*.ts" --include="*.js" --include="*.py" --include="*.go" \
    "$PROJECT_ROOT" 2>/dev/null; then
    echo -e "  ${GREEN}✓ Found: $func()${NC}"
  else
    # It might be new, just note it
    echo -e "  ${BLUE}ℹ️ New or external: $func()${NC}"
  fi
done

echo ""

# Check for dependency references
echo -e "${BLUE}📦 Checking dependency references...${NC}"
echo ""

# Extract npm package references
grep -oE '"[a-z@][a-z0-9@/-]+"' "$PLAN_FILE" 2>/dev/null | \
  sed 's/"//g' | sort -u | head -10 | while read pkg; do
  # Skip if it looks like a file path
  [[ "$pkg" == *"/"* && "$pkg" != "@"* ]] && continue

  if [[ -f "$PROJECT_ROOT/package.json" ]]; then
    if grep -q "\"$pkg\"" "$PROJECT_ROOT/package.json" 2>/dev/null; then
      echo -e "  ${GREEN}✓ Installed: $pkg${NC}"
    else
      echo -e "  ${YELLOW}⚠️ Not installed: $pkg (may need npm install)${NC}"
      WARNINGS=$((WARNINGS + 1))
    fi
  fi
done

echo ""

# Check for potential conflicts
echo -e "${BLUE}⚡ Checking for potential conflicts...${NC}"
echo ""

# Look for "modify" or "change" statements and verify target exists
grep -iE "modify|change|update|delete|remove|rename" "$PLAN_FILE" 2>/dev/null | head -10 | while read line; do
  # Extract file reference from the line
  file=$(echo "$line" | grep -oE '`[^`]+`|src/[^\s]+|lib/[^\s]+' | head -1 | sed 's/`//g')

  if [[ -n "$file" && -f "$PROJECT_ROOT/$file" ]]; then
    # Check if file has uncommitted changes
    if git -C "$PROJECT_ROOT" diff --quiet "$file" 2>/dev/null; then
      echo -e "  ${GREEN}✓ Clean: $file${NC}"
    else
      echo -e "  ${YELLOW}⚠️ Uncommitted changes: $file${NC}"
      WARNINGS=$((WARNINGS + 1))
    fi
  fi
done

echo ""

# Check for breaking change indicators
echo -e "${BLUE}💥 Checking for breaking changes...${NC}"
echo ""

if grep -qiE "breaking|incompatible|migration required|schema change" "$PLAN_FILE" 2>/dev/null; then
  echo -e "  ${RED}❌ Breaking changes indicated - review carefully${NC}"
  BLOCKERS=$((BLOCKERS + 1))
  grep -iE "breaking|incompatible|migration required|schema change" "$PLAN_FILE" | head -5 | while read line; do
    echo -e "     ${line:0:80}..."
  done
else
  echo -e "  ${GREEN}✓ No breaking changes indicated${NC}"
fi

echo ""

# Summary
echo "========================="
echo "📊 Validation Summary"
echo "========================="
echo ""

if [[ $BLOCKERS -gt 0 ]]; then
  echo -e "${RED}❌ BLOCKERS: $BLOCKERS${NC}"
  echo "   Review breaking changes before proceeding"
fi

if [[ $WARNINGS -gt 0 ]]; then
  echo -e "${YELLOW}⚠️ WARNINGS: $WARNINGS${NC}"
  echo "   Some references may need attention"
fi

if [[ $BLOCKERS -eq 0 && $WARNINGS -eq 0 ]]; then
  echo -e "${GREEN}✅ Plan validation passed${NC}"
  echo "   All referenced files and functions found"
fi

echo ""

# Exit with appropriate code
if [[ $BLOCKERS -gt 0 ]]; then
  exit 2
elif [[ $WARNINGS -gt 0 ]]; then
  exit 1
else
  exit 0
fi
