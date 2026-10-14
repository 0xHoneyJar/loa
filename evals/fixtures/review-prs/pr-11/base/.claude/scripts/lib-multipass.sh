#!/usr/bin/env bash
# =============================================================================
# lib-multipass.sh — 3-pass reasoning sandwich orchestrator
# =============================================================================
# Version: 1.0.0
# Cycle: cycle-033 (Codex CLI Integration for GPT Review)
#
# Implements the 3-pass reasoning sandwich pattern (xhigh→high→xhigh)
# with per-pass context budgets, failure handling, and intermediate
# output persistence.
#
# Used by:
#   - gpt-review-api.sh (multi-pass review via route_review)
#
# Functions:
#   run_multipass <system> <user> <model> <workspace> <timeout> <output_file> <review_type> [tool_access]
#   estimate_token_count <text>        → approximate token count to stdout
#   enforce_token_budget <content> <budget> → truncated content to stdout
#   check_budget_overflow <elapsed> <pass_timeout> <total_budget> → 0=ok, 1=overflow
#   build_pass1_prompt <system> <user>
#   build_pass2_prompt <system> <content> <pass1_context>
#   build_pass3_prompt <system> <pass2_findings>
#   build_combined_prompt <system> <user>
#   inject_verification_skipped <json>
#
# Design decisions:
#   - Reasoning sandwich: xhigh→high→xhigh from LangChain harness pattern
#   - Token budgets configurable via config + env (SDD §3.3, Flatline IMP-001)
#   - CI concurrency via $CI_JOB_ID or $$ prefix (Flatline IMP-002)
#   - timeout(1) per-pass wrapping (Flatline IMP-004)
#   - Secret redaction on all intermediate outputs (SDD §3.3)
#
# IMPORTANT: This file must NOT call any function at the top level.

# Guard against double-sourcing
if [[ "${_LIB_MULTIPASS_LOADED:-}" == "true" ]]; then
  return 0 2>/dev/null || true
fi
_LIB_MULTIPASS_LOADED="true"

# =============================================================================
# Dependencies
# =============================================================================

if [[ "${_LIB_CODEX_EXEC_LOADED:-}" != "true" ]]; then
  _lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  source "$_lib_dir/lib-codex-exec.sh"
  unset _lib_dir
fi

# =============================================================================
# Constants / Configurable Budgets
# =============================================================================

_read_mp_config() {
  local key="$1" default="$2"
  # Input guard: restrict keys to safe yq path characters (cycle-034, Bridge medium-1)
  # Prevents yq expression injection if future callers pass untrusted input
  # Note: hyphens intentionally excluded — all config keys use underscores
  if [[ ! "$key" =~ ^[.a-zA-Z0-9_]+$ ]]; then
    echo "$default"
    return
  fi
  if [[ -f "${CONFIG_FILE:-.loa.config.yaml}" ]] && command -v yq &>/dev/null; then
    local v; v=$(yq eval "$key // \"\"" "${CONFIG_FILE:-.loa.config.yaml}" 2>/dev/null) || v=""
    [[ -n "$v" && "$v" != "null" ]] && { echo "$v"; return; }
  fi
  echo "$default"
}

# Token budgets (IMP-001: configurable via config + env)
PASS1_OUTPUT_BUDGET="${GPT_REVIEW_PASS1_OUTPUT_BUDGET:-$(_read_mp_config '.gpt_review.pass_budgets.pass1_output' 4000)}"
PASS2_INPUT_BUDGET="${GPT_REVIEW_PASS2_INPUT_BUDGET:-$(_read_mp_config '.gpt_review.pass_budgets.pass2_input' 20000)}"
PASS2_OUTPUT_BUDGET="${GPT_REVIEW_PASS2_OUTPUT_BUDGET:-$(_read_mp_config '.gpt_review.pass_budgets.pass2_output' 6000)}"
PASS3_INPUT_BUDGET="${GPT_REVIEW_PASS3_INPUT_BUDGET:-$(_read_mp_config '.gpt_review.pass_budgets.pass3_input' 6000)}"

# Per-pass timeouts (IMP-004: configurable)
PASS1_TIMEOUT="${CODEX_PASS1_TIMEOUT:-}"
PASS2_TIMEOUT="${CODEX_PASS2_TIMEOUT:-}"
PASS3_TIMEOUT="${CODEX_PASS3_TIMEOUT:-}"

# CI concurrency prefix (IMP-002)
_MP_PREFIX="${CI_JOB_ID:-$$}"

# =============================================================================
# Token Estimation (IMP-001)
# =============================================================================

# Approximate token count using chars/4 heuristic.
# If tiktoken is available, use it for better accuracy.
# Args: text
# Outputs: token count to stdout
estimate_token_count() {
  local text="$1"
  local char_count=${#text}

  # Try tiktoken if available (within 5% accuracy)
  # Pipe text via stdin to avoid command injection from content
  if command -v python3 &>/dev/null; then
    local tk_count
    tk_count=$(printf '%s' "${text:0:400000}" | python3 -c "
import sys
try:
    import tiktoken
    enc = tiktoken.encoding_for_model('gpt-4')
    print(len(enc.encode(sys.stdin.read())))
except:
    print(-1)
" 2>/dev/null) || tk_count="-1"
    if [[ "$tk_count" != "-1" && "$tk_count" -gt 0 ]]; then
      echo "$tk_count"
      return 0
    fi
  fi

  # Tier 2: hybrid word+char heuristic (calibrated ≤15% mean, ≤25% p95 error)
  # Pure word-count (~1.33 tok/word) underestimates for code (~2.2 tok/word).
  # Blending words*1.1 + chars/7 accounts for punctuation tokens in code/JSON/YAML.
  local word_count
  word_count=$(printf '%s' "$text" | wc -w) || word_count=0
  if [[ "$word_count" -gt 0 ]]; then
    echo $(( word_count * 11 / 10 + (char_count + 6) / 7 ))
    return 0
  fi

  # Tier 3: chars/4 heuristic (fallback for empty word-count edge case)
  echo $(( (char_count + 3) / 4 ))
}

# =============================================================================
# Token Budget Enforcement
# =============================================================================

# Truncate content to fit within token budget.
# Priority: findings > context > metadata.
# Args: content budget_tokens
# Outputs: truncated content to stdout
enforce_token_budget() {
  local content="$1"
  local budget="$2"

  local current; current=$(estimate_token_count "$content")
  if [[ "$current" -le "$budget" ]]; then
    echo "$content"
    return 0
  fi

  # Truncate to approximate character limit (budget * 4)
  local char_limit=$(( budget * 4 ))
  local truncated="${content:0:$char_limit}"

  # If JSON, try to preserve structure
  if echo "$truncated" | jq empty 2>/dev/null; then
    echo "$truncated"
  else
    # Try to truncate JSON content field if present
    if echo "$content" | jq -e '.findings' &>/dev/null; then
      # Preserve findings, truncate other fields
      echo "$content" | jq --argjson limit "$char_limit" '
        if (.summary | length) > ($limit / 2) then
          .summary = (.summary | .[:($limit/2)] + "... [truncated]")
        else . end
      '
    else
      printf '%s\n[TRUNCATED: exceeded %d token budget]' "$truncated" "$budget"
    fi
  fi
}

# Check if total time budget is exceeded.
# Args: elapsed_seconds pass_timeout total_budget
# Returns: 0 if OK, 1 if overflow (caller should switch to --fast)
check_budget_overflow() {
  local elapsed="$1"
  local pass_timeout="$2"
  local total_budget="$3"

  local remaining=$(( total_budget - elapsed ))
  if (( remaining < pass_timeout )); then
    echo "[multipass] WARNING: Budget overflow: ${remaining}s remaining < ${pass_timeout}s per-pass — switching to --fast" >&2
    return 1
  fi
  return 0
}

# =============================================================================
# Pass-Specific Prompt Builders (Task 2.2)
# =============================================================================

# Pass 1: Deep planning analysis (xhigh reasoning)
build_pass1_prompt() {
  local system="$1" user="$2"
  printf '%s\n\n---\n\n## REASONING INSTRUCTIONS (Pass 1: Planning — Deep Analysis)\n\nYou are performing deep planning analysis. Think step-by-step about the full codebase structure, dependencies, and change surface area before summarizing.\n\nAnalyze:\n1. What files and modules are affected by these changes?\n2. What are the dependency chains and potential ripple effects?\n3. What test coverage exists for the changed code?\n4. What security boundaries are crossed?\n\nOutput a structured JSON context summary with keys: scope_analysis, dependency_map, risk_areas, test_gaps.\n\n---\n\n%s\n\n---\n\nRespond with valid JSON only.' "$system" "$user"
}

# Pass 2: Efficient finding detection (high reasoning)
build_pass2_prompt() {
  local system="$1" content="$2" pass1_context="$3"
  printf '%s\n\n---\n\n## REASONING INSTRUCTIONS (Pass 2: Review — Efficient Detection)\n\nYou are performing an efficient code review. Focus on finding concrete bugs, security issues, and fabrication. Do not over-analyze. Be concise and specific.\n\n### Context from Planning Pass:\n%s\n\n---\n\n## CONTENT TO REVIEW:\n\n%s\n\n---\n\nRespond with valid JSON matching the review schema. Include "verdict": "APPROVED"|"CHANGES_REQUIRED"|"DECISION_NEEDED".' "$system" "$pass1_context" "$content"
}

# Pass 3: Verification quality gate (xhigh reasoning)
build_pass3_prompt() {
  local system="$1" pass2_findings="$2"
  printf '%s\n\n---\n\n## REASONING INSTRUCTIONS (Pass 3: Verification — Quality Gate)\n\nYou are the final verification gate. For each finding from the previous review, verify:\n1. The file:line reference exists and is accurate\n2. The issue is real, not speculative\n3. The suggested fix is correct and complete\n\nRemove false positives. Validate severity ratings. Output the final verdict.\n\n### Findings to Verify:\n%s\n\n---\n\nRespond with valid JSON matching the review schema. Include "verdict": "APPROVED"|"CHANGES_REQUIRED"|"DECISION_NEEDED".' "$system" "$pass2_findings"
}

# Combined prompt for --fast single-pass mode
build_combined_prompt() {
  local system="$1" user="$2"
  printf '%s\n\n---\n\n## REASONING INSTRUCTIONS (Single-Pass Review)\n\nPerform a thorough code review in a single pass:\n1. Analyze the codebase structure and change scope\n2. Find concrete bugs, security issues, and quality problems\n3. Verify your findings are real, not speculative — check file:line references\n\nBe concise but thorough. Prioritize security and correctness.\n\n---\n\n## CONTENT TO REVIEW:\n\n%s\n\n---\n\nRespond with valid JSON matching the review schema. Include "verdict": "APPROVED"|"CHANGES_REQUIRED"|"DECISION_NEEDED".' "$system" "$user"
}

# =============================================================================
# Verification Injection (Task 2.3/2.4)
# =============================================================================

# Add verification=skipped to Pass 2 output when Pass 3 fails.
# Args: json_content
# Outputs: modified JSON to stdout
inject_verification_skipped() {
  local json="$1"
  echo "$json" | jq '. + {"verification": "skipped"}'
}

# =============================================================================
# Complexity Classification (cycle-034, SDD §3.3.1)
# =============================================================================

# Classify change complexity using deterministic diff signals.
# Args: user_content (the diff/review content)
# Returns: "low" | "medium" | "high" to stdout
classify_complexity() {
  local content="$1"

  local files_changed=0 lines_changed=0 security_hit=false

  # Count files and lines from diff markers
  files_changed=$(echo "$content" | grep -c '^diff --git' 2>/dev/null) || files_changed=0
  lines_changed=$(echo "$content" | grep -cE '^\+[^+]|^-[^-]' 2>/dev/null) || lines_changed=0

  # Security-sensitive path check (never-single-pass denylist)
  # Segment-anchored patterns prevent false positives (cycle-034, Bridge medium-2)
  # e.g. "auth/" matches but "authorization/" does not; ".env" matches but "environment.ts" does not
  local -a security_patterns=(
    '/\.claude/'              # .claude/ directory
    '/lib-security(/| )'      # lib-security directory
    '/auth(/| )'              # auth/ directory (not authorization/)
    '/credentials(/| |\.)'    # credentials dir or file
    '/secrets(/| |\.)'        # secrets dir or file
    '/\.env( |\.|$)'          # .env file (not environment.ts)
  )
  local pattern
  for pattern in "${security_patterns[@]}"; do
    if echo "$content" | grep -qE "^diff --git.*${pattern}"; then
      security_hit=true
      break
    fi
  done

  # Classify
  if [[ "$security_hit" == "true" ]]; then
    echo "high"
  elif [[ $files_changed -gt 15 || $lines_changed -gt 2000 ]]; then
    echo "high"
  elif [[ $files_changed -gt 3 || $lines_changed -gt 200 ]]; then
    echo "medium"
  else
    echo "low"
  fi
}

# Reclassify after Pass 1 using model signals.
# Requires BOTH signals to agree for single-pass (PRD FR-2.1).
# Args: det_level pass1_output
# Returns: "low" | "medium" | "high" to stdout
reclassify_with_model_signals() {
  local det_level="$1" pass1_output="$2"

  local risk_areas scope_tokens
  risk_areas=$(echo "$pass1_output" | jq -r '.complexity.risk_area_count // .risk_areas // 0' 2>/dev/null) || risk_areas=0
  scope_tokens=$(estimate_token_count "$pass1_output")

  # Configurable thresholds
  local low_risk high_risk low_scope high_scope
  low_risk=$(_read_mp_config '.gpt_review.multipass.thresholds.low_risk_areas' 3)
  high_risk=$(_read_mp_config '.gpt_review.multipass.thresholds.high_risk_areas' 6)
  low_scope=$(_read_mp_config '.gpt_review.multipass.thresholds.low_scope_tokens' 500)
  high_scope=$(_read_mp_config '.gpt_review.multipass.thresholds.high_scope_tokens' 2000)

  local model_level="medium"
  if [[ $risk_areas -le $low_risk && $scope_tokens -le $low_scope ]]; then
    model_level="low"
  elif [[ $risk_areas -gt $high_risk || $scope_tokens -gt $high_scope ]]; then
    model_level="high"
  fi

  # Dual-signal matrix: single-pass requires BOTH signals low
  if [[ "$det_level" == "low" && "$model_level" == "low" ]]; then
    echo "low"
  elif [[ "$det_level" == "high" || "$model_level" == "high" ]]; then
    echo "high"
  else
    echo "medium"
  fi
}

# =============================================================================
# Main Orchestrator (Task 2.1)
# =============================================================================

# Execute 3-pass reasoning sandwich review (with adaptive classification).
# Args: system user model workspace timeout output_file review_type [tool_access]
# Returns: 0 on success, 1 on failure
# Outputs: final review JSON to output_file
run_multipass() {
  local system="$1"
  local user="$2"
  local model="$3"
  local workspace="$4"
  local timeout="$5"
  local output_file="$6"
  local review_type="${7:-code}"
  local tool_access="${8:-false}"

  local output_dir="grimoires/loa/a2a/gpt-review"
  mkdir -p "$output_dir"

  local total_start=$SECONDS
  local total_budget=$(( timeout * 3 ))  # Total budget = 3x single-pass timeout
  local pass_timeout="$timeout"

  # Adaptive classification (cycle-034, SDD §3.3.2)
  # GPT_REVIEW_ADAPTIVE env var overrides config (Task 3.4)
  local adaptive="true"
  if [[ -n "${GPT_REVIEW_ADAPTIVE:-}" ]]; then
    [[ "${GPT_REVIEW_ADAPTIVE}" == "0" ]] && adaptive="false" || adaptive="true"
  else
    adaptive=$(_read_mp_config '.gpt_review.multipass.adaptive' 'true')
  fi

  local det_level=""
  if [[ "$adaptive" == "true" ]]; then
    det_level=$(classify_complexity "$user")
    echo "[multipass] Adaptive mode: det_level=$det_level" >&2
  fi

  echo "[multipass] Starting 3-pass review (model=$model, budget=${total_budget}s, adaptive=$adaptive)" >&2

  # === Pass 1: Planning (xhigh) ===
  echo "[multipass] Pass 1/3: Planning (deep context analysis)..." >&2
  local p1_timeout="${PASS1_TIMEOUT:-$pass_timeout}"
  local p1_prompt; p1_prompt=$(build_pass1_prompt "$system" "$user")
  local p1_file="$output_dir/${review_type}-pass-1-${_MP_PREFIX}.json"

  local p1_exit=0
  codex_exec_single "$p1_prompt" "$model" "$p1_file" "$workspace" "$p1_timeout" || p1_exit=$?

  if [[ $p1_exit -ne 0 ]] || [[ ! -s "$p1_file" ]]; then
    echo "[multipass] WARNING: Pass 1 failed (exit $p1_exit) — falling back to single-pass" >&2
    local combined; combined=$(build_combined_prompt "$system" "$user")
    codex_exec_single "$combined" "$model" "$output_file" "$workspace" "$pass_timeout"
    local sp_exit=$?
    if [[ $sp_exit -eq 0 && -s "$output_file" ]]; then
      local sp_raw; sp_raw=$(cat "$output_file")
      local sp_parsed; sp_parsed=$(parse_codex_output "$sp_raw" 2>/dev/null) || sp_parsed=""
      if [[ -n "$sp_parsed" ]]; then
        sp_parsed=$(echo "$sp_parsed" | jq '. + {"pass_metadata": {"passes_completed": 1, "mode": "single-pass-fallback"}}')
        redact_secrets "$sp_parsed" "json" > "$output_file"
        return 0
      fi
    fi
    return $sp_exit
  fi

  local p1_raw; p1_raw=$(cat "$p1_file")
  local p1_output; p1_output=$(parse_codex_output "$p1_raw" 2>/dev/null) || p1_output="$p1_raw"
  p1_output=$(redact_secrets "$p1_output" "auto")
  p1_output=$(enforce_token_budget "$p1_output" "$PASS1_OUTPUT_BUDGET")

  local p1_elapsed=$(( SECONDS - total_start ))
  local p1_tokens; p1_tokens=$(estimate_token_count "$p1_output")
  echo "[multipass] Pass 1 complete: ${p1_elapsed}s, ~${p1_tokens} tokens" >&2

  # Adaptive decision: reclassify with model signals (cycle-034)
  if [[ "$adaptive" == "true" && -n "$det_level" ]]; then
    local final_level
    final_level=$(reclassify_with_model_signals "$det_level" "$p1_output")
    echo "[multipass] Adaptive reclassification: det=$det_level → final=$final_level" >&2

    if [[ "$final_level" == "low" ]]; then
      # Low complexity → return Pass 1 output as combined review
      echo "[multipass] Adaptive: low complexity — returning Pass 1 as single-pass" >&2
      local p1_review
      p1_review=$(echo "$p1_output" | jq --argjson e "$p1_elapsed" \
        '. + {"pass_metadata": {"passes_completed": 1, "mode": "adaptive-single-pass", "complexity": "low", "total_elapsed_s": $e}}' 2>/dev/null) || p1_review="$p1_output"
      redact_secrets "$p1_review" "json" > "$output_file"
      return 0
    elif [[ "$final_level" == "high" ]]; then
      # High complexity → use extended budgets for Pass 2
      echo "[multipass] Adaptive: high complexity — using extended budgets" >&2
      PASS2_INPUT_BUDGET=$(_read_mp_config '.gpt_review.multipass.budgets.high_complexity.pass2_input' 30000)
      PASS2_OUTPUT_BUDGET=$(_read_mp_config '.gpt_review.multipass.budgets.high_complexity.pass2_output' 10000)
    fi
    # medium → standard 3-pass (no changes)
  fi

  # Check budget before Pass 2
  if ! check_budget_overflow "$p1_elapsed" "$pass_timeout" "$total_budget"; then
    echo "[multipass] Auto-switching to --fast due to budget overflow" >&2
    local combined; combined=$(build_combined_prompt "$system" "$user")
    codex_exec_single "$combined" "$model" "$output_file" "$workspace" "$pass_timeout"
    local sp_exit=$?
    if [[ $sp_exit -eq 0 && -s "$output_file" ]]; then
      local sp_raw; sp_raw=$(cat "$output_file")
      local sp_parsed; sp_parsed=$(parse_codex_output "$sp_raw" 2>/dev/null) || sp_parsed=""
      if [[ -n "$sp_parsed" ]]; then
        sp_parsed=$(echo "$sp_parsed" | jq --argjson e "$p1_elapsed" '. + {"pass_metadata": {"passes_completed": 1, "mode": "budget-overflow-fallback", "pass1_elapsed_s": $e}}')
        redact_secrets "$sp_parsed" "json" > "$output_file"
        return 0
      fi
    fi
    return $sp_exit
  fi

  # === Pass 2: Review (high) ===
  echo "[multipass] Pass 2/3: Review (finding detection)..." >&2
  local p2_timeout="${PASS2_TIMEOUT:-$pass_timeout}"
  local truncated_user; truncated_user=$(enforce_token_budget "$user" "$PASS2_INPUT_BUDGET")
  local p2_prompt; p2_prompt=$(build_pass2_prompt "$system" "$truncated_user" "$p1_output")
  local p2_file="$output_dir/${review_type}-pass-2-${_MP_PREFIX}.json"

  local p2_exit=0
  codex_exec_single "$p2_prompt" "$model" "$p2_file" "$workspace" "$p2_timeout" || p2_exit=$?

  if [[ $p2_exit -ne 0 ]] || [[ ! -s "$p2_file" ]]; then
    echo "[multipass] WARNING: Pass 2 failed (exit $p2_exit) — retrying once" >&2
    p2_exit=0
    codex_exec_single "$p2_prompt" "$model" "$p2_file" "$workspace" "$p2_timeout" || p2_exit=$?
    if [[ $p2_exit -ne 0 ]] || [[ ! -s "$p2_file" ]]; then
      echo "[multipass] ERROR: Pass 2 retry failed (exit $p2_exit)" >&2
      return 1
    fi
  fi

  local p2_raw; p2_raw=$(cat "$p2_file")
  local p2_output; p2_output=$(parse_codex_output "$p2_raw" 2>/dev/null) || p2_output="$p2_raw"
  p2_output=$(redact_secrets "$p2_output" "auto")
  p2_output=$(enforce_token_budget "$p2_output" "$PASS2_OUTPUT_BUDGET")

  local p2_elapsed=$(( SECONDS - total_start ))
  local p2_tokens; p2_tokens=$(estimate_token_count "$p2_output")
  echo "[multipass] Pass 2 complete: ${p2_elapsed}s total, ~${p2_tokens} tokens" >&2

  # Check budget before Pass 3
  if ! check_budget_overflow "$p2_elapsed" "$pass_timeout" "$total_budget"; then
    echo "[multipass] Skipping Pass 3 — budget overflow; returning Pass 2 with verification=skipped" >&2
    local p2_final; p2_final=$(inject_verification_skipped "$p2_output")
    p2_final=$(echo "$p2_final" | jq --argjson e "$p2_elapsed" '. + {"pass_metadata": {"passes_completed": 2, "mode": "budget-overflow-skip-p3", "total_elapsed_s": $e}}')
    redact_secrets "$p2_final" "json" > "$output_file"
    return 0
  fi

  # === Pass 3: Verification (xhigh) ===
  echo "[multipass] Pass 3/3: Verification (quality gate)..." >&2
  local p3_timeout="${PASS3_TIMEOUT:-$pass_timeout}"
  local p3_prompt; p3_prompt=$(build_pass3_prompt "$system" "$p2_output")
  local p3_file="$output_dir/${review_type}-pass-3-${_MP_PREFIX}.json"

  local p3_exit=0
  codex_exec_single "$p3_prompt" "$model" "$p3_file" "$workspace" "$p3_timeout" || p3_exit=$?

  if [[ $p3_exit -ne 0 ]] || [[ ! -s "$p3_file" ]]; then
    echo "[multipass] WARNING: Pass 3 failed (exit $p3_exit) — returning Pass 2 with verification=skipped" >&2
    local p2_final; p2_final=$(inject_verification_skipped "$p2_output")
    p2_final=$(echo "$p2_final" | jq --argjson e "$(( SECONDS - total_start ))" '. + {"pass_metadata": {"passes_completed": 2, "verification": "skipped", "total_elapsed_s": $e}}')
    redact_secrets "$p2_final" "json" > "$output_file"
    return 0
  fi

  local p3_raw; p3_raw=$(cat "$p3_file")
  local p3_output; p3_output=$(parse_codex_output "$p3_raw" 2>/dev/null) || p3_output="$p3_raw"

  # Add pass_metadata (Task 2.4)
  local total_elapsed=$(( SECONDS - total_start ))
  local p1_tc; p1_tc=$(estimate_token_count "$p1_output")
  local p2_tc; p2_tc=$(estimate_token_count "$p2_output")
  local p3_tc; p3_tc=$(estimate_token_count "$p3_output")

  p3_output=$(echo "$p3_output" | jq \
    --argjson p1t "$p1_tc" --argjson p2t "$p2_tc" --argjson p3t "$p3_tc" \
    --argjson elapsed "$total_elapsed" \
    '. + {"verification": "passed", "pass_metadata": {"passes_completed": 3, "mode": "multi-pass", "pass1_tokens": $p1t, "pass2_tokens": $p2t, "pass3_tokens": $p3t, "total_elapsed_s": $elapsed}}')

  redact_secrets "$p3_output" "json" > "$output_file"

  echo "[multipass] All 3 passes complete: ${total_elapsed}s total" >&2
  return 0
}
