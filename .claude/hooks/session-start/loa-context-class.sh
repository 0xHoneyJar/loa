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
# SessionStart also fires on /clear, compaction and resume; such a re-fire that
# carries no model keeps a `model` or `env` record rather than resetting it.
# Bedrock ids (global.anthropic.<id>-v1:0) resolve with those affixes stripped.
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
SOURCE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    # a value flag given last has no value: stop parsing (shift 2 would not move, and the loop would spin)
    --root)    [[ $# -ge 2 ]] || break; ROOT="$2"; shift 2 ;;
    --model)   [[ $# -ge 2 ]] || break; MODEL="$2"; shift 2 ;;
    --catalog) [[ $# -ge 2 ]] || break; CATALOG="$2"; shift 2 ;;
    --line)    MODE="line"; shift ;;
    --json)    MODE="json"; shift ;;
    --show)    MODE="show"; shift ;;
    -h|--help) sed -n '3,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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
  # timeout → gtimeout → bash's own read -t (compat-lib.sh run_with_timeout's order; never blocks)
  if command -v timeout >/dev/null 2>&1; then
    payload="$(timeout 2 cat 2>/dev/null || true)"
  elif command -v gtimeout >/dev/null 2>&1; then
    payload="$(gtimeout 2 cat 2>/dev/null || true)"
  else
    payload=""; IFS= read -r -d '' -t 2 payload || true
  fi
  if [[ -n "$payload" ]] && command -v jq >/dev/null 2>&1; then
    MODEL="$(printf '%s' "$payload" | jq -r '(.model // .model_id // .model_name // empty) | if type == "object" then (.id // .name // empty) else . end' 2>/dev/null || true)"
    SOURCE="$(printf '%s' "$payload" | jq -r '.source // empty | strings' 2>/dev/null | tr -cd 'a-z')"
  fi
fi
MODEL="${MODEL//[^A-Za-z0-9._:-]/}"

# --- resolve the model's context window through the catalog (alias-aware) ---
_window_of_id() {  # <catalog id or alias> → integer or ""
  local m="$1" target cw=""
  target="$(yq eval ".aliases.\"$m\"" "$CATALOG" 2>/dev/null)"
  [[ -n "$target" && "$target" != "null" ]] && m="${target#*:}"
  m="${m//[^A-Za-z0-9._:-]/}"   # the alias target is catalog text: the same whitelist before the second lookup
  [[ -n "$m" ]] || { echo ""; return 0; }
  # one line per provider; the first non-null wins (yq has no `empty`)
  cw="$(yq eval "[.providers[].models.\"$m\".context_window | select(. != null)] | .[0]" "$CATALOG" 2>/dev/null)"
  [[ "$cw" =~ ^[0-9]+$ ]] && echo "$cw" || echo ""
}
_context_window_of() {  # <model> → integer or ""
  local m="$1" c cw
  command -v yq >/dev/null 2>&1 && [[ -f "$CATALOG" ]] || { echo ""; return 0; }
  m="${m#anthropic:}"; m="${m#openai:}"; m="${m#google:}"
  # a Bedrock id (global.anthropic.claude-haiku-4-5-20251001-v1:0): try it as given, then without the
  # region prefix, the anthropic. vendor prefix and the -vN[:M] version suffix, in that order
  local c1="$m" c2 c3 c4
  c2="$(printf '%s' "$c1" | sed -E 's/^(global|us|eu|apac|jp|au|ca|us-gov)\.//')"
  c3="${c2#anthropic.}"
  c4="$(printf '%s' "$c3" | sed -E 's/-v[0-9]+(:[0-9]+)?$//')"
  for c in "$c1" "$c2" "$c3" "$c4"; do
    cw="$(_window_of_id "$c")"
    [[ -n "$cw" ]] && { echo "$cw"; return 0; }
  done
  echo ""
}

CLASS="long"; BASIS="default"; CW=""
ENV_CLASS="$(printf '%s' "${LOA_CONTEXT_CLASS:-}" | tr '[:upper:]' '[:lower:]')"   # bash 3.2 has no ${v,,}
if [[ "$ENV_CLASS" == "standard" ]]; then
  CLASS="standard"; BASIS="env"
elif [[ "$ENV_CLASS" == "long" ]]; then
  CLASS="long"; BASIS="env"
elif [[ -n "$MODEL" ]]; then
  CW="$(_context_window_of "$MODEL")"
  if [[ -n "$CW" ]]; then
    BASIS="model"
    (( CW <= STANDARD_MAX )) && CLASS="standard" || CLASS="long"
  fi
fi

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
# --- a clear/compact/resume re-fire that carries no model keeps a model or env record --
# (SessionStart fires again inside the same session; the default would overwrite what startup decided)
KEEP=0
if [[ "$BASIS" == "default" && "$SOURCE" =~ ^(clear|compact|resume)$ && -f "$ROOT/.run/context-class" ]]; then
  rec_basis="$(sed -n 2p "$ROOT/.run/context-class" 2>/dev/null | grep -o 'basis=[a-z]*' | cut -d= -f2)"
  rec_class="$(head -1 "$ROOT/.run/context-class" 2>/dev/null | tr -cd 'a-z')"
  if [[ "$rec_basis" =~ ^(model|env)$ && "$rec_class" =~ ^(long|standard)$ ]]; then
    KEEP=1; CLASS="$rec_class"; BASIS="$rec_basis"
    MODEL="$(sed -n 2p "$ROOT/.run/context-class" 2>/dev/null | grep -o 'model=[A-Za-z0-9._:-]*' | cut -d= -f2)"
    [[ "$MODEL" == "null" ]] && MODEL=""
  fi
fi
# --- write .run/context-class atomically (two lines: the class, then the basis) --
if (( KEEP == 0 )) && mkdir -p "$ROOT/.run" 2>/dev/null; then
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
