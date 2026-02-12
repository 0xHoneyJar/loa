#!/usr/bin/env bash
# sync-fixtures.sh — Copy source files into eval fixtures
# Run this after modifying any file that has a fixture copy.
# Usage: evals/fixtures/sync-fixtures.sh [--check]
#   --check: Verify fixtures match source (exit 1 on drift)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FIXTURE_DIR="$SCRIPT_DIR/loa-skill-dir"

# Source → Fixture mapping
# Add new entries here when creating fixture copies of source files.
declare -A SYNC_MAP=(
  [".claude/scripts/golden-path.sh"]=".claude/scripts/golden-path.sh"
  [".claude/scripts/mount-loa.sh"]=".claude/scripts/mount-loa.sh"
  [".claude/scripts/loa-setup-check.sh"]=".claude/scripts/loa-setup-check.sh"
)

check_mode=false
[[ "${1:-}" == "--check" ]] && check_mode=true

drift_count=0

for src_rel in "${!SYNC_MAP[@]}"; do
  dst_rel="${SYNC_MAP[$src_rel]}"
  src="$REPO_ROOT/$src_rel"
  dst="$FIXTURE_DIR/$dst_rel"

  if [[ ! -f "$src" ]]; then
    echo "WARN: Source not found: $src_rel"
    continue
  fi

  if [[ ! -f "$dst" ]]; then
    if [[ "$check_mode" == "true" ]]; then
      echo "DRIFT: Fixture missing: $dst_rel (source exists)"
      drift_count=$((drift_count + 1))
    else
      mkdir -p "$(dirname "$dst")"
      cp "$src" "$dst"
      echo "CREATED: $dst_rel"
    fi
    continue
  fi

  if ! diff -q "$src" "$dst" >/dev/null 2>&1; then
    if [[ "$check_mode" == "true" ]]; then
      echo "DRIFT: $src_rel differs from fixture"
      drift_count=$((drift_count + 1))
    else
      cp "$src" "$dst"
      echo "SYNCED: $dst_rel"
    fi
  else
    [[ "$check_mode" != "true" ]] && echo "OK: $dst_rel (already current)"
  fi
done

# Also sync archetype files
for src in "$REPO_ROOT"/.claude/data/archetypes/*.yaml; do
  [[ -f "$src" ]] || continue
  fname="$(basename "$src")"
  dst="$FIXTURE_DIR/.claude/data/archetypes/$fname"

  if [[ ! -f "$dst" ]]; then
    if [[ "$check_mode" == "true" ]]; then
      echo "DRIFT: Fixture missing: .claude/data/archetypes/$fname"
      drift_count=$((drift_count + 1))
    else
      mkdir -p "$(dirname "$dst")"
      cp "$src" "$dst"
      echo "CREATED: .claude/data/archetypes/$fname"
    fi
  elif ! diff -q "$src" "$dst" >/dev/null 2>&1; then
    if [[ "$check_mode" == "true" ]]; then
      echo "DRIFT: .claude/data/archetypes/$fname differs from fixture"
      drift_count=$((drift_count + 1))
    else
      cp "$src" "$dst"
      echo "SYNCED: .claude/data/archetypes/$fname"
    fi
  fi
done

if [[ "$check_mode" == "true" ]]; then
  if [[ "$drift_count" -gt 0 ]]; then
    echo ""
    echo "ERROR: $drift_count fixture(s) out of sync."
    echo "Run: evals/fixtures/sync-fixtures.sh"
    exit 1
  else
    echo "All fixtures current."
    exit 0
  fi
fi
