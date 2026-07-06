#!/usr/bin/env bats
# =============================================================================
# #1177 (item G): update-loa.sh submodule-mode verification gates.
#
# update_submodule() previously (a) wrote .loa-version.json with no read-back
# (a silently-failed write or a marker frozen at a stale value survived a bump)
# and (b) discarded refresh_copy_set's exit code, so a repo whose copy set
# still drifted after "refresh" got a false "Update complete." with no signal.
#
# Per LEAD decision #8, the new logic is factored into two sourceable helpers
# (assert_version_marker, verify_copyset_gate) that are unit-tested directly —
# no full git-submodule fetch/checkout harness required. update-loa.sh only
# runs main() when executed directly, so sourcing it is side-effect free.
# =============================================================================

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    UPDATE="$REPO_ROOT/.claude/scripts/update-loa.sh"
    MOUNT="$REPO_ROOT/.claude/scripts/mount-submodule.sh"
    [[ -f "$UPDATE" ]] || skip "update-loa.sh not found"
    [[ -f "$MOUNT" ]] || skip "mount-submodule.sh not found"

    FIX="$BATS_TEST_TMPDIR/consumer"
    mkdir -p "$FIX/.loa/.claude/hooks" "$FIX/.claude/hooks"
    (cd "$FIX" && git init -q -b main)
    printf '#!/bin/sh\necho NEW\n' > "$FIX/.loa/.claude/hooks/probe.sh"
    printf '%s' '{"permissions":{"allow":["Write(grimoires/**)"],"deny":[]}}' \
        > "$FIX/.loa/.claude/settings.json"
}

# --- source-only side-effect guard -----------------------------------------

@test "#1177-G: sourcing update-loa.sh does not run main (source-only guard)" {
    run bash -c "source '$UPDATE'; echo READY"
    [ "$status" -eq 0 ]
    [[ "$output" == *"READY"* ]]
    # A full update run would have printed the banner / mode detection.
    [[ "$output" != *"Loa Framework Update"* ]]
    [[ "$output" != *"Detected mode"* ]]
}

# --- assert_version_marker (read-back assertion, AC-c) ----------------------

@test "#1177-G: assert_version_marker passes when framework_version reads back" {
    printf '%s' '{"framework_version":"v1.190.0"}' > "$FIX/.loa-version.json"
    run bash -c "cd '$FIX' && source '$UPDATE' && assert_version_marker 'v1.190.0'"
    [ "$status" -eq 0 ]
}

@test "#1177-G: assert_version_marker hard-fails on a mismatched read-back" {
    printf '%s' '{"framework_version":"v1.171.6"}' > "$FIX/.loa-version.json"
    run bash -c "cd '$FIX' && source '$UPDATE' && assert_version_marker 'v1.190.0'"
    [ "$status" -ne 0 ]
    [[ "$output" == *"write verification FAILED"* ]]
}

@test "#1177-G: assert_version_marker refuses an empty computed version" {
    printf '%s' '{"framework_version":"v1.190.0"}' > "$FIX/.loa-version.json"
    run bash -c "cd '$FIX' && source '$UPDATE' && assert_version_marker ''"
    [ "$status" -ne 0 ]
    [[ "$output" == *"empty"* ]]
}

# --- verify_copyset_gate (hard gate, AC-a / AC-d) ---------------------------

@test "#1177-G: verify_copyset_gate returns 0 when the copy set is in sync (idempotent)" {
    cp -R "$FIX/.loa/.claude/hooks" "$FIX/.claude/hooks.tmp" && rm -rf "$FIX/.claude/hooks" && mv "$FIX/.claude/hooks.tmp" "$FIX/.claude/hooks"
    cp "$FIX/.loa/.claude/settings.json" "$FIX/.claude/settings.json"
    run bash -c "cd '$FIX' && source '$UPDATE' && SUBMODULE_PATH='.loa' source '$MOUNT' --source-only && verify_copyset_gate"
    [ "$status" -eq 0 ]
    [[ "$output" != *"COPY-DRIFT"* ]]
}

@test "#1177-G: verify_copyset_gate hard-fails on residual drift before commit" {
    cp -R "$FIX/.loa/.claude/hooks/." "$FIX/.claude/hooks/"
    printf '%s' '{"permissions":{"allow":[],"deny":[]}}' > "$FIX/.claude/settings.json"
    run bash -c "cd '$FIX' && source '$UPDATE' && SUBMODULE_PATH='.loa' source '$MOUNT' --source-only && verify_copyset_gate"
    [ "$status" -ne 0 ]
    [[ "$output" == *"COPY-DRIFT"* ]]
    [[ "$output" == *"Copy-set verification FAILED"* ]]
}

@test "#1177-G: LOA_UPDATE_SKIP_COPYSET_VERIFY=1 skips the gate LOUDLY, naming the drift" {
    cp -R "$FIX/.loa/.claude/hooks/." "$FIX/.claude/hooks/"
    printf '%s' '{"permissions":{"allow":[],"deny":[]}}' > "$FIX/.claude/settings.json"
    run bash -c "cd '$FIX' && LOA_UPDATE_SKIP_COPYSET_VERIFY=1 bash -c \"source '$UPDATE' && SUBMODULE_PATH='.loa' source '$MOUNT' --source-only && verify_copyset_gate\""
    [ "$status" -eq 0 ]
    # The drift is still reported (named) above the skip line.
    [[ "$output" == *"COPY-DRIFT"* ]]
    [[ "$output" == *"SKIPPING"* ]]
}

@test "#1177-G: verify_copyset_gate is a no-op when refresh_copy_set is unavailable" {
    # Older submodule without the copy-set mechanism: gate must not hard-fail.
    run bash -c "cd '$FIX' && source '$UPDATE' && verify_copyset_gate"
    [ "$status" -eq 0 ]
}
