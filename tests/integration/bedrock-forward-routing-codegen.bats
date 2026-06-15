#!/usr/bin/env bats
# =============================================================================
# tests/integration/bedrock-forward-routing-codegen.bats
#
# bedrock-forward-routing (this PR) — bash codegen side.
#
# Asserts that gen-adapter-maps.sh, when fed a config whose
# providers.bedrock.compliance_profile is prefer_bedrock / bedrock_only,
# rewrites Anthropic-targeted aliases to their Bedrock equivalent in the
# emitted MODEL_PROVIDERS / MODEL_IDS maps — WITHOUT the operator editing the
# aliases by hand. Equivalence comes from each Bedrock model's fallback_to
# (inverted). Non-Anthropic aliases must be left untouched, and a config with
# no Bedrock posture must emit the unmodified anthropic: routing.
#
# This is what keeps flatline's bash resolve_provider_id in lock-step with the
# Python loader's _apply_bedrock_forward_routing.
# =============================================================================

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    GEN="$REPO_ROOT/.claude/scripts/gen-adapter-maps.sh"
    TMPDIR_T="$(mktemp -d)"

    # Minimal but realistic config: two bedrock models with fallback_to, and
    # aliases targeting the direct Anthropic API plus an openai control.
    CFG="$TMPDIR_T/config.yaml"
    cat > "$CFG" <<'YAML'
providers:
  anthropic:
    type: anthropic
    models:
      claude-opus-4-8: { capabilities: [chat], auth_type: http_api, dispatch_group: anthropic-claude }
      claude-sonnet-4-6: { capabilities: [chat], auth_type: http_api, dispatch_group: anthropic-claude }
  openai:
    type: openai
    models:
      gpt-5.5: { capabilities: [chat], endpoint_family: responses, auth_type: http_api, dispatch_group: openai-gpt }
  bedrock:
    type: bedrock
    compliance_profile: prefer_bedrock
    models:
      "us.anthropic.claude-opus-4-8":
        capabilities: [chat]
        auth_type: aws_iam
        dispatch_group: bedrock-anthropic
        fallback_to: "anthropic:claude-opus-4-8"
      "us.anthropic.claude-sonnet-4-6":
        capabilities: [chat]
        auth_type: aws_iam
        dispatch_group: bedrock-anthropic
        fallback_to: "anthropic:claude-sonnet-4-6"
aliases:
  opus: "anthropic:claude-opus-4-8"
  cheap: "anthropic:claude-sonnet-4-6"
  gpt: "openai:gpt-5.5"
YAML
    OUT="$TMPDIR_T/maps.sh"
}

teardown() {
    rm -rf "$TMPDIR_T"
}

@test "prefer_bedrock: opus alias routes to bedrock provider in generated map" {
    run bash "$GEN" --config "$CFG" --output "$OUT"
    [ "$status" -eq 0 ]
    run grep -E '\["opus"\]="bedrock"' "$OUT"
    [ "$status" -eq 0 ]
}

@test "prefer_bedrock: opus model id rewritten to us.anthropic.* in generated map" {
    bash "$GEN" --config "$CFG" --output "$OUT"
    run grep -E '\["opus"\]="us\.anthropic\.claude-opus-4-8"' "$OUT"
    [ "$status" -eq 0 ]
}

@test "prefer_bedrock: cheap (sonnet) alias also routes to bedrock" {
    bash "$GEN" --config "$CFG" --output "$OUT"
    run grep -E '\["cheap"\]="bedrock"' "$OUT"
    [ "$status" -eq 0 ]
}

@test "prefer_bedrock: non-anthropic alias (gpt) is left on its own provider" {
    bash "$GEN" --config "$CFG" --output "$OUT"
    run grep -E '\["gpt"\]="openai"' "$OUT"
    [ "$status" -eq 0 ]
}

@test "prefer_bedrock: forward-routing INFO is emitted to stderr" {
    run bash "$GEN" --config "$CFG" --output "$OUT"
    [[ "$output" == *"bedrock-forward-routing active"* ]]
}

@test "no bedrock posture: aliases keep their anthropic routing (no-op)" {
    # Strip the compliance_profile -> codegen must NOT rewrite.
    sed '/compliance_profile:/d' "$CFG" > "$TMPDIR_T/noposture.yaml"
    bash "$GEN" --config "$TMPDIR_T/noposture.yaml" --output "$OUT"
    run grep -E '\["opus"\]="anthropic"' "$OUT"
    [ "$status" -eq 0 ]
}
