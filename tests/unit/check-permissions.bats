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

# --- cycle-126 sprint-250 Task 4.5 (SDD D-4.5, sprint SKP-010): the second rule grammar.
# Bash(<body>) normalises to <body> with one trailing ":*" or " *" removed and the
# surrounding whitespace trimmed; a body without a wildcard is an exact rule; nothing
# else is rewritten. A wildcard rule covers a requirement when its key equals the
# requirement's key or the requirement's first word; deny precedence is unchanged.

@test "CP-11 Bash(git push *) in allow satisfies Bash(git push:*); Bash(git *) covers every git requirement" {
  allow=$(echo "$REQ" | jq -c 'map(if . == "Bash(git push:*)" then "Bash(git push *)" else . end)')
  settings "$PROJ" "$allow" '[]'
  run bash "$CP" --root "$R" --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.total_found == 16 and (.found | index("Bash(git push:*)")) != null' >/dev/null
  settings "$PROJ" '["Bash(git *)","Bash(gh *)","Bash(mkdir *)","Bash(rm *)","Bash(cp *)","Bash(mv *)","Bash(bash *)"]' '[]'
  run bash "$CP" --root "$R" --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.total_found == 16' >/dev/null
}

@test "CP-12 Bash(git push *) in deny denies Bash(git push:*), reported by the deny rule as written; Bash(git *) denies every git requirement" {
  settings "$PROJ" "$REQ" '[]'
  settings "$LOCAL" '[]' '["Bash(git push *)"]'
  run bash "$CP" --root "$R" --json
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.total_denied == 1 and .denied[0].rule == "Bash(git push:*)" and .denied[0].by == "Bash(git push *)"' >/dev/null
  echo "$output" | jq -e --arg p "$LOCAL" '.denied[0].file == $p' >/dev/null
  settings "$LOCAL" '[]' '["Bash(git *)"]'
  run bash "$CP" --root "$R" --json
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.total_denied == 9 and ([.denied[].by] | unique == ["Bash(git *)"])' >/dev/null
}

# cp13_case <name> <project-allow-json> <local-deny-json> <expected-exit> <jq-assertion>
cp13_case() {
  settings "$PROJ" "$2" '[]'
  settings "$LOCAL" '[]' "$3"
  run bash "$CP" --root "$R" --json
  if [ "$status" -ne "$4" ] || ! echo "$output" | jq -e "$5" >/dev/null; then
    echo "CP-13 case '$1' failed: status=$status output=$output" >&2
    return 1
  fi
}

@test "CP-13 table: mixed forms across layers, whitespace and escaping, and a dangerous-shape deny fuzz set behave per the grammar" {
  base='["Bash(gh:*)","Bash(mkdir:*)","Bash(rm:*)","Bash(cp:*)","Bash(mv:*)","Bash(bash:*)"]'
  base_space=$(echo "$base" | jq -c 'map(sub(":\\*\\)$"; " *)"))')
  all_space=$(echo "$REQ" | jq -c 'map(sub(":\\*\\)$"; " *)"))')
  # mixed forms across layers: the colon form in the user file, the space form in the project file
  settings "$USERF" '["Bash(git:*)"]' '[]'
  cp13_case "mixed-layers" "$base_space" '[]' 0 '.total_found == 16'
  settings "$USERF" '[]' '[]'
  cp13_case "all-space-form" "$all_space" '[]' 0 '.total_found == 16'
  # whitespace: surrounding whitespace inside the parentheses is trimmed
  cp13_case "padded-allow" "$(echo "$base" | jq -c '. + ["Bash(  git :* )"]')" '[]' 0 '.total_found == 16'
  cp13_case "padded-deny" "$REQ" '["Bash( git push * )"]' 1 '.total_denied == 1 and .denied[0].rule == "Bash(git push:*)"'
  # no other rewriting: inner whitespace is not collapsed, escapes are not interpreted
  cp13_case "inner-double-space" "$(echo "$base" | jq -c '. + ["Bash(git  push *)"]')" '[]' 1 '(.missing | index("Bash(git push:*)")) != null'
  cp13_case "escaped-space" "$(echo "$base" | jq -c '. + ["Bash(git\\ *)"]')" '[]' 1 '.total_found == 7'
  cp13_case "escaped-colon" "$(echo "$base" | jq -c '. + ["Bash(git\\:*)"]')" '[]' 1 '.total_found == 7'
  # an exact rule (no wildcard) never satisfies a wildcard requirement
  cp13_case "exact-allow" "$(echo "$base" | jq -c '. + ["Bash(git push)","Bash(git)"]')" '[]' 1 '(.missing | index("Bash(git push:*)")) != null and .total_found == 7'
  # a non-Bash rule, a malformed wrapper or a bare prefix never matches
  cp13_case "non-bash" "$(echo "$base" | jq -c '. + ["Read(git:*)","Bashgit:*)","Bash(gi:*)","Bash(git:*"]')" '[]' 1 '.total_found == 7'
  # dangerous-shape fuzz: every narrower deny leaves the generic requirement effective
  local d
  for d in 'Bash(git push --force:*)' 'Bash(git push --force *)' 'Bash(git push -f *)' \
           'Bash(rm -rf /:*)' 'Bash(rm -rf / *)' 'Bash(rm -rf /)' 'Bash(rm -rf ~ *)' 'Bash(git reset --hard *)' \
           'Bash(git checkout -- *)' 'Bash(git push origin main:*)' 'Bash(git)' 'Bash(rm)' 'Bash(git push)' \
           'Bash(sudo *)' 'Bash(git push\ *)' 'Bash(bash -c *)' 'Bash(mv / *)' \
           'Bash(git  push *)' 'Bash(gh pr merge *)' 'Bash(git:)' 'Bash(git push :*)x'; do
    cp13_case "narrow-deny $d" "$REQ" "$(jq -nc --arg d "$d" '[$d]')" 0 '.total_denied == 0 and .total_found == 16'
  done
  # every generic deny covers each subcommand, in either form
  for d in 'Bash(git:*)' 'Bash(git *)' 'Bash( git:* )' 'Bash(git :*)'; do
    cp13_case "generic-deny $d" "$REQ" "$(jq -nc --arg d "$d" '[$d]')" 1 '.total_denied == 9'
  done
  for d in 'Bash(rm:*)' 'Bash(rm *)' 'Bash(git push:*)' 'Bash(git push *)'; do
    cp13_case "subcommand-deny $d" "$REQ" "$(jq -nc --arg d "$d" '[$d]')" 1 '.total_denied == 1 and .total_found == 15'
  done
  cp13_case "gh-deny" "$REQ" '["Bash(gh *)"]' 1 '.total_denied == 2'
  # a deny in one form wins over an allow of the other form in another layer
  settings "$USERF" '[]' '["Bash(gh pr *)"]'
  cp13_case "cross-form-deny" "$REQ" '[]' 1 '.total_denied == 1 and .denied[0].rule == "Bash(gh pr:*)" and .denied[0].by == "Bash(gh pr *)"'
}

@test "CP-14 table: a universal rule, bare Bash, Bash(*) or Bash(:*), covers every Bash requirement, for allow and for deny" {
  # sprint-250 review run 1, n29: rule_key skipped bare Bash and keyed Bash(*) as the
  # exact body "*", so a universal deny passed the preflight and the run stalled later
  local u
  # run 2, #9: an empty prefix (Bash(:*)) matches every command in Claude Code's prefix grammar
  for u in 'Bash' 'Bash(*)' 'Bash( * )' 'Bash(:*)' 'Bash( :* )'; do
    cp13_case "universal-allow $u" "$(jq -nc --arg u "$u" '[$u]')" '[]' 0 '.total_found == 16 and .total_denied == 0'
    cp13_case "universal-deny $u" "$REQ" "$(jq -nc --arg u "$u" '[$u]')" 1 \
      ".total_denied == 16 and .total_found == 0 and ([.denied[].by] | unique == [\"$u\"])"
  done
  # a narrower deny still subtracts from a universal allow
  cp13_case "universal-allow-narrow-deny" '["Bash"]' '["Bash(rm:*)"]' 1 '.total_found == 15 and .total_denied == 1 and .denied[0].rule == "Bash(rm:*)"'
  # a universal deny in the user file wins over the full allow list in the project file
  settings "$USERF" '[]' '["Bash"]'
  cp13_case "universal-deny-user-layer" "$REQ" '[]' 1 '.total_denied == 16'
  settings "$USERF" '[]' '[]'
  # near-misses are not universal: another tool, a lowercase name, a literal ** body
  cp13_case "not-universal" '["Read","bash","Bash(**)","Bashx"]' '[]' 1 '.total_found == 0 and .total_missing == 16'
}
