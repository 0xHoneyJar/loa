#!/usr/bin/env bats
# Tests for NOTES.md template and structured-memory protocol

setup() {
    export PROJECT_ROOT="${BATS_TEST_DIRNAME}/../.."
    export TEMPLATE_FILE="${PROJECT_ROOT}/.claude/templates/NOTES.md.template"
    export PROTOCOL_FILE="${PROJECT_ROOT}/.claude/protocols/structured-memory.md"
}

# =============================================================================
# Template Existence Tests
# =============================================================================

@test "NOTES.md template exists" {
    [ -f "$TEMPLATE_FILE" ]
}

@test "NOTES.md template is not empty" {
    [ -s "$TEMPLATE_FILE" ]
}

@test "structured-memory protocol exists" {
    [ -f "$PROTOCOL_FILE" ]
}

# =============================================================================
# Required Sections Tests
# =============================================================================

@test "template has Current Focus section" {
    grep -q "## Current Focus" "$TEMPLATE_FILE"
}

@test "template has Session Log section" {
    grep -q "## Session Log" "$TEMPLATE_FILE"
}

@test "template has Decisions section" {
    grep -q "## Decisions" "$TEMPLATE_FILE"
}

@test "template has Blockers section" {
    grep -q "## Blockers" "$TEMPLATE_FILE"
}

@test "template has Technical Debt section" {
    grep -q "## Technical Debt" "$TEMPLATE_FILE"
}

@test "template has Learnings section" {
    grep -q "## Learnings" "$TEMPLATE_FILE"
}

@test "template has Session Continuity section" {
    grep -q "## Session Continuity" "$TEMPLATE_FILE"
}

# =============================================================================
# Current Focus Section Tests
# =============================================================================

@test "Current Focus has Active Task field" {
    grep -q "Active Task" "$TEMPLATE_FILE"
}

@test "Current Focus has Status field" {
    grep -q "Status" "$TEMPLATE_FILE"
}

@test "Current Focus has Blocked By field" {
    grep -q "Blocked By" "$TEMPLATE_FILE"
}

@test "Current Focus has Next Action field" {
    grep -q "Next Action" "$TEMPLATE_FILE"
}

# =============================================================================
# Session Log Table Tests
# =============================================================================

@test "Session Log has table header" {
    grep -q "| Timestamp | Event | Outcome |" "$TEMPLATE_FILE"
}

@test "Session Log has table separator" {
    grep -q "|-----------|-------|---------|" "$TEMPLATE_FILE"
}

@test "Session Log has append-only comment" {
    grep -q "Append-only.*never delete" "$TEMPLATE_FILE"
}

# =============================================================================
# Decisions Table Tests
# =============================================================================

@test "Decisions has table header" {
    grep -q "| Date | Decision | Rationale | Decided By |" "$TEMPLATE_FILE"
}

@test "Decisions has table separator" {
    grep -q "|------|----------|-----------|------------|" "$TEMPLATE_FILE"
}

# =============================================================================
# Blockers Section Tests
# =============================================================================

@test "Blockers shows checkbox format" {
    grep -q "\- \[ \]" "$TEMPLATE_FILE"
}

@test "Blockers documents RESOLVED prefix" {
    grep -q "\[RESOLVED\]" "$TEMPLATE_FILE"
}

# =============================================================================
# Technical Debt Table Tests
# =============================================================================

@test "Technical Debt has table header" {
    grep -q "| ID | Description | Severity | Found By | Sprint |" "$TEMPLATE_FILE"
}

@test "Technical Debt has table separator" {
    grep -q "|----|-------------|----------|----------|--------|" "$TEMPLATE_FILE"
}

@test "Technical Debt shows TD-NNN format" {
    grep -q "TD-001" "$TEMPLATE_FILE"
}

# =============================================================================
# Session Continuity Section Tests
# =============================================================================

@test "Session Continuity has Active Context subsection" {
    grep -q "### Active Context" "$TEMPLATE_FILE"
}

@test "Session Continuity has Lightweight Identifiers subsection" {
    grep -q "### Lightweight Identifiers" "$TEMPLATE_FILE"
}

@test "Session Continuity has Pending Questions subsection" {
    grep -q "### Pending Questions" "$TEMPLATE_FILE"
}

@test "Session Continuity references PROJECT_ROOT" {
    grep -q '\${PROJECT_ROOT}' "$TEMPLATE_FILE"
}

@test "Session Continuity references session-continuity.md protocol" {
    grep -q "session-continuity.md" "$TEMPLATE_FILE"
}

# =============================================================================
# Protocol Required Sections Tests
# =============================================================================

@test "protocol documents Required Sections" {
    grep -q "Required Sections" "$PROTOCOL_FILE"
}

@test "protocol documents Current Focus format" {
    grep -q "Current Focus" "$PROTOCOL_FILE"
}

@test "protocol documents Session Log format" {
    grep -q "Session Log" "$PROTOCOL_FILE"
}

@test "protocol documents Decisions format" {
    grep -q "Decisions" "$PROTOCOL_FILE"
}

@test "protocol documents Blockers format" {
    grep -q "Blockers" "$PROTOCOL_FILE"
}

@test "protocol documents Technical Debt format" {
    grep -q "Technical Debt" "$PROTOCOL_FILE"
}

@test "protocol documents Learnings format" {
    grep -q "Learnings" "$PROTOCOL_FILE"
}

# =============================================================================
# Protocol Agent Discipline Tests
# =============================================================================

@test "protocol documents Agent Discipline" {
    grep -q "Agent Discipline" "$PROTOCOL_FILE"
}

@test "protocol documents session start event" {
    grep -q "Session start" "$PROTOCOL_FILE"
}

@test "protocol documents decision made event" {
    grep -q "Decision made" "$PROTOCOL_FILE"
}

@test "protocol documents blocker hit event" {
    grep -q "Blocker hit" "$PROTOCOL_FILE"
}

@test "protocol documents blocker resolved event" {
    grep -q "Blocker resolved" "$PROTOCOL_FILE"
}

@test "protocol documents session end event" {
    grep -q "Session end" "$PROTOCOL_FILE"
}

@test "protocol documents mistake discovered event" {
    grep -q "Mistake discovered" "$PROTOCOL_FILE"
}

# =============================================================================
# Template Guidelines Tests
# =============================================================================

@test "template includes guidelines comment" {
    grep -q "SECTION GUIDELINES" "$TEMPLATE_FILE"
}

@test "template explains ISO 8601 timestamp format" {
    grep -q "ISO 8601" "$TEMPLATE_FILE"
}

@test "template explains severity levels" {
    grep -q "CRITICAL.*HIGH.*MEDIUM.*LOW" "$TEMPLATE_FILE"
}

# =============================================================================
# v0.16.0 Version Tests
# =============================================================================

@test "protocol mentions v0.16.0" {
    grep -q "v0.16.0" "$PROTOCOL_FILE"
}

@test "protocol mentions v0.9.0 session continuity" {
    grep -q "v0.9.0" "$PROTOCOL_FILE"
}
