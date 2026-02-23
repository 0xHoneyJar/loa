#!/usr/bin/env bash
# =============================================================================
# lib-route-table.sh — Declarative execution router
# =============================================================================
# Version: 1.0.0
# Cycle: cycle-034 (Declarative Execution Router + Adaptive Multi-Pass)
#
# Replaces imperative if/else cascade in route_review() with a YAML-driven
# route table. Routing decisions move from bash logic into .loa.config.yaml.
#
# Used by:
#   - gpt-review-api.sh (via route_review)
#
# Architecture:
#   - Parallel arrays for route table (bash has no nested data types)
#   - Associative arrays for condition + backend registries
#   - No eval, no dynamic function construction, no user-supplied code execution
#
# Configuration precedence (Flatline IMP-009):
#   LOA_LEGACY_ROUTER > LOA_CUSTOM_ROUTES > execution_mode > routes > defaults
#
# YAML Schema (v1, Flatline IMP-004):
#
#   gpt_review:
#     route_schema: 1          # Schema version (required if routes present)
#     routes:
#       - backend: hounfour    # Required: registered backend name
#         when:                # Required: condition names (AND logic)
#           - flatline_routing_enabled
#           - model_invoke_available
#         capabilities:        # Optional: capability tags
#           - agent_binding
#           - metering
#         fail_mode: fallthrough  # "fallthrough" (default) | "hard_fail"
#         timeout: 300         # Optional: per-route timeout 1-600s
#         retries: 0           # Optional: per-route retries 0-5
#
# IMPORTANT: This file must NOT call any function at the top level.
# It is designed to be sourced by other scripts.

# Guard against double-sourcing
if [[ "${_LIB_ROUTE_TABLE_LOADED:-}" == "true" ]]; then
  return 0 2>/dev/null || true
fi
_LIB_ROUTE_TABLE_LOADED="true"

# =============================================================================
# Constants
# =============================================================================

# Policy constraints
_RT_MAX_ROUTES="${_RT_MAX_ROUTES:-10}"

# Global max total attempts across all routes (Flatline SKP-005)
_RT_MAX_TOTAL_ATTEMPTS="${_RT_MAX_TOTAL_ATTEMPTS:-10}"

# Bounds for per-route timeout and retries (Flatline SKP-005)
_RT_TIMEOUT_MIN=1
_RT_TIMEOUT_MAX=600
_RT_RETRIES_MIN=0
_RT_RETRIES_MAX=5

# =============================================================================
# Data Structures (SDD §3.1.1)
# =============================================================================

# Route table — parallel arrays
declare -a _RT_BACKENDS=()       # ("hounfour" "codex" "curl")
declare -a _RT_CONDITIONS=()     # ("flatline_routing_enabled,model_invoke_available" ...)
declare -a _RT_CAPABILITIES=()   # ("agent_binding,metering" ...)
declare -a _RT_FAIL_MODES=()     # ("fallthrough" "fallthrough" "hard_fail")
declare -a _RT_TIMEOUTS=()       # ("" "" "") — per-route timeout overrides
declare -a _RT_RETRIES=()        # ("0" "0" "0") — per-route retry counts

# Registries — associative arrays
declare -A _CONDITION_REGISTRY=()
declare -A _BACKEND_REGISTRY=()

# =============================================================================
# Parallel Array Safety (Flatline SKP-002)
# =============================================================================

# Atomically append a route to all 6 parallel arrays.
# Prevents desynchronization by ensuring all arrays grow together.
# Args: backend conditions capabilities fail_mode timeout retries
_rt_append_route() {
  local backend="$1" conditions="$2" capabilities="${3:-}" fail_mode="${4:-fallthrough}"
  local timeout="${5:-}" retries="${6:-0}"

  _RT_BACKENDS+=("$backend")
  _RT_CONDITIONS+=("$conditions")
  _RT_CAPABILITIES+=("$capabilities")
  _RT_FAIL_MODES+=("$fail_mode")
  _RT_TIMEOUTS+=("$timeout")
  _RT_RETRIES+=("$retries")
}

# Assert all _RT_* arrays have identical length.
# Returns: 0 if valid, 1 if desynchronized
_rt_validate_array_lengths() {
  local expected=${#_RT_BACKENDS[@]}

  if [[ ${#_RT_CONDITIONS[@]} -ne $expected ]] ||
     [[ ${#_RT_CAPABILITIES[@]} -ne $expected ]] ||
     [[ ${#_RT_FAIL_MODES[@]} -ne $expected ]] ||
     [[ ${#_RT_TIMEOUTS[@]} -ne $expected ]] ||
     [[ ${#_RT_RETRIES[@]} -ne $expected ]]; then
    error "FATAL: Route table array desynchronization detected"
    error "  BACKENDS=${#_RT_BACKENDS[@]} CONDITIONS=${#_RT_CONDITIONS[@]} CAPABILITIES=${#_RT_CAPABILITIES[@]}"
    error "  FAIL_MODES=${#_RT_FAIL_MODES[@]} TIMEOUTS=${#_RT_TIMEOUTS[@]} RETRIES=${#_RT_RETRIES[@]}"
    return 1
  fi
  return 0
}

# =============================================================================
# Default Route Table (SDD §3.1.9)
# =============================================================================

# Load built-in default route table matching cycle-033 behavior:
#   hounfour → codex → curl
_rt_load_defaults() {
  _RT_BACKENDS=() _RT_CONDITIONS=() _RT_CAPABILITIES=()
  _RT_FAIL_MODES=() _RT_TIMEOUTS=() _RT_RETRIES=()

  _rt_append_route "hounfour" \
    "flatline_routing_enabled,model_invoke_available" \
    "agent_binding,metering,trust_scopes" \
    "fallthrough" "" "0"

  _rt_append_route "codex" \
    "codex_available" \
    "sandbox,ephemeral,multi_pass,tool_access" \
    "fallthrough" "" "0"

  _rt_append_route "curl" \
    "always" \
    "basic" \
    "hard_fail" "" "0"
}

# =============================================================================
# Condition Registry (SDD §3.1.4)
# =============================================================================

_cond_always() { return 0; }

_cond_flatline_routing_enabled() {
  is_flatline_routing_enabled
}

_cond_model_invoke_available() {
  [[ -x "${MODEL_INVOKE:-}" ]]
}

_cond_codex_available() {
  codex_is_available
}

register_builtin_conditions() {
  _CONDITION_REGISTRY=(
    ["always"]="_cond_always"
    ["flatline_routing_enabled"]="_cond_flatline_routing_enabled"
    ["model_invoke_available"]="_cond_model_invoke_available"
    ["codex_available"]="_cond_codex_available"
  )
}

# =============================================================================
# Backend Registry (SDD §3.1.5)
# =============================================================================

# Backend functions take: model sys usr timeout fast tool_access reasoning_mode review_type route_idx
# Return: 0 + JSON on stdout (success), non-zero (failure)

_backend_hounfour() {
  local model="$1" sys="$2" usr="$3" timeout="$4"
  call_api_via_model_invoke "$model" "$sys" "$usr" "$timeout"
}

_backend_codex() {
  local model="$1" sys="$2" usr="$3" timeout="$4"
  local fast="${5:-false}" ta="${6:-false}" rm="${7:-single-pass}" rtype="${8:-code}"
  local route_idx="${9:-0}"

  # Check multi-pass capability from route table
  local caps="${_RT_CAPABILITIES[$route_idx]:-}"
  local has_multipass=false
  [[ "$caps" == *"multi_pass"* ]] && has_multipass=true

  # Single workspace lifecycle — reuse across multipass/single-pass (cycle-034, Bridge medium-3)
  local ws of
  ws=$(setup_review_workspace "" "$ta")

  # Try multipass if conditions met
  if [[ "$rm" == "multi-pass" && "$fast" != "true" && "$has_multipass" == "true" ]]; then
    of=$(mktemp "${ws}/out-mp-$$.XXXXXX")
    local me=0
    run_multipass "$sys" "$usr" "$model" "$ws" "$timeout" "$of" "$rtype" "$ta" || me=$?
    if [[ $me -eq 0 && -s "$of" ]]; then
      local result; result=$(cat "$of")
      if echo "$result" | jq -e '.verdict' &>/dev/null; then
        cleanup_workspace "$ws"
        echo "$result"; return 0
      fi
      log "WARNING: multipass returned non-verdict output, falling back to single-pass codex"
    else
      log "WARNING: multipass failed (exit=$me), falling back to single-pass codex"
    fi
    # Fall through to single-pass using same workspace
  elif [[ "$rm" == "multi-pass" && "$has_multipass" != "true" ]]; then
    log "WARNING: Backend 'codex' lacks multi_pass capability; downgrading to single-pass"
  fi

  # Single-pass codex (also serves as multipass fallback)
  of=$(mktemp "${ws}/out-sp-$$.XXXXXX")
  local cp
  cp=$(printf '%s\n\n---\n\n## CONTENT TO REVIEW:\n\n%s\n\n---\n\nRespond with valid JSON only. Include "verdict": "APPROVED"|"CHANGES_REQUIRED"|"DECISION_NEEDED".' "$sys" "$usr")
  local ee=0
  codex_exec_single "$cp" "$model" "$of" "$ws" "$timeout" || ee=$?
  if [[ $ee -eq 0 && -s "$of" ]]; then
    local raw; raw=$(cat "$of")
    local pr; pr=$(parse_codex_output "$raw" 2>/dev/null) || pr=""
    if [[ -n "$pr" ]]; then
      cleanup_workspace "$ws"
      echo "$pr"; return 0
    fi
  fi
  cleanup_workspace "$ws"
  return 1
}

_backend_curl() {
  local model="$1" sys="$2" usr="$3" timeout="$4"
  call_api "$model" "$sys" "$usr" "$timeout"
}

register_builtin_backends() {
  _BACKEND_REGISTRY=(
    ["hounfour"]="_backend_hounfour"
    ["codex"]="_backend_codex"
    ["curl"]="_backend_curl"
  )
}

# =============================================================================
# Clamp Utility
# =============================================================================

# Clamp an integer value to [min, max] bounds.
# Args: value min max
# Returns: clamped value to stdout
_rt_clamp() {
  local val="$1" min="$2" max="$3"
  # Validate numeric
  if ! [[ "$val" =~ ^[0-9]+$ ]]; then
    echo "$min"
    return
  fi
  if [[ $val -lt $min ]]; then echo "$min"
  elif [[ $val -gt $max ]]; then echo "$max"
  else echo "$val"
  fi
}

# =============================================================================
# YAML Parser (SDD §3.1.2, Task 1.2)
# =============================================================================

# Check yq version. Returns 0 for v4+, 1 for v3 or unknown.
# Flatline IMP-003: reject v3 with clear error message.
_rt_check_yq_version() {
  local ver_output
  ver_output=$(yq --version 2>&1) || { error "yq --version failed"; return 1; }

  # yq v4+ output: "yq (https://github.com/mikefarah/yq/) version v4.x.x"
  # yq v3 output: "yq version 3.x.x"
  if echo "$ver_output" | grep -qE 'version [v]?3\.'; then
    error "yq v3 detected. Loa requires yq v4+."
    error "Install: https://github.com/mikefarah/yq/#install"
    error "Detected: $ver_output"
    return 1
  fi

  # Accept v4+ or unrecognized (newer versions)
  return 0
}

# Parse YAML route table into parallel arrays.
# Args: config_file
# Returns: 0 on success, 2 on parse error
# Side effects: populates _RT_* arrays via _rt_append_route()
parse_route_table() {
  local config_file="${1:-$CONFIG_FILE}"

  # Check for custom routes
  local route_count
  route_count=$(yq eval '.gpt_review.routes | length // 0' "$config_file" 2>/dev/null) || route_count=0

  if [[ "$route_count" -eq 0 ]]; then
    _rt_load_defaults
    log "[route-table] Using default route table (no gpt_review.routes in config)"
    return 0
  fi

  # Check schema version
  local schema_ver
  schema_ver=$(yq eval '.gpt_review.route_schema // 1' "$config_file" 2>/dev/null) || schema_ver=1
  if [[ "$schema_ver" -gt 1 ]]; then
    error "Route table schema version $schema_ver not supported (max: 1). Upgrade Loa."
    return 2
  fi

  # Parse each route
  local i
  for ((i = 0; i < route_count; i++)); do
    local backend when caps fail_mode route_timeout route_retries
    backend=$(yq eval ".gpt_review.routes[$i].backend // \"\"" "$config_file")
    when=$(yq eval ".gpt_review.routes[$i].when | join(\",\")" "$config_file" 2>/dev/null) || when=""
    caps=$(yq eval ".gpt_review.routes[$i].capabilities | join(\",\")" "$config_file" 2>/dev/null) || caps=""
    fail_mode=$(yq eval ".gpt_review.routes[$i].fail_mode // \"fallthrough\"" "$config_file")
    route_timeout=$(yq eval ".gpt_review.routes[$i].timeout // \"\"" "$config_file" 2>/dev/null) || route_timeout=""
    route_retries=$(yq eval ".gpt_review.routes[$i].retries // \"0\"" "$config_file" 2>/dev/null) || route_retries="0"

    # Clamp timeout and retries to bounds (Flatline SKP-005)
    if [[ -n "$route_timeout" && "$route_timeout" != "null" ]]; then
      route_timeout=$(_rt_clamp "$route_timeout" "$_RT_TIMEOUT_MIN" "$_RT_TIMEOUT_MAX")
    else
      route_timeout=""
    fi
    route_retries=$(_rt_clamp "${route_retries:-0}" "$_RT_RETRIES_MIN" "$_RT_RETRIES_MAX")

    _rt_append_route "$backend" "$when" "$caps" "$fail_mode" "$route_timeout" "$route_retries"
  done

  return 0
}

# =============================================================================
# Validation (SDD §3.1.3, Task 1.2)
# =============================================================================

# Validate parsed route table against schema rules.
# Args: is_custom ("true" if user-defined routes)
# Returns: 0 on valid, 2 on hard error
validate_route_table() {
  local is_custom="${1:-false}"
  local errors=0

  # Array length invariant (SKP-002)
  if ! _rt_validate_array_lengths; then
    return 2
  fi

  # Policy constraint — max routes
  if [[ ${#_RT_BACKENDS[@]} -gt $_RT_MAX_ROUTES ]]; then
    error "Route table exceeds max routes ($_RT_MAX_ROUTES)"
    return 2
  fi

  # Must have at least one route
  if [[ ${#_RT_BACKENDS[@]} -eq 0 ]]; then
    error "Route table is empty"
    return 2
  fi

  local i
  for ((i = 0; i < ${#_RT_BACKENDS[@]}; i++)); do
    local backend="${_RT_BACKENDS[$i]}"
    local conditions="${_RT_CONDITIONS[$i]}"
    local fail_mode="${_RT_FAIL_MODES[$i]}"

    # Backend required and must be registered
    if [[ -z "$backend" ]]; then
      error "Route $i: backend is required"
      errors=$((errors + 1))
    elif [[ -z "${_BACKEND_REGISTRY[$backend]:-}" ]]; then
      error "Route $i: unknown backend '$backend'"
      errors=$((errors + 1))
    fi

    # Conditions: empty = unconditional (always match), non-empty = validate each
    if [[ -z "$conditions" ]]; then
      : # Empty conditions = unconditional match (valid)
    else
      # Validate each condition name (with whitespace trimming per SKP-003)
      IFS=',' read -ra conds <<< "$conditions"
      local c
      for c in "${conds[@]}"; do
        # Trim whitespace
        c="${c#"${c%%[![:space:]]*}"}"
        c="${c%"${c##*[![:space:]]}"}"
        if [[ -z "$c" ]]; then
          continue  # Skip empty tokens
        fi
        if [[ -z "${_CONDITION_REGISTRY[$c]:-}" ]]; then
          if [[ "$is_custom" == "true" ]]; then
            error "Route $i: unknown condition '$c'"
            errors=$((errors + 1))
          else
            log "WARNING: Route $i: unknown condition '$c' (will evaluate as false)"
          fi
        fi
      done
    fi

    # Fail mode validation
    if [[ "$fail_mode" != "fallthrough" && "$fail_mode" != "hard_fail" ]]; then
      if [[ "$is_custom" == "true" ]]; then
        error "Route $i: invalid fail_mode '$fail_mode' (expected: fallthrough|hard_fail)"
        errors=$((errors + 1))
      else
        log "WARNING: Route $i: invalid fail_mode '$fail_mode', defaulting to fallthrough"
        _RT_FAIL_MODES[$i]="fallthrough"
      fi
    fi
  done

  # Advisory: last route should be hard_fail
  local last_idx=$(( ${#_RT_FAIL_MODES[@]} - 1 ))
  if [[ "${_RT_FAIL_MODES[$last_idx]}" != "hard_fail" ]]; then
    log "WARNING: Last route is not hard_fail — all routes could fall through silently"
  fi

  # Fail-closed for custom routes with errors
  if [[ $errors -gt 0 && "$is_custom" == "true" ]]; then
    error "Custom route table has $errors error(s) — aborting (fail-closed)"
    return 2
  fi

  return 0
}

# =============================================================================
# Condition Evaluation (SDD §3.1.6, Task 1.3)
# =============================================================================

# Evaluate conditions for a route (AND logic).
# Trims whitespace, rejects empty tokens (Flatline SKP-003).
# Unknown conditions evaluate as false.
# Args: conditions (comma-separated string)
# Returns: 0 if all conditions met, 1 if any condition fails
_evaluate_conditions() {
  local conditions="$1"

  IFS=',' read -ra conds <<< "$conditions"
  local c
  for c in "${conds[@]}"; do
    # Trim whitespace (SKP-003)
    c="${c#"${c%%[![:space:]]*}"}"
    c="${c%"${c##*[![:space:]]}"}"

    # Reject empty tokens (SKP-003)
    if [[ -z "$c" ]]; then
      continue
    fi

    local func="${_CONDITION_REGISTRY[$c]:-}"
    if [[ -z "$func" ]]; then
      return 1  # Unknown condition → false
    fi
    if ! "$func"; then
      return 1  # Condition not met
    fi
  done
  return 0  # All conditions met
}

# =============================================================================
# Route Execution (SDD §3.1.6, Task 1.3)
# =============================================================================

# Execute route table: try each route in order, first success wins.
# Implements per-route timeout/retries with global max attempts cap (SKP-005).
# Args: model sys usr timeout fast tool_access reasoning_mode review_type
# Returns: 0 + JSON on stdout (success), 2 (all routes failed)
execute_route_table() {
  local model="$1" sys="$2" usr="$3" timeout="$4"
  local fast="${5:-false}" ta="${6:-false}" rm="${7:-single-pass}" rtype="${8:-code}"

  local total_attempts=0
  local i

  for ((i = 0; i < ${#_RT_BACKENDS[@]}; i++)); do
    local backend="${_RT_BACKENDS[$i]}"
    local conditions="${_RT_CONDITIONS[$i]}"
    local fail_mode="${_RT_FAIL_MODES[$i]}"
    local route_timeout="${_RT_TIMEOUTS[$i]:-$timeout}"
    local route_retries="${_RT_RETRIES[$i]:-0}"
    local func="${_BACKEND_REGISTRY[$backend]:-}"

    # Use global timeout if route timeout is empty
    [[ -z "$route_timeout" ]] && route_timeout="$timeout"

    # Evaluate conditions (AND logic)
    if ! _evaluate_conditions "$conditions"; then
      log "[route-table] skipping backend=$backend (conditions not met)"
      continue
    fi

    log "[route-table] trying backend=$backend, conditions=[$conditions], result=pending"

    # Call backend with retries
    local result="" be=0 attempt=0
    while [[ $attempt -le $route_retries ]]; do
      # Global max attempts guard (SKP-005)
      if [[ $total_attempts -ge $_RT_MAX_TOTAL_ATTEMPTS ]]; then
        error "Global max attempts ($_RT_MAX_TOTAL_ATTEMPTS) exceeded — aborting"
        return 2
      fi

      [[ $attempt -gt 0 ]] && log "[route-table] retry $attempt/$route_retries for backend=$backend"

      be=0
      result=$("$func" "$model" "$sys" "$usr" "$route_timeout" "$fast" "$ta" "$rm" "$rtype" "$i") || be=$?
      total_attempts=$((total_attempts + 1))

      if [[ $be -eq 0 && -n "$result" ]]; then
        # Validate result contract
        if validate_review_result "$result"; then
          log "[route-table] trying backend=$backend, conditions=[$conditions], result=success"
          echo "$result"
          return 0
        else
          log "[route-table] trying backend=$backend, conditions=[$conditions], result=fail (invalid output)"
          # Invalid JSON counts as failure — retry if retries remain
        fi
      else
        log "[route-table] trying backend=$backend, conditions=[$conditions], result=fail (exit $be)"
      fi

      attempt=$((attempt + 1))
    done

    # Check fail_mode
    if [[ "$fail_mode" == "hard_fail" ]]; then
      error "Backend '$backend' failed with hard_fail — aborting"
      # Propagate backend's native exit code (preserves 1=API error, 4=auth, 5=format)
      # If backend returned 0 but output was invalid, use 1 (generic failure)
      [[ $be -eq 0 ]] && be=1
      return $be
    fi
    # fallthrough → continue to next route
  done

  error "All routes exhausted — no backend returned a valid result"
  return 2
}

# =============================================================================
# Result Contract (SDD §3.1.7, Task 1.4)
# =============================================================================

# Validate backend output against result contract.
# Verdict-to-exit-code truth table (Flatline IMP-006):
#   APPROVED → exit 0 (valid)
#   CHANGES_REQUIRED → exit 0 (valid)
#   DECISION_NEEDED → exit 0 (valid)
#   SKIPPED → exit 0 (valid)
#   Invalid/missing → exit 1 (fallthrough)
#
# Args: json_string
# Returns: 0 if valid, 1 if invalid
validate_review_result() {
  local result="$1"

  # Minimum length
  if [[ ${#result} -lt 20 ]]; then
    log "WARNING: validate_review_result: response too short (${#result} chars)"
    return 1
  fi

  # JSON validity
  if ! echo "$result" | jq empty 2>/dev/null; then
    log "WARNING: validate_review_result: invalid JSON"
    return 1
  fi

  # Required field: verdict
  local verdict
  verdict=$(echo "$result" | jq -r '.verdict // empty' 2>/dev/null)
  if [[ -z "$verdict" ]]; then
    log "WARNING: validate_review_result: missing 'verdict' field"
    return 1
  fi

  # Verdict enum (IMP-006)
  case "$verdict" in
    APPROVED|CHANGES_REQUIRED|DECISION_NEEDED|SKIPPED) ;;
    *)
      log "WARNING: validate_review_result: invalid verdict '$verdict'"
      return 1
      ;;
  esac

  # findings must be array if present
  local findings_type
  findings_type=$(echo "$result" | jq -r 'if has("findings") then (.findings | type) else "absent" end' 2>/dev/null)
  if [[ "$findings_type" != "absent" && "$findings_type" != "array" ]]; then
    log "WARNING: validate_review_result: 'findings' must be array, got '$findings_type'"
    return 1
  fi

  return 0
}

# =============================================================================
# Logging (SDD §3.1.8, Task 1.5)
# =============================================================================

# Log effective route table for auditability (PRD G6).
# Emits: backend names, conditions, fail modes, SHA-256 hash.
log_route_table() {
  local table_str=""
  local i
  for ((i = 0; i < ${#_RT_BACKENDS[@]}; i++)); do
    local line="${_RT_BACKENDS[$i]}:[${_RT_CONDITIONS[$i]}]:${_RT_FAIL_MODES[$i]}"
    [[ -n "${_RT_TIMEOUTS[$i]}" ]] && line+=":t=${_RT_TIMEOUTS[$i]}"
    [[ "${_RT_RETRIES[$i]:-0}" != "0" ]] && line+=":r=${_RT_RETRIES[$i]}"
    table_str+="$line;"
  done

  local hash
  hash=$(printf '%s' "$table_str" | sha256sum | cut -d' ' -f1)

  log "[route-table] effective routes: ${table_str}"
  log "[route-table] hash: sha256:${hash:0:16}"
}

# =============================================================================
# Execution Mode Filter (SDD §3.1.10, Task 1.5)
# =============================================================================

# Apply execution_mode filter to route table.
# Args: mode (auto|codex|curl)
_rt_apply_execution_mode() {
  local mode="$1"
  [[ "$mode" == "auto" ]] && return 0

  local -a new_backends=() new_conditions=() new_caps=() new_modes=() new_timeouts=() new_retries=()
  local i
  for ((i = 0; i < ${#_RT_BACKENDS[@]}; i++)); do
    local b="${_RT_BACKENDS[$i]}"
    case "$mode" in
      curl)
        [[ "$b" == "curl" ]] && {
          new_backends+=("$b"); new_conditions+=("${_RT_CONDITIONS[$i]}")
          new_caps+=("${_RT_CAPABILITIES[$i]}"); new_modes+=("hard_fail")
          new_timeouts+=("${_RT_TIMEOUTS[$i]}"); new_retries+=("${_RT_RETRIES[$i]}")
        }
        ;;
      codex)
        [[ "$b" == "codex" || "$b" == "curl" ]] && {
          new_backends+=("$b"); new_conditions+=("${_RT_CONDITIONS[$i]}")
          new_caps+=("${_RT_CAPABILITIES[$i]}")
          [[ "$b" == "codex" ]] && new_modes+=("hard_fail") || new_modes+=("${_RT_FAIL_MODES[$i]}")
          new_timeouts+=("${_RT_TIMEOUTS[$i]}"); new_retries+=("${_RT_RETRIES[$i]}")
        }
        ;;
    esac
  done

  _RT_BACKENDS=("${new_backends[@]}")
  _RT_CONDITIONS=("${new_conditions[@]}")
  _RT_CAPABILITIES=("${new_caps[@]}")
  _RT_FAIL_MODES=("${new_modes[@]}")
  _RT_TIMEOUTS=("${new_timeouts[@]}")
  _RT_RETRIES=("${new_retries[@]}")
}

# =============================================================================
# Initialization (SDD §3.1.11, Task 1.5)
# =============================================================================

# Initialize the full route table: parse, register, validate.
# Idempotent: safe to call multiple times (overwrites global state).
# Single-process assumption: no cross-process locking.
# Args: config_file
# Returns: 0 on success, 2 on fatal error
init_route_table() {
  local config_file="${1:-$CONFIG_FILE}"

  # Clear any previous state (idempotency)
  _RT_BACKENDS=(); _RT_CONDITIONS=(); _RT_CAPABILITIES=()
  _RT_FAIL_MODES=(); _RT_TIMEOUTS=(); _RT_RETRIES=()

  # Register built-in conditions and backends
  register_builtin_conditions
  register_builtin_backends

  # Detect custom routes — with yq availability check (Flatline IMP-004)
  local is_custom="false"
  if [[ -f "$config_file" ]]; then
    # Cheap grep check: does config mention gpt_review routes?
    if grep -q 'gpt_review:' "$config_file" 2>/dev/null && \
       grep -q '  routes:' "$config_file" 2>/dev/null; then
      if ! command -v yq &>/dev/null; then
        # Config has routes but yq is missing — fail-closed
        error "Config file has gpt_review.routes but yq is not installed."
        error "Install yq v4+ to use custom routes, or remove the routes section."
        error "Override with LOA_ALLOW_DEFAULTS_WITHOUT_YQ=1 to use defaults."
        # LOA_ALLOW_DEFAULTS_WITHOUT_YQ illegal in CI (Flatline SKP-001)
        if [[ "${CI:-}" == "true" ]]; then
          error "LOA_ALLOW_DEFAULTS_WITHOUT_YQ is not allowed in CI. Install yq v4+."
          return 2
        fi
        if [[ "${LOA_ALLOW_DEFAULTS_WITHOUT_YQ:-}" != "1" ]]; then
          return 2
        fi
        log "WARNING: LOA_ALLOW_DEFAULTS_WITHOUT_YQ=1 set — using defaults despite config"
      else
        # Verify yq version (IMP-003)
        if ! _rt_check_yq_version; then
          return 2
        fi
        local rc
        rc=$(yq eval '.gpt_review.routes | length // 0' "$config_file" 2>/dev/null) || rc=0
        [[ "$rc" -gt 0 ]] && is_custom="true"
      fi
    fi
  fi

  parse_route_table "$config_file" || return $?

  # Check CI opt-in for custom routes
  if [[ "$is_custom" == "true" && "${CI:-}" == "true" && "${LOA_CUSTOM_ROUTES:-}" != "1" ]]; then
    log "WARNING: Custom routes in CI require LOA_CUSTOM_ROUTES=1 — using defaults"
    _RT_BACKENDS=(); _RT_CONDITIONS=(); _RT_CAPABILITIES=()
    _RT_FAIL_MODES=(); _RT_TIMEOUTS=(); _RT_RETRIES=()
    _rt_load_defaults
    is_custom="false"
  fi

  # Validate
  validate_route_table "$is_custom" || return $?

  return 0
}
