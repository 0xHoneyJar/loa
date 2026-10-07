#!/usr/bin/env bats
# =============================================================================
# tests/unit/multipass-estimator.bats — cycle-126 Sprint 1 (PRD FR-1.4, SDD D-1.4)
# lib-multipass.sh estimate_token_count: an Anthropic pass uses the chars / 3.5
# bound (cheval's own estimator), never the OpenAI gpt-4 encoding; other
# providers keep the tiktoken / heuristic path.
# =============================================================================

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  # shellcheck source=/dev/null
  source "$PROJECT_ROOT/.claude/scripts/lib-multipass.sh"
  TEXT="$(printf 'a%.0s' $(seq 1 350))"   # 350 chars → ceil(350 / 3.5) = 100
}

@test "MPE-1 an Anthropic model (canonical id or alias) gets ceil(chars / 3.5)" {
  [ "$(estimate_token_count "$TEXT" claude-opus-5)" = "100" ]
  [ "$(estimate_token_count "$TEXT" opus)" = "100" ]
  [ "$(estimate_token_count "$TEXT" anthropic:claude-sonnet-5)" = "100" ]
  [ "$(estimate_token_count "$TEXT" tiny)" = "100" ]
  [ "$(estimate_token_count "ab" fable)" = "1" ]
}

@test "MPE-2 the run's model is picked up from the global run_multipass sets" {
  _MULTIPASS_MODEL="claude-fable-5-1"
  [ "$(estimate_token_count "$TEXT")" = "100" ]
  _MULTIPASS_MODEL=""
}

@test "MPE-3 a non-Anthropic model keeps the tiktoken / heuristic path (a positive integer, not the 3.5 bound by construction)" {
  n="$(estimate_token_count "$TEXT" gpt-5.5)"
  [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -gt 0 ]
  m="$(estimate_token_count "$TEXT" gemini-3.1-pro-preview)"
  [[ "$m" =~ ^[0-9]+$ ]] && [ "$m" -gt 0 ]
}
