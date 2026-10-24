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
  # br stub mirroring br's --json shapes: success on stdout; a missing issue is
  # exit 3 with {"error":{"code":"ISSUE_NOT_FOUND",...}} on stderr; any other
  # failure is a different code. bd-obj1 answers with an object, bd-warn1 adds
  # a stderr warning, bd-eat1 reads stdin, bd-flaky1 fails with a message that
  # merely contains "not found".
  cat > "$R/bin/br" <<'BR'
#!/usr/bin/env bash
[[ "$1" == "show" ]] || exit 2
case "$2" in
  bd-open1)   printf '[{"id":"bd-open1","status":"open"}]\n' ;;
  bd-closed1) printf '[{"id":"bd-closed1","status":"closed"}]\n' ;;
  bd-obj1)    printf '{"id":"bd-obj1","status":"open"}\n' ;;
  bd-warn1)   echo "warning: database is 3 days stale" >&2; printf '[{"id":"bd-warn1","status":"open"}]\n' ;;
  bd-eat1)    cat >/dev/null; printf '[{"id":"bd-eat1","status":"open"}]\n' ;;
  bd-flaky1)  printf '{"error":{"code":"IO_ERROR","message":"config file not found: .beads/config.yaml"}}\n' >&2; exit 2 ;;
  *) printf '{"error":{"code":"ISSUE_NOT_FOUND","message":"Issue not found: %s"}}\n' "$2" >&2; exit 3 ;;
esac
BR
  chmod +x "$R/bin/br"
  export LOA_QUARANTINE_BR="$R/bin/br"
  mkdir -p "$R/.beads"   # a beads workspace exists; QX-21 removes it
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

# _git_commit <author day> <message> [<committer day>]
_git_commit() {
  GIT_AUTHOR_DATE="${1}T12:00:00Z" GIT_COMMITTER_DATE="${3:-$1}T12:00:00Z" \
    git -C "$R" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -q --allow-empty -m "$2"
}

# Write the quarantine file and commit it on the given day (YYYY-MM-DD).
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

@test "QX-7 the expiry must be the quarantine commit date + 30 days (one day of tolerance) and lie within 60 days of today" {
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

# --- follow-up d2 (Sprint 272 review round 1) --------------------------------

@test "QX-17 an empty owner is reported as such (empty fields survive the column split)" {
  _commit_q 2026-10-20 "$(_row 'tests/unit/sample.bats::S-1 flaky thing' '' 2026-11-19 bd-open1 r)"
  run bash "$CQ" --repo "$R" --today 2026-10-24
  [ "$status" -eq 1 ]
  [[ "$output" == *"owner is empty"* ]]
  [[ "$output" != *"not an ISO date"* ]]
}

@test "QX-18 a TAP file with no test lines is a usage error, never zero totals" {
  _commit_q 2026-10-20
  printf '1..0\n# nothing ran\n' > "$R/empty.tap"
  run bash "$CQ" --repo "$R" --today 2026-10-24 --tap "$R/empty.tap"
  [ "$status" -eq 2 ]
  [[ "$output" == *"no TAP test lines found"* ]]
  [[ "$output" != *"executed=0"* ]]
}

@test "QX-19 a br failure that merely says 'not found' is unverified (exit 3), not a missing bead" {
  _commit_q 2026-10-20 "$(_row 'tests/unit/sample.bats::S-1 flaky thing' lead 2026-11-19 bd-flaky1 r)"
  run bash "$CQ" --repo "$R" --today 2026-10-24
  [ "$status" -eq 3 ]
  [[ "$output" == *"unverified"* ]]
  [[ "$output" != *"bead bd-flaky1 not found"* ]]
}

@test "QX-20 br --json answering with an object, or with a stderr warning, still parses" {
  _commit_q 2026-10-20 "$(_row 'tests/unit/sample.bats::S-1 flaky thing' lead 2026-11-19 bd-obj1 r)"
  run bash "$CQ" --repo "$R" --today 2026-10-24
  [ "$status" -eq 0 ]
  _commit_q 2026-10-20 "$(_row 'tests/unit/sample.bats::S-1 flaky thing' lead 2026-11-19 bd-warn1 r)"
  run bash "$CQ" --repo "$R" --today 2026-10-24
  [ "$status" -eq 0 ]
}

@test "QX-21 no .beads directory in the repository means unverified (exit 3) before br is called" {
  find "$R/.beads" -depth -delete
  _commit_q 2026-10-20 "$(_row 'tests/unit/sample.bats::S-1 flaky thing' lead 2026-11-19 bd-open1 r)"
  run bash "$CQ" --repo "$R" --today 2026-10-24
  [ "$status" -eq 3 ]
  [[ "$output" == *"no beads workspace"* ]]
}

@test "QX-22 br cannot consume the row loop's stdin: every row is still validated" {
  cp "$R/tests/unit/sample.bats" "$R/tests/unit/other.bats"
  _commit_q 2026-10-20 \
    "$(_row 'tests/unit/sample.bats::S-1 flaky thing' lead 2026-11-19 bd-eat1 r)" \
    "$(_row 'tests/unit/other.bats::S-1 flaky thing' '' 2026-11-19 bd-open1 r)"
  run bash "$CQ" --repo "$R" --today 2026-10-24
  [[ "$output" == *"rows=2"* ]]
  [[ "$output" == *"owner is empty"* ]]
  [ "$status" -eq 1 ]
}

@test "QX-23 the quarantine date is the COMMITTER date: a rebased row (old author date) is judged by its commit" {
  printf '%s\n%s\n' "$HDR" "$(_row 'tests/unit/sample.bats::S-1 flaky thing' lead 2026-11-19 bd-open1 r)" > "$Q"
  git -C "$R" add -A
  _git_commit 2026-09-01 quarantine 2026-10-20
  run bash "$CQ" --repo "$R" --today 2026-10-24
  [ "$status" -eq 0 ]
  printf '%s\n%s\n' "$HDR" "$(_row 'tests/unit/sample.bats::S-1 flaky thing' lead 2026-10-01 bd-open1 r)" > "$Q"
  git -C "$R" add -A
  _git_commit 2026-09-01 quarantine 2026-10-20
  run bash "$CQ" --repo "$R" --today 2026-09-20
  [ "$status" -eq 1 ]
  [[ "$output" == *"2026-11-19"* ]]
}

@test "QX-24 the exact rule tolerates one day: quarantine date + 30 or + 31 passes, + 29 and + 32 fail" {
  local exp rc
  for exp in 2026-11-19:0 2026-11-20:0 2026-11-18:1 2026-11-21:1; do
    _commit_q 2026-10-20 "$(_row 'tests/unit/sample.bats::S-1 flaky thing' lead "${exp%:*}" bd-open1 r)"
    rc=0; bash "$CQ" --repo "$R" --today 2026-10-24 >/dev/null 2>&1 || rc=$?
    [ "$rc" -eq "${exp#*:}" ] || { echo "expiry ${exp%:*}: exit $rc, expected ${exp#*:}" >&2; return 1; }
  done
}

@test "QX-25 in a shallow clone a row blamed on the boundary commit is judged against today + 30 (+1 day), not the boundary date" {
  _commit_q 2026-10-20 "$(_row 'tests/unit/sample.bats::S-1 flaky thing' lead 2026-11-24 bd-open1 r)"
  _git_commit 2026-10-10 later
  local S="$R.shallow"
  git clone -q --depth 1 "file://$R" "$S"
  mkdir -p "$S/.beads"
  [ "$(git -C "$S" rev-parse --is-shallow-repository)" = "true" ]
  # boundary date 2026-10-10 + 30 = 2026-11-09 would refuse 2026-11-24; today + 31 = 2026-11-24 accepts it
  run bash "$CQ" --repo "$S" --today 2026-10-24
  [ "$status" -eq 0 ]
  run bash "$CQ" --repo "$S" --today 2026-10-20
  [ "$status" -eq 1 ]
  [[ "$output" == *"shallow"* ]]
  find "$S" -mindepth 1 -delete; rmdir "$S"
}

@test "QX-26 the CI gate step tells a usage failure (2) from invalid rows (1) and warns on 3" {
  local wf="$PROJECT_ROOT/.github/workflows/bats-tests.yml" step rc
  step="$(yq -r '.jobs.bats.steps[] | select(.name == "Quarantine gate (check-quarantine-expiry.sh)") | .run' "$wf")"
  [ -n "$step" ]
  mkdir -p "$R/ci/tools"
  for rc in 1 2 3; do
    printf '#!/usr/bin/env bash\nexit %s\n' "$rc" > "$R/ci/tools/check-quarantine-expiry.sh"
    run bash -c "cd '$R/ci' && $step"
    case "$rc" in
      1) [ "$status" -eq 1 ]; [[ "$output" == *"rows invalid or expired"* ]] ;;
      2) [ "$status" -eq 2 ]; [[ "$output" == *"usage"* ]]; [[ "$output" != *"invalid or expired"* ]] ;;
      3) [ "$status" -eq 0 ]; [[ "$output" == *"::warning::"* ]] ;;
    esac
  done
}

@test "QX-27 an empty bead column is reported as such, not shifted into the reason" {
  _commit_q 2026-10-20 "$(_row 'tests/unit/sample.bats::S-1 flaky thing' lead 2026-11-19 '' r)"
  run bash "$CQ" --repo "$R" --today 2026-10-24
  [ "$status" -eq 1 ]
  [[ "$output" == *'bead "" is not a bead id'* ]]
}
