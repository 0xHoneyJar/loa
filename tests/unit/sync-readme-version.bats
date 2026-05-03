#!/usr/bin/env bats
# =============================================================================
# Unit tests for sync-readme-version.sh — issue #687
#
# sprint-bug-141 (T2+T3 hardening bundle). The script shipped with PR #686
# without bats coverage. Bridgebuilder iter-1 of #686 flagged this as MEDIUM
# non-blocking follow-up. Tests cover --check / --apply / idempotency /
# error modes / lock-step pattern updates.
# =============================================================================

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT_REAL="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    SCRIPT="$PROJECT_ROOT_REAL/.claude/scripts/sync-readme-version.sh"

    [[ -f "$SCRIPT" ]] || skip "sync-readme-version.sh not present"
    command -v jq >/dev/null 2>&1 || skip "jq not installed"

    # Create an isolated tmp repo with a fake .claude/scripts/ + README.md +
    # .loa-version.json. The script resolves REPO_ROOT relative to its own
    # path (../.. from .claude/scripts/), so we must mirror that layout in
    # the tmp tree so the script reads OUR fixtures, not the real repo.
    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_TMPDIR="$BATS_TMPDIR/sync-readme-test-$$"
    mkdir -p "$TEST_TMPDIR/.claude/scripts"
    cp "$SCRIPT" "$TEST_TMPDIR/.claude/scripts/"
    chmod +x "$TEST_TMPDIR/.claude/scripts/sync-readme-version.sh"

    export TEST_SCRIPT="$TEST_TMPDIR/.claude/scripts/sync-readme-version.sh"
    export TEST_README="$TEST_TMPDIR/README.md"
    export TEST_VERSION_FILE="$TEST_TMPDIR/.loa-version.json"
}

teardown() {
    cd /
    [[ -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
}

# Helper: write a baseline in-sync README + version file at a given version.
_write_synced() {
    local version="$1"
    cat > "$TEST_README" <<EOF
# Loa Framework

A multi-agent development framework.

Version: $version

[![Version](https://img.shields.io/badge/version-$version-blue.svg)](CHANGELOG.md)

## Overview

Test fixture content.
EOF
    jq -n --arg v "$version" '{
        framework_version: $v,
        schema_version: 2,
        last_sync: "2026-05-03T00:00:00Z"
    }' > "$TEST_VERSION_FILE"
}

# -----------------------------------------------------------------------------
# Case 1: --check on in-sync state → exit 0
# -----------------------------------------------------------------------------
@test "sync-readme: --check on in-sync state exits 0" {
    _write_synced "1.110.1"

    run "$TEST_SCRIPT" --check
    [[ "$status" -eq 0 ]] || {
        echo "Expected exit 0; got $status"
        echo "output: $output"
        return 1
    }
    echo "$output" | grep -qE 'OK|in sync' || {
        echo "Expected 'OK' / 'in sync' message; got: $output"
        return 1
    }
}

# -----------------------------------------------------------------------------
# Case 2: --check on drifted state → exit 1 with structured stderr
# -----------------------------------------------------------------------------
@test "sync-readme: --check on drifted state exits 1 with diagnostic" {
    _write_synced "1.0.0"
    # Bump version file but leave README behind.
    jq '.framework_version = "2.0.0"' "$TEST_VERSION_FILE" > "$TEST_VERSION_FILE.tmp"
    mv "$TEST_VERSION_FILE.tmp" "$TEST_VERSION_FILE"

    run "$TEST_SCRIPT" --check
    [[ "$status" -eq 1 ]] || {
        echo "Expected exit 1 (drift detected); got $status"
        echo "output: $output"
        return 1
    }
    # Stderr should explain the drift and recommend --apply.
    echo "$output" | grep -q 'DRIFT' || {
        echo "Expected DRIFT marker; got: $output"
        return 1
    }
    echo "$output" | grep -qE '\-\-apply' || {
        echo "Expected --apply remediation hint; got: $output"
        return 1
    }
}

# -----------------------------------------------------------------------------
# Case 3: --apply on drifted state → rewrites README correctly
# -----------------------------------------------------------------------------
@test "sync-readme: --apply on drifted state rewrites README" {
    _write_synced "1.0.0"
    jq '.framework_version = "2.5.3"' "$TEST_VERSION_FILE" > "$TEST_VERSION_FILE.tmp"
    mv "$TEST_VERSION_FILE.tmp" "$TEST_VERSION_FILE"

    run "$TEST_SCRIPT" --apply
    [[ "$status" -eq 0 ]] || {
        echo "Expected exit 0; got $status, output: $output"
        return 1
    }

    # Both patterns must update.
    grep -qF 'Version: 2.5.3' "$TEST_README" || {
        echo "HTML comment 'Version: 2.5.3' not in README"
        cat "$TEST_README"
        return 1
    }
    grep -qF 'version-2.5.3-blue.svg' "$TEST_README" || {
        echo "Badge 'version-2.5.3-blue.svg' not in README"
        cat "$TEST_README"
        return 1
    }
    # Old version should be gone.
    if grep -qF '1.0.0' "$TEST_README"; then
        echo "Old version 1.0.0 still in README"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Case 4: --apply is idempotent
# -----------------------------------------------------------------------------
@test "sync-readme: --apply is idempotent (run twice, no change)" {
    _write_synced "1.0.0"
    jq '.framework_version = "2.0.0"' "$TEST_VERSION_FILE" > "$TEST_VERSION_FILE.tmp"
    mv "$TEST_VERSION_FILE.tmp" "$TEST_VERSION_FILE"

    "$TEST_SCRIPT" --apply >/dev/null
    local first_md5
    first_md5=$(md5sum "$TEST_README" | awk '{print $1}')

    run "$TEST_SCRIPT" --apply
    [[ "$status" -eq 0 ]] || {
        echo "Second --apply failed: $output"
        return 1
    }
    # Idempotent run reports either "OK: in sync" (early exit before sed)
    # OR "NO-OP" (sed produced byte-identical output).
    echo "$output" | grep -qE 'NO-OP|OK.*in sync|already' || {
        echo "Expected idempotent signal; got: $output"
        return 1
    }

    local second_md5
    second_md5=$(md5sum "$TEST_README" | awk '{print $1}')
    [[ "$first_md5" == "$second_md5" ]] || {
        echo "README mutated on idempotent run (md5 differs)"
        return 1
    }
}

# -----------------------------------------------------------------------------
# Case 5: missing .loa-version.json → exit 2
# -----------------------------------------------------------------------------
@test "sync-readme: missing .loa-version.json exits 2" {
    _write_synced "1.0.0"
    rm -f "$TEST_VERSION_FILE"

    run "$TEST_SCRIPT" --check
    [[ "$status" -eq 2 ]] || {
        echo "Expected exit 2 for missing version file; got $status"
        return 1
    }
    echo "$output" | grep -qE 'ERROR|not found' || {
        echo "Expected error message; got: $output"
        return 1
    }
}

# -----------------------------------------------------------------------------
# Case 6: malformed framework_version (not semver) → exit 2
# -----------------------------------------------------------------------------
@test "sync-readme: non-semver framework_version exits 2" {
    _write_synced "1.0.0"
    jq '.framework_version = "not-a-version"' "$TEST_VERSION_FILE" > "$TEST_VERSION_FILE.tmp"
    mv "$TEST_VERSION_FILE.tmp" "$TEST_VERSION_FILE"

    run "$TEST_SCRIPT" --check
    [[ "$status" -eq 2 ]] || {
        echo "Expected exit 2 for malformed version; got $status"
        return 1
    }
    echo "$output" | grep -qE 'semver|not.*X\.Y\.Z' || {
        echo "Expected semver validation error; got: $output"
        return 1
    }
}

# -----------------------------------------------------------------------------
# Case 7: lock-step update — both HTML comment AND badge update together
# -----------------------------------------------------------------------------
@test "sync-readme: --apply updates both patterns in lock-step (no partial drift)" {
    # Start with a README where ONLY the badge is wrong (HTML comment correct).
    cat > "$TEST_README" <<'EOF'
# Loa
Version: 2.0.0

[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](CHANGELOG.md)
EOF
    jq -n '{framework_version: "2.0.0", schema_version: 2}' > "$TEST_VERSION_FILE"

    run "$TEST_SCRIPT" --apply
    [[ "$status" -eq 0 ]]

    grep -qF 'Version: 2.0.0' "$TEST_README"
    grep -qF 'version-2.0.0-blue.svg' "$TEST_README"
    # Pre-update mismatched badge must be gone.
    if grep -qF 'version-1.0.0-blue.svg' "$TEST_README"; then
        echo "Stale badge still present after lock-step update"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Case 8: --help / no args / unknown mode → exit 2 with usage
# -----------------------------------------------------------------------------
@test "sync-readme: --help exits 2 with usage banner" {
    run "$TEST_SCRIPT" --help
    [[ "$status" -eq 2 ]]
    echo "$output" | grep -qE 'Usage:|--check|--apply'
}

@test "sync-readme: unknown mode exits 2" {
    run "$TEST_SCRIPT" --bogus
    [[ "$status" -eq 2 ]]
    echo "$output" | grep -q 'Unknown mode'
}
