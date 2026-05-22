#!/usr/bin/env bats
# =============================================================================
# Issue #927 — mount-submodule validate_symlink_target resolves from CWD
# instead of from symlink's parent directory
# =============================================================================
# Pre-fix, validate_symlink_target("../.loa/.claude/scripts") resolved the
# target relative to the script's CWD (the repo root), where ../.loa/...
# does not exist. Result: a "Cannot resolve symlink target" warning fired
# for every legitimate symlink the mount path creates (~100+ warnings).
#
# Post-fix, the validator accepts an optional 2nd arg (source = symlink
# file path) and resolves relative targets against dirname(source).
#
# Test strategy: structural diff check — the validator function's
# signature MUST accept a 2nd arg and the resolve_base logic MUST use
# dirname(source) when source is provided. This is a regression guard.
# A full integration test would require running mount-submodule.sh
# end-to-end against a fixture submodule, which is heavy and tested
# in cycle-099 fixture tests separately.
# =============================================================================

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    MOUNT="$REPO_ROOT/.claude/scripts/mount-submodule.sh"
    [[ -f "$MOUNT" ]] || skip "mount-submodule.sh not found"
}

@test "#927: validate_symlink_target accepts 2nd arg (source)" {
    # Pre-fix: `local target="$1"` followed immediately by `local repo_root`
    # Post-fix: `local target="$1"` followed (within ~5 lines) by
    #          `local source="${2:-}"` (or equivalent 2nd arg capture).
    # 15-line window covers the function preamble (comments + arg binds).
    grep -A15 'validate_symlink_target() {' "$MOUNT" \
        | grep -qE 'source="\$\{?2' \
        || {
            echo "REGRESSION: validate_symlink_target signature dropped 2nd arg" >&2
            echo "Pre-fix bug per #927: resolves from CWD, warns on every relative target" >&2
            return 1
        }
}

@test "#927: safe_symlink passes \$source to validate_symlink_target" {
    # The caller must pass both args, not just target.
    grep -E 'validate_symlink_target "\$target"' "$MOUNT" \
        | grep -qE '"\$target" "\$source"' \
        || {
            echo "REGRESSION: safe_symlink no longer passes source to validate_symlink_target" >&2
            return 1
        }
}

@test "#927: resolve_base uses dirname(source) for relative targets" {
    # The core logic of the fix: when source is provided AND target is
    # relative, resolve_base must equal `dirname "$source"`. Static check.
    grep -qE 'resolve_base=.*dirname.*source' "$MOUNT" \
        || {
            echo "REGRESSION: relative-target resolve_base no longer derives from source" >&2
            return 1
        }
}

@test "#927: behavioral — relative target with source arg resolves cleanly" {
    # End-to-end: extract just validate_symlink_target into a standalone
    # harness, exercise it with the failing case from the issue body.
    # We bypass the lib-source maze in mount-submodule.sh by writing a
    # minimal harness that supplies the helpers the function depends on.
    local tmp_harness
    tmp_harness=$(mktemp)

    # Minimal stubs for the helpers validate_symlink_target uses.
    cat > "$tmp_harness" <<'HARNESS'
warn() { echo "WARN: $*" >&2; }
err()  { echo "ERR:  $*" >&2; }
get_repo_root() { echo "$REPO_ROOT_OVERRIDE"; }
HARNESS

    # Extract the validate_symlink_target function body from the script.
    awk '/^validate_symlink_target\(\) \{/,/^\}/' "$MOUNT" >> "$tmp_harness"

    # Build a stub repo layout: $TMP/.loa/.claude/scripts exists,
    # symlink at $TMP/.claude/scripts -> ../.loa/.claude/scripts should
    # validate cleanly.
    local tmp_repo
    tmp_repo=$(mktemp -d)
    mkdir -p "$tmp_repo/.loa/.claude/scripts"
    mkdir -p "$tmp_repo/.claude"

    # Append the invocation to the harness
    cat >> "$tmp_harness" <<HARNESS_INVOKE

cd "$tmp_repo" || exit 99
REPO_ROOT_OVERRIDE="$tmp_repo"
validate_symlink_target "../.loa/.claude/scripts" ".claude/scripts"
echo "EXIT=\$?"
HARNESS_INVOKE

    run bash "$tmp_harness"
    rm -rf "$tmp_repo" "$tmp_harness"

    # Success: validator returns 0 AND no "Cannot resolve" warning fires.
    [[ "$output" == *"EXIT=0"* ]]
    ! [[ "$output" == *"Cannot resolve symlink target"* ]]
}

@test "#927: escape attempt via deep .. still rejected" {
    # Defense-in-depth: a malicious target like ../../../etc/passwd should
    # still be rejected even with the new source-aware resolution.
    local tmp_harness
    tmp_harness=$(mktemp)

    cat > "$tmp_harness" <<'HARNESS'
warn() { echo "WARN: $*" >&2; }
err()  { echo "ERR:  $*" >&2; }
get_repo_root() { echo "$REPO_ROOT_OVERRIDE"; }
HARNESS
    awk '/^validate_symlink_target\(\) \{/,/^\}/' "$MOUNT" >> "$tmp_harness"

    local tmp_repo
    tmp_repo=$(mktemp -d)
    mkdir -p "$tmp_repo/.claude"

    cat >> "$tmp_harness" <<HARNESS_INVOKE
cd "$tmp_repo" || exit 99
REPO_ROOT_OVERRIDE="$tmp_repo"
validate_symlink_target "../../../../../../etc/passwd" ".claude/scripts"
echo "EXIT=\$?"
HARNESS_INVOKE

    run bash "$tmp_harness"
    rm -rf "$tmp_repo" "$tmp_harness"

    # Reject (exit 1) AND emit "escapes repository bounds" error.
    [[ "$output" == *"EXIT=1"* ]]
    [[ "$output" == *"escapes repository bounds"* ]]
}
