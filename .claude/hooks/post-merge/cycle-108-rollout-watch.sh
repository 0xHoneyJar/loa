#!/usr/bin/env bash
# =============================================================================
# cycle-108-rollout-watch.sh — sprint-4 T4.B
# =============================================================================
# SDD §20.2 step 3 (post-rollout 30-day watch).
#
# Fires on post-merge to main. Looks for executor-tier audit-failure envelopes
# in .run/model-invoke.jsonl within 30 days of the rollout-commit-SHA. On
# detection: emits an alert to stderr + writes a queue entry that the
# post-merge orchestrator promotes to an auto-revert PR.
#
# Rollout-commit-SHA: the merge SHA where `advisor_strategy.enabled` last
# flipped to `true`. Recorded in `.run/cycle-108-rollout-anchor` (one line:
# `<sha>\t<iso-ts>`); the hook is a no-op when the file is absent (cycle still
# in (c') state) OR the file's timestamp is older than 30 days.
#
# To install: post-merge-orchestrator.sh sources this script's
# `cycle108_run_rollout_watch` function and calls it in its phase loop.
# =============================================================================

set -uo pipefail

_LOA_C108_REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null || cd "$(dirname "$0")/../../../" && pwd)"
_LOA_C108_ANCHOR="$_LOA_C108_REPO_ROOT/.run/cycle-108-rollout-anchor"
_LOA_C108_LOG="$_LOA_C108_REPO_ROOT/.run/model-invoke.jsonl"
_LOA_C108_QUEUE="$_LOA_C108_REPO_ROOT/.run/cycle-108-rollout-revert-queue.jsonl"
_LOA_C108_WINDOW_DAYS="${LOA_C108_ROLLOUT_WATCH_DAYS:-30}"


cycle108_log() {
    printf '[cycle-108-rollout-watch] %s\n' "$*" >&2
}


cycle108_within_window() {
    local anchor_file="$1"
    local window_days="$2"
    [ -f "$anchor_file" ] || return 1
    local anchor_ts
    anchor_ts="$(awk -F'\t' '{print $2}' "$anchor_file" 2>/dev/null | head -1)"
    [ -n "$anchor_ts" ] || return 1
    local anchor_epoch now_epoch elapsed_days
    if command -v gdate >/dev/null 2>&1; then
        anchor_epoch="$(gdate -d "$anchor_ts" +%s 2>/dev/null)"
    else
        anchor_epoch="$(date -d "$anchor_ts" +%s 2>/dev/null || date -j -f '%Y-%m-%dT%H:%M:%SZ' "$anchor_ts" +%s 2>/dev/null)"
    fi
    [ -n "$anchor_epoch" ] || return 1
    now_epoch="$(date -u +%s)"
    elapsed_days=$(( (now_epoch - anchor_epoch) / 86400 ))
    [ "$elapsed_days" -le "$window_days" ]
}


cycle108_detect_executor_audit_failures() {
    # Scans .run/model-invoke.jsonl for envelopes within the watch window
    # whose payload.tier == "executor" AND models_failed length > 0 AND
    # operator_visible_warn == false (silent-degradation pattern from
    # cycle-102 vision-019 M1).
    local since_ts="$1"
    [ -f "$_LOA_C108_LOG" ] || return 1
    jq -c \
        --arg since "$since_ts" \
        'select(type == "object") | select(.ts_utc >= $since) |
         select((.payload.tier // "") == "executor") |
         select((.payload.models_failed // []) | length > 0) |
         select((.payload.operator_visible_warn // false) == false) |
         {ts: .ts_utc, model: (.payload.final_model_id // "unknown"), tier: .payload.tier, skill: (.payload.invocation_chain // [] | first // "unknown")}' \
        "$_LOA_C108_LOG" 2>/dev/null
}


cycle108_run_rollout_watch() {
    if [ ! -f "$_LOA_C108_ANCHOR" ]; then
        cycle108_log "no rollout anchor — cycle-108 still in substrate-validation; no-op"
        return 0
    fi
    if ! cycle108_within_window "$_LOA_C108_ANCHOR" "$_LOA_C108_WINDOW_DAYS"; then
        cycle108_log "watch window expired (${_LOA_C108_WINDOW_DAYS} days) — no-op"
        return 0
    fi
    local anchor_ts
    anchor_ts="$(awk -F'\t' '{print $2}' "$_LOA_C108_ANCHOR" 2>/dev/null | head -1)"
    cycle108_log "scanning .run/model-invoke.jsonl for executor-tier failures since $anchor_ts"

    local hits
    hits="$(cycle108_detect_executor_audit_failures "$anchor_ts")"
    if [ -z "$hits" ]; then
        cycle108_log "no executor-tier failures in window — OK"
        return 0
    fi

    cycle108_log "ALERT: executor-tier audit failures detected within ${_LOA_C108_WINDOW_DAYS}-day window. Queueing revert."
    printf '%s\n' "$hits" >> "$_LOA_C108_QUEUE"
    # The orchestrator promotes queue entries to revert PRs in its next phase.
    return 0
}


# Allow direct execution for ad-hoc invocation.
if [ "${BASH_SOURCE[0]:-$0}" = "${0}" ]; then
    cycle108_run_rollout_watch
    exit $?
fi
