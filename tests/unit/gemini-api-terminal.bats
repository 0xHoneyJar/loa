#!/usr/bin/env bats
# =============================================================================
# #1089 — gemini-api terminal: key-based (GOOGLE_API_KEY / HTTP) Gemini path
# =============================================================================
# Provides an explicit named terminal operators can swap for the deprecated
# `gemini-headless` CLI (Gemini Code Assist for individuals retired, KF-018).
# It must route through the HTTP/api-key path (auth_type http_api), NOT the CLI.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    CFG="$REPO_ROOT/.claude/defaults/model-config.yaml"
    [[ -f "$CFG" ]] || skip "model-config.yaml not found"
    command -v yq >/dev/null 2>&1 || skip "yq required"
}

@test "#1089: gemini-api alias exists and resolves to a google:gemini-* model" {
    run yq -r '.aliases.gemini-api' "$CFG"
    [ "$status" -eq 0 ]
    [[ "$output" == google:gemini* ]]
}

@test "#1089: gemini-api routes through the HTTP api-key path (auth_type http_api), NOT the dead CLI" {
    local target
    target="$(yq -r '.aliases.gemini-api' "$CFG")"
    target="${target#google:}"
    run yq -r ".providers.google.models.\"$target\".auth_type" "$CFG"
    [ "$status" -eq 0 ]
    [ "$output" = "http_api" ]
    # explicitly NOT the headless CLI terminal
    [[ "$target" != *"headless"* ]]
}

@test "#1089: the google provider's api-key terminal target advertises chat" {
    local target
    target="$(yq -r '.aliases.gemini-api' "$CFG")"
    target="${target#google:}"
    run yq -r ".providers.google.models.\"$target\".capabilities | contains([\"chat\"])" "$CFG"
    [ "$output" = "true" ]
}
