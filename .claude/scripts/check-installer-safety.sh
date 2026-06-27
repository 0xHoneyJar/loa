#!/usr/bin/env bash
set -euo pipefail

repo_root="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
failures=0
warnings=0

check_file() {
  local file="$1"
  local path="${repo_root}/${file}"
  if [[ ! -f "$path" ]]; then
    echo "ERROR: missing installer file: $file" >&2
    failures=$((failures + 1))
    return
  fi

  if grep -n 'echo -e' "$path" >/dev/null; then
    echo "WARNING: $file uses echo -e formatting; migrate to printf helpers in a later commit" >&2
    warnings=$((warnings + 1))
  fi

  if grep -n '="\$2"' "$path" >/dev/null; then
    echo "WARNING: $file reads option operands directly from \$2; add operand guards in a later commit" >&2
    warnings=$((warnings + 1))
  fi

  if grep -n '!= "\$repo_root"\*' "$path" >/dev/null; then
    echo "ERROR: $file uses prefix-only repo boundary matching; require repo_root or repo_root/" >&2
    failures=$((failures + 1))
  fi
}

check_file ".claude/scripts/mount-submodule.sh"
check_file ".claude/scripts/mount-loa.sh"

if [[ "$failures" -gt 0 ]]; then
  echo "Installer safety guard failed with ${failures} issue(s) and ${warnings} warning(s)." >&2
  exit 1
fi

echo "Installer safety guard passed with ${warnings} warning(s)."
