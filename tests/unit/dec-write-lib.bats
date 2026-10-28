#!/usr/bin/env bats
# =============================================================================
# dec-write-lib.bats: the decision-ledger writer (.claude/scripts/lib/dec-write-lib.sh).
#
# Hermetic: every test copies the writer, its validator and compat-lib into a fresh temp project
# (its own git repo and .run), so the host's run state, the live ledger and the operator's session
# never leak in. The live grimoires/loa/decisions.yaml of this repository is never written.
# Seams: the CLI (subcommands, exit codes) and the ledger file after each operation.
# =============================================================================

# An empty ledger carrying the tracked file's header only: fixtures never inherit live rows
# (the live ledger is seeded in the main checkout).
empty_ledger(){ { sed '/^schema_version:/,$d' "$1"; printf 'schema_version: 1\ndecisions: []\n'; } > "$2"; }

setup() {
  BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO="$(cd "$BATS_TEST_DIR/../.." && pwd)"
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
  command -v yq >/dev/null 2>&1 || skip "yq not installed"
  [[ "$(yq --version 2>&1)" == *mikefarah*"version v4."* ]] || skip "Mike Farah yq v4 not installed"
  unset CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID LOA_UNATTENDED LOA_FLATLINE_MODE CI GITHUB_ACTIONS \
        LOA_HOOK_CONTEXT LOA_DEC_NO_FLOCK LOA_DEC_LOCK_WAIT
  T="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$T/.claude/scripts/lib" "$T/grimoires/loa"
  cp "$REPO/.claude/scripts/lib/dec-write-lib.sh" "$T/.claude/scripts/lib/"
  cp "$REPO/.claude/scripts/compat-lib.sh" "$REPO/.claude/scripts/validate-artifact.sh" "$T/.claude/scripts/"
  [[ -f "$REPO/.claude/scripts/pii-filter.sh" ]] && cp "$REPO/.claude/scripts/pii-filter.sh" "$T/.claude/scripts/"
  empty_ledger "$REPO/grimoires/loa/decisions.yaml" "$T/grimoires/loa/decisions.yaml"
  git -C "$T" init -q
  D="$T/.claude/scripts/lib/dec-write-lib.sh"
  L="$T/grimoires/loa/decisions.yaml"
  F="$T/fixture.yaml"
  cp "$L" "$F"
  ALT='{"option":"keep sequential","rejected_because":"one question per turn is slow"}'
}

# Same transformation as the writer's san1() (kf-write-lib.sh's), used to state expected values.
DEC_ULB_RE="$(printf '\302[\200-\237]|\342\200[\250\251]')"
san1(){ printf '%s' "${1-}" | LC_ALL=C tr -d '\000-\010\013\014\016-\037\177' | LC_ALL=C tr '\t\n\r' '   ' | LC_ALL=C sed -E "s/${DEC_ULB_RE}/ /g"' ; s/  +/ /g; s/^ //; s/ $//'; }

# new_open FILE [extra args]  -> an open row
new_open(){ local f="$1"; shift; bash "$D" new --file "$f" --summary "an open question" --phase discovery --category scope --recorded-by plan-and-analyze --source "prd.md#fr-1" --quiet "$@"; }
# new_prop FILE [extra args]  -> a proposed row
new_prop(){ local f="$1"; shift; bash "$D" new --file "$f" --summary "rounds is the thorough default" --phase discovery --category scope --recorded-by plan-and-analyze --source "prd.md#e (D1)" --status proposed --decision "pacing rounds" --rationale "brief recommendation" --alternative-json "$ALT" --cycle cycle-128 --quiet "$@"; }
field(){ yq -o=json -I0 '.' "$1" | jq -r --arg id "$2" ".decisions[] | select(.id == \$id) | $3"; }
ids(){ yq -o=json -I0 '.' "$1" | jq -r '[.decisions[].id] | join(",")'; }
confirm_op(){ bash "$D" confirm --recorded-by decisions-command --evidence "cli:2026-10-13T12:00:00Z" --quiet "$@"; }
lockpath(){ # target -> the writer's lock path
  local abs; abs="$(cd "$(dirname "$1")" && pwd -P)/$(basename "$1")"
  # shellcheck source=/dev/null
  ( source "$REPO/.claude/scripts/compat-lib.sh"; printf '%s/.run/.dec-write-%s.lock' "$(cd "$T" && pwd -P)" "$(printf '%s' "$abs" | sha256_portable | cut -c1-12)" )
}
# A PATH holding every command of the current PATH except $1 (the tool reads as absent).
path_without(){
  local tool="$1" d="$BATS_TEST_TMPDIR/pw-$1" p f b
  mkdir -p "$d"
  local IFS=:
  local -a batch
  for p in $PATH; do
    [[ -d "$p" ]] || continue
    batch=()
    for f in "$p"/*; do b="${f##*/}"; [[ "$b" == "$tool" || -e "$d/$b" ]] && continue; batch+=("$f"); done
    # one ln per PATH dir instead of one per file; names are unique within a dir, so the -e test above is the first-wins rule
    (( ${#batch[@]} )) && { ln -s -- "${batch[@]}" "$d/" 2>/dev/null || true; }
  done
  printf '%s' "$d"
}

# ---- ids, growth, verify-before-swap ------------------------------------------------

@test "dec-write new: ids allocate max+1 and print DEC-%04d" {
  run new_open "$F"; [ "$status" -eq 0 ]; [ "$output" = "DEC-0001" ]
  run new_prop "$F"; [ "$status" -eq 0 ]; [ "$output" = "DEC-0002" ]
  # a gap: max+1 from the highest id, never a reused or lower one
  yq -i '.decisions[1].id = "DEC-0007" | .decisions[1].supersedes = null' "$F"
  run new_open "$F"; [ "$status" -eq 0 ]; [ "$output" = "DEC-0008" ]
  [ "$(ids "$F")" = "DEC-0001,DEC-0007,DEC-0008" ]
}

@test "dec-write: the ledger never shrinks and never drops an id across every operation" {
  new_open "$F" >/dev/null; new_prop "$F" >/dev/null; new_open "$F" >/dev/null
  local before; before="$(ids "$F")"
  bash "$D" decide --file "$F" --id DEC-0001 --decision d --rationale r --alternative-json "$ALT" --evidence "interview turn 3" --recorded-by x --quiet
  confirm_op --file "$F" --id DEC-0002
  bash "$D" reject --file "$F" --id DEC-0003 --rationale "out of scope" --follow-up bd-abcd --recorded-by x --quiet
  run bash "$D" supersede --file "$F" --id DEC-0002 --summary "a newer take" --phase discovery --category scope --recorded-by x --source s2 --decision d2 --rationale r2 --alternative-json "$ALT" --quiet
  [ "$status" -eq 0 ]
  [ "$(ids "$F")" = "${before},DEC-0004" ]
  [ "$(yq '.decisions | length' "$F")" -eq 4 ]
}

@test "dec-write: a failed write leaves the previous file byte-identical (validation refuses the candidate)" {
  new_open "$F" >/dev/null
  # plant a row the validator refuses (a URL in free text), as a hand edit would
  yq -i '.decisions[0].summary = "see https://example.com"' "$F"
  cp "$F" "$BATS_TEST_TMPDIR/before.yaml"
  run new_open "$F"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ledger untouched"* ]]
  cmp "$F" "$BATS_TEST_TMPDIR/before.yaml"
  # no temp file is left beside the target
  [ -z "$(find "$T" -maxdepth 1 -name 'fixture.yaml.*')" ]
}

@test "dec-write: an unknown schema_version is refused before any write" {
  yq -i '.schema_version = 2' "$F"; cp "$F" "$BATS_TEST_TMPDIR/before.yaml"
  run new_open "$F"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown schema_version"* ]]
  cmp "$F" "$BATS_TEST_TMPDIR/before.yaml"
}

@test "dec-write: the header comment survives a write (yq keeps the head comment)" {
  new_prop "$F" >/dev/null
  grep -q '^# grimoires/loa/decisions.yaml: the decision ledger' "$F"
  grep -q '^schema_version: 1' "$F"
}

@test "dec-write: ids come from the target file only; a populated live ledger does not shift a fresh --file fixture" {
  # a throwaway "live" ledger with rows, at the project's live path
  local i; for i in 1 2 3 4 5; do bash "$D" new --summary "live row $i" --phase discovery --category scope --recorded-by x --source s --quiet >/dev/null; done
  [ "$(yq '.decisions | length' "$L")" -eq 5 ]
  # and a populated ledger at another path
  cp "$L" "$BATS_TEST_TMPDIR/other.yaml"
  empty_ledger "$REPO/grimoires/loa/decisions.yaml" "$BATS_TEST_TMPDIR/fresh.yaml"
  run bash "$D" new --file "$BATS_TEST_TMPDIR/fresh.yaml" --summary s --phase discovery --category scope --recorded-by x --source s --quiet
  [ "$status" -eq 0 ]; [ "$output" = "DEC-0001" ]
  run bash "$D" list --file "$BATS_TEST_TMPDIR/fresh.yaml" --format json
  [ "$(printf '%s' "$output" | jq 'length')" -eq 1 ]
  # the live ledger continues from its own max
  run bash "$D" new --summary "live row 6" --phase discovery --category scope --recorded-by x --source s --quiet
  [ "$output" = "DEC-0006" ]
  [ "$(yq '.decisions | length' "$BATS_TEST_TMPDIR/other.yaml")" -eq 5 ]
}

# ---- required fields, transitions, operator-only ops ----------------------------------

@test "dec-write: decide and confirm without --evidence, reject without --rationale or --follow-up exit non-zero" {
  new_open "$F" >/dev/null; new_prop "$F" >/dev/null
  run bash "$D" decide --file "$F" --id DEC-0001 --decision d --rationale r --alternative-json "$ALT" --recorded-by x
  [ "$status" -ne 0 ]; [[ "$output" == *"--evidence is required"* ]]
  run bash "$D" confirm --file "$F" --id DEC-0002 --recorded-by decisions-command
  [ "$status" -ne 0 ]; [[ "$output" == *"--evidence is required"* ]]
  run bash "$D" reject --file "$F" --id DEC-0002 --rationale "no" --recorded-by x
  [ "$status" -ne 0 ]; [[ "$output" == *"--follow-up is required"* ]]
  run bash "$D" reject --file "$F" --id DEC-0002 --follow-up bd-x --recorded-by x
  [ "$status" -ne 0 ]; [[ "$output" == *"--rationale is required"* ]]
  [ "$(field "$F" DEC-0001 .status)" = "open" ]; [ "$(field "$F" DEC-0002 .status)" = "proposed" ]
}

@test "dec-write: a proposed row needs a decision, a rationale and an alternative" {
  run bash "$D" new --file "$F" --summary s --phase discovery --category scope --recorded-by x --source src --status proposed --decision d
  [ "$status" -eq 1 ]; [[ "$output" == *"needs --decision, --rationale and at least one --alternative-json"* ]]
  run bash "$D" new --file "$F" --summary s --phase discovery --category scope --recorded-by x --source src --status decided
  [ "$status" -eq 2 ]
  [ "$(yq '.decisions | length' "$F")" -eq 0 ]
}

@test "dec-write: every write lands open or proposed and decided_by stays null" {
  new_open "$F" >/dev/null; new_prop "$F" >/dev/null
  [ "$(field "$F" DEC-0001 '.status + "|" + (.decided_by|tostring) + "|" + .proposed_by')" = "open|null|agent" ]
  [ "$(field "$F" DEC-0002 '.status + "|" + (.decided_by|tostring) + "|" + .proposed_by')" = "proposed|null|agent" ]
  [ "$(field "$F" DEC-0002 '.transitions[0] | "\(.from)>\(.to) \(.by)"')" = "null>proposed agent:plan-and-analyze" ]
}

@test "dec-write decide: open -> proposed appends one transition and sets the decide fields once" {
  new_open "$F" >/dev/null
  run bash "$D" decide --file "$F" --id DEC-0001 --decision "use yq v4" --rationale "env() keeps values out of expressions" --alternative-json "$ALT" --evidence "sdd D-3.3" --recorded-by designing-architecture
  [ "$status" -eq 0 ]
  [ "$(field "$F" DEC-0001 '.status')" = "proposed" ]
  [ "$(field "$F" DEC-0001 '.transitions | length')" -eq 2 ]
  [ "$(field "$F" DEC-0001 '.transitions[1] | "\(.from)>\(.to) \(.evidence)"')" = "open>proposed sdd D-3.3" ]
  run bash "$D" decide --file "$F" --id DEC-0001 --decision x --rationale y --alternative-json "$ALT" --evidence e --recorded-by x
  [ "$status" -eq 1 ]; [[ "$output" == *"not open (illegal transition)"* ]]
}

@test "dec-write confirm: only --recorded-by decisions-command may confirm" {
  new_prop "$F" >/dev/null
  run bash "$D" confirm --file "$F" --id DEC-0001 --recorded-by plan-and-analyze --evidence "cli:2026-10-13T12:00:00Z"
  [ "$status" -eq 1 ]; [[ "$output" == *"only from the operator-only /decisions command"* ]]
  [ "$(field "$F" DEC-0001 .status)" = "proposed" ]
}

@test "dec-write confirm: an operator-kind ref makes decided_by operator; without one decided_by is the proposing voice" {
  new_prop "$F" >/dev/null; new_prop "$F" >/dev/null
  run confirm_op --file "$F" --id DEC-0001 --answer-ref "cli:2026-10-13T12:00:00Z"
  [ "$status" -eq 0 ]
  [ "$(field "$F" DEC-0001 '.status + "|" + .decided_by + "|" + .decided_by_ref')" = "decided|operator|cli:2026-10-13T12:00:00Z" ]
  [ "$(field "$F" DEC-0001 '.transitions[-1].by')" = "operator:decisions-command" ]
  run confirm_op --file "$F" --id DEC-0002
  [ "$status" -eq 0 ]
  [ "$(field "$F" DEC-0002 '.status + "|" + .decided_by')" = "decided|agent" ]
}

@test "dec-write confirm --cycle: two matches refuse without --all; --all confirms both" {
  new_prop "$F" >/dev/null; new_prop "$F" >/dev/null; new_prop "$F" --cycle other >/dev/null
  run confirm_op --file "$F" --cycle cycle-128
  [ "$status" -eq 1 ]
  [[ "$output" == *"DEC-0001"* && "$output" == *"DEC-0002"* && "$output" == *"pass --all"* ]]
  [ "$(field "$F" DEC-0001 .status)" = "proposed" ]
  run confirm_op --file "$F" --cycle cycle-128 --all
  [ "$status" -eq 0 ]
  [ "$(field "$F" DEC-0001 .status)$(field "$F" DEC-0002 .status)$(field "$F" DEC-0003 .status)" = "decideddecidedproposed" ]
}

@test "dec-write reject: open/proposed -> rejected records rejection_rationale, follow_up and prior requests" {
  new_prop "$F" >/dev/null
  run bash "$D" reject --file "$F" --id DEC-0001 --rationale "the operator wants sequential" --follow-up "bd-1234" --prior-request "issue 12" --recorded-by run-mode
  [ "$status" -eq 0 ]
  [ "$(field "$F" DEC-0001 '.status + "|" + .rejection_rationale + "|" + .follow_up + "|" + (.prior_requests|join(","))')" = "rejected|the operator wants sequential|bd-1234|issue 12" ]
  [ "$(field "$F" DEC-0001 '.transitions[-1] | "\(.from)>\(.to) \(.by)"')" = "proposed>rejected agent:run-mode" ]
}

@test "dec-write reject: an agent cannot reject a decided row; the operator command can" {
  new_prop "$F" >/dev/null; confirm_op --file "$F" --id DEC-0001
  run bash "$D" reject --file "$F" --id DEC-0001 --rationale r --follow-up bd-x --recorded-by run-mode
  [ "$status" -eq 1 ]; [[ "$output" == *"supersede --id DEC-0001"* ]]
  [ "$(field "$F" DEC-0001 .status)" = "decided" ]
  run bash "$D" reject --file "$F" --id DEC-0001 --rationale r --follow-up bd-x --recorded-by decisions-command
  [ "$status" -eq 0 ]
  [ "$(field "$F" DEC-0001 '.status + "|" + .transitions[-1].by')" = "rejected|operator:decisions-command" ]
}

@test "dec-write supersede (agent): the new row is proposed, the old stays decided with supersede_proposed_by; confirming the new row supersedes the old" {
  new_prop "$F" >/dev/null; confirm_op --file "$F" --id DEC-0001
  run bash "$D" supersede --file "$F" --id DEC-0001 --summary "batch is the default" --phase discovery --category scope --recorded-by run-mode --source "pr 9" --decision batch --rationale "fewer turns" --alternative-json "$ALT"
  [ "$status" -eq 0 ]; [[ "$output" == *"DEC-0002"* ]]
  [ "$(field "$F" DEC-0001 '.status + "|" + .supersede_proposed_by')" = "decided|DEC-0002" ]
  [ "$(field "$F" DEC-0002 '.status + "|" + .supersedes')" = "proposed|DEC-0001" ]
  run bash "$D" supersede --file "$F" --id DEC-0001 --summary "again" --phase discovery --category scope --recorded-by run-mode --source s --decision d --rationale r --alternative-json "$ALT"
  [ "$status" -eq 1 ]; [[ "$output" == *"already proposed"* ]]
  run confirm_op --file "$F" --id DEC-0002
  [ "$status" -eq 0 ]
  [ "$(field "$F" DEC-0001 '.status + "|" + .transitions[-1].by')" = "superseded|operator:decisions-command" ]
  [ "$(field "$F" DEC-0002 .status)" = "decided" ]
  [ "$(ids "$F")" = "DEC-0001,DEC-0002" ]
}

@test "dec-write supersede (operator): the old row moves to superseded and nothing is removed" {
  new_prop "$F" >/dev/null; confirm_op --file "$F" --id DEC-0001
  run bash "$D" supersede --file "$F" --id DEC-0001 --summary "batch" --phase discovery --category scope --recorded-by decisions-command --source s --decision d --rationale r --alternative-json "$ALT"
  [ "$status" -eq 0 ]
  [ "$(field "$F" DEC-0001 .status)" = "superseded" ]
  [ "$(field "$F" DEC-0002 '.status + "|" + .supersedes')" = "proposed|DEC-0001" ]
  [ "$(yq '.decisions | length' "$F")" -eq 2 ]
  run bash "$D" supersede --file "$F" --id DEC-0002 --summary x --phase discovery --category scope --recorded-by x --source s --decision d --rationale r --alternative-json "$ALT"
  [ "$status" -eq 1 ]; [[ "$output" == *"only a decided row is superseded"* ]]
}

# ---- derived attribution: refs, voices, artifacts, unattended signals -----------------

@test "dec-write: a ref outside the grammar is refused" {
  run new_prop "$F" --answer-ref "trust me"
  [ "$status" -eq 1 ]; [[ "$output" == *"ref grammar"* ]]
  run new_prop "$F" --answer-ref "session:4f2a#turn-12"
  [ "$status" -eq 0 ]
  [ "$(field "$F" DEC-0001 .decided_by_ref)" = "session:4f2a#turn-12" ]
  [ "$(field "$F" DEC-0001 '.decided_by|tostring')" = "null" ]
}

@test "dec-write --as flatline: a missing artifact is refused; an existing one is hashed into evidence_sha256" {
  run new_prop "$F" --as flatline --answer-ref "flatline:.flatline/runs/nope.json"
  [ "$status" -eq 1 ]; [[ "$output" == *"artifact not found"* ]]
  mkdir -p "$T/.flatline/runs"; printf '{"phase":"prd","consensus":[]}\n' > "$T/.flatline/runs/r1.json"
  run new_prop "$F" --as flatline --answer-ref "flatline:.flatline/runs/r1.json"
  [ "$status" -eq 0 ]
  local want; want="$(source "$REPO/.claude/scripts/compat-lib.sh"; sha256_portable "$T/.flatline/runs/r1.json" | cut -d' ' -f1)"
  [ "$(field "$F" DEC-0001 '.proposed_by + "|" + .evidence_sha256')" = "flatline|${want}" ]
  # the record is checkable: a changed artifact fails validation
  printf '{"phase":"prd","consensus":["edited"]}\n' > "$T/.flatline/runs/r1.json"
  run bash "$T/.claude/scripts/validate-artifact.sh" --type decisions --file "$F"
  [ "$status" -eq 1 ]; [[ "$output" == *"not the recorded evidence_sha256"* ]]
}

@test "dec-write --as dissent: the artifact must be an a2a adversarial-*.json" {
  mkdir -p "$T/grimoires/loa/a2a/sprint-1"; printf '{"findings":[]}\n' > "$T/grimoires/loa/a2a/sprint-1/adversarial-review.json"
  printf '{}\n' > "$T/grimoires/loa/a2a/sprint-1/other.json"
  run new_prop "$F" --as dissent --answer-ref "dissent:grimoires/loa/a2a/sprint-1/other.json"
  [ "$status" -eq 1 ]
  run new_prop "$F" --as dissent --answer-ref "dissent:grimoires/loa/a2a/sprint-1/adversarial-review.json"
  [ "$status" -eq 0 ]
  [ "$(field "$F" DEC-0001 .proposed_by)" = "dissent" ]
}

# Each unattended signal forces proposed + proposed_by agent, ignoring --answer-ref and --as.
assert_unattended_write(){
  mkdir -p "$T/.flatline/runs"; printf '{"phase":"prd"}\n' > "$T/.flatline/runs/r1.json"
  run "$@" bash "$D" new --file "$F" --summary "taken unattended" --phase discovery --category scope --recorded-by run-mode --source "prd.md#x" \
      --decision d --rationale r --alternative-json "$ALT" --answer-ref "session:abc#turn-1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"unattended context: --answer-ref ignored"* ]]
  local id; id="$(printf '%s\n' "$output" | grep -E '^DEC-' | tail -1)"
  [ "$(field "$F" "$id" '.status + "|" + .proposed_by + "|" + (.decided_by|tostring) + "|" + (.decided_by_ref|tostring)')" = "proposed|agent|null|null" ]
  run "$@" bash "$D" new --file "$F" --summary "flatline voice" --phase discovery --category scope --recorded-by run-mode --source s \
      --decision d --rationale r --alternative-json "$ALT" --as flatline --answer-ref "flatline:.flatline/runs/r1.json"
  [ "$status" -eq 0 ]
  id="$(printf '%s\n' "$output" | grep -E '^DEC-' | tail -1)"
  [ "$(field "$F" "$id" '.proposed_by + "|" + (.evidence_sha256|tostring)')" = "agent|null" ]
}

@test "dec-write unattended: a RUNNING sprint-plan-state.json forces proposed/agent" {
  mkdir -p "$T/.run"; printf '{"state":"RUNNING"}\n' > "$T/.run/sprint-plan-state.json"
  assert_unattended_write env
}

@test "dec-write unattended: a RUNNING .run/state.json forces proposed/agent" {
  mkdir -p "$T/.run"; printf '{"state":"RUNNING"}\n' > "$T/.run/state.json"
  assert_unattended_write env
}

@test "dec-write unattended: a fresh .run/unattended.json forces proposed/agent" {
  run bash "$D" context --set-unattended --reason "autonomous run" --quiet
  [ "$status" -eq 0 ]; [ "$output" = "unattended" ]
  assert_unattended_write env
}

@test "dec-write unattended: LOA_UNATTENDED=1 forces proposed/agent" {
  assert_unattended_write env LOA_UNATTENDED=1
}

@test "dec-write unattended: LOA_FLATLINE_MODE=autonomous forces proposed/agent" {
  assert_unattended_write env LOA_FLATLINE_MODE=autonomous
}

@test "dec-write unattended: a PRD Status line naming an autonomous run forces proposed/agent" {
  printf '# PRD\n\n**Date:** 2026-10-13\n**Status:** Draft, autonomous run\n' > "$T/grimoires/loa/prd.md"
  assert_unattended_write env
}

@test "dec-write unattended: the default status is proposed; an explicit --status open stays open" {
  run env LOA_UNATTENDED=1 bash "$D" new --file "$F" --summary q --phase discovery --category scope --recorded-by x --source s --decision d --rationale r --alternative-json "$ALT" --quiet
  [ "$status" -eq 0 ]; [ "$(field "$F" DEC-0001 .status)" = "proposed" ]
  run env LOA_UNATTENDED=1 bash "$D" new --file "$F" --summary q --phase discovery --category scope --recorded-by x --source s --status open --quiet
  [ "$status" -eq 0 ]; [ "$(field "$F" DEC-0002 .status)" = "open" ]
}

@test "dec-write context: a stale marker (other session or past the TTL) is ignored" {
  mkdir -p "$T/.run"
  printf '{"reason":"r","session_id":"other","created_at":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$T/.run/unattended.json"
  run env CLAUDE_SESSION_ID=mine bash "$D" context --why
  [ "$status" -eq 0 ]; [[ "${lines[0]}" == "interactive" ]]; [[ "$output" == *"stale marker ignored"* ]]
  printf '{"reason":"r","session_id":"mine","created_at":"2020-01-01T00:00:00Z"}\n' > "$T/.run/unattended.json"
  run env CLAUDE_SESSION_ID=mine bash "$D" context
  [ "$output" = "interactive" ]
  printf '{"reason":"r","session_id":"mine","created_at":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$T/.run/unattended.json"
  run env CLAUDE_SESSION_ID=mine bash "$D" context
  [ "$output" = "unattended" ]
}

@test "dec-write context --clear runs only from the operator command" {
  bash "$D" context --set-unattended --reason r --quiet >/dev/null
  run bash "$D" context --clear --recorded-by run-mode
  [ "$status" -eq 1 ]; [ -f "$T/.run/unattended.json" ]
  run bash "$D" context --clear --recorded-by decisions-command --quiet
  [ "$status" -eq 0 ]; [ ! -f "$T/.run/unattended.json" ]; [ "$output" = "interactive" ]
}

@test "dec-write confirm: refused under a live-run signal; the PRD Status line alone does not block it" {
  new_prop "$F" >/dev/null; new_prop "$F" >/dev/null
  run env LOA_UNATTENDED=1 bash "$D" confirm --file "$F" --id DEC-0001 --recorded-by decisions-command --evidence "cli:2026-10-13T12:00:00Z"
  [ "$status" -eq 1 ]; [[ "$output" == *"live-run signal"* ]]
  mkdir -p "$T/.run"; printf '{"state":"RUNNING"}\n' > "$T/.run/sprint-plan-state.json"
  run confirm_op --file "$F" --id DEC-0001
  [ "$status" -eq 1 ]
  rm -f "$T/.run/sprint-plan-state.json"
  printf '**Status:** Draft, autonomous run\n' > "$T/grimoires/loa/prd.md"
  run confirm_op --file "$F" --id DEC-0002
  [ "$status" -eq 0 ]
  [ "$(field "$F" DEC-0001 .status)$(field "$F" DEC-0002 .status)" = "proposeddecided" ]
}

# ---- single writer: CI/hook refusal, worktree pending file, import --------------------

@test "dec-write: CI, GITHUB_ACTIONS and LOA_HOOK_CONTEXT=1 make a live-ledger write exit 1; --file fixtures still run" {
  cp "$L" "$BATS_TEST_TMPDIR/live-before.yaml"
  local v
  for v in CI=1 GITHUB_ACTIONS=true LOA_HOOK_CONTEXT=1; do
    run env "$v" bash "$D" new --summary s --phase discovery --category scope --recorded-by x --source s
    [ "$status" -eq 1 ]; [[ "$output" == *"never written from CI or a hook"* ]]
  done
  cmp "$L" "$BATS_TEST_TMPDIR/live-before.yaml"
  run env CI=1 bash "$D" new --file "$F" --summary s --phase discovery --category scope --recorded-by x --source s --quiet
  [ "$status" -eq 0 ]; [ "$output" = "DEC-0001" ]
}

@test "dec-write: under CI, GITHUB_ACTIONS or LOA_HOOK_CONTEXT, --file naming the live ledger or a pending file (relative or absolute) is refused; a temp fixture is allowed" {
  mkdir -p "$T/grimoires/loa/a2a/sprint-252"
  empty_ledger "$REPO/grimoires/loa/decisions.yaml" "$T/grimoires/loa/a2a/sprint-252/decisions-pending.yaml"
  cp "$L" "$BATS_TEST_TMPDIR/live-before.yaml"
  local v tgt
  for v in CI=1 GITHUB_ACTIONS=1 LOA_HOOK_CONTEXT=1; do
    for tgt in "$L" "grimoires/loa/decisions.yaml" "./grimoires/loa/../loa/decisions.yaml" "$T/grimoires/loa/a2a/sprint-252/decisions-pending.yaml" "grimoires/loa/a2a/sprint-252/decisions-pending.yaml"; do
      run bash -c 'cd "$1" && shift && env "$@"' _ "$T" "$v" bash "$D" new --file "$tgt" --summary s --phase discovery --category scope --recorded-by x --source s
      [ "$status" -eq 1 ] || { echo "$v --file $tgt: status $status: $output"; return 1; }
      [[ "$output" == *"never written from CI or a hook"* ]]
    done
    run env "$v" bash "$D" new --file "$F" --summary s --phase discovery --category scope --recorded-by x --source s --quiet
    [ "$status" -eq 0 ]
  done
  cmp "$L" "$BATS_TEST_TMPDIR/live-before.yaml"
  [ "$(yq '.decisions | length' "$T/grimoires/loa/a2a/sprint-252/decisions-pending.yaml")" -eq 0 ]
  # import into the live ledger by --file is refused under CI too, and leaves the pending file in place
  run env -u CI bash "$D" new --pending --sprint 252 --summary p --phase discovery --category scope --recorded-by x --source s --quiet
  [ "$status" -eq 0 ]
  local P="$T/grimoires/loa/a2a/sprint-252/decisions-pending.yaml"
  run env CI=1 bash "$D" import --from "$P" --file "$L"
  [ "$status" -eq 1 ]; [[ "$output" == *"never written from CI or a hook"* ]]
  [ -f "$P" ]; cmp "$L" "$BATS_TEST_TMPDIR/live-before.yaml"
  # without CI, --file naming the live ledger is the live kind (DEC ids, normal verify)
  run bash -c 'cd "$1" && bash "$2" new --file grimoires/loa/decisions.yaml --summary s --phase discovery --category scope --recorded-by x --source s --quiet' _ "$T" "$D"
  [ "$status" -eq 0 ]; [ "$output" = "DEC-0001" ]
}

@test "dec-write: in a linked worktree, --file naming a live ledger is refused (worktrees write the pending file)" {
  git -C "$T" add -A
  git -C "$T" -c core.hooksPath=/dev/null -c user.email=t@t -c user.name=t commit -qm fixture
  git -C "$T" worktree add -q "$T/wt" -b wt-file
  local WD="$T/wt/.claude/scripts/lib/dec-write-lib.sh"
  run bash "$WD" new --file "$T/wt/grimoires/loa/decisions.yaml" --summary s --phase discovery --category scope --recorded-by x --source s
  [ "$status" -eq 1 ]; [[ "$output" == *"linked worktree"* ]]
  run bash "$WD" new --file "$T/grimoires/loa/decisions.yaml" --summary s --phase discovery --category scope --recorded-by x --source s
  [ "$status" -eq 1 ]; [[ "$output" == *"linked worktree"* ]]
  [ "$(yq '.decisions | length' "$L")" -eq 0 ]
}

@test "dec-write: the live ledger in the main checkout gets DEC ids; --pending writes the sprint pending file" {
  run bash "$D" new --summary s --phase discovery --category scope --recorded-by x --source s --quiet
  [ "$status" -eq 0 ]; [ "$output" = "DEC-0001" ]
  run bash "$D" new --pending --sprint 252 --summary s --phase discovery --category scope --recorded-by x --source s --quiet
  [ "$status" -eq 0 ]; [[ "$output" =~ ^PEND-[0-9a-f]{8}$ ]]
  [ "$(yq '.decisions[0].id' "$T/grimoires/loa/a2a/sprint-252/decisions-pending.yaml")" = "$output" ]
  [ "$(yq '.decisions | length' "$L")" -eq 1 ]
}

@test "dec-write: a linked worktree writes PEND rows to the pending file; import in the main checkout allocates ids, rewrites refs and deletes the file" {
  git -C "$T" add -A
  git -C "$T" -c core.hooksPath=/dev/null -c user.email=t@t -c user.name=t commit -qm fixture
  bash "$D" new --summary "already here" --phase discovery --category scope --recorded-by x --source s --quiet >/dev/null
  git -C "$T" worktree add -q "$T/wt" -b wt-test
  local WD="$T/wt/.claude/scripts/lib/dec-write-lib.sh"
  run bash "$WD" new --sprint 252 --summary "from the worktree" --phase implementation --category scope --recorded-by implementing-tasks --source "src/x.sh:10" --quiet
  [ "$status" -eq 0 ]; [[ "$output" =~ ^PEND-[0-9a-f]{8}$ ]]; local p1="$output"
  run bash "$WD" new --sprint 252 --summary "refers to ${p1}" --phase implementation --category scope --recorded-by implementing-tasks --source "src/y.sh:2" --quiet
  [ "$status" -eq 0 ]; local p2="$output"
  local P="$T/wt/grimoires/loa/a2a/sprint-252/decisions-pending.yaml"
  [ -f "$P" ]; [ "$(yq '.decisions | length' "$P")" -eq 2 ]
  [ "$(yq '.decisions | length' "$T/wt/grimoires/loa/decisions.yaml")" -eq 0 ]
  run bash "$WD" import --from "$P"
  [ "$status" -eq 1 ]; [[ "$output" == *"main checkout"* ]]
  printf 'NOTES: see %s and %s\n' "$p1" "$p2" > "$T/notes.md"
  run bash "$D" import --from "$P" --rewrite "$T/notes.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$p1 DEC-0002"* && "$output" == *"$p2 DEC-0003"* ]]
  [ ! -f "$P" ]
  [ "$(ids "$L")" = "DEC-0001,DEC-0002,DEC-0003" ]
  [ "$(field "$L" DEC-0003 .summary)" = "refers to DEC-0002" ]
  [ "$(cat "$T/notes.md")" = "NOTES: see DEC-0002 and DEC-0003" ]
  run bash "$T/.claude/scripts/validate-artifact.sh" --type decisions --file "$L"
  [ "$status" -eq 0 ]
}

@test "dec-write import: --rewrite targets outside the project, with '..', symlinks or missing files are refused before any write" {
  run bash "$D" new --pending --sprint 252 --summary p --phase discovery --category scope --recorded-by x --source s --quiet
  [ "$status" -eq 0 ]; local pid="$output"
  local P="$T/grimoires/loa/a2a/sprint-252/decisions-pending.yaml"
  printf 'see %s\n' "$pid" > "$BATS_TEST_TMPDIR/outside.md"
  printf 'see %s\n' "$pid" > "$T/inside.md"
  ln -s "$BATS_TEST_TMPDIR/outside.md" "$T/link.md"
  cp "$L" "$BATS_TEST_TMPDIR/live-before.yaml"
  local bad
  for bad in "$BATS_TEST_TMPDIR/outside.md" "$T/grimoires/../inside.md" "$T/link.md" "$T/missing.md"; do
    run bash "$D" import --from "$P" --rewrite "$bad"
    [ "$status" -eq 1 ] || { echo "--rewrite $bad: status $status: $output"; return 1; }
    [[ "$output" == *"--rewrite"* ]]
  done
  cmp "$L" "$BATS_TEST_TMPDIR/live-before.yaml"; [ -f "$P" ]
  [ "$(cat "$BATS_TEST_TMPDIR/outside.md")" = "see $pid" ]
  run bash "$D" import --from "$P" --rewrite "$T/inside.md"
  [ "$status" -eq 0 ]
  [ "$(cat "$T/inside.md")" = "see DEC-0001" ]
}

# ---- lock --------------------------------------------------------------------------

@test "dec-write: a held flock makes a second writer exit 1 and leaves the file intact" {
  command -v flock >/dev/null 2>&1 || skip "flock not installed"
  mkdir -p "$T/.run"; local lp; lp="$(lockpath "$F")"
  ( exec 9>"$lp"; flock 9; sleep 6 ) &
  local holder=$!
  sleep 0.5
  cp "$F" "$BATS_TEST_TMPDIR/before.yaml"
  run env LOA_DEC_LOCK_WAIT=1 bash "$D" new --file "$F" --summary s --phase discovery --category scope --recorded-by x --source s
  kill "$holder" 2>/dev/null || true; wait "$holder" 2>/dev/null || true
  [ "$status" -eq 1 ]; [[ "$output" == *"lock busy"* ]]
  cmp "$F" "$BATS_TEST_TMPDIR/before.yaml"
}

@test "dec-write: without flock the mkdir lock refuses a live holder and breaks a stale one" {
  mkdir -p "$T/.run"; local lp; lp="$(lockpath "$F")"
  mkdir "${lp}.d"; printf '%s\n' "$$" > "${lp}.d/pid"
  run env LOA_DEC_NO_FLOCK=1 LOA_DEC_LOCK_WAIT=1 bash "$D" new --file "$F" --summary s --phase discovery --category scope --recorded-by x --source s
  [ "$status" -eq 1 ]; [[ "$output" == *"lock busy"* ]]
  printf '999999\n' > "${lp}.d/pid"; touch -t 202001010000 "${lp}.d"
  run env LOA_DEC_NO_FLOCK=1 LOA_DEC_LOCK_WAIT=1 bash "$D" new --file "$F" --summary s --phase discovery --category scope --recorded-by x --source s --quiet
  [ "$status" -eq 0 ]; [ "$output" = "DEC-0001" ]
  [ ! -d "${lp}.d" ]
}

@test "dec-write: with flock absent from PATH the mkdir lock serialises writers" {
  mkdir -p "$T/.run"; local lp; lp="$(lockpath "$F")"
  local pf; pf="$(path_without flock)"
  mkdir "${lp}.d"; printf '%s\n' "$$" > "${lp}.d/pid"
  run env PATH="$pf" LOA_DEC_LOCK_WAIT=1 bash "$D" new --file "$F" --summary s --phase discovery --category scope --recorded-by x --source s
  [ "$status" -eq 1 ]; [[ "$output" == *"${lp}.d"* ]]
  rm -f "${lp}.d/pid"; rmdir "${lp}.d"
  run env PATH="$pf" bash "$D" new --file "$F" --summary s --phase discovery --category scope --recorded-by x --source s --quiet
  [ "$status" -eq 0 ]; [ "$output" = "DEC-0001" ]
  [ ! -d "${lp}.d" ]
}

# ---- preflight -------------------------------------------------------------------------

@test "dec-write preflight: a missing jq or a non-v4 yq fails closed; a missing br does not" {
  local pj; pj="$(path_without jq)"
  run env PATH="$pj" bash "$D" new --file "$F" --summary s --phase discovery --category scope --recorded-by x --source s
  [ "$status" -eq 1 ]; [[ "$output" == *"jq is required"* ]]
  local shim="$BATS_TEST_TMPDIR/shim"; mkdir -p "$shim"
  printf '#!/bin/sh\necho "yq 3.4.1"\n' > "$shim/yq"; chmod +x "$shim/yq"
  run env PATH="$shim:$PATH" bash "$D" new --file "$F" --summary s --phase discovery --category scope --recorded-by x --source s
  [ "$status" -eq 1 ]; [[ "$output" == *"not Mike Farah yq v4"* ]]
  [ "$(yq '.decisions | length' "$F")" -eq 0 ]
  local pb; pb="$(path_without br)"
  run env PATH="$pb" bash "$D" new --file "$F" --summary s --phase discovery --category scope --recorded-by x --source s --quiet
  [ "$status" -eq 0 ]; [ "$output" = "DEC-0001" ]
}

@test "dec-write: the 160-character summary limit counts characters, not bytes" {
  local cjk; cjk="$(printf '決%.0s' $(seq 1 150))"
  run bash "$D" new --file "$F" --summary "$cjk" --phase discovery --category scope --recorded-by x --source s --quiet
  [ "$status" -eq 0 ]
  run bash "$D" new --file "$F" --summary "$(printf 'a%.0s' $(seq 1 161))" --phase discovery --category scope --recorded-by x --source s --quiet
  [ "$status" -eq 1 ]; [[ "$output" == *"over 160 characters"* ]]
}

@test "dec-write: an unknown flag or command is a usage error (exit 2)" {
  run bash "$D" new --file "$F" --decided-by operator --summary s
  [ "$status" -eq 2 ]
  run bash "$D" frobnicate
  [ "$status" -eq 2 ]
  run bash "$D" new --file "$F" --summary s --phase nowhere --category scope --recorded-by x --source s
  [ "$status" -eq 2 ]
}

# ---- hostile-string corpus -------------------------------------------------------------

@test "dec-write: the hostile-string corpus round-trips byte-equal against the sanitised input" {
  local -a corpus=(
    'double "quoted" and single '"'"'quoted'"'"''
    'key: value with: colons'
    '# leading hash'
    'mid # hash'
    '-leading dash'
    '- leading dash and space'
    $'multiline\nevidence\r\nlines'
    '日本語のテキスト 😀 é (e + U+0301) مرحبا'
    $'ctl\x01\x07\x1b[31mred\x7f end'
    "$(printf 'c1\302\205nel and \342\200\250ls \342\200\251ps')"
    '!!binary' '!!str' '&anchor' '*alias' '<<: *x' '---' '...' 'null' '~' 'yes' '0x1F' '1e3'
  )
  local s i=0 id want alt
  for s in "${corpus[@]}"; do
    i=$((i + 1))
    alt="$(jq -cn --arg o "$s" --arg r "$s" '{option: $o, rejected_because: $r}')"
    run bash "$D" new --file "$F" --summary "$s" --phase discovery --category scope --recorded-by x --source "$s" \
        --status proposed --decision "$s" --rationale "$s" --alternative-json "$alt" --consequence-pos "$s" --evidence "$s" --quiet
    [ "$status" -eq 0 ] || { echo "corpus $i ($s): $output"; return 1; }
    id="$output"; want="$(san1 "$s")"
    local got
    for got in .summary .decision .rationale .source '.alternatives_considered[0].option' '.alternatives_considered[0].rejected_because' '.consequences.positive[0]' '.transitions[0].evidence'; do
      [ "$(yq -o=json -I0 '.' "$F" | jq -j --arg id "$id" ".decisions[] | select(.id == \$id) | $got")" = "$want" ] \
        || { echo "corpus $i field $got: want [$want]"; yq -o=json '.' "$F" | jq --arg id "$id" '.decisions[] | select(.id == $id)'; return 1; }
      [ "$(yq -o=json -I0 '.' "$F" | jq -r --arg id "$id" ".decisions[] | select(.id == \$id) | $got | type")" = "string" ]
    done
  done
  [ "$(yq '.decisions | length' "$F")" -eq "${#corpus[@]}" ]
  run bash "$T/.claude/scripts/validate-artifact.sh" --type decisions --file "$F"
  [ "$status" -eq 0 ]
}

# ---- list --------------------------------------------------------------------------------

@test "dec-write list: tsv, md (Voice column, confirm line) and json, filtered by status, voice and cycle" {
  new_prop "$F" >/dev/null; new_open "$F" >/dev/null; new_prop "$F" --cycle other >/dev/null
  confirm_op --file "$F" --id DEC-0003 --answer-ref "cli:2026-10-13T12:00:00Z"
  run bash "$D" list --file "$F"
  [ "$status" -eq 0 ]; [ "${#lines[@]}" -eq 3 ]
  [ "${lines[0]}" = "$(printf 'DEC-0001\tproposed\tagent\trounds is the thorough default\tprd.md#e (D1)')" ]
  run bash "$D" list --file "$F" --not-decided-by operator --cycle cycle-128 --format md
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "| Decision | Voice | Status | Why | Source |" ]
  [ "${lines[2]}" = "| rounds is the thorough default (DEC-0001) | agent | proposed | brief recommendation | prd.md#e (D1) |" ]
  [ "${lines[-1]}" = "Confirm with /decisions confirm." ]
  [[ "$output" != *"DEC-0003"* ]]
  run bash "$D" list --file "$F" --voice operator --format json
  [ "$(printf '%s' "$output" | jq -r '[.[].id] | join(",")')" = "DEC-0003" ]
  run bash "$D" list --file "$F" --status open --format json
  [ "$(printf '%s' "$output" | jq -r '[.[].id] | join(",")')" = "DEC-0002" ]
  run bash "$D" list --file "$F" --status decided --voice agent --format md
  [ "$output" = "_None: every decision in this run was the operator's._" ]
}

@test "dec-write: no skill grants the operator-only operations in allowed-tools" {
  run grep -rlE 'dec-write-lib\.sh[^"'"'"']*(confirm|supersede|context --clear)' "$REPO/.claude/skills" --include=SKILL.md
  [ "$status" -ne 0 ] || { echo "skills granting operator ops: $output"; return 1; }
}

@test "dec-write: /decisions is model-uninvocable and the only command or skill passing --recorded-by decisions-command" {
  local cmd="$REPO/.claude/commands/decisions.md"
  [ -f "$cmd" ]
  # frontmatter carries the flag
  awk 'NR == 1 && $0 != "---" { exit 1 } NR > 1 && /^---$/ { exit } NR > 1 { print }' "$cmd" | grep -qx 'disable-model-invocation: true'
  # the writer accepts operator operations only under this recorder; nothing else may pass it
  run grep -rlF -- '--recorded-by decisions-command' "$REPO/.claude/commands" "$REPO/.claude/skills"
  [ "$output" = "$cmd" ]
  grep -qE '"\$DW" confirm .*--recorded-by decisions-command' "$cmd"
  grep -qE '"\$DW" context --clear --recorded-by decisions-command' "$cmd"
}

@test "dec-write: the ledger is tracked: not ignored by git, any -v match is the negation, and the gitignore-state check is clean" {
  run git -C "$REPO" check-ignore -q grimoires/loa/decisions.yaml
  [ "$status" -eq 1 ]
  run git -C "$REPO" check-ignore -v grimoires/loa/decisions.yaml
  if [ -n "$output" ]; then [[ "$output" == *':!grimoires/loa/decisions.yaml'* ]]; fi
  run bash -c 'cd "$1" && bash .claude/scripts/validate-gitignore-state.sh' _ "$REPO"
  # exit 0 and no drift row for the ledger; unrelated WARN rows for other State-Zone
  # paths (e.g. an untracked .ck/ in a developer checkout) are not this test's concern
  [ "$status" -eq 0 ]; [[ "$output" != *"decisions.yaml"* ]]
}

# ---- the PRD Status line is a planning-time default, not a live signal (Bridgebuilder F-003) ----

@test "dec-write F-003: with only an autonomous PRD Status line, context is interactive and --why lists the PRD signal as advisory" {
  printf '# PRD\n\n**Status:** Draft, autonomous run\n' > "$T/grimoires/loa/prd.md"
  run bash "$D" context
  [ "$status" -eq 0 ]; [ "$output" = "interactive" ]
  run bash "$D" context --why
  [ "${lines[0]}" = "interactive" ]
  [[ "$output" == *"signal: prd prd-status:"*"(advisory: a planning-time default for new and decide only)"* ]]
  run env LOA_UNATTENDED=1 bash "$D" context
  [ "$output" = "unattended" ]
}

@test "dec-write F-003: under an autonomous PRD Status line, the operator's confirm --answer-ref records decided_by operator; reject and supersede of decided rows stay operator acts" {
  printf '# PRD\n\n**Status:** Draft, autonomous run\n' > "$T/grimoires/loa/prd.md"
  new_prop "$F" >/dev/null; new_prop "$F" >/dev/null; new_prop "$F" >/dev/null
  run confirm_op --file "$F" --id DEC-0001 --answer-ref "cli:2026-10-13T12:00:00Z"
  [ "$status" -eq 0 ]
  [[ "$output" != *"--answer-ref ignored"* ]]
  [ "$(field "$F" DEC-0001 '.decided_by + "|" + .decided_by_ref')" = "operator|cli:2026-10-13T12:00:00Z" ]
  confirm_op --file "$F" --id DEC-0002 --answer-ref "cli:2026-10-13T12:00:00Z"
  run bash "$D" reject --file "$F" --id DEC-0002 --rationale "the operator changed course" --follow-up bd-x --recorded-by decisions-command --quiet
  [ "$status" -eq 0 ]; [ "$(field "$F" DEC-0002 '.status + "|" + .transitions[-1].by')" = "rejected|operator:decisions-command" ]
  run bash "$D" supersede --file "$F" --id DEC-0001 --summary s2 --phase discovery --category scope --recorded-by decisions-command --source s --decision d --rationale r --alternative-json "$ALT" --quiet
  [ "$status" -eq 0 ]; [ "$(field "$F" DEC-0001 .status)" = "superseded" ]
}

@test "dec-write F-003: under a live signal the operator ops still refuse or downgrade as before" {
  new_prop "$F" >/dev/null; confirm_op --file "$F" --id DEC-0001 --answer-ref "cli:2026-10-13T12:00:00Z"
  new_prop "$F" >/dev/null
  run env LOA_UNATTENDED=1 bash "$D" confirm --file "$F" --id DEC-0002 --recorded-by decisions-command --evidence "cli:2026-10-13T12:00:00Z" --answer-ref "cli:2026-10-13T12:00:00Z"
  [ "$status" -eq 1 ]; [[ "$output" == *"live-run signal"* ]]
  run env LOA_UNATTENDED=1 bash "$D" reject --file "$F" --id DEC-0001 --rationale r --follow-up bd-x --recorded-by decisions-command
  [ "$status" -eq 1 ]; [[ "$output" == *"unattended"* ]]
  run env LOA_UNATTENDED=1 bash "$D" supersede --file "$F" --id DEC-0001 --summary s2 --phase discovery --category scope --recorded-by decisions-command --source s --decision d --rationale r --alternative-json "$ALT" --quiet
  [ "$status" -eq 0 ]
  [ "$(field "$F" DEC-0001 '.status + "|" + .supersede_proposed_by')" = "decided|DEC-0003" ]
}

@test "dec-write F-003: new and decide under an autonomous PRD Status line still land proposed and ignore refs" {
  printf '# PRD\n\n**Status:** Draft, unattended planning\n' > "$T/grimoires/loa/prd.md"
  run bash "$D" new --file "$F" --summary s --phase discovery --category scope --recorded-by plan-and-analyze --source "prd.md#x" \
      --decision d --rationale r --alternative-json "$ALT" --answer-ref "session:abc#turn-1"
  [ "$status" -eq 0 ]; [[ "$output" == *"--answer-ref ignored"* ]]
  [ "$(field "$F" DEC-0001 '.status + "|" + .proposed_by + "|" + (.decided_by_ref|tostring)')" = "proposed|agent|null" ]
  bash "$D" new --file "$F" --summary q --phase discovery --category scope --recorded-by x --source s --status open --quiet >/dev/null
  run bash "$D" decide --file "$F" --id DEC-0002 --decision d --rationale r --alternative-json "$ALT" --evidence e --recorded-by x --answer-ref "session:abc#turn-2"
  [ "$status" -eq 0 ]; [[ "$output" == *"--answer-ref ignored"* ]]
  [ "$(field "$F" DEC-0002 '.status + "|" + (.decided_by_ref|tostring)')" = "proposed|null" ]
}

# ---- LOA_PROJECT_ROOT (Bridgebuilder F-017) --------------------------------------------------

@test "dec-write F-017: LOA_PROJECT_ROOT points the context at another tree; an invalid one is a usage error" {
  local fx="$BATS_TEST_TMPDIR/fx"; mkdir -p "$fx/.run" "$fx/grimoires/loa"
  printf '{"state":"RUNNING"}\n' > "$fx/.run/state.json"
  run bash "$D" context
  [ "$output" = "interactive" ]
  run env LOA_PROJECT_ROOT="$fx" bash "$D" context --why
  [ "${lines[0]}" = "unattended" ]; [[ "$output" == *"run-state:$(cd "$fx" && pwd -P)/.run/state.json"* ]]
  run env LOA_PROJECT_ROOT="$BATS_TEST_TMPDIR/nope" bash "$D" context
  [ "$status" -eq 2 ]; [[ "$output" == *"LOA_PROJECT_ROOT is not a directory"* ]]
}
