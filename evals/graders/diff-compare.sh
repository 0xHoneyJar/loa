#!/usr/bin/env bash
# diff-compare.sh — Compare workspace against expected directory
# Args: $1=workspace, $2=expected directory path (relative to workspace)
# Exit: 0=pass (identical), 1=fail (differences), 2=error
set -euo pipefail

workspace="${1:-}"
expected_dir="${2:-}"

if [[ -z "$workspace" || ! -d "$workspace" ]]; then
  echo '{"pass":false,"score":0,"details":"Invalid workspace","grader_version":"1.0.0"}'
  exit 2
fi

if [[ -z "$expected_dir" ]]; then
  echo '{"pass":false,"score":0,"details":"No expected directory specified","grader_version":"1.0.0"}'
  exit 2
fi

# Reject path traversal
if [[ "$expected_dir" == *".."* ]]; then
  echo '{"pass":false,"score":0,"details":"Path traversal rejected","grader_version":"1.0.0"}'
  exit 2
fi

expected_path="$workspace/$expected_dir"
if [[ ! -d "$expected_path" ]]; then
  echo '{"pass":false,"score":0,"details":"Expected directory not found: '"$expected_dir"'","grader_version":"1.0.0"}'
  exit 2
fi

# Run diff
diff_output=""
diff_exit=0
diff_output="$(diff -rq "$workspace" "$expected_path" --exclude='.git' --exclude='node_modules' --exclude='__pycache__' --exclude="$expected_dir" 2>&1)" || diff_exit=$?

if [[ $diff_exit -eq 0 ]]; then
  echo '{"pass":true,"score":100,"details":"Workspace matches expected output","grader_version":"1.0.0"}'
  exit 0
else
  # Count differences
  diff_count="$(echo "$diff_output" | wc -l)"
  truncated="${diff_output:0:300}"
  truncated_json="$(echo "$truncated" | jq -Rsa .)"
  echo '{"pass":false,"score":0,"details":'"$truncated_json"',"grader_version":"1.0.0"}'
  exit 1
fi
