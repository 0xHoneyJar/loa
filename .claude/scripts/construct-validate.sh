#!/usr/bin/env bash
# =============================================================================
# construct-validate.sh — pre-install / pre-publish manifest validator (cycle-005 L4)
# =============================================================================
# Validates a construct pack directory against the cycle-005 checks surfaced
# by F28 (missing commands declarations) and SEED §12 (grimoires read/write
# convention on CLAUDE.md). Emits Verdict stream rows per doctrine §3 on
# failure; each finding carries severity and evidence.
#
# Usage:
#   construct-validate.sh <pack-path> [--json] [--strict]
#
# Checks:
#   1. construct.yaml present + parseable
#   2. required fields: schema_version, slug, name, version, description
#   3. skills[].path resolves to a filesystem directory
#   4. persona routes declared: identity/<HANDLE>.md file OR personas: list
#   5. /-commands OR persona handles exist (F28 closure gate)
#   6. streams declared: reads / writes not empty (warn only)
#   7. CLAUDE.md contains an explicit grimoires read/write declaration (SEED §12)
#
# Severity tiers:
#   critical — missing construct.yaml / unparseable
#   high     — missing required field, broken skill path
#   medium   — no routes (F28), missing grimoires section (§12)
#   low      — empty stream declarations (advisory)
#   info     — pack passes all hard checks
#
# Exit codes:
#   0 = no high or critical findings
#   1 = at least one high/critical (or medium if --strict)
#   2 = pack path does not exist
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
SCHEMA_VERSION="1.0.0"

OUTPUT_JSON=0
STRICT=0
PACK_PATH=""

usage() { sed -n '2,32p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --json)    OUTPUT_JSON=1; shift ;;
    --strict)  STRICT=1; shift ;;
    -*) echo "[construct-validate] ERROR: unknown flag $1" >&2; exit 2 ;;
    *) if [[ -z "$PACK_PATH" ]]; then PACK_PATH="$1"; else echo "[construct-validate] ERROR: unexpected positional: $1" >&2; exit 2; fi; shift ;;
  esac
done

[[ -n "$PACK_PATH" ]] || { usage >&2; exit 2; }
PACK_PATH="$(cd "$PACK_PATH" 2>/dev/null && pwd)" || { echo "[construct-validate] ERROR: pack path does not exist: $PACK_PATH" >&2; exit 2; }

command -v yq >/dev/null 2>&1 || { echo "[construct-validate] ERROR: yq v4+ required" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "[construct-validate] ERROR: jq required" >&2; exit 2; }

declare -a FINDINGS=()

emit_finding() {
  local severity="$1" check="$2" message="$3" evidence="${4:-}"
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local row
  row=$(jq -n \
    --arg sv "$severity" --arg ck "$check" --arg msg "$message" \
    --arg ev "$evidence" --arg ts "$ts" \
    --arg schema_version "$SCHEMA_VERSION" --arg pack "$PACK_PATH" \
    '{
      stream_type: "Verdict",
      schema_version: $schema_version,
      timestamp: $ts,
      source: "construct-validate",
      verdict: ("[" + $ck + "] " + $msg),
      severity: $sv,
      evidence: ([$ev] | map(select(. != ""))),
      subject: $pack,
      tags: [$ck]
    }')
  FINDINGS+=("$row")
}

PACK_YAML="$PACK_PATH/construct.yaml"
if [[ ! -f "$PACK_YAML" ]]; then
  emit_finding critical construct_yaml "construct.yaml not found in pack root" "$PACK_PATH"
else
  PACK_JSON=$(yq -o=json '.' "$PACK_YAML" 2>/dev/null) || PACK_JSON=""
  if [[ -z "$PACK_JSON" ]]; then
    emit_finding critical construct_yaml "construct.yaml failed to parse" "$PACK_YAML"
  else
    # Required fields
    for field in schema_version slug name version description; do
      val=$(echo "$PACK_JSON" | jq -r --arg f "$field" '.[$f] // empty')
      [[ -z "$val" ]] && emit_finding high required_field "construct.yaml missing required field '$field'" "$PACK_YAML"
    done

    # skills[].path resolution
    mapfile -t skills < <(echo "$PACK_JSON" | jq -r '(.skills // [])[] | .path // empty')
    for s in "${skills[@]}"; do
      [[ -z "$s" ]] && continue
      if [[ ! -d "$PACK_PATH/$s" && ! -L "$PACK_PATH/$s" ]]; then
        emit_finding high skill_path "skills[].path does not resolve: $s" "$PACK_YAML"
      fi
    done

    # Commands consistency (if declared) — every commands[].path must exist
    mapfile -t cmd_paths < <(echo "$PACK_JSON" | jq -r '(.commands // [])[] | .path // empty')
    for c in "${cmd_paths[@]}"; do
      [[ -z "$c" ]] && continue
      if [[ ! -f "$PACK_PATH/$c" ]]; then
        emit_finding high command_path "commands[].path does not resolve: $c" "$PACK_YAML"
      fi
    done

    # F28 gate — pack must declare at least one route: commands OR persona handles
    cmd_count=$(echo "$PACK_JSON" | jq '(.commands // []) | length')
    persona_count=0
    if [[ -d "$PACK_PATH/identity" ]]; then
      persona_count=$(find "$PACK_PATH/identity" -maxdepth 1 -name '*.md' -print | while read -r f; do base=$(basename "$f" .md); [[ "$base" =~ ^[A-Z][A-Z0-9_]+$ ]] && echo 1; done | wc -l | tr -d ' ')
    fi
    listed_personas=$(echo "$PACK_JSON" | jq '(.personas // []) | length')
    if (( cmd_count == 0 && persona_count == 0 && listed_personas == 0 )); then
      emit_finding medium route_declared "F28: pack declares neither commands: nor personas — operator can only route by slug/name" "$PACK_YAML"
    fi

    # Stream declarations — warn if empty
    reads_count=$(echo "$PACK_JSON" | jq '(.reads // .streams.reads // []) | length')
    writes_count=$(echo "$PACK_JSON" | jq '(.writes // .streams.writes // []) | length')
    if (( reads_count == 0 )); then
      emit_finding low streams "construct declares no 'reads:' stream types — pipe composition will be ambiguous" "$PACK_YAML"
    fi
    if (( writes_count == 0 )); then
      emit_finding low streams "construct declares no 'writes:' stream types — pipe composition will be ambiguous" "$PACK_YAML"
    fi
  fi
fi

# SEED §12 — CLAUDE.md must carry explicit grimoires read/write declaration
CLAUDE_MD="$PACK_PATH/CLAUDE.md"
if [[ -f "$CLAUDE_MD" ]]; then
  if ! grep -qiE 'grimoires?/' "$CLAUDE_MD"; then
    emit_finding medium grimoires_section \
      "CLAUDE.md contains no grimoires/ path reference — SEED §12 convention: 'grimoire path IS the interface'" \
      "$CLAUDE_MD"
  else
    # Must reference at least one of: 'Writes to', 'Reads from', 'writes:' or 'reads:'
    if ! grep -qiE '(writes to|reads from|writes:|reads:)' "$CLAUDE_MD"; then
      emit_finding medium grimoires_section \
        "CLAUDE.md mentions grimoires/ but lacks explicit read/write declaration — SEED §12" \
        "$CLAUDE_MD"
    fi
  fi
else
  emit_finding medium claude_md "pack is missing CLAUDE.md — operator-facing description not declared" "$PACK_PATH"
fi

# Exit-code calculation
worst="info"
for row in "${FINDINGS[@]}"; do
  sev=$(echo "$row" | jq -r '.severity')
  case "$sev" in
    critical) worst="critical" ;;
    high) [[ "$worst" != "critical" ]] && worst="high" ;;
    medium) [[ "$worst" != "critical" && "$worst" != "high" ]] && worst="medium" ;;
    low) [[ "$worst" == "info" ]] && worst="low" ;;
  esac
done

# Output
if (( OUTPUT_JSON == 1 )); then
  # Emit JSON array of Verdict rows
  if (( ${#FINDINGS[@]} == 0 )); then
    echo "[]"
  else
    printf '%s\n' "${FINDINGS[@]}" | jq -s '.'
  fi
else
  echo "# construct-validate · $PACK_PATH"
  if (( ${#FINDINGS[@]} == 0 )); then
    echo "  ✓ all checks passed"
  else
    for row in "${FINDINGS[@]}"; do
      sev=$(echo "$row" | jq -r '.severity')
      msg=$(echo "$row" | jq -r '.verdict')
      ev=$(echo "$row" | jq -r '.evidence[0] // "-"')
      printf "  [%s] %s\n    → %s\n" "$sev" "$msg" "$ev"
    done
  fi
  echo "# worst: $worst · total: ${#FINDINGS[@]}"
fi

case "$worst" in
  critical|high) exit 1 ;;
  medium)        (( STRICT )) && exit 1 || exit 0 ;;
  *) exit 0 ;;
esac
