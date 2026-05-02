#!/usr/bin/env bats
# =============================================================================
# Tests for .claude/scripts/lib-provider-parse.sh — parse_provider_model_id
#
# Cycle-096 Sprint 1 Task 1.1 (closes Flatline v1.1 SKP-006).
# Source-based testing: sources the helper directly to introspect functions.
# Cross-language equivalence enforced by tests/integration/parser-cross-language.bats.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export PROJECT_ROOT
    LIB="$PROJECT_ROOT/.claude/scripts/lib-provider-parse.sh"
    # Reset double-source guard so each test gets a fresh source.
    unset _LIB_PROVIDER_PARSE_LOADED
    source "$LIB"
}

# --- Happy path ---

@test "parses simple provider:model-id" {
    parse_provider_model_id "anthropic:claude-opus-4-7" p m
    [ "$p" = "anthropic" ]
    [ "$m" = "claude-opus-4-7" ]
}

@test "parses bedrock inference profile (multiple dots, no trailing colon)" {
    parse_provider_model_id "bedrock:us.anthropic.claude-opus-4-7" p m
    [ "$p" = "bedrock" ]
    [ "$m" = "us.anthropic.claude-opus-4-7" ]
}

@test "parses bedrock model with colon-bearing suffix (Haiku 4.5 case)" {
    parse_provider_model_id "bedrock:us.anthropic.claude-haiku-4-5-20251001-v1:0" p m
    [ "$p" = "bedrock" ]
    [ "$m" = "us.anthropic.claude-haiku-4-5-20251001-v1:0" ]
}

@test "parses openai model with dots and dashes" {
    parse_provider_model_id "openai:gpt-5.5-pro" p m
    [ "$p" = "openai" ]
    [ "$m" = "gpt-5.5-pro" ]
}

@test "parses google preview model" {
    parse_provider_model_id "google:gemini-3.1-pro-preview" p m
    [ "$p" = "google" ]
    [ "$m" = "gemini-3.1-pro-preview" ]
}

@test "preserves multiple colons in model_id (split on FIRST only)" {
    parse_provider_model_id "provider:multi:colon:value" p m
    [ "$p" = "provider" ]
    [ "$m" = "multi:colon:value" ]
}

# --- Error path ---

@test "rejects empty input" {
    run parse_provider_model_id "" p m
    [ "$status" -eq 2 ]
    [[ "$output" == *"empty input"* ]]
}

@test "rejects empty provider half (':model-id')" {
    run parse_provider_model_id ":claude-opus-4-7" p m
    [ "$status" -eq 2 ]
    [[ "$output" == *"empty provider"* ]]
}

@test "rejects empty model_id half ('provider:')" {
    run parse_provider_model_id "anthropic:" p m
    [ "$status" -eq 2 ]
    [[ "$output" == *"empty model_id"* ]]
}

@test "rejects missing colon" {
    run parse_provider_model_id "no-colon-at-all" p m
    [ "$status" -eq 2 ]
    [[ "$output" == *"missing colon"* ]]
}

@test "rejects missing output variable arguments" {
    run parse_provider_model_id "anthropic:claude-opus-4-7"
    [ "$status" -eq 2 ]
    [[ "$output" == *"usage:"* ]]
}

@test "rejects single output variable argument" {
    run parse_provider_model_id "anthropic:claude-opus-4-7" p
    [ "$status" -eq 2 ]
    [[ "$output" == *"usage:"* ]]
}

# --- Idempotency / reuse ---

@test "double-source is idempotent (no side effects)" {
    source "$LIB"
    source "$LIB"
    parse_provider_model_id "anthropic:claude-opus-4-7" p m
    [ "$p" = "anthropic" ]
    [ "$m" = "claude-opus-4-7" ]
}

@test "successive calls with different inputs do not bleed state" {
    parse_provider_model_id "anthropic:opus" p1 m1
    parse_provider_model_id "openai:gpt-5.5" p2 m2
    [ "$p1" = "anthropic" ]
    [ "$m1" = "opus" ]
    [ "$p2" = "openai" ]
    [ "$m2" = "gpt-5.5" ]
}

@test "out vars can be reused across calls" {
    parse_provider_model_id "anthropic:opus" p m
    [ "$p" = "anthropic" ]
    parse_provider_model_id "openai:gpt-5.5" p m
    [ "$p" = "openai" ]
    [ "$m" = "gpt-5.5" ]
}

# --- Bedrock-specific Day-1 model IDs (from Sprint 0 G-S0-2 probe captures) ---

@test "Day-1: us.anthropic.claude-opus-4-7 (no version suffix)" {
    parse_provider_model_id "bedrock:us.anthropic.claude-opus-4-7" p m
    [ "$p" = "bedrock" ]
    [ "$m" = "us.anthropic.claude-opus-4-7" ]
}

@test "Day-1: us.anthropic.claude-sonnet-4-6 (no version suffix)" {
    parse_provider_model_id "bedrock:us.anthropic.claude-sonnet-4-6" p m
    [ "$p" = "bedrock" ]
    [ "$m" = "us.anthropic.claude-sonnet-4-6" ]
}

@test "Day-1: us.anthropic.claude-haiku-4-5-20251001-v1:0 (datestamp + colon-bearing suffix)" {
    parse_provider_model_id "bedrock:us.anthropic.claude-haiku-4-5-20251001-v1:0" p m
    [ "$p" = "bedrock" ]
    [ "$m" = "us.anthropic.claude-haiku-4-5-20251001-v1:0" ]
}

@test "Day-1: global.anthropic.claude-opus-4-7 (alternative inference profile namespace)" {
    parse_provider_model_id "bedrock:global.anthropic.claude-opus-4-7" p m
    [ "$p" = "bedrock" ]
    [ "$m" = "global.anthropic.claude-opus-4-7" ]
}
