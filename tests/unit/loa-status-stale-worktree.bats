#!/usr/bin/env bats
# Real linked-worktree/ledger fixtures; workflow and doctor output are hermetic.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    TEST_DIR="$(mktemp -d)"
    MAIN="$TEST_DIR/main"
    WORKTREE="$TEST_DIR/parked worktree"
    mkdir -p "$MAIN/.claude/scripts" "$MAIN/grimoires/loa"
    cp "$REPO_ROOT/.claude/scripts/loa-status.sh" "$MAIN/.claude/scripts/"
    cat > "$MAIN/.claude/scripts/workflow-state.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '{"state":"complete","description":"Local snapshot","progress_percent":100,"suggested_command":"/deploy-production"}'
EOF
    cat > "$MAIN/.claude/scripts/loa-doctor.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '{"status":"HEALTHY"}'
EOF
    chmod +x "$MAIN/.claude/scripts/"*.sh
    printf '{"framework_version":"1.0.0","history":[]}\n' > "$MAIN/.loa-version.json"
    printf '{"active_cycle":"cycle-1","cycles":[{"id":"cycle-1","status":"active"}]}\n' \
        > "$MAIN/grimoires/loa/ledger.json"
    git -C "$MAIN" init -q -b main
    git -C "$MAIN" add .
    fixture_commit "$MAIN" initial
    git -C "$MAIN" worktree add -q -b parked "$WORKTREE"
    printf 'branch-only work\n' > "$WORKTREE/branch.txt"
    git -C "$WORKTREE" add branch.txt
    fixture_commit "$WORKTREE" branch-only
    set_upstream_ledger '{"active_cycle":null,"cycles":[{"id":"cycle-1","status":"archived","archive_path":"grimoires/loa/archive/cycle-1"}]}'
    cd "$WORKTREE"
}

teardown() {
    cd /
    rm -rf "$TEST_DIR"
}

fixture_commit() {
    git -C "$1" -c user.name=Fixture -c user.email=fixture@example.com \
        -c core.hooksPath=/dev/null -c commit.gpgsign=false commit -qm "$2"
}

set_upstream_ledger() {
    printf '%s\n' "$1" > "$MAIN/grimoires/loa/ledger.json"
    git -C "$MAIN" add grimoires/loa/ledger.json
    fixture_commit "$MAIN" ledger-update
    git -C "$MAIN" update-ref refs/remotes/origin/main HEAD
}

@test "issue-1233: archived cycle is stale even when the parked branch is not an ancestor" {
    run git merge-base --is-ancestor HEAD origin/main
    [ "$status" -eq 1 ]
    run .claude/scripts/loa-status.sh --json
    [ "$status" -eq 0 ]
    jq -e '.state == "complete" and .stale_worktree.cycle_id == "cycle-1"
        and .stale_worktree.upstream_ref == "origin/main"
        and .suggested_command == "git worktree list"' <<< "$output"
}

@test "issue-1233: human output warns and does not suggest deployment" {
    run .claude/scripts/loa-status.sh
    [ "$status" -eq 0 ]
    [[ "$output" == *"stale snapshot"* ]]
    [[ "$output" != *"/deploy-production"* ]]
    [[ "$output" == *"git worktree list"* ]]
}

@test "issue-1233: triage replaces halted resume advice in both output modes" {
    cat > .claude/scripts/workflow-state.sh <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '{"state":"halted","suggested_command":"/run-resume"}'
EOF
    run .claude/scripts/loa-status.sh --triage --json
    [ "$status" -eq 0 ]
    jq -e '.status.state == "halted" and .status.stale_worktree.cycle_id == "cycle-1"
        and .next.suggested_command == "git worktree list"' <<< "$output"
    run .claude/scripts/loa-status.sh --triage
    [ "$status" -eq 0 ]
    [[ "$output" == *"stale snapshot"* ]]
    [[ "$output" != *"/run-resume"* ]]
}

@test "issue-1233: null upstream active_cycle without a matching archived record is not proof" {
    set_upstream_ledger '{"active_cycle":null,"cycles":[{"id":"other-cycle","status":"archived"}]}'
    run .claude/scripts/loa-status.sh --json
    [ "$status" -eq 0 ]
    jq -e '.stale_worktree == null and .suggested_command == "/deploy-production"' <<< "$output"
}

@test "issue-1233: an active matching upstream cycle is not stale" {
    set_upstream_ledger '{"active_cycle":"cycle-1","cycles":[{"id":"cycle-1","status":"active"}]}'
    run .claude/scripts/loa-status.sh --json
    [ "$status" -eq 0 ]
    jq -e '.stale_worktree == null and .suggested_command == "/deploy-production"' <<< "$output"
}

@test "issue-1233: missing cached upstream preserves local status without fetching" {
    git -C "$MAIN" update-ref -d refs/remotes/origin/main
    run .claude/scripts/loa-status.sh --json
    [ "$status" -eq 0 ]
    jq -e '.stale_worktree == null and .suggested_command == "/deploy-production"' <<< "$output"
}

@test "issue-1233: malformed cached ledger preserves local status" {
    set_upstream_ledger 'invalid{'
    run .claude/scripts/loa-status.sh --json
    [ "$status" -eq 0 ]
    jq -e '.stale_worktree == null and .suggested_command == "/deploy-production"' <<< "$output"
}

@test "issue-1233: primary checkout is not labelled a stale worktree" {
    cd "$MAIN"
    run .claude/scripts/loa-status.sh --json
    [ "$status" -eq 0 ]
    jq -e '.stale_worktree == null' <<< "$output"
}

@test "issue-1233: no-stale-check preserves explicit local-snapshot behavior" {
    run .claude/scripts/loa-status.sh --no-stale-check --json
    [ "$status" -eq 0 ]
    jq -e '.stale_worktree == null and .suggested_command == "/deploy-production"' <<< "$output"
}

@test "issue-1233: closed cycle on cached default branch is recognized without touching dirty work" {
    set_upstream_ledger '{"active_cycle":null,"cycles":[{"id":"cycle-1","status":"closed"}]}'
    git -C "$MAIN" update-ref refs/remotes/origin/trunk HEAD
    git -C "$MAIN" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/trunk
    git -C "$MAIN" update-ref -d refs/remotes/origin/main
    printf 'uncommitted work\n' >> branch.txt
    local before
    before="$(git diff --binary)"
    run .claude/scripts/loa-status.sh --json
    [ "$status" -eq 0 ]
    jq -e '.stale_worktree.upstream_ref == "origin/trunk"
        and .stale_worktree.upstream_status == "closed"' <<< "$output"
    [ "$(git diff --binary)" = "$before" ]
}
