#!/usr/bin/env bash
# =============================================================================
# run-checkpoint.sh — run position in .run/ (cycle-125 FR-3, SDD D-3.2;
# cycle-129 FR-4(f)/FR-5, SDD D-4.6, D-5.1 … D-5.4). Beads are the task ledger;
# the checkpoint is a HINT; the run state and the breaker are caches DERIVED
# from files (COMPLETED markers, LOA-VERDICT trailers, the ledger, git).
#
#   run-checkpoint.sh write --sprint sprint-N --phase PHASE [--task BEAD-ID] [--file F]
#       Atomically sets .schema_version = 2, .checkpoint = {sprint, task, phase, ts}
#       and .timestamps.last_activity = ts: jq → F.tmp.$$ → mv -f, under flock
#       on F.lock. F must already exist (a run in progress). Then runs
#       `derive --write` (a missing ledger is skipped). Exit 0 · 2 usage /
#       no run · 3 write failed (the previous file is untouched).
#   run-checkpoint.sh read [--file F] [--json]
#       Prints the checkpoint when it is trustworthy: parses, and when a task
#       is named, `br show <task> --json` reports it closed (a checkpoint that
#       names an open or unknown bead is DISCARDED with a logged line — beads
#       remain the recovery source). schema_version 1 / no checkpoint → prints
#       "sprint granularity". Exit 0 always when F exists; 2 when it does not.
#   run-checkpoint.sh derive [--json] [--write] [--root DIR] [--file F]
#       For the ledger's active cycle, per sprint: global_id, local_label,
#       ledger status, completed_marker (a2a/sprint-<gid>/COMPLETED exists and
#       the feedback trailers name this sprint, as sprint-<gid> or the local
#       label; a trailer or a `sprint:` line naming another sprint makes it a
#       stale_marker, treated as absent), review/audit verdicts (verdict-derive.sh;
#       APPROVED needs exit 0; a file without a trailer is legacy: no verdict,
#       listed in derivation.legacy_feedback), impl_commit (newest non-merge
#       commit on HEAD since max(sprint started|created, cycle created) touching
#       a path outside grimoires/, .run/, REPO-MAP.md, checksums.json,
#       CHANGELOG.md) and state complete | awaiting_marker | in_progress.
#       Run state, first match wins:
#         cache .state or .status JACKED_OUT, or .completion.merged_sha → JACKED_OUT (terminal)
#         breaker OPEN, or cache HALTED                                 → HALTED (sticky until /run-resume)
#         every sprint complete                                         → COMPLETE
#         cache COMPLETE and the ledger registers no new incomplete sprint → COMPLETE
#         last_activity within run_mode.stale_hours (12)                → RUNNING
#         otherwise                                                     → INTERRUPTED
#       Breaker (active sprint = first incomplete, else the last): the ordered
#       rounds engineer-feedback-r*.md, auditor-sprint-feedback-r*.md and the
#       current files (sorted by trailer ts, round, gate; rounds before the
#       breaker's reset_at are ignored) give cycle_count (non-APPROVED rounds),
#       same_issue (consecutive equal hashes) and no_progress (consecutive
#       equal counts); each cached counter is raised to its recomputed value,
#       never lowered; OPEN when a count threshold is met (timeout is left to
#       record-round). --json prints the derivation; --write rewrites F
#       (.state canonical, .status mirrored, derived_at, derivation {source,
#       stale_markers, legacy_feedback, sprint_ids}; schema_version kept) and
#       the breaker, under their locks — only when F exists, parses, and
#       run_mode.file_authoritative is not false (false = report-only).
#       Exit 0 · 4 no ledger / no active cycle · 2 usage.
#   run-checkpoint.sh record-round --gate review|audit --file FEEDBACK [--sprint sprint-N]
#                                  [--state-file F] [--breaker B]
#       After a review or audit: verdict-derive.sh --json on FEEDBACK; the
#       same-issue hash is md5 of `jq -Sc '{verdict,counts}'` of that output
#       (no trailer: md5 of the first 50 lines from ## Findings / ## Issues /
#       ## Changes Required). APPROVED (exit 0) leaves every counter as is.
#       Otherwise, atomically on B: same_issue +1 when the hash equals
#       last_hash, else count 1 and last_hash = hash; no_progress +1 when the
#       counts equal the previous round's, else 0; cycle_count.current +1; then
#       the triggers in order same_issue ≥ threshold, no_progress ≥ threshold,
#       cycle_count ≥ limit, timeout (now - started ≥ limit_hours). A trip sets
#       state OPEN, appends history {timestamp, trigger, reason, gate, sprint},
#       sets F (.run/state.json) .state = HALTED, prints
#       `TRIPPED: <trigger>: <reason>` and exits 10 (also when B is already OPEN).
#       Exit 0 recorded · 2 usage / missing file · 3 write failed · 10 tripped.
#   run-checkpoint.sh mark --skill implement|bug --sprint ID [--root DIR]
#       Writes .run/implement-active.json {skill, sprint, started_at} (the
#       implement gate's marker sanction, valid two hours), then runs
#       `derive --write` when F exists. `unmark` removes the marker. Exit 0 · 2 usage.
#
# Default F: $LOA_RUN_DIR/sprint-plan-state.json, else <root>/.run/sprint-plan-state.json
# (--root DIR sets <root> and ignores LOA_RUN_DIR). B: <run dir>/circuit-breaker.json.
# Readers accept schema_version 1 and 2 and files without derived_at/derivation.
# Config (<root>/.loa.config.yaml, yq; absent = defaults): run_mode.stale_hours (12),
# run_mode.file_authoritative (true), run_mode.circuit_breaker.{same_issue,no_progress}_threshold
# (3, 5), run_mode.defaults.{max_cycles,timeout_hours} (20, 8) for a new breaker file.
# =============================================================================
set -euo pipefail
export LC_ALL=C
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERDICT_DERIVE="$SCRIPT_DIR/verdict-derive.sh"
usage() { sed -n '3,/^# Default F/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

sub="${1:-}"; [[ -n "$sub" ]] || usage; shift
file="" sprint="" task="" phase="" json=0 write=0 root="" gate="" state_file="" breaker="" skill=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --file)   [[ $# -ge 2 && -n "$2" ]] || usage; file="$2"; shift 2 ;;
    --sprint) [[ $# -ge 2 && "$2" =~ ^[A-Za-z0-9._-]+$ ]] || usage; sprint="$2"; shift 2 ;;
    --task)   [[ $# -ge 2 && "$2" =~ ^[A-Za-z0-9._-]+$ ]] || usage; task="$2"; shift 2 ;;
    --phase)  [[ $# -ge 2 && "$2" =~ ^[A-Z_]+$ ]] || usage; phase="$2"; shift 2 ;;
    --json)   json=1; shift ;;
    --write)  write=1; shift ;;
    --root)   [[ $# -ge 2 && -d "${2:-}" ]] || usage; root="$(cd "$2" && pwd)"; shift 2 ;;
    --gate)   [[ $# -ge 2 && ( "$2" == review || "$2" == audit ) ]] || usage; gate="$2"; shift 2 ;;
    --state-file|--file-state) [[ $# -ge 2 && -n "$2" ]] || usage; state_file="$2"; shift 2 ;;
    --breaker) [[ $# -ge 2 && -n "$2" ]] || usage; breaker="$2"; shift 2 ;;
    --skill)  [[ $# -ge 2 && ( "$2" == implement || "$2" == bug ) ]] || usage; skill="$2"; shift 2 ;;
    *) usage ;;
  esac
done

# Root and run dir: --root wins (and pins the run dir under it); else the
# directory holding a --file that sits in a .run/ dir (write/read/derive only);
# else this script's checkout with $LOA_RUN_DIR honoured.
if [[ -n "$root" ]]; then
  run_dir="$root/.run"
else
  root="$(cd "$SCRIPT_DIR/../.." && pwd)"
  run_dir="${LOA_RUN_DIR:-$root/.run}"
  if [[ -n "$file" && "$sub" != record-round ]]; then
    fdir="$(cd "$(dirname "$file")" 2>/dev/null && pwd)" || fdir=""
    if [[ -n "$fdir" && "$(basename "$fdir")" == .run ]]; then root="$(dirname "$fdir")"; run_dir="$fdir"; fi
  fi
fi
if [[ "$sub" != record-round && -z "$file" ]]; then file="$run_dir/sprint-plan-state.json"; fi
[[ -n "$breaker" ]] || breaker="$run_dir/circuit-breaker.json"
[[ -n "$state_file" ]] || state_file="$run_dir/state.json"
CONFIG="$root/.loa.config.yaml"

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# cfg KEY → the raw yq value ("null" when absent or unreadable). yq's `//`
# treats false as absent, so callers compare the raw text.
cfg() {
  local v
  if command -v yq >/dev/null 2>&1 && [[ -f "$CONFIG" ]]; then
    v=$(yq "$1" "$CONFIG" 2>/dev/null) || v="null"
    printf '%s' "${v//\"/}"
  else
    printf 'null'
  fi
}
cfg_int() {  # KEY DEFAULT MAX → a positive integer ≤ MAX, else DEFAULT
  local v; v=$(cfg "$1")
  if [[ "$v" =~ ^[0-9]+$ ]] && (( v > 0 && v <= $3 )); then printf '%s' "$v"; else printf '%s' "$2"; fi
}

_md5() { if command -v md5sum >/dev/null 2>&1; then md5sum | cut -d' ' -f1; else md5 -q; fi; }

# atomic_update FILE JQ-ARGS... — jq over FILE (or {} when FILE is absent) →
# FILE.tmp.$$ → mv -f, under flock on FILE.lock. Exit 3 on any failure; the
# previous file is untouched.
atomic_update() {
  local f="$1"; shift
  local tmp="$f.tmp.$$" rc=0
  (
    # flock is util-linux (Linux); without it (macOS) the write is still atomic
    # (tmp + mv) but concurrent writers may interleave — last writer wins.
    if command -v flock >/dev/null 2>&1; then flock -w 5 9 || { echo "run-checkpoint: lock timeout on $f.lock" >&2; exit 3; }; fi
    if [[ -f "$f" ]]; then
      jq "$@" "$f" > "$tmp" 2>/dev/null || { rm -f -- "$tmp"; echo "run-checkpoint: $f is not valid JSON — not written" >&2; exit 3; }
    else
      jq "$@" <<<'{}' > "$tmp" 2>/dev/null || { rm -f -- "$tmp"; echo "run-checkpoint: could not build $f" >&2; exit 3; }
    fi
    jq -e . "$tmp" >/dev/null 2>&1 || { rm -f -- "$tmp"; echo "run-checkpoint: refusing to replace $f with unparseable output" >&2; exit 3; }
    mv -f -- "$tmp" "$f"
  ) 9>"$f.lock" || rc=$?
  return $rc
}

cmd_write() {
  [[ -n "$sprint" && -n "$phase" ]] || usage
  if [[ ! -f "$file" ]]; then echo "run-checkpoint: no run state at $file (start a run first)" >&2; return 2; fi
  local ts rc=0
  ts=$(now_iso)
  atomic_update "$file" --arg s "$sprint" --arg t "$task" --arg p "$phase" --arg ts "$ts" \
    '.schema_version = 2
     | .checkpoint = {sprint: $s, task: (if $t == "" then null else $t end), phase: $p, ts: $ts}
     | .timestamps = ((.timestamps // {}) + {last_activity: $ts})' || rc=$?
  (( rc == 0 )) || return $rc
  # Every checkpoint refreshes the derived caches (D-5.2); a missing ledger (4) is not an error here
  local err drc=0
  err=$( { write=1; json=0; cmd_derive >/dev/null; } 2>&1 ) || drc=$?
  if (( drc != 0 && drc != 4 )); then printf '%s\n' "$err" >&2; fi
  return 0
}

bead_closed() {  # $1 bead id → 0 when br reports closed
  command -v br >/dev/null 2>&1 || return 2
  local js st
  js=$(br show "$1" --json 2>/dev/null) || return 1
  st=$(printf '%s' "$js" | jq -r 'if type=="array" then .[0] else . end | .status // .issue.status // empty' 2>/dev/null) || return 1
  [[ "$st" == "closed" ]]
}

cmd_read() {
  if [[ ! -f "$file" ]]; then echo "run-checkpoint: no run state at $file" >&2; return 2; fi
  if ! jq -e . "$file" >/dev/null 2>&1; then echo "run-checkpoint: $file unparseable — no checkpoint; beads are the recovery truth" >&2; if (( json )); then echo '{"checkpoint":null,"reason":"unparseable"}'; fi; return 0; fi
  local sv cp s t p ts reason="" brc
  sv=$(jq -r '.schema_version // 1' "$file"); cp=$(jq -c '.checkpoint // null' "$file")
  [[ "$sv" =~ ^[0-9]+$ ]] || sv=1
  if [[ "$cp" == "null" || "$sv" -lt 2 ]]; then
    if (( json )); then echo '{"checkpoint":null,"reason":"sprint granularity"}'; else echo "checkpoint: none (schema_version $sv → sprint granularity; resume at the first open bead of sprints.current)"; fi
    return 0
  fi
  s=$(jq -r '.checkpoint.sprint // empty' "$file"); t=$(jq -r '.checkpoint.task // empty' "$file"); p=$(jq -r '.checkpoint.phase // empty' "$file"); ts=$(jq -r '.checkpoint.ts // empty' "$file")
  if [[ -z "$s" || -z "$p" ]]; then reason="malformed checkpoint"
  elif [[ -n "$t" ]]; then
    # A task checkpoint is trusted only when beads CONFIRMS the task closed;
    # "br unavailable" is not a confirmation (Bridgebuilder PR #1269 FIND-003).
    brc=0; bead_closed "$t" || brc=$?
    case $brc in 0) ;; 2) reason="beads unavailable — task $t cannot be verified";; *) reason="task $t is not closed in beads";; esac
  fi
  if [[ -n "$reason" ]]; then
    echo "run-checkpoint: discarding checkpoint ($reason) — resume from the first open bead of $s" >&2
    if (( json )); then jq -cn --arg r "$reason" --arg s "$s" '{checkpoint:null, reason:$r, sprint:$s}'; else echo "checkpoint: discarded ($reason); resume at the first open bead of $s"; fi
    return 0
  fi
  if (( json )); then jq -c '{checkpoint: .checkpoint}' "$file"
  else echo "checkpoint: $s ${t:+task $t }phase $p at $ts → resume at the first open bead after $t in $s"; fi
}

# fb_parse FILE GATE → one compact JSON object: {file, exists, trailer, verdict,
# counts, exit_code, sprint_id, ts, approved, hash}. The hash is the run-mode
# same-issue hash (md5 of `jq -Sc '{verdict,counts}'` over verdict-derive's
# --json output; legacy files hash their findings section).
fb_parse() {
  local f="$1" g="$2" rel vj tl pj hash
  rel="${f#"$root"/}"
  if [[ ! -f "$f" ]]; then jq -nc --arg f "$rel" '{file: $f, exists: false}'; return 0; fi
  vj=$(bash "$VERDICT_DERIVE" --file "$f" --gate "$g" --json 2>/dev/null) || true
  jq -e 'type == "object"' >/dev/null 2>&1 <<<"$vj" || vj='{"trailer_found":false,"verdict":null,"counts":null,"exit_code":1}'
  tl=$(grep -E '^<!-- LOA-VERDICT \{.*\} -->[[:space:]]*$' "$f" 2>/dev/null | tail -n 1) || tl=""
  pj=$(printf '%s' "$tl" | sed -E 's/^<!-- LOA-VERDICT (.*) -->[[:space:]]*$/\1/')
  jq -e 'type == "object"' >/dev/null 2>&1 <<<"$pj" || pj='{}'
  if [[ "$(jq -r '.trailer_found' <<<"$vj")" == true ]]; then
    hash=$(printf '%s\n' "$vj" | jq -Sc '{verdict,counts}' | _md5)
  else
    hash=$( { grep -A 100 "## Findings\|## Issues\|## Changes Required" "$f" 2>/dev/null || true; } | head -50 | _md5)
  fi
  jq -nc --arg f "$rel" --argjson v "$vj" --argjson p "$pj" --arg h "$hash" '
    def sid: if type == "string" and test("^[A-Za-z0-9._-]{1,64}$") then . else null end;
    def tsv: if type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z$") then . else null end;
    {file: $f, exists: true, trailer: ($v.trailer_found == true),
     verdict: ($v.verdict | if type == "string" then . else null end),
     counts: ($v.counts // null), exit_code: ($v.exit_code // 1),
     sprint_id: ($p.sprint_id | sid), ts: ($p.ts | tsv), hash: $h}
    | .approved = (.exit_code == 0 and .verdict == "APPROVED")'
}

# impl_commit SINCE → "sha epoch" of the newest non-merge commit on HEAD since
# SINCE touching a path outside the state/generated set, or nothing
impl_commit() {
  git -C "$root" rev-parse --git-dir >/dev/null 2>&1 || return 0
  git -C "$root" log --no-merges -n 1 --format='%H %ct' ${1:+"--since=$1"} -- . \
    ':(exclude,glob)grimoires/**' ':(exclude,glob).run/**' ':(exclude,glob)**/REPO-MAP.md' \
    ':(exclude,glob)**/checksums.json' ':(exclude,glob)**/CHANGELOG.md' 2>/dev/null || true
}

# The ordered rounds of one sprint directory: every -rN file, then the current
# file unless it is byte-identical to the highest -rN of its gate
rounds_of() {
  local dir="$1" g base f n top topn cur
  for g in review audit; do
    if [[ "$g" == review ]]; then base=engineer-feedback; else base=auditor-sprint-feedback; fi
    top=""; topn=-1
    for f in "$dir/$base"-r*.md; do
      [[ -f "$f" ]] || continue
      n=${f##*-r}; n=${n%.md}
      [[ "$n" =~ ^[0-9]{1,6}$ ]] || continue
      fb_parse "$f" "$g" | jq -c --arg g "$g" --argjson n "$((10#$n))" '. + {gate: $g, round: $n}'
      if (( 10#$n > topn )); then topn=$((10#$n)); top="$f"; fi
    done
    cur="$dir/$base.md"
    if [[ -f "$cur" ]] && ! { [[ -n "$top" ]] && cmp -s "$cur" "$top"; }; then
      fb_parse "$cur" "$g" | jq -c --arg g "$g" '. + {gate: $g, round: 999999}'
    fi
  done
}

# Shared jq definitions: time, the breaker recompute and the run-state resolution
JQ_DEFS='
def epoch: if type == "string" then (sub("\\.[0-9]+Z$"; "Z") | try fromdateiso8601 catch null) else null end;
def fresh($now; $win): epoch as $t | $t != null and ($now - $t) <= $win and ($t - $now) <= 300;
def recompute($rounds; $reset):
  ($rounds
   | map(select($reset == null or ((.ts // "") > $reset)))
   | sort_by([(.ts // ""), .round, (if .gate == "review" then 0 else 1 end)])
   | map(select(.approved | not))) as $nr
  | reduce $nr[] as $r ({cycle: 0, same: 0, hash: null, np: 0, lc: null};
      .cycle += 1
      | (if $r.hash != "none" and $r.hash == .hash then .same += 1 else .same = 1 | .hash = $r.hash end)
      | ($r.counts | tojson) as $c
      | (if .lc != null and .lc == $c then .np += 1 else .np = 0 end)
      | .lc = $c);
def skeleton($th; $ts):
  {state: "CLOSED",
   triggers: {same_issue: {count: 0, threshold: $th.same, last_hash: null},
              no_progress: {count: 0, threshold: $th.np},
              cycle_count: {current: 0, limit: $th.cycles},
              timeout: {started: $ts, limit_hours: $th.hours}},
   history: []};
def merge_breaker($rc; $th; $ts):
  (if type == "object" then . else skeleton($th; $ts) end)
  | .triggers = (.triggers // {})
  | .triggers.cycle_count.current = ([(.triggers.cycle_count.current // 0), $rc.cycle] | max)
  | (if $rc.same > (.triggers.same_issue.count // 0)
     then .triggers.same_issue.count = $rc.same | .triggers.same_issue.last_hash = $rc.hash else . end)
  | (if $rc.np > (.triggers.no_progress.count // 0) or (.triggers.no_progress.last_counts == null and $rc.lc != null)
     then .triggers.no_progress.count = ([(.triggers.no_progress.count // 0), $rc.np] | max)
          | .triggers.no_progress.last_counts = $rc.lc else . end)
  | ( if (.triggers.same_issue.count // 0) >= (.triggers.same_issue.threshold // $th.same)
        then ["same_issue", "same issue hash repeated \(.triggers.same_issue.count) times (derived from the feedback history)"]
      elif (.triggers.no_progress.count // 0) >= (.triggers.no_progress.threshold // $th.np)
        then ["no_progress", "counts unchanged for \(.triggers.no_progress.count) consecutive rounds (derived from the feedback history)"]
      elif (.triggers.cycle_count.current // 0) >= (.triggers.cycle_count.limit // $th.cycles)
        then ["cycle_count", "\(.triggers.cycle_count.current) changes-required rounds (derived from the feedback history)"]
      else null end ) as $trip
  | if $trip != null and (.state // "CLOSED") != "OPEN"
    then .state = "OPEN" | .history = ((.history // []) + [{timestamp: $ts, trigger: $trip[0], reason: $trip[1], source: "derive"}])
    else .state = (.state // "CLOSED") end;
def known_ids: (.derivation.sprint_ids // null) // ((.sprints.list // []) | map(.id? // empty));
def resolve($f; $now; $win):
  . as $c
  | (if ($c | type) == "object" then $c else {} end) as $c
  | ($c.state // $c.status // "") as $cs
  | ($c | known_ids) as $known
  | ([$f.sprints[] | select(.state != "complete")
      | "sprint-\(.global_id)" as $g | .local_label as $l
      | select(($known | index($g)) == null and ($l == "" or ($known | index($l)) == null))] | length > 0) as $new
  | ((($c.completion // {}) | .merged_sha? // "") | type == "string" and length > 0) as $merged
  | if ($c.state // "") == "JACKED_OUT" or ($c.status // "") == "JACKED_OUT" or $merged then "JACKED_OUT"
    elif $f.breaker_open or $cs == "HALTED" then "HALTED"
    elif $f.all_complete then "COMPLETE"
    elif $cs == "COMPLETE" and ($new | not) then "COMPLETE"
    elif ($c.timestamps.last_activity? // null) | fresh($now; $win) then "RUNNING"
    else "INTERRUPTED" end;
'

cmd_derive() {
  local ledger="$root/grimoires/loa/ledger.json" a2a="$root/grimoires/loa/a2a" active rows
  if [[ ! -f "$ledger" ]] || ! jq -e 'type == "object"' "$ledger" >/dev/null 2>&1; then
    echo "run-checkpoint: derive: no readable ledger at $ledger — callers keep the cache" >&2; return 4
  fi
  active=$(jq -r '.active_cycle // empty | strings' "$ledger")
  if [[ -z "$active" ]] || ! jq -e --arg c "$active" 'any(.cycles[]?; .id == $c)' "$ledger" >/dev/null 2>&1; then
    echo "run-checkpoint: derive: the ledger has no active cycle — callers keep the cache" >&2; return 4
  fi
  local win now now_ts fa=1 th
  win=$(( $(cfg_int '.run_mode.stale_hours' 12 8760) * 3600 ))
  [[ "$(cfg '.run_mode.file_authoritative')" == false ]] && fa=0
  th=$(jq -nc --argjson s "$(cfg_int '.run_mode.circuit_breaker.same_issue_threshold' 3 1000)" \
              --argjson n "$(cfg_int '.run_mode.circuit_breaker.no_progress_threshold' 5 1000)" \
              --argjson c "$(cfg_int '.run_mode.defaults.max_cycles' 20 10000)" \
              --argjson h "$(cfg_int '.run_mode.defaults.timeout_hours' 8 8760)" \
              '{same: $s, np: $n, cycles: $c, hours: $h}')
  now=$(date +%s); now_ts=$(now_iso)

  # Per-sprint facts
  local sprints="[]" gid label lstatus since dir rv au mex msid ic sj
  rows=$(jq -r --arg c "$active" '
    (.cycles[] | select(.id == $c)) as $cy
    | ($cy.sprints // [])[]
    | select((.global_id | type) == "number")
    | [(.global_id | tostring), ((.local_label // "") | tostring), ((.status // "") | tostring),
       ([.started, .created, $cy.created] | map(select(type == "string" and test("^[0-9]{4}-")))
        | if length == 0 then "" else ([.[0], ($cy.created // "")] | max) end)]
    | map(if . == "" then "-" else . end)
    | @tsv' "$ledger")
  # "-" stands for an empty field: IFS whitespace (tab) would collapse two adjacent separators
  while IFS=$'\t' read -r gid label lstatus since; do
    [[ "$gid" =~ ^[0-9]+$ ]] || continue
    [[ "$label" == - ]] && label=""
    [[ "$since" == - ]] && since=""
    [[ "$label" =~ ^[A-Za-z0-9._-]{1,64}$ ]] || label=""
    [[ "$lstatus" =~ ^[a-z_]{1,32}$ ]] || lstatus="unknown"
    [[ "$since" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z$ ]] || since=""
    dir="$a2a/sprint-$gid"
    rv=$(fb_parse "$dir/engineer-feedback.md" review)
    au=$(fb_parse "$dir/auditor-sprint-feedback.md" audit)
    mex=false; msid=""
    if [[ -f "$dir/COMPLETED" ]]; then
      mex=true
      msid=$(sed -n 's/^sprint:[[:space:]]*\([A-Za-z0-9._-]*\).*/\1/p' "$dir/COMPLETED" | head -n 1) || msid=""
    fi
    ic=$(impl_commit "$since")
    sj=$(jq -nc --argjson gid "$gid" --arg label "$label" --arg status "$lstatus" --argjson rv "$rv" --argjson au "$au" \
              --argjson mex "$mex" --arg msid "$msid" --arg ic "$ic" '
      def mine: type == "string" and length > 0 and (. == "sprint-\($gid)" or ($label != "" and . == $label));
      ($rv.approved == true and ($rv.sprint_id | mine)) as $R
      | ($au.approved == true and ($au.sprint_id | mine)) as $A
      | ([$rv.sprint_id, $au.sprint_id, (if $msid == "" then null else $msid end)] | map(select(type == "string" and length > 0))) as $ids
      | ($mex and any($ids[]; mine | not)) as $stale
      | ($mex and ($stale | not) and (($rv.sprint_id | mine) or ($au.sprint_id | mine))) as $M
      | ($ic | split(" ")) as $c
      | ([$rv.ts, $au.ts] | map(select(. != null)) | max) as $vts
      | def verdict($x): if $x.exists then {verdict: $x.verdict, sprint_id: $x.sprint_id, consistent: ($x.exit_code == 0), file: $x.file} else null end;
      {global_id: $gid, local_label: $label, status: $status,
       completed_marker: $M, marker_present: $mex, stale_marker: $stale,
       review: verdict($rv), audit: verdict($au),
       impl_commit: (if ($c | length) == 2 then $c[0] else null end),
       commit_after_verdict: (if ($c | length) == 2 and $vts != null
                              then (($c[1] | tonumber) > ($vts | sub("\\.[0-9]+Z$"; "Z") | try fromdateiso8601 catch 0)) else null end),
       legacy_feedback: ([$rv, $au] | map(select(.exists and (.trailer | not)) | .file)),
       state: (if $M and $R and $A and $status == "completed" then "complete"
               elif ($M | not) and $R and $A then "awaiting_marker" else "in_progress" end)}')
    sprints=$(jq -c --argjson s "$sj" '. + [$s]' <<<"$sprints")
  done <<<"$rows"

  # Breaker recompute over the active sprint's ordered rounds
  local active_gid rounds cache="null" cache_ok=1 bcache="null" reset rc merged
  active_gid=$(jq -r 'if length == 0 then "" else ((map(select(.state != "complete")) | .[0]) // .[-1]) | .global_id | tostring end' <<<"$sprints")
  rounds="[]"
  if [[ -n "$active_gid" && -d "$a2a/sprint-$active_gid" ]]; then
    rounds=$(rounds_of "$a2a/sprint-$active_gid" | jq -sc '.')
  fi
  if [[ -f "$file" ]]; then
    if cache=$(jq -c . "$file" 2>/dev/null) && [[ -n "$cache" ]]; then :; else cache="null"; cache_ok=0; fi
  fi
  if [[ -f "$breaker" ]]; then bcache=$(jq -c 'if type == "object" then . else null end' "$breaker" 2>/dev/null) || bcache="null"; [[ -n "$bcache" ]] || bcache="null"; fi
  reset=$(jq -c '.reset_at? // null | if type == "string" then . else null end' <<<"$bcache")
  rc=$(jq -nc --argjson r "$rounds" --argjson z "$reset" "$JQ_DEFS"' recompute($r; $z)')
  merged=$(jq -c --argjson rc "$rc" --argjson th "$th" --arg ts "$now_ts" "$JQ_DEFS"' merge_breaker($rc; $th; $ts)' <<<"$bcache")

  local facts report
  facts=$(jq -nc --argjson s "$sprints" --argjson b "$merged" '
    {sprints: $s,
     all_complete: (($s | length) > 0 and all($s[]; .state == "complete")),
     breaker_open: ($b.state == "OPEN"),
     stale_markers: [$s[] | select(.stale_marker) | "sprint-\(.global_id)"],
     legacy_feedback: [$s[] | .legacy_feedback[]],
     sprint_ids: [$s[] | "sprint-\(.global_id)"]}')
  report=$(jq -nc --argjson f "$facts" --argjson c "$cache" --argjson b "$merged" --argjson rc "$rc" \
                  --argjson now "$now" --argjson win "$win" --arg ts "$now_ts" --arg cycle "$active" \
                  --argjson fa "$fa" --argjson cache_ok "$cache_ok" --arg ag "$active_gid" "$JQ_DEFS"'
    def st: if type == "string" then (if test("^[A-Z_]{1,32}$") then . else "INVALID" end) else null end;
    ($c | resolve($f; $now; $win)) as $s
    | ($c | if type == "object" then (.state | st) else null end) as $cs
    | ($c | if type == "object" then (.status | st) else null end) as $cst
    | {cycle: $cycle, derived_at: $ts, stale_hours: ($win / 3600), file_authoritative: ($fa == 1),
       state: $s, cache_state: $cs, cache_status: $cst,
       cache: (if $cache_ok == 0 then "unparseable" elif $c == null then "missing" else "present" end),
       drift: ($c != null and ($cs != $s or ($cst != null and $cst != $s))),
       notes: ([
         (if $cs != null and $cst != null and $cs != $cst then "cache .state \($cs) and .status \($cst) disagree" else empty end),
         (if $s == "JACKED_OUT" and ($f.all_complete | not) then "JACKED_OUT is terminal: files show incomplete sprints; the cache is kept" else empty end),
         (if $s == "COMPLETE" and ($f.all_complete | not) then "COMPLETE kept: no new incomplete sprint in the ledger" else empty end),
         ($f.sprints[] | select(.stale_marker) | "sprint-\(.global_id): COMPLETED marker names another sprint (stale_marker, not counted)"),
         ($f.sprints[] | select(.state == "awaiting_marker") | "sprint-\(.global_id): review and audit APPROVED, no COMPLETED marker")
       ]),
       sprints: $f.sprints,
       active_sprint: (if $ag == "" then null else "sprint-\($ag)" end),
       breaker: {state: $b.state, cycle_count: $b.triggers.cycle_count.current, same_issue: $b.triggers.same_issue.count,
                 no_progress: $b.triggers.no_progress.count, recomputed: {cycle_count: $rc.cycle, same_issue: $rc.same, no_progress: $rc.np}},
       derivation: {source: "files", stale_markers: $f.stale_markers, legacy_feedback: $f.legacy_feedback},
       written: false}')

  if (( write )); then
    local why=""
    if (( fa == 0 )); then why="run_mode.file_authoritative: false — report-only"
    elif [[ ! -f "$file" ]]; then why="no run state at $file — nothing to rewrite"
    elif (( cache_ok == 0 )); then why="$file unparseable — kept for inspection, not rewritten"
    fi
    if [[ -z "$why" ]]; then
      atomic_update "$breaker" --argjson rc "$rc" --argjson th "$th" --arg ts "$now_ts" "$JQ_DEFS"' merge_breaker($rc; $th; $ts)' || return 3
      merged=$(jq -c . "$breaker")
      facts=$(jq -c --argjson b "$merged" '.breaker_open = ($b.state == "OPEN")' <<<"$facts")
      atomic_update "$file" --argjson f "$facts" --argjson now "$now" --argjson win "$win" --arg ts "$now_ts" "$JQ_DEFS"'
        resolve($f; $now; $win) as $s
        | .state = $s | .status = $s | .derived_at = $ts
        | .derivation = {source: "files", stale_markers: $f.stale_markers, legacy_feedback: $f.legacy_feedback, sprint_ids: $f.sprint_ids}
        | .schema_version = (.schema_version // 2)' || return 3
      report=$(jq -c --slurpfile c "$file" --argjson b "$merged" '.written = true | .state = $c[0].state | .breaker.state = $b.state' <<<"$report")
    else
      report=$(jq -c --arg w "$why" '.notes += [$w]' <<<"$report")
    fi
  fi

  if (( json )); then
    jq . <<<"$report"
  else
    jq -r '"derive: files say \(.state), cache said \(.cache_state // "nothing") (\(if .drift then "drift" else "in sync" end))"
           + (if .written then " — caches rewritten" else "" end), (.notes[] | "  note: " + .)' <<<"$report"
  fi
  return 0
}

cmd_record_round() {
  [[ -n "$gate" && -n "$file" ]] || usage
  if [[ ! -f "$file" ]]; then echo "run-checkpoint: record-round: no feedback file at $file" >&2; return 2; fi
  local p th ts now out trip
  p=$(fb_parse "$file" "$gate")
  if [[ "$(jq -r '.approved' <<<"$p")" == true ]]; then
    echo "recorded: $gate APPROVED — breaker counters unchanged"
    return 0
  fi
  th=$(jq -nc --argjson s "$(cfg_int '.run_mode.circuit_breaker.same_issue_threshold' 3 1000)" \
              --argjson n "$(cfg_int '.run_mode.circuit_breaker.no_progress_threshold' 5 1000)" \
              --argjson c "$(cfg_int '.run_mode.defaults.max_cycles' 20 10000)" \
              --argjson h "$(cfg_int '.run_mode.defaults.timeout_hours' 8 8760)" \
              '{same: $s, np: $n, cycles: $c, hours: $h}')
  ts=$(now_iso); now=$(date +%s)
  atomic_update "$breaker" --argjson p "$p" --argjson th "$th" --arg ts "$ts" --argjson now "$now" \
      --arg gate "$gate" --arg sprint "$sprint" "$JQ_DEFS"'
    (if type == "object" and (.triggers | type) == "object" then . else skeleton($th; $ts) end)
    | ($p.counts | tojson) as $c
    | (if $p.hash != "none" and $p.hash == (.triggers.same_issue.last_hash // null)
       then .triggers.same_issue.count = ((.triggers.same_issue.count // 0) + 1)
       else .triggers.same_issue.count = 1 | .triggers.same_issue.last_hash = $p.hash end)
    | (if (.triggers.no_progress.last_counts // null) != null and .triggers.no_progress.last_counts == $c
       then .triggers.no_progress.count = ((.triggers.no_progress.count // 0) + 1)
       else .triggers.no_progress.count = 0 end)
    | .triggers.no_progress.last_counts = $c
    | .triggers.cycle_count.current = ((.triggers.cycle_count.current // 0) + 1)
    | (.triggers.timeout.started // null | epoch) as $start
    | ( if .triggers.same_issue.count >= (.triggers.same_issue.threshold // $th.same)
          then ["same_issue", "same issue hash \($p.hash[0:8]) seen \(.triggers.same_issue.count) times in a row"]
        elif .triggers.no_progress.count >= (.triggers.no_progress.threshold // $th.np)
          then ["no_progress", "finding counts unchanged for \(.triggers.no_progress.count) consecutive rounds"]
        elif .triggers.cycle_count.current >= (.triggers.cycle_count.limit // $th.cycles)
          then ["cycle_count", "\(.triggers.cycle_count.current) changes-required rounds reached the limit \(.triggers.cycle_count.limit // $th.cycles)"]
        elif $start != null and ($now - $start) >= ((.triggers.timeout.limit_hours // $th.hours) * 3600)
          then ["timeout", "run older than \(.triggers.timeout.limit_hours // $th.hours) hours"]
        elif (.state // "CLOSED") == "OPEN" then ["open", "breaker already OPEN"]
        else null end ) as $trip
    | .last_round = {gate: $gate, sprint: (if $sprint == "" then null else $sprint end), verdict: $p.verdict, hash: $p.hash, ts: $ts}
    | if $trip != null and $trip[0] != "open" and (.state // "CLOSED") != "OPEN"
      then .state = "OPEN" | .history = ((.history // []) + [{timestamp: $ts, trigger: $trip[0], reason: $trip[1], gate: $gate, sprint: (if $sprint == "" then null else $sprint end)}])
      elif $trip != null then .state = "OPEN"
      else .state = (.state // "CLOSED") end
    | .last_trip = $trip' || return 3
  trip=$(jq -r '.last_trip // empty | if type == "array" then "\(.[0]): \(.[1])" else empty end' "$breaker")
  out=$(jq -r '"recorded: \(.last_round.gate) \(.last_round.verdict // "no verdict") — cycle \(.triggers.cycle_count.current)/\(.triggers.cycle_count.limit), same_issue \(.triggers.same_issue.count)/\(.triggers.same_issue.threshold), no_progress \(.triggers.no_progress.count)/\(.triggers.no_progress.threshold)"' "$breaker")
  echo "$out"
  if [[ -n "$trip" ]]; then
    atomic_update "$state_file" --arg ts "$ts" '.state = "HALTED"' || return 3
    echo "TRIPPED: $trip"
    return 10
  fi
  return 0
}

cmd_mark() {
  [[ -n "$skill" && -n "$sprint" ]] || usage
  mkdir -p "$run_dir"
  atomic_update "$run_dir/implement-active.json" --arg k "$skill" --arg s "$sprint" --arg ts "$(now_iso)" \
    '{skill: $k, sprint: $s, started_at: $ts}' || return 3
  if [[ -f "$file" ]]; then
    local err drc=0
    err=$( { write=1; json=0; cmd_derive >/dev/null; } 2>&1 ) || drc=$?
    if (( drc != 0 && drc != 4 )); then printf '%s\n' "$err" >&2; fi
  fi
  echo "marked: $skill $sprint ($run_dir/implement-active.json)"
}

case "$sub" in
  write)  cmd_write ;;
  read)   cmd_read ;;
  derive) cmd_derive ;;
  record-round) cmd_record_round ;;
  mark)   cmd_mark ;;
  unmark) rm -f -- "$run_dir/implement-active.json" "$run_dir/implement-active.json.lock"; echo "unmarked" ;;
  *) usage ;;
esac
