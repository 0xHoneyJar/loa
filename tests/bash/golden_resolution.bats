#!/usr/bin/env bats
# =============================================================================
# tests/bash/golden_resolution.bats — cycle-099 Sprint 2D bash golden runner
# contract pins.
#
# Tests the bash golden test runner (`tests/bash/golden_resolution.sh`) which
# independently re-implements the FR-3.9 6-stage resolver in bash for cross-
# runtime parity verification (per SDD §1.5.1 + §7.6.2).
#
# G-series (G1-G15): per-runner contract pins (output shape, sorting, error
# handling, env-override gates). Cross-runtime byte-equality with Python is
# asserted in `tests/integration/sprint-2D-resolver-parity.bats`.
#
# Sprint 2D supersedes Sprint 1D's alias-lookup-only output shape. The
# Sprint 1D shape `{fixture, input_alias, subset_supported, deferred_to?,
# resolved_provider?, resolved_model_id?}` is replaced by the FR-3.9
# `{fixture, skill, role, resolved_provider, resolved_model_id,
# resolution_path}` OR `{fixture, skill, role, error}` shape.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    FIXTURES_DIR="$PROJECT_ROOT/tests/fixtures/model-resolution"
    GOLDEN_FILE="$FIXTURES_DIR/_golden.cross-runtime.jsonl"
    RUNNER="$PROJECT_ROOT/tests/bash/golden_resolution.sh"
    RESOLVER_PY="$PROJECT_ROOT/.claude/scripts/lib/model-resolver.py"

    [[ -d "$FIXTURES_DIR" ]] || skip "fixtures dir not present"
    [[ -f "$RESOLVER_PY" ]] || skip "model-resolver.py not present"
    command -v jq >/dev/null 2>&1 || skip "jq not present"
    command -v yq >/dev/null 2>&1 || skip "yq not present"

    WORK_DIR="$(mktemp -d)"
}

teardown() {
    if [[ -n "${WORK_DIR:-}" ]] && [[ -d "$WORK_DIR" ]]; then
        rm -rf "$WORK_DIR"
    fi
    return 0
}

@test "G1 runner script exists and is executable" {
    [[ -x "$RUNNER" ]] || {
        printf 'expected runner at %s to be executable\n' "$RUNNER" >&2
        return 1
    }
}

@test "G2 runner emits one JSON line per (fixture × resolution) tuple" {
    "$RUNNER" > "$WORK_DIR/out.jsonl"
    # Today every fixture has 1 resolution → expect 12 lines. If a fixture in
    # the future declares N resolutions, the count grows. The pin asserts
    # one-line-per-resolution invariant.
    local expected_lines
    expected_lines=$(find "$FIXTURES_DIR" -maxdepth 1 -name '*.yaml' -type f \
        -exec yq -o json '.expected.resolutions // [] | length' {} \; \
        | awk '{s+=$1} END{print s}')
    local got_lines
    got_lines=$(wc -l < "$WORK_DIR/out.jsonl")
    [[ "$got_lines" -eq "$expected_lines" ]] || {
        printf 'expected %d output lines (sum of expected.resolutions across fixtures); got %d\n' \
            "$expected_lines" "$got_lines" >&2
        cat "$WORK_DIR/out.jsonl" >&2
        return 1
    }
}

@test "G3 each output line is canonical JSON (sorted keys, no whitespace)" {
    "$RUNNER" > "$WORK_DIR/out.jsonl"
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        echo "$line" | jq -e . >/dev/null || {
            printf 'non-JSON line: %s\n' "$line" >&2
            return 1
        }
        local canonical
        canonical=$(echo "$line" | jq -S -c .)
        [[ "$line" == "$canonical" ]] || {
            printf 'non-canonical line:\n  got: %s\n  exp: %s\n' "$line" "$canonical" >&2
            return 1
        }
    done < "$WORK_DIR/out.jsonl"
}

@test "G4 every line carries fixture + skill + role context" {
    "$RUNNER" > "$WORK_DIR/out.jsonl"
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        echo "$line" | jq -e 'has("fixture") and has("skill") and has("role")' >/dev/null || {
            printf 'missing fixture/skill/role: %s\n' "$line" >&2
            return 1
        }
    done < "$WORK_DIR/out.jsonl"
}

@test "G5 success entries have resolved_provider + resolved_model_id + resolution_path; error entries have error block (mutually exclusive)" {
    "$RUNNER" > "$WORK_DIR/out.jsonl"
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local has_error
        has_error=$(echo "$line" | jq -r 'has("error")')
        if [[ "$has_error" == "true" ]]; then
            echo "$line" | jq -e '
                .error.code and (.error.stage_failed | type == "number") and .error.detail and
                (has("resolved_provider") | not) and (has("resolution_path") | not)
            ' >/dev/null || {
                printf 'error entry malformed or has both error+success fields: %s\n' "$line" >&2
                return 1
            }
        else
            echo "$line" | jq -e '
                has("resolved_provider") and has("resolved_model_id") and has("resolution_path") and
                (.resolution_path | length) > 0
            ' >/dev/null || {
                printf 'success entry missing required fields: %s\n' "$line" >&2
                return 1
            }
        fi
    done < "$WORK_DIR/out.jsonl"
}

@test "G6 stage labels are pinned (stage1_pin_check..stage6_prefer_pro_overlay)" {
    "$RUNNER" > "$WORK_DIR/out.jsonl"
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local has_path
        has_path=$(echo "$line" | jq -r 'has("resolution_path")')
        [[ "$has_path" == "false" ]] && continue
        echo "$line" | jq -e '
            .resolution_path
            | all(.label == "stage1_pin_check"
                  or .label == "stage2_skill_models"
                  or .label == "stage3_tier_groups"
                  or .label == "stage4_legacy_shape"
                  or .label == "stage5_framework_default"
                  or .label == "stage6_prefer_pro_overlay")
        ' >/dev/null || {
            printf 'unknown stage label in: %s\n' "$line" >&2
            return 1
        }
    done < "$WORK_DIR/out.jsonl"
}

@test "G7 output matches committed golden file (regression guard)" {
    "$RUNNER" > "$WORK_DIR/out.jsonl"
    if [[ ! -f "$GOLDEN_FILE" ]]; then
        skip 'golden file not yet committed (initial run); regenerate with: tests/bash/golden_resolution.sh > tests/fixtures/model-resolution/_golden.cross-runtime.jsonl'
    fi
    if ! diff -u "$GOLDEN_FILE" "$WORK_DIR/out.jsonl"; then
        printf 'runner output diverged from golden file.\n' >&2
        printf 'If this is intentional, regenerate with: %s > %s\n' "$RUNNER" "$GOLDEN_FILE" >&2
        return 1
    fi
}

@test "G8 fixture order is stable (sorted by fixture filename, then skill, then role)" {
    "$RUNNER" > "$WORK_DIR/out.jsonl"
    local extracted sorted
    extracted=$(jq -r '"\(.fixture)|\(.skill // "")|\(.role // "")"' < "$WORK_DIR/out.jsonl")
    sorted=$(printf '%s\n' "$extracted" | LC_ALL=C sort)
    [[ "$extracted" == "$sorted" ]] || {
        printf 'output not in (fixture, skill, role) order:\n--- got ---\n%s\n--- want ---\n%s\n' \
            "$extracted" "$sorted" >&2
        return 1
    }
}

@test "G9 fixture 02 (explicit pin) resolves to anthropic:claude-opus-4-7 via stage1" {
    "$RUNNER" > "$WORK_DIR/out.jsonl"
    local line
    line=$(grep '"02-explicit-pin-wins"' "$WORK_DIR/out.jsonl")
    echo "$line" | jq -e '
        .resolved_provider == "anthropic" and
        .resolved_model_id == "claude-opus-4-7" and
        .resolution_path[0].stage == 1 and
        .resolution_path[0].label == "stage1_pin_check"
    ' >/dev/null || {
        printf 'fixture 02 stage1 expectation failed: %s\n' "$line" >&2
        return 1
    }
}

@test "G10 fixture 03 (missing tier) emits [TIER-NO-MAPPING] error" {
    "$RUNNER" > "$WORK_DIR/out.jsonl"
    local line
    line=$(grep '"03-missing-tier-fail-closed"' "$WORK_DIR/out.jsonl")
    echo "$line" | jq -e '
        .error.code == "[TIER-NO-MAPPING]" and
        .error.stage_failed == 3
    ' >/dev/null || {
        printf 'fixture 03 error expectation failed: %s\n' "$line" >&2
        return 1
    }
}

@test "G11 prototype-poisoning skill names emit per-runner uniform output (no JS-style prototype walk)" {
    # cypherpunk CRIT-1 from PR #735 (Sprint 1D) targeted TS `key in obj`
    # walking Object.prototype. In Sprint 2D the equivalent threat surface is
    # in the runners' jq queries — `(.operator_config.skill_models // {})[$s]`
    # where $s is "toString" or "constructor" must NOT match anything in an
    # empty skill_models map. jq's `[]` operator is hasOwn-equivalent, so this
    # is a regression guard against a future runtime swap.
    local synth_dir="$WORK_DIR/synth-proto"
    mkdir -p "$synth_dir"
    for proto_skill in "toString" "constructor" "hasOwnProperty" "valueOf" "__proto__" "isPrototypeOf"; do
        cat > "$synth_dir/zz-${proto_skill}.yaml" <<EOF
description: "cypherpunk CRIT-1 regression — Object.prototype attribute via skill name"
input:
  schema_version: 2
  framework_defaults:
    providers:
      anthropic:
        models:
          claude-opus-4-7: { capabilities: [chat] }
    aliases:
      opus: { provider: anthropic, model_id: claude-opus-4-7 }
  operator_config: {}
expected:
  resolutions:
    - skill: $proto_skill
      role: primary
      error:
        code: "[NO-RESOLUTION]"
        stage_failed: 5
        detail: "no resolution"
EOF
    done
    LOA_GOLDEN_TEST_MODE=1 LOA_GOLDEN_FIXTURES_DIR="$synth_dir" \
        "$RUNNER" > "$WORK_DIR/proto.jsonl"
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        echo "$line" | jq -e '.error.code == "[NO-RESOLUTION]"' >/dev/null || {
            printf 'prototype-skill should NOT resolve as success: %s\n' "$line" >&2
            return 1
        }
    done < "$WORK_DIR/proto.jsonl"
}

@test "G12 LOA_GOLDEN_FIXTURES_DIR ungated → IGNORED (cypherpunk CRIT-3 parity)" {
    local synth_dir="$WORK_DIR/synth-fake"
    mkdir -p "$synth_dir"
    cat > "$synth_dir/zz-fake.yaml" <<'EOF'
description: "fake fixture — should NOT be loaded without test mode"
input:
  schema_version: 2
  framework_defaults: {}
  operator_config: {}
expected:
  resolutions:
    - skill: should_not_appear
      role: primary
      resolved_provider: evil
      resolved_model_id: evil
EOF
    # WITHOUT LOA_GOLDEN_TEST_MODE=1 (and NOT under bats since we use env -i)
    run env -i HOME="$HOME" PATH="$PATH" \
        LOA_GOLDEN_FIXTURES_DIR="$synth_dir" \
        bash "$RUNNER"
    [[ "$status" -eq 0 ]] || {
        printf 'runner should still succeed (override ignored, default loaded); status=%d output=%s\n' \
            "$status" "$output" >&2
        return 1
    }
    # Output should contain the REAL fixtures (e.g., 01-happy-path) — not "should_not_appear"
    [[ "$output" != *"should_not_appear"* ]] || {
        printf 'override should be ignored without test mode; got: %s\n' "$output" >&2
        return 1
    }
}

@test "G12b LOA_GOLDEN_FIXTURES_DIR + LOA_GOLDEN_TEST_MODE=1 → HONORED" {
    local synth_dir="$WORK_DIR/synth-honored"
    mkdir -p "$synth_dir"
    cat > "$synth_dir/zz-honored.yaml" <<'EOF'
description: "honored fixture — loaded under TEST_MODE"
input:
  schema_version: 2
  framework_defaults:
    providers:
      anthropic:
        models:
          claude-opus-4-7: { capabilities: [chat] }
    aliases:
      opus: { provider: anthropic, model_id: claude-opus-4-7 }
  operator_config:
    skill_models:
      synth_skill:
        primary: opus
expected:
  resolutions:
    - skill: synth_skill
      role: primary
      resolved_provider: anthropic
      resolved_model_id: claude-opus-4-7
EOF
    LOA_GOLDEN_TEST_MODE=1 \
    LOA_GOLDEN_FIXTURES_DIR="$synth_dir" \
        "$RUNNER" > "$WORK_DIR/honored.jsonl"
    grep -q '"synth_skill"' "$WORK_DIR/honored.jsonl" || {
        printf 'honored fixture skill should appear under TEST_MODE; got: %s\n' \
            "$(cat "$WORK_DIR/honored.jsonl")" >&2
        return 1
    }
}

@test "G13 malformed YAML emits uniform [YAML-PARSE-FAILED] error" {
    local synth_dir="$WORK_DIR/synth-broken"
    mkdir -p "$synth_dir"
    cat > "$synth_dir/zz-broken.yaml" <<'EOF'
input:
  schema_version: [unbalanced
EOF
    LOA_GOLDEN_TEST_MODE=1 LOA_GOLDEN_FIXTURES_DIR="$synth_dir" \
        "$RUNNER" > "$WORK_DIR/broken.jsonl" 2>&1 || true
    grep -q '\[YAML-PARSE-FAILED\]' "$WORK_DIR/broken.jsonl" || {
        printf 'malformed YAML should emit [YAML-PARSE-FAILED]; got: %s\n' \
            "$(cat "$WORK_DIR/broken.jsonl")" >&2
        return 1
    }
}

@test "G14 fixture lacking expected.resolutions[] emits [NO-EXPECTED-RESOLUTIONS] error" {
    local synth_dir="$WORK_DIR/synth-noexp"
    mkdir -p "$synth_dir"
    cat > "$synth_dir/zz-noexp.yaml" <<'EOF'
description: "no expected resolutions block"
input:
  schema_version: 2
  framework_defaults: {}
  operator_config: {}
EOF
    LOA_GOLDEN_TEST_MODE=1 LOA_GOLDEN_FIXTURES_DIR="$synth_dir" \
        "$RUNNER" > "$WORK_DIR/noexp.jsonl"
    grep -q '\[NO-EXPECTED-RESOLUTIONS\]' "$WORK_DIR/noexp.jsonl" || {
        printf 'fixture without expected.resolutions[] should emit [NO-EXPECTED-RESOLUTIONS]; got: %s\n' \
            "$(cat "$WORK_DIR/noexp.jsonl")" >&2
        return 1
    }
}

@test "G15 IMP-007 alias-collides-with-tier surfaces alias_collides_with_tier=true on stage 3 details" {
    local synth_dir="$WORK_DIR/synth-imp007"
    mkdir -p "$synth_dir"
    cat > "$synth_dir/zz-imp007.yaml" <<'EOF'
description: "IMP-007 — tier-tag wins; collision flag on details"
input:
  schema_version: 2
  framework_defaults:
    providers:
      anthropic:
        models:
          claude-opus-4-7: { capabilities: [chat] }
    aliases:
      opus: { provider: anthropic, model_id: claude-opus-4-7 }
    tier_groups:
      mappings:
        max: { anthropic: opus }
  operator_config:
    skill_models:
      flatline_protocol:
        primary: max
    model_aliases_extra:
      max:
        provider: anthropic
        model_id: claude-opus-4-7
        capabilities: [chat]
expected:
  resolutions:
    - skill: flatline_protocol
      role: primary
      resolved_provider: anthropic
      resolved_model_id: claude-opus-4-7
EOF
    LOA_GOLDEN_TEST_MODE=1 LOA_GOLDEN_FIXTURES_DIR="$synth_dir" \
        "$RUNNER" > "$WORK_DIR/imp007.jsonl"
    grep -q '"alias_collides_with_tier":true' "$WORK_DIR/imp007.jsonl" || {
        printf 'IMP-007 collision flag missing; got: %s\n' "$(cat "$WORK_DIR/imp007.jsonl")" >&2
        return 1
    }
}
