#!/usr/bin/env bash
# =============================================================================
# flatline-orchestrator.sh - Main orchestrator for Flatline Protocol
# =============================================================================
# Version: 1.1.0
# Part of: Flatline Protocol v1.17.0, Autonomous Flatline v1.22.0
#
# Usage:
#   flatline-orchestrator.sh --doc <path> --phase <type> [options]
#
# Options:
#   --doc <path>           Document to review (required)
#   --phase <type>         Phase type: prd, sdd, sprint, beads, spec, pr (required)
#   --domain <text>        Domain for knowledge retrieval (auto-extracted if not provided)
#   --interactive          Force interactive mode (overrides auto-detection)
#   --autonomous           Force autonomous mode (overrides auto-detection)
#   --run-id <id>          Run ID for manifest tracking (autonomous mode)
#   --dry-run              Validate without executing reviews
#   --skip-knowledge       Skip knowledge retrieval
#   --skip-consensus       Return raw reviews without consensus
#   --timeout <seconds>    Overall timeout (default: 300)
#   --budget <cents>       Cost budget in cents (default: 300 = $3.00)
#   --json                 Output as JSON
#   --no-silent-noop-detect  Disable post-run silent-no-op detection (cycle-062, #485)
#
# Mode Detection Precedence:
#   1. CLI flags (--interactive, --autonomous)
#   2. Environment variable (LOA_FLATLINE_MODE)
#   3. Config file (autonomous_mode.enabled)
#   4. Auto-detection (strong AI signals only)
#   5. Default (interactive)
#
# State Machine:
#   INIT -> KNOWLEDGE -> PHASE1 -> PHASE2 -> CONSENSUS -> INTEGRATE -> DONE
#
# Exit codes:
#   0 - Success
#   1 - Configuration error
#   2 - Knowledge retrieval failed (non-fatal)
#   3 - All model calls failed
#   4 - Timeout exceeded
#   5 - Budget exceeded
#   6 - Partial success (degraded mode)
#   7 - Silent no-op detected (no findings/attacks produced; see --no-silent-noop-detect)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/bootstrap.sh"
source "$SCRIPT_DIR/lib/normalize-json.sh"
source "$SCRIPT_DIR/lib/invoke-diagnostics.sh"
source "$SCRIPT_DIR/lib/context-isolation-lib.sh"
# cycle-099 Sprint 1B parity (mirrors red-team-model-adapter.sh): exposes
# `resolve_provider_id` from generated-model-maps.sh so flatline picks up
# new model registry entries (gpt-5.5, gpt-5.5-pro, gemini-3.1-pro-preview,
# etc.) without needing edits to the local MODEL_TO_PROVIDER_ID fallback.
# shellcheck source=lib/model-resolver.sh
source "$SCRIPT_DIR/lib/model-resolver.sh"

# Cycle-104 sprint-2 T2.8 (FR-S2.5): voice-drop classifier. Distinguishes
# cheval's CHAIN_EXHAUSTED (exit 12) from other failures so a voice whose
# within-company fallback chain ran to end is DROPPED from consensus
# instead of being treated as a hard failure or silently substituted across
# companies. SDD §6.5.
VOICE_DROP_CLASSIFIER="$SCRIPT_DIR/lib/voice-drop-classifier.sh"

# Note: bootstrap.sh already handles PROJECT_ROOT canonicalization via realpath
TRAJECTORY_DIR=$(get_trajectory_dir)

# cycle-109 Sprint 3 T3.5 (#820 Issue D): source .env / .env.local so
# provider API keys cross into the model-adapter / model-invoke /
# cheval.py subprocess chain. Mirrors the BB pattern at
# .claude/skills/bridgebuilder-review/resources/entry.sh (cycle-037 #395).
#
# .env Trust Model: `source .env` executes arbitrary shell code by
# design. .env files are trusted local input — user-controlled, never
# committed (.gitignore'd). Same trust model as Node's dotenv and
# Python's python-dotenv. API keys sourced here are available to the
# subsequent subprocess invocations.
#
# set -a exports all sourced variables (so they cross subprocess
# boundaries); set +a restores default behavior.
if [[ -f .env ]]; then
    set -a; source .env; set +a
fi
if [[ -f .env.local ]]; then
    set -a; source .env.local; set +a
fi

# Component scripts
MODEL_ADAPTER="$SCRIPT_DIR/model-adapter.sh"
# bug-899 / BB #915 F-001: honor a pre-set MODEL_INVOKE so tests sourcing
# this script can substitute a stub. Production callers always invoke as
# a top-level executable (BASH_SOURCE guard runs main()), so MODEL_INVOKE
# isn't in their env — `:-` is a no-op there. Tests that source the
# script can `export MODEL_INVOKE=/path/to/stub` before sourcing and
# exercise call_model end-to-end.
MODEL_INVOKE="${MODEL_INVOKE:-$SCRIPT_DIR/model-invoke}"
SCORING_ENGINE="$SCRIPT_DIR/scoring-engine.sh"
KNOWLEDGE_LOCAL="$SCRIPT_DIR/flatline-knowledge-local.sh"
NOTEBOOKLM_QUERY="$PROJECT_ROOT/.claude/skills/flatline-knowledge/resources/notebooklm-query.py"

# Default configuration
DEFAULT_TIMEOUT=300
DEFAULT_BUDGET=300  # cents ($3.00)
DEFAULT_MODEL_TIMEOUT=120

# Issue #675 (sub-issue 4): per-call max_tokens override. Empty = use the
# downstream default (cheval.py's default 4096 / model-adapter.sh's hardcoded
# 4096). Historical (#675): Anthropic disconnected ~60s for max_tokens > 4096
# on very large prompts; operators could lower this knob for large-document
# reviews. NOTE (#774): the disconnect failure mode now manifests at much
# smaller doc sizes (~38KB observed) and on OpenAI as well. Lowering the
# knob is a no-op against `failure_class=PROVIDER_DISCONNECT` — the flag is
# preserved for back-compat only.
PER_CALL_MAX_TOKENS=""

# State tracking
STATE="INIT"
TOTAL_COST=0
TOTAL_TOKENS=0
START_TIME=""

# Temp directory for intermediate files
TEMP_DIR=""

# =============================================================================
# Logging
# =============================================================================

log() {
    echo "[flatline] $*" >&2
}

error() {
    echo "ERROR: $*" >&2
}

# =============================================================================
# Silent-no-op detection (cycle-062, #485)
# =============================================================================
# Extends the cycle-058 pattern from bridge-orchestrator to flatline. Guards
# against the class of bug where jq construction fails (e.g., parser error)
# yet the script still exits 0 because the empty result was swallowed.
#
# For each orchestrator mode, verifies the final_result is non-empty valid JSON
# with mode-specific required fields. On failure, emits a clear diagnostic and
# exits non-zero.
#
# Arguments:
#   $1 - orchestrator mode (review|red-team|inquiry)
#   $2 - final_result JSON string
# =============================================================================
detect_silent_noop_flatline() {
    local mode="$1"
    local result="$2"

    # Non-empty result required.
    if [[ -z "$result" ]]; then
        error "Silent no-op detected in mode=$mode: final_result is empty."
        error "This usually indicates jq construction failed without a hard exit."
        error "Re-run with logs enabled or pass --no-silent-noop-detect to bypass."
        exit 7
    fi

    # Valid JSON required.
    if ! echo "$result" | jq -e . >/dev/null 2>&1; then
        error "Silent no-op detected in mode=$mode: final_result is not valid JSON."
        error "This usually means the jq pipeline emitted a parse/type error."
        error "Re-run with logs enabled or pass --no-silent-noop-detect to bypass."
        exit 7
    fi

    # Mode-specific required fields.
    case "$mode" in
        red-team)
            # Red-team runs MUST produce a mode="red-team" field and an attacks
            # object (may be empty if model legitimately found no vulnerabilities —
            # that is valid). We only check structural integrity here.
            if ! echo "$result" | jq -e '.mode == "red-team"' >/dev/null 2>&1; then
                error "Silent no-op in red-team mode: missing .mode=\"red-team\" field."
                exit 7
            fi
            ;;
        inquiry)
            if ! echo "$result" | jq -e '.orchestrator_mode == "inquiry"' >/dev/null 2>&1; then
                error "Silent no-op in inquiry mode: missing .orchestrator_mode=\"inquiry\" field."
                exit 7
            fi
            ;;
        review)
            # Review mode result should have a phase and timestamp at minimum.
            if ! echo "$result" | jq -e '(.phase != null) and (.timestamp != null)' >/dev/null 2>&1; then
                error "Silent no-op in review mode: missing required .phase or .timestamp."
                exit 7
            fi
            ;;
        *)
            # Defense-in-depth: unknown mode should never reach the helper,
            # but if it does, refuse rather than silently skip validation.
            error "Silent no-op helper called with unknown mode: $mode"
            error "Expected one of: red-team, inquiry, review."
            exit 7
            ;;
    esac
}

# Strip markdown code blocks from JSON content (some models wrap JSON in ```json ... ```)
strip_markdown_json() {
    local content="$1"
    # Handle multi-line markdown blocks:
    # 1. Remove leading ```json or ``` (with optional newline)
    # 2. Remove trailing ``` (with optional preceding newline)
    echo "$content" | sed -E '
        # Remove opening code fence with language tag
        s/^```(json)?[[:space:]]*\n?//
        # Remove closing code fence
        s/\n?```[[:space:]]*$//
    '
}

# #582: compute grounding-failure stats from a red-team result JSON.
#
# Pure function — no side effects, no exits. Takes the red-team final_result
# on stdin and emits `{total, opus_zero, opus_zero_ratio, threshold,
# min_attacks, grounding_failure}` on stdout. Callers interpret the
# `grounding_failure` boolean to decide whether to halt.
#
# Exposed as a function (not inline) so BATS can exercise the runtime
# exit behavior against known fixtures — addresses Gemini's PR #583
# review finding M001 ("exit 3 is grep-verified, not runtime-verified").
#
# Usage: echo "$final_result_json" | compute_grounding_stats <threshold> <min_attacks>
compute_grounding_stats() {
    local threshold="${1:-0.8}"
    local min_attacks="${2:-3}"

    jq -c --argjson threshold "$threshold" --argjson min "$min_attacks" '
        def scored_attacks:
            [ (.attacks.confirmed // [])[],
              (.attacks.theoretical // [])[],
              (.attacks.creative // [])[],
              (.attacks.defended // [])[]
            ];
        (scored_attacks) as $all
        | ($all | length) as $total
        | ([$all[] | select(.opus_score == 0 or .opus_score == "0")] | length) as $opus_zero
        | (if $total > 0 then ($opus_zero / $total) else 0 end) as $ratio
        | {
            total: $total,
            opus_zero: $opus_zero,
            opus_zero_ratio: $ratio,
            threshold: $threshold,
            min_attacks: $min,
            grounding_failure: ($total >= $min and $ratio >= $threshold)
        }
    ' 2>/dev/null || echo '{"grounding_failure":false}'
}

# Extract and parse JSON content from model response
# Uses centralized normalize_json_response() from lib/normalize-json.sh
extract_json_content() {
    local file="$1"
    local default="$2"
    local agent="${3:-}"

    if [[ ! -f "$file" ]]; then
        echo "$default"
        return
    fi

    local content
    content=$(jq -r '.content // ""' "$file" 2>/dev/null)

    if [[ -z "$content" || "$content" == "null" ]]; then
        echo "$default"
        return
    fi

    # Normalize via centralized library (handles BOM, fences, prose wrapping)
    local normalized
    normalized=$(normalize_json_response "$content" 2>/dev/null) || {
        log "WARNING: JSON normalization failed for $file — using default"
        echo "$default"
        return
    }

    # Per-agent schema validation if agent specified
    if [[ -n "$agent" ]]; then
        if ! validate_agent_response "$normalized" "$agent" 2>/dev/null; then
            log "WARNING: Schema validation failed for agent '$agent' in $file"
        fi
    fi

    echo "$normalized"
}

# Log to trajectory
log_trajectory() {
    local event_type="$1"
    local data="$2"

    # Security: Create log directory with restrictive permissions
    (umask 077 && mkdir -p "$TRAJECTORY_DIR")
    local date_str
    date_str=$(date +%Y-%m-%d)
    local log_file="$TRAJECTORY_DIR/flatline-$date_str.jsonl"

    # Ensure log file has restrictive permissions
    touch "$log_file"
    chmod 600 "$log_file"

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    jq -n \
        --arg type "flatline_protocol" \
        --arg event "$event_type" \
        --arg timestamp "$timestamp" \
        --arg state "$STATE" \
        --argjson data "$data" \
        '{type: $type, event: $event, timestamp: $timestamp, state: $state, data: $data}' >> "$log_file"
}

# Cycle-104 sprint-2 T2.8 (FR-S2.5): emit a single `consensus.voice_dropped`
# event when a voice's within-company chain exhausted. Caller passes the
# voice label (e.g. "opus-review") and the orchestrator phase. Soft-fails
# on jq errors so a logging glitch never aborts the consensus path.
emit_voice_dropped() {
    local voice_label="$1"
    local phase="${2:-unknown}"
    local payload
    payload=$(jq -nc \
        --arg voice "$voice_label" \
        --arg phase "$phase" \
        --arg reason "chain_exhausted" \
        '{voice: $voice, phase: $phase, reason: $reason, exit_code: 12}' 2>/dev/null) || return 0
    log_trajectory "consensus.voice_dropped" "$payload" || true
    log "Voice dropped from consensus (chain exhausted): $voice_label"
}

# Cycle-104 sprint-2 T2.8: classify a captured call_model exit code.
# Returns "success" | "dropped" | "failed" on stdout.
classify_voice_exit_status() {
    local code="$1"
    "$VOICE_DROP_CLASSIFIER" "$code" 2>/dev/null || echo "failed"
}

# =============================================================================
# Configuration
# =============================================================================

read_config() {
    local path="$1"
    local default="$2"
    if [[ -f "$CONFIG_FILE" ]] && command -v yq &> /dev/null; then
        local value
        value=$(yq -r "$path // \"\"" "$CONFIG_FILE" 2>/dev/null)
        if [[ -n "$value" && "$value" != "null" ]]; then
            echo "$value"
            return
        fi
    fi
    echo "$default"
}

is_flatline_enabled() {
    local enabled
    enabled=$(read_config '.flatline_protocol.enabled' 'false')
    [[ "$enabled" == "true" ]]
}

get_model_primary() {
    read_config '.flatline_protocol.models.primary' 'opus'
}

get_model_secondary() {
    read_config '.flatline_protocol.models.secondary' 'gpt-5.3-codex'
}

# Provisional resolution — will be replaced by Hounfour router capability
# query when ModelPort interface is available (see loa-finn #31).
# The function signature is the durable contract; the config lookup is temporary.
#
# Checks hounfour config first (canonical), then flatline_protocol.models.tertiary (alias)
# Returns empty string when not configured (2-model mode preserved)
# Cache avoids repeated yq invocations during a single Flatline run
_CACHED_TERTIARY_MODEL=""
_CACHED_TERTIARY_MODEL_SET=false

get_model_tertiary() {
    if [[ "$_CACHED_TERTIARY_MODEL_SET" == true ]]; then
        echo "$_CACHED_TERTIARY_MODEL"
        return
    fi
    local model
    model=$(read_config '.hounfour.flatline_tertiary_model' '')
    if [[ -z "$model" ]]; then
        model=$(read_config '.flatline_protocol.models.tertiary' '')
    fi
    _CACHED_TERTIARY_MODEL="$model"
    _CACHED_TERTIARY_MODEL_SET=true
    echo "$model"
}

get_max_iterations() {
    read_config '.flatline_protocol.max_iterations' '5'
}

# Valid model names — known-good models verified against live APIs.
# Phantom Gemini 3 entries (gemini-3-pro, gemini-3-flash, gemini-3.1-pro)
# removed per #574: they passed allowlist but Google v1beta returned
# NOT_FOUND at runtime, collapsing the Flatline review.
#
# Forward-compat regex VALID_MODEL_PATTERNS admits new model versions
# without requiring code edits (per #573 operator experience with
# gpt-5.4-codex). The regex structure ensures typos still fail fast.
# VALID_FLATLINE_MODELS — Sprint-4 T4.2 (closes SDD §1.4 C4 SSOT coverage gap).
# Now derived from .claude/defaults/model-config.yaml via gen-adapter-maps.sh
# rather than hand-maintained. Source the generated file if available;
# fall back to a stub allowlist if the generator hasn't run (model-adapter
# tooling will surface the actual error path on use).
_GENERATED_MAPS="$(dirname "${BASH_SOURCE[0]}")/generated-model-maps.sh"
if [[ -f "$_GENERATED_MAPS" ]]; then
    # shellcheck source=generated-model-maps.sh
    source "$_GENERATED_MAPS"
else
    # Fallback (should never trigger in checked-in state — generator is run
    # alongside YAML edits per SDD §4.3 Flow 1).
    declare -a VALID_FLATLINE_MODELS=(opus gpt-5.3-codex claude-opus-4-7 claude-sonnet-4-6 gemini-2.5-pro)
fi

# Forward-compat patterns for provider-side verified models not yet in
# the explicit allowlist. Operators running newer models (gpt-5.4-codex,
# gemini-3.0-pro, claude-opus-4-8) can set them in config and the
# pattern admits them; provider-side validation at API call time catches
# typos/invalid names with a clearer error than a pre-runtime allowlist.
# Note: gemini pattern requires X.Y (with dot). Variants like gemini-3-flash
# don't match and must wait for explicit allowlist addition.
VALID_MODEL_PATTERNS=(
    '^gpt-[0-9]+\.[0-9]+(-codex)?$'          # openai: gpt-5.2, gpt-5.3-codex, gpt-5.4-codex, gpt-6.0
    '^claude-(opus|sonnet|haiku)-[0-9]+[-.][0-9]+$'  # anthropic: claude-opus-4-7, claude-sonnet-4-6
    '^gemini-[0-9]+\.[0-9]+(-flash|-pro)?(-preview)?$'  # google: gemini-2.5-pro, gemini-3.1-pro-preview (cycle-109 T3.4 #793: -preview suffix)
    '^(opus|sonnet|haiku)$'                  # short anthropic aliases (DISS-002: anchored alternation)
    # cycle-109 Sprint 3 T3.4 (#793): cheval-headless pin form.
    # PR #727 (cycle-098) introduced subscription-auth headless adapters;
    # the orchestrator's pre-validator must admit the canonical pin shape
    # so operators following the cycle-098/099 setup don't fall back to
    # API providers (which defeats the cost-via-subscription benefit).
    '^(claude|codex|gemini)-headless:.+$'    # cheval-headless pin form
)

validate_model() {
    local model="$1"
    local config_key="$2"  # e.g., "primary" or "secondary"

    if [[ -z "$model" ]]; then
        error "Flatline model '$config_key' is empty. Set flatline_protocol.models.$config_key in .loa.config.yaml"
        error "Valid models: ${VALID_FLATLINE_MODELS[*]}"
        return 1
    fi

    # Explicit allowlist match
    for valid_model in "${VALID_FLATLINE_MODELS[@]}"; do
        if [[ "$model" == "$valid_model" ]]; then
            return 0
        fi
    done

    # Forward-compat pattern match — accept plausible model names so operators
    # running new vendor releases don't need to wait for a Loa update. The
    # provider-side call will reject actually-invalid names with a clearer
    # error than a pre-runtime allowlist.
    for pattern in "${VALID_MODEL_PATTERNS[@]}"; do
        if [[ "$model" =~ $pattern ]]; then
            log "Flatline model '$model' (config_key=$config_key) accepted via forward-compat pattern" >&2
            return 0
        fi
    done

    error "Unknown flatline model: '$model' (from flatline_protocol.models.$config_key in .loa.config.yaml)"
    error "Known-good models: ${VALID_FLATLINE_MODELS[*]}"
    error "Forward-compat patterns also accepted: gpt-X.Y(-codex), claude-{opus|sonnet|haiku}-X-Y, gemini-X.Y(-flash|-pro)"
    error "Note: '$model' may be an agent alias, not a model name. Check .claude/defaults/model-config.yaml for alias mappings."
    return 1
}

is_notebooklm_enabled() {
    local enabled
    enabled=$(read_config '.flatline_protocol.knowledge.notebooklm.enabled' 'false')
    [[ "$enabled" == "true" ]]
}

get_notebooklm_notebook_id() {
    read_config '.flatline_protocol.knowledge.notebooklm.notebook_id' ''
}

get_notebooklm_timeout() {
    read_config '.flatline_protocol.knowledge.notebooklm.timeout_ms' '30000'
}

# =============================================================================
# Hounfour Routing (SDD §4.4.2)
# =============================================================================

# cycle-109 Sprint 3 T3.8 (commit E): is_flatline_routing_enabled()
# definition removed. T3.6 removed the consuming branch at call_model
# (cheval is now the unconditional dispatch path); T3.7 deleted the
# legacy adapter the flag used to gate. Other files retain their own
# copies of the helper for non-flatline-orchestrator callers; cleanup
# of those callsites is tracked as a follow-up.

# Mode → Agent mapping for model-invoke routing
declare -A MODE_TO_AGENT=(
    ["review"]="flatline-reviewer"
    ["skeptic"]="flatline-skeptic"
    ["score"]="flatline-scorer"
    ["dissent"]="flatline-dissenter"
)

# Legacy model name → provider:model-id for model-invoke --model override.
# Phantom Gemini 3 entries (gemini-3-flash, gemini-3-pro) removed per #574 —
# they passed allowlist but Google v1beta returned NOT_FOUND at runtime.
# Re-add when vendor confirms availability (smoke test via live API first).
declare -A MODEL_TO_PROVIDER_ID=(
    ["gpt-5.2"]="openai:gpt-5.2"
    ["gpt-5.3-codex"]="openai:gpt-5.3-codex"
    ["opus"]="anthropic:claude-opus-4-7"
    ["claude-opus-4.7"]="anthropic:claude-opus-4-7"
    ["claude-opus-4-7"]="anthropic:claude-opus-4-7"
    ["claude-opus-4.6"]="anthropic:claude-opus-4-7"    # Retargeted in bash layer (cycle-082)
    ["claude-opus-4-6"]="anthropic:claude-opus-4-7"    # Retargeted in bash layer (cycle-082)
    ["claude-sonnet-4-6"]="anthropic:claude-sonnet-4-6"
    ["gemini-2.0"]="google:gemini-2.0-flash"
    ["gemini-2.5-flash"]="google:gemini-2.5-flash"
    ["gemini-2.5-pro"]="google:gemini-2.5-pro"
)

# cycle-109 Sprint 2 T2.4 — verdict_quality multi-voice aggregation
# (CONSUMER #2 per SDD §3.2.3 IMP-004).
#
# Reads verdict_quality from each per-voice phase1 output file, shells out
# to `python -m loa_cheval.verdict.aggregate` (the canonical Python
# aggregator per SDD §5.2.1 — bash twin never reimplements the merge
# logic), and writes the aggregated multi-voice envelope to
# final_consensus.json alongside the existing phase artifacts.
#
# Usage: aggregate_and_write_final_consensus <phase> <file1> [<file2> ...]
# Files are phase1 output JSON files; each is expected to carry a
# verdict_quality field (legacy / pre-T2.3 cheval emits omit the field;
# such voices are silently skipped from the aggregate).
#
# Fail-soft: missing python module / empty input / aggregator error
# logs a warning but does NOT abort the orchestrator. The final
# consensus calculation runs regardless.
aggregate_and_write_final_consensus() {
    local phase="$1"
    shift
    local -a input_files=("$@")
    if [[ ${#input_files[@]} -eq 0 ]]; then
        log "[vq-aggregate] no input files supplied — skipping"
        return 0
    fi

    local output_dir="$PROJECT_ROOT/grimoires/loa/a2a/flatline"
    mkdir -p "$output_dir"
    local target="$output_dir/${phase}-final_consensus.json"

    # Extract verdict_quality from each input file into per-voice tmp files.
    local -a vq_files=()
    local cleanup_files=()
    local f vq
    for f in "${input_files[@]}"; do
        [[ -s "$f" ]] || continue
        vq=$(jq -c '.verdict_quality // empty' "$f" 2>/dev/null || true)
        if [[ -n "$vq" && "$vq" != "null" ]]; then
            local tmp
            tmp=$(mktemp "${TEMP_DIR:-/tmp}/vq-input.XXXXXX.json")
            printf '%s' "$vq" > "$tmp"
            vq_files+=("$tmp")
            cleanup_files+=("$tmp")
        fi
    done

    if [[ ${#vq_files[@]} -eq 0 ]]; then
        log "[vq-aggregate] no verdict_quality envelopes found in inputs — skipping ${target##*/} (legacy / pre-T2.3 cheval emits)"
        return 0
    fi

    # Shell out to the canonical Python aggregator. PYTHONPATH points at
    # .claude/adapters so loa_cheval is importable without an install step.
    #
    # PR #896 BB iter-1 FIND-003 closure: pass `--expected-voices-count`
    # = ${#input_files[@]} (the EXPECTED cohort size, not the count of
    # envelopes that actually arrived). Missing voices are recorded in
    # voices_dropped[] instead of silently shrinking voices_planned —
    # which would have turned "2-of-3 degraded" into "APPROVED 2-of-2".
    local agg_out agg_rc=0
    agg_out=$(PYTHONPATH="$PROJECT_ROOT/.claude/adapters" \
        python3 -m loa_cheval.verdict.aggregate \
            --expected-voices-count "${#input_files[@]}" \
            "${vq_files[@]}" 2>&1) || agg_rc=$?
    if [[ $agg_rc -ne 0 ]]; then
        log "[vq-aggregate] aggregator failed (rc=$agg_rc): $agg_out"
    else
        printf '%s\n' "$agg_out" | jq . > "$target" 2>/dev/null || {
            log "[vq-aggregate] aggregator output not valid JSON; skipping write"
        }
        if [[ -s "$target" ]]; then
            local final_status
            final_status=$(jq -r '.status' "$target" 2>/dev/null || echo "?")
            log "[vq-aggregate] wrote $target (status=$final_status, voices=${#vq_files[@]}/${#input_files[@]})"
        fi
    fi

    # Clean up per-voice tmp inputs.
    local c
    for c in "${cleanup_files[@]}"; do
        rm -f "$c" 2>/dev/null || true
    done
}

# Unified model call: routes through model-invoke (direct) or model-adapter.sh (legacy)
# Usage: call_model <model> <mode> <input> <phase> [context] [timeout]
call_model() {
    local model="$1"
    local mode="$2"
    local input="$3"
    local phase="$4"
    local context="${5:-}"
    local timeout="${6:-$DEFAULT_MODEL_TIMEOUT}"

    # cycle-109 Sprint 3 T3.6 (commit C in SDD §5.3.1 sequence): the
    # pre-fix `if is_flatline_routing_enabled && [[ -x "$MODEL_INVOKE" ]];
    # then ... else <legacy> fi` branch was removed. cheval (model-invoke)
    # is now the unconditional dispatch path. The legacy MODEL_ADAPTER
    # fallback else-branch was deleted alongside the conditional;
    # MODEL_ADAPTER is preserved (T3.8 cleanup) but no caller path here
    # invokes it.
    if [[ ! -x "$MODEL_INVOKE" ]]; then
        log "ERROR: MODEL_INVOKE not executable at $MODEL_INVOKE — substrate misconfigured"
        return 2
    fi
    {
        # Direct model-invoke path (SDD §4.4.2)
        local agent="${MODE_TO_AGENT[$mode]:-}"
        # cycle-099 Sprint 1B + post-Sprint-2E parity: prefer the SSOT-aware
        # resolver (model-resolver.sh::resolve_provider_id) which reads
        # generated-model-maps.sh; fall back to the local MODEL_TO_PROVIDER_ID
        # for legacy aliases that intentionally aren't in model-config.yaml.
        # Mirrors the red-team-model-adapter.sh pattern.
        local model_override
        if model_override="$(resolve_provider_id "$model" 2>/dev/null)"; then
            : # canonical alias resolved via shared lib
        else
            model_override="${MODEL_TO_PROVIDER_ID[$model]:-$model}"
        fi

        if [[ -z "$agent" ]]; then
            log "ERROR: Unknown mode for model-invoke: $mode"
            return 2
        fi

        local -a args=(
            --agent "$agent"
            --input "$input"
            --model "$model_override"
            --output-format json
            --json-errors
            --timeout "$timeout"
        )

        # Issue #675 (sub-issue 4): plumb operator-supplied max_tokens override
        # to model-invoke (cheval --max-tokens). When unset, cheval defaults to
        # 4096 (cheval.py:337 `args.max_tokens or 4096`).
        if [[ -n "${PER_CALL_MAX_TOKENS:-}" ]]; then
            args+=(--max-tokens "$PER_CALL_MAX_TOKENS")
        fi

        if [[ -n "$context" && -f "$context" ]]; then
            args+=(--system "$context")
        fi

        # Per-invocation diagnostic log (unique suffix for parallel calls)
        local invoke_log
        invoke_log=$(setup_invoke_log "flatline-${mode}-${model}")

        # cycle-109 Sprint 2 T2.4 — verdict_quality sidecar (CONSUMER #2).
        # Allocate a per-call sidecar path so cheval writes its envelope
        # back into a per-voice file. Parallel-dispatch safe because each
        # invocation gets a unique TEMP_DIR-rooted path (TEMP_DIR is set
        # by the orchestrator's setup; mode+model+PID-derived suffix keeps
        # concurrent reviews on the same model distinct).
        local vq_sidecar
        vq_sidecar="${TEMP_DIR:-/tmp}/vq-${mode}-${model//[^A-Za-z0-9_-]/_}-$$-$RANDOM.json"

        local result exit_code=0
        # Synchronous stderr capture — avoids process substitution race condition
        # where >(redact_secrets) may not finish writing before log is read
        result=$(LOA_VERDICT_QUALITY_SIDECAR="$vq_sidecar" \
            "$MODEL_INVOKE" "${args[@]}" 2>"${invoke_log}.raw") || exit_code=$?
        if [[ -s "${invoke_log}.raw" ]]; then
            redact_secrets < "${invoke_log}.raw" >> "$invoke_log"
        fi
        rm -f "${invoke_log}.raw"

        if [[ $exit_code -ne 0 ]]; then
            # bug-899: preserve verdict_quality envelope on failure so the
            # cohort aggregator (see line 534 region) can attribute
            # blocker_risk / reason / chain health to this voice. cheval
            # writes the envelope to the sidecar BEFORE the failure mode
            # that drives a non-zero exit becomes observable, so the
            # sidecar's FAILED/DEGRADED envelope carries the attribution
            # we need; deleting it before the aggregator runs causes the
            # cohort verdict to silently drop this voice's failure signal.
            # Mirror of the success-path read below at line ~715.
            local vq_envelope_on_failure="null"
            if [[ -s "$vq_sidecar" ]] && jq empty < "$vq_sidecar" 2>/dev/null; then
                vq_envelope_on_failure=$(cat "$vq_sidecar")
            fi
            if [[ "$vq_envelope_on_failure" != "null" ]]; then
                # Emit a failure-shaped per-voice output to stdout so the
                # caller's `>` redirect captures the envelope. Aggregator
                # reads .verdict_quality from each per-voice file; the
                # additional `status` / `exit_code` fields are additive
                # and ignored by legacy consumers.
                #
                # BB #915 F-004 fix: previously suffixed with `|| true`,
                # which recreated the silent-drop pattern this fix exists
                # to prevent — a jq failure (OOM, missing binary, sidecar
                # mutation between `jq empty` and `cat`) would absorb the
                # error and leave the envelope unwritten with no log
                # signal. Now: capture jq's status, log on failure to
                # `$invoke_log` (already opened above), continue to the
                # rm + return. The aggregator will see no envelope on
                # double-failure, but the operator will see WHY in the
                # log instead of silent attrition.
                local _vq_jq_status=0
                jq -cn \
                    --argjson vq "$vq_envelope_on_failure" \
                    --arg model "$model" \
                    --arg mode "$mode" \
                    --arg phase "$phase" \
                    --argjson exit_code "$exit_code" \
                    '{
                        content: "",
                        tokens_input: 0,
                        tokens_output: 0,
                        latency_ms: 0,
                        retries: 0,
                        model: $model,
                        mode: $mode,
                        phase: $phase,
                        cost_usd: 0,
                        status: "failed",
                        exit_code: $exit_code,
                        verdict_quality: $vq
                    }' || _vq_jq_status=$?
                if [[ $_vq_jq_status -ne 0 ]]; then
                    printf '[vq-warn] failure-envelope jq exit=%d for model=%s mode=%s phase=%s — verdict_quality dropped from cohort attribution; sidecar may have been mutated between validation and emit\n' \
                        "$_vq_jq_status" "$model" "$mode" "$phase" >> "$invoke_log" 2>/dev/null || true
                fi
            fi
            rm -f "$vq_sidecar" 2>/dev/null || true
            log_invoke_failure "$exit_code" "$invoke_log" "$timeout"
            return $exit_code
        fi

        # Clean up on success
        cleanup_invoke_log "$invoke_log"

        # cycle-109 Sprint 2 T2.4 — read verdict_quality sidecar back.
        # Absent file = cheval was an older build or envelope construction
        # failed; downstream consumers handle absent verdict_quality
        # gracefully (no propagation = legacy shape).
        local vq_envelope="null"
        if [[ -s "$vq_sidecar" ]]; then
            if jq empty < "$vq_sidecar" 2>/dev/null; then
                vq_envelope=$(cat "$vq_sidecar")
            else
                log "[vq-warn] sidecar present but not valid JSON: $vq_sidecar"
            fi
        fi
        rm -f "$vq_sidecar" 2>/dev/null || true

        # Translate output to legacy format for downstream compatibility,
        # attaching the verdict_quality envelope as a new additive field.
        echo "$result" | jq \
            --arg model "$model" \
            --arg mode "$mode" \
            --arg phase "$phase" \
            --argjson vq "$vq_envelope" \
            '{
                content: .content,
                tokens_input: (.usage.input_tokens // 0),
                tokens_output: (.usage.output_tokens // 0),
                latency_ms: (.latency_ms // 0),
                retries: 0,
                model: $model,
                mode: $mode,
                phase: $phase,
                cost_usd: 0,
                verdict_quality: $vq
            }'
    }
}

# =============================================================================
# Domain Extraction
# =============================================================================

extract_domain() {
    local doc="$1"
    local phase="$2"

    # Try to extract meaningful domain keywords from the document
    local domain=""

    case "$phase" in
        prd)
            # Look for product name and key technologies
            domain=$(grep -iE "^#|product|application|system|platform|service" "$doc" 2>/dev/null | \
                head -5 | \
                tr -cs '[:alnum:]' ' ' | \
                tr '[:upper:]' '[:lower:]' | \
                tr -s ' ' | \
                cut -d' ' -f1-5)
            ;;
        sdd)
            # Look for tech stack and architecture terms
            domain=$(grep -iE "technology|stack|framework|database|api|architecture" "$doc" 2>/dev/null | \
                head -5 | \
                tr -cs '[:alnum:]' ' ' | \
                tr '[:upper:]' '[:lower:]' | \
                tr -s ' ' | \
                cut -d' ' -f1-5)
            ;;
        sprint)
            # Look for task domains
            domain=$(grep -iE "^##|task|implement|create|build|feature" "$doc" 2>/dev/null | \
                head -5 | \
                tr -cs '[:alnum:]' ' ' | \
                tr '[:upper:]' '[:lower:]' | \
                tr -s ' ' | \
                cut -d' ' -f1-5)
            ;;
        beads)
            # Look for task graph keywords from JSON
            domain=$(jq -r '[.[]? | .title // .description // empty] | join(" ")' "$doc" 2>/dev/null | \
                tr -cs '[:alnum:]' ' ' | \
                tr '[:upper:]' '[:lower:]' | \
                tr -s ' ' | \
                cut -d' ' -f1-5 || echo "task graph")
            ;;
    esac

    # Default fallback
    if [[ -z "$domain" ]]; then
        domain="software development"
    fi

    echo "$domain"
}

# =============================================================================
# NotebookLM Integration (Tier 2 Knowledge)
# =============================================================================

query_notebooklm() {
    local domain="$1"
    local phase="$2"
    local output_file="$3"

    # Check if NotebookLM is enabled
    if ! is_notebooklm_enabled; then
        log "NotebookLM: disabled (skipping)"
        return 0
    fi

    # Check if Python script exists
    if [[ ! -f "$NOTEBOOKLM_QUERY" ]]; then
        log "NotebookLM: query script not found (skipping)"
        return 0
    fi

    # Check if Python is available
    if ! command -v python3 &> /dev/null; then
        log "NotebookLM: Python3 not available (skipping)"
        return 0
    fi

    local notebook_id
    notebook_id=$(get_notebooklm_notebook_id)

    local timeout_ms
    timeout_ms=$(get_notebooklm_timeout)

    log "NotebookLM: querying for domain '$domain' phase '$phase'"

    local nlm_result
    local nlm_args=(
        --domain "$domain"
        --phase "$phase"
        --timeout "$timeout_ms"
        --json
    )

    if [[ -n "$notebook_id" ]]; then
        nlm_args+=(--notebook "$notebook_id")
    fi

    # Run NotebookLM query (with timeout protection)
    local timeout_sec=$((timeout_ms / 1000 + 5))  # Add 5s buffer
    if nlm_result=$(timeout "${timeout_sec}s" python3 "$NOTEBOOKLM_QUERY" "${nlm_args[@]}" 2>/dev/null); then
        local status
        status=$(echo "$nlm_result" | jq -r '.status // "error"')

        case "$status" in
            success)
                log "NotebookLM: query successful"
                # Extract content and append to output
                local content
                content=$(echo "$nlm_result" | jq -r '.results[0].content // ""')
                if [[ -n "$content" && "$content" != "null" ]]; then
                    echo "" >> "$output_file"
                    echo "## NotebookLM Knowledge (Tier 2)" >> "$output_file"
                    echo "" >> "$output_file"
                    echo "$content" >> "$output_file"
                    echo "" >> "$output_file"
                    echo "_Source: NotebookLM (weight: 0.8)_" >> "$output_file"

                    local latency
                    latency=$(echo "$nlm_result" | jq -r '.latency_ms // 0')
                    log "NotebookLM: retrieved in ${latency}ms"
                fi
                return 0
                ;;
            auth_expired)
                log "Warning: NotebookLM authentication expired (skipping)"
                log "  Run: python3 $NOTEBOOKLM_QUERY --setup-auth"
                return 0
                ;;
            dry_run)
                log "NotebookLM: dry run mode"
                return 0
                ;;
            timeout)
                log "Warning: NotebookLM query timed out (skipping)"
                return 0
                ;;
            *)
                local error_msg
                error_msg=$(echo "$nlm_result" | jq -r '.error // "Unknown error"')
                log "Warning: NotebookLM query failed: $error_msg (skipping)"
                return 0
                ;;
        esac
    else
        log "Warning: NotebookLM query timed out or failed (skipping)"
        return 0
    fi
}

# =============================================================================
# Budget Tracking
# =============================================================================

check_budget() {
    local additional_cost="$1"
    local budget="$2"

    local new_total=$((TOTAL_COST + additional_cost))
    if [[ $new_total -gt $budget ]]; then
        return 1
    fi
    return 0
}

add_cost() {
    local cost="$1"
    TOTAL_COST=$((TOTAL_COST + cost))
}

# =============================================================================
# State Machine
# =============================================================================

set_state() {
    local new_state="$1"
    log "State: $STATE -> $new_state"
    STATE="$new_state"
}

# =============================================================================
# Phase 1: Parallel Reviews
# =============================================================================

# =============================================================================
# Inquiry Mode (FR-4): Collaborative Multi-Model Architectural Inquiry
# =============================================================================
# Runs 3 parallel collaborative queries with distinct prompts:
#   1. Structural — isomorphisms, patterns, design parallels
#   2. Historical — precedents, evolution, prior art
#   3. Governance — constraints, policies, Ostrom-like rules
# Results are synthesized into a unified JSON output.

run_inquiry() {
    local doc="$1"
    local phase="$2"
    local context_file="$3"
    local timeout="$4"
    local budget="${5:-500}"

    set_state "PHASE1"
    log "Starting Inquiry Mode: 3 parallel collaborative queries"

    local primary_model secondary_model tertiary_model
    primary_model=$(get_model_primary)
    secondary_model=$(get_model_secondary)
    tertiary_model=$(get_model_tertiary)

    # Assign models to perspectives (rotating for diversity)
    local structural_model="$primary_model"
    local historical_model="$secondary_model"
    local governance_model="${tertiary_model:-$primary_model}"

    # Read document content
    local doc_content
    doc_content=$(cat "$doc" 2>/dev/null | head -2000) || doc_content=""

    # Read context if available
    local extra_context=""
    if [[ -n "$context_file" && -f "$context_file" && -s "$context_file" ]]; then
        extra_context=$(cat "$context_file" 2>/dev/null | head -500) || extra_context=""
    fi

    # Apply context isolation wrappers (vision-003: de-authorization for untrusted content)
    doc_content=$(isolate_content "$doc_content" "DOCUMENT UNDER REVIEW")
    if [[ -n "$extra_context" ]]; then
        extra_context=$(isolate_content "$extra_context" "ADDITIONAL CONTEXT")
    fi

    # Build inquiry prompts
    local structural_prompt="You are conducting a structural architectural inquiry.

Analyze the following document for structural patterns, isomorphisms, and design parallels.
Look for:
- Recurring structural patterns across components
- Isomorphisms between seemingly different subsystems
- Design patterns that could be generalized or extracted
- Architectural symmetries and asymmetries

Document (${phase}):
${doc_content}

${extra_context:+Additional context:
${extra_context}
}
Output your findings as JSON with this schema:
{\"perspective\": \"structural\", \"findings\": [{\"pattern\": \"...\", \"description\": \"...\", \"confidence\": 0.0-1.0, \"connections\": [\"...\"]}]}"

    local historical_prompt="You are conducting a historical architectural inquiry.

Analyze the following document for historical precedents, evolutionary patterns, and prior art.
Look for:
- Historical software engineering precedents for the patterns used
- How the architecture has evolved or could evolve
- FAANG-scale parallels from industry practice
- Anti-patterns that history has shown to fail

Document (${phase}):
${doc_content}

${extra_context:+Additional context:
${extra_context}
}
Output your findings as JSON with this schema:
{\"perspective\": \"historical\", \"findings\": [{\"pattern\": \"...\", \"precedent\": \"...\", \"confidence\": 0.0-1.0, \"lesson\": \"...\"}]}"

    local governance_prompt="You are conducting a governance architectural inquiry.

Analyze the following document for governance structures, constraint patterns, and policy design.
Look for:
- Ostrom-like governance principles in the architecture
- Constraint enforcement mechanisms and their completeness
- Trust boundaries and their implications
- Policy patterns that could be formalized or improved

Document (${phase}):
${doc_content}

${extra_context:+Additional context:
${extra_context}
}
Output your findings as JSON with this schema:
{\"perspective\": \"governance\", \"findings\": [{\"pattern\": \"...\", \"description\": \"...\", \"confidence\": 0.0-1.0, \"principle\": \"...\"}]}"

    # Write prompts to temp files for model invocation
    local structural_input="$TEMP_DIR/inquiry-structural.txt"
    local historical_input="$TEMP_DIR/inquiry-historical.txt"
    local governance_input="$TEMP_DIR/inquiry-governance.txt"
    echo "$structural_prompt" > "$structural_input"
    echo "$historical_prompt" > "$historical_input"
    echo "$governance_prompt" > "$governance_input"

    # Output files
    local structural_output="$TEMP_DIR/inquiry-structural-result.json"
    local historical_output="$TEMP_DIR/inquiry-historical-result.json"
    local governance_output="$TEMP_DIR/inquiry-governance-result.json"

    # Launch 3 parallel queries
    local pids=() labels=()

    call_model "$structural_model" "review" "$structural_input" "$phase" "$context_file" "$timeout" > "$structural_output" 2>/dev/null &
    pids+=($!); labels+=("structural($structural_model)")

    call_model "$historical_model" "review" "$historical_input" "$phase" "$context_file" "$timeout" > "$historical_output" 2>/dev/null &
    pids+=($!); labels+=("historical($historical_model)")

    call_model "$governance_model" "review" "$governance_input" "$phase" "$context_file" "$timeout" > "$governance_output" 2>/dev/null &
    pids+=($!); labels+=("governance($governance_model)")

    # Wait for all queries
    local failures=0
    for i in "${!pids[@]}"; do
        if ! wait "${pids[$i]}" 2>/dev/null; then
            log "WARNING: Inquiry query failed: ${labels[$i]}"
            failures=$((failures + 1))
        else
            log "Inquiry query complete: ${labels[$i]}"
        fi
    done

    # Require at least 2 successful queries
    local success_count=$(( ${#pids[@]} - failures ))
    if [[ $success_count -lt 2 ]]; then
        log "ERROR: Only $success_count of 3 inquiry queries succeeded (minimum 2 required)"
        jq -n '{error: "insufficient_queries", success_count: '"$success_count"', required: 2}'
        return 1
    fi

    # Aggregate costs
    for f in "$structural_output" "$historical_output" "$governance_output"; do
        if [[ -f "$f" && -s "$f" ]]; then
            local cost
            cost=$(jq '.cost_usd // 0' "$f" 2>/dev/null) || cost=0
            TOTAL_COST=$(echo "$TOTAL_COST + ($cost * 100)" | bc 2>/dev/null || echo "$TOTAL_COST")
        fi
    done

    set_state "CONSENSUS"

    # Synthesize results
    local structural_content="" historical_content="" governance_content=""
    if [[ -f "$structural_output" && -s "$structural_output" ]]; then
        structural_content=$(jq -r '.content // ""' "$structural_output" 2>/dev/null) || structural_content=""
    fi
    if [[ -f "$historical_output" && -s "$historical_output" ]]; then
        historical_content=$(jq -r '.content // ""' "$historical_output" 2>/dev/null) || historical_content=""
    fi
    if [[ -f "$governance_output" && -s "$governance_output" ]]; then
        governance_content=$(jq -r '.content // ""' "$governance_output" 2>/dev/null) || governance_content=""
    fi

    # Try to parse JSON from each response content
    local structural_json historical_json governance_json
    structural_json=$(echo "$structural_content" | jq '.' 2>/dev/null) || structural_json='{"perspective":"structural","findings":[],"raw":true}'
    historical_json=$(echo "$historical_content" | jq '.' 2>/dev/null) || historical_json='{"perspective":"historical","findings":[],"raw":true}'
    governance_json=$(echo "$governance_content" | jq '.' 2>/dev/null) || governance_json='{"perspective":"governance","findings":[],"raw":true}'

    # Build unified synthesis
    jq -n \
        --argjson structural "$structural_json" \
        --argjson historical "$historical_json" \
        --argjson governance "$governance_json" \
        --argjson queries_launched "${#pids[@]}" \
        --argjson queries_succeeded "$success_count" \
        --arg structural_model "$structural_model" \
        --arg historical_model "$historical_model" \
        --arg governance_model "$governance_model" \
        '{
            mode: "inquiry",
            perspectives: {
                structural: $structural,
                historical: $historical,
                governance: $governance
            },
            models: {
                structural: $structural_model,
                historical: $historical_model,
                governance: $governance_model
            },
            summary: {
                queries_launched: $queries_launched,
                queries_succeeded: $queries_succeeded,
                structural_findings: (($structural.findings // []) | length),
                historical_findings: (($historical.findings // []) | length),
                governance_findings: (($governance.findings // []) | length),
                total_findings: ((($structural.findings // []) | length) + (($historical.findings // []) | length) + (($governance.findings // []) | length))
            }
        }'
}

run_phase1() {
    local doc="$1"
    local phase="$2"
    local context_file="$3"
    local timeout="$4"
    local budget="$5"

    set_state "PHASE1"
    log "Starting Phase 1: Independent reviews (4 parallel calls)"

    local primary_model secondary_model
    primary_model=$(get_model_primary)
    secondary_model=$(get_model_secondary)

    # Validate model names before making any API calls
    if ! validate_model "$primary_model" "primary"; then
        return 3
    fi
    if ! validate_model "$secondary_model" "secondary"; then
        return 3
    fi

    # FR-3: Optional tertiary model for 3-model Flatline
    local tertiary_model
    tertiary_model=$(get_model_tertiary)
    local has_tertiary=false
    if [[ -n "$tertiary_model" ]]; then
        if ! validate_model "$tertiary_model" "tertiary"; then
            log "Warning: tertiary model '$tertiary_model' invalid, continuing with 2-model mode"
            tertiary_model=""
        else
            has_tertiary=true
            log "Tertiary model confirmed: $tertiary_model (3-model Flatline active)"
        fi
    fi

    local total_calls=4
    [[ "$has_tertiary" == "true" ]] && total_calls=6

    # Create output files
    local gpt_review_file="$TEMP_DIR/gpt-review.json"
    local opus_review_file="$TEMP_DIR/opus-review.json"
    local gpt_skeptic_file="$TEMP_DIR/gpt-skeptic.json"
    local opus_skeptic_file="$TEMP_DIR/opus-skeptic.json"
    local tertiary_review_file="$TEMP_DIR/tertiary-review.json"
    local tertiary_skeptic_file="$TEMP_DIR/tertiary-skeptic.json"

    # Stderr capture files for diagnosis on failure
    local gpt_review_stderr="$TEMP_DIR/gpt-review-stderr.log"
    local opus_review_stderr="$TEMP_DIR/opus-review-stderr.log"
    local gpt_skeptic_stderr="$TEMP_DIR/gpt-skeptic-stderr.log"
    local opus_skeptic_stderr="$TEMP_DIR/opus-skeptic-stderr.log"
    local tertiary_review_stderr="$TEMP_DIR/tertiary-review-stderr.log"
    local tertiary_skeptic_stderr="$TEMP_DIR/tertiary-skeptic-stderr.log"

    # Run parallel API calls with stagger to avoid same-provider rate-limit contention.
    # Review calls launch first, then skeptic calls after a 2s delay.
    local pids=()
    local pid_labels=()

    # Wave 1: Review calls (all models concurrently)
    {
        call_model "$secondary_model" review "$doc" "$phase" "$context_file" "$timeout" \
            > "$gpt_review_file" 2>"$gpt_review_stderr"
    } &
    pids+=($!)
    pid_labels+=("gpt-review")

    {
        call_model "$primary_model" review "$doc" "$phase" "$context_file" "$timeout" \
            > "$opus_review_file" 2>"$opus_review_stderr"
    } &
    pids+=($!)
    pid_labels+=("opus-review")

    if [[ "$has_tertiary" == "true" ]]; then
        {
            call_model "$tertiary_model" review "$doc" "$phase" "$context_file" "$timeout" \
                > "$tertiary_review_file" 2>"$tertiary_review_stderr"
        } &
        pids+=($!)
        pid_labels+=("tertiary-review")
    fi

    # Stagger: 2s delay before skeptic calls to avoid rate-limit contention
    sleep 2

    # Wave 2: Skeptic calls (all models concurrently)
    {
        call_model "$secondary_model" skeptic "$doc" "$phase" "$context_file" "$timeout" \
            > "$gpt_skeptic_file" 2>"$gpt_skeptic_stderr"
    } &
    pids+=($!)
    pid_labels+=("gpt-skeptic")

    {
        call_model "$primary_model" skeptic "$doc" "$phase" "$context_file" "$timeout" \
            > "$opus_skeptic_file" 2>"$opus_skeptic_stderr"
    } &
    pids+=($!)
    pid_labels+=("opus-skeptic")

    if [[ "$has_tertiary" == "true" ]]; then
        {
            call_model "$tertiary_model" skeptic "$doc" "$phase" "$context_file" "$timeout" \
                > "$tertiary_skeptic_file" 2>"$tertiary_skeptic_stderr"
        } &
        pids+=($!)
        pid_labels+=("tertiary-skeptic")
    fi

    # Wait for all processes and track failures + voice-drops separately.
    # Voice-drops (cheval exit 12 = CHAIN_EXHAUSTED) are the per-voice
    # graceful-fall-through per SDD §6.5; they ARE NOT treated as failures
    # because the within-company chain already walked to end and there is
    # no cross-company substitute to try (FR-S2.5).
    local failed=0
    local failed_labels=()
    local dropped_labels=()
    for i in "${!pids[@]}"; do
        local _wait_exit=0
        wait "${pids[$i]}" || _wait_exit=$?
        local _classification
        _classification=$(classify_voice_exit_status "$_wait_exit")
        case "$_classification" in
            success) ;;
            dropped)
                dropped_labels+=("${pid_labels[$i]}")
                emit_voice_dropped "${pid_labels[$i]}" "$phase"
                ;;
            *)
                failed=$((failed + 1))
                failed_labels+=("${pid_labels[$i]}")
                ;;
        esac
    done
    local dropped_count=${#dropped_labels[@]}

    # All voices unavailable (failures + chain-exhaustions) → hard error.
    if [[ $((failed + dropped_count)) -eq $total_calls ]]; then
        if [[ $failed -gt 0 && $dropped_count -gt 0 ]]; then
            error "All Phase 1 model voices unavailable ($failed failed, $dropped_count chain-exhausted)"
        elif [[ $dropped_count -eq $total_calls ]]; then
            error "All Phase 1 model voices chain-exhausted (no within-company fallback succeeded)"
        else
            error "All Phase 1 model calls failed"
        fi
        # Log stderr from all failed calls for diagnosis
        for label in "${failed_labels[@]}"; do
            local stderr_file="$TEMP_DIR/${label}-stderr.log"
            if [[ -s "$stderr_file" ]]; then
                log "  $label stderr: $(head -5 "$stderr_file")"
            fi
        done
        return 3
    fi

    if [[ $dropped_count -gt 0 ]]; then
        log "Voice-drop: $dropped_count of $total_calls Phase 1 voices dropped from consensus (chain exhausted): ${dropped_labels[*]}"
    fi

    if [[ $failed -gt 0 ]]; then
        log "Warning: $failed of $total_calls Phase 1 calls failed (degraded mode)"
        # Issue #774: count failed calls whose stderr carries the typed
        # `failure_class=PROVIDER_DISCONNECT` JSON marker emitted by cheval.py.
        # When ≥1 such call appears, surface a single tip line that points
        # operators at the right diagnosis (NOT --per-call-max-tokens 4096,
        # which is a no-op against the disconnect failure mode).
        local disconnect_count=0
        for label in "${failed_labels[@]}"; do
            local stderr_file="$TEMP_DIR/${label}-stderr.log"
            if [[ -s "$stderr_file" ]]; then
                # Match the JSON-error shape literally: '"failure_class":"PROVIDER_DISCONNECT"'
                # (with arbitrary whitespace inside the JSON object).
                if grep -q '"failure_class"[[:space:]]*:[[:space:]]*"PROVIDER_DISCONNECT"' "$stderr_file" 2>/dev/null; then
                    disconnect_count=$((disconnect_count + 1))
                fi
                log "  $label stderr: $(head -5 "$stderr_file")"
            fi
        done
        if [[ $disconnect_count -gt 0 ]]; then
            log "tip: $disconnect_count of $failed failed calls had failure_class=PROVIDER_DISCONNECT — see issue #774. The --per-call-max-tokens flag does NOT address this failure mode (cheval default already=4096)."
        fi
    fi

    # Aggregate costs
    local cost_files=("$gpt_review_file" "$opus_review_file" "$gpt_skeptic_file" "$opus_skeptic_file")
    [[ "$has_tertiary" == "true" ]] && cost_files+=("$tertiary_review_file" "$tertiary_skeptic_file")
    for file in "${cost_files[@]}"; do
        if [[ -f "$file" ]]; then
            local cost
            cost=$(jq -r '.cost_usd // 0' "$file" 2>/dev/null | awk '{printf "%.0f", $1 * 100}')
            add_cost "${cost:-0}"
        fi
    done

    log "Phase 1 complete ($total_calls calls). Total cost so far: $TOTAL_COST cents"

    # Output file paths for next phase
    echo "$gpt_review_file"
    echo "$opus_review_file"
    echo "$gpt_skeptic_file"
    echo "$opus_skeptic_file"
    # FR-3: Output tertiary file paths only when configured (avoids empty paths)
    if [[ "$has_tertiary" == "true" ]]; then
        echo "$tertiary_review_file"
        echo "$tertiary_skeptic_file"
    fi
}

# =============================================================================
# Phase 2: Cross-Scoring
# =============================================================================

run_phase2() {
    local gpt_review_file="$1"
    local opus_review_file="$2"
    local phase="$3"
    local timeout="$4"
    local tertiary_review_file="${5:-}"

    set_state "PHASE2"

    local primary_model secondary_model tertiary_model
    primary_model=$(get_model_primary)
    secondary_model=$(get_model_secondary)
    tertiary_model=$(get_model_tertiary)

    local has_tertiary=false
    [[ -n "$tertiary_model" && -n "$tertiary_review_file" && -s "$tertiary_review_file" ]] && has_tertiary=true

    local total_calls=2
    [[ "$has_tertiary" == "true" ]] && total_calls=6

    log "Starting Phase 2: Cross-scoring ($total_calls parallel calls)"

    # Extract items to score
    local gpt_items_file="$TEMP_DIR/gpt-items.json"
    local opus_items_file="$TEMP_DIR/opus-items.json"
    local tertiary_items_file="$TEMP_DIR/tertiary-items.json"

    # Extract improvements from each review (handles markdown-wrapped JSON)
    extract_json_content "$gpt_review_file" '{"improvements":[]}' > "$gpt_items_file"
    extract_json_content "$opus_review_file" '{"improvements":[]}' > "$opus_items_file"
    if [[ "$has_tertiary" == "true" ]]; then
        extract_json_content "$tertiary_review_file" '{"improvements":[]}' > "$tertiary_items_file"
    fi

    # Create output files
    local gpt_scores_file="$TEMP_DIR/gpt-scores.json"
    local opus_scores_file="$TEMP_DIR/opus-scores.json"
    local tertiary_scores_opus_file="$TEMP_DIR/tertiary-scores-opus.json"
    local tertiary_scores_gpt_file="$TEMP_DIR/tertiary-scores-gpt.json"
    local gpt_scores_tertiary_file="$TEMP_DIR/gpt-scores-tertiary.json"
    local opus_scores_tertiary_file="$TEMP_DIR/opus-scores-tertiary.json"

    local pids=()

    # GPT scores Opus items
    {
        call_model "$secondary_model" score "$opus_items_file" "$phase" "" "$timeout" \
            > "$gpt_scores_file" 2>/dev/null
    } &
    pids+=($!)

    # Opus scores GPT items
    {
        call_model "$primary_model" score "$gpt_items_file" "$phase" "" "$timeout" \
            > "$opus_scores_file" 2>/dev/null
    } &
    pids+=($!)

    # FR-3: 3-way triangular cross-scoring when tertiary configured
    if [[ "$has_tertiary" == "true" ]]; then
        # Tertiary scores Opus items
        {
            call_model "$tertiary_model" score "$opus_items_file" "$phase" "" "$timeout" \
                > "$tertiary_scores_opus_file" 2>/dev/null
        } &
        pids+=($!)

        # Tertiary scores GPT items
        {
            call_model "$tertiary_model" score "$gpt_items_file" "$phase" "" "$timeout" \
                > "$tertiary_scores_gpt_file" 2>/dev/null
        } &
        pids+=($!)

        # GPT scores Tertiary items
        {
            call_model "$secondary_model" score "$tertiary_items_file" "$phase" "" "$timeout" \
                > "$gpt_scores_tertiary_file" 2>/dev/null
        } &
        pids+=($!)

        # Opus scores Tertiary items
        {
            call_model "$primary_model" score "$tertiary_items_file" "$phase" "" "$timeout" \
                > "$opus_scores_tertiary_file" 2>/dev/null
        } &
        pids+=($!)
    fi

    # Wait for all processes. Voice-drop classifier distinguishes the
    # chain-exhausted case (cheval exit 12) per SDD §6.5; in Phase 2
    # cross-scoring a dropped voice means that voice's chain ran out
    # while scoring the other voice's items — we surface it but proceed
    # with partial consensus (mirrors the pre-cycle-104 partial-tolerance
    # behaviour for Phase 2).
    local failed=0
    local dropped_p2=0
    for pid in "${pids[@]}"; do
        local _wait_exit=0
        wait "$pid" || _wait_exit=$?
        local _classification
        _classification=$(classify_voice_exit_status "$_wait_exit")
        case "$_classification" in
            success) ;;
            dropped) dropped_p2=$((dropped_p2 + 1)) ;;
            *) failed=$((failed + 1)) ;;
        esac
    done

    if [[ $((failed + dropped_p2)) -eq $total_calls ]]; then
        log "Warning: All Phase 2 calls unavailable ($failed failed, $dropped_p2 chain-exhausted) - using partial consensus"
    elif [[ $dropped_p2 -gt 0 ]]; then
        log "Voice-drop: $dropped_p2 of $total_calls Phase 2 cross-scoring calls chain-exhausted; partial scores aggregated"
    fi

    # Aggregate costs
    local cost_files=("$gpt_scores_file" "$opus_scores_file")
    if [[ "$has_tertiary" == "true" ]]; then
        cost_files+=("$tertiary_scores_opus_file" "$tertiary_scores_gpt_file"
                     "$gpt_scores_tertiary_file" "$opus_scores_tertiary_file")
    fi
    for file in "${cost_files[@]}"; do
        if [[ -f "$file" ]]; then
            local cost
            cost=$(jq -r '.cost_usd // 0' "$file" 2>/dev/null | awk '{printf "%.0f", $1 * 100}')
            add_cost "${cost:-0}"
        fi
    done

    log "Phase 2 complete ($total_calls calls). Total cost: $TOTAL_COST cents"

    echo "$gpt_scores_file"
    echo "$opus_scores_file"
    # FR-3: Output tertiary scoring files when configured (consumed by consensus)
    if [[ "$has_tertiary" == "true" ]]; then
        echo "$tertiary_scores_opus_file"
        echo "$tertiary_scores_gpt_file"
        echo "$gpt_scores_tertiary_file"
        echo "$opus_scores_tertiary_file"
    fi
}

# =============================================================================
# Phase 3: Consensus Calculation
# =============================================================================

run_consensus() {
    local gpt_scores_file="$1"
    local opus_scores_file="$2"
    local gpt_skeptic_file="$3"
    local opus_skeptic_file="$4"
    # FR-3: Optional tertiary scoring files for 3-model consensus
    local tertiary_scores_opus="${5:-}"
    local tertiary_scores_gpt="${6:-}"
    local gpt_scores_tertiary="${7:-}"
    local opus_scores_tertiary="${8:-}"
    local tertiary_skeptic_file="${9:-}"

    set_state "CONSENSUS"
    log "Calculating consensus"

    # Prepare scores files for scoring engine (handles markdown-wrapped JSON)
    local gpt_scores_prepared="$TEMP_DIR/gpt-scores-prepared.json"
    local opus_scores_prepared="$TEMP_DIR/opus-scores-prepared.json"

    # Extract and format scores using extract_json_content (handles markdown wrapping)
    extract_json_content "$gpt_scores_file" '{"scores":[]}' > "$gpt_scores_prepared"
    extract_json_content "$opus_scores_file" '{"scores":[]}' > "$opus_scores_prepared"

    # Prepare skeptic files (handles markdown-wrapped JSON)
    local gpt_skeptic_prepared="$TEMP_DIR/gpt-skeptic-prepared.json"
    local opus_skeptic_prepared="$TEMP_DIR/opus-skeptic-prepared.json"

    extract_json_content "$gpt_skeptic_file" '{"concerns":[]}' > "$gpt_skeptic_prepared"
    extract_json_content "$opus_skeptic_file" '{"concerns":[]}' > "$opus_skeptic_prepared"

    # FR-3: Prepare tertiary scoring and skeptic files when available
    local tertiary_args=()
    if [[ -n "$tertiary_scores_opus" && -s "$tertiary_scores_opus" ]]; then
        local tertiary_scores_opus_prepared="$TEMP_DIR/tertiary-scores-opus-prepared.json"
        local tertiary_scores_gpt_prepared="$TEMP_DIR/tertiary-scores-gpt-prepared.json"
        local gpt_scores_tertiary_prepared="$TEMP_DIR/gpt-scores-tertiary-prepared.json"
        local opus_scores_tertiary_prepared="$TEMP_DIR/opus-scores-tertiary-prepared.json"

        extract_json_content "$tertiary_scores_opus" '{"scores":[]}' > "$tertiary_scores_opus_prepared"
        extract_json_content "$tertiary_scores_gpt" '{"scores":[]}' > "$tertiary_scores_gpt_prepared"
        extract_json_content "$gpt_scores_tertiary" '{"scores":[]}' > "$gpt_scores_tertiary_prepared"
        extract_json_content "$opus_scores_tertiary" '{"scores":[]}' > "$opus_scores_tertiary_prepared"

        tertiary_args=(
            --tertiary-scores-opus "$tertiary_scores_opus_prepared"
            --tertiary-scores-gpt "$tertiary_scores_gpt_prepared"
            --gpt-scores-tertiary "$gpt_scores_tertiary_prepared"
            --opus-scores-tertiary "$opus_scores_tertiary_prepared"
        )
        log "Including tertiary model scores in consensus (3-model mode)"
    fi

    # FR-3: Prepare tertiary skeptic file when available
    local tertiary_skeptic_args=()
    if [[ -n "$tertiary_skeptic_file" && -s "$tertiary_skeptic_file" ]]; then
        local tertiary_skeptic_prepared="$TEMP_DIR/tertiary-skeptic-prepared.json"
        extract_json_content "$tertiary_skeptic_file" '{"concerns":[]}' > "$tertiary_skeptic_prepared"
        tertiary_skeptic_args=(--skeptic-tertiary "$tertiary_skeptic_prepared")
        log "Including tertiary model skeptic concerns in consensus"
    fi

    # Run scoring engine
    "$SCORING_ENGINE" \
        --gpt-scores "$gpt_scores_prepared" \
        --opus-scores "$opus_scores_prepared" \
        --include-blockers \
        --skeptic-gpt "$gpt_skeptic_prepared" \
        --skeptic-opus "$opus_skeptic_prepared" \
        "${tertiary_args[@]}" \
        "${tertiary_skeptic_args[@]}" \
        --json
}

# =============================================================================
# Main
# =============================================================================

usage() {
    cat <<EOF
Usage: flatline-orchestrator.sh --doc <path> --phase <type> [options]

Required:
  --doc <path>           Document to review
  --phase <type>         Phase type: prd, sdd, sprint, beads, spec, pr

Options:
  --mode <type>          Mode: review (default), red-team, inquiry
  --domain <text>        Domain for knowledge retrieval (auto-extracted if not provided)
  --dry-run              Validate without executing reviews
  --skip-knowledge       Skip knowledge retrieval
  --skip-consensus       Return raw reviews without consensus
  --timeout <seconds>    Overall timeout (default: 300)
  --budget <cents>       Cost budget in cents (default: 300 = \$3.00)
  --per-call-max-tokens <N>
                         Override max_tokens passed to each model invocation.
                         Preserved for backward compat with issue #675.
                         NOTE: does NOT address failure_class=PROVIDER_DISCONNECT
                         (issue #774) — both the Anthropic AND OpenAI cheval
                         paths fail on long-prompt requests with the typed
                         transport error; the gemini path is unaffected.
                         cheval.py default is already 4096, so passing 4096
                         is a no-op against the disconnect failure mode.
                         When unset, downstream defaults apply
                         (cheval.py: 4096; model-adapter.sh: 4096).
  --json                 Output as JSON
  -h, --help             Show this help

Red Team Options (--mode red-team):
  --focus <categories>   Comma-separated attack surface categories
  --surface <name>       Target specific surface from registry
  --depth <N>            Attack-counter_design iterations (default: 1)
  --execution-mode <m>   Cost tier: quick, standard (default), deep

State Machine:
  INIT -> KNOWLEDGE -> PHASE1 -> PHASE2 -> CONSENSUS -> DONE

Exit codes:
  0 - Success
  1 - Configuration error
  2 - Knowledge retrieval failed (non-fatal if local)
  3 - All model calls failed
  4 - Timeout exceeded
  5 - Budget exceeded
  6 - Partial success (degraded mode)

Example:
  flatline-orchestrator.sh --doc grimoires/loa/prd.md --phase prd --json
  flatline-orchestrator.sh --doc grimoires/loa/sdd.md --phase sdd --mode red-team --json
EOF
}

cleanup() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}

main() {
    local doc=""
    local phase=""
    local domain=""
    local dry_run=false
    local skip_knowledge=false
    local skip_consensus=false
    local timeout="$DEFAULT_TIMEOUT"
    local budget="$DEFAULT_BUDGET"
    local json_output=false
    local mode_flag=""
    local run_id=""
    local orchestrator_mode="review"
    local rt_focus=""
    local rt_surface=""
    local rt_depth=1
    local rt_execution_mode="standard"
    local detect_silent_noop=true

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --doc)
                doc="$2"
                shift 2
                ;;
            --phase)
                phase="$2"
                shift 2
                ;;
            --domain)
                domain="$2"
                shift 2
                ;;
            --mode)
                orchestrator_mode="$2"
                shift 2
                ;;
            --focus)
                rt_focus="$2"
                shift 2
                ;;
            --surface)
                rt_surface="$2"
                shift 2
                ;;
            --depth)
                rt_depth="$2"
                shift 2
                ;;
            --execution-mode)
                rt_execution_mode="$2"
                shift 2
                ;;
            --interactive)
                mode_flag="--interactive"
                shift
                ;;
            --autonomous)
                mode_flag="--autonomous"
                shift
                ;;
            --run-id)
                run_id="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --skip-knowledge)
                skip_knowledge=true
                shift
                ;;
            --skip-consensus)
                skip_consensus=true
                shift
                ;;
            --timeout)
                timeout="$2"
                shift 2
                ;;
            --budget)
                budget="$2"
                shift 2
                ;;
            --per-call-max-tokens)
                # Issue #675 (sub-issue 4): operator override for downstream
                # max_tokens. Preserved for back-compat. NOTE (#774): does NOT
                # address `failure_class=PROVIDER_DISCONNECT` — cheval default
                # is already 4096, so passing 4096 is a no-op against the
                # disconnect failure mode (Anthropic + OpenAI cheval paths).
                PER_CALL_MAX_TOKENS="$2"
                shift 2
                ;;
            --json)
                json_output=true
                shift
                ;;
            --no-silent-noop-detect)
                # cycle-062 (#485): opt out of the post-run no-findings check
                # (for tests/CI). Extends cycle-058's pattern to flatline.
                detect_silent_noop=false
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    # Set up cleanup trap
    trap cleanup EXIT

    # Validate required arguments
    if [[ -z "$doc" ]]; then
        error "Document required (--doc)"
        exit 1
    fi

    if [[ ! -f "$doc" ]]; then
        error "Document not found: $doc"
        exit 1
    fi

    # Security: Validate document path is within project directory (prevent path traversal)
    local realpath_doc
    realpath_doc=$(realpath "$doc" 2>/dev/null) || {
        error "Cannot resolve document path: $doc"
        exit 1
    }
    if [[ ! "$realpath_doc" == "$PROJECT_ROOT"* ]]; then
        error "Document must be within project directory: $doc"
        error "Resolved to: $realpath_doc (outside $PROJECT_ROOT)"
        exit 1
    fi

    if [[ -z "$phase" ]]; then
        error "Phase required (--phase)"
        exit 1
    fi

    if [[ "$phase" != "prd" && "$phase" != "sdd" && "$phase" != "sprint" && "$phase" != "beads" && "$phase" != "spec" && "$phase" != "pr" ]]; then
        error "Invalid phase: $phase (expected: prd, sdd, sprint, beads, spec, pr)"
        exit 1
    fi

    # Issue #774: warn when prompt size is in the cheval connection-loss
    # danger zone. Empirical break point in the issue reporter's run was
    # ~38KB on Anthropic + OpenAI (Gemini unaffected — control case). The
    # threshold here (30KB) gives an 8KB safety margin under the observed
    # break point. The disconnect manifests as `failure_class=PROVIDER_DISCONNECT`
    # in cheval JSON-error stderr; the workaround is upstream (streaming or
    # HTTP/1.1 forcing) and is deferred per /bug scope to /plan.
    local doc_bytes doc_kb
    doc_bytes=$(wc -c < "$doc" 2>/dev/null || echo 0)
    doc_kb=$(( (doc_bytes + 512) / 1024 ))   # round to nearest KB
    if [[ "$doc_bytes" -gt 30720 ]]; then
        echo "WARNING: Document size ${doc_kb} KB; long prompts may trip the cheval connection-loss path on Anthropic + OpenAI. See issue #774 if Phase 1 reports failure_class=PROVIDER_DISCONNECT. The --per-call-max-tokens flag does NOT address this failure mode." >&2
    fi

    # Validate orchestrator mode
    if [[ "$orchestrator_mode" != "review" && "$orchestrator_mode" != "red-team" && "$orchestrator_mode" != "inquiry" ]]; then
        error "Invalid mode: $orchestrator_mode (expected: review, red-team, inquiry)"
        exit 1
    fi

    # Validate red-team execution mode
    if [[ "$orchestrator_mode" == "red-team" ]]; then
        if [[ "$rt_execution_mode" != "quick" && "$rt_execution_mode" != "standard" && "$rt_execution_mode" != "deep" ]]; then
            error "Invalid execution mode: $rt_execution_mode (expected: quick, standard, deep)"
            exit 1
        fi
        # Apply token budget per execution mode (separate from cost budget used in review mode)
        local rt_token_budget
        case "$rt_execution_mode" in
            quick)    rt_token_budget=$(yq '.red_team.budgets.quick_max_tokens // 50000' "$CONFIG_FILE" 2>/dev/null || echo 50000) ;;
            standard) rt_token_budget=$(yq '.red_team.budgets.standard_max_tokens // 200000' "$CONFIG_FILE" 2>/dev/null || echo 200000) ;;
            deep)     rt_token_budget=$(yq '.red_team.budgets.deep_max_tokens // 500000' "$CONFIG_FILE" 2>/dev/null || echo 500000) ;;
        esac
        log "Red team mode: execution=$rt_execution_mode, depth=$rt_depth, token_budget=$rt_token_budget"
    fi

    # Check if Flatline is enabled (skip check in dry-run mode)
    if [[ "$dry_run" != "true" ]] && ! is_flatline_enabled; then
        log "Flatline Protocol is disabled in config"
        jq -n \
            --arg status "disabled" \
            --arg doc "$doc" \
            --arg phase "$phase" \
            '{status: $status, document: $doc, phase: $phase, reason: "flatline_protocol.enabled is false in .loa.config.yaml"}'
        exit 0
    fi

    # Create temp directory
    TEMP_DIR=$(mktemp -d)
    START_TIME=$(date +%s)

    # Detect execution mode (interactive vs autonomous)
    local mode_detect_script="$SCRIPT_DIR/flatline-mode-detect.sh"
    local execution_mode="interactive"
    local mode_reason="default"

    if [[ -x "$mode_detect_script" ]]; then
        local mode_result
        if mode_result=$("$mode_detect_script" $mode_flag --json 2>/dev/null); then
            execution_mode=$(echo "$mode_result" | jq -r '.mode // "interactive"')
            mode_reason=$(echo "$mode_result" | jq -r '.reason // "unknown"')
            log "Execution mode: $execution_mode (reason: $mode_reason)"
        else
            log "Warning: Mode detection failed, defaulting to interactive"
        fi
    else
        log "Warning: Mode detection script not found, defaulting to interactive"
    fi

    # FR-1 (cycle-045): Log tertiary model status for observability
    local tertiary_model_check
    tertiary_model_check=$(get_model_tertiary)
    if [[ -n "$tertiary_model_check" ]]; then
        log "Tertiary model: $tertiary_model_check (active)"
    else
        log "Tertiary model: none (disabled)"
    fi

    log "Document: $doc"
    log "Phase: $phase"
    log "Mode: $execution_mode"
    log "Timeout: ${timeout}s"
    log "Budget: ${budget} cents"

    # Dry run - validate only
    if [[ "$dry_run" == "true" ]]; then
        log "Dry run - validation passed"
        jq -n \
            --arg status "dry_run" \
            --arg doc "$doc" \
            --arg phase "$phase" \
            --arg mode "$execution_mode" \
            --arg mode_reason "$mode_reason" \
            '{status: $status, document: $doc, phase: $phase, mode: $mode, mode_reason: $mode_reason}'
        exit 0
    fi

    # Extract domain if not provided
    if [[ -z "$domain" ]]; then
        domain=$(extract_domain "$doc" "$phase")
        log "Extracted domain: $domain"
    fi

    # Phase -0.5: Knowledge Retrieval (Two-Tier)
    local context_file="$TEMP_DIR/knowledge-context.md"
    if [[ "$skip_knowledge" != "true" ]]; then
        set_state "KNOWLEDGE"
        log "Retrieving knowledge context (two-tier)"

        # Tier 1: Local knowledge (framework + project learnings)
        log "Tier 1: Local knowledge retrieval"
        if "$KNOWLEDGE_LOCAL" --domain "$domain" --phase "$phase" --format markdown > "$context_file" 2>/dev/null; then
            log "Tier 1: Local knowledge retrieval complete"
        else
            log "Warning: Tier 1 knowledge retrieval failed (continuing)"
            echo "" > "$context_file"
        fi

        # Tier 2: NotebookLM (optional, appends to context)
        log "Tier 2: NotebookLM knowledge retrieval"
        query_notebooklm "$domain" "$phase" "$context_file"

        log "Knowledge retrieval complete (two-tier)"
    else
        echo "" > "$context_file"
    fi

    # Mode dispatch: red-team mode uses separate pipeline
    if [[ "$orchestrator_mode" == "red-team" ]]; then
        local rt_pipeline="$SCRIPT_DIR/red-team-pipeline.sh"
        if [[ ! -x "$rt_pipeline" ]]; then
            error "Red team pipeline not found: $rt_pipeline"
            exit 1
        fi

        local rt_run_id
        rt_run_id="rt-$(date +%s)-$(head -c 4 /dev/urandom | od -An -tx1 | tr -d ' \n')"

        # cycle-102 Sprint 1 T1.8 (AC-1.4): pipeline stderr de-suppression.
        # Previously `2>/dev/null` swallowed red-team-pipeline.sh's stderr,
        # masking cheval / model-adapter / probe-gate diagnostics during
        # silent-degradation events. Per vision-019 thesis, these
        # diagnostics MUST surface — typed errors are structured (cheval
        # _error_json wraps them in `{"error": true, ...}`) so consumers
        # can grep / filter; only unstructured stderr noise actually
        # surfaces, which IS the operator-visible signal we want.
        local rt_result
        rt_result=$("$rt_pipeline" \
            --doc "$doc" \
            --phase "$phase" \
            --context-file "$context_file" \
            --execution-mode "$rt_execution_mode" \
            --depth "$rt_depth" \
            --run-id "$rt_run_id" \
            --timeout "$timeout" \
            --budget "$rt_token_budget" \
            ${rt_focus:+--focus "$rt_focus"} \
            ${rt_surface:+--surface "$rt_surface"} \
            --json) || {
            local rt_exit=$?
            error "Red team pipeline failed (exit $rt_exit)"
            exit $rt_exit
        }

        set_state "DONE"

        # Add metadata to result
        local end_time
        end_time=$(date +%s)
        local total_latency_ms=$(( (end_time - START_TIME) * 1000 ))

        local final_result
        final_result=$(echo "$rt_result" | jq \
            --arg phase "$phase" \
            --arg doc "$doc" \
            --arg domain "$domain" \
            --arg mode "$execution_mode" \
            --arg mode_reason "$mode_reason" \
            --arg run_id "$rt_run_id" \
            --arg orch_mode "red-team" \
            --arg exec_mode "$rt_execution_mode" \
            --argjson latency_ms "$total_latency_ms" \
            --argjson cost_cents "$TOTAL_COST" \
            --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            '. + {
                phase: $phase,
                document: $doc,
                mode: $orch_mode,
                execution_mode: $exec_mode,
                execution: {
                    mode: $mode,
                    mode_reason: $mode_reason,
                    run_id: $run_id
                },
                timestamp: $timestamp,
                metrics: ((.metrics // {}) + {
                    total_latency_ms: $latency_ms,
                    cost_cents: $cost_cents
                })
            }')

        # #582: fail closed when primary reviewer rejects the whole attack set.
        # If the red-team domain extractor grounds poorly, the secondary model
        # generates off-target attacks that the primary scores 0 across the
        # board. Detect that pattern and halt rather than returning noise.
        local rtg_threshold rtg_min_attacks
        rtg_threshold=$(yq -r '.red_team.grounding_failure.opus_zero_threshold // 0.8' "$CONFIG_FILE" 2>/dev/null || echo "0.8")
        rtg_min_attacks=$(yq -r '.red_team.grounding_failure.min_attacks // 3' "$CONFIG_FILE" 2>/dev/null || echo "3")

        local grounding_stats
        grounding_stats=$(echo "$final_result" | compute_grounding_stats "$rtg_threshold" "$rtg_min_attacks")

        local grounding_failure
        grounding_failure=$(echo "$grounding_stats" | jq -r '.grounding_failure // false')

        if [[ "$grounding_failure" == "true" ]]; then
            local gf_total gf_zero gf_ratio
            gf_total=$(echo "$grounding_stats" | jq -r '.total')
            gf_zero=$(echo "$grounding_stats" | jq -r '.opus_zero')
            gf_ratio=$(echo "$grounding_stats" | jq -r '.opus_zero_ratio')

            final_result=$(echo "$final_result" | jq --argjson stats "$grounding_stats" '
                . + {
                    grounding_failure: true,
                    grounding_stats: $stats
                }
            ')

            error "Red team grounding failure: $gf_zero/$gf_total attacks scored opus_score=0 (ratio $gf_ratio >= threshold $rtg_threshold)."
            error "The primary reviewer found none of the attacks grounded in the target document."
            error "Likely cause: domain extractor produced a weak domain string, and the attacker model generated off-target attacks from its prior."
            error "Action: inspect '$doc' section headings and opening paragraph; re-run with --domain '<specific domain text>' to override extraction."
            error "See GitHub issue #582 for context."

            log_trajectory "grounding_failure" "$final_result"
            echo "$final_result" | jq .
            log "Red team HALTED (grounding failure). Run ID: $rt_run_id, Cost: $TOTAL_COST cents"
            exit 3
        fi

        # cycle-062 (#485): silent-no-op detection extension.
        if [[ "$detect_silent_noop" == "true" ]]; then
            detect_silent_noop_flatline "red-team" "$final_result"
        fi

        log_trajectory "complete" "$final_result"
        echo "$final_result" | jq .
        log "Red team complete. Run ID: $rt_run_id, Cost: $TOTAL_COST cents"
        exit 0
    fi

    # Mode dispatch: inquiry mode uses collaborative multi-model queries (FR-4)
    if [[ "$orchestrator_mode" == "inquiry" ]]; then
        local inq_run_id
        inq_run_id="inq-$(date +%s)-$(head -c 4 /dev/urandom | od -An -tx1 | tr -d ' \n')"

        local inq_budget
        inq_budget=$(read_config '.flatline_protocol.inquiry.budget_cents' '500')

        local inq_result
        inq_result=$(run_inquiry "$doc" "$phase" "$context_file" "$DEFAULT_MODEL_TIMEOUT" "$inq_budget") || {
            local inq_exit=$?
            error "Inquiry mode failed (exit $inq_exit)"
            exit $inq_exit
        }

        set_state "DONE"

        local end_time
        end_time=$(date +%s)
        local total_latency_ms=$(( (end_time - START_TIME) * 1000 ))

        local final_result
        final_result=$(echo "$inq_result" | jq \
            --arg phase "$phase" \
            --arg doc "$doc" \
            --arg domain "$domain" \
            --arg mode "$execution_mode" \
            --arg mode_reason "$mode_reason" \
            --arg run_id "$inq_run_id" \
            --arg orch_mode "inquiry" \
            --argjson latency_ms "$total_latency_ms" \
            --argjson cost_cents "$TOTAL_COST" \
            --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            '. + {
                phase: $phase,
                document: $doc,
                domain: $domain,
                orchestrator_mode: $orch_mode,
                execution: {
                    mode: $mode,
                    mode_reason: $mode_reason,
                    run_id: $run_id
                },
                timestamp: $timestamp,
                metrics: ((.metrics // {}) + {
                    total_latency_ms: $latency_ms,
                    cost_cents: $cost_cents,
                    cost_usd: ($cost_cents / 100)
                })
            }')

        # cycle-062 (#485): silent-no-op detection extension.
        if [[ "$detect_silent_noop" == "true" ]]; then
            detect_silent_noop_flatline "inquiry" "$final_result"
        fi

        # Save to output directory
        local output_dir="$PROJECT_ROOT/grimoires/loa/a2a/flatline"
        mkdir -p "$output_dir"
        echo "$final_result" | jq . > "$output_dir/${phase}-inquiry.json"

        log_trajectory "complete" "$final_result"
        echo "$final_result" | jq .
        log "Inquiry complete. Run ID: $inq_run_id, Cost: $TOTAL_COST cents"
        exit 0
    fi

    # Phase 1: Independent Reviews (review mode)
    local phase1_output
    phase1_output=$(run_phase1 "$doc" "$phase" "$context_file" "$DEFAULT_MODEL_TIMEOUT" "$budget")

    local gpt_review_file opus_review_file gpt_skeptic_file opus_skeptic_file
    local tertiary_review_file="" tertiary_skeptic_file=""
    gpt_review_file=$(echo "$phase1_output" | sed -n '1p')
    opus_review_file=$(echo "$phase1_output" | sed -n '2p')
    gpt_skeptic_file=$(echo "$phase1_output" | sed -n '3p')
    opus_skeptic_file=$(echo "$phase1_output" | sed -n '4p')
    # FR-3: Tertiary paths are lines 5-6 when present
    tertiary_review_file=$(echo "$phase1_output" | sed -n '5p')
    tertiary_skeptic_file=$(echo "$phase1_output" | sed -n '6p')

    # cycle-109 Sprint 2 T2.4 — aggregate verdict_quality from per-voice
    # phase1 review files into final_consensus.json. Uses ONLY the review
    # files (not skeptic / tertiary skeptic) since those represent the
    # canonical adversarial cohort voices that compute_blocker_risk and
    # the schema-conformance suite (T2.8) anchor on. Skeptic / tertiary
    # paths are inferential, not first-class voices.
    local -a vq_phase1_files=("$gpt_review_file" "$opus_review_file")
    if [[ -n "$tertiary_review_file" && -s "$tertiary_review_file" ]]; then
        vq_phase1_files+=("$tertiary_review_file")
    fi
    aggregate_and_write_final_consensus "$phase" "${vq_phase1_files[@]}" || true

    # Check budget before Phase 2
    if ! check_budget 100 "$budget"; then
        log "Warning: Budget limit approaching, skipping Phase 2"
        skip_consensus=true
    fi

    # Phase 2: Cross-Scoring (unless skipped)
    local gpt_scores_file="" opus_scores_file=""
    local tertiary_scores_opus="" tertiary_scores_gpt="" gpt_scores_tertiary="" opus_scores_tertiary=""
    if [[ "$skip_consensus" != "true" ]]; then
        local phase2_output
        phase2_output=$(run_phase2 "$gpt_review_file" "$opus_review_file" "$phase" "$DEFAULT_MODEL_TIMEOUT" "$tertiary_review_file")

        gpt_scores_file=$(echo "$phase2_output" | sed -n '1p')
        opus_scores_file=$(echo "$phase2_output" | sed -n '2p')
        # FR-3: Tertiary scoring files are lines 3-6 when present
        tertiary_scores_opus=$(echo "$phase2_output" | sed -n '3p')
        tertiary_scores_gpt=$(echo "$phase2_output" | sed -n '4p')
        gpt_scores_tertiary=$(echo "$phase2_output" | sed -n '5p')
        opus_scores_tertiary=$(echo "$phase2_output" | sed -n '6p')
    fi

    # Phase 3: Consensus Calculation
    local result
    if [[ "$skip_consensus" != "true" && -n "$gpt_scores_file" && -n "$opus_scores_file" ]]; then
        result=$(run_consensus "$gpt_scores_file" "$opus_scores_file" "$gpt_skeptic_file" "$opus_skeptic_file" \
            "$tertiary_scores_opus" "$tertiary_scores_gpt" "$gpt_scores_tertiary" "$opus_scores_tertiary" \
            "$tertiary_skeptic_file")
    else
        # Return raw reviews without consensus
        result=$(jq -n \
            --slurpfile gpt_review "$gpt_review_file" \
            --slurpfile opus_review "$opus_review_file" \
            '{
                consensus_summary: {
                    high_consensus_count: 0,
                    disputed_count: 0,
                    low_value_count: 0,
                    blocker_count: 0,
                    model_agreement_percent: 0
                },
                raw_reviews: {
                    gpt: $gpt_review[0],
                    opus: $opus_review[0]
                },
                note: "Consensus calculation skipped"
            }')
    fi

    # =========================================================================
    # Phase 3: Round-Robin Arbiter (cycle-070 FR-4)
    # When autonomous mode + arbiter enabled, a single model arbitrates
    # DISPUTED and BLOCKER findings instead of HITL prompts.
    # =========================================================================

    local arbiter_enabled
    arbiter_enabled=$(yq eval '.flatline_protocol.autonomous_arbiter.enabled // false' "$PROJECT_ROOT/.loa.config.yaml" 2>/dev/null || echo "false")

    if [[ "$arbiter_enabled" == "true" && "${SIMSTIM_AUTONOMOUS:-0}" == "1" ]]; then
        local disputed_count blocker_count
        disputed_count=$(echo "$result" | jq '.consensus_summary.disputed_count // 0')
        blocker_count=$(echo "$result" | jq '.consensus_summary.blocker_count // 0')

        if [[ "$disputed_count" -gt 0 || "$blocker_count" -gt 0 ]]; then
            log "Arbiter: $((disputed_count + blocker_count)) findings require arbitration (phase: $phase)"

            # Select arbiter model (round-robin by phase)
            local arbiter_model
            local rotation_raw
            rotation_raw=$(yq eval '.flatline_protocol.autonomous_arbiter.rotation[]' "$PROJECT_ROOT/.loa.config.yaml" 2>/dev/null || true)
            local rotation=()
            if [[ -n "$rotation_raw" ]]; then
                mapfile -t rotation <<< "$rotation_raw"
            fi
            [[ ${#rotation[@]} -lt 3 ]] && rotation=("opus" "gpt-5.3-codex" "gemini-2.5-pro")

            case "$phase" in
                prd)    arbiter_model="${rotation[0]}" ;;
                sdd)    arbiter_model="${rotation[1]}" ;;
                sprint) arbiter_model="${rotation[2]}" ;;
                *)      arbiter_model="${rotation[0]}" ;;
            esac

            # Build arbiter prompt
            local arbiter_prompt_file
            arbiter_prompt_file=$(mktemp)
            chmod 600 "$arbiter_prompt_file"

            local doc_excerpt=""
            if [[ -f "$doc" ]]; then
                doc_excerpt=$(head -c 2048 "$doc")
            fi

            local findings_to_arbitrate
            findings_to_arbitrate=$(echo "$result" | jq '[(.disputed // [])[], (.blockers // [])[]]')

            jq -n \
                --arg doc_excerpt "$doc_excerpt" \
                --arg phase "$phase" \
                --argjson findings "$findings_to_arbitrate" \
                '"You are the arbiter for this Flatline review. For each finding below, decide: accept (integrate the suggestion) or reject (with rationale). Your decision is final.\n\nDocument (" + $phase + ") excerpt:\n" + $doc_excerpt[0:2048] + "\n\nFindings requiring your decision:\n" + ($findings | tojson) + "\n\nRespond with a JSON array:\n[{\"finding_id\": \"...\", \"decision\": \"accept\"|\"reject\", \"rationale\": \"...\"}]"' \
                | jq -r '.' > "$arbiter_prompt_file"

            # Invoke with provider cascade (SKP-006)
            local arbiter_result="" arbiter_success=false cascade_attempts=0
            local try_models=("$arbiter_model")
            # Build cascade: designated → others
            for m in "${rotation[@]}"; do
                [[ "$m" != "$arbiter_model" ]] && try_models+=("$m")
            done

            for try_model in "${try_models[@]}"; do
                cascade_attempts=$((cascade_attempts + 1))
                log "Arbiter: trying $try_model (attempt $cascade_attempts)"

                local max_arbiter_tokens
                max_arbiter_tokens=$(yq eval '.flatline_protocol.autonomous_arbiter.max_arbiter_tokens // 4000' "$PROJECT_ROOT/.loa.config.yaml" 2>/dev/null || echo "4000")

                arbiter_result=$("$SCRIPT_DIR/model-adapter.sh" \
                    --mode "review" \
                    --model "$try_model" \
                    --input "$arbiter_prompt_file" \
                    --timeout 120 \
                    2>/dev/null) && {
                    arbiter_success=true
                    log "Arbiter: $try_model decided (phase: $phase)"
                    break
                }
                log "WARNING: Arbiter $try_model failed, cascading..."
            done

            rm -f "$arbiter_prompt_file"

            # Apply arbiter decisions
            if [[ "$arbiter_success" == "true" ]]; then
                # Extract JSON decisions from arbiter response
                local decisions
                decisions=$(echo "$arbiter_result" | jq -r '.content // .' 2>/dev/null | \
                    grep -oE '\[.*\]' | head -1 | jq '.' 2>/dev/null || echo "[]")

                if echo "$decisions" | jq -e 'type == "array"' >/dev/null 2>&1; then
                    # Process each decision
                    local accepted_ids rejected_ids
                    accepted_ids=$(echo "$decisions" | jq -r '[.[] | select(.decision == "accept") | .finding_id] | join(",")')
                    rejected_ids=$(echo "$decisions" | jq -r '[.[] | select(.decision == "reject") | .finding_id] | join(",")')

                    # Modify consensus: accepted findings → high_consensus, rejected → arbiter_rejected
                    result=$(echo "$result" | jq --arg accepted "$accepted_ids" --arg rejected "$rejected_ids" '
                        . as $orig |
                        ($accepted | split(",") | map(select(. != ""))) as $acc |
                        ($rejected | split(",") | map(select(. != ""))) as $rej |

                        # Move accepted blockers/disputed to high_consensus
                        .high_consensus = (.high_consensus + [
                            (.disputed[]? | select(.id as $id | $acc | index($id))),
                            (.blockers[]? | select(.id as $id | $acc | index($id)))
                        ] | map(. + {arbiter_accepted: true})) |

                        # Move rejected to arbiter_rejected
                        .arbiter_rejected = [
                            (.disputed[]? | select(.id as $id | $rej | index($id))),
                            (.blockers[]? | select(.id as $id | $rej | index($id)))
                        ] |

                        # Remove arbitrated items from disputed/blockers
                        .disputed = [.disputed[]? | select(.id as $id | ($acc + $rej) | index($id) | not)] |
                        .blockers = [.blockers[]? | select(.id as $id | ($acc + $rej) | index($id) | not)] |

                        # Recalculate summary
                        .consensus_summary.high_consensus_count = (.high_consensus | length) |
                        .consensus_summary.disputed_count = (.disputed | length) |
                        .consensus_summary.blocker_count = (.blockers | length) |
                        .consensus_summary.arbiter_accepted_count = ([$acc | length] | .[0]) |
                        .consensus_summary.arbiter_rejected_count = ([$rej | length] | .[0])
                    ')

                    # Trajectory logging (NFR-4)
                    local trajectory_dir
                    trajectory_dir=$(get_trajectory_dir 2>/dev/null || echo "$PROJECT_ROOT/grimoires/loa/a2a/trajectory")
                    mkdir -p "$trajectory_dir"
                    local arbiter_log="$trajectory_dir/flatline-arbiter-$(date +%Y-%m-%d).jsonl"

                    echo "$decisions" | jq -c --arg phase "$phase" --arg model "$arbiter_model" \
                        --argjson attempts "$cascade_attempts" '.[] | {
                            type: "flatline_arbiter",
                            phase: $phase,
                            arbiter_model: $model,
                            finding_id: .finding_id,
                            decision: .decision,
                            rationale: .rationale,
                            cascade_attempts: $attempts,
                            timestamp: (now | strftime("%Y-%m-%dT%H:%M:%SZ"))
                        }' >> "$arbiter_log" 2>/dev/null || true

                    log "Arbiter: $(echo "$decisions" | jq 'length') decisions applied"
                else
                    log "WARNING: Arbiter returned malformed JSON, treating as failure"
                    arbiter_success=false
                fi
            fi

            if [[ "$arbiter_success" != "true" ]]; then
                # Conservative fallback: auto-reject all blockers
                log "WARNING: All arbiter models failed, auto-rejecting blockers"
                result=$(echo "$result" | jq '
                    .arbiter_rejected = .blockers |
                    .blockers = [] |
                    .consensus_summary.blocker_count = 0 |
                    .consensus_summary.arbiter_rejected_count = (.arbiter_rejected | length) |
                    .consensus_summary.arbiter_fallback = true
                ')
            fi
        fi
    fi

    set_state "DONE"

    # Calculate final metrics
    local end_time
    end_time=$(date +%s)
    local total_latency_ms=$(( (end_time - START_TIME) * 1000 ))

    # FR-1 (cycle-045): Determine tertiary model status for output metadata
    local tertiary_model_output
    tertiary_model_output=$(get_model_tertiary)
    local tertiary_status_output="disabled"
    if [[ -n "$tertiary_model_output" ]]; then
        tertiary_status_output="active"
    fi

    # Add metadata to result
    local final_result
    final_result=$(echo "$result" | jq \
        --arg phase "$phase" \
        --arg doc "$doc" \
        --arg domain "$domain" \
        --arg mode "$execution_mode" \
        --arg mode_reason "$mode_reason" \
        --arg run_id "${run_id:-}" \
        --argjson tertiary_model "$(if [[ -n "${tertiary_model_output:-}" ]]; then jq -n --arg m "$tertiary_model_output" '$m'; else echo 'null'; fi)" \
        --arg tertiary_status "$tertiary_status_output" \
        --argjson latency_ms "$total_latency_ms" \
        --argjson cost_cents "$TOTAL_COST" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '. + {
            phase: $phase,
            document: $doc,
            domain: $domain,
            tertiary_model_used: $tertiary_model,
            tertiary_status: $tertiary_status,
            execution: {
                mode: $mode,
                mode_reason: $mode_reason,
                run_id: (if $run_id == "" then null else $run_id end)
            },
            timestamp: $timestamp,
            metrics: {
                total_latency_ms: $latency_ms,
                cost_cents: $cost_cents,
                cost_usd: ($cost_cents / 100)
            }
        }')

    # cycle-062 follow-up (#485): silent-no-op detection for review mode.
    # Wires the helper branch that was defined but previously unused.
    if [[ "$detect_silent_noop" == "true" ]]; then
        detect_silent_noop_flatline "review" "$final_result"
    fi

    # Log to trajectory
    log_trajectory "complete" "$final_result"

    # Output result
    echo "$final_result" | jq .

    # FR-4 (cycle-045): Log model count for observability
    local primary_model_name
    primary_model_name=$(get_model_primary)
    local secondary_model_name
    secondary_model_name=$(get_model_secondary)
    if [[ -n "$tertiary_model_output" ]]; then
        log "Flatline: 3-model ($primary_model_name + $secondary_model_name + $tertiary_model_output)"
    else
        log "Flatline: 2-model ($primary_model_name + $secondary_model_name)"
    fi
    log "Flatline Protocol complete. Cost: $TOTAL_COST cents, Latency: ${total_latency_ms}ms"
}

# Only invoke main when executed directly; sourcing exposes functions for tests.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
