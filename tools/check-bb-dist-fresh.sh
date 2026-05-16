#!/usr/bin/env bash
# =============================================================================
# tools/check-bb-dist-fresh.sh
#
# cycle-104 sprint-1 T1.4 — BB dist build hygiene drift gate.
#
# Closes the cycle-103 near-miss in which BB TypeScript source could be
# committed without the corresponding `dist/` regenerate, silently shipping
# source-only changes that don't actually run. After cycle-104 Sprint 1
# lands, any PR touching BB TS source MUST also regenerate `dist/` — the
# gate verifies a manifest of source-file content hashes against the
# committed `dist/.build-manifest.json`.
#
# Design (per SDD §1.4.4 + AC-1.6):
#   - Content-hash based (NOT timestamp) so legitimate `dist/` edits do not
#     produce false-positive failures.
#   - Hash the *source* tree (`.ts` files in `resources/` excluding
#     `__tests__/`, `.run/`, `node_modules/`, generated codegen outputs).
#   - Manifest is small (one entry per source file) and committed to
#     `dist/.build-manifest.json` by `npm run build` via this same script
#     in `--write-manifest` mode.
#   - In `--check` mode (default, used by CI), recompute source hashes and
#     compare to the committed manifest. Mismatch or missing manifest →
#     fail with operator instructions.
#
# Usage:
#   tools/check-bb-dist-fresh.sh                 # check mode (CI, default)
#   tools/check-bb-dist-fresh.sh --check         # explicit check
#   tools/check-bb-dist-fresh.sh --write-manifest # build-time manifest write
#   tools/check-bb-dist-fresh.sh --json          # machine-readable output
#
# Exit codes:
#   0 - manifest matches source (dist is fresh) OR manifest written
#   1 - manifest missing or source/manifest hash mismatch (dist is stale)
#   2 - invocation / configuration error
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BB_DIR="$REPO_ROOT/.claude/skills/bridgebuilder-review"
RESOURCES_DIR="$BB_DIR/resources"
DIST_DIR="$BB_DIR/dist"
MANIFEST_PATH="$DIST_DIR/.build-manifest.json"

MODE="check"
JSON_OUTPUT=false

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check) MODE="check"; shift ;;
      --write-manifest) MODE="write"; shift ;;
      --json) JSON_OUTPUT=true; shift ;;
      --help|-h)
        sed -n '/^# Usage:/,/^# Exit codes:/p' "$0" | sed 's/^# //'
        exit 0
        ;;
      *)
        echo "ERROR: unknown argument: $1" >&2
        exit 2
        ;;
    esac
  done
}

# Enumerate source files. Stable sort by path so the combined hash is
# reproducible across runs and platforms. Excludes:
#   - __tests__/ (test files; not shipped to dist)
#   - .run/ (state artifacts)
#   - node_modules/
#   - .build-manifest.json (would create a self-referential cycle)
list_source_files() {
  if [[ ! -d "$RESOURCES_DIR" ]]; then
    echo "ERROR: resources dir not found: $RESOURCES_DIR" >&2
    exit 2
  fi
  find "$RESOURCES_DIR" \
    -type f \
    \( -name "*.ts" -o -name "*.tsx" \) \
    -not -path "*/node_modules/*" \
    -not -path "*/__tests__/*" \
    -not -path "*/.run/*" \
    2>/dev/null \
    | LC_ALL=C sort
}

# Compute SHA-256 of a single file; emit just the hex digest.
hash_file() {
  sha256sum "$1" | cut -d' ' -f1
}

# Compute combined SHA-256 over the sorted list of (relative-path, file-hash)
# pairs. The combined hash is the single value the manifest compares against;
# tested with positive (synced) + negative (stale) controls in bats.
compute_source_hash() {
  local file rel hash
  local hash_lines=""
  while IFS= read -r file; do
    rel="${file#$REPO_ROOT/}"
    hash=$(hash_file "$file")
    hash_lines+="${hash}  ${rel}"$'\n'
  done < <(list_source_files)
  printf '%s' "$hash_lines" | sha256sum | cut -d' ' -f1
}

write_manifest() {
  if [[ ! -d "$DIST_DIR" ]]; then
    echo "ERROR: dist dir not found: $DIST_DIR" >&2
    echo "       run 'npm run build' first to produce dist/, then re-run --write-manifest" >&2
    exit 2
  fi

  local source_hash now file rel hash files_json
  source_hash=$(compute_source_hash)
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  files_json=$(
    while IFS= read -r file; do
      rel="${file#$REPO_ROOT/}"
      hash=$(hash_file "$file")
      jq -n --arg p "$rel" --arg h "$hash" '{path: $p, sha256: $h}'
    done < <(list_source_files) | jq -s '.'
  )

  jq -n \
    --arg version "1.0" \
    --arg generated_at "$now" \
    --arg source_hash "$source_hash" \
    --argjson files "$files_json" \
    '{
      version: $version,
      generated_at: $generated_at,
      source_hash: $source_hash,
      file_count: ($files | length),
      files: $files
    }' > "$MANIFEST_PATH"

  if [[ "$JSON_OUTPUT" == "true" ]]; then
    jq -n --arg source_hash "$source_hash" --arg path "$MANIFEST_PATH" \
      '{outcome: "manifest_written", source_hash: $source_hash, path: $path}'
  else
    echo "[INFO] Wrote BB dist manifest: $MANIFEST_PATH"
    echo "[INFO] source_hash: $source_hash"
  fi
}

check_manifest() {
  if [[ ! -f "$MANIFEST_PATH" ]]; then
    if [[ "$JSON_OUTPUT" == "true" ]]; then
      jq -n --arg path "$MANIFEST_PATH" \
        '{outcome: "manifest_missing", path: $path, fix: "run: cd .claude/skills/bridgebuilder-review && npm run build"}'
    else
      echo "[FAIL] BB dist manifest missing: $MANIFEST_PATH" >&2
      echo "       Fix: cd .claude/skills/bridgebuilder-review && npm run build" >&2
    fi
    exit 1
  fi

  local committed_hash current_hash
  committed_hash=$(jq -r '.source_hash // empty' "$MANIFEST_PATH" 2>/dev/null || true)
  if [[ -z "$committed_hash" ]]; then
    if [[ "$JSON_OUTPUT" == "true" ]]; then
      jq -n --arg path "$MANIFEST_PATH" \
        '{outcome: "manifest_malformed", path: $path, fix: "regenerate via: cd .claude/skills/bridgebuilder-review && npm run build"}'
    else
      echo "[FAIL] BB dist manifest malformed (no source_hash field): $MANIFEST_PATH" >&2
      echo "       Fix: cd .claude/skills/bridgebuilder-review && npm run build" >&2
    fi
    exit 1
  fi

  current_hash=$(compute_source_hash)

  if [[ "$committed_hash" == "$current_hash" ]]; then
    if [[ "$JSON_OUTPUT" == "true" ]]; then
      jq -n --arg source_hash "$current_hash" \
        '{outcome: "fresh", source_hash: $source_hash}'
    else
      echo "[OK] BB dist is fresh (source_hash=$current_hash)"
    fi
    exit 0
  fi

  if [[ "$JSON_OUTPUT" == "true" ]]; then
    jq -n \
      --arg committed "$committed_hash" \
      --arg current "$current_hash" \
      --arg path "$MANIFEST_PATH" \
      '{
        outcome: "stale",
        committed_source_hash: $committed,
        current_source_hash: $current,
        manifest_path: $path,
        fix: "run: cd .claude/skills/bridgebuilder-review && npm run build && git add dist/"
      }'
  else
    echo "[FAIL] BB dist is stale — source files have changed since last build" >&2
    echo "       committed source_hash: $committed_hash" >&2
    echo "       current   source_hash: $current_hash" >&2
    echo "       Fix:" >&2
    echo "         cd .claude/skills/bridgebuilder-review" >&2
    echo "         npm run build" >&2
    echo "         git add dist/" >&2
  fi
  exit 1
}

main() {
  parse_args "$@"
  case "$MODE" in
    write) write_manifest ;;
    check) check_manifest ;;
    *) echo "ERROR: unknown mode: $MODE" >&2; exit 2 ;;
  esac
}

main "$@"
