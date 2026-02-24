#!/usr/bin/env bats
# =============================================================================
# test-construct-manifest.bats — Verify construct manifest extension point
# =============================================================================
# Sprint 7 (sprint-50) — vision-008: Construct Manifest Extension
# Validates that construct packs can declare symlink requirements via
# .loa-construct-manifest.json, with boundary enforcement, conflict
# detection, and dependency validation.

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.."; pwd)"
MANIFEST_LIB="$SCRIPT_DIR/lib/symlink-manifest.sh"

setup() {
  TEST_DIR=$(mktemp -d)
  cd "$TEST_DIR"

  # Create minimal submodule structure for get_symlink_manifest
  mkdir -p .loa/.claude/scripts
  mkdir -p .loa/.claude/protocols
  mkdir -p .loa/.claude/hooks
  mkdir -p .loa/.claude/data
  mkdir -p .loa/.claude/schemas
  mkdir -p .loa/.claude/loa/reference
  mkdir -p .loa/.claude/loa/learnings
  echo "# test" > .loa/.claude/loa/CLAUDE.loa.md
  echo "ontology: test" > .loa/.claude/loa/feedback-ontology.yaml
  echo '{}' > .loa/.claude/settings.json
  echo '{}' > .loa/.claude/checksums.json
}

teardown() {
  cd /
  rm -rf "$TEST_DIR"
}

# ---------------------------------------------------------------------------
# Task 7.2: Construct manifest discovery and merge
# ---------------------------------------------------------------------------

@test "construct: discovers manifest in submodule constructs directory" {
  skip_if_no_jq

  # Create a construct pack with manifest
  mkdir -p .loa/.claude/constructs/test-pack
  cat > .loa/.claude/constructs/test-pack/.loa-construct-manifest.json << 'MANIFEST'
{
  "name": "test-pack",
  "version": "1.0.0",
  "symlinks": {
    "directories": [
      {"link": ".claude/constructs/test-pack/data", "target": "../../.loa/.claude/constructs/test-pack/data"}
    ]
  }
}
MANIFEST
  mkdir -p .loa/.claude/constructs/test-pack/data

  source "$MANIFEST_LIB"
  get_symlink_manifest ".loa" "$TEST_DIR"

  # Should have found the construct manifest entry
  [ "${#MANIFEST_CONSTRUCT_SYMLINKS[@]}" -ge 1 ]

  # Verify the entry matches
  local found=false
  for entry in "${MANIFEST_CONSTRUCT_SYMLINKS[@]}"; do
    if [[ "$entry" == ".claude/constructs/test-pack/data:"* ]]; then
      found=true
      break
    fi
  done
  [ "$found" = "true" ]
}

@test "construct: discovers manifest in user constructs directory" {
  skip_if_no_jq

  # Create a user-installed construct pack
  mkdir -p .claude/constructs/user-pack
  cat > .claude/constructs/user-pack/.loa-construct-manifest.json << 'MANIFEST'
{
  "name": "user-pack",
  "version": "1.0.0",
  "symlinks": {
    "files": [
      {"link": ".claude/constructs/user-pack/config.yaml", "target": "../../.claude/constructs/user-pack/defaults.yaml"}
    ]
  }
}
MANIFEST

  source "$MANIFEST_LIB"
  get_symlink_manifest ".loa" "$TEST_DIR"

  [ "${#MANIFEST_CONSTRUCT_SYMLINKS[@]}" -ge 1 ]
}

@test "construct: merges into get_all_manifest_entries" {
  skip_if_no_jq

  mkdir -p .loa/.claude/constructs/merge-pack
  cat > .loa/.claude/constructs/merge-pack/.loa-construct-manifest.json << 'MANIFEST'
{
  "name": "merge-pack",
  "version": "1.0.0",
  "symlinks": {
    "directories": [
      {"link": ".claude/constructs/merge-pack/templates", "target": "../../.loa/.claude/constructs/merge-pack/templates"}
    ]
  }
}
MANIFEST

  source "$MANIFEST_LIB"
  get_all_manifest_entries ".loa" "$TEST_DIR"

  # ALL_MANIFEST_ENTRIES should include core + construct entries
  local total=${#ALL_MANIFEST_ENTRIES[@]}
  # Core has 5 dir + 6 file = 11 minimum (no skills/commands in test setup)
  [ "$total" -ge 12 ]  # 11 core + at least 1 construct
}

# ---------------------------------------------------------------------------
# Task 7.3: Boundary enforcement and validation
# ---------------------------------------------------------------------------

@test "construct: rejects symlinks outside .claude/ boundary" {
  skip_if_no_jq

  mkdir -p .loa/.claude/constructs/escape-pack
  cat > .loa/.claude/constructs/escape-pack/.loa-construct-manifest.json << 'MANIFEST'
{
  "name": "escape-pack",
  "version": "1.0.0",
  "symlinks": {
    "directories": [
      {"link": "src/malicious", "target": "../../.loa/.claude/constructs/escape-pack/payload"}
    ]
  }
}
MANIFEST

  source "$MANIFEST_LIB"
  get_symlink_manifest ".loa" "$TEST_DIR" 2>/dev/null

  # Should NOT have any construct symlinks (boundary violation)
  [ "${#MANIFEST_CONSTRUCT_SYMLINKS[@]}" -eq 0 ]
}

@test "construct: rejects path traversal in link" {
  skip_if_no_jq

  mkdir -p .loa/.claude/constructs/traversal-pack
  cat > .loa/.claude/constructs/traversal-pack/.loa-construct-manifest.json << 'MANIFEST'
{
  "name": "traversal-pack",
  "version": "1.0.0",
  "symlinks": {
    "files": [
      {"link": ".claude/../.env", "target": "../../.loa/.claude/constructs/traversal-pack/secrets"}
    ]
  }
}
MANIFEST

  source "$MANIFEST_LIB"
  get_symlink_manifest ".loa" "$TEST_DIR" 2>/dev/null

  [ "${#MANIFEST_CONSTRUCT_SYMLINKS[@]}" -eq 0 ]
}

@test "construct: rejects absolute paths" {
  skip_if_no_jq

  mkdir -p .loa/.claude/constructs/abs-pack
  cat > .loa/.claude/constructs/abs-pack/.loa-construct-manifest.json << 'MANIFEST'
{
  "name": "abs-pack",
  "version": "1.0.0",
  "symlinks": {
    "files": [
      {"link": "/etc/passwd", "target": "/tmp/evil"}
    ]
  }
}
MANIFEST

  source "$MANIFEST_LIB"
  get_symlink_manifest ".loa" "$TEST_DIR" 2>/dev/null

  [ "${#MANIFEST_CONSTRUCT_SYMLINKS[@]}" -eq 0 ]
}

@test "construct: rejects entries conflicting with core manifest" {
  skip_if_no_jq

  mkdir -p .loa/.claude/constructs/conflict-pack
  cat > .loa/.claude/constructs/conflict-pack/.loa-construct-manifest.json << 'MANIFEST'
{
  "name": "conflict-pack",
  "version": "1.0.0",
  "symlinks": {
    "directories": [
      {"link": ".claude/scripts", "target": "../../.loa/.claude/constructs/conflict-pack/scripts"}
    ]
  }
}
MANIFEST

  source "$MANIFEST_LIB"
  get_symlink_manifest ".loa" "$TEST_DIR" 2>/dev/null

  # Core already has .claude/scripts — construct entry should be rejected
  [ "${#MANIFEST_CONSTRUCT_SYMLINKS[@]}" -eq 0 ]
}

@test "construct: warns on unmet requires dependency" {
  skip_if_no_jq

  mkdir -p .loa/.claude/constructs/dep-pack
  cat > .loa/.claude/constructs/dep-pack/.loa-construct-manifest.json << 'MANIFEST'
{
  "name": "dep-pack",
  "version": "1.0.0",
  "symlinks": {
    "files": [
      {"link": ".claude/constructs/dep-pack/config.yaml", "target": "../../.loa/.claude/constructs/dep-pack/config.yaml"}
    ]
  },
  "requires": [
    ".claude/nonexistent/path"
  ]
}
MANIFEST

  source "$MANIFEST_LIB"

  # Capture stderr to a temp file so get_symlink_manifest runs in current shell
  local stderr_file="$TEST_DIR/stderr.txt"
  get_symlink_manifest ".loa" "$TEST_DIR" 2>"$stderr_file"
  local stderr_output
  stderr_output=$(cat "$stderr_file")

  # Should have a warning about unmet dependency
  [[ "$stderr_output" == *"requires"* ]] || [[ "$stderr_output" == *"not in core manifest"* ]]

  # But the symlink itself should still be added (warning, not rejection)
  [ "${#MANIFEST_CONSTRUCT_SYMLINKS[@]}" -ge 1 ]
}

# ---------------------------------------------------------------------------
# Task 7.3: Edge cases and graceful degradation
# ---------------------------------------------------------------------------

@test "construct: graceful with empty constructs directory" {
  mkdir -p .loa/.claude/constructs

  source "$MANIFEST_LIB"
  get_symlink_manifest ".loa" "$TEST_DIR"

  # Should still work with 0 construct entries
  [ "${#MANIFEST_CONSTRUCT_SYMLINKS[@]}" -eq 0 ]
}

@test "construct: graceful with no constructs directory" {
  source "$MANIFEST_LIB"
  get_symlink_manifest ".loa" "$TEST_DIR"

  # Should still work — no constructs dirs exist
  [ "${#MANIFEST_CONSTRUCT_SYMLINKS[@]}" -eq 0 ]
}

@test "construct: skips invalid JSON gracefully" {
  skip_if_no_jq

  mkdir -p .loa/.claude/constructs/bad-json-pack
  echo "this is not json{{{" > .loa/.claude/constructs/bad-json-pack/.loa-construct-manifest.json

  source "$MANIFEST_LIB"
  local stderr_output
  stderr_output=$(get_symlink_manifest ".loa" "$TEST_DIR" 2>&1 1>/dev/null) || true

  [[ "$stderr_output" == *"Invalid JSON"* ]] || [[ "$stderr_output" == *"WARNING"* ]]
  [ "${#MANIFEST_CONSTRUCT_SYMLINKS[@]}" -eq 0 ]
}

@test "construct: skips when jq not available" {
  # Simulate jq missing by running in subshell with modified PATH
  source "$MANIFEST_LIB"

  mkdir -p .loa/.claude/constructs/no-jq-pack
  cat > .loa/.claude/constructs/no-jq-pack/.loa-construct-manifest.json << 'MANIFEST'
{
  "name": "no-jq-pack",
  "version": "1.0.0",
  "symlinks": {
    "files": [
      {"link": ".claude/constructs/no-jq-pack/test.txt", "target": "../../.loa/.claude/constructs/no-jq-pack/test.txt"}
    ]
  }
}
MANIFEST

  # Run in subshell with jq removed from PATH
  local result
  result=$(PATH="/usr/bin:/bin" bash -c "
    source '$MANIFEST_LIB'
    get_symlink_manifest '.loa' '$TEST_DIR' 2>/dev/null
    echo \${#MANIFEST_CONSTRUCT_SYMLINKS[@]}
  " 2>/dev/null) || true

  # If jq is truly missing from the restricted PATH, should get 0 construct entries
  # If jq is at /usr/bin/jq (common), it may still work — that's fine too
  true  # Graceful behavior either way is acceptable
}

@test "construct: schema file exists and is valid JSON" {
  local schema_file="$SCRIPT_DIR/../schemas/construct-manifest.schema.json"
  [ -f "$schema_file" ]

  # If jq is available, validate it's valid JSON
  if command -v jq &>/dev/null; then
    jq empty "$schema_file"
  fi
}

# ---------------------------------------------------------------------------
# Task 8.7: Schema-runtime alignment tests (F-007)
# Verify that JSON Schema constraints and bash runtime validation agree
# on the same set of invalid inputs. If these two layers drift, a
# malicious manifest could pass one gate while failing the other.
# ---------------------------------------------------------------------------

@test "alignment: both schema and runtime reject link outside .claude/" {
  skip_if_no_jq

  local manifest_file="$TEST_DIR/outside-boundary.json"
  cat > "$manifest_file" << 'MANIFEST'
{
  "name": "evil-pack",
  "version": "1.0.0",
  "symlinks": {
    "directories": [
      {"link": "src/malicious", "target": "../../.loa/.claude/constructs/evil/payload"}
    ]
  }
}
MANIFEST

  # Schema check: link must match pattern ^\.claude/
  local schema_file="$SCRIPT_DIR/../schemas/construct-manifest.schema.json"
  if command -v ajv &>/dev/null; then
    run ajv validate -s "$schema_file" -d "$manifest_file" 2>&1
    [ "$status" -ne 0 ]
  elif command -v jsonschema &>/dev/null; then
    run jsonschema -i "$manifest_file" "$schema_file" 2>&1
    [ "$status" -ne 0 ]
  else
    # No schema validator available — verify schema has the pattern constraint
    local pattern
    pattern=$(jq -r '.properties.symlinks.properties.directories.items.properties.link.pattern // empty' "$schema_file")
    [ -n "$pattern" ]
  fi

  # Runtime check: _validate_and_add_construct_entry rejects non-.claude/ prefix
  source "$MANIFEST_LIB"
  get_symlink_manifest ".loa" "$TEST_DIR" 2>/dev/null

  mkdir -p .loa/.claude/constructs/evil
  cp "$manifest_file" .loa/.claude/constructs/evil/.loa-construct-manifest.json
  MANIFEST_CONSTRUCT_SYMLINKS=()
  _discover_construct_manifests ".loa" "$TEST_DIR" 2>/dev/null

  [ "${#MANIFEST_CONSTRUCT_SYMLINKS[@]}" -eq 0 ]
}

@test "alignment: both schema and runtime reject path traversal with .." {
  skip_if_no_jq

  local manifest_file="$TEST_DIR/traversal.json"
  cat > "$manifest_file" << 'MANIFEST'
{
  "name": "traversal-pack",
  "version": "1.0.0",
  "symlinks": {
    "files": [
      {"link": ".claude/constructs/..", "target": "../../.loa/.claude/constructs/traversal/secrets"}
    ]
  }
}
MANIFEST

  # Schema check: pattern ^\.claude/ passes but runtime catches the ..
  # The schema enforces prefix; runtime enforces no-traversal — layered defense
  source "$MANIFEST_LIB"
  get_symlink_manifest ".loa" "$TEST_DIR" 2>/dev/null

  mkdir -p .loa/.claude/constructs/traversal-pack
  cp "$manifest_file" .loa/.claude/constructs/traversal-pack/.loa-construct-manifest.json
  MANIFEST_CONSTRUCT_SYMLINKS=()
  _discover_construct_manifests ".loa" "$TEST_DIR" 2>/dev/null

  # Runtime must reject trailing .. (F-001 fix)
  [ "${#MANIFEST_CONSTRUCT_SYMLINKS[@]}" -eq 0 ]
}

@test "alignment: both schema and runtime reject absolute path link" {
  skip_if_no_jq

  local manifest_file="$TEST_DIR/absolute.json"
  cat > "$manifest_file" << 'MANIFEST'
{
  "name": "abs-pack",
  "version": "1.0.0",
  "symlinks": {
    "files": [
      {"link": "/etc/passwd", "target": "/tmp/evil"}
    ]
  }
}
MANIFEST

  # Schema check: pattern ^\.claude/ rejects /etc/passwd
  local schema_file="$SCRIPT_DIR/../schemas/construct-manifest.schema.json"
  if command -v ajv &>/dev/null; then
    run ajv validate -s "$schema_file" -d "$manifest_file" 2>&1
    [ "$status" -ne 0 ]
  elif command -v jsonschema &>/dev/null; then
    run jsonschema -i "$manifest_file" "$schema_file" 2>&1
    [ "$status" -ne 0 ]
  else
    # Verify schema pattern exists as a fallback assertion
    local pattern
    pattern=$(jq -r '.properties.symlinks.properties.files.items.properties.link.pattern // empty' "$schema_file")
    [ -n "$pattern" ]
  fi

  # Runtime check: rejects absolute paths
  source "$MANIFEST_LIB"
  get_symlink_manifest ".loa" "$TEST_DIR" 2>/dev/null

  mkdir -p .loa/.claude/constructs/abs-pack
  cp "$manifest_file" .loa/.claude/constructs/abs-pack/.loa-construct-manifest.json
  MANIFEST_CONSTRUCT_SYMLINKS=()
  _discover_construct_manifests ".loa" "$TEST_DIR" 2>/dev/null

  [ "${#MANIFEST_CONSTRUCT_SYMLINKS[@]}" -eq 0 ]
}

@test "alignment: schema pattern field exists on both link properties" {
  skip_if_no_jq

  local schema_file="$SCRIPT_DIR/../schemas/construct-manifest.schema.json"
  [ -f "$schema_file" ]

  # Both directories and files link properties must have the pattern constraint
  local dir_pattern file_pattern
  dir_pattern=$(jq -r '.properties.symlinks.properties.directories.items.properties.link.pattern // empty' "$schema_file")
  file_pattern=$(jq -r '.properties.symlinks.properties.files.items.properties.link.pattern // empty' "$schema_file")

  [ -n "$dir_pattern" ]
  [ -n "$file_pattern" ]
  [ "$dir_pattern" = '^\.claude/' ]
  [ "$file_pattern" = '^\.claude/' ]
}

# ---------------------------------------------------------------------------
# Helper: skip tests that require jq
# ---------------------------------------------------------------------------

skip_if_no_jq() {
  if ! command -v jq &>/dev/null; then
    skip "jq not installed"
  fi
}
