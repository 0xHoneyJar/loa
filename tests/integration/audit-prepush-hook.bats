#!/usr/bin/env bats
# audit pre-push hook + installer — the MEANINGFUL local enforcement surface for the
# verify-for-merge gate (CI/post-merge would be a no-op over gitignored .run/).

setup() {
  BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO="$(cd "$BATS_TEST_DIR/../.." && pwd)"
  HOOK_SRC="$REPO/.claude/scripts/git-hooks/pre-push-audit"
  INSTALLER="$REPO/.claude/scripts/install-audit-prepush.sh"
  [[ -f "$HOOK_SRC" && -f "$INSTALLER" ]] || skip "hook/installer not present"
  T="$(mktemp -d)"; ( cd "$T" && git init -q )
  mkdir -p "$T/.claude/scripts"
}
teardown() { [[ -n "${T:-}" ]] && find "$T" -mindepth 0 -delete 2>/dev/null || true; }

_stub_gate() { # rc — install a stub gate at the temp repo that exits with rc
  cat > "$T/.claude/scripts/audit-verify-for-merge.sh" <<EOF
#!/usr/bin/env bash
echo "[stub-gate] PROJECT_ROOT=\${PROJECT_ROOT:-unset}"
exit $1
EOF
  chmod +x "$T/.claude/scripts/audit-verify-for-merge.sh"
}

@test "installer: installs pre-push-audit into .git/hooks/pre-push (with the v1 sentinel)" {
  ( cd "$T" && bash "$INSTALLER" )
  [ -x "$T/.git/hooks/pre-push" ]
  grep -qF '# loa:pre-push-audit:v1' "$T/.git/hooks/pre-push"
}

@test "installer: BACKS UP a pre-existing non-loa pre-push hook (never clobbers)" {
  printf '#!/bin/sh\necho someone-elses-hook\n' > "$T/.git/hooks/pre-push"; chmod +x "$T/.git/hooks/pre-push"
  run bash -c "cd '$T' && bash '$INSTALLER'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"backed up"* ]]
  grep -q 'someone-elses-hook' "$T/.git/hooks/pre-push.pre-loa-bak"   # original preserved
  grep -qF '# loa:pre-push-audit:v1' "$T/.git/hooks/pre-push"          # ours installed
}

@test "installer: a foreign hook merely MENTIONING the string is still backed up, not clobbered" {
  printf '#!/bin/sh\n# see also pre-push-audit docs\necho IMPORTANT-USER-HOOK\n' > "$T/.git/hooks/pre-push"; chmod +x "$T/.git/hooks/pre-push"
  ( cd "$T" && bash "$INSTALLER" )
  grep -q 'IMPORTANT-USER-HOOK' "$T/.git/hooks/pre-push.pre-loa-bak"   # not lost
}

@test "installer: re-installing its own hook is idempotent (sentinel match → no spurious backup)" {
  ( cd "$T" && bash "$INSTALLER" && bash "$INSTALLER" )
  grep -qF '# loa:pre-push-audit:v1' "$T/.git/hooks/pre-push"
  [ ! -f "$T/.git/hooks/pre-push.pre-loa-bak" ]   # our own hook is never backed up over itself
}

@test "installer: respects core.hooksPath (lands in the configured dir)" {
  ( cd "$T" && git config core.hooksPath .githooks && bash "$INSTALLER" )
  [ -x "$T/.githooks/pre-push" ]
  grep -qF '# loa:pre-push-audit:v1' "$T/.githooks/pre-push"
}

@test "hook: gate present + returns 0 → hook exits 0 (push allowed)" {
  _stub_gate 0
  run bash -c "cd '$T' && bash '$HOOK_SRC' </dev/null"
  [ "$status" -eq 0 ]
}

@test "hook: gate present + returns non-zero → hook exits non-zero (push blocked)" {
  _stub_gate 7
  run bash -c "cd '$T' && bash '$HOOK_SRC' </dev/null"
  [ "$status" -eq 7 ]
}

@test "hook: handles git's real pre-push contract (argv = remote name+url, ref lines on stdin)" {
  _stub_gate 0
  run bash -c "cd '$T' && printf 'refs/heads/x aaa refs/heads/x bbb\n' | bash '$HOOK_SRC' origin https://example.invalid/repo.git"
  [ "$status" -eq 0 ]
}

@test "hook: pins PROJECT_ROOT to the git root (ignores a stale inherited PROJECT_ROOT)" {
  _stub_gate 0
  run bash -c "cd '$T' && PROJECT_ROOT=/some/other/repo bash '$HOOK_SRC' </dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PROJECT_ROOT=$T"* ]]   # gate saw the git root, not the stale value
}

@test "hook: gate ABSENT → hook exits 0 (never blocks a push on an older checkout)" {
  run bash -c "cd '$T' && bash '$HOOK_SRC' </dev/null"
  [ "$status" -eq 0 ]
}

@test "hook: against the REAL gate in DEFAULT-OFF state → exits 0 (installing is genuinely inert)" {
  run bash -c "cd '$REPO' && env -u LOA_AUDIT_VERIFY_FOR_MERGE bash '$HOOK_SRC' </dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DISABLED"* ]]
}
