#!/usr/bin/env bats
# =============================================================================
# record-branch.bats — .claude/scripts/record-branch.sh (cycle-133 Sprint 1
# Task 1.4, SDD C-4, PRD FR-4(a)).
#
# Hermetic: every test builds a fixture repository with a bare `origin`, a
# ledger naming cycle-133, gitignored record paths and a results batch whose
# sandbox/, snapshots/ and grading/pr/ must stay out of the record. The script
# under test runs from this checkout with the fixture as its working directory.
#
# Planted secrets are assembled at run time so this file never carries a
# credential-shaped literal or the scanner's forbidden assignment literal.
# =============================================================================

setup() {
  BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO="$(cd "$BATS_TEST_DIR/../.." && pwd)"
  RB="$REPO/.claude/scripts/record-branch.sh"
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
  export GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.invalid
  export GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.invalid
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  W="$BATS_TEST_TMPDIR"
  O="$W/origin.git"
  F="$W/repo"
  REF=refs/heads/record/cycle-133-fixture
  git init -q --bare "$O"
  git init -q -b main "$F"
  git -C "$F" remote add origin "$O"
  mkdir -p "$F/grimoires/loa"
  cat > "$F/.gitignore" <<'EOF'
grimoires/loa/a2a/*
grimoires/loa/NOTES.md
grimoires/loa/archive/
evals/results/*
EOF
  jq -n '{schema_version: 1, next_sprint_number: 273, active_cycle: "cycle-133-fixture",
          cycles: [
            {id: "cycle-132-old", status: "archived", created: "2026-10-21T00:48:44Z", archived: "2026-10-23T16:49:48Z",
             sprints: [{global_id: 271, local_label: "sprint-3"}]},
            {id: "cycle-133-fixture", status: "active", created: "2026-10-23T21:25:35Z", archived: null,
             sprints: [{global_id: 272, local_label: "sprint-1"}]}],
          bugfix_cycles: [{id: "cycle-bug-20261024-abcdef", created_at: "2026-10-23T22:00:00Z",
             sprints: ["sprint-bug-300"], triage: "grimoires/loa/a2a/bug-20261024-abcdef/triage.md"}],
          bugfixes: []}' > "$F/grimoires/loa/ledger.json"
  printf 'tracked\n' > "$F/README.md"
  git -C "$F" add -A && git -C "$F" commit -q -m base
  git -C "$F" push -q origin main
  HEAD_SHA="$(git -C "$F" rev-parse HEAD)"
  # the previous cycle's record: a public commit on origin
  git -C "$F" checkout -q -b record/cycle-132-old
  printf 'old record\n' > "$F/old-record.txt"
  git -C "$F" add old-record.txt && git -C "$F" commit -q -m "record(cycle-132-old): stage 1"
  git -C "$F" push -q origin record/cycle-132-old
  PREV_SHA="$(git -C "$F" rev-parse HEAD)"
  git -C "$F" checkout -q main
  rm -f "$F/old-record.txt"
  # the gitignored records
  local a="$F/grimoires/loa/a2a" r="$F/evals/results/ablation-2.0"
  mkdir -p "$a/sprint-272" "$a/sprint-271" "$a/flatline" "$a/prompts" "$a/audits/2026-10-23" "$a/audits/2020-01-01" \
           "$a/bug-20261024-abcdef" "$a/sprint-bug-300" "$F/grimoires/loa/archive/notes" \
           "$r/c133-b1/cell-a/run-1/sandbox" "$r/c133-b1/cell-a/run-1/snapshots" "$r/c133-b1/cell-a/run-1/grading/pr" \
           "$r/c133-lite" "$r/c132-old"
  printf 'reviewer report\n' > "$a/sprint-272/reviewer.md"
  printf 'previous cycle\n' > "$a/sprint-271/reviewer.md"
  printf '{"consensus": 1}\n' > "$a/flatline/prd-flatline-1-final_consensus.json"
  ln -s prd-flatline-1-final_consensus.json "$a/flatline/prd-final_consensus.json"
  printf 'prompt\n' > "$a/prompts/next.md"
  printf 'audit\n' > "$a/audits/2026-10-23/AUDIT.md"
  printf 'ancient audit\n' > "$a/audits/2020-01-01/AUDIT.md"
  printf 'triage\n' > "$a/bug-20261024-abcdef/triage.md"
  printf 'bug sprint\n' > "$a/sprint-bug-300/reviewer.md"
  printf '## Blockers\n\nNone.\n' > "$F/grimoires/loa/NOTES.md"
  printf 'archived notes\n' > "$F/grimoires/loa/archive/notes/NOTES-20261023T000000Z.md"
  printf '{"batch": "c133-b1"}\n' > "$r/c133-b1/MANIFEST.json"
  printf '{"row": 1}\n' > "$r/c133-b1/rows.jsonl"
  printf '{"grade": 1}\n' > "$r/c133-b1/cell-a/run-1/grade.json"
  printf 'gates\n' > "$r/c133-b1/cell-a/run-1/grading/gates-combined.md"
  printf 'sandbox file\n' > "$r/c133-b1/cell-a/run-1/sandbox/src.py"
  printf 'snapshot\n' > "$r/c133-b1/cell-a/run-1/snapshots/s.tar"
  printf 'pr grading\n' > "$r/c133-b1/cell-a/run-1/grading/pr/diff.patch"
  printf '{"index": 1}\n' > "$r/c133-lite/INDEX.json"
  printf 'old batch\n' > "$r/c132-old/rows.jsonl"
  cd "$F"
}

rb() { bash "$RB" --cycle 133 --head "$HEAD_SHA" --prev "$PREV_SHA" --stage "stage 1" "$@"; }
tree_of() { git ls-tree -r --name-only "$1"; }
# the staged tree sha the script names in its refusal line
scan_tree_from() { printf '%s\n' "$1" | sed -n 's/.*scan_tree=\([0-9a-f]\{40,64\}\).*/\1/p' | head -1; }
gh_token() { printf '%s%s' 'gh' 'p_'; printf 'Ab1Cd2Ef3Gh4%.0s' 1 2 3; }
pw_assign() { printf '%s%s' 'LOA_AUDIT_KEY_' 'PASSWORD='; }

@test "record-branch: builds the record from the ledger cycle (paths present, sandbox, snapshots, grading/pr absent)" {
  git status --porcelain --ignored > "$W/status.before"
  run rb
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  c="$(git rev-parse "$REF")"
  [ "$(git rev-parse "$c^1")" = "$PREV_SHA" ]
  [ "$(git rev-parse "$c^2")" = "$HEAD_SHA" ]
  t="$(tree_of "$c")"
  for p in README.md grimoires/loa/a2a/sprint-272/reviewer.md grimoires/loa/a2a/flatline/prd-final_consensus.json \
           grimoires/loa/a2a/prompts/next.md grimoires/loa/a2a/audits/2026-10-23/AUDIT.md \
           grimoires/loa/a2a/bug-20261024-abcdef/triage.md grimoires/loa/a2a/sprint-bug-300/reviewer.md \
           grimoires/loa/NOTES.md grimoires/loa/archive/notes/NOTES-20261023T000000Z.md \
           evals/results/ablation-2.0/c133-b1/MANIFEST.json evals/results/ablation-2.0/c133-b1/cell-a/run-1/grade.json \
           evals/results/ablation-2.0/c133-b1/cell-a/run-1/grading/gates-combined.md \
           evals/results/ablation-2.0/c133-lite/INDEX.json; do
    grep -qxF "$p" <<<"$t" || { echo "missing $p"; false; }
  done
  for p in sandbox/ snapshots/ grading/pr/ c132-old/ sprint-271/ audits/2020-01-01/; do
    ! grep -qF "$p" <<<"$t" || { echo "unexpected $p"; false; }
  done
  # the in-record symlink travels as a symlink to a recorded sibling
  [ "$(git ls-tree "$c" -- grimoires/loa/a2a/flatline/prd-final_consensus.json | cut -c1-6)" = "120000" ]
  # working tree and real index untouched
  git status --porcelain --ignored > "$W/status.after"
  diff "$W/status.before" "$W/status.after"
  [ -z "$(git diff --cached --name-only)" ]
}

@test "record-branch: the manifest in the tree carries cycle, parents, stage, scan_tree and accepted_scan" {
  run rb
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  m="$(git show "$REF:grimoires/loa/a2a/record-manifests/cycle-133-fixture/stage-1.json")"
  [ "$(jq -r .cycle <<<"$m")" = "cycle-133-fixture" ]
  [ "$(jq -r .head <<<"$m")" = "$HEAD_SHA" ]
  [ "$(jq -r .prev <<<"$m")" = "$PREV_SHA" ]
  [ "$(jq -r .stage <<<"$m")" = "stage 1" ]
  [ "$(jq -r '.scan_tree | length' <<<"$m")" -ge 40 ]
  [ "$(jq -r '.accepted_scan | length' <<<"$m")" -eq 0 ]
  [ "$(jq -r '.lite_tree' <<<"$m")" = "evals/results/ablation-2.0/c133-lite" ]
  jq -e '.results_roots == ["evals/results/ablation-2.0/c133-b1"]' <<<"$m" >/dev/null
  git log -1 --format=%B "$REF" | grep -q "scan_tree: $(jq -r .scan_tree <<<"$m")"
}

@test "record-branch: a symlink leaving the repository is refused before staging (exit 2, no ref, no objects)" {
  printf 'outside secret\n' > "$W/outside.txt"
  ln -s "$W/outside.txt" grimoires/loa/a2a/sprint-272/leak.txt
  before="$(git count-objects -v | sed -n 's/^count: //p')"
  run rb
  [ "$status" -eq 2 ]
  [[ "$output" == *"grimoires/loa/a2a/sprint-272/leak.txt"* ]]
  [[ "$output" == *"symlink"* ]]
  ! git rev-parse --verify --quiet "$REF"
  [ "$(git count-objects -v | sed -n 's/^count: //p')" = "$before" ]
}

@test "record-branch: a symlink to an in-repository path that is not recorded is refused" {
  printf 'X=1\n' > .env
  ln -s ../../../../.env grimoires/loa/a2a/sprint-272/env-link
  run rb
  [ "$status" -eq 2 ]
  [[ "$output" == *"env-link"* ]]
  ! git rev-parse --verify --quiet "$REF"
}

@test "record-branch: an escaping --add path and a path through a symlinked directory are refused" {
  printf 'x\n' > "$W/outside.txt"
  run rb --add ../outside.txt
  [ "$status" -eq 2 ]
  [[ "$output" == *"outside the repository"* ]]
  mkdir -p "$W/elsewhere"; printf 'y\n' > "$W/elsewhere/f.txt"
  ln -s "$W/elsewhere" linked-dir
  run rb --add linked-dir/f.txt
  [ "$status" -eq 2 ]
  [[ "$output" == *"linked-dir"* ]]
  ! git rev-parse --verify --quiet "$REF"
}

@test "record-branch: a planted credential-shaped string stops the build even with --accept-scan for that tree" {
  printf 'token: %s\n' "$(gh_token)" > grimoires/loa/a2a/sprint-272/transcript.txt
  run rb
  [ "$status" -eq 2 ]
  [[ "$output" == *"grimoires/loa/a2a/sprint-272/transcript.txt:1"* ]]
  [[ "$output" == *"github-token"* ]]
  [[ "$output" != *"$(gh_token)"* ]]          # the secret is never echoed
  tree="$(scan_tree_from "$output")"
  [ -n "$tree" ]
  run rb --accept-scan "$tree"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not bypassable"* ]]
  ! git rev-parse --verify --quiet "$REF"
}

@test "record-branch: a non-credential hit is accepted only for the named tree and recorded" {
  printf 'export %sredacted\n' "$(pw_assign)" > grimoires/loa/a2a/sprint-272/notes.md
  run rb
  [ "$status" -eq 2 ]
  [[ "$output" == *"grimoires/loa/a2a/sprint-272/notes.md:1"* ]]
  [[ "$output" == *"--accept-scan"* ]]
  tree="$(scan_tree_from "$output")"
  [ -n "$tree" ]
  wrong="$(printf '%040d' 0 | tr 0 a)"
  run rb --accept-scan "$wrong"
  [ "$status" -eq 2 ]
  [[ "$output" == *"$tree"* ]]
  ! git rev-parse --verify --quiet "$REF"
  run rb --accept-scan "$tree"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  msg="$(git log -1 --format=%B "$REF")"
  [[ "$msg" == *"scan_tree: $tree"* ]]
  [[ "$msg" == *"accepted_scan: grimoires/loa/a2a/sprint-272/notes.md:1 audit-key-password-assignment"* ]]
  m="$(git show "$REF:grimoires/loa/a2a/record-manifests/cycle-133-fixture/stage-1.json")"
  [ "$(jq -r .scan_tree <<<"$m")" = "$tree" ]
  jq -e '.accepted_scan == [{"class":"audit-key-password-assignment","line":1,"path":"grimoires/loa/a2a/sprint-272/notes.md"}]' <<<"$m" >/dev/null
}

@test "record-branch: the record ref moved away from --prev is refused (compare-and-swap), ref unchanged" {
  other="$(git commit-tree "$(git rev-parse "$HEAD_SHA^{tree}")" -p "$HEAD_SHA" -m moved </dev/null)"
  git update-ref "$REF" "$other"
  run rb
  [ "$status" -eq 2 ]
  [[ "$output" == *"compare-and-swap"* ]]
  [ "$(git rev-parse "$REF")" = "$other" ]
}

@test "record-branch: a later stage builds on the pushed previous stage of the same record" {
  run rb
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  s1="$(git rev-parse "$REF")"
  git push -q origin "$REF:$REF"
  printf 'stage two\n' > grimoires/loa/a2a/sprint-272/late.md
  run bash "$RB" --cycle 133 --head "$HEAD_SHA" --prev "$s1" --stage "stage 2"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(git rev-parse "$REF^1")" = "$s1" ]
  git cat-file -e "$REF:grimoires/loa/a2a/record-manifests/cycle-133-fixture/stage-2.json"
}

@test "record-branch: parents that are not on origin are refused before any write" {
  printf 'unpushed\n' > README.md
  git commit -q -am unpushed
  local_head="$(git rev-parse HEAD)"
  run bash "$RB" --cycle 133 --head "$local_head" --prev "$PREV_SHA" --stage "stage 1"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not on origin"* ]]
  ! git rev-parse --verify --quiet "$REF"
}

@test "record-branch: --dry-run prints the size table, exits 0, writes no ref and no object" {
  before="$(git count-objects -v | sed -n 's/^count: //p')"
  run rb --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"grimoires/loa/a2a/sprint-272"* ]]
  [[ "$output" == *"evals/results/ablation-2.0/c133-b1"* ]]
  [[ "$output" == *"total"* ]]
  [[ "$output" != *"sandbox"* ]]
  ! git rev-parse --verify --quiet "$REF"
  [ "$(git count-objects -v | sed -n 's/^count: //p')" = "$before" ]
}

@test "record-branch: --manifest FILE replaces the ledger derivation and --add extends it" {
  jq -n '{paths: ["grimoires/loa/a2a/prompts"], results_roots: [], lite_tree: null}' > "$W/m.json"
  run rb --manifest "$W/m.json" --add grimoires/loa/NOTES.md
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  t="$(tree_of "$REF")"
  grep -qxF grimoires/loa/a2a/prompts/next.md <<<"$t"
  grep -qxF grimoires/loa/NOTES.md <<<"$t"
  ! grep -qF grimoires/loa/a2a/sprint-272/ <<<"$t"
  ! grep -qF evals/results <<<"$t"
}

@test "record-branch: usage errors exit 2 with one line naming the repair; --help exits 0" {
  run bash "$RB" --cycle 133 --head "$HEAD_SHA" --prev "$PREV_SHA"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--stage"* ]]
  run bash "$RB" --cycle 999 --head "$HEAD_SHA" --prev "$PREV_SHA" --stage x
  [ "$status" -eq 2 ]
  [[ "$output" == *"cycle-999"* ]]
  run bash "$RB" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--accept-scan"* ]]
}

@test "record-branch: a nested git repository under a results root is refused" {
  mkdir -p evals/results/ablation-2.0/c133-b1/cell-a/run-1/work/.git
  printf 'ref: refs/heads/main\n' > evals/results/ablation-2.0/c133-b1/cell-a/run-1/work/.git/HEAD
  run rb
  [ "$status" -eq 2 ]
  [[ "$output" == *"nested git"* ]]
}
