#!/usr/bin/env bash
# function-exported.sh — Check named export exists in file
# Args: $1=workspace, $2=export name, $3=file path (relative)
# Exit: 0=pass, 1=fail, 2=error
set -euo pipefail

workspace="${1:-}"
export_name="${2:-}"
file_path="${3:-}"

if [[ -z "$workspace" || ! -d "$workspace" ]]; then
  echo '{"pass":false,"score":0,"details":"Invalid workspace","grader_version":"1.0.0"}'
  exit 2
fi

if [[ -z "$export_name" || -z "$file_path" ]]; then
  echo '{"pass":false,"score":0,"details":"Usage: function-exported.sh <workspace> <name> <file>","grader_version":"1.0.0"}'
  exit 2
fi

# Reject path traversal
if [[ "$file_path" == *".."* ]]; then
  echo '{"pass":false,"score":0,"details":"Path traversal rejected","grader_version":"1.0.0"}'
  exit 2
fi

target="$workspace/$file_path"
if [[ ! -f "$target" ]]; then
  echo '{"pass":false,"score":0,"details":"File not found: '"$file_path"'","grader_version":"1.0.0"}'
  exit 1
fi

# Check for common export patterns
# TypeScript/JavaScript: export function X, export const X, export { X }, module.exports.X, exports.X
# Python: def X (at top level — not indented)
# Bash: X() { (function definition)
found=false

case "$file_path" in
  *.ts|*.tsx|*.js|*.jsx|*.mjs)
    if grep -qE "(export\s+(function|const|let|var|class|type|interface|enum|default)\s+${export_name}|export\s*\{[^}]*\b${export_name}\b|module\.exports\.\b${export_name}\b|exports\.\b${export_name}\b)" "$target" 2>/dev/null; then
      found=true
    fi
    ;;
  *.py)
    if grep -qE "^(def|class)\s+${export_name}\b" "$target" 2>/dev/null; then
      found=true
    fi
    ;;
  *.sh|*.bash)
    if grep -qE "^(function\s+)?${export_name}\s*\(\)" "$target" 2>/dev/null; then
      found=true
    fi
    ;;
  *)
    # Generic: look for the name as a declaration
    if grep -qE "(export|def|function|class)\s+${export_name}\b" "$target" 2>/dev/null; then
      found=true
    fi
    ;;
esac

if [[ "$found" == "true" ]]; then
  echo '{"pass":true,"score":100,"details":"Export '"$export_name"' found in '"$file_path"'","grader_version":"1.0.0"}'
  exit 0
else
  echo '{"pass":false,"score":0,"details":"Export '"$export_name"' not found in '"$file_path"'","grader_version":"1.0.0"}'
  exit 1
fi
