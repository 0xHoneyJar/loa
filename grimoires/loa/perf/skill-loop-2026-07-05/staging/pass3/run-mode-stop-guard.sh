#!/usr/bin/env bash
# =============================================================================
# Stop Hook — Run Mode Guard
# =============================================================================
# Detects active autonomous runs and injects context reminder before stopping.
# Uses stdout JSON decision field (soft block, not hard block).
#
# WHY soft block (JSON decision) not hard block (exit 2): A hard block on
# the Stop event would make it impossible to gracefully halt a malfunctioning
# agent. The soft block provides context ("Run mode is active") and lets the
# agent decide whether to continue or stop. This preserves the human's ability
# to Ctrl+C as the ultimate override — the agent can be informed, but never
# trapped. (cf. Unix SIGTERM vs SIGKILL: always leave an escape hatch)
#
# WHY no set -euo pipefail: Same rationale as block-destructive-bash.sh —
# if jq fails to parse the state file (corrupted JSON, missing field), the
# hook must exit 0 (allow stop), not crash. A crashing stop guard would
# prevent the agent from ever stopping, which is worse than the risk it
# prevents. (Source: bridge-20260213-c011he iter-1 HIGH-1 principle)
#
# WHY check multiple state files: Each autonomous mode (sprint-plan, bridge,
# simstim) has its own state file. We check all three because they can be
# active independently. The first match triggers the soft block with
# mode-specific context.
#
# Checks:
#   1. .run/sprint-plan-state.json — state=RUNNING
#   2. .run/bridge-state.json — state=ITERATING or FINALIZING
#   3. .run/simstim-state.json — state=RUNNING, phase=implementation
#
# perf pass-2 (2026-07-05, skill-loop): fork/exec reduction — stdin is read
# with the read builtin; the four soft-block heredoc `cat`s are printf
# builtins with byte-identical output.
#
# perf pass-3 (2026-07-05, skill-loop): jq single-pass consolidation — the
# 1-3 stdin jq spawns + 2 jq spawns per existing state file (7 total in the
# idle steady state) collapse into ONE jq invocation that receives stdin as
# --arg and each existing state file as --rawfile, and emits every decision
# field NUL-delimited. Isomorphism notes:
#   - Fields are NUL-delimited ("[0] | implode" builds the NUL string; no
#     escape literal appears in this file). State/id strings are read from
#     untrusted-shape files and can contain tabs/newlines; @tsv would
#     rewrite those bytes. Embedded JSON NUL escapes (backslash-u-0000) are
#     stripped via string division, and trailing newlines are stripped from
#     every field — byte-identical to the old $() command-substitution
#     NUL-dropping + trailing-newline-stripping (minus bash's cosmetic
#     warning). The strip is decision-relevant: a state value rendering as
#     "RUNNING\n" must still soft-block, exactly as the old $() capture did.
#   - Every per-field expression is try-wrapped, replicating each old
#     `jq ... || echo <default>` fallback INDEPENDENTLY: a corrupt stdin
#     cannot mask state-file checks and vice versa (the old code had the
#     same independence because every field had its own jq spawn).
#   - stdin is parsed with `fromjson` (single JSON document). Multi-document
#     stdin streams made every old bg-field multi-line -> the numeric guards
#     rejected them -> bg branch skipped; fromjson fails on such streams ->
#     defaults -> same skip. Malformed stdin: old bg_count fell back to "0"
#     (skip), state checks still ran — identical here.
#   - State files that do not exist cost no spawn and produce the same
#     non-blocking defaults as the old `[[ -f ]]`-gated skips. A state file
#     that is valid JSON but a non-string scalar renders via tostring
#     (identical to the old jq -r for scalars; containers would render
#     compact-vs-pretty, but state/phase/current are strings or null by the
#     framework's write contract).
#   - Nothing to parse at all (empty stdin + no state files) exits with
#     zero spawns.
#
# Registered in settings.hooks.json as Stop matcher: ""
# Part of Loa Harness Engineering (cycle-011, issue #297)
# Source: Trail of Bits Stop hook pattern

# ---------------------------------------------------------------------------
# cycle-114 FR-5: background-task / scheduled-cron awareness
#
# Stop / SubagentStop input (Claude Code 2.1.145+) carries `background_tasks`
# and `session_crons`. Live background tasks must not be silently orphaned by
# a Stop, so soft-block (decision:block) when any background task is still
# running. `session_crons` are surfaced for context but do NOT block on their
# own (they are designed to outlive a session). Fail-open: malformed/absent
# stdin or a missing jq → allow the stop (never crash a Stop guard).
# ---------------------------------------------------------------------------
STOP_INPUT=""
IFS= read -rd '' STOP_INPUT || true

SPRINT_STATE_FILE=".run/sprint-plan-state.json"
BRIDGE_STATE_FILE=".run/bridge-state.json"
SIMSTIM_STATE_FILE=".run/simstim-state.json"

# Fast path: nothing to inspect — allow the stop without spawning anything.
if [[ -z "$STOP_INPUT" && ! -f "$SPRINT_STATE_FILE" && ! -f "$BRIDGE_STATE_FILE" && ! -f "$SIMSTIM_STATE_FILE" ]]; then
  exit 0
fi

# ONE jq extracts every decision field (see pass-3 header note).
_sg_args=()
if [[ -f "$SPRINT_STATE_FILE" ]]; then _sg_args+=(--rawfile s1 "$SPRINT_STATE_FILE"); else _sg_args+=(--arg s1 ""); fi
if [[ -f "$BRIDGE_STATE_FILE" ]]; then _sg_args+=(--rawfile s2 "$BRIDGE_STATE_FILE"); else _sg_args+=(--arg s2 ""); fi
if [[ -f "$SIMSTIM_STATE_FILE" ]]; then _sg_args+=(--rawfile s3 "$SIMSTIM_STATE_FILE"); else _sg_args+=(--arg s3 ""); fi

mapfile -d '' -t _sg < <(
  jq -nj --arg stop "$STOP_INPUT" "${_sg_args[@]}" '
    def denul($z): . / $z | join("");
    def sval: if type == "string" then . else tostring end;
    ([0] | implode) as $z |
    ($stop | try fromjson catch null) as $d |
    ($s1 | try fromjson catch null) as $j1 |
    ($s2 | try fromjson catch null) as $j2 |
    ($s3 | try fromjson catch null) as $j3 |
    [ ($d  | try ((.background_tasks // []) | length | tostring) catch "0"),
      ($d  | try ([.background_tasks[]? | (.id // .task_id // .)] | map(tostring) | join(", ")) catch ""),
      ($d  | try ((.session_crons // []) | length | tostring) catch "0"),
      ($j1 | try ((.state // "UNKNOWN") | sval) catch "UNKNOWN"),
      ($j1 | try ((.sprints.current // "null") | sval) catch "null"),
      ($j2 | try ((.state // "UNKNOWN") | sval) catch "UNKNOWN"),
      ($j2 | try ((.current_iteration // 0) | sval) catch "0"),
      ($j3 | try ((.state // "UNKNOWN") | sval) catch "UNKNOWN"),
      ($j3 | try ((.phase // "unknown") | sval) catch "unknown")
    ] | map(denul($z) | sub("\n+$"; "")) | join($z) + $z
  ' 2>/dev/null
)
if [[ "${#_sg[@]}" -ne 9 ]]; then
  # jq missing or catastrophic failure — a Stop guard must fail open.
  exit 0
fi
bg_count="${_sg[0]}"
bg_ids="${_sg[1]}"
cron_count="${_sg[2]}"
state="${_sg[3]}"
current="${_sg[4]}"
bridge_state="${_sg[5]}"
iteration="${_sg[6]}"
simstim_state="${_sg[7]}"
phase="${_sg[8]}"

if [[ "${bg_count:-0}" =~ ^[0-9]+$ ]] && [[ "${bg_count:-0}" -gt 0 ]]; then
  cron_note=""
  [[ "${cron_count:-0}" =~ ^[0-9]+$ ]] && [[ "${cron_count:-0}" -gt 0 ]] && cron_note=" (${cron_count} scheduled cron(s) will persist beyond this session)"
  printf '%s\n' "{\"decision\": \"block\", \"reason\": \"${bg_count} background task(s) still running: [${bg_ids}]${cron_note}. Cancel them via TaskStop <id>, or wait for completion before stopping — background agents left running may be orphaned.\"}"
  exit 0
fi

# ---------------------------------------------------------------------------
# Check sprint-plan state
# ---------------------------------------------------------------------------
if [[ "$state" == "RUNNING" && "$current" != "null" ]]; then
  printf '%s\n' "{\"decision\": \"block\", \"reason\": \"Run mode is active (state=RUNNING, sprint=${current}). Verify all acceptance criteria are met before stopping. Check .run/sprint-plan-state.json for sprint status.\"}"
  exit 0
fi

# ---------------------------------------------------------------------------
# Check bridge state
# ---------------------------------------------------------------------------
if [[ "$bridge_state" == "ITERATING" || "$bridge_state" == "FINALIZING" ]]; then
  printf '%s\n' "{\"decision\": \"block\", \"reason\": \"Bridge mode is active (state=${bridge_state}, iteration=${iteration}). Complete the current bridge iteration before stopping. Check .run/bridge-state.json for bridge status.\"}"
  exit 0
fi

# ---------------------------------------------------------------------------
# Check simstim state
# ---------------------------------------------------------------------------
if [[ "$simstim_state" == "RUNNING" && "$phase" == "implementation" ]]; then
  printf '%s\n' "{\"decision\": \"block\", \"reason\": \"Simstim implementation phase is active (state=RUNNING, phase=${phase}). Complete or halt the current simstim workflow before stopping.\"}"
  exit 0
fi

# No active runs — allow stop
exit 0
