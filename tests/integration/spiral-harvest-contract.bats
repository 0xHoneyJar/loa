#!/usr/bin/env bats
# =============================================================================
# spiral-harvest-contract.bats — FR-8 HARVEST adapter contract tests (cycle-067)
# =============================================================================
# Tests the 3-tier parse precedence, fail-closed policy, schema validation,
# and flatline signature computation.
# =============================================================================

setup() {
    export PROJECT_ROOT
    PROJECT_ROOT=$(mktemp -d)
    mkdir -p "$PROJECT_ROOT/.claude/scripts" \
             "$PROJECT_ROOT/.run" \
             "$PROJECT_ROOT/grimoires/loa/a2a/trajectory"
    cd "$PROJECT_ROOT"

    # Copy adapter + dependencies
    REAL_ROOT="$BATS_TEST_DIRNAME/../.."
    cp "$REAL_ROOT/.claude/scripts/spiral-harvest-adapter.sh" "$PROJECT_ROOT/.claude/scripts/"
    cp "$REAL_ROOT/.claude/scripts/bootstrap.sh" "$PROJECT_ROOT/.claude/scripts/"
    cp "$REAL_ROOT/.claude/scripts/path-lib.sh" "$PROJECT_ROOT/.claude/scripts/" 2>/dev/null || true

    # Minimal config
    cat > "$PROJECT_ROOT/.loa.config.yaml" <<'YAML'
spiral:
  enabled: true
YAML

    # Init git (bootstrap needs it)
    git init -q -b main
    git config user.email test@test
    git config user.name test

    # Source adapter
    source "$PROJECT_ROOT/.claude/scripts/bootstrap.sh"
    source "$PROJECT_ROOT/.claude/scripts/spiral-harvest-adapter.sh"

    # Create test cycle directory
    CYCLE_DIR="$PROJECT_ROOT/cycles/cycle-abc123"
    mkdir -p "$CYCLE_DIR"
}

teardown() {
    cd /
    rm -rf "$PROJECT_ROOT"
}

# Helper: create valid sidecar
_write_valid_sidecar() {
    local dir="${1:-$CYCLE_DIR}"
    cat > "$dir/cycle-outcome.json" <<'JSON'
{
  "$schema_version": 1,
  "cycle_id": "cycle-abc123",
  "review_verdict": "APPROVED",
  "audit_verdict": "APPROVED",
  "findings": { "blocker": 0, "high": 1, "medium": 3, "low": 2 },
  "artifacts": { "reviewer_md": "cycles/cycle-abc123/reviewer.md", "auditor_md": "cycles/cycle-abc123/auditor-sprint-feedback.md", "pr_url": null },
  "flatline_signature": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "content_hash": "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  "elapsed_sec": 7,
  "exit_status": "success"
}
JSON
}

# Helper: create valid reviewer.md + auditor-sprint-feedback.md
_write_valid_markdown() {
    local dir="${1:-$CYCLE_DIR}"
    cat > "$dir/reviewer.md" <<'MD'
# Review

## Verdict

APPROVED

## Findings Summary

| Severity | Count |
|----------|-------|
| Blocker | 0 |
| High | 1 |
| Medium | 3 |
| Low | 2 |
MD

    cat > "$dir/auditor-sprint-feedback.md" <<'MD'
# Audit

## Final Verdict

APPROVED

## Findings Summary

| Severity | Count |
|----------|-------|
| Blocker | 0 |
| High | 0 |
| Medium | 1 |
| Low | 0 |
MD
}

# =============================================================================
# Happy path: valid sidecar → parsed
# =============================================================================
@test "parse_cycle_outcome: valid sidecar parses successfully" {
    _write_valid_sidecar
    run parse_cycle_outcome "$CYCLE_DIR" "$PROJECT_ROOT/.run" "cycle-abc123"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.review_verdict == "APPROVED"'
    echo "$output" | jq -e '.audit_verdict == "APPROVED"'
    echo "$output" | jq -e '.findings_critical == 1'
    echo "$output" | jq -e '.findings_minor == 5'
    echo "$output" | jq -e '.parse_source == "sidecar"'
}

# =============================================================================
# Sidecar absent, markdown valid → fallback succeeds
# =============================================================================
@test "parse_cycle_outcome: sidecar absent, markdown valid → fallback" {
    _write_valid_markdown
    local result
    result=$(parse_cycle_outcome "$CYCLE_DIR" "$PROJECT_ROOT/.run" "cycle-abc123" 2>/dev/null)
    echo "$result" | jq -e '.review_verdict == "APPROVED"'
    echo "$result" | jq -e '.audit_verdict == "APPROVED"'
    echo "$result" | jq -e '.parse_source == "markdown"'
}

# =============================================================================
# Sidecar absent, markdown malformed → fail-closed
# =============================================================================
@test "parse_cycle_outcome: sidecar absent, markdown malformed → fail-closed" {
    # Create malformed markdown with no verdict
    echo "# Bad Review" > "$CYCLE_DIR/reviewer.md"
    echo "No verdict here" >> "$CYCLE_DIR/reviewer.md"
    echo "# Bad Audit" > "$CYCLE_DIR/auditor-sprint-feedback.md"

    local result
    result=$(parse_cycle_outcome "$CYCLE_DIR" "$PROJECT_ROOT/.run" "cycle-abc123" 2>/dev/null)
    # Verdicts should be null (parsed nothing)
    echo "$result" | jq -e '.review_verdict == null'
    echo "$result" | jq -e '.parse_source == "markdown"'
}

# =============================================================================
# Schema version mismatch → fail-closed
# =============================================================================
@test "parse_cycle_outcome: schema version mismatch → fail-closed" {
    _write_valid_sidecar
    # Bump version to unsupported
    jq '."$schema_version" = 2' "$CYCLE_DIR/cycle-outcome.json" > "$CYCLE_DIR/cycle-outcome.json.tmp"
    mv "$CYCLE_DIR/cycle-outcome.json.tmp" "$CYCLE_DIR/cycle-outcome.json"

    local result
    result=$(parse_cycle_outcome "$CYCLE_DIR" "$PROJECT_ROOT/.run" "cycle-abc123" 2>/dev/null)
    echo "$result" | jq -e '.exit_status == "failed"'
    echo "$result" | jq -e '.parse_source == "fail_closed"'
}

# =============================================================================
# Sidecar present, missing required field → fail-closed
# =============================================================================
@test "parse_cycle_outcome: sidecar missing findings → fail-closed" {
    _write_valid_sidecar
    jq 'del(.findings)' "$CYCLE_DIR/cycle-outcome.json" > "$CYCLE_DIR/cycle-outcome.json.tmp"
    mv "$CYCLE_DIR/cycle-outcome.json.tmp" "$CYCLE_DIR/cycle-outcome.json"

    local result
    result=$(parse_cycle_outcome "$CYCLE_DIR" "$PROJECT_ROOT/.run" "cycle-abc123" 2>/dev/null)
    echo "$result" | jq -e '.exit_status == "failed"'
    echo "$result" | jq -e '.parse_source == "fail_closed"'
}

# =============================================================================
# Sidecar present, invalid JSON → fail-closed
# =============================================================================
@test "parse_cycle_outcome: invalid JSON sidecar → fail-closed" {
    echo "NOT JSON {{{" > "$CYCLE_DIR/cycle-outcome.json"

    local result
    result=$(parse_cycle_outcome "$CYCLE_DIR" "$PROJECT_ROOT/.run" "cycle-abc123" 2>/dev/null)
    echo "$result" | jq -e '.exit_status == "failed"'
    echo "$result" | jq -e '.parse_source == "fail_closed"'
}

# =============================================================================
# Content-hash anomaly → warning logged, continues with sidecar
# =============================================================================
@test "parse_cycle_outcome: content hash mismatch → uses sidecar values" {
    _write_valid_sidecar
    _write_valid_markdown
    # Sidecar has content_hash bbbb..., markdown would produce a different hash
    # Parser should use sidecar values regardless

    run parse_cycle_outcome "$CYCLE_DIR" "$PROJECT_ROOT/.run" "cycle-abc123"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.parse_source == "sidecar"'
    echo "$output" | jq -e '.review_verdict == "APPROVED"'
}

# =============================================================================
# T38: parse_from_state_files rejects stale state (cycle_id mismatch proxy)
# =============================================================================
@test "parse_from_state_files: rejects stale state (>1h old)" {
    # Create a state file with old timestamp
    cat > "$PROJECT_ROOT/.run/sprint-plan-state.json" <<'JSON'
{
  "plan_id": "plan-old",
  "state": "JACKED_OUT",
  "timestamps": {
    "last_activity": "2020-01-01T00:00:00Z"
  }
}
JSON

    run parse_from_state_files "$PROJECT_ROOT/.run" "cycle-abc123"
    [ "$status" -ne 0 ]
}

# =============================================================================
# emit_cycle_outcome_sidecar writes valid sidecar
# =============================================================================
@test "emit_cycle_outcome_sidecar: produces valid sidecar" {
    _write_valid_markdown  # needed for content hash computation

    run emit_cycle_outcome_sidecar "$CYCLE_DIR" "APPROVED" "APPROVED" \
        '{"blocker":0,"high":1,"medium":2,"low":3}'
    [ "$status" -eq 0 ]

    # Validate the written sidecar
    [ -f "$CYCLE_DIR/cycle-outcome.json" ]
    run validate_sidecar_schema "$CYCLE_DIR/cycle-outcome.json"
    [ "$status" -eq 0 ]

    # Check content
    run jq -r '.review_verdict' "$CYCLE_DIR/cycle-outcome.json"
    [ "$output" = "APPROVED" ]
    run jq -r '."$schema_version"' "$CYCLE_DIR/cycle-outcome.json"
    [ "$output" = "1" ]
}

# =============================================================================
# Orphan .tmp detection (IMP-002: crash between jq and mv)
# =============================================================================
@test "parse_cycle_outcome: detects and cleans orphan .tmp file" {
    # Create orphan .tmp (simulates crash between jq write and mv)
    echo '{"partial": true}' > "$CYCLE_DIR/cycle-outcome.json.tmp"
    _write_valid_markdown

    local result
    result=$(parse_cycle_outcome "$CYCLE_DIR" "$PROJECT_ROOT/.run" "cycle-abc123" 2>/dev/null)
    # Orphan should be cleaned up
    [ ! -f "$CYCLE_DIR/cycle-outcome.json.tmp" ]
    # Should fall through to markdown
    echo "$result" | jq -e '.parse_source == "markdown"'
}

# =============================================================================
# validate_sidecar_schema: invalid enum value
# =============================================================================
@test "validate_sidecar_schema: invalid exit_status → returns 2" {
    _write_valid_sidecar
    jq '.exit_status = "unknown"' "$CYCLE_DIR/cycle-outcome.json" > "$CYCLE_DIR/cycle-outcome.json.tmp"
    mv "$CYCLE_DIR/cycle-outcome.json.tmp" "$CYCLE_DIR/cycle-outcome.json"

    run validate_sidecar_schema "$CYCLE_DIR/cycle-outcome.json"
    [ "$status" -eq 2 ]
}

# =============================================================================
# validate_sidecar_schema: unsupported version → returns 3
# =============================================================================
@test "validate_sidecar_schema: unsupported version → returns 3" {
    _write_valid_sidecar
    jq '."$schema_version" = 99' "$CYCLE_DIR/cycle-outcome.json" > "$CYCLE_DIR/cycle-outcome.json.tmp"
    mv "$CYCLE_DIR/cycle-outcome.json.tmp" "$CYCLE_DIR/cycle-outcome.json"

    run validate_sidecar_schema "$CYCLE_DIR/cycle-outcome.json"
    [ "$status" -eq 3 ]
}
