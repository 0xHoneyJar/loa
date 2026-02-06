#!/usr/bin/env bash
# run-persistence-tests.sh — Run vitest for .claude/lib/persistence/
#
# This script handles the temp package.json + vitest setup required
# because the upstream loa repo has no package.json.
#
# Usage:
#   ./run-persistence-tests.sh              # Run all persistence tests
#   ./run-persistence-tests.sh --watch      # Run in watch mode
#   ./run-persistence-tests.sh <pattern>    # Run tests matching pattern

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Track whether we created temp files (for cleanup)
CREATED_PACKAGE_JSON=false
CREATED_TSCONFIG=false

cleanup() {
  cd "$REPO_ROOT"
  if [[ "$CREATED_PACKAGE_JSON" == "true" ]] && [[ -f package.json ]]; then
    rm -f package.json
  fi
  if [[ "$CREATED_TSCONFIG" == "true" ]] && [[ -f tsconfig.json ]]; then
    rm -f tsconfig.json
  fi
}

trap cleanup EXIT

cd "$REPO_ROOT"

# ── Setup package.json if missing ──
if [[ ! -f package.json ]]; then
  echo -e "${YELLOW}Creating temporary package.json for vitest...${NC}"
  cat > package.json << 'PKGJSON'
{
  "private": true,
  "type": "module",
  "devDependencies": {
    "typescript": "^5.7.0",
    "vitest": "^3.0.0"
  }
}
PKGJSON
  CREATED_PACKAGE_JSON=true
fi

# ── Setup tsconfig.json if missing ──
if [[ ! -f tsconfig.json ]]; then
  echo -e "${YELLOW}Creating temporary tsconfig.json...${NC}"
  cat > tsconfig.json << 'TSCFG'
{
  "compilerOptions": {
    "target": "ESNext",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "outDir": "dist",
    "rootDir": ".",
    "declaration": true,
    "resolveJsonModule": true
  },
  "include": [".claude/lib/**/*.ts"],
  "exclude": ["node_modules", "dist"]
}
TSCFG
  CREATED_TSCONFIG=true
fi

# ── Install deps if needed ──
if [[ ! -d node_modules ]] || [[ ! -f node_modules/.package-lock.json ]]; then
  echo -e "${YELLOW}Installing dependencies...${NC}"
  npm install --no-audit --no-fund 2>&1 | tail -1
fi

# ── Parse args ──
VITEST_ARGS=()
WATCH=false

for arg in "$@"; do
  case "$arg" in
    --watch)
      WATCH=true
      ;;
    *)
      VITEST_ARGS+=("$arg")
      ;;
  esac
done

# ── Run tests ──
echo -e "${GREEN}Running persistence tests...${NC}"

VITEST_CONFIG="$SCRIPT_DIR/vitest.config.ts"

if [[ "$WATCH" == "true" ]]; then
  npx vitest watch --config "$VITEST_CONFIG" "${VITEST_ARGS[@]}"
else
  npx vitest run --config "$VITEST_CONFIG" "${VITEST_ARGS[@]}"
fi
