#!/bin/bash
# detect-drift.sh - Detect documentation drift in established codebases
# Usage: .claude/scripts/detect-drift.sh [--verbose] [--create-issues]
set -e

VERBOSE=false
CREATE_ISSUES=false
DRIFT_FOUND=0

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --verbose|-v)
      VERBOSE=true
      shift
      ;;
    --create-issues)
      CREATE_ISSUES=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--verbose] [--create-issues]"
      exit 1
      ;;
  esac
done

log() {
  if [ "$VERBOSE" = true ]; then
    echo "$1"
  fi
}

echo "🔍 Checking for documentation drift..."

# Check if loa-grimoire exists
if [ ! -d "loa-grimoire" ]; then
  echo "❌ loa-grimoire directory not found. Run /adopt first."
  exit 1
fi

# ============================================================================
# Schema Drift Detection
# ============================================================================

if [ -f "prisma/schema.prisma" ]; then
  log "Checking Prisma schema drift..."
  CURRENT_HASH=$(md5sum prisma/schema.prisma 2>/dev/null | cut -d' ' -f1)
  RECORDED_HASH=$(grep -o 'schema_hash: [a-f0-9]*' loa-grimoire/sdd.md 2>/dev/null | cut -d' ' -f2 || echo "")

  if [ -n "$RECORDED_HASH" ] && [ "$CURRENT_HASH" != "$RECORDED_HASH" ]; then
    echo "⚠️  Schema drift detected (Prisma)"
    echo "   Recorded: $RECORDED_HASH"
    echo "   Current:  $CURRENT_HASH"
    DRIFT_FOUND=1
    if [ "$CREATE_ISSUES" = true ] && command -v bd &> /dev/null; then
      bd create "Drift: Prisma schema changed, update SDD" -t task -p 2 -l drift,auto --json 2>/dev/null || true
    fi
  fi
fi

# Check for other schema files (TypeORM, Sequelize, etc.)
for schema_file in "src/entities/*.ts" "src/models/*.ts" "models/*.py"; do
  if compgen -G "$schema_file" > /dev/null 2>&1; then
    log "Checking schema files: $schema_file"
    CURRENT_COUNT=$(find . -path "./$schema_file" -type f 2>/dev/null | wc -l)
    DOCUMENTED_COUNT=$(grep -c "@Entity\|class.*Model" loa-grimoire/sdd.md 2>/dev/null || echo 0)

    if [ "$CURRENT_COUNT" -gt "$((DOCUMENTED_COUNT + 3))" ]; then
      echo "⚠️  New data models detected ($CURRENT_COUNT in code, ~$DOCUMENTED_COUNT documented)"
      DRIFT_FOUND=1
    fi
  fi
done

# ============================================================================
# API Route Drift Detection
# ============================================================================

log "Checking API route drift..."

# Count routes in code (TypeScript/JavaScript)
CURRENT_ROUTES=$(grep -rn "@Get\|@Post\|@Put\|@Delete\|@Patch\|router\.\(get\|post\|put\|delete\|patch\)\|app\.\(get\|post\|put\|delete\|patch\)" \
  --include="*.ts" --include="*.js" 2>/dev/null | \
  grep -v "node_modules\|dist\|build\|\.test\.\|\.spec\." | wc -l)

# Count documented routes in SDD
DOCUMENTED_ROUTES=$(grep -c "| GET\|| POST\|| PUT\|| DELETE\|| PATCH" loa-grimoire/sdd.md 2>/dev/null || echo 0)

log "Routes in code: $CURRENT_ROUTES"
log "Routes documented: $DOCUMENTED_ROUTES"

# Allow some buffer for internal/dev routes
if [ "$CURRENT_ROUTES" -gt "$((DOCUMENTED_ROUTES + 5))" ]; then
  echo "⚠️  New undocumented routes detected"
  echo "   In code: $CURRENT_ROUTES"
  echo "   Documented: $DOCUMENTED_ROUTES"
  DRIFT_FOUND=1
  if [ "$CREATE_ISSUES" = true ] && command -v bd &> /dev/null; then
    bd create "Drift: New API routes need documentation" -t task -p 3 -l drift,auto --json 2>/dev/null || true
  fi
fi

# ============================================================================
# Environment Variable Drift Detection
# ============================================================================

if [ -f "loa-grimoire/reality/env-vars.txt" ]; then
  log "Checking environment variable drift..."

  # Count current env vars in code
  CURRENT_ENVS=$(grep -roh 'process\.env\.\w\+\|os\.environ\[.\+\]\|os\.Getenv\(.\+\)' \
    --include="*.ts" --include="*.js" --include="*.py" --include="*.go" 2>/dev/null | \
    grep -v "node_modules\|dist\|build" | sort -u | wc -l)

  # Count recorded env vars
  RECORDED_ENVS=$(wc -l < loa-grimoire/reality/env-vars.txt 2>/dev/null || echo 0)

  log "Env vars in code: $CURRENT_ENVS"
  log "Env vars recorded: $RECORDED_ENVS"

  if [ "$CURRENT_ENVS" -gt "$((RECORDED_ENVS + 3))" ]; then
    echo "⚠️  New environment variables detected"
    echo "   In code: $CURRENT_ENVS"
    echo "   Recorded: $RECORDED_ENVS"
    DRIFT_FOUND=1
    if [ "$CREATE_ISSUES" = true ] && command -v bd &> /dev/null; then
      bd create "Drift: New env vars need documentation" -t task -p 3 -l drift,auto --json 2>/dev/null || true
    fi
  fi
fi

# ============================================================================
# Tech Debt Drift Detection
# ============================================================================

if [ -f "loa-grimoire/reality/tech-debt.txt" ]; then
  log "Checking tech debt drift..."

  # Count current TODO/FIXMEs
  CURRENT_DEBT=$(grep -rn "TODO\|FIXME\|HACK\|XXX\|BUG" \
    --include="*.ts" --include="*.js" --include="*.py" --include="*.go" 2>/dev/null | \
    grep -v "node_modules\|dist\|build\|\.test\.\|\.spec\." | wc -l)

  # Count recorded tech debt
  RECORDED_DEBT=$(wc -l < loa-grimoire/reality/tech-debt.txt 2>/dev/null || echo 0)

  log "Tech debt in code: $CURRENT_DEBT"
  log "Tech debt recorded: $RECORDED_DEBT"

  # New tech debt is concerning
  if [ "$CURRENT_DEBT" -gt "$((RECORDED_DEBT + 10))" ]; then
    echo "⚠️  Significant new tech debt detected"
    echo "   In code: $CURRENT_DEBT items"
    echo "   Recorded: $RECORDED_DEBT items"
    DRIFT_FOUND=1
  fi
fi

# ============================================================================
# Feature Flag Drift Detection
# ============================================================================

log "Checking feature flag drift..."

CURRENT_FLAGS=$(grep -rn "feature\|flag\|toggle\|isEnabled\|featureFlag" \
  --include="*.ts" --include="*.js" --include="*.py" 2>/dev/null | \
  grep -v "node_modules\|dist\|build\|\.test\.\|\.spec\." | wc -l)

if [ -f "loa-grimoire/reality/features-permissions.txt" ]; then
  RECORDED_FLAGS=$(wc -l < loa-grimoire/reality/features-permissions.txt 2>/dev/null || echo 0)

  if [ "$CURRENT_FLAGS" -gt "$((RECORDED_FLAGS + 5))" ]; then
    echo "⚠️  New feature flags detected"
    DRIFT_FOUND=1
  fi
fi

# ============================================================================
# Package.json / Dependencies Drift
# ============================================================================

if [ -f "package.json" ]; then
  log "Checking dependency drift..."

  # Count current dependencies
  CURRENT_DEPS=$(jq -r '.dependencies | keys | length' package.json 2>/dev/null || echo 0)
  CURRENT_DEV_DEPS=$(jq -r '.devDependencies | keys | length' package.json 2>/dev/null || echo 0)

  # Check if recorded in SDD
  if [ -f "loa-grimoire/sdd.md" ]; then
    DOCUMENTED_DEPS=$(grep -c "^\|.*\|.*\|" loa-grimoire/sdd.md 2>/dev/null | head -1 || echo 0)

    if [ "$((CURRENT_DEPS + CURRENT_DEV_DEPS))" -gt "$((DOCUMENTED_DEPS + 10))" ]; then
      echo "⚠️  Dependency changes detected"
      echo "   Current: $((CURRENT_DEPS + CURRENT_DEV_DEPS)) dependencies"
      DRIFT_FOUND=1
    fi
  fi
fi

# ============================================================================
# Summary
# ============================================================================

echo ""
if [ "$DRIFT_FOUND" -eq 0 ]; then
  echo "✅ No significant drift detected"
  echo ""
  echo "Last check: $(date -Iseconds)"
else
  echo "📋 Drift Summary"
  echo "   Drift items found - review and update documentation"
  echo ""
  echo "Recommended actions:"
  echo "   1. Run /adopt --phase drift to regenerate drift report"
  echo "   2. Review loa-grimoire/drift-report.md"
  echo "   3. Update PRD and SDD with new code evidence"
  echo ""
  if [ "$CREATE_ISSUES" = false ]; then
    echo "Tip: Run with --create-issues to auto-create Beads tasks"
  fi
fi

exit 0
