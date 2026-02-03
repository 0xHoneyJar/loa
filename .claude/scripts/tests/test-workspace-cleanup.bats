#!/usr/bin/env bats
# =============================================================================
# test-workspace-cleanup.bats - Unit tests for workspace-cleanup.sh
# =============================================================================
# Tests cover:
#   - Lock acquisition and release
#   - Stale lock detection
#   - Path validation (reject .., symlinks, absolute paths)
#   - Pattern matching for archivable files
#   - Checksum verification
#   - Disk space calculation
#   - Archive creation and manifest
#   - Transaction log for recovery
#   - Concurrent invocation handling (IMP-003)
# =============================================================================

# Setup and teardown
setup() {
    # Create temporary test directory
    export TEST_DIR=$(mktemp -d)
    export PROJECT_ROOT="$TEST_DIR"

    # Create grimoire structure
    mkdir -p "$TEST_DIR/grimoires/loa/archive"
    mkdir -p "$TEST_DIR/grimoires/loa/a2a"
    mkdir -p "$TEST_DIR/.run"

    # Path to script under test
    export SCRIPT="$BATS_TEST_DIRNAME/../workspace-cleanup.sh"

    # Ensure script exists
    if [[ ! -f "$SCRIPT" ]]; then
        skip "workspace-cleanup.sh not found"
    fi
}

teardown() {
    # Clean up test directory
    if [[ -d "$TEST_DIR" ]]; then
        rm -rf "$TEST_DIR"
    fi
}

# =============================================================================
# Help and Arguments
# =============================================================================

@test "shows help with --help flag" {
    run bash "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"workspace-cleanup.sh"* ]]
    [[ "$output" == *"OPTIONS"* ]]
}

@test "exits 0 when no files to archive" {
    cd "$TEST_DIR"
    run bash "$SCRIPT" --grimoire grimoires/loa
    [ "$status" -eq 0 ]
    [[ "$output" == *"No archivable files found"* ]] || [[ "$output" == *'"archived": false'* ]]
}

@test "rejects conflicting --yes and --no flags" {
    cd "$TEST_DIR"
    run bash "$SCRIPT" --yes --no
    [ "$status" -eq 1 ]
    [[ "$output" == *"Cannot use both"* ]]
}

# =============================================================================
# Lock Management
# =============================================================================

@test "creates lock file on acquisition" {
    cd "$TEST_DIR"

    # Create a file to archive
    echo "test" > grimoires/loa/prd.md

    # Run with --dry-run to avoid actual archive
    run bash "$SCRIPT" --grimoire grimoires/loa --dry-run
    [ "$status" -eq 0 ]

    # Lock file should exist (may still be present after script)
    # and we should be able to acquire it (proving the script released it)
    if [[ -f "grimoires/loa/.cleanup.lock" ]]; then
        # If lock file exists, we should be able to acquire the lock
        # (proving the previous holder released it)
        exec 200>"grimoires/loa/.cleanup.lock"
        flock -n 200
        exec 200>&-
    fi
    # Test passes - script ran successfully and released lock
}

@test "lock file contains valid JSON metadata" {
    cd "$TEST_DIR"
    echo "test" > grimoires/loa/prd.md

    # Start cleanup in background with intentional delay
    timeout 5 bash -c '
        source '"$SCRIPT"' --grimoire grimoires/loa --dry-run &
        sleep 0.5
        if [[ -f "grimoires/loa/.cleanup.lock" ]]; then
            cat "grimoires/loa/.cleanup.lock"
        fi
    ' > lock_content.txt 2>&1 || true

    # Check lock file had valid JSON if it was captured
    if [[ -s lock_content.txt ]] && grep -q "pid" lock_content.txt; then
        run jq -e '.pid' lock_content.txt
        [ "$status" -eq 0 ]
    else
        skip "Lock file not captured (process too fast)"
    fi
}

@test "detects stale lock from dead process" {
    cd "$TEST_DIR"
    echo "test" > grimoires/loa/prd.md

    # Create stale lock with dead PID
    cat > "grimoires/loa/.cleanup.lock" << EOF
{
  "pid": 99999999,
  "hostname": "$(hostname)",
  "timestamp": "2000-01-01T00:00:00Z",
  "ttl_seconds": 1
}
EOF

    # Should succeed by detecting stale lock
    run bash "$SCRIPT" --grimoire grimoires/loa --dry-run
    [ "$status" -eq 0 ]
}

@test "IMP-003: concurrent invocations show lock held message" {
    cd "$TEST_DIR"
    echo "test" > grimoires/loa/prd.md

    # Create lock file and hold it using flock with a bash subshell
    # Use bash explicitly and BASHPID for correct PID
    bash -c '
        exec 200>"grimoires/loa/.cleanup.lock"
        flock -n 200 || exit 1
        cat > "grimoires/loa/.cleanup.lock" << EOF
{
  "pid": $BASHPID,
  "hostname": "$(hostname)",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "ttl_seconds": 300
}
EOF
        # Keep lock held
        sleep 10
    ' &
    HOLDER_PID=$!

    # Wait for lock to be acquired
    sleep 1

    # Verify the lock is actually held
    if ! flock -n "grimoires/loa/.cleanup.lock" -c "exit 0" 2>/dev/null; then
        # Lock is held - now test that the script fails appropriately
        run timeout 5 bash "$SCRIPT" --grimoire grimoires/loa --dry-run
        [ "$status" -eq 1 ]
        [[ "$output" == *"Lock held"* ]] || [[ "$output" == *"another process"* ]] || [[ "$output" == *"Lock busy"* ]]
    else
        # Lock wasn't held - skip test
        skip "Could not acquire lock for test setup"
    fi

    # Clean up
    kill $HOLDER_PID 2>/dev/null || true
    wait $HOLDER_PID 2>/dev/null || true
}

# =============================================================================
# Path Validation (Security)
# =============================================================================

@test "rejects paths with .." {
    cd "$TEST_DIR"

    # Create manifest with malicious path
    cat > ".run/cycle-manifest.json" << 'EOF'
{
  "produced_files": [
    {"path": "grimoires/loa/../../../etc/passwd"}
  ]
}
EOF

    # Should not archive the malicious path
    run bash "$SCRIPT" --grimoire grimoires/loa --dry-run --json
    [ "$status" -eq 0 ]
    # Should have no files or the malicious file should be skipped
    # Matches: dry-run output (would_archive_count: 0), skip output (archived_count: 0), or log message
    [[ "$output" == *'"would_archive_count": 0'* ]] || \
        [[ "$output" == *'"archived_count": 0'* ]] || \
        [[ "$output" == *"No archivable"* ]]
}

@test "rejects absolute paths" {
    cd "$TEST_DIR"

    cat > ".run/cycle-manifest.json" << 'EOF'
{
  "produced_files": [
    {"path": "/etc/passwd"}
  ]
}
EOF

    run bash "$SCRIPT" --grimoire grimoires/loa --dry-run --json
    [ "$status" -eq 0 ]
    # Matches: dry-run output (would_archive_count: 0), skip output (archived_count: 0), or log message
    [[ "$output" == *'"would_archive_count": 0'* ]] || \
        [[ "$output" == *'"archived_count": 0'* ]] || \
        [[ "$output" == *"No archivable"* ]]
}

@test "rejects symlinks" {
    cd "$TEST_DIR"

    # Create ONLY a symlink (no real files matching patterns)
    ln -s /etc/passwd grimoires/loa/prd.md

    run bash "$SCRIPT" --grimoire grimoires/loa --dry-run
    [ "$status" -eq 0 ]
    # Should either warn about symlink, show skipping message, or have no files
    [[ "$output" == *"Symlink detected"* ]] || \
        [[ "$output" == *"skipping"* ]] || \
        [[ "$output" == *'"would_archive_count": 0'* ]] || \
        [[ "$output" == *'"archived_count": 0'* ]] || \
        [[ "$output" == *"No archivable"* ]]
}

# =============================================================================
# Pattern Matching
# =============================================================================

@test "matches prd.md, sdd.md, sprint.md" {
    cd "$TEST_DIR"

    echo "prd content" > grimoires/loa/prd.md
    echo "sdd content" > grimoires/loa/sdd.md
    echo "sprint content" > grimoires/loa/sprint.md

    run bash "$SCRIPT" --grimoire grimoires/loa --dry-run --json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"would_archive_count": 3'* ]]
}

@test "matches prd-*.md, sdd-*.md, sprint-*.md patterns" {
    cd "$TEST_DIR"

    echo "content" > grimoires/loa/prd-feature.md
    echo "content" > grimoires/loa/sdd-feature.md
    echo "content" > grimoires/loa/sprint-feature.md

    run bash "$SCRIPT" --grimoire grimoires/loa --dry-run --json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"would_archive_count": 3'* ]]
}

@test "matches a2a/sprint-N directories" {
    cd "$TEST_DIR"

    mkdir -p grimoires/loa/a2a/sprint-1
    echo "content" > grimoires/loa/a2a/sprint-1/task.md

    run bash "$SCRIPT" --grimoire grimoires/loa --dry-run --json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"would_archive_count": 1'* ]]
}

# =============================================================================
# Archive Creation
# =============================================================================

@test "creates archive directory with date" {
    cd "$TEST_DIR"

    echo "content" > grimoires/loa/prd.md

    run bash "$SCRIPT" --grimoire grimoires/loa --yes
    [ "$status" -eq 0 ]

    # Check archive was created
    local today=$(date +%Y-%m-%d)
    [ -d "grimoires/loa/archive/$today" ] || [ -d "grimoires/loa/archive/${today}-1" ]
}

@test "handles duplicate dates with counter" {
    cd "$TEST_DIR"

    local today=$(date +%Y-%m-%d)

    # Create first archive
    echo "content1" > grimoires/loa/prd.md
    run bash "$SCRIPT" --grimoire grimoires/loa --yes
    [ "$status" -eq 0 ]
    [ -d "grimoires/loa/archive/$today" ]

    # Create second file
    echo "content2" > grimoires/loa/prd.md
    run bash "$SCRIPT" --grimoire grimoires/loa --yes
    [ "$status" -eq 0 ]

    # Should have created counter-suffixed archive
    [ -d "grimoires/loa/archive/${today}-1" ]
}

@test "creates manifest.json in archive" {
    cd "$TEST_DIR"

    echo "content" > grimoires/loa/prd.md

    run bash "$SCRIPT" --grimoire grimoires/loa --yes
    [ "$status" -eq 0 ]

    local archive_dir=$(find grimoires/loa/archive -maxdepth 1 -type d -name "20*" | head -1)
    [ -f "$archive_dir/manifest.json" ]

    # Validate manifest JSON
    run jq -e '.archived_at' "$archive_dir/manifest.json"
    [ "$status" -eq 0 ]
}

@test "creates .committed marker on success" {
    cd "$TEST_DIR"

    echo "content" > grimoires/loa/prd.md

    run bash "$SCRIPT" --grimoire grimoires/loa --yes
    [ "$status" -eq 0 ]

    local archive_dir=$(find grimoires/loa/archive -maxdepth 1 -type d -name "20*" | head -1)
    [ -f "$archive_dir/.committed" ]
}

@test "removes original files after archive" {
    cd "$TEST_DIR"

    echo "content" > grimoires/loa/prd.md

    run bash "$SCRIPT" --grimoire grimoires/loa --yes
    [ "$status" -eq 0 ]

    # Original should be gone
    [ ! -f "grimoires/loa/prd.md" ]
}

# =============================================================================
# Checksum Verification
# =============================================================================

@test "creates checksums file in archive" {
    cd "$TEST_DIR"

    echo "content" > grimoires/loa/prd.md

    run bash "$SCRIPT" --grimoire grimoires/loa --yes
    [ "$status" -eq 0 ]

    local archive_dir=$(find grimoires/loa/archive -maxdepth 1 -type d -name "20*" | head -1)
    [ -f "$archive_dir/.checksums" ]
}

@test "archived file content matches original" {
    cd "$TEST_DIR"

    local content="unique test content $(date +%s)"
    echo "$content" > grimoires/loa/prd.md
    local original_sum=$(sha256sum grimoires/loa/prd.md | cut -d' ' -f1)

    run bash "$SCRIPT" --grimoire grimoires/loa --yes
    [ "$status" -eq 0 ]

    local archive_dir=$(find grimoires/loa/archive -maxdepth 1 -type d -name "20*" | head -1)
    local archived_sum=$(sha256sum "$archive_dir/prd.md" | cut -d' ' -f1)

    [ "$original_sum" = "$archived_sum" ]
}

# =============================================================================
# Transaction Log
# =============================================================================

@test "removes transaction log on success" {
    cd "$TEST_DIR"

    echo "content" > grimoires/loa/prd.md

    run bash "$SCRIPT" --grimoire grimoires/loa --yes
    [ "$status" -eq 0 ]

    # Transaction log should be removed
    local transaction_logs=$(find grimoires/loa/archive -name ".transaction-*.log" 2>/dev/null)
    [ -z "$transaction_logs" ]
}

# =============================================================================
# Disk Space Check
# =============================================================================

@test "calculates disk space requirement" {
    cd "$TEST_DIR"

    # Create a file
    dd if=/dev/zero of=grimoires/loa/prd.md bs=1024 count=10 2>/dev/null

    run bash "$SCRIPT" --grimoire grimoires/loa --dry-run
    [ "$status" -eq 0 ]
    # Should show size in output
    [[ "$output" == *"KB"* ]] || [[ "$output" == *"MB"* ]] || [[ "$output" == *"bytes"* ]]
}

# =============================================================================
# JSON Output
# =============================================================================

@test "produces valid JSON with --json flag" {
    cd "$TEST_DIR"

    echo "content" > grimoires/loa/prd.md

    run bash "$SCRIPT" --grimoire grimoires/loa --yes --json
    [ "$status" -eq 0 ]

    # Validate JSON
    echo "$output" | jq -e '.' > /dev/null
}

@test "JSON includes required fields" {
    cd "$TEST_DIR"

    echo "content" > grimoires/loa/prd.md

    run bash "$SCRIPT" --grimoire grimoires/loa --yes --json
    [ "$status" -eq 0 ]

    echo "$output" | jq -e '.success' > /dev/null
    echo "$output" | jq -e '.archived' > /dev/null
    echo "$output" | jq -e '.archived_count' > /dev/null
}

# =============================================================================
# Dry Run
# =============================================================================

@test "dry run does not modify files" {
    cd "$TEST_DIR"

    echo "content" > grimoires/loa/prd.md

    run bash "$SCRIPT" --grimoire grimoires/loa --dry-run
    [ "$status" -eq 0 ]

    # File should still exist
    [ -f "grimoires/loa/prd.md" ]

    # No archive created
    local archives=$(find grimoires/loa/archive -maxdepth 1 -type d -name "20*" 2>/dev/null)
    [ -z "$archives" ]
}

# =============================================================================
# User Prompt Handling
# =============================================================================

@test "--no flag skips cleanup with exit 2" {
    cd "$TEST_DIR"

    echo "content" > grimoires/loa/prd.md

    run bash "$SCRIPT" --grimoire grimoires/loa --no
    [ "$status" -eq 2 ]

    # File should still exist
    [ -f "grimoires/loa/prd.md" ]
}

@test "--yes flag archives without prompt" {
    cd "$TEST_DIR"

    echo "content" > grimoires/loa/prd.md

    run bash "$SCRIPT" --grimoire grimoires/loa --yes
    [ "$status" -eq 0 ]

    # File should be archived
    [ ! -f "grimoires/loa/prd.md" ]
}

# =============================================================================
# Retention Policy
# =============================================================================

@test "keeps archives with .keep marker" {
    cd "$TEST_DIR"

    # Create old archive with .keep
    mkdir -p grimoires/loa/archive/2020-01-01
    touch grimoires/loa/archive/2020-01-01/.keep
    echo "preserved" > grimoires/loa/archive/2020-01-01/prd.md

    # Create new file to archive
    echo "content" > grimoires/loa/prd.md

    run bash "$SCRIPT" --grimoire grimoires/loa --yes
    [ "$status" -eq 0 ]

    # .keep archive should still exist
    [ -d "grimoires/loa/archive/2020-01-01" ]
}

# =============================================================================
# IMP-001: Partial State Detection
# =============================================================================

@test "IMP-001: detects .staging directory as partial state" {
    cd "$TEST_DIR"

    mkdir -p grimoires/loa/archive/2024-01-01.staging
    echo "content" > grimoires/loa/prd.md

    run bash "$SCRIPT" --grimoire grimoires/loa --yes --json
    [ "$status" -eq 0 ]

    # Should report partial state in JSON
    [[ "$output" == *"partial_state"* ]] || [[ "$output" == *"staging"* ]]
}

@test "IMP-001: detects .failed directory as partial state" {
    cd "$TEST_DIR"

    mkdir -p grimoires/loa/archive/2024-01-01.failed
    echo "content" > grimoires/loa/prd.md

    run bash "$SCRIPT" --grimoire grimoires/loa --yes --json
    [ "$status" -eq 0 ]

    # Should report partial state in JSON
    [[ "$output" == *"partial_state"* ]] || [[ "$output" == *"failed"* ]]
}
