#!/usr/bin/env bash
# =============================================================================
# loa-decisions-surface.sh: SessionStart hook that surfaces pending decision rows.
#
# Prints up to 10 `proposed` then `open` rows of grimoires/loa/decisions.yaml (id, status,
# summary only) so the operator sees what awaits /decisions confirm. DEFAULT-OFF: gated on
# `decisions.surface_at_session_start` (default false) in .loa.config.yaml.
#
# CONTRACT (observability, never a gate; same as loa-kf-surface.sh):
#   - Exits 0 on every path and never blocks a session.
#   - Disabled or no config: prints nothing (read with yq, or a plain-text fallback without it).
#   - Enabled but Mike Farah yq v4 or jq is missing, or the ledger is unreadable or has an
#     unknown schema_version: one "[DECISIONS] WARNING ..." line on stdout.
#   - Enabled and healthy: the block on stdout (SessionStart injects stdout as context);
#     nothing when no row is open or proposed and no marker is stale.
#   - A stale .run/unattended.json (another session, or older than
#     decisions.unattended_marker_ttl_hours, default 24) adds one notice line.
#
# TRUST BOUNDARY: row text is agent-authored and UNTRUSTED. Only id, status and summary are
#   read; each summary is control-stripped (C0, C1, U+2028/9), angle brackets are replaced so
#   no tag can close the fence, and it is capped at 100 characters. The whole block is then
#   wrapped by the L6 data fence, sanitize_for_session_start L6 <block> --max-chars 2000
#   (context-isolation-lib.sh). Without that sanitizer the block is not printed.
# =============================================================================
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${HOOK_DIR}/../../.." && pwd)"

# Test seam (mirrors loa-kf-surface.sh): overrides are honoured only under
# LOA_DEC_SURFACE_TEST_MODE=1 with a bats marker present.
_dec_test_mode_active() {
  [[ "${LOA_DEC_SURFACE_TEST_MODE:-0}" == "1" ]] || return 1
  [[ -n "${BATS_TEST_FILENAME:-}" || -n "${BATS_VERSION:-}" ]]
}

have_yq4=0
if command -v yq >/dev/null 2>&1 && [[ "$(yq --version 2>&1 || true)" == *mikefarah*"version v4."* ]]; then have_yq4=1; fi

# The config is read first (yq, or a plain-text fallback without it), so an enabled surface on a host
# without its tools says so instead of looking disabled.
config_path="${REPO_ROOT}/.loa.config.yaml"
enabled="false"
if _dec_test_mode_active && [[ -n "${LOA_DEC_SURFACE_TEST_CONFIG-}" ]]; then
  enabled="${LOA_DEC_SURFACE_TEST_CONFIG}"
elif [[ -f "$config_path" ]]; then
  if [[ $have_yq4 -eq 1 ]]; then
    # Explicit key, else the loa.profile default (cycle-129 D-9.1).
    # shellcheck source=../../scripts/lib/profile-lib.sh
    source "${REPO_ROOT}/.claude/scripts/lib/profile-lib.sh" 2>/dev/null &&
      enabled="$(loa_knob decisions.surface_at_session_start false 2>/dev/null || echo false)"
  else
    # top-level `decisions:` block, then an indented `surface_at_session_start: true`
    enabled="$(awk '
      /^[^[:space:]#]/ { blk = ($0 ~ /^decisions:[[:space:]]*(#.*)?$/) }
      blk && /^[[:space:]]+surface_at_session_start:[[:space:]]*true[[:space:]]*(#.*)?$/ { print "true"; exit }
    ' "$config_path" 2>/dev/null || true)"
  fi
fi
[[ "$enabled" == "true" ]] || exit 0

missing=""
[[ $have_yq4 -eq 1 ]] || missing="Mike Farah yq v4"
command -v jq >/dev/null 2>&1 || missing="${missing:+${missing} and }jq"
if [[ -n "$missing" ]]; then
  echo "[DECISIONS] WARNING: the decisions surface is enabled but ${missing} is missing; rows are not shown. Install it, or set decisions.surface_at_session_start: false."
  exit 0
fi

LEDGER="${REPO_ROOT}/grimoires/loa/decisions.yaml"
RUN_DIR="${REPO_ROOT}/.run"
if _dec_test_mode_active; then
  [[ -n "${LOA_DECISIONS_FILE:-}" ]] && LEDGER="${LOA_DECISIONS_FILE}"
  [[ -n "${LOA_DEC_SURFACE_RUN_DIR:-}" ]] && RUN_DIR="${LOA_DEC_SURFACE_RUN_DIR}"
fi

if [[ ! -r "$LEDGER" ]]; then
  echo "[DECISIONS] WARNING: the decision ledger is unreadable at grimoires/loa/decisions.yaml; the surface is enabled but degraded."
  exit 0
fi
doc="$(yq -o=json -I0 '.' "$LEDGER" 2>/dev/null || true)"
if [[ -z "$doc" ]] || ! printf '%s' "$doc" | jq -e '.schema_version == 1 and ((.decisions // []) | type == "array")' >/dev/null 2>&1; then
  echo "[DECISIONS] WARNING: grimoires/loa/decisions.yaml does not parse or has an unknown schema_version; the surface is enabled but degraded."
  exit 0
fi

# Rows: proposed first, then open; fields reduced to a safe id, the status and a cleaned summary.
rows="$(printf '%s' "$doc" | jq -r '
  # (every non-ASCII character is written as a \u escape: no invisible separator sits in the source)
  def clean: tostring | gsub("[[:cntrl:]\u0080-\u009f\u2028\u2029]"; " ") | gsub("<"; "\u2039") | gsub(">"; "\u203a")
             | gsub("`"; "\u2018") | gsub("  +"; " ") | sub("^ "; "") | sub(" $"; "");
  def cap: if length > 100 then .[0:99] + "\u2026" else . end;
  [ (.decisions // [])[] | objects | select(.status == "proposed" or .status == "open") ]
  | (map(select(.status == "proposed")) + map(select(.status == "open"))) as $r
  | "C\t\($r | map(select(.status == "proposed")) | length)\t\($r | map(select(.status == "open")) | length)",
    ($r[0:10][] | "R\t\((.id // "") | tostring | gsub("[^A-Za-z0-9-]"; "") | .[0:16])\t\(.status)\t\((.summary // "") | clean | cap)")
' 2>/dev/null || true)"

n_prop=0; n_open=0; lines=()
while IFS=$'\t' read -r kind a b c; do
  case "$kind" in
    C) n_prop="$a"; n_open="$b" ;;
    R) lines+=("- ${a} ${b}: ${c}") ;;
  esac
done <<< "$rows"

# Stale unattended marker (the writer ignores it; the notice tells the operator to clear it).
stale_note=""
marker="${RUN_DIR}/unattended.json"
if [[ -f "$marker" ]]; then
  ttl="$(yq '.decisions.unattended_marker_ttl_hours // 24' "$config_path" 2>/dev/null || echo 24)"
  [[ "$ttl" =~ ^[0-9]+$ && "$ttl" -gt 0 ]] || ttl=24
  sid="$(jq -r '.session_id // empty' "$marker" 2>/dev/null || true)"
  ca="$(jq -r '.created_at // empty' "$marker" 2>/dev/null || true)"
  ep=""
  if [[ -n "$ca" ]]; then
    # shellcheck source=/dev/null
    ep="$( (source "${REPO_ROOT}/.claude/scripts/compat-lib.sh" >/dev/null 2>&1; _date_to_epoch "$ca") 2>/dev/null || true)"
  fi
  sess="${CLAUDE_SESSION_ID:-${CLAUDE_CODE_SESSION_ID:-}}"
  if [[ ! "$ep" =~ ^[0-9]+$ ]] || (( $(date -u +%s) - ep > ttl * 3600 )) || [[ -n "$sess" && -n "$sid" && "$sid" != "$sess" ]]; then
    stale_note="[DECISIONS] .run/unattended.json is stale (other session or older than ${ttl} h): ignored; clear it with /decisions clear-unattended"
  fi
fi

total=$(( n_prop + n_open ))
[[ "$total" -gt 0 || -n "$stale_note" ]] || exit 0

block="$(
  if [[ "$total" -gt 0 ]]; then
    echo "[DECISIONS] ${n_prop} proposed, ${n_open} open (grimoires/loa/decisions.yaml):"
    printf '%s\n' "${lines[@]}"
    if [[ "$total" -gt 10 ]]; then echo "... and $(( total - 10 )) more: dec-write-lib.sh list --status proposed,open"; fi
  fi
  [[ -z "$stale_note" ]] || echo "$stale_note"
  if [[ "$n_prop" -gt 0 ]]; then echo "Confirm proposed rows with /decisions confirm."; fi
)"

fenced="$( (source "${REPO_ROOT}/.claude/scripts/lib/context-isolation-lib.sh" >/dev/null 2>&1 \
            && sanitize_for_session_start L6 "$block" --max-chars 2000) 2>/dev/null || true)"
if [[ "$fenced" == *"<untrusted-content"* ]]; then
  printf '%s\n' "$fenced"
else
  echo "[DECISIONS] WARNING: ${n_prop} proposed, ${n_open} open; the L6 sanitizer is unavailable, so rows are not shown. Run: .claude/scripts/lib/dec-write-lib.sh list --status proposed,open"
fi
exit 0
