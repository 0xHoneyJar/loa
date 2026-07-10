#!/usr/bin/env bash
# =============================================================================
# stop-input-probe.sh — DIAGNOSTIC Stop-input dumper (default-OFF, UNREGISTERED)
# =============================================================================
# Part of: cycle-117 session-economy (bd-c117-a-session-cap-x04j, issue #1177 A).
#
# Answers the issue's open question empirically: does Stop / SubagentStop hook
# input EVER carry the raw session-limit error text in any field? Static
# investigation found no such field, and no Claude Code hook schema documents
# one — so we instrument a throwaway probe and read a real cap event's dump.
#
# Gated by LOA_STOP_INPUT_PROBE=1 (env-var gate, matching every other opt-in
# hook in this repo). Ships UNREGISTERED: an operator merges it into their local
# settings.local.json Stop matcher for the duration of ONE cap-hitting session,
# then removes it. Do NOT add it to settings.json / settings.hooks.json.
#
# Diagnostic-only: appends one JSON line per Stop to .run/stop-input-probe.jsonl
# (plain >>, no atomicity needed) and ALWAYS exits 0 — it must never alter the
# Stop decision or trap the agent. After the question is answered this file is
# either deleted or promoted into the real capture path (follow-up bead).
# =============================================================================

set -uo pipefail

# Gate FIRST — an unset/0 flag is a complete no-op (no file, no dir creation).
[[ "${LOA_STOP_INPUT_PROBE:-0}" == "1" ]] || exit 0

PROJECT_ROOT="${PROJECT_ROOT:-$PWD}"
RUN_DIR="${PROJECT_ROOT}/.run"
mkdir -p "$RUN_DIR" 2>/dev/null || true
PROBE_LOG="${RUN_DIR}/stop-input-probe.jsonl"

STOP_INPUT=""
IFS= read -rd '' STOP_INPUT || true

TZ=UTC0 printf -v _ts '%(%Y-%m-%dT%H:%M:%SZ)T' -1
# Store the raw stdin as a JSON string (robust — the probe does not assume the
# input is valid JSON). jq -Rs slurps stdin into one escaped string.
_encoded="$(printf '%s' "$STOP_INPUT" | jq -Rs . 2>/dev/null || printf '""')"
printf '{"ts":"%s","stop_input":%s}\n' "$_ts" "$_encoded" >> "$PROBE_LOG" 2>/dev/null || true

exit 0
