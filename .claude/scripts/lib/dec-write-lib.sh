#!/usr/bin/env bash
# =============================================================================
# dec-write-lib.sh: the single writer of the decision ledger grimoires/loa/decisions.yaml
#
# Rows are append-only (schema: grimoires/loa/sdd.md §3.1, docs/architecture/decision-lineage.md).
# Every write takes the lock, copies the ledger to a temp file beside it, applies the change with
# yq v4 (values reach yq only through env(); rows are built by jq --arg), VERIFIES the temp (it
# parses, no id dropped or repeated, the row count moves by exactly the operation's rows, every
# other row JSON-equal, and validate-artifact.sh --type decisions --base-file <current> passes),
# then renames it over the ledger. Any failure deletes the temp and leaves the ledger untouched.
#
# Attribution is derived, never passed: no caller sets decided_by. Skills write `open` or
# `proposed` rows with proposed_by agent (flatline|dissent only interactively, with an existing
# artifact whose sha256 is recorded). In an unattended context (`context` below) every write lands
# `proposed` (an explicit --status open stays open: an open question, not a decision taken),
# proposed_by is agent, and --answer-ref / --as are ignored with a WARN. Only the operator-only
# /decisions command passes --recorded-by decisions-command, the one caller of `confirm`, of
# `reject`/`supersede` on a decided row and of `context --clear`.
#
# A linked worktree (git-common-dir differs from git-dir) or --pending writes
# grimoires/loa/a2a/sprint-<N>/decisions-pending.yaml with PEND-<8 hex> ids; `import` in the
# main checkout allocates the real DEC ids. Live-ledger writes exit 1 under CI, GITHUB_ACTIONS
# or LOA_HOOK_CONTEXT=1 (--file fixtures are exempt so the suites run in CI).
#
# Ops:
#   new        --summary S --phase P --category C --recorded-by R --source SRC
#              [--status open|proposed] [--decision D --rationale W --alternative-json J ...]
#              [--consequence-pos X ...] [--consequence-neg X ...] [--answer-ref REF]
#              [--as flatline|dissent] [--cycle C] [--evidence E] [--pending] [--sprint N]
#   decide     --id ID --decision D --rationale W --alternative-json J ... --evidence E --recorded-by R
#              [--answer-ref REF] [--consequence-pos X ...] [--consequence-neg X ...]
#   confirm    --recorded-by decisions-command --evidence E (--id ID ... | --cycle C [--all])
#              [--answer-ref REF]                                   (/decisions only)
#   reject     --id ID --rationale W --follow-up F --recorded-by R [--prior-request X ...]
#   supersede  --id OLD plus the `new` flags (decision, rationale, alternatives required)
#   import     --from PENDING [--rewrite PATH ...]                   (main checkout only)
#   list       [--status S,..] [--voice V,..] [--decided-by V,..] [--not-decided-by V,..]
#              [--cycle C] [--since ISO] [--source-prefix P] [--source-epic SLUG] [--id ID ...]
#              [--format tsv|md|json]                               (read-only)
#   context    [--why] [--prd PATH] | --set-unattended --reason R | --clear --recorded-by decisions-command
# Common: --file PATH (target override), --quiet
# Exit: 0 ok; 1 refused (preflight, CI/hook context, lock busy, verify, validation, unknown id,
#       illegal transition, ref grammar, missing artifact, ambiguous confirm); 2 usage.
# =============================================================================
export LC_ALL=C
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd -P)"
G="${PROJECT_ROOT}/grimoires/loa"
LIVE="${G}/decisions.yaml"
VALIDATOR="${PROJECT_ROOT}/.claude/scripts/validate-artifact.sh"
OPERATOR_CMD="decisions-command"
QUIET=0
TMPF=""
MKLOCK=""
SCRATCH=""
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../compat-lib.sh"

release_mklock(){ [[ -n "$MKLOCK" ]] || return 0; rm -f "${MKLOCK}/pid" 2>/dev/null; rmdir "$MKLOCK" 2>/dev/null; MKLOCK=""; return 0; }
cleanup(){ [[ -n "$TMPF" ]] && rm -f "$TMPF" 2>/dev/null; [[ -n "$SCRATCH" ]] && rm -f "$SCRATCH".old "$SCRATCH".new "$SCRATCH" 2>/dev/null; release_mklock; return 0; }
trap cleanup EXIT

log(){ [[ $QUIET -eq 0 ]] && echo "$@" >&2 || true; }
warn(){ echo "dec-write: WARN: $*" >&2; }
die(){ echo "dec-write: $*" >&2; exit 1; }
usage(){ echo "dec-write: usage: $*" >&2; exit 2; }

# Single-line scalar, identical to kf-write-lib.sh san1(): strip control bytes, C1 controls and
# U+2028/U+2029 (as their UTF-8 bytes under LC_ALL=C), flatten whitespace, trim.
DEC_ULB_RE="$(printf '\302[\200-\237]|\342\200[\250\251]')"
san1(){ printf '%s' "${1-}" | tr -d '\000-\010\013\014\016-\037\177' | tr '\t\n\r' '   ' | sed -E "s/${DEC_ULB_RE}/ /g"' ; s/  +/ /g; s/^ //; s/ $//'; }

# ---- arg parsing (bash 3.2 safe: no associative arrays; values stored as O_<key>) ----
BOOL_KEYS=" quiet all pending why set-unattended clear "
MULTI_KEYS=" id alternative-json consequence-pos consequence-neg rewrite prior-request "
KNOWN_KEYS=" file summary phase category recorded-by source status decision rationale answer-ref as cycle evidence sprint follow-up from format voice decided-by not-decided-by since source-prefix source-epic reason prd "
US=$'\037'
o(){ local n="O_${1//-/_}"; printf '%s' "${!n-}"; }
has(){ local n="O_${1//-/_}"; [[ -n "${!n+x}" ]]; }
# Print each value of a repeatable flag as a NUL-terminated record.
om(){
  local n="O_${1//-/_}" v rest
  [[ -n "${!n+x}" ]] || return 0
  v="${!n}"
  while :; do
    if [[ "$v" == *"$US"* ]]; then printf '%s\0' "${v%%"$US"*}"; v="${v#*"$US"}"; else printf '%s\0' "$v"; break; fi
  done
}
CMD="${1:-}"; [[ $# -gt 0 ]] && shift || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --*)
      k="${1#--}"; shift
      [[ "$k" =~ ^[a-z][a-z0-9-]*$ ]] || usage "bad flag --$k"
      if [[ "$BOOL_KEYS" == *" $k "* ]]; then printf -v "O_${k//-/_}" '%s' 1; continue; fi
      [[ "$MULTI_KEYS" == *" $k "* || "$KNOWN_KEYS" == *" $k "* ]] || usage "unknown flag --$k (see --help)"
      [[ $# -gt 0 ]] || usage "--$k needs a value"
      v="$1"; shift
      if [[ "$MULTI_KEYS" == *" $k "* ]]; then
        n="O_${k//-/_}"
        if [[ -n "${!n+x}" ]]; then printf -v "$n" '%s' "${!n}${US}${v}"; else printf -v "$n" '%s' "$v"; fi
      else
        printf -v "O_${k//-/_}" '%s' "$v"
      fi ;;
    *) usage "unexpected argument: $1" ;;
  esac
done
has quiet && QUIET=1

# ---- environment -------------------------------------------------------------
session_id(){ local s="${CLAUDE_SESSION_ID:-${CLAUDE_CODE_SESSION_ID:-}}"; s="$(printf '%s' "$s" | tr -cd 'A-Za-z0-9_.-')"; printf '%s' "${s:-unknown-session}"; }
now_utc(){ date -u +%Y-%m-%dT%H:%M:%SZ; }

abs_dir(){ (cd "$1" 2>/dev/null && pwd -P); }
# Main checkout root when PROJECT_ROOT is a linked worktree; empty otherwise.
MAIN_ROOT=""
IS_WORKTREE=0
detect_worktree(){
  command -v git >/dev/null 2>&1 || return 0
  local gd cd
  gd="$(cd "$PROJECT_ROOT" && git rev-parse --git-dir 2>/dev/null)" || return 0
  cd="$(cd "$PROJECT_ROOT" && git rev-parse --git-common-dir 2>/dev/null)" || return 0
  gd="$(cd "$PROJECT_ROOT" && abs_dir "$gd")"; cd="$(cd "$PROJECT_ROOT" && abs_dir "$cd")"
  if [[ -n "$gd" && -n "$cd" && "$gd" != "$cd" ]]; then
    IS_WORKTREE=1
    MAIN_ROOT="$(dirname "$cd")"
  fi
  return 0
}
detect_worktree

# Run-state directories: this checkout's .run, plus the main checkout's when this is a worktree.
run_dirs(){ printf '%s\n' "${PROJECT_ROOT}/.run"; [[ -n "$MAIN_ROOT" ]] && printf '%s\n' "${MAIN_ROOT}/.run"; return 0; }

ttl_hours(){
  local t="" cfg="${PROJECT_ROOT}/.loa.config.yaml"
  if [[ -f "$cfg" ]] && command -v yq >/dev/null 2>&1; then
    t="$(yq '.decisions.unattended_marker_ttl_hours // ""' "$cfg" 2>/dev/null || true)"
  fi
  [[ "$t" =~ ^[0-9]+$ && "$t" -gt 0 ]] || t=24
  printf '%s' "$t"
}

# fresh | stale | absent for one marker file.
marker_state(){
  local f="$1" sid ca ep now sess
  [[ -f "$f" ]] || { echo absent; return 0; }
  sid="$(jq -r '.session_id // empty' "$f" 2>/dev/null || true)"
  ca="$(jq -r '.created_at // empty' "$f" 2>/dev/null || true)"
  [[ -n "$ca" ]] || { echo stale; return 0; }
  ep="$(_date_to_epoch "$ca" 2>/dev/null || true)"
  [[ "$ep" =~ ^[0-9]+$ ]] || { echo stale; return 0; }
  now="$(date -u +%s)"
  if (( now - ep > $(ttl_hours) * 3600 )); then echo stale; return 0; fi
  sess="${CLAUDE_SESSION_ID:-${CLAUDE_CODE_SESSION_ID:-}}"
  if [[ -n "$sess" && -n "$sid" && "$sid" != "$sess" ]]; then echo stale; return 0; fi
  echo fresh
}

PRD_PATH=""
# Print one line per active unattended signal: "<kind> <detail>"; kind live|prd.
ctx_signals(){
  local d f st
  while IFS= read -r d; do
    [[ -n "$d" ]] || continue
    if [[ "$(marker_state "$d/unattended.json")" == "fresh" ]]; then echo "live unattended-marker:${d}/unattended.json"; fi
    for f in "$d/sprint-plan-state.json" "$d/state.json"; do
      [[ -f "$f" ]] || continue
      st="$(jq -r '.state // empty' "$f" 2>/dev/null || true)"
      if [[ "$st" == "RUNNING" ]]; then echo "live run-state:${f}"; fi
    done
  done < <(run_dirs)
  if [[ "${LOA_UNATTENDED:-}" == "1" ]]; then echo "live env:LOA_UNATTENDED=1"; fi
  if [[ "${LOA_FLATLINE_MODE:-}" == "autonomous" ]]; then echo "live env:LOA_FLATLINE_MODE=autonomous"; fi
  local prd="${PRD_PATH:-${G}/prd.md}"
  if [[ -f "$prd" ]] && grep -m1 -E '^\*\*Status:?\*\*:?' "$prd" 2>/dev/null | grep -qiE 'autonomous|unattended'; then
    echo "prd prd-status:${prd}"
  fi
  return 0
}
is_unattended(){ [[ -n "$(ctx_signals)" ]]; }
live_run_signal(){ ctx_signals | grep -q '^live ' ; }

ci_blocked(){
  if [[ -n "${CI:-}" && "${CI}" != "false" && "${CI}" != "0" ]]; then echo "CI"; return 0; fi
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then echo "GITHUB_ACTIONS"; return 0; fi
  if [[ "${LOA_HOOK_CONTEXT:-}" == "1" ]]; then echo "LOA_HOOK_CONTEXT"; return 0; fi
  return 1
}

preflight(){
  command -v jq >/dev/null 2>&1 || die "preflight: jq is required (install jq 1.6+); nothing written"
  command -v yq >/dev/null 2>&1 || die "preflight: Mike Farah yq v4 is required (https://github.com/mikefarah/yq, e.g. brew install yq); nothing written"
  local v; v="$(yq --version 2>&1 || true)"
  [[ "$v" == *mikefarah* && "$v" == *"version v4."* ]] || die "preflight: yq is not Mike Farah yq v4 (found: $(san1 "$v")); install https://github.com/mikefarah/yq v4; nothing written"
}

# ---- lock (flock -w when present, else a mkdir lock with a stale check) ------
LOCK_WAIT="${LOA_DEC_LOCK_WAIT:-10}"
[[ "$LOCK_WAIT" =~ ^[0-9]+$ && "$LOCK_WAIT" -ge 1 && "$LOCK_WAIT" -le 10 ]] || LOCK_WAIT=10
lock_path(){ # target -> lock file under .run, keyed by the target's absolute path
  local abs h
  abs="$(abs_dir "$(dirname "$1")")/$(basename "$1")"
  h="$(printf '%s' "$abs" | sha256_portable | cut -c1-12)"
  printf '%s' "${PROJECT_ROOT}/.run/.dec-write-${h}.lock"
}
acquire_lock(){ # target
  local lp; lp="$(lock_path "$1")"
  mkdir -p "${PROJECT_ROOT}/.run"
  if command -v flock >/dev/null 2>&1 && [[ "${LOA_DEC_NO_FLOCK:-0}" != "1" ]]; then
    exec 9>"$lp"
    flock -w "$LOCK_WAIT" 9 || die "lock busy: another writer holds ${lp} (waited ${LOCK_WAIT}s); retry"
    return 0
  fi
  local d="${lp}.d" tries=$(( LOCK_WAIT * 10 )) pid
  while ! mkdir "$d" 2>/dev/null; do
    pid="$(cat "$d/pid" 2>/dev/null || true)"
    # Stale: older than 60 s and its owner is gone.
    if [[ -n "$(find "$d" -maxdepth 0 -mmin +1 2>/dev/null)" ]] && { [[ -z "$pid" ]] || ! kill -0 "$pid" 2>/dev/null; }; then
      rm -f "$d/pid" 2>/dev/null; rmdir "$d" 2>/dev/null || true; continue
    fi
    tries=$(( tries - 1 ))
    (( tries > 0 )) || die "lock busy: another writer holds ${d} (waited ${LOCK_WAIT}s); retry"
    sleep 0.1
  done
  MKLOCK="$d"
  printf '%s\n' "$$" > "$d/pid"
}

# ---- target resolution -------------------------------------------------------
TARGET=""
TARGET_KIND=""   # fixture | live | pending
pending_path(){
  local n="" st
  n="$(san1 "$(o sprint)")"
  if [[ -z "$n" ]]; then
    for st in "${PROJECT_ROOT}/.run/sprint-plan-state.json" ${MAIN_ROOT:+"${MAIN_ROOT}/.run/sprint-plan-state.json"}; do
      [[ -f "$st" ]] || continue
      n="$(jq -r '(.sprints.current // "") as $c | ([.sprints.list[]? | select(.id == $c) | .global_id] | first) // $c // empty' "$st" 2>/dev/null || true)"
      [[ -n "$n" ]] && break
    done
  fi
  n="${n#sprint-}"
  if [[ ! "$n" =~ ^[A-Za-z0-9_.-]+$ ]]; then warn "no sprint number (pass --sprint N); writing the pending file under sprint-unknown"; n="unknown"; fi
  printf '%s' "${G}/a2a/sprint-${n}/decisions-pending.yaml"
}
# Canonical path of a file whose directory exists (pwd -P of the directory + basename); empty otherwise.
canon(){ local d; d="$(abs_dir "$(dirname "$1")")" || return 0; [[ -n "$d" ]] && printf '%s/%s' "$d" "$(basename "$1")"; return 0; }
# Kind of an explicit --file target, by its resolved path: live (this checkout's or the main checkout's
# ledger), pending (grimoires/loa/a2a/<dir>/decisions-pending.yaml under either root) or fixture.
# The CI/hook exemption belongs to fixtures only, so naming the live ledger by path never bypasses it.
file_kind(){
  local c root r; c="$(canon "$1")"
  [[ -n "$c" ]] || { echo fixture; return 0; }
  for root in "$PROJECT_ROOT" ${MAIN_ROOT:+"$MAIN_ROOT"}; do
    r="$(abs_dir "$root")"; [[ -n "$r" ]] || continue
    if [[ "$c" == "$(canon "${r}/grimoires/loa/decisions.yaml")" ]]; then echo live; return 0; fi
    case "$c" in "${r}/grimoires/loa/a2a/"*/decisions-pending.yaml)
      local mid="${c#"${r}/grimoires/loa/a2a/"}"; mid="${mid%/decisions-pending.yaml}"
      if [[ "$mid" != */* ]]; then echo pending; return 0; fi ;;
    esac
  done
  echo fixture
}
resolve_target(){ # mode: write|read
  if has file; then
    TARGET="$(o file)"; TARGET_KIND="$(file_kind "$TARGET")"
    [[ -f "$TARGET" ]] || die "target not found: ${TARGET}"
    if [[ "$1" == "write" && "$TARGET_KIND" != "fixture" ]]; then
      local why; if why="$(ci_blocked)"; then die "refused: ${why} is set; --file ${TARGET} is the ${TARGET_KIND} ledger, which is never written from CI or a hook"; fi
      if [[ "$TARGET_KIND" == "live" && $IS_WORKTREE -eq 1 ]]; then
        die "refused: --file ${TARGET} is a live ledger and this is a linked worktree; worktrees write the pending file (drop --file), the lead imports it"
      fi
    fi
    return 0
  fi
  if [[ "$1" == "write" ]] && { has pending || [[ $IS_WORKTREE -eq 1 ]]; }; then
    TARGET="$(pending_path)"; TARGET_KIND="pending"
  else
    TARGET="$LIVE"; TARGET_KIND="live"
  fi
  if [[ "$1" == "write" ]]; then
    local why; if why="$(ci_blocked)"; then die "refused: ${why} is set; the ledger is never written from CI or a hook (use --file <fixture> in tests)"; fi
    if [[ "$TARGET_KIND" == "pending" && ! -f "$TARGET" ]]; then
      mkdir -p "$(dirname "$TARGET")"
      cat > "$TARGET" <<'EOF_PEND'
# decisions-pending.yaml: provisional decision rows (PEND-<8 hex> ids) written outside the main checkout.
# The lead imports them in the main checkout: .claude/scripts/lib/dec-write-lib.sh import --from <this file>
schema_version: 1
decisions: []
EOF_PEND
    fi
    [[ -f "$TARGET" ]] || die "ledger not found: ${TARGET} (restore the tracked grimoires/loa/decisions.yaml)"
  fi
  return 0
}

# JSON view of a ledger file; dies unless schema_version 1 and .decisions a sequence.
read_ledger(){
  local j
  j="$(yq -o=json -I0 '.' "$1" 2>/dev/null)" || die "unparsable ledger: $1"
  printf '%s' "$j" | jq -e '(.schema_version == 1) and ((.decisions // null) | type == "array")' >/dev/null 2>&1 \
    || die "ledger $1 has an unknown schema_version or no decisions sequence; refusing to write"
  printf '%s' "$j"
}

# ---- refs, voices, artifacts ---------------------------------------------------
REF_RE='^(session:[A-Za-z0-9_.-]+#turn-[0-9]+|debrief:[^#[:space:]]+#[A-Za-z0-9_.-]+|transcript:[^#[:space:]]+#L[0-9]+|cli:[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}(:[0-9]{2})?(\.[0-9]+)?(Z|[+-][0-9]{2}:?[0-9]{2})|flatline:[^[:space:]]+|dissent:[^[:space:]]+)$'
OPREF_RE='^(session|debrief|transcript|cli):'
# Resolve an artifact path from a flatline:/dissent: ref; prints the absolute path or dies.
artifact_path(){ # voice path
  local voice="$1" p="$2" a
  [[ "$p" != *".."* ]] || die "artifact path may not contain '..': $p"
  if [[ "$p" == /* ]]; then a="$p"; else a="${PROJECT_ROOT}/${p}"; fi
  [[ -f "$a" ]] || die "--as ${voice}: artifact not found: $p"
  a="$(abs_dir "$(dirname "$a")")/$(basename "$a")"
  case "$a" in "${PROJECT_ROOT}/"*) ;; *) die "--as ${voice}: artifact must live inside the project: $p" ;; esac
  local rel="${a#"${PROJECT_ROOT}/"}"
  if [[ "$voice" == "flatline" ]]; then
    [[ "$rel" =~ ^\.flatline/runs/[^/]+\.json$ ]] || die "--as flatline: the artifact must be .flatline/runs/<run>.json (got $rel)"
    jq -e 'has("phase")' "$a" >/dev/null 2>&1 || die "--as flatline: $rel is not a Flatline run record (no .phase)"
  else
    [[ "$rel" =~ ^grimoires/loa/a2a/(.+/)?adversarial-[^/]*\.json$ ]] || die "--as dissent: the artifact must be grimoires/loa/a2a/**/adversarial-*.json (got $rel)"
    jq -e '.' "$a" >/dev/null 2>&1 || die "--as dissent: $rel is not valid JSON"
  fi
  printf '%s' "$a"
}

# Sets VOICE, REF, SHA from --as / --answer-ref and the context. $1 = allow_as (1 at creation).
VOICE="agent"; REF=""; SHA=""
derive_attribution(){
  local allow_as="$1" as ref
  as="$(san1 "$(o as)")"; ref="$(san1 "$(o answer-ref)")"
  VOICE="agent"; REF=""; SHA=""
  if is_unattended; then
    [[ -z "$ref" ]] || warn "unattended context: --answer-ref ignored (the row stays proposed with proposed_by agent until /decisions confirm)"
    [[ -z "$as" ]] || warn "unattended context: --as ${as} ignored"
    return 0
  fi
  if [[ -n "$as" ]]; then
    [[ "$allow_as" == "1" ]] || die "--as is set once, at creation (proposed_by is immutable)"
    [[ "$as" == "flatline" || "$as" == "dissent" ]] || usage "--as must be flatline or dissent"
    [[ "$ref" == "${as}:"* ]] || die "--as ${as} needs --answer-ref ${as}:<artifact path>"
  fi
  if [[ -n "$ref" ]]; then
    [[ "$ref" =~ $REF_RE ]] || die "--answer-ref does not match the ref grammar (session:<id>#turn-<n> | debrief:<path>#<anchor> | transcript:<path>#L<n> | cli:<iso-8601> | flatline:<path> | dissent:<path>): $ref"
    if [[ "$ref" == flatline:* || "$ref" == dissent:* ]]; then
      local rv="${ref%%:*}" a
      [[ "$as" == "$rv" ]] || die "a ${rv}: ref needs --as ${rv}"
      a="$(artifact_path "$rv" "${ref#*:}")"
      SHA="$(sha256_portable "$a" | cut -d' ' -f1)"
      VOICE="$rv"
    fi
    REF="$ref"
  fi
  return 0
}

# ---- row parts -------------------------------------------------------------------
alts_json(){
  local a="[]" item op rb
  while IFS= read -r -d '' item; do
    printf '%s' "$item" | jq -e 'type == "object" and ((.option // null) | type == "string") and ((.rejected_because // null) | type == "string") and ((keys - ["option","rejected_because"]) | length == 0)' >/dev/null 2>&1 \
      || die "--alternative-json must be {\"option\":\"...\",\"rejected_because\":\"...\"}: $(san1 "$item")"
    op="$(san1 "$(printf '%s' "$item" | jq -r '.option')")"; rb="$(san1 "$(printf '%s' "$item" | jq -r '.rejected_because')")"
    [[ -n "$op" && -n "$rb" ]] || die "--alternative-json needs a non-empty option and rejected_because"
    a="$(jq -cn --argjson a "$a" --arg o "$op" --arg r "$rb" '$a + [{option: $o, rejected_because: $r}]')"
  done < <(om alternative-json)
  printf '%s' "$a"
}
str_list_json(){ local a="[]" item s; while IFS= read -r -d '' item; do s="$(san1 "$item")"; [[ -z "$s" ]] || a="$(jq -cn --argjson a "$a" --arg s "$s" '$a + [$s]')"; done < <(om "$1"); printf '%s' "$a"; }
cons_json(){ local p n; p="$(str_list_json consequence-pos)"; n="$(str_list_json consequence-neg)"
  jq -cn --argjson p "$p" --argjson n "$n" 'if ($p|length) == 0 and ($n|length) == 0 then null else {positive: $p, negative: $n} end'; }

recorded_by(){
  local r; r="$(o recorded-by)"
  [[ -n "$r" ]] || usage "--recorded-by <skill-or-command> is required"
  [[ "$r" =~ ^[A-Za-z0-9_.-]+$ ]] || usage "--recorded-by must match [A-Za-z0-9_.-]+ (a skill or command name): $(san1 "$r")"
  printf '%s' "$r"
}
is_operator_call(){ [[ "$(o recorded-by)" == "$OPERATOR_CMD" ]]; }
head_commit(){ local c; c="$(cd "$PROJECT_ROOT" && git rev-parse --short=8 HEAD 2>/dev/null || true)"; if [[ "$c" =~ ^[0-9a-f]{7,40}$ ]]; then printf '%s' "$c"; else printf 'unknown'; fi; }
default_cycle(){
  local c st
  for st in "${PROJECT_ROOT}/.run/sprint-plan-state.json" "${PROJECT_ROOT}/.run/state.json" ${MAIN_ROOT:+"${MAIN_ROOT}/.run/sprint-plan-state.json"}; do
    [[ -f "$st" ]] || continue
    c="$(jq -r '.cycle_id // .cycle // empty' "$st" 2>/dev/null || true)"
    if [[ -n "$c" ]]; then printf '%s' "$c"; return 0; fi
  done
  for st in "${G}/ledger.json" ${MAIN_ROOT:+"${MAIN_ROOT}/grimoires/loa/ledger.json"}; do
    [[ -f "$st" ]] || continue
    c="$(jq -r '.active_cycle // empty' "$st" 2>/dev/null || true)"
    if [[ -n "$c" ]]; then printf '%s' "$c"; return 0; fi
  done
  return 0
}

next_dec_id(){ # ledger-json
  printf '%s' "$1" | jq -r '[.decisions[].id | strings | select(test("^DEC-[0-9]+$")) | ltrimstr("DEC-") | tonumber] | (max // 0) + 1 | tostring | (if length < 4 then ("0000"[0:(4 - length)] + .) else . end) | "DEC-" + .'
}
pend_id(){ printf 'PEND-%s' "$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"; }

# ---- temp / apply / verify -------------------------------------------------------
STYLE_ROW='(.decisions[] | select(.id == strenv(ROWID)) | ..) style="" | (.decisions[] | select(.id == strenv(ROWID)) | .. | select(tag == "!!str")) style="double" | (.decisions[] | select(.id == strenv(ROWID)) | .. | key) style=""'
begin_tmp(){ TMPF="$(mktemp "${TARGET}.XXXXXX")"; cp "$TARGET" "$TMPF"; }
append_row(){ # row-json
  local id; id="$(printf '%s' "$1" | jq -r '.id')"
  ROW="$1" ROWID="$id" yq -i ".decisions += [env(ROW)] | ${STYLE_ROW}" "$TMPF" || die "yq append failed; ledger untouched"
}
replace_row(){ # row-json
  local id; id="$(printf '%s' "$1" | jq -r '.id')"
  ROW="$1" ROWID="$id" yq -i "(.decisions[] | select(.id == strenv(ROWID))) = env(ROW) | ${STYLE_ROW}" "$TMPF" || die "yq update failed; ledger untouched"
}
# verify_and_swap OLD_JSON ADDED TOUCHED_IDS_JSON
verify_and_swap(){
  local old="$1" added="$2" touched="$3" errs
  # Whole-ledger JSON goes through files (--slurpfile): a large ledger overflows one argv string.
  SCRATCH="$(mktemp "${TMPDIR:-/tmp}/dec-verify.XXXXXX")"
  printf '%s' "$old" > "${SCRATCH}.old"
  yq -o=json -I0 '.' "$TMPF" > "${SCRATCH}.new" 2>/dev/null || die "ABORT: the candidate ledger does not parse; ledger untouched"
  errs="$(jq -rn --slurpfile O "${SCRATCH}.old" --slurpfile N "${SCRATCH}.new" --argjson added "$added" --argjson t "$touched" '
    $O[0] as $o | $N[0] as $n
    | ($o.decisions | map(.id)) as $oi | (($n.decisions // []) | map(.id)) as $ni
    | (($n.decisions // []) | map(select(type == "object" and (.id | type) == "string") | {key: .id, value: .}) | from_entries) as $nb
    | ($oi | map({key: ., value: true}) | from_entries) as $os | ($t | map({key: ., value: true}) | from_entries) as $ts
    | [ (if $n.schema_version != 1 then "unknown schema_version" else empty end),
        (if ($n.decisions | type) != "array" then "decisions is not a sequence" else empty end),
        ($oi - $ni | .[] | "would drop id \(.)"),
        ($ni | group_by(.) | map(select(length > 1) | .[0]) | .[] | "duplicate id \(.)"),
        (if ($ni | length) != (($o.decisions | length) + $added) then "row count \($ni | length) != \($o.decisions | length) + \($added)" else empty end),
        ($o.decisions[] as $r | select($ts[$r.id] | not) | select($nb[$r.id] != $r) | "row \($r.id) changed outside this operation"),
        ($n.decisions[] | .id as $x | select($os[$x] | not) | select($ts[$x] | not) | "unexpected new row \($x)")
      ] | .[]')" || die "ABORT: verification failed to run; ledger untouched"
  [[ -z "$errs" ]] || die "ABORT: ${errs//$'\n'/; }; ledger untouched"
  [[ -f "$VALIDATOR" ]] || die "ABORT: validator missing at ${VALIDATOR}; ledger untouched"
  local vout
  if ! vout="$(PROJECT_ROOT="$PROJECT_ROOT" bash "$VALIDATOR" --type decisions --file "$TMPF" --base-file "$TARGET" 2>&1)"; then
    die "ABORT: the candidate fails validate-artifact.sh --type decisions; ledger untouched:"$'\n'"$vout"
  fi
  chmod 0644 "$TMPF"
  mv -f "$TMPF" "$TARGET"; TMPF=""
}
row_by_id(){ printf '%s' "$1" | jq -c --arg id "$2" '[.decisions[] | select(.id == $id)] | first // empty'; }

# ---- ops -------------------------------------------------------------------------
# Build a new row JSON. Args: id status voice ref sha supersedes
build_row(){
  local id="$1" status="$2" voice="$3" ref="$4" sha="$5" sup="$6"
  local summary phase category source decision rationale alts cons rb cyc now ev
  summary="$(san1 "$(o summary)")"; phase="$(san1 "$(o phase)")"; category="$(san1 "$(o category)")"; source="$(san1 "$(o source)")"
  [[ -n "$summary" ]] || usage "--summary is required"
  # characters, not bytes (LC_ALL=C makes ${#x} a byte count): the validator's limit is 160 code points
  [[ "$(jq -rn --arg s "$summary" '$s | length')" -le 160 ]] || die "--summary is over 160 characters; one plain line"
  [[ "$phase" =~ ^(discovery|architecture|sprint-planning|implementation|review|charting|spike|operations)$ ]] || usage "--phase must be discovery|architecture|sprint-planning|implementation|review|charting|spike|operations"
  [[ "$category" =~ ^[a-z][a-z0-9-]*$ ]] || usage "--category must match [a-z][a-z0-9-]* (e.g. scope, technology, architecture)"
  [[ -n "$source" ]] || usage "--source is required (bead id, PR, NOTES anchor, spike path, with a line or anchor)"
  decision="$(san1 "$(o decision)")"; rationale="$(san1 "$(o rationale)")"; alts="$(alts_json)"; cons="$(cons_json)"
  if [[ "$status" == "proposed" ]]; then
    [[ -n "$decision" && -n "$rationale" && "$(printf '%s' "$alts" | jq 'length')" -ge 1 ]] \
      || die "a proposed row needs --decision, --rationale and at least one --alternative-json"
  fi
  rb="$(recorded_by)"; cyc="$(san1 "$(o cycle)")"; [[ -n "$cyc" ]] || cyc="$(default_cycle)"
  if [[ -z "$cyc" ]] && is_unattended; then warn "no cycle id (pass --cycle); the row's cycle is null"; fi
  now="$(now_utc)"; ev="$(san1 "$(o evidence)")"; [[ -n "$ev" ]] || ev="$source"
  jq -cn --arg id "$id" --arg now "$now" --arg phase "$phase" --arg category "$category" --arg summary "$summary" \
    --arg decision "$decision" --arg rationale "$rationale" --argjson alts "$alts" --argjson cons "$cons" \
    --arg voice "$voice" --arg ref "$ref" --arg sha "$sha" --arg rb "${rb}/$(session_id)" --arg by "${voice}:${rb}" \
    --arg commit "$(head_commit)" --arg source "$source" --arg cycle "$cyc" --arg sup "$sup" --arg status "$status" --arg ev "$ev" '
    def n: if . == "" then null else . end;
    {id: $id, created_at: $now, updated_at: $now, phase: $phase, category: $category, summary: $summary,
     decision: ($decision | n), rationale: ($rationale | n),
     alternatives_considered: (if ($alts | length) == 0 then null else $alts end), consequences: $cons,
     proposed_by: $voice, decided_by: null, decided_by_ref: ($ref | n), evidence_sha256: ($sha | n),
     recorded_by: $rb, commit: $commit, source: $source, cycle: ($cycle | n), supersedes: ($sup | n),
     supersede_proposed_by: null, status: $status,
     transitions: [{at: $now, from: null, to: $status, by: $by, evidence: $ev}],
     rejection_rationale: null, follow_up: null, prior_requests: []}'
}

alloc_id(){ # ledger-json
  if [[ "$TARGET_KIND" == "pending" ]]; then pend_id; else next_dec_id "$1"; fi
}

op_new(){
  preflight; resolve_target write
  local status; status="$(san1 "$(o status)")"
  [[ -z "$status" || "$status" == "open" || "$status" == "proposed" ]] || usage "--status must be open or proposed (a row reaches decided only through /decisions confirm)"
  derive_attribution 1
  if is_unattended; then [[ "$status" == "open" ]] || status="proposed"; else status="${status:-open}"; fi
  acquire_lock "$TARGET"
  local old id row; old="$(read_ledger "$TARGET")"
  id="$(alloc_id "$old")"
  row="$(build_row "$id" "$status" "$VOICE" "$REF" "$SHA" "")"
  begin_tmp; append_row "$row"
  verify_and_swap "$old" 1 "$(jq -cn --arg i "$id" '[$i]')"
  log "dec-write: appended ${id} (${status}) to ${TARGET#"${PROJECT_ROOT}/"}"
  echo "$id"
}

need_id(){ local id; id="$(san1 "$(o id)")"; [[ "$id" =~ ^(DEC-[0-9]{4,}|PEND-[0-9a-f]{8})$ ]] || usage "--id DEC-NNNN (or PEND-<8 hex>) required"; printf '%s' "$id"; }

op_decide(){
  preflight
  local id; id="$(need_id)"
  [[ -n "$(san1 "$(o evidence)")" ]] || die "decide: --evidence is required (what the decision rests on)"
  resolve_target write
  derive_attribution 0
  acquire_lock "$TARGET"
  local old r; old="$(read_ledger "$TARGET")"; r="$(row_by_id "$old" "$id")"
  [[ -n "$r" ]] || die "decide: unknown id ${id}"
  [[ "$(printf '%s' "$r" | jq -r '.status')" == "open" ]] || die "decide: ${id} is $(printf '%s' "$r" | jq -r '.status'), not open (illegal transition)"
  local decision rationale alts cons rb now
  decision="$(san1 "$(o decision)")"; rationale="$(san1 "$(o rationale)")"; alts="$(alts_json)"; cons="$(cons_json)"
  [[ -n "$decision" && -n "$rationale" && "$(printf '%s' "$alts" | jq 'length')" -ge 1 ]] || die "decide: --decision, --rationale and at least one --alternative-json are required"
  rb="$(recorded_by)"; now="$(now_utc)"
  r="$(printf '%s' "$r" | jq -c --arg d "$decision" --arg w "$rationale" --argjson a "$alts" --argjson c "$cons" --arg ref "$REF" \
      --arg now "$now" --arg by "$(printf '%s' "$r" | jq -r '.proposed_by'):${rb}" --arg ev "$(san1 "$(o evidence)")" '
      .decision = $d | .rationale = $w | .alternatives_considered = $a
      | .consequences = (if .consequences == null then $c else .consequences end)
      | .decided_by_ref = (if .decided_by_ref == null and $ref != "" then $ref else .decided_by_ref end)
      | .status = "proposed" | .updated_at = $now
      | .transitions += [{at: $now, from: "open", to: "proposed", by: $by, evidence: $ev}]')"
  begin_tmp; replace_row "$r"
  verify_and_swap "$old" 0 "$(jq -cn --arg i "$id" '[$i]')"
  log "dec-write: ${id} open -> proposed"
}

op_confirm(){
  preflight
  is_operator_call || die "confirm runs only from the operator-only /decisions command (--recorded-by ${OPERATOR_CMD})"
  if live_run_signal; then die "confirm refused: a live-run signal holds ($(ctx_signals | grep '^live ' | cut -d' ' -f2 | paste -sd, -)); confirm after the run, interactively"; fi
  local ev; ev="$(san1 "$(o evidence)")"; [[ -n "$ev" ]] || die "confirm: --evidence is required (e.g. cli:<iso-8601>)"
  resolve_target write
  [[ "$TARGET_KIND" != "pending" ]] || die "confirm runs on the live ledger in the main checkout, never on a pending file"
  derive_attribution 0
  acquire_lock "$TARGET"
  local old id cyc; old="$(read_ledger "$TARGET")"
  local -a ids=()
  while IFS= read -r -d '' id; do id="$(san1 "$id")"; [[ "$id" =~ ^DEC-[0-9]{4,}$ ]] || usage "confirm: bad --id $id"; ids+=("$id"); done < <(om id)
  cyc="$(san1 "$(o cycle)")"
  if [[ ${#ids[@]} -eq 0 ]]; then
    [[ -n "$cyc" ]] || usage "confirm needs --id DEC-NNNN ... or --cycle <cycle> [--all]"
    local matches; matches="$(printf '%s' "$old" | jq -r --arg c "$cyc" '.decisions[] | select(.status == "proposed" and .cycle == $c) | .id')"
    [[ -n "$matches" ]] || die "confirm: no proposed rows in cycle ${cyc}"
    if [[ "$(printf '%s\n' "$matches" | grep -c .)" -gt 1 ]] && ! has all; then
      echo "confirm --cycle ${cyc} matches these proposed rows:" >&2
      printf '%s' "$old" | jq -r --arg c "$cyc" '.decisions[] | select(.status == "proposed" and .cycle == $c) | "  \(.id) \(.summary)"' >&2
      die "confirm: more than one row matches; pass --all or explicit --id values"
    fi
    while IFS= read -r id; do [[ -z "$id" ]] || ids+=("$id"); done <<< "$matches"
  fi
  local touched="[]" r now sup so cur="$old"; now="$(now_utc)"
  begin_tmp
  for id in "${ids[@]}"; do
    r="$(row_by_id "$cur" "$id")"; [[ -n "$r" ]] || die "confirm: unknown id ${id}"
    [[ "$(printf '%s' "$r" | jq -r '.status')" == "proposed" ]] || die "confirm: ${id} is $(printf '%s' "$r" | jq -r '.status'), not proposed (illegal transition)"
    echo "confirming ${id}: $(printf '%s' "$r" | jq -r '.summary')" >&2
    r="$(printf '%s' "$r" | jq -c --arg ref "$REF" --arg now "$now" --arg by "operator:${OPERATOR_CMD}" --arg ev "$ev" --arg opre "$OPREF_RE" '
        .decided_by_ref = (if .decided_by_ref == null and $ref != "" then $ref else .decided_by_ref end)
        | .decided_by = (if ((.decided_by_ref // "") | test($opre)) then "operator" else .proposed_by end)
        | .status = "decided" | .updated_at = $now
        | .transitions += [{at: $now, from: "proposed", to: "decided", by: $by, evidence: $ev}]')"
    replace_row "$r"
    touched="$(jq -cn --argjson t "$touched" --arg i "$id" '$t + [$i]')"
    # An agent-proposed supersede: the old decided row moves to superseded when its replacement is confirmed.
    sup="$(printf '%s' "$r" | jq -r '.supersedes // empty')"
    if [[ -n "$sup" ]]; then
      so="$(row_by_id "$cur" "$sup")"
      if [[ -n "$so" ]] && [[ "$(printf '%s' "$so" | jq -r '.status + "|" + (.supersede_proposed_by // "")')" == "decided|${id}" ]]; then
        so="$(printf '%s' "$so" | jq -c --arg now "$now" --arg by "operator:${OPERATOR_CMD}" --arg ev "$ev" --arg n "$id" '
            .status = "superseded" | .updated_at = $now | .transitions += [{at: $now, from: "decided", to: "superseded", by: $by, evidence: ("superseded by " + $n + "; " + $ev)}]')"
        replace_row "$so"
        touched="$(jq -cn --argjson t "$touched" --arg i "$sup" '$t + [$i]')"
      fi
    fi
    cur="$(yq -o=json -I0 '.' "$TMPF")"
  done
  verify_and_swap "$old" 0 "$touched"
  log "dec-write: confirmed ${ids[*]}"
}

op_reject(){
  preflight
  local id; id="$(need_id)"
  local rat fu; rat="$(san1 "$(o rationale)")"; fu="$(san1 "$(o follow-up)")"
  [[ -n "$rat" ]] || die "reject: --rationale is required"
  [[ -n "$fu" ]] || die "reject: --follow-up is required (a bead id or NOTES anchor, so the correction propagates)"
  resolve_target write
  acquire_lock "$TARGET"
  local old r st rb by; old="$(read_ledger "$TARGET")"; r="$(row_by_id "$old" "$id")"
  [[ -n "$r" ]] || die "reject: unknown id ${id}"
  st="$(printf '%s' "$r" | jq -r '.status')"; rb="$(recorded_by)"
  case "$st" in
    open|proposed) if is_operator_call && ! is_unattended; then by="operator:${OPERATOR_CMD}"; else by="agent:${rb}"; fi ;;
    decided)
      is_operator_call || die "reject: ${id} is decided; only the operator rejects it through /decisions. Propose the reversal with: dec-write-lib.sh supersede --id ${id} ... (lands proposed)"
      if is_unattended; then die "reject: ${id} is decided and the context is unattended; the operator rejects it interactively"; fi
      by="operator:${OPERATOR_CMD}" ;;
    *) die "reject: ${id} is ${st} (illegal transition)" ;;
  esac
  local pr now; pr="$(str_list_json prior-request)"; now="$(now_utc)"
  r="$(printf '%s' "$r" | jq -c --arg rat "$rat" --arg fu "$fu" --argjson pr "$pr" --arg now "$now" --arg by "$by" --arg st "$st" '
      .rejection_rationale = $rat | .follow_up = $fu | .prior_requests = ((.prior_requests // []) + $pr)
      | .status = "rejected" | .updated_at = $now
      | .transitions += [{at: $now, from: $st, to: "rejected", by: $by, evidence: $rat}]')"
  begin_tmp; replace_row "$r"
  verify_and_swap "$old" 0 "$(jq -cn --arg i "$id" '[$i]')"
  log "dec-write: ${id} ${st} -> rejected"
}

op_supersede(){
  preflight
  local oid; oid="$(need_id)"
  resolve_target write
  [[ "$TARGET_KIND" != "pending" ]] || die "supersede runs in the main checkout against the live ledger (the old row lives there)"
  derive_attribution 1
  acquire_lock "$TARGET"
  local old r st; old="$(read_ledger "$TARGET")"; r="$(row_by_id "$old" "$oid")"
  [[ -n "$r" ]] || die "supersede: unknown id ${oid}"
  st="$(printf '%s' "$r" | jq -r '.status')"
  [[ "$st" == "decided" ]] || die "supersede: ${oid} is ${st}; only a decided row is superseded (reject an open or proposed row instead)"
  if ! { is_operator_call && ! is_unattended; }; then
    [[ -z "$(printf '%s' "$r" | jq -r '.supersede_proposed_by // empty')" ]] || die "supersede: a replacement is already proposed for ${oid}: $(printf '%s' "$r" | jq -r '.supersede_proposed_by')"
  fi
  local nid row now; nid="$(next_dec_id "$old")"; now="$(now_utc)"
  row="$(build_row "$nid" "proposed" "$VOICE" "$REF" "$SHA" "$oid")"
  begin_tmp; append_row "$row"
  if is_operator_call && ! is_unattended; then
    r="$(printf '%s' "$r" | jq -c --arg now "$now" --arg by "operator:${OPERATOR_CMD}" --arg n "$nid" '
        .status = "superseded" | .updated_at = $now | .transitions += [{at: $now, from: "decided", to: "superseded", by: $by, evidence: ("superseded by " + $n)}]')"
  else
    r="$(printf '%s' "$r" | jq -c --arg now "$now" --arg n "$nid" '.supersede_proposed_by = $n | .updated_at = $now')"
  fi
  replace_row "$r"
  verify_and_swap "$old" 1 "$(jq -cn --arg a "$oid" --arg b "$nid" '[$a, $b]')"
  log "dec-write: ${nid} proposed to supersede ${oid}"
  echo "$nid"
}

op_import(){
  preflight
  local from; from="$(o from)"; [[ -n "$from" ]] || usage "import --from <pending file> required"
  [[ -f "$from" ]] || die "import: pending file not found: $from"
  if has file; then resolve_target write; else
    [[ $IS_WORKTREE -eq 0 ]] || die "import runs in the main checkout (this is a linked worktree)"
    local why; if why="$(ci_blocked)"; then die "refused: ${why} is set"; fi
    TARGET="$LIVE"; TARGET_KIND="live"; [[ -f "$TARGET" ]] || die "ledger not found: $TARGET"
  fi
  # --rewrite targets are checked before anything is written: an existing regular file (not a symlink)
  # whose canonical path lies under PROJECT_ROOT, named without '..'.
  local rw rwc proot; proot="$(abs_dir "$PROJECT_ROOT")"
  while IFS= read -r -d '' rw; do
    [[ "$rw" != *".."* ]] || die "import: --rewrite path may not contain '..': $rw"
    [[ -f "$rw" && ! -L "$rw" ]] || die "import: --rewrite target is not an existing regular file: $rw"
    rwc="$(canon "$rw")"
    case "$rwc" in "${proot}/"*) ;; *) die "import: --rewrite target is outside the project (${proot}): $rw" ;; esac
  done < <(om rewrite)
  local pv; pv="$(PROJECT_ROOT="$PROJECT_ROOT" bash "$VALIDATOR" --type decisions --file "$from" 2>&1)" || die "import: the pending file fails validation:"$'\n'"$pv"
  acquire_lock "$TARGET"
  local old pend n; old="$(read_ledger "$TARGET")"; pend="$(read_ledger "$from")"
  n="$(printf '%s' "$pend" | jq '.decisions | length')"
  [[ "$n" -gt 0 ]] || die "import: no rows in $from"
  # Allocate ids in file order, then rewrite every PEND reference inside the imported rows.
  local map="{}" pid i next cur="$old"
  for (( i = 0; i < n; i++ )); do
    pid="$(printf '%s' "$pend" | jq -r --argjson i "$i" '.decisions[$i].id')"
    [[ "$pid" =~ ^PEND-[0-9a-f]{8}$ ]] || die "import: row $i has id $pid, not PEND-<8 hex>"
    next="$(next_dec_id "$cur")"
    map="$(jq -cn --argjson m "$map" --arg p "$pid" --arg d "$next" '$m + {($p): $d}')"
    cur="$(printf '%s' "$cur" | jq -c --arg d "$next" '.decisions += [{id: $d}]')"
  done
  begin_tmp
  local rows touched r; rows="$(printf '%s' "$pend" | jq -c --argjson m "$map" '
      def rw: reduce ($m | to_entries[]) as $e (.; gsub($e.key; $e.value));
      .decisions[] | walk(if type == "string" then rw else . end)')"
  touched="$(jq -cn --argjson m "$map" '[$m[]]')"
  while IFS= read -r r; do [[ -z "$r" ]] || append_row "$r"; done <<< "$rows"
  verify_and_swap "$old" "$n" "$touched"
  local p tmp2
  while IFS= read -r -d '' p; do
    [[ -f "$p" ]] || { warn "import: --rewrite target not found: $p"; continue; }
    tmp2="$(mktemp "${p}.XXXXXX")"
    printf '%s' "$map" | jq -r 'to_entries[] | "\(.key)\t\(.value)"' | awk -F'\t' 'NR == FNR { m[$1] = $2; next } { for (k in m) gsub(k, m[k]); print }' - "$p" > "$tmp2"
    chmod 0644 "$tmp2"; mv -f "$tmp2" "$p"
  done < <(om rewrite)
  rm -f -- "$from"
  printf '%s' "$map" | jq -r 'to_entries[] | "\(.key) \(.value)"'
  log "dec-write: imported ${n} row(s) from ${from}; pending file removed. A bead whose external_ref holds a PEND id: br update <bead> --external-ref <DEC id> (beads stay with the lead)"
}

op_list(){
  command -v jq >/dev/null 2>&1 || die "list: jq is required"
  command -v yq >/dev/null 2>&1 || die "list: Mike Farah yq v4 is required"
  resolve_target read
  local fmt; fmt="$(o format)"; fmt="${fmt:-tsv}"
  [[ "$fmt" =~ ^(tsv|md|json)$ ]] || usage "--format must be tsv, md or json"
  local j
  if [[ ! -f "$TARGET" ]]; then j='{"schema_version":1,"decisions":[]}'; else
    j="$(yq -o=json -I0 '.' "$TARGET" 2>/dev/null)" || die "list: unparsable ledger ${TARGET}"
    printf '%s' "$j" | jq -e '.schema_version == 1' >/dev/null 2>&1 || warn "list: unknown schema_version in ${TARGET}"
    printf '%s' "$j" | jq -e '(.decisions // []) | type == "array"' >/dev/null 2>&1 || die "list: no decisions sequence in ${TARGET}"
  fi
  local voice; voice="$(o voice)"; [[ -n "$voice" ]] || voice="$(o decided-by)"
  local ids; ids="$(om id | tr '\0' ',')"
  printf '%s' "$j" | jq -r --arg fmt "$fmt" --arg st "$(o status)" --arg vo "$voice" --arg nv "$(o not-decided-by)" \
    --arg cy "$(o cycle)" --arg since "$(o since)" --arg sp "$(o source-prefix)" --arg se "$(o source-epic)" --arg ids "$ids" '
    def csv: if . == "" then [] else split(",") | map(select(length > 0)) end;
    def cl: tostring | gsub("[[:cntrl:]]"; " ");
    def mc: cl | gsub("\\|"; "\\|");
    ($st | csv) as $S | ($vo | csv) as $V | ($nv | csv) as $NV | ($ids | csv) as $I
    | [ (.decisions // [])[]
        | (.decided_by // .proposed_by // "") as $voice | (.status // "") as $status | (.id // "") as $id
        | select(($S | length) == 0 or ($S | index($status)))
        | select(($V | length) == 0 or ($V | index($voice)))
        | select(($NV | length) == 0 or (($NV | index($voice)) | not))
        | select($cy == "" or .cycle == $cy)
        | select($since == "" or ((.created_at // "") >= $since))
        | select($sp == "" or ((.source // "") | startswith($sp)))
        | select($se == "" or ((.source // "") | startswith("map:" + $se + "/")))
        | select(($I | length) == 0 or ($I | index($id)))
        | . + {voice: $voice} ] as $rows
    | if $fmt == "json" then ($rows | tojson)
      elif $fmt == "tsv" then ($rows[] | [.id, .status, .voice, (.summary // ""), (.source // "")] | map(cl) | join("\t"))
      else
        if ($rows | length) == 0 then "_None: every decision in this run was the operator'"'"'s._"
        else ("| Decision | Voice | Status | Why | Source |", "|---|---|---|---|---|",
              ($rows[] | "| \((.summary // "") | mc) (\(.id)) | \(.voice | mc) | \(.status | mc) | \((.rationale // "") | mc) | \((.source // "") | mc) |"),
              "Confirm with /decisions confirm.")
        end
      end'
}

op_context(){
  PRD_PATH="$(o prd)"
  if has set-unattended; then
    local reason; reason="$(san1 "$(o reason)")"; [[ -n "$reason" ]] || usage "context --set-unattended needs --reason"
    command -v jq >/dev/null 2>&1 || die "context: jq is required"
    mkdir -p "${PROJECT_ROOT}/.run"
    local m="${PROJECT_ROOT}/.run/unattended.json" t
    t="$(mktemp "${m}.XXXXXX")"
    jq -n --arg r "$reason" --arg s "$(session_id)" --arg c "$(now_utc)" '{reason: $r, session_id: $s, created_at: $c}' > "$t"
    mv -f "$t" "$m"
    log "dec-write: unattended marker written (${m#"${PROJECT_ROOT}/"}); it expires after $(ttl_hours) h or when the session changes"
    echo unattended; return 0
  fi
  if has clear; then
    is_operator_call || die "context --clear runs only from the operator-only /decisions command (--recorded-by ${OPERATOR_CMD})"
    local mk="${PROJECT_ROOT}/.run/unattended.json"
    rm -f -- "$mk"
    log "dec-write: unattended marker cleared"
  fi
  local sig; sig="$(ctx_signals)"
  if [[ -n "$sig" ]]; then echo unattended; else echo interactive; fi
  if has why; then
    if [[ -n "$sig" ]]; then printf '%s\n' "$sig" | sed 's/^/signal: /'; else echo "signal: none"; fi
    local d ms; while IFS= read -r d; do ms="$(marker_state "$d/unattended.json")"; if [[ "$ms" == "stale" ]]; then echo "note: stale marker ignored: $d/unattended.json"; fi; done < <(run_dirs)
  fi
  return 0
}

case "$CMD" in
  new) op_new ;;
  decide) op_decide ;;
  confirm) op_confirm ;;
  reject) op_reject ;;
  supersede) op_supersede ;;
  import) op_import ;;
  list) op_list ;;
  context) op_context ;;
  -h|--help|help|"") sed -n '2,45p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; if [[ -z "$CMD" ]]; then exit 2; fi; exit 0 ;;
  *) usage "unknown command: $CMD (new|decide|confirm|reject|supersede|import|list|context)" ;;
esac
