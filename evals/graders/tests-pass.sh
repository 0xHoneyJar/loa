#!/usr/bin/env bash
# tests-pass.sh — Run test suite and check results
# Args: $1=workspace, $2=test command (explicit, no auto-detect)
# Exit: 0=pass, 1=fail, 2=error
set -euo pipefail

workspace="${1:-}"
test_command="${2:-}"

if [[ -z "$workspace" || ! -d "$workspace" ]]; then
  echo '{"pass":false,"score":0,"details":"Invalid workspace","grader_version":"1.0.0"}'
  exit 2
fi

if [[ -z "$test_command" ]]; then
  echo '{"pass":false,"score":0,"details":"No test command specified (auto-detect disabled)","grader_version":"1.0.0"}'
  exit 2
fi

# Validate test command against simple allowlist
allowed_prefixes="node npx python3 pytest bash sh jest mocha"
cmd_first="${test_command%% *}"
allowed=false
for prefix in $allowed_prefixes; do
  if [[ "$cmd_first" == "$prefix" ]]; then
    allowed=true
    break
  fi
done

if [[ "$allowed" == "false" ]]; then
  echo '{"pass":false,"score":0,"details":"Test command not in allowlist: '"$cmd_first"'","grader_version":"1.0.0"}'
  exit 2
fi

# Reject shell metacharacters in command (prevent injection via args)
if echo "$test_command" | grep -qE '[;|&`$\\]'; then
  echo '{"pass":false,"score":0,"details":"Test command contains shell metacharacters","grader_version":"1.0.0"}'
  exit 2
fi

# Split command into array for direct execution (no bash -c subshell)
read -ra cmd_array <<< "$test_command"
if [[ ${#cmd_array[@]} -eq 0 ]]; then
  echo '{"pass":false,"score":0,"details":"Empty test command after parsing","grader_version":"1.0.0"}'
  exit 2
fi

# Run tests from workspace directory
cd "$workspace"
test_output=""
test_exit=0
test_output="$("${cmd_array[@]}" 2>&1)" || test_exit=$?

if [[ $test_exit -eq 0 ]]; then
  echo '{"pass":true,"score":100,"details":"Tests passed","grader_version":"1.0.0"}'
  exit 0
else
  # Truncate output for details
  truncated="${test_output:0:500}"
  # Escape for JSON
  truncated="$(echo "$truncated" | jq -Rsa .)"
  echo '{"pass":false,"score":0,"details":'"$truncated"',"grader_version":"1.0.0"}'
  exit 1
fi
