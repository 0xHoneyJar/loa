#!/usr/bin/env bash
# Loa Session Priming Script
# Equivalent to `br prime` from original beads
# Outputs context-optimized summary for AI agent session injection
#
# Usage: loa-prime.sh [--json]
#
# Part of Loa beads_rust integration

set -euo pipefail

# Parse arguments
JSON_MODE=false
if [ "${1:-}" = "--json" ]; then
  JSON_MODE=true
fi

# Navigate to project root
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# Ensure we have latest state (silent on errors for fresh repos)
br sync --import-only 2>/dev/null || true

if [ "$JSON_MODE" = true ]; then
  # Pure JSON output for programmatic consumption
  cat <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "ready": $(br ready --json 2>/dev/null || echo "[]"),
  "blocked": $(br blocked --json 2>/dev/null || echo "[]"),
  "in_progress": $(br list --status in_progress --json 2>/dev/null || echo "[]"),
  "stats": {
    "total": $(br list --json 2>/dev/null | jq 'length' || echo "0"),
    "open": $(br list --status open --json 2>/dev/null | jq 'length' || echo "0"),
    "closed": $(br list --status closed --json 2>/dev/null | jq 'length' || echo "0")
  }
}
EOF
else
  # Human-readable markdown output
  echo "# Loa Session Context"
  echo ""
  echo "**Generated**: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo ""

  echo "## Ready Work (unblocked, actionable)"
  echo ""
  READY=$(br ready --json 2>/dev/null || echo "[]")
  if [ "$READY" = "[]" ]; then
    echo "_No ready tasks_"
  else
    echo '```json'
    echo "$READY" | jq -r '.[] | "- [\(.id)] P\(.priority) \(.type): \(.title)"' 2>/dev/null || echo "$READY"
    echo '```'
  fi
  echo ""

  echo "## In Progress"
  echo ""
  IN_PROGRESS=$(br list --status in_progress --json 2>/dev/null || echo "[]")
  if [ "$IN_PROGRESS" = "[]" ]; then
    echo "_No tasks in progress_"
  else
    echo '```json'
    echo "$IN_PROGRESS" | jq -r '.[] | "- [\(.id)] P\(.priority) \(.type): \(.title)"' 2>/dev/null || echo "$IN_PROGRESS"
    echo '```'
  fi
  echo ""

  echo "## Blocked Issues"
  echo ""
  BLOCKED=$(br blocked --json 2>/dev/null || echo "[]")
  if [ "$BLOCKED" = "[]" ]; then
    echo "_No blocked tasks_"
  else
    echo '```json'
    echo "$BLOCKED" | jq '.' 2>/dev/null || echo "$BLOCKED"
    echo '```'
  fi
  echo ""

  echo "## Statistics"
  echo ""
  br stats 2>/dev/null || echo "_Stats unavailable_"
  echo ""

  echo "---"
  echo "_Sync state before making changes. Run \`br sync --flush-only\` before git commit._"
fi
