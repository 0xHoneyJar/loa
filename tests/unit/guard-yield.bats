#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# =============================================================================
# tests/unit/guard-yield.bats — cycle-129 Sprint 1 (PRD FR-1 AC-1.2 … AC-1.4,
# SDD D-1.3, D-1.4)
# guard-yield.sh over a fixture audit log and a rotated segment, at a fixed
# --now: replay exclusion (flag, cwd, burst) counted in the header, the
# likely-false-positive heuristic (heredoc, outside-repo cwd, prose class without
# a destructive verb at statement start), day-granular last_real_catch, the
# --check drift gate (0 after generation, 1 after an origin edit, 0 after a
# yield-only change), the --json shape, and no command text or cwd in any output.
# =============================================================================

NOW="2026-10-14T12:00:00Z"

setup() {
  export LOA_AUDIT_REPLAY=1
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
  GY="$ROOT/.claude/scripts/guard-yield.sh"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/gyield.XXXXXX")"
  T="$(cd "$T" && pwd -P)"
  mkdir -p "$T/run" "$T/scratch"
  # A temp prefix the fixture controls (the script's own mktemp also uses it).
  export TMPDIR="$T"
  cp "$ROOT/.claude/data/guard-origins.yaml" "$T/origins.yaml"
  cp "$ROOT/.claude/loa/reference/hooks-reference.md" "$T/hooks-reference.md"
  A="$T/audit.jsonl"
  row() {  # ts pattern cwd command [extra-json]
    jq -cn --arg ts "$1" --arg p "$2" --arg cwd "$3" --arg c "$4" --argjson x "${5:-{\}}" \
      '{ts: $ts, tool: "Bash", command: $c, exit_code: 2, cwd: $cwd, model: "claude-test-model", hook: "block-destructive-bash", action: "block", pattern_id: $p, matched: "m"} + $x'
  }
  {
    # live, inside the repo
    row "2026-10-12T08:00:00Z" "FR-SZ2-REDIR" "$ROOT" "cat > .claude/x.md <<'EOF'"$'\n'"hello"$'\n'"EOF"   # complete non-executing heredoc → likely FP (FR-6 classifier via lib/heredoc-classifier.sh)
    row "2026-10-12T09:00:00Z" "P2" "/srv/elsewhere/scratch" "git push --force origin topic"    # outside repo → likely FP
    row "2026-10-12T10:00:00Z" "SP-1" "$ROOT" "br comments add bd-1 'note about spike/x merge'" # prose class, no verb → likely FP
    row "2026-10-13T23:59:00Z" "FR-2-AMBIGUOUS" "$ROOT" "cd sub && rm -rf ./.cache"             # prose class WITH verb → real
    # replays
    row "2026-10-11T08:00:00Z" "P3" "$ROOT" "git reset --hard HEAD~1" '{"replay": true}'        # flag
    row "2026-10-11T09:00:00Z" "P3" "$T/scratch" "git reset --hard HEAD~2"                       # cwd under TMPDIR
    row "2026-10-11T10:00:00Z" "P3" "/home/u/bats-run-42/repo" "git reset --hard HEAD~3"        # cwd /bats-run-
    for s in 00 01 02 03 04 05 06 07 08 09; do                                                  # burst: 10 in one minute
      row "2026-10-09T10:00:${s}Z" "P2" "$ROOT" "git push --force origin main"
    done
    # outside the window
    row "2026-08-01T08:00:00Z" "P3" "$ROOT" "git reset --hard HEAD~9"
    # implement-gate telemetry and ask
    jq -cn '{ts: "2026-10-12T11:00:00Z", hook: "implement-gate", action: "telemetry", cwd: "x"}'
    jq -cn '{ts: "2026-10-12T11:05:00Z", hook: "implement-gate", action: "ask", cwd: "x"}'
    # a non-block row and an unparseable line
    jq -cn '{ts: "2026-10-12T11:10:00Z", tool: "Bash", command: "ls", cwd: "x"}'
    printf 'this is not json\n'
  } > "$A"
  # the rotated segment holds the one real P3 catch
  row "2026-10-10T09:00:00Z" "P3" "$ROOT" "git reset --hard HEAD~3" > "$A.1"
  ARGS=(--now "$NOW" --audit-log "$A" --origins "$T/origins.yaml" --out "$T/guards.md" --yield-dir "$T/run" --hooks-ref "$T/hooks-reference.md")
}
teardown() { find "$T" -mindepth 1 -delete 2>/dev/null || true; rmdir "$T" 2>/dev/null || true; }

g() { jq -c --arg id "$1" '.guards[] | select(.id == $id) | [.blocks_30d, .likely_fp_30d, .telemetry_30d, .last_real_catch]' "$T/run/guard-yield.json"; }

@test "GY-1 replay rows are excluded by flag, cwd and burst and counted in the header; the window and bad rows are honoured" {
  run bash "$GY" "${ARGS[@]}"
  [ "$status" -eq 0 ] || { echo "$output" >&2; false; }
  J="$T/run/guard-yield.json"
  [ "$(jq '.audit_segments' "$J")" = "2" ]
  [ "$(jq '.audit_rows_considered' "$J")" = "20" ]
  [ "$(jq '.replay_rows_excluded' "$J")" = "13" ]
  [ "$(jq -c '.replay_rows_by_rule' "$J")" = '{"flag":1,"cwd":2,"burst":10}' ]
  [ "$(jq '.audit_rows_unparseable' "$J")" = "1" ]
  # the FR-SZ2-REDIR row is a real block since audit r256-4 (System-Zone target), so 3 real / 2 likely FP
  [ "$(jq -c '.totals | [.blocks_30d, .real_blocks_30d, .likely_fp_30d, .telemetry_30d]' "$J")" = '[5,3,2,2]' ]
  [ "$(jq -r '.scope' "$J")" = "host" ]
  [ "$(jq -r '.window_days' "$J")" = "30" ]
}

@test "GY-2 the rotated segment is read: its real P3 catch is counted and is the guard's last_real_catch" {
  run bash "$GY" "${ARGS[@]}"
  [ "$status" -eq 0 ]
  [ "$(g fence:P3)" = '[1,0,0,"2026-10-10"]' ]
}

@test "GY-3 scratch-path and prose-class blocks classify as likely false positives; a prose class with a destructive verb is real; a System-Zone block is real whatever its heredoc body" {
  run bash "$GY" "${ARGS[@]}"
  [ "$status" -eq 0 ]
  # FR-SZ2-REDIR: a prose heredoc into .claude/ is the hazard SZ2 exists for (audit r256-4 MEDIUM-A2)
  [ "$(g fence:FR-SZ2-REDIR)" = '[1,0,0,"2026-10-12"]' ]
  [ "$(g fence:P2)" = '[1,1,0,"none in window"]' ]
  [ "$(g fence:SP-1)" = '[1,1,0,"none in window"]' ]
  [ "$(g fence:FR-2-AMBIGUOUS)" = '[1,0,0,"2026-10-13"]' ]
  [ "$(g hook:safety/block-destructive-bash.sh)" = '[5,2,0,"2026-10-13"]' ]
}

@test "GY-4 last_real_catch and generated_at are day-granular; telemetry counts implement-gate rows; non-writers show n/a" {
  run bash "$GY" "${ARGS[@]}"
  [ "$status" -eq 0 ]
  J="$T/run/guard-yield.json"
  [ "$(jq -r '.generated_at' "$J")" = "2026-10-14" ]
  [ -z "$(jq -r '.guards[].last_real_catch' "$J" | grep -vE '^([0-9]{4}-[0-9]{2}-[0-9]{2}|none in window|n/a)$' || true)" ]
  [ "$(g gate:implement-gate)" = '[0,0,2,"none in window"]' ]
  [ "$(g hook:compliance/implement-gate.sh)" = '[0,0,2,"none in window"]' ]
  [ "$(g hook:safety/zone-write-guard.sh)" = '[null,null,null,"n/a"]' ]
  grep -qE '^\| hook:safety/zone-write-guard.sh \|.*\| n/a \| n/a \| n/a \| n/a \|$' "$T/run/guard-yield.md"
}

@test "GY-5 no command text, cwd, hostname or model name reaches guards.md, the yield files or the hooks table" {
  run bash "$GY" "${ARGS[@]}" --hooks-table
  [ "$status" -eq 0 ]
  # the hooks reference documents fence commands in its own prose; only the generated block is checked
  awk '/^<!-- guard-register:begin -->$/,/^<!-- guard-register:end -->$/' "$T/hooks-reference.md" > "$T/hooks-block.md"
  [ -s "$T/hooks-block.md" ]
  for f in "$T/guards.md" "$T/run/guard-yield.md" "$T/run/guard-yield.json" "$T/hooks-block.md"; do
    for needle in "reset --hard" "push --force" "rm -rf" "spike/x merge" "<<'EOF'" "/srv/elsewhere" "bats-run-42" "$T" "claude-test-model" "$(hostname)"; do
      if grep -qF -- "$needle" "$f"; then echo "$f leaks '$needle'" >&2; false; fi
    done
  done
}

@test "GY-6 guards.md is structural: header counts, one table per kind, no timestamp, and identical whatever the audit log holds" {
  run bash "$GY" "${ARGS[@]}"
  [ "$status" -eq 0 ]
  n="$(yq '.guards | length' "$T/origins.yaml")"
  grep -qx -- "- guards: $n" "$T/guards.md"
  grep -qx -- "- guards_without_origin: 0" "$T/guards.md"
  grep -qx -- "- dormant: 3" "$T/guards.md"
  for k in hook fence validator gate policy; do grep -qE "^## $k \([0-9]+\)$" "$T/guards.md"; done
  [ "$(grep -cE '^\| (hook|fence|validator|gate|policy):' "$T/guards.md")" -eq "$n" ]
  ! grep -qE '20[0-9]{2}-[0-9]{2}-[0-9]{2}T|generated_at' "$T/guards.md"
  cp "$T/guards.md" "$T/guards.first"
  : > "$A"; rm -f "$A.1"
  run bash "$GY" "${ARGS[@]}"
  [ "$status" -eq 0 ]
  cmp "$T/guards.first" "$T/guards.md"
}

@test "GY-7 --check exits 0 after generation, 1 after an origin edit (with the regenerate hint), 0 after a yield-only change" {
  run bash "$GY" "${ARGS[@]}" --hooks-table
  [ "$status" -eq 0 ]
  run bash "$GY" "${ARGS[@]}" --check
  [ "$status" -eq 0 ]
  # yield-only change: more audit rows, regenerate the yield; the structure is untouched
  jq -cn '{ts: "2026-10-14T08:00:00Z", hook: "block-destructive-bash", action: "block", pattern_id: "P4", cwd: "/x", command: "git clean -fd"}' >> "$A"
  run bash "$GY" "${ARGS[@]}"
  [ "$status" -eq 0 ]
  run bash "$GY" "${ARGS[@]}" --check
  [ "$status" -eq 0 ]
  # origin edit
  yq -i '(.guards[] | select(.id == "fence:P3") | .origin.ref) = "cycle-011 edited"' "$T/origins.yaml"
  run bash "$GY" "${ARGS[@]}" --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"drift"*"guards.md"* ]]
  [[ "$output" == *"regenerate: .claude/scripts/guard-yield.sh --hooks-table"* ]]
  # a purpose edit drifts the hooks table too
  run bash "$GY" "${ARGS[@]}"
  yq -i '(.guards[] | select(.id == "hook:safety/notes-size-guard.sh") | .note) = "edited purpose"' "$T/origins.yaml"
  run bash "$GY" "${ARGS[@]}" --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"guard-register table"* ]]
}

@test "GY-8 --hooks-table writes one row per registration between the markers, including the six hooks the hand table omitted" {
  run bash "$GY" "${ARGS[@]}" --hooks-table
  [ "$status" -eq 0 ]
  block="$(awk '/^<!-- guard-register:begin -->$/,/^<!-- guard-register:end -->$/' "$T/hooks-reference.md")"
  regs="$(jq '[.hooks | to_entries[] | .value[] | .hooks[]] | length' "$ROOT/.claude/settings.json")"
  [ "$(grep -E '^\| [A-Za-z]+ \|' <<<"$block" | grep -cv '^| Event |')" -eq "$regs" ]
  for s in safety/zone-write-guard.sh safety/spiral-dispatch-guard.sh safety/spiral-skill-sentinel.sh safety/adversarial-review-gate.sh quality/karpathy-surgical-diff-check.sh scripts/upgrade-health-check.sh scripts/permission-audit.sh; do
    grep -qF "$s" <<<"$block" || { echo "hooks table misses $s" >&2; false; }
  done
  grep -qE '^\| PreToolUse \| Bash \| `hook-guard.sh safety/team-role-guard.sh` \| dormant \| LOA_TEAM_MEMBER \|' <<<"$block"
  grep -qE '^\| PreToolUse \| Write\\\|Edit\\\|MultiEdit\\\|NotebookEdit \|' <<<"$block"
}

@test "GY-9 --json prints the yield object (header, totals and one row per guard)" {
  run --separate-stderr bash "$GY" "${ARGS[@]}" --json
  [ "$status" -eq 0 ]
  n="$(yq '.guards | length' "$T/origins.yaml")"
  jq -e --argjson n "$n" '
    (keys | contains(["schema_version","generated_at","window_days","scope","audit_segments","audit_rows_considered","replay_rows_excluded","replay_rows_by_rule","heuristic","totals","guards"]))
    and (.guards | length) == $n
    and all(.guards[]; has("id") and has("class") and has("status") and has("origin") and has("knob") and has("floor") and has("registrations") and has("blocks_30d") and has("likely_fp_30d") and has("telemetry_30d") and has("last_real_catch"))
    and (.totals | has("real_blocks_30d") and has("likely_fp_30d"))' <<<"$output" >/dev/null
}

@test "GY-10 a missing audit log is a WARN and an empty yield (exit 0); a missing origin row is exit 5" {
  run bash "$GY" --now "$NOW" --audit-log "$T/none.jsonl" --origins "$T/origins.yaml" --out "$T/guards.md" --yield-dir "$T/run"
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN: no audit log"* ]]
  [ "$(jq '.audit_rows_considered + .totals.blocks_30d' "$T/run/guard-yield.json")" = "0" ]
  yq -i 'del(.guards[] | select(.id == "hook:safety/notes-size-guard.sh"))' "$T/origins.yaml"
  run bash "$GY" "${ARGS[@]}"
  [ "$status" -eq 5 ]
  [[ "$output" == *"guard hook:safety/notes-size-guard.sh has no origin row"* ]]
}

@test "GY-11 a 10,000-row audit log is joined in under 10 seconds" {
  jq -cn --arg r "$ROOT" 'range(10000) | {ts: "2026-10-12T08:\(. % 60 | tostring | if length == 1 then "0" + . else . end):00Z", hook: "block-destructive-bash", action: (if . % 2 == 0 then "block" else "allow-marker" end), pattern_id: "P2", cwd: $r, command: "git push --force origin b\(.)"}' > "$A"
  rm -f "$A.1"
  start=$(date +%s)
  run bash "$GY" "${ARGS[@]}"
  [ "$status" -eq 0 ]
  [ $(( $(date +%s) - start )) -lt 10 ]
}
