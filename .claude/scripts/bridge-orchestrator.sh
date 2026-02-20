#!/usr/bin/env bash
# bridge-orchestrator.sh - Run Bridge loop orchestrator
# Version: 1.0.0
#
# Main orchestrator for the bridge loop: iteratively runs sprint-plan,
# invokes Bridgebuilder review, parses findings, detects flatline,
# and generates new sprint plans from findings.
#
# Usage:
#   bridge-orchestrator.sh [OPTIONS]
#
# Options:
#   --depth N          Maximum iterations (default: 3)
#   --per-sprint       Review after each sprint instead of full plan
#   --resume           Resume from interrupted bridge
#   --from PHASE       Start from phase (sprint-plan)
#   --help             Show help
#
# Exit Codes:
#   0 - Complete (JACKED_OUT)
#   1 - Halted (circuit breaker or error)
#   2 - Config error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/bootstrap.sh"
source "$SCRIPT_DIR/bridge-state.sh"

# =============================================================================
# Defaults (overridden by config)
# =============================================================================

DEPTH=3
PER_SPRINT=false
RESUME=false
FROM_PHASE=""
FLATLINE_THRESHOLD=0.05
CONSECUTIVE_FLATLINE=2
PER_ITERATION_TIMEOUT=14400   # 4 hours in seconds
TOTAL_TIMEOUT=86400            # 24 hours in seconds

# CLI-explicit tracking (for CLI > config precedence)
CLI_DEPTH=""
CLI_PER_SPRINT=""
CLI_FLATLINE_THRESHOLD=""
BRIDGE_REPO=""

# =============================================================================
# Usage
# =============================================================================

usage() {
  cat <<'USAGE'
Usage: bridge-orchestrator.sh [OPTIONS]

Options:
  --depth N          Maximum iterations (default: 3)
  --per-sprint       Review after each sprint instead of full plan
  --resume           Resume from interrupted bridge
  --from PHASE       Start from phase (sprint-plan)
  --repo OWNER/REPO  Target repository for gh commands
  --help             Show help

Exit Codes:
  0  Complete (JACKED_OUT)
  1  Halted (circuit breaker or error)
  2  Config error
USAGE
  exit "${1:-0}"
}

# =============================================================================
# Argument Parsing
# =============================================================================

while [[ $# -gt 0 ]]; do
  case "$1" in
    --depth)
      if [[ -z "${2:-}" ]]; then
        echo "ERROR: --depth requires a value" >&2
        exit 2
      fi
      CLI_DEPTH="$2"
      DEPTH="$2"
      shift 2
      ;;
    --per-sprint)
      CLI_PER_SPRINT=true
      PER_SPRINT=true
      shift
      ;;
    --resume)
      RESUME=true
      shift
      ;;
    --from)
      if [[ -z "${2:-}" ]]; then
        echo "ERROR: --from requires a value" >&2
        exit 2
      fi
      FROM_PHASE="$2"
      shift 2
      ;;
    --repo)
      if [[ -z "${2:-}" ]]; then
        echo "ERROR: --repo requires a value (owner/repo)" >&2
        exit 2
      fi
      BRIDGE_REPO="$2"
      shift 2
      ;;
    --help)
      usage 0
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      usage 2
      ;;
  esac
done

# =============================================================================
# Config Loading
# =============================================================================

load_bridge_config() {
  if command -v yq &>/dev/null && [[ -f "$CONFIG_FILE" ]]; then
    local enabled
    enabled=$(yq '.run_bridge.enabled // false' "$CONFIG_FILE" 2>/dev/null)
    if [[ "$enabled" != "true" ]]; then
      echo "ERROR: run_bridge.enabled is not true in $CONFIG_FILE" >&2
      exit 2
    fi

    # CLI > config > default precedence
    if [[ -z "$CLI_DEPTH" ]]; then
      DEPTH=$(yq ".run_bridge.defaults.depth // $DEPTH" "$CONFIG_FILE" 2>/dev/null)
    fi
    if [[ -z "$CLI_PER_SPRINT" ]]; then
      PER_SPRINT=$(yq ".run_bridge.defaults.per_sprint // $PER_SPRINT" "$CONFIG_FILE" 2>/dev/null)
    fi
    if [[ -z "$CLI_FLATLINE_THRESHOLD" ]]; then
      FLATLINE_THRESHOLD=$(yq ".run_bridge.defaults.flatline_threshold // $FLATLINE_THRESHOLD" "$CONFIG_FILE" 2>/dev/null)
    fi
    CONSECUTIVE_FLATLINE=$(yq ".run_bridge.defaults.consecutive_flatline // $CONSECUTIVE_FLATLINE" "$CONFIG_FILE" 2>/dev/null)

    local per_iter_hours total_hours
    per_iter_hours=$(yq '.run_bridge.timeouts.per_iteration_hours // 4' "$CONFIG_FILE" 2>/dev/null)
    total_hours=$(yq '.run_bridge.timeouts.total_hours // 24' "$CONFIG_FILE" 2>/dev/null)
    PER_ITERATION_TIMEOUT=$((per_iter_hours * 3600))
    TOTAL_TIMEOUT=$((total_hours * 3600))
  fi
}

# Load QMD context for bridge review enrichment
load_bridge_context() {
  local query="${1:-}"
  BRIDGE_CONTEXT=""
  if [[ -n "$query" ]] && [[ -x "$PROJECT_ROOT/.claude/scripts/qmd-context-query.sh" ]]; then
    BRIDGE_CONTEXT=$("$PROJECT_ROOT/.claude/scripts/qmd-context-query.sh" \
      --query "$query" \
      --scope grimoires \
      --budget 2500 \
      --format text 2>/dev/null) || BRIDGE_CONTEXT=""
  fi
}

# =============================================================================
# Preflight
# =============================================================================

preflight() {
  echo "═══════════════════════════════════════════════════"
  echo "  BRIDGE ORCHESTRATOR — PREFLIGHT"
  echo "═══════════════════════════════════════════════════"

  # Check config
  load_bridge_config

  # Check beads health (non-blocking — warn if unavailable)
  if [[ -f "$SCRIPT_DIR/beads/beads-health.sh" ]]; then
    local beads_status
    beads_status=$("$SCRIPT_DIR/beads/beads-health.sh" --quick --json 2>/dev/null | jq -r '.status // "UNKNOWN"' 2>/dev/null || echo "UNKNOWN")
    if [[ "$beads_status" != "HEALTHY" ]]; then
      echo "WARNING: Beads health: $beads_status (bridge continues without beads)"
    fi
  fi

  # Validate branch — protected branch check is unconditional
  local current_branch
  current_branch=$(git branch --show-current 2>/dev/null || echo "unknown")
  echo "Branch: $current_branch"

  if [[ "$current_branch" == "main" ]] || [[ "$current_branch" == "master" ]]; then
    echo "ERROR: Cannot run bridge on protected branch: $current_branch" >&2
    exit 2
  fi

  # Check required files
  if [[ ! -f "$PROJECT_ROOT/grimoires/loa/sprint.md" ]]; then
    echo "ERROR: Sprint plan not found at grimoires/loa/sprint.md" >&2
    exit 2
  fi

  # Validate depth is numeric and in range
  if ! [[ "$DEPTH" =~ ^[0-9]+$ ]]; then
    echo "ERROR: --depth must be a positive integer, got: $DEPTH" >&2
    exit 2
  fi
  if [[ "$DEPTH" -lt 1 ]] || [[ "$DEPTH" -gt 5 ]]; then
    echo "ERROR: --depth must be between 1 and 5, got: $DEPTH" >&2
    exit 2
  fi

  echo "Depth: $DEPTH"
  echo "Per-sprint: $PER_SPRINT"
  echo "Flatline threshold: $FLATLINE_THRESHOLD"
  echo "Consecutive flatline: $CONSECUTIVE_FLATLINE"
  echo ""
  echo "Preflight PASSED"
}

# =============================================================================
# Resume Logic
# =============================================================================

handle_resume() {
  if [[ ! -f "$BRIDGE_STATE_FILE" ]]; then
    echo "ERROR: No bridge state file found for resume" >&2
    exit 1
  fi

  local state bridge_id
  state=$(jq -r '.state' "$BRIDGE_STATE_FILE")
  bridge_id=$(jq -r '.bridge_id' "$BRIDGE_STATE_FILE")

  echo "Resuming bridge: $bridge_id (state: $state)" >&2

  case "$state" in
    HALTED)
      # Resume from HALTED — transition back to ITERATING
      update_bridge_state "ITERATING"
      local last_iteration
      last_iteration=$(jq '.iterations | length' "$BRIDGE_STATE_FILE")
      echo "Resuming from iteration $((last_iteration + 1))" >&2
      echo "$last_iteration"
      ;;
    ITERATING)
      # Already iterating — continue from current
      local last_iteration
      last_iteration=$(jq '.iterations | length' "$BRIDGE_STATE_FILE")
      echo "Continuing from iteration $last_iteration" >&2
      echo "$last_iteration"
      ;;
    EXPLORING)
      # Convergence was already achieved when EXPLORING starts.
      # Safest recovery: skip exploration, proceed to finalization.
      echo "Convergence was achieved. Skipping exploration, proceeding to finalization." >&2
      update_bridge_state "FINALIZING"
      if command -v jq &>/dev/null && [[ -f "$BRIDGE_STATE_FILE" ]]; then
        jq '.finalization.vision_sprint_skipped = "resumed"' "$BRIDGE_STATE_FILE" > "$BRIDGE_STATE_FILE.tmp"
        mv "$BRIDGE_STATE_FILE.tmp" "$BRIDGE_STATE_FILE"
      fi
      # Return DEPTH so the caller computes iteration = DEPTH+1, which exceeds
      # the while loop condition (iteration <= DEPTH), skipping directly to finalization.
      echo "$DEPTH"
      ;;
    *)
      echo "ERROR: Cannot resume from state: $state" >&2
      exit 1
      ;;
  esac
}

# =============================================================================
# BUTTERFREEZONE Hook (SDD 3.4.2)
# =============================================================================

is_butterfreezone_enabled() {
  local enabled
  enabled=$(yq '.butterfreezone.enabled // true' "$CONFIG_FILE" 2>/dev/null || echo "true")
  local hook_enabled
  hook_enabled=$(yq '.butterfreezone.hooks.run_bridge // true' "$CONFIG_FILE" 2>/dev/null || echo "true")
  [[ "$enabled" == "true" ]] && [[ "$hook_enabled" == "true" ]]
}

# =============================================================================
# Core Loop
# =============================================================================

bridge_main() {
  local start_iteration=0

  if [[ "$RESUME" == "true" ]]; then
    start_iteration=$(handle_resume)
  else
    # Fresh start
    preflight

    local bridge_id
    bridge_id="bridge-$(date +%Y%m%d)-$(head -c 3 /dev/urandom | xxd -p)"
    # Validate generated bridge_id format
    if [[ ! "$bridge_id" =~ ^bridge-[0-9]{8}-[0-9a-f]{6}$ ]]; then
      echo "ERROR: Generated invalid bridge_id: $bridge_id" >&2
      exit 1
    fi
    local branch
    branch=$(git branch --show-current 2>/dev/null || echo "unknown")

    init_bridge_state "$bridge_id" "$DEPTH" "$PER_SPRINT" "$FLATLINE_THRESHOLD" "$branch" "$BRIDGE_REPO"
    update_bridge_state "JACK_IN"

    echo ""
    echo "═══════════════════════════════════════════════════"
    echo "  JACK IN — Bridge ID: $bridge_id"
    echo "═══════════════════════════════════════════════════"

    update_bridge_state "ITERATING"
    start_iteration=0
  fi

  # Iteration loop
  local iteration=$((start_iteration + 1))
  local total_start_time=$SECONDS

  while [[ $iteration -le $DEPTH ]]; do
    local iter_start_time=$SECONDS

    echo ""
    echo "───────────────────────────────────────────────────"
    echo "  ITERATION $iteration / $DEPTH"
    echo "───────────────────────────────────────────────────"

    # Track iteration
    local source="existing"
    if [[ $iteration -gt 1 ]]; then
      source="findings"
    fi
    update_iteration "$iteration" "in_progress" "$source"

    # 2a: Sprint Plan
    if [[ $iteration -eq 1 ]] && [[ -z "$FROM_PHASE" || "$FROM_PHASE" == "sprint-plan" ]]; then
      echo "[PLAN] Using existing sprint plan"
    elif [[ $iteration -gt 1 ]]; then
      echo "[PLAN] Generating sprint plan from findings (iteration $iteration)"
      # The findings-to-sprint-plan generation is handled by the Claude agent
      # This script signals that it needs to happen
      echo "SIGNAL:GENERATE_SPRINT_FROM_FINDINGS:$iteration"
    fi

    # 2b: Execute Sprint Plan
    echo "[EXECUTE] Running sprint plan..."
    if [[ "$PER_SPRINT" == "true" ]]; then
      echo "SIGNAL:RUN_PER_SPRINT:$iteration"
    else
      echo "SIGNAL:RUN_SPRINT_PLAN:$iteration"
    fi

    # 2c: Cross-Repo Pattern Query (FR-1)
    local cross_repo_enabled
    cross_repo_enabled=$(yq '.run_bridge.cross_repo_query.enabled // false' "$CONFIG_FILE" 2>/dev/null || echo "false")
    if [[ "$cross_repo_enabled" == "true" ]]; then
      echo "[CROSS-REPO] Querying ecosystem repos for pattern matches..."
      echo "SIGNAL:CROSS_REPO_QUERY:$iteration"

      local cross_repo_cache="${PROJECT_ROOT}/.run/cross-repo-context.json"
      if [[ -x "$SCRIPT_DIR/cross-repo-query.sh" ]]; then
        local diff_file
        diff_file=$(mktemp "${TMPDIR:-/tmp}/bridge-diff.XXXXXX")
        git diff "origin/main...HEAD" > "$diff_file" 2>/dev/null || true

        if [[ -s "$diff_file" ]]; then
          local xr_budget xr_max_repos xr_timeout
          xr_budget=$(yq '.run_bridge.cross_repo_query.budget // 2000' "$CONFIG_FILE" 2>/dev/null || echo "2000")
          xr_max_repos=$(yq '.run_bridge.cross_repo_query.max_repos // 5' "$CONFIG_FILE" 2>/dev/null || echo "5")
          xr_timeout=$(yq '.run_bridge.cross_repo_query.timeout // 15' "$CONFIG_FILE" 2>/dev/null || echo "15")

          "$SCRIPT_DIR/cross-repo-query.sh" \
            --diff "$diff_file" \
            --output "$cross_repo_cache" \
            --budget "$xr_budget" \
            --max-repos "$xr_max_repos" \
            --timeout "$xr_timeout" 2>/dev/null || true

          if [[ -f "$cross_repo_cache" ]]; then
            local xr_matches
            xr_matches=$(jq '.total_matches // 0' "$cross_repo_cache" 2>/dev/null) || xr_matches=0
            echo "[CROSS-REPO] Found $xr_matches cross-repo pattern matches"

            # Record in bridge state
            if command -v jq &>/dev/null && [[ -f "$BRIDGE_STATE_FILE" ]]; then
              jq --argjson m "$xr_matches" \
                '.metrics.cross_repo_matches = ((.metrics.cross_repo_matches // 0) + $m)' \
                "$BRIDGE_STATE_FILE" > "$BRIDGE_STATE_FILE.tmp"
              mv "$BRIDGE_STATE_FILE.tmp" "$BRIDGE_STATE_FILE"
            fi
          fi
        fi
        rm -f "$diff_file"
      fi
    fi

    # 2c.1: Vision Relevance Check (FR-3)
    local vision_activation_enabled
    vision_activation_enabled=$(yq '.run_bridge.vision_registry.activation_enabled // false' "$CONFIG_FILE" 2>/dev/null || echo "false")
    if [[ "$vision_activation_enabled" == "true" ]]; then
      echo "[VISION CHECK] Scanning for relevant visions..."
      echo "SIGNAL:VISION_CHECK:$iteration"

      if [[ -x "$SCRIPT_DIR/bridge-vision-capture.sh" ]]; then
        local vcheck_diff
        vcheck_diff=$(mktemp "${TMPDIR:-/tmp}/bridge-vcheck.XXXXXX")
        git diff "origin/main...HEAD" > "$vcheck_diff" 2>/dev/null || true

        if [[ -s "$vcheck_diff" ]]; then
          local relevant_visions
          relevant_visions=$("$SCRIPT_DIR/bridge-vision-capture.sh" --check-relevant "$vcheck_diff" 2>/dev/null) || true

          if [[ -n "$relevant_visions" ]]; then
            echo "[VISION CHECK] Relevant visions: $relevant_visions"

            # Record in bridge state
            if command -v jq &>/dev/null && [[ -f "$BRIDGE_STATE_FILE" ]]; then
              local vision_arr
              vision_arr=$(echo "$relevant_visions" | jq -R . | jq -s .)
              jq --argjson v "$vision_arr" \
                '.metrics.visions_referenced = ((.metrics.visions_referenced // []) + $v | unique)' \
                "$BRIDGE_STATE_FILE" > "$BRIDGE_STATE_FILE.tmp"
              mv "$BRIDGE_STATE_FILE.tmp" "$BRIDGE_STATE_FILE"
            fi
          fi
        fi
        rm -f "$vcheck_diff"
      fi
    fi

    # 2d: Load QMD context for review enrichment
    local sprint_goal
    sprint_goal=$(grep -m1 "^## Sprint" "$PROJECT_ROOT/grimoires/loa/sprint.md" 2>/dev/null | sed 's/^## //' || echo "bridge iteration $iteration")
    load_bridge_context "$sprint_goal"

    # 2e: Bridgebuilder Review
    if [[ -n "$BRIDGE_CONTEXT" ]]; then
      echo "[CONTEXT] QMD context loaded (${#BRIDGE_CONTEXT} bytes)"
    fi
    echo "[REVIEW] Invoking Bridgebuilder review..."
    echo "SIGNAL:BRIDGEBUILDER_REVIEW:$iteration"

    # 2f: Lore Reference Scan (FR-5)
    echo "[LORE REFS] Scanning review for lore references..."
    echo "SIGNAL:LORE_REFERENCE_SCAN:$iteration"
    if [[ -x "$SCRIPT_DIR/lore-discover.sh" ]]; then
      local bridge_id
      bridge_id=$(jq -r '.bridge_id // ""' "$BRIDGE_STATE_FILE" 2>/dev/null) || bridge_id=""
      local review_dir="${PROJECT_ROOT}/.run/bridge-reviews"
      local latest_review
      latest_review=$(find "$review_dir" -name "${bridge_id}*-iter${iteration}-full.md" 2>/dev/null | head -1) || true

      if [[ -n "$latest_review" && -f "$latest_review" ]]; then
        "$SCRIPT_DIR/lore-discover.sh" \
          --scan-references \
          --bridge-id "$bridge_id" \
          --review-file "$latest_review" \
          --repo-name "loa" 2>/dev/null || true
      fi
    fi

    # 2g: Vision Capture
    echo "[VISION] Capturing VISION findings..."
    echo "SIGNAL:VISION_CAPTURE:$iteration"

    # 2h: GitHub Trail
    echo "[TRAIL] Posting to GitHub..."
    echo "SIGNAL:GITHUB_TRAIL:$iteration"

    # 2i: Flatline Detection
    echo "[FLATLINE] Checking flatline condition..."
    echo "SIGNAL:FLATLINE_CHECK:$iteration"

    # Mark iteration as completed
    update_iteration "$iteration" "completed"

    # Check flatline
    local flatlined
    flatlined=$(is_flatlined "$CONSECUTIVE_FLATLINE")
    if [[ "$flatlined" == "true" ]]; then
      echo ""
      echo "═══════════════════════════════════════════════════"
      echo "  FLATLINE DETECTED"
      echo "  Terminating after $iteration iterations"
      echo "═══════════════════════════════════════════════════"
      break
    fi

    # Check per-iteration timeout
    local iter_elapsed=$((SECONDS - iter_start_time))
    if [[ $iter_elapsed -gt $PER_ITERATION_TIMEOUT ]]; then
      echo "WARNING: Per-iteration timeout exceeded ($iter_elapsed s > $PER_ITERATION_TIMEOUT s)"
      update_bridge_state "HALTED"
      exit 1
    fi

    # Check total timeout
    local total_elapsed=$((SECONDS - total_start_time))
    if [[ $total_elapsed -gt $TOTAL_TIMEOUT ]]; then
      echo "WARNING: Total timeout exceeded ($total_elapsed s > $TOTAL_TIMEOUT s)"
      update_bridge_state "HALTED"
      exit 1
    fi

    iteration=$((iteration + 1))
  done

  # Research Mode (FR-2 — Divergent Exploration Iteration)
  # After iteration 1, optionally transition to RESEARCHING state for one
  # divergent exploration iteration. Produces SPECULATION-only findings
  # with N/A score excluded from flatline trajectory.
  local research_mode_enabled
  research_mode_enabled=$(yq '.run_bridge.research_mode.enabled // false' "$CONFIG_FILE" 2>/dev/null || echo "false")
  local research_trigger_after
  research_trigger_after=$(yq '.run_bridge.research_mode.trigger_after_iteration // 1' "$CONFIG_FILE" 2>/dev/null || echo "1")
  local research_max
  research_max=$(yq '.run_bridge.research_mode.max_research_iterations // 1' "$CONFIG_FILE" 2>/dev/null || echo "1")
  local research_completed=0

  # Check bridge state for prior research iterations (for resume support)
  if command -v jq &>/dev/null && [[ -f "$BRIDGE_STATE_FILE" ]]; then
    research_completed=$(jq '.metrics.research_iterations_completed // 0' "$BRIDGE_STATE_FILE" 2>/dev/null) || research_completed=0
  fi

  # -ge: trigger_after_iteration=N means "fire after iteration N completes"
  if [[ "$research_mode_enabled" == "true" ]] && [[ $iteration -ge $research_trigger_after ]] && [[ $research_completed -lt $research_max ]]; then
    echo ""
    echo "═══════════════════════════════════════════════════"
    echo "  RESEARCHING — Divergent Exploration"
    echo "═══════════════════════════════════════════════════"

    update_bridge_state "RESEARCHING"

    # Signal for the skill layer to compose a research prompt
    # including cross-repo context, top lore entries, and relevant visions.
    echo "SIGNAL:RESEARCH_ITERATION:$((research_completed + 1))"

    # Inquiry Mode (FR-4): If inquiry_enabled, trigger multi-model architectural inquiry
    local inquiry_enabled
    inquiry_enabled=$(yq '.run_bridge.research_mode.inquiry_enabled // false' "$CONFIG_FILE" 2>/dev/null || echo "false")
    if [[ "$inquiry_enabled" == "true" ]] && [[ -x "$SCRIPT_DIR/flatline-orchestrator.sh" ]]; then
      echo "[INQUIRY] Triggering multi-model architectural inquiry..."
      echo "SIGNAL:INQUIRY_MODE:$((research_completed + 1))"

      # Feed cross-repo context into inquiry if available
      local cross_repo_cache="${PROJECT_ROOT}/.run/cross-repo-context.json"
      local inquiry_context=""
      if [[ -f "$cross_repo_cache" ]]; then
        inquiry_context=$(mktemp "${TMPDIR:-/tmp}/bridge-inquiry-ctx.XXXXXX")
        jq -r '.results[]? | "## \(.repo)\n\(.matches[]? | "- \(.pattern): \(.context)")"' \
          "$cross_repo_cache" > "$inquiry_context" 2>/dev/null || true
      fi

      # Find the document for inquiry (sprint.md or sdd.md)
      local inquiry_doc="${PROJECT_ROOT}/grimoires/loa/sprint.md"
      if [[ ! -f "$inquiry_doc" ]]; then
        inquiry_doc="${PROJECT_ROOT}/grimoires/loa/sdd.md"
      fi

      if [[ -f "$inquiry_doc" ]]; then
        local inquiry_output
        inquiry_output=$("$SCRIPT_DIR/flatline-orchestrator.sh" \
          --doc "$inquiry_doc" \
          --phase "sprint" \
          --mode inquiry \
          --json 2>/dev/null) || true

        if [[ -n "$inquiry_output" ]]; then
          local inquiry_findings
          inquiry_findings=$(echo "$inquiry_output" | jq '.summary.total_findings // 0' 2>/dev/null) || inquiry_findings=0
          echo "[INQUIRY] Inquiry produced $inquiry_findings findings"

          # Record in bridge state
          if command -v jq &>/dev/null && [[ -f "$BRIDGE_STATE_FILE" ]]; then
            jq --argjson f "$inquiry_findings" \
              '.metrics.inquiry_findings = ((.metrics.inquiry_findings // 0) + $f)' \
              "$BRIDGE_STATE_FILE" > "$BRIDGE_STATE_FILE.tmp"
            mv "$BRIDGE_STATE_FILE.tmp" "$BRIDGE_STATE_FILE"
          fi
        fi
      fi
      rm -f "$inquiry_context"
    fi

    research_completed=$((research_completed + 1))

    # Record in bridge state
    if command -v jq &>/dev/null && [[ -f "$BRIDGE_STATE_FILE" ]]; then
      jq --argjson rc "$research_completed" \
        '.metrics.research_iterations_completed = $rc' \
        "$BRIDGE_STATE_FILE" > "$BRIDGE_STATE_FILE.tmp"
      mv "$BRIDGE_STATE_FILE.tmp" "$BRIDGE_STATE_FILE"
    fi

    # Transition back to ITERATING (research iteration doesn't affect flatline)
    update_bridge_state "ITERATING"

    # Lore reference scan on research output
    echo "[LORE REFS] Scanning research output for lore references..."
    if [[ -x "$SCRIPT_DIR/lore-discover.sh" ]]; then
      local bridge_id
      bridge_id=$(jq -r '.bridge_id // ""' "$BRIDGE_STATE_FILE" 2>/dev/null) || bridge_id=""
      local research_review
      research_review=$(find "${PROJECT_ROOT}/.run/bridge-reviews" \
        -name "${bridge_id}*-research-*.md" 2>/dev/null | sort | tail -1) || true

      if [[ -n "$research_review" && -f "$research_review" ]]; then
        "$SCRIPT_DIR/lore-discover.sh" \
          --scan-references \
          --bridge-id "$bridge_id" \
          --review-file "$research_review" \
          --repo-name "loa" 2>/dev/null || true
      fi
    fi
  fi

  # Vision Sprint (v1.39.0 — Dedicated Exploration Time)
  # After flatline convergence, optionally run a vision sprint to explore
  # captured visions from the registry. Output is architectural proposals, not code.
  local vision_sprint_enabled
  vision_sprint_enabled=$(yq '.run_bridge.vision_sprint.enabled // false' "$CONFIG_FILE" 2>/dev/null || echo "false")

  if [[ "$vision_sprint_enabled" == "true" ]]; then
    local vision_timeout
    vision_timeout=$(yq '.run_bridge.vision_sprint.timeout_minutes // 10' "$CONFIG_FILE" 2>/dev/null || echo "10")

    echo ""
    echo "═══════════════════════════════════════════════════"
    echo "  EXPLORING — Vision Sprint"
    echo "═══════════════════════════════════════════════════"

    update_bridge_state "EXPLORING"

    # The vision sprint signal is handled by the skill layer (run-bridge).
    # It reads the vision registry, generates architectural proposals,
    # and saves them to .run/bridge-reviews/{bridge_id}-vision-sprint.md.
    #
    # Defense-in-depth: wrap the vision sprint phase in a hard timeout.
    # The skill layer reads SIGNAL lines and performs the actual work. We emit the
    # signals, then block on a sentinel file that the skill layer writes on completion.
    # The timeout wraps the WAIT, not the echo — this is what actually enforces the bound.
    echo "[VISION SPRINT] Reviewing captured visions (hard timeout: ${vision_timeout}m)..."

    local vision_sentinel="${PROJECT_ROOT}/.run/vision-sprint-done"
    rm -f "$vision_sentinel"

    # Emit signals for the skill layer to act on.
    # CONTRACT: The skill layer MUST touch $vision_sentinel when vision sprint
    # completes (success or failure). If this contract is not honored, the
    # orchestrator's timeout will fire as a safety net.
    echo "SIGNAL:VISION_SPRINT"
    echo "SIGNAL:VISION_SPRINT_TIMEOUT:${vision_timeout}"
    echo "SIGNAL:VISION_SPRINT_SENTINEL:${vision_sentinel}"

    # Block until the skill layer writes the sentinel, bounded by hard timeout.
    # Uses env var to avoid word-splitting issues with paths containing spaces.
    local vision_timed_out=false
    if ! VISION_SENTINEL="$vision_sentinel" timeout --signal=TERM "$((vision_timeout * 60))" \
      bash -c 'while [[ ! -f "$VISION_SENTINEL" ]]; do sleep 2; done'; then
      echo "WARNING: Vision sprint timed out after ${vision_timeout}m — proceeding to finalization"
      vision_timed_out=true
    fi
    rm -f "$vision_sentinel"

    # Record in bridge state
    if command -v jq &>/dev/null && [[ -f "$BRIDGE_STATE_FILE" ]]; then
      if [[ "$vision_timed_out" == "true" ]]; then
        jq '.finalization.vision_sprint = true | .finalization.vision_sprint_timeout = true' "$BRIDGE_STATE_FILE" > "$BRIDGE_STATE_FILE.tmp"
      else
        jq '.finalization.vision_sprint = true | .finalization.vision_sprint_timeout = false' "$BRIDGE_STATE_FILE" > "$BRIDGE_STATE_FILE.tmp"
      fi
      mv "$BRIDGE_STATE_FILE.tmp" "$BRIDGE_STATE_FILE"
    fi
  fi

  # Finalization
  echo ""
  echo "═══════════════════════════════════════════════════"
  echo "  FINALIZING"
  echo "═══════════════════════════════════════════════════"

  update_bridge_state "FINALIZING"

  echo "[GT] Updating Grounded Truth..."
  echo "SIGNAL:GROUND_TRUTH_UPDATE"

  # BUTTERFREEZONE generation (SDD 3.4) — between GT update and RTFM gate
  if is_butterfreezone_enabled; then
    echo "[BUTTERFREEZONE] Regenerating agent-grounded README..."
    echo "SIGNAL:BUTTERFREEZONE_GEN"
    local butterfreezone_gen_exit=0
    local bfz_stderr_file
    bfz_stderr_file=$(mktemp "${TMPDIR:-/tmp}/bfz-stderr.XXXXXX")
    .claude/scripts/butterfreezone-gen.sh --json 2>"$bfz_stderr_file" || butterfreezone_gen_exit=$?

    if [[ $butterfreezone_gen_exit -eq 0 ]]; then
      echo "[BUTTERFREEZONE] BUTTERFREEZONE.md regenerated"
      git add BUTTERFREEZONE.md 2>/dev/null || true
    else
      echo "[BUTTERFREEZONE] WARNING: Generation failed (exit $butterfreezone_gen_exit) — non-blocking"
      # Surface security-related failures (redaction check, etc.)
      if grep -qi "secret\|redact\|BLOCKING\|credential" "$bfz_stderr_file" 2>/dev/null; then
        echo "[BUTTERFREEZONE] SECURITY: stderr contains security-related messages:"
        cat "$bfz_stderr_file" >&2
      fi
    fi
    rm -f "$bfz_stderr_file"

    # Update bridge state
    if command -v jq &>/dev/null && [[ -f "$BRIDGE_STATE_FILE" ]]; then
      jq --argjson val "$([ $butterfreezone_gen_exit -eq 0 ] && echo true || echo false)" \
        '.finalization.butterfreezone_generated = $val' "$BRIDGE_STATE_FILE" > "$BRIDGE_STATE_FILE.tmp"
      mv "$BRIDGE_STATE_FILE.tmp" "$BRIDGE_STATE_FILE"
    fi
  fi

  # Lore Discovery (v1.39.0 — Bidirectional Lore)
  # Extract patterns from bridge reviews for the discovered-patterns lore category
  local lore_discovery_enabled
  lore_discovery_enabled=$(yq '.run_bridge.lore_discovery.enabled // false' "$CONFIG_FILE" 2>/dev/null || echo "false")

  if [[ "$lore_discovery_enabled" == "true" ]]; then
    echo "[LORE] Running pattern discovery..."
    echo "SIGNAL:LORE_DISCOVERY"

    local lore_candidates=0
    if [[ -x ".claude/scripts/lore-discover.sh" ]]; then
      local lore_output
      lore_output=$(.claude/scripts/lore-discover.sh --bridge-id "$BRIDGE_ID" 2>/dev/null) || true
      lore_candidates=$(echo "$lore_output" | grep -o '[0-9]*' | head -1) || lore_candidates=0
      echo "[LORE] Discovered $lore_candidates candidate patterns"
    else
      echo "[LORE] lore-discover.sh not found — skipping"
    fi

    # Record in bridge state
    if command -v jq &>/dev/null && [[ -f "$BRIDGE_STATE_FILE" ]]; then
      jq --argjson candidates "${lore_candidates:-0}" \
        '.finalization.lore_discovery = {candidates: $candidates}' \
        "$BRIDGE_STATE_FILE" > "$BRIDGE_STATE_FILE.tmp"
      mv "$BRIDGE_STATE_FILE.tmp" "$BRIDGE_STATE_FILE"
    fi
  else
    echo "[LORE] Skipped (disabled in config — set run_bridge.lore_discovery.enabled: true to enable)"
  fi

  # RTFM gate: test GT index, README, new protocol docs
  # Max 1 fix iteration to prevent circular loops
  local rtfm_enabled
  rtfm_enabled=$(yq '.run_bridge.rtfm.enabled // true' "$CONFIG_FILE" 2>/dev/null || echo "true")
  local rtfm_max_fix
  rtfm_max_fix=$(yq '.run_bridge.rtfm.max_fix_iterations // 1' "$CONFIG_FILE" 2>/dev/null || echo "1")

  if [[ "$rtfm_enabled" == "true" ]]; then
    echo "[RTFM] Running documentation gate..."
    echo "SIGNAL:RTFM_PASS"

    # RTFM retry logic: on FAILURE, generate 1 fix sprint, re-test
    # On second FAILURE, log warning and continue (non-blocking)
    local rtfm_attempt=0
    while [[ $rtfm_attempt -lt $rtfm_max_fix ]]; do
      echo "SIGNAL:RTFM_CHECK_RESULT:$rtfm_attempt"
      rtfm_attempt=$((rtfm_attempt + 1))
    done
  else
    echo "[RTFM] Skipped (disabled in config)"
  fi

  echo "[PR] Updating final PR..."
  echo "SIGNAL:FINAL_PR_UPDATE"

  # Record RTFM result in state (default to true — actual result set by agent)
  if command -v jq &>/dev/null && [[ -f "$BRIDGE_STATE_FILE" ]]; then
    jq '.finalization.rtfm_passed = true' "$BRIDGE_STATE_FILE" > "$BRIDGE_STATE_FILE.tmp"
    mv "$BRIDGE_STATE_FILE.tmp" "$BRIDGE_STATE_FILE"
  fi

  update_bridge_state "JACKED_OUT"

  echo ""
  echo "═══════════════════════════════════════════════════"
  echo "  JACKED OUT — Bridge complete"
  echo "═══════════════════════════════════════════════════"

  # Print summary
  local metrics
  metrics=$(jq '.metrics' "$BRIDGE_STATE_FILE")
  echo ""
  echo "Metrics:"
  echo "  Sprints executed: $(echo "$metrics" | jq '.total_sprints_executed')"
  echo "  Files changed: $(echo "$metrics" | jq '.total_files_changed')"
  echo "  Findings addressed: $(echo "$metrics" | jq '.total_findings_addressed')"
  echo "  Visions captured: $(echo "$metrics" | jq '.total_visions_captured')"
}

# =============================================================================
# Entry Point
# =============================================================================

bridge_main
