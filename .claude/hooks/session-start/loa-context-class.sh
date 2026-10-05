#!/usr/bin/env bash
# =============================================================================
# .claude/hooks/session-start/loa-context-class.sh — cycle-126 FR-3.1 (SDD D-3.1)
#
# Decide the context class this session runs under and write it to
# .run/context-class so the ten skills' context-discipline block can read it:
#
#   long      the default — the Claude 5 generation (≥ 1M context): the
#             tool-result-clearing thresholds are 20K / 50K / 30K / 150K
#   standard  when LOA_CONTEXT_CLASS=standard, or when the session model
#             (the hook payload's `.model` when the harness exposes it, or
#             --model) resolves to a catalog entry with context_window ≤ 200000:
#             2K / 5K / 3K / 15K
#
# Never blocks and never fails the session: every error path is `long`
# (basis `default`). Silent on stdout as a SessionStart hook; `--line` prints
# the one line /loa shows. Usage:
#   loa-context-class.sh [--root DIR] [--model ID] [--catalog FILE] [--line] [--json] [--show]
# Payload: the hook's stdin JSON is read only when stdin is not a terminal.
# `--show` (what /loa uses) prints the line for the class already recorded in
# .run/context-class without recomputing or rewriting it; with no record it
# behaves like --line.
# =============================================================================
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
MODEL=""
CATALOG=""
MODE="hook"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)    ROOT="${2:-}"; shift 2 ;;
    --model)   MODEL="${2:-}"; shift 2 ;;
    --catalog) CATALOG="${2:-}"; shift 2 ;;
    --line)    MODE="line"; shift ;;
    --json)    MODE="json"; shift ;;
    --show)    MODE="show"; shift ;;
    -h|--help) sed -n '3,23p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) shift ;;
  esac
done
# the catalog ships with the framework (next to this hook); --root only says where .run/ lives
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
CATALOG="${CATALOG:-$HOOK_DIR/../../defaults/model-config.yaml}"
STANDARD_MAX=200000

_print_line() {  # <class> <basis> <model>
  if [[ "$1" == "long" ]]; then
    echo "Context: long ($2; thresholds 20K/50K/30K/150K — LOA_CONTEXT_CLASS=standard for a ≤200K model)"
  else
    echo "Context: standard ($2${3:+, $3}; thresholds 2K/5K/3K/15K)"
  fi
}

# --- --show: the recorded class, verbatim, no rewrite ------------------------
if [[ "$MODE" == "show" && -f "$ROOT/.run/context-class" ]]; then
  rec_class="$(head -1 "$ROOT/.run/context-class" 2>/dev/null | tr -cd 'a-z')"
  rec_meta="$(sed -n 2p "$ROOT/.run/context-class" 2>/dev/null)"
  rec_basis="$(printf '%s' "$rec_meta" | grep -o 'basis=[a-z]*' | cut -d= -f2)"
  rec_model="$(printf '%s' "$rec_meta" | grep -o 'model=[A-Za-z0-9._:-]*' | cut -d= -f2)"
  [[ "$rec_model" == "null" ]] && rec_model=""
  case "$rec_class" in
    long|standard) _print_line "$rec_class" "${rec_basis:-recorded}" "$rec_model"; exit 0 ;;
  esac
fi
[[ "$MODE" == "show" ]] && MODE="line"

# --- the session model: --model, else the payload's .model (when piped) -----
if [[ -z "$MODEL" && ! -t 0 ]]; then
  payload="$(timeout 2 cat 2>/dev/null || true)"
  if [[ -n "$payload" ]] && command -v jq >/dev/null 2>&1; then
    MODEL="$(printf '%s' "$payload" | jq -r '(.model // .model_id // .model_name // empty) | if type == "object" then (.id // .name // empty) else . end' 2>/dev/null || true)"
  fi
fi
MODEL="${MODEL//[^A-Za-z0-9._:-]/}"

# --- resolve the model's context window through the catalog (alias-aware) ---
_context_window_of() {  # <model> → integer or ""
  local m="$1" target cw=""
  command -v yq >/dev/null 2>&1 && [[ -f "$CATALOG" ]] || { echo ""; return 0; }
  m="${m#anthropic:}"; m="${m#openai:}"; m="${m#google:}"
  target="$(yq eval ".aliases.\"$m\"" "$CATALOG" 2>/dev/null)"
  [[ -n "$target" && "$target" != "null" ]] && m="${target#*:}"
  # one line per provider; the first non-null wins (yq has no `empty`)
  cw="$(yq eval "[.providers[].models.\"$m\".context_window | select(. != null)] | .[0]" "$CATALOG" 2>/dev/null)"
  [[ "$cw" =~ ^[0-9]+$ ]] && echo "$cw" || echo ""
}

CLASS="long"; BASIS="default"; CW=""
if [[ "${LOA_CONTEXT_CLASS:-}" == "standard" ]]; then
  CLASS="standard"; BASIS="env"
elif [[ "${LOA_CONTEXT_CLASS:-}" == "long" ]]; then
  CLASS="long"; BASIS="env"
elif [[ -n "$MODEL" ]]; then
  CW="$(_context_window_of "$MODEL")"
  if [[ -n "$CW" ]]; then
    BASIS="model"
    (( CW <= STANDARD_MAX )) && CLASS="standard" || CLASS="long"
  fi
fi

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
# --- write .run/context-class atomically (two lines: the class, then the basis) --
if mkdir -p "$ROOT/.run" 2>/dev/null; then
  tmp="$(mktemp "$ROOT/.run/.context-class.XXXXXX" 2>/dev/null || true)"
  if [[ -n "$tmp" ]]; then
    printf '%s\nbasis=%s model=%s context_window=%s ts=%s\n' "$CLASS" "$BASIS" "${MODEL:-null}" "${CW:-null}" "$TS" > "$tmp" \
      && mv -f "$tmp" "$ROOT/.run/context-class" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  fi
fi

case "$MODE" in
  line) _print_line "$CLASS" "$BASIS" "$MODEL" ;;
  json)
    jq -nc --arg c "$CLASS" --arg b "$BASIS" --arg m "$MODEL" --arg cw "$CW" --arg ts "$TS" \
      '{class: $c, basis: $b, model: (if $m == "" then null else $m end), context_window: (if $cw == "" then null else ($cw | tonumber) end), ts: $ts}' ;;
  *) : ;;
esac
exit 0
