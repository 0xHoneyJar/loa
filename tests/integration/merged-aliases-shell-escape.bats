#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# =============================================================================
# AC-S2.7 — Shell-escape corpus (cycle-099 Sprint 2B / SDD §3.5)
#
# Per SDD §3.5 rule 6: "Test corpus at tests/integration/merged-aliases-shell-escape.bats
# constructs a fixture where the schema-bypassing reaches the writer (simulated
# via a debug flag) — writer rejects, asserts non-zero exit. Probe values:
# `; rm -rf`, `$(touch /tmp/pwned)`, `\` `\n`, ` `, `'`, `"`. **All probes MUST
# exit 1 with structured error** before any disk write."
#
# This bats file probes the writer's shell-safety gate via the hook's
# `--probe-shell-safety` test surface. Each hostile probe MUST exit 78
# (EXIT_REFUSE) with [MERGED-ALIASES-WRITE-FAILED] on stderr; legitimate
# values MUST exit 0. Positive controls verify the gate isn't too tight.
# =============================================================================

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  HOOK="$REPO_ROOT/.claude/scripts/lib/model-overlay-hook.py"
  PYTHON="$(command -v python3)"
  [[ -n "$PYTHON" ]] || skip "python3 not on PATH"
  WORK="$(mktemp -d)"
}

teardown() {
  rm -rf "$WORK"
}

# -----------------------------------------------------------------------------
# A — POSITIVE CONTROLS (must pass — too-tight gate would silently break here)
# -----------------------------------------------------------------------------

@test "A1: legitimate alias 'opus' is accepted" {
  run "$PYTHON" "$HOOK" --probe-shell-safety "opus"
  [ "$status" -eq 0 ]
}

@test "A2: model id 'claude-opus-4-7' is accepted" {
  run "$PYTHON" "$HOOK" --probe-shell-safety "claude-opus-4-7"
  [ "$status" -eq 0 ]
}

@test "A3: model id 'gpt-5.5' is accepted (dot in version)" {
  run "$PYTHON" "$HOOK" --probe-shell-safety "gpt-5.5"
  [ "$status" -eq 0 ]
}

@test "A4: alias with underscore 'my_model' is accepted" {
  run "$PYTHON" "$HOOK" --probe-shell-safety "my_model"
  [ "$status" -eq 0 ]
}

# -----------------------------------------------------------------------------
# B — SDD §3.5 rule 5 PROBES (must each exit 78 with [MERGED-ALIASES-WRITE-FAILED])
# -----------------------------------------------------------------------------

@test "B1: '\$(touch /tmp/pwned)' is rejected" {
  run "$PYTHON" "$HOOK" --probe-shell-safety '$(touch /tmp/pwned)'
  [ "$status" -eq 78 ]
  [[ "$output" == *"[MERGED-ALIASES-WRITE-FAILED]"* ]]
}

@test "B2: backtick command substitution '\`whoami\`' is rejected" {
  run "$PYTHON" "$HOOK" --probe-shell-safety '`whoami`'
  [ "$status" -eq 78 ]
  [[ "$output" == *"[MERGED-ALIASES-WRITE-FAILED]"* ]]
}

@test "B3: backslash 'foo\\bar' is rejected" {
  run "$PYTHON" "$HOOK" --probe-shell-safety 'foo\bar'
  [ "$status" -eq 78 ]
  [[ "$output" == *"[MERGED-ALIASES-WRITE-FAILED]"* ]]
}

@test "B4: literal newline is rejected" {
  printf -v probe 'foo\nbar'
  run "$PYTHON" "$HOOK" --probe-shell-safety "$probe"
  [ "$status" -eq 78 ]
  [[ "$output" == *"[MERGED-ALIASES-WRITE-FAILED]"* ]]
}

@test "B5: literal carriage return is rejected" {
  printf -v probe 'foo\rbar'
  run "$PYTHON" "$HOOK" --probe-shell-safety "$probe"
  [ "$status" -eq 78 ]
  [[ "$output" == *"[MERGED-ALIASES-WRITE-FAILED]"* ]]
}

@test "B6: single quote is rejected" {
  run "$PYTHON" "$HOOK" --probe-shell-safety "foo'bar"
  [ "$status" -eq 78 ]
  [[ "$output" == *"[MERGED-ALIASES-WRITE-FAILED]"* ]]
}

@test "B7: double quote is rejected" {
  run "$PYTHON" "$HOOK" --probe-shell-safety 'foo"bar'
  [ "$status" -eq 78 ]
  [[ "$output" == *"[MERGED-ALIASES-WRITE-FAILED]"* ]]
}

@test "B8: '; rm -rf' shell-injection is rejected" {
  run "$PYTHON" "$HOOK" --probe-shell-safety '; rm -rf /'
  [ "$status" -eq 78 ]
  [[ "$output" == *"[MERGED-ALIASES-WRITE-FAILED]"* ]]
}

@test "B9: variable expansion '\$VAR' is rejected" {
  run "$PYTHON" "$HOOK" --probe-shell-safety '$VAR'
  [ "$status" -eq 78 ]
  [[ "$output" == *"[MERGED-ALIASES-WRITE-FAILED]"* ]]
}

@test "B10: brace expansion '\${HOME}' is rejected" {
  run "$PYTHON" "$HOOK" --probe-shell-safety '${HOME}'
  [ "$status" -eq 78 ]
  [[ "$output" == *"[MERGED-ALIASES-WRITE-FAILED]"* ]]
}

@test "B11: pipe '|' is rejected" {
  run "$PYTHON" "$HOOK" --probe-shell-safety 'a|b'
  [ "$status" -eq 78 ]
  [[ "$output" == *"[MERGED-ALIASES-WRITE-FAILED]"* ]]
}

@test "B12: ampersand '&' is rejected" {
  run "$PYTHON" "$HOOK" --probe-shell-safety 'a&b'
  [ "$status" -eq 78 ]
  [[ "$output" == *"[MERGED-ALIASES-WRITE-FAILED]"* ]]
}

@test "B13: redirect '<' is rejected" {
  run "$PYTHON" "$HOOK" --probe-shell-safety 'a<b'
  [ "$status" -eq 78 ]
  [[ "$output" == *"[MERGED-ALIASES-WRITE-FAILED]"* ]]
}

@test "B14: redirect '>' is rejected" {
  run "$PYTHON" "$HOOK" --probe-shell-safety 'a>b'
  [ "$status" -eq 78 ]
  [[ "$output" == *"[MERGED-ALIASES-WRITE-FAILED]"* ]]
}

@test "B15: parenthesis '(' is rejected" {
  run "$PYTHON" "$HOOK" --probe-shell-safety 'a(b'
  [ "$status" -eq 78 ]
  [[ "$output" == *"[MERGED-ALIASES-WRITE-FAILED]"* ]]
}

@test "B16: space is rejected" {
  run "$PYTHON" "$HOOK" --probe-shell-safety 'a b'
  [ "$status" -eq 78 ]
  [[ "$output" == *"[MERGED-ALIASES-WRITE-FAILED]"* ]]
}

@test "B17: empty string is rejected" {
  run "$PYTHON" "$HOOK" --probe-shell-safety ''
  [ "$status" -eq 78 ]
  [[ "$output" == *"[MERGED-ALIASES-WRITE-FAILED]"* ]]
}

@test "B18: tab character is rejected" {
  printf -v probe 'a\tb'
  run "$PYTHON" "$HOOK" --probe-shell-safety "$probe"
  [ "$status" -eq 78 ]
  [[ "$output" == *"[MERGED-ALIASES-WRITE-FAILED]"* ]]
}

@test "B19: '/path/sep' is rejected (path separator outside allowlist)" {
  run "$PYTHON" "$HOOK" --probe-shell-safety '/etc/passwd'
  [ "$status" -eq 78 ]
  [[ "$output" == *"[MERGED-ALIASES-WRITE-FAILED]"* ]]
}

@test "B20: '..' (dot-dot bypass) is rejected" {
  # The schema rejects `..` via not.anyOf clause (cycle-099 sprint-1E.c.3.b
  # char-class regex bypass); the writer-side gate ALSO rejects via the
  # forbidden-charset path. Belt-and-suspenders.
  run "$PYTHON" "$HOOK" --probe-shell-safety '..'
  [ "$status" -eq 78 ]
  [[ "$output" == *"[MERGED-ALIASES-WRITE-FAILED]"* ]]
}

# -----------------------------------------------------------------------------
# C — NEGATIVE-FORM PROBES (regression pin: ensure writer NEVER touches disk)
# -----------------------------------------------------------------------------

@test "C1: rejected probe does NOT create any file in the working dir" {
  # Probe with hostile value AND verify no .sh / .tmp file appears.
  before=$(ls -la "$WORK" | wc -l)
  run "$PYTHON" "$HOOK" --probe-shell-safety '$(touch '"$WORK"'/pwned)'
  [ "$status" -eq 78 ]
  after=$(ls -la "$WORK" | wc -l)
  [ "$before" -eq "$after" ]
  # explicit pwned-file check
  [ ! -f "$WORK/pwned" ]
}

@test "C2: rejected probe stderr starts with the marker token" {
  # The error message MUST contain the marker as the first token of the
  # first non-empty line — operators grep for the marker as the leading
  # signal. We verify with bats 1.5+'s --separate-stderr split.
  run --separate-stderr "$PYTHON" "$HOOK" --probe-shell-safety '$(reflected)'
  [ "$status" -eq 78 ]
  # The first line of stderr should start with the marker.
  first_line="$(printf '%s\n' "$stderr" | head -1)"
  [[ "$first_line" == "[MERGED-ALIASES-WRITE-FAILED]"* ]]
}
