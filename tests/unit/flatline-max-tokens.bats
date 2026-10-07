#!/usr/bin/env bats
# =============================================================================
# tests/unit/flatline-max-tokens.bats — cycle-126 Sprint 1 (PRD FR-1.6, SDD D-1.6)
# flatline-orchestrator.sh call_model sizes --max-tokens from the resolved
# catalog entry: min(64000, max_output_tokens). A 128K entry → 64000; a smaller
# entry → its own value; an entry without a declared budget → no flag (cheval's
# per-model default); --per-call-max-tokens still overrides. No 16000 literal.
# =============================================================================

setup() {
  bats_require_minimum_version 1.5.0   # `run -1 grep`: a bare `! grep` cannot fail, and only "no match" (exit 1) passes — a missing file (exit 2) fails (sprint-250 review run 1, n20; run 2, #10)
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"; export PROJECT_ROOT
  ORCHESTRATOR="$PROJECT_ROOT/.claude/scripts/flatline-orchestrator.sh"
  ARGV="$BATS_TEST_TMPDIR/argv.txt"
  SHIM="$BATS_TEST_TMPDIR/model-invoke-shim.sh"
  cat > "$SHIM" <<SHIM
printf '%s\n' "\$@" > "$ARGV"
cat <<'JSON'
{"content": "{\\"findings\\": []}", "model": "stub", "provider": "stub", "usage": {"input_tokens": 1, "output_tokens": 1}, "latency_ms": 1}
JSON
SHIM
  chmod +x "$SHIM"
  export MODEL_INVOKE="$SHIM"
  export TEMP_DIR="$BATS_TEST_TMPDIR"
  echo "doc" > "$BATS_TEST_TMPDIR/input.txt"
}

_call_model() {  # <resolved provider:model> <mode> [override]
  RESOLVED_ARG="$1" MODE_ARG="$2" OVERRIDE_ARG="${3:-}" INPUT_ARG="$BATS_TEST_TMPDIR/input.txt" ORCHESTRATOR_PATH="$ORCHESTRATOR" bash -c '
    SCRIPT_DIR="$PROJECT_ROOT/.claude/scripts"
    declare -A MODE_TO_AGENT=([review]=flatline-reviewer [skeptic]=flatline-skeptic [score]=flatline-scorer)
    DEFAULT_MODEL_TIMEOUT=30
    PER_CALL_MAX_TOKENS="$OVERRIDE_ARG"
    source "$SCRIPT_DIR/generated-model-maps.sh"
    eval "$(grep -E "^FLATLINE_VOICE_MAX_TOKENS_CAP=" "$ORCHESTRATOR_PATH")"
    eval "$(awk "/^flatline_voice_max_tokens\\(\\)/,/^}/" "$ORCHESTRATOR_PATH")"
    log() { :; }; log_invoke_failure() { :; }; cleanup_invoke_log() { :; }
    redact_secrets() { cat; }
    setup_invoke_log() { echo "$TEMP_DIR/invoke-$$.log"; }
    configured_flatline_model() { return 1; }
    resolve_provider_id() { echo "$RESOLVED_ARG"; }
    is_stage_routing_scorer_enabled() { return 1; }
    eval "$(awk "/^call_model\\(\\)/,/^}/" "$ORCHESTRATOR_PATH")"
    call_model "x" "$MODE_ARG" "$INPUT_ARG" "prd" "" "30" >/dev/null 2>&1 || true
  '
  cat "$ARGV" 2>/dev/null
}
_argv_value() { awk -v flag="$1" '$0 == flag {getline; print; exit}' "$ARGV"; }

@test "FMT-1 a 128K entry (claude-opus-5) is capped at the 64000 streaming default, for every mode" {
  for mode in review skeptic score; do
    : > "$ARGV"; _call_model anthropic:claude-opus-5 "$mode" >/dev/null
    [ "$(_argv_value --max-tokens)" = "64000" ]
  done
}

@test "FMT-2 a smaller entry passes its own catalog value (gpt-5.2 → 16000, gemini-3.1-pro-preview → 32000)" {
  _call_model openai:gpt-5.2 review >/dev/null
  [ "$(_argv_value --max-tokens)" = "16000" ]
  _call_model google:gemini-3.1-pro-preview review >/dev/null
  [ "$(_argv_value --max-tokens)" = "32000" ]
}

@test "FMT-3 an alias resolves through MODEL_IDS (opus → claude-opus-5-5 → 64000)" {
  _call_model anthropic:opus review >/dev/null
  [ "$(_argv_value --max-tokens)" = "64000" ]
}

@test "FMT-4 an entry without a declared budget passes no --max-tokens (cheval's per-model default applies)" {
  _call_model anthropic:claude-headless review >/dev/null
  [ -s "$ARGV" ]
  ! grep -qx -- '--max-tokens' "$ARGV"
}

@test "FMT-5 --per-call-max-tokens still overrides the catalog-bounded value" {
  _call_model anthropic:claude-opus-5 review 4096 >/dev/null
  [ "$(_argv_value --max-tokens)" = "4096" ]
}

@test "FMT-6 no per-call-kind literal remains in the orchestrator" {
  run -1 grep -qE '^FLATLINE_(REVIEW|SCORE)_MAX_TOKENS=' "$ORCHESTRATOR"
  grep -qE '^FLATLINE_VOICE_MAX_TOKENS_CAP=64000' "$ORCHESTRATOR"
}
