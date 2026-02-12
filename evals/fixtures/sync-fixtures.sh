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

# Auto-discover additional sync targets from eval task YAML files.
# Scans for pattern-match graders that reference specific source files
# via their args[1] field (the file glob argument to pattern-match.sh).
if command -v yq >/dev/null 2>&1; then
  for task_yaml in "$REPO_ROOT"/evals/tasks/framework/*.yaml; do
    [[ -f "$task_yaml" ]] || continue
    fixture=$(yq '.fixture // ""' "$task_yaml" 2>/dev/null)
    [[ "$fixture" != "loa-skill-dir" ]] && continue

    # Extract file globs from grader args (args[1] is typically the filename)
    file_arg=$(yq '.graders[0].args[1] // ""' "$task_yaml" 2>/dev/null)
    [[ -z "$file_arg" || "$file_arg" == "null" ]] && continue

    # Map known fixture file globs to source paths
    case "$file_arg" in
      golden-path.sh)
        SYNC_MAP[".claude/scripts/golden-path.sh"]=".claude/scripts/golden-path.sh" ;;
      mount-loa.sh)
        SYNC_MAP[".claude/scripts/mount-loa.sh"]=".claude/scripts/mount-loa.sh" ;;
      loa-setup-check.sh)
        SYNC_MAP[".claude/scripts/loa-setup-check.sh"]=".claude/scripts/loa-setup-check.sh" ;;
      rest-api.yaml)
        ;; # Handled by archetype sync loop below
    esac
  done
fi

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

# Also sync archetype files (skip schema.yaml — it's a meta-file, not an archetype)
for src in "$REPO_ROOT"/.claude/data/archetypes/*.yaml; do
  [[ -f "$src" ]] || continue
  fname="$(basename "$src")"
  [[ "$fname" == "schema.yaml" ]] && continue
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

# Validate archetype files against schema
schema_file="$REPO_ROOT/.claude/data/archetypes/schema.yaml"
if [[ -f "$schema_file" ]] && command -v yq >/dev/null 2>&1; then
  for src in "$REPO_ROOT"/.claude/data/archetypes/*.yaml; do
    [[ -f "$src" ]] || continue
    fname="$(basename "$src")"
    [[ "$fname" == "schema.yaml" ]] && continue

    # Validate required top-level fields
    for field in name description tags context; do
      val=$(yq ".$field" "$src" 2>/dev/null)
      if [[ -z "$val" || "$val" == "null" ]]; then
        echo "SCHEMA: $fname missing required field: $field"
        drift_count=$((drift_count + 1))
      fi
    done

    # Validate required context sub-fields
    for field in vision technical non_functional testing risks; do
      val=$(yq ".context.$field" "$src" 2>/dev/null)
      if [[ -z "$val" || "$val" == "null" ]]; then
        echo "SCHEMA: $fname missing required context field: $field"
        drift_count=$((drift_count + 1))
      fi
    done
  done
fi

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
