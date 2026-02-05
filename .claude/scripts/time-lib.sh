#!/usr/bin/env bash
# =============================================================================
# time-lib.sh - Cross-platform time utilities
# =============================================================================
# Version: 1.0.0
# Part of: Loa Framework
#
# Provides cross-platform timestamp functions that work on both Linux and macOS.
#
# Problem:
#   - Linux `date` supports %N for nanoseconds: date +%s%3N → 1738742714123
#   - macOS `date` does NOT support %N: date +%s%3N → 1738742714N (literal N)
#   - The fallback pattern `$(date +%s%3N 2>/dev/null || date +%s)000` fails
#     because `date +%s%3N` doesn't error on macOS, it just outputs garbage
#
# Solution:
#   Detect platform once, use appropriate method.
#
# Usage:
#   source .claude/scripts/time-lib.sh
#
#   start=$(get_timestamp_ms)
#   # ... do work ...
#   end=$(get_timestamp_ms)
#   duration=$((end - start))
#   echo "Took ${duration}ms"
#
# Functions:
#   get_timestamp_ms      Returns current time in milliseconds since epoch
#   get_timestamp_ns      Returns current time in nanoseconds (Linux only, ms*1000000 on macOS)
#   get_elapsed_ms        Returns elapsed time since a start timestamp
#   format_duration_ms    Formats milliseconds as human-readable string
#
# Environment:
#   LOA_TIME_DEBUG=1      Enable debug output for timing operations
# =============================================================================

# Prevent double-sourcing
if [[ "${_TIME_LIB_LOADED:-}" == "true" ]]; then
  return 0 2>/dev/null || exit 0
fi
_TIME_LIB_LOADED=true

_TIME_LIB_VERSION="1.0.0"

# =============================================================================
# Platform Detection (run once at source time)
# =============================================================================

_TIME_HAS_NANOSECONDS=false

# Test if date supports %N by checking output format
# On Linux: date +%s%3N → 1738742714123 (all digits)
# On macOS: date +%s%3N → 1738742714N (contains literal N)
_test_output=$(date +%s%3N 2>/dev/null)
if [[ "$_test_output" =~ ^[0-9]+$ ]]; then
  _TIME_HAS_NANOSECONDS=true
fi
unset _test_output

# Debug output
if [[ "${LOA_TIME_DEBUG:-}" == "1" ]]; then
  if [[ "$_TIME_HAS_NANOSECONDS" == "true" ]]; then
    echo "[time-lib] Platform supports nanoseconds (date +%N)" >&2
  else
    echo "[time-lib] Platform does NOT support nanoseconds (using second precision)" >&2
  fi
fi

# =============================================================================
# Core Functions
# =============================================================================

# Get current timestamp in milliseconds since Unix epoch
# Returns: integer milliseconds
get_timestamp_ms() {
  if [[ "$_TIME_HAS_NANOSECONDS" == "true" ]]; then
    # Linux: native millisecond support
    date +%s%3N
  else
    # macOS: multiply seconds by 1000
    # Note: This loses sub-second precision, but is safe for timing operations
    echo "$(($(date +%s) * 1000))"
  fi
}

# Get current timestamp in nanoseconds since Unix epoch
# Returns: integer nanoseconds
# Note: On macOS, this returns milliseconds * 1000000 (microsecond precision lost)
get_timestamp_ns() {
  if [[ "$_TIME_HAS_NANOSECONDS" == "true" ]]; then
    # Linux: native nanosecond support
    date +%s%N
  else
    # macOS: convert seconds to nanoseconds
    echo "$(($(date +%s) * 1000000000))"
  fi
}

# Get elapsed time in milliseconds since a start timestamp
# Arguments:
#   $1 - Start timestamp in milliseconds (from get_timestamp_ms)
# Returns: integer milliseconds elapsed
get_elapsed_ms() {
  local start_ms="$1"
  local end_ms
  end_ms=$(get_timestamp_ms)
  echo $((end_ms - start_ms))
}

# Format milliseconds as human-readable duration
# Arguments:
#   $1 - Duration in milliseconds
# Returns: String like "1.234s" or "45ms" or "2m 30s"
format_duration_ms() {
  local ms="$1"

  if [[ $ms -lt 1000 ]]; then
    echo "${ms}ms"
  elif [[ $ms -lt 60000 ]]; then
    # Less than a minute: show as seconds with 3 decimal places
    local seconds=$((ms / 1000))
    local remainder=$((ms % 1000))
    printf "%d.%03ds\n" "$seconds" "$remainder"
  else
    # More than a minute: show as Xm Ys
    local total_seconds=$((ms / 1000))
    local minutes=$((total_seconds / 60))
    local seconds=$((total_seconds % 60))
    echo "${minutes}m ${seconds}s"
  fi
}

# =============================================================================
# Convenience Functions
# =============================================================================

# Generate a unique ID using timestamp + random
# Useful for run IDs, transaction IDs, etc.
# Returns: String like "1738742714123-a1b2c3"
generate_timestamp_id() {
  local prefix="${1:-}"
  local ts
  ts=$(get_timestamp_ms)
  local rand
  rand=$(printf '%06x' $((RANDOM * RANDOM % 16777216)))

  if [[ -n "$prefix" ]]; then
    echo "${prefix}-${ts}-${rand}"
  else
    echo "${ts}-${rand}"
  fi
}

# =============================================================================
# Version
# =============================================================================

get_time_lib_version() {
  echo "$_TIME_LIB_VERSION"
}
