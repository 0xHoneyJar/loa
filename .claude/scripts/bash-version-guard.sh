#!/usr/bin/env bash
# =============================================================================
# bash-version-guard.sh - Bash 4.0+ version requirement check
# =============================================================================
# Version: 1.0.0
# Part of: Cross-Platform Shell Compatibility (Issue #240)
#
# Scripts using `declare -A` (associative arrays) require bash 4.0+.
# macOS ships with bash 3.2 by default, causing cryptic "unbound variable"
# errors instead of a clear diagnostic.
#
# Usage:
#   source "${SCRIPT_DIR}/bash-version-guard.sh"
#
# This file checks the bash version immediately when sourced.
# If bash < 4.0, it prints a clear error message and exits.
#
# Design: Source-time check (no function call needed). Same pattern as
# compat-lib.sh — detect once at source time, fail fast.
# =============================================================================

# Guard against double-sourcing
[[ -n "${_BASH_VERSION_GUARD_LOADED:-}" ]] && return 0

if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
    echo "ERROR: bash 4.0+ required (found ${BASH_VERSION})" >&2
    echo "" >&2
    echo "This script uses associative arrays (declare -A) which require bash 4.0+." >&2
    echo "macOS ships with bash 3.2 by default." >&2
    echo "" >&2
    echo "Upgrade bash:" >&2
    echo "  macOS:  brew install bash" >&2
    echo "          Then add /opt/homebrew/bin/bash to /etc/shells" >&2
    echo "          And run: chsh -s /opt/homebrew/bin/bash" >&2
    echo "  Linux:  sudo apt install bash  (usually already 4.0+)" >&2
    exit 1
fi

_BASH_VERSION_GUARD_LOADED=1
