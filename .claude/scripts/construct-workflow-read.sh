#!/usr/bin/env bash
# construct-workflow-read.sh — Read and validate workflow section from pack manifest
# Part of: Construct-Aware Constraint Yielding (cycle-029, FR-1)
#
# Usage:
#   construct-workflow-read.sh <manifest_path>           # Full read → JSON stdout
#   construct-workflow-read.sh <manifest_path> --gate <name>  # Single gate value
#
# Exit codes:
#   0 — Valid workflow found (or gate found)
#   1 — No workflow section (pack uses default pipeline)
#   2 — Validation error (invalid values, implement: skip)
set -euo pipefail

# ── Constants ──────────────────────────────────────────

# Valid gate values per SDD Section 3.1
readonly VALID_DEPTH="light standard deep full"
readonly VALID_GATES_PRD="skip condense full"
readonly VALID_GATES_SDD="skip condense full"
readonly VALID_GATES_SPRINT="skip condense full"
readonly VALID_GATES_IMPLEMENT="required"
readonly VALID_GATES_REVIEW="skip visual textual both"
readonly VALID_GATES_AUDIT="skip lightweight full"
readonly VALID_VERIFICATION="visual tsc build test manual"

# ── Helpers ────────────────────────────────────────────

die()  { echo "ERROR: $*" >&2; exit 2; }
warn() { echo "ADVISORY: $*" >&2; }

# Check if value is in a space-separated list
value_in() {
  local value="$1" list="$2"
  for v in $list; do
    [[ "$v" == "$value" ]] && return 0
  done
  return 1
}

# ── Validation ─────────────────────────────────────────

validate_workflow() {
  local workflow="$1"

  # Validate depth
  local depth
  depth=$(echo "$workflow" | jq -r '.depth // "full"')
  if ! value_in "$depth" "$VALID_DEPTH"; then
    die "Invalid workflow.depth: '$depth'. Valid: $VALID_DEPTH"
  fi

  # Validate app_zone_access (must be boolean or absent)
  local aza
  aza=$(echo "$workflow" | jq -r '.app_zone_access // "false"')
  if [[ "$aza" != "true" && "$aza" != "false" ]]; then
    die "Invalid workflow.app_zone_access: '$aza'. Must be true or false."
  fi

  # Validate each gate
  local gate_val

  gate_val=$(echo "$workflow" | jq -r '.gates.prd // "full"')
  if ! value_in "$gate_val" "$VALID_GATES_PRD"; then
    die "Invalid workflow.gates.prd: '$gate_val'. Valid: $VALID_GATES_PRD"
  fi
  [[ "$gate_val" == "condense" ]] && warn "condense treated as full this cycle (gates.prd)"

  gate_val=$(echo "$workflow" | jq -r '.gates.sdd // "full"')
  if ! value_in "$gate_val" "$VALID_GATES_SDD"; then
    die "Invalid workflow.gates.sdd: '$gate_val'. Valid: $VALID_GATES_SDD"
  fi
  [[ "$gate_val" == "condense" ]] && warn "condense treated as full this cycle (gates.sdd)"

  gate_val=$(echo "$workflow" | jq -r '.gates.sprint // "full"')
  if ! value_in "$gate_val" "$VALID_GATES_SPRINT"; then
    die "Invalid workflow.gates.sprint: '$gate_val'. Valid: $VALID_GATES_SPRINT"
  fi
  [[ "$gate_val" == "condense" ]] && warn "condense treated as full this cycle (gates.sprint)"

  gate_val=$(echo "$workflow" | jq -r '.gates.implement // "required"')
  if [[ "$gate_val" == "skip" ]]; then
    die "implement gate cannot be skip. implement: required is enforced."
  fi
  if ! value_in "$gate_val" "$VALID_GATES_IMPLEMENT"; then
    die "Invalid workflow.gates.implement: '$gate_val'. Valid: $VALID_GATES_IMPLEMENT"
  fi

  gate_val=$(echo "$workflow" | jq -r '.gates.review // "textual"')
  if ! value_in "$gate_val" "$VALID_GATES_REVIEW"; then
    die "Invalid workflow.gates.review: '$gate_val'. Valid: $VALID_GATES_REVIEW"
  fi

  gate_val=$(echo "$workflow" | jq -r '.gates.audit // "full"')
  if ! value_in "$gate_val" "$VALID_GATES_AUDIT"; then
    die "Invalid workflow.gates.audit: '$gate_val'. Valid: $VALID_GATES_AUDIT"
  fi

  # Validate verification method
  local method
  method=$(echo "$workflow" | jq -r '.verification.method // "test"')
  if ! value_in "$method" "$VALID_VERIFICATION"; then
    die "Invalid workflow.verification.method: '$method'. Valid: $VALID_VERIFICATION"
  fi

  return 0
}

# ── Gate Query ─────────────────────────────────────────

query_gate() {
  local workflow="$1" gate="$2"

  # Map gate to default
  local default
  case "$gate" in
    prd|sdd|sprint) default="full" ;;
    implement)      default="required" ;;
    review)         default="textual" ;;
    audit)          default="full" ;;
    *)              die "Unknown gate: '$gate'. Valid: prd, sdd, sprint, implement, review, audit" ;;
  esac

  local value
  value=$(echo "$workflow" | jq -r --arg g "$gate" '.gates[$g] // "'"$default"'"')

  # Enforce implement cannot be skip
  if [[ "$gate" == "implement" && "$value" == "skip" ]]; then
    die "implement gate cannot be skip"
  fi

  # Log condense advisory
  if [[ "$value" == "condense" ]]; then
    warn "condense treated as full this cycle (gates.$gate)"
  fi

  echo "$value"
}

# ── Main ───────────────────────────────────────────────

main() {
  local manifest="${1:-}"
  [[ -z "$manifest" ]] && { echo "Usage: $0 <manifest_path> [--gate <name>]" >&2; exit 2; }

  # Fail-closed: parse error → exit 1 (no workflow)
  local workflow
  workflow=$(jq -e '.workflow // empty' "$manifest" 2>/dev/null) || exit 1

  # Check if workflow is empty/null
  if [[ -z "$workflow" || "$workflow" == "null" ]]; then
    exit 1
  fi

  local mode="${2:---read}"

  case "$mode" in
    --gate)
      local gate="${3:-}"
      [[ -z "$gate" ]] && die "Usage: $0 <manifest_path> --gate <name>"
      query_gate "$workflow" "$gate"
      ;;
    --read|*)
      validate_workflow "$workflow"
      echo "$workflow"
      ;;
  esac
}

main "$@"
