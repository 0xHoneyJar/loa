#!/usr/bin/env bats
# =============================================================================
# lockfile-checksum.bats — cycle-099 sprint-1B (T1.6)
# =============================================================================
# Verifies that .claude/defaults/model-config.yaml.checksum matches the
# SHA256 of .claude/defaults/model-config.yaml. The lockfile is the cheap
# drift gate that pairs with sprint-1B's CI workflow (T1.5): if a PR mutates
# the yaml without bumping the checksum, this test (and the CI gate that
# runs it) fails.
#
# Why a separate lockfile when the codegen --check mode already detects
# drift? The codegen --check needs Bun/tsx + node_modules to run; the
# lockfile is a 64-byte hex string and a sha256sum invocation. It catches
# the SAME drift surface from two angles, with different runtime costs.
# Keeps the gate fast on tiny yaml-only PRs.
#
# Sprint plan: grimoires/loa/cycles/cycle-099-model-registry/sprint.md §1
# AC: AC-S1.5 (lockfile checksum bats PASSES on green main; FAILS when
# source mutated without checksum update)

setup() {
    export PROJECT_ROOT="$BATS_TEST_DIRNAME/../.."
    export YAML_PATH="$PROJECT_ROOT/.claude/defaults/model-config.yaml"
    export CHECKSUM_PATH="$PROJECT_ROOT/.claude/defaults/model-config.yaml.checksum"
}

@test "L1: yaml source file exists" {
    [ -f "$YAML_PATH" ]
}

@test "L1: checksum lockfile exists" {
    [ -f "$CHECKSUM_PATH" ]
}

@test "L2: checksum file contains exactly one line of 64-char hex" {
    local content
    content="$(cat "$CHECKSUM_PATH")"
    # Strip trailing newline; ensure remaining content is 64 hex chars.
    local trimmed
    trimmed="$(printf '%s' "$content" | tr -d '\n')"
    [ "${#trimmed}" -eq 64 ]
    [[ "$trimmed" =~ ^[0-9a-f]{64}$ ]]
}

@test "L3: lockfile matches sha256sum of yaml (no drift)" {
    local recorded
    recorded="$(cat "$CHECKSUM_PATH" | tr -d '\n[:space:]')"
    local computed
    computed="$(sha256sum < "$YAML_PATH" | awk '{print $1}')"

    if [ "$recorded" != "$computed" ]; then
        echo "FAIL: model-config.yaml.checksum drift detected"
        echo "  recorded:  $recorded"
        echo "  computed:  $computed"
        echo "  yaml path: $YAML_PATH"
        echo
        echo "If you intentionally modified model-config.yaml, refresh the lockfile:"
        echo "  sha256sum .claude/defaults/model-config.yaml | awk '{print \$1}' > .claude/defaults/model-config.yaml.checksum"
        return 1
    fi
}

@test "L4: tampered yaml produces a different checksum (sanity check)" {
    # Sanity test for the test itself: copy yaml + mutate + verify the
    # computed checksum differs from the recorded one. Confirms the test
    # would catch a real drift, not just pass vacuously.
    local tmp_yaml="$BATS_TEST_TMPDIR/tampered.yaml"
    cp "$YAML_PATH" "$tmp_yaml"
    echo "# drift marker" >> "$tmp_yaml"

    local tampered_sha
    tampered_sha="$(sha256sum < "$tmp_yaml" | awk '{print $1}')"
    local recorded
    recorded="$(cat "$CHECKSUM_PATH" | tr -d '\n[:space:]')"

    [ "$tampered_sha" != "$recorded" ]
}

@test "L5: sha256sum invariant — same input always produces same output" {
    # Determinism guard: two invocations of sha256sum on the same file MUST
    # yield identical hashes. Catches a hypothetical CI environment where
    # sha256sum is shimmed or aliased to something nondeterministic.
    local h1 h2
    h1="$(sha256sum < "$YAML_PATH" | awk '{print $1}')"
    h2="$(sha256sum < "$YAML_PATH" | awk '{print $1}')"
    [ "$h1" = "$h2" ]
}
