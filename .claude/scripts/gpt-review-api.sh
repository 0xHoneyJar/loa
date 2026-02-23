#!/usr/bin/env bash
# GPT 5.2/5.3 API interaction for cross-model review
# Usage: gpt-review-api.sh <review_type> <content_file> [options]
# See: usage() or --help for full documentation
# Exit codes: 0=success 1=API 2=input 3=timeout 4=auth 5=format

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROMPTS_DIR="${SCRIPT_DIR}/../prompts/gpt-review/base"
CONFIG_FILE=".loa.config.yaml"
MODEL_INVOKE="$SCRIPT_DIR/model-invoke"

source "$SCRIPT_DIR/lib/normalize-json.sh"
source "$SCRIPT_DIR/lib/invoke-diagnostics.sh"
source "$SCRIPT_DIR/bash-version-guard.sh"
source "$SCRIPT_DIR/lib-content.sh"
source "$SCRIPT_DIR/lib-security.sh"
source "$SCRIPT_DIR/lib-codex-exec.sh"
source "$SCRIPT_DIR/lib-curl-fallback.sh"

declare -A DEFAULT_MODELS=(["prd"]="gpt-5.2" ["sdd"]="gpt-5.2" ["sprint"]="gpt-5.2" ["code"]="gpt-5.2-codex")
declare -A PHASE_KEYS=(["prd"]="prd" ["sdd"]="sdd" ["sprint"]="sprint" ["code"]="implementation")
DEFAULT_TIMEOUT=300; MAX_RETRIES=3; RETRY_DELAY=5
DEFAULT_MAX_ITERATIONS=3; DEFAULT_MAX_REVIEW_TOKENS=30000
SYSTEM_ZONE_ALERT="${GPT_REVIEW_SYSTEM_ZONE_ALERT:-true}"

log() { echo "[gpt-review-api] $*" >&2; }
error() { echo "ERROR: $*" >&2; }
skip_review() { printf '{"verdict":"SKIPPED","reason":"%s"}\n' "$1"; exit 0; }

check_config_enabled() {
  local review_type="$1" phase_key="${PHASE_KEYS[$1]}"
  [[ -f "$CONFIG_FILE" ]] && command -v yq &>/dev/null || return 1
  local enabled; enabled=$(yq eval '.gpt_review.enabled // false' "$CONFIG_FILE" 2>/dev/null || echo "false")
  [[ "$enabled" == "true" ]] || return 1
  local key_exists; key_exists=$(yq eval ".gpt_review.phases | has(\"${phase_key}\")" "$CONFIG_FILE" 2>/dev/null || echo "false")
  local phase_raw="true"
  [[ "$key_exists" == "true" ]] && phase_raw=$(yq eval ".gpt_review.phases.${phase_key}" "$CONFIG_FILE" 2>/dev/null || echo "true")
  local pe; pe=$(echo "$phase_raw" | tr '[:upper:]' '[:lower:]')
  [[ "$pe" != "false" && "$pe" != "no" && "$pe" != "off" && "$pe" != "0" ]]
}

load_config() {
  [[ -f "$CONFIG_FILE" ]] && command -v yq &>/dev/null || return 0
  local v; v=$(yq eval '.gpt_review.timeout_seconds // ""' "$CONFIG_FILE" 2>/dev/null || echo "")
  [[ -n "$v" && "$v" != "null" ]] && GPT_REVIEW_TIMEOUT="${GPT_REVIEW_TIMEOUT:-$v}"
  v=$(yq eval '.gpt_review.max_iterations // ""' "$CONFIG_FILE" 2>/dev/null || echo "")
  [[ -n "$v" && "$v" != "null" ]] && MAX_ITERATIONS="$v"
  local dm cm; dm=$(yq eval '.gpt_review.models.documents // ""' "$CONFIG_FILE" 2>/dev/null || echo "")
  cm=$(yq eval '.gpt_review.models.code // ""' "$CONFIG_FILE" 2>/dev/null || echo "")
  [[ -n "$dm" && "$dm" != "null" ]] && { DEFAULT_MODELS["prd"]="$dm"; DEFAULT_MODELS["sdd"]="$dm"; DEFAULT_MODELS["sprint"]="$dm"; }
  [[ -n "$cm" && "$cm" != "null" ]] && DEFAULT_MODELS["code"]="$cm"
  v=$(yq eval '.gpt_review.max_review_tokens // ""' "$CONFIG_FILE" 2>/dev/null || echo "")
  [[ -n "$v" && "$v" != "null" ]] && DEFAULT_MAX_REVIEW_TOKENS="$v"
  v=$(yq eval '.gpt_review.system_zone_alert // ""' "$CONFIG_FILE" 2>/dev/null || echo "")
  [[ -n "$v" && "$v" != "null" ]] && SYSTEM_ZONE_ALERT="$v"
}

detect_system_zone_changes() {
  local sf; sf=$(printf '%s' "$1" | grep -oE '(\+\+\+ b/|diff --git a/)\.claude/[^ ]+' \
    | sed 's|^+++ b/||;s|^diff --git a/||' | sort -u) || true
  [[ -n "$sf" ]] && { echo "$sf"; return 0; }; return 1
}

build_first_review_prompt() {
  local base="${PROMPTS_DIR}/${1}-review.md"
  [[ -f "$base" ]] || { error "Base prompt not found: $base"; exit 2; }
  local sp=""; [[ -n "${2:-}" && -f "${2:-}" ]] && sp="$(cat "$2")"$'\n\n---\n\n'
  printf '%s%s' "$sp" "$(cat "$base")"
}

build_user_prompt() {
  local up=""; [[ -n "$1" && -f "$1" ]] && up="$(cat "$1")"$'\n\n---\n\n'
  printf '%s## Content to Review\n\n%s' "$up" "$2"
}

build_re_review_prompt() {
  local rf="${PROMPTS_DIR}/re-review.md"
  [[ -f "$rf" ]] || { error "Re-review prompt not found: $rf"; exit 2; }
  local sp=""; [[ -n "${3:-}" && -f "${3:-}" ]] && sp="$(cat "$3")"$'\n\n---\n\n'
  local rp; rp=$(cat "$rf"); rp="${rp//\{\{ITERATION\}\}/$1}"; rp="${rp//\{\{PREVIOUS_FINDINGS\}\}/$2}"
  printf '%s%s' "$sp" "$rp"
}

# Execution Router (SDD §3.1): Hounfour → Codex → curl
route_review() {
  local model="$1" sys="$2" usr="$3" timeout="$4" fast="${5:-false}" ta="${6:-false}"
  local em="auto"
  [[ -f "$CONFIG_FILE" ]] && command -v yq &>/dev/null && {
    local c; c=$(yq eval '.gpt_review.execution_mode // "auto"' "$CONFIG_FILE" 2>/dev/null || echo "auto")
    [[ -n "$c" && "$c" != "null" ]] && em="$c"
  }
  # Route 1: Hounfour
  if [[ "$em" != "curl" ]] && is_flatline_routing_enabled && [[ -x "$MODEL_INVOKE" ]]; then
    local r me=0; r=$(call_api_via_model_invoke "$model" "$sys" "$usr" "$timeout") || me=$?
    [[ $me -eq 0 ]] && { echo "$r"; return 0; }
    log "WARNING: model-invoke failed (exit $me), trying next backend"
  fi
  # Route 2: Codex
  if [[ "$em" != "curl" ]]; then
    local ce=0; codex_is_available || ce=$?
    if [[ $ce -eq 0 ]]; then
      local ws of; ws=$(setup_review_workspace "" "$ta"); of=$(mktemp "${ws}/out-$$.XXXXXX")
      local cp; cp=$(printf '%s\n\n---\n\n## CONTENT TO REVIEW:\n\n%s\n\n---\n\nRespond with valid JSON only. Include "verdict": "APPROVED"|"CHANGES_REQUIRED"|"DECISION_NEEDED".' "$sys" "$usr")
      local ee=0; codex_exec_single "$cp" "$model" "$of" "$ws" "$timeout" || ee=$?
      if [[ $ee -eq 0 && -s "$of" ]]; then
        local raw; raw=$(cat "$of"); cleanup_workspace "$ws"
        local pr; pr=$(parse_codex_output "$raw" 2>/dev/null) || pr=""
        if [[ -n "$pr" ]] && echo "$pr" | jq -e '.verdict' &>/dev/null; then
          echo "$pr"; return 0
        fi; log "WARNING: codex response invalid, falling back to curl"
      else
        cleanup_workspace "$ws"
        [[ "$em" == "codex" ]] && { error "Codex failed (exit $ee), execution_mode=codex (hard fail)"; return 2; }
        log "WARNING: codex exec failed (exit $ee), falling back to curl"
      fi
    elif [[ "$em" == "codex" ]]; then
      error "Codex unavailable (exit $ce), execution_mode=codex (hard fail)"; return 2
    fi
  fi
  # Route 3: curl fallback
  call_api "$model" "$sys" "$usr" "$timeout"
}

usage() {
  cat <<'USAGE'
Usage: gpt-review-api.sh <review_type> <content_file> [options]
  review_type: prd | sdd | sprint | code
Options:
  --expertise <file>   Domain expertise (SYSTEM prompt)
  --context <file>     Product/feature context (USER prompt)
  --iteration <N>      Review iteration (1=first, 2+=re-review)
  --previous <file>    Previous findings JSON (for iteration > 1)
  --output <file>      Write JSON response to file
  --fast               Single-pass mode
  --tool-access        Repo-root file access for Codex
Environment: OPENAI_API_KEY (required, env var only)
USAGE
}

main() {
  local rt="" cf="" ef="" ctf="" iter=1 pf="" of="" fast="false" ta="false"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --expertise) ef="$2"; shift 2;; --context) ctf="$2"; shift 2;;
      --iteration) iter="$2"; shift 2;; --previous) pf="$2"; shift 2;;
      --output) of="$2"; shift 2;; --fast) fast="true"; shift;;
      --tool-access) ta="true"; shift;; --help|-h) usage; exit 0;;
      -*) error "Unknown option: $1"; usage; exit 2;;
      *) if [[ -z "$rt" ]]; then rt="$1"; elif [[ -z "$cf" ]]; then cf="$1"; fi; shift;;
    esac
  done
  [[ -z "$rt" ]] && { usage; exit 2; }
  [[ "${DEFAULT_MODELS[$rt]+x}" ]] || { error "Invalid review type: $rt"; exit 2; }
  [[ -n "$cf" && -f "$cf" ]] || { error "Content file required/not found"; exit 2; }
  [[ -n "$ef" && -f "$ef" ]] || { error "--expertise file required/not found"; exit 2; }
  [[ -n "$ctf" && -f "$ctf" ]] || { error "--context file required/not found"; exit 2; }
  ensure_codex_auth || { error "OPENAI_API_KEY not set"; exit 4; }
  command -v jq &>/dev/null || { error "jq required"; exit 2; }

  MAX_ITERATIONS="$DEFAULT_MAX_ITERATIONS"; load_config
  if [[ "$iter" -gt "$MAX_ITERATIONS" ]]; then
    log "Iteration $iter exceeds max ($MAX_ITERATIONS) - auto-approving"
    local ar; ar=$(printf '{"verdict":"APPROVED","summary":"Auto-approved after %s iterations","auto_approved":true,"iteration":%s}' "$MAX_ITERATIONS" "$iter")
    [[ -n "$of" ]] && { mkdir -p "$(dirname "$of")"; echo "$ar" > "$of"; }
    echo "$ar"; exit 0
  fi

  local model="${GPT_REVIEW_MODEL:-${DEFAULT_MODELS[$rt]}}" timeout="${GPT_REVIEW_TIMEOUT:-$DEFAULT_TIMEOUT}"
  log "Review: type=$rt iter=$iter model=$model timeout=${timeout}s fast=$fast"

  local sp
  if [[ "$iter" -eq 1 ]]; then sp=$(build_first_review_prompt "$rt" "$ef")
  else [[ -n "$pf" && -f "$pf" ]] || { error "Re-review requires --previous"; exit 2; }
    sp=$(build_re_review_prompt "$iter" "$(cat "$pf")" "$ef"); fi

  local raw; raw=$(cat "$cf")
  local szw=""
  if [[ "$SYSTEM_ZONE_ALERT" == "true" ]]; then
    local szf=""; szf=$(detect_system_zone_changes "$raw") && \
      szw="SYSTEM ZONE (.claude/) CHANGES DETECTED. Elevated scrutiny: $(echo "$szf" | tr '\n' ', ' | sed 's/,$//')"
    [[ -n "$szw" ]] && log "WARNING: $szw"
  fi

  local mrt="${GPT_REVIEW_MAX_TOKENS:-$DEFAULT_MAX_REVIEW_TOKENS}"
  local pc; pc=$(prepare_content "$raw" "$mrt")
  [[ -n "$szw" ]] && pc=">>> ${szw}"$'\n\n'"${pc}"
  local up; up=$(build_user_prompt "$ctf" "$pc")

  local resp; resp=$(route_review "$model" "$sp" "$up" "$timeout" "$fast" "$ta")
  resp=$(echo "$resp" | jq --arg i "$iter" '. + {iteration: ($i | tonumber)}')
  [[ -n "$szw" ]] && resp=$(echo "$resp" | jq '. + {system_zone_detected: true}')
  resp=$(echo "$resp" | tr -d '\033' | tr -d '\000-\010\013\014\016-\037')
  resp=$(redact_secrets "$resp" "json")

  [[ -n "$of" ]] && { mkdir -p "$(dirname "$of")"; echo "$resp" > "$of"; log "Written to: $of"; }
  echo "$resp"
}

main "$@"
