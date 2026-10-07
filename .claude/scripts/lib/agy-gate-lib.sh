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
#                                       twin — `yes`, `on`, `True`, `TRUE`, `1`, the string "true" are all off; r251-4 S3:
#                                       the EXACT tag tag:yaml.org,2002:bool — `!<x:bool> true` is off — and an alias
#                                       (`*t`) or a merge key (`<<: *b`) on the path reads off, as in Python and BB). The yq
#                                       flavour is chosen by `yq --version` (K5): mikefarah → the typed go-yq read only;
#                                       any other yq (python yq, which wraps PyYAML) → a PyYAML node read of the source
#                                       text, never an untyped `== true`. r251-5 U1/U2, r251-6 V1: a config not owned by
#                                       the current user, world-writable, or group-writable for any group but the
#                                       owner's user-private one reads off (the Python and TS readers' rule);
#                                       agy_gate_warn_once names the reason. r251-6 V3: the config is opened once (fd 9).
#   agy_headless_mode <config>        → prints the effective hounfour.headless.mode: env LOA_HEADLESS_MODE wins (as in
#                                       cheval), then the config, then prefer-api
#   routes_to_agy <model> [<mode>] [<config>]
#                                     → 0 when cheval would dispatch <model> through agy: the gemini-headless hop by
#                                       name (bare, `google:gemini-headless`, `gemini-headless:<m>`), or a Google model
#                                       under mode cli-only — by PROVIDER (agy_catalog_provider: the `google:` prefix, the
#                                       generated catalog maps incl. aliases, the `gemini*` name as fallback; r251-3 R3). <mode> defaults to
#                                       ${LOA_HEADLESS_MODE:-prefer-api}. prefer-cli is NOT agy-routed (the API hop stays
#                                       planned; cheval's walk skips the gated hop itself). With <config>, a project
#                                       alias (hounfour.aliases) is resolved first, as cheval does (r251-4, audit n14).
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

# (review r251-4 S4, audit n10: the include guard is SHELL state — the lib's own function — never an environment variable:
# an exported guard used to skip loading and leave routes_to_agy undefined; the said-once flag is never seeded from env)
declare -F agy_opted_in >/dev/null 2>&1 && return 0
_LOA_AGY_GATE_WARNED=''
_LOA_AGY_MAPS_WARNED=''

AGY_OPT_IN_KEY="hounfour.headless.agy_opt_in"
AGY_OPT_IN_NOTE="agy: opt-in (disabled; hounfour.headless.agy_opt_in)"

_agy_yq_is_mikefarah() {  # (review r251-2 K5) select the reader by flavour, never by output shape
  local v
  v=$(yq --version 2>/dev/null) || return 1
  [[ "$v" == *mikefarah* ]]
}

# ONE go-yq program for the "is the key present" test (Python twin loader._YQ_HAS; Bridgebuilder readAgyGate): every level a
# real mapping — `kind` is "alias" for an alias node — and `has` sees the explicit key only, never a merge key's (r251-4 S3)
_AGY_YQ_HAS='.hounfour | (kind == "map" and (.headless | (kind == "map" and has("agy_opt_in"))))'

_agy_group_not_private() {  # <uid> <gid> <open file> → prints why the group is not the owner's user-private group and returns 0; 1 when it is
  # (review r251-6 V1, BB #1: ONE rule with cheval's loader._not_private_group and Bridgebuilder's agyGroupNotPrivate — the
  # file's gid is the owner's primary gid, the group is NAMED for the owner (a shared `users` / macOS `staff` fails: their
  # member lists are empty for primary members, so emptiness alone never proved privacy — audit LOW-001), no account but the
  # owner is a listed member, no other account has it as its primary group (enumerated last), and no ACL makes the group
  # bits a mask over named grants (`ls -ldL`'s `+`). The account database is NSS through `getent`; a host without it, or
  # one that cannot answer, is no proof: not private)
  local uid="$1" gid="$2" f="$3" pw gr owner pgid gname members m others="" acct a_name a_uid a_gid ls_mode
  pw=$(getent passwd "$uid" 2>/dev/null) || pw=""
  IFS=: read -r owner _ _ pgid _ <<<"$pw"
  if [[ -z "$owner" || ! "$pgid" =~ ^[0-9]+$ ]]; then printf 'its owner uid %s could not be looked up\n' "$uid"; return 0; fi
  gr=$(getent group "$gid" 2>/dev/null) || gr=""
  IFS=: read -r gname _ _ members <<<"$gr"
  if [[ -z "$gname" ]]; then printf 'its group could not be looked up (gid %s)\n' "$gid"; return 0; fi
  if [[ "$gid" != "$pgid" ]]; then printf "its group '%s' (gid %s) is not the owner's primary group\n" "$gname" "$gid"; return 0; fi
  if [[ "$gname" != "$owner" ]]; then printf "its group '%s' is not named for the owner '%s' (not a user-private group)\n" "$gname" "$owner"; return 0; fi
  local IFS_save="$IFS"; IFS=,
  for m in $members; do [[ -n "$m" && "$m" != "$owner" ]] && others="${others:+$others, }$m"; done
  IFS="$IFS_save"
  if [[ -n "$others" ]]; then printf "its group '%s' has other members (%s)\n" "$gname" "$others"; return 0; fi
  acct=$(getent passwd 2>/dev/null) || { printf "the accounts of group '%s' could not be enumerated\n" "$gname"; return 0; }
  while IFS=: read -r a_name _ a_uid a_gid _; do
    [[ "$a_gid" == "$gid" && "$a_uid" != "$uid" ]] && others="${others:+$others, }$a_name"
  done <<<"$acct"
  if [[ -n "$others" ]]; then printf "its group '%s' is the primary group of another account (%s)\n" "$gname" "$others"; return 0; fi
  ls_mode=$(ls -ldL -- "$f" 2>/dev/null) || ls_mode=""
  ls_mode="${ls_mode%% *}"
  if [[ ${#ls_mode} -lt 10 ]]; then printf 'its ACL could not be read\n'; return 0; fi
  if [[ "${ls_mode:10:1}" == "+" ]]; then printf "it carries an extended ACL (the group bits are the ACL mask over other accounts' grants)\n"; return 0; fi
  return 1
}

_agy_config_untrusted() {  # <config> [<open file>] → prints why the config is not the current user's alone to write and returns 0; 1 when trusted
  # (review r251-5 U1/U2, r251-6 V1: ONE permission rule with cheval's loader._config_untrusted_reason and Bridgebuilder's
  # agyConfigUntrustedReason — owned by the current user, never world-writable, and group-writable only for the owner's
  # user-private group (_agy_group_not_private; Ubuntu's umask 002 makes every checkout 0664). <open file> is the read's
  # own descriptor (/dev/fd/9 — r251-6 V3: the bytes read and the inode judged are one); default the config path. stat -L:
  # a symlink's TARGET decides, as in Python. GNU `stat -c`, else BSD `stat -f`; a config that cannot be stat'ed is
  # untrusted — fail closed)
  local cfg="${1:-}" f="${2:-${1:-}}" st uid mode me gid why
  st=$(stat -L -c '%u %a' -- "$f" 2>/dev/null) || st=$(stat -L -f '%u %Lp' -- "$f" 2>/dev/null) || st=""
  read -r uid mode <<<"$st"
  if [[ ! "$uid" =~ ^[0-9]+$ || ! "$mode" =~ ^[0-7]{3,4}$ ]]; then
    printf '%s could not be stat'"'"'ed (owner and mode unknown)\n' "$cfg"; return 0
  fi
  me="${EUID:-$(id -u)}"
  if [[ "$uid" != "$me" ]]; then printf '%s is not owned by the current user (uid %s, euid %s)\n' "$cfg" "$uid" "$me"; return 0; fi
  if (( 8#$mode & 8#002 )); then printf '%s is world-writable (mode %04o)\n' "$cfg" "$(( 8#$mode & 8#7777 ))"; return 0; fi
  if (( 8#$mode & 8#020 )); then
    gid=$(stat -L -c '%g' -- "$f" 2>/dev/null) || gid=$(stat -L -f '%g' -- "$f" 2>/dev/null) || gid=""
    if [[ ! "$gid" =~ ^[0-9]+$ ]]; then why="its group could not be stat'ed"
    else why=$(_agy_group_not_private "$uid" "$gid" "$f") || why=""
    fi
    if [[ -n "$why" ]]; then printf '%s is group-writable (mode %04o) and %s\n' "$cfg" "$(( 8#$mode & 8#7777 ))" "$why"; return 0; fi
  fi
  return 1
}

_agy_opt_in_node() (  # <config> → "<kind> <source text>" of agy_opt_in (kind: bool | str | int | null | map | alias | <tag> …;
  # `ancestor <path>:<alias|kind>` for an alias / non-mapping hounfour or hounfour.headless — r251-6 V5); nothing when
  # absent/unreadable; "untrusted <reason>" when the value would opt in but others can write the config (r251-5 U1 — it
  # reads off; agy_gate_warn_once says why). The permission rule decides only a value that would opt in, as in the Python
  # and TS readers: a config that reads off anyway is not flagged (a umask-002 host that never opted in hears nothing).
  # (r251-6 V3, BB #2: a subshell — the config is opened ONCE on fd 9; its bytes are parsed from that descriptor and its
  # owner / mode / group / ACL judged through /dev/fd/9, so a swap of the path between read and check changes nothing)
  cfg="${1:-}"
  [[ -n "$cfg" && -f "$cfg" ]] || exit 0
  exec 9<"$cfg" 2>/dev/null || exit 0
  doc=$(cat <&9) || exit 0
  n=$(_agy_opt_in_node_raw "$doc")
  if [[ "$n" == "bool true" ]] && why=$(_agy_config_untrusted "$cfg" /dev/fd/9); then printf 'untrusted %s\n' "$why"; exit 0; fi
  [[ -n "$n" ]] && printf '%s\n' "$n"
  exit 0
)

_agy_opt_in_node_raw() {  # <document text> → the node read of _agy_opt_in_node, without the permission rule
  local doc="${1:-}" has k t v lvl kt
  [[ -n "$doc" ]] || return 0
  if command -v yq >/dev/null 2>&1 && _agy_yq_is_mikefarah; then
    has=$(yq eval "$_AGY_YQ_HAS" - 2>/dev/null <<<"$doc") || return 0
    if [[ "$has" != true ]]; then
      # (r251-6 V5, BB #5: an alias / non-mapping ancestor is said, never read silently as absent — one level at a time:
      # a level below a non-mapping is never traversed)
      for lvl in hounfour hounfour.headless; do
        kt=$(yq eval ".$lvl | kind + \" \" + tag" - 2>/dev/null <<<"$doc") || return 0
        k="${kt%% *}"; t="${kt#* }"
        [[ "$k" == map ]] && continue
        [[ "$k" == alias ]] && { printf 'ancestor %s:alias\n' "$lvl"; return 0; }
        [[ "$t" == '!!null' || -z "$t" || "$t" == "$kt" ]] && return 0
        printf 'ancestor %s:%s\n' "$lvl" "${t#!!}"; return 0
      done
      return 0
    fi
    k=$(yq eval '.hounfour.headless.agy_opt_in | kind' - 2>/dev/null <<<"$doc") || return 0
    [[ "$k" == alias ]] && { printf 'alias \n'; return 0; }
    t=$(yq eval '.hounfour.headless.agy_opt_in | tag' - 2>/dev/null <<<"$doc") || return 0
    v=$(yq eval '.hounfour.headless.agy_opt_in' - 2>/dev/null <<<"$doc") || return 0
    [[ "$v" == *$'\n'* ]] && v=""
    printf '%s %s\n' "${t#!!}" "$v"
    return 0
  fi
  # any other yq flavour (python yq wraps PyYAML) or none: the PyYAML node — its tag and SOURCE text, as the Python twin
  command -v python3 >/dev/null 2>&1 || return 0
  python3 -I -c '
import sys, yaml
class L(yaml.SafeLoader):  # (r251-4 S3: an alias reads as a sentinel, never as the anchored value — the Python twin loader)
    def compose_node(self, parent, index):
        if self.check_event(yaml.AliasEvent):
            self.get_event()
            return yaml.ScalarNode("!loa/alias", "")
        return super().compose_node(parent, index)
core = "tag:yaml.org,2002:"
def kind_of(tag):
    return ("bool" if tag == core + "bool" else "alias" if tag == "!loa/alias"
            else tag[len(core):] if tag.startswith(core) else (tag or "?"))
node = yaml.compose(sys.stdin.buffer.read(), Loader=L)
path = []
for key in ("hounfour", "headless", "agy_opt_in"):
    if not isinstance(node, yaml.MappingNode):
        sys.exit(0)
    found = None
    for k, v in node.value:
        if isinstance(k, yaml.ScalarNode) and k.tag != "tag:yaml.org,2002:merge" and k.value == key:
            found = v
    if found is None:
        sys.exit(0)
    path.append(key)
    if key != "agy_opt_in" and not isinstance(found, yaml.MappingNode):
        kind = kind_of(found.tag or "")
        if kind != "null":
            print("ancestor", ".".join(path) + ":" + kind.replace(" ", "_"))
        sys.exit(0)
    node = found
kind = kind_of(node.tag or "")
text = node.value if isinstance(node, yaml.ScalarNode) and "\n" not in node.value else ""
print(kind.replace(" ", "_"), text)
' 2>/dev/null <<<"$doc" || return 0
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

_AGY_GATE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

_agy_catalog_provider_rc() {  # <model> → as agy_catalog_provider; returns 3 when the maps could not be read (the name fallback was used)
  local m="${1:-}" maps="${_AGY_GATE_LIB_DIR:-}/../generated-model-maps.sh" p="" rc=0
  [[ -n "$m" ]] || return 0
  if [[ "$m" == *:* ]]; then printf '%s\n' "${m%%:*}"; return 0; fi
  # (review r251-4 S5, audit run-2 n7: only a catalog-shaped id reaches an array subscript — an undeclared array is an
  # INDEXED one, whose subscript bash evaluates arithmetically, so `a[$(cmd)]` would run; and the maps must really be
  # associative before one is indexed)
  if [[ "$m" =~ ^[A-Za-z0-9][A-Za-z0-9._@+/-]*$ ]]; then
    if [[ -f "$maps" ]] && (( ${BASH_VERSINFO[0]:-0} >= 4 )); then
      p=$(source "$maps" >/dev/null 2>&1 || exit 3
          [[ "$(declare -p MODEL_IDS 2>/dev/null)" == "declare -A"* && "$(declare -p MODEL_PROVIDERS 2>/dev/null)" == "declare -A"* ]] || exit 3
          id="${MODEL_IDS[$m]:-$m}"
          [[ "$id" =~ ^[A-Za-z0-9][A-Za-z0-9._@+/-]*$ ]] || id="$m"
          printf '%s' "${MODEL_PROVIDERS[$m]:-${MODEL_PROVIDERS[$id]:-}}") 2>/dev/null || { p=""; rc=3; }
    else
      rc=3
    fi
  fi
  if [[ -z "$p" ]]; then case "$m" in gemini*) p=google ;; esac; fi
  [[ -n "$p" ]] && printf '%s\n' "$p"
  return "$rc"
}

_agy_maps_warn_once() {  # (review r251-4 S5 / review Obs 4: the name fallback is said once per shell, never silently)
  [[ -z "$_LOA_AGY_MAPS_WARNED" ]] || return 0
  _LOA_AGY_MAPS_WARNED=1
  printf 'WARN: the generated model maps (%s) could not be read — agy routing falls back to the gemini* name rule; a catalog-only Google alias (deep-research-pro, researcher) is not recognised\n' \
    "${_AGY_GATE_LIB_DIR:-?}/../generated-model-maps.sh" >&2
}

agy_catalog_provider() {  # <model> → the provider cheval resolves it to (review r251-3 R3; Python twin loader.catalog_provider_of)
  # a `provider:` prefix, else the generated catalog maps (MODEL_IDS resolves an alias, MODEL_PROVIDERS names the
  # provider — read in a subshell: this lib may be sourced inside a function, where `declare -A` would be local), else
  # the `gemini*` name → google; nothing when none applies. Bash < 4 or an unreadable map file: the name fallback only,
  # said once per shell (r251-4 S5). Always returns 0.
  _agy_catalog_provider_rc "$@"
  (( $? == 3 )) && _agy_maps_warn_once
  return 0
}

_agy_project_alias_target() {  # <model> <config> → the project config's alias target (hounfour.aliases.<model>: "p:m", or
  # {target|model}); nothing when absent or unreadable (r251-4 S8, audit n14 — the Python twin overlays the same aliases)
  local m="${1:-}" cfg="${2:-}" t
  [[ -n "$m" && "$m" != *:* && -n "$cfg" && -f "$cfg" ]] || return 0
  [[ "$m" =~ ^[A-Za-z0-9][A-Za-z0-9._@+/-]*$ ]] || return 0
  command -v yq >/dev/null 2>&1 && _agy_yq_is_mikefarah || return 0
  t=$(M="$m" yq eval -r '.hounfour.aliases[strenv(M)] | select(kind == "map") .target // select(kind == "map") .model // select(kind == "scalar") // ""' "$cfg" 2>/dev/null) || return 0
  [[ "$t" == null || "$t" == *$'\n'* ]] && t=""
  [[ -n "$t" ]] && printf '%s\n' "$t"
  return 0
}

routes_to_agy() {
  local m="${1:-}" mode="${2:-${LOA_HEADLESS_MODE:-prefer-api}}" cfg="${3:-}" t
  [[ -n "$m" ]] || return 1
  # (r251-4 S8, audit n14: with the project config, a project alias is resolved first — as cheval resolves the hop before
  # its own agy test — so an alias of gemini-headless is agy-routed on any mode; one level, as cheval's alias lookup)
  if [[ -n "$cfg" ]]; then
    t=$(_agy_project_alias_target "$m" "$cfg")
    if [[ -n "$t" && "$t" != "$m" ]] && routes_to_agy "$t" "$mode"; then return 0; fi
  fi
  case "$m" in gemini-headless|*:gemini-headless|gemini-headless:*) return 0 ;; esac
  [[ "$mode" == "cli-only" ]] || return 1
  # (review r251-3 R3: under cli-only the PROVIDER decides — `deep-research-pro`, `researcher` are Google voices without
  # the gemini* name — as in cheval's _entry_routes_to_agy and Bridgebuilder's isAgyRouted)
  local p rc
  p=$(_agy_catalog_provider_rc "$m"); rc=$?
  (( rc == 3 )) && _agy_maps_warn_once   # (in the caller's shell: said once)
  [[ "$p" == google ]]
}

agy_route_planned() {
  local m="${1:-}" cfg="${2:-}"
  routes_to_agy "$m" "$(agy_headless_mode "$cfg")" "$cfg" || return 0
  agy_opted_in "$cfg"
}

agy_gate_warn_once() {
  local cfg="${1:-}" t why=""
  [[ -z "$_LOA_AGY_GATE_WARNED" ]] || return 0
  _LOA_AGY_GATE_WARNED=1
  t=$(_agy_opt_in_node "$cfg")
  case "$t" in
    untrusted\ *)   # (r251-5 U1: the one WARN for this config — the availability WARN below would only repeat "off")
      printf 'WARN: %s: %s — a config others can write never opts in (own it and `chmod go-w` it); the agy route stays off\n' "$AGY_OPT_IN_KEY" "${t#untrusted }" >&2
      return 0 ;;
    ""|"bool true"|"bool false"|null\ *) ;;
    ancestor\ *)   # (r251-6 V5: an alias / non-mapping hounfour or hounfour.headless — the key cannot be read there)
      local where="${t#ancestor }" what
      what="${where##*:}"; where="${where%:*}"
      if [[ "$what" == alias ]]; then what="a YAML alias"; else what="not a mapping ($what)"; fi
      printf 'WARN: %s is %s — %s cannot be read through an alias or merge node (write the mapping inline); the agy route stays off\n' "$where" "$what" "$AGY_OPT_IN_KEY" >&2 ;;
    bool\ *) printf 'WARN: %s is %s, a boolean spelled other than true/false — only `agy_opt_in: true` opts in (the lowercase scalar); the agy route stays off\n' "$AGY_OPT_IN_KEY" "${t#bool }" >&2 ;;
    *) printf 'WARN: %s is present but not a YAML boolean (%s) — only `agy_opt_in: true` opts in (expected true or false); the agy route stays off\n' "$AGY_OPT_IN_KEY" "${t%% *}" >&2 ;;
  esac
  agy_opted_in "$cfg" && return 0
  command -v "${AGY_HEADLESS_BIN:-agy}" >/dev/null 2>&1 && why="agy on PATH"
  [[ -n "${GOOGLE_API_KEY:-}${GEMINI_API_KEY:-}" ]] && why="${why:+$why, }a Google/Gemini key is set"
  [[ -n "$why" ]] || return 0
  printf "WARN: the agy route is available here (%s) but not planned: %s is not true — opt in only knowingly (the prompt travels on the CLI's argv, readable by local users; the CLI must be OAuth-authed)\n" "$why" "$AGY_OPT_IN_KEY" >&2
}
