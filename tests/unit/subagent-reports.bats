#!/usr/bin/env bats
# Tests for security-scanner and test-adequacy-reviewer subagents

setup() {
    export PROJECT_ROOT="${BATS_TEST_DIRNAME}/../.."
    export SUBAGENTS_DIR="${PROJECT_ROOT}/.claude/subagents"
    export REPORTS_DIR="${PROJECT_ROOT}/grimoires/loa/a2a/subagent-reports"
}

# =============================================================================
# security-scanner Tests
# =============================================================================

@test "security-scanner.md exists" {
    [ -f "$SUBAGENTS_DIR/security-scanner.md" ]
}

@test "security-scanner.md has valid YAML frontmatter" {
    head -1 "$SUBAGENTS_DIR/security-scanner.md" | grep -q "^---$"
    grep -n "^---$" "$SUBAGENTS_DIR/security-scanner.md" | wc -l | grep -q "2"
}

@test "security-scanner has name field" {
    grep -q "^name: security-scanner" "$SUBAGENTS_DIR/security-scanner.md"
}

@test "security-scanner has version field" {
    grep -q "^version:" "$SUBAGENTS_DIR/security-scanner.md"
}

@test "security-scanner has description field" {
    grep -q "^description:" "$SUBAGENTS_DIR/security-scanner.md"
}

@test "security-scanner has triggers field" {
    grep -q "^triggers:" "$SUBAGENTS_DIR/security-scanner.md"
}

@test "security-scanner has severity_levels field" {
    grep -q "^severity_levels:" "$SUBAGENTS_DIR/security-scanner.md"
}

@test "security-scanner has output_path field" {
    grep -q "^output_path:" "$SUBAGENTS_DIR/security-scanner.md"
}

@test "security-scanner defines CRITICAL severity" {
    grep -q "CRITICAL" "$SUBAGENTS_DIR/security-scanner.md"
}

@test "security-scanner defines HIGH severity" {
    grep -q "HIGH" "$SUBAGENTS_DIR/security-scanner.md"
}

@test "security-scanner defines MEDIUM severity" {
    grep -q "MEDIUM" "$SUBAGENTS_DIR/security-scanner.md"
}

@test "security-scanner defines LOW severity" {
    grep -q "LOW" "$SUBAGENTS_DIR/security-scanner.md"
}

@test "security-scanner has checks section" {
    grep -q "<checks>" "$SUBAGENTS_DIR/security-scanner.md"
}

@test "security-scanner has output_format section" {
    grep -q "<output_format>" "$SUBAGENTS_DIR/security-scanner.md"
}

@test "security-scanner has Input Validation checks" {
    grep -q "Input Validation" "$SUBAGENTS_DIR/security-scanner.md"
}

@test "security-scanner has Authentication checks" {
    grep -q "Authentication" "$SUBAGENTS_DIR/security-scanner.md"
}

@test "security-scanner has Data Protection checks" {
    grep -q "Data Protection" "$SUBAGENTS_DIR/security-scanner.md"
}

@test "security-scanner has API Security checks" {
    grep -q "API Security" "$SUBAGENTS_DIR/security-scanner.md"
}

@test "security-scanner has Dependency Security checks" {
    grep -q "Dependency Security" "$SUBAGENTS_DIR/security-scanner.md"
}

@test "security-scanner has Cryptography checks" {
    grep -q "Cryptography" "$SUBAGENTS_DIR/security-scanner.md"
}

@test "security-scanner checks for SQL injection" {
    grep -q "SQL injection" "$SUBAGENTS_DIR/security-scanner.md"
}

@test "security-scanner checks for hardcoded credentials" {
    grep -q "Hardcoded credentials" "$SUBAGENTS_DIR/security-scanner.md"
}

@test "security-scanner checks for XSS" {
    grep -q "XSS" "$SUBAGENTS_DIR/security-scanner.md"
}

# =============================================================================
# test-adequacy-reviewer Tests
# =============================================================================

@test "test-adequacy-reviewer.md exists" {
    [ -f "$SUBAGENTS_DIR/test-adequacy-reviewer.md" ]
}

@test "test-adequacy-reviewer.md has valid YAML frontmatter" {
    head -1 "$SUBAGENTS_DIR/test-adequacy-reviewer.md" | grep -q "^---$"
    grep -n "^---$" "$SUBAGENTS_DIR/test-adequacy-reviewer.md" | wc -l | grep -q "2"
}

@test "test-adequacy-reviewer has name field" {
    grep -q "^name: test-adequacy-reviewer" "$SUBAGENTS_DIR/test-adequacy-reviewer.md"
}

@test "test-adequacy-reviewer has version field" {
    grep -q "^version:" "$SUBAGENTS_DIR/test-adequacy-reviewer.md"
}

@test "test-adequacy-reviewer has description field" {
    grep -q "^description:" "$SUBAGENTS_DIR/test-adequacy-reviewer.md"
}

@test "test-adequacy-reviewer has triggers field" {
    grep -q "^triggers:" "$SUBAGENTS_DIR/test-adequacy-reviewer.md"
}

@test "test-adequacy-reviewer has severity_levels field" {
    grep -q "^severity_levels:" "$SUBAGENTS_DIR/test-adequacy-reviewer.md"
}

@test "test-adequacy-reviewer has output_path field" {
    grep -q "^output_path:" "$SUBAGENTS_DIR/test-adequacy-reviewer.md"
}

@test "test-adequacy-reviewer defines STRONG severity" {
    grep -q "STRONG" "$SUBAGENTS_DIR/test-adequacy-reviewer.md"
}

@test "test-adequacy-reviewer defines ADEQUATE severity" {
    grep -q "ADEQUATE" "$SUBAGENTS_DIR/test-adequacy-reviewer.md"
}

@test "test-adequacy-reviewer defines WEAK severity" {
    grep -q "WEAK" "$SUBAGENTS_DIR/test-adequacy-reviewer.md"
}

@test "test-adequacy-reviewer defines INSUFFICIENT severity" {
    grep -q "INSUFFICIENT" "$SUBAGENTS_DIR/test-adequacy-reviewer.md"
}

@test "test-adequacy-reviewer has checks section" {
    grep -q "<checks>" "$SUBAGENTS_DIR/test-adequacy-reviewer.md"
}

@test "test-adequacy-reviewer has output_format section" {
    grep -q "<output_format>" "$SUBAGENTS_DIR/test-adequacy-reviewer.md"
}

@test "test-adequacy-reviewer has Coverage Quality checks" {
    grep -q "Coverage Quality" "$SUBAGENTS_DIR/test-adequacy-reviewer.md"
}

@test "test-adequacy-reviewer has Test Independence checks" {
    grep -q "Test Independence" "$SUBAGENTS_DIR/test-adequacy-reviewer.md"
}

@test "test-adequacy-reviewer has Assertion Quality checks" {
    grep -q "Assertion Quality" "$SUBAGENTS_DIR/test-adequacy-reviewer.md"
}

@test "test-adequacy-reviewer has Missing Tests checks" {
    grep -q "Missing Tests" "$SUBAGENTS_DIR/test-adequacy-reviewer.md"
}

@test "test-adequacy-reviewer has Test Smells checks" {
    grep -q "Test Smells" "$SUBAGENTS_DIR/test-adequacy-reviewer.md"
}

# =============================================================================
# Cross-Subagent Integration Tests
# =============================================================================

@test "all three subagents exist" {
    [ -f "$SUBAGENTS_DIR/architecture-validator.md" ]
    [ -f "$SUBAGENTS_DIR/security-scanner.md" ]
    [ -f "$SUBAGENTS_DIR/test-adequacy-reviewer.md" ]
}

@test "all subagents have consistent frontmatter structure" {
    # Check all have the 6 required frontmatter fields
    for subagent in architecture-validator security-scanner test-adequacy-reviewer; do
        grep -q "^name:" "$SUBAGENTS_DIR/${subagent}.md"
        grep -q "^version:" "$SUBAGENTS_DIR/${subagent}.md"
        grep -q "^description:" "$SUBAGENTS_DIR/${subagent}.md"
        grep -q "^triggers:" "$SUBAGENTS_DIR/${subagent}.md"
        grep -q "^severity_levels:" "$SUBAGENTS_DIR/${subagent}.md"
        grep -q "^output_path:" "$SUBAGENTS_DIR/${subagent}.md"
    done
}

@test "all subagents have objective section" {
    for subagent in architecture-validator security-scanner test-adequacy-reviewer; do
        grep -q "<objective>" "$SUBAGENTS_DIR/${subagent}.md"
    done
}

@test "all subagents have checks section" {
    for subagent in architecture-validator security-scanner test-adequacy-reviewer; do
        grep -q "<checks>" "$SUBAGENTS_DIR/${subagent}.md"
    done
}

@test "all subagents have output_format section" {
    for subagent in architecture-validator security-scanner test-adequacy-reviewer; do
        grep -q "<output_format>" "$SUBAGENTS_DIR/${subagent}.md"
    done
}

@test "subagent-reports directory exists" {
    [ -d "$REPORTS_DIR" ]
}

@test "subagent-reports has .gitkeep" {
    [ -f "$REPORTS_DIR/.gitkeep" ]
}

# =============================================================================
# README Integration Tests
# =============================================================================

@test "README documents security-scanner" {
    grep -q "security-scanner" "$SUBAGENTS_DIR/README.md"
}

@test "README documents test-adequacy-reviewer" {
    grep -q "test-adequacy-reviewer" "$SUBAGENTS_DIR/README.md"
}

@test "README documents all severity levels for security-scanner" {
    grep -q "CRITICAL.*HIGH.*MEDIUM.*LOW" "$SUBAGENTS_DIR/README.md" || \
    (grep -q "CRITICAL" "$SUBAGENTS_DIR/README.md" && \
     grep -q "HIGH" "$SUBAGENTS_DIR/README.md" && \
     grep -q "MEDIUM" "$SUBAGENTS_DIR/README.md" && \
     grep -q "LOW" "$SUBAGENTS_DIR/README.md")
}

@test "README documents all severity levels for test-adequacy-reviewer" {
    grep -q "STRONG" "$SUBAGENTS_DIR/README.md"
    grep -q "ADEQUATE" "$SUBAGENTS_DIR/README.md"
    grep -q "WEAK" "$SUBAGENTS_DIR/README.md"
    grep -q "INSUFFICIENT" "$SUBAGENTS_DIR/README.md"
}
