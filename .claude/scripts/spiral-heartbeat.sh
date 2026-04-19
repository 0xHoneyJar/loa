#!/usr/bin/env bash
# =============================================================================
# spiral-heartbeat.sh — SIMSTIM heartbeat emitter (cycle-092 Sprint 4, #598)
# =============================================================================
# Version: 1.0.0
#
# Emits operator-facing [HEARTBEAT] and [INTENT] lines to dispatch.log on a
# configurable interval. Consumes Sprint 1's .phase-current as truth source,
# Sprint 3's dashboard-latest.json for cost totals, and dispatch.log for gate
# attempt / fix-iteration state. Does not write to any state files — pure
# observability surface.
#
# Sibling of RFC-062 (seed-seam editor-of-intent at cycle N→N+1 boundary):
# this script adds the IN-FLIGHT editor-of-intent so operators read intent
# DURING a cycle, not just at the seed seam.
#
# Usage (daemon mode):
#   spiral-heartbeat.sh --cycle-dir .run/cycles/cycle-092 [--interval 60] &
#
# Usage (library mode — source + call functions):
#   source spiral-heartbeat.sh
#   _emit_heartbeat "$cycle_dir"
#   _emit_intent "$cycle_dir"
#   _confidence_cue "$cycle_dir/dispatch.log"
#
# Env overrides:
#   SPIRAL_HEARTBEAT_INTERVAL_SEC  [60]  — emit interval, clamp [30, 300]
#   SPIRAL_HEARTBEAT_BUDGET_USD    [80]  — total budget for pace/display
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Prevent double-sourcing
if [[ "${_SPIRAL_HEARTBEAT_LOADED:-}" == "true" ]]; then
    return 0 2>/dev/null || exit 0
fi
_SPIRAL_HEARTBEAT_LOADED=true

# =============================================================================
# Phase verb mapping (per issue #598)
# =============================================================================

_heartbeat_phase_verb() {
    local phase="${1:-}"
    case "$phase" in
        DISCOVERY)                 echo "🔍 discovering" ;;
        ARCHITECTURE)              echo "🏛️ designing" ;;
        PLANNING)                  echo "📋 planning" ;;
        FLATLINE_PRD|FLATLINE_SDD|FLATLINE_SPRINT|FLATLINE) echo "⚔️ scoring" ;;
        IMPLEMENT|IMPLEMENTATION)  echo "🔨 implementing" ;;
        PRE_CHECK_SEED|PRE_CHECK_IMPL|PRE_CHECK_REVIEW|PRE_CHECK_IMPL_EVIDENCE)
                                   echo "⚙️ validating" ;;
        REVIEW)                    echo "👁️ reviewing" ;;
        AUDIT)                     echo "🛡️ auditing" ;;
        IMPL_FIX|*fix*)            echo "🔧 fixing" ;;
        BRIDGEBUILDER|BB_FIX_LOOP) echo "🌉 bridging" ;;
        *Circuit*|*recovered*)     echo "🚨 recovering" ;;
        PR_CREATION|*complete*)    echo "🚢 shipping" ;;
        *)                         echo "⚙️ preparing" ;;
    esac
}

# =============================================================================
# Phase baseline (seconds) — from sprint.md §Pace baselines
# =============================================================================

_heartbeat_phase_baseline_sec() {
    local phase="${1:-}"
    case "$phase" in
        DISCOVERY|ARCHITECTURE|PLANNING) echo "240" ;;     # 4 min
        FLATLINE*)                        echo "120" ;;     # 2 min
        IMPLEMENT|IMPLEMENTATION)         echo "1080" ;;    # 18 min
        REVIEW|AUDIT)                     echo "240" ;;     # 4 min
        IMPL_FIX|*fix*)                   echo "600" ;;     # 10 min
        *)                                echo "300" ;;     # 5 min default
    esac
}

# =============================================================================
# Pace classification — green/blue/yellow/red per issue #598 §Ops-correct colors
# =============================================================================

_heartbeat_pace() {
    local elapsed="${1:-0}"
    local baseline="${2:-300}"

    if [[ "$elapsed" -eq 0 ]]; then
        echo "advancing"
        return 0
    fi

    # 3× baseline → stuck
    if (( elapsed > baseline * 3 )); then
        echo "stuck"
    elif (( elapsed > baseline * 2 )); then
        echo "slow"
    else
        echo "on_pace"
    fi
}

# =============================================================================
# Confidence cue — parses dispatch.log tail for gate attempt / fix iter state
# =============================================================================
#
# Returns one of:
#   attempt_N_of_M         (Gate: X (attempt N/M))
#   attempt_N_of_M_last    (N == M, last chance)
#   iteration_N_of_M       (Review fix loop: iteration N/M)
#   iteration_N_of_M_last  (N == M)
#   steady                 (no attempt/iteration state detected)

_confidence_cue() {
    local dispatch_log="${1:-}"
    [[ -f "$dispatch_log" && -r "$dispatch_log" ]] || { echo "steady"; return 0; }

    local attempt fix_iter
    attempt=$(tail -200 "$dispatch_log" 2>/dev/null | \
        grep -oE 'Gate: [A-Z_]+ \(attempt [0-9]+/[0-9]+\)' | tail -1 | \
        grep -oE 'attempt [0-9]+/[0-9]+' || echo "")
    fix_iter=$(tail -200 "$dispatch_log" 2>/dev/null | \
        grep -oE 'Review fix loop: iteration [0-9]+/[0-9]+' | tail -1 | \
        grep -oE 'iteration [0-9]+/[0-9]+' || echo "")

    if [[ -n "$attempt" ]]; then
        local n m
        n=$(echo "$attempt" | grep -oE '^attempt [0-9]+' | grep -oE '[0-9]+')
        m=$(echo "$attempt" | grep -oE '[0-9]+$')
        if [[ "$n" == "$m" && "$m" -ge 3 ]]; then
            echo "attempt_${n}_of_${m}_last"
        else
            echo "attempt_${n}_of_${m}"
        fi
    elif [[ -n "$fix_iter" ]]; then
        local n m
        n=$(echo "$fix_iter" | grep -oE '^iteration [0-9]+' | grep -oE '[0-9]+')
        m=$(echo "$fix_iter" | grep -oE '[0-9]+$')
        if [[ "$n" == "$m" ]]; then
            echo "iteration_${n}_of_${m}_last"
        else
            echo "iteration_${n}_of_${m}"
        fi
    else
        echo "steady"
    fi
}

# =============================================================================
# Intent extraction — phase → source file → first meaningful line
# =============================================================================
#
# Per issue #598 §Proposal — 4 canonical sources:
#   IMPLEMENTATION/IMPL_FIX → engineer-feedback.md first CRITICAL-Blocking
#   REVIEW                  → static "checking amendment compliance"
#   AUDIT                   → auditor-sprint-feedback.md first `## ` heading
#   FLATLINE/PLANNING/ARCHITECTURE/DISCOVERY → static strings

_heartbeat_intent_source() {
    local phase="${1:-}"
    # cycle-092 Sprint 4 review F-4.2: anchor to $PROJECT_ROOT (set by
    # spiral-harness.sh's bootstrap.sh) so daemon works regardless of CWD.
    # Fall back to "." for library-mode callers that don't set PROJECT_ROOT.
    local root="${PROJECT_ROOT:-.}"
    case "$phase" in
        IMPLEMENT|IMPLEMENTATION|IMPL_FIX|*fix*)
            echo "$root/grimoires/loa/a2a/engineer-feedback.md" ;;
        AUDIT)
            echo "$root/grimoires/loa/a2a/auditor-sprint-feedback.md" ;;
        *)
            echo "" ;;   # static string below — no file source
    esac
}

_heartbeat_intent_text() {
    local phase="${1:-}"
    local source="${2:-}"

    case "$phase" in
        REVIEW)
            echo "checking amendment compliance against the implementation"
            return 0 ;;
        FLATLINE*)
            echo "3 models scoring plan together"
            return 0 ;;
        PLANNING)
            echo "breaking design into sprint tasks"
            return 0 ;;
        ARCHITECTURE)
            echo "writing system design"
            return 0 ;;
        DISCOVERY)
            echo "reading the seed, writing requirements"
            return 0 ;;
        PRE_CHECK_*)
            echo "validating phase inputs"
            return 0 ;;
        PR_CREATION)
            echo "creating draft PR"
            return 0 ;;
    esac

    # File-sourced: extract first relevant line
    if [[ -f "$source" && -r "$source" ]]; then
        local line=""
        case "$phase" in
            IMPLEMENT|IMPLEMENTATION|IMPL_FIX|*fix*)
                # engineer-feedback.md: find first CRITICAL-Blocking finding title
                line=$(awk '
                    /CRITICAL — Blocking/ { found=1; next }
                    found && /^### 1\./ { sub(/^### 1\. /, ""); print; exit }
                ' "$source" 2>/dev/null | head -c 90)
                ;;
            AUDIT)
                # auditor-sprint-feedback.md: first `## ` heading after document title
                line=$(awk '
                    /^## / && !first_done { sub(/^## /, ""); print; first_done=1; exit }
                ' "$source" 2>/dev/null | head -c 90)
                ;;
        esac
        if [[ -n "$line" ]]; then
            # Strip newlines + tabs per security note in sprint.md §Risks
            line="${line//$'\n'/ }"
            line="${line//$'\t'/ }"
            # cycle-092 Sprint 4 review F-4.1: strip embedded quotes + CR so
            # the emitted intent="..." log line stays parseable. Replacements
            # chosen to preserve meaning: " → ' (soft quote), CR → space.
            line="${line//\"/\'}"
            line="${line//$'\r'/ }"
            echo "$line"
            return 0
        fi
    fi

    # Fallback static text
    case "$phase" in
        IMPLEMENT|IMPLEMENTATION) echo "writing code per sprint plan" ;;
        IMPL_FIX|*fix*)           echo "addressing review findings" ;;
        AUDIT)                    echo "security + acceptance-criteria sweep" ;;
        *)                        echo "preparing next step" ;;
    esac
}

# =============================================================================
# Heartbeat emitter (11 keys per issue #598 §Proposal)
# =============================================================================
#
# Writes one `[HEARTBEAT <iso-ts>] key=value ...` line to dispatch.log with
# all 11 required keys. Reads phase from Sprint 1's .phase-current file
# (NOT dispatch.log grep — per sprint.md D.3 decision).
#
# Keys: phase phase_verb phase_elapsed_sec total_elapsed_sec cost_usd
#       budget_usd files ins del activity confidence pace

_emit_heartbeat() {
    local cycle_dir="${1:-}"
    [[ -z "$cycle_dir" || ! -d "$cycle_dir" ]] && return 1

    local phase_current="$cycle_dir/.phase-current"
    local dispatch_log="$cycle_dir/dispatch.log"
    local dashboard="$cycle_dir/dashboard-latest.json"

    # Read phase from .phase-current (Sprint 1 truth source)
    local phase start_ts_iso attempt fix_iter
    if [[ -f "$phase_current" ]]; then
        IFS=$'\t' read -r phase start_ts_iso attempt fix_iter < "$phase_current" 2>/dev/null || {
            phase="UNKNOWN"
            start_ts_iso=""
        }
    else
        phase="IDLE"
        start_ts_iso=""
    fi

    local ts_iso
    ts_iso=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Compute phase_elapsed_sec from start_ts in .phase-current
    local phase_elapsed_sec=0
    if [[ -n "$start_ts_iso" && "$start_ts_iso" != "-" ]]; then
        local start_epoch now_epoch
        start_epoch=$(date -u -d "$start_ts_iso" +%s 2>/dev/null || \
                      date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$start_ts_iso" +%s 2>/dev/null || \
                      echo 0)
        now_epoch=$(date +%s)
        [[ "$start_epoch" -gt 0 ]] && phase_elapsed_sec=$((now_epoch - start_epoch))
    fi

    # Total elapsed from dashboard-latest.json first_action_ts
    local total_elapsed_sec=0
    if [[ -f "$dashboard" ]]; then
        local first_ts
        first_ts=$(jq -r '.totals.first_action_ts // empty' "$dashboard" 2>/dev/null)
        if [[ -n "$first_ts" ]]; then
            local first_epoch now_epoch
            first_epoch=$(date -u -d "$first_ts" +%s 2>/dev/null || \
                          date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$first_ts" +%s 2>/dev/null || \
                          echo 0)
            now_epoch=$(date +%s)
            [[ "$first_epoch" -gt 0 ]] && total_elapsed_sec=$((now_epoch - first_epoch))
        fi
    fi

    # Cost and budget
    local cost_usd="0.00" budget_usd="${SPIRAL_HEARTBEAT_BUDGET_USD:-80}"
    if [[ -f "$dashboard" ]]; then
        cost_usd=$(jq -r '.totals.cost_usd // 0' "$dashboard" 2>/dev/null)
        [[ -z "$cost_usd" || "$cost_usd" == "null" ]] && cost_usd="0.00"
    fi

    # Git diff stats (best-effort — empty if git unavailable or not in a repo)
    local files=0 ins=0 del=0
    if command -v git >/dev/null 2>&1 && git rev-parse --show-toplevel >/dev/null 2>&1; then
        local diff_stat
        diff_stat=$(git diff --shortstat main...HEAD 2>/dev/null | head -1 || echo "")
        if [[ -n "$diff_stat" ]]; then
            files=$(echo "$diff_stat" | grep -oE '[0-9]+ files?' | grep -oE '[0-9]+' | head -1 || echo 0)
            ins=$(echo "$diff_stat" | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+' | head -1 || echo 0)
            del=$(echo "$diff_stat" | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+' | head -1 || echo 0)
        fi
    fi

    # Activity: recent write detected via .phase-current mtime
    local activity="quiet"
    if [[ -f "$phase_current" ]]; then
        local mtime now age
        mtime=$(stat -c %Y "$phase_current" 2>/dev/null || \
                stat -f %m "$phase_current" 2>/dev/null || echo 0)
        now=$(date +%s)
        age=$((now - mtime))
        (( age < 60 )) && activity="writing"
    fi

    # Confidence cue
    local confidence
    confidence=$(_confidence_cue "$dispatch_log")

    # Pace
    local baseline
    baseline=$(_heartbeat_phase_baseline_sec "$phase")
    local pace
    pace=$(_heartbeat_pace "$phase_elapsed_sec" "$baseline")

    # Phase verb
    local phase_verb
    phase_verb=$(_heartbeat_phase_verb "$phase")

    # Emit the heartbeat line to dispatch.log (best-effort)
    printf '[HEARTBEAT %s] phase=%s phase_verb=%s phase_elapsed_sec=%d total_elapsed_sec=%d cost_usd=%s budget_usd=%s files=%d ins=%d del=%d activity=%s confidence=%s pace=%s\n' \
        "$ts_iso" "$phase" "$phase_verb" "$phase_elapsed_sec" "$total_elapsed_sec" \
        "$cost_usd" "$budget_usd" "$files" "$ins" "$del" "$activity" \
        "$confidence" "$pace" \
        >> "$dispatch_log" 2>/dev/null || true
}

# =============================================================================
# Intent emitter (fires on phase change only)
# =============================================================================
#
# Writes `[INTENT <iso-ts>] phase=X intent="..." source=Y` to dispatch.log
# ONLY when phase has changed since last emission. Tracks last-emitted phase
# in $cycle_dir/.heartbeat-state (single-line file with current phase).

_emit_intent() {
    local cycle_dir="${1:-}"
    [[ -z "$cycle_dir" || ! -d "$cycle_dir" ]] && return 1

    local phase_current="$cycle_dir/.phase-current"
    local dispatch_log="$cycle_dir/dispatch.log"
    local state_file="$cycle_dir/.heartbeat-state"

    [[ -f "$phase_current" ]] || return 0

    local phase
    phase=$(awk -F'\t' '{print $1; exit}' "$phase_current" 2>/dev/null)
    [[ -z "$phase" ]] && return 0

    # Check if phase changed since last emission
    local last_phase=""
    [[ -f "$state_file" ]] && last_phase=$(cat "$state_file" 2>/dev/null)
    [[ "$phase" == "$last_phase" ]] && return 0   # no change → no emit

    # Record the new phase before emitting (avoid race on rapid phase flips)
    echo "$phase" > "$state_file" 2>/dev/null || true

    local source intent ts_iso
    source=$(_heartbeat_intent_source "$phase")
    intent=$(_heartbeat_intent_text "$phase" "$source")
    ts_iso=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Emit (display source=none when text is static)
    printf '[INTENT %s] phase=%s intent="%s" source=%s\n' \
        "$ts_iso" "$phase" "$intent" "${source:-none}" \
        >> "$dispatch_log" 2>/dev/null || true
}

# =============================================================================
# Daemon mode — backgrounded while-loop
# =============================================================================

_run_heartbeat_daemon() {
    local cycle_dir="${1:-}"
    local interval_sec="${SPIRAL_HEARTBEAT_INTERVAL_SEC:-60}"

    [[ -z "$cycle_dir" || ! -d "$cycle_dir" ]] && return 1

    # Clamp interval
    if ! [[ "$interval_sec" =~ ^[0-9]+$ ]]; then
        interval_sec=60
    fi
    (( interval_sec < 30 )) && interval_sec=30
    (( interval_sec > 300 )) && interval_sec=300

    # Signal handling: SIGTERM/SIGINT → clean exit via sleep-child kill
    local SLEEP_PID=""
    trap 'kill $SLEEP_PID 2>/dev/null; exit 0' TERM INT

    while true; do
        # Emit intent on phase change (before sleep so first emit is fast)
        _emit_intent "$cycle_dir" 2>/dev/null || true

        # Signal-responsive sleep
        sleep "$interval_sec" &
        SLEEP_PID=$!
        wait "$SLEEP_PID" 2>/dev/null || true
        SLEEP_PID=""

        # After sleep: if .phase-current gone, harness exited — stop
        if [[ ! -f "$cycle_dir/.phase-current" ]]; then
            exit 0
        fi

        _emit_heartbeat "$cycle_dir" 2>/dev/null || true
    done
}

# =============================================================================
# CLI entry point (only runs when script is invoked directly, not sourced)
# =============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    cycle_dir=""
    interval=""
    run_mode="daemon"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --cycle-dir) cycle_dir="$2"; shift 2 ;;
            --interval)  interval="$2"; shift 2 ;;
            --once)      run_mode="once"; shift ;;
            -h|--help)
                cat <<EOF
spiral-heartbeat.sh — SIMSTIM heartbeat emitter (cycle-092 Sprint 4, #598)

Usage:
  spiral-heartbeat.sh --cycle-dir <path> [--interval SEC] [--once]

Modes:
  (default)    Daemon — backgrounded loop emitting heartbeats + intents
  --once       Single emission — one heartbeat + one intent (for testing)

Env:
  SPIRAL_HEARTBEAT_INTERVAL_SEC  [60]  — daemon interval, clamp [30,300]
  SPIRAL_HEARTBEAT_BUDGET_USD    [80]  — budget shown in heartbeat

Output: dispatch.log inside cycle-dir (Sprint 1 path convention)
EOF
                exit 0
                ;;
            *) echo "Unknown arg: $1" >&2; exit 2 ;;
        esac
    done

    [[ -z "$cycle_dir" ]] && { echo "Missing --cycle-dir" >&2; exit 2; }

    [[ -n "$interval" ]] && export SPIRAL_HEARTBEAT_INTERVAL_SEC="$interval"

    if [[ "$run_mode" == "once" ]]; then
        _emit_intent "$cycle_dir"
        _emit_heartbeat "$cycle_dir"
    else
        _run_heartbeat_daemon "$cycle_dir"
    fi
fi
