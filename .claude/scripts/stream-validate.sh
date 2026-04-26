#!/usr/bin/env bash
# =============================================================================
# stream-validate.sh — JSON Schema validator for construct stream rows (cycle-005 L2)
# =============================================================================
# Validates a Signal / Verdict / Artifact / Intent / Operator-Model JSON payload
# against its schema at .claude/schemas/<type-slug>.schema.json.
#
# Usage:
#   stream-validate.sh <stream_type> <json-string>
#   stream-validate.sh <stream_type> --file <path>
#   stream-validate.sh <stream_type> -           # read JSON from stdin
#
# Stream types: Signal | Verdict | Artifact | Intent | Operator-Model
#
# Exit codes:
#   0 = valid
#   1 = schema validation failed (message on stderr)
#   2 = unknown stream type or schema file missing
#   3 = validator engine unavailable (python3+jsonschema required)
#
# Doctrine §3 + §14.2 — stream typing enforced at pipe edges.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
SCHEMA_DIR="${LOA_SCHEMA_DIR:-$PROJECT_ROOT/.claude/schemas}"

usage() {
  sed -n '2,24p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# Map Stream-Type name → slug used in schema filename.
schema_slug() {
  case "$1" in
    Signal)         echo "signal" ;;
    Verdict)        echo "verdict" ;;
    Artifact)       echo "artifact" ;;
    Intent)         echo "intent" ;;
    Operator-Model) echo "operator-model" ;;
    *)              return 1 ;;
  esac
}

main() {
  if [[ $# -lt 2 ]]; then
    usage >&2
    exit 2
  fi

  local stream_type="$1"
  local arg2="$2"
  local payload

  local slug
  if ! slug=$(schema_slug "$stream_type"); then
    echo "[stream-validate] ERROR: unknown stream_type '$stream_type'. Expected one of: Signal, Verdict, Artifact, Intent, Operator-Model." >&2
    exit 2
  fi

  local schema_file="$SCHEMA_DIR/${slug}.schema.json"
  if [[ ! -f "$schema_file" ]]; then
    echo "[stream-validate] ERROR: schema file missing: $schema_file" >&2
    exit 2
  fi

  if [[ "$arg2" == "--file" ]]; then
    [[ $# -ge 3 ]] || { echo "[stream-validate] ERROR: --file requires a path argument." >&2; exit 2; }
    payload=$(cat "$3")
  elif [[ "$arg2" == "-" ]]; then
    payload=$(cat -)
  else
    payload="$arg2"
  fi

  # Sanity-check: payload is valid JSON.
  if ! echo "$payload" | jq -e . >/dev/null 2>&1; then
    echo "[stream-validate] ERROR: payload is not valid JSON." >&2
    exit 1
  fi

  # Sanity-check: declared stream_type matches.
  local declared
  declared=$(echo "$payload" | jq -r '.stream_type // empty')
  if [[ -n "$declared" && "$declared" != "$stream_type" ]]; then
    echo "[stream-validate] ERROR: payload declares stream_type='$declared' but validator invoked with '$stream_type'." >&2
    exit 1
  fi

  # Prefer python3+jsonschema (full draft-07). Fall back to jq required-field check.
  if command -v python3 >/dev/null 2>&1 && python3 -c "import jsonschema" >/dev/null 2>&1; then
    local payload_tmp
    payload_tmp=$(mktemp -t stream-validate-payload.XXXXXX.json)
    # shellcheck disable=SC2064  # expand trap path now
    trap "rm -f '$payload_tmp'" EXIT
    printf '%s' "$payload" > "$payload_tmp"
    python3 - "$schema_file" "$stream_type" "$payload_tmp" <<'PY'
import json
import sys

schema_path, stream_type, payload_path = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(payload_path) as fh:
        payload = json.load(fh)
except json.JSONDecodeError as exc:
    print(f"[stream-validate] ERROR: JSON decode failed: {exc}", file=sys.stderr)
    sys.exit(1)

with open(schema_path) as fh:
    schema = json.load(fh)

from jsonschema import Draft7Validator  # type: ignore

validator = Draft7Validator(schema)
errors = sorted(validator.iter_errors(payload), key=lambda e: list(e.absolute_path))
if errors:
    print(f"[stream-validate] {stream_type} INVALID:", file=sys.stderr)
    for err in errors[:20]:
        loc = "/".join(str(p) for p in err.absolute_path) or "<root>"
        print(f"  - {loc}: {err.message}", file=sys.stderr)
    sys.exit(1)
sys.exit(0)
PY
    exit $?
  fi

  # Fallback validator — required-field presence only, no full schema semantics.
  echo "[stream-validate] WARNING: python3/jsonschema missing — running degraded required-field-only validation." >&2
  local required
  required=$(jq -r '.required // [] | .[]' "$schema_file")
  local missing=()
  while IFS= read -r field; do
    [[ -z "$field" ]] && continue
    if ! echo "$payload" | jq -e --arg f "$field" '.[$f] != null' >/dev/null 2>&1; then
      missing+=("$field")
    fi
  done <<< "$required"

  if (( ${#missing[@]} > 0 )); then
    echo "[stream-validate] $stream_type INVALID: missing required field(s): ${missing[*]}" >&2
    exit 1
  fi
  exit 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
