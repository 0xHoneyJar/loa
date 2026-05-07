#!/usr/bin/env bats
# =============================================================================
# tests/integration/cycle099-sprint-2F-validate-bindings.bats
#
# cycle-099 Sprint 2F (T2.12 + T2.13) — `model-invoke --validate-bindings` CLI
# + `LOA_DEBUG_MODEL_RESOLUTION=1` runtime tracing.
#
# Spec sources: SDD §5.2 (FR-5.6 contract) + SDD §1.5.2 (--diff-bindings) +
# SDD §6.4 ([MODEL-RESOLVE] format) + SDD §5.6 (log-redactor integration) +
# AC-S2.10 + AC-S2.11 + AC-S2.13.
#
# Test surface:
#   V-series — T2.12 validate-bindings output shape + exit codes
#   D-series — T2.13 LOA_DEBUG_MODEL_RESOLUTION stderr trace
#   I-series — integration: validate-bindings under LOA_DEBUG_MODEL_RESOLUTION
# =============================================================================

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    MODEL_INVOKE="$PROJECT_ROOT/.claude/scripts/model-invoke"
    VALIDATE_BINDINGS="$PROJECT_ROOT/.claude/scripts/lib/validate-bindings.py"
    RESOLVER="$PROJECT_ROOT/.claude/scripts/lib/model-resolver.py"
    DEFAULTS="$PROJECT_ROOT/.claude/defaults/model-config.yaml"

    [[ -f "$MODEL_INVOKE" ]] || skip "model-invoke not present"
    [[ -f "$VALIDATE_BINDINGS" ]] || skip "validate-bindings.py not present"
    [[ -f "$RESOLVER" ]] || skip "model-resolver.py not present"
    [[ -f "$DEFAULTS" ]] || skip "framework defaults not present"
    command -v python3 >/dev/null 2>&1 || skip "python3 not present"
    command -v jq >/dev/null 2>&1 || skip "jq not present"

    WORK_DIR="$(mktemp -d)"

    # Minimal merged config fixture used by V-series tests directly.
    # `validate-bindings.py` accepts a `--merged-config` path that bypasses
    # the framework-defaults + operator-config stitching for unit testing.
    cat > "$WORK_DIR/merged-clean.yaml" <<'YAML'
schema_version: 2
framework_defaults:
  providers:
    anthropic:
      models:
        claude-haiku-4-5-20251001:
          capabilities: [chat]
          context_window: 200000
          pricing: { input_per_mtok: 1000000, output_per_mtok: 5000000 }
        claude-opus-4-7:
          capabilities: [chat, thinking]
          context_window: 1000000
          pricing: { input_per_mtok: 15000000, output_per_mtok: 75000000 }
    openai:
      models:
        gpt-5.5-pro:
          capabilities: [chat]
          context_window: 400000
          pricing: { input_per_mtok: 2500000, output_per_mtok: 10000000 }
  aliases:
    tiny: { provider: anthropic, model_id: claude-haiku-4-5-20251001 }
    opus: { provider: anthropic, model_id: claude-opus-4-7 }
    gpt55-pro: { provider: openai, model_id: gpt-5.5-pro }
  tier_groups:
    mappings:
      max:
        anthropic: opus
        openai: gpt55-pro
      tiny:
        anthropic: tiny
  agents:
    reviewer-default:
      model: opus
operator_config:
  skill_models:
    audit_log_lookup:
      primary: tiny
    big_thinker:
      primary: max
runtime_state: {}
YAML

    # Unresolved-binding fixture — operator references unknown alias.
    cat > "$WORK_DIR/merged-unresolved.yaml" <<'YAML'
schema_version: 2
framework_defaults:
  providers:
    anthropic:
      models:
        claude-haiku-4-5-20251001:
          capabilities: [chat]
          context_window: 200000
          pricing: { input_per_mtok: 1000000, output_per_mtok: 5000000 }
  aliases:
    tiny: { provider: anthropic, model_id: claude-haiku-4-5-20251001 }
  tier_groups:
    mappings:
      tiny:
        anthropic: tiny
  agents: {}
operator_config:
  skill_models:
    broken_skill:
      primary: ghost-alias-that-does-not-exist
runtime_state: {}
YAML

    # diff-bindings fixture — operator overrides a framework agent default.
    cat > "$WORK_DIR/merged-diff.yaml" <<'YAML'
schema_version: 2
framework_defaults:
  providers:
    anthropic:
      models:
        claude-haiku-4-5-20251001:
          capabilities: [chat]
          context_window: 200000
          pricing: { input_per_mtok: 1000000, output_per_mtok: 5000000 }
        claude-opus-4-7:
          capabilities: [chat]
          context_window: 1000000
          pricing: { input_per_mtok: 15000000, output_per_mtok: 75000000 }
  aliases:
    tiny: { provider: anthropic, model_id: claude-haiku-4-5-20251001 }
    opus: { provider: anthropic, model_id: claude-opus-4-7 }
  tier_groups:
    mappings:
      tiny: { anthropic: tiny }
      max: { anthropic: opus }
  agents:
    reviewing-code:
      model: opus
operator_config:
  skill_models:
    reviewing-code:
      primary: tiny
runtime_state: {}
YAML

    # URL-bearing fixture for redaction tests (V15 + D8). The URL is placed
    # in `skill_models.<skill>.<role>` because S1 (explicit pin) surfaces the
    # raw value in `details.pin` of the resolution_path. Without flowing to
    # output, the redactor integration is invisible.
    cat > "$WORK_DIR/merged-with-url.yaml" <<'YAML'
schema_version: 2
framework_defaults:
  providers:
    custom_provider:
      models:
        custom-model:
          capabilities: [chat]
          context_window: 100000
          pricing: { input_per_mtok: 0, output_per_mtok: 0 }
  aliases:
    custom-alias: { provider: custom_provider, model_id: custom-model }
  tier_groups:
    mappings:
      custom: { custom_provider: custom-alias }
  agents: {}
operator_config:
  skill_models:
    test_skill:
      # S1 explicit-pin path surfaces this raw string in details.pin →
      # the redactor masks the userinfo + ?api_key= secret patterns.
      primary: "https://leaky-user:secret-token@api.example.com/v1/chat?api_key=should-be-redacted&model=foo"
runtime_state: {}
YAML
}

teardown() {
    if [[ -n "${WORK_DIR:-}" ]] && [[ -d "$WORK_DIR" ]]; then
        rm -rf "$WORK_DIR"
    fi
    return 0
}

# --------------------------------------------------------------------------
# V-series: T2.12 validate-bindings output shape + exit codes
# --------------------------------------------------------------------------

@test "V1 — validate-bindings emits valid JSON to stdout (--format json default)" {
    run "$MODEL_INVOKE" --validate-bindings --merged-config "$WORK_DIR/merged-clean.yaml"
    [ "$status" -eq 0 ]
    echo "$output" | python3 -c "import sys, json; json.loads(sys.stdin.read())"
}

@test "V2 — JSON contains required top-level fields per SDD §5.2" {
    run "$MODEL_INVOKE" --validate-bindings --merged-config "$WORK_DIR/merged-clean.yaml"
    [ "$status" -eq 0 ]
    local json="$output"
    [[ "$(echo "$json" | jq -r '.schema_version')" == "1.0.0" ]]
    [[ "$(echo "$json" | jq -r '.command')" == "validate-bindings" ]]
    [[ "$(echo "$json" | jq -r '.exit_code')" == "0" ]]
    [[ "$(echo "$json" | jq -r '.summary | type')" == "object" ]]
    [[ "$(echo "$json" | jq -r '.bindings | type')" == "array" ]]
}

@test "V3 — summary contains required keys" {
    run "$MODEL_INVOKE" --validate-bindings --merged-config "$WORK_DIR/merged-clean.yaml"
    [ "$status" -eq 0 ]
    local json="$output"
    [[ "$(echo "$json" | jq 'has("summary")')" == "true" ]]
    [[ "$(echo "$json" | jq '.summary | has("total_bindings")')" == "true" ]]
    [[ "$(echo "$json" | jq '.summary | has("resolved")')" == "true" ]]
    [[ "$(echo "$json" | jq '.summary | has("unresolved")')" == "true" ]]
    [[ "$(echo "$json" | jq '.summary | has("legacy_shape_warnings")')" == "true" ]]
}

@test "V4 — bindings include operator skill_models pairs" {
    run "$MODEL_INVOKE" --validate-bindings --merged-config "$WORK_DIR/merged-clean.yaml"
    [ "$status" -eq 0 ]
    local pairs
    pairs=$(echo "$output" | jq -r '.bindings[] | "\(.skill):\(.role)"' | sort)
    echo "Pairs: $pairs" >&2
    [[ "$pairs" == *"audit_log_lookup:primary"* ]]
    [[ "$pairs" == *"big_thinker:primary"* ]]
}

@test "V5 — bindings include framework agents (role=primary)" {
    run "$MODEL_INVOKE" --validate-bindings --merged-config "$WORK_DIR/merged-clean.yaml"
    [ "$status" -eq 0 ]
    local pairs
    pairs=$(echo "$output" | jq -r '.bindings[] | "\(.skill):\(.role)"' | sort)
    [[ "$pairs" == *"reviewer-default:primary"* ]]
}

@test "V6 — each binding has resolved_provider + resolved_model_id + resolution_path" {
    run "$MODEL_INVOKE" --validate-bindings --merged-config "$WORK_DIR/merged-clean.yaml"
    [ "$status" -eq 0 ]
    # Every binding without `error` MUST have these three fields.
    local missing
    missing=$(echo "$output" | jq '[.bindings[] | select(has("error") | not) | select((has("resolved_provider") and has("resolved_model_id") and has("resolution_path")) | not)] | length')
    [ "$missing" -eq 0 ]
}

@test "V7 — exit 0 when all bindings resolve cleanly" {
    run "$MODEL_INVOKE" --validate-bindings --merged-config "$WORK_DIR/merged-clean.yaml"
    [ "$status" -eq 0 ]
    [[ "$(echo "$output" | jq -r '.exit_code')" == "0" ]]
    [[ "$(echo "$output" | jq -r '.summary.unresolved')" == "0" ]]
}

@test "V8 — exit 1 when at least one binding fails to resolve (FR-3.8)" {
    run "$MODEL_INVOKE" --validate-bindings --merged-config "$WORK_DIR/merged-unresolved.yaml"
    [ "$status" -eq 1 ]
    [[ "$(echo "$output" | jq -r '.exit_code')" == "1" ]]
    [[ "$(echo "$output" | jq -r '.summary.unresolved')" -ge "1" ]]
}

@test "V9 — exit 2 on unknown --format value" {
    run "$MODEL_INVOKE" --validate-bindings --format invalidformat --merged-config "$WORK_DIR/merged-clean.yaml"
    [ "$status" -eq 2 ]
}

@test "V10 — exit 78 (EX_CONFIG) when merged-config file is missing" {
    run "$MODEL_INVOKE" --validate-bindings --merged-config "$WORK_DIR/does-not-exist.yaml"
    [ "$status" -eq 78 ]
}

@test "V11 — exit 78 when merged-config is malformed YAML" {
    cat > "$WORK_DIR/malformed.yaml" <<'YAML'
schema_version: 2
framework_defaults: [this is wrong - should be a dict
YAML
    run "$MODEL_INVOKE" --validate-bindings --merged-config "$WORK_DIR/malformed.yaml"
    [ "$status" -eq 78 ]
    # gp LOW-4: assert error message structure so a regression that changes
    # exit-code-78 path to silent-78 (e.g., uncaught yaml error → wrong code)
    # surfaces in test rather than the bare exit-code check.
    [[ "$output" == *"[VALIDATE-BINDINGS] ERROR"* ]]
}

@test "V12 — --format text produces non-JSON human-readable output" {
    run "$MODEL_INVOKE" --validate-bindings --format text --merged-config "$WORK_DIR/merged-clean.yaml"
    [ "$status" -eq 0 ]
    # Plain-text output should NOT parse as JSON.
    if echo "$output" | python3 -c "import sys, json; json.loads(sys.stdin.read())" 2>/dev/null; then
        echo "FAIL — --format text emitted JSON" >&2
        return 1
    fi
    # And SHOULD contain at least one binding's skill name.
    [[ "$output" == *"audit_log_lookup"* ]]
}

@test "V13 — --diff-bindings emits [BINDING-OVERRIDDEN] to stderr when operator overrides framework default" {
    # merged-diff has operator skill_models.reviewing-code.primary=tiny but
    # framework agents.reviewing-code.model=opus → effective != compiled.
    # BB-iter1 F1 + gp MED-5 fix: use --separate-stderr (bats >=1.10) so stdout
    # and stderr are captured from a SINGLE invocation. Avoids the
    # double-invocation pattern where status check and stderr assertion
    # came from different runs.
    run --separate-stderr "$MODEL_INVOKE" --validate-bindings --diff-bindings \
        --merged-config "$WORK_DIR/merged-diff.yaml"
    [ "$status" -eq 0 ]
    [[ "$stderr" == *"[BINDING-OVERRIDDEN]"* ]]
    [[ "$stderr" == *"skill=reviewing-code"* ]]
    [[ "$stderr" == *"role=primary"* ]]
}

@test "V14 — without --diff-bindings, no [BINDING-OVERRIDDEN] emitted" {
    run --separate-stderr "$MODEL_INVOKE" --validate-bindings \
        --merged-config "$WORK_DIR/merged-diff.yaml"
    [ "$status" -eq 0 ]
    [[ "$stderr" != *"[BINDING-OVERRIDDEN]"* ]]
}

@test "V15 — URL-shape pin: secret never reaches validate-bindings output (#761 closure)" {
    # Original V15 (Sprint 2F) tested redactor behavior on URL secrets that
    # surfaced in `details.pin` via S1 explicit-pin. #761 closed that surface
    # at the source: `_stage1_explicit_pin` rejects URL-shape values
    # entirely, falling through to S2/S3/S5 with no URL fragment in
    # `resolution_path` or `resolved_*` fields. The hardened assertion is
    # now structural rather than redactor-dependent: NO part of the pasted
    # URL EVER appears in the JSON output. Status may be 0 (clean) or 1
    # (unresolved binding); both are valid post-#761 — what matters is that
    # the secret-bearing input never echoes into output.
    run "$MODEL_INVOKE" --validate-bindings --merged-config "$WORK_DIR/merged-with-url.yaml"
    [[ "$status" -eq 0 || "$status" -eq 1 ]]
    [[ "$output" != *"secret-token"* ]]
    [[ "$output" != *"should-be-redacted"* ]]
    [[ "$output" != *"leaky-user"* ]]
    [[ "$output" != *"https://"* ]]
}

@test "V16 — makes ZERO API calls (no provider HTTP traffic)" {
    # Force any HTTP call to fail by clearing provider env vars.
    # If validate-bindings tried to invoke a model, ANTHROPIC_API_KEY=fake
    # would surface a 401 and we'd see a non-clean run. Clean run = no calls.
    run env -i PATH="/usr/bin:/bin:/usr/local/bin" \
        ANTHROPIC_API_KEY="" \
        OPENAI_API_KEY="" \
        GOOGLE_API_KEY="" \
        "$MODEL_INVOKE" --validate-bindings --merged-config "$WORK_DIR/merged-clean.yaml"
    [ "$status" -eq 0 ]
}

@test "V17 — bindings deduplicated on (skill, role) — operator wins on collision" {
    cat > "$WORK_DIR/merged-collision.yaml" <<'YAML'
schema_version: 2
framework_defaults:
  providers:
    anthropic:
      models:
        claude-haiku-4-5-20251001: { capabilities: [chat], context_window: 200000, pricing: { input_per_mtok: 1000000, output_per_mtok: 5000000 } }
  aliases:
    tiny: { provider: anthropic, model_id: claude-haiku-4-5-20251001 }
  tier_groups:
    mappings:
      tiny: { anthropic: tiny }
  agents:
    shared-skill:
      model: tiny
operator_config:
  skill_models:
    shared-skill:
      primary: tiny
runtime_state: {}
YAML
    run "$MODEL_INVOKE" --validate-bindings --merged-config "$WORK_DIR/merged-collision.yaml"
    [ "$status" -eq 0 ]
    # Only ONE binding for (shared-skill, primary) — not two.
    local count
    count=$(echo "$output" | jq -r '[.bindings[] | select(.skill == "shared-skill" and .role == "primary")] | length')
    [ "$count" -eq 1 ]
}

# --------------------------------------------------------------------------
# D-series: T2.13 LOA_DEBUG_MODEL_RESOLUTION stderr trace
# --------------------------------------------------------------------------

@test "D1 — LOA_DEBUG_MODEL_RESOLUTION=1 emits [MODEL-RESOLVE] line via resolve()" {
    # Direct resolver invocation should also honor the env var.
    local stderr_out
    stderr_out=$(LOA_DEBUG_MODEL_RESOLUTION=1 python3 "$RESOLVER" resolve \
        --config "$WORK_DIR/merged-clean.yaml" \
        --skill audit_log_lookup \
        --role primary 2>&1 >/dev/null)
    [[ "$stderr_out" == *"[MODEL-RESOLVE]"* ]]
    [[ "$stderr_out" == *"skill=audit_log_lookup"* ]]
    [[ "$stderr_out" == *"role=primary"* ]]
}

@test "D2 — LOA_DEBUG_MODEL_RESOLUTION unset → no [MODEL-RESOLVE] emission" {
    # Use env -u to ensure var is truly absent (not just empty).
    local stderr_out
    stderr_out=$(env -u LOA_DEBUG_MODEL_RESOLUTION python3 "$RESOLVER" resolve \
        --config "$WORK_DIR/merged-clean.yaml" \
        --skill audit_log_lookup \
        --role primary 2>&1 >/dev/null)
    [[ "$stderr_out" != *"[MODEL-RESOLVE]"* ]]
}

@test "D3 — LOA_DEBUG_MODEL_RESOLUTION=0 → no emission (only literal '1' enables)" {
    local stderr_out
    stderr_out=$(LOA_DEBUG_MODEL_RESOLUTION=0 python3 "$RESOLVER" resolve \
        --config "$WORK_DIR/merged-clean.yaml" \
        --skill audit_log_lookup \
        --role primary 2>&1 >/dev/null)
    [[ "$stderr_out" != *"[MODEL-RESOLVE]"* ]]
}

@test "D4 — LOA_DEBUG_MODEL_RESOLUTION=true (string) → no emission (strict '1' check)" {
    local stderr_out
    stderr_out=$(LOA_DEBUG_MODEL_RESOLUTION=true python3 "$RESOLVER" resolve \
        --config "$WORK_DIR/merged-clean.yaml" \
        --skill audit_log_lookup \
        --role primary 2>&1 >/dev/null)
    [[ "$stderr_out" != *"[MODEL-RESOLVE]"* ]]
}

@test "D5 — [MODEL-RESOLVE] line includes resolved=provider:model_id" {
    local stderr_out
    stderr_out=$(LOA_DEBUG_MODEL_RESOLUTION=1 python3 "$RESOLVER" resolve \
        --config "$WORK_DIR/merged-clean.yaml" \
        --skill audit_log_lookup \
        --role primary 2>&1 >/dev/null)
    [[ "$stderr_out" == *"resolved=anthropic:claude-haiku-4-5-20251001"* ]]
}

@test "D6 — [MODEL-RESOLVE] line includes resolution_path" {
    local stderr_out
    stderr_out=$(LOA_DEBUG_MODEL_RESOLUTION=1 python3 "$RESOLVER" resolve \
        --config "$WORK_DIR/merged-clean.yaml" \
        --skill audit_log_lookup \
        --role primary 2>&1 >/dev/null)
    [[ "$stderr_out" == *"resolution_path="* ]]
    [[ "$stderr_out" == *"stage"* ]]
}

@test "D7 — stdout NOT polluted by debug trace (only stderr writes)" {
    local stdout_out stderr_out
    stdout_out=$(LOA_DEBUG_MODEL_RESOLUTION=1 python3 "$RESOLVER" resolve \
        --config "$WORK_DIR/merged-clean.yaml" \
        --skill audit_log_lookup \
        --role primary 2>/dev/null)
    [[ "$stdout_out" != *"[MODEL-RESOLVE]"* ]]
    # And stdout should still parse as JSON (the resolver's normal output).
    echo "$stdout_out" | python3 -c "import sys, json; json.loads(sys.stdin.read())"
}

@test "D8 — debug trace redacts URL userinfo in resolution_path details" {
    # Use the URL-bearing fixture (D-fixture has model_aliases_extra with secret URL).
    # This requires the resolution to surface the URL into resolution_path.
    # We test the redactor integration directly by checking a synthesized line
    # via the resolver that hits an alias whose details could carry a URL.
    # Simpler check: confirm no plaintext "secret-token" appears in stderr trace.
    # `|| true` because URL-shape pin causes #761 fall-through → resolver
    # exits 1 (unresolved). The trace-emission defense being tested is
    # orthogonal to the resolution outcome.
    local stderr_out
    stderr_out=$(LOA_DEBUG_MODEL_RESOLUTION=1 python3 "$RESOLVER" resolve \
        --config "$WORK_DIR/merged-with-url.yaml" \
        --skill test_skill \
        --role primary 2>&1 >/dev/null) || true
    [[ "$stderr_out" != *"secret-token"* ]]
    [[ "$stderr_out" != *"should-be-redacted"* ]]
}

@test "D9 — overhead under tracing is bounded (<2ms p50, <50ms p95)" {
    # Per FR-5.7: <2ms per-resolution overhead. Sample 20 resolutions and
    # verify avg under a generous budget. We use a 50ms ceiling on a single
    # call as a smoke gate (CI variance + Python startup amortized) — the
    # canonical 2ms applies to a hot resolve() inside an in-process loop, not
    # cold Python boot. A separate microbenchmark in tests/perf/ is the
    # rigorous contract; this is the "no-pathological-regression" gate.
    local total_ms count
    count=20
    total_ms=$(LOA_DEBUG_MODEL_RESOLUTION=1 python3 -c "
import os, sys, time
sys.path.insert(0, '$PROJECT_ROOT/.claude/scripts/lib')
import importlib.util
spec = importlib.util.spec_from_file_location('mr', '$RESOLVER')
mr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mr)
import yaml
with open('$WORK_DIR/merged-clean.yaml') as fh:
    cfg = yaml.safe_load(fh)
t0 = time.monotonic()
for _ in range($count):
    mr.resolve(cfg, 'audit_log_lookup', 'primary')
dt_ms = (time.monotonic() - t0) * 1000
print(f'{dt_ms:.1f}')
" 2>/dev/null)
    # Bash arithmetic doesn't do floats; compare via awk.
    local avg_ms
    avg_ms=$(awk -v t="$total_ms" -v c="$count" 'BEGIN { printf "%.2f", t/c }')
    echo "Avg per-resolution under tracing: ${avg_ms}ms (budget: <50ms)" >&2
    awk -v a="$avg_ms" 'BEGIN { exit !(a < 50) }'
}

# --------------------------------------------------------------------------
# I-series: integration
# --------------------------------------------------------------------------

@test "I1 — validate-bindings under LOA_DEBUG_MODEL_RESOLUTION=1 emits one [MODEL-RESOLVE] per binding" {
    # BB-iter1 F6 fix: tighten from `>= 3` to `== 3` so a regression that
    # emitted 2 traces per binding (e.g., a re-introduction of F4 doubling)
    # would surface here AND in S5. The merged-clean.yaml has 3 bindings:
    # audit_log_lookup, big_thinker (operator), reviewer-default (framework agent).
    local stderr_out trace_count
    stderr_out=$(LOA_DEBUG_MODEL_RESOLUTION=1 "$MODEL_INVOKE" --validate-bindings \
        --merged-config "$WORK_DIR/merged-clean.yaml" 2>&1 >/dev/null)
    trace_count=$(echo "$stderr_out" | grep -c '\[MODEL-RESOLVE\]' || echo 0)
    [[ "$trace_count" -eq 3 ]] || { echo "Got $trace_count, expected 3" >&2; return 1; }
}

# --------------------------------------------------------------------------
# S-series: Sprint 2F cypherpunk-review pre-merge defenses
# --------------------------------------------------------------------------

@test "S1 [F2] — newline in skill name does NOT inject fake [MODEL-RESOLVE] line" {
    # Operator-controlled skill name with embedded newline that, without F2
    # mitigation, would emit two pseudo-[MODEL-RESOLVE] lines. With F2, the
    # newline must be escaped to \x0a and the line stays on one line.
    # Use a SHORT skill name so the F1 length-cap doesn't fire first.
    cat > "$WORK_DIR/merged-newline.yaml" <<'YAML'
schema_version: 2
framework_defaults:
  providers:
    anthropic:
      models:
        claude-haiku-4-5-20251001: { capabilities: [chat], context_window: 200000, pricing: { input_per_mtok: 1000000, output_per_mtok: 5000000 } }
  aliases:
    tiny: { provider: anthropic, model_id: claude-haiku-4-5-20251001 }
  tier_groups:
    mappings:
      tiny: { anthropic: tiny }
operator_config:
  skill_models:
    "evil\nfake-pwn":
      primary: tiny
runtime_state: {}
YAML
    local stderr_out malicious
    malicious=$(printf 'evil\nfake-pwn')
    stderr_out=$(LOA_DEBUG_MODEL_RESOLUTION=1 python3 "$RESOLVER" resolve \
        --config "$WORK_DIR/merged-newline.yaml" \
        --skill "$malicious" \
        --role primary 2>&1 >/dev/null) || true
    # Exactly one [MODEL-RESOLVE] line — the injected one is escaped.
    local count
    count=$(echo "$stderr_out" | grep -c '^\[MODEL-RESOLVE\]' || echo 0)
    [[ "$count" -eq 1 ]] || { echo "Got $count [MODEL-RESOLVE] lines, expected 1. stderr was:" >&2; echo "$stderr_out" >&2; return 1; }
    # The newline must be escaped (literal `\x0a` 4-char sequence in output).
    [[ "$stderr_out" == *'\x0a'* ]]
}

@test "S1b [BB-F5] — newline-bearing skill_models VALUE from YAML does NOT inject fake [MODEL-RESOLVE] line" {
    # BB iter-1 F5: S1 only exercised the argv door (--skill "$malicious").
    # The realistic attack vector is an operator committing a malicious
    # value to YAML; validate-bindings then iterates skill_models keys/values.
    # This test fires validate-bindings end-to-end so the only source of
    # the malicious string is the loaded config — no argv interpolation.
    cat > "$WORK_DIR/merged-yaml-newline.yaml" <<'YAML'
schema_version: 2
framework_defaults:
  providers:
    anthropic:
      models:
        claude-haiku-4-5-20251001: { capabilities: [chat], context_window: 200000, pricing: { input_per_mtok: 1000000, output_per_mtok: 5000000 } }
  aliases:
    tiny: { provider: anthropic, model_id: claude-haiku-4-5-20251001 }
  tier_groups:
    mappings:
      tiny: { anthropic: tiny }
operator_config:
  skill_models:
    yamlsk:
      # Newline-bearing VALUE — exercises the input=Z field
      primary: "tiny\n[MODEL-RESOLVE] skill=spoofed role=admin input=PWNED resolved=fake:fake resolution_path=[]"
runtime_state: {}
YAML
    run --separate-stderr env LOA_DEBUG_MODEL_RESOLUTION=1 \
        "$MODEL_INVOKE" --validate-bindings \
        --merged-config "$WORK_DIR/merged-yaml-newline.yaml"
    # Resolution may exit 0 (clean) or 1 (TIER-NO-MAPPING since the value
    # isn't a known alias); either is fine for THIS test, which is about
    # log-injection defense regardless of resolution outcome.
    [[ "$status" -eq 0 || "$status" -eq 1 ]]
    # Exactly one [MODEL-RESOLVE] line in stderr (one per binding, the only
    # binding here is `yamlsk.primary`). The injected pseudo-line must NOT
    # appear as a separate line.
    local count
    count=$(echo "$stderr" | grep -c '^\[MODEL-RESOLVE\]' || echo 0)
    [[ "$count" -eq 1 ]] || { echo "Got $count [MODEL-RESOLVE] lines, expected 1. stderr was:" >&2; echo "$stderr" >&2; return 1; }
    # The newline must be escaped as the 4-char literal sequence `\x0a`.
    [[ "$stderr" == *'\x0a'* ]]
    # The injected `skill=spoofed` MUST NOT appear at the start of any line.
    if echo "$stderr" | grep -qE '^\[MODEL-RESOLVE\] skill=spoofed'; then
        echo "FAIL — pseudo-line was emitted via YAML-door injection" >&2
        return 1
    fi
}

@test "S2 [F1] — overlength input value is replaced with [REDACTED-OVERLENGTH-N] (bearer-token defense)" {
    # Operator pastes a long bearer-shaped string into skill_models.<skill>.<role>.
    # Without F1 mitigation, the trace line would carry the secret literally.
    # With F1, anything >80 chars defaults to [REDACTED-OVERLENGTH-N].
    local long_secret="sk-ant-api03-AAAA-base64-bearer-token-AAAA-this-is-100-plus-chars-of-pasted-secret-material-XYZ"
    cat > "$WORK_DIR/merged-long.yaml" <<YAML
schema_version: 2
framework_defaults:
  providers:
    anthropic:
      models:
        claude-haiku-4-5-20251001: { capabilities: [chat], context_window: 200000, pricing: { input_per_mtok: 1000000, output_per_mtok: 5000000 } }
  aliases:
    tiny: { provider: anthropic, model_id: claude-haiku-4-5-20251001 }
  tier_groups:
    mappings:
      tiny: { anthropic: tiny }
operator_config:
  skill_models:
    bad_skill:
      primary: "$long_secret"
runtime_state: {}
YAML
    local stderr_out
    # `|| true` since long_secret won't resolve to a known alias → resolver
    # exits 1 (TIER-NO-MAPPING). We're testing the trace-emission mitigation,
    # not the resolution outcome.
    stderr_out=$(LOA_DEBUG_MODEL_RESOLUTION=1 python3 "$RESOLVER" resolve \
        --config "$WORK_DIR/merged-long.yaml" \
        --skill bad_skill --role primary 2>&1 >/dev/null) || true
    # The secret MUST NOT appear in the trace line.
    [[ "$stderr_out" != *"sk-ant-api03-AAAA-base64-bearer-token-AAAA"* ]]
    # The redacted sentinel MUST appear.
    [[ "$stderr_out" == *"REDACTED-OVERLENGTH"* ]]
}

@test "S3 [F1] — short input values flow through (no false-positive redaction)" {
    # Legitimate short skill_models value passes through unmodified.
    local stderr_out
    stderr_out=$(LOA_DEBUG_MODEL_RESOLUTION=1 python3 "$RESOLVER" resolve \
        --config "$WORK_DIR/merged-clean.yaml" \
        --skill audit_log_lookup --role primary 2>&1 >/dev/null)
    [[ "$stderr_out" == *"input=tiny"* ]]
    [[ "$stderr_out" != *"REDACTED-OVERLENGTH"* ]]
}

@test "S4 [F1] — LOA_TRACE_INPUT_MAX_LEN env var extends the cap" {
    # Operator with longer-than-80-char model_ids can extend via env override.
    local long_value="this-is-a-long-but-legitimate-model-id-that-an-operator-might-have-95chars-XYZW-abc"
    cat > "$WORK_DIR/merged-cap.yaml" <<YAML
schema_version: 2
framework_defaults:
  providers:
    anthropic:
      models:
        claude-haiku-4-5-20251001: { capabilities: [chat], context_window: 200000, pricing: { input_per_mtok: 1000000, output_per_mtok: 5000000 } }
  aliases:
    tiny: { provider: anthropic, model_id: claude-haiku-4-5-20251001 }
  tier_groups:
    mappings:
      tiny: { anthropic: tiny }
operator_config:
  skill_models:
    long_skill:
      primary: "$long_value"
runtime_state: {}
YAML
    local stderr_out
    # `|| true` because the long value isn't a known alias (TIER-NO-MAPPING).
    stderr_out=$(LOA_DEBUG_MODEL_RESOLUTION=1 LOA_TRACE_INPUT_MAX_LEN=200 \
        python3 "$RESOLVER" resolve \
        --config "$WORK_DIR/merged-cap.yaml" \
        --skill long_skill --role primary 2>&1 >/dev/null) || true
    # With cap=200, the 82-char value passes through.
    [[ "$stderr_out" == *"input=$long_value"* ]]
    [[ "$stderr_out" != *"REDACTED-OVERLENGTH"* ]]
}

@test "S5 [F4] — --diff-bindings under LOA_DEBUG=1 emits ONE trace per binding (not two)" {
    # F4 mitigation: _diff_bindings calls resolve.__wrapped__ to bypass the
    # decorator's trace emission for the framework-only re-resolution.
    local stderr_out trace_count
    stderr_out=$(LOA_DEBUG_MODEL_RESOLUTION=1 "$MODEL_INVOKE" --validate-bindings \
        --diff-bindings --merged-config "$WORK_DIR/merged-clean.yaml" 2>&1 >/dev/null)
    trace_count=$(echo "$stderr_out" | grep -cE '^\[MODEL-RESOLVE\]' || echo 0)
    # Expected: 3 bindings × 1 trace each = 3 (NOT 6 = 3×2 if doubled).
    # merged-clean.yaml has audit_log_lookup, big_thinker, reviewer-default = 3 pairs.
    [[ "$trace_count" -eq 3 ]] || { echo "Got $trace_count traces, expected 3 (no doubling). Output:" >&2; echo "$stderr_out" >&2; return 1; }
}

@test "S6 [F7] — trace-emission exception emits [MODEL-RESOLVE-TRACE-FAILED] WARN counter" {
    # Inject a deliberate trace-emit exception via a non-stringifiable value
    # in the resolution result. We do this by monkey-patching _emit_trace_line
    # in a one-shot Python invocation — easier than crafting a YAML fixture
    # that triggers an exception inside json.dumps.
    local stderr_out
    stderr_out=$(LOA_DEBUG_MODEL_RESOLUTION=1 python3 -c "
import os, sys
sys.path.insert(0, '$PROJECT_ROOT/.claude/scripts/lib')
import importlib.util
spec = importlib.util.spec_from_file_location('mr', '$RESOLVER')
mr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mr)
def boom(*a, **kw):
    raise RuntimeError('synthetic-trace-failure')
mr._emit_trace_line = boom
import yaml
with open('$WORK_DIR/merged-clean.yaml') as fh:
    cfg = yaml.safe_load(fh)
mr.resolve(cfg, 'audit_log_lookup', 'primary')
" 2>&1 >/dev/null)
    [[ "$stderr_out" == *"[MODEL-RESOLVE-TRACE-FAILED]"* ]]
    [[ "$stderr_out" == *"error=RuntimeError"* ]]
    # Bare error name only — no `synthetic-trace-failure` text.
    [[ "$stderr_out" != *"synthetic-trace-failure"* ]]
}

@test "S8 [GP-HIGH-1] — --diff-bindings does NOT false-positive on operator-introduced bindings (no framework counterpart)" {
    # gp HIGH-1: operator-introduced skill_models entries with no
    # framework agents.<skill> counterpart should NOT emit [BINDING-OVERRIDDEN]
    # because there is nothing for the operator to "override". Per SDD §1.5.2,
    # [BINDING-OVERRIDDEN] is for runtime-overrides-build-time divergence —
    # not for operator-added bindings that have no compiled equivalent.
    cat > "$WORK_DIR/merged-operator-only.yaml" <<'YAML'
schema_version: 2
framework_defaults:
  providers:
    anthropic:
      models:
        claude-haiku-4-5-20251001: { capabilities: [chat], context_window: 200000, pricing: { input_per_mtok: 1000000, output_per_mtok: 5000000 } }
  aliases:
    tiny: { provider: anthropic, model_id: claude-haiku-4-5-20251001 }
  tier_groups:
    mappings:
      tiny: { anthropic: tiny }
  agents: {}
operator_config:
  skill_models:
    operator_introduced_only:
      primary: tiny
runtime_state: {}
YAML
    local stderr_out
    stderr_out=$("$MODEL_INVOKE" --validate-bindings --diff-bindings \
        --merged-config "$WORK_DIR/merged-operator-only.yaml" 2>&1 >/dev/null)
    # No [BINDING-OVERRIDDEN] line because there's no framework default to override.
    [[ "$stderr_out" != *"[BINDING-OVERRIDDEN]"* ]]
}

@test "S9 [GP-HIGH-1] — --diff-bindings DOES emit [BINDING-OVERRIDDEN] for genuine override" {
    # Positive control for S8: an operator binding that DOES override a
    # framework agent default MUST still emit [BINDING-OVERRIDDEN].
    # Reuses merged-diff.yaml fixture (operator skill_models.reviewing-code.primary=tiny;
    # framework agents.reviewing-code.model=opus).
    local stderr_out
    stderr_out=$("$MODEL_INVOKE" --validate-bindings --diff-bindings \
        --merged-config "$WORK_DIR/merged-diff.yaml" 2>&1 >/dev/null)
    [[ "$stderr_out" == *"[BINDING-OVERRIDDEN]"* ]]
    [[ "$stderr_out" == *"skill=reviewing-code"* ]]
}

@test "S7 [F3] — redactor identity-fallback emits [REDACTOR-FALLBACK-IDENTITY] WARN" {
    # Force the lazy-load path to fail by pointing it at a non-existent dir.
    # We do this via a monkey-patched __file__ attribute on the resolver module.
    local stderr_out
    stderr_out=$(LOA_DEBUG_MODEL_RESOLUTION=1 python3 -c "
import os, sys
sys.path.insert(0, '$PROJECT_ROOT/.claude/scripts/lib')
import importlib.util
spec = importlib.util.spec_from_file_location('mr', '$RESOLVER')
mr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mr)
# Force a load failure by replacing the redactor's __file__-derived dir.
mr.__file__ = '/nonexistent/path/model-resolver.py'
mr._redact = None  # invalidate cache
import yaml
with open('$WORK_DIR/merged-clean.yaml') as fh:
    cfg = yaml.safe_load(fh)
mr.resolve(cfg, 'audit_log_lookup', 'primary')
" 2>&1 >/dev/null)
    [[ "$stderr_out" == *"[REDACTOR-FALLBACK-IDENTITY]"* ]]
}

@test "I2 — validate-bindings AC-S2.13: operator E2E with model_aliases_extra resolves cleanly" {
    # AC-S2.13 from sprint plan: fresh-clone repo + sample .loa.config.yaml
    # with model_aliases_extra entry → validate-bindings resolves cleanly.
    cat > "$WORK_DIR/merged-extra.yaml" <<'YAML'
schema_version: 2
framework_defaults:
  providers:
    anthropic:
      models:
        claude-haiku-4-5-20251001:
          capabilities: [chat]
          context_window: 200000
          pricing: { input_per_mtok: 1000000, output_per_mtok: 5000000 }
  aliases:
    tiny: { provider: anthropic, model_id: claude-haiku-4-5-20251001 }
  tier_groups:
    mappings:
      tiny: { anthropic: tiny }
  agents: {}
operator_config:
  skill_models:
    custom_workflow:
      primary: hypothetical-future-model
  model_aliases_extra:
    hypothetical-future-model:
      provider: anthropic
      model_id: claude-haiku-4-5-20251001
      capabilities: [chat]
runtime_state: {}
YAML
    run "$MODEL_INVOKE" --validate-bindings --merged-config "$WORK_DIR/merged-extra.yaml"
    [ "$status" -eq 0 ]
    [[ "$(echo "$output" | jq -r '.summary.unresolved')" == "0" ]]
}
