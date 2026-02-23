#!/usr/bin/env bash
# Simple bash function with conditionals and loops

validate_config() {
  local config_file="$1"
  local errors=0

  if [[ ! -f "$config_file" ]]; then
    echo "ERROR: Config file not found: $config_file" >&2
    return 1
  fi

  local enabled
  enabled=$(yq eval '.enabled // false' "$config_file" 2>/dev/null)
  if [[ "$enabled" != "true" ]]; then
    echo "WARNING: Feature disabled in config" >&2
    errors=$((errors + 1))
  fi

  local timeout
  timeout=$(yq eval '.timeout // 300' "$config_file" 2>/dev/null)
  if [[ $timeout -lt 1 || $timeout -gt 600 ]]; then
    echo "ERROR: Timeout out of range (1-600): $timeout" >&2
    errors=$((errors + 1))
  fi

  return $errors
}
