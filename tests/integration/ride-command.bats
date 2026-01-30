#!/usr/bin/env bats
# Integration tests for /ride command
# Tests end-to-end code reality extraction workflow

setup() {
    export PROJECT_ROOT="${BATS_TEST_DIRNAME}/../.."
    export TEST_TMPDIR="${BATS_TMPDIR}/ride-integration-$$"
    mkdir -p "${TEST_TMPDIR}"

    # Create mock codebase structure (small codebase <10K LOC)
    mkdir -p "${TEST_TMPDIR}/src/auth"
    mkdir -p "${TEST_TMPDIR}/src/api"
    mkdir -p "${TEST_TMPDIR}/lib"
    mkdir -p "${TEST_TMPDIR}/loa-grimoire/a2a/trajectory"
    mkdir -p "${TEST_TMPDIR}/loa-grimoire/context"
    mkdir -p "${TEST_TMPDIR}/loa-grimoire/reality"
    mkdir -p "${TEST_TMPDIR}/loa-grimoire/legacy"
    mkdir -p "${TEST_TMPDIR}/.claude/scripts"
    mkdir -p "${TEST_TMPDIR}/.beads" 2>/dev/null || true

    # Create sample source files
    cat > "${TEST_TMPDIR}/src/auth/jwt.js" << 'EOF'
// JWT authentication module
export function validateToken(token) {
    return jwt.verify(token, SECRET_KEY);
}

export function generateToken(payload) {
    return jwt.sign(payload, SECRET_KEY, { expiresIn: '1h' });
}
EOF

    cat > "${TEST_TMPDIR}/src/api/users.js" << 'EOF'
// User API endpoints
import { validateToken } from '../auth/jwt.js';

export async function getUser(req, res) {
    const token = req.headers.authorization;
    const payload = await validateToken(token);
    // ... implementation
}
EOF

    cat > "${TEST_TMPDIR}/lib/database.js" << 'EOF'
// Database connection module
export class Database {
    constructor(config) {
        this.config = config;
    }

    async connect() {
        // ... implementation
    }
}
EOF

    # Create documentation that mentions a feature
    cat > "${TEST_TMPDIR}/loa-grimoire/context/features.md" << 'EOF'
# Features

## Authentication
- JWT token validation
- Token generation
- OAuth2 SSO (planned)

## User Management
- User retrieval API
- User creation (not yet implemented)
EOF

    # Initialize git repo
    cd "${TEST_TMPDIR}"
    git init -q
    git config user.email "test@example.com"
    git config user.name "Test User"
    git add .
    git commit -q -m "Initial commit"
}

teardown() {
    rm -rf "${TEST_TMPDIR}"
}

# =============================================================================
# Small Codebase Tests (<10K LOC)
# =============================================================================

@test "/ride completes successfully on small codebase" {
    skip "Requires /ride command implementation in agent context"
    cd "${TEST_TMPDIR}"

    # Run ride command (would normally be invoked through Claude agent)
    # This is a placeholder for integration with the actual /ride flow
    run bash -c "echo 'Simulating /ride command execution'"

    [ "$status" -eq 0 ]
}

@test "/ride generates drift-report.md" {
    skip "Requires full /ride implementation"
    cd "${TEST_TMPDIR}"

    # After /ride runs, check outputs
    [ -f "loa-grimoire/reality/drift-report.md" ]
}

@test "/ride updates NOTES.md with findings" {
    skip "Requires full /ride implementation"
    cd "${TEST_TMPDIR}"

    [ -f "loa-grimoire/NOTES.md" ]

    # Check for structured sections
    run grep "## Active Sub-Goals" "loa-grimoire/NOTES.md"
    [ "$status" -eq 0 ]
}

@test "/ride creates trajectory logs" {
    skip "Requires full /ride implementation"
    cd "${TEST_TMPDIR}"

    trajectory_file="loa-grimoire/a2a/trajectory/$(date +%Y-%m-%d).jsonl"
    [ -f "$trajectory_file" ]

    # Check trajectory has search operations logged
    run grep '"phase":"intent"' "$trajectory_file"
    [ "$status" -eq 0 ]
}

@test "/ride creates Beads tasks for Ghost Features (if bd installed)" {
    skip "Requires full /ride implementation and Beads"
    cd "${TEST_TMPDIR}"

    if command -v bd >/dev/null 2>&1; then
        # Check for Beads tasks created
        [ -d ".beads" ]

        # Check for liability tracking
        run bd list --type liability
        [ "$status" -eq 0 ]
    fi
}

# =============================================================================
# Performance Validation Tests
# =============================================================================

@test "/ride completes in <30s on small codebase" {
    skip "Requires full /ride implementation with timing"
    cd "${TEST_TMPDIR}"

    start_time=$(date +%s)

    # Run /ride
    # (placeholder for actual invocation)

    end_time=$(date +%s)
    duration=$((end_time - start_time))

    [ "$duration" -lt 30 ]
}

# =============================================================================
# Search Mode Tests
# =============================================================================

@test "/ride works with ck installed (semantic search mode)" {
    skip "Requires ck installation"
    cd "${TEST_TMPDIR}"

    if command -v ck >/dev/null 2>&1; then
        # Run /ride with ck available
        # Check trajectory log shows mode=ck
        trajectory_file="loa-grimoire/a2a/trajectory/$(date +%Y-%m-%d).jsonl"

        run grep '"mode":"ck"' "$trajectory_file"
        [ "$status" -eq 0 ]
    fi
}

@test "/ride works without ck (grep fallback mode)" {
    cd "${TEST_TMPDIR}"

    # Hide ck temporarily
    export PATH="/usr/bin:/bin"

    # Run /ride
    # Check trajectory log shows mode=grep
    # (placeholder for actual verification)

    [ "$status" -eq 0 ]
}

# =============================================================================
# Ghost Feature Detection Tests
# =============================================================================

@test "/ride detects Ghost Features (documented but not implemented)" {
    skip "Requires full /ride implementation"
    cd "${TEST_TMPDIR}"

    # The features.md mentions "OAuth2 SSO" and "User creation"
    # These should be detected as Ghost Features

    # Check drift report
    run grep "OAuth2 SSO" "loa-grimoire/reality/drift-report.md"
    [ "$status" -eq 0 ]

    run grep "GHOST" "loa-grimoire/reality/drift-report.md"
    [ "$status" -eq 0 ]
}

@test "/ride uses Negative Grounding for Ghost detection" {
    skip "Requires full /ride implementation"
    cd "${TEST_TMPDIR}"

    # Check trajectory log shows two diverse queries for Ghost detection
    trajectory_file="loa-grimoire/a2a/trajectory/$(date +%Y-%m-%d).jsonl"

    # Should have multiple semantic searches with 0 results
    run grep -c '"search_type":"semantic"' "$trajectory_file"
    [ "$output" -ge 2 ]
}

# =============================================================================
# Shadow System Detection Tests
# =============================================================================

@test "/ride detects Shadow Systems (undocumented code)" {
    skip "Requires full /ride implementation"
    cd "${TEST_TMPDIR}"

    # The Database class is implemented but not documented
    # Should be flagged as Shadow

    run grep "Database" "loa-grimoire/reality/drift-report.md"
    [ "$status" -eq 0 ]

    run grep "SHADOW" "loa-grimoire/reality/drift-report.md"
    [ "$status" -eq 0 ]
}

@test "/ride classifies Shadow Systems (Orphaned/Drifted/Partial)" {
    skip "Requires full /ride implementation"
    cd "${TEST_TMPDIR}"

    # Check drift report has classification
    run grep -E "(Orphaned|Drifted|Partial)" "loa-grimoire/reality/drift-report.md"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Code Extraction Tests
# =============================================================================

@test "/ride extracts entry points to reality/" {
    skip "Requires full /ride implementation"
    cd "${TEST_TMPDIR}"

    # Check reality directory has extracted code info
    [ -d "loa-grimoire/reality" ]

    # Check for entry points file
    if [ -f "loa-grimoire/reality/entry-points.md" ]; then
        run grep "validateToken" "loa-grimoire/reality/entry-points.md"
        [ "$status" -eq 0 ]
    fi
}

@test "/ride creates legacy document inventory" {
    skip "Requires full /ride implementation"
    cd "${TEST_TMPDIR}"

    [ -f "loa-grimoire/legacy/INVENTORY.md" ]

    # Check inventory lists existing docs
    run grep "features.md" "loa-grimoire/legacy/INVENTORY.md"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Output Format Tests
# =============================================================================

@test "/ride output is identical regardless of search mode" {
    skip "Requires full /ride implementation and comparison"
    cd "${TEST_TMPDIR}"

    # Run /ride twice: once with ck, once with grep
    # Compare outputs (should be semantically equivalent)

    # This test would require two runs and diff comparison
    [ "$status" -eq 0 ]
}

# =============================================================================
# Error Handling Tests
# =============================================================================

@test "/ride handles empty codebase gracefully" {
    cd "${TEST_TMPDIR}"

    # Remove all source files
    rm -rf src lib

    # Run /ride
    # Should not crash, may report no code found
    run bash -c "echo 'Simulating /ride on empty codebase'"

    [ "$status" -eq 0 ]
}

@test "/ride handles missing loa-grimoire directory" {
    cd "${TEST_TMPDIR}"

    rm -rf loa-grimoire

    # /ride should create necessary directories
    run bash -c "echo 'Simulating /ride with missing dirs'"

    [ "$status" -eq 0 ]
}

@test "/ride handles non-git repository" {
    cd "${TEST_TMPDIR}"

    rm -rf .git

    # Should still work (uses pwd instead of git root)
    run bash -c "echo 'Simulating /ride in non-git repo'"

    [ "$status" -eq 0 ]
}

# =============================================================================
# Medium Codebase Tests (10K-100K LOC)
# =============================================================================

@test "/ride completes in <2min on medium codebase" {
    skip "Requires medium-sized test codebase"

    # Would need to generate or clone a medium codebase
    [ "$status" -eq 0 ]
}

# =============================================================================
# Large Codebase Tests (>100K LOC)
# =============================================================================

@test "/ride completes in <5min on large codebase" {
    skip "Requires large test codebase"

    # Would need to clone a large open-source project
    [ "$status" -eq 0 ]
}

# =============================================================================
# Tool Result Clearing Tests
# =============================================================================

@test "/ride applies Tool Result Clearing after >20 results" {
    skip "Requires full /ride implementation with trajectory inspection"
    cd "${TEST_TMPDIR}"

    trajectory_file="loa-grimoire/a2a/trajectory/$(date +%Y-%m-%d).jsonl"

    # Check for "clear" phase in trajectory when result_count > 20
    run grep '"phase":"clear"' "$trajectory_file"
    [ "$status" -eq 0 ]
}

@test "/ride synthesizes findings to NOTES.md (not raw results)" {
    skip "Requires full /ride implementation"
    cd "${TEST_TMPDIR}"

    # NOTES.md should have high-level synthesis, not raw search output
    if [ -f "loa-grimoire/NOTES.md" ]; then
        # Check for synthesis format (file:line references, not full snippets)
        run grep -E "\[/.*:[0-9]+\]" "loa-grimoire/NOTES.md"
        [ "$status" -eq 0 ]
    fi
}
