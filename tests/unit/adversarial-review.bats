#!/usr/bin/env bats
# Tests for adversarial-review.sh — core functions
#
# Tests: validate_finding, severity_rank, secret_scan_content,
#        anchor validation, merge_findings, schema validation
#
# Uses source-based testing: sources the script functions directly
# for unit testing without invoking the full CLI.

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export PROJECT_ROOT
    ADVERSARIAL_REVIEW="$PROJECT_ROOT/.claude/scripts/adversarial-review.sh"
    FIXTURES_DIR="$PROJECT_ROOT/tests/fixtures/adversarial-review"
    TEST_DIR="${BATS_TEST_TMPDIR:-$(mktemp -d)}"

    # Save PROJECT_ROOT before sourcing (script redefines it)
    local saved_root="$PROJECT_ROOT"

    # Pre-source lib-content.sh so its functions are available even when the
    # eval'd script can't find it (BASH_SOURCE[0] resolves to bats tmp dir).
    # The double-source guard in lib-content.sh prevents duplicate loading.
    source "$PROJECT_ROOT/.claude/scripts/lib-content.sh"

    # Source the script functions (but don't run main)
    eval "$(sed 's/^main "\$@"/# main disabled for testing/' "$ADVERSARIAL_REVIEW")"

    # Restore our PROJECT_ROOT
    PROJECT_ROOT="$saved_root"
    export PROJECT_ROOT

    # Set defaults that load_adversarial_config would set
    CONF_ENABLED="true"
    CONF_MODEL="gpt-5.2-codex"
    CONF_TIMEOUT=60
    CONF_BUDGET_CENTS=150
    CONF_ESCALATION_ENABLED="true"
    CONF_SECONDARY_BUDGET=12000
    CONF_MAX_FILE_LINES=500
    CONF_MAX_FILE_BYTES=51200
    CONF_SECRET_SCANNING="true"
    CONF_SECRET_ALLOWLIST=()
}

# =============================================================================
# Script existence and basic validation
# =============================================================================

@test "adversarial-review.sh exists and is executable" {
    [[ -x "$ADVERSARIAL_REVIEW" ]]
}

@test "exits with code 2 when no arguments provided" {
    run "$ADVERSARIAL_REVIEW"
    [[ "$status" -eq 2 ]]
}

@test "exits with code 2 for invalid --type" {
    run "$ADVERSARIAL_REVIEW" --type invalid --sprint-id sprint-1 --diff-file /dev/null
    [[ "$status" -eq 2 ]]
}

@test "exits with code 2 when --diff-file missing" {
    run "$ADVERSARIAL_REVIEW" --type review --sprint-id sprint-1 --diff-file /nonexistent
    [[ "$status" -eq 2 ]]
}

# =============================================================================
# severity_rank (FR-3)
# =============================================================================

@test "severity_rank: CRITICAL=4" {
    result=$(severity_rank "CRITICAL")
    [[ "$result" == "4" ]]
}

@test "severity_rank: HIGH=3" {
    result=$(severity_rank "HIGH")
    [[ "$result" == "3" ]]
}

@test "severity_rank: BLOCKING=3" {
    result=$(severity_rank "BLOCKING")
    [[ "$result" == "3" ]]
}

@test "severity_rank: MEDIUM=2" {
    result=$(severity_rank "MEDIUM")
    [[ "$result" == "2" ]]
}

@test "severity_rank: ADVISORY=2" {
    result=$(severity_rank "ADVISORY")
    [[ "$result" == "2" ]]
}

@test "severity_rank: LOW=1" {
    result=$(severity_rank "LOW")
    [[ "$result" == "1" ]]
}

@test "severity_rank: unknown=0" {
    result=$(severity_rank "UNKNOWN")
    [[ "$result" == "0" ]]
}

# =============================================================================
# validate_finding (FR-4, SDD 4.3)
# =============================================================================

@test "validate_finding: accepts valid review finding" {
    local finding='{"id":"DISS-001","severity":"BLOCKING","category":"null-safety","description":"test","failure_mode":"crash"}'
    run validate_finding "$finding" "review"
    [[ "$status" -eq 0 ]]
}

@test "validate_finding: accepts valid audit finding" {
    local finding='{"id":"DISS-001","severity":"CRITICAL","category":"injection","description":"test","failure_mode":"exploit"}'
    run validate_finding "$finding" "audit"
    [[ "$status" -eq 0 ]]
}

@test "validate_finding: rejects missing severity" {
    local finding='{"id":"DISS-001","category":"injection","description":"test","failure_mode":"crash"}'
    run validate_finding "$finding" "review"
    [[ "$status" -ne 0 ]]
}

@test "validate_finding: rejects invalid severity for review" {
    local finding='{"id":"DISS-001","severity":"CRITICAL","category":"injection","description":"test","failure_mode":"crash"}'
    run validate_finding "$finding" "review"
    [[ "$status" -ne 0 ]]
}

@test "validate_finding: rejects invalid severity for audit" {
    local finding='{"id":"DISS-001","severity":"BLOCKING","category":"injection","description":"test","failure_mode":"crash"}'
    run validate_finding "$finding" "audit"
    [[ "$status" -ne 0 ]]
}

@test "validate_finding: rejects invalid category" {
    local finding='{"id":"DISS-001","severity":"BLOCKING","category":"invalid-cat","description":"test","failure_mode":"crash"}'
    run validate_finding "$finding" "review"
    [[ "$status" -ne 0 ]]
}

@test "validate_finding: rejects empty description" {
    local finding='{"id":"DISS-001","severity":"BLOCKING","category":"injection","description":"","failure_mode":"crash"}'
    run validate_finding "$finding" "review"
    [[ "$status" -ne 0 ]]
}

@test "validate_finding: rejects missing failure_mode" {
    local finding='{"id":"DISS-001","severity":"BLOCKING","category":"injection","description":"test"}'
    run validate_finding "$finding" "review"
    [[ "$status" -ne 0 ]]
}

@test "validate_finding: accepts all valid categories" {
    local categories=(injection authz data-loss null-safety concurrency type-error resource-leak error-handling spec-violation performance secrets xss ssrf deserialization crypto info-disclosure rate-limiting input-validation config other)
    for cat in "${categories[@]}"; do
        local finding="{\"id\":\"DISS-001\",\"severity\":\"BLOCKING\",\"category\":\"$cat\",\"description\":\"test\",\"failure_mode\":\"fail\"}"
        run validate_finding "$finding" "review"
        [[ "$status" -eq 0 ]] || { echo "Failed for category: $cat"; return 1; }
    done
}

# =============================================================================
# secret_scan_content (NFR-4)
# =============================================================================

@test "secret_scan: redacts AWS access keys" {
    local content="key=AKIAIOSFODNN7EXAMPLE1 is bad"
    result=$(secret_scan_content "$content")
    [[ "$result" == *"[REDACTED:aws_key]"* ]]
    [[ "$result" != *"AKIAIOSFODNN7EXAMPLE1"* ]]
}

@test "secret_scan: redacts private key headers" {
    local content="-----BEGIN RSA PRIVATE KEY-----"
    result=$(secret_scan_content "$content")
    [[ "$result" == *"[REDACTED:private_key]"* ]]
}

@test "secret_scan: redacts GitHub PATs" {
    local content="token=ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghij"
    result=$(secret_scan_content "$content")
    [[ "$result" == *"[REDACTED:github_pat]"* ]]
    [[ "$result" != *"ghp_ABCDEF"* ]]
}

@test "secret_scan: does NOT redact SHA-256 hashes" {
    local content="sha256:d44359609673a45268f453443a2657cef1d10caedb763483809d9d6473d34fe1"
    result=$(secret_scan_content "$content")
    [[ "$result" == *"d44359609673a45268f453443a2657cef1d10caedb763483809d9d6473d34fe1"* ]]
}

@test "secret_scan: does NOT redact UUIDs" {
    local content="id=550e8400-e29b-41d4-a716-446655440000"
    result=$(secret_scan_content "$content")
    [[ "$result" == *"550e8400-e29b-41d4-a716-446655440000"* ]]
}

@test "secret_scan: handles content with no secrets" {
    local content="function validateToken(token) { return true; }"
    result=$(secret_scan_content "$content")
    [[ "$result" == "$content" ]]
}

# =============================================================================
# Anchor Validation (FR-3, SDD Section 5)
# =============================================================================

@test "anchor_validation: valid anchor in diff" {
    local finding='{"id":"DISS-001","severity":"BLOCKING","category":"injection","anchor":"src/auth.ts:validateToken","anchor_type":"function","scope":"diff","description":"test","failure_mode":"crash"}'
    local diff_files="src/auth.ts"
    result=$(validate_anchor "$finding" "review" "$diff_files")
    local status
    status=$(echo "$result" | jq -r '.anchor_status')
    [[ "$status" == "valid" ]]
}

@test "anchor_validation: demotes anchorless BLOCKING to ADVISORY in review" {
    local finding='{"id":"DISS-001","severity":"BLOCKING","category":"injection","description":"test","failure_mode":"crash"}'
    local diff_files="src/auth.ts"
    result=$(validate_anchor "$finding" "review" "$diff_files")
    local sev status
    sev=$(echo "$result" | jq -r '.severity')
    status=$(echo "$result" | jq -r '.anchor_status')
    [[ "$sev" == "ADVISORY" ]]
    [[ "$status" == "unresolved" ]]
}

@test "anchor_validation: marks anchorless HIGH audit as needs_triage (D-010)" {
    local finding='{"id":"DISS-001","severity":"HIGH","category":"injection","description":"test","failure_mode":"crash"}'
    local diff_files="src/auth.ts"
    result=$(validate_anchor "$finding" "audit" "$diff_files")
    local sev status
    sev=$(echo "$result" | jq -r '.severity')
    status=$(echo "$result" | jq -r '.anchor_status')
    [[ "$sev" == "HIGH" ]]  # NOT demoted
    [[ "$status" == "needs_triage" ]]
}

@test "anchor_validation: validates cross-file with trigger_anchor in diff" {
    local finding='{"id":"DISS-001","severity":"BLOCKING","category":"authz","anchor":"src/middleware/auth.ts:checkPermission","anchor_type":"function","scope":"cross_file","trigger_anchor":"src/auth.ts:validateToken","cross_file_justification":"callee affected by caller change","description":"test","failure_mode":"bypass"}'
    local diff_files="src/auth.ts"
    result=$(validate_anchor "$finding" "review" "$diff_files")
    local status
    status=$(echo "$result" | jq -r '.anchor_status')
    [[ "$status" == "cross_file" ]]
}

@test "anchor_validation: demotes out-of-scope anchor" {
    local finding='{"id":"DISS-001","severity":"BLOCKING","category":"injection","anchor":"src/unrelated.ts:foo","anchor_type":"function","scope":"diff","description":"test","failure_mode":"crash"}'
    local diff_files="src/auth.ts"
    result=$(validate_anchor "$finding" "review" "$diff_files")
    local sev status
    sev=$(echo "$result" | jq -r '.severity')
    status=$(echo "$result" | jq -r '.anchor_status')
    [[ "$sev" == "ADVISORY" ]]
    [[ "$status" == "out_of_scope" ]]
}

@test "anchor_validation: classifies symbol anchor stability" {
    local finding='{"id":"DISS-001","severity":"BLOCKING","category":"injection","anchor":"src/auth.ts:validateToken","anchor_type":"function","scope":"diff","description":"test","failure_mode":"crash"}'
    local diff_files="src/auth.ts"
    result=$(validate_anchor "$finding" "review" "$diff_files")
    local stability
    stability=$(echo "$result" | jq -r '.anchor_stability')
    [[ "$stability" == "symbol" ]]
}

@test "anchor_validation: classifies hunk_header anchor stability" {
    local finding='{"id":"DISS-001","severity":"BLOCKING","category":"injection","anchor":"src/auth.ts:@@-42,6","anchor_type":"hunk","scope":"diff","description":"test","failure_mode":"crash"}'
    local diff_files="src/auth.ts"
    result=$(validate_anchor "$finding" "review" "$diff_files")
    local stability
    stability=$(echo "$result" | jq -r '.anchor_stability')
    [[ "$stability" == "hunk_header" ]]
}

@test "anchor_validation: skips enforcement for low-severity findings" {
    local finding='{"id":"DISS-001","severity":"ADVISORY","category":"performance","description":"test","failure_mode":"slow"}'
    local diff_files="src/auth.ts"
    result=$(validate_anchor "$finding" "review" "$diff_files")
    local status
    status=$(echo "$result" | jq -r '.anchor_status')
    [[ "$status" == "valid" ]]
}

# =============================================================================
# process_findings — 4-state machine (SDD Section 4.1)
# =============================================================================

@test "process_findings: STATE 1 — api_failure" {
    result=$(process_findings "" "review" "gpt-5.2-codex" "sprint-1" "3" "")
    local status
    status=$(echo "$result" | jq -r '.metadata.status')
    [[ "$status" == "api_failure" ]]
    # Review: degraded=false
    local degraded
    degraded=$(echo "$result" | jq -r '.metadata.degraded')
    [[ "$degraded" == "false" ]]
}

@test "process_findings: STATE 1 — api_failure sets degraded for audit" {
    result=$(process_findings "" "audit" "gpt-5.2-codex" "sprint-1" "3" "")
    local degraded
    degraded=$(echo "$result" | jq -r '.metadata.degraded')
    [[ "$degraded" == "true" ]]
}

@test "process_findings: STATE 2 — malformed_response" {
    local raw='{"content": "{\"suggestions\": [\"wrong format\"]}"}'
    result=$(process_findings "$raw" "review" "gpt-5.2-codex" "sprint-1" "0" "")
    local status
    status=$(echo "$result" | jq -r '.metadata.status')
    [[ "$status" == "malformed_response" ]]
}

@test "process_findings: STATE 3 — clean (empty findings)" {
    local raw='{"content": "{\"findings\": []}", "tokens_input": 100, "tokens_output": 50, "cost_usd": 0.01, "latency_ms": 500}'
    result=$(process_findings "$raw" "review" "gpt-5.2-codex" "sprint-1" "0" "")
    local status count
    status=$(echo "$result" | jq -r '.metadata.status')
    count=$(echo "$result" | jq '.findings | length')
    [[ "$status" == "clean" ]]
    [[ "$count" == "0" ]]
}

@test "process_findings: STATE 4 — reviewed with valid findings" {
    local findings_json
    findings_json=$(cat "$FIXTURES_DIR/valid-review-response.json")
    local raw
    raw=$(jq -n --arg c "$findings_json" '{"content": $c, "tokens_input": 1000, "tokens_output": 200, "cost_usd": 0.05, "latency_ms": 2000}')
    result=$(process_findings "$raw" "review" "gpt-5.2-codex" "sprint-1" "0" "src/auth.ts")
    local status count
    status=$(echo "$result" | jq -r '.metadata.status')
    count=$(echo "$result" | jq '.findings | length')
    [[ "$status" == "reviewed" ]]
    [[ "$count" == "2" ]]
}

@test "process_findings: rejects invalid findings in STATE 4" {
    local content='{"findings": [{"id":"DISS-001","severity":"INVALID","category":"injection","description":"test","failure_mode":"crash"}]}'
    local raw
    raw=$(jq -n --arg c "$content" '{"content": $c, "tokens_input": 100, "tokens_output": 50, "cost_usd": 0.01, "latency_ms": 500}')
    result=$(process_findings "$raw" "review" "gpt-5.2-codex" "sprint-1" "0" "src/auth.ts")
    local count
    count=$(echo "$result" | jq '.findings | length')
    [[ "$count" == "0" ]]
}

# =============================================================================
# merge_findings (SDD Section 5 — Dedup)
# =============================================================================

@test "merge_findings: adds dissenter findings when no existing" {
    local dissenter_json='{"findings":[{"id":"DISS-001","severity":"BLOCKING","category":"injection","anchor":"src/auth.ts:validateToken","description":"test","failure_mode":"crash"}]}'
    result=$(merge_findings "$dissenter_json" "")
    local count source
    count=$(echo "$result" | jq 'length')
    source=$(echo "$result" | jq -r '.[0].source')
    [[ "$count" == "1" ]]
    [[ "$source" == "dissenter" ]]
}

@test "merge_findings: max severity wins on duplicate" {
    # Create existing findings file
    local existing_file="$TEST_DIR/existing.json"
    # finding_id must match sha256("src/auth.ts:validateToken:injection")[0:8]
    local expected_fid
    expected_fid=$(printf 'src/auth.ts:validateToken:injection' | sha256sum | cut -c1-8)
    cat > "$existing_file" << EOF
{"findings":[{"id":"REV-001","severity":"ADVISORY","category":"injection","anchor":"src/auth.ts:validateToken","description":"possible issue","failure_mode":"maybe","finding_id":"${expected_fid}"}]}
EOF
    # Dissenter finding with same anchor+category but higher severity
    local dissenter_json='{"findings":[{"id":"DISS-001","severity":"BLOCKING","category":"injection","anchor":"src/auth.ts:validateToken","description":"confirmed issue","failure_mode":"crash"}]}'
    result=$(merge_findings "$dissenter_json" "$existing_file")
    local sev confirmed
    sev=$(echo "$result" | jq -r '.[0].severity')
    confirmed=$(echo "$result" | jq -r '.[0].note // "none"')
    [[ "$sev" == "BLOCKING" ]]
    [[ "$confirmed" == "Confirmed by cross-model review" ]]
}

@test "merge_findings: no-anchor findings treated as unique" {
    local dissenter_json='{"findings":[{"id":"DISS-001","severity":"ADVISORY","category":"injection","description":"test1","failure_mode":"crash"},{"id":"DISS-002","severity":"ADVISORY","category":"injection","description":"test2","failure_mode":"crash"}]}'
    result=$(merge_findings "$dissenter_json" "")
    local count
    count=$(echo "$result" | jq 'length')
    [[ "$count" == "2" ]]
}

# =============================================================================
# is_denied_file (context escalation denylist)
# =============================================================================

@test "denylist: blocks .pem files" {
    run is_denied_file "cert.pem"
    [[ "$status" -eq 0 ]]
}

@test "denylist: blocks .key files" {
    run is_denied_file "server.key"
    [[ "$status" -eq 0 ]]
}

@test "denylist: blocks .env files" {
    run is_denied_file ".env.production"
    [[ "$status" -eq 0 ]]
}

@test "denylist: allows normal source files" {
    run is_denied_file "src/auth.ts"
    [[ "$status" -ne 0 ]]
}

@test "denylist: allows shell scripts" {
    run is_denied_file "scripts/deploy.sh"
    [[ "$status" -ne 0 ]]
}

# =============================================================================
# Schema validation — adversarial-finding.schema.json
# =============================================================================

@test "schema: file exists and is valid JSON" {
    local schema="$PROJECT_ROOT/.claude/schemas/adversarial-finding.schema.json"
    [[ -f "$schema" ]]
    run jq empty "$schema"
    [[ "$status" -eq 0 ]]
}

@test "schema: documents both review and audit severities" {
    local schema="$PROJECT_ROOT/.claude/schemas/adversarial-finding.schema.json"
    # Check review severities
    run jq -e '.. | objects | select(.title == "Review severities") | .enum | contains(["BLOCKING","ADVISORY"])' "$schema"
    [[ "$status" -eq 0 ]]
    # Check audit severities
    run jq -e '.. | objects | select(.title == "Audit severities") | .enum | contains(["CRITICAL","HIGH","MEDIUM","LOW"])' "$schema"
    [[ "$status" -eq 0 ]]
}

@test "schema: includes trigger_anchor field" {
    local schema="$PROJECT_ROOT/.claude/schemas/adversarial-finding.schema.json"
    run jq -e '."$defs".finding.properties.trigger_anchor' "$schema"
    [[ "$status" -eq 0 ]]
}

@test "schema: includes anchor_status with needs_triage" {
    local schema="$PROJECT_ROOT/.claude/schemas/adversarial-finding.schema.json"
    run jq -e '."$defs".finding.properties.anchor_status.enum | contains(["needs_triage"])' "$schema"
    [[ "$status" -eq 0 ]]
}

@test "schema: metadata has 4-state status enum" {
    local schema="$PROJECT_ROOT/.claude/schemas/adversarial-finding.schema.json"
    run jq -e '."$defs".metadata.properties.status.enum | contains(["api_failure","malformed_response","clean","reviewed"])' "$schema"
    [[ "$status" -eq 0 ]]
}

@test "schema: category enum matches validate_finding" {
    local schema="$PROJECT_ROOT/.claude/schemas/adversarial-finding.schema.json"
    # Extract categories from schema
    local schema_cats
    schema_cats=$(jq -r '."$defs".finding.properties.category.enum | sort | join(",")' "$schema")
    # Expected categories (sorted)
    local expected="authz,concurrency,config,crypto,data-loss,deserialization,error-handling,info-disclosure,injection,input-validation,null-safety,other,performance,rate-limiting,resource-leak,secrets,spec-violation,ssrf,type-error,xss"
    [[ "$schema_cats" == "$expected" ]]
}

# =============================================================================
# Bridgebuilder Finding #1: lib-content.sh shared library
# =============================================================================

@test "lib-content: file_priority available from shared library" {
    # file_priority should be available via lib-content.sh (not inline)
    local pri
    pri=$(file_priority ".claude/scripts/adversarial-review.sh")
    [[ "$pri" == "0" ]]
}

@test "lib-content: estimate_tokens available from shared library" {
    local tokens
    tokens=$(estimate_tokens "hello world")
    [[ "$tokens" -ge 1 ]]
}

@test "lib-content: prepare_content available from shared library" {
    # Should pass through small content unchanged
    local result
    result=$(prepare_content "small diff content" 30000)
    [[ "$result" == "small diff content" ]]
}

# =============================================================================
# Bridgebuilder Finding #2: compute_finding_id consistency
# =============================================================================

@test "compute_finding_id: anchored finding produces 8-char hex" {
    local id
    id=$(compute_finding_id "src/auth.ts:validateToken" "injection")
    [[ ${#id} -eq 8 ]]
    [[ "$id" =~ ^[0-9a-f]{8}$ ]]
}

@test "compute_finding_id: no-anchor finding produces 8-char hex" {
    local id
    id=$(compute_finding_id "no_anchor" "injection" "0")
    [[ ${#id} -eq 8 ]]
    [[ "$id" =~ ^[0-9a-f]{8}$ ]]
}

@test "compute_finding_id: same inputs produce same hash (deterministic)" {
    local id1 id2
    id1=$(compute_finding_id "src/auth.ts:validateToken" "injection")
    id2=$(compute_finding_id "src/auth.ts:validateToken" "injection")
    [[ "$id1" == "$id2" ]]
}

@test "compute_finding_id: different anchors produce different hashes" {
    local id1 id2
    id1=$(compute_finding_id "src/auth.ts:validateToken" "injection")
    id2=$(compute_finding_id "src/db.ts:query" "injection")
    [[ "$id1" != "$id2" ]]
}

@test "compute_finding_id: different categories produce different hashes" {
    local id1 id2
    id1=$(compute_finding_id "src/auth.ts:validateToken" "injection")
    id2=$(compute_finding_id "src/auth.ts:validateToken" "xss")
    [[ "$id1" != "$id2" ]]
}

@test "compute_finding_id: no-anchor uses index for uniqueness" {
    local id1 id2
    id1=$(compute_finding_id "no_anchor" "injection" "0")
    id2=$(compute_finding_id "no_anchor" "injection" "1")
    [[ "$id1" != "$id2" ]]
}

# =============================================================================
# Bridgebuilder Finding #3: file-based secret scanning
# =============================================================================

@test "secret_scan: handles large content without ARG_MAX failure" {
    # Generate content larger than typical ARG_MAX (128KB+)
    # This would fail with the old printf-pipe approach
    local large_content
    large_content=$(dd if=/dev/urandom bs=1024 count=200 2>/dev/null | base64)
    result=$(secret_scan_content "$large_content")
    # Should return content unchanged (no secrets in random base64)
    [[ -n "$result" ]]
}

@test "secret_scan: temp files are cleaned up" {
    local content="AKIAIOSFODNN7EXAMPLE1 is a test key"
    local before_count after_count
    before_count=$(ls /tmp/tmp.* 2>/dev/null | wc -l || echo 0)
    result=$(secret_scan_content "$content")
    after_count=$(ls /tmp/tmp.* 2>/dev/null | wc -l || echo 0)
    # Should not leak temp files
    [[ "$after_count" -le "$before_count" ]]
}

# =============================================================================
# Bridgebuilder Finding #4: config allowlist wiring
# =============================================================================

@test "secret_scan: allowlist protects matching patterns from redaction" {
    # Set up allowlist to protect a specific pattern
    CONF_SECRET_ALLOWLIST=('[0-9a-f]{64}')
    local sha256="a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
    local content="hash=$sha256 and secret=AKIAIOSFODNN7EXAMPLE1"
    result=$(secret_scan_content "$content")
    # SHA-256 hash should survive (allowlisted)
    [[ "$result" == *"$sha256"* ]]
    # AWS key should still be redacted
    [[ "$result" == *"[REDACTED:aws_key]"* ]]
    # Reset
    CONF_SECRET_ALLOWLIST=()
}

@test "secret_scan: empty allowlist does not affect redaction" {
    CONF_SECRET_ALLOWLIST=()
    local content="key=AKIAIOSFODNN7EXAMPLE1"
    result=$(secret_scan_content "$content")
    [[ "$result" == *"[REDACTED:aws_key]"* ]]
}

# =============================================================================
# Bridgebuilder Finding #5: code-aware token estimation (bytes/3)
# =============================================================================

@test "estimate_tokens: uses bytes/3 for code content" {
    # 300 bytes should give ~100 tokens (300/3)
    local content
    content=$(printf '%0300d' 0)  # 300 bytes of zeros
    local tokens
    tokens=$(estimate_tokens "$content")
    [[ "$tokens" -eq 100 ]]
}

@test "estimate_tokens: conservative estimate (higher than bytes/4)" {
    # 1200 bytes: bytes/3 = 400, bytes/4 = 300
    local content
    content=$(printf '%01200d' 0)
    local tokens
    tokens=$(estimate_tokens "$content")
    # Should be 400 (bytes/3), not 300 (bytes/4)
    [[ "$tokens" -eq 400 ]]
}
