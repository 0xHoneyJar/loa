#!/usr/bin/env bash
# =============================================================================
# construct-compose.sh — composition runner (cycle-005 L1)
# =============================================================================
# Reads a composition YAML from grimoires/compositions/<name>.yaml and
# executes its pipe chain: validates type compatibility at chain-build time,
# sequences stages via construct-invoke.sh entry/exit, pipes stdin/stdout
# between stages, emits a final summary at the requested read-mode.
#
# Doctrine:
#   §3  — typed streams (Signal/Verdict/Artifact/Intent/Operator-Model)
#   §4  — composition = pipe chain spec
#   §5  — runner is the shell-equivalent layer (layer 4 in §5.1)
#   §13.1 — shell-first, no TypeScript
#   §14.3 — three read-modes (glance / orient / intervene)
#   §16.4 — agent-transparency invariant: active set + trajectory on every stage
#
# Usage:
#   construct-compose.sh <composition-name> [options]
#   construct-compose.sh feel-audit --target src/app/ui/Button.tsx
#
# Options:
#   --target PATH           Input artifact path (binds composition.inputs[type=Artifact])
#   --input JSON            Raw JSON value for the first-stage stdin (overrides --target)
#   --dry-run               Validate + print plan; no trajectory emitted, no stages run
#   --run-id ID             Override generated run_id (useful in tests)
#   --executor PATH         Override stage executor (env LOA_COMPOSE_STAGE_EXECUTOR)
#   --compositions-dir DIR  Override compositions search dir (default: grimoires/compositions)
#   --glance                Summary: 1 line (default)
#   --orient                Summary: 3-6 lines, per-stage durations
#   --intervene             Summary: full JSON blob on stderr
#   -h, --help              Print this help
#
# Exit codes:
#   0 = success
#   1 = composition missing or malformed
#   2 = type-compatibility failure (reported with stage + expected vs produced)
#   3 = stage execution failure
#   4 = final-output schema validation failure
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
DEFAULT_COMPOSITIONS_DIR="${LOA_COMPOSITIONS_DIR:-$PROJECT_ROOT/grimoires/compositions}"
TRAJECTORY_FILE="${LOA_TRAJECTORY_FILE:-$PROJECT_ROOT/.run/construct-trajectory.jsonl}"
FEEDBACK_FILE="${LOA_FEEDBACK_FILE:-$PROJECT_ROOT/.run/feedback-v3.jsonl}"
SCHEMA_VERSION="1.0.0"

# --------------------------------------------------------------------------
# Args
# --------------------------------------------------------------------------
COMPOSITION_NAME=""
TARGET_PATH=""
RAW_INPUT=""
DRY_RUN=0
RUN_ID=""
STAGE_EXECUTOR="${LOA_COMPOSE_STAGE_EXECUTOR:-}"
COMPOSITIONS_DIR="$DEFAULT_COMPOSITIONS_DIR"
READ_MODE="glance"

usage() {
  sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

die() {
  local code="${1:-1}"
  shift || true
  echo "[construct-compose] ERROR: $*" >&2
  exit "$code"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)           usage; exit 0 ;;
    --target)            TARGET_PATH="$2"; shift 2 ;;
    --input)             RAW_INPUT="$2"; shift 2 ;;
    --dry-run)           DRY_RUN=1; shift ;;
    --run-id)            RUN_ID="$2"; shift 2 ;;
    --executor)          STAGE_EXECUTOR="$2"; shift 2 ;;
    --compositions-dir)  COMPOSITIONS_DIR="$2"; shift 2 ;;
    --glance)            READ_MODE="glance"; shift ;;
    --orient)            READ_MODE="orient"; shift ;;
    --intervene)         READ_MODE="intervene"; shift ;;
    --) shift; break ;;
    -*) die 1 "unknown flag: $1" ;;
    *)  if [[ -z "$COMPOSITION_NAME" ]]; then COMPOSITION_NAME="$1"; else die 1 "unexpected positional: $1"; fi; shift ;;
  esac
done

[[ -n "$COMPOSITION_NAME" ]] || { usage >&2; die 1 "composition name required"; }

# --------------------------------------------------------------------------
# Tool dependencies
# --------------------------------------------------------------------------
command -v yq >/dev/null 2>&1 || die 1 "yq (v4+) required — install via 'brew install yq' or equivalent"
command -v jq >/dev/null 2>&1 || die 1 "jq required"

# --------------------------------------------------------------------------
# Composition load
# --------------------------------------------------------------------------
COMPOSITION_FILE="$COMPOSITIONS_DIR/$COMPOSITION_NAME.yaml"
[[ -f "$COMPOSITION_FILE" ]] || die 1 "composition not found: $COMPOSITION_FILE"

COMPOSITION_JSON=$(yq -o=json '.' "$COMPOSITION_FILE" 2>/dev/null) \
  || die 1 "failed to parse YAML: $COMPOSITION_FILE"

STAGE_COUNT=$(echo "$COMPOSITION_JSON" | jq -r '.chain | length')
(( STAGE_COUNT > 0 )) || die 1 "composition '$COMPOSITION_NAME' has empty chain"

# --------------------------------------------------------------------------
# run_id
# --------------------------------------------------------------------------
if [[ -z "$RUN_ID" ]]; then
  RUN_ID=$(uuidgen 2>/dev/null \
           || python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null \
           || echo "compose-$(date +%s)-$$")
fi

# --------------------------------------------------------------------------
# Persona resolution — first persona of the stage's construct
# --------------------------------------------------------------------------
resolve_persona() {
  local slug="$1"
  local resolver="$SCRIPT_DIR/construct-resolve.sh"
  local persona=""
  if [[ -x "$resolver" ]]; then
    persona=$("$resolver" resolve "$slug" --json 2>/dev/null \
              | jq -r '.construct.personas[0] // empty' 2>/dev/null || echo "")
  fi
  if [[ -z "$persona" ]]; then
    # Fallback: uppercase slug prefix
    persona=$(echo "$slug" | tr '[:lower:]' '[:upper:]')
  fi
  echo "$persona"
}

# --------------------------------------------------------------------------
# Type-compatibility check (chain-build-time)
# --------------------------------------------------------------------------
# Per doctrine §4: every pipe edge's types must align. A stage's `reads` must
# be satisfiable by the union of composition inputs + all prior stages' writes.
# --------------------------------------------------------------------------
produced_types=()
inputs_types=$(echo "$COMPOSITION_JSON" | jq -r '.inputs[]?.type // empty')
while IFS= read -r t; do
  [[ -z "$t" ]] && continue
  produced_types+=("$t")
done <<< "$inputs_types"

set_contains() {
  local needle="$1"; shift
  for x in "$@"; do
    [[ "$x" == "$needle" ]] && return 0
  done
  return 1
}

# Pre-flight: verify every stage's reads ⊆ produced-so-far
for (( i=0; i<STAGE_COUNT; i++ )); do
  stage_json=$(echo "$COMPOSITION_JSON" | jq -c ".chain[$i]")
  stage_label=$(echo "$stage_json" | jq -r '.stage // (. | tostring)')
  reads=$(echo "$stage_json" | jq -r '(.reads // [])[]')
  while IFS= read -r r; do
    [[ -z "$r" ]] && continue
    if ! set_contains "$r" "${produced_types[@]}"; then
      produced_csv=$(IFS=, ; echo "${produced_types[*]}")
      die 2 "type mismatch at stage $stage_label: reads '$r' but upstream has produced only [$produced_csv]"
    fi
  done <<< "$reads"
  writes=$(echo "$stage_json" | jq -r '(.writes // [])[]')
  while IFS= read -r w; do
    [[ -z "$w" ]] && continue
    set_contains "$w" "${produced_types[@]}" || produced_types+=("$w")
  done <<< "$writes"
done

# --------------------------------------------------------------------------
# Plan output
# --------------------------------------------------------------------------
print_plan() {
  echo "[construct-compose] composition=$COMPOSITION_NAME run_id=$RUN_ID stages=$STAGE_COUNT" >&2
  for (( i=0; i<STAGE_COUNT; i++ )); do
    local s construct skill reads writes stage_label
    s=$(echo "$COMPOSITION_JSON" | jq -c ".chain[$i]")
    stage_label=$(echo "$s" | jq -r '.stage // empty')
    construct=$(echo "$s" | jq -r '.construct')
    skill=$(echo "$s" | jq -r '.skill // "<none>"')
    reads=$(echo "$s" | jq -r '(.reads // []) | join(",")')
    writes=$(echo "$s" | jq -r '(.writes // []) | join(",")')
    printf "[construct-compose] stage %s: %s::%s reads=[%s] writes=[%s]\n" \
      "${stage_label:-$((i+1))}" "$construct" "$skill" "$reads" "$writes" >&2
  done
}

if (( DRY_RUN )); then
  print_plan
  echo "[construct-compose] dry-run OK — type compatibility verified, no stages executed" >&2
  exit 0
fi

# --------------------------------------------------------------------------
# Initial stdin payload for stage 1
# --------------------------------------------------------------------------
emit_initial_payload() {
  if [[ -n "$RAW_INPUT" ]]; then
    printf '%s' "$RAW_INPUT"
    return
  fi
  # Build a seed payload that carries composition inputs to stage 1 via stdin.
  # Stage 1's reads determine which typed fields we populate.
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local target_path="$TARGET_PATH"
  [[ -z "$target_path" ]] && target_path="<unspecified>"
  jq -n \
    --arg run_id "$RUN_ID" \
    --arg composition "$COMPOSITION_NAME" \
    --arg ts "$ts" \
    --arg target "$target_path" \
    --arg schema_version "$SCHEMA_VERSION" \
    '{
      _compose_meta: {
        run_id: $run_id,
        composition: $composition,
        timestamp: $ts,
        schema_version: $schema_version
      },
      inputs: {
        target: $target
      }
    }'
}

# --------------------------------------------------------------------------
# Default stage executor (stub)
#
# Produces a schema-valid placeholder row for the primary type in `writes`.
# Designed to be swapped via --executor / $LOA_COMPOSE_STAGE_EXECUTOR when
# real LLM-driven skill dispatch ships (cycle-006+ orchestrator).
#
# Stdin: previous stage output (JSON, may be empty on stage 1 if no inputs)
# Args: construct_slug skill persona stage_label writes_csv run_id session_id
# Stdout: JSON row conforming to the PRIMARY write type's schema
# --------------------------------------------------------------------------
default_stage_executor() {
  local construct="$1" skill="$2" persona="$3" stage_label="$4" writes_csv="$5" run_id="$6" session_id="$7"
  local primary_type
  primary_type=$(echo "$writes_csv" | awk -F',' '{print $1}')
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # Carry forward prior stage output for transparency.
  local prior=""
  if [[ ! -t 0 ]]; then
    prior=$(cat -)
  fi

  case "$primary_type" in
    Signal)
      jq -n \
        --arg ts "$ts" --arg source "$construct/$skill" --arg persona "$persona" \
        --arg observation "[stub] stage $stage_label · $construct/$skill executed over upstream payload" \
        --arg schema_version "$SCHEMA_VERSION" --arg run_id "$run_id" --arg session_id "$session_id" \
        --argjson prior "${prior:-null}" \
        '{
          stream_type: "Signal",
          schema_version: $schema_version,
          timestamp: $ts,
          source: $source,
          observation: $observation,
          tags: ["stub", "composition", $persona],
          session_id: $session_id,
          run_id: $run_id,
          _prior: $prior
        }'
      ;;
    Verdict)
      jq -n \
        --arg ts "$ts" --arg source "$persona" --arg schema_version "$SCHEMA_VERSION" \
        --arg run_id "$run_id" --arg session_id "$session_id" \
        --arg verdict "[stub] stage $stage_label · $construct/$skill judgment placeholder — swap executor for real skill dispatch" \
        --arg glance "[stub $persona] stage $stage_label verdict" \
        --argjson prior "${prior:-null}" \
        '{
          stream_type: "Verdict",
          schema_version: $schema_version,
          timestamp: $ts,
          source: $source,
          verdict: $verdict,
          severity: "info",
          evidence: [],
          glance: $glance,
          session_id: $session_id,
          run_id: $run_id,
          _prior: $prior
        }'
      ;;
    Artifact)
      jq -n \
        --arg ts "$ts" --arg producer "$construct/$skill" --arg schema_version "$SCHEMA_VERSION" \
        --arg run_id "$run_id" --arg session_id "$session_id" \
        --arg path "${TARGET_PATH:-/tmp/stub-artifact}" \
        '{
          stream_type: "Artifact",
          schema_version: $schema_version,
          timestamp: $ts,
          path: $path,
          producer: $producer,
          media_type: "application/x-stub",
          session_id: $session_id,
          run_id: $run_id
        }'
      ;;
    Intent)
      jq -n \
        --arg ts "$ts" --arg schema_version "$SCHEMA_VERSION" --arg run_id "$run_id" \
        --arg intent "[stub] stage $stage_label · $construct/$skill intent placeholder" \
        '{
          stream_type: "Intent",
          schema_version: $schema_version,
          timestamp: $ts,
          intent: $intent,
          run_id: $run_id
        }'
      ;;
    Operator-Model)
      jq -n \
        --arg ts "$ts" --arg schema_version "$SCHEMA_VERSION" --arg run_id "$run_id" \
        '{
          stream_type: "Operator-Model",
          schema_version: $schema_version,
          timestamp: $ts,
          expertise: [],
          run_id: $run_id
        }'
      ;;
    *)
      die 3 "stage $stage_label declares unknown primary write type '$primary_type'"
      ;;
  esac
}

# --------------------------------------------------------------------------
# Execute chain
# --------------------------------------------------------------------------
now_ms() {
  python3 -c "import time; print(int(time.time()*1000))" 2>/dev/null \
    || echo "$(($(date +%s) * 1000))"
}

start_ms=$(now_ms)
print_plan

declare -a STAGE_DURATIONS=()
declare -a STAGE_OUTCOMES=()
declare -a STAGE_LABELS=()
declare -a STAGE_SESSIONS=()

current_payload=$(emit_initial_payload)

for (( i=0; i<STAGE_COUNT; i++ )); do
  stage_json=$(echo "$COMPOSITION_JSON" | jq -c ".chain[$i]")
  stage_label=$(echo "$stage_json" | jq -r '.stage // empty')
  [[ -z "$stage_label" ]] && stage_label="$((i+1))"
  construct=$(echo "$stage_json" | jq -r '.construct')
  skill=$(echo "$stage_json" | jq -r '.skill // "<none>"')
  writes_csv=$(echo "$stage_json" | jq -r '(.writes // []) | join(",")')
  persona=$(resolve_persona "$construct")

  # Entry row — construct-invoke prints session_id on stdout, trajectory on disk.
  session_id=$("$SCRIPT_DIR/construct-invoke.sh" entry "$persona" "$construct" "/compose:$COMPOSITION_NAME#$stage_label" 2>/dev/null || echo "")
  [[ -z "$session_id" ]] && session_id="compose-${RUN_ID}-stage-${stage_label}"

  t0_ms=$(now_ms)

  # Execute stage — default stub or operator-supplied executor.
  stage_output=""
  exec_rc=0
  if [[ -n "$STAGE_EXECUTOR" && -x "$STAGE_EXECUTOR" ]]; then
    stage_output=$(printf '%s' "$current_payload" | "$STAGE_EXECUTOR" \
      "$construct" "$skill" "$persona" "$stage_label" "$writes_csv" "$RUN_ID" "$session_id") || exec_rc=$?
  else
    stage_output=$(printf '%s' "$current_payload" | default_stage_executor \
      "$construct" "$skill" "$persona" "$stage_label" "$writes_csv" "$RUN_ID" "$session_id") || exec_rc=$?
  fi

  t1_ms=$(now_ms)
  dur_ms=$(( t1_ms - t0_ms ))
  (( dur_ms >= 0 )) || dur_ms=0

  outcome="completed"
  if (( exec_rc != 0 )); then
    outcome="failed"
    "$SCRIPT_DIR/construct-invoke.sh" exit "$persona" "$construct" "$dur_ms" "$outcome" "/compose:$COMPOSITION_NAME#$stage_label" "$session_id" >/dev/null 2>&1 || true
    die 3 "stage $stage_label ($construct/$skill) executor exited $exec_rc"
  fi

  # Exit row
  "$SCRIPT_DIR/construct-invoke.sh" exit "$persona" "$construct" "$dur_ms" "$outcome" "/compose:$COMPOSITION_NAME#$stage_label" >/dev/null 2>&1 || true

  STAGE_DURATIONS+=("$dur_ms")
  STAGE_OUTCOMES+=("$outcome")
  STAGE_LABELS+=("$stage_label:$construct/$skill")
  STAGE_SESSIONS+=("$session_id")

  current_payload="$stage_output"
done

end_ms=$(now_ms)
total_ms=$(( end_ms - start_ms ))
(( total_ms >= 0 )) || total_ms=0

# --------------------------------------------------------------------------
# Final output validation — if last stage writes a known stream type,
# validate against its schema. Failure routes to exit 4.
# --------------------------------------------------------------------------
last_writes=$(echo "$COMPOSITION_JSON" | jq -r '(.chain[-1].writes // [])[0] // empty')
if [[ -n "$last_writes" ]]; then
  if ! "$SCRIPT_DIR/stream-validate.sh" "$last_writes" "$current_payload" 2>/dev/null; then
    echo "[construct-compose] final output failed $last_writes schema validation:" >&2
    "$SCRIPT_DIR/stream-validate.sh" "$last_writes" "$current_payload" || true
    echo "[construct-compose] raw final output follows on stdout; exit 4" >&2
    printf '%s\n' "$current_payload"
    exit 4
  fi
fi

# --------------------------------------------------------------------------
# Final payload to stdout (the chain's last output)
# --------------------------------------------------------------------------
printf '%s\n' "$current_payload"

# --------------------------------------------------------------------------
# Summary per read-mode (to stderr so stdout stays pipe-clean)
# --------------------------------------------------------------------------
case "$READ_MODE" in
  glance)
    local_stages=${#STAGE_DURATIONS[@]}
    echo "✓ compose $COMPOSITION_NAME · stages=$local_stages · ${total_ms}ms · run=${RUN_ID:0:8}" >&2
    ;;
  orient)
    echo "compose $COMPOSITION_NAME · run_id=$RUN_ID · total=${total_ms}ms" >&2
    for (( i=0; i<${#STAGE_LABELS[@]}; i++ )); do
      echo "  stage ${STAGE_LABELS[$i]} · ${STAGE_DURATIONS[$i]}ms · ${STAGE_OUTCOMES[$i]}" >&2
    done
    echo "  final writes: ${last_writes:-<untyped>}" >&2
    ;;
  intervene)
    jq -n \
      --arg composition "$COMPOSITION_NAME" \
      --arg run_id "$RUN_ID" \
      --argjson total_ms "$total_ms" \
      --arg final_type "$last_writes" \
      --argjson stages "$(printf '%s\n' "${STAGE_LABELS[@]}" | jq -R . | jq -s .)" \
      --argjson durations "$(printf '%s\n' "${STAGE_DURATIONS[@]}" | jq -s .)" \
      --argjson outcomes "$(printf '%s\n' "${STAGE_OUTCOMES[@]}" | jq -R . | jq -s .)" \
      --argjson sessions "$(printf '%s\n' "${STAGE_SESSIONS[@]}" | jq -R . | jq -s .)" \
      '{
        composition: $composition,
        run_id: $run_id,
        total_ms: $total_ms,
        final_type: $final_type,
        stages: $stages,
        durations_ms: $durations,
        outcomes: $outcomes,
        session_ids: $sessions
      }' >&2
    ;;
esac
