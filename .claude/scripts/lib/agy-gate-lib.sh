#!/usr/bin/env bash
# =============================================================================
# agy-gate-lib.sh — the ONE bash reader of the agy opt-in rule (cycle-127 FR-1, SDD D-1.5; review r251-1 G2)
# =============================================================================
# The agy (Antigravity) headless route — cheval's `gemini-headless` hop — is opt-in, default off: it is planned only
# when `hounfour.headless.agy_opt_in` is a YAML boolean `true` in .loa.config.yaml (absent, false, a string — off;
# no environment override: a planner is never talked into the voice by ambient env). Every bash planner
# (adversarial-review.sh companion chains, flatline-orchestrator.sh tertiary, run-preflight.sh P3, loa-status.sh
# Providers) sources this file; the Python twin is loa_cheval/config/loader.py (agy_opt_in_enabled, routes_to_agy).
#
# Public API:
#   agy_opted_in <config>             → 0 only for the YAML boolean scalar written exactly `true` at
#                                       .hounfour.headless.agy_opt_in (review r251-2 K1: ONE strict rule with the Python
#                                       twin — `yes`, `on`, `True`, `TRUE`, `1`, the string "true" are all off). The yq
#                                       flavour is chosen by `yq --version` (K5): mikefarah → the typed go-yq read only;
#                                       any other yq (python yq, which wraps PyYAML) → a PyYAML node read of the source
#                                       text, never an untyped `== true`.
#   agy_headless_mode <config>        → prints the effective hounfour.headless.mode: env LOA_HEADLESS_MODE wins (as in
#                                       cheval), then the config, then prefer-api
#   routes_to_agy <model> [<mode>]    → 0 when cheval would dispatch <model> through agy: the gemini-headless hop by
#                                       name (bare, `google:gemini-headless`, `gemini-headless:<m>`), or a Google model
#                                       (`gemini*`, `google:gemini*`) under mode cli-only. <mode> defaults to
#                                       ${LOA_HEADLESS_MODE:-prefer-api}. prefer-cli is NOT agy-routed (the API hop stays
#                                       planned; cheval's walk skips the gated hop itself).
#   agy_route_planned <model> <config> → 0 when <model> is planned: not agy-routed, or the opt-in is on
#   agy_gate_warn_once <config>       → at most once per shell, on stderr: a present agy_opt_in not written exactly
#                                       `true` / `false` (the string "true", yes, True …) reads off — named with its type
#                                       and the accepted spelling (review r251-1 G12, r251-2 K1); and, with the opt-in
#                                       off while the route looks usable here (agy on PATH, or GOOGLE_API_KEY /
#                                       GEMINI_API_KEY set), that it is gated and why (SDD D-1.7, G18). A PATH lookup only —
#                                       nothing is spawned. Call it from a top-level planning point, not inside $(...):
#                                       the said-once flag is a shell variable.
#
# Pure readers: no spawn of cheval or agy, no writes. Sourcing twice is a no-op.
# =============================================================================

[[ -n "${_LOA_AGY_GATE_LIB_LOADED:-}" ]] && return 0
_LOA_AGY_GATE_LIB_LOADED=1
_LOA_AGY_GATE_WARNED="${_LOA_AGY_GATE_WARNED:-}"

AGY_OPT_IN_KEY="hounfour.headless.agy_opt_in"
AGY_OPT_IN_NOTE="agy: opt-in (disabled; hounfour.headless.agy_opt_in)"

_agy_yq_is_mikefarah() {  # (review r251-2 K5) select the reader by flavour, never by output shape
  local v
  v=$(yq --version 2>/dev/null) || return 1
  [[ "$v" == *mikefarah* ]]
}

_agy_opt_in_node() {  # <config> → "<kind> <source text>" of agy_opt_in (kind: bool | str | int | null | map | …); nothing when absent/unreadable
  local cfg="${1:-}" has t v
  [[ -n "$cfg" && -f "$cfg" ]] || return 0
  if command -v yq >/dev/null 2>&1 && _agy_yq_is_mikefarah; then
    has=$(yq eval '.hounfour.headless | (tag == "!!map" and has("agy_opt_in"))' "$cfg" 2>/dev/null) || return 0
    [[ "$has" == true ]] || return 0
    t=$(yq eval '.hounfour.headless.agy_opt_in | tag' "$cfg" 2>/dev/null) || return 0
    v=$(yq eval '.hounfour.headless.agy_opt_in' "$cfg" 2>/dev/null) || return 0
    [[ "$v" == *$'\n'* ]] && v=""
    printf '%s %s\n' "${t#!!}" "$v"
    return 0
  fi
  # any other yq flavour (python yq wraps PyYAML) or none: the PyYAML node — its tag and SOURCE text, as the Python twin
  command -v python3 >/dev/null 2>&1 || return 0
  python3 -I - "$cfg" 2>/dev/null <<'PY' || return 0
import sys, yaml
with open(sys.argv[1]) as f:
    node = yaml.compose(f, Loader=yaml.SafeLoader)
for key in ("hounfour", "headless", "agy_opt_in"):
    if not isinstance(node, yaml.MappingNode):
        sys.exit(0)
    found = None
    for k, v in node.value:
        if isinstance(k, yaml.ScalarNode) and k.value == key:
            found = v
    if found is None:
        sys.exit(0)
    node = found
text = node.value if isinstance(node, yaml.ScalarNode) and "\n" not in node.value else ""
print((node.tag or "").rsplit(":", 1)[-1], text)
PY
}

agy_opted_in() {
  local n
  n=$(_agy_opt_in_node "${1:-}")
  [[ "$n" == "bool true" ]]
}

agy_headless_mode() {
  local cfg="${1:-}" v=""
  if [[ -n "${LOA_HEADLESS_MODE:-}" ]]; then printf '%s\n' "$LOA_HEADLESS_MODE"; return 0; fi
  if [[ -n "$cfg" && -f "$cfg" ]] && command -v yq >/dev/null 2>&1; then
    v=$(yq eval '.hounfour.headless.mode // ""' "$cfg" 2>/dev/null) || v=""
    [[ "$v" == *$'\n'* ]] && v=""
    if [[ -z "$v" ]]; then v=$(yq -r '.hounfour.headless.mode // ""' "$cfg" 2>/dev/null) || v=""; fi
  fi
  [[ "$v" == "null" ]] && v=""
  printf '%s\n' "${v:-prefer-api}"
}

routes_to_agy() {
  local m="${1:-}" mode="${2:-${LOA_HEADLESS_MODE:-prefer-api}}"
  [[ -n "$m" ]] || return 1
  case "$m" in gemini-headless|*:gemini-headless|gemini-headless:*) return 0 ;; esac
  [[ "$mode" == "cli-only" ]] || return 1
  case "${m#google:}" in gemini*) return 0 ;; esac
  return 1
}

agy_route_planned() {
  local m="${1:-}" cfg="${2:-}"
  routes_to_agy "$m" "$(agy_headless_mode "$cfg")" || return 0
  agy_opted_in "$cfg"
}

agy_gate_warn_once() {
  local cfg="${1:-}" t why=""
  [[ -z "$_LOA_AGY_GATE_WARNED" ]] || return 0
  _LOA_AGY_GATE_WARNED=1
  t=$(_agy_opt_in_node "$cfg")
  case "$t" in
    ""|"bool true"|"bool false"|null\ *) ;;
    bool\ *) printf 'WARN: %s is %s, a boolean spelled other than true/false — only `agy_opt_in: true` opts in (the lowercase scalar); the agy route stays off\n' "$AGY_OPT_IN_KEY" "${t#bool }" >&2 ;;
    *) printf 'WARN: %s is present but not a YAML boolean (%s) — only `agy_opt_in: true` opts in (expected true or false); the agy route stays off\n' "$AGY_OPT_IN_KEY" "${t%% *}" >&2 ;;
  esac
  agy_opted_in "$cfg" && return 0
  command -v "${AGY_HEADLESS_BIN:-agy}" >/dev/null 2>&1 && why="agy on PATH"
  [[ -n "${GOOGLE_API_KEY:-}${GEMINI_API_KEY:-}" ]] && why="${why:+$why, }a Google/Gemini key is set"
  [[ -n "$why" ]] || return 0
  printf "WARN: the agy route is available here (%s) but not planned: %s is not true — opt in only knowingly (the prompt travels on the CLI's argv, readable by local users; the CLI must be OAuth-authed)\n" "$why" "$AGY_OPT_IN_KEY" >&2
}
