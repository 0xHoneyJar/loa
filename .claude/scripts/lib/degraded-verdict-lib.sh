#!/usr/bin/env bash
# =============================================================================
# degraded-verdict-lib.sh — shared DEGRADED/FAILED trajectory + page helper
# =============================================================================
# Part of: cycle-117 session-economy item D (bd-c117-d-degraded-band-zodl,
# issue #1177 D). Bundle D (772d7f43, #1007) made adversarial-review.sh,
# red-team-code-vs-design.sh, and flatline-orchestrator.sh HONEST about
# degradation but left the signal prose-only — nothing appended to the
# trajectory channel and nothing paged. This lib is the ONE shared writer
# so no gate can forget either half of the contract.
#
# Public API:
#   degraded_verdict_emit <gate> <verdict_band> <degradation_reason> \
#       <sprint_id> <model_exit_code|-> [leg...]
#     Unconditional: always appends a trajectory record and attempts a page,
#     regardless of verdict_band. Callers normally go through the guarded
#     wrapper below instead of calling this directly.
#
#   degraded_verdict_maybe_emit <gate> <verdict_band> <degradation_reason> \
#       <sprint_id> <model_exit_code|-> [leg...]
#     Guarded entry point. No-ops silently (returns 0, writes nothing, pages
#     nothing) unless verdict_band is DEGRADED or FAILED — a fully-clean
#     (APPROVED) or UNKNOWN run produces neither a record nor a page.
#
# Record shape (grimoires/loa/a2a/trajectory/degraded-verdict-<DATE>.jsonl,
# one line per record): {gate, verdict_band, degradation_reason,
# degraded_legs, model_exit_code, sprint_id, ts} — schema at
# .claude/data/trajectory-schemas/degraded-verdict.schema.json.
# degraded_legs is omitted (not emitted as []) when no leg args are given.
# model_exit_code is null when the 5th arg is "-" or empty (not every
# degrade site has a single meaningful exit code).
#
# Paging: soft-sources push-notify-lib.sh (sibling in this dir) and calls
# push_notify "<msg>" "$gate" "$verdict_band" "$sprint_id" when it declares
# push_notify. push-notify-lib.sh is itself config-gated (notifications.
# push_command.enabled) and always returns 0 — a disabled/missing config is
# a silent no-op, not a failure. When the lib FILE itself is absent
# (downstream repos mid-update), this lib logs a stderr skip-line and moves
# on — the trajectory record still lands either way.
#
# Sourceable with no side effects beyond function/PUSH_* var definitions.
# Every function ALWAYS returns 0 — a paging/logging side channel must never
# change a caller's exit code or control flow (mirrors push-notify-lib.sh's
# own contract).
#
# Test seam: LOA_DEGRADED_VERDICT_DIR overrides the trajectory directory
# (default: <repo-root>/grimoires/loa/a2a/trajectory) so tests never write
# into the real repo tree. Mirrors push-notify-lib.sh's LOA_PUSH_CONFIG seam.
# =============================================================================

_DVL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_DVL_PROJECT_ROOT="$(cd "${_DVL_DIR}/../../.." && pwd)"

# Soft-source the real push channel (Wave 1, item C). Absent file (downstream
# repos mid-update) -> push_notify stays undeclared; the fail-soft stderr
# path below fires instead of a hard error.
# shellcheck source=push-notify-lib.sh
source "${_DVL_DIR}/push-notify-lib.sh" 2>/dev/null || true

# Directory the trajectory jsonl lives in. Test-overridable; see header.
_dvl_trajectory_dir() {
  printf '%s' "${LOA_DEGRADED_VERDICT_DIR:-${_DVL_PROJECT_ROOT}/grimoires/loa/a2a/trajectory}"
}

# Unconditional emit: one trajectory record + one best-effort page attempt.
degraded_verdict_emit() {
  local gate="${1:?degraded_verdict_emit: gate required}"
  local band="${2:?degraded_verdict_emit: verdict_band required}"
  local reason="${3:-unknown}"
  local sprint_id="${4:?degraded_verdict_emit: sprint_id required}"
  local model_exit_code="${5:--}"
  local -a legs=("${@:6}")

  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  local trajectory_dir trajectory_file
  trajectory_dir="$(_dvl_trajectory_dir)"
  mkdir -p "$trajectory_dir" 2>/dev/null || true
  trajectory_file="$trajectory_dir/degraded-verdict-$(date -u +%Y-%m-%d).jsonl"

  local entry
  entry=$(jq -nc \
    --arg gate "$gate" \
    --arg band "$band" \
    --arg reason "$reason" \
    --arg sprint "$sprint_id" \
    --arg mec "$model_exit_code" \
    --arg ts "$ts" \
    --args '
      {
        gate: $gate,
        verdict_band: $band,
        degradation_reason: $reason,
        sprint_id: $sprint,
        ts: $ts,
        model_exit_code: (if ($mec == "-" or $mec == "") then null
                           else ($mec | (try tonumber catch null)) end)
      }
      + (if ($ARGS.positional | length) > 0
         then {degraded_legs: $ARGS.positional} else {} end)
    ' ${legs[@]+"${legs[@]}"} 2>/dev/null) || entry=""

  if [[ -n "$entry" ]]; then
    # Append with flock if available, otherwise mkdir-based lock. Copied
    # from adversarial-review.sh's own trajectory writer (:1227-1248) — NOT
    # post-pr-triage.sh's unlocked `>>`, since this lib has 3 concurrent
    # writers (adversarial-review/red-team/flatline) that can race.
    if command -v flock &>/dev/null; then
      (
        flock -w 5 200
        printf '%s\n' "$entry" >> "$trajectory_file"
      ) 200>"${trajectory_file}.lock" 2>/dev/null
    else
      local lock_dir="${trajectory_file}.lockdir"
      local max_wait=5 waited=0
      while ! mkdir "$lock_dir" 2>/dev/null; do
        waited=$((waited + 1))
        if [[ $waited -ge $max_wait ]]; then
          printf '%s\n' "$entry" >> "$trajectory_file"
          waited=-1
          break
        fi
        sleep 1
      done
      if [[ $waited -ne -1 ]]; then
        printf '%s\n' "$entry" >> "$trajectory_file"
        rmdir "$lock_dir" 2>/dev/null || true
      fi
    fi
  fi

  # Best-effort page. push_notify (when the real lib sourced cleanly)
  # always returns 0 and is internally config-gated; a stubbed test
  # push_notify is honored too since bash resolves functions at call time.
  local legs_csv=""
  if [[ ${#legs[@]} -gt 0 ]]; then
    legs_csv=$(IFS=,; echo "${legs[*]}")
  fi
  local msg="${sprint_id} ${gate} ${band}: ${legs_csv} ${reason}"
  if declare -F push_notify >/dev/null 2>&1; then
    push_notify "$msg" "$gate" "$band" "$sprint_id"
  else
    echo "[degraded-verdict] page skipped — push_notify unavailable (push-notify-lib.sh not found)" >&2
  fi
  return 0
}

# Guarded entry point — the one callers should use. No-ops for every band
# except DEGRADED/FAILED so a clean (APPROVED/UNKNOWN) run writes and pages
# nothing.
degraded_verdict_maybe_emit() {
  local band="${2:-}"
  case "$band" in
    DEGRADED|FAILED)
      degraded_verdict_emit "$@"
      ;;
    *)
      return 0
      ;;
  esac
}
