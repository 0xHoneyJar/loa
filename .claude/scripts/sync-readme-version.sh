#!/usr/bin/env bash
# sync-readme-version.sh — keep README.md version references aligned with .loa-version.json
#
# Modes:
#   --check  : exit 1 if README.md drifts from .loa-version.json (CI-friendly)
#   --apply  : rewrite README.md to match .loa-version.json::framework_version
#
# Background: Loa's auto-release pipeline tags + releases on every cycle/bugfix PR
# but does NOT update README.md or .loa-version.json — that's a manual catch-up step.
# This script eliminates the manual step and adds a CI gate to prevent future drift.
#
# Closes cycle-098 PR #685 bridgebuilder findings:
#   - REFRAME (low-conf): "make readme target deriving badge/metadata from .loa-version.json"
#   - CI hardening: "consistency lint that fails when README disagrees with .loa-version.json"
#
# Source: grimoires/loa/a2a/bridge-pr685-summary.md
set -euo pipefail

SCRIPT_NAME="${0##*/}"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
README="$REPO_ROOT/README.md"
VERSION_FILE="$REPO_ROOT/.loa-version.json"

usage() {
  cat <<EOF >&2
Usage: $SCRIPT_NAME <--check|--apply>

  --check   Exit 1 if README.md drifts from .loa-version.json::framework_version (CI mode).
  --apply   Rewrite README.md version references to match .loa-version.json (operator mode).

The script edits two patterns in README.md:
  1. HTML comment "Version: <X.Y.Z>" near the top
  2. Shields.io badge "version-<X.Y.Z>-blue.svg"

Idempotent: running twice produces the same output. Safe to run from CI.
EOF
}

mode="${1:-}"
case "$mode" in
  --check|--apply) ;;
  -h|--help|"") usage; exit 2 ;;
  *) printf '%s\n' "Unknown mode: $mode" >&2; usage; exit 2 ;;
esac

# Pre-flight
[[ -f "$VERSION_FILE" ]] || { printf '%s\n' "ERROR: $VERSION_FILE not found" >&2; exit 2; }
[[ -f "$README" ]] || { printf '%s\n' "ERROR: $README not found" >&2; exit 2; }
command -v jq >/dev/null || { printf '%s\n' "ERROR: jq required" >&2; exit 2; }

version=$(jq -r '.framework_version // empty' "$VERSION_FILE")
[[ -n "$version" ]] || { printf '%s\n' "ERROR: .framework_version missing from $VERSION_FILE" >&2; exit 2; }

# Validate version string format (semver: X.Y.Z)
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf '%s\n' "ERROR: .framework_version='$version' is not semver (expected X.Y.Z)" >&2
  exit 2
fi

# Detect drift: are both expected lines present?
expected_comment="Version: $version"
expected_badge="version-$version-blue.svg"

drift_lines=()
grep -qF "$expected_comment" "$README" || drift_lines+=("HTML comment 'Version: $version'")
grep -qF "$expected_badge" "$README" || drift_lines+=("badge 'version-$version-blue.svg'")

if [[ ${#drift_lines[@]} -eq 0 ]]; then
  printf 'OK: README.md version refs in sync (v%s)\n' "$version"
  exit 0
fi

if [[ "$mode" == "--check" ]]; then
  printf 'DRIFT: README.md does not match .loa-version.json::framework_version=%s\n' "$version" >&2
  printf 'Missing in README.md:\n' >&2
  printf '  - %s\n' "${drift_lines[@]}" >&2
  printf 'Fix: %s --apply\n' ".claude/scripts/sync-readme-version.sh" >&2
  exit 1
fi

# --apply: rewrite README.md (portable sed via tmpfile pattern; no -i.bak)
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

sed -E \
  -e "s|^Version: [0-9]+\\.[0-9]+\\.[0-9]+\$|Version: $version|" \
  -e "s|version-[0-9]+\\.[0-9]+\\.[0-9]+-blue\\.svg|version-$version-blue.svg|g" \
  "$README" > "$tmp"

if cmp -s "$tmp" "$README"; then
  printf 'NO-OP: README.md already at v%s (no changes)\n' "$version"
  exit 0
fi

mv "$tmp" "$README"
printf 'UPDATED: README.md version refs synced to v%s\n' "$version"
