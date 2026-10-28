#!/usr/bin/env bash
# =============================================================================
# profile-lib.sh — `loa.profile` resolution (cycle-129 SDD D-9.1, §5.3;
# DEC-0143, DEC-0152, DEC-0166).
#
# Sourced API (bash 3.2 safe; sets no shell options; every function returns 0
# unless stated):
#   loa_profile                     → lean | standard | full
#   loa_profile_source              → explicit | default | invalid
#   loa_knob <yq-path> <fallback>   → the effective value of one config key:
#        the key set explicitly in the config (an explicit `false` counts —
#        never `// default`, which reads false as absent), else the selected
#        profile's value when the key is a profile key, else <fallback>.
#        Returns 2 (printing the fallback) on a malformed path.
#   loa_profile_overrides           → `key=value` lines, one per explicit
#        profile key whose value differs from the selected profile's value
#   loa_effective_json              → the resolved document (below)
#
# CLI: profile-lib.sh profile | source | knob <path> <fallback> | overrides | json
#
# Inputs (each has a test seam):
#   config    LOA_PROFILE_CONFIG_FILE, else LOA_STATUS_CONFIG_FILE (honoured
#             only under bats, like loa-status.sh), else <root>/.loa.config.yaml
#   profiles  LOA_PROFILES_FILE, else <root>/.claude/data/profiles.yaml
#   floor     LOA_PROFILE_FLOOR_FILE, else <root>/.claude/data/floor.yaml
#   root      LOA_PROFILE_ROOT, else three directories above this file
#
# Cache: <root>/.run/effective-config.json (LOA_PROFILE_CACHE_FILE overrides),
# keyed on the paths and the mtime+size of the config, profiles.yaml and
# floor.yaml: any edit to one of them rebuilds it on the next call, so it is
# built once per session in practice. When the config is a seam (not the
# repository's own file) and no cache seam is set, nothing is cached — a test
# config never overwrites the repository's cache. The warm path is one stat
# and one jq. The write is atomic (temp file + mv in the same directory).
#
# Safety: a profile key that names a floor key (floor.yaml `floor_keys`, `*`
# matches one or more characters; an ancestor of a floor key also counts) is
# ignored with a WARN — no profile can reach the floor. Key paths are checked
# against ^[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)*$ before they reach a yq expression.
# Overrides and the requested profile name are control-stripped and cut.
# =============================================================================

_LOA_PL_SELF="${BASH_SOURCE[0]}"
_LOA_PL_SELF_DIR="${_LOA_PL_SELF%/*}"
[[ "$_LOA_PL_SELF_DIR" == "$_LOA_PL_SELF" ]] && _LOA_PL_SELF_DIR="."
_LOA_PL_SELF_DIR="$(cd "$_LOA_PL_SELF_DIR" 2>/dev/null && pwd -P)"
_LOA_PL_JSON=""
_LOA_PL_ID=""

_loa_pl_paths() {
  local root="${LOA_PROFILE_ROOT:-}"
  if [[ -z "$root" ]]; then
    root="$(cd "$_LOA_PL_SELF_DIR/../../.." 2>/dev/null && pwd -P)"
  fi
  _LOA_PL_ROOT="$root"
  local default_cfg="$root/.loa.config.yaml" status_cfg=""
  # LOA_STATUS_CONFIG_FILE is loa-status.sh's bats-gated seam; honour it the same way.
  if [[ -n "${BATS_TEST_FILENAME:-}${BATS_VERSION:-}" ]]; then
    status_cfg="${LOA_STATUS_CONFIG_FILE:-}"
  fi
  _LOA_PL_CFG="${LOA_PROFILE_CONFIG_FILE:-${status_cfg:-$default_cfg}}"
  # The seam is honoured outside bats (hooks pass their test config through it); make a
  # redirected live read visible, once per process (audit r256-5, dissent DISS-C-004).
  if [[ -n "${LOA_PROFILE_CONFIG_FILE:-}" && -z "${BATS_TEST_FILENAME:-}${BATS_VERSION:-}" && -z "${_LOA_PL_SEAM_WARNED:-}" ]]; then
    printf 'profile-lib: WARN knob reads come from %s (LOA_PROFILE_CONFIG_FILE is set)\n' "$LOA_PROFILE_CONFIG_FILE" >&2
    _LOA_PL_SEAM_WARNED=1
  fi
  _LOA_PL_PROF="${LOA_PROFILES_FILE:-$root/.claude/data/profiles.yaml}"
  _LOA_PL_FLOOR="${LOA_PROFILE_FLOOR_FILE:-$root/.claude/data/floor.yaml}"
  if [[ -n "${LOA_PROFILE_CACHE_FILE:-}" ]]; then
    _LOA_PL_CACHE="$LOA_PROFILE_CACHE_FILE"
  elif [[ "$_LOA_PL_CFG" == "$default_cfg" ]]; then
    _LOA_PL_CACHE="$root/.run/effective-config.json"
  else
    _LOA_PL_CACHE=""
  fi
}

# The cache key: the three paths plus one stat line per existing file. An
# empty stat output for an existing file (no usable stat) disables caching.
_loa_pl_id() {
  local st
  st=$(stat -Lc '%n|%y|%s' -- "$_LOA_PL_CFG" "$_LOA_PL_PROF" "$_LOA_PL_FLOOR" 2>/dev/null) ||
    st=$(stat -Lf '%N|%Fm|%z' -- "$_LOA_PL_CFG" "$_LOA_PL_PROF" "$_LOA_PL_FLOOR" 2>/dev/null) || true
  if [[ -z "$st" ]] && [[ -e "$_LOA_PL_CFG" || -e "$_LOA_PL_PROF" ]]; then
    _LOA_PL_CUR_ID=""
    return 0
  fi
  _LOA_PL_CUR_ID="v1|$_LOA_PL_CFG|$_LOA_PL_PROF|$_LOA_PL_FLOOR|${st//$'\n'/;}"
}

_loa_pl_warn() { printf '[profile-lib] WARN: %s\n' "$*" >&2; }

# Builds the resolved document from the three inputs into _LOA_PL_JSON.
_loa_pl_build() {
  local cfg='{}' prof='{}' floor='[]' out
  if ! command -v jq >/dev/null 2>&1 || ! command -v yq >/dev/null 2>&1; then
    _LOA_PL_JSON=""
    return 1
  fi
  if [[ -f "$_LOA_PL_CFG" ]]; then
    if ! cfg=$(yq -o=json '.' "$_LOA_PL_CFG" 2>/dev/null); then
      _loa_pl_warn "$_LOA_PL_CFG does not parse; profile defaults apply"
      cfg='{}'
    fi
  fi
  if [[ -f "$_LOA_PL_PROF" ]]; then
    if ! prof=$(yq -o=json '.' "$_LOA_PL_PROF" 2>/dev/null); then
      _loa_pl_warn "$_LOA_PL_PROF does not parse; no profile defaults apply"
      prof='{}'
    fi
  else
    _loa_pl_warn "$_LOA_PL_PROF is missing; no profile defaults apply"
  fi
  if [[ -f "$_LOA_PL_FLOOR" ]]; then
    floor=$(yq -o=json '.floor_keys // []' "$_LOA_PL_FLOOR" 2>/dev/null) || floor='[]'
  fi
  [[ -n "$cfg" ]] || cfg='{}'
  [[ -n "$prof" ]] || prof='{}'
  [[ -n "$floor" ]] || floor='[]'
  out=$(printf '%s\n%s\n%s\n' "$cfg" "$prof" "$floor" | jq -cs --arg id "$_LOA_PL_CUR_ID" '
    def render: if type == "string" then . elif type == "object" or type == "array" then tojson else tostring end;
    def clean($n): render | gsub("[[:cntrl:]]"; "?") | .[0:$n];
    def globre: "^" + (split("*") | map(gsub("\\."; "\\.")) | join(".+")) + "$";
    (.[0] | if type == "object" then . else {} end) as $cfg |
    (.[1] | if type == "object" then . else {} end) as $pf |
    (.[2] | if type == "array" then map(select(type == "string")) else [] end) as $floor |
    ($pf.profiles | if type == "object" then . else {} end) as $profiles |
    ([$profiles[] | objects | keys[]] | unique) as $all |
    def forbidden($k): any($floor[]; . as $f | ($k | test($f | globre)) or (($f | split("*")[0]) | startswith($k + ".")));
    ($all | map(select(forbidden(.)))) as $bad |
    ($all - $bad) as $keys |
    # cycle-137 FR-4 (SDD § 5.4): profiles.yaml `cached_keys` — non-profile knobs read on hot paths. A listed
    # key that is a profile key stays a profile key; a floor key is dropped with the profile WARN text.
    ($pf.cached_keys | if type == "array" then map(select(type == "string" and test("^[A-Za-z0-9_]+(\\.[A-Za-z0-9_]+)*$"))) else [] end
     | reduce .[] as $c ([]; if index([$c]) then . else . + [$c] end) | . - $all) as $cks |
    ($cks | map(select(forbidden(.)))) as $ckbad |
    ($cks - $ckbad) as $cached |
    (try ($cfg.loa.profile) catch null) as $req |
    (if $req == null then {name: "standard", source: "default"}
     elif ($req | type) == "string" and ($profiles[$req]? | type) == "object" then {name: $req, source: "explicit"}
     else {name: "standard", source: "invalid"} end) as $sel |
    ($profiles[$sel.name]? // {} | if type == "object" then . else {} end) as $pv |
    (reduce $keys[] as $k ({};
        (try ($cfg | getpath($k | split("."))) catch null) as $e |
        (if ($pv | has($k)) then $pv[$k] else null end) as $p |
        if $e != null then .[$k] = {value: $e, source: "explicit", profile_value: $p}
        elif ($pv | has($k)) then .[$k] = {value: $p, source: "profile", profile_value: $p}
        else . end)
     # (a cached key: `explicit` iff the config value is not null, the same `. == null → MISS` rule as _loa_pl_live;
     # `absent` → loa_knob prints the fallback of the caller without a live read)
     | reduce $cached[] as $k (.;
        (try ($cfg | getpath($k | split("."))) catch null) as $e |
        .[$k] = {value: $e, source: (if $e != null then "explicit" else "absent" end), profile_value: null})) as $knobs |
    {
      schema_version: 1,
      id: $id,
      profile: $sel.name,
      profile_source: $sel.source,
      profile_requested: (if $req == null then null else ($req | clean(64)) end),
      profile_keys: $keys,
      knobs: $knobs,
      overrides: ([$knobs | to_entries[] | select(.key as $k | $keys | index([$k]))
                   | select(.value.source == "explicit" and .value.value != .value.profile_value)
                   | "\(.key)=\(.value.value | clean(128))"] | sort),
      warnings: ([if $sel.source == "invalid" then "unknown loa.profile \"\($req | clean(64))\"; using standard" else empty end]
                 + [($bad + $ckbad)[] | "profiles.yaml key \(.) names a floor key; ignored"])
    }' 2>/dev/null) || out=""
  if [[ -z "$out" ]]; then
    _LOA_PL_JSON=""
    return 1
  fi
  _LOA_PL_JSON="$out"
  local w
  while IFS= read -r w; do
    [[ -n "$w" ]] && _loa_pl_warn "$w"
  done < <(printf '%s' "$out" | jq -r '.warnings[]?' 2>/dev/null)
  return 0
}

_loa_pl_write_cache() {
  [[ -n "$_LOA_PL_CACHE" && -n "$_LOA_PL_CUR_ID" && -n "$_LOA_PL_JSON" ]] || return 0
  local dir="${_LOA_PL_CACHE%/*}" tmp
  [[ "$dir" == "$_LOA_PL_CACHE" ]] && dir="."
  if [[ ! -d "$dir" ]]; then
    mkdir -p "$dir" 2>/dev/null || return 0
  fi
  tmp="$_LOA_PL_CACHE.tmp.$$"
  if printf '%s\n' "$_LOA_PL_JSON" > "$tmp" 2>/dev/null; then
    mv -f "$tmp" "$_LOA_PL_CACHE" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  else
    rm -f "$tmp" 2>/dev/null
  fi
  return 0
}

# Loads the resolved document into _LOA_PL_JSON (memo → cache → build).
# Returns 1 when it cannot be resolved (jq or yq missing).
_loa_pl_load() {
  _loa_pl_paths
  _loa_pl_id
  if [[ -n "$_LOA_PL_JSON" && -n "$_LOA_PL_CUR_ID" && "$_LOA_PL_ID" == "$_LOA_PL_CUR_ID" ]]; then
    return 0
  fi
  command -v jq >/dev/null 2>&1 || return 1
  if [[ -n "$_LOA_PL_CACHE" && -n "$_LOA_PL_CUR_ID" && -f "$_LOA_PL_CACHE" ]]; then
    local j
    j=$(jq -c --arg id "$_LOA_PL_CUR_ID" 'if .schema_version == 1 and .id == $id then . else empty end' \
        "$_LOA_PL_CACHE" 2>/dev/null) || j=""
    if [[ -n "$j" ]]; then
      _LOA_PL_JSON="$j"
      _LOA_PL_ID="$_LOA_PL_CUR_ID"
      return 0
    fi
  fi
  _loa_pl_build || return 1
  _LOA_PL_ID="$_LOA_PL_CUR_ID"
  _loa_pl_write_cache
  return 0
}

# Live read of one explicit key (non-profile keys, or no resolution available).
_loa_pl_live() {
  local key="$1" fallback="$2" v
  if [[ -f "${_LOA_PL_CFG:-}" ]] && command -v yq >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    v=$(yq -o=json ".$key" "$_LOA_PL_CFG" 2>/dev/null | jq -r 'if . == null then "__LOA_PL_MISS__" elif type == "string" then . elif type == "object" or type == "array" then tojson else tostring end' 2>/dev/null) || v=""
    if [[ -n "$v" && "$v" != "__LOA_PL_MISS__" ]]; then
      printf '%s\n' "$v"
      return 0
    fi
  fi
  printf '%s\n' "$fallback"
  return 0
}

loa_knob() {
  local path="${1:-}" fallback="${2:-}" key v
  key="${path#.}"
  if [[ ! "$key" =~ ^[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)*$ ]]; then
    _loa_pl_warn "loa_knob: malformed key path '${path//[^A-Za-z0-9._-]/?}'"
    printf '%s\n' "$fallback"
    return 2
  fi
  # Warm path: one stat + one jq straight from the cache file.
  _loa_pl_paths
  _loa_pl_id
  if [[ -z "$_LOA_PL_JSON" && -n "$_LOA_PL_CACHE" && -n "$_LOA_PL_CUR_ID" && -f "$_LOA_PL_CACHE" ]] &&
     command -v jq >/dev/null 2>&1; then
    v=$(jq -r --arg id "$_LOA_PL_CUR_ID" --arg k "$key" '
          if .schema_version == 1 and .id == $id then
            (if (.knobs | has($k)) then
               (if .knobs[$k].source == "absent" then "__LOA_PL_ABSENT__" else .knobs[$k].value
                | (if type == "string" then . elif type == "object" or type == "array" then tojson else tostring end) end)
             else "__LOA_PL_MISS__" end)
          else "__LOA_PL_STALE__" end' "$_LOA_PL_CACHE" 2>/dev/null) || v="__LOA_PL_STALE__"
    if [[ "$v" == "__LOA_PL_ABSENT__" ]]; then   # (cycle-137 FR-4: a cached key the config does not set — no live read)
      printf '%s\n' "$fallback"
      return 0
    fi
    if [[ "$v" == "__LOA_PL_MISS__" ]]; then
      _loa_pl_live "$key" "$fallback"
      return 0
    fi
    if [[ -n "$v" && "$v" != "__LOA_PL_STALE__" ]]; then
      printf '%s\n' "$v"
      return 0
    fi
  fi
  if ! _loa_pl_load; then
    _loa_pl_live "$key" "$fallback"
    return 0
  fi
  v=$(printf '%s' "$_LOA_PL_JSON" | jq -r --arg k "$key" '
        if (.knobs | has($k)) then
          (if .knobs[$k].source == "absent" then "__LOA_PL_ABSENT__" else .knobs[$k].value
           | (if type == "string" then . elif type == "object" or type == "array" then tojson else tostring end) end)
        else "__LOA_PL_MISS__" end' 2>/dev/null) || v="__LOA_PL_MISS__"
  if [[ "$v" == "__LOA_PL_ABSENT__" ]]; then
    printf '%s\n' "$fallback"
    return 0
  fi
  if [[ -z "$v" || "$v" == "__LOA_PL_MISS__" ]]; then
    _loa_pl_live "$key" "$fallback"
    return 0
  fi
  printf '%s\n' "$v"
  return 0
}

loa_profile() {
  if _loa_pl_load; then
    printf '%s' "$_LOA_PL_JSON" | jq -r '.profile // "standard"' 2>/dev/null || echo standard
  else
    echo standard
  fi
  return 0
}

loa_profile_source() {
  if _loa_pl_load; then
    printf '%s' "$_LOA_PL_JSON" | jq -r '.profile_source // "default"' 2>/dev/null || echo default
  else
    echo default
  fi
  return 0
}

loa_profile_overrides() {
  if _loa_pl_load; then
    printf '%s' "$_LOA_PL_JSON" | jq -r '.overrides[]?' 2>/dev/null || true
  fi
  return 0
}

loa_effective_json() {
  if _loa_pl_load; then
    printf '%s\n' "$_LOA_PL_JSON"
  else
    echo '{}'
  fi
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  export LC_ALL=C
  case "${1:-}" in
    profile)   loa_profile ;;
    source)    loa_profile_source ;;
    knob)      [[ $# -ge 2 ]] || { echo "usage: profile-lib.sh knob <yq-path> [fallback]" >&2; exit 2; }
               loa_knob "$2" "${3:-}"; exit $? ;;
    overrides) loa_profile_overrides ;;
    json)      loa_effective_json ;;
    *)         sed -n '3,/^# =====/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
  esac
fi
