#!/usr/bin/env bash
# file-exists.sh — Check that file(s) exist in workspace
# Args: $1=workspace, $2..N=file paths (relative to workspace)
# Exit: 0=pass, 1=fail, 2=error
# Version: 1.0.1
set -euo pipefail

workspace="${1:-}"
shift || true

if [[ -z "$workspace" || ! -d "$workspace" ]]; then
  echo '{"pass":false,"score":0,"details":"Invalid workspace","grader_version":"1.0.0"}'
  exit 2
fi

if [[ $# -eq 0 ]]; then
  echo '{"pass":false,"score":0,"details":"No file paths specified","grader_version":"1.0.0"}'
  exit 2
fi

total=$#
found=0
missing=()

for file in "$@"; do
  # Reject path traversal
  if [[ "$file" == *".."* ]]; then
    echo '{"pass":false,"score":0,"details":"Path traversal rejected: '"$file"'","grader_version":"1.0.0"}'
    exit 2
  fi

  if [[ -e "$workspace/$file" ]]; then
    found=$((found + 1))
  else
    missing+=("$file")
  fi
done

if [[ $found -eq $total ]]; then
  echo '{"pass":true,"score":100,"details":"All '"$total"' files exist","grader_version":"1.0.0"}'
  exit 0
else
  missing_list="$(printf '%s, ' "${missing[@]}")"
  echo '{"pass":false,"score":0,"details":"Missing files: '"${missing_list%, }"'","grader_version":"1.0.0"}'
  exit 1
fi
