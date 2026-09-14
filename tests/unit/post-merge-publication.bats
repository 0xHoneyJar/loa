#!/usr/bin/env bats

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    CASE_DIR="$(mktemp -d)"
    export PROJECT_ROOT="$CASE_DIR/repo"
    mkdir -p "$PROJECT_ROOT/.claude/scripts" "$PROJECT_ROOT/.run" "$CASE_DIR/bin"
    cp "$ROOT/.claude/scripts/"{bootstrap.sh,path-lib.sh,post-merge-orchestrator.sh,semver-bump.sh,release-notes-gen.sh} "$PROJECT_ROOT/.claude/scripts/"
    git -C "$PROJECT_ROOT" init -q
    git -C "$PROJECT_ROOT" config user.name Test
    git -C "$PROJECT_ROOT" config user.email test@example.invalid
    printf '.run/\n' > "$PROJECT_ROOT/.gitignore"
    printf '# Changelog\n\n## [Unreleased]\n\n## [1.0.0]\n\n- old change\n' > "$PROJECT_ROOT/CHANGELOG.md"
    git -C "$PROJECT_ROOT" add .
    git -C "$PROJECT_ROOT" commit -qm "feat: initial"
    git -C "$PROJECT_ROOT" tag v1.0.0
    printf 'fixed\n' > "$PROJECT_ROOT/app.txt"
    git -C "$PROJECT_ROOT" add app.txt
    git -C "$PROJECT_ROOT" commit -qm "fix: repair application"
    git init --bare -q "$CASE_DIR/remote"
    git -C "$PROJECT_ROOT" remote add origin https://github.com/test/repo.git
    git -C "$PROJECT_ROOT" remote set-url --push origin "$CASE_DIR/remote"
    SHA="$(git -C "$PROJECT_ROOT" rev-parse HEAD)"
    SCRIPT="$PROJECT_ROOT/.claude/scripts/post-merge-orchestrator.sh"
    export GH_LOG="$CASE_DIR/gh.log"
    cat > "$CASE_DIR/bin/gh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_LOG"
if [[ "${GH_MODE:-}" == host-bound && "$*" != *"--hostname github.com"* ]]; then
    echo "unbound GitHub API host" >&2
    exit 1
fi
if [[ "${GH_MODE:-fail}" == fail ]]; then
    echo "simulated GitHub failure" >&2
    exit 1
fi
if [[ "$*" == *"releases/tags/"* ]]; then
    [[ -f "${GH_LOG}.release" ]] || exit 1
    cat "${GH_LOG}.release"
elif [[ "$*" == *"releases/81"* ]]; then
    cat "${GH_LOG}.release"
elif [[ "$*" == *"--method POST"* && "$*" == *"/releases "* ]]; then
    jq '. + {id:81}' > "${GH_LOG}.release"
    cat "${GH_LOG}.release"
elif [[ "$*" == *"repos/test/repo/issues/7" && "$*" != *"--method POST"* ]]; then
    printf '{"number":7,"url":"https://api.github.com/repos/test/repo/issues/7"}\n'
elif [[ "$*" == *"--method POST"* ]]; then
    cat > "${GH_LOG}.request"
    if [[ "${GH_MODE:-}" == empty ]]; then exit 0; fi
    printf '{"id":73,"html_url":"https://github.com/test/repo/issues/7#issuecomment-73"}\n'
elif [[ "$*" == *"issues/comments/73"* ]]; then
    jq --argjson id 73 --argjson pr "${GH_COMMENT_PR:-7}" \
      '. + {id:$id,issue_url:("https://api.github.com/repos/test/repo/issues/" + ($pr | tostring))}' "${GH_LOG}.request"
fi
SH
    chmod +x "$CASE_DIR/bin/gh"
    export PATH="$CASE_DIR/bin:$PATH"
}

teardown() { rm -rf "$CASE_DIR"; }

invoke_notify() {
    sed '$d' "$SCRIPT" > "$PROJECT_ROOT/.claude/scripts/source-orchestrator.sh"
    bash -c '
      source "$1"
      PR_NUMBER=7
      PR_TYPE=other
      MERGE_SHA="$2"
      bind_github_origin https://github.com/test/repo.git
      init_state
      phase_notify
    ' _ "$PROJECT_ROOT/.claude/scripts/source-orchestrator.sh" "$SHA"
}

@test "publication: notify fails when gh fails and records failed phase" {
    run invoke_notify
    [ "$status" -ne 0 ]
    jq -e '.phases.notify.status == "failed"' "$PROJECT_ROOT/.run/post-merge-state.json"
}

@test "publication: notify requires returned comment identifier" {
    export GH_MODE=empty
    run invoke_notify
    [ "$status" -ne 0 ]
    jq -e '.phases.notify.status == "failed"' "$PROJECT_ROOT/.run/post-merge-state.json"
}

@test "publication: notify re-reads and verifies the returned comment" {
    export GH_MODE=ok
    run invoke_notify
    [ "$status" -eq 0 ]
    grep -q 'issues/comments/73' "$GH_LOG"
    jq -e '.phases.notify.result.id == 73' "$PROJECT_ROOT/.run/post-merge-state.json"
}

@test "publication: generation yields inspectable candidate and zero remote objects" {
    run bash "$SCRIPT" --generate --pr 7 --type cycle --sha "$SHA" --downstream --skip-gt --skip-rtfm
    [ "$status" -eq 0 ]
    [ -f "$PROJECT_ROOT/.run/post-merge-candidate.json" ]
    jq -e '.tag == "v1.0.1" and (.release_body | length > 0) and (.notification_body | length > 0) and (.target_commit | length == 40)' "$PROJECT_ROOT/.run/post-merge-candidate.json"
    [ -z "$(git --git-dir="$CASE_DIR/remote" tag)" ]
    if [[ -f "$GH_LOG" ]]; then
        ! grep -Eq 'release create|pr comment|--method POST' "$GH_LOG"
    fi
}

prepare_from_workflow() {
    local job="$1" pr_type="$2"
    yq eval -r ".jobs[\"$job\"].steps[] | select(.name == \"Prepare release candidate\") | .run" \
      "$ROOT/.github/workflows/post-merge.yml" > "$CASE_DIR/prepare.sh"
    (
        cd "$PROJECT_ROOT"
        export PM_PR_NUMBER=7 PM_PR_TYPE="$pr_type" PM_MERGE_SHA="$SHA"
        export GITHUB_STEP_SUMMARY="$CASE_DIR/summary.md"
        bash -e "$CASE_DIR/prepare.sh"
    )
}

assert_workflow_candidate() {
    [ "$status" -eq 0 ]
    [ ! -x "$PROJECT_ROOT/.claude/scripts/bootstrap.sh" ]
    git -C "$PROJECT_ROOT" diff --exit-code -- .claude/scripts
    jq -e '.state == "PREPARED"' "$PROJECT_ROOT/.run/post-merge-state.json"
    [ -f "$PROJECT_ROOT/.run/post-merge-candidate.patch" ]
    git -C "$PROJECT_ROOT" bundle verify .run/post-merge-candidate.bundle
    (cd "$PROJECT_ROOT" && sha256sum -c .run/post-merge-candidate.sha256)
    [ -z "$(git --git-dir="$CASE_DIR/remote" tag)" ]
    if [[ -f "$GH_LOG" ]]; then
        ! grep -Eq 'release create|pr comment|--method POST' "$GH_LOG"
    fi
}

@test "publication: simple-release workflow prepares artifacts without changing script modes" {
    run prepare_from_workflow simple-release other
    assert_workflow_candidate
}

@test "publication: full-pipeline workflow prepares artifacts without changing script modes" {
    run prepare_from_workflow full-pipeline cycle
    assert_workflow_candidate
}

@test "publication: generation still refuses a tracked script mode change" {
    chmod +x "$PROJECT_ROOT/.claude/scripts/bootstrap.sh"
    run bash "$SCRIPT" --generate --pr 7 --type other --sha "$SHA"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Candidate generation requires a clean tracked checkout and index"* ]]
    [ ! -f "$PROJECT_ROOT/.run/post-merge-candidate.json" ]
}

@test "publication: empty Unreleased section is filled from classified commits" {
    run bash "$SCRIPT" --generate --pr 7 --type cycle --sha "$SHA" --downstream --skip-gt --skip-rtfm
    [ "$status" -eq 0 ]
    awk '/^## \[1.0.1\]/{found=1;next} found && /^## /{exit} found{print}' "$PROJECT_ROOT/CHANGELOG.md" | grep -q 'repair application'
}

@test "publication: unclassifiable commits cannot write a version heading" {
    git -C "$PROJECT_ROOT" tag v1.0.1
    git -C "$PROJECT_ROOT" commit --allow-empty -qm "Ship completed work"
    SHA="$(git -C "$PROJECT_ROOT" rev-parse HEAD)"
    cp "$PROJECT_ROOT/CHANGELOG.md" "$CASE_DIR/before"
    run bash "$SCRIPT" --generate --pr 7 --type cycle --sha "$SHA" --downstream --skip-gt --skip-rtfm
    [ "$status" -ne 0 ]
    cmp "$PROJECT_ROOT/CHANGELOG.md" "$CASE_DIR/before"
    [ -z "$(git --git-dir="$CASE_DIR/remote" tag)" ]
}

generate() {
    bash "$SCRIPT" --generate --pr 7 --type cycle --sha "$SHA" --downstream --skip-gt --skip-rtfm
    CANDIDATE="$PROJECT_ROOT/.run/post-merge-candidate.json"
    DIGEST="$(sha256sum "$CANDIDATE" | cut -d' ' -f1)"
}

@test "publication: approved candidate publishes and verifies tag release and comment" {
    generate
    export GH_MODE=ok
    run bash "$SCRIPT" --publish "$CANDIDATE" --approve-sha256 "$DIGEST"
    [ "$status" -eq 0 ]
    jq -e '.state == "DONE" and .phases.tag.result.verified and .phases.release.result.id == 81 and .phases.notify.result.id == 73' "$PROJECT_ROOT/.run/post-merge-state.json"
    grep -q 'releases/81' "$GH_LOG"
    grep -q 'issues/comments/73' "$GH_LOG"
    [ "$(git --git-dir="$CASE_DIR/remote" rev-parse 'v1.0.1^{commit}')" = "$(jq -r '.target_commit' "$CANDIDATE")" ]
}

@test "publication: changed candidate digest refuses before any remote write" {
    generate
    printf '\n' >> "$CANDIDATE"
    run bash "$SCRIPT" --publish "$CANDIDATE" --approve-sha256 "$DIGEST"
    [ "$status" -ne 0 ]
    [ -z "$(git --git-dir="$CASE_DIR/remote" tag)" ]
}

@test "publication: changed checkout refuses before any remote write" {
    generate
    git -C "$PROJECT_ROOT" commit --allow-empty -qm "fix: later change"
    run bash "$SCRIPT" --publish "$CANDIDATE" --approve-sha256 "$DIGEST"
    [ "$status" -ne 0 ]
    [ -z "$(git --git-dir="$CASE_DIR/remote" tag)" ]
}

@test "publication: gh failure makes publication fail overall" {
    generate
    export GH_MODE=fail
    run bash "$SCRIPT" --publish "$CANDIDATE" --approve-sha256 "$DIGEST"
    [ "$status" -ne 0 ]
    jq -e '.state == "FAILED" and .phases.release.status == "failed"' "$PROJECT_ROOT/.run/post-merge-state.json"
}

@test "publication: retry verifies the retained comment without creating a duplicate" {
    generate
    export GH_MODE=ok
    bash "$SCRIPT" --publish "$CANDIDATE" --approve-sha256 "$DIGEST"
    run bash "$SCRIPT" --publish "$CANDIDATE" --approve-sha256 "$DIGEST"
    [ "$status" -eq 0 ]
    [ "$(grep -c -- '--method POST repos/test/repo/issues/7/comments' "$GH_LOG")" = 1 ]
    [ "$(grep -c 'issues/comments/73' "$GH_LOG")" = 2 ]
}

@test "publication: mutable receipt cannot change approved release version" {
    generate
    jq --arg digest "$DIGEST" \
      '.candidate_digest=$digest | .phases.semver.result.next="99.0.0"' \
      "$PROJECT_ROOT/.run/post-merge-state.json" > "$CASE_DIR/state"
    mv "$CASE_DIR/state" "$PROJECT_ROOT/.run/post-merge-state.json"
    export GH_MODE=ok
    run bash "$SCRIPT" --publish "$CANDIDATE" --approve-sha256 "$DIGEST"
    [ "$status" -eq 0 ]
    [ -z "$(git --git-dir="$CASE_DIR/remote" tag -l v99.0.0)" ]
    [ "$(git --git-dir="$CASE_DIR/remote" tag -l v1.0.1)" = v1.0.1 ]
}

@test "publication: changed push URL is rejected before either remote is written" {
    generate
    git init --bare -q "$CASE_DIR/other-remote"
    git -C "$PROJECT_ROOT" remote set-url --push origin "$CASE_DIR/other-remote"
    export GH_MODE=ok
    run bash "$SCRIPT" --publish "$CANDIDATE" --approve-sha256 "$DIGEST"
    [ "$status" -ne 0 ]
    [ -z "$(git --git-dir="$CASE_DIR/remote" tag)" ]
    [ -z "$(git --git-dir="$CASE_DIR/other-remote" tag)" ]
}

@test "publication: failed generation commit cannot create a candidate" {
    printf '#!/bin/sh\nexit 1\n' > "$PROJECT_ROOT/.git/hooks/pre-commit"
    chmod +x "$PROJECT_ROOT/.git/hooks/pre-commit"
    run bash "$SCRIPT" --generate --pr 7 --type cycle --sha "$SHA" --downstream --skip-gt --skip-rtfm
    [ "$status" -ne 0 ]
    [ ! -f "$PROJECT_ROOT/.run/post-merge-candidate.json" ]
}

@test "publication: API host and repository come from the approved origin" {
    generate
    export GH_MODE=host-bound GH_HOST=wrong.example GH_REPO=wrong/other
    run bash "$SCRIPT" --publish "$CANDIDATE" --approve-sha256 "$DIGEST"
    [ "$status" -eq 0 ]
    ! grep -q 'wrong.example\|wrong/other' "$GH_LOG"
    [ "$(grep -c '^api ' "$GH_LOG")" = "$(grep -c '^api --hostname github.com ' "$GH_LOG")" ]
}

@test "publication: a retained comment must belong to the approved PR" {
    generate
    export GH_MODE=ok
    bash "$SCRIPT" --publish "$CANDIDATE" --approve-sha256 "$DIGEST"
    export GH_COMMENT_PR=999
    run bash "$SCRIPT" --publish "$CANDIDATE" --approve-sha256 "$DIGEST"
    [ "$status" -ne 0 ]
    jq -e '.state == "FAILED" and .phases.notify.status == "failed"' "$PROJECT_ROOT/.run/post-merge-state.json"
    [ "$(grep -c -- '--method POST repos/test/repo/issues/7/comments' "$GH_LOG")" = 1 ]
}
