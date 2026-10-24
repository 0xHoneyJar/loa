#!/usr/bin/env bash
# Security Audit Scope Analysis
# Two-Pass Methodology v1.0
#
# Shows file counts by security-relevant category to understand audit surface.
# Part of Loa's /audit skill enhancement.
#
# Usage: .claude/scripts/security-audit-scope.sh [OPTIONS]
#   --no-symlinks    Skip symlinks (default: follow)
#   --max-depth N    Limit search depth (default: unlimited)
#   --json           Output as JSON
#   --files FILE     Walk only the paths listed in FILE, one per line, relative
#                    to the current directory (blank lines ignored), e.g. a
#                    sprint diff: git diff --name-only main...HEAD > /tmp/scope.txt
#   --paths P...     Walk only these files or directories (every argument up to
#                    the next option); combines with --files
#   -h, --help       Print this usage and exit 0
#
# Without --files/--paths the walk is the current directory ("tree" scope).
# The scope used is printed (text) or reported as "scope" (JSON).
# Exit codes: 0 done · 2 usage (unknown option, missing --files file,
# nonexistent --paths entry, --paths without a path).

set -euo pipefail

usage() { sed -n '/^# Usage:/,/^set -euo/p' "$0" | sed -n 's/^# \{0,1\}//p'; }
usage_error() { echo "security-audit-scope: $* (see --help)" >&2; exit 2; }

# Parse arguments
FOLLOW_SYMLINKS=true
MAX_DEPTH=""
OUTPUT_JSON=false
SCOPE_MODE="tree"
declare -a ROOTS=()

add_root() {
  [[ -e "$1" || -L "$1" ]] || usage_error "no such path: $1"
  # a leading '-' would read as a find option
  if [[ "$1" == -* ]]; then ROOTS+=("./$1"); else ROOTS+=("$1"); fi
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --no-symlinks) FOLLOW_SYMLINKS=false; shift ;;
    --max-depth) [[ $# -ge 2 && "$2" =~ ^[0-9]+$ ]] || usage_error "--max-depth needs a number"; MAX_DEPTH="$2"; shift 2 ;;
    --json) OUTPUT_JSON=true; shift ;;
    --files)
      [[ $# -ge 2 && -f "$2" ]] || usage_error "--files needs a readable list file"
      while IFS= read -r _line || [[ -n "$_line" ]]; do
        [[ -n "${_line//[[:space:]]/}" ]] || continue
        add_root "$_line"
      done < "$2"
      [[ "$SCOPE_MODE" == "paths" ]] || SCOPE_MODE="files"
      shift 2 ;;
    --paths)
      shift
      _n=0
      while [[ $# -gt 0 && "$1" != --* ]]; do add_root "$1"; _n=$((_n + 1)); shift; done
      [[ "$_n" -gt 0 ]] || usage_error "--paths needs at least one path"
      SCOPE_MODE="paths" ;;
    -h|--help) usage; exit 0 ;;
    *) usage_error "unknown option: $1" ;;
  esac
done
if [[ "$SCOPE_MODE" == "tree" ]]; then
  ROOTS=(.)
elif [[ ${#ROOTS[@]} -eq 0 ]]; then
  # an empty --files list: nothing to walk (counts are zero), never the whole tree
  ROOTS=()
fi

# Build find options as array (HIGH-002 remediation - prevents word splitting)
declare -a FIND_OPTS=(-type f)
if [[ "$FOLLOW_SYMLINKS" == "false" ]]; then
  FIND_OPTS=(-type f -not -type l)
fi
if [[ -n "$MAX_DEPTH" ]]; then
  FIND_OPTS=(-maxdepth "$MAX_DEPTH" "${FIND_OPTS[@]}")
fi

# Exclude patterns (POSIX compatible)
EXCLUDE_DIRS="node_modules|\.git|dist|build|\.next|vendor|__pycache__|\.venv"

# Count function with error suppression
# Uses array expansion for safe variable handling
count_files() {
  local pattern="$1"
  local result
  [[ ${#ROOTS[@]} -gt 0 ]] || { echo 0; return 0; }   # find with no root would walk "."
  result=$(find "${ROOTS[@]}" "${FIND_OPTS[@]}" \( -name "*.ts" -o -name "*.js" -o -name "*.py" -o -name "*.go" -o -name "*.java" \) 2>/dev/null | \
    grep -v -E "$EXCLUDE_DIRS" | \
    xargs grep -l "$pattern" 2>/dev/null | wc -l || echo "0")
  echo "$result" | tr -d '[:space:]'
}

count_by_name() {
  local pattern="$1"
  local result
  [[ ${#ROOTS[@]} -gt 0 ]] || { echo 0; return 0; }
  result=$(find "${ROOTS[@]}" "${FIND_OPTS[@]}" \( -name "*$pattern*" \) 2>/dev/null | \
    grep -v -E "$EXCLUDE_DIRS" | wc -l || echo "0")
  echo "$result" | tr -d '[:space:]'
}

# Collect metrics
START_TIME=$(date +%s)

# Source files (entry points)
CONTROLLERS=$(count_by_name "controller")
ROUTES=$(count_by_name "route")
HANDLERS=$(count_by_name "handler")
API_ENDPOINTS=$(count_files 'app\.\(get\|post\|put\|delete\|patch\)\|router\.\(get\|post\)')

# Sink files (dangerous operations)
DB_QUERY=$(count_files '\.query\|\.execute\|SELECT\|INSERT\|UPDATE\|DELETE')
CMD_EXEC=$(count_files 'exec\|spawn\|system\|popen\|subprocess')
FILE_OPS=$(count_files 'readFile\|writeFile\|open(\|fs\.')

# Auth files
AUTH_FILES=$(count_files 'auth\|login\|session\|jwt\|token\|password')

# LLM/AI files
LLM_FILES=$(count_files 'openai\|anthropic\|llm\|prompt\|completion\|chat\|gpt\|claude')

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

# Output
if [[ "$OUTPUT_JSON" == "true" ]]; then
  cat <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "elapsed_seconds": $ELAPSED,
  "sources": {
    "controllers": $CONTROLLERS,
    "routes": $ROUTES,
    "handlers": $HANDLERS,
    "api_endpoints": $API_ENDPOINTS,
    "total": $((CONTROLLERS + ROUTES + HANDLERS + API_ENDPOINTS))
  },
  "sinks": {
    "database_query": $DB_QUERY,
    "command_exec": $CMD_EXEC,
    "file_operations": $FILE_OPS,
    "total": $((DB_QUERY + CMD_EXEC + FILE_OPS))
  },
  "auth_files": $AUTH_FILES,
  "llm_files": $LLM_FILES,
  "scope": { "mode": "$SCOPE_MODE", "roots": ${#ROOTS[@]} }
}
EOF
else
  echo "=== Security Audit Scope Analysis ==="
  echo "Two-Pass Methodology v1.0"
  if [[ "$SCOPE_MODE" == "tree" ]]; then
    echo "Scope: the whole tree under $(pwd)"
  else
    echo "Scope: ${#ROOTS[@]} path(s) from --$SCOPE_MODE"
  fi
  echo ""
  echo "SOURCE FILES (Entry Points)"
  printf "  Controllers:     %4d files\n" "$CONTROLLERS"
  printf "  Routes:          %4d files\n" "$ROUTES"
  printf "  Handlers:        %4d files\n" "$HANDLERS"
  printf "  API Endpoints:   %4d files\n" "$API_ENDPOINTS"
  echo ""
  echo "SINK FILES (Dangerous Operations)"
  printf "  Database/Query:  %4d files\n" "$DB_QUERY"
  printf "  Command Exec:    %4d files\n" "$CMD_EXEC"
  printf "  File Operations: %4d files\n" "$FILE_OPS"
  echo ""
  printf "AUTH FILES:        %4d files\n" "$AUTH_FILES"
  printf "LLM/AI FILES:      %4d files\n" "$LLM_FILES"
  echo ""
  echo "=== Completed in ${ELAPSED}s ==="
fi
