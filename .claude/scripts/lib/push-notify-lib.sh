#!/usr/bin/env bash
# =============================================================================
# push-notify-lib.sh — operator-configurable, best-effort external push channel
# =============================================================================
# Part of: cycle-117 session-economy (bd-c117-c-push-gate-eld2, issue #1177 C).
#
# Shared dispatch for the `notifications.push_command` config surface. Two real
# consumers this cycle: the Stop-hook push-at-gate (item C) and the degraded-
# gate paging (item D, bd-c117-d-degraded-band-zodl). Both fire an operator-
# owned external command as a side channel — this is NOT the Claude Code
# `PushNotification` tool (unreachable from a standalone process), it is the
# Spiral `phase_complete_hook` pattern finally wired.
#
# TRUST MODEL: `.loa.config.yaml` is operator-owned/trusted input, not agent-
# or PR-controlled. `push_command.command` is executed via `bash -c` — the same
# trust posture as the (previously inert) Spiral schema, but this is the FIRST
# config value in the repo that is actually EXECUTED. No new attack surface
# beyond what an operator could already run by hand.
#
# Sourceable with no side effects. Every function ALWAYS returns 0 — a push
# channel must never change a caller's exit code or fail its control flow.
#
# Dedup is the CALLER's responsibility — this lib never records "already sent".
#
# API:
#   push_notify_active            -> 0 iff enabled==true AND command non-empty
#                                    (loads config into PUSH_* globals as a
#                                    side effect; safe to call before a caller
#                                    decides whether to burn a dedup slot)
#   push_notify <msg> [src] [state] [id]
#                                 -> best-effort dispatch; always returns 0
#
# Config keys (all optional, fail-soft to inert defaults):
#   notifications.push_command.enabled     (bool,   default false)
#   notifications.push_command.command     (string, default "")
#   notifications.push_command.timeout_sec (int,    default 5)
#
# Env vars exported to the command: LOA_PUSH_MESSAGE / LOA_PUSH_SOURCE /
# LOA_PUSH_STATE / LOA_PUSH_ID. Messages are truncated to 200 chars.
# =============================================================================

# Config file, relative to CWD (project root). Overridable for tests.
: "${LOA_PUSH_CONFIG:=.loa.config.yaml}"

# Load config into PUSH_* globals. Fail-soft: no yq / no file => inert defaults.
_push_load_config() {
  PUSH_ENABLED="false"
  PUSH_COMMAND=""
  PUSH_TIMEOUT="5"
  [[ -f "$LOA_PUSH_CONFIG" ]] || return 0
  command -v yq >/dev/null 2>&1 || return 0
  PUSH_ENABLED="$(yq eval '.notifications.push_command.enabled // false' "$LOA_PUSH_CONFIG" 2>/dev/null || echo false)"
  PUSH_COMMAND="$(yq eval '.notifications.push_command.command // ""' "$LOA_PUSH_CONFIG" 2>/dev/null || echo "")"
  PUSH_TIMEOUT="$(yq eval '.notifications.push_command.timeout_sec // 5' "$LOA_PUSH_CONFIG" 2>/dev/null || echo 5)"
  # yq renders an absent scalar under `// ""` as the literal string "null" only
  # when the key exists and is null; normalize both to empty.
  [[ "$PUSH_COMMAND" == "null" ]] && PUSH_COMMAND=""
  return 0
}

# True (0) iff a real push would fire. Loads config as a side effect.
push_notify_active() {
  _push_load_config
  [[ "$PUSH_ENABLED" == "true" && -n "$PUSH_COMMAND" ]]
}

# Best-effort dispatch. Always returns 0.
push_notify() {
  local msg="${1:-}" source="${2:-}" state="${3:-}" id="${4:-}"
  # Load config if a caller has not already (idempotent — PUSH_COMMAND is
  # always set after a load, even when empty, so +x distinguishes loaded).
  [[ -n "${PUSH_COMMAND+x}" ]] || _push_load_config
  [[ "$PUSH_ENABLED" == "true" && -n "$PUSH_COMMAND" ]] || return 0

  msg="${msg:0:200}"
  export LOA_PUSH_MESSAGE="$msg" LOA_PUSH_SOURCE="$source" LOA_PUSH_STATE="$state" LOA_PUSH_ID="$id"

  local to="${PUSH_TIMEOUT:-5}"
  [[ "$to" =~ ^[0-9]+$ ]] || to=5

  if ! timeout "$to" bash -c "$PUSH_COMMAND" </dev/null >/dev/null 2>&1; then
    # Best-effort audit note on failure; never let this fail the caller.
    {
      local ts note
      ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
      note="$(jq -cn --arg ts "$ts" --arg src "$source" --arg st "$state" --arg id "$id" \
        '{ts:$ts,hook:"push-notify",action:"push_command_failed",source:$src,state:$st,id:$id}' 2>/dev/null)"
      [[ -n "$note" ]] && printf '%s\n' "$note" >> .run/audit.jsonl 2>/dev/null
    } 2>/dev/null || true
  fi
  return 0
}
