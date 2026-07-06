#!/usr/bin/env bats
# =============================================================================
# #1177 (item G): `mount-submodule.sh --check-symlinks` set -e early-exit bug.
#
# check_symlinks_subcommand() called `verify_and_reconcile_symlinks "false"`
# as a BARE statement under `set -euo pipefail`. When that returned 1 (any
# dangling / missing core symlink), set -e killed the whole script on the
# spot — so `refresh_copy_set "false"` (the #842 copy-set drift check) never
# ran and --check-symlinks silently omitted ALL COPY-* diagnostics. Reproduced
# live on hosaka/carrefour.
#
# Fix: guard the call with `|| result=1`, mirroring the --reconcile path. This
# test drives the REAL script end-to-end (not sourced) because the bug only
# manifests through top-level set -e execution.
# =============================================================================

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    MOUNT="$REPO_ROOT/.claude/scripts/mount-submodule.sh"
    [[ -f "$MOUNT" ]] || skip "mount-submodule.sh not found"

    # Fixture consumer repo: a fake .loa payload, a drifted copy-set entry,
    # and ZERO core symlinks present (so verify_and_reconcile_symlinks returns
    # 1 in check mode — the precondition that used to trip set -e).
    FIX="$BATS_TEST_TMPDIR/consumer"
    mkdir -p "$FIX/.loa/.claude/hooks" "$FIX/.claude/hooks"
    (cd "$FIX" && git init -q -b main)

    # Copy-set source in the submodule.
    printf '#!/bin/sh\necho NEW\n' > "$FIX/.loa/.claude/hooks/probe.sh"
    printf '%s' '{"permissions":{"allow":["Write(grimoires/**)"],"deny":[]}}' \
        > "$FIX/.loa/.claude/settings.json"

    # On-disk copies: hooks in sync, settings.json DRIFTED (regular file).
    cp "$FIX/.loa/.claude/hooks/probe.sh" "$FIX/.claude/hooks/probe.sh"
    printf '%s' '{"permissions":{"allow":[],"deny":[]}}' > "$FIX/.claude/settings.json"
}

@test "#1177-G: --check-symlinks reaches the copy-set check even when a symlink is missing" {
    run bash -c "cd '$FIX' && '$MOUNT' --check-symlinks"
    # Precondition: at least one core symlink is missing → verify returns 1.
    [[ "$output" == *"MISSING:"* ]]
    # The load-bearing assertion: the copy-set section STILL ran and reported
    # the drift. Pre-fix, set -e killed the script before this line printed.
    [[ "$output" == *"COPY-DRIFT"* ]]
    # And the overall exit code is non-zero (issues detected).
    [ "$status" -ne 0 ]
}

@test "#1177-G: --check-symlinks does not silently die before the copy-set summary" {
    run bash -c "cd '$FIX' && '$MOUNT' --check-symlinks"
    # The copy-set step banner proves the section executed.
    [[ "$output" == *"Copy set (#842)"* ]]
}

# =============================================================================
# #1177 (item G, LEAD decision #3): --check-symlinks must also detect a stale
# .loa-version.json marker — compare .framework_version against the submodule's
# `git describe --tags` (fallback short HEAD). This is the fleet class where an
# operator bumps the .loa gitlink by hand ("pointer-only") without running
# update-loa.sh, leaving the marker stale by up to ~85 releases while the pin
# advances. WARN-only (advisory) — does not flip the exit code.
# =============================================================================

# Helper: turn $VER/.loa into a real git repo with a lightweight tag so
# `git describe --tags` resolves, and seed .loa-version.json at the root.
_seed_versioned_submodule() {
    local marker_ver="$1"
    VER="$BATS_TEST_TMPDIR/versioned"
    mkdir -p "$VER/.loa"
    (cd "$VER" && git init -q -b main)
    (cd "$VER/.loa" && git init -q -b main \
        && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init \
        && git -c user.email=t@t -c user.name=t tag -a v9.9.9 -m v9.9.9)
    printf '{"framework_version":"%s","installation_mode":"submodule"}\n' \
        "$marker_ver" > "$VER/.loa-version.json"
}

@test "#1177-G: marker check WARNs when framework_version lags the submodule pin" {
    _seed_versioned_submodule "v0.0.1"
    run bash -c "cd '$VER' && SUBMODULE_PATH='.loa' source '$MOUNT' --source-only && check_version_marker_staleness"
    [ "$status" -eq 0 ]
    [[ "$output" == *"MARKER-STALE"* ]]
    [[ "$output" == *"v0.0.1"* ]]
    [[ "$output" == *"v9.9.9"* ]]
}

@test "#1177-G: marker check is quiet (fresh) when framework_version matches the pin" {
    _seed_versioned_submodule "v9.9.9"
    run bash -c "cd '$VER' && SUBMODULE_PATH='.loa' source '$MOUNT' --source-only && check_version_marker_staleness"
    [ "$status" -eq 0 ]
    [[ "$output" == *"marker fresh"* ]]
    [[ "$output" != *"MARKER-STALE"* ]]
}

@test "#1177-G: marker check no-ops (exit 0, silent) when .loa-version.json is absent" {
    # The setE $FIX fixture has no .loa-version.json and a non-git .loa payload.
    run bash -c "cd '$FIX' && SUBMODULE_PATH='.loa' source '$MOUNT' --source-only && check_version_marker_staleness"
    [ "$status" -eq 0 ]
    [[ "$output" != *"MARKER-STALE"* ]]
    [[ "$output" != *"marker fresh"* ]]
}

@test "#1177-G: --check-symlinks surfaces MARKER-STALE end-to-end for a lagging marker" {
    _seed_versioned_submodule "v0.0.1"
    # Provide an in-sync copy set so the run isn't dominated by COPY-* noise.
    mkdir -p "$VER/.loa/.claude/hooks" "$VER/.claude/hooks"
    printf '#!/bin/sh\necho X\n' > "$VER/.loa/.claude/hooks/probe.sh"
    cp "$VER/.loa/.claude/hooks/probe.sh" "$VER/.claude/hooks/probe.sh"
    printf '%s' '{"permissions":{"allow":[],"deny":[]}}' > "$VER/.loa/.claude/settings.json"
    cp "$VER/.loa/.claude/settings.json" "$VER/.claude/settings.json"
    run bash -c "cd '$VER' && '$MOUNT' --check-symlinks"
    [[ "$output" == *"MARKER-STALE"* ]]
}
