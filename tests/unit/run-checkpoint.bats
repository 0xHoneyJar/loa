#!/usr/bin/env bats
# =============================================================================
# tests/unit/run-checkpoint.bats — cycle-125 Sprint 3 (PRD FR-3 AC 2, SDD D-3.2)
# .claude/scripts/run-checkpoint.sh write/read: atomic, locked, schema_version 2,
# beads-validated (stub `br` on PATH), schema 1 readers keep sprint granularity.
# =============================================================================

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  CK="$PROJECT_ROOT/.claude/scripts/run-checkpoint.sh"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/ck.XXXXXX")"
  mkdir -p "$T/.run" "$T/bin"
  F="$T/.run/sprint-plan-state.json"
  printf '{"plan_id":"p","state":"RUNNING","timestamps":{"started":"2026-09-23T00:00:00Z","last_activity":"2026-09-23T00:00:00Z"},"sprints":{"total":2,"completed":0,"current":"sprint-1","list":[{"id":"sprint-1","status":"in_progress"},{"id":"sprint-2","status":"pending"}]}}\n' > "$F"
  # stub br: `br show <id> --json` answers from $T/beads/<id>
  mkdir -p "$T/beads"
  cat > "$T/bin/br" <<EOF
#!/usr/bin/env bash
[[ "\$1" == "show" ]] || exit 1
id="\$2"; [[ -f "$T/beads/\$id" ]] || { echo "not found" >&2; exit 1; }
printf '{"id":"%s","status":"%s"}\n' "\$id" "\$(cat "$T/beads/\$id")"
EOF
  chmod +x "$T/bin/br"
  export PATH="$T/bin:$PATH"
}
teardown() { find "$T" -mindepth 1 -delete 2>/dev/null || true; rmdir "$T" 2>/dev/null || true; }

@test "CK-1 write sets schema_version 2, checkpoint {sprint,task,phase,ts} and last_activity; the rest of the state is untouched; no tmp or lock residue" {
  run bash "$CK" write --file "$F" --sprint sprint-1 --task bd-aaaa --phase IMPLEMENT
  [ "$status" -eq 0 ]
  jq -e '.schema_version==2 and .checkpoint.sprint=="sprint-1" and .checkpoint.task=="bd-aaaa" and .checkpoint.phase=="IMPLEMENT" and (.checkpoint.ts|test("^2026")) and .timestamps.last_activity==.checkpoint.ts and .plan_id=="p" and .sprints.total==2' "$F" >/dev/null
  [ -z "$(ls "$T/.run" | grep -E 'tmp\.')" ]
}

@test "CK-2 read: closed task → trustworthy checkpoint; open or unknown task → discarded with a logged line and the beads-truth pointer" {
  bash "$CK" write --file "$F" --sprint sprint-1 --task bd-aaaa --phase IMPLEMENT
  echo closed > "$T/beads/bd-aaaa"
  run bash "$CK" read --file "$F"
  [ "$status" -eq 0 ]
  [[ "$output" == "checkpoint: sprint-1 task bd-aaaa phase IMPLEMENT at 2026"* ]]
  run bash "$CK" read --file "$F" --json
  echo "$output" | jq -e '.checkpoint.task=="bd-aaaa"' >/dev/null
  echo open > "$T/beads/bd-aaaa"
  run bash "$CK" read --file "$F"
  [ "$status" -eq 0 ]
  [[ "$output" == *"discarding checkpoint (task bd-aaaa is not closed in beads)"* ]]
  [[ "$output" == *"resume at the first open bead of sprint-1"* ]]
  rm "$T/beads/bd-aaaa"
  run bash "$CK" read --file "$F" --json
  echo "$output" | tail -n1 | jq -e '.checkpoint==null and (.reason|test("not closed"))' >/dev/null
  [[ "$output" == *"discarding checkpoint"* ]]
}

@test "CK-2b with no br on PATH a task checkpoint is NOT trusted (unverifiable → discarded); a phase-only checkpoint still is" {
  bash "$CK" write --file "$F" --sprint sprint-1 --task bd-aaaa --phase IMPLEMENT
  echo closed > "$T/beads/bd-aaaa"
  run env PATH="/usr/bin:/bin" bash "$CK" read --file "$F" --json
  [ "$status" -eq 0 ]
  echo "$output" | tail -n1 | jq -e '.checkpoint==null and (.reason|test("beads unavailable"))' >/dev/null
  bash "$CK" write --file "$F" --sprint sprint-1 --phase REVIEW
  run env PATH="/usr/bin:/bin" bash "$CK" read --file "$F" --json
  echo "$output" | tail -n1 | jq -e '.checkpoint.phase=="REVIEW" and .checkpoint.task==null' >/dev/null
}

@test "CK-3 a phase-only checkpoint (no task) is trusted without consulting beads; schema 1 / no checkpoint reads as sprint granularity" {
  bash "$CK" write --file "$F" --sprint sprint-1 --phase REVIEW
  run bash "$CK" read --file "$F"
  [[ "$output" == "checkpoint: sprint-1 phase REVIEW at 2026"* ]]
  printf '{"plan_id":"p","state":"RUNNING","sprints":{"current":"sprint-1"}}\n' > "$F"
  run bash "$CK" read --file "$F"
  [ "$status" -eq 0 ]
  [[ "$output" == *"sprint granularity"* ]]
  run bash "$CK" read --file "$F" --json
  echo "$output" | jq -e '.checkpoint==null and .reason=="sprint granularity"' >/dev/null
}

@test "CK-4 write refuses when there is no run (exit 2) and never replaces a file with unparseable output (exit 3, file intact)" {
  run bash "$CK" write --file "$T/.run/nope.json" --sprint sprint-1 --phase IMPLEMENT
  [ "$status" -eq 2 ]
  printf 'not json' > "$F"
  run bash "$CK" write --file "$F" --sprint sprint-1 --phase IMPLEMENT
  [ "$status" -eq 3 ]
  [ "$(cat "$F")" = "not json" ]
  run bash "$CK" read --file "$F"
  [ "$status" -eq 0 ]
  [[ "$output" == *"unparseable"* ]]
}

@test "CK-5 concurrent writes serialise under the lock: the file stays valid JSON and holds the last writer" {
  for i in $(seq 1 12); do bash "$CK" write --file "$F" --sprint sprint-1 --task "bd-$i" --phase IMPLEMENT & done
  wait
  jq -e '.schema_version==2 and (.checkpoint.task|test("^bd-[0-9]+$"))' "$F" >/dev/null
  [ -z "$(ls "$T/.run" | grep -E 'tmp\.')" ]
}

@test "CK-6 usage: bad ids, phases and missing values exit 2" {
  run bash "$CK" write --file "$F" --sprint 'sprint 1' --phase IMPLEMENT; [ "$status" -eq 2 ]
  run bash "$CK" write --file "$F" --sprint sprint-1 --phase implement; [ "$status" -eq 2 ]
  run bash "$CK" write --file "$F" --sprint sprint-1; [ "$status" -eq 2 ]
  run bash "$CK" bogus; [ "$status" -eq 2 ]
}
