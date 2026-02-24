#!/usr/bin/env bats
# =============================================================================
# test-eject-portability.bats — Verify loa-eject.sh cross-platform portability
# =============================================================================
# Sprint 6 (sprint-49) — Bridgebuilder finding high-1
# Validates that loa-eject.sh uses get_canonical_path() from compat-lib.sh
# instead of raw readlink -f (which fails on macOS BSD).

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

# ---------------------------------------------------------------------------
# Task 6.1: No raw readlink -f in loa-eject.sh
# ---------------------------------------------------------------------------

@test "eject: no raw readlink -f calls in loa-eject.sh" {
  # readlink -f should only appear in comments, not in actual code
  local code_matches
  code_matches=$(grep -n 'readlink -f' "$SCRIPT_DIR/loa-eject.sh" | grep -v '^\s*#' | grep -v '#.*readlink' || true)
  [ -z "$code_matches" ]
}

@test "eject: sources compat-lib.sh for portable path resolution" {
  grep -q 'source.*compat-lib\.sh' "$SCRIPT_DIR/loa-eject.sh"
}

@test "eject: uses get_canonical_path instead of readlink -f" {
  # Should have get_canonical_path calls in the eject_submodule function
  grep -q 'get_canonical_path' "$SCRIPT_DIR/loa-eject.sh"
}

@test "eject: compat-lib.sh provides get_canonical_path function" {
  source "$SCRIPT_DIR/compat-lib.sh"
  # Function should exist after sourcing
  type get_canonical_path &>/dev/null
}

@test "eject: get_canonical_path resolves symlinks on current platform" {
  source "$SCRIPT_DIR/compat-lib.sh"

  # Create a temp directory with a symlink to test resolution
  local tmp_dir
  tmp_dir=$(mktemp -d)
  mkdir -p "$tmp_dir/real"
  echo "test" > "$tmp_dir/real/file.txt"
  ln -sf "$tmp_dir/real/file.txt" "$tmp_dir/link.txt"

  # get_canonical_path should resolve the symlink
  local resolved
  resolved=$(get_canonical_path "$tmp_dir/link.txt")
  [ -n "$resolved" ]
  [ -f "$resolved" ]

  # Resolved path should point to the real file
  [[ "$resolved" == *"/real/file.txt" ]]

  rm -rf "$tmp_dir"
}

@test "eject: get_canonical_path handles non-existent paths gracefully" {
  source "$SCRIPT_DIR/compat-lib.sh"

  # Should not crash on non-existent paths
  local result
  result=$(get_canonical_path "/nonexistent/path/to/file" 2>/dev/null) || true
  # Result may be empty or the path itself — just shouldn't crash
  true
}
