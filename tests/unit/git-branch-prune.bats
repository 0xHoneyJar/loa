#!/usr/bin/env bats
# =============================================================================
# tests/unit/git-branch-prune.bats — cycle-125 Sprint 1 (PRD FR-1, SDD D-1.4)
# The sanctioned path for `git branch -D`: merged (ancestor), squash-merged
# (via a stub `gh`), gone-upstream and unmerged branches in a fixture repo.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    PRUNE="$PROJECT_ROOT/.claude/scripts/git-branch-prune.sh"
    WORK="$(mktemp -d)"
    export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
    export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid
    export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
    unset LOA_FENCE_NO_NETWORK

    # Stub gh: reports one merged PR for the branch named in STUB_GH_MERGED.
    mkdir -p "$WORK/bin"
    cat > "$WORK/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "${STUB_GH_LOG:-/dev/null}"
head=""; prev=""
for a in "$@"; do [[ "$prev" == "--head" ]] && head="$a"; prev="$a"; done
if [[ -n "${STUB_GH_FAIL:-}" ]]; then exit 1; fi
if [[ "$head" == "${STUB_GH_MERGED:-}" ]]; then echo 1; else echo 0; fi
EOF
    chmod +x "$WORK/bin/gh"
    export PATH="$WORK/bin:$PATH"
    export STUB_GH_LOG="$WORK/gh.log"

    # Fixture: bare origin + clone with main, merged-br, squash-br, wip-br, gone-br.
    git init -q --bare "$WORK/origin.git"
    git init -q -b main "$WORK/repo"
    cd "$WORK/repo"
    git remote add origin "$WORK/origin.git"
    echo a > a && git add a && git commit -qm init
    git push -q -u origin main

    git checkout -qb merged-br && echo m > m && git add m && git commit -qm merged
    git checkout -q main && git merge -q --no-ff -m "merge merged-br" merged-br

    git checkout -qb squash-br && echo s > s && git add s && git commit -qm squash
    git checkout -q main && git merge -q --squash squash-br >/dev/null && git commit -qm "squash squash-br"

    git checkout -qb wip-br && echo w > w && git add w && git commit -qm wip
    git checkout -q main

    git checkout -qb gone-br && echo g > g && git add g && git commit -qm gone
    git push -q -u origin gone-br
    git checkout -q main
    git push -q origin --delete gone-br
    git fetch -q --prune
    git push -q origin main
    export STUB_GH_MERGED="squash-br"
}

teardown() {
    cd /
    rm -rf -- "$WORK"
}

branches() { git for-each-ref --format='%(refname:short)' refs/heads/ | sort | tr '\n' ' '; }

@test "merged (ancestor) branch is deleted with a restore hint" {
    run bash "$PRUNE"
    [ "$status" -eq 0 ]
    [[ "$output" =~ deleted[[:space:]]+merged[[:space:]]+merged-br ]]
    [[ "$output" =~ "restore: git branch merged-br" ]]
    ! git rev-parse -q --verify refs/heads/merged-br >/dev/null
}

@test "squash-merged branch is detected through the gh probe" {
    run bash "$PRUNE"
    [ "$status" -eq 0 ]
    [[ "$output" =~ squash-merged[[:space:]]+squash-br ]]
    ! git rev-parse -q --verify refs/heads/squash-br >/dev/null
    grep -q -- "--state merged --head squash-br" "$STUB_GH_LOG"
}

@test "gone-upstream branch is deleted" {
    run bash "$PRUNE"
    [ "$status" -eq 0 ]
    [[ "$output" =~ gone[[:space:]]+gone-br ]]
    ! git rev-parse -q --verify refs/heads/gone-br >/dev/null
}

@test "unmerged branch is kept; main and the current branch are never touched" {
    run bash "$PRUNE"
    [ "$status" -eq 0 ]
    [[ "$output" != *"wip-br"* ]]
    [ "$(branches)" = "main wip-br " ]
}

@test "--dry-run lists every candidate and deletes nothing" {
    before="$(branches)"
    run bash "$PRUNE" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" =~ "would delete" ]]
    [[ "$output" == *"merged-br"* && "$output" == *"squash-br"* && "$output" == *"gone-br"* ]]
    [[ "$output" != *"wip-br"* ]]
    [ "$(branches)" = "$before" ]
}

@test "LOA_FENCE_NO_NETWORK=1 skips the gh probe: squash-merged branch is kept" {
    LOA_FENCE_NO_NETWORK=1 run bash "$PRUNE"
    [ "$status" -eq 0 ]
    [[ "$output" != *"squash-br"* ]]
    git rev-parse -q --verify refs/heads/squash-br >/dev/null
    [ ! -s "$STUB_GH_LOG" ]
}

@test "a failing gh probe keeps the branch (failure is not merged)" {
    STUB_GH_FAIL=1 run bash "$PRUNE" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" != *"squash-br"* ]]
}

@test "--json emits one object per branch with reason and sha" {
    run bash "$PRUNE" --dry-run --json
    [ "$status" -eq 0 ]
    echo "$output" | jq -e . >/dev/null
    [ "$(echo "$output" | jq -r 'select(.branch=="merged-br") | .reason')" = "merged" ]
    [ "$(echo "$output" | jq -r 'select(.branch=="squash-br") | .reason')" = "squash-merged" ]
    [ "$(echo "$output" | jq -r 'select(.branch=="gone-br") | .reason')" = "gone" ]
    [ "$(echo "$output" | jq -r 'select(.branch=="merged-br") | .deleted')" = "false" ]
}

@test "--base <ref> changes the ancestor test" {
    # Against wip-br as base, merged-br and squash-br's squash commit are not
    # ancestors (wip-br forked before them)... merged-br IS: wip-br descends
    # from the merge. gone-br is gone regardless. squash-br needs gh.
    run bash "$PRUNE" --dry-run --base wip-br
    [ "$status" -eq 0 ]
    [[ "$output" == *"merged-br"* ]]
    [[ "$output" != *"wip-br"* ]]
}

@test "exit 1 when nothing qualifies" {
    bash "$PRUNE" >/dev/null
    run bash "$PRUNE"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "nothing to prune" ]]
}

@test "usage errors exit 2" {
    run bash "$PRUNE" --bogus
    [ "$status" -eq 2 ]
    run bash "$PRUNE" --base
    [ "$status" -eq 2 ]
    run bash "$PRUNE" --base no/such/ref
    [ "$status" -eq 2 ]
}

@test "outside a work tree exits 2" {
    cd "$WORK"
    run bash "$PRUNE"
    [ "$status" -eq 2 ]
}

@test "the destructive-command fence allows the helper's invocation shape" {
    HOOK="$PROJECT_ROOT/.claude/hooks/safety/block-destructive-bash.sh"
    for cmd in "bash .claude/scripts/git-branch-prune.sh --dry-run" \
               ".claude/scripts/git-branch-prune.sh --base origin/main" \
               "LOA_FENCE_NO_NETWORK=1 bash .claude/scripts/git-branch-prune.sh"; do
        payload=$(jq -cn --arg c "$cmd" '{tool_input: {command: $c}}')
        run bash -c "echo '$payload' | LOA_REPO_ROOT='$WORK' '$HOOK'"
        [ "$status" -eq 0 ]
    done
}
