#!/usr/bin/env bash
# =============================================================================
# hitl-jury-panel-lib.sh — L1 jury-panel adjudication primitive (Sprint 1D)
#
# cycle-098 Sprint 1D — implementation of the L1 hitl-jury-panel skill per
# RFC #653, PRD FR-L1, SDD §1.4.2 + §5.3.
#
# Composition (does NOT reinvent):
#   - 1A audit envelope:       audit_emit (writes JSONL with prev_hash chain)
#   - 1B signing scheme:       audit_emit honors LOA_AUDIT_SIGNING_KEY_ID
#   - 1B protected-class:      is_protected_class (router short-circuit)
#   - 1B operator identity:    NOT consumed here (caller's responsibility)
#   - 1C sanitize:             sanitize_for_session_start (panelist context wrap)
#
# Public functions:
#   panel_invoke <decision_id> <decision_class> <context_hash> <panelists_yaml> <context>
#   panel_solicit <panelist_id> <model> <persona_path> <context_path> [--timeout <s>]
#   panel_select <panelists_json> <decision_id> <context_hash>
#   panel_log_views <decision_id> <panelists_with_views_json> <log_path>
#   panel_log_binding <decision_id> <selected_panelist_id> <seed> <minority_dissent_json> <log_path>
#   panel_log_queued_protected <decision_id> <decision_class> <log_path>
#   panel_log_fallback <decision_id> <fallback_path> <panelists_json> <log_path>
#   panel_check_disagreement <panelists_views_json> <threshold>
#
# Environment variables:
#   LOA_PANEL_AUDIT_LOG          path for audit log; default .run/panel-decisions.jsonl
#   LOA_PANEL_PROTECTED_QUEUE    path for protected queue; default .run/protected-queue.jsonl
#   LOA_PANEL_PER_PANELIST_TIMEOUT  per-panelist timeout in seconds (default 60)
#   LOA_PANEL_MIN_PANELISTS      minimum surviving panelists for BOUND (default 2)
#   LOA_PANEL_DISAGREEMENT_FN    optional path to disagreement-check script
#   LOA_PANEL_TEST_INVOKE_DIR    test-only: per-panelist mock-invoke fixtures
#   LOA_PANEL_TEST_PANELIST      test-only: current panelist (set by panel_solicit)
#
# Exit codes:
#   0 = success (BOUND, QUEUED_PROTECTED, or FALLBACK; outcome in JSON return)
#   2 = invalid arguments
#   1 = unrecoverable error (audit-log write failure, etc.)
# =============================================================================

set -euo pipefail

if [[ "${_LOA_PANEL_LIB_SOURCED:-0}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi
_LOA_PANEL_LIB_SOURCED=1

_PANEL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_PANEL_REPO_ROOT="$(cd "${_PANEL_DIR}/../../.." && pwd)"
_PANEL_AUDIT_ENVELOPE="${_PANEL_REPO_ROOT}/.claude/scripts/audit-envelope.sh"
_PANEL_PROTECTED_ROUTER="${_PANEL_REPO_ROOT}/.claude/scripts/lib/protected-class-router.sh"
_PANEL_CTX_ISOLATION="${_PANEL_REPO_ROOT}/.claude/scripts/lib/context-isolation-lib.sh"

# Source dependencies (idempotent — they all guard against double-source).
# shellcheck source=../audit-envelope.sh
source "${_PANEL_AUDIT_ENVELOPE}"
# shellcheck source=protected-class-router.sh
source "${_PANEL_PROTECTED_ROUTER}"
# shellcheck source=context-isolation-lib.sh
source "${_PANEL_CTX_ISOLATION}"

_panel_log() { echo "[hitl-jury-panel] $*" >&2; }

# -----------------------------------------------------------------------------
# panel_select <panelists_json> <decision_id> <context_hash>
#
# Compute deterministic seed and selected panelist index.
#   seed = sha256(decision_id || context_hash)
#   index = (seed-as-uint256) % len(sorted-by-id panelists)
#
# Output (stdout): JSON object
#   {
#     "selected_panelist_id": "<id>",
#     "selection_seed": "<64-hex>",
#     "sorted_panelist_ids": ["a", "b", "c"]
#   }
# -----------------------------------------------------------------------------
panel_select() {
    local panelists_json="${1:-}"
    local decision_id="${2:-}"
    local context_hash="${3:-}"

    if [[ -z "$panelists_json" || -z "$decision_id" || -z "$context_hash" ]]; then
        _panel_log "panel_select: missing required argument(s)"
        return 2
    fi

    # Validate input is an array.
    if ! printf '%s' "$panelists_json" | jq -e 'type == "array"' >/dev/null 2>&1; then
        _panel_log "panel_select: panelists must be a JSON array"
        return 2
    fi
    local count
    count=$(printf '%s' "$panelists_json" | jq 'length')
    if (( count < 1 )); then
        _panel_log "panel_select: empty panelist list"
        return 2
    fi

    # Sort panelist ids (canonical for cross-process determinism).
    local sorted_ids_json
    sorted_ids_json=$(printf '%s' "$panelists_json" | jq -c '[.[].id] | sort')

    # Compute seed = sha256(decision_id || context_hash) hex.
    local seed
    seed=$(printf '%s%s' "$decision_id" "$context_hash" | sha256sum | awk '{print $1}')

    # Compute index = seed-as-uint256 mod count (Python big-int).
    local index selected
    index=$(LOA_PANEL_SEED="$seed" LOA_PANEL_COUNT="$count" python3 -c '
import os, sys
s = int(os.environ["LOA_PANEL_SEED"], 16)
n = int(os.environ["LOA_PANEL_COUNT"])
print(s % n)
')
    selected=$(printf '%s' "$sorted_ids_json" | jq -r ".[$index]")

    # Emit selection JSON.
    jq -nc \
        --arg sel "$selected" \
        --arg seed "$seed" \
        --argjson sorted "$sorted_ids_json" \
        '{selected_panelist_id:$sel, selection_seed:$seed, sorted_panelist_ids:$sorted}'
}

# -----------------------------------------------------------------------------
# panel_solicit <panelist_id> <model> <persona_path> <context_path> [--timeout <s>]
#
# Invoke a single panelist via model-invoke (or LOA_PANEL_TEST_INVOKE_DIR shim).
# Returns JSON object on stdout:
#   {
#     "id": "<panelist-id>",
#     "model": "<model>",
#     "persona_path": "<path>",
#     "view": "<text>",
#     "reasoning_summary": "<text>",
#     "error": "<diagnostic|null>",
#     "timed_out": <bool>,
#     "duration_seconds": <number>
#   }
#
# Always exits 0 — failures are reported in the JSON's `error` field so
# panel_invoke can aggregate without losing data on a single panelist's failure.
# -----------------------------------------------------------------------------
panel_solicit() {
    local panelist_id="${1:-}"
    local model="${2:-}"
    local persona_path="${3:-}"
    local context_path="${4:-}"
    shift 4 2>/dev/null || true

    local timeout_s="${LOA_PANEL_PER_PANELIST_TIMEOUT:-60}"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --timeout) timeout_s="$2"; shift 2 ;;
            *) _panel_log "panel_solicit: unknown flag '$1'"; return 2 ;;
        esac
    done

    if [[ -z "$panelist_id" || -z "$model" ]]; then
        _panel_log "panel_solicit: missing required argument(s)"
        return 2
    fi

    local started ended duration
    started=$(date +%s)

    # Capture stdout to a temp file; capture stderr separately; respect timeout.
    # NOTE: cleanup is explicit at the end of the function — no RETURN trap.
    local out_file err_file rc
    out_file=$(mktemp)
    err_file=$(mktemp)

    # We use the `timeout` utility when available; otherwise SIGALRM-style fallback
    # via background + sleep guard. Linux + macOS Homebrew both ship `timeout`
    # (coreutils on Mac); when missing, panel_solicit accepts longer waits.
    # NB: do NOT use --preserve-status — that masks timeout (124) with the
    # killed child's exit status. Also: `if ! cmd; then rc=$?; fi` does NOT
    # preserve rc reliably under bats/`set -e` — use `cmd || rc=$?`.
    local timed_out=false
    rc=0
    if command -v timeout >/dev/null 2>&1; then
        LOA_PANEL_TEST_PANELIST="$panelist_id" \
            timeout "$timeout_s" \
                model-invoke --model "$model" --prompt "$(cat "$context_path" 2>/dev/null || true)" \
                </dev/null >"$out_file" 2>"$err_file" \
            || rc=$?
        # `timeout` exits 124 on its SIGTERM, 137 (=128+9) on SIGKILL,
        # OR forwards the child's signal-status if the child was killed
        # mid-sleep (e.g. 143 = 128+15 for SIGTERM-killed child).
        if [[ "$rc" -eq 124 || "$rc" -eq 137 || "$rc" -eq 143 ]]; then
            timed_out=true
        fi
    else
        LOA_PANEL_TEST_PANELIST="$panelist_id" \
            model-invoke --model "$model" --prompt "$(cat "$context_path" 2>/dev/null || true)" \
                </dev/null >"$out_file" 2>"$err_file" \
            || rc=$?
    fi

    ended=$(date +%s)
    duration=$((ended - started))

    # Defense-in-depth: if the wall-clock duration met or exceeded the timeout
    # AND the child failed (rc≠0), treat this as a timeout regardless of the
    # exact signal status forwarded.
    if [[ "$rc" -ne 0 && "$duration" -ge "$timeout_s" ]]; then
        timed_out=true
    fi

    local view="" reasoning="" err=""
    if [[ "$timed_out" == "true" ]]; then
        err="timeout after ${timeout_s}s"
    elif [[ "$rc" -ne 0 ]]; then
        # Take the first 200 bytes of stderr for the diagnostic.
        err="exit=$rc; $(head -c 200 "$err_file" | tr -d '\n' || true)"
    else
        # Try to parse JSON {view, reasoning_summary}; fall back to raw stdout.
        if jq -e '. | type == "object"' >/dev/null 2>&1 < "$out_file"; then
            view=$(jq -r '.view // ""' < "$out_file")
            reasoning=$(jq -r '.reasoning_summary // ""' < "$out_file")
        else
            view=$(cat "$out_file" | tr -d '\n')
            reasoning=""
        fi
    fi

    # Build JSON. Empty error → null.
    if [[ -z "$err" ]]; then
        jq -nc \
            --arg id "$panelist_id" \
            --arg model "$model" \
            --arg pp "$persona_path" \
            --arg view "$view" \
            --arg rs "$reasoning" \
            --argjson to "$timed_out" \
            --argjson dur "$duration" \
            '{id:$id, model:$model, persona_path:$pp, view:$view, reasoning_summary:$rs, error:null, timed_out:$to, duration_seconds:$dur}'
    else
        jq -nc \
            --arg id "$panelist_id" \
            --arg model "$model" \
            --arg pp "$persona_path" \
            --arg view "" \
            --arg rs "" \
            --arg err "$err" \
            --argjson to "$timed_out" \
            --argjson dur "$duration" \
            '{id:$id, model:$model, persona_path:$pp, view:$view, reasoning_summary:$rs, error:$err, timed_out:$to, duration_seconds:$dur}'
    fi

    # Explicit cleanup (no RETURN trap — see note in panel_invoke).
    rm -f "$out_file" "$err_file"
    return 0
}

# -----------------------------------------------------------------------------
# panel_log_views <decision_id> <panelists_with_views_json> <log_path>
#
# Emits a panel.solicit envelope BEFORE selection. FR-L1-2 requires this to
# be persisted before the selection step so a crash leaves an auditable trail.
# -----------------------------------------------------------------------------
panel_log_views() {
    local decision_id="${1:-}"
    local panelists_json="${2:-}"
    local log_path="${3:-${LOA_PANEL_AUDIT_LOG:-.run/panel-decisions.jsonl}}"

    if [[ -z "$decision_id" || -z "$panelists_json" ]]; then
        _panel_log "panel_log_views: missing required argument(s)"
        return 2
    fi

    if ! printf '%s' "$panelists_json" | jq -e 'type == "array"' >/dev/null 2>&1; then
        _panel_log "panel_log_views: panelists must be JSON array"
        return 2
    fi

    local payload
    payload=$(jq -nc \
        --arg d "$decision_id" \
        --argjson p "$panelists_json" \
        '{decision_id:$d, panelists:$p}')

    audit_emit L1 panel.solicit "$payload" "$log_path"
}

# -----------------------------------------------------------------------------
# panel_log_binding <decision_id> <selected_panelist_id> <seed> <minority_dissent_json> <log_path>
#
# Emits the panel.bind envelope after selection. Records the binding view +
# minority dissent + selection seed.
# -----------------------------------------------------------------------------
panel_log_binding() {
    local decision_id="${1:-}"
    local selected="${2:-}"
    local seed="${3:-}"
    local minority="${4:-[]}"
    local log_path="${5:-${LOA_PANEL_AUDIT_LOG:-.run/panel-decisions.jsonl}}"

    if [[ -z "$decision_id" || -z "$selected" || -z "$seed" ]]; then
        _panel_log "panel_log_binding: missing required argument(s)"
        return 2
    fi

    # Optionally accept extra fields via env vars (avoids long arg lists).
    local binding_view="${LOA_PANEL_BIND_VIEW:-}"
    local panelists_json="${LOA_PANEL_BIND_PANELISTS:-[]}"
    local fallback_path="${LOA_PANEL_BIND_FALLBACK_PATH:-null}"
    local cost_estimate="${LOA_PANEL_BIND_COST:-null}"
    local trust_check="${LOA_PANEL_BIND_TRUST:-null}"
    local decision_class="${LOA_PANEL_BIND_CLASS:-}"
    local context_hash="${LOA_PANEL_BIND_CTX_HASH:-}"

    # Normalize JSON-ish env vars: trust_check / cost_estimate / fallback may be "null".
    local fallback_json="$fallback_path"
    if [[ "$fallback_path" == "null" || -z "$fallback_path" ]]; then
        fallback_json="null"
    else
        fallback_json="\"$fallback_path\""
    fi
    local trust_json="$trust_check"
    if [[ "$trust_check" == "null" || -z "$trust_check" ]]; then
        trust_json="null"
    else
        trust_json="\"$trust_check\""
    fi
    local cost_json="$cost_estimate"
    if [[ "$cost_estimate" == "null" || -z "$cost_estimate" ]]; then
        cost_json="null"
    fi

    local payload
    payload=$(jq -nc \
        --arg d "$decision_id" \
        --arg dc "$decision_class" \
        --arg ch "$context_hash" \
        --arg sel "$selected" \
        --arg seed "$seed" \
        --arg view "$binding_view" \
        --argjson minority "$minority" \
        --argjson panelists "$panelists_json" \
        --argjson fallback "$fallback_json" \
        --argjson cost "$cost_json" \
        --argjson trust "$trust_json" \
        '{
            decision_id:$d,
            decision_class:$dc,
            context_hash:$ch,
            panelists:$panelists,
            selection_seed:$seed,
            selected_panelist_id:$sel,
            binding_view:$view,
            minority_dissent:$minority,
            outcome:"BOUND",
            fallback_path:$fallback,
            cost_estimate_usd:$cost,
            trust_check_result:$trust
        }')

    audit_emit L1 panel.bind "$payload" "$log_path"
}

# -----------------------------------------------------------------------------
# panel_log_queued_protected <decision_id> <decision_class> <log_path>
#
# Emits a panel.queued_protected envelope when the pre-flight protected-class
# check matched. ALSO appends a queue entry to .run/protected-queue.jsonl
# for operator triage.
# -----------------------------------------------------------------------------
panel_log_queued_protected() {
    local decision_id="${1:-}"
    local decision_class="${2:-}"
    local log_path="${3:-${LOA_PANEL_AUDIT_LOG:-.run/panel-decisions.jsonl}}"
    local queue="${LOA_PANEL_PROTECTED_QUEUE:-.run/protected-queue.jsonl}"

    if [[ -z "$decision_id" || -z "$decision_class" ]]; then
        _panel_log "panel_log_queued_protected: missing required argument(s)"
        return 2
    fi

    local payload
    payload=$(jq -nc \
        --arg d "$decision_id" \
        --arg dc "$decision_class" \
        --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        '{decision_id:$d, decision_class:$dc, route:"QUEUED_PROTECTED", queued_at:$ts}')

    # 1. Audit envelope (signed if signing key configured).
    audit_emit L1 panel.queued_protected "$payload" "$log_path"

    # 2. Queue entry (operator-bound; consumed when operator takes action).
    mkdir -p "$(dirname "$queue")"
    printf '%s\n' "$payload" >> "$queue"
}

# -----------------------------------------------------------------------------
# panel_log_fallback <decision_id> <fallback_path> <panelists_json> <log_path>
#
# Emits a panel.fallback envelope when the panel cannot reach a binding view
# (all panelists failed, or surviving count < min). Outcome stored = FALLBACK.
# -----------------------------------------------------------------------------
panel_log_fallback() {
    local decision_id="${1:-}"
    local fallback_path="${2:-unknown}"
    local panelists_json="${3:-[]}"
    local log_path="${4:-${LOA_PANEL_AUDIT_LOG:-.run/panel-decisions.jsonl}}"

    if [[ -z "$decision_id" ]]; then
        _panel_log "panel_log_fallback: missing decision_id"
        return 2
    fi

    if ! printf '%s' "$panelists_json" | jq -e 'type == "array"' >/dev/null 2>&1; then
        panelists_json='[]'
    fi

    local payload
    payload=$(jq -nc \
        --arg d "$decision_id" \
        --arg fp "$fallback_path" \
        --argjson p "$panelists_json" \
        '{decision_id:$d, fallback_path:$fp, panelists:$p, outcome:"FALLBACK"}')

    audit_emit L1 panel.fallback "$payload" "$log_path"
}

# -----------------------------------------------------------------------------
# panel_check_disagreement <panelists_views_json> <threshold>
#
# FR-L1-6: caller-configurable embedding fn. Default behavior is no-op pass.
# When LOA_PANEL_DISAGREEMENT_FN is set (path to executable script), the
# script is invoked with stdin = panelists_views_json + arg = threshold.
# Script's exit code is propagated:
#   0   = pass (panel proceeds)
#   !=0 = disagreement detected (caller routes to QUEUED_DISAGREE)
# -----------------------------------------------------------------------------
panel_check_disagreement() {
    local panelists_views_json="${1:-[]}"
    local threshold="${2:-0.5}"

    # Default (no embedding fn supplied): pass.
    if [[ -z "${LOA_PANEL_DISAGREEMENT_FN:-}" ]]; then
        return 0
    fi
    if [[ ! -x "$LOA_PANEL_DISAGREEMENT_FN" ]]; then
        _panel_log "panel_check_disagreement: LOA_PANEL_DISAGREEMENT_FN not executable: $LOA_PANEL_DISAGREEMENT_FN"
        return 0
    fi

    # Run the caller-supplied fn; pass views via stdin, threshold via arg.
    printf '%s' "$panelists_views_json" | "$LOA_PANEL_DISAGREEMENT_FN" "$threshold"
}

# -----------------------------------------------------------------------------
# panel_invoke <decision_id> <decision_class> <context_hash> <panelists_yaml> <context>
#
# Top-level orchestrator. See SDD §5.3.1 for the contract.
#
# Steps:
#   1. Pre-flight: is_protected_class check → QUEUED_PROTECTED short-circuit
#   2. Read panelists from YAML config
#   3. Solicit each panelist in parallel
#   4. Log views BEFORE selection (FR-L1-2)
#   5. Apply fallback matrix to surviving panelists
#   6. Compute seed + select binding view (FR-L1-3)
#   7. Run disagreement check (default no-op)
#   8. Log binding (FR-L1-7) + return result JSON
# -----------------------------------------------------------------------------
panel_invoke() {
    # Outer wrapper: runs the impl and cleans up the work dir on every exit
    # path. We pass the work dir to the impl via env var so the inner function
    # can reference it without a global.
    local _panel_work_dir
    _panel_work_dir=$(mktemp -d)
    local _panel_rc=0
    LOA_PANEL_WORK_DIR="$_panel_work_dir" _panel_invoke_impl "$@" || _panel_rc=$?
    rm -rf "$_panel_work_dir"
    return "$_panel_rc"
}

_panel_invoke_impl() {
    local decision_id="${1:-}"
    local decision_class="${2:-}"
    local context_hash="${3:-}"
    local panelists_yaml="${4:-}"
    local context_path="${5:-}"

    if [[ -z "$decision_id" || -z "$decision_class" || -z "$context_hash" || -z "$panelists_yaml" ]]; then
        _panel_log "panel_invoke: missing required argument(s)"
        return 2
    fi

    local log_path="${LOA_PANEL_AUDIT_LOG:-.run/panel-decisions.jsonl}"

    # ---- 1. Pre-flight: protected class -----------------------------------
    if is_protected_class "$decision_class"; then
        panel_log_queued_protected "$decision_id" "$decision_class" "$log_path"
        jq -nc \
            --arg d "$decision_id" \
            --arg dc "$decision_class" \
            '{
                outcome:"QUEUED_PROTECTED",
                binding_view:null,
                selected_panelist_id:null,
                selection_seed:null,
                minority_dissent:[],
                audit_log_entry_id:("L1:panel.queued_protected:" + $d),
                diagnostic:("decision_class \"" + $dc + "\" is protected; queued for operator")
            }'
        return 0
    fi

    # ---- 2. Read panelist config -------------------------------------------
    if [[ ! -f "$panelists_yaml" ]]; then
        _panel_log "panel_invoke: panelists yaml not found: $panelists_yaml"
        return 2
    fi
    local panelists_json
    if command -v yq >/dev/null 2>&1; then
        panelists_json=$(yq -o=json '.panelists' "$panelists_yaml" 2>/dev/null || echo "[]")
    else
        panelists_json=$(LOA_PANEL_YAML="$panelists_yaml" python3 -c '
import json, os, sys
try:
    import yaml
except ImportError:
    print("[]"); sys.exit(0)
with open(os.environ["LOA_PANEL_YAML"]) as f:
    doc = yaml.safe_load(f) or {}
print(json.dumps(doc.get("panelists") or []))
')
    fi
    if ! printf '%s' "$panelists_json" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1; then
        _panel_log "panel_invoke: no panelists configured in $panelists_yaml"
        return 2
    fi

    # ---- 3. Solicit panelists in parallel ----------------------------------
    # We avoid GNU parallel for portability — use background bash + temp files.
    # The work dir is owned by the outer panel_invoke() wrapper which handles
    # cleanup; do NOT use `trap RETURN` (it fires in each subshell exit and
    # would race-delete the work dir).
    local solicit_dir="${LOA_PANEL_WORK_DIR:-$(mktemp -d)}"

    local n_panelists pidx pid model persona pp_pid
    n_panelists=$(printf '%s' "$panelists_json" | jq 'length')

    # Sanitize the context for session-start (untrusted-content wrap).
    local ctx_sanitized="$solicit_dir/context.txt"
    if [[ -f "$context_path" ]]; then
        sanitize_for_session_start L7 "$context_path" > "$ctx_sanitized" 2>/dev/null || cp "$context_path" "$ctx_sanitized"
    else
        : > "$ctx_sanitized"
    fi

    local pids=()
    for ((pidx=0; pidx<n_panelists; pidx++)); do
        pid=$(printf '%s' "$panelists_json" | jq -r ".[$pidx].id")
        model=$(printf '%s' "$panelists_json" | jq -r ".[$pidx].model")
        persona=$(printf '%s' "$panelists_json" | jq -r ".[$pidx].persona_path // \"\"")
        # Background each solicitation; write JSON output to a per-panelist file.
        (
            panel_solicit "$pid" "$model" "$persona" "$ctx_sanitized" \
                > "$solicit_dir/$pid.json" 2>"$solicit_dir/$pid.err" || true
        ) &
        pids+=($!)
    done
    # Wait for all background solicitations.
    for pp_pid in ${pids[@]+"${pids[@]}"}; do
        wait "$pp_pid" || true
    done

    # ---- 4. Aggregate views (BEFORE selection) ----------------------------
    # Read in panelist-config order (deterministic).
    local views_json="[]"
    for ((pidx=0; pidx<n_panelists; pidx++)); do
        pid=$(printf '%s' "$panelists_json" | jq -r ".[$pidx].id")
        if [[ -s "$solicit_dir/$pid.json" ]] && jq -e . "$solicit_dir/$pid.json" >/dev/null 2>&1; then
            views_json=$(printf '%s' "$views_json" | jq -c --slurpfile entry "$solicit_dir/$pid.json" '. + $entry')
        fi
    done

    # FR-L1-2: log panelist views BEFORE selection.
    panel_log_views "$decision_id" "$views_json" "$log_path" || {
        _panel_log "panel_invoke: failed to log panelist views"
        return 1
    }

    # ---- 5. Fallback matrix -----------------------------------------------
    local survivors_json
    survivors_json=$(printf '%s' "$views_json" | jq -c '[.[] | select(.error == null and .timed_out == false and .view != "")]')
    local n_survivors
    n_survivors=$(printf '%s' "$survivors_json" | jq 'length')
    local min_survivors="${LOA_PANEL_MIN_PANELISTS:-2}"

    if (( n_survivors == 0 )); then
        # All-fail
        panel_log_fallback "$decision_id" "all_fail" "$views_json" "$log_path" || true
        jq -nc \
            --arg d "$decision_id" \
            '{
                outcome:"FALLBACK",
                binding_view:null,
                selected_panelist_id:null,
                selection_seed:null,
                minority_dissent:[],
                audit_log_entry_id:("L1:panel.fallback:" + $d),
                diagnostic:"all panelists failed; queued for operator"
            }'
        return 0
    fi

    if (( n_survivors < min_survivors )); then
        # Tertiary unavailable / not enough survivors → FALLBACK
        panel_log_fallback "$decision_id" "tertiary_unavailable" "$views_json" "$log_path" || true
        jq -nc \
            --arg d "$decision_id" \
            --argjson n "$n_survivors" \
            '{
                outcome:"FALLBACK",
                binding_view:null,
                selected_panelist_id:null,
                selection_seed:null,
                minority_dissent:[],
                audit_log_entry_id:("L1:panel.fallback:" + $d),
                diagnostic:("only " + ($n | tostring) + " surviving panelists; below minimum")
            }'
        return 0
    fi

    # Determine fallback_path for the bind envelope when degraded.
    local fallback_path="null"
    if (( n_survivors < n_panelists )); then
        # Identify which kind of failure dominated.
        local n_timeout n_error
        n_timeout=$(printf '%s' "$views_json" | jq '[.[] | select(.timed_out == true)] | length')
        n_error=$(printf '%s' "$views_json" | jq '[.[] | select(.error != null and .timed_out == false)] | length')
        if (( n_timeout > 0 )); then
            fallback_path="timeout"
        elif (( n_error > 0 )); then
            fallback_path="api_failure"
        else
            fallback_path="tertiary_unavailable"
        fi
    fi

    # ---- 6. Selection ------------------------------------------------------
    local sel_json selected seed
    sel_json=$(panel_select "$survivors_json" "$decision_id" "$context_hash") || {
        _panel_log "panel_invoke: panel_select failed"
        return 1
    }
    selected=$(printf '%s' "$sel_json" | jq -r '.selected_panelist_id')
    seed=$(printf '%s' "$sel_json" | jq -r '.selection_seed')

    local binding_view minority
    binding_view=$(printf '%s' "$survivors_json" | jq -r ".[] | select(.id == \"$selected\") | .view")
    minority=$(printf '%s' "$survivors_json" | jq -c "[.[] | select(.id != \"$selected\") | {id, view}]")

    # ---- 7. Disagreement check (default no-op pass) -----------------------
    local disagreement_threshold="${LOA_PANEL_DISAGREEMENT_THRESHOLD:-0.5}"
    if ! panel_check_disagreement "$survivors_json" "$disagreement_threshold"; then
        # Operator-supplied fn flagged disagreement → queue, but still log.
        local diag_payload
        diag_payload=$(jq -nc --arg d "$decision_id" --argjson p "$views_json" \
            '{decision_id:$d, panelists:$p, route:"QUEUED_DISAGREE", reason:"panel_check_disagreement returned non-zero"}')
        audit_emit L1 panel.queued_disagree "$diag_payload" "$log_path" || true
        jq -nc \
            --arg d "$decision_id" \
            '{
                outcome:"FALLBACK",
                binding_view:null,
                selected_panelist_id:null,
                selection_seed:null,
                minority_dissent:[],
                audit_log_entry_id:("L1:panel.queued_disagree:" + $d),
                diagnostic:"panel views diverged beyond threshold; queued"
            }'
        return 0
    fi

    # ---- 8. Bind + return --------------------------------------------------
    LOA_PANEL_BIND_VIEW="$binding_view" \
    LOA_PANEL_BIND_PANELISTS="$views_json" \
    LOA_PANEL_BIND_FALLBACK_PATH="$fallback_path" \
    LOA_PANEL_BIND_CLASS="$decision_class" \
    LOA_PANEL_BIND_CTX_HASH="$context_hash" \
        panel_log_binding "$decision_id" "$selected" "$seed" "$minority" "$log_path" || {
            _panel_log "panel_invoke: failed to log binding"
            return 1
        }

    # Return JSON contract per SDD §5.3.1.
    jq -nc \
        --arg d "$decision_id" \
        --arg sel "$selected" \
        --arg seed "$seed" \
        --arg view "$binding_view" \
        --argjson minority "$minority" \
        '{
            outcome:"BOUND",
            binding_view:$view,
            selected_panelist_id:$sel,
            selection_seed:$seed,
            minority_dissent:$minority,
            audit_log_entry_id:("L1:panel.bind:" + $d),
            diagnostic:""
        }'
    return 0
}

# -----------------------------------------------------------------------------
# CLI dispatcher (supports the SDD §5.3.1 skill invocation pattern).
# -----------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        invoke)
            shift
            panel_invoke "$@"
            ;;
        select)
            shift
            panel_select "$@"
            ;;
        solicit)
            shift
            panel_solicit "$@"
            ;;
        check-disagreement)
            shift
            panel_check_disagreement "$@"
            ;;
        ""|--help|-h)
            cat <<'USAGE'
hitl-jury-panel-lib.sh — L1 jury-panel adjudication primitive

Usage (CLI):
  hitl-jury-panel-lib.sh invoke <decision_id> <decision_class> <context_hash> <panelists_yaml> <context_path>
  hitl-jury-panel-lib.sh select <panelists_json> <decision_id> <context_hash>
  hitl-jury-panel-lib.sh solicit <panelist_id> <model> <persona_path> <context_path>
  hitl-jury-panel-lib.sh check-disagreement <panelists_views_json> <threshold>

Usage (library):
  source .claude/scripts/lib/hitl-jury-panel-lib.sh
  panel_invoke <decision_id> <decision_class> <context_hash> <panelists_yaml> <context_path>

See SKILL.md (.claude/skills/hitl-jury-panel/SKILL.md) for full contract.
USAGE
            ;;
        *)
            echo "hitl-jury-panel-lib.sh: unknown subcommand '${1}'" >&2
            exit 2
            ;;
    esac
fi
