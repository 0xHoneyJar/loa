# SDD: Declarative Execution Router + Adaptive Multi-Pass Review

> Cycle: cycle-034 | Author: soju + Claude
> Source PRD: `grimoires/loa/prd.md` ([#403](https://github.com/0xHoneyJar/loa/issues/403))
> Predecessor: cycle-033 SDD (Codex CLI Integration — 3-tier imperative router)
> Design Context: Bridgebuilder review of [PR #401](https://github.com/0xHoneyJar/loa/pull/401)

---

## 1. Executive Summary

This SDD refactors the GPT review execution pipeline from imperative control flow to declarative configuration. The 56-line if/else cascade in `route_review()` (gpt-review-api.sh:91-147) becomes a generic loop over a YAML-defined route table. The multi-pass orchestrator gains adaptive depth based on dual-signal complexity classification. Supporting improvements include a word-count token estimation tier, cached capability detection, a shared backend result contract, and a Python3 JSON decoder fallback.

**Architecture principle**: Configuration as code. Routing decisions move from bash logic into `.loa.config.yaml`, making them diffable, auditable, and operator-customizable without code changes. The runtime loop is generic — it doesn't know what backends exist, only how to evaluate conditions and try routes in order.

**Scope boundary**: Only routing and multi-pass depth are declarative. Prompt construction, security policy, and API interaction remain in code.

---

## 2. System Architecture

### 2.1 Component Diagram

```
┌──────────────────────────────────────────────────────────────────┐
│ gpt-review-api.sh (entry point)                                  │
│                                                                  │
│  main() → load_config() → route_review()                         │
│                                │                                 │
│                                ▼                                 │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │              lib-route-table.sh (NEW)                        │ │
│  │                                                             │ │
│  │  parse_route_table()     → _ROUTE_TABLE[] arrays            │ │
│  │  validate_route_table()  → fail-closed / fail-open          │ │
│  │  register_condition()    → _CONDITION_REGISTRY{}             │ │
│  │  register_backend()      → _BACKEND_REGISTRY{}              │ │
│  │  evaluate_route()        → try conditions, call backend     │ │
│  │  execute_route_table()   → main loop (first success wins)   │ │
│  │  validate_review_result()→ backend result contract          │ │
│  │  log_route_table()       → startup tracing                  │ │
│  └──────────┬───────────────────────────────┬──────────────────┘ │
│             │                               │                    │
│      ┌──────▼──────┐   ┌──────────────┐   ┌▼─────────────────┐  │
│      │ Conditions   │   │ Backends     │   │ Result Contract  │  │
│      │ Registry     │   │ Registry     │   │ (shared gate)    │  │
│      │ (assoc arr)  │   │ (assoc arr)  │   │                  │  │
│      └──────────────┘   └──────┬───────┘   └──────────────────┘  │
│                                │                                 │
│      ┌─────────────────────────┼────────────────────┐            │
│      ▼                         ▼                    ▼            │
│  ┌──────────┐  ┌───────────────────────┐  ┌────────────────┐    │
│  │ Hounfour │  │ Codex                 │  │ curl           │    │
│  │ backend  │  │ (multi/single pass)   │  │ fallback       │    │
│  │          │  │                       │  │                │    │
│  │ lib-curl │  │ lib-codex-exec.sh     │  │ lib-curl       │    │
│  │ fallback │  │ lib-multipass.sh      │  │ fallback.sh    │    │
│  └──────────┘  └───────────────────────┘  └────────────────┘    │
└──────────────────────────────────────────────────────────────────┘
```

### 2.2 Data Flow

```
1. main() parses CLI args, calls load_config()
2. load_config() reads .loa.config.yaml including gpt_review.routes
3. route_review() calls init_route_table()
   a. parse_route_table() reads YAML routes into bash arrays
   b. validate_route_table() checks schema (fail-closed if custom, fail-open if absent)
   c. register_conditions() populates condition registry with named functions
   d. register_backends() populates backend registry with named functions
   e. log_route_table() emits effective config + SHA-256 hash to stderr
4. route_review() calls execute_route_table(model, sys, usr, timeout, ...)
   a. For each route in order:
      i.   Evaluate all conditions in `when` array (AND logic)
      ii.  If all true → call backend function
      iii. validate_review_result() checks output
      iv.  If valid → return result
      v.   If invalid or backend error → check fail_mode
           - fallthrough → log, continue to next route
           - hard_fail → return error immediately
   b. If no route succeeds → return error (exit 2)
5. Multipass orchestrator checks backend capabilities before choosing mode
6. Result flows back through main() for enrichment (iteration, redaction)
```

### 2.3 Execution Mode Compatibility

The existing `execution_mode` config key maps to route table filtering:

| `execution_mode` | Route Table Behavior |
|-------------------|---------------------|
| `auto` (default) | Full route table, unmodified |
| `codex` | Filter to `codex` + `curl` only; `codex` set to `hard_fail` |
| `curl` | Filter to `curl` only |

When both `execution_mode` and `routes` are present, `routes` takes precedence (with warning).

---

## 3. Component Design

### 3.1 lib-route-table.sh (NEW)

New library sourced by `gpt-review-api.sh`. Contains all route table logic.

#### 3.1.1 Data Structures

```bash
# Route table — parallel arrays (bash 4.0+ associative arrays for registries)
declare -a _RT_BACKENDS=()       # ("hounfour" "codex" "curl")
declare -a _RT_CONDITIONS=()     # ("flatline_routing_enabled,model_invoke_available" "codex_available" "always")
declare -a _RT_CAPABILITIES=()   # ("agent_binding,metering,trust_scopes" "sandbox,ephemeral,multi_pass,tool_access" "basic")
declare -a _RT_FAIL_MODES=()     # ("fallthrough" "fallthrough" "hard_fail")
declare -a _RT_TIMEOUTS=()       # ("" "" "") — per-route timeout overrides (Flatline IMP-002)
declare -a _RT_RETRIES=()        # ("0" "0" "0") — per-route retry counts (Flatline IMP-002)

# Registries — associative arrays
declare -A _CONDITION_REGISTRY=() # (["always"]="_cond_always" ["codex_available"]="codex_is_available" ...)
declare -A _BACKEND_REGISTRY=()   # (["hounfour"]="_backend_hounfour" ["codex"]="_backend_codex" ...)
```

Using parallel arrays instead of a single nested structure because:
- Bash has no nested data types
- Parallel arrays are O(1) index access
- Condition and capability lists are comma-delimited strings split at evaluation time

#### 3.1.2 parse_route_table()

```bash
# Parse YAML route table into parallel arrays.
# Args: config_file
# Returns: 0 on success, 2 on parse error
# Side effects: populates _RT_* arrays
parse_route_table() {
  local config_file="${1:-$CONFIG_FILE}"

  # Check for custom routes
  local route_count
  route_count=$(yq eval '.gpt_review.routes | length // 0' "$config_file" 2>/dev/null) || route_count=0

  if [[ "$route_count" -eq 0 ]]; then
    # No custom routes — use built-in defaults (cycle-033 behavior)
    _rt_load_defaults
    log "Using default route table (no gpt_review.routes in config)"
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
    local backend when caps fail_mode
    backend=$(yq eval ".gpt_review.routes[$i].backend // \"\"" "$config_file")
    when=$(yq eval ".gpt_review.routes[$i].when | join(\",\")" "$config_file" 2>/dev/null) || when=""
    caps=$(yq eval ".gpt_review.routes[$i].capabilities | join(\",\")" "$config_file" 2>/dev/null) || caps=""
    fail_mode=$(yq eval ".gpt_review.routes[$i].fail_mode // \"fallthrough\"" "$config_file")

    _RT_BACKENDS+=("$backend")
    _RT_CONDITIONS+=("$when")
    _RT_CAPABILITIES+=("$caps")
    _RT_FAIL_MODES+=("$fail_mode")
  done
}
```

#### 3.1.3 validate_route_table()

Implements fail-closed for custom routes, fail-open for defaults (PRD FR-1.4):

```bash
# Validate parsed route table against schema rules.
# Args: is_custom ("true" if user-defined routes)
# Returns: 0 on valid, 2 on hard error
validate_route_table() {
  local is_custom="${1:-false}"
  local errors=0 warnings=0

  # R3.2: Policy constraint — max routes
  local max_routes="${_RT_MAX_ROUTES:-10}"
  if [[ ${#_RT_BACKENDS[@]} -gt $max_routes ]]; then
    error "Route table exceeds max routes ($max_routes)"
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
      ((errors++))
    elif [[ -z "${_BACKEND_REGISTRY[$backend]:-}" ]]; then
      error "Route $i: unknown backend '$backend'"
      ((errors++))
    fi

    # Conditions must be non-empty
    if [[ -z "$conditions" ]]; then
      error "Route $i: 'when' must be non-empty array"
      ((errors++))
    else
      IFS=',' read -ra conds <<< "$conditions"
      for cond in "${conds[@]}"; do
        if [[ -z "${_CONDITION_REGISTRY[$cond]:-}" ]]; then
          log "WARNING: Route $i: unknown condition '$cond' (will evaluate as false)"
          ((warnings++))
        fi
      done
    fi

    # Fail mode validation
    if [[ "$fail_mode" != "fallthrough" && "$fail_mode" != "hard_fail" ]]; then
      log "WARNING: Route $i: invalid fail_mode '$fail_mode', defaulting to fallthrough"
      _RT_FAIL_MODES[$i]="fallthrough"
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
```

#### 3.1.4 Condition Registry

Built-in conditions registered at source time:

```bash
_cond_always() { return 0; }
_cond_flatline_routing_enabled() { is_flatline_routing_enabled; }
_cond_model_invoke_available() { [[ -x "${MODEL_INVOKE:-}" ]]; }
_cond_codex_available() { codex_is_available; }

register_builtin_conditions() {
  _CONDITION_REGISTRY=(
    ["always"]="_cond_always"
    ["flatline_routing_enabled"]="_cond_flatline_routing_enabled"
    ["model_invoke_available"]="_cond_model_invoke_available"
    ["codex_available"]="_cond_codex_available"
  )
}
```

**Security**: Conditions are looked up by name in a fixed associative array. Unknown names evaluate as false. No `eval`, no dynamic function construction, no user-supplied code execution.

#### 3.1.5 Backend Registry

```bash
# Backend execution functions.
# Each takes: model sys usr timeout fast tool_access reasoning_mode review_type route_idx
# Each returns: 0 + JSON on stdout (success), non-zero (failure)

_backend_hounfour() {
  local model="$1" sys="$2" usr="$3" timeout="$4"
  call_api_via_model_invoke "$model" "$sys" "$usr" "$timeout"
}

_backend_codex() {
  local model="$1" sys="$2" usr="$3" timeout="$4"
  local fast="${5:-false}" ta="${6:-false}" rm="${7:-single-pass}" rtype="${8:-code}"
  local route_idx="${9:-0}"
  local ws of
  ws=$(setup_review_workspace "" "$ta")
  of=$(mktemp "${ws}/out-$$.XXXXXX")

  # Check multi-pass capability from route table
  local caps="${_RT_CAPABILITIES[$route_idx]:-}"
  local has_multipass=false
  [[ "$caps" == *"multi_pass"* ]] && has_multipass=true

  if [[ "$rm" == "multi-pass" && "$fast" != "true" && "$has_multipass" == "true" ]]; then
    local me=0
    run_multipass "$sys" "$usr" "$model" "$ws" "$timeout" "$of" "$rtype" "$ta" || me=$?
    if [[ $me -eq 0 && -s "$of" ]]; then
      local result; result=$(cat "$of"); cleanup_workspace "$ws"
      if echo "$result" | jq -e '.verdict' &>/dev/null; then
        echo "$result"; return 0
      fi
    fi
    cleanup_workspace "$ws"
    log "WARNING: multipass failed, falling back to single-pass codex"
    ws=$(setup_review_workspace "" "$ta"); of=$(mktemp "${ws}/out-$$.XXXXXX")
  elif [[ "$rm" == "multi-pass" && "$has_multipass" != "true" ]]; then
    log "WARNING: Backend 'codex' lacks multi_pass capability; downgrading to single-pass"
  fi

  # Single-pass codex
  local cp
  cp=$(printf '%s\n\n---\n\n## CONTENT TO REVIEW:\n\n%s\n\n---\n\nRespond with valid JSON only. Include "verdict": "APPROVED"|"CHANGES_REQUIRED"|"DECISION_NEEDED".' "$sys" "$usr")
  local ee=0
  codex_exec_single "$cp" "$model" "$of" "$ws" "$timeout" || ee=$?
  if [[ $ee -eq 0 && -s "$of" ]]; then
    local raw; raw=$(cat "$of"); cleanup_workspace "$ws"
    local pr; pr=$(parse_codex_output "$raw" 2>/dev/null) || pr=""
    if [[ -n "$pr" ]]; then echo "$pr"; return 0; fi
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
```

#### 3.1.6 execute_route_table()

The main loop — replaces the imperative `route_review()`:

```bash
# Execute route table: try each route in order, first success wins.
# Args: model sys usr timeout fast tool_access reasoning_mode review_type
# Returns: 0 + JSON on stdout (success), 2 (all routes failed)
execute_route_table() {
  local model="$1" sys="$2" usr="$3" timeout="$4"
  local fast="${5:-false}" ta="${6:-false}" rm="${7:-single-pass}" rtype="${8:-code}"

  local i
  for ((i = 0; i < ${#_RT_BACKENDS[@]}; i++)); do
    local backend="${_RT_BACKENDS[$i]}"
    local conditions="${_RT_CONDITIONS[$i]}"
    local fail_mode="${_RT_FAIL_MODES[$i]}"
    local route_timeout="${_RT_TIMEOUTS[$i]:-$timeout}"  # Per-route timeout (IMP-002)
    local route_retries="${_RT_RETRIES[$i]:-0}"           # Per-route retries (IMP-002)
    local func="${_BACKEND_REGISTRY[$backend]:-}"

    # Evaluate conditions (AND logic)
    if ! _evaluate_conditions "$conditions"; then
      log "[route-table] skipping backend=$backend (conditions not met)"
      continue
    fi

    log "[route-table] trying backend=$backend, conditions=[$conditions], result=pending"

    # Call backend (with per-route timeout and retries)
    local result="" be=0 attempt=0
    while [[ $attempt -le $route_retries ]]; do
      [[ $attempt -gt 0 ]] && log "[route-table] retry $attempt/$route_retries for backend=$backend"
      result=$("$func" "$model" "$sys" "$usr" "$route_timeout" "$fast" "$ta" "$rm" "$rtype" "$i") || be=$?
      [[ $be -eq 0 && -n "$result" ]] && break
      ((attempt++))
      be=1
    done

    if [[ $be -eq 0 && -n "$result" ]]; then
      # Validate result contract
      if validate_review_result "$result"; then
        log "[route-table] trying backend=$backend, conditions=[$conditions], result=success"
        echo "$result"
        return 0
      else
        log "[route-table] trying backend=$backend, conditions=[$conditions], result=fail (invalid output)"
      fi
    else
      log "[route-table] trying backend=$backend, conditions=[$conditions], result=fail (exit $be)"
    fi

    # Check fail_mode
    if [[ "$fail_mode" == "hard_fail" ]]; then
      error "Backend '$backend' failed with hard_fail — aborting"
      return 2
    fi
    # fallthrough → continue to next route
  done

  error "All routes exhausted — no backend returned a valid result"
  return 2
}
```

#### 3.1.7 validate_review_result() (PRD FR-1.8)

Shared gate checking backend output validity:

```bash
# Validate backend output against result contract.
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

  # Verdict enum
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
```

#### 3.1.8 log_route_table() (PRD G6)

Config-to-code tracing at startup:

```bash
# Log effective route table for auditability.
# Emits: backend names, conditions, fail modes, SHA-256 hash.
log_route_table() {
  local table_str=""
  local i
  for ((i = 0; i < ${#_RT_BACKENDS[@]}; i++)); do
    local line="${_RT_BACKENDS[$i]}:[${_RT_CONDITIONS[$i]}]:${_RT_FAIL_MODES[$i]}"
    table_str+="$line;"
  done

  local hash
  hash=$(printf '%s' "$table_str" | sha256sum | cut -d' ' -f1)

  log "[route-table] effective routes: ${table_str}"
  log "[route-table] hash: sha256:${hash:0:16}"
}
```

#### 3.1.9 Default Route Table

Built-in default matching cycle-033 behavior:

```bash
_rt_load_defaults() {
  _RT_BACKENDS=("hounfour" "codex" "curl")
  _RT_CONDITIONS=("flatline_routing_enabled,model_invoke_available" "codex_available" "always")
  _RT_CAPABILITIES=("agent_binding,metering,trust_scopes" "sandbox,ephemeral,multi_pass,tool_access" "basic")
  _RT_FAIL_MODES=("fallthrough" "fallthrough" "hard_fail")
}
```

#### 3.1.10 Execution Mode Filter

```bash
# Apply execution_mode filter to route table.
# Args: mode (auto|codex|curl)
_rt_apply_execution_mode() {
  local mode="$1"
  [[ "$mode" == "auto" ]] && return 0

  local -a new_backends=() new_conditions=() new_caps=() new_modes=()
  local i
  for ((i = 0; i < ${#_RT_BACKENDS[@]}; i++)); do
    local b="${_RT_BACKENDS[$i]}"
    case "$mode" in
      curl)
        [[ "$b" == "curl" ]] && {
          new_backends+=("$b"); new_conditions+=("${_RT_CONDITIONS[$i]}")
          new_caps+=("${_RT_CAPABILITIES[$i]}"); new_modes+=("hard_fail")
        }
        ;;
      codex)
        [[ "$b" == "codex" || "$b" == "curl" ]] && {
          new_backends+=("$b"); new_conditions+=("${_RT_CONDITIONS[$i]}")
          new_caps+=("${_RT_CAPABILITIES[$i]}")
          [[ "$b" == "codex" ]] && new_modes+=("hard_fail") || new_modes+=("${_RT_FAIL_MODES[$i]}")
        }
        ;;
    esac
  done

  _RT_BACKENDS=("${new_backends[@]}")
  _RT_CONDITIONS=("${new_conditions[@]}")
  _RT_CAPABILITIES=("${new_caps[@]}")
  _RT_FAIL_MODES=("${new_modes[@]}")
}
```

#### 3.1.11 init_route_table()

Single initialization entrypoint called from route_review().

**Concurrency model** (Flatline IMP-001): `init_route_table()` is idempotent — calling it multiple times overwrites the same global arrays. It assumes single-process execution (one `gpt-review-api.sh` invocation per workspace). Parallel CI jobs using the same workspace must serialize invocations externally or use separate workspaces. The function is NOT thread-safe in the bash sense (no locking on globals), but this is acceptable because `gpt-review-api.sh` is a short-lived CLI tool, not a long-running daemon.

```bash
# Initialize the full route table: parse, register, validate.
# Idempotent: safe to call multiple times (overwrites global state).
# Single-process assumption: no cross-process locking.
# Args: config_file
# Returns: 0 on success, 2 on fatal error
init_route_table() {
  local config_file="${1:-$CONFIG_FILE}"

  # Clear any previous state (idempotency)
  _RT_BACKENDS=(); _RT_CONDITIONS=(); _RT_CAPABILITIES=(); _RT_FAIL_MODES=()

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
        if [[ "${LOA_ALLOW_DEFAULTS_WITHOUT_YQ:-}" != "1" ]]; then
          return 2
        fi
        log "WARNING: LOA_ALLOW_DEFAULTS_WITHOUT_YQ=1 set — using defaults despite config"
      else
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
    _RT_BACKENDS=(); _RT_CONDITIONS=(); _RT_CAPABILITIES=(); _RT_FAIL_MODES=()
    _rt_load_defaults
    is_custom="false"
  fi

  # Validate
  validate_route_table "$is_custom" || return $?
}
```

### 3.2 Refactored route_review() (gpt-review-api.sh)

The imperative 56-line `route_review()` is replaced with:

```bash
# Execution Router (SDD §3.2): Declarative route table
route_review() {
  local model="$1" sys="$2" usr="$3" timeout="$4" fast="${5:-false}" ta="${6:-false}"
  local rm="${7:-single-pass}" rtype="${8:-code}"

  # Initialize route table (once per invocation)
  init_route_table "$CONFIG_FILE"

  # Apply execution_mode filter if set
  local em="auto"
  [[ -f "$CONFIG_FILE" ]] && command -v yq &>/dev/null && {
    local c; c=$(yq eval '.gpt_review.execution_mode // "auto"' "$CONFIG_FILE" 2>/dev/null || echo "auto")
    [[ -n "$c" && "$c" != "null" ]] && em="$c"
  }
  [[ "$em" != "auto" ]] && _rt_apply_execution_mode "$em"

  # Log effective table
  log_route_table

  # Execute
  execute_route_table "$model" "$sys" "$usr" "$timeout" "$fast" "$ta" "$rm" "$rtype"
}
```

**Target**: ~15 lines of declarative orchestration replacing 56 lines of imperative logic.

### 3.3 Adaptive Multi-Pass (lib-multipass.sh)

#### 3.3.1 Dual-Signal Complexity Classifier

New function added to lib-multipass.sh:

```bash
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
  local -a security_paths=(".claude/" "lib-security" "auth" "credentials" "secrets" ".env")
  for pattern in "${security_paths[@]}"; do
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
```

```bash
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
```

#### 3.3.2 Modified run_multipass()

The adaptive flow integrates into the existing orchestrator:

```
run_multipass():
  1. Check adaptive config (.gpt_review.multipass.adaptive, default true)
  2. If adaptive disabled → existing 3-pass behavior (unchanged)
  3. If adaptive enabled:
     a. classify_complexity(user_content) → det_level
     b. Run Pass 1 (unchanged)
     c. reclassify_with_model_signals(det_level, p1_output) → final_level
     d. If final_level == "low" → return Pass 1 output as combined review
     e. If final_level == "high" → use extended budgets for Pass 2
     f. If final_level == "medium" → standard 3-pass
  4. All fallback paths unchanged (budget overflow, pass failure)
```

The key insight: Pass 1 always runs (it produces the context map). The adaptive decision happens between Pass 1 and Pass 2. This means we never skip planning — we only skip the full review + verification when the content is clearly simple.

#### 3.3.3 Extended Budgets for High Complexity

When `final_level == "high"`, read overrides from config:

```bash
if [[ "$final_level" == "high" ]]; then
  PASS2_INPUT_BUDGET=$(_read_mp_config '.gpt_review.multipass.budgets.high_complexity.pass2_input' 30000)
  PASS2_OUTPUT_BUDGET=$(_read_mp_config '.gpt_review.multipass.budgets.high_complexity.pass2_output' 10000)
fi
```

### 3.4 Token Estimation (lib-multipass.sh)

#### 3.4.1 Word-Count Tier

Insert between tiktoken (Tier 1) and chars/4 (Tier 3):

```bash
estimate_token_count() {
  local text="$1"
  local char_count=${#text}

  # Tier 1: tiktoken (within 5% accuracy)
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

  # Tier 2: word-count heuristic (~1.33 tokens/word, ≤15% mean error for code)
  local word_count
  word_count=$(printf '%s' "$text" | wc -w) || word_count=0
  if [[ "$word_count" -gt 0 ]]; then
    echo $(( (word_count * 4 + 2) / 3 ))
    return 0
  fi

  # Tier 3: chars/4 heuristic (fallback for empty word-count edge case)
  echo $(( (char_count + 3) / 4 ))
}
```

The word-count tier is better than chars/4 for code because:
- Code has many non-word characters (braces, operators, punctuation) that inflate char count
- Tokenizers align more closely with word boundaries than character boundaries
- The 1.33 multiplier is calibrated for mixed prose/code content

### 3.5 Capability Detection (lib-codex-exec.sh)

#### 3.5.1 Cached Help Text

Replace the per-flag `codex exec --help` invocation with a single call:

```bash
detect_capabilities() {
  # ... version hash + cache file logic unchanged ...

  local capabilities="{}"

  # Single help text invocation (was: one per flag in the loop)
  local help_text
  help_text=$(codex exec --help 2>&1) || help_text=""

  for flag in "${_CODEX_PROBE_FLAGS[@]}"; do
    local supported="true"
    if echo "$help_text" | grep -qiE "(unknown option|unrecognized|invalid).*${flag}"; then
      supported="false"
    elif ! echo "$help_text" | grep -q -- "$flag"; then
      supported="true"
    fi
    capabilities=$(echo "$capabilities" | jq --arg f "$flag" --arg s "$supported" '. + {($f): ($s == "true")}')
  done

  # ... metadata + write cache unchanged ...
}
```

**Change**: The existing code already calls `codex exec --help` in the loop body but does so per iteration. The fix is to hoist the call above the loop. The cache file logic is unchanged.

### 3.6 JSON Extraction Fallback (lib-codex-exec.sh)

#### 3.6.1 Python3 raw_decode Tier

Add between the greedy regex (Tier 3) and the error return (Tier 4) in `parse_codex_output()`:

```bash
  # Tier 3: Greedy regex (2-level nesting) — unchanged
  # ...

  # Tier 3.5: Python3 raw_decode (arbitrary nesting, correct by construction)
  if command -v python3 &>/dev/null; then
    local decoded
    decoded=$(printf '%s' "$raw" | python3 -c "
import json, sys
s = sys.stdin.read()
try:
    idx = s.index('{')
    obj, _ = json.JSONDecoder().raw_decode(s[idx:])
    print(json.dumps(obj))
except (ValueError, json.JSONDecodeError):
    sys.exit(1)
" 2>/dev/null) || decoded=""
    if [[ -n "$decoded" ]] && echo "$decoded" | jq empty 2>/dev/null; then
      echo "$decoded" | jq '.'
      return 0
    fi
  fi

  # Tier 4: All extraction methods failed — unchanged
```

Note: `normalize-json.sh` already has a Python3 raw_decode path. The `parse_codex_output()` function in lib-codex-exec.sh is kept separate because it's the Codex-specific normalization path, while `normalize_json_response()` is the Hounfour/model-invoke path. Both now share the same Python3 fallback technique.

---

## 4. Configuration Schema

### 4.1 New Config Keys

```yaml
gpt_review:
  enabled: true

  # Schema version for route table format (FR-1.5)
  route_schema: 1

  # Declarative route table (FR-1.1)
  routes:
    - backend: hounfour
      when: [flatline_routing_enabled, model_invoke_available]
      capabilities: [agent_binding, metering, trust_scopes]
      fail_mode: fallthrough
      timeout: 300           # per-route timeout override (Flatline IMP-002)
      retries: 0             # per-route retry count (Flatline IMP-002)

    - backend: codex
      when: [codex_available]
      capabilities: [sandbox, ephemeral, multi_pass, tool_access]
      fail_mode: fallthrough
      timeout: 120
      retries: 0

    - backend: curl
      when: [always]
      capabilities: [basic]
      fail_mode: hard_fail
      timeout: 300
      retries: 3             # curl backend retries (existing behavior)

  # Legacy execution mode shorthand (FR-1.7)
  execution_mode: auto  # auto | codex | curl

  # Adaptive multi-pass (FR-2)
  multipass:
    adaptive: true  # false = always 3-pass
    thresholds:
      low_risk_areas: 3
      low_scope_tokens: 500
      high_risk_areas: 6
      high_scope_tokens: 2000
    budgets:
      high_complexity:
        pass2_input: 30000
        pass2_output: 10000

  # Policy constraints (R3.2)
  policy:
    max_routes: 10
    max_attempts: 10
    require_custom_routes_opt_in: false  # true in CI via LOA_CUSTOM_ROUTES env
```

### 4.2 CI Environment Variables

| Variable | Purpose | Default |
|----------|---------|---------|
| `LOA_CUSTOM_ROUTES` | Opt-in for non-default routing in CI | unset (custom routes blocked in CI) |
| `GPT_REVIEW_ADAPTIVE` | Override adaptive multi-pass | unset (uses config) |

---

## 5. Security Architecture

### 5.1 Condition Registry (R2)

- Conditions are a **closed set** of named functions in a bash associative array
- Unknown condition names evaluate as `false` (not as error, not as `eval`)
- No user-supplied expressions, no dynamic function construction
- Registered at source time, not at config parse time

### 5.2 Route Table Supply Chain (R3.2)

- Policy constraints enforced: max routes (10), max attempts (10)
- CI opt-in via `LOA_CUSTOM_ROUTES=1` environment variable
- Effective route table SHA-256 hash logged at startup
- Route table hash can be pinned in CI for reproducibility

### 5.3 Backend Result Contract (FR-1.8)

All backends pass through `validate_review_result()`:
- JSON validity (jq empty)
- Required `verdict` field with enum constraint
- Minimum length (20 chars)
- Array type check on `findings` if present

A backend returning exit 0 with garbage output is treated as failure (fallthrough), not success.

### 5.4 Auth Boundary

No changes to auth model. `ensure_codex_auth()` checks `OPENAI_API_KEY` env-only. No new secrets introduced.

---

## 6. File Inventory

### 6.1 New Files

| File | Purpose | Lines (est.) |
|------|---------|-------------|
| `.claude/scripts/lib-route-table.sh` | Route table parser, registries, executor, result contract | ~300 |
| `.claude/scripts/tests/test-gpt-review-route-table.bats` | Route table unit tests + golden tests | ~250 |
| `.claude/scripts/tests/test-gpt-review-adaptive.bats` | Adaptive multi-pass tests | ~150 |
| `.claude/scripts/tests/fixtures/gpt-review/route-configs/` | YAML fixture files for route table tests | ~10 files |
| `.claude/scripts/tests/fixtures/gpt-review/token-corpus/` | Benchmark corpus for token estimation (≥10 samples) | ~10 files |

### 6.2 Modified Files

| File | Change | Risk |
|------|--------|------|
| `.claude/scripts/gpt-review-api.sh` | Replace `route_review()` body (~56 → ~15 lines), add `source lib-route-table.sh` | **Medium** — core routing path |
| `.claude/scripts/lib-multipass.sh` | Add `classify_complexity()`, `reclassify_with_model_signals()`, modify `run_multipass()` adaptive branch, update `estimate_token_count()` | **Medium** — multi-pass behavior |
| `.claude/scripts/lib-codex-exec.sh` | Optimize `detect_capabilities()` (hoist help text), add Python3 fallback to `parse_codex_output()` | **Low** — additive |
| `.claude/scripts/tests/test-gpt-review-routing.bats` | Add golden tests for backend selection sequences | **Low** — test-only |

### 6.3 Unchanged Files

| File | Why Unchanged |
|------|---------------|
| `lib-security.sh` | No security policy changes |
| `lib-curl-fallback.sh` | Backend functions called via registry, source unchanged |
| `lib/normalize-json.sh` | Already has Python3 raw_decode |
| `.loa.config.yaml` | No changes needed (defaults match cycle-033 behavior) |

---

## 7. Test Strategy

### 7.1 Golden Tests (PRD FR-1.10)

Behavioral equivalence tests asserting exact backend selection sequences:

| Test | Scenario | Expected Sequence |
|------|----------|-------------------|
| `golden_all_available` | All backends available | `hounfour` (success) |
| `golden_hounfour_fail` | Hounfour fails, codex OK | `hounfour` (fail) → `codex` (success) |
| `golden_full_cascade` | Hounfour + codex fail | `hounfour` (fail) → `codex` (fail) → `curl` (success) |
| `golden_curl_only` | execution_mode=curl | `curl` (success) |
| `golden_codex_hard_fail` | execution_mode=codex, codex down | `codex` (hard fail, exit 2) |
| `golden_invalid_json` | Backend returns garbage | backend (fail validation) → next |
| `golden_empty_table` | All routes filtered out | exit 2 |

Implementation: Mock backends via env vars and stub functions in test fixtures.

### 7.2 Route Table Parser Tests

| Test | Input | Expected |
|------|-------|----------|
| `valid_3_routes` | Standard YAML | Parse succeeds, 3 entries |
| `empty_routes` | No routes key | Defaults loaded |
| `unknown_backend` | backend: "nonexistent" | Custom fail-closed (exit 2) |
| `unknown_condition` | when: ["fake"] | Warning, evaluates as false |
| `schema_v2` | route_schema: 2 | Rejected with upgrade message |
| `max_routes_exceeded` | 11 routes | Rejected (max 10) |
| `missing_when` | when: [] | Custom fail-closed (exit 2) |
| `invalid_fail_mode` | fail_mode: "retry" | Warning, defaults to fallthrough |
| `duplicate_backend` | Two hounfour entries | Warning, first wins |

### 7.3 Adaptive Multi-Pass Tests

| Test | Input | Expected |
|------|-------|----------|
| `small_diff_both_low` | 2 files, 50 lines + low model signals | 1 pass (low) |
| `large_diff_det_high` | 20 files, 3000 lines | 3 passes (high) |
| `security_path` | .claude/ in diff | 3 passes (always high) |
| `det_low_model_high` | 2 files + high risk_areas | 3 passes (medium) |
| `det_high_model_low` | 20 files + low risk_areas | 3 passes (medium) |
| `adaptive_disabled` | adaptive: false | Always 3 passes |

### 7.4 Token Estimation Benchmark

10+ code samples with pre-computed tiktoken counts. Test asserts:
- Word-count tier mean error ≤15%
- Word-count tier p95 error ≤25%
- Chars/4 tier included for comparison (expected ~40% error for code)

### 7.5 Result Contract Tests

| Test | Input | Expected |
|------|-------|----------|
| `valid_approved` | `{"verdict":"APPROVED","summary":"good review"}` | Pass |
| `valid_changes` | `{"verdict":"CHANGES_REQUIRED","findings":[...]}` | Pass |
| `missing_verdict` | `{"summary":"..."}` | Fail |
| `invalid_verdict` | `{"verdict":"PASS"}` | Fail |
| `too_short` | `{"verdict":"APPROVED"}` | Fail (< 20 chars) |
| `invalid_json` | `not json` | Fail |
| `findings_not_array` | `{"verdict":"APPROVED","findings":"string"}` | Fail |

### 7.6 Regression Suite

All 117 existing tests from cycle-033 must pass without modification:
- `test-gpt-review-routing.bats` (13 tests)
- `test-gpt-review-codex-adapter.bats`
- `test-gpt-review-multipass.bats`
- `test-gpt-review-security.bats`
- `test-gpt-review-integration.bats`

---

## 8. Migration & Backward Compatibility

### 8.1 Zero-Config Migration

Users with no `gpt_review.routes` in `.loa.config.yaml` get identical behavior:
1. `parse_route_table()` detects no custom routes
2. `_rt_load_defaults()` loads the cycle-033 cascade
3. `execute_route_table()` produces the same sequence: hounfour → codex → curl

### 8.2 execution_mode Compatibility

The legacy `execution_mode` key continues to work:
1. If only `execution_mode` is set → applied as route table filter
2. If both `execution_mode` and `routes` are set → `routes` wins (with log warning)
3. If neither → default table

### 8.3 Adaptive Multi-Pass Default

`multipass.adaptive` defaults to `true`. Users who want cycle-033 behavior (always 3-pass) can set `adaptive: false`.

---

## 9. Technical Risks & Mitigation

| Risk | Severity | Mitigation |
|------|----------|------------|
| yq v4 not available | Medium | `parse_route_table` checks for yq, falls back to defaults |
| Bash 4.0 associative arrays not available | Low | Already required by existing code (bash-version-guard.sh) |
| Route table parse error in production | Medium | Fail-closed for custom routes, fail-open for defaults |
| Adaptive classification too aggressive (skips reviews) | Medium | Dual-signal requires BOTH det+model agreement for single-pass |
| Python3 not available for Tier 2 token estimation | None | Word-count uses `wc -w` (always available), Python only for Tier 1 |
| Backend returns exit 0 with empty output | Low | validate_review_result checks length + JSON + verdict |

---

## 10. Sprint Decomposition Guidance

Suggested sprint structure for implementation:

**Sprint 1: Core Route Table Infrastructure**
- lib-route-table.sh (parse, validate, registries, execute, log)
- Refactor route_review() in gpt-review-api.sh
- validate_review_result() shared gate
- Golden tests for backend selection sequences
- Route table parser tests

**Sprint 2: Adaptive Multi-Pass + Token Estimation**
- classify_complexity() + reclassify_with_model_signals()
- Modify run_multipass() for adaptive flow
- Word-count tier in estimate_token_count()
- Token estimation benchmark corpus
- Adaptive multi-pass tests

**Sprint 3: Polish + Hardening**
- Capability detection optimization (hoist help text)
- Python3 JSON decoder fallback in parse_codex_output()
- Result contract tests
- CI policy constraints (LOA_CUSTOM_ROUTES opt-in)
- Integration verification (all 117 existing tests pass)
