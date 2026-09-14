#!/usr/bin/env bats

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    CASE_DIR="$(mktemp -d)"
    export PROJECT_ROOT="$CASE_DIR/repo"
    mkdir -p "$PROJECT_ROOT/.claude/scripts" "$PROJECT_ROOT/.run" "$CASE_DIR/bin"
    cp "$ROOT/.claude/scripts/"{bootstrap.sh,path-lib.sh,post-merge-orchestrator.sh,semver-bump.sh,release-notes-gen.sh} "$PROJECT_ROOT/.claude/scripts/"
    if [[ -n "${POST_MERGE_UNDER_TEST:-}" ]]; then
        cp "$POST_MERGE_UNDER_TEST" "$PROJECT_ROOT/.claude/scripts/post-merge-orchestrator.sh"
    fi
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
    export GH_MERGE_SHA="$SHA"
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
elif [[ "$*" == *"repos/test/repo/pulls/7" ]]; then
    if [[ "${GH_PR_MODE:-}" == issue ]]; then
        printf '{"number":7,"url":"https://api.github.com/repos/test/repo/issues/7"}\n'
    elif [[ "${GH_PR_MODE:-}" == unavailable ]]; then
        exit 1
    else
        jq -nc --arg mode "${GH_PR_MODE:-ok}" --arg sha "$GH_MERGE_SHA" '
          {number:7, url:"https://api.github.com/repos/test/repo/pulls/7",
           issue_url:"https://api.github.com/repos/test/repo/issues/7",
           merged:true, merge_commit_sha:$sha, base:{repo:{full_name:"test/repo"}}} |
          if $mode == "unmerged" then .merged=false
          elif $mode == "wrong-merge" then .merge_commit_sha=("0" * 40)
          elif $mode == "wrong-repo" then .base.repo.full_name="test/other"
          elif $mode == "wrong-pr" then .number=99
          elif $mode == "wrong-url" then .url="https://api.github.com/repos/test/other/pulls/7"
          elif $mode == "wrong-issue" then .issue_url="https://api.github.com/repos/test/other/issues/7"
          else . end'
    fi
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
    jq -e '.state == "FAILED" and .phases.notify.status == "failed"' "$PROJECT_ROOT/.run/post-merge-state.json"
    [ -z "$(git --git-dir="$CASE_DIR/remote" tag)" ]
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

@test "RL-02: curated and generated changelog install failures abort preparation" {
    # Fail only the rename into the actual changelog, retaining real Git/jq/state I/O.
    export REAL_MV="$(command -v mv)"
    cat > "$CASE_DIR/bin/mv" <<'SH'
#!/usr/bin/env bash
if [[ "${!#}" == "$PROJECT_ROOT/CHANGELOG.md" ]]; then exit 73; fi
exec "$REAL_MV" "$@"
SH
    chmod +x "$CASE_DIR/bin/mv"
    for curated in false true; do
        if [[ "$curated" == true ]]; then
            printf '# Changelog\n\n## [Unreleased]\n\n- curated fix\n\n## [1.0.0]\n\n- old change\n' > "$PROJECT_ROOT/CHANGELOG.md"
            git -C "$PROJECT_ROOT" add CHANGELOG.md
            git -C "$PROJECT_ROOT" commit -qm "docs: curate changelog"
            SHA="$(git -C "$PROJECT_ROOT" rev-parse HEAD)"
        fi
        cp "$PROJECT_ROOT/CHANGELOG.md" "$CASE_DIR/before"
        run bash "$SCRIPT" --generate --pr 7 --type cycle --sha "$SHA" --downstream --skip-gt --skip-rtfm
        [ "$status" -ne 0 ]
        cmp "$PROJECT_ROOT/CHANGELOG.md" "$CASE_DIR/before"
        [ ! -f "$PROJECT_ROOT/.run/post-merge-candidate.json" ]
        jq -e '.state == "FAILED" and .phases.changelog.status == "failed"' "$PROJECT_ROOT/.run/post-merge-state.json"
    done
}

@test "RL-04: only the identical content-determining generation request reuses a candidate" {
    generate
    cp "$CANDIDATE" "$CASE_DIR/candidate-before"
    cp "$PROJECT_ROOT/.run/post-merge-state.json" "$CASE_DIR/state-before"
    run bash "$SCRIPT" --generate --pr 7 --type cycle --sha "$SHA" --downstream --skip-gt --skip-rtfm
    [ "$status" -eq 0 ]
    for change in pr type downstream gt rtfm; do
        args=(--generate --pr 7 --type cycle --sha "$SHA" --downstream --skip-gt --skip-rtfm)
        case "$change" in
            pr) args[2]=99 ;;
            type) args[4]=other ;;
            downstream) unset 'args[7]' ;;
            gt) unset 'args[8]' ;;
            rtfm) unset 'args[9]' ;;
        esac
        run bash "$SCRIPT" "${args[@]}"
        [ "$status" -ne 0 ]
        [[ "$output" == *"request differs"* ]]
        cmp "$CANDIDATE" "$CASE_DIR/candidate-before"
        cmp "$PROJECT_ROOT/.run/post-merge-state.json" "$CASE_DIR/state-before"
    done
}

@test "RL-04: abbreviated merge SHA is normalized for candidate identity and reuse" {
    run bash "$SCRIPT" --generate --pr 7 --type cycle --sha "${SHA:0:10}" --downstream --skip-gt --skip-rtfm
    [ "$status" -eq 0 ]
    CANDIDATE="$PROJECT_ROOT/.run/post-merge-candidate.json"
    jq -e --arg sha "$SHA" '.merge_sha == $sha and .generation_request.merge_sha == $sha and .prepared_state.merge_sha == $sha' "$CANDIDATE"
    cp "$CANDIDATE" "$CASE_DIR/before"
    run bash "$SCRIPT" --generate --pr 7 --type cycle --sha "$SHA" --downstream --skip-gt --skip-rtfm
    [ "$status" -eq 0 ]
    cmp "$CANDIDATE" "$CASE_DIR/before"
    export GH_MODE=ok
    DIGEST="$(sha256sum "$CANDIDATE" | cut -d' ' -f1)"
    run bash "$SCRIPT" --publish "$CANDIDATE" --approve-sha256 "$DIGEST"
    [ "$status" -eq 0 ]
}

@test "RL-05: publication requires the intended merged PR before any remote mutation" {
    generate
    export GH_MODE=ok
    for invalid in issue unavailable unmerged wrong-merge wrong-repo wrong-pr wrong-url wrong-issue; do
        export GH_PR_MODE="$invalid"
        : > "$GH_LOG"
        run bash "$SCRIPT" --publish "$CANDIDATE" --approve-sha256 "$DIGEST"
        [ "$status" -ne 0 ]
        [ -z "$(git --git-dir="$CASE_DIR/remote" tag)" ]
        ! grep -q -- '--method POST' "$GH_LOG"
        jq -e '.state == "FAILED"' "$PROJECT_ROOT/.run/post-merge-state.json"
    done
}

assert_changelog_failure() {
    [ "$status" -ne 0 ]
    [ ! -f "$PROJECT_ROOT/.run/post-merge-candidate.json" ]
    jq -e '.state == "FAILED" and .phases.changelog.status == "failed"' "$PROJECT_ROOT/.run/post-merge-state.json"
    [ -z "$(git --git-dir="$CASE_DIR/remote" tag)" ]
}

@test "RL-02: temp creation and temp write failures abort curated and generated entries" {
    export REAL_MKTEMP="$(command -v mktemp)"
    export BAD_TEMP="$CASE_DIR/not-a-file"
    mkdir "$BAD_TEMP"
    cat > "$CASE_DIR/bin/mktemp" <<'SH'
#!/usr/bin/env bash
if [[ "$*" == *"CHANGELOG.md.tmp."* || "$#" == 0 ]]; then
    if [[ "$TEMP_MODE" == fail ]]; then exit 73; fi
    printf '%s\n' "$BAD_TEMP"
    exit 0
fi
exec "$REAL_MKTEMP" "$@"
SH
    chmod +x "$CASE_DIR/bin/mktemp"
    for curated in false true; do
        if [[ "$curated" == true ]]; then
            printf '# Changelog\n\n## [Unreleased]\n\n- curated fix\n' > "$PROJECT_ROOT/CHANGELOG.md"
            git -C "$PROJECT_ROOT" add CHANGELOG.md
            git -C "$PROJECT_ROOT" commit -qm "docs: curate changelog"
            SHA="$(git -C "$PROJECT_ROOT" rev-parse HEAD)"
        fi
        cp "$PROJECT_ROOT/CHANGELOG.md" "$CASE_DIR/before"
        for mode in fail write; do
            export TEMP_MODE="$mode"
            run bash "$SCRIPT" --generate --pr 7 --type cycle --sha "$SHA" --downstream --skip-gt --skip-rtfm
            assert_changelog_failure
            cmp "$PROJECT_ROOT/CHANGELOG.md" "$CASE_DIR/before"
        done
    done
}

@test "RL-02: curated sed failure cannot become a successful finalization" {
    printf '# Changelog\n\n## [Unreleased]\n\n- curated fix\n' > "$PROJECT_ROOT/CHANGELOG.md"
    git -C "$PROJECT_ROOT" add CHANGELOG.md
    git -C "$PROJECT_ROOT" commit -qm "docs: curate changelog"
    SHA="$(git -C "$PROJECT_ROOT" rev-parse HEAD)"
    cp "$PROJECT_ROOT/CHANGELOG.md" "$CASE_DIR/before"
    export REAL_SED="$(command -v sed)"
    cat > "$CASE_DIR/bin/sed" <<'SH'
#!/usr/bin/env bash
if [[ "${!#}" == "$PROJECT_ROOT/CHANGELOG.md" ]]; then exit 73; fi
exec "$REAL_SED" "$@"
SH
    chmod +x "$CASE_DIR/bin/sed"
    run bash "$SCRIPT" --generate --pr 7 --type cycle --sha "$SHA" --downstream --skip-gt --skip-rtfm
    assert_changelog_failure
    cmp "$PROJECT_ROOT/CHANGELOG.md" "$CASE_DIR/before"
}

@test "RL-02: successful rename without installed bytes fails release section readback" {
    export REAL_MV="$(command -v mv)"
    cat > "$CASE_DIR/bin/mv" <<'SH'
#!/usr/bin/env bash
if [[ "${!#}" == "$PROJECT_ROOT/CHANGELOG.md" ]]; then exit 0; fi
exec "$REAL_MV" "$@"
SH
    chmod +x "$CASE_DIR/bin/mv"
    cp "$PROJECT_ROOT/CHANGELOG.md" "$CASE_DIR/before"
    run bash "$SCRIPT" --generate --pr 7 --type cycle --sha "$SHA" --downstream --skip-gt --skip-rtfm
    assert_changelog_failure
    cmp "$PROJECT_ROOT/CHANGELOG.md" "$CASE_DIR/before"
}

dual_changelog_failure() {
    export FAILED_CHANGELOG="$PROJECT_ROOT/$1"
    printf '# Changelog\n\n## [Unreleased]\n\n- curated framework fix\n' > "$PROJECT_ROOT/CHANGELOG.md"
    printf '# Changelog\n\n## [Unreleased]\n\n- curated project fix\n' > "$PROJECT_ROOT/PROJECT-CHANGELOG.md"
    git -C "$PROJECT_ROOT" add CHANGELOG.md PROJECT-CHANGELOG.md
    git -C "$PROJECT_ROOT" commit -qm "docs: curate domain changelogs"
    SHA="$(git -C "$PROJECT_ROOT" rev-parse HEAD)"
    cp "$FAILED_CHANGELOG" "$CASE_DIR/before"
    export REAL_MV="$(command -v mv)"
    cat > "$CASE_DIR/bin/mv" <<'SH'
#!/usr/bin/env bash
if [[ "${!#}" == "$FAILED_CHANGELOG" ]]; then exit 73; fi
exec "$REAL_MV" "$@"
SH
    chmod +x "$CASE_DIR/bin/mv"
    run bash "$SCRIPT" --generate --pr 7 --type cycle --sha "$SHA" --downstream --skip-gt --skip-rtfm
    assert_changelog_failure
    cmp "$FAILED_CHANGELOG" "$CASE_DIR/before"
}

@test "RL-02: framework changelog failure aborts multi-domain preparation" {
    dual_changelog_failure CHANGELOG.md
}

@test "RL-02: project changelog failure aborts multi-domain preparation" {
    dual_changelog_failure PROJECT-CHANGELOG.md
}
