#!/usr/bin/env bats
# =============================================================================
# tests/unit/zones-schema.bats — cycle-106 sprint-1 T1.4
# =============================================================================
# Validates that grimoires/loa/zones.yaml conforms to
# .claude/data/zones.schema.yaml. Per SDD §8.3 ZS-T1..T5.

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    SCHEMA="$PROJECT_ROOT/.claude/data/zones.schema.yaml"
    INSTANCE="$PROJECT_ROOT/grimoires/loa/zones.yaml"
    [[ -f "$SCHEMA" ]] || skip "schema not at $SCHEMA"

    SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/zsv-XXXXXX")"
    chmod 700 "$SCRATCH"

    # Pick a JSON Schema validator. We use python jsonschema if available;
    # ajv-cli as a fallback. Skip if neither.
    if command -v python3 >/dev/null 2>&1 && python3 -c 'import jsonschema' 2>/dev/null; then
        VALIDATOR="python"
    elif command -v ajv >/dev/null 2>&1; then
        VALIDATOR="ajv"
    else
        skip "neither python3 jsonschema nor ajv available"
    fi
}

teardown() {
    [[ -n "${SCRATCH:-}" && -d "$SCRATCH" ]] && rm -rf "$SCRATCH"
}

# Validate a YAML instance against the schema. Echos PASS/FAIL.
_validate() {
    local instance="$1"
    local schema="${2:-$SCHEMA}"
    if [[ "$VALIDATOR" == "python" ]]; then
        python3 - <<PY 2>&1
import json, sys, yaml
import jsonschema
try:
    schema = yaml.safe_load(open("${schema}"))
    instance = yaml.safe_load(open("${instance}"))
    jsonschema.validate(instance, schema)
    print("PASS")
except jsonschema.ValidationError as e:
    print(f"FAIL: {e.message}")
    sys.exit(1)
except Exception as e:
    print(f"ERROR: {type(e).__name__}: {e}")
    sys.exit(1)
PY
    else
        # ajv expects JSON; convert via yq
        yq -o=json "$schema" > "$SCRATCH/schema.json"
        yq -o=json "$instance" > "$SCRATCH/instance.json"
        ajv validate -s "$SCRATCH/schema.json" -d "$SCRATCH/instance.json" --strict=false 2>&1
    fi
}

# ---- ZS-T1 happy path ----------------------------------------------------

@test "ZS-T1: framework zones.yaml validates clean" {
    [[ -f "$INSTANCE" ]] || skip "framework instance not at $INSTANCE"
    run _validate "$INSTANCE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]] || [[ "$output" == *"valid"* ]]
}

# ---- ZS-T2 missing required field ----------------------------------------

@test "ZS-T2: missing schema_version → validation error" {
    cat > "$SCRATCH/bad.yaml" <<'YAML'
zones:
  framework:
    tracked_paths: [".claude/**"]
  project:
    tracked_paths: ["grimoires/**"]
YAML
    run _validate "$SCRATCH/bad.yaml"
    [ "$status" -ne 0 ]
    [[ "$output" == *"schema_version"* ]] || [[ "$output" == *"required"* ]]
}

# ---- ZS-T3 unknown zone -------------------------------------------------

@test "ZS-T3: unknown zone name → schema error" {
    cat > "$SCRATCH/bad.yaml" <<'YAML'
schema_version: "1.0"
zones:
  framework:
    tracked_paths: [".claude/**"]
  project:
    tracked_paths: ["grimoires/**"]
  evil_zone:
    tracked_paths: ["secret/**"]
YAML
    run _validate "$SCRATCH/bad.yaml"
    [ "$status" -ne 0 ]
}

# ---- ZS-T4 path not a string --------------------------------------------

@test "ZS-T4: path that is not a string → schema error" {
    cat > "$SCRATCH/bad.yaml" <<'YAML'
schema_version: "1.0"
zones:
  framework:
    tracked_paths: [42]
  project:
    tracked_paths: ["grimoires/**"]
YAML
    run _validate "$SCRATCH/bad.yaml"
    [ "$status" -ne 0 ]
}

# ---- ZS-T5 future schema_version ----------------------------------------

@test "ZS-T5: schema_version 2.x → schema error (until 2.0 specced)" {
    cat > "$SCRATCH/bad.yaml" <<'YAML'
schema_version: "2.0"
zones:
  framework:
    tracked_paths: [".claude/**"]
  project:
    tracked_paths: ["grimoires/**"]
YAML
    run _validate "$SCRATCH/bad.yaml"
    [ "$status" -ne 0 ]
}

# ---- ZS-T6 minimum tracked_paths ----------------------------------------

@test "ZS-T6: empty tracked_paths array → schema error (minItems=1)" {
    cat > "$SCRATCH/bad.yaml" <<'YAML'
schema_version: "1.0"
zones:
  framework:
    tracked_paths: []
  project:
    tracked_paths: ["grimoires/**"]
YAML
    run _validate "$SCRATCH/bad.yaml"
    [ "$status" -ne 0 ]
}
