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
        skip "golden file not yet committed (initial run); will be generated by `bats --tap` + commit step"
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
