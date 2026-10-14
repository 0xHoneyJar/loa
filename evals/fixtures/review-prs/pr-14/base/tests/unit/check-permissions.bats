#!/usr/bin/env bats
# =============================================================================
# tests/unit/check-permissions.bats — sprint-bug-246 (bead bd-n7v3, cycle-125
# sprint-243 review MEDIUM). check-permissions.sh (run preflight P2) must
# evaluate the settings layers Claude Code evaluates — ~/.claude/settings.json,
# .claude/settings.json, .claude/settings.local.json — as JSON arrays (never
# file text), let a deny rule in any layer win, keep the base-wildcard rule,
# and name the files it consulted. Every case runs against a temp --root and
# a temp HOME; the repository's settings files are never read.
# =============================================================================

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  CP="$PROJECT_ROOT/.claude/scripts/check-permissions.sh"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/cp.XXXXXX")"
  R="$T/root"
  mkdir -p "$R/.claude" "$T/home/.claude"
  export HOME="$T/home"
  REQ='["Bash(git checkout:*)","Bash(git commit:*)","Bash(git push:*)","Bash(git branch:*)","Bash(git add:*)","Bash(git status:*)","Bash(git diff:*)","Bash(git rev-parse:*)","Bash(git show-ref:*)","Bash(gh:*)","Bash(gh pr:*)","Bash(mkdir:*)","Bash(rm:*)","Bash(cp:*)","Bash(mv:*)","Bash(bash:*)"]'
  PROJ="$R/.claude/settings.json"; LOCAL="$R/.claude/settings.local.json"; USERF="$HOME/.claude/settings.json"
}
teardown() { find "$T" -mindepth 1 -delete 2>/dev/null || true; rmdir "$T" 2>/dev/null || true; }

settings() {  # settings <file> <allow-json-array> <deny-json-array>
  jq -nc --argjson a "$2" --argjson d "$3" '{permissions:{allow:$a,deny:$d}}' > "$1"
}

@test "CP-1 all required rules in .claude/settings.json → exit 0; --json lists the consulted file and 16 found" {
  settings "$PROJ" "$REQ" '[]'
  run bash "$CP" --root "$R" --quiet
  [ "$status" -eq 0 ]
  run bash "$CP" --root "$R" --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.success == true and .total_required == 16 and .total_found == 16 and .total_missing == 0 and (.denied|length) == 0' >/dev/null
  echo "$output" | jq -e --arg p "$PROJ" '.settings_files | index($p) != null' >/dev/null
}

@test "CP-2 rules only in .claude/settings.local.json are effective (Claude Code merges the local file over the shared one)" {
  settings "$PROJ" '[]' '[]'
  settings "$LOCAL" "$REQ" '[]'
  run bash "$CP" --root "$R" --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.success == true and .total_found == 16' >/dev/null
  echo "$output" | jq -e --arg p "$LOCAL" '.settings_files | index($p) != null' >/dev/null
}

@test "CP-3 rules only in ~/.claude/settings.json are effective (user-level allow rules apply to every project)" {
  settings "$USERF" "$REQ" '[]'
  run bash "$CP" --root "$R" --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.success == true and .total_found == 16' >/dev/null
  echo "$output" | jq -e --arg p "$USERF" '.settings_files | index($p) != null' >/dev/null
}

@test "CP-4 a pattern that appears only inside a deny array is never counted as found — it is reported as denied" {
  settings "$PROJ" '[]' '["Bash(rm:*)"]'
  run bash "$CP" --root "$R" --json
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '(.found | index("Bash(rm:*)")) == null and .success == false and ([.denied[].rule] | index("Bash(rm:*)")) != null' >/dev/null
}

@test "CP-5 a deny rule in any layer wins over an allow rule in any layer: exit 1, the rule is listed under denied with the denying file" {
  settings "$PROJ" "$REQ" '[]'
  settings "$LOCAL" '[]' '["Bash(git push:*)"]'
  run bash "$CP" --root "$R" --json
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.success == false and .total_denied == 1 and (.denied[0].rule == "Bash(git push:*)") and (.denied[0].by == "Bash(git push:*)")' >/dev/null
  echo "$output" | jq -e --arg p "$LOCAL" '.denied[0].file == $p' >/dev/null
  run bash "$CP" --root "$R"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Denied"* && "$output" == *"Bash(git push:*)"* && "$output" == *"settings.local.json"* ]]
  # the same deny in the user file
  settings "$LOCAL" '[]' '[]'
  settings "$USERF" '[]' '["Bash(git push:*)"]'
  run bash "$CP" --root "$R" --json
  [ "$status" -eq 1 ]
  echo "$output" | jq -e --arg p "$USERF" '.denied[0].file == $p' >/dev/null
}

@test "CP-6 the base wildcard still covers subcommands for allow, and for deny: Bash(git:*) in deny denies every git rule; a narrower deny does not" {
  settings "$PROJ" '["Bash(git:*)","Bash(gh:*)","Bash(mkdir:*)","Bash(rm:*)","Bash(cp:*)","Bash(mv:*)","Bash(bash:*)"]' '[]'
  run bash "$CP" --root "$R" --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.total_found == 16' >/dev/null
  settings "$USERF" '[]' '["Bash(git:*)"]'
  run bash "$CP" --root "$R" --json
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.total_denied == 9 and ([.denied[].by] | unique == ["Bash(git:*)"])' >/dev/null
  # a narrower deny (a specific dangerous form) does not deny the generic requirement
  settings "$USERF" '[]' '["Bash(rm -rf /:*)","Bash(sudo:*)"]'
  run bash "$CP" --root "$R" --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.total_denied == 0' >/dev/null
}

@test "CP-7 no settings file in any layer → exit 2; --json reports it with an empty settings_files; --quiet prints nothing" {
  run bash "$CP" --root "$R" --json
  [ "$status" -eq 2 ]
  echo "$output" | jq -e '.success == false and .settings_files == []' >/dev/null
  run bash "$CP" --root "$R" --quiet
  [ "$status" -eq 2 ]
  [ -z "$output" ]
}

@test "CP-8 a malformed settings file is skipped with a warning, never treated as allowing (or denying) anything" {
  printf 'not json\n' > "$PROJ"
  settings "$LOCAL" "$REQ" '[]'
  run bash "$CP" --root "$R" --json
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN"*"settings.json"* ]]
  echo "$output" | grep -v '^WARN' | jq -e '.success == true and .total_found == 16' >/dev/null
  printf 'not json\n' > "$LOCAL"
  run bash "$CP" --root "$R" --quiet
  [ "$status" -eq 1 ]
  [ -z "$output" ]   # --quiet is exit-code only: no WARN either (BB #1270 FIND-003)
  # a scalar permissions block or a scalar allow/deny is skipped too, never an abort (review dissent)
  printf '{"permissions":"x"}\n' > "$PROJ"
  printf '{"permissions":{"allow":"Bash(git:*)","deny":{"a":1}}}\n' > "$LOCAL"
  settings "$USERF" "$REQ" '[]'
  run bash "$CP" --root "$R" --json
  [ "$status" -eq 0 ]
  echo "$output" | grep -v '^WARN' | jq -e '.success == true and (.settings_files | length) == 1' >/dev/null
  [ "$(echo "$output" | grep -c '^WARN')" -eq 2 ]
}

@test "CP-10 the check stays fast against hundreds of rules (no fork per comparison): 500 allow + 100 deny rules in under two seconds" {
  big_allow=$(jq -nc '[range(500) | "Bash(tool\(.):*)"] + ["Bash(git:*)","Bash(gh:*)","Bash(mkdir:*)","Bash(rm:*)","Bash(cp:*)","Bash(mv:*)","Bash(bash:*)"]')
  big_deny=$(jq -nc '[range(100) | "Bash(danger\(.) -rf /:*)"]')
  settings "$PROJ" "$big_allow" "$big_deny"
  start=$(date +%s%N)
  run bash "$CP" --root "$R" --quiet
  end=$(date +%s%N)
  [ "$status" -eq 0 ]
  [ $(( (end - start) / 1000000 )) -lt 2000 ]
}

@test "CP-9 --help exits 0 and names the three layers; an unknown option exits 2" {
  run bash "$CP" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"settings.local.json"* && "$output" == *"--root"* ]]
  run bash "$CP" --bogus
  [ "$status" -eq 2 ]
}
