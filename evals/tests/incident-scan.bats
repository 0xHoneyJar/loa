#!/usr/bin/env bats
# =============================================================================
# evals/tests/incident-scan.bats — cycle-132 Sprint 1 Task 1.2 (FR-2, SDD §1.4,
# §5.2, D-2.1, D-7.8)
#
# incident-scan.sh over a synthetic repository: a feature branch (head, fix)
# merged into main as PR #7 on 2026-10-10, then post-merge commits, a
# known-failures file on main and a record branch with Bridgebuilder rounds.
# Proves: one window (merge date → scan date) for every source; a fix commit
# before the merge, outside the window, not a fix, or on an unchanged file is
# not counted; evidence files exist per incident; the meta carries the counts,
# the SHA, the window and the maturity; --no-gh records no queries; the gh
# source is paginated and its completeness recorded (gh stubbed on PATH).
# =============================================================================

setup() {
  TESTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$TESTS_DIR/../.." && pwd)"
  SCAN="$REPO_ROOT/evals/harness/incident-scan.sh"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/is.XXXXXX")"
  G="$T/repo"; C="$T/corpus"; O="$T/out"
  mkdir -p "$G" "$C"
  export INCIDENT_SCAN_GH_PAUSE=0
  FAKE_KEY="AKIA$(printf 'QZ%.0s' 1 2 3 4 5 6 7 8)"
  git -C "$G" init -q -b main
  at() { GIT_COMMITTER_DATE="$1" GIT_AUTHOR_DATE="$1" git -C "$G" -c user.email=t@t -c user.name=t "${@:2}"; }
  mkdir -p "$G/scripts" "$G/docs" "$G/grimoires/loa"
  printf 'a1\na2\na3\n' > "$G/scripts/a.sh"; printf 'b1\nb2\n' > "$G/scripts/b.sh"; printf 'doc\n' > "$G/docs/x.md"
  at 2026-10-01T00:00:00Z add -A; at 2026-10-01T00:00:00Z commit -q -m "base"
  BASE="$(git -C "$G" rev-parse HEAD)"
  at 2026-10-02T00:00:00Z checkout -q -b feature
  printf 'a1\nA2\na3\n' > "$G/scripts/a.sh"; printf 'b1\nB2\n' > "$G/scripts/b.sh"
  at 2026-10-03T00:00:00Z add -A; at 2026-10-03T00:00:00Z commit -q -m "feat: sprint-9 the change (round 1)"
  HEAD_C="$(git -C "$G" rev-parse HEAD)"
  printf 'a1\nA2-fixed\na3\n' > "$G/scripts/a.sh"
  at 2026-10-04T00:00:00Z add -A; at 2026-10-04T00:00:00Z commit -q -m "fix: sprint-9 review round 1"
  FIX="$(git -C "$G" rev-parse HEAD)"
  at 2026-10-05T00:00:00Z checkout -q main
  # a fix on main before the merge, on a changed file: an ancestor of the merge, never counted
  printf 'doc2\n' > "$G/docs/x.md"; printf 'pre\n' > "$G/scripts/pre.sh"
  at 2026-10-06T00:00:00Z add -A; at 2026-10-06T00:00:00Z commit -q -m "fix: an earlier main-only change"
  at 2026-10-10T00:00:00Z merge -q --no-ff feature -m "Merge pull request #7 from x/feature"
  MERGE="$(git -C "$G" rev-parse HEAD)"
  # after the merge: counted (fix, changed file, in window) …
  printf 'a1\nA2-fixed\na3\na4 guard\n' > "$G/scripts/a.sh"
  at 2026-10-12T00:00:00Z add -A
  at 2026-10-12T00:00:00Z commit -q -m "fix(a): post-merge guard for the empty value" -m "$(printf 'body\twith a tab and an escape \033[0m %0.s........' $(seq 1 60))"
  POST="$(git -C "$G" rev-parse HEAD)"
  # … and not counted: not a fix; a fix on an unchanged file; a fix after the scan date
  printf 'a1\nA2-fixed\na3\na4 guard\na5\n' > "$G/scripts/a.sh"
  at 2026-10-13T00:00:00Z add -A; at 2026-10-13T00:00:00Z commit -q -m "feat: more behaviour"
  printf 'doc3\n' > "$G/docs/x.md"
  at 2026-10-14T00:00:00Z add -A; at 2026-10-14T00:00:00Z commit -q -m "fix: docs only"
  cat > "$G/grimoires/loa/known-failures.md" <<EOF
# Known failures

## KF-001: the empty value passes scripts/a.sh

**First observed**: 2026-10-11 after the merge; key seen in a log: $FAKE_KEY

## KF-002: an old failure in scripts/b.sh

**First observed**: 2026-09-01

## KF-003: docs/x.md drift

**First observed**: 2026-10-11
EOF
  at 2026-10-15T00:00:00Z add -A; at 2026-10-15T00:00:00Z commit -q -m "chore: known failures"
  printf 'b1\nB2\nlate\n' > "$G/scripts/b.sh"
  at 2026-11-30T00:00:00Z add -A; at 2026-11-30T00:00:00Z commit -q -m "fix: late change to b"
  MAIN="$(git -C "$G" rev-parse HEAD)"
  # the record branch: rounds on PR #7 before and after the merge, and one on PR #8
  at 2026-10-20T00:00:00Z checkout -q --orphan record/cycle-9-a2a
  git -C "$G" rm -rq --cached .; find "$G" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
  mkdir -p "$G/grimoires/loa/a2a/sprint-9"
  printf '# Bridgebuilder triage — PR #7, round 1\n\nRun bridgebuilder-20261009T120000-aaaa; scripts/a.sh fixed.\n' > "$G/grimoires/loa/a2a/sprint-9/bridgebuilder-triage.md"
  printf '# Bridgebuilder triage — PR #7, round 2\n\nRun bridgebuilder-20261015T000000-bbbb: scripts/a.sh still accepts an empty value.\n' > "$G/grimoires/loa/a2a/sprint-9/bb-triage-r2.md"
  printf '# Bridgebuilder triage — PR #8\n\nRun bridgebuilder-20261016T000000-cccc: scripts/a.sh; see also PR #7.\n' > "$G/grimoires/loa/a2a/sprint-9/bridgebuilder-other.md"
  at 2026-10-20T00:00:00Z add -A; at 2026-10-20T00:00:00Z commit -q -m "record"
  at 2026-10-20T00:00:00Z checkout -q main
  # the fixture
  mkdir -p "$C/pr-50"
  printf 'name: pr-50\nsprint: 9\nbase_commit: "%s"\nhead_commit: "%s"\nfix_commit: "%s"\nrecord_ref: "record/cycle-9-a2a"\n' "$BASE" "$HEAD_C" "$FIX" > "$C/pr-50/fixture.yaml"
  git -C "$G" diff "$BASE" "$HEAD_C" > "$C/pr-50/head.diff"
  ARGS=(--repo "$G" --corpus "$C" --out "$O" --main-ref main --record-refs record/cycle-9-a2a --scan-date 2026-11-01T00:00:00Z)
}

teardown() { find "$T" -mindepth 1 -delete 2>/dev/null || true; rmdir "$T" 2>/dev/null || true; }

@test "IS-1 one window (merge → scan) over the git, Bridgebuilder and KF sources; out-of-window, non-fix and unchanged-file items are not counted" {
  run "$SCAN" pr-50 "${ARGS[@]}" --no-gh
  [ "$status" -eq 0 ]
  F="$O/pr-50.tsv"
  [ "$(head -1 "$F")" = "$(printf 'id\tkind\tref\tdate\tfiles\texcerpt')" ]
  [ "$(tail -n +2 "$F" | cut -f1-5 | tr '\t' '|')" = "$(printf '%s\n' \
    "I01|kf|KF-001|2026-10-11T00:00:00Z|scripts/a.sh" \
    "I02|fix-commit|${POST:0:12}|2026-10-12T00:00:00Z|scripts/a.sh" \
    "I03|bridgebuilder|record/cycle-9-a2a:grimoires/loa/a2a/sprint-9/bb-triage-r2.md|2026-10-15T00:00:00Z|scripts/a.sh")" ]
  # never counted: the pre-merge main fix, the feat commit, the docs-only fix, the post-scan fix,
  # the pre-merge round, the PR #8 round, the pre-merge KF and the KF on an unchanged file
  ! grep -qE 'earlier main-only|more behaviour|docs only|late change|KF-002|KF-003|bridgebuilder-other|bridgebuilder-triage.md' "$F"
}

@test "IS-2 every incident has its evidence file; the fix-commit diff is restricted to the changed files; third-party text is fenced and secrets redacted" {
  run "$SCAN" pr-50 "${ARGS[@]}" --no-gh
  [ "$status" -eq 0 ]
  E="$O/pr-50/evidence"
  [ "$(ls "$E" | tr '\n' ,)" = "I01.md,I02.diff,I03.md," ]
  grep -q '^diff --git a/scripts/a.sh b/scripts/a.sh' "$E/I02.diff"
  ! grep -q 'docs/x.md' "$E/I02.diff"
  grep -q "^commit $POST" "$E/I02.diff"
  head -1 "$E/I01.md" | grep -q '^~~~~markdown$'
  grep -q 'REDACTED-SECRET' "$E/I01.md"
  ! grep -rqF "$FAKE_KEY" "$O"
  run bash "$REPO_ROOT/evals/graders/no-secrets.sh" "$O"
  [ "$status" -eq 0 ]
}

@test "IS-3 the meta records the main SHA, the merge, the PR, the window, per-source counts, no gh queries under --no-gh and the maturity" {
  run "$SCAN" pr-50 "${ARGS[@]}" --no-gh
  [ "$status" -eq 0 ]
  M="$O/pr-50.meta.json"
  [ "$(jq -r '.main_sha' "$M")" = "$MAIN" ]
  [ "$(jq -r '.merge_commit' "$M")" = "$MERGE" ]
  [ "$(jq -r '.merge_date' "$M")" = "2026-10-10T00:00:00Z" ]
  [ "$(jq -r '.pr' "$M")" = "7" ]
  [ "$(jq -r '.window.from + " " + .window.to' "$M")" = "2026-10-10T00:00:00Z 2026-11-01T00:00:00Z" ]
  [ "$(jq -c '.counts' "$M")" = '{"bridgebuilder":1,"fix-commit":1,"issue":0,"kf":1}' ]
  [ "$(jq -c '.gh_queries' "$M")" = "[]" ]
  [ "$(jq -r '.gh' "$M")" = "skipped" ]
  [ "$(jq -r '.truncated' "$M")" = "false" ]
  [ "$(jq -r '.maturity_days' "$M")" = "22" ]
  [ "$(jq -r '.scanned_at' "$M")" = "2026-11-01T00:00:00Z" ]
}

@test "IS-4 excerpts are control-stripped and at most 400 characters; a rescan is byte-identical and replaces stale evidence" {
  run "$SCAN" pr-50 "${ARGS[@]}" --no-gh
  [ "$status" -eq 0 ]
  local ex; ex="$(awk -F'\t' '$2 == "fix-commit" {print $6}' "$O/pr-50.tsv")"
  [ "${#ex}" -le 400 ]
  [[ "$ex" == "fix(a): post-merge guard"* ]]
  ! printf '%s' "$ex" | LC_ALL=C grep -q $'\033'
  [ "$(awk -F'\t' '{print NF}' "$O/pr-50.tsv" | sort -u)" = "6" ]
  cp -R "$O" "$T/first"
  touch "$O/pr-50/evidence/I99.md"
  run "$SCAN" pr-50 "${ARGS[@]}" --no-gh
  [ "$status" -eq 0 ]
  diff -r "$O" "$T/first"
}

@test "IS-5 --window-days caps the window; a window that ends before an item drops it" {
  run "$SCAN" pr-50 "${ARGS[@]}" --no-gh --window-days 1
  [ "$status" -eq 0 ]
  [ "$(tail -n +2 "$O/pr-50.tsv" | cut -f2 | tr '\n' ,)" = "kf," ]
  [ "$(jq -r '.window.to' "$O/pr-50.meta.json")" = "2026-10-11T00:00:00Z" ]
  [ "$(jq -r '.maturity_days' "$O/pr-50.meta.json")" = "22" ]
}

@test "IS-6 refusals: a missing fixture, a fix commit not on the main ref and a missing ref exit 1; usage errors exit 2" {
  run "$SCAN" pr-51 "${ARGS[@]}" --no-gh
  [ "$status" -eq 1 ]
  # a fix commit on an unmerged branch
  git -C "$G" checkout -q -b side "$HEAD_C"
  printf 'side\n' > "$G/scripts/a.sh"; git -C "$G" -c user.email=t@t -c user.name=t commit -qam "fix: unmerged"
  local SIDE; SIDE="$(git -C "$G" rev-parse HEAD)"; git -C "$G" checkout -q main
  mkdir -p "$C/pr-52"; cp "$C/pr-50/head.diff" "$C/pr-52/"
  sed "s/$FIX/$SIDE/" "$C/pr-50/fixture.yaml" > "$C/pr-52/fixture.yaml"
  run "$SCAN" pr-52 "${ARGS[@]}" --no-gh
  [ "$status" -eq 1 ]; grep -q 'is not on main' <<<"$output"
  [ ! -e "$O/pr-52.tsv" ]
  run "$SCAN" pr-50 --repo "$G" --corpus "$C" --out "$O" --main-ref nope --no-gh
  [ "$status" -eq 1 ]
  run "$SCAN" pr-50 "${ARGS[@]}" --no-gh --record-refs record/nope
  [ "$status" -eq 1 ]
  run "$SCAN"
  [ "$status" -eq 2 ]
  run "$SCAN" pr-50 "${ARGS[@]}" --no-gh --window-days 0
  [ "$status" -eq 2 ]
  run "$SCAN" pr-50 "${ARGS[@]}" --no-gh --scan-date 2026-10-01T00:00:00Z
  [ "$status" -eq 2 ]
}

# a gh stub: prints the pages in $GH_PAGES (concatenated JSON, as `gh api --paginate` does) and logs its argv
make_gh_stub() {
  mkdir -p "$T/bin"
  cat > "$T/bin/gh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_LOG"
cat "$GH_PAGES"
SH
  chmod +x "$T/bin/gh"
  export GH_LOG="$T/gh.log" GH_PAGES="$T/pages.json"
}

@test "IS-7 the gh source: paginated pages are all read, an item is kept only when created in the window and citing a changed path; completeness recorded" {
  make_gh_stub
  {
    printf '{"total_count":3,"incomplete_results":false,"items":['
    printf '{"number":11,"title":"empty value","body":"scripts/a.sh accepts an empty value\\u0007","created_at":"2026-10-20T00:00:00Z","state":"open","html_url":"u11"},'
    printf '{"number":12,"title":"unrelated","body":"no path here","created_at":"2026-10-20T00:00:00Z","state":"open","html_url":"u12"}]}'
    printf '{"total_count":3,"incomplete_results":false,"items":['
    printf '{"number":13,"title":"old","body":"scripts/b.sh","created_at":"2026-10-01T00:00:00Z","state":"closed","html_url":"u13"}]}'
  } > "$GH_PAGES"
  PATH="$T/bin:$PATH" run "$SCAN" pr-50 "${ARGS[@]}"
  [ "$status" -eq 0 ]
  [ "$(awk -F'\t' '$2 == "issue" {print $3 "|" $5}' "$O/pr-50.tsv")" = "#11|scripts/a.sh" ]
  M="$O/pr-50.meta.json"
  [ "$(jq -r '.gh_queries | length' "$M")" = "1" ]
  [ "$(jq -r '.gh_queries[0].pages' "$M")" = "2" ]
  [ "$(jq -r '.gh_queries[0].total_count' "$M")" = "3" ]
  [ "$(jq -r '.gh_queries[0].kept' "$M")" = "1" ]
  [ "$(jq -r '.truncated' "$M")" = "false" ]
  [ "$(jq -r '.counts.issue' "$M")" = "1" ]
  grep -q -- '--paginate' "$GH_LOG"
  grep -q 'repo:0xHoneyJar/loa created:>=2026-10-10 "a.sh" OR "b.sh"' "$GH_LOG"
  local id; id="$(awk -F'\t' '$2 == "issue" {print $1}' "$O/pr-50.tsv")"
  grep -q '^# issue #11: empty value' "$O/pr-50/evidence/$id.md"
  ! LC_ALL=C grep -q $'\a' "$O/pr-50/evidence/$id.md"
}

@test "IS-8 an incomplete or short gh result marks the scan truncated; a gh failure refuses (exit 1) and writes nothing" {
  make_gh_stub
  printf '{"total_count":5,"incomplete_results":true,"items":[]}' > "$GH_PAGES"
  PATH="$T/bin:$PATH" run "$SCAN" pr-50 "${ARGS[@]}"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.truncated' "$O/pr-50.meta.json")" = "true" ]
  grep -q 'TRUNCATED' <<<"$output"
  rm -rf "$O"
  printf '#!/usr/bin/env bash\necho "HTTP 500" >&2\nexit 1\n' > "$T/bin/gh"
  PATH="$T/bin:$PATH" run "$SCAN" pr-50 "${ARGS[@]}"
  [ "$status" -eq 1 ]
  [ ! -e "$O/pr-50.tsv" ]
}
