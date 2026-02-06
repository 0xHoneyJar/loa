#!/usr/bin/env bash
# =============================================================================
# compat-lib.sh - Cross-platform compatibility utilities
# =============================================================================
# Version: 1.0.0
# Part of: Loa Framework
# Issue: https://github.com/0xHoneyJar/loa/issues/195
#
# Provides portable alternatives for commands that behave differently
# across Linux (GNU), macOS (BSD), and Windows WSL.
#
# Design principle: Detect once at source time, dispatch per-call.
# This is the same pattern Kubernetes uses in hack/lib/util.sh —
# cache the platform detection result so every subsequent call is
# a single branch, not a fork+exec of `uname`.
#
# Usage:
#   source .claude/scripts/compat-lib.sh
#
#   sed_inplace 's/old/new/' file.txt
#   canonical=$(get_canonical_path "./relative/../path")
#   sorted=$(echo "$versions" | version_sort)
#   tmpfile=$(make_temp ".log")
#
# Functions:
#   sed_inplace        Portable in-place sed (handles GNU vs BSD)
#   get_canonical_path Portable readlink -f / realpath
#   version_sort       Portable sort -V
#   make_temp          Portable mktemp with suffix support
#   get_file_mtime     Portable file modification time (epoch seconds)
#   find_sorted_by_time Portable find + sort by mtime (no -printf)
#
# Environment:
#   LOA_COMPAT_DEBUG=1   Enable debug output for platform detection
# =============================================================================

# Prevent double-sourcing
if [[ "${_COMPAT_LIB_LOADED:-}" == "true" ]]; then
  return 0 2>/dev/null || exit 0
fi
_COMPAT_LIB_LOADED=true

_COMPAT_LIB_VERSION="1.0.0"

# =============================================================================
# Platform Detection (run once at source time)
#
# Like Chromium's build/detect_host_arch.py — detect early, cache globally,
# avoid per-call overhead. Every function below reads these cached flags
# instead of forking a subprocess.
# =============================================================================

_COMPAT_OS="unknown"
case "$(uname -s)" in
  Darwin)  _COMPAT_OS="darwin" ;;
  Linux)   _COMPAT_OS="linux" ;;
  MINGW*|MSYS*|CYGWIN*) _COMPAT_OS="windows" ;;
esac

# Feature detection for sort -V (absent on macOS <10.15)
_COMPAT_HAS_SORT_V=false
if echo "1.0" | sort -V &>/dev/null; then
  _COMPAT_HAS_SORT_V=true
fi

# Feature detection for GNU sed vs BSD sed
_COMPAT_SED_STYLE="bsd"
if sed --version &>/dev/null 2>&1; then
  _COMPAT_SED_STYLE="gnu"
fi

# Feature detection for readlink -f
_COMPAT_HAS_READLINK_F=false
if readlink -f / &>/dev/null 2>&1; then
  _COMPAT_HAS_READLINK_F=true
fi

# Feature detection for GNU find -printf
_COMPAT_HAS_FIND_PRINTF=false
if find /dev/null -maxdepth 0 -printf '%T+' &>/dev/null 2>&1; then
  _COMPAT_HAS_FIND_PRINTF=true
fi

# Feature detection for GNU stat -c vs BSD stat -f
_COMPAT_STAT_STYLE="bsd"
if stat -c %Y / &>/dev/null 2>&1; then
  _COMPAT_STAT_STYLE="gnu"
fi

if [[ "${LOA_COMPAT_DEBUG:-}" == "1" ]]; then
  echo "[compat-lib] OS: $_COMPAT_OS" >&2
  echo "[compat-lib] sed: $_COMPAT_SED_STYLE" >&2
  echo "[compat-lib] sort -V: $_COMPAT_HAS_SORT_V" >&2
  echo "[compat-lib] readlink -f: $_COMPAT_HAS_READLINK_F" >&2
  echo "[compat-lib] find -printf: $_COMPAT_HAS_FIND_PRINTF" >&2
  echo "[compat-lib] stat: $_COMPAT_STAT_STYLE" >&2
fi

# =============================================================================
# sed_inplace - Portable in-place sed
# =============================================================================
#
# The sed -i portability problem is one of the most common cross-platform
# shell scripting footguns. GNU sed takes `sed -i 's/x/y/' file`, while
# BSD sed (macOS) requires `sed -i '' 's/x/y/' file`. Getting this wrong
# creates a backup file with an empty-string extension on Linux, or fails
# outright on macOS.
#
# Google's Shell Style Guide recommends avoiding sed -i entirely in favor
# of temp-file-and-mv. We provide both: sed_inplace for the common case,
# and the temp-file pattern is documented in the protocol for cases where
# atomic writes matter.
#
# Arguments:
#   All arguments are passed through to sed.
#   The LAST argument must be the file to edit.
#
# Usage:
#   sed_inplace 's/old/new/' file.txt
#   sed_inplace 's/old/new/g' file.txt
#   sed_inplace '/pattern/d' file.txt
#
sed_inplace() {
  if [[ $# -lt 2 ]]; then
    echo "ERROR: sed_inplace requires at least 2 arguments (expression + file)" >&2
    return 1
  fi

  if [[ "$_COMPAT_SED_STYLE" == "gnu" ]]; then
    sed -i "$@"
  else
    # BSD sed: insert empty string as backup extension
    # Collect all args, insert '' after -i
    local args=()
    local file="${!#}"  # last argument
    local i
    for ((i=1; i<$#; i++)); do
      args+=("${!i}")
    done
    sed -i '' "${args[@]}" "$file"
  fi
}

# =============================================================================
# get_canonical_path - Portable canonical path resolution
# =============================================================================
#
# GNU coreutils provides `readlink -f` for canonical path resolution.
# macOS doesn't include it — you need `realpath` (which may also be absent)
# or Homebrew's `greadlink`. This function provides a 3-tier fallback chain:
#
#   1. readlink -f (GNU coreutils — fastest)
#   2. realpath -m (GNU/Python — handles non-existent paths)
#   3. Pure bash fallback (cd + pwd -P — always works)
#
# The pure bash fallback is the same approach used by Node.js's
# `path.resolve()` implementation in their configure script.
#
# Arguments:
#   $1 - Path to resolve (may be relative, may contain symlinks)
#
# Returns:
#   Absolute canonical path on stdout
#
get_canonical_path() {
  local target="$1"

  # Tier 1: GNU readlink -f
  if [[ "$_COMPAT_HAS_READLINK_F" == "true" ]]; then
    readlink -f "$target" 2>/dev/null && return 0
  fi

  # Tier 2: realpath (may exist on macOS via Homebrew or Python)
  if command -v realpath &>/dev/null; then
    realpath -m "$target" 2>/dev/null && return 0
  fi

  # Tier 3: Pure bash fallback
  # Handle both existing and non-existing paths
  if [[ -e "$target" ]]; then
    if [[ -d "$target" ]]; then
      (cd "$target" && pwd -P)
    else
      local dir base
      dir=$(cd "$(dirname "$target")" && pwd -P)
      base=$(basename "$target")
      echo "${dir}/${base}"
    fi
  else
    # Path doesn't exist yet — resolve what we can
    local dir base
    dir=$(dirname "$target")
    base=$(basename "$target")
    if [[ -d "$dir" ]]; then
      echo "$(cd "$dir" && pwd -P)/${base}"
    else
      # Best effort: just make it absolute
      if [[ "$target" == /* ]]; then
        echo "$target"
      else
        echo "$(pwd -P)/${target}"
      fi
    fi
  fi
}

# =============================================================================
# version_sort - Portable version-aware sort
# =============================================================================
#
# GNU sort -V implements "version sort" that handles dotted version strings
# correctly (1.9 < 1.10). macOS sort didn't support -V until 10.15.
#
# The fallback uses `sort -t. -k1,1n -k2,2n -k3,3n` which handles the
# common case of semver-style X.Y.Z versions. This is the same approach
# Homebrew's version comparison uses internally.
#
# Arguments:
#   Reads from stdin, passes additional args to sort
#
# Usage:
#   echo -e "1.10.0\n1.9.0\n1.2.0" | version_sort
#   echo -e "1.10.0\n1.9.0\n1.2.0" | version_sort -r  # reverse
#
version_sort() {
  if [[ "$_COMPAT_HAS_SORT_V" == "true" ]]; then
    sort -V "$@"
  else
    # Fallback: numeric sort by dot-separated components
    # Handles X.Y.Z correctly; breaks on X.Y.Z-rc1 (rare in our codebase)
    sort -t. -k1,1n -k2,2n -k3,3n "$@"
  fi
}

# =============================================================================
# make_temp - Portable mktemp with suffix support
# =============================================================================
#
# GNU mktemp supports `--suffix=.ext`, BSD mktemp does not.
# Both support template patterns with XXXXXX.
#
# Arguments:
#   $1 - (optional) File extension/suffix, e.g., ".log", ".json"
#   $2 - (optional) "-d" to create a directory instead of a file
#
# Returns:
#   Path to created temp file/directory on stdout
#
# Usage:
#   tmpfile=$(make_temp ".json")
#   tmpdir=$(make_temp "" "-d")
#
make_temp() {
  local suffix="${1:-}"
  local dir_flag="${2:-}"

  if [[ "$dir_flag" == "-d" ]]; then
    mktemp -d "${TMPDIR:-/tmp}/loa.XXXXXX"
    return
  fi

  if [[ -z "$suffix" ]]; then
    mktemp "${TMPDIR:-/tmp}/loa.XXXXXX"
    return
  fi

  # Try GNU --suffix first, fall back to template pattern
  if mktemp --suffix="$suffix" "${TMPDIR:-/tmp}/loa.XXXXXX" 2>/dev/null; then
    return 0
  fi

  # BSD fallback: create temp file then rename with suffix
  local tmp
  tmp=$(mktemp "${TMPDIR:-/tmp}/loa.XXXXXX")
  mv "$tmp" "${tmp}${suffix}"
  echo "${tmp}${suffix}"
}

# =============================================================================
# get_file_mtime - Portable file modification time
# =============================================================================
#
# GNU stat uses `-c %Y`, BSD stat uses `-f %m`. Both return epoch seconds.
#
# Many Loa scripts use the inline fallback pattern:
#   stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null
#
# This function caches the detection so the fallback fork only happens once.
#
# Arguments:
#   $1 - File path
#
# Returns:
#   Modification time in seconds since epoch
#
get_file_mtime() {
  local file="$1"

  if [[ "$_COMPAT_STAT_STYLE" == "gnu" ]]; then
    stat -c %Y "$file"
  else
    stat -f %m "$file"
  fi
}

# =============================================================================
# find_sorted_by_time - Portable find + sort by modification time
# =============================================================================
#
# GNU find supports `-printf '%T+ %p\n'` for formatted output.
# BSD find (macOS) does not. This function provides the same semantics
# using portable stat calls.
#
# Arguments:
#   $1 - Directory to search
#   $2 - Name pattern (e.g., "*.snapshot")
#   $3 - (optional) "reverse" for newest-first
#
# Returns:
#   Newline-separated list of files sorted by modification time (oldest first)
#
find_sorted_by_time() {
  local dir="$1"
  local pattern="$2"
  local order="${3:-}"

  if [[ "$_COMPAT_HAS_FIND_PRINTF" == "true" ]]; then
    if [[ "$order" == "reverse" ]]; then
      find "$dir" -name "$pattern" -type f -printf '%T+ %p\n' 2>/dev/null | sort -r | cut -d' ' -f2-
    else
      find "$dir" -name "$pattern" -type f -printf '%T+ %p\n' 2>/dev/null | sort | cut -d' ' -f2-
    fi
  else
    # Portable fallback: stat each file
    local sort_flag=""
    [[ "$order" == "reverse" ]] && sort_flag="-r"

    find "$dir" -name "$pattern" -type f 2>/dev/null | while IFS= read -r file; do
      local mtime
      mtime=$(get_file_mtime "$file" 2>/dev/null) || continue
      printf '%s %s\n' "$mtime" "$file"
    done | sort -n $sort_flag | cut -d' ' -f2-
  fi
}

# =============================================================================
# Version
# =============================================================================

get_compat_lib_version() {
  echo "$_COMPAT_LIB_VERSION"
}
