#!/usr/bin/env bats
# Unit tests for bridge-github-trail.sh
# Sprint 3: Integration — comment format, subcommands, graceful degradation

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    SCRIPT="$PROJECT_ROOT/.claude/scripts/bridge-github-trail.sh"

    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_TMPDIR="$BATS_TMPDIR/github-trail-test-$$"
    mkdir -p "$TEST_TMPDIR/.claude/scripts" "$TEST_TMPDIR/.run"

    # Copy bootstrap for sourcing
    cp "$PROJECT_ROOT/.claude/scripts/bootstrap.sh" "$TEST_TMPDIR/.claude/scripts/"
    if [[ -f "$PROJECT_ROOT/.claude/scripts/path-lib.sh" ]]; then
        cp "$PROJECT_ROOT/.claude/scripts/path-lib.sh" "$TEST_TMPDIR/.claude/scripts/"
    fi

    # Initialize git repo for bootstrap
    cd "$TEST_TMPDIR"
    git init -q
    git add -A 2>/dev/null || true
    git commit -q -m "init" --allow-empty

    export PROJECT_ROOT="$TEST_TMPDIR"
}

teardown() {
    cd /
    if [[ -d "$TEST_TMPDIR" ]]; then
        rm -rf "$TEST_TMPDIR"
    fi
}

# =============================================================================
# Basic Validation
# =============================================================================

@test "github-trail: script exists and is executable" {
    [ -x "$SCRIPT" ]
}

@test "github-trail: --help shows usage" {
    run "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "github-trail: no arguments returns exit 2" {
    run "$SCRIPT"
    [ "$status" -eq 2 ]
}

@test "github-trail: unknown subcommand returns exit 2" {
    run "$SCRIPT" invalid
    [ "$status" -eq 2 ]
}

# =============================================================================
# Comment Subcommand
# =============================================================================

@test "github-trail: comment missing args returns exit 2" {
    run "$SCRIPT" comment --pr 100
    [ "$status" -eq 2 ]
}

@test "github-trail: comment missing review body file returns exit 2" {
    run "$SCRIPT" comment \
        --pr 100 \
        --iteration 1 \
        --review-body "/nonexistent.md" \
        --bridge-id "bridge-test"
    [ "$status" -eq 2 ]
}

@test "github-trail: comment gracefully degrades without gh" {
    cat > "$TEST_TMPDIR/review.md" <<'EOF'
## Test Review
Some findings here.
EOF

    # Create a minimal PATH with essential POSIX tools but no gh
    mkdir -p "$TEST_TMPDIR/nogh-bin"
    for cmd in bash cat git realpath dirname cd pwd ls sed grep echo printf test "[" head tail tr cut wc; do
        local cmd_path
        cmd_path=$(command -v "$cmd" 2>/dev/null) || continue
        ln -sf "$cmd_path" "$TEST_TMPDIR/nogh-bin/$cmd" 2>/dev/null || true
    done
    # coreutils
    for util in /usr/bin/env /bin/env /usr/bin/id /bin/id /usr/bin/stat /usr/bin/mktemp; do
        [[ -f "$util" ]] && ln -sf "$util" "$TEST_TMPDIR/nogh-bin/$(basename "$util")" 2>/dev/null || true
    done

    PATH="$TEST_TMPDIR/nogh-bin" run "$SCRIPT" comment \
        --pr 100 \
        --iteration 1 \
        --review-body "$TEST_TMPDIR/review.md" \
        --bridge-id "bridge-test"

    [ "$status" -eq 0 ]
    [[ "$output" == *"gh CLI not available"* ]]
}

# =============================================================================
# Update-PR Subcommand
# =============================================================================

@test "github-trail: update-pr missing args returns exit 2" {
    run "$SCRIPT" update-pr --pr 100
    [ "$status" -eq 2 ]
}

@test "github-trail: update-pr missing state file returns exit 2" {
    run "$SCRIPT" update-pr \
        --pr 100 \
        --state-file "/nonexistent.json"
    [ "$status" -eq 2 ]
}

# =============================================================================
# Vision Subcommand
# =============================================================================

@test "github-trail: vision missing args returns exit 2" {
    run "$SCRIPT" vision --pr 100
    [ "$status" -eq 2 ]
}

@test "github-trail: vision gracefully degrades without gh" {
    # Reuse nogh-bin from comment test or create it
    if [[ ! -d "$TEST_TMPDIR/nogh-bin" ]]; then
        mkdir -p "$TEST_TMPDIR/nogh-bin"
        for cmd in bash cat git realpath dirname cd pwd ls sed grep echo printf test "[" head tail tr cut wc; do
            local cmd_path
            cmd_path=$(command -v "$cmd" 2>/dev/null) || continue
            ln -sf "$cmd_path" "$TEST_TMPDIR/nogh-bin/$cmd" 2>/dev/null || true
        done
        for util in /usr/bin/env /bin/env /usr/bin/id /bin/id /usr/bin/stat /usr/bin/mktemp; do
            [[ -f "$util" ]] && ln -sf "$util" "$TEST_TMPDIR/nogh-bin/$(basename "$util")" 2>/dev/null || true
        done
    fi

    PATH="$TEST_TMPDIR/nogh-bin" run "$SCRIPT" vision \
        --pr 100 \
        --vision-id "vision-001" \
        --title "Test Vision"

    [ "$status" -eq 0 ]
    [[ "$output" == *"gh CLI not available"* ]]
}
