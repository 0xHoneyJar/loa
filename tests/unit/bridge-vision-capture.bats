#!/usr/bin/env bats
# Unit tests for bridge-vision-capture.sh
# Sprint 2: Bridge Core — vision extraction, index update, numbering

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    SCRIPT="$PROJECT_ROOT/.claude/scripts/bridge-vision-capture.sh"

    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_TMPDIR="$BATS_TMPDIR/vision-capture-test-$$"
    mkdir -p "$TEST_TMPDIR/grimoires/loa/visions/entries"
    mkdir -p "$TEST_TMPDIR/.claude/scripts"

    # Copy bootstrap for sourcing
    cp "$PROJECT_ROOT/.claude/scripts/bootstrap.sh" "$TEST_TMPDIR/.claude/scripts/"
    if [[ -f "$PROJECT_ROOT/.claude/scripts/path-lib.sh" ]]; then
        cp "$PROJECT_ROOT/.claude/scripts/path-lib.sh" "$TEST_TMPDIR/.claude/scripts/"
    fi

    # Create index.md
    cat > "$TEST_TMPDIR/grimoires/loa/visions/index.md" <<'EOF'
# Vision Registry

## Active Visions

| ID | Title | Source | Status | Tags |
|----|-------|--------|--------|------|

## Statistics

- Total captured: 0
- Exploring: 0
- Implemented: 0
- Deferred: 0
EOF

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

skip_if_deps_missing() {
    if ! command -v jq &>/dev/null; then
        skip "jq not installed"
    fi
}

# =============================================================================
# Basic Capture
# =============================================================================

@test "vision-capture: script exists and is executable" {
    [ -x "$SCRIPT" ]
}

@test "vision-capture: handles 0 visions gracefully" {
    skip_if_deps_missing

    cat > "$TEST_TMPDIR/findings.json" <<'EOF'
{
  "findings": [
    {"severity": "HIGH", "title": "Not a vision", "description": "Bug"}
  ],
  "total": 1,
  "by_severity": {"high": 1, "vision": 0},
  "severity_weighted_score": 5
}
EOF

    run "$SCRIPT" \
        --findings "$TEST_TMPDIR/findings.json" \
        --bridge-id "bridge-test-1" \
        --iteration 1 \
        --pr 100 \
        --output-dir "$TEST_TMPDIR/grimoires/loa/visions"

    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

@test "vision-capture: creates vision entry files" {
    skip_if_deps_missing

    cat > "$TEST_TMPDIR/findings.json" <<'EOF'
{
  "findings": [
    {"severity": "VISION", "id": "vision-1", "title": "Cross-repo GT hub", "description": "Could share GT across repos", "potential": "Unified codebase understanding"}
  ],
  "total": 1,
  "by_severity": {"vision": 1},
  "severity_weighted_score": 0
}
EOF

    run "$SCRIPT" \
        --findings "$TEST_TMPDIR/findings.json" \
        --bridge-id "bridge-test-2" \
        --iteration 2 \
        --pr 200 \
        --output-dir "$TEST_TMPDIR/grimoires/loa/visions"

    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
    [ -f "$TEST_TMPDIR/grimoires/loa/visions/entries/vision-001.md" ]
}

@test "vision-capture: missing arguments returns exit 2" {
    run "$SCRIPT"
    [ "$status" -eq 2 ]
}

@test "vision-capture: missing findings file returns exit 2" {
    run "$SCRIPT" \
        --findings "/nonexistent.json" \
        --bridge-id "bridge-test" \
        --iteration 1 \
        --output-dir "$TEST_TMPDIR/grimoires/loa/visions"
    [ "$status" -eq 2 ]
}

# =============================================================================
# Eval Tasks
# =============================================================================

@test "vision-capture: --help shows usage" {
    run "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}
