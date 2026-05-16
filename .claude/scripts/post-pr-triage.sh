#!/usr/bin/env bash
# post-pr-triage.sh — Triage Bridgebuilder findings and emit reasoning logs
#
# Amendment 1 (cycle-053, Issue #464 Part B):
# Closes the loop between the external Bridgebuilder reviewer and Loa state.
# Reads bridge findings, classifies by severity, takes actions per HITL design
# decisions (autonomous with logged reasoning).
#
# Usage:
#   post-pr-triage.sh --pr <PR_NUMBER> [--auto-triage true|false]
#                     [--review-dir PATH] [--dry-run]
#
# Outputs:
#   - Trajectory entries to grimoires/loa/a2a/trajectory/bridge-triage-<DATE>.jsonl
#   - Lore candidate entries to .run/bridge-lore-candidates.jsonl (PRAISE findings)
#   - Pending bug queue to .run/bridge-pending-bugs.jsonl (BLOCKER auto-dispatch)
#
# Exit codes:
#   0 - Triage complete (findings processed or none present — both success)
#   1 - Input validation error
#   2 - Configuration error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default paths resolve relative to cwd (not script location) to stay consistent
# with how post-pr-orchestrator.sh passes paths and with how bridge-orchestrator.sh
# writes findings (Bridgebuilder H4 from PR #466 v2 review).
# Set LOA_REVIEW_DIR etc. to override.
CWD_AT_INVOKE="$(pwd)"

# ============================================================================
# Defaults
# ============================================================================

PR_NUMBER=""
AUTO_TRIAGE="true"
REVIEW_DIR="${LOA_REVIEW_DIR:-$CWD_AT_INVOKE/.run/bridge-reviews}"
TRAJECTORY_DIR="${LOA_TRAJECTORY_DIR:-$CWD_AT_INVOKE/grimoires/loa/a2a/trajectory}"
LORE_QUEUE="${LOA_LORE_QUEUE:-$CWD_AT_INVOKE/.run/bridge-lore-candidates.jsonl}"
BUG_QUEUE="${LOA_BUG_QUEUE:-$CWD_AT_INVOKE/.run/bridge-pending-bugs.jsonl}"
DRY_RUN="false"

# ============================================================================
# Argument Parsing
# ============================================================================

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pr)
      PR_NUMBER="$2"
      shift 2
      ;;
    --auto-triage)
      AUTO_TRIAGE="$2"
      shift 2
      ;;
    --review-dir)
      REVIEW_DIR="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    --help|-h)
      grep -E '^#( |$)' "$0" | head -30
      exit 0
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$PR_NUMBER" ]]; then
  echo "ERROR: --pr <PR_NUMBER> required" >&2
  exit 1
fi

if ! [[ "$PR_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "ERROR: --pr must be a positive integer, got: $PR_NUMBER" >&2
  exit 1
fi

# ============================================================================
# Helpers
# ============================================================================

log() {
  echo "[post-pr-triage] $*" >&2
}

# Append a trajectory entry per bridge-triage.schema.json
# Args: finding_id severity action reasoning [bug_id] [review_file] [iteration]
emit_trajectory() {
  local finding_id="$1"
  local severity="$2"
  local action="$3"
  local reasoning="$4"
  local bug_id="${5:-}"
  local review_file="${6:-}"
  local iteration="${7:-}"

  local date_tag
  date_tag="$(date -u +"%Y-%m-%d")"
  local traj_file="$TRAJECTORY_DIR/bridge-triage-${date_tag}.jsonl"

  mkdir -p "$TRAJECTORY_DIR"

  # Build entry with jq to ensure proper escaping (HITL design decision #1)
  local entry
  entry=$(jq -nc \
    --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --argjson pr "$PR_NUMBER" \
    --arg fid "$finding_id" \
    --arg sev "$severity" \
    --arg act "$action" \
    --arg reason "$reasoning" \
    --arg bug "$bug_id" \
    --arg rfile "$review_file" \
    --arg iter "$iteration" \
    '{
      timestamp: $ts,
      pr_number: $pr,
      finding_id: $fid,
      severity: $sev,
      action: $act,
      reasoning: $reason
    } + (if $bug != "" then {auto_dispatched_bug_id: $bug} else {} end)
      + (if $rfile != "" then {review_file: $rfile} else {} end)
      + (if $iter != "" then {review_iteration: ($iter | tonumber)} else {} end)')

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY-RUN] Would append to $traj_file: $entry"
  else
    echo "$entry" >> "$traj_file"
  fi
}

# Append a finding to the lore-candidates queue (PRAISE findings)
# Args: review_file finding_json
queue_lore_candidate() {
  local review_file="$1"
  local finding_json="$2"

  mkdir -p "$(dirname "$LORE_QUEUE")"

  local entry
  entry=$(jq -nc \
    --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --argjson pr "$PR_NUMBER" \
    --arg rfile "$review_file" \
    --argjson finding "$finding_json" \
    '{
      timestamp: $ts,
      pr_number: $pr,
      review_file: $rfile,
      finding: $finding
    }')

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY-RUN] Would append to $LORE_QUEUE"
  else
    echo "$entry" >> "$LORE_QUEUE"
  fi
}

# Queue a BLOCKER for /bug auto-dispatch (HITL design decision #1: autonomous
# may act on blockers with logged reasoning). Since shell cannot invoke skills
# directly, we queue the bug request for the next Claude invocation to pick up.
# Args: review_file finding_json reasoning
queue_pending_bug() {
  local review_file="$1"
  local finding_json="$2"
  local reasoning="$3"

  mkdir -p "$(dirname "$BUG_QUEUE")"

  # Sanitize finding ID so the resulting bug_seed_id matches the schema's
  # auto_dispatched_bug_id pattern ^[0-9]{8}-[a-z0-9][a-z0-9-]*$:
  # - lowercase everything
  # - replace underscores and other separators with hyphens
  # - strip anything not in [a-z0-9-]
  # - collapse runs of hyphens; trim leading/trailing hyphens
  # (Bridgebuilder H2 from PR #466 v2 review)
  local raw_id sanitized_id
  raw_id="$(echo "$finding_json" | jq -r '.id')"
  sanitized_id="$(echo "$raw_id" \
    | tr '[:upper:]' '[:lower:]' \
    | tr '_' '-' \
    | tr -cd 'a-z0-9-' \
    | sed -E 's/-+/-/g; s/^-+|-+$//g')"
  # Safety fallback — if sanitization left us with empty string, use "unknown"
  [[ -z "$sanitized_id" ]] && sanitized_id="unknown"

  local bug_seed_id
  bug_seed_id="$(date -u +"%Y%m%d")-autobridge-${sanitized_id}"

  local entry
  entry=$(jq -nc \
    --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --argjson pr "$PR_NUMBER" \
    --arg rfile "$review_file" \
    --arg reason "$reasoning" \
    --arg seed_id "$bug_seed_id" \
    --argjson finding "$finding_json" \
    '{
      timestamp: $ts,
      pr_number: $pr,
      review_file: $rfile,
      reasoning: $reason,
      suggested_bug_id: $seed_id,
      finding: $finding,
      status: "pending_dispatch"
    }')

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY-RUN] Would queue bug: $bug_seed_id"
  else
    echo "$entry" >> "$BUG_QUEUE"
  fi

  echo "$bug_seed_id"
}

# Classify a finding's severity into an action.
# Per HITL design decision #1: autonomous mode acts on BLOCKERs with logged
# reasoning. HIGH is log-only in autonomous mode; HITL mode would gate.
# Args: severity (e.g., CRITICAL, HIGH, PRAISE)
# Returns via echo: action name
classify_action() {
  local severity="$1"

  case "$severity" in
    CRITICAL|BLOCKER)
      if [[ "$AUTO_TRIAGE" == "true" ]]; then
        echo "dispatch_bug"
      else
        echo "defer"
      fi
      ;;
    HIGH|HIGH_CONSENSUS)
      echo "log_only"
      ;;
    MEDIUM|LOW|DISPUTED|LOW_VALUE)
      echo "log_only"
      ;;
    PRAISE)
      echo "lore_candidate"
      ;;
    REFRAME|SPECULATION)
      echo "defer"
      ;;
    *)
      echo "defer"
      ;;
  esac
}

# Build a reasoning string for the triage decision (satisfies schema's required
# reasoning field per HITL design decision #1).
# Args: severity action finding_title
build_reasoning() {
  local severity="$1"
  local action="$2"
  local title="$3"

  case "$action" in
    dispatch_bug)
      echo "Severity=$severity flagged as BLOCKER. Auto-triage enabled. Queued for /bug dispatch per HITL design decision #1 (autonomous acts on blockers with logged reasoning). Title: '$title'"
      ;;
    log_only)
      echo "Severity=$severity. Autonomous mode — logged for HITL review, no gate applied. Title: '$title'"
      ;;
    lore_candidate)
      echo "Severity=$severity (PRAISE). Queued for lore mining — pattern-aggregation workstream (Amendment 3)."
      ;;
    defer)
      echo "Severity=$severity. Deferred — HITL review recommended for $severity classification. Title: '$title'"
      ;;
    skip_false_positive)
      echo "Heuristic filter matched. Skipped as likely false positive."
      ;;
    *)
      echo "Default action: $action for severity=$severity."
      ;;
  esac
}

# ============================================================================
# Main: Process all findings in review directory
# ============================================================================

process_findings_file() {
  local findings_file="$1"

  # Extract iteration number from filename (bridge-*-iterN-findings.json)
  local iteration
  iteration=$(basename "$findings_file" | grep -oE 'iter[0-9]+' | grep -oE '[0-9]+' || echo "1")

  local total_findings
  total_findings=$(jq '.findings | length // 0' "$findings_file" 2>/dev/null || echo "0")

  if [[ "$total_findings" -eq 0 ]]; then
    log "No findings in $findings_file"
    return 0
  fi

  # cycle-109 Sprint 2 T2.7 — CONSUMER #7: surface verdict_quality from the
  # findings artifact (when present). BB cheval-delegate (T2.6) writes
  # verdict_quality alongside findings in the per-iteration output; this
  # consumer reads .verdict_quality (or .metadata.verdict_quality, depending
  # on upstream shape) and logs the status banner so operators see the
  # substrate health at triage time. NFR-Rel-1: a degraded substrate
  # produced these findings; triage decisions should account for that.
  local vq_status vq_chain_health
  vq_status=$(jq -r '(.verdict_quality.status // .metadata.verdict_quality.status // "")' \
      "$findings_file" 2>/dev/null || echo "")
  vq_chain_health=$(jq -r '(.verdict_quality.chain_health // .metadata.verdict_quality.chain_health // "")' \
      "$findings_file" 2>/dev/null || echo "")
  if [[ -n "$vq_status" && "$vq_status" != "null" ]]; then
    log "Substrate verdict_quality: status=$vq_status chain_health=${vq_chain_health:-?}"
    if [[ "$vq_status" == "FAILED" || "$vq_chain_health" == "exhausted" ]]; then
      log "[vq-warn] Findings produced by a FAILED/exhausted substrate — triage decisions are advisory only (NFR-Rel-1)."
    fi
  fi

  log "Processing $total_findings findings from $findings_file (iter $iteration)"

  # Iterate through findings
  local idx=0
  while [[ $idx -lt $total_findings ]]; do
    local finding_json
    finding_json=$(jq -c ".findings[$idx]" "$findings_file" 2>/dev/null || echo "null")

    if [[ "$finding_json" == "null" ]]; then
      idx=$((idx + 1))
      continue
    fi

    local fid severity title
    fid=$(echo "$finding_json" | jq -r '.id // "unknown"')
    severity=$(echo "$finding_json" | jq -r '.severity // "UNKNOWN"')
    title=$(echo "$finding_json" | jq -r '.title // "(no title)"')

    local action
    action=$(classify_action "$severity")

    local reasoning
    reasoning=$(build_reasoning "$severity" "$action" "$title")

    case "$action" in
      dispatch_bug)
        local bug_id
        bug_id=$(queue_pending_bug "$findings_file" "$finding_json" "$reasoning")
        emit_trajectory "$fid" "$severity" "$action" "$reasoning" "$bug_id" "$findings_file" "$iteration"
        log "  BLOCKER '$fid' ($severity) → queued bug: $bug_id"
        ;;
      lore_candidate)
        queue_lore_candidate "$findings_file" "$finding_json"
        emit_trajectory "$fid" "$severity" "$action" "$reasoning" "" "$findings_file" "$iteration"
        log "  PRAISE '$fid' → lore queue"
        ;;
      log_only|defer|skip_false_positive|*)
        emit_trajectory "$fid" "$severity" "$action" "$reasoning" "" "$findings_file" "$iteration"
        log "  $severity '$fid' → $action"
        ;;
    esac

    idx=$((idx + 1))
  done
}

main() {
  if [[ ! -d "$REVIEW_DIR" ]]; then
    log "Review directory not found: $REVIEW_DIR"
    log "No findings to triage (bridge-orchestrator may not have run yet)"
    return 0
  fi

  # Issue #676 Defect B (sprint-bug-140): filter findings by current bridge_id
  # so stale entries from prior bridge runs don't get re-tagged with the current
  # PR. When .run/bridge-state.json is absent or bridge_id is empty (interactive
  # /run-bridge legacy mode), fall through to the existing glob — preserves
  # backward compat.
  local bridge_state_file="$CWD_AT_INVOKE/.run/bridge-state.json"
  local bridge_id=""
  if [[ -f "$bridge_state_file" ]]; then
    bridge_id=$(jq -r '.bridge_id // empty' "$bridge_state_file" 2>/dev/null || echo "")
  fi

  local findings_files=()
  if [[ -n "$bridge_id" ]]; then
    # Filter to fresh findings files matching the current bridge_id only.
    while IFS= read -r -d '' f; do
      findings_files+=("$f")
    done < <(find "$REVIEW_DIR" -maxdepth 1 -name "${bridge_id}-iter*-findings.json" -print0 2>/dev/null)

    if [[ ${#findings_files[@]} -eq 0 ]]; then
      log "WARN: bridge ${bridge_id} produced no findings files in $REVIEW_DIR"
      log "(prior-run findings will NOT be processed; bridge_id filter active)"
      # Still emit a convergence record below so downstream consumers see FLATLINE
      # rather than thinking triage was never invoked.
    else
      log "Filtered to ${#findings_files[@]} findings file(s) matching bridge_id=${bridge_id}"
    fi
  else
    # Backward-compat path: no bridge-state.json or empty bridge_id. Glob all.
    while IFS= read -r -d '' f; do
      findings_files+=("$f")
    done < <(find "$REVIEW_DIR" -name "*-findings.json" -print0 2>/dev/null)

    if [[ ${#findings_files[@]} -eq 0 ]]; then
      log "No findings files found in $REVIEW_DIR"
      return 0
    fi

    log "Found ${#findings_files[@]} findings file(s) (no bridge_id filter — interactive mode)"
  fi

  # If filter yielded zero results, skip the per-file loop. The convergence
  # record below still emits FLATLINE so the orchestrator sees a clean state
  # (rather than treating "no triage" as "no signal").

  for f in "${findings_files[@]}"; do
    process_findings_file "$f"
  done

  log "Triage complete — see trajectory logs in $TRAJECTORY_DIR"

  # Kaironic termination check: emit a machine-readable summary so callers
  # (e.g., iterative post-pr-orchestrator loops or /run-bridge) can decide
  # whether to continue iterating or jack out.
  #
  # Convergence heuristic:
  #   - actionable_high >0 OR blocker_count >0 → KEEP_ITERATING
  #   - actionable_high =0 AND blocker_count =0 → FLATLINE (safe to converge)
  #
  # This is the "nothing left to converge on" signal from the Neuromancer lore
  # captured in /run-bridge's kaironic termination pattern.
  # Count severity/action markers across all trajectory files using awk
  # (single-line output, no pipefail issues with grep exiting 1 on no-match).
  local actionable_high=0 blocker_count=0 disputed_count=0
  local traj_glob_found=false
  for f in "$TRAJECTORY_DIR"/bridge-triage-*.jsonl; do
    [[ -f "$f" ]] || continue
    traj_glob_found=true
    break
  done
  if [[ "$traj_glob_found" == "true" ]]; then
    actionable_high=$(awk '/"action":"dispatch_bug"/ {c++} END {print c+0}' \
      "$TRAJECTORY_DIR"/bridge-triage-*.jsonl 2>/dev/null || echo "0")
    blocker_count=$(awk '/"severity":"BLOCKER"|"severity":"CRITICAL"/ {c++} END {print c+0}' \
      "$TRAJECTORY_DIR"/bridge-triage-*.jsonl 2>/dev/null || echo "0")
    disputed_count=$(awk '/"severity":"DISPUTED"|"severity":"HIGH"/ {c++} END {print c+0}' \
      "$TRAJECTORY_DIR"/bridge-triage-*.jsonl 2>/dev/null || echo "0")
  fi

  local convergence_state
  if [[ "$actionable_high" -eq 0 && "$blocker_count" -eq 0 ]]; then
    convergence_state="FLATLINE"
  else
    convergence_state="KEEP_ITERATING"
  fi

  log "Kaironic state: $convergence_state (actionable_high=$actionable_high, blocker=$blocker_count, disputed/high_logged=$disputed_count)"

  # Write the convergence record to a stable location for downstream consumers
  if [[ "$DRY_RUN" != "true" ]]; then
    local convergence_file="$CWD_AT_INVOKE/.run/bridge-triage-convergence.json"
    mkdir -p "$(dirname "$convergence_file")"
    jq -nc \
      --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
      --argjson pr "$PR_NUMBER" \
      --argjson high "$actionable_high" \
      --argjson blocker "$blocker_count" \
      --argjson disputed "$disputed_count" \
      --arg state "$convergence_state" \
      '{timestamp: $ts, pr_number: $pr, state: $state, actionable_high: $high, blocker_count: $blocker, disputed_count: $disputed}' \
      > "$convergence_file"
  fi

  if [[ -f "$BUG_QUEUE" ]] && [[ "$DRY_RUN" != "true" ]]; then
    local pending_count
    pending_count=$(grep -c '^' "$BUG_QUEUE" 2>/dev/null || echo "0")
    if [[ "$pending_count" -gt 0 ]]; then
      log "Pending bug queue: $pending_count entries in $BUG_QUEUE"
      log "Next /bug invocation should consume these — see post-pr-triage docs"
    fi
  fi

  return 0
}

main "$@"
