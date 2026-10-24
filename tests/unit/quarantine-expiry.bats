#!/usr/bin/env bats
# =============================================================================
# tests/unit/quarantine-expiry.bats — cycle-133 Sprint 1 Task 1.6 (FR-5, SDD C-5)
#
# tools/check-quarantine-expiry.sh validates tests/QUARANTINE.tsv
# (test_id<TAB>owner<TAB>expiry<TAB>bead<TAB>reason): the test id names a real
# bats test, the owner is set, the bead exists and is open, the expiry is an
# ISO date equal to the row's quarantine (author) date + 30 days and never more
# than 60 days out, ids are unique, mandatory-gate tests are never listed, and
# an expired row fails. With --tap it prints the full-suite executed / skipped /
# quarantined totals. tests/unit/helpers/quarantine.bash skips a listed test
# with its reason and refuses a mismatched id or a mandatory-gate test.
#
# Every fixture is a throwaway git repository under BATS_TEST_TMPDIR with
# commits at fixed author dates; `br` is a stub (LOA_QUARANTINE_BR), and
# "today" is pinned with --today, so nothing reads the live beads workspace.
# =============================================================================

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  CQ="$PROJECT_ROOT/tools/check-quarantine-expiry.sh"
  R="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/qr.XXXXXX")"
  mkdir -p "$R/tests/unit/helpers" "$R/bin"
  cp "$PROJECT_ROOT/tests/unit/helpers/quarantine.bash" "$R/tests/unit/helpers/"
  # bats rewrites a line-leading test keyword even inside a heredoc, so the
  # fixture's test lines are emitted through a variable.
  local T='@test'
  cat > "$R/tests/unit/sample.bats" <<BATS
#!/usr/bin/env bats
setup() {
  load helpers/quarantine
  loa_quarantine_check
}
$T "S-1 flaky thing" {
  false
}
$T "S-2 steady thing" {
  true
}
BATS
  # br stub: bd-open1 is open, bd-closed1 is closed, anything else is unknown
  cat > "$R/bin/br" <<'BR'
#!/usr/bin/env bash
[[ "$1" == "show" ]] || exit 2
case "$2" in
  bd-open1)   printf '[{"id":"bd-open1","status":"open"}]\n' ;;
  bd-closed1) printf '[{"id":"bd-closed1","status":"closed"}]\n' ;;
  *) echo "Error: Issue not found: $2" >&2; exit 3 ;;
esac
BR
  chmod +x "$R/bin/br"
  export LOA_QUARANTINE_BR="$R/bin/br"
  git -C "$R" init -q
  git -C "$R" add -A
  _git_commit 2026-10-01 base
  Q="$R/tests/QUARANTINE.tsv"
  HDR=$'test_id\towner\texpiry\tbead\treason'
}

teardown() {
  find "$R" -mindepth 1 -delete 2>/dev/null || true
  rmdir "$R" 2>/dev/null || true
}

_git_commit() {
  GIT_AUTHOR_DATE="${1}T12:00:00Z" GIT_COMMITTER_DATE="${1}T12:00:00Z" \
    git -C "$R" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -q --allow-empty -m "$2"
}

# Write the quarantine file and commit it at the given author date (YYYY-MM-DD).
_commit_q() {
  local day="$1"; shift
  printf '%s\n' "$HDR" "$@" > "$Q"
  git -C "$R" add -A
  _git_commit "$day" quarantine
}

_row() { printf '%s\t%s\t%s\t%s\t%s' "$1" "$2" "$3" "$4" "$5"; }

@test "QX-1 a valid file passes and prints the quarantined count" {
  _commit_q 2026-10-20 "$(_row 'tests/unit/sample.bats::S-1 flaky thing' lead 2026-11-19 bd-open1 'races the clock')"
  run bash "$CQ" --repo "$R" --today 2026-10-24
  [ "$status" -eq 0 ]
  [[ "$output" == *"quarantined=1"* ]]
}

@test "QX-2 a header-only file passes with zero rows and needs no beads workspace" {
  _commit_q 2026-10-20
  run env LOA_QUARANTINE_BR=/nonexistent/br bash "$CQ" --repo "$R" --today 2026-10-24
  [ "$status" -eq 0 ]
  [[ "$output" == *"quarantined=0"* ]]
}

@test "QX-3 an expired row fails CI (the expired-quarantine fixture)" {
  _commit_q 2026-09-01 "$(_row 'tests/unit/sample.bats::S-1 flaky thing' lead 2026-10-01 bd-open1 'races the clock')"
  run bash "$CQ" --repo "$R" --today 2026-10-24
  [ "$status" -eq 1 ]
  [[ "$output" == *"expired"* ]]
  # the expiry day itself is still valid
  run bash "$CQ" --repo "$R" --today 2026-10-01
  [ "$status" -eq 0 ]
}

@test "QX-4 an unknown test id fails (file missing, or test name absent from the file)" {
  _commit_q 2026-10-20 "$(_row 'tests/unit/sample.bats::S-9 no such test' lead 2026-11-19 bd-open1 r)"
  run bash "$CQ" --repo "$R" --today 2026-10-24
  [ "$status" -eq 1 ]
  [[ "$output" == *"no such test"* ]]
  _commit_q 2026-10-20 "$(_row 'tests/unit/missing.bats::S-1 flaky thing' lead 2026-11-19 bd-open1 r)"
  run bash "$CQ" --repo "$R" --today 2026-10-24
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a bats file"* ]]
}

@test "QX-5 a duplicate test id fails" {
  _commit_q 2026-10-20 \
    "$(_row 'tests/unit/sample.bats::S-1 flaky thing' lead 2026-11-19 bd-open1 r)" \
    "$(_row 'tests/unit/sample.bats::S-1 flaky thing' lead 2026-11-19 bd-open1 r)"
  run bash "$CQ" --repo "$R" --today 2026-10-24
  [ "$status" -eq 1 ]
  [[ "$output" == *"duplicate"* ]]
}

@test "QX-6 a mandatory-gate test name is refused (egress, mount-home-scope, sandbox-mount)" {
  for name in egress-proxy mount-home-scope sandbox-mount; do
    cp "$R/tests/unit/sample.bats" "$R/tests/unit/$name.bats"
    _commit_q 2026-10-20 "$(_row "tests/unit/$name.bats::S-1 flaky thing" lead 2026-11-19 bd-open1 r)"
    run bash "$CQ" --repo "$R" --today 2026-10-24
    [ "$status" -eq 1 ]
    [[ "$output" == *"mandatory gate"* ]]
  done
}

@test "QX-7 the expiry must equal the quarantine author date + 30 days and lie within 60 days of today" {
  _commit_q 2026-10-20 "$(_row 'tests/unit/sample.bats::S-1 flaky thing' lead 2026-11-25 bd-open1 r)"
  run bash "$CQ" --repo "$R" --today 2026-10-24
  [ "$status" -eq 1 ]
  [[ "$output" == *"2026-11-19"* ]]
  # an uncommitted row is dated today: expiry today + 30 passes, + 61 fails
  printf '%s\n%s\n' "$HDR" "$(_row 'tests/unit/sample.bats::S-1 flaky thing' lead 2026-11-23 bd-open1 r)" > "$Q"
  run bash "$CQ" --repo "$R" --today 2026-10-24
  [ "$status" -eq 0 ]
  printf '%s\n%s\n' "$HDR" "$(_row 'tests/unit/sample.bats::S-1 flaky thing' lead 2026-12-24 bd-open1 r)" > "$Q"
  run bash "$CQ" --repo "$R" --today 2026-10-24
  [ "$status" -eq 1 ]
  [[ "$output" == *"60 days"* ]]
}

@test "QX-8 malformed rows fail: non-ISO expiry, empty owner, bad bead id, wrong column count, empty reason; bad header or missing file is a usage error" {
  local row
  for row in \
    "$(_row 'tests/unit/sample.bats::S-1 flaky thing' lead 19/11/2026 bd-open1 r)" \
    "$(_row 'tests/unit/sample.bats::S-1 flaky thing' lead 2026-02-30 bd-open1 r)" \
    "$(_row 'tests/unit/sample.bats::S-1 flaky thing' '' 2026-11-19 bd-open1 r)" \
    "$(_row 'tests/unit/sample.bats::S-1 flaky thing' lead 2026-11-19 'not a bead' r)" \
    "$(printf '%s\t%s' 'tests/unit/sample.bats::S-1 flaky thing' lead)" \
    "$(_row 'tests/unit/sample.bats::S-1 flaky thing' lead 2026-11-19 bd-open1 '')"; do
    _commit_q 2026-10-20 "$row"
    run bash "$CQ" --repo "$R" --today 2026-10-24
    [ "$status" -eq 1 ]
  done
  printf 'id\towner\n' > "$Q"
  run bash "$CQ" --repo "$R" --today 2026-10-24
  [ "$status" -eq 2 ]
  mv "$Q" "$Q.gone"
  run bash "$CQ" --repo "$R" --today 2026-10-24
  [ "$status" -eq 2 ]
  run bash "$CQ" --repo "$R" --today yesterday
  [ "$status" -eq 2 ]
}

@test "QX-9 the bead must exist and be open; without a beads CLI the run is degraded (exit 3), never a silent pass" {
  _commit_q 2026-10-20 "$(_row 'tests/unit/sample.bats::S-1 flaky thing' lead 2026-11-19 bd-closed1 r)"
  run bash "$CQ" --repo "$R" --today 2026-10-24
  [ "$status" -eq 1 ]
  [[ "$output" == *"closed"* ]]
  _commit_q 2026-10-20 "$(_row 'tests/unit/sample.bats::S-1 flaky thing' lead 2026-11-19 bd-nope9 r)"
  run bash "$CQ" --repo "$R" --today 2026-10-24
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
  _commit_q 2026-10-20 "$(_row 'tests/unit/sample.bats::S-1 flaky thing' lead 2026-11-19 bd-open1 r)"
  run env LOA_QUARANTINE_BR=/nonexistent/br bash "$CQ" --repo "$R" --today 2026-10-24
  [ "$status" -eq 3 ]
  [[ "$output" == *"unverified"* ]]
  # an expired row still fails (1) even when the bead check is degraded
  _commit_q 2026-09-01 "$(_row 'tests/unit/sample.bats::S-1 flaky thing' lead 2026-10-01 bd-open1 r)"
  run env LOA_QUARANTINE_BR=/nonexistent/br bash "$CQ" --repo "$R" --today 2026-10-24
  [ "$status" -eq 1 ]
}

@test "QX-10 a listed test whose file does not call the helper is refused (the row would not take effect)" {
  sed -i '/loa_quarantine_check/d' "$R/tests/unit/sample.bats"
  _commit_q 2026-10-20 "$(_row 'tests/unit/sample.bats::S-1 flaky thing' lead 2026-11-19 bd-open1 r)"
  run bash "$CQ" --repo "$R" --today 2026-10-24
  [ "$status" -eq 1 ]
  [[ "$output" == *"loa_quarantine_check"* ]]
}

@test "QX-11 --tap prints full-suite executed / skipped / quarantined totals" {
  _commit_q 2026-10-20
  cat > "$R/unit.tap" <<'TAP'
1..5
ok 1 a
ok 2 b # skip needs docker
not ok 3 c
ok 4 d # skip quarantined: until 2026-11-19 (bd-open1, owner lead): races
ok 5 e
TAP
  run bash "$CQ" --repo "$R" --today 2026-10-24 --tap "$R/unit.tap"
  [ "$status" -eq 0 ]
  [[ "$output" == *"executed=3 skipped=1 quarantined=1"* ]]
  run bash "$CQ" --repo "$R" --today 2026-10-24 --tap "$R/no-such.tap"
  [ "$status" -eq 2 ]
}

@test "QX-12 the helper skips a listed test with its reason and runs the rest" {
  _commit_q 2026-10-20 "$(_row 'tests/unit/sample.bats::S-1 flaky thing' lead 2026-11-19 bd-open1 'races the clock')"
  run npx --no-install bats --tap "$R/tests/unit/sample.bats"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok 1 S-1 flaky thing # skip quarantined: until 2026-11-19 (bd-open1, owner lead): races the clock"* ]]
  [[ "$output" == *"ok 2 S-2 steady thing"* ]]
  [[ "$output" != *"S-2 steady thing # skip"* ]]
}

@test "QX-13 the helper does not skip an expired row; the test runs (and here fails)" {
  _commit_q 2026-09-01 "$(_row 'tests/unit/sample.bats::S-1 flaky thing' lead 2026-10-01 bd-open1 r)"
  run npx --no-install bats --tap "$R/tests/unit/sample.bats"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not ok 1 S-1 flaky thing"* ]]
}

@test "QX-14 the helper refuses an id argument that does not match the running test" {
  sed -i 's|^  loa_quarantine_check$|  loa_quarantine_check "tests/unit/sample.bats::S-2 steady thing"|' "$R/tests/unit/sample.bats"
  _commit_q 2026-10-20
  run npx --no-install bats --tap "$R/tests/unit/sample.bats"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not ok 1 S-1 flaky thing"* ]]
  [[ "$output" == *"does not match the running test"* ]]
  [[ "$output" == *"ok 2 S-2 steady thing"* ]]
}

@test "QX-15 the helper refuses to skip a mandatory-gate test even when it is listed" {
  sed 's/^  false$/  true/' "$R/tests/unit/sample.bats" > "$R/tests/unit/sandbox-mount-home-scope.bats"
  _commit_q 2026-10-20 "$(_row 'tests/unit/sandbox-mount-home-scope.bats::S-1 flaky thing' lead 2026-11-19 bd-open1 r)"
  run npx --no-install bats --tap "$R/tests/unit/sandbox-mount-home-scope.bats"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not ok 1 S-1 flaky thing"* ]]
  [[ "$output" == *"mandatory gate"* ]]
}

@test "QX-16 the repository's own tests/QUARANTINE.tsv is valid today (structure; bead status when a workspace exists)" {
  unset LOA_QUARANTINE_BR
  run bash "$CQ" --repo "$PROJECT_ROOT"
  [ "$status" -eq 0 ] || [ "$status" -eq 3 ]
  [[ "$output" == *"quarantined="* ]]
}
