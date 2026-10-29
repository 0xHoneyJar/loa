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
#   loa_profile_cache_state         → on | off (<reason>): whether the cache
#        below may be read (the trust predicate; no build, no write)
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
# and one jq. The write is atomic (mktemp beside the cache + mv -T, under
# umask 077). The cache is read and written only under the trust predicate
# (cycle-138 FR-1, SDD § 5.1): its directory is a real, uid-owned directory
# with no group/other write bit, and the file a uid-owned single-link regular
# file without one — anything else is REFUSED (cache off, live read, same
# output); this lib never chmods (grimoire-index.sh tightens a legacy
# writable .run on its next run).
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
    # (a bare file name has no directory part: name the directory, so the trust
    # predicate and the writer never take the file name for the directory)
    [[ "$_LOA_PL_CACHE" == */* ]] || _LOA_PL_CACHE="./$_LOA_PL_CACHE"
  elif [[ "$_LOA_PL_CFG" == "$default_cfg" ]]; then
    _LOA_PL_CACHE="$root/.run/effective-config.json"
  else
    _LOA_PL_CACHE=""
  fi
}

# The cache key: the three paths plus one stat line (`path|mtime|size`) per
# existing file. An empty stat output for an existing file (no usable stat)
# disables caching.
#
# The same single stat also samples the trust predicate's inputs (cycle-138
# FR-1, SDD § 5.1 — zero added spawns): the cache's directory and the cache
# file are the fourth and fifth paths and every row carries `|mode|uid|links`.
# `stat -L` prints a row for every path that exists and exits non-zero for the
# missing ones, so its rc is ignored (the BSD form runs only when the GNU form
# printed no row at all) and presence comes from the rows, matched by path in
# argument order (_loa_pl_rows). The three extra fields are stripped from the
# source rows, so the id bytes are today's, and the two extra rows never enter
# the id (a mode change does not rebuild the cache). Output that does not parse
# disables the cache (no id); the predicate then reads both rows as malformed.
# The raw rows stay in _LOA_PL_ST ("x" + one "\n<row>" per existing path).
_loa_pl_id() {
  _LOA_PL_ST=x$'\n'$(stat -Lc '%n|%y|%s|%a|%u|%h' -- "$_LOA_PL_CFG" "$_LOA_PL_PROF" "$_LOA_PL_FLOOR" "${_LOA_PL_CACHE%/*}" "$_LOA_PL_CACHE" 2>/dev/null)
  if ! _loa_pl_rows; then
    if [[ "$_LOA_PL_ST" == x$'\n' ]]; then
      _loa_pl_id_bsd || return 0               # (it sets the id when the BSD form printed no row either)
      _loa_pl_rows || { _LOA_PL_CUR_ID=""; return 0; }
    else
      _LOA_PL_CUR_ID=""                        # output that does not parse: no cache
      return 0
    fi
  fi
  # the source rows without their |mode|uid|links suffix, joined by ";" (group 1 spans rows one and two)
  _LOA_PL_CUR_ID="v1|$_LOA_PL_CFG|$_LOA_PL_PROF|$_LOA_PL_FLOOR|${BASH_REMATCH[3]}${BASH_REMATCH[10]:+${BASH_REMATCH[3]:+;}}${BASH_REMATCH[10]}${BASH_REMATCH[17]:+${BASH_REMATCH[1]:+;}}${BASH_REMATCH[17]}"
}

# The GNU form printed no row (the rows regex needs one): retry with the BSD form; still no row → today's
# rule (no id when the config or profiles.yaml exists — no usable stat — else the id of three absent
# files) and 1; 0 → parse the BSD rows.
_loa_pl_id_bsd() {
  _LOA_PL_ST=x$'\n'$(stat -Lf '%N|%Fm|%z|%Lp|%u|%l' -- "$_LOA_PL_CFG" "$_LOA_PL_PROF" "$_LOA_PL_FLOOR" "${_LOA_PL_CACHE%/*}" "$_LOA_PL_CACHE" 2>/dev/null)
  [[ "$_LOA_PL_ST" == x$'\n' ]] || return 0
  if [[ -e "$_LOA_PL_CFG" || -e "$_LOA_PL_PROF" ]]; then
    _LOA_PL_CUR_ID=""
  else
    _LOA_PL_CUR_ID="v1|$_LOA_PL_CFG|$_LOA_PL_PROF|$_LOA_PL_FLOOR|"
  fi
  return 1
}

# One row per existing path, in argument order: \n<path>|<f1>|<f2>|<mode>|<uid>|<links>. BASH_REMATCH groups:
#   1 rows one+two · cfg 2 (row) 3 (path|mtime|size) 4-8 · prof 9 10 11-15 · floor 16 17 18-22
#   dir 23 24 25 26 27=mode 28=uid 29 · file 30 31 32 33 34=mode 35=uid 36=links
_LOA_PL_F=$'\\|([^|\n]*)'
_loa_pl_rows() {
  [[ "$_LOA_PL_ST" =~ ^x(($'\n'("$_LOA_PL_CFG"$_LOA_PL_F$_LOA_PL_F)$_LOA_PL_F$_LOA_PL_F$_LOA_PL_F)?($'\n'("$_LOA_PL_PROF"$_LOA_PL_F$_LOA_PL_F)$_LOA_PL_F$_LOA_PL_F$_LOA_PL_F)?)($'\n'("$_LOA_PL_FLOOR"$_LOA_PL_F$_LOA_PL_F)$_LOA_PL_F$_LOA_PL_F$_LOA_PL_F)?($'\n'("${_LOA_PL_CACHE%/*}"$_LOA_PL_F$_LOA_PL_F)$_LOA_PL_F$_LOA_PL_F$_LOA_PL_F)?($'\n'("$_LOA_PL_CACHE"$_LOA_PL_F$_LOA_PL_F)$_LOA_PL_F$_LOA_PL_F$_LOA_PL_F)?$ ]]
}

# --- The cache trust predicate (cycle-138 FR-1, SDD § 5.1; D-1.1 DEC-1148, D-1.2 DEC-1166, DEC-1157).
# REFUSE, never chmod: a directory or file that fails is not read and the live read answers (same output,
# no stderr); the reason is kept in _LOA_PL_CACHE_OFF for loa_profile_cache_state.
#
# Trust lifetime = the process. The predicate is evaluated from the stat rows sampled by _loa_pl_id. Every
# sampled property (owner, mode bits, file type, link count) can be changed afterwards only by the same uid
# or by root: a same-uid adversary already owns the session and root is outside the threat model. Replacing
# .run itself needs write permission on the checkout root, the trust root. The writer's builtin re-check
# right before the rename ([[ -O dir && ! -L dir ]]) is a belt, not the argument.
#
# _loa_pl_cache_usable is the warm-path form: ONE regex over the raw directory and file rows (uid == EUID
# on both, no group/other write digit, one link, the seam outside bats excluded) plus three file-type
# tests — xtrace counts every [[ ]] primary, and the karpathy hook's budget counts trace lines. The bats
# markers (BATS_TEST_FILENAME / BATS_VERSION) that let a redirected seam skip the anchored-realpath check are
# ordinary environment variables: the gate is a footgun guard for test fixtures, not a security boundary
# (DEC-1157, DEC-1168) — the default cache path is covered by the directory checks regardless. When it
# does not admit, the reference ladders _loa_pl_cache_trusted && _loa_pl_cache_readable decide and name
# the reason. The fast form admits a subset of what the ladders admit: [0145][0145] as the last two mode
# digits is "no 022 bit"; a file row exists only when the directory resolves to a directory, and the
# directory is not a symlink, so it is a real directory.
_loa_pl_cache_usable() {
  [[ "$_LOA_PL_ST|${LOA_PROFILE_CACHE_FILE:+S}${BATS_TEST_FILENAME:+B}${BATS_VERSION:+B}" =~ $'\n'"${_LOA_PL_CACHE%/*}"$_LOA_PL_F$_LOA_PL_F\|[0-7]*[0145][0145]\|$EUID$_LOA_PL_F$'\n'"$_LOA_PL_CACHE"$_LOA_PL_F$_LOA_PL_F\|[0-7]*[0145][0145]\|$EUID\|1\|(S?B+)?$ &&
     ! -L "${_LOA_PL_CACHE%/*}" && -f "$_LOA_PL_CACHE" && ! -L "$_LOA_PL_CACHE" ]] ||
    { _loa_pl_cache_trusted && _loa_pl_cache_readable; }
}

# The ladders' view of the two trust rows: _LOA_PL_{DIR,FILE}_ROW ("d" / "f" when the row exists),
# _LOA_PL_{DIR,FILE}_MODE, _LOA_PL_{DIR,FILE}_UID, _LOA_PL_FILE_LINKS (raw fields; validated by the ladders).
# Unparsable stat output → both rows present with empty (malformed) fields.
_loa_pl_trust_rows() {
  _LOA_PL_DIR_ROW="" _LOA_PL_DIR_MODE="" _LOA_PL_DIR_UID="" _LOA_PL_FILE_ROW="" _LOA_PL_FILE_MODE="" _LOA_PL_FILE_UID="" _LOA_PL_FILE_LINKS=""
  [[ -n "${_LOA_PL_ST:-}" && "$_LOA_PL_ST" != x$'\n' ]] || return 0
  if ! _loa_pl_rows; then
    _LOA_PL_DIR_ROW=d _LOA_PL_FILE_ROW=f
    return 0
  fi
  _LOA_PL_DIR_ROW="${BASH_REMATCH[23]:+d}" _LOA_PL_DIR_MODE="${BASH_REMATCH[27]}" _LOA_PL_DIR_UID="${BASH_REMATCH[28]}"
  _LOA_PL_FILE_ROW="${BASH_REMATCH[30]:+f}" _LOA_PL_FILE_MODE="${BASH_REMATCH[34]}" _LOA_PL_FILE_UID="${BASH_REMATCH[35]}" _LOA_PL_FILE_LINKS="${BASH_REMATCH[36]}"
}

# _loa_pl_trusted_dir <dir> "<uid> <mode>": the invariant lines shared with grimoire-index.sh's
# _gi_trusted_dir (the drift guard in profile-lib.bats compares them); there it chmods, here it refuses.
_loa_pl_trusted_dir() {
  local st="$2"
  [[ "$st" =~ ^([0-9]+)\ ([0-7]+)$ ]] || { _LOA_PL_CACHE_OFF=dir-stat; return 1; }
  [[ -d "$1" && ! -L "$1" ]] || { _LOA_PL_CACHE_OFF=dir-not-plain; return 1; }
  [[ "${BASH_REMATCH[1]}" == "$EUID" ]] || { _LOA_PL_CACHE_OFF=dir-foreign; return 1; }
  (( (8#${BASH_REMATCH[2]} & 8#022) == 0 )) || { _LOA_PL_CACHE_OFF=dir-writable; return 1; }   # REFUSE (DEC-1157); repair owner: grimoire-index
  return 0
}

# _loa_pl_cache_anchored <dir>: 0 when the canonical <dir> is the canonical trust root joined to <dir>'s
# path below the root — no symlinked component below the root (a path outside the root never matches).
# No `realpath -m` (BSD) → refused.
_loa_pl_cache_anchored() {
  local real root_real
  real=$(realpath -m -- "$1" 2>/dev/null) || return 1
  root_real=$(realpath -m -- "$_LOA_PL_ROOT" 2>/dev/null) || return 1
  [[ -n "$real" && -n "$root_real" && "$1" == "$_LOA_PL_ROOT/"* && "$real" == "$root_real/${1#"$_LOA_PL_ROOT/"}" ]]
}

# The directory half: 0 → the directory may be used. dir-absent is the writer's cue to create it.
_loa_pl_cache_trusted() {
  local d="${_LOA_PL_CACHE%/*}"
  _LOA_PL_CACHE_OFF=""
  _loa_pl_trust_rows
  [[ -n "$_LOA_PL_CACHE" ]] || { _LOA_PL_CACHE_OFF=no-cache-path; return 1; }
  # A redirected cache outside bats: no symlinked component below the trust root (inside bats the seam's
  # directory is a test's own mktemp directory; the tests call _loa_pl_cache_anchored directly). Checked
  # first, so an absent directory under a symlinked component is never created by the writer.
  if [[ -n "${LOA_PROFILE_CACHE_FILE:-}" && -z "${BATS_TEST_FILENAME:-}${BATS_VERSION:-}" ]]; then
    _loa_pl_cache_anchored "$d" || { _LOA_PL_CACHE_OFF=dir-symlinked-component; return 1; }
  fi
  if [[ -z "$_LOA_PL_DIR_ROW" ]]; then
    if [[ -e "$d" || -L "$d" ]]; then _LOA_PL_CACHE_OFF=dir-stat; else _LOA_PL_CACHE_OFF=dir-absent; fi
    return 1
  fi
  _loa_pl_trusted_dir "$d" "$_LOA_PL_DIR_UID $_LOA_PL_DIR_MODE" || return 1
  return 0
}

# The file half, for reads only: a regular non-symlink file, owned by the uid, one link, no g/o write bit.
_loa_pl_cache_readable() {
  local st
  _LOA_PL_CACHE_OFF=""
  _loa_pl_trust_rows
  st="$_LOA_PL_FILE_UID $_LOA_PL_FILE_MODE $_LOA_PL_FILE_LINKS"
  if [[ -z "$_LOA_PL_FILE_ROW" ]]; then
    if [[ -e "$_LOA_PL_CACHE" || -L "$_LOA_PL_CACHE" ]]; then _LOA_PL_CACHE_OFF=file-untrusted; else _LOA_PL_CACHE_OFF=file-absent; fi
    return 1
  fi
  [[ "$st" =~ ^([0-9]+)\ ([0-7]+)\ ([0-9]+)$ ]] || { _LOA_PL_CACHE_OFF=file-untrusted; return 1; }
  [[ -f "$_LOA_PL_CACHE" && ! -L "$_LOA_PL_CACHE" ]] || { _LOA_PL_CACHE_OFF=file-untrusted; return 1; }
  [[ "${BASH_REMATCH[1]}" == "$EUID" && "${BASH_REMATCH[3]}" == 1 ]] || { _LOA_PL_CACHE_OFF=file-untrusted; return 1; }
  (( (8#${BASH_REMATCH[2]} & 8#022) == 0 )) || { _LOA_PL_CACHE_OFF=file-untrusted; return 1; }
  return 0
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

# Writes the cache only into a directory the predicate trusts (SDD § 5.1 outcomes): a refused directory is
# left untouched (no mkdir, no chmod); an absent one is created 0700 with mkdir WITHOUT -p (a directory that
# appeared meanwhile is not ours → no cache this process; one we just created is trusted by construction).
# The file is never written through: mktemp beside it, then a rename that replaces the directory entry — a
# planted symlink, FIFO, foreign or hard-linked file is replaced (a symlink's target and a hard link's other
# name keep their bytes); a directory at the cache path is not replaced (mv -T fails, the fallback refuses).
# Any failure removes the temp.
_loa_pl_write_cache() {
  [[ -n "$_LOA_PL_CACHE" && -n "$_LOA_PL_CUR_ID" && -n "$_LOA_PL_JSON" ]] || return 0
  local dir="${_LOA_PL_CACHE%/*}"
  if ! _loa_pl_cache_trusted; then
    [[ "$_LOA_PL_CACHE_OFF" == dir-absent ]] || return 0
    ( umask 077; mkdir -- "$dir" ) 2>/dev/null || return 0
  fi
  ( umask 077
    [[ -O "$dir" && ! -L "$dir" ]] || exit 1   # builtin belt right before the write (trust lifetime: above)
    tmp=$(mktemp "$_LOA_PL_CACHE.XXXXXX" 2>/dev/null) || exit 1
    if printf '%s\n' "$_LOA_PL_JSON" > "$tmp" 2>/dev/null &&
       { mv -f -T "$tmp" "$_LOA_PL_CACHE" 2>/dev/null ||
         { [[ ! -d "$_LOA_PL_CACHE" && ! -L "$_LOA_PL_CACHE" ]] && mv -f "$tmp" "$_LOA_PL_CACHE" 2>/dev/null; }; }; then
      exit 0
    fi
    rm -f "$tmp" 2>/dev/null
    exit 1 )
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
  if [[ -n "$_LOA_PL_CACHE" && -n "$_LOA_PL_CUR_ID" ]] && _loa_pl_cache_usable; then
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
  if [[ -z "$_LOA_PL_JSON" && -n "$_LOA_PL_CACHE" && -n "$_LOA_PL_CUR_ID" ]] && _loa_pl_cache_usable &&
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

# on | off (<reason>) — the trust predicate on a fresh stat sample, without a build or a write
# (cycle-138 FR-1; /loa appends it to the Profile line only when off). Reasons: no-cache-path, dir-absent,
# dir-stat, dir-not-plain, dir-foreign, dir-writable, dir-symlinked-component, file-absent, file-untrusted.
loa_profile_cache_state() {
  _loa_pl_paths
  _loa_pl_id
  if _loa_pl_cache_trusted && _loa_pl_cache_readable; then
    echo on
  else
    printf 'off (%s)\n' "${_LOA_PL_CACHE_OFF:-dir-stat}"
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
