#!/usr/bin/env bats
# =============================================================================
# tests/unit/run-preflight.bats — cycle-125 Sprint 3 (PRD FR-3 AC 1, SDD D-3.1)
#
# .claude/scripts/run-preflight.sh [--unattended] [--resume] [--json] [--root DIR]
# composes the run-mode pre-flight into one checklist: P1 defaultMode, P2 allow
# rules, P3 voices, P4 breakers, P5 NOTES size, P6 run state, P7 beads,
# P8 branch. One passing and one failing fixture per predicate; the checklist
# names the predicate and the fix; exit 1 on any FAIL; --json shape.
#
# Fixtures are synthetic project roots. The composed helper scripts
# (check-permissions.sh, beads/beads-health.sh, run-mode-ice.sh) read the real
# repository, so they are stubbed through the bats-gated LOA_PREFLIGHT_HELPERS_DIR
# seam; notes-guard.sh is pure and runs for real.
# =============================================================================

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  PF="$PROJECT_ROOT/.claude/scripts/run-preflight.sh"
  GEN="$PROJECT_ROOT/tests/fixtures/notes/make-large-notes.sh"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/pf.XXXXXX")"
  R="$T/root"
  mkdir -p "$R/.claude" "$R/.run" "$R/grimoires/loa" "$T/home/.claude" "$T/helpers/beads" "$T/bin"
  export HOME="$T/home"
  export LOA_PREFLIGHT_HELPERS_DIR="$T/helpers"
  unset OPENAI_API_KEY ANTHROPIC_API_KEY GOOGLE_API_KEY GEMINI_API_KEY LOA_BEADS_AUTONOMOUS_OVERRIDE
  # PATH: $T/bin first, then only the directories that hold the tools the script
  # needs (yq, jq, git, date) plus the system dirs — never the operator's
  # ~/.local/bin or npm bin where claude/codex/agy may live.
  local tool
  for tool in yq jq git; do ln -s "$(command -v "$tool")" "$T/bin/$tool"; done
  export PATH="$T/bin:/usr/bin:/bin"
  for c in claude codex agy; do command -v "$c" >/dev/null 2>&1 && skip "CLI hop '$c' is reachable on the minimal PATH; fixture cannot isolate P3"; done
  # helper stubs, controllable per test
  echo 0 > "$T/cp.rc"; echo HEALTHY > "$T/beads.status"; echo 0 > "$T/ice.rc"
  cat > "$T/helpers/check-permissions.sh" <<EOF
#!/usr/bin/env bash
exit \$(cat "$T/cp.rc")
EOF
  # like the real script: exit 0 HEALTHY, 4 DEGRADED, 2 otherwise — the JSON is the contract
  cat > "$T/helpers/beads/beads-health.sh" <<EOF
#!/usr/bin/env bash
s="\$(cat "$T/beads.status")"; case "\$s" in HEALTHY) rc=0;; DEGRADED) rc=4;; *) rc=2;; esac
printf '{"status":"%s","exit_code":%d}\n' "\$s" "\$rc"; exit \$rc
EOF
  cat > "$T/helpers/run-mode-ice.sh" <<EOF
#!/usr/bin/env bash
rc=\$(cat "$T/ice.rc"); if [[ \$rc -ne 0 ]]; then echo "BLOCKED: protected branch 'main'" >&2; else echo "OK: On safe branch 'feature/x'"; fi; exit \$rc
EOF
  chmod +x "$T/helpers/check-permissions.sh" "$T/helpers/beads/beads-health.sh" "$T/helpers/run-mode-ice.sh"
  # a healthy default root: bypassPermissions, one usable voice, no breakers, small NOTES, no run state
  printf '{"permissions":{"defaultMode":"bypassPermissions","allow":["Bash(git:*)"]}}\n' > "$R/.claude/settings.json"
  cat > "$R/.loa.config.yaml" <<'EOF'
run_mode:
  enabled: true
flatline_protocol:
  code_review:
    enabled: true
    model: gpt-5.5-pro
    fallback_chain: [gpt-5.5, gemini-3.1-pro, claude-headless]
  security_audit:
    enabled: true
    model: gpt-5.5-pro
    fallback_chain: [gpt-5.5, gemini-3.1-pro, claude-headless]
EOF
  printf 'OPENAI_API_KEY=sk-test-not-a-real-key\n' > "$R/.env.local"
  "$GEN" "$R/grimoires/loa/NOTES.md" under
}

teardown() { find "$T" -mindepth 1 -delete 2>/dev/null || true; rmdir "$T" 2>/dev/null || true; }

pf() { run bash "$PF" --root "$R" "$@"; }
status_of() { echo "$output" | jq -r --arg id "$1" '.checks[] | select(.id==$id) | .status'; }
line_of() { echo "$output" | grep -E "^\[(PASS|WARN|FAIL)\] $1 "; }

@test "PF-0 the healthy fixture passes in unattended mode: exit 0, every predicate PASS or WARN, summary line" {
  pf --unattended
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE '^run-preflight \(unattended\): [0-9]+ pass, [0-9]+ warn, 0 fail'
  for p in P1 P2 P3 P4 P5 P6 P7 P8; do line_of "$p" >/dev/null; done
  ! echo "$output" | grep -q '^\[FAIL\]'
}

@test "PF-J --json emits one object: mode, ok, counts, checks[] with id/name/status/detail/fix, ts" {
  pf --unattended --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode=="unattended" and .ok==true and (.checks|length)==8 and (.pass+.warn+.fail)==8 and (.ts|test("^[0-9]{4}-"))' >/dev/null
  echo "$output" | jq -e '.checks[] | select(.id=="P1") | has("name") and has("status") and has("detail") and has("fix")' >/dev/null
  echo "$output" | jq -e '[.checks[].id] == ["P1","P2","P3","P4","P5","P6","P7","P8"]' >/dev/null
}

@test "PF-1 P1 defaultMode: bypassPermissions passes; plan fails in unattended mode (warns interactive); auto fails with the auto-denied symptom; precedence local > project > home" {
  printf '{"permissions":{"defaultMode":"plan"}}\n' > "$R/.claude/settings.json"
  pf --unattended
  [ "$status" -eq 1 ]
  line_of P1 | grep -q '^\[FAIL\] P1 .*plan.*fix:'
  pf
  [ "$status" -eq 0 ]
  line_of P1 | grep -q '^\[WARN\] P1 .*plan'
  printf '{"permissions":{"defaultMode":"auto"}}\n' > "$R/.claude/settings.json"
  pf --unattended
  [ "$status" -eq 1 ]
  line_of P1 | grep -qi 'auto-denied'
  # settings.local.json wins over settings.json; home is the last resort
  printf '{"permissions":{"defaultMode":"bypassPermissions"}}\n' > "$R/.claude/settings.local.json"
  pf --unattended
  [ "$status" -eq 0 ]
  line_of P1 | grep -q 'settings.local.json'
  rm "$R/.claude/settings.local.json"; printf '{}\n' > "$R/.claude/settings.json"
  printf '{"permissions":{"defaultMode":"bypassPermissions"}}\n' > "$HOME/.claude/settings.json"
  pf --unattended
  [ "$status" -eq 0 ]
  line_of P1 | grep -q 'home'
}

@test "PF-1b P1 acceptEdits / default pass unattended only when P2 confirms the allow rules" {
  printf '{"permissions":{"defaultMode":"acceptEdits"}}\n' > "$R/.claude/settings.json"
  pf --unattended
  [ "$status" -eq 0 ]
  line_of P1 | grep -q '^\[PASS\] P1 .*acceptEdits'
  echo 1 > "$T/cp.rc"
  pf --unattended
  [ "$status" -eq 1 ]
  line_of P1 | grep -q '^\[FAIL\] P1 '
  line_of P2 | grep -q '^\[FAIL\] P2 '
}

@test "PF-2 P2 allow rules: check-permissions.sh exit 0 passes; non-zero fails and names the fix" {
  pf --unattended; [ "$status" -eq 0 ]; line_of P2 | grep -q '^\[PASS\]'
  echo 1 > "$T/cp.rc"
  pf --unattended
  [ "$status" -eq 1 ]
  line_of P2 | grep -q 'fix:.*check-permissions.sh'
}

@test "PF-3 P3 voices: a stage with no credential and no CLI hop fails; a CLI hop on PATH or a key in the environment or .env makes it pass with per-voice warnings" {
  rm "$R/.env.local"
  pf --unattended
  [ "$status" -eq 1 ]
  line_of P3 | grep -q '^\[FAIL\] P3 .*code_review'
  line_of P3 | grep -q 'fix:'
  printf '#!/usr/bin/env bash\nexit 0\n' > "$T/bin/claude"; chmod +x "$T/bin/claude"
  pf --unattended
  [ "$status" -eq 0 ]
  line_of P3 | grep -qE '^\[(PASS|WARN)\] P3 '
  line_of P3 | grep -q 'claude-headless'
  rm "$T/bin/claude"
  export OPENAI_API_KEY=sk-test
  pf --unattended
  [ "$status" -eq 0 ]
  unset OPENAI_API_KEY
  printf 'GOOGLE_API_KEY=not-a-real-key\n' > "$R/.env.local"
  pf --unattended
  [ "$status" -eq 0 ]
  line_of P3 | grep -q 'gemini'
  # never prints a credential value
  [[ "$output" != *"not-a-real-key"* && "$output" != *"sk-test"* ]]
}

@test "PF-4 P4 breakers: OPEN for the only usable provider fails; OPEN for another provider warns with its age; CLOSED is silent" {
  now=$(date +%s)
  printf '{"state":"OPEN","failure_count":5,"opened_at":%d}\n' $((now - 7200)) > "$R/.run/circuit-breaker-openai-http_api.json"
  pf --unattended
  [ "$status" -eq 1 ]
  line_of P4 | grep -q '^\[FAIL\] P4 .*openai'
  line_of P4 | grep -qE '2h|120m'
  rm "$R/.run/circuit-breaker-openai-http_api.json"
  printf '{"state":"OPEN","failure_count":5,"opened_at":%d}\n' $((now - 600)) > "$R/.run/circuit-breaker-google-http_api.json"
  pf --unattended
  [ "$status" -eq 0 ]
  line_of P4 | grep -q '^\[WARN\] P4 .*google'
  printf '{"state":"CLOSED","failure_count":0,"opened_at":null}\n' > "$R/.run/circuit-breaker-google-http_api.json"
  printf '{"state":"CLOSED"}\n' > "$R/.run/circuit-breaker.json"   # the run-mode ICE breaker is not a provider bucket
  pf --unattended
  [ "$status" -eq 0 ]
  line_of P4 | grep -q '^\[PASS\] P4 '
}

@test "PF-5 P5 NOTES size: under the line passes; at the warn line warns; at the block line fails with the rotate command" {
  pf --unattended; line_of P5 | grep -q '^\[PASS\] P5 '
  "$GEN" "$R/grimoires/loa/NOTES.md" 100k
  pf --unattended; [ "$status" -eq 0 ]; line_of P5 | grep -q '^\[WARN\] P5 '
  "$GEN" "$R/grimoires/loa/NOTES.md" 250k
  pf --unattended
  [ "$status" -eq 1 ]
  line_of P5 | grep -q 'fix:.*notes-guard.sh rotate'
}

@test "PF-6 P6 run state: none passes; fresh RUNNING fails as in-progress; RUNNING older than 12h fails with /run-resume; HALTED fails with /run-resume; JACKED_OUT passes; --resume inverts" {
  pf --unattended; line_of P6 | grep -q '^\[PASS\] P6 '
  fresh=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  printf '{"plan_id":"p","state":"RUNNING","timestamps":{"started":"%s","last_activity":"%s"},"sprints":{"current":"sprint-2"}}\n' "$fresh" "$fresh" > "$R/.run/sprint-plan-state.json"
  pf --unattended
  [ "$status" -eq 1 ]
  line_of P6 | grep -qi 'in progress'
  stale=$(date -u -d '@'$(( $(date +%s) - 14*3600 )) +%Y-%m-%dT%H:%M:%SZ)
  printf '{"plan_id":"p","state":"RUNNING","timestamps":{"started":"%s","last_activity":"%s"},"sprints":{"current":"sprint-2"}}\n' "$stale" "$stale" > "$R/.run/sprint-plan-state.json"
  pf --unattended
  [ "$status" -eq 1 ]
  line_of P6 | grep -q '/run-resume'
  line_of P6 | grep -qE '1[34]h'
  printf '{"state":"HALTED","timestamps":{"last_activity":"%s"}}\n' "$fresh" > "$R/.run/sprint-plan-state.json"
  pf --unattended
  [ "$status" -eq 1 ]
  line_of P6 | grep -q '/run-resume'
  printf '{"state":"JACKED_OUT","timestamps":{"last_activity":"%s"}}\n' "$fresh" > "$R/.run/sprint-plan-state.json"
  pf --unattended
  [ "$status" -eq 0 ]
  # --resume: a resumable state passes, nothing to resume fails
  printf '{"state":"HALTED","timestamps":{"last_activity":"%s"}}\n' "$fresh" > "$R/.run/sprint-plan-state.json"
  pf --unattended --resume
  [ "$status" -eq 0 ]
  line_of P6 | grep -q '^\[PASS\] P6 .*HALTED'
  rm "$R/.run/sprint-plan-state.json"
  pf --unattended --resume
  [ "$status" -eq 1 ]
  line_of P6 | grep -qi 'nothing to resume'
}

@test "PF-6b P6 also reads .run/state.json and .run/simstim-state.json; a malformed state file is a FAIL with a fix, never a crash" {
  printf '{"run_id":"r","state":"HALTED","timestamps":{"last_activity":"2026-09-01T00:00:00Z"}}\n' > "$R/.run/state.json"
  pf --unattended
  [ "$status" -eq 1 ]
  line_of P6 | grep -q 'state.json'
  rm "$R/.run/state.json"
  printf '{"phase":"implementation","status":"RUNNING","updated_at":"2026-09-01T00:00:00Z"}\n' > "$R/.run/simstim-state.json"
  pf --unattended
  [ "$status" -eq 1 ]
  line_of P6 | grep -q 'simstim'
  printf 'not json' > "$R/.run/simstim-state.json"
  pf --unattended
  [ "$status" -eq 1 ]
  line_of P6 | grep -qi 'unparseable'
}

@test "PF-7 P7 beads: HEALTHY passes, DEGRADED warns, MISSING fails unless requires_beads is false or the override env is set" {
  pf --unattended; line_of P7 | grep -q '^\[PASS\] P7 '
  echo DEGRADED > "$T/beads.status"
  pf --unattended; [ "$status" -eq 0 ]; line_of P7 | grep -q '^\[WARN\] P7 '
  echo MISSING > "$T/beads.status"
  pf --unattended
  [ "$status" -eq 1 ]
  line_of P7 | grep -q 'fix:.*br init'
  export LOA_BEADS_AUTONOMOUS_OVERRIDE=true
  pf --unattended
  [ "$status" -eq 0 ]
  line_of P7 | grep -q '^\[WARN\] P7 '
  unset LOA_BEADS_AUTONOMOUS_OVERRIDE
  printf 'beads:\n  autonomous:\n    requires_beads: false\n' >> "$R/.loa.config.yaml"
  pf --unattended
  [ "$status" -eq 0 ]
}

@test "PF-8 P8 branch: run-mode-ice.sh validate exit 0 passes; non-zero fails and surfaces the message" {
  pf --unattended; line_of P8 | grep -q '^\[PASS\] P8 '
  echo 1 > "$T/ice.rc"
  pf --unattended
  [ "$status" -eq 1 ]
  line_of P8 | grep -q "protected branch"
}

@test "PF-M several failures are all listed (no short-circuit) and the exit code is 1; usage errors exit 2" {
  echo 1 > "$T/cp.rc"; echo 1 > "$T/ice.rc"; "$GEN" "$R/grimoires/loa/NOTES.md" 250k
  pf --unattended
  [ "$status" -eq 1 ]
  [ "$(echo "$output" | grep -c '^\[FAIL\]')" -ge 3 ]
  echo "$output" | grep -qE '^run-preflight \(unattended\): [0-9]+ pass, [0-9]+ warn, [3-9] fail'
  run bash "$PF" --bogus
  [ "$status" -eq 2 ]
  run bash "$PF" --root "$T/nope"
  [ "$status" -eq 2 ]
}

@test "PF-S the helpers seam is bats-gated: without the bats marker the stub directory is ignored" {
  echo 1 > "$T/cp.rc"
  run bash -c "unset BATS_TEST_FILENAME BATS_VERSION; bash '$PF' --root '$R' --unattended --json"
  # the real check-permissions.sh reads this repository's settings; whatever it says, the stub's forced failure must not be the source
  echo "$output" | jq -e '.checks[] | select(.id=="P2") | .detail | test("stub") | not' >/dev/null
}
