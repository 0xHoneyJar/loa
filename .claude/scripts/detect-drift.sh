#!/usr/bin/env bash
#
# detect-drift.sh - Detect drift between code and documentation
#
# Usage:
#   .claude/scripts/detect-drift.sh [--quick|--full]
#
# Options:
#   --quick    Quick check for obvious drift (default)
#   --full     Full drift analysis (slower, more thorough)
#
# Output:
#   Prints drift status and optionally updates grimoires/loa/drift-report.md
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOA_CONFIG="${PROJECT_ROOT}/.loa.config.yaml"

# =============================================================================
# SECURITY: Path Validation (HIGH-001 fix)
# =============================================================================
# Validates paths to prevent directory traversal attacks.

# Validate path is safe and within project root
# Args:
#   $1 - Path to validate (relative to project root)
# Returns: 0 if safe, 1 if unsafe
# Outputs: Validated absolute path on stdout
validate_path_safe() {
    local base_dir="$1"
    local path="$2"
    local resolved

    # Reject obviously malicious patterns
    if [[ "$path" == *".."* ]] || [[ "$path" == "/"* ]]; then
        echo "ERROR: Path contains traversal sequence or is absolute: $path" >&2
        return 1
    fi

    # Resolve path (don't follow symlinks with -m to avoid TOCTOU)
    resolved=$(realpath -m "${base_dir}/${path}" 2>/dev/null) || {
        echo "ERROR: Invalid path: $path" >&2
        return 1
    }

    # Ensure within base directory
    if [[ ! "$resolved" =~ ^"$base_dir" ]]; then
        echo "ERROR: Path traversal detected: $path resolves to $resolved" >&2
        return 1
    fi

    echo "$resolved"
}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

MODE="${1:-quick}"
DRIFT_COUNT=0
SHADOW_COUNT=0
GHOST_COUNT=0

echo "🔍 Drift Detection - Mode: $MODE"
echo "================================"
echo ""

# Check if grimoire exists
if [[ ! -d "$PROJECT_ROOT/grimoires/loa" ]]; then
  echo -e "${YELLOW}⚠️ No grimoires/loa found. Run /mount first.${NC}"
  exit 0
fi

# Sprint 4 Enhancement: Load configurable watch paths (FR-9.1, GitHub Issue #10)
# Default watch paths if config not available
DEFAULT_WATCH_PATHS=(".claude/" "grimoires/loa/")
WATCH_PATHS=()

if command -v yq >/dev/null 2>&1 && [[ -f "${LOA_CONFIG}" ]]; then
    # Load watch paths from configuration
    while IFS= read -r path; do
        if [[ -n "${path}" ]] && [[ "${path}" != "null" ]]; then
            WATCH_PATHS+=("${path}")
        fi
    done < <(yq eval '.drift_detection.watch_paths[]' "${LOA_CONFIG}" 2>/dev/null || echo "")

    # Fall back to defaults if no paths configured
    if [[ ${#WATCH_PATHS[@]} -eq 0 ]]; then
        WATCH_PATHS=("${DEFAULT_WATCH_PATHS[@]}")
    fi
else
    # No yq or config, use defaults
    WATCH_PATHS=("${DEFAULT_WATCH_PATHS[@]}")
fi

# Function: Check git status for watched paths
check_watched_paths_drift() {
    echo "📂 Checking watched directories for uncommitted changes..."
    echo ""

    local has_drift=false

    for watch_path in "${WATCH_PATHS[@]}"; do
        # SECURITY: Validate path before use (HIGH-001 fix)
        local full_path
        full_path=$(validate_path_safe "${PROJECT_ROOT}" "${watch_path}") || {
            echo -e "${RED}⚠️ Skipping invalid watch path: ${watch_path}${NC}"
            continue
        }

        if [[ ! -d "${full_path}" ]]; then
            # Directory doesn't exist, skip
            continue
        fi

        # Check git status for this path (use validated path)
        local changes=$(cd "${PROJECT_ROOT}" && git status --porcelain "${watch_path}" 2>/dev/null || echo "")

        if [[ -n "${changes}" ]]; then
            echo -e "${YELLOW}⚠️ Drift detected in ${watch_path}:${NC}"
            echo "${changes}" | head -10
            if [[ $(echo "${changes}" | wc -l) -gt 10 ]]; then
                echo "   ... and $(($(echo "${changes}" | wc -l) - 10)) more files"
            fi
            echo ""
            has_drift=true
            DRIFT_COUNT=$((DRIFT_COUNT + 1))
        else
            echo -e "${GREEN}✓ ${watch_path} - clean${NC}"
        fi
    done

    if [[ "${has_drift}" == false ]]; then
        echo -e "${GREEN}✓ All watched directories are clean${NC}"
    fi
    echo ""
}

# Function to count routes in code
count_code_routes() {
  grep -rn "@Get\|@Post\|@Put\|@Delete\|@Patch\|router\.\|app\.\(get\|post\|put\|delete\|patch\)" \
    --include="*.ts" --include="*.js" --include="*.py" --include="*.go" \
    "$PROJECT_ROOT" 2>/dev/null | \
    grep -v node_modules | grep -v dist | wc -l || echo 0
}

# Function to count routes in docs
count_doc_routes() {
  if [[ -f "$PROJECT_ROOT/grimoires/loa/sdd.md" ]]; then
    grep -c "| GET\|| POST\|| PUT\|| DELETE\|| PATCH" "$PROJECT_ROOT/grimoires/loa/sdd.md" 2>/dev/null || echo 0
  else
    echo 0
  fi
}

# Function to count entities in code
count_code_entities() {
  grep -rn "model \|@Entity\|class.*Entity\|interface.*{" \
    --include="*.prisma" --include="*.ts" --include="*.go" --include="*.graphql" \
    "$PROJECT_ROOT" 2>/dev/null | \
    grep -v node_modules | grep -v dist | wc -l || echo 0
}

# Function to count entities in docs
count_doc_entities() {
  if [[ -f "$PROJECT_ROOT/grimoires/loa/sdd.md" ]]; then
    grep -c "### Entity:\|### Model:\|## Data Model" "$PROJECT_ROOT/grimoires/loa/sdd.md" 2>/dev/null || echo 0
  else
    echo 0
  fi
}

# Quick mode: basic counts
if [[ "$MODE" == "--quick" || "$MODE" == "quick" ]]; then
  echo "📊 Quick Drift Check"
  echo ""

  # Sprint 4: Check watched paths for uncommitted changes
  check_watched_paths_drift

  # Route drift
  CODE_ROUTES=$(count_code_routes)
  DOC_ROUTES=$(count_doc_routes)
  ROUTE_DIFF=$((CODE_ROUTES - DOC_ROUTES))

  if [[ $ROUTE_DIFF -gt 5 ]]; then
    echo -e "${YELLOW}⚠️ Routes: $CODE_ROUTES in code, $DOC_ROUTES documented (${ROUTE_DIFF} shadows)${NC}"
    SHADOW_COUNT=$((SHADOW_COUNT + ROUTE_DIFF))
  elif [[ $ROUTE_DIFF -lt -5 ]]; then
    echo -e "${RED}❌ Routes: $CODE_ROUTES in code, $DOC_ROUTES documented (${ROUTE_DIFF#-} ghosts)${NC}"
    GHOST_COUNT=$((GHOST_COUNT + ${ROUTE_DIFF#-}))
  else
    echo -e "${GREEN}✓ Routes: $CODE_ROUTES in code, $DOC_ROUTES documented${NC}"
  fi

  # Entity drift
  CODE_ENTITIES=$(count_code_entities)
  DOC_ENTITIES=$(count_doc_entities)
  ENTITY_DIFF=$((CODE_ENTITIES - DOC_ENTITIES))

  if [[ $ENTITY_DIFF -gt 3 ]]; then
    echo -e "${YELLOW}⚠️ Entities: $CODE_ENTITIES in code, $DOC_ENTITIES documented (${ENTITY_DIFF} shadows)${NC}"
    SHADOW_COUNT=$((SHADOW_COUNT + ENTITY_DIFF))
  elif [[ $ENTITY_DIFF -lt -3 ]]; then
    echo -e "${RED}❌ Entities: $CODE_ENTITIES in code, $DOC_ENTITIES documented (${ENTITY_DIFF#-} ghosts)${NC}"
    GHOST_COUNT=$((GHOST_COUNT + ${ENTITY_DIFF#-}))
  else
    echo -e "${GREEN}✓ Entities: $CODE_ENTITIES in code, $DOC_ENTITIES documented${NC}"
  fi

  # Check if PRD/SDD exist
  if [[ ! -f "$PROJECT_ROOT/grimoires/loa/prd.md" ]]; then
    echo -e "${RED}❌ PRD missing - run /ride to generate${NC}"
    DRIFT_COUNT=$((DRIFT_COUNT + 1))
  else
    echo -e "${GREEN}✓ PRD exists${NC}"
  fi

  if [[ ! -f "$PROJECT_ROOT/grimoires/loa/sdd.md" ]]; then
    echo -e "${RED}❌ SDD missing - run /ride to generate${NC}"
    DRIFT_COUNT=$((DRIFT_COUNT + 1))
  else
    echo -e "${GREEN}✓ SDD exists${NC}"
  fi

  # Check last ride date
  if [[ -f "$PROJECT_ROOT/grimoires/loa/drift-report.md" ]]; then
    LAST_RIDE=$(grep "Generated:" "$PROJECT_ROOT/grimoires/loa/drift-report.md" 2>/dev/null | head -1 | cut -d: -f2- | xargs)
    if [[ -n "$LAST_RIDE" ]]; then
      echo ""
      echo "📅 Last ride: $LAST_RIDE"
    fi
  fi

fi

# Full mode: detailed analysis
if [[ "$MODE" == "--full" || "$MODE" == "full" ]]; then
  echo "📊 Full Drift Analysis"
  echo ""

  # Create temporary file for results
  TEMP_FILE=$(mktemp) || { echo "mktemp failed" >&2; exit 1; }
  chmod 600 "$TEMP_FILE"  # CRITICAL-001 FIX
  trap "rm -f '$TEMP_FILE'" EXIT

  # Check for new files since last ride
  if [[ -f "$PROJECT_ROOT/grimoires/loa/drift-report.md" ]]; then
    LAST_RIDE_EPOCH=$(stat -c %Y "$PROJECT_ROOT/grimoires/loa/drift-report.md" 2>/dev/null || stat -f %m "$PROJECT_ROOT/grimoires/loa/drift-report.md" 2>/dev/null || echo 0)

    echo "Files modified since last ride:"
    find "$PROJECT_ROOT" \
      -type f \( -name "*.ts" -o -name "*.js" -o -name "*.py" -o -name "*.go" \) \
      -not -path "*/node_modules/*" \
      -not -path "*/.git/*" \
      -not -path "*/dist/*" \
      -newer "$PROJECT_ROOT/grimoires/loa/drift-report.md" 2>/dev/null | head -20 | while read f; do
      echo "  📝 $f"
      DRIFT_COUNT=$((DRIFT_COUNT + 1))
    done
    echo ""
  fi

  # Check for new TODO/FIXME since last ride
  echo "New tech debt markers:"
  grep -rn "TODO\|FIXME\|HACK\|XXX" \
    --include="*.ts" --include="*.js" --include="*.py" --include="*.go" \
    "$PROJECT_ROOT" 2>/dev/null | \
    grep -v node_modules | grep -v dist | head -10 | while read line; do
    echo "  ⚠️ $line"
  done
  echo ""

  # Check for orphaned documentation
  echo "Checking for ghost documentation..."
  if [[ -f "$PROJECT_ROOT/grimoires/loa/legacy/doc-files.txt" ]]; then
    while read doc; do
      if [[ ! -f "$PROJECT_ROOT/$doc" ]]; then
        echo -e "  ${RED}👻 Missing: $doc${NC}"
        GHOST_COUNT=$((GHOST_COUNT + 1))
      fi
    done < "$PROJECT_ROOT/grimoires/loa/legacy/doc-files.txt"
  fi
fi

echo ""
echo "================================"
echo "📈 Drift Summary"
echo "================================"
echo ""

TOTAL_DRIFT=$((DRIFT_COUNT + SHADOW_COUNT + GHOST_COUNT))

if [[ $TOTAL_DRIFT -eq 0 ]]; then
  echo -e "${GREEN}✅ No significant drift detected${NC}"
  exit 0
elif [[ $TOTAL_DRIFT -lt 5 ]]; then
  echo -e "${YELLOW}⚠️ Minor drift detected (${TOTAL_DRIFT} items)${NC}"
  echo "   Consider running /ride to refresh documentation"
  exit 0
else
  echo -e "${RED}❌ Significant drift detected (${TOTAL_DRIFT} items)${NC}"
  echo ""
  echo "   Shadows (undocumented): $SHADOW_COUNT"
  echo "   Ghosts (missing): $GHOST_COUNT"
  echo "   Other: $DRIFT_COUNT"
  echo ""
  echo "   Run /ride to regenerate grimoire artifacts"
  exit 1
fi
