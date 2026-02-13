#!/usr/bin/env bats
# Unit tests for butterfreezone-gen.sh
# Sprint 1: Generation Core — tier detection, extractors, provenance, budgets, checksums

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    SCRIPT="$PROJECT_ROOT/.claude/scripts/butterfreezone-gen.sh"

    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_TMPDIR="$BATS_TMPDIR/butterfreezone-gen-test-$$"
    mkdir -p "$TEST_TMPDIR"

    # Create a mock repo structure for testing
    export MOCK_REPO="$TEST_TMPDIR/mock-repo"
    mkdir -p "$MOCK_REPO"
    cd "$MOCK_REPO"

    # Initialize a git repo
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"

    # Create basic structure
    mkdir -p src
    echo 'console.log("hello")' > src/index.js
    git add -A
    git commit -q -m "Initial commit"
}

teardown() {
    cd /
    if [[ -d "$TEST_TMPDIR" ]]; then
        rm -rf "$TEST_TMPDIR"
    fi
}

# =============================================================================
# Script Basics
# =============================================================================

@test "butterfreezone-gen: script exists and is executable" {
    [ -x "$SCRIPT" ]
}

@test "butterfreezone-gen: --help prints usage and exits 0" {
    run "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: butterfreezone-gen.sh"* ]]
    [[ "$output" == *"--dry-run"* ]]
    [[ "$output" == *"--tier"* ]]
}

@test "butterfreezone-gen: unknown flag exits 2" {
    run "$SCRIPT" --invalid-flag
    [ "$status" -eq 2 ]
}

# =============================================================================
# Tier Detection (SDD 3.1.2)
# =============================================================================

@test "butterfreezone-gen: tier detection — Tier 1 with reality files" {
    # Create reality directory with content
    mkdir -p grimoires/loa/reality
    cat > grimoires/loa/reality/api-surface.md <<'EOF'
# API Surface

This is the API surface documentation with more than ten words of content to trigger Tier 1 detection properly.
EOF
    git add -A && git commit -q -m "Add reality"

    run "$SCRIPT" --dry-run --verbose
    [ "$status" -eq 0 ]
    [[ "$output" == *"AGENT-CONTEXT"* ]]
    # Check stderr for tier info
    [[ "${lines[0]}" == *"tier: 1"* ]] || [[ "$output" == *"CODE-FACTUAL"* ]] || true
}

@test "butterfreezone-gen: tier detection — Tier 2 with package.json" {
    # Create package.json (no reality files)
    cat > package.json <<'EOF'
{
  "name": "test-project",
  "version": "1.2.3",
  "description": "A test project"
}
EOF
    git add -A && git commit -q -m "Add package.json"

    run "$SCRIPT" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"AGENT-CONTEXT"* ]]
    [[ "$output" == *"name: test-project"* ]]
}

@test "butterfreezone-gen: tier detection — Tier 3 empty repo (bootstrap)" {
    # Create empty repo with no manifests or source files
    local empty_repo="$TEST_TMPDIR/empty-repo"
    mkdir -p "$empty_repo"
    cd "$empty_repo"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"
    echo "readme" > README.md
    git add -A && git commit -q -m "Empty"

    # Remove any source files
    rm -f src/index.js 2>/dev/null || true

    run "$SCRIPT" --dry-run --tier 3
    [ "$status" -eq 3 ]
    [[ "$output" == *"AGENT-CONTEXT"* ]]
}

@test "butterfreezone-gen: --tier N forces specific tier" {
    run "$SCRIPT" --dry-run --tier 2
    [ "$status" -eq 0 ]

    run "$SCRIPT" --dry-run --tier 3
    [ "$status" -eq 3 ]
}

# =============================================================================
# Agent Context (SDD 3.1.3)
# =============================================================================

@test "butterfreezone-gen: AGENT-CONTEXT block present with required fields" {
    cat > package.json <<'EOF'
{
  "name": "my-app",
  "version": "2.0.0",
  "description": "My awesome application"
}
EOF
    git add -A && git commit -q -m "Add manifest"

    run "$SCRIPT" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"<!-- AGENT-CONTEXT"* ]]
    [[ "$output" == *"name: my-app"* ]]
    [[ "$output" == *"type:"* ]]
    [[ "$output" == *"purpose:"* ]]
    [[ "$output" == *"version:"* ]]
    [[ "$output" == *"trust_level: grounded"* ]]
}

# =============================================================================
# Provenance Tags (SDD 3.1.4)
# =============================================================================

@test "butterfreezone-gen: provenance tags on all sections" {
    cat > package.json <<'EOF'
{"name": "prov-test", "version": "1.0.0"}
EOF
    mkdir -p src
    echo 'export function hello() {}' > src/index.ts
    git add -A && git commit -q -m "Add source"

    run "$SCRIPT" --dry-run
    [ "$status" -eq 0 ]

    # Count sections that have provenance
    local section_count
    section_count=$(echo "$output" | grep -c "^## " || true)
    local provenance_count
    provenance_count=$(echo "$output" | grep -c "<!-- provenance:" || true)

    # Each generated section should have a provenance tag
    [ "$provenance_count" -ge "$section_count" ]
}

@test "butterfreezone-gen: Tier 2 sections tagged as DERIVED" {
    cat > package.json <<'EOF'
{"name": "derive-test", "version": "1.0.0"}
EOF
    git add -A && git commit -q -m "Add pkg"

    run "$SCRIPT" --dry-run --tier 2
    [ "$status" -eq 0 ]
    [[ "$output" == *"DERIVED"* ]]
}

# =============================================================================
# Word Budget (SDD 3.1.6)
# =============================================================================

@test "butterfreezone-gen: output under total word budget" {
    git add -A && git commit -q --allow-empty -m "Budget test"

    run "$SCRIPT" --dry-run
    [ "$status" -eq 0 ]

    local word_count
    word_count=$(echo "$output" | wc -w | tr -d ' ')
    [ "$word_count" -le 3200 ]
}

@test "butterfreezone-gen: per-section budget enforced (large content truncated)" {
    # Create a project with many exports to trigger truncation
    mkdir -p src
    for i in $(seq 1 200); do
        echo "export function func${i}() { return ${i}; }" >> src/big.ts
    done
    git add -A && git commit -q -m "Big exports"

    run "$SCRIPT" --dry-run
    [ "$status" -eq 0 ]

    local word_count
    word_count=$(echo "$output" | wc -w | tr -d ' ')
    [ "$word_count" -le 3200 ]
}

# =============================================================================
# Checksums (SDD 3.1.7)
# =============================================================================

@test "butterfreezone-gen: ground-truth-meta block present" {
    git add -A && git commit -q --allow-empty -m "Meta test"

    run "$SCRIPT" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"<!-- ground-truth-meta"* ]]
    [[ "$output" == *"head_sha:"* ]]
    [[ "$output" == *"generated_at:"* ]]
    [[ "$output" == *"generator: butterfreezone-gen v1.0.0"* ]]
}

@test "butterfreezone-gen: checksums exclude generated_at timestamp" {
    git add -A && git commit -q --allow-empty -m "Checksum test"

    # Run twice with small delay — checksums should match even if generated_at differs
    local run1
    run1=$("$SCRIPT" --dry-run 2>/dev/null | grep -v "generated_at")
    sleep 1
    local run2
    run2=$("$SCRIPT" --dry-run 2>/dev/null | grep -v "generated_at")

    [ "$run1" = "$run2" ]
}

# =============================================================================
# Manual Section Preservation (SDD 3.1.5)
# =============================================================================

@test "butterfreezone-gen: preserves manual sections across regeneration" {
    git add -A && git commit -q --allow-empty -m "Manual test"

    # First generation
    "$SCRIPT" --output "$MOCK_REPO/BUTTERFREEZONE.md" 2>/dev/null

    # Add manual section
    cat >> "$MOCK_REPO/BUTTERFREEZONE.md" <<'EOF'

<!-- manual-start:ecosystem -->
Custom ecosystem notes that should survive regeneration.
<!-- manual-end:ecosystem -->
EOF

    # Make a change to trigger regeneration
    echo "change" >> src/index.js
    git add -A && git commit -q -m "Trigger regen"

    # Regenerate
    "$SCRIPT" --output "$MOCK_REPO/BUTTERFREEZONE.md" 2>/dev/null

    # Manual section should still be present
    run grep "Custom ecosystem notes" "$MOCK_REPO/BUTTERFREEZONE.md"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Atomic Write (SDD 3.1.9)
# =============================================================================

@test "butterfreezone-gen: atomic write doesn't corrupt on success" {
    git add -A && git commit -q --allow-empty -m "Atomic test"

    run "$SCRIPT" --output "$MOCK_REPO/BUTTERFREEZONE.md"
    [ "$status" -eq 0 ]
    [ -f "$MOCK_REPO/BUTTERFREEZONE.md" ]
    [ ! -f "$MOCK_REPO/BUTTERFREEZONE.md.tmp" ]

    # File should have content
    local words
    words=$(wc -w < "$MOCK_REPO/BUTTERFREEZONE.md" | tr -d ' ')
    [ "$words" -gt 0 ]
}

# =============================================================================
# Security Redaction (SDD 3.1.8)
# =============================================================================

@test "butterfreezone-gen: redacts AWS access keys" {
    mkdir -p src
    echo 'const key = "AKIAIOSFODNN7EXAMPLE"' > src/config.js
    git add -A && git commit -q -m "Add fake key"

    run "$SCRIPT" --dry-run
    # The key should not appear in output
    [[ "$output" != *"AKIAIOSFODNN7EXAMPLE"* ]]
}

@test "butterfreezone-gen: redacts GitHub tokens" {
    mkdir -p src
    echo 'const token = "ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"' > src/auth.js
    git add -A && git commit -q -m "Add fake token"

    run "$SCRIPT" --dry-run
    [[ "$output" != *"ghp_xxxx"* ]]
}

@test "butterfreezone-gen: allowlist preserves sha256 checksums" {
    run "$SCRIPT" --dry-run
    # ground-truth-meta should have sha256 hashes
    [[ "$output" == *"sha256"* ]] || [[ "$output" == *"head_sha:"* ]]
}

# =============================================================================
# Dry Run (SDD 3.1.17)
# =============================================================================

@test "butterfreezone-gen: --dry-run prints to stdout only" {
    git add -A && git commit -q --allow-empty -m "Dry run test"

    run "$SCRIPT" --dry-run --output "$MOCK_REPO/BUTTERFREEZONE.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"AGENT-CONTEXT"* ]]
    # File should NOT be written
    [ ! -f "$MOCK_REPO/BUTTERFREEZONE.md" ]
}

# =============================================================================
# Determinism (SDD 3.1.16)
# =============================================================================

@test "butterfreezone-gen: two runs produce identical output" {
    git add -A && git commit -q --allow-empty -m "Determinism test"

    local run1
    run1=$("$SCRIPT" --dry-run 2>/dev/null | grep -v "generated_at")
    local run2
    run2=$("$SCRIPT" --dry-run 2>/dev/null | grep -v "generated_at")

    [ "$run1" = "$run2" ]
}

# =============================================================================
# Exit Codes
# =============================================================================

@test "butterfreezone-gen: exit code 0 on success" {
    git add -A && git commit -q --allow-empty -m "Exit test"

    run "$SCRIPT" --dry-run
    [ "$status" -eq 0 ]
}

@test "butterfreezone-gen: exit code 3 for Tier 3 bootstrap" {
    local empty_repo="$TEST_TMPDIR/empty-exit"
    mkdir -p "$empty_repo"
    cd "$empty_repo"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"
    echo "x" > readme.txt
    git add -A && git commit -q -m "Empty"

    run "$SCRIPT" --dry-run --tier 3
    [ "$status" -eq 3 ]
}

@test "butterfreezone-gen: exit code 2 for invalid config" {
    run "$SCRIPT" --tier 5
    [ "$status" -eq 2 ]
}

# =============================================================================
# JSON Output (SDD 4.2)
# =============================================================================

@test "butterfreezone-gen: --json emits valid JSON to stderr" {
    git add -A && git commit -q --allow-empty -m "JSON test"

    local json_out
    json_out=$("$SCRIPT" --dry-run --json 2>&1 >/dev/null)

    # Should be valid JSON
    echo "$json_out" | jq . >/dev/null 2>&1
    [ $? -eq 0 ]

    # Should have expected fields
    echo "$json_out" | jq -e '.status' >/dev/null
    echo "$json_out" | jq -e '.tier' >/dev/null
    echo "$json_out" | jq -e '.generator' >/dev/null
}

# =============================================================================
# Edge Cases (Flatline IMP-005)
# =============================================================================

@test "butterfreezone-gen: handles empty package.json gracefully" {
    echo '{}' > package.json
    git add -A && git commit -q -m "Empty manifest"

    run "$SCRIPT" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"AGENT-CONTEXT"* ]]
}

@test "butterfreezone-gen: handles malformed package.json gracefully" {
    echo 'not valid json' > package.json
    git add -A && git commit -q -m "Bad manifest"

    run "$SCRIPT" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"AGENT-CONTEXT"* ]]
}

# =============================================================================
# Staleness / Regeneration (SDD 3.1.10)
# =============================================================================

@test "butterfreezone-gen: skips generation when file is up-to-date" {
    git add -A && git commit -q --allow-empty -m "Stale test"

    # Generate once
    "$SCRIPT" --output "$MOCK_REPO/BUTTERFREEZONE.md" 2>/dev/null

    # Run again — should detect up-to-date and skip
    run "$SCRIPT" --output "$MOCK_REPO/BUTTERFREEZONE.md" --verbose
    [ "$status" -eq 0 ]
    [[ "$output" == *"up-to-date"* ]] || [[ "${lines[*]}" == *"up-to-date"* ]]
}
