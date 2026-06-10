#!/usr/bin/env bats
# =============================================================================
# Issue #842 — Hooks fail with "No such file or directory" when .claude/
# uses symlinks from /mount
# =============================================================================
# Pre-fix, mount-submodule.sh symlinked .claude/hooks -> ../.loa/.claude/hooks
# (relative). Claude Code's hook executor on macOS cannot follow relative
# symlinks across `..` from a subprocess context — every hook failed silently
# with "No such file or directory". Per @juniperbevensee report, this
# disabled ALL safety hooks, audit logging, compaction recovery, run-mode
# stop guard, etc.
#
# Fix: hooks/ + settings.json are now COPIED into the consumer tree instead
# of symlinked. Tradeoff documented in manifest: operators must re-run
# mount-submodule on submodule update to pick up framework changes in
# these paths.
# =============================================================================

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    MANIFEST="$REPO_ROOT/.claude/scripts/lib/symlink-manifest.sh"
    MOUNT="$REPO_ROOT/.claude/scripts/mount-submodule.sh"
    [[ -f "$MANIFEST" ]] || skip "symlink-manifest.sh not found"
    [[ -f "$MOUNT" ]] || skip "mount-submodule.sh not found"
}

@test "#842: .claude/hooks is NOT in MANIFEST_DIR_SYMLINKS" {
    # Regression guard. If a future PR re-adds hooks to the symlink set,
    # this fails until they justify it. Scope the grep to the array body
    # so the explanatory comment block isn't matched.
    ! awk '/MANIFEST_DIR_SYMLINKS=\(/,/^  \)/' "$MANIFEST" \
        | grep -qE '"\.claude/hooks:' \
        || {
            echo "REGRESSION: .claude/hooks was re-added to MANIFEST_DIR_SYMLINKS" >&2
            echo "Issue #842: hooks must be COPIED, not symlinked. See lib/symlink-manifest.sh comment." >&2
            return 1
        }
}

@test "#842: .claude/settings.json is NOT in MANIFEST_FILE_SYMLINKS" {
    # Same scope-to-array-body discipline as above.
    ! awk '/MANIFEST_FILE_SYMLINKS=\(/,/^  \)/' "$MANIFEST" \
        | grep -qE '"\.claude/settings\.json:' \
        || {
            echo "REGRESSION: .claude/settings.json was re-added to MANIFEST_FILE_SYMLINKS" >&2
            return 1
        }
}

@test "#842: .claude/hooks IS in MANIFEST_COPY_DIRS" {
    grep -qE '"\.claude/hooks:' "$MANIFEST" \
        || {
            echo "REGRESSION: .claude/hooks missing from MANIFEST_COPY_DIRS" >&2
            echo "Issue #842 fix requires hooks to be copied. See lib/symlink-manifest.sh." >&2
            return 1
        }

    # Verify it's specifically inside MANIFEST_COPY_DIRS, not some other array
    awk '/MANIFEST_COPY_DIRS=\(/,/\)/' "$MANIFEST" \
        | grep -qE '"\.claude/hooks:' \
        || {
            echo "REGRESSION: .claude/hooks is referenced but not in MANIFEST_COPY_DIRS array" >&2
            return 1
        }
}

@test "#842: .claude/settings.json IS in MANIFEST_COPY_FILES" {
    awk '/MANIFEST_COPY_FILES=\(/,/\)/' "$MANIFEST" \
        | grep -qE '"\.claude/settings\.json:' \
        || {
            echo "REGRESSION: .claude/settings.json missing from MANIFEST_COPY_FILES" >&2
            return 1
        }
}

@test "#842: mount-submodule has a copy phase that consumes MANIFEST_COPY_*" {
    # The copy logic in mount-submodule.sh must reference both arrays.
    grep -qE 'MANIFEST_COPY_DIRS' "$MOUNT" \
        || {
            echo "REGRESSION: mount-submodule no longer iterates MANIFEST_COPY_DIRS" >&2
            return 1
        }
    grep -qE 'MANIFEST_COPY_FILES' "$MOUNT" \
        || {
            echo "REGRESSION: mount-submodule no longer iterates MANIFEST_COPY_FILES" >&2
            return 1
        }
    # The copy phase must use `cp -R` for directories (preserves perms,
    # follows symlinks within source tree — required because the framework
    # may itself contain inner symlinks we want copied as files).
    grep -qE 'cp -R "\$(abs_)?target"' "$MOUNT" \
        || {
            echo "REGRESSION: copy phase doesn't use cp -R for dirs" >&2
            return 1
        }
}

@test "#842: copy phase replaces stale symlinks at the destination" {
    # If a user has already mounted (with old symlink behavior) and re-runs
    # mount, the existing `.claude/hooks` symlink must be removed before cp.
    # #968 extracted the copy phase into _refresh_copy_entry, which removes
    # the stale dest ("$abs_dest") before cp -R. Behavior is ALSO pinned
    # functionally by bug-968-reconcile-copy-refresh.bats test 2.
    awk '/_refresh_copy_entry\(\)/,/^}/' "$MOUNT" \
        | grep -qE 'rm -rf "\$abs_dest"' \
        || {
            echo "REGRESSION: copy phase doesn't remove stale symlinks/dirs before copy" >&2
            echo "Without this, re-running mount on a previously-mounted tree leaves the old symlink intact." >&2
            return 1
        }
}
