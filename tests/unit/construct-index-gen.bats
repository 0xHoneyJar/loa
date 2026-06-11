#!/usr/bin/env bats
# =============================================================================
# construct-index-gen.bats — Tests for construct-index-gen.sh
# =============================================================================
# Part of cycle-051, Sprint 103: Index Generation + Capability Aggregation
#
# Tests:
#   1.  Single pack with full manifest generates complete index entry
#   2.  Multiple packs all appear in index
#   3.  Sparse manifest (only name, slug, version) works with null optionals
#   4.  construct.yaml merge: construct.yaml fields win on overlap
#   5.  Missing construct.yaml: manifest-only fields used
#   6.  No packs: exit 1, empty index
#   7.  Malformed manifest.json: skip with warning, don't halt
#   8.  --output flag writes to custom path
#   9.  --quiet flag suppresses log output
#   10. Capability aggregation: union semantics (one true -> all true)
#   11. Capability aggregation: execute_commands merge (true wins over allowed list)
#   12. Missing capabilities in SKILL.md: skip silently

setup() {
    export BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    export PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    SCRIPT="$PROJECT_ROOT/.claude/scripts/construct-index-gen.sh"

    # Create isolated temp directory
    export TEST_TMPDIR="${BATS_TEST_TMPDIR:-$(mktemp -d)}"
    export TEST_PACKS_DIR="$TEST_TMPDIR/packs"
    export TEST_SKILLS_DIR="$TEST_TMPDIR/skills"
    export TEST_OUTPUT_DIR="$TEST_TMPDIR/run"
    export TEST_OUTPUT="$TEST_OUTPUT_DIR/construct-index.yaml"

    mkdir -p "$TEST_PACKS_DIR" "$TEST_SKILLS_DIR" "$TEST_OUTPUT_DIR"

    # Override environment for script
    export LOA_PACKS_DIR="$TEST_PACKS_DIR"
    export LOA_SKILLS_DIR="$TEST_SKILLS_DIR"
    export PROJECT_ROOT="$TEST_TMPDIR"
}

teardown() {
    rm -rf "$TEST_TMPDIR" 2>/dev/null || true
}

# =============================================================================
# Helpers
# =============================================================================

# Create a mock pack with manifest.json
# Args: $1=slug, $2=manifest_json
create_mock_pack() {
    local slug="$1"
    local manifest_json="$2"
    mkdir -p "$TEST_PACKS_DIR/$slug"
    echo "$manifest_json" > "$TEST_PACKS_DIR/$slug/manifest.json"
}

# Create a mock SKILL.md in the skills directory
# Args: $1=skill_slug, $2=frontmatter_content
create_mock_skill() {
    local slug="$1"
    local content="$2"
    mkdir -p "$TEST_SKILLS_DIR/$slug"
    printf '%s' "$content" > "$TEST_SKILLS_DIR/$slug/SKILL.md"
}

# Create a mock construct.yaml in the pack directory
# Args: $1=pack_slug, $2=yaml_content
create_mock_construct_yaml() {
    local slug="$1"
    local content="$2"
    echo "$content" > "$TEST_PACKS_DIR/$slug/construct.yaml"
}

# Full manifest for testing
FULL_MANIFEST='{
  "name": "Test Pack",
  "slug": "test-pack",
  "version": "1.0.0",
  "description": "A test pack for unit testing",
  "tags": ["test", "unit"],
  "skills": [
    {"slug": "test-skill-a", "path": "skills/test-skill-a/"},
    {"slug": "test-skill-b", "path": "skills/test-skill-b/"}
  ],
  "commands": [
    {"name": "test-cmd", "path": "commands/test-cmd.md"}
  ],
  "events": {
    "emits": [
      {"name": "test.event_fired", "version": "1.0.0", "description": "Test event"}
    ],
    "consumes": [
      {"event": "other.event_received", "delivery": "broadcast"}
    ]
  }
}'

SPARSE_MANIFEST='{
  "name": "Sparse Pack",
  "slug": "sparse-pack",
  "version": "0.1.0"
}'

SECOND_MANIFEST='{
  "name": "Second Pack",
  "slug": "second-pack",
  "version": "2.0.0",
  "description": "Another test pack",
  "tags": ["second"],
  "skills": [],
  "commands": [],
  "events": {}
}'

# =============================================================================
# T1: Single pack with full manifest generates complete index entry
# =============================================================================

@test "T1: single pack with full manifest generates complete index entry" {
    create_mock_pack "test-pack" "$FULL_MANIFEST"

    run "$SCRIPT" --json --output "$TEST_OUTPUT" --quiet
    [ "$status" -eq 0 ]
    [ -f "$TEST_OUTPUT" ]

    # Verify top-level structure
    local count
    count=$(jq '.constructs | length' "$TEST_OUTPUT")
    [ "$count" -eq 1 ]

    # Verify fields
    [ "$(jq -r '.constructs[0].slug' "$TEST_OUTPUT")" = "test-pack" ]
    [ "$(jq -r '.constructs[0].name' "$TEST_OUTPUT")" = "Test Pack" ]
    [ "$(jq -r '.constructs[0].version' "$TEST_OUTPUT")" = "1.0.0" ]
    [ "$(jq -r '.constructs[0].description' "$TEST_OUTPUT")" = "A test pack for unit testing" ]

    # Verify skills array
    [ "$(jq '.constructs[0].skills | length' "$TEST_OUTPUT")" -eq 2 ]
    [ "$(jq -r '.constructs[0].skills[0].slug' "$TEST_OUTPUT")" = "test-skill-a" ]

    # Verify commands array
    [ "$(jq '.constructs[0].commands | length' "$TEST_OUTPUT")" -eq 1 ]
    [ "$(jq -r '.constructs[0].commands[0].name' "$TEST_OUTPUT")" = "test-cmd" ]

    # Verify events
    [ "$(jq '.constructs[0].events.emits | length' "$TEST_OUTPUT")" -eq 1 ]
    [ "$(jq -r '.constructs[0].events.emits[0]' "$TEST_OUTPUT")" = "test.event_fired" ]
    [ "$(jq '.constructs[0].events.consumes | length' "$TEST_OUTPUT")" -eq 1 ]
    [ "$(jq -r '.constructs[0].events.consumes[0]' "$TEST_OUTPUT")" = "other.event_received" ]

    # Verify tags
    [ "$(jq '.constructs[0].tags | length' "$TEST_OUTPUT")" -eq 2 ]

    # Verify quick_start (first command name)
    [ "$(jq -r '.constructs[0].quick_start' "$TEST_OUTPUT")" = "test-cmd" ]

    # Verify metadata is present
    [ "$(jq -r '.metadata.generated_at' "$TEST_OUTPUT")" != "null" ]
    [ "$(jq -r '.metadata.generator_version' "$TEST_OUTPUT")" = "1.0.0" ]
}

# =============================================================================
# T2: Multiple packs all appear in index
# =============================================================================

@test "T2: multiple packs all appear in index" {
    create_mock_pack "test-pack" "$FULL_MANIFEST"
    create_mock_pack "second-pack" "$SECOND_MANIFEST"

    run "$SCRIPT" --json --output "$TEST_OUTPUT" --quiet
    [ "$status" -eq 0 ]

    local count
    count=$(jq '.constructs | length' "$TEST_OUTPUT")
    [ "$count" -eq 2 ]

    # Both slugs present
    local slugs
    slugs=$(jq -r '.constructs[].slug' "$TEST_OUTPUT" | sort)
    echo "$slugs" | grep -q "second-pack"
    echo "$slugs" | grep -q "test-pack"
}

# =============================================================================
# T3: Sparse manifest works with null optionals
# =============================================================================

@test "T3: sparse manifest with only name/slug/version works with null optionals" {
    create_mock_pack "sparse-pack" "$SPARSE_MANIFEST"

    run "$SCRIPT" --json --output "$TEST_OUTPUT" --quiet
    [ "$status" -eq 0 ]

    [ "$(jq -r '.constructs[0].slug' "$TEST_OUTPUT")" = "sparse-pack" ]
    [ "$(jq -r '.constructs[0].name' "$TEST_OUTPUT")" = "Sparse Pack" ]
    [ "$(jq -r '.constructs[0].version' "$TEST_OUTPUT")" = "0.1.0" ]
    [ "$(jq -r '.constructs[0].description' "$TEST_OUTPUT")" = "" ]

    # Null optionals
    [ "$(jq -r '.constructs[0].persona_path' "$TEST_OUTPUT")" = "null" ]
    [ "$(jq -r '.constructs[0].quick_start' "$TEST_OUTPUT")" = "null" ]

    # Empty arrays
    [ "$(jq '.constructs[0].skills | length' "$TEST_OUTPUT")" -eq 0 ]
    [ "$(jq '.constructs[0].commands | length' "$TEST_OUTPUT")" -eq 0 ]
    [ "$(jq '.constructs[0].tags | length' "$TEST_OUTPUT")" -eq 0 ]
    [ "$(jq '.constructs[0].writes | length' "$TEST_OUTPUT")" -eq 0 ]
    [ "$(jq '.constructs[0].reads | length' "$TEST_OUTPUT")" -eq 0 ]
}

# =============================================================================
# T4: construct.yaml merge — fields win on overlap
# =============================================================================

@test "T4: construct.yaml fields win on overlap with manifest.json" {
    create_mock_pack "test-pack" "$FULL_MANIFEST"
    create_mock_construct_yaml "test-pack" "
name: Overridden Name
version: 9.9.9
description: Overridden description
writes:
  - grimoires/test/output.md
reads:
  - grimoires/test/input.md
gates:
  review: required
  audit: required
"

    run "$SCRIPT" --json --output "$TEST_OUTPUT" --quiet
    [ "$status" -eq 0 ]

    # construct.yaml wins on overlap
    [ "$(jq -r '.constructs[0].name' "$TEST_OUTPUT")" = "Overridden Name" ]
    [ "$(jq -r '.constructs[0].version' "$TEST_OUTPUT")" = "9.9.9" ]
    [ "$(jq -r '.constructs[0].description' "$TEST_OUTPUT")" = "Overridden description" ]

    # Writes and reads populated from construct.yaml
    [ "$(jq '.constructs[0].writes | length' "$TEST_OUTPUT")" -eq 1 ]
    [ "$(jq -r '.constructs[0].writes[0]' "$TEST_OUTPUT")" = "grimoires/test/output.md" ]
    [ "$(jq '.constructs[0].reads | length' "$TEST_OUTPUT")" -eq 1 ]
    [ "$(jq -r '.constructs[0].reads[0]' "$TEST_OUTPUT")" = "grimoires/test/input.md" ]

    # Gates populated
    [ "$(jq -r '.constructs[0].gates.review' "$TEST_OUTPUT")" = "required" ]
}

# =============================================================================
# T5: Missing construct.yaml — manifest-only fields used
# =============================================================================

@test "T5: missing construct.yaml uses manifest-only fields" {
    create_mock_pack "test-pack" "$FULL_MANIFEST"
    # No construct.yaml created

    run "$SCRIPT" --json --output "$TEST_OUTPUT" --quiet
    [ "$status" -eq 0 ]

    # Manifest fields used
    [ "$(jq -r '.constructs[0].name' "$TEST_OUTPUT")" = "Test Pack" ]
    [ "$(jq -r '.constructs[0].version' "$TEST_OUTPUT")" = "1.0.0" ]

    # Writes/reads/gates are empty defaults
    [ "$(jq '.constructs[0].writes | length' "$TEST_OUTPUT")" -eq 0 ]
    [ "$(jq '.constructs[0].reads | length' "$TEST_OUTPUT")" -eq 0 ]
    [ "$(jq '.constructs[0].gates | length' "$TEST_OUTPUT")" -eq 0 ]
}

# =============================================================================
# T6: No packs — exit 1, empty index
# =============================================================================

@test "T6: no packs exits 1 and writes empty index" {
    # Packs dir exists but empty
    run "$SCRIPT" --json --output "$TEST_OUTPUT" --quiet
    [ "$status" -eq 1 ]
}

# =============================================================================
# T7: Malformed manifest.json — skip with warning, don't halt
# =============================================================================

@test "T7: malformed manifest.json is skipped with warning" {
    # Create a good pack and a bad pack
    create_mock_pack "good-pack" "$SECOND_MANIFEST"
    mkdir -p "$TEST_PACKS_DIR/bad-pack"
    echo "NOT VALID JSON {{{" > "$TEST_PACKS_DIR/bad-pack/manifest.json"

    run "$SCRIPT" --json --output "$TEST_OUTPUT"
    [ "$status" -eq 0 ]

    # Warning emitted
    [[ "$output" == *"WARNING"* ]] || [[ "$output" == *"Malformed"* ]] || [[ "$output" == *"skipping"* ]]

    # Good pack still present
    [ "$(jq '.constructs | length' "$TEST_OUTPUT")" -eq 1 ]
    [ "$(jq -r '.constructs[0].slug' "$TEST_OUTPUT")" = "good-pack" ]
}

# =============================================================================
# T8: --output flag writes to custom path
# =============================================================================

@test "T8: --output flag writes to custom path" {
    create_mock_pack "sparse-pack" "$SPARSE_MANIFEST"

    local custom_path="$TEST_TMPDIR/custom/output/index.json"
    run "$SCRIPT" --json --output "$custom_path" --quiet
    [ "$status" -eq 0 ]
    [ -f "$custom_path" ]

    [ "$(jq -r '.constructs[0].slug' "$custom_path")" = "sparse-pack" ]
}

# =============================================================================
# T9: --quiet flag suppresses log output
# =============================================================================

@test "T9: --quiet flag suppresses log output" {
    create_mock_pack "test-pack" "$SPARSE_MANIFEST"

    # With --quiet: no log lines on stderr captured in output
    run "$SCRIPT" --json --output "$TEST_OUTPUT" --quiet
    [ "$status" -eq 0 ]

    # Should NOT contain log lines (they go to stderr, but bats captures both)
    [[ "$output" != *"Generating construct index"* ]]
    [[ "$output" != *"Processing pack"* ]]

    # Without --quiet: log lines present
    run "$SCRIPT" --json --output "$TEST_OUTPUT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Generating construct index"* ]]
}

# =============================================================================
# T10: Capability aggregation — union semantics (one true -> all true)
# =============================================================================

@test "T10: capability aggregation uses union semantics" {
    create_mock_pack "cap-pack" '{
      "name": "Cap Pack",
      "slug": "cap-pack",
      "version": "1.0.0",
      "skills": [
        {"slug": "skill-reader", "path": "skills/skill-reader/"},
        {"slug": "skill-writer", "path": "skills/skill-writer/"}
      ],
      "commands": [],
      "events": {}
    }'

    # skill-reader: read_files true, write_files false
    create_mock_skill "skill-reader" "---
name: reader
description: Read-only skill
capabilities:
  schema_version: 1
  read_files: true
  search_code: true
  write_files: false
  execute_commands: false
  web_access: false
  user_interaction: false
  agent_spawn: false
  task_management: false
---
# Reader"

    # skill-writer: write_files true, read_files false
    create_mock_skill "skill-writer" "---
name: writer
description: Write skill
capabilities:
  schema_version: 2
  read_files: false
  search_code: false
  write_files: true
  execute_commands: false
  web_access: true
  user_interaction: false
  agent_spawn: false
  task_management: false
---
# Writer"

    run "$SCRIPT" --json --output "$TEST_OUTPUT" --quiet
    [ "$status" -eq 0 ]

    local caps
    caps=$(jq '.constructs[0].aggregated_capabilities' "$TEST_OUTPUT")

    # Union: if ANY skill has true, aggregate is true
    [ "$(echo "$caps" | jq '.read_files')" = "true" ]
    [ "$(echo "$caps" | jq '.search_code')" = "true" ]
    [ "$(echo "$caps" | jq '.write_files')" = "true" ]
    [ "$(echo "$caps" | jq '.web_access')" = "true" ]

    # Both false → aggregate false
    [ "$(echo "$caps" | jq '.agent_spawn')" = "false" ]
    [ "$(echo "$caps" | jq '.task_management')" = "false" ]

    # schema_version = max (2)
    [ "$(echo "$caps" | jq '.schema_version')" = "2" ]
}

# =============================================================================
# T11: Capability aggregation — execute_commands merge (true wins)
# =============================================================================

@test "T11: execute_commands true wins over allowed list" {
    create_mock_pack "exec-pack" '{
      "name": "Exec Pack",
      "slug": "exec-pack",
      "version": "1.0.0",
      "skills": [
        {"slug": "skill-limited", "path": "skills/skill-limited/"},
        {"slug": "skill-unrestricted", "path": "skills/skill-unrestricted/"}
      ],
      "commands": [],
      "events": {}
    }'

    # skill-limited: execute_commands with allowed list
    create_mock_skill "skill-limited" "---
name: limited
description: Limited exec
capabilities:
  schema_version: 1
  read_files: true
  search_code: false
  write_files: false
  execute_commands:
    allowed:
      - command: git
        args: [\"diff\", \"*\"]
  web_access: false
  user_interaction: false
  agent_spawn: false
  task_management: false
---
# Limited"

    # skill-unrestricted: execute_commands true (unrestricted)
    create_mock_skill "skill-unrestricted" "---
name: unrestricted
description: Unrestricted exec
capabilities:
  schema_version: 1
  read_files: false
  search_code: false
  write_files: false
  execute_commands: true
  web_access: false
  user_interaction: false
  agent_spawn: false
  task_management: false
---
# Unrestricted"

    run "$SCRIPT" --json --output "$TEST_OUTPUT" --quiet
    [ "$status" -eq 0 ]

    # true wins over allowed list
    [ "$(jq '.constructs[0].aggregated_capabilities.execute_commands' "$TEST_OUTPUT")" = "true" ]
}

# =============================================================================
# T12: Missing capabilities in SKILL.md — skip silently
# =============================================================================

@test "T12: missing capabilities in SKILL.md skipped silently" {
    create_mock_pack "nocap-pack" '{
      "name": "NoCap Pack",
      "slug": "nocap-pack",
      "version": "1.0.0",
      "skills": [
        {"slug": "skill-nocaps", "path": "skills/skill-nocaps/"}
      ],
      "commands": [],
      "events": {}
    }'

    # SKILL.md with no capabilities field
    create_mock_skill "skill-nocaps" "---
name: nocaps
description: No capabilities
allowed-tools: Read
---
# No Caps"

    run "$SCRIPT" --json --output "$TEST_OUTPUT" --quiet
    [ "$status" -eq 0 ]

    # aggregated_capabilities should be empty object
    [ "$(jq '.constructs[0].aggregated_capabilities' "$TEST_OUTPUT")" = "{}" ]

    # No warning about missing capabilities
    [[ "$output" != *"capabilities"* ]]
}

# =============================================================================
# T13: .type-keyed manifest events extracted (per-element alternation, PR #981)
# =============================================================================
# Regression for the GAP C event-key fix: `[.[].name // .event // .type]`
# evaluates `.event`/`.type` against the outer ARRAY, errors on .type-keyed
# manifests, and the stderr swallow turned that into []. The per-element form
# must extract .type-keyed AND mixed-key arrays with no nulls.

@test "T13: .type-keyed and mixed-key manifest events are extracted" {
    create_mock_pack "type-pack" '{
      "name": "Type Pack",
      "slug": "type-pack",
      "version": "1.0.0",
      "events": {
        "emits": [
          {"type": "gecko.drift_detected", "version": "1.0.0"},
          {"name": "gecko.patrol_complete", "version": "1.0.0"}
        ],
        "consumes": [
          {"type": "keeper.sweep_requested"}
        ]
      }
    }'

    run "$SCRIPT" --json --output "$TEST_OUTPUT" --quiet
    [ "$status" -eq 0 ]

    # Both emit shapes extracted, in order, no nulls
    [ "$(jq '.constructs[0].events.emits | length' "$TEST_OUTPUT")" -eq 2 ]
    [ "$(jq -r '.constructs[0].events.emits[0]' "$TEST_OUTPUT")" = "gecko.drift_detected" ]
    [ "$(jq -r '.constructs[0].events.emits[1]' "$TEST_OUTPUT")" = "gecko.patrol_complete" ]
    [ "$(jq '[.constructs[0].events.emits[] | select(. == null)] | length' "$TEST_OUTPUT")" -eq 0 ]

    # .type-keyed consume extracted
    [ "$(jq '.constructs[0].events.consumes | length' "$TEST_OUTPUT")" -eq 1 ]
    [ "$(jq -r '.constructs[0].events.consumes[0]' "$TEST_OUTPUT")" = "keeper.sweep_requested" ]
}

# =============================================================================
# T14: construct.yaml event membrane overlays manifest events (PR #981)
# =============================================================================

@test "T14: construct.yaml event membrane overlays manifest events" {
    command -v yq >/dev/null || skip "yq not installed"

    create_mock_pack "overlay-pack" '{
      "name": "Overlay Pack",
      "slug": "overlay-pack",
      "version": "1.0.0",
      "events": {
        "emits": [{"name": "manifest.event_old"}],
        "consumes": []
      }
    }'

    # construct.yaml declares the real membrane with .type-keyed events —
    # overlay must WIN over manifest.json when present
    create_mock_construct_yaml "overlay-pack" 'name: Overlay Pack
version: 1.0.0
events:
  emits:
    - type: arcade.loop_designed
    - name: arcade.economy_balanced
  consumes:
    - type: keeper.gap_reported'

    run "$SCRIPT" --json --output "$TEST_OUTPUT" --quiet
    [ "$status" -eq 0 ]

    # Overlay replaced manifest events entirely
    [ "$(jq '.constructs[0].events.emits | length' "$TEST_OUTPUT")" -eq 2 ]
    [ "$(jq -r '.constructs[0].events.emits[0]' "$TEST_OUTPUT")" = "arcade.loop_designed" ]
    [ "$(jq -r '.constructs[0].events.emits[1]' "$TEST_OUTPUT")" = "arcade.economy_balanced" ]
    [ "$(jq -r '.constructs[0].events.consumes[0]' "$TEST_OUTPUT")" = "keeper.gap_reported" ]
    [[ "$(jq -c '.constructs[0].events.emits' "$TEST_OUTPUT")" != *"manifest.event_old"* ]]
}

# =============================================================================
# T15: compose_with[].slug seeding incl. dangling slug (PR #981)
# =============================================================================
# compose_with declarations seed composes_with and are unioned with derived
# read/write overlaps. A dangling slug (no such pack) is PRESERVED — the field
# is a declaration overlay, not a resolved reference; silent filtering would
# hide misdeclarations. This test pins that semantic so a future change to
# filter/warn is a deliberate one.

@test "T15: compose_with slugs seed composes_with, dangling slug preserved" {
    command -v yq >/dev/null || skip "yq not installed"

    create_mock_pack "composer-pack" '{
      "name": "Composer Pack",
      "slug": "composer-pack",
      "version": "1.0.0",
      "events": {}
    }'
    create_mock_construct_yaml "composer-pack" 'name: Composer Pack
version: 1.0.0
compose_with:
  - slug: test-pack
    reason: real peer
  - slug: ghost-pack
    reason: dangling — no such pack'

    # Real peer exists in the index; ghost-pack does not
    create_mock_pack "test-pack" "$FULL_MANIFEST"

    run "$SCRIPT" --json --output "$TEST_OUTPUT" --quiet
    [ "$status" -eq 0 ]

    local composes
    composes=$(jq -c '.constructs[] | select(.slug == "composer-pack") | .composes_with' "$TEST_OUTPUT")
    [[ "$composes" == *"test-pack"* ]]
    [[ "$composes" == *"ghost-pack"* ]]
}
