#!/usr/bin/env bash
# Portable harness gate for runtimes that do not expose Claude-style hooks.
# Usage:
#   echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}' \
#     | .loa-harness/bin/portable_gate.sh PreToolUse
set -euo pipefail
EVENT="${1:-PreToolUse}"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-${LOA_PROJECT_DIR:-$(pwd)}}"
python3 "$PROJECT_DIR/.loa-harness/bin/loa_harness.py" hook --event "$EVENT"
