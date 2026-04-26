#!/usr/bin/env bash
# =============================================================================
# construct-invoke.sh — Trajectory emission wrapper for construct invocations
# =============================================================================
# Emits JSONL rows to .run/construct-trajectory.jsonl for persona session
# observability. Supports paired entry/exit rows matched by session_id.
#
# Usage:
#   construct-invoke.sh entry <persona> <construct_slug> [trigger]
#   construct-invoke.sh exit  <persona> <construct_slug> [duration_ms] [outcome] [trigger] [session_id]
#
# Concurrency:
#   The default correlator between entry and exit is a temp file keyed by
#   (persona, construct_slug). Callers that may run parallel entries with
#   the same key MUST capture the session_id from entry's stdout and pass
#   it explicitly to exit (positional arg 6, or via LOA_SESSION_ID env).
#   The temp-file fallback is racy under that condition.
#
# Exit Codes:
#   0 = success (JSONL write failure is non-fatal — logs warning)
#   1 = invalid subcommand
#
# Cycle: loa-constructs-cycle-001 (Leg D — Construct Trajectory Emission)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

TRAJECTORY_FILE="${LOA_TRAJECTORY_FILE:-$PROJECT_ROOT/.run/construct-trajectory.jsonl}"
TEMP_DIR="${TMPDIR:-/tmp}/construct-invoke"

# =============================================================================
# Log rotation — 30-day retention, runs before each emit
# =============================================================================

rotate_trajectory() {
  if [[ ! -f "$TRAJECTORY_FILE" ]]; then
    return 0
  fi

  # BSD/GNU compatible date arithmetic
  local cutoff
  cutoff=$(date -u -d '30 days ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
           || date -u -v-30d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
           || echo "")

  if [[ -z "$cutoff" ]]; then
    # Cannot compute cutoff — skip rotation
    return 0
  fi

  local tmp
  tmp=$(mktemp) || return 0

  if jq -c "select(.timestamp >= \"$cutoff\")" "$TRAJECTORY_FILE" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$TRAJECTORY_FILE"
  else
    rm -f "$tmp"
  fi
}

# =============================================================================
# Session ID management
# =============================================================================

session_key() {
  local persona="$1"
  local construct="$2"
  echo "${persona}__${construct}" | tr '[:upper:]' '[:lower:]' | tr ' /' '__'
}

session_temp_path() {
  local key="$1"
  echo "$TEMP_DIR/session_${key}.id"
}

# =============================================================================
# JSONL emit
# =============================================================================

emit_row() {
  local row="$1"

  mkdir -p "$(dirname "$TRAJECTORY_FILE")" 2>/dev/null || true

  if ! echo "$row" >> "$TRAJECTORY_FILE" 2>/dev/null; then
    echo "[construct-invoke] WARNING: failed to write to $TRAJECTORY_FILE" >&2
  fi
}

# =============================================================================
# Subcommand: entry
# =============================================================================

do_entry() {
  local persona="$1"
  local construct_slug="$2"
  local trigger="${3:-}"

  # Derive trigger from persona name if not supplied
  if [[ -z "$trigger" ]]; then
    case "$persona" in
      ALEXANDER) trigger="/feel" ;;
      STAMETS)   trigger="/dig" ;;
      OSTROM)    trigger="/systems" ;;
      *)         trigger="/${persona,,}" ;;
    esac
  fi

  # Generate session_id
  local session_id
  session_id=$(uuidgen 2>/dev/null || python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "$(date +%s)-$$")

  # Store session_id keyed by persona+construct
  local key
  key=$(session_key "$persona" "$construct_slug")
  mkdir -p "$TEMP_DIR" 2>/dev/null || true
  echo "$session_id" > "$(session_temp_path "$key")" 2>/dev/null || true

  # Rotate before emit
  rotate_trajectory

  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # Doctrine §13.3 L3: declare stream_type on trajectory rows.
  # Default to "Signal" (an observation-type emission) for invocation events;
  # persona-specific downstream rows may declare "Verdict" explicitly.
  local stream_type="${LOA_STREAM_TYPE:-Signal}"
  local read_mode="${LOA_READ_MODE:-orient}"

  local row
  row=$(jq -cn \
    --arg event "entry" \
    --arg session_id "$session_id" \
    --arg persona "$persona" \
    --arg trigger "$trigger" \
    --arg construct_slug "$construct_slug" \
    --arg timestamp "$ts" \
    --arg stream_type "$stream_type" \
    --arg read_mode "$read_mode" \
    '{event: $event, session_id: $session_id, persona: $persona, trigger: $trigger, construct_slug: $construct_slug, stream_type: $stream_type, read_mode: $read_mode, timestamp: $timestamp}')

  emit_row "$row"
  echo "$session_id"
}

# =============================================================================
# Subcommand: exit
# =============================================================================

do_exit() {
  local persona="$1"
  local construct_slug="$2"
  local duration_ms="${3:-}"
  local outcome="${4:-completed}"
  local trigger="${5:-}"
  # Bridgebuilder iter-3 HIGH_CONSENSUS: explicit session_id passing is the
  # robust correlator. Callers that need concurrency-safe pairing capture
  # the session_id from entry's stdout and pass it via $6 (or
  # LOA_SESSION_ID env). Filesystem-as-shared-memory remains the fallback
  # for callers that don't yet thread the value through.
  local explicit_session_id="${6:-${LOA_SESSION_ID:-}}"

  # Derive trigger from persona name if not supplied
  if [[ -z "$trigger" ]]; then
    case "$persona" in
      ALEXANDER) trigger="/feel" ;;
      STAMETS)   trigger="/dig" ;;
      OSTROM)    trigger="/systems" ;;
      *)         trigger="/${persona,,}" ;;
    esac
  fi

  local session_id=""
  if [[ -n "$explicit_session_id" ]]; then
    # Explicit value-passing — preferred, race-free correlation.
    session_id="$explicit_session_id"
    # Best-effort cleanup of any stale temp file from a prior run.
    local key
    key=$(session_key "$persona" "$construct_slug")
    rm -f "$(session_temp_path "$key")" 2>/dev/null || true
  else
    # Fallback: filesystem-as-shared-memory, keyed by (persona, construct).
    # Race-prone under parallel entry calls with the same key — see
    # Bridgebuilder PR #617 iter-3 HIGH_CONSENSUS finding. Callers should
    # migrate to explicit value-passing.
    local key
    key=$(session_key "$persona" "$construct_slug")
    local temp_path
    temp_path=$(session_temp_path "$key")
    if [[ -f "$temp_path" ]]; then
      session_id=$(cat "$temp_path" 2>/dev/null || echo "")
      rm -f "$temp_path" 2>/dev/null || true
    fi
  fi

  if [[ -z "$session_id" ]]; then
    echo "[construct-invoke] WARNING: no session_id found for $persona/$construct_slug — exit row will have null session_id" >&2
    session_id="null"
  fi

  # Validate/normalize duration_ms
  local dur_json
  if [[ -n "$duration_ms" ]] && [[ "$duration_ms" =~ ^[0-9]+$ ]]; then
    dur_json="$duration_ms"
  else
    dur_json="null"
  fi

  # Rotate before emit
  rotate_trajectory

  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # Doctrine §13.3 L3: declare stream_type on trajectory rows.
  local stream_type="${LOA_STREAM_TYPE:-Signal}"
  local read_mode="${LOA_READ_MODE:-orient}"

  local row
  if [[ "$session_id" == "null" ]]; then
    row=$(jq -cn \
      --arg event "exit" \
      --arg persona "$persona" \
      --arg trigger "$trigger" \
      --arg construct_slug "$construct_slug" \
      --arg timestamp "$ts" \
      --argjson duration_ms "$dur_json" \
      --arg outcome "$outcome" \
      --arg stream_type "$stream_type" \
      --arg read_mode "$read_mode" \
      '{event: $event, session_id: null, persona: $persona, trigger: $trigger, construct_slug: $construct_slug, stream_type: $stream_type, read_mode: $read_mode, timestamp: $timestamp, duration_ms: $duration_ms, outcome: $outcome}')
  else
    row=$(jq -cn \
      --arg event "exit" \
      --arg session_id "$session_id" \
      --arg persona "$persona" \
      --arg trigger "$trigger" \
      --arg construct_slug "$construct_slug" \
      --arg timestamp "$ts" \
      --argjson duration_ms "$dur_json" \
      --arg outcome "$outcome" \
      --arg stream_type "$stream_type" \
      --arg read_mode "$read_mode" \
      '{event: $event, session_id: $session_id, persona: $persona, trigger: $trigger, construct_slug: $construct_slug, stream_type: $stream_type, read_mode: $read_mode, timestamp: $timestamp, duration_ms: $duration_ms, outcome: $outcome}')
  fi

  emit_row "$row"
}

# =============================================================================
# Main
# =============================================================================

main() {
  local subcommand="${1:-}"

  case "$subcommand" in
    entry)
      [[ $# -ge 3 ]] || { echo "Usage: construct-invoke.sh entry <persona> <construct_slug> [trigger]" >&2; exit 1; }
      do_entry "$2" "$3" "${4:-}"
      ;;
    exit)
      [[ $# -ge 3 ]] || { echo "Usage: construct-invoke.sh exit <persona> <construct_slug> [duration_ms] [outcome] [trigger] [session_id]" >&2; exit 1; }
      do_exit "$2" "$3" "${4:-}" "${5:-completed}" "${6:-}" "${7:-}"
      ;;
    -h|--help)
      echo "Usage: construct-invoke.sh entry|exit <persona> <construct_slug> [args...]"
      echo "  entry <persona> <slug> [trigger]"
      echo "  exit  <persona> <slug> [duration_ms] [outcome] [trigger] [session_id]"
      echo ""
      echo "Concurrency: pass session_id explicitly (or via LOA_SESSION_ID env)"
      echo "for race-free correlation under parallel callers. Without it, the"
      echo "fallback temp-file lookup races on (persona, construct) collisions."
      exit 0
      ;;
    *)
      echo "ERROR: Unknown subcommand: $subcommand" >&2
      echo "Usage: construct-invoke.sh entry|exit <persona> <construct_slug>" >&2
      exit 1
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
