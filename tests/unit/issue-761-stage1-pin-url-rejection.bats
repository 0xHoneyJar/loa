#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# =============================================================================
# tests/unit/issue-761-stage1-pin-url-rejection.bats
#
# Issue #761: `_stage1_explicit_pin` partitions skill_models.<skill>.<role>
# values at the first `:`. If an operator pastes a URL like
# `https://user:secret@host?api_key=v` into that field, the resolver treats
# `https` as the provider and the rest as model_id. The redactor masks
# userinfo in `details.pin` (full URL with `://` framing), but
# `resolved_model_id` carries `//user:secret@...` (no `://` anchor) which
# the redactor's regex doesn't catch — secret leaks to validate-bindings
# JSON output.
#
# Fix: S1 rejects values containing `://`, leading `//`, or `?` (URL
# sentinels). Operators still get a clear `provider:model_id` pin path; URL-
# shaped misconfiguration falls through to S2 → S3 → [TIER-NO-MAPPING].
#
# Tests:
#   P1 — positive control: valid `provider:model_id` pin still resolves at S1
#   P2 — pin with simple alphanumeric model_id (no special chars) works
#   P3 — pin with dot in model_id (e.g. claude-opus-4-7) works
#   N1 — URL with full `://` scheme is rejected (FALL through, NOT S1 hit)
#   N2 — value starting with `//` (S1-strip artifact) is rejected
#   N3 — value containing `?` (query-string sentinel) is rejected
#   N4 — URL-with-secret no longer surfaces secret in resolved_model_id
#   V1 — Sprint 2F V15 xfail flips green: secret-token absent from JSON
# =============================================================================

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    RESOLVER="$PROJECT_ROOT/.claude/scripts/lib/model-resolver.py"
    MODEL_INVOKE="$PROJECT_ROOT/.claude/scripts/model-invoke"
    [[ -f "$RESOLVER" ]] || skip "model-resolver.py not present"
    command -v python3 >/dev/null 2>&1 || skip "python3 not present"
    command -v jq >/dev/null 2>&1 || skip "jq not present"

    WORK_DIR="$(mktemp -d)"

    # Minimal valid config used by all tests. The skill_models tertiary
    # value is overridden per-test via _write_pin.
    cat > "$WORK_DIR/base.yaml" <<'YAML'
schema_version: 2
framework_defaults:
  providers:
    anthropic:
      models:
        claude-opus-4-7:
          capabilities: [chat]
          context_window: 1000000
          pricing: { input_per_mtok: 15000000, output_per_mtok: 75000000 }
        claude-haiku-4-5-20251001:
          capabilities: [chat]
          context_window: 200000
          pricing: { input_per_mtok: 1000000, output_per_mtok: 5000000 }
  aliases:
    opus: { provider: anthropic, model_id: claude-opus-4-7 }
    tiny: { provider: anthropic, model_id: claude-haiku-4-5-20251001 }
  tier_groups:
    mappings:
      tiny: { anthropic: tiny }
operator_config:
  skill_models:
    test_skill:
      primary: PIN_VALUE_PLACEHOLDER
runtime_state: {}
YAML
}

teardown() {
    if [[ -n "${WORK_DIR:-}" ]] && [[ -d "$WORK_DIR" ]]; then
        rm -rf "$WORK_DIR"
    fi
    return 0
}

_write_pin() {
    local pin_value="$1"
    sed "s|PIN_VALUE_PLACEHOLDER|$pin_value|" "$WORK_DIR/base.yaml" > "$WORK_DIR/cfg.yaml"
}

# --------------------------------------------------------------------------
# P-series: positive controls (valid provider:model_id pins still work)
# --------------------------------------------------------------------------

@test "P1 — valid provider:model_id pin resolves at S1 (positive control)" {
    _write_pin "anthropic:claude-opus-4-7"
    run --separate-stderr python3 "$RESOLVER" resolve \
        --config "$WORK_DIR/cfg.yaml" --skill test_skill --role primary
    [ "$status" -eq 0 ]
    local stage1
    stage1=$(echo "$output" | jq -r '.resolution_path[] | select(.stage == 1) | .label')
    [[ "$stage1" == "stage1_pin_check" ]]
    [[ "$(echo "$output" | jq -r '.resolved_provider')" == "anthropic" ]]
    [[ "$(echo "$output" | jq -r '.resolved_model_id')" == "claude-opus-4-7" ]]
}

@test "P2 — pin with alphanumeric provider+model_id works" {
    _write_pin "openai:gpt-5.5-pro"
    run --separate-stderr python3 "$RESOLVER" resolve \
        --config "$WORK_DIR/cfg.yaml" --skill test_skill --role primary
    [ "$status" -eq 0 ]
    [[ "$(echo "$output" | jq -r '.resolved_provider')" == "openai" ]]
    [[ "$(echo "$output" | jq -r '.resolved_model_id')" == "gpt-5.5-pro" ]]
}

@test "P3 — pin with dotted model_id (anthropic:claude-haiku-4-5-20251001) works" {
    _write_pin "anthropic:claude-haiku-4-5-20251001"
    run --separate-stderr python3 "$RESOLVER" resolve \
        --config "$WORK_DIR/cfg.yaml" --skill test_skill --role primary
    [ "$status" -eq 0 ]
    [[ "$(echo "$output" | jq -r '.resolved_model_id')" == "claude-haiku-4-5-20251001" ]]
}

# --------------------------------------------------------------------------
# N-series: negative tests (URL-shaped values are rejected at S1)
# --------------------------------------------------------------------------

@test "N1 — URL with :// scheme falls through S1 (NOT a pin hit)" {
    _write_pin "https://example.com/v1/chat"
    run --separate-stderr python3 "$RESOLVER" resolve \
        --config "$WORK_DIR/cfg.yaml" --skill test_skill --role primary
    # S1 rejects URL-shape (this is the fix). S2 also bypasses any
    # `:`-containing value (the existing behavior that defers to S1). With
    # neither S1 nor S2 firing, S3 isn't invoked either; cascade falls
    # through legacy/agents/prefer_pro to NO-RESOLUTION at S5. The KEY
    # security property is that no URL fragment ever surfaces in resolved_*.
    [ "$status" -eq 1 ]
    # No stage 1 hit in resolution_path.
    [[ "$(echo "$output" | jq '[.resolution_path[]? | select(.stage == 1)] | length')" == "0" ]]
    # Error is one of the fall-through codes (NO-RESOLUTION or TIER-NO-MAPPING
    # depending on internal cascade). Not a pin hit.
    local err_code
    err_code=$(echo "$output" | jq -r '.error.code // "none"')
    [[ "$err_code" == "[NO-RESOLUTION]" || "$err_code" == "[TIER-NO-MAPPING]" ]]
}

@test "N2 — value starting with // is rejected" {
    _write_pin "//user:pass@host"
    run --separate-stderr python3 "$RESOLVER" resolve \
        --config "$WORK_DIR/cfg.yaml" --skill test_skill --role primary
    [ "$status" -eq 1 ]
    [[ "$(echo "$output" | jq '[.resolution_path[]? | select(.stage == 1)] | length')" == "0" ]]
}

@test "N3 — value with ? (query-string sentinel) is rejected" {
    _write_pin "anthropic:claude-opus-4-7?api_key=secret"
    run --separate-stderr python3 "$RESOLVER" resolve \
        --config "$WORK_DIR/cfg.yaml" --skill test_skill --role primary
    [ "$status" -eq 1 ]
    [[ "$(echo "$output" | jq '[.resolution_path[]? | select(.stage == 1)] | length')" == "0" ]]
}

@test "N4 — URL with userinfo+secret: secret NOT in resolved_model_id" {
    # The #761 main repro: operator pastes a URL with secret-token@. Pre-fix,
    # `secret-token` surfaced in resolved_model_id (S1 split made //user:secret@
    # the model_id, redactor's `://` regex didn't match). Post-fix, S1 rejects
    # the entire URL-shape value AND the JSON output never carries the secret.
    _write_pin "https://leaky-user:secret-token@api.example.com/v1?api_key=v"
    run --separate-stderr python3 "$RESOLVER" resolve \
        --config "$WORK_DIR/cfg.yaml" --skill test_skill --role primary
    # Even if S2/S3 surfaces an error, the secret must NOT appear anywhere.
    [[ "$output" != *"secret-token"* ]]
    [[ "$output" != *"leaky-user:secret-token"* ]]
}

# --------------------------------------------------------------------------
# V-series: Sprint 2F V15 follow-up (xfail flips green)
# --------------------------------------------------------------------------

@test "V1 — Sprint 2F V15 xfail flips: validate-bindings JSON does NOT carry secret" {
    [[ -f "$MODEL_INVOKE" ]] || skip "model-invoke not present"
    cat > "$WORK_DIR/merged-with-url.yaml" <<'YAML'
schema_version: 2
framework_defaults:
  providers:
    anthropic:
      models:
        claude-opus-4-7:
          capabilities: [chat]
          context_window: 1000000
          pricing: { input_per_mtok: 15000000, output_per_mtok: 75000000 }
  aliases:
    opus: { provider: anthropic, model_id: claude-opus-4-7 }
  tier_groups:
    mappings:
      tiny: { anthropic: opus }
operator_config:
  skill_models:
    test_skill:
      primary: "https://leaky-user:secret-token@api.example.com/v1/chat?api_key=should-be-redacted&model=foo"
runtime_state: {}
YAML
    run --separate-stderr "$MODEL_INVOKE" --validate-bindings \
        --merged-config "$WORK_DIR/merged-with-url.yaml"
    # Either status 0 (resolved via fall-through) or 1 (unresolved). Both fine
    # for THIS test — what matters is the output content.
    [[ "$status" -eq 0 || "$status" -eq 1 ]]
    # The hardened assertion that V15's TODO promised: secret-token MUST NOT
    # appear anywhere in the JSON output. Pre-fix this leaked via
    # resolved_model_id; post-#761 it never reaches output at all.
    [[ "$output" != *"secret-token"* ]]
    [[ "$output" != *"should-be-redacted"* ]]
}
