#!/usr/bin/env bats
# #1065: real malformed capability input plus all eight residual extractors.

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    SCRIPT="$REPO/.claude/scripts/construct-index-gen.sh"
    export PROJECT_ROOT="$BATS_TEST_TMPDIR"
    export LOA_PACKS_DIR="$PROJECT_ROOT/packs"
    export LOA_SKILLS_DIR="$PROJECT_ROOT/skills"
    OUT="$PROJECT_ROOT/index.json"
    mkdir -p "$LOA_PACKS_DIR/demo" "$LOA_SKILLS_DIR/demo"
    cat > "$LOA_PACKS_DIR/demo/manifest.json" <<'JSON'
{"slug":"demo","name":"Manifest name","version":"1.0.0","description":"Manifest description","skills":[{"slug":"demo"}]}
JSON
    cat > "$LOA_SKILLS_DIR/demo/SKILL.md" <<'YAML'
---
capabilities:
  schema_version: 1
  read_files: true
  execute_commands:
    allowed:
      - command: git status
---
YAML
    cat > "$LOA_PACKS_DIR/demo/construct.yaml" <<'YAML'
name: Overlay name
version: 2.0.0
description: Overlay description
YAML
}

@test "#1065 malformed capability YAML warns with pack and field and retains defaults" {
    printf '%s\n' '---' 'capabilities: [' '---' > "$LOA_SKILLS_DIR/demo/SKILL.md"
    run bash "$SCRIPT" --json --quiet --output "$OUT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING: demo/demo capabilities.schema_version: extraction failed"* ]]
    [[ "$output" == *"capabilities.read_files: extraction failed"* ]]
    [[ "$output" == *"capabilities.execute_commands type: extraction failed"* ]]
    jq -e '.constructs[0].aggregated_capabilities | .schema_version == 0 and .read_files == false and .execute_commands == false' "$OUT"
}

@test "#1065 all eight residual sites discard failed partial output and warn" {
    export REAL_YQ="$(command -v yq)"
    mkdir -p "$PROJECT_ROOT/bin"
    cat > "$PROJECT_ROOT/bin/yq" <<'SH'
#!/usr/bin/env bash
for arg in "$@"; do
    if [[ "$arg" == "$FAIL_QUERY" ]]; then
        printf 'poison partial output\n'
        printf 'injected extractor failure\n' >&2
        exit 7
    fi
done
exec "$REAL_YQ" "$@"
SH
    chmod +x "$PROJECT_ROOT/bin/yq"
    export PATH="$PROJECT_ROOT/bin:$PATH"
    local query ctx
    while IFS=';' read -r query ctx; do
        export FAIL_QUERY="$query"
        if [[ "$ctx" == "capabilities.execute_commands" ]]; then
            printf '%s\n' '---' 'capabilities:' '  execute_commands: true' '---' > "$LOA_SKILLS_DIR/demo/SKILL.md"
        fi
        run bash "$SCRIPT" --json --quiet --output "$OUT"
        [ "$status" -eq 0 ]
        [[ "$output" == *"$ctx: extraction failed (exit 7)"* ]]
        ! rg -q 'poison partial output' "$OUT"
    done <<'QUERIES'
.capabilities.schema_version // 0;capabilities.schema_version
.capabilities.read_files // false;capabilities.read_files
.capabilities.execute_commands.allowed // [];capabilities.execute_commands.allowed
.capabilities.execute_commands | type;capabilities.execute_commands type
.name // "";construct.yaml name
.version // "";construct.yaml version
.description // "";construct.yaml description
.capabilities.execute_commands;capabilities.execute_commands
QUERIES
}

@test "#1065 success output retains overlay values and capability union without warnings" {
    run bash "$SCRIPT" --json --quiet --output "$OUT"
    [ "$status" -eq 0 ]
    [[ "$output" != *"WARNING:"* ]]
    jq -e '.constructs[0] | .name == "Overlay name" and .version == "2.0.0" and .description == "Overlay description" and .aggregated_capabilities.read_files == true and .aggregated_capabilities.execute_commands.allowed[0].command == "git status"' "$OUT"
}
