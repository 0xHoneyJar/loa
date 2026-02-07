#!/usr/bin/env bash
# run-lib-tests.sh — Test runner for .claude/lib/ TypeScript modules
# Per SDD Section 5.1 / Sprint 1 Task T1.9
#
# Usage:
#   ./run-lib-tests.sh                   # Run all tests (node --test)
#   ./run-lib-tests.sh security/         # Run tests matching module path
#   ./run-lib-tests.sh --vitest          # Use vitest runner
#   ./run-lib-tests.sh --smoke           # Barrel import smoke test only
#   ./run-lib-tests.sh --loader-info     # Print detected loader and exit
#
# Environment:
#   NODE_VERSION=18 ./run-lib-tests.sh   # (informational, uses whatever node is on PATH)

set -euo pipefail

# ── Constants ────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../lib" && pwd)"
TEST_DIR="$LIB_DIR/__tests__"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MIN_NODE_MAJOR=18

# ── Colors ───────────────────────────────────────────────
if [[ "${CI:-}" == "true" ]] || [[ ! -t 1 ]]; then
  RED='' GREEN='' YELLOW='' CYAN='' NC=''
else
  RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' CYAN='\033[0;36m' NC='\033[0m'
fi

info()  { echo -e "${GREEN}[lib-test]${NC} $*"; }
warn()  { echo -e "${YELLOW}[lib-test]${NC} $*"; }
err()   { echo -e "${RED}[lib-test]${NC} $*" >&2; }
debug() { echo -e "${CYAN}[lib-test]${NC} $*"; }

# ── Node Version Check ──────────────────────────────────
check_node_version() {
  local node_version
  node_version="$(node --version 2>/dev/null || true)"
  if [[ -z "$node_version" ]]; then
    err "Node.js not found. Install Node.js >= $MIN_NODE_MAJOR."
    exit 1
  fi

  local major
  major="${node_version#v}"
  major="${major%%.*}"

  if [[ "$major" -lt "$MIN_NODE_MAJOR" ]]; then
    err "Node.js $node_version is too old. Minimum required: v${MIN_NODE_MAJOR}.x"
    err "Current: $node_version"
    exit 1
  fi

  debug "Node.js $node_version (major: $major)"
}

# ── Loader Detection ────────────────────────────────────
# Priority: bun → tsx (PATH or repo-root) → node --experimental-strip-types (22+)
LOADER=""
LOADER_NAME=""
LOADER_CMD=()

detect_loader() {
  # 1. bun
  if command -v bun &>/dev/null; then
    LOADER="bun"
    LOADER_NAME="bun"
    LOADER_CMD=(bun --test)
    return
  fi

  # 2. tsx on PATH
  if command -v tsx &>/dev/null; then
    LOADER="tsx"
    LOADER_NAME="tsx (PATH)"
    LOADER_CMD=(tsx --test)
    return
  fi

  # 3. tsx in repo-root node_modules
  if [[ -x "$REPO_ROOT/node_modules/.bin/tsx" ]]; then
    LOADER="tsx-local"
    LOADER_NAME="tsx (repo-root)"
    LOADER_CMD=("$REPO_ROOT/node_modules/.bin/tsx" --test)
    return
  fi

  # 4. npx tsx (cached or downloadable)
  if command -v npx &>/dev/null && npx tsx --version &>/dev/null 2>&1; then
    LOADER="npx-tsx"
    LOADER_NAME="tsx (npx)"
    LOADER_CMD=(npx tsx --test)
    return
  fi

  # 5. Node 22+ native strip-types
  local major
  major="$(node --version)"
  major="${major#v}"
  major="${major%%.*}"
  if [[ "$major" -ge 22 ]]; then
    LOADER="native"
    LOADER_NAME="node --experimental-strip-types (v$major)"
    LOADER_CMD=(node --experimental-strip-types --test)
    return
  fi

  err "No TypeScript loader found."
  err "Install one of: bun, tsx (npm i -D tsx), or use Node >= 22"
  exit 1
}

# ── Smoke Test (barrel imports) ──────────────────────────
run_smoke_test() {
  info "Running barrel import smoke test..."

  local barrels=(
    "security/index"
    "memory/index"
    "testing/fake-clock"
    "errors"
  )

  # Write a temp .ts file that imports each barrel using relative .js specifiers
  # (tsx -e treats code as CJS and cannot resolve .js→.ts, so we need a real file)
  local smoke_file
  smoke_file="$(mktemp "$LIB_DIR/smoke-XXXXXX.ts")"
  trap "rm -f '$smoke_file'" RETURN

  local pass=0 fail=0 skip=0
  for barrel in "${barrels[@]}"; do
    local ts_file="$LIB_DIR/${barrel}.ts"
    if [[ ! -f "$ts_file" ]]; then
      warn "  SKIP $barrel (not found)"
      skip=$((skip + 1))
      continue
    fi

    # Write a single-import smoke test next to the modules (relative imports work)
    cat > "$smoke_file" << TSEOF
import './${barrel}.js';
console.log('OK: ${barrel}');
TSEOF

    local result
    case "$LOADER" in
      bun)          result=$(bun "$smoke_file" 2>&1) || true ;;
      tsx)          result=$(tsx "$smoke_file" 2>&1) || true ;;
      tsx-local)    result=$("$REPO_ROOT/node_modules/.bin/tsx" "$smoke_file" 2>&1) || true ;;
      npx-tsx)      result=$(npx tsx "$smoke_file" 2>&1) || true ;;
      native)       result=$(node --experimental-strip-types "$smoke_file" 2>&1) || true ;;
    esac

    if echo "$result" | grep -q "^OK:"; then
      info "  PASS $barrel"
      pass=$((pass + 1))
    else
      warn "  FAIL $barrel"
      [[ -n "${result:-}" ]] && warn "       $(echo "$result" | tail -5)"
      fail=$((fail + 1))
    fi
  done

  rm -f "$smoke_file"

  info "Smoke test: $pass passed, $fail failed, $skip skipped"
  [[ "$fail" -gt 0 ]] && return 1
  return 0
}

# ── Vitest Mode ──────────────────────────────────────────
VITEST_TMPDIR=""

cleanup_vitest() {
  if [[ -n "$VITEST_TMPDIR" ]] && [[ -d "$VITEST_TMPDIR" ]]; then
    debug "Cleaning up vitest temp dir: $VITEST_TMPDIR"
    rm -rf "$VITEST_TMPDIR"
  fi
}

run_vitest() {
  local module_filter="${1:-}"

  VITEST_TMPDIR="$(mktemp -d)"
  trap cleanup_vitest EXIT

  info "Setting up vitest in $VITEST_TMPDIR..."

  # Create a minimal package.json + vitest config
  cat > "$VITEST_TMPDIR/package.json" << 'PJSON'
{"private":true,"type":"module","devDependencies":{"vitest":"^3.0.0"}}
PJSON

  cat > "$VITEST_TMPDIR/vitest.config.ts" << VCONF
import { defineConfig } from 'vitest/config';
export default defineConfig({
  test: {
    include: ['${TEST_DIR}/**/*.test.ts'],
    globals: false,
  },
});
VCONF

  # Install vitest
  (cd "$VITEST_TMPDIR" && npm install --no-audit --no-fund --silent 2>&1) || {
    err "Failed to install vitest"
    exit 1
  }

  info "Running vitest..."
  local test_args=()
  if [[ -n "$module_filter" ]]; then
    test_args+=("$module_filter")
  fi

  (cd "$VITEST_TMPDIR" && npx vitest run "${test_args[@]}" --reporter verbose 2>&1)
}

# ── Node --test Mode ────────────────────────────────────
run_node_test() {
  local module_filter="${1:-}"

  # Find test files
  local test_files=()
  if [[ -n "$module_filter" ]]; then
    # Strip trailing slash for convenience (security/ → security)
    module_filter="${module_filter%/}"

    # Strategy: find test files matching the filter as a substring of the filename
    # This handles both direct names (pii-redactor) and module names (security → pii-redactor, audit-logger)
    # For module names, we also search the source directory to find which tests exist
    while IFS= read -r -d '' f; do
      test_files+=("$f")
    done < <(find "$TEST_DIR" -name "*${module_filter}*.test.ts" -print0 2>/dev/null || true)

    # If no direct filename match, try mapping module dir → source files → test files
    if [[ ${#test_files[@]} -eq 0 ]] && [[ -d "$LIB_DIR/$module_filter" ]]; then
      for src_file in "$LIB_DIR/$module_filter"/*.ts; do
        [[ "$src_file" == */index.ts ]] && continue
        local base
        base="$(basename "${src_file%.ts}")"
        local test_file="$TEST_DIR/${base}.test.ts"
        if [[ -f "$test_file" ]]; then
          test_files+=("$test_file")
        fi
      done
    fi

    if [[ ${#test_files[@]} -eq 0 ]]; then
      err "No test files matching '$module_filter' found in $TEST_DIR"
      exit 1
    fi
  else
    while IFS= read -r -d '' f; do
      test_files+=("$f")
    done < <(find "$TEST_DIR" -name "*.test.ts" -print0 | sort -z)
  fi

  info "Running ${#test_files[@]} test file(s) with ${LOADER_NAME}..."

  local exit_code=0
  "${LOADER_CMD[@]}" "${test_files[@]}" || exit_code=$?
  return "$exit_code"
}

# ── Main ─────────────────────────────────────────────────
main() {
  local mode="test"
  local module_filter=""

  # Parse args
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --vitest)   mode="vitest"; shift ;;
      --smoke)    mode="smoke"; shift ;;
      --loader-info) mode="loader-info"; shift ;;
      --help|-h)
        echo "Usage: run-lib-tests.sh [OPTIONS] [MODULE_PATH]"
        echo ""
        echo "Options:"
        echo "  --vitest       Use vitest runner (installs to temp dir)"
        echo "  --smoke        Run barrel import smoke test only"
        echo "  --loader-info  Print detected loader and exit"
        echo "  --help         Show this help"
        echo ""
        echo "Examples:"
        echo "  run-lib-tests.sh                  # All tests"
        echo "  run-lib-tests.sh security          # Tests matching 'security'"
        echo "  run-lib-tests.sh --vitest          # All tests via vitest"
        echo "  run-lib-tests.sh --smoke           # Barrel import smoke test"
        exit 0
        ;;
      -*)
        err "Unknown option: $1"
        exit 1
        ;;
      *)
        module_filter="$1"; shift ;;
    esac
  done

  check_node_version
  detect_loader
  debug "Loader: $LOADER_NAME"

  case "$mode" in
    loader-info)
      echo "$LOADER_NAME"
      exit 0
      ;;
    smoke)
      run_smoke_test
      ;;
    vitest)
      run_vitest "$module_filter"
      ;;
    test)
      run_node_test "$module_filter"
      ;;
  esac
}

main "$@"
