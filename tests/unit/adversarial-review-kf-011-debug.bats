#!/usr/bin/env bats
# Tests for adversarial-review.sh — KF-011 debug capture (issue #930).
#
# Verifies:
#   - When LOA_ADVERSARIAL_DEBUG=1 AND status: malformed_response,
#     a sidecar file is written to grimoires/loa/a2a/{sprint_id}/
#   - When LOA_ADVERSARIAL_DEBUG unset (default), NO sidecar is written
#   - When LOA_ADVERSARIAL_DEBUG=1 but response is well-formed (state: clean
#     or populated), NO debug sidecar is written
#   - The sidecar passes through log-redactor (NFR-Sec-1)

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export PROJECT_ROOT
    ADVERSARIAL_REVIEW="$PROJECT_ROOT/.claude/scripts/adversarial-review.sh"
    TEST_DIR="${BATS_TEST_TMPDIR:-$(mktemp -d)}"

    # Sandbox the sprint dir so we don't pollute the real grimoires tree.
    # The sidecar is written under $PROJECT_ROOT/grimoires/loa/a2a/$sprint_id,
    # so we override PROJECT_ROOT to a tmp tree for each test.
    SANDBOX_ROOT="$TEST_DIR/sandbox"
    mkdir -p "$SANDBOX_ROOT/.claude/scripts/lib"
    # Copy the redactor so process_findings can find it under sandbox PROJECT_ROOT.
    cp "$PROJECT_ROOT/.claude/scripts/lib/log-redactor.sh" "$SANDBOX_ROOT/.claude/scripts/lib/"
    chmod +x "$SANDBOX_ROOT/.claude/scripts/lib/log-redactor.sh"

    local saved_root="$PROJECT_ROOT"
    source "$PROJECT_ROOT/.claude/scripts/lib-content.sh"
    eval "$(sed 's/^main "\$@"/# main disabled for testing/' "$ADVERSARIAL_REVIEW")"

    PROJECT_ROOT="$SANDBOX_ROOT"
    export PROJECT_ROOT

    SPRINT_ID="sprint-kf011-test"
    SIDECAR_DIR="$SANDBOX_ROOT/grimoires/loa/a2a/$SPRINT_ID"
}

teardown() {
    unset LOA_ADVERSARIAL_DEBUG
}

# Build a synthetic model-adapter envelope where the .content does NOT
# contain a 'findings' key. process_findings should bucket this as
# malformed_response.
_malformed_envelope() {
    jq -n '{
        content: "Sorry, I cannot review this without more context. The review object should contain a list of issues but instead I will explain my reasoning.",
        model: "openai:gpt-5.5-pro",
        cost_cents: 12
    }'
}

# Build a well-formed envelope.
_well_formed_envelope() {
    jq -n '{
        content: "{\"findings\": []}",
        model: "openai:gpt-5.5-pro",
        cost_cents: 8
    }'
}

# Build a well-formed envelope with populated findings.
_populated_envelope() {
    jq -n '{
        content: "{\"findings\": [{\"id\": \"X\", \"severity\": \"MEDIUM\", \"category\": \"quality\", \"summary\": \"test\", \"detail\": \"test\", \"file\": \"foo.sh\", \"line\": 1, \"anchor\": \"echo hi\"}]}",
        model: "openai:gpt-5.5-pro",
        cost_cents: 8
    }'
}

@test "KF-011 debug: LOA_ADVERSARIAL_DEBUG=1 + malformed → sidecar written" {
    export LOA_ADVERSARIAL_DEBUG=1
    raw=$(_malformed_envelope)

    result=$(process_findings "$raw" "review" "openai:gpt-5.5-pro" "$SPRINT_ID" "0" "" 2>/dev/null)
    status_val=$(echo "$result" | jq -r '.metadata.status' 2>/dev/null)
    [ "$status_val" = "malformed_response" ]

    # Sidecar must exist
    [ -d "$SIDECAR_DIR" ]
    sidecar_count=$( (ls -1 "$SIDECAR_DIR"/adversarial-debug-*.txt 2>/dev/null || true) | wc -l )
    [ "$sidecar_count" -ge 1 ]
}

@test "KF-011 debug: LOA_ADVERSARIAL_DEBUG unset + malformed → NO sidecar" {
    unset LOA_ADVERSARIAL_DEBUG
    raw=$(_malformed_envelope)

    result=$(process_findings "$raw" "review" "openai:gpt-5.5-pro" "$SPRINT_ID" "0" "" 2>/dev/null)
    status_val=$(echo "$result" | jq -r '.metadata.status' 2>/dev/null)
    [ "$status_val" = "malformed_response" ]

    # NO debug sidecar should exist (the dir may exist from other sidecars,
    # but no adversarial-debug-* file)
    sidecar_count=$( (ls -1 "$SIDECAR_DIR"/adversarial-debug-*.txt 2>/dev/null || true) | wc -l )
    [ "$sidecar_count" -eq 0 ]
}

@test "KF-011 debug: LOA_ADVERSARIAL_DEBUG=1 + well-formed empty → NO sidecar" {
    export LOA_ADVERSARIAL_DEBUG=1
    raw=$(_well_formed_envelope)

    result=$(process_findings "$raw" "review" "openai:gpt-5.5-pro" "$SPRINT_ID" "0" "" 2>/dev/null)
    status_val=$(echo "$result" | jq -r '.metadata.status' 2>/dev/null)
    [ "$status_val" = "clean" ]

    sidecar_count=$( (ls -1 "$SIDECAR_DIR"/adversarial-debug-*.txt 2>/dev/null || true) | wc -l )
    [ "$sidecar_count" -eq 0 ]
}

@test "KF-011 debug: LOA_ADVERSARIAL_DEBUG=1 + populated findings → NO sidecar" {
    export LOA_ADVERSARIAL_DEBUG=1
    raw=$(_populated_envelope)

    result=$(process_findings "$raw" "review" "openai:gpt-5.5-pro" "$SPRINT_ID" "0" "" 2>/dev/null)
    # Status should be clean or some populated state — not malformed
    status_val=$(echo "$result" | jq -r '.metadata.status' 2>/dev/null)
    [ "$status_val" != "malformed_response" ]

    sidecar_count=$( (ls -1 "$SIDECAR_DIR"/adversarial-debug-*.txt 2>/dev/null || true) | wc -l )
    [ "$sidecar_count" -eq 0 ]
}

@test "KF-011 debug: sidecar applies log-redactor (no AKIA leak)" {
    export LOA_ADVERSARIAL_DEBUG=1
    # Inject an AKIA-shape secret into the malformed content. Log-redactor
    # should scrub it before write.
    fake_secret="AKIA1234567890ABCDEF"
    raw=$(jq -n --arg secret "$fake_secret" '{
        content: "I refuse to produce findings, but here is an AWS key for testing: \($secret)",
        model: "openai:gpt-5.5-pro",
        cost_cents: 5
    }')

    result=$(process_findings "$raw" "review" "openai:gpt-5.5-pro" "$SPRINT_ID" "0" "" 2>/dev/null)
    status_val=$(echo "$result" | jq -r '.metadata.status' 2>/dev/null)
    [ "$status_val" = "malformed_response" ]

    sidecar=$(find "$SIDECAR_DIR" -name "adversarial-debug-*.txt" 2>/dev/null | head -1)
    [ -n "$sidecar" ]
    [ -f "$sidecar" ]
    # AKIA-shape must NOT appear verbatim in the sidecar
    if grep -q "$fake_secret" "$sidecar"; then
        echo "REDACTION FAILURE: $fake_secret leaked into $sidecar"
        cat "$sidecar"
        false
    fi
    # And the redaction marker should be present
    grep -q "REDACTED-AKIA" "$sidecar"
}

# ============================================================================
# KF-011 PARSER FIX (closes the malformed_response on prose-prefixed JSON)
# ============================================================================

@test "KF-011 fix: prose preamble + JSON envelope is correctly extracted" {
    # Verbatim shape from the 2026-05-17 capture
    # (grimoires/loa/a2a/sprint-kf011-repro-large/adversarial-debug-gpt-5.5-pro-*.txt):
    # model emits "Using the `ubs` review skill because... I'll keep...\n{findings:[...]}"
    raw=$(jq -n '{
        content: "Using the `ubs` review skill because this is a bug-focused adversarial review. I’ll keep the final response to the requested JSON shape.\n{\"findings\":[{\"id\":\"DISS-001\",\"severity\":\"BLOCKING\",\"category\":\"spec-violation\",\"summary\":\"missing arg form\",\"detail\":\"shim does not recognize --foo=bar\",\"file\":\"tools/example.sh\",\"line\":10,\"anchor\":\"echo hi\"}]}",
        model: "openai:gpt-5.5-pro",
        cost_cents: 12
    }')

    result=$(process_findings "$raw" "review" "openai:gpt-5.5-pro" "$SPRINT_ID" "0" "" 2>/dev/null)
    status_val=$(echo "$result" | jq -r '.metadata.status' 2>/dev/null)
    # Must NOT be malformed_response — the fix extracted the JSON envelope
    [ "$status_val" != "malformed_response" ]
    # Should be either "reviewed" (with findings) or "clean" (empty findings)
    case "$status_val" in
        reviewed|clean) ;;
        *)
            echo "unexpected status: $status_val"
            echo "result: $result" >&3
            false
            ;;
    esac
}

@test "KF-011 fix: prose preamble + JSON does NOT fire debug capture" {
    # When the parser fix successfully extracts, the malformed_response branch
    # is not entered, so LOA_ADVERSARIAL_DEBUG=1 should NOT write a sidecar.
    export LOA_ADVERSARIAL_DEBUG=1
    raw=$(jq -n '{
        content: "I will produce JSON now:\n{\"findings\":[]}",
        model: "openai:gpt-5.5-pro"
    }')
    result=$(process_findings "$raw" "review" "openai:gpt-5.5-pro" "$SPRINT_ID" "0" "" 2>/dev/null)
    status_val=$(echo "$result" | jq -r '.metadata.status' 2>/dev/null)
    [ "$status_val" != "malformed_response" ]
    sidecar_count=$( (ls -1 "$SIDECAR_DIR"/adversarial-debug-*.txt 2>/dev/null || true) | wc -l )
    [ "$sidecar_count" -eq 0 ]
}

@test "KF-011 fix: refusal-only content (no JSON anywhere) is still malformed" {
    # Negative control: when model truly refuses with no JSON, the fix should
    # NOT manufacture one. The state should remain malformed_response so the
    # diagnostic capture continues to fire.
    raw=$(jq -n '{
        content: "I cannot review this content as it contains sensitive information.",
        model: "openai:gpt-5.5-pro"
    }')
    result=$(process_findings "$raw" "review" "openai:gpt-5.5-pro" "$SPRINT_ID" "0" "" 2>/dev/null)
    status_val=$(echo "$result" | jq -r '.metadata.status' 2>/dev/null)
    [ "$status_val" = "malformed_response" ]
}

@test "KF-011 fix: nested JSON envelope (other top-level fields besides findings) extracts findings" {
    # Some models may return {review: {findings:[]}} or include findings as a
    # nested key. The fix uses raw_decode which expects the OUTER object to
    # contain "findings" — verify this works when "findings" is at top level
    # alongside other fields.
    raw=$(jq -n '{
        content: "Here is my analysis:\n{\"findings\":[{\"id\":\"X\",\"severity\":\"MEDIUM\",\"category\":\"quality\",\"summary\":\"s\",\"detail\":\"d\",\"file\":\"f\",\"line\":1,\"anchor\":\"a\"}],\"metadata_extra\":\"ignored\",\"model_thoughts\":\"some reasoning\"}",
        model: "openai:gpt-5.5-pro"
    }')
    result=$(process_findings "$raw" "review" "openai:gpt-5.5-pro" "$SPRINT_ID" "0" "" 2>/dev/null)
    status_val=$(echo "$result" | jq -r '.metadata.status' 2>/dev/null)
    [ "$status_val" != "malformed_response" ]
}

@test "KF-011 fix: markdown code fence wrapping the JSON still works (regression: existing behavior)" {
    # The existing ```json fence extraction should still work — the new
    # Python fallback only kicks in when fence extraction + direct parse both fail.
    raw=$(jq -n '{
        content: "```json\n{\"findings\":[]}\n```",
        model: "openai:gpt-5.5-pro"
    }')
    result=$(process_findings "$raw" "review" "openai:gpt-5.5-pro" "$SPRINT_ID" "0" "" 2>/dev/null)
    status_val=$(echo "$result" | jq -r '.metadata.status' 2>/dev/null)
    [ "$status_val" = "clean" ]
}

@test "KF-011 debug: filename slugs colon in model id" {
    export LOA_ADVERSARIAL_DEBUG=1
    raw=$(_malformed_envelope)

    result=$(process_findings "$raw" "review" "openai:gpt-5.5-pro" "$SPRINT_ID" "0" "" 2>/dev/null)
    [ -n "$result" ]

    # No file should have a `:` in its name (sanitized to `__`)
    bad_count=$( (ls -1 "$SIDECAR_DIR"/*:* 2>/dev/null || true) | wc -l )
    [ "$bad_count" -eq 0 ]

    # And the expected slug (provider__model_id) should be present
    expected_slug_count=$( (ls -1 "$SIDECAR_DIR"/adversarial-debug-openai__gpt-5.5-pro-*.txt 2>/dev/null || true) | wc -l )
    [ "$expected_slug_count" -ge 1 ]
}
