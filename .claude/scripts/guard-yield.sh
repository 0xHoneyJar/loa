#!/usr/bin/env bash
# =============================================================================
# guard-yield.sh — the guard register and its 30-day host yield (cycle-129 FR-1)
# =============================================================================
# Enumerates every guard Loa ships and joins it with its origin and its yield:
#   hooks       every command registered in .claude/settings.json, parsed against
#               the canonical schema "$(git rev-parse --show-toplevel)"/.claude/<path> [args]
#               (or the same wrapped in hook-guard.sh); one row per unique script
#   fences      the `# @guard fence:<id>` markers in block-destructive-bash.sh,
#               cross-checked both ways against its emit_block call sites and
#               its literal `pattern_id: "<id>"` audit constants
#   validators  the `# @guard validator:<id>` markers in validate-artifact.sh
#   gates       the fixed list in the origin map (each row's `script` must exist)
#   policies    the floor policies in the origin map
# Origins, class, status, knob and floor come from .claude/data/guard-origins.yaml;
# the floor set must equal .claude/data/floor.yaml floor_guards.
#
# Outputs:
#   grimoires/loa/guards.md        tracked, STRUCTURAL ONLY (a pure function of the
#                                  repository; no timestamp, no yield) — --check gates it
#   .run/guard-yield.md, .json     untracked host yield: blocks_30d, likely_fp_30d,
#                                  telemetry_30d, last_real_catch per guard
#   hooks-reference.md table       with --hooks-table, the rows between
#                                  <!-- guard-register:begin --> and <!-- guard-register:end -->
#
# Yield (SDD D-1.3): rows of .run/audit.jsonl and its rotated segments
# .run/audit.jsonl.* with action == "block", plus implement-gate rows (telemetry
# when action is telemetry or ask), with ts inside the window. Replays are
# excluded and counted: replay == true (LOA_AUDIT_REPLAY=1 at the source), or,
# for rows that predate the flag, a cwd under ${TMPDIR:-/tmp}/ or containing
# /bats-run-, /bats., /evals/results/ or /sandbox/, or a UTC minute holding
# BURST_ROWS (10) or more block rows (a suite replaying fixtures into the live
# log from inside the repository; no interactive session blocks ten commands in
# one minute). A block is a likely false
# positive (a heuristic) when its command holds a heredoc (`<<`; or, when
# .claude/scripts/lib/heredoc-classifier.sh defines heredoc_nonexec, a heredoc
# that function calls non-executing), when its cwd lies outside the repository
# (this checkout and its main worktree), or when its pattern id is a prose class
# (SP-1, FR-MERGE-2, FR-2-AMBIGUOUS) with no destructive verb at statement start.
# A real catch is a block that is not a likely false positive.
#
# Privacy: no command text, cwd, hostname, user or model name is written to any
# output; ids match ^[A-Za-z0-9._/:-]+$; origin text comes from the tracked map.
#
# Usage:
#   guard-yield.sh [--window-days 30] [--audit-log PATH] [--origins PATH]
#                  [--floor PATH] [--out grimoires/loa/guards.md] [--yield-dir .run]
#                  [--hooks-table] [--check] [--json] [--root DIR]
#                  [--settings PATH] [--fence PATH] [--validator PATH]
#                  [--hooks-ref PATH] [--now YYYY-MM-DD|YYYY-MM-DDTHH:MM:SSZ|EPOCH]
#
# Exit codes:
#   0  written, or in sync (--check)
#   1  drift (--check): guards.md or the hooks table differ from what would be written
#   2  usage error
#   3  unreadable or unparseable input (a missing audit log is a WARN and an empty yield)
#   5  a guard without an origin row, a row that resolves to nothing, an invalid row,
#      a floor mismatch, or a hook command outside the canonical schema
#
# Tested by tests/unit/guard-yield.bats and tests/unit/guard-origins.bats.
# =============================================================================
set -euo pipefail
export LC_ALL=C

SCRIPT_NAME="guard-yield.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

usage() {
    sed -n '/^# Usage:/,/^# Tested/p' "${BASH_SOURCE[0]}" | sed -e 's/^# \{0,1\}//' -e '/^Tested/d'
}
die() { local code="$1"; shift; echo "$SCRIPT_NAME: $*" >&2; exit "$code"; }
warn() { echo "$SCRIPT_NAME: WARN: $*" >&2; }

ROOT="" WINDOW_DAYS=30 AUDIT_LOG="" ORIGINS="" FLOOR="" OUT="" YIELD_DIR="" HOOKS_REF=""
SETTINGS="" FENCE="" VALIDATOR="" NOW=""
DO_HOOKS_TABLE=0 DO_CHECK=0 DO_JSON=0

need_arg() { [[ $# -ge 2 && -n "$2" ]] || die 2 "$1 needs a value (see --help)"; }
while [[ $# -gt 0 ]]; do
    case "$1" in
        --window-days) need_arg "$@"; WINDOW_DAYS="$2"; shift 2 ;;
        --audit-log)   need_arg "$@"; AUDIT_LOG="$2"; shift 2 ;;
        --origins)     need_arg "$@"; ORIGINS="$2"; shift 2 ;;
        --floor)       need_arg "$@"; FLOOR="$2"; shift 2 ;;
        --out)         need_arg "$@"; OUT="$2"; shift 2 ;;
        --yield-dir)   need_arg "$@"; YIELD_DIR="$2"; shift 2 ;;
        --root)        need_arg "$@"; ROOT="$2"; shift 2 ;;
        --settings)    need_arg "$@"; SETTINGS="$2"; shift 2 ;;
        --fence)       need_arg "$@"; FENCE="$2"; shift 2 ;;
        --validator)   need_arg "$@"; VALIDATOR="$2"; shift 2 ;;
        --hooks-ref)   need_arg "$@"; HOOKS_REF="$2"; shift 2 ;;
        --now)         need_arg "$@"; NOW="$2"; shift 2 ;;
        --hooks-table) DO_HOOKS_TABLE=1; shift ;;
        --check)       DO_CHECK=1; shift ;;
        --json)        DO_JSON=1; shift ;;
        -h|--help)     usage; exit 0 ;;
        *) die 2 "unknown argument '$1' (see --help)" ;;
    esac
done

[[ "$WINDOW_DAYS" =~ ^[0-9]+$ && "$WINDOW_DAYS" -ge 1 && "$WINDOW_DAYS" -le 3650 ]] \
    || die 2 "--window-days must be an integer from 1 to 3650 (got '$WINDOW_DAYS')"

command -v jq >/dev/null 2>&1 || die 3 "jq is required"
command -v yq >/dev/null 2>&1 || die 3 "yq v4 (mikefarah) is required"
case "$(yq --version 2>&1 || true)" in
    *mikefarah*"version v4."*) ;;
    *) die 3 "yq v4 (mikefarah) is required; found: $(yq --version 2>&1 | head -1)" ;;
esac

if [[ -z "$ROOT" ]]; then ROOT="$SCRIPT_DIR/../.."; fi
[[ -d "$ROOT" ]] || die 3 "--root '$ROOT' is not a directory"
ROOT="$(cd "$ROOT" && pwd -P)"

: "${ORIGINS:=$ROOT/.claude/data/guard-origins.yaml}"
: "${FLOOR:=$ROOT/.claude/data/floor.yaml}"
: "${OUT:=$ROOT/grimoires/loa/guards.md}"
: "${YIELD_DIR:=$ROOT/.run}"
: "${SETTINGS:=$ROOT/.claude/settings.json}"
: "${FENCE:=$ROOT/.claude/hooks/safety/block-destructive-bash.sh}"
: "${VALIDATOR:=$ROOT/.claude/scripts/validate-artifact.sh}"
: "${HOOKS_REF:=$ROOT/.claude/loa/reference/hooks-reference.md}"
: "${AUDIT_LOG:=$ROOT/.run/audit.jsonl}"
HEREDOC_LIB="$ROOT/.claude/scripts/lib/heredoc-classifier.sh"
BURST_ROWS=10
REGEN_HINT="regenerate: .claude/scripts/guard-yield.sh --hooks-table"

# The time base: --now, else the clock. Day granularity is all any output shows.
if [[ -z "$NOW" ]]; then
    NOW_EPOCH="$(date -u +%s)"
elif [[ "$NOW" =~ ^[0-9]+$ ]]; then
    NOW_EPOCH="$NOW"
elif [[ "$NOW" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    NOW_EPOCH="$(jq -rn --arg d "${NOW}T00:00:00Z" '$d | fromdateiso8601')" || die 2 "--now '$NOW' is not a date"
elif [[ "$NOW" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
    NOW_EPOCH="$(jq -rn --arg d "$NOW" '$d | fromdateiso8601')" || die 2 "--now '$NOW' is not a timestamp"
else
    die 2 "--now takes YYYY-MM-DD, YYYY-MM-DDTHH:MM:SSZ or epoch seconds (got '$NOW')"
fi

TMPWORK="$(mktemp -d "${TMPDIR:-/tmp}/guard-yield.XXXXXX")"
cleanup() { rm -rf -- "$TMPWORK"; }
trap cleanup EXIT

# ----------------------------------------------------------------------------- inputs
for f in "$ORIGINS" "$FLOOR" "$SETTINGS" "$FENCE" "$VALIDATOR"; do
    [[ -f "$f" && -r "$f" ]] || die 3 "input not readable: $f"
done
MAP_JSON="$(yq -o=json -I0 '.' "$ORIGINS" 2>/dev/null)" || die 3 "origin map does not parse as YAML: $ORIGINS"
[[ -n "$MAP_JSON" && "$MAP_JSON" != "null" ]] || die 3 "origin map is empty: $ORIGINS"
FLOOR_JSON="$(yq -o=json -I0 '.' "$FLOOR" 2>/dev/null)" || die 3 "floor file does not parse as YAML: $FLOOR"
jq -e 'type == "object"' "$SETTINGS" >/dev/null 2>&1 || die 3 "settings file does not parse as a JSON object: $SETTINGS"

ERRORS="$TMPWORK/errors"
: > "$ERRORS"

# ----------------------------------------------------------------------------- map schema
jq -r '
  def idok: type == "string" and test("^[A-Za-z0-9._/:-]+$");
  def nonempty: type == "string" and length > 0;
  (if .schema_version != 1 then "origin map: schema_version must be 1" else empty end),
  (if (.guards | type) != "array" then "origin map: guards must be a list" else
    ((.guards | map(.id) | group_by(.) | map(select(length > 1) | .[0]))[] | "origin map: duplicate id \(tostring)"),
    (.guards[] | . as $r | ($r.id | tostring) as $id |
      (if ($r.id | idok | not) then "origin map: row id \($id) does not match ^[A-Za-z0-9._/:-]+$" else empty end),
      (if (($r.kind // "") | IN("hook","fence","validator","gate","policy") | not) then "\($id): kind must be hook|fence|validator|gate|policy" else empty end),
      (if ($id | startswith(($r.kind // "?") + ":") | not) then "\($id): the id prefix must equal its kind" else empty end),
      (if (($r.class // "") | IN("harness","script","prose") | not) then "\($id): class must be harness|script|prose" else empty end),
      (if (($r.status // "") | IN("active","dormant","telemetry") | not) then "\($id): status must be active|dormant|telemetry" else empty end),
      (if ($r.origin.ref | nonempty | not) then "guard \($id) has no origin (origin.ref is empty)" else empty end),
      (if (($r.origin.kind // "") | IN("kf","issue","finding","cycle","design") | not) then "\($id): origin.kind must be kf|issue|finding|cycle|design" else empty end),
      (if ($r.knob | nonempty | not) then "\($id): knob must be a config key, an env var or none" else empty end),
      (if ($r.floor | type) != "boolean" then "\($id): floor must be true or false" else empty end),
      (if (($r.registrations // []) | type != "array" or any(.[]; type != "string")) then "\($id): registrations must be a list of strings" else empty end),
      (if $r.status == "dormant" and (($r.knob // "") | test("^[A-Z][A-Z0-9_]*$") | not) then "\($id): a dormant row names the arming env var in knob" else empty end),
      (if ($r.kind == "gate" or $r.kind == "policy") and ($r.script | nonempty | not) then "\($id): gate and policy rows name their script" else empty end),
      (if ($r.note // "" | type) != "string" then "\($id): note must be a string" else empty end)
    )
  end)
' <<<"$MAP_JSON" >> "$ERRORS" || die 3 "origin map could not be checked: $ORIGINS"
if [[ -s "$ERRORS" ]]; then
    sed "s/^/$SCRIPT_NAME: /" "$ERRORS" >&2
    exit 5
fi

# ----------------------------------------------------------------------------- hooks
# jq parses each registered command against the canonical schema; bash resolves
# symlinks once and checks the script exists. US (0x1f) separates fields so an
# empty matcher survives `read`.
US=$'\x1f'
HOOK_LINES="$TMPWORK/hooks.lines"
jq -r '
  def pfx: "\"\\$\\(git rev-parse --show-toplevel\\)\"/\\.claude/";
  def path_re: "(?<p>[A-Za-z0-9._/-]+)";
  def args_re: "(?<a>( [A-Za-z0-9._=-]+)*)";
  def badpath: split("/") | any(.[]; . == "" or . == "." or . == "..");
  (.hooks // {}) | to_entries[] | .key as $e | (.value // [])[] | (.matcher // "") as $m | (.hooks // [])[] |
  (.command // "") as $c |
  ( ([$c | capture("^" + pfx + "hooks/hook-guard\\.sh " + pfx + path_re + args_re + "$")?] | .[0]) as $w
  | if $w != null then
      (if ($w.p | badpath) then ["bad", $c] else ["ok", $e, $m, $w.p, "1"] end)
    else
      (([$c | capture("^" + pfx + path_re + args_re + "$")?] | .[0]) as $d
       | if $d != null and ($d.p != "hooks/hook-guard.sh") and ($d.p | badpath | not) then ["ok", $e, $m, $d.p, "0"]
         else ["bad", $c] end)
    end )
  | if any(.[]; explode | any(.[]; . < 32 or . == 127)) then ["bad", "(a command with control characters)"] else . end
  | join("\u001f")
' "$SETTINGS" > "$HOOK_LINES" || die 3 "settings hooks could not be enumerated: $SETTINGS"

HOOK_ROWS="$TMPWORK/hooks.jsonl"
: > "$HOOK_ROWS"
while IFS="$US" read -r tag ev mt rel wrapped; do
    [[ -n "$tag" ]] || continue
    if [[ "$tag" != "ok" ]]; then
        echo "hook command outside the canonical schema \"\$(git rev-parse --show-toplevel)\"/.claude/<path> [args] (or wrapped in hook-guard.sh): $ev" >> "$ERRORS"
        continue
    fi
    abs="$ROOT/.claude/$rel"
    if [[ ! -e "$abs" ]]; then
        echo "hook script .claude/$rel registered for $ev does not exist" >> "$ERRORS"
        continue
    fi
    # Containment on the physical path: every component resolved (pwd -P on the
    # parent, readlink on the leaf), so an intermediate symlinked directory under
    # .claude/ cannot point the register at a file outside it (review r1 DISS-C-002).
    tdir="$(cd "$(dirname "$abs")" 2>/dev/null && pwd -P)" || tdir=""
    canon="$tdir/$(basename "$abs")"
    if [[ -L "$canon" ]]; then
        tgt="$(readlink "$canon")"
        case "$tgt" in /*) ;; *) tgt="$tdir/$tgt" ;; esac
        tdir="$(cd "$(dirname "$tgt")" 2>/dev/null && pwd -P)" || tdir=""
        canon="$tdir/$(basename "$tgt")"
    fi
    case "$canon" in
        "$ROOT/.claude/"*) rel="${canon#"$ROOT/.claude/"}"; abs="$canon" ;;
        *) echo "hook script .claude/$rel resolves outside .claude/ (registered for $ev): $canon" >> "$ERRORS"; continue ;;
    esac
    if [[ ! -f "$abs" ]]; then
        echo "hook script .claude/$rel registered for $ev does not exist" >> "$ERRORS"
        continue
    fi
    case "$rel" in hooks/*) id="hook:${rel#hooks/}" ;; *) id="hook:$rel" ;; esac
    if [[ -n "$mt" ]]; then reg="$ev:$mt"; else reg="$ev"; fi
    jq -cn --arg id "$id" --arg rel "$rel" --arg ev "$ev" --arg mt "$mt" --arg reg "$reg" --arg w "$wrapped" \
        '{id: $id, rel: $rel, event: $ev, matcher: $mt, registration: $reg, wrapped: ($w == "1")}' >> "$HOOK_ROWS"
done < "$HOOK_LINES"
HOOKS_JSON="$(jq -cs '.' "$HOOK_ROWS")"

# ----------------------------------------------------------------------------- fence markers
# Sites: `emit_block "<ID>"` calls and literal `pattern_id: "<ID>"` audit constants on
# non-comment lines. Each site needs a marker with its id within the 8 lines above;
# each marker needs a site with its id within the 8 lines below.
FENCE_IDS="$TMPWORK/fence.ids"
awk -v errs="$ERRORS" '
  function note(s) { print s >> errs }
  /^[[:space:]]*#[[:space:]]*@guard[[:space:]]+fence:/ {
    s = $0; sub(/^[[:space:]]*#[[:space:]]*@guard[[:space:]]+fence:/, "", s); sub(/[[:space:]]+$/, "", s)
    if (s !~ /^[A-Za-z0-9._-]+$/) { note("fence marker at line " NR " has an invalid id"); next }
    nm++; mline[nm] = NR; mid[nm] = s; next
  }
  /^[[:space:]]*#/ { next }
  {
    line = $0
    if (line ~ /emit_block[[:space:]]*\(\)/) next
    while (match(line, /emit_block[[:space:]]+[^[:space:]]+/)) {
      tok = substr(line, RSTART, RLENGTH); line = substr(line, RSTART + RLENGTH)
      sub(/^emit_block[[:space:]]+/, "", tok)
      if (tok ~ /^"[A-Za-z0-9._-]+"$/) { gsub(/"/, "", tok); ns++; sline[ns] = NR; sid[ns] = tok }
      else note("fence emit_block call at line " NR " has a non-literal pattern id; give it a literal id and a # @guard fence:<id> marker")
    }
    line = $0
    while (match(line, /pattern_id(: |=)"[A-Za-z0-9._-]+"/)) {
      tok = substr(line, RSTART, RLENGTH); line = substr(line, RSTART + RLENGTH)
      sub(/^pattern_id(: |=)"/, "", tok); sub(/"$/, "", tok)
      ns++; sline[ns] = NR; sid[ns] = tok
    }
  }
  END {
    for (i = 1; i <= ns; i++) {
      ok = 0
      for (j = 1; j <= nm; j++) if (mid[j] == sid[i] && mline[j] < sline[i] && sline[i] - mline[j] <= 8) ok = 1
      if (!ok) note("fence site " sid[i] " at line " sline[i] " has no # @guard fence:" sid[i] " marker within the 8 lines above it")
    }
    for (j = 1; j <= nm; j++) {
      ok = 0
      for (i = 1; i <= ns; i++) if (mid[j] == sid[i] && mline[j] < sline[i] && sline[i] - mline[j] <= 8) ok = 1
      if (!ok) note("fence marker " mid[j] " at line " mline[j] " has no emit_block or pattern_id site with that id within the 8 lines below it")
      print mid[j]
    }
  }
' "$FENCE" | sort -u > "$FENCE_IDS"

# ----------------------------------------------------------------------------- validator markers
VALIDATOR_IDS="$TMPWORK/validator.ids"
awk -v errs="$ERRORS" '
  /^[[:space:]]*#[[:space:]]*@guard[[:space:]]+validator:/ {
    s = $0; sub(/^[[:space:]]*#[[:space:]]*@guard[[:space:]]+validator:/, "", s); sub(/[[:space:]]+$/, "", s)
    if (s !~ /^[A-Za-z0-9._-]+$/) { print "validator marker at line " NR " has an invalid id" >> errs; next }
    if (s in seen) { print "validator marker " s " appears twice (lines " seen[s] " and " NR ")" >> errs; next }
    seen[s] = NR; print s
  }
' "$VALIDATOR" | sort -u > "$VALIDATOR_IDS"

ENUM_JSON="$(jq -cn \
    --argjson hooks "$HOOKS_JSON" \
    --rawfile fences "$FENCE_IDS" \
    --rawfile validators "$VALIDATOR_IDS" '
  ($hooks | map(.id)) as $direct
  | ($hooks | map(select(.wrapped)) | length) as $nw
  | {
      hooks: ((($hooks | map({id, registration})) + (if $nw > 0 then ($hooks | map(select(.wrapped) | {id: "hook:hook-guard.sh", registration})) else [] end))
              | group_by(.id) | map({id: .[0].id, registrations: (map(.registration) | unique)})),
      fences: ($fences | split("\n") | map(select(length > 0)) | map("fence:" + .)),
      validators: ($validators | split("\n") | map(select(length > 0)) | map("validator:" + .))
    }')"

# ----------------------------------------------------------------------------- cross-check
GATE_LIST='["gate:verdict-derive","gate:adversarial-review-gate","gate:implement-gate","gate:success-criteria","gate:dissent-budget","gate:seams","gate:kinds","gate:prompt-budget","gate:guard-origins"]'
POLICY_LIST='["policy:permission-deny-list","policy:verdict-one-way-rule","policy:operator-only-commands"]'
jq -r --argjson e "$ENUM_JSON" --argjson floor "$FLOOR_JSON" --argjson gates "$GATE_LIST" --argjson policies "$POLICY_LIST" --arg map "$ORIGINS" '
  .guards as $g
  | ($g | map({key: .id, value: .}) | from_entries) as $by
  | ($e.hooks | map(.id)) as $hooks | $e.fences as $fences | $e.validators as $validators
  | (($hooks + $fences + $validators)[] | select($by[.] == null) | "guard \(.) has no origin row in \($map)"),
    ($g[] | select(.kind == "hook") | select(.id | IN($hooks[]) | not) | "row \(.id) resolves to nothing: no command in .claude/settings.json runs that script"),
    ($g[] | select(.kind == "fence") | select(.id | IN($fences[]) | not) | "row \(.id) resolves to nothing: no # @guard fence marker with that id in the fence"),
    ($g[] | select(.kind == "validator") | select(.id | IN($validators[]) | not) | "row \(.id) resolves to nothing: no # @guard validator marker with that id in validate-artifact.sh"),
    ($e.hooks[] | . as $h | $by[$h.id] // empty | select(((.registrations // []) | unique) != $h.registrations)
      | "row \($h.id) registrations \((.registrations // []) | unique | tojson) differ from .claude/settings.json \($h.registrations | tojson)"),
    (($gates + $policies)[] | select($by[.] == null) | "required row \(.) is missing from \($map)"),
    ((($floor.floor_guards // []) | if type != "array" then ["(floor_guards is not a list)"] else . end) as $fg
      | ($fg[] | select($by[.] == null) | "floor guard \(.) has no row in \($map)"),
        ($g[] | select(.floor == true) | select(.id | IN($fg[]) | not) | "row \(.id) has floor: true but is not in floor.yaml floor_guards"),
        ($g[] | select(.floor != true) | select(.id | IN($fg[])) | "row \(.id) is in floor.yaml floor_guards but has floor: false"))
' <<<"$MAP_JSON" >> "$ERRORS"

while IFS= read -r spath; do
    [[ -n "$spath" ]] || continue
    case "$spath" in /*|*..*) echo "gate or policy script '$spath' must be a repository-relative path" >> "$ERRORS"; continue ;; esac
    [[ -f "$ROOT/$spath" ]] || echo "gate or policy script $spath does not exist" >> "$ERRORS"
done < <(jq -r '.guards[] | select(.kind == "gate" or .kind == "policy") | .script' <<<"$MAP_JSON")

# A floor gate implemented as a hook must be REGISTERED, not merely present on disk:
# a row whose script lives under .claude/hooks/ needs a command in settings.json that
# runs it (review r1 DISS-C-003 — unregistering adversarial-review-gate.sh and dropping
# its hook row would otherwise leave --check green while the COMPLETED gate never runs).
jq -r --argjson e "$ENUM_JSON" '
  ($e.hooks | map(.id)) as $hooks
  | .guards[] | select(.floor == true and .kind == "gate" and ((.script // "") | startswith(".claude/hooks/")))
  | . as $g | ("hook:" + ($g.script | ltrimstr(".claude/hooks/"))) as $hid
  | select($hooks | index($hid) | not)
  | "floor gate \($g.id) names \($g.script) but no command in .claude/settings.json runs it (the gate is not registered)"
' <<<"$MAP_JSON" >> "$ERRORS"

if [[ -s "$ERRORS" ]]; then
    sed "s/^/$SCRIPT_NAME: /" "$ERRORS" >&2
    exit 5
fi

# ----------------------------------------------------------------------------- renderers
# Shared cell sanitiser: control characters removed, pipes escaped for GFM tables.
JQ_DEFS='
  def cell: tostring | explode | map(select(. >= 32 and . != 127)) | implode | gsub("\\|"; "\\|");
  def kinds: ["hook", "fence", "validator", "gate", "policy"];
  def regs: if (.registrations // []) | length == 0 then "-" else (.registrations | map("`" + cell + "`") | join(", ")) end;
  def origin_txt: .origin as $o | if ($o.ref | tostring | startswith($o.kind | tostring)) then ($o.ref | tostring) else "\($o.kind) \($o.ref)" end;
  def yesno: if . == true then "yes" else "no" end;
'

render_register() {
    jq -r "$JQ_DEFS"'
      .guards as $g
      | "# Guard register",
        "",
        "<!-- Generated by .claude/scripts/guard-yield.sh from .claude/settings.json, the fence and validator markers and .claude/data/guard-origins.yaml. Do not edit by hand: edit the origin map and regenerate (.claude/scripts/guard-yield.sh --hooks-table); CI runs --check. -->",
        "",
        "Every guard Loa ships, with its class, status, origin, knob and floor flag. Structural only: the 30-day yield of a host is untracked, in `.run/guard-yield.md` and `.run/guard-yield.json` (regenerate with `.claude/scripts/guard-yield.sh`). Classes: harness (the model cannot override it), script (a script checks or reports), prose (the model is asked to comply). Status: dormant means armed only by the env var in the knob column; telemetry means it observes and never refuses.",
        "",
        "- guards: \($g | length)",
        "- guards_without_origin: \($g | map(select((.origin.ref // "") == "")) | length)",
        "- dormant: \($g | map(select(.status == "dormant")) | length)",
        "- floor: \($g | map(select(.floor == true)) | length)",
        (kinds[] as $k | ($g | map(select(.kind == $k))) as $rows | select($rows | length > 0)
          | "",
            "## \($k) (\($rows | length))",
            "",
            "| id | class | status | origin | knob | floor | registrations |",
            "|----|-------|--------|--------|------|-------|---------------|",
            ($rows[] | "| \(.id | cell) | \(.class | cell) | \(.status | cell) | \(origin_txt | cell) | \(.knob | cell) | \(.floor | yesno) | \(regs) |"))
    ' <<<"$MAP_JSON"
}

render_hooks_block() {
    jq -r --argjson hooks "$HOOKS_JSON" "$JQ_DEFS"'
      (.guards | map({key: .id, value: .}) | from_entries) as $by
      | "<!-- guard-register:begin -->",
        "<!-- Generated by .claude/scripts/guard-yield.sh --hooks-table from .claude/settings.json and .claude/data/guard-origins.yaml; do not edit by hand. Full register: grimoires/loa/guards.md -->",
        "| Event | Matcher | Script | Status | Knob | Purpose |",
        "|-------|---------|--------|--------|------|---------|",
        ($hooks[] | . as $h | $by[$h.id] as $r
          | "| \($h.event | cell) | \(if $h.matcher == "" then "(all)" else ($h.matcher | cell) end) | `\(if $h.wrapped then "hook-guard.sh " else "" end)\($h.id | ltrimstr("hook:") | cell)` | \($r.status | cell) | \($r.knob | cell) | \($r.note // "" | cell) |"),
        "<!-- guard-register:end -->"
    ' <<<"$MAP_JSON"
}

# Rewrites the marker block of $HOOKS_REF into $2 (exit 3 when the markers are absent or repeated).
render_hooks_ref() {
    local block="$1" dest="$2" nb ne
    [[ -f "$HOOKS_REF" && -r "$HOOKS_REF" ]] || die 3 "hooks reference not readable: $HOOKS_REF"
    nb="$(grep -c '^<!-- guard-register:begin -->$' "$HOOKS_REF" || true)"
    ne="$(grep -c '^<!-- guard-register:end -->$' "$HOOKS_REF" || true)"
    [[ "$nb" == "1" && "$ne" == "1" ]] \
        || die 3 "$HOOKS_REF needs exactly one <!-- guard-register:begin --> and one <!-- guard-register:end --> line (found $nb and $ne)"
    # The end marker must follow the begin marker, else the awk pass below would drop
    # everything after a misplaced end line (review r1 DISS-C-006).
    local lb le
    lb="$(grep -n '^<!-- guard-register:begin -->$' "$HOOKS_REF" | cut -d: -f1)"
    le="$(grep -n '^<!-- guard-register:end -->$' "$HOOKS_REF" | cut -d: -f1)"
    [[ "$lb" -lt "$le" ]] \
        || die 3 "$HOOKS_REF has its <!-- guard-register:end --> marker (line $le) before the begin marker (line $lb); restore the order"
    awk -v blockfile="$block" '
      /^<!-- guard-register:begin -->$/ { while ((getline l < blockfile) > 0) print l; skip = 1; next }
      /^<!-- guard-register:end -->$/ { skip = 0; next }
      !skip { print }
    ' "$HOOKS_REF" > "$dest"
}

# Atomic replace: temp beside the destination, then rename.
install_file() {
    local src="$1" dest="$2" tmp
    mkdir -p "$(dirname "$dest")"
    tmp="$(mktemp "$(dirname "$dest")/.$(basename "$dest").XXXXXX")"
    cat "$src" > "$tmp"
    chmod 0644 "$tmp"
    mv -f "$tmp" "$dest"
}

REGISTER_NEW="$TMPWORK/guards.md"
render_register > "$REGISTER_NEW"
HOOKS_BLOCK="$TMPWORK/hooks-block.md"
render_hooks_block > "$HOOKS_BLOCK"
HOOKS_REF_NEW="$TMPWORK/hooks-reference.md"
N_GUARDS="$(jq '.guards | length' <<<"$MAP_JSON")"

# ----------------------------------------------------------------------------- --check
if (( DO_CHECK )); then
    render_hooks_ref "$HOOKS_BLOCK" "$HOOKS_REF_NEW"
    drift=0
    if [[ ! -f "$OUT" ]] || ! cmp -s "$REGISTER_NEW" "$OUT"; then
        echo "$SCRIPT_NAME: drift: $OUT differs from the generated register" >&2
        diff -u "$OUT" "$REGISTER_NEW" 2>/dev/null | head -20 >&2 || true
        drift=1
    fi
    if ! cmp -s "$HOOKS_REF_NEW" "$HOOKS_REF"; then
        echo "$SCRIPT_NAME: drift: the guard-register table in $HOOKS_REF differs from the generated one" >&2
        diff -u "$HOOKS_REF" "$HOOKS_REF_NEW" 2>/dev/null | head -20 >&2 || true
        drift=1
    fi
    if (( drift )); then
        echo "$SCRIPT_NAME: $REGEN_HINT" >&2
        exit 1
    fi
    echo "$SCRIPT_NAME: in sync ($N_GUARDS guards)"
    exit 0
fi

# ----------------------------------------------------------------------------- yield
SEGMENTS="$TMPWORK/segments"
: > "$SEGMENTS"
for f in "$AUDIT_LOG" "$AUDIT_LOG".*; do
    [[ -e "$f" ]] || continue
    [[ -f "$f" && -r "$f" ]] || die 3 "audit log segment not readable: $f"
    printf '%s\n' "$f" >> "$SEGMENTS"
done
N_SEGMENTS="$(wc -l < "$SEGMENTS" | tr -d ' ')"
ROWS="$TMPWORK/audit.rows"
: > "$ROWS"
if [[ "$N_SEGMENTS" == "0" ]]; then
    warn "no audit log at $AUDIT_LOG (or segments $AUDIT_LOG.*); the yield is empty"
else
    while IFS= read -r f; do cat -- "$f" >> "$ROWS"; printf '\n' >> "$ROWS"; done < "$SEGMENTS"
fi

TMP_PREFIX="${TMPDIR:-/tmp}"
TMP_PREFIX="${TMP_PREFIX%/}/"
MAIN_ROOT=""
if common="$(cd "$ROOT" && git rev-parse --git-common-dir 2>/dev/null)"; then
    common="$(cd "$ROOT" && cd "$common" 2>/dev/null && pwd -P)" || common=""
    case "$common" in */.git) MAIN_ROOT="${common%/.git}" ;; esac
fi

# Heredoc classification: the FR-6 classifier when present (heredoc_nonexec <command>
# returns 0 for a heredoc whose consumer does not execute it), else `<<` presence.
NONEXEC_IDX='null'
if [[ -f "$HEREDOC_LIB" ]] && grep -q '^heredoc_nonexec[[:space:]]*()' "$HEREDOC_LIB"; then
    # shellcheck source=/dev/null
    if source "$HEREDOC_LIB" 2>/dev/null && declare -F heredoc_nonexec >/dev/null; then
        IDX_FILE="$TMPWORK/nonexec.idx"
        : > "$IDX_FILE"
        # Same row indexing as the join below: non-blank lines, in order. Commands travel base64-encoded.
        while IFS="$US" read -r idx b64; do
            [[ -n "$idx" ]] || continue
            cmd="$(printf '%s' "$b64" | base64 --decode 2>/dev/null || printf '%s' "$b64" | base64 -D 2>/dev/null || true)"
            if heredoc_nonexec "$cmd" 2>/dev/null; then printf '%s\n' "$idx" >> "$IDX_FILE"; fi
        done < <(jq -R -n -r '[inputs | select(test("\\S")) | (try fromjson catch null)] | to_entries[]
                   | select((.value | type) == "object" and .value.action == "block" and ((.value.command // "") | tostring | contains("<<")))
                   | "\(.key)\u001f\(.value.command | tostring | @base64)"' "$ROWS" 2>/dev/null)
        NONEXEC_IDX="$(jq -R -s 'split("\n") | map(select(length > 0) | tonumber)' "$IDX_FILE")"
    fi
fi

YIELD_JSON="$(jq -R -n \
    --argjson map "$MAP_JSON" \
    --argjson hooks "$HOOKS_JSON" \
    --argjson nonexec "$NONEXEC_IDX" \
    --argjson now "$NOW_EPOCH" \
    --argjson win "$WINDOW_DAYS" \
    --argjson segs "$N_SEGMENTS" \
    --argjson burst_rows "$BURST_ROWS" \
    --arg tmp "$TMP_PREFIX" \
    --arg root "$ROOT" \
    --arg mainroot "$MAIN_ROOT" '
  def epoch: (.ts // .timestamp // null) | if type == "string" then (sub("\\.[0-9]+Z$"; "Z") | try fromdateiso8601 catch null) else null end;
  def under($r): . as $c | ($r != "") and ($c == $r or ($c | startswith($r + "/")));
  def minute: (.ts // .timestamp // "") | tostring | .[0:16];
  def replay($burst): (.replay == true)
    or ((.cwd // "") | type == "string" and (startswith($tmp) or contains("/bats-run-") or contains("/bats.") or contains("/evals/results/") or contains("/sandbox/")))
    or (minute | IN($burst[]));
  def outside_repo: (.cwd // "") as $c | ($c | type == "string") and $c != "" and (($c | under($root)) or ($c | under($mainroot)) | not);
  def verbs: ["rm","git","find","dd","mkfs","shred","truncate","kubectl","terraform","aws","gcloud","psql","mysql","DROP","DELETE","TRUNCATE"];
  def destructive_start: (.command // "") | tostring | [splits("(;|&&|\\|\\||\\||\n)")] | map(sub("^\\s+"; "") | (split("\\s+"; null)[0] // "")) | any(.[]; IN(verbs[]));
  def heredoc: if $nonexec == null then ((.command // "") | tostring | contains("<<")) else (._i | IN($nonexec[])) end;
  def prose_class: (.pattern_id // "") | IN("SP-1", "FR-MERGE-2", "FR-2-AMBIGUOUS");
  # A System-Zone block is never a false positive on account of its body: the hazard is the
  # target (files under .claude/ are read as instructions), so the heredoc heuristic applies to
  # content rules only (cycle-129 sprint-256 audit MEDIUM-A2).
  def system_zone: (.pattern_id // "") | tostring | startswith("FR-SZ");
  def likely_fp: (heredoc and (system_zone | not)) or outside_repo or (prose_class and (destructive_start | not));
  def day: strftime("%Y-%m-%d");
  def origin_txt: .origin as $o | if ($o.ref | tostring | startswith($o.kind | tostring)) then ($o.ref | tostring) else "\($o.kind) \($o.ref)" end;
  ($hooks | map({key: (.rel | split("/") | last | sub("\\.sh$"; "")), value: .id}) | from_entries) as $hookid
  | ($map.guards | map(.id)) as $known
  | [inputs | select(test("\\S")) | (try fromjson catch null)] as $raw
  | ($raw | to_entries | map(.value as $v | if ($v | type) == "object" then ($v + {_i: .key}) else null end)) as $all
  | ($all | map(select(. != null))) as $rows
  | ($rows | length) as $read
  | ($rows | map(select(.action == "block" or .hook == "implement-gate") | . + {_t: epoch})) as $cand
  | ($cand | map(select(._t != null and ._t >= ($now - $win * 86400) and ._t <= ($now + 86400)))) as $inwin
  | ($inwin | map(select(.action == "block" and .replay != true)) | group_by(minute)
     | map(select(length >= $burst_rows) | .[0] | minute)) as $burst
  | ($inwin | map(select(replay($burst) | not))) as $live
  | ($live | map(
      (if .hook == "block-destructive-bash" then
         ["hook:safety/block-destructive-bash.sh"] + (if ((.pattern_id // "") | tostring | test("^[A-Za-z0-9._-]+$")) then ["fence:" + .pattern_id] else [] end)
       elif .hook == "implement-gate" then ["hook:compliance/implement-gate.sh", "gate:implement-gate"]
       elif ((.hook // "") | type) == "string" and $hookid[.hook] != null then [$hookid[.hook]]
       else [] end) as $ids
      | {ids: ($ids | map(select(IN($known[])))),
         block: (.action == "block" or .action == "deny"),
         telemetry: (.action == "telemetry" or .action == "ask"),
         fp: ((.action == "block" or .action == "deny") and likely_fp),
         t: ._t})) as $cls
  | ($cls | map(.ids[]) | unique) as $seen
  | (["hook:safety/block-destructive-bash.sh", "hook:compliance/implement-gate.sh", "gate:implement-gate"]
     + ($map.guards | map(select(.kind == "fence") | .id)) + $seen | unique) as $writers
  | ($map.guards | map(. as $g
      | if ($g.id | IN($writers[])) then
          ($cls | map(select(any(.ids[]; . == $g.id)))) as $mine
          | ($mine | map(select(.block and (.fp | not))) | map(.t) | max) as $last
          | {id, kind, class, status, origin: origin_txt, knob, floor, registrations: (.registrations // []), audited: true,
             blocks_30d: ($mine | map(select(.block)) | length),
             likely_fp_30d: ($mine | map(select(.fp)) | length),
             telemetry_30d: ($mine | map(select(.telemetry)) | length),
             last_real_catch: (if $last == null then "none in window" else ($last | day) end)}
        else
          {id, kind, class, status, origin: origin_txt, knob, floor, registrations: (.registrations // []), audited: false,
           blocks_30d: null, likely_fp_30d: null, telemetry_30d: null, last_real_catch: "n/a"}
        end)) as $guards
  | {
      schema_version: 1,
      generated_at: ($now | day),
      window_days: $win,
      scope: "host",
      audit_segments: $segs,
      audit_rows_read: $read,
      audit_rows_unparseable: (($raw | length) - $read),
      audit_rows_considered: ($inwin | length),
      replay_rows_excluded: (($inwin | length) - ($live | length)),
      replay_rows_by_rule: {
        flag: ($inwin | map(select(.replay == true)) | length),
        cwd: ($inwin | map(select(.replay != true and replay([]))) | length),
        burst: ($inwin | map(select(.replay != true and (replay([]) | not) and replay($burst))) | length)
      },
      heuristic: "likely_fp = heredoc in the command OR cwd outside the repository OR (pattern SP-1, FR-MERGE-2 or FR-2-AMBIGUOUS with no destructive verb at statement start); real = block AND NOT likely_fp",
      totals: {
        guards: ($map.guards | length),
        guards_without_origin: 0,
        dormant: ($map.guards | map(select(.status == "dormant")) | length),
        blocks_30d: ($cls | map(select(.block)) | length),
        real_blocks_30d: ($cls | map(select(.block and (.fp | not))) | length),
        likely_fp_30d: ($cls | map(select(.fp)) | length),
        telemetry_30d: ($cls | map(select(.telemetry)) | length),
        unattributed_30d: ($cls | map(select(.ids | length == 0)) | length)
      },
      guards: $guards
    }
' "$ROWS")" || die 3 "the audit log could not be joined"

render_yield_md() {
    jq -r "$JQ_DEFS"'
      def n: if . == null then "n/a" else tostring end;
      . as $y
      | "# Guard yield (host)",
        "",
        "<!-- Generated by .claude/scripts/guard-yield.sh; untracked, host-local. The structural register is grimoires/loa/guards.md. -->",
        "",
        "- generated_at: \($y.generated_at)",
        "- window_days: \($y.window_days)",
        "- scope: \($y.scope)",
        "- audit_segments: \($y.audit_segments)",
        "- audit_rows_considered: \($y.audit_rows_considered)",
        "- replay_rows_excluded: \($y.replay_rows_excluded) (flag \($y.replay_rows_by_rule.flag), cwd \($y.replay_rows_by_rule.cwd), burst \($y.replay_rows_by_rule.burst))",
        "- audit_rows_unparseable: \($y.audit_rows_unparseable)",
        "- totals: \($y.totals.real_blocks_30d) real blocks, \($y.totals.likely_fp_30d) likely FP, \($y.totals.telemetry_30d) telemetry, \($y.totals.unattributed_30d) unattributed",
        "- heuristic: \($y.heuristic | cell)",
        (kinds[] as $k | ($y.guards | map(select(.kind == $k))) as $rows | select($rows | length > 0)
          | "",
            "## \($k) (\($rows | length))",
            "",
            "| id | class | status | origin | knob | floor | registrations | blocks_30d | likely_fp_30d | telemetry_30d | last_real_catch |",
            "|----|-------|--------|--------|------|-------|---------------|------------|---------------|---------------|-----------------|",
            ($rows[] | "| \(.id | cell) | \(.class | cell) | \(.status | cell) | \(.origin | cell) | \(.knob | cell) | \(.floor | yesno) | \(regs) | \(.blocks_30d | n) | \(.likely_fp_30d | n) | \(.telemetry_30d | n) | \(.last_real_catch | cell) |"))
    ' <<<"$YIELD_JSON"
}

YIELD_MD_NEW="$TMPWORK/guard-yield.md"
YIELD_JSON_NEW="$TMPWORK/guard-yield.json"
render_yield_md > "$YIELD_MD_NEW"
jq '.' <<<"$YIELD_JSON" > "$YIELD_JSON_NEW"

install_file "$REGISTER_NEW" "$OUT"
install_file "$YIELD_MD_NEW" "$YIELD_DIR/guard-yield.md"
install_file "$YIELD_JSON_NEW" "$YIELD_DIR/guard-yield.json"
if (( DO_HOOKS_TABLE )); then
    render_hooks_ref "$HOOKS_BLOCK" "$HOOKS_REF_NEW"
    cmp -s "$HOOKS_REF_NEW" "$HOOKS_REF" || install_file "$HOOKS_REF_NEW" "$HOOKS_REF"
fi

summary="$(jq -r '"\(.totals.guards) guards (\(.totals.dormant) dormant); \(.window_days) d: \(.totals.real_blocks_30d) real blocks, \(.totals.likely_fp_30d) likely FP, \(.replay_rows_excluded) replay rows excluded; scope host"' <<<"$YIELD_JSON")"
if (( DO_JSON )); then
    cat "$YIELD_JSON_NEW"
    echo "$SCRIPT_NAME: wrote $OUT and $YIELD_DIR/guard-yield.{md,json}: $summary" >&2
else
    echo "$SCRIPT_NAME: wrote $OUT and $YIELD_DIR/guard-yield.{md,json}: $summary"
fi
exit 0
