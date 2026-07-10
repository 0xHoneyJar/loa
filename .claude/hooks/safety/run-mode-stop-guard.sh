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

# ---------------------------------------------------------------------------
# cycle-117 item C: push-at-gate side channel (bd-c117-c-push-gate-eld2)
#
# When this guard reaches its "no active runs — allow stop" fallthrough, it
# has observed a terminal gate: a Stop while a run/bridge/simstim state file
# holds a TERMINAL state (sprint JACKED_OUT/READY_FOR_HITL/HALTED; bridge
# JACKED_OUT/HALTED — bridge has no READY_FOR_HITL state; simstim COMPLETED/
# AWAITING_HITL/HALTED). At exactly that moment it fires an operator-
# configurable, best-effort external push command ONCE per distinct terminal
# transition, so an operator can be paged when an autonomous run needs them.
#
# WHY side-channel only: the push is dispatched via push-notify-lib.sh with
# all of the operator command's stdio redirected to /dev/null. It NEVER writes
# to this hook's stdout and NEVER changes its exit code — the block/allow
# contract above is untouched. A failed or slow command cannot trap the agent.
#
# WHY it sits AFTER every block-check and BEFORE the final `exit 0`: placement
# is load-bearing. It only runs once bg-tasks / sprint-RUNNING /
# bridge-ITERATING-FINALIZING / simstim-RUNNING-implementation have all failed
# to match, so "never push while blocking" is structural, not a condition to
# get wrong.
#
# SPAWN COST: the hot idle/active paths are untouched. The terminal-candidate
# test is pure string comparison; if no candidate is terminal it exits before
# sourcing the lib or reading config, so idle/RUNNING/ITERATING Stops pay zero
# extra forks. Only a genuine terminal Stop pays the config read, and only an
# operator who opted in (enabled+command) pays the dispatch.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# cycle-117 item A: session-cap zombie exemption (bd-c117-a-session-cap-x04j)
#
# A background teammate stuck behind an exhausted Claude session cap can never
# respond to TaskStop/SendMessage, so it stays listed in `background_tasks`
# forever and the bg-task soft-block below traps every Stop attempt — a
# deadlock. When an UNEXPIRED .run/session-limit-state.json is present (the
# capture marker from session-limit-capture.sh, reset time not yet reached),
# the bg-task block is swapped for ONE loud stderr advisory and falls through
# to the remaining checks. Freshness (now < reset_at_epoch) is computed inside
# the SAME single jq call via jq's builtin `now` — ZERO extra process spawns,
# preserving the skill-loop spawn-elimination discipline on this file. A
# malformed/expired/absent marker yields exempt=false → today's block is kept
# (fail-open to the existing deadlock guard).
# ---------------------------------------------------------------------------
STOP_INPUT=""
IFS= read -rd '' STOP_INPUT || true

SPRINT_STATE_FILE=".run/sprint-plan-state.json"
BRIDGE_STATE_FILE=".run/bridge-state.json"
SIMSTIM_STATE_FILE=".run/simstim-state.json"
SESSION_LIMIT_STATE_FILE=".run/session-limit-state.json"

# Fast path: nothing to inspect — allow the stop without spawning anything.
# (A session-limit marker alone, with no stdin and no run state, has nothing to
# exempt: bg-task exemption only matters when stdin carries background_tasks.)
if [[ -z "$STOP_INPUT" && ! -f "$SPRINT_STATE_FILE" && ! -f "$BRIDGE_STATE_FILE" && ! -f "$SIMSTIM_STATE_FILE" ]]; then
  exit 0
fi

# ONE jq extracts every decision field (see pass-3 header note).
_sg_args=()
if [[ -f "$SPRINT_STATE_FILE" ]]; then _sg_args+=(--rawfile s1 "$SPRINT_STATE_FILE"); else _sg_args+=(--arg s1 ""); fi
if [[ -f "$BRIDGE_STATE_FILE" ]]; then _sg_args+=(--rawfile s2 "$BRIDGE_STATE_FILE"); else _sg_args+=(--arg s2 ""); fi
if [[ -f "$SIMSTIM_STATE_FILE" ]]; then _sg_args+=(--rawfile s3 "$SIMSTIM_STATE_FILE"); else _sg_args+=(--arg s3 ""); fi
if [[ -f "$SESSION_LIMIT_STATE_FILE" ]]; then _sg_args+=(--rawfile s4 "$SESSION_LIMIT_STATE_FILE"); else _sg_args+=(--arg s4 ""); fi

mapfile -d '' -t _sg < <(
  jq -nj --arg stop "$STOP_INPUT" "${_sg_args[@]}" '
    def denul($z): . / $z | join("");
    def sval: if type == "string" then . else tostring end;
    ([0] | implode) as $z |
    ($stop | try fromjson catch null) as $d |
    ($s1 | try fromjson catch null) as $j1 |
    ($s2 | try fromjson catch null) as $j2 |
    ($s3 | try fromjson catch null) as $j3 |
    ($s4 | try fromjson catch null) as $j4 |
    [ ($d  | try ((.background_tasks // []) | length | tostring) catch "0"),
      ($d  | try ([.background_tasks[]? | (.id // .task_id // .)] | map(tostring) | join(", ")) catch ""),
      ($d  | try ((.session_crons // []) | length | tostring) catch "0"),
      ($j1 | try ((.state // "UNKNOWN") | sval) catch "UNKNOWN"),
      ($j1 | try ((.sprints.current // "null") | sval) catch "null"),
      ($j2 | try ((.state // "UNKNOWN") | sval) catch "UNKNOWN"),
      ($j2 | try ((.current_iteration // 0) | sval) catch "0"),
      ($j3 | try ((.state // "UNKNOWN") | sval) catch "UNKNOWN"),
      ($j3 | try ((.phase // "unknown") | sval) catch "unknown"),
      ($j1 | try ((.timestamps.last_activity // "") | sval) catch ""),
      ($j2 | try ((.timestamps.last_activity // "") | sval) catch ""),
      ($j3 | try ((.timestamps.last_activity // .completed_at // "") | sval) catch ""),
      ($j4 | try (if . == null then "false"
                  else ((.reset_at_epoch // 0) as $r
                        | if (($r | type) == "number") and ($r > 0) and (now < $r)
                          then "true" else "false" end)
                  end) catch "false")
    ] | map(denul($z) | sub("\n+$"; "")) | join($z) + $z
  ' 2>/dev/null
)
if [[ "${#_sg[@]}" -ne 13 ]]; then
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
sprint_ts="${_sg[9]}"
bridge_ts="${_sg[10]}"
simstim_ts="${_sg[11]}"
session_limit_exempt="${_sg[12]}"

if [[ "${bg_count:-0}" =~ ^[0-9]+$ ]] && [[ "${bg_count:-0}" -gt 0 ]]; then
  if [[ "$session_limit_exempt" == "true" ]]; then
    # cycle-117 item A: an unexpired session-cap marker is present, so these
    # background tasks are presumed quota-zombied and cannot be stopped by the
    # agent. Emit ONE loud advisory to stderr (stdout stays clean → no decision
    # block) and fall through to the sprint/bridge/simstim checks below.
    # loa:shortcut: all-or-nothing exemption while the marker is unexpired — the
    # Stop input schema carries no per-task last-activity timestamp, so we
    # cannot filter to only the zombied tasks. Upgrade trigger: if Claude Code
    # adds a per-task timestamp to background_tasks[], exempt only tasks whose
    # last activity predates the marker's hit_at instead of exempting all.
    printf '%s\n' "[session-limit-active] ${bg_count} background task(s) presumed quota-zombied (.run/session-limit-state.json present, reset not yet reached) — NOT blocking stop; verify manually: [${bg_ids}]" >&2
  else
    cron_note=""
    [[ "${cron_count:-0}" =~ ^[0-9]+$ ]] && [[ "${cron_count:-0}" -gt 0 ]] && cron_note=" (${cron_count} scheduled cron(s) will persist beyond this session)"
    printf '%s\n' "{\"decision\": \"block\", \"reason\": \"${bg_count} background task(s) still running: [${bg_ids}]${cron_note}. Cancel them via TaskStop <id>, or wait for completion before stopping — background agents left running may be orphaned.\"}"
    exit 0
  fi
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

# ---------------------------------------------------------------------------
# cycle-117 item C: push-at-gate side channel (see header). Runs ONLY here,
# after every block-check has fallen through. Never touches stdout/exit code.
# ---------------------------------------------------------------------------
# Per-source terminal fingerprints (pure string compares — no forks). A
# candidate is non-empty only when that source is in a TERMINAL state.
_push_sprint_cand=""
case "$state" in JACKED_OUT|READY_FOR_HITL|HALTED) _push_sprint_cand="${state}:${current}:${sprint_ts}" ;; esac
_push_bridge_cand=""
case "$bridge_state" in JACKED_OUT|HALTED) _push_bridge_cand="${bridge_state}:${iteration}:${bridge_ts}" ;; esac
_push_simstim_cand=""
case "$simstim_state" in COMPLETED|AWAITING_HITL|HALTED) _push_simstim_cand="${simstim_state}:${phase}:${simstim_ts}" ;; esac

if [[ -n "$_push_sprint_cand" || -n "$_push_bridge_cand" || -n "$_push_simstim_cand" ]]; then
  _push_lib="$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib/push-notify-lib.sh"
  if [[ -f "$_push_lib" ]]; then
    # shellcheck source=/dev/null
    . "$_push_lib"
    # Config gate BEFORE any dedup slot is burned: disabled/empty command ->
    # silent no-op, marker file untouched (AC row 3).
    if push_notify_active; then
      _push_marker=".run/push-last-state.json"
      # Read prior per-source markers (one jq call; missing file -> empties).
      _pm_sprint=""; _pm_bridge=""; _pm_simstim=""
      if [[ -f "$_push_marker" ]]; then
        mapfile -d '' -t _pm < <(
          jq -nj --rawfile m "$_push_marker" '
            def denul($z): . / $z | join("");
            ([0] | implode) as $z |
            ($m | try fromjson catch {}) as $j |
            [ ($j.sprint_plan // ""), ($j.bridge // ""), ($j.simstim // "") ]
            | map(denul($z)) | join($z) + $z
          ' 2>/dev/null
        )
        if [[ "${#_pm[@]}" -eq 3 ]]; then
          _pm_sprint="${_pm[0]}"; _pm_bridge="${_pm[1]}"; _pm_simstim="${_pm[2]}"
        fi
      fi

      # Skip already-acked sources, fall through to the next fresh one. This
      # per-source walk (not a single flat marker) is required: the state
      # files are never archived after completion, so a stale terminal state
      # from an old run must not permanently mask a later, different source.
      _push_src=""; _push_fp=""; _push_msg=""; _push_state=""; _push_id=""
      if [[ -n "$_push_sprint_cand" && "$_push_sprint_cand" != "$_pm_sprint" ]]; then
        _push_src="sprint_plan"; _push_fp="$_push_sprint_cand"
        _push_state="$state"; _push_id="$current"
        _push_msg="${current} sprint-plan ${state}"
      elif [[ -n "$_push_bridge_cand" && "$_push_bridge_cand" != "$_pm_bridge" ]]; then
        _push_src="bridge"; _push_fp="$_push_bridge_cand"
        _push_state="$bridge_state"; _push_id="iteration-${iteration}"
        _push_msg="iteration-${iteration} bridge ${bridge_state}"
      elif [[ -n "$_push_simstim_cand" && "$_push_simstim_cand" != "$_pm_simstim" ]]; then
        _push_src="simstim"; _push_fp="$_push_simstim_cand"
        _push_state="$simstim_state"; _push_id="${phase}"
        _push_msg="${phase} simstim ${simstim_state}"
      fi

      if [[ -n "$_push_src" ]]; then
        # Write the marker FIRST — a failed/slow command still counts as
        # attempted once, so a permanently broken operator command cannot
        # cause a retry storm on every subsequent Stop.
        mkdir -p .run 2>/dev/null
        _push_tmp="$(mktemp .run/push-last-state.json.XXXXXX 2>/dev/null || true)"
        if [[ -n "$_push_tmp" ]]; then
          if jq --arg k "$_push_src" --arg v "$_push_fp" '.[$k]=$v' "$_push_marker" 2>/dev/null > "$_push_tmp" \
             || jq -n --arg k "$_push_src" --arg v "$_push_fp" '{($k):$v}' > "$_push_tmp" 2>/dev/null; then
            mv -f "$_push_tmp" "$_push_marker" 2>/dev/null || rm -f "$_push_tmp" 2>/dev/null
          else
            rm -f "$_push_tmp" 2>/dev/null
          fi
        fi
        # Dispatch (best-effort; always returns 0, stdio fully redirected).
        push_notify "$_push_msg" "$_push_src" "$_push_state" "$_push_id"
      fi
    fi
  fi
fi

# No active runs — allow stop
exit 0
