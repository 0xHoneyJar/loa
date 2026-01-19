#!/usr/bin/env bash
# Permission Audit Logger for Loa Framework
# Logs permission requests that required HITL approval
# Used via PermissionRequest hook in .claude/settings.json
#
# Usage:
#   As hook: .claude/scripts/permission-audit.sh log
#   View log: .claude/scripts/permission-audit.sh view [--json]
#   Analyze:  .claude/scripts/permission-audit.sh analyze
#   Suggest:  .claude/scripts/permission-audit.sh suggest
#   Clear:    .claude/scripts/permission-audit.sh clear
#
# Log format: JSONL at grimoires/loa/analytics/permission-requests.jsonl

set -euo pipefail

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_DIR="$PROJECT_ROOT/grimoires/loa/analytics"
LOG_FILE="$LOG_DIR/permission-requests.jsonl"
SETTINGS_FILE="$PROJECT_ROOT/.claude/settings.json"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# =============================================================================
# SECURITY: Sensitive Data Sanitization (CRITICAL-003 fix)
# =============================================================================
# Redacts credentials and API keys before logging to prevent exposure.
# Patterns based on common credential formats.

sanitize_sensitive_data() {
    local input="$1"
    echo "$input" | sed \
        -e 's/sk_[a-zA-Z0-9_-]\{20,\}/sk_REDACTED/g' \
        -e 's/ghp_[a-zA-Z0-9_-]\{36,\}/ghp_REDACTED/g' \
        -e 's/gho_[a-zA-Z0-9_-]\{36,\}/gho_REDACTED/g' \
        -e 's/ghs_[a-zA-Z0-9_-]\{36,\}/ghs_REDACTED/g' \
        -e 's/github_pat_[a-zA-Z0-9_-]\{20,\}/github_pat_REDACTED/g' \
        -e 's/Bearer [a-zA-Z0-9._-]\{20,\}/Bearer REDACTED/g' \
        -e 's/Authorization: [^"'\'']*[a-zA-Z0-9._-]\{20,\}/Authorization: REDACTED/gi' \
        -e 's/api[_-]\?key["'\''[:space:]:=]*[a-zA-Z0-9_-]\{16,\}/api_key: REDACTED/gi' \
        -e 's/password["'\''[:space:]:=]*[^"'\''[:space:]}\]]\{8,\}/password: REDACTED/gi' \
        -e 's/secret["'\''[:space:]:=]*[a-zA-Z0-9_-]\{16,\}/secret: REDACTED/gi' \
        -e 's/token["'\''[:space:]:=]*[a-zA-Z0-9._-]\{20,\}/token: REDACTED/gi' \
        -e 's/aws_[a-zA-Z_]*_key[_id]*["'\''[:space:]:=]*[A-Z0-9]\{16,\}/aws_key: REDACTED/gi' \
        -e 's/AKIA[A-Z0-9]\{16\}/AKIA_REDACTED/g'
}

# Colors (if terminal supports them)
if [[ -t 1 ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  BLUE='\033[0;34m'
  NC='\033[0m' # No Color
else
  RED='' GREEN='' YELLOW='' BLUE='' NC=''
fi

log_permission() {
  # Read JSON from stdin (provided by Claude Code PermissionRequest hook)
  local input
  input=$(cat)

  # Extract tool info from hook input
  # Hook input format: {"tool_name": "Bash", "tool_input": {...}}
  local tool_name tool_input timestamp
  tool_name=$(echo "$input" | jq -r '.tool_name // "unknown"' 2>/dev/null || echo "unknown")
  tool_input=$(echo "$input" | jq -c '.tool_input // {}' 2>/dev/null || echo "{}")
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # For Bash commands, extract the command
  local command=""
  if [[ "$tool_name" == "Bash" ]]; then
    command=$(echo "$tool_input" | jq -r '.command // ""' 2>/dev/null || echo "")
  elif [[ "$tool_name" == "Write" ]] || [[ "$tool_name" == "Edit" ]]; then
    command=$(echo "$tool_input" | jq -r '.file_path // ""' 2>/dev/null || echo "")
  fi

  # SECURITY: Sanitize sensitive data before logging (CRITICAL-003 fix)
  local sanitized_input sanitized_command
  sanitized_input=$(sanitize_sensitive_data "$tool_input")
  sanitized_command=$(sanitize_sensitive_data "$command")

  # Create log entry with sanitized data
  local log_entry
  log_entry=$(jq -nc \
    --arg ts "$timestamp" \
    --arg tool "$tool_name" \
    --arg cmd "$sanitized_command" \
    --arg input "$sanitized_input" \
    '{timestamp: $ts, tool: $tool, command: $cmd, input: $input}')

  # Append to log
  echo "$log_entry" >> "$LOG_FILE"

  # Output nothing (hook should be silent)
}

view_log() {
  local json_mode=false
  if [[ "${1:-}" == "--json" ]]; then
    json_mode=true
  fi

  if [[ ! -f "$LOG_FILE" ]]; then
    echo "No permission requests logged yet."
    echo "Log file: $LOG_FILE"
    exit 0
  fi

  if $json_mode; then
    cat "$LOG_FILE"
  else
    echo -e "${BLUE}Permission Request Log${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    local count=0
    while IFS= read -r line; do
      count=$((count + 1))
      local ts tool cmd
      ts=$(echo "$line" | jq -r '.timestamp' 2>/dev/null)
      tool=$(echo "$line" | jq -r '.tool' 2>/dev/null)
      cmd=$(echo "$line" | jq -r '.command' 2>/dev/null)

      # Truncate long commands
      if [[ ${#cmd} -gt 80 ]]; then
        cmd="${cmd:0:77}..."
      fi

      echo -e "${YELLOW}[$ts]${NC} ${GREEN}$tool${NC}"
      if [[ -n "$cmd" ]]; then
        echo "  $cmd"
      fi
      echo ""
    done < "$LOG_FILE"

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Total: $count permission requests"
  fi
}

analyze_log() {
  if [[ ! -f "$LOG_FILE" ]]; then
    echo "No permission requests logged yet."
    exit 0
  fi

  echo -e "${BLUE}Permission Request Analysis${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  # Count by tool
  echo -e "${GREEN}By Tool:${NC}"
  jq -r '.tool' "$LOG_FILE" | sort | uniq -c | sort -rn | while read count tool; do
    printf "  %-20s %d\n" "$tool" "$count"
  done
  echo ""

  # For Bash commands, extract command prefixes
  echo -e "${GREEN}Bash Command Patterns:${NC}"
  jq -r 'select(.tool == "Bash") | .command' "$LOG_FILE" 2>/dev/null | \
    sed 's/^\([^ ]*\).*/\1/' | \
    sort | uniq -c | sort -rn | head -20 | while read count prefix; do
    printf "  %-30s %d\n" "$prefix" "$count"
  done
  echo ""

  # File paths for Write/Edit
  echo -e "${GREEN}File Operations:${NC}"
  jq -r 'select(.tool == "Write" or .tool == "Edit") | .command' "$LOG_FILE" 2>/dev/null | \
    sort | uniq -c | sort -rn | head -10 | while read count path; do
    printf "  %-50s %d\n" "$path" "$count"
  done
  echo ""

  # Total count
  local total
  total=$(wc -l < "$LOG_FILE")
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Total permission requests: $total"
}

suggest_permissions() {
  if [[ ! -f "$LOG_FILE" ]]; then
    echo "No permission requests logged yet."
    exit 0
  fi

  echo -e "${BLUE}Suggested Permission Additions${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "Based on your permission request history, consider adding these"
  echo "to .claude/settings.json permissions.allow:"
  echo ""

  # Get current allowed patterns
  local current_allows
  current_allows=$(jq -r '.permissions.allow[]?' "$SETTINGS_FILE" 2>/dev/null || echo "")

  # Analyze Bash commands
  echo -e "${GREEN}Bash Commands (requested 2+ times):${NC}"
  jq -r 'select(.tool == "Bash") | .command' "$LOG_FILE" 2>/dev/null | \
    sed 's/^\([^ ]*\).*/\1/' | \
    sort | uniq -c | sort -rn | \
    while read count prefix; do
      if [[ $count -ge 2 ]]; then
        local pattern="Bash($prefix:*)"
        # Check if already allowed
        if echo "$current_allows" | grep -qF "$pattern"; then
          echo -e "  ${YELLOW}[already allowed]${NC} $pattern ($count times)"
        else
          echo -e "  ${GREEN}[suggest]${NC} \"$pattern\" ($count times)"
        fi
      fi
    done
  echo ""

  # File paths
  echo -e "${GREEN}File Paths (Write/Edit):${NC}"
  jq -r 'select(.tool == "Write" or .tool == "Edit") | "\(.tool):\(.command)"' "$LOG_FILE" 2>/dev/null | \
    sort | uniq -c | sort -rn | head -10 | \
    while read count entry; do
      local tool path
      tool=$(echo "$entry" | cut -d: -f1)
      path=$(echo "$entry" | cut -d: -f2-)
      if [[ $count -ge 2 ]]; then
        echo -e "  ${GREEN}[suggest]${NC} \"$tool($path)\" ($count times)"
      fi
    done
  echo ""

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "To add a permission, edit .claude/settings.json:"
  echo "  \"permissions\": { \"allow\": [ ... , \"Bash(command:*)\" ] }"
}

clear_log() {
  if [[ -f "$LOG_FILE" ]]; then
    local count
    count=$(wc -l < "$LOG_FILE")
    rm "$LOG_FILE"
    echo "Cleared $count permission request entries."
  else
    echo "No log file to clear."
  fi
}

show_help() {
  cat << 'EOF'
Permission Audit Logger for Loa Framework

Usage:
  .claude/scripts/permission-audit.sh <command> [options]

Commands:
  log           Log a permission request (used by hook, reads JSON from stdin)
  view          View permission request log
  view --json   Output raw JSONL log
  analyze       Analyze patterns in permission requests
  suggest       Suggest permissions to add based on history
  clear         Clear the permission request log

Log Location:
  grimoires/loa/analytics/permission-requests.jsonl

Hook Setup:
  Add to .claude/settings.json:
  {
    "hooks": {
      "PermissionRequest": [
        {
          "matcher": "",
          "hooks": [
            {
              "type": "command",
              "command": ".claude/scripts/permission-audit.sh log"
            }
          ]
        }
      ]
    }
  }

EOF
}

# Main
case "${1:-help}" in
  log)
    log_permission
    ;;
  view)
    view_log "${2:-}"
    ;;
  analyze)
    analyze_log
    ;;
  suggest)
    suggest_permissions
    ;;
  clear)
    clear_log
    ;;
  help|--help|-h)
    show_help
    ;;
  *)
    echo "Unknown command: $1"
    echo "Run with --help for usage"
    exit 1
    ;;
esac
