#!/usr/bin/env bash
# utils.sh — Shell utility functions

# Check if a string is a valid integer
is_integer() {
  local val="$1"
  [[ "$val" =~ ^-?[0-9]+$ ]]
}

# Convert string to uppercase
to_upper() {
  echo "$1" | tr '[:lower:]' '[:upper:]'
}

# Count lines in a file
count_lines() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "0"
    return 1
  fi
  wc -l < "$file"
}

# Check if command exists
command_exists() {
  command -v "$1" &>/dev/null
}
