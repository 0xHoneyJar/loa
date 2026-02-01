#!/usr/bin/env bats
# Tests for subagent loading and validation infrastructure

setup() {
    export PROJECT_ROOT="${BATS_TEST_DIRNAME}/../.."
    export SUBAGENTS_DIR="${PROJECT_ROOT}/.claude/subagents"
    export REPORTS_DIR="${PROJECT_ROOT}/grimoires/loa/a2a/subagent-reports"
    export COMMANDS_DIR="${PROJECT_ROOT}/.claude/commands"
    export PROTOCOLS_DIR="${PROJECT_ROOT}/.claude/protocols"
}

# =============================================================================
# Directory Structure Tests
# =============================================================================

@test "subagents directory exists" {
    [ -d "$SUBAGENTS_DIR" ]
}

@test "subagents README.md exists" {
    [ -f "$SUBAGENTS_DIR/README.md" ]
}

@test "subagent-reports directory exists" {
    [ -d "$REPORTS_DIR" ]
}

@test "subagent-reports has .gitkeep" {
    [ -f "$REPORTS_DIR/.gitkeep" ]
}

# =============================================================================
# architecture-validator Tests
# =============================================================================

@test "architecture-validator.md exists" {
    [ -f "$SUBAGENTS_DIR/architecture-validator.md" ]
}

@test "architecture-validator.md has valid YAML frontmatter" {
    # Check for YAML frontmatter delimiters
    head -1 "$SUBAGENTS_DIR/architecture-validator.md" | grep -q "^---$"
    # Check frontmatter closes
    grep -n "^---$" "$SUBAGENTS_DIR/architecture-validator.md" | wc -l | grep -q "2"
}

@test "architecture-validator has name field" {
    grep -q "^name:" "$SUBAGENTS_DIR/architecture-validator.md"
}

@test "architecture-validator has version field" {
    grep -q "^version:" "$SUBAGENTS_DIR/architecture-validator.md"
}

@test "architecture-validator has description field" {
    grep -q "^description:" "$SUBAGENTS_DIR/architecture-validator.md"
}

@test "architecture-validator has triggers field" {
    grep -q "^triggers:" "$SUBAGENTS_DIR/architecture-validator.md"
}

@test "architecture-validator has severity_levels field" {
    grep -q "^severity_levels:" "$SUBAGENTS_DIR/architecture-validator.md"
}

@test "architecture-validator has output_path field" {
    grep -q "^output_path:" "$SUBAGENTS_DIR/architecture-validator.md"
}

@test "architecture-validator defines COMPLIANT severity" {
    grep -q "COMPLIANT" "$SUBAGENTS_DIR/architecture-validator.md"
}

@test "architecture-validator defines DRIFT_DETECTED severity" {
    grep -q "DRIFT_DETECTED" "$SUBAGENTS_DIR/architecture-validator.md"
}

@test "architecture-validator defines CRITICAL_VIOLATION severity" {
    grep -q "CRITICAL_VIOLATION" "$SUBAGENTS_DIR/architecture-validator.md"
}

@test "architecture-validator has checks section" {
    grep -q "<checks>" "$SUBAGENTS_DIR/architecture-validator.md"
}

@test "architecture-validator has output_format section" {
    grep -q "<output_format>" "$SUBAGENTS_DIR/architecture-validator.md"
}

@test "architecture-validator has structural compliance checks" {
    grep -q "Structural Compliance" "$SUBAGENTS_DIR/architecture-validator.md"
}

@test "architecture-validator has interface compliance checks" {
    grep -q "Interface Compliance" "$SUBAGENTS_DIR/architecture-validator.md"
}

@test "architecture-validator has pattern compliance checks" {
    grep -q "Pattern Compliance" "$SUBAGENTS_DIR/architecture-validator.md"
}

@test "architecture-validator has naming compliance checks" {
    grep -q "Naming Compliance" "$SUBAGENTS_DIR/architecture-validator.md"
}

# =============================================================================
# /validate Command Tests
# =============================================================================

@test "validate.md command exists" {
    [ -f "$COMMANDS_DIR/validate.md" ]
}

@test "validate command documents architecture type" {
    grep -q "architecture" "$COMMANDS_DIR/validate.md"
}

@test "validate command documents security type" {
    grep -q "security" "$COMMANDS_DIR/validate.md"
}

@test "validate command documents tests type" {
    grep -q "tests" "$COMMANDS_DIR/validate.md"
}

@test "validate command documents all type" {
    grep -q '"all"' "$COMMANDS_DIR/validate.md" || grep -q "`all`" "$COMMANDS_DIR/validate.md"
}

@test "validate command references output location" {
    grep -q "subagent-reports" "$COMMANDS_DIR/validate.md"
}

# =============================================================================
# Protocol Tests
# =============================================================================

@test "subagent-invocation protocol exists" {
    [ -f "$PROTOCOLS_DIR/subagent-invocation.md" ]
}

@test "protocol defines scope determination" {
    grep -q "Scope Determination" "$PROTOCOLS_DIR/subagent-invocation.md"
}

@test "protocol defines invocation methods" {
    grep -q "Invocation Methods" "$PROTOCOLS_DIR/subagent-invocation.md"
}

@test "protocol defines verdict processing" {
    grep -q "Verdict Processing" "$PROTOCOLS_DIR/subagent-invocation.md"
}

@test "protocol defines error handling" {
    grep -q "Error Handling" "$PROTOCOLS_DIR/subagent-invocation.md"
}

# =============================================================================
# README Documentation Tests
# =============================================================================

@test "README explains subagent system" {
    grep -q "validation agents" "$SUBAGENTS_DIR/README.md" || grep -q "Validation" "$SUBAGENTS_DIR/README.md"
}

@test "README documents invocation patterns" {
    grep -q "/validate" "$SUBAGENTS_DIR/README.md"
}

@test "README lists available subagents" {
    grep -q "architecture-validator" "$SUBAGENTS_DIR/README.md"
}

@test "README documents severity levels" {
    grep -q "Severity" "$SUBAGENTS_DIR/README.md"
}

# =============================================================================
# Integration Tests
# =============================================================================

@test "validate command mentions protocol" {
    grep -q "subagent-invocation" "$COMMANDS_DIR/validate.md"
}

@test "protocol mentions validate command" {
    grep -q "/validate" "$PROTOCOLS_DIR/subagent-invocation.md"
}

@test "subagents README mentions protocol" {
    grep -q "subagent-invocation" "$SUBAGENTS_DIR/README.md"
}

# =============================================================================
# File Format Tests
# =============================================================================

@test "all subagent files are markdown" {
    # Count non-markdown files (excluding README)
    local non_md
    non_md=$(find "$SUBAGENTS_DIR" -type f ! -name "*.md" | wc -l)
    [ "$non_md" -eq 0 ]
}

@test "subagents directory has no empty files" {
    local empty_count
    empty_count=$(find "$SUBAGENTS_DIR" -type f -empty | wc -l)
    [ "$empty_count" -eq 0 ]
}
