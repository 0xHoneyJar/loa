#!/usr/bin/env bats

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    CASE_DIR="$(mktemp -d)"
    # KF-034 / bd-fpt3: a host whose global config forces annotated or signed
    # tags (or sets hooksPath / followTags) must not change this suite.
    : > "$CASE_DIR/gitconfig"
    export GIT_CONFIG_GLOBAL="$CASE_DIR/gitconfig" GIT_CONFIG_NOSYSTEM=1
    export PROJECT_ROOT="$CASE_DIR/repo"
    mkdir -p "$PROJECT_ROOT/.claude/scripts/lib" "$PROJECT_ROOT/lib" "$PROJECT_ROOT/grimoires/loa" "$PROJECT_ROOT/.run" "$CASE_DIR/bin"
    cp "$ROOT/.claude/scripts/"{bootstrap.sh,path-lib.sh,post-merge-orchestrator.sh,semver-bump.sh,release-notes-gen.sh} "$PROJECT_ROOT/.claude/scripts/"
    # Candidate v2 is canonicalised through lib/jcs.sh (RFC 8785).
    cp "$ROOT/.claude/scripts/lib/jcs-helper.py" "$PROJECT_ROOT/.claude/scripts/lib/"
    cp "$ROOT/lib/jcs.sh" "$PROJECT_ROOT/lib/"
    git -C "$PROJECT_ROOT" init -q
    git -C "$PROJECT_ROOT" config user.name Test
    git -C "$PROJECT_ROOT" config user.email test@example.invalid
    printf '.run/\n' > "$PROJECT_ROOT/.gitignore"
    printf '# Changelog\n\n## [Unreleased]\n\n## [1.0.0]\n\n- old change\n' > "$PROJECT_ROOT/CHANGELOG.md"
    git -C "$PROJECT_ROOT" add .
    git -C "$PROJECT_ROOT" commit -qm "feat: initial"
    git -C "$PROJECT_ROOT" tag v1.0.0
    printf 'fixed\n' > "$PROJECT_ROOT/app.txt"
    # cycle-133 C-3: the merge carries its release content (the CHANGELOG
    # heading) and the active cycle the post-merge ledger step archives.
    printf '# Changelog\n\n## [Unreleased]\n\n## [1.0.1]\n\n- repair application\n\n## [1.0.0]\n\n- old change\n' > "$PROJECT_ROOT/CHANGELOG.md"
    printf '{\n  "schema_version": 1,\n  "active_cycle": "cycle-001",\n  "cycles": [\n    {\n      "id": "cycle-001",\n      "status": "active",\n      "sprints": [\n        {"id": 1, "status": "completed"}\n      ]\n    }\n  ]\n}\n' > "$PROJECT_ROOT/grimoires/loa/ledger.json"
    printf 'grimoires/loa/ledger.json.lock\n' >> "$PROJECT_ROOT/.gitignore"
    git -C "$PROJECT_ROOT" add app.txt CHANGELOG.md grimoires/loa/ledger.json .gitignore
    git -C "$PROJECT_ROOT" commit -qm "fix: repair application"
    git init --bare -q "$CASE_DIR/remote"
    git --git-dir="$CASE_DIR/remote" config core.logAllRefUpdates always
    git -C "$PROJECT_ROOT" remote add origin https://github.com/test/repo.git
    git -C "$PROJECT_ROOT" remote set-url --push origin "$CASE_DIR/remote"
    SHA="$(git -C "$PROJECT_ROOT" rev-parse HEAD)"
    # The merge is the remote main; setup pushes no tag.
    git -C "$PROJECT_ROOT" push -q "$CASE_DIR/remote" "$SHA:refs/heads/main"
    SCRIPT="$PROJECT_ROOT/.claude/scripts/post-merge-orchestrator.sh"
    export GH_LOG="$CASE_DIR/gh.log"
    cat > "$CASE_DIR/bin/gh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_LOG"
# Simulated crashes: fail exactly one call, once per case.
if [[ -n "${GH_FAIL_ONCE:-}" && ! -f "${GH_LOG}.failed-once" ]]; then
    case "$GH_FAIL_ONCE:$*" in
        release-readback:*releases/81*|notify:*"--method POST"*"/comments "*)
            touch "${GH_LOG}.failed-once"
            echo "simulated crash ($GH_FAIL_ONCE)" >&2
            exit 1 ;;
    esac
fi
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
    if [[ "${GH_BODY_REWRITE:-}" == caret ]]; then
        # GitHub stores a literal \u00XX escape of a C0 control (00-1F) or DEL (7F) in a release body as caret
        # notation: \u0000 -> \^@, \u001f -> \^_, \u007f -> \^? (observed publishing v2.0.0-rc.9, KF-064).
        jq '. + {id:81}' | python3 -I -c '
import json, re, sys
r = json.load(sys.stdin)
def caret(m):
    v = int(m.group(1), 16)
    return "\\^" + ("?" if v == 0x7f else chr(v + 64))
r["body"] = re.sub(r"\\u00([01][0-9a-fA-F]|7[fF])", caret, r.get("body", ""))
print(json.dumps(r))' > "${GH_LOG}.release"
    else
        jq '. + {id:81}' > "${GH_LOG}.release"
    fi
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
    # The phase still fills the heading. Candidate v2 tags the merge, so the
    # generated CHANGELOG commit is sealed as unpublished and named.
    printf '# Changelog\n\n## [Unreleased]\n\n## [1.0.0]\n\n- old change\n' > "$PROJECT_ROOT/CHANGELOG.md"
    git -C "$PROJECT_ROOT" commit -qam "fix: repair application"
    SHA="$(git -C "$PROJECT_ROOT" rev-parse HEAD)"
    run bash "$SCRIPT" --generate --pr 7 --type cycle --sha "$SHA" --downstream --skip-gt --skip-rtfm
    [ "$status" -eq 0 ]
    [[ "$output" == *"not published"*"CHANGELOG.md"* ]]
    jq -e --arg sha "$SHA" '.target_commit == $sha and .unpublished_paths == ["CHANGELOG.md"]
        and (.ref_updates | length) == 1' "$PROJECT_ROOT/.run/post-merge-candidate.json"
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
    # G-3 (rc.6/rc.7): the published tag is reachable from the remote main.
    git --git-dir="$CASE_DIR/remote" merge-base --is-ancestor v1.0.1 refs/heads/main
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

# =============================================================================
# sprint-bug-240 (bug 20260923-27d899): pre-release candidates. An untagged
# rc heading on top of CHANGELOG.md makes the candidate carry the prerelease
# version and `prerelease: true`; publication posts the flag and verifies it
# on read-back. A release candidate posts `prerelease: false`.
# =============================================================================

rc_fixture() {
    printf '# Changelog\n\n## [Unreleased]\n\n## [1.1.0-rc.1] — 2026-09-23 — Release candidate\n\n- model floor\n\n## [1.0.0]\n\n- old change\n' > "$PROJECT_ROOT/CHANGELOG.md"
    printf 'feature\n' > "$PROJECT_ROOT/feature.txt"
    git -C "$PROJECT_ROOT" add CHANGELOG.md feature.txt
    git -C "$PROJECT_ROOT" commit -qm "feat: cut the release candidate"
    SHA="$(git -C "$PROJECT_ROOT" rev-parse HEAD)"
    git -C "$PROJECT_ROOT" push -q "$CASE_DIR/remote" "$SHA:refs/heads/main"
}

@test "publication: an untagged rc heading prepares a prerelease candidate and publishes it flagged pre-release" {
    rc_fixture
    generate
    jq -e '.tag == "v1.1.0-rc.1" and .prerelease == true and .prepared_state.phases.semver.result.prerelease_transition.kind == "enter"' "$CANDIDATE"
    export GH_MODE=ok
    run bash "$SCRIPT" --publish "$CANDIDATE" --approve-sha256 "$DIGEST"
    [ "$status" -eq 0 ]
    jq -e '.state == "DONE" and .phases.release.result.verified' "$PROJECT_ROOT/.run/post-merge-state.json"
    jq -e '.tag_name == "v1.1.0-rc.1" and .prerelease == true and .draft == false' "${GH_LOG}.release"
    [ "$(git --git-dir="$CASE_DIR/remote" rev-parse 'v1.1.0-rc.1^{commit}')" = "$(jq -r '.target_commit' "$CANDIDATE")" ]
}

@test "publication: a release candidate is published with prerelease false" {
    generate
    jq -e '.tag == "v1.0.1" and .prerelease == false' "$CANDIDATE"
    export GH_MODE=ok
    run bash "$SCRIPT" --publish "$CANDIDATE" --approve-sha256 "$DIGEST"
    [ "$status" -eq 0 ]
    jq -e '.tag_name == "v1.0.1" and .prerelease == false' "${GH_LOG}.release"
}

@test "publication: a pre-existing release whose prerelease flag disagrees with the tag fails read-back" {
    rc_fixture
    generate
    export GH_MODE=ok
    jq -n --arg body "$(jq -r '.release_body' "$CANDIDATE")" \
      '{id:81,tag_name:"v1.1.0-rc.1",body:$body,draft:false,prerelease:false}' > "${GH_LOG}.release"
    run bash "$SCRIPT" --publish "$CANDIDATE" --approve-sha256 "$DIGEST"
    [ "$status" -ne 0 ]
    jq -e '.state == "FAILED" and .phases.release.status == "failed"' "$PROJECT_ROOT/.run/post-merge-state.json"
    ! grep -q 'issues/comments/73' "$GH_LOG"
}

# =============================================================================
# cycle-133 C-3 (FR-3, bd-kwloh): candidate schema_version 2. The tag targets
# the merge (reachable from main by construction), the ledger archive is one
# deterministic commit named in the sealed candidate and pushed with a lease
# against the observed remote main; a moved main defers it to --ledger-only.
# =============================================================================

remote_git() { git --git-dir="$CASE_DIR/remote" "$@"; }

publish() {
    bash "$SCRIPT" --publish "$CANDIDATE" --approve-sha256 "$DIGEST" "$@"
}

ledger_new() { jq -r '.ref_updates[0].new' "$CANDIDATE"; }

# Re-serialise a candidate after a mutation (RFC 8785, as --generate does).
recanon() {
    python3 "$ROOT/.claude/scripts/lib/jcs-helper.py" < "$1" > "$1.canon"
    mv "$1.canon" "$1"
}

reapprove() { DIGEST="$(sha256sum "$CANDIDATE" | cut -d' ' -f1)"; }

# A later merge on top of the candidate's merge, available on the remote.
later_merge() {
    LATER="$(git -C "$PROJECT_ROOT" commit-tree "$SHA^{tree}" -p "$SHA" -m "fix: later merge")"
    git -C "$PROJECT_ROOT" push -q "$CASE_DIR/remote" "$LATER:refs/heads/later"
}

# A commit that does not contain the merge, available on the remote.
unrelated_commit() {
    UNRELATED="$(git -C "$PROJECT_ROOT" commit-tree "$SHA^{tree}" -m "rewritten history")"
    git -C "$PROJECT_ROOT" push -q "$CASE_DIR/remote" "$UNRELATED:refs/heads/unrelated"
}

# Move the remote main to $2 once, while a push of a ref matching $1 is in
# flight (after the publisher's last check, before the remote applies it).
move_main_during_push() {
    cat > "$PROJECT_ROOT/.git/hooks/pre-push" <<HOOK
#!/usr/bin/env bash
while read -r _lref _lsha rref _rsha; do
    if [[ "\$rref" == $1 && ! -f "$CASE_DIR/moved" ]]; then
        touch "$CASE_DIR/moved"
        git --git-dir="$CASE_DIR/remote" update-ref refs/heads/main "$2"
    fi
done
exit 0
HOOK
    chmod +x "$PROJECT_ROOT/.git/hooks/pre-push"
}

assert_nothing_published() {
    [ -z "$(remote_git tag)" ]
    [ "$(remote_git rev-parse refs/heads/main)" = "${1:-$SHA}" ]
    if [[ -f "$GH_LOG" ]]; then
        ! grep -q -- '--method POST' "$GH_LOG"
    fi
}

@test "c133 v2: the sealed candidate targets the merge and names the ledger ref update" {
    generate
    jq -e --arg sha "$SHA" '.schema_version == 2 and .merge_sha == $sha and .target_commit == $sha
        and .target_on_main == true and .release_title == .tag
        and .ref_updates == [{ref:"refs/heads/main", expected_old:$sha, new:.ref_updates[0].new}]
        and (.ref_updates[0].new | test("^[0-9a-f]{40}$"))
        and .ledger_cycle == "cycle-001" and .ledger_patch_file == "post-merge-ledger.patch"
        and (.ledger_commit.author.name == "Test") and (.ledger_commit.committer.date | test("^[0-9]+ [+]0000$"))' "$CANDIDATE"
    [ "$(jq -r '.target_tree' "$CANDIDATE")" = "$(git -C "$PROJECT_ROOT" rev-parse "$SHA^{tree}")" ]
    [ "$(jq -j '.release_body' "$CANDIDATE" | sha256sum | cut -d' ' -f1)" = "$(jq -r '.release_notes_sha256' "$CANDIDATE")" ]
    [ "$(sha256sum "$PROJECT_ROOT/.run/post-merge-ledger.patch" | cut -d' ' -f1)" = "$(jq -r '.ledger_patch_sha256' "$CANDIDATE")" ]
    [ "$(grep -c '^diff --git ' "$PROJECT_ROOT/.run/post-merge-ledger.patch")" = 1 ]
    grep -q '^diff --git a/grimoires/loa/ledger.json b/grimoires/loa/ledger.json$' "$PROJECT_ROOT/.run/post-merge-ledger.patch"
    # The file is its own RFC 8785 form, so its byte digest is the approval digest.
    python3 "$ROOT/.claude/scripts/lib/jcs-helper.py" < "$CANDIDATE" | cmp - "$CANDIDATE"
    # The named ledger commit has the generated tree and the merge as parent.
    [ "$(git -C "$PROJECT_ROOT" rev-parse "$(ledger_new)^{tree}")" = "$(git -C "$PROJECT_ROOT" rev-parse 'HEAD^{tree}')" ]
    [ "$(git -C "$PROJECT_ROOT" rev-parse "$(ledger_new)^")" = "$SHA" ]
    [ -z "$(remote_git tag)" ]
}

@test "c133 v2: ancestor success publishes a tag reachable from main and fast-forwards the ledger" {
    generate
    export GH_MODE=ok
    run publish
    [ "$status" -eq 0 ]
    [ "$(remote_git rev-parse 'v1.0.1^{commit}')" = "$SHA" ]
    [ "$(remote_git rev-parse refs/heads/main)" = "$(ledger_new)" ]
    remote_git branch --contains v1.0.1 | grep -qx '[* ]*main'
    remote_git show main:grimoires/loa/ledger.json | jq -e '.cycles[0].status == "archived" and .active_cycle == null'
    jq -e '.state == "DONE" and .phases.ledger.status == "completed" and .phases.ledger.result.state == "published"' "$PROJECT_ROOT/.run/post-merge-state.json"
    jq -e --arg d "$DIGEST" '.candidate_digest == $d and .ledger.state == "published"' "$PROJECT_ROOT/.run/post-merge-progress.json"
    [ ! -f "$PROJECT_ROOT/.run/post-merge-ledger-deferred.json" ]
}

@test "c133 v2: a later merge on main still publishes the tag and defers the ledger step" {
    generate
    later_merge
    remote_git update-ref refs/heads/main "$LATER"
    export GH_MODE=ok
    run publish
    [ "$status" -eq 3 ]
    [[ "$output" == *"--ledger-only"* ]]
    [ "$(remote_git rev-parse 'v1.0.1^{commit}')" = "$SHA" ]
    remote_git merge-base --is-ancestor v1.0.1 main
    [ "$(remote_git rev-parse refs/heads/main)" = "$LATER" ]
    jq -e --arg later "$LATER" '.reason == "main_moved" and .observed_main == $later and .ledger_cycle == "cycle-001"' "$PROJECT_ROOT/.run/post-merge-ledger-deferred.json"
    jq -e '.state == "DONE" and .degraded_reason == "ledger_deferred" and .phases.ledger.result.state == "deferred" and .phases.notify.result.verified' "$PROJECT_ROOT/.run/post-merge-state.json"
}

@test "c133 v2: main advanced between the ancestry check and the tag push: ancestry still holds, ledger defers" {
    generate
    later_merge
    move_main_during_push 'refs/tags/*' "$LATER"
    export GH_MODE=ok
    run publish
    [ "$status" -eq 3 ]
    [ -f "$CASE_DIR/moved" ]
    [ "$(remote_git rev-parse 'v1.0.1^{commit}')" = "$SHA" ]
    [ "$(remote_git rev-parse refs/heads/main)" = "$LATER" ]
    remote_git merge-base --is-ancestor v1.0.1 main
    jq -e '.phases.release.result.verified and .phases.ledger.result.state == "deferred"' "$PROJECT_ROOT/.run/post-merge-state.json"
}

@test "c133 v2: main moved at the ledger push (lease failure) defers without overwriting main" {
    generate
    later_merge
    move_main_during_push 'refs/heads/main' "$LATER"
    export GH_MODE=ok
    run publish
    [ "$status" -eq 3 ]
    [ -f "$CASE_DIR/moved" ]
    [ "$(remote_git rev-parse refs/heads/main)" = "$LATER" ]
    jq -e '.reason == "lease_failed"' "$PROJECT_ROOT/.run/post-merge-ledger-deferred.json"
    jq -e '.ledger.state == "deferred"' "$PROJECT_ROOT/.run/post-merge-progress.json"
}

@test "c133 v2: --ledger-only after a deferral applies the patch onto the then-current main" {
    generate
    later_merge
    remote_git update-ref refs/heads/main "$LATER"
    export GH_MODE=ok
    run publish
    [ "$status" -eq 3 ]
    run publish --ledger-only
    [ "$status" -eq 0 ]
    [ "$(remote_git rev-parse 'refs/heads/main^')" = "$LATER" ]
    remote_git show main:grimoires/loa/ledger.json | jq -e '.cycles[0].status == "archived" and .active_cycle == null'
    [ "$(remote_git log -1 --format='%an <%ae>|%s' main)" = "Test <test@example.invalid>|chore(ledger): archive cycle-001 after merge" ]
    remote_git merge-base --is-ancestor v1.0.1 main
    [ ! -f "$PROJECT_ROOT/.run/post-merge-ledger-deferred.json" ]
    jq -e '.ledger.state == "published"' "$PROJECT_ROOT/.run/post-merge-progress.json"
    # Idempotent: a second --ledger-only sees the archived cycle and pushes nothing.
    before="$(remote_git rev-parse refs/heads/main)"
    run publish --ledger-only
    [ "$status" -eq 0 ]
    [ "$(remote_git rev-parse refs/heads/main)" = "$before" ]
}

@test "c133 v2: --ledger-only before any publish refuses" {
    generate
    run publish --ledger-only
    [ "$status" -eq 2 ]
    assert_nothing_published
}

@test "c133 v2: a remote main that does not contain the merge refuses before any write" {
    generate
    unrelated_commit
    remote_git update-ref refs/heads/main "$UNRELATED"
    export GH_MODE=ok
    run publish
    [ "$status" -eq 2 ]
    [[ "$output" == *"not an ancestor"* ]]
    assert_nothing_published "$UNRELATED"
}

@test "c133 v2: ancestry is re-verified before each visible step (main rewritten after the tag)" {
    generate
    unrelated_commit
    move_main_during_push 'refs/tags/*' "$UNRELATED"
    export GH_MODE=ok
    run publish
    [ "$status" -eq 1 ]
    [ "$(remote_git rev-parse 'v1.0.1^{commit}')" = "$SHA" ]
    [ "$(remote_git rev-parse refs/heads/main)" = "$UNRELATED" ]
    ! grep -q -- '--method POST' "$GH_LOG"
    jq -e '.state == "FAILED" and .phases.release.status == "failed"' "$PROJECT_ROOT/.run/post-merge-state.json"
}

@test "c133 v2: an existing tag with the identical target and release identity is accepted" {
    generate
    git -C "$PROJECT_ROOT" tag -a v1.0.1 "$SHA" -m "Release v1.0.1"
    tag_object="$(git -C "$PROJECT_ROOT" rev-parse refs/tags/v1.0.1)"
    git -C "$PROJECT_ROOT" push -q "$CASE_DIR/remote" refs/tags/v1.0.1
    git -C "$PROJECT_ROOT" tag -d v1.0.1 >/dev/null
    export GH_MODE=ok
    run publish
    [ "$status" -eq 0 ]
    [ "$(remote_git rev-parse refs/tags/v1.0.1)" = "$tag_object" ]
    [ "$(remote_git rev-parse refs/heads/main)" = "$(ledger_new)" ]
}

@test "c133 v2: an existing tag on another commit refuses" {
    generate
    git -C "$PROJECT_ROOT" tag -a v1.0.1 v1.0.0 -m "Release v1.0.1"
    tag_object="$(git -C "$PROJECT_ROOT" rev-parse refs/tags/v1.0.1)"
    git -C "$PROJECT_ROOT" push -q "$CASE_DIR/remote" refs/tags/v1.0.1
    export GH_MODE=ok
    run publish
    [ "$status" -eq 2 ]
    [ "$(remote_git rev-parse refs/tags/v1.0.1)" = "$tag_object" ]
    [ "$(remote_git rev-parse refs/heads/main)" = "$SHA" ]
    ! grep -q -- '--method POST' "$GH_LOG"
}

@test "c133 v2: an existing tag on the merge with another release identity refuses" {
    generate
    git -C "$PROJECT_ROOT" tag -a v1.0.1 "$SHA" -m "Something else"
    git -C "$PROJECT_ROOT" push -q "$CASE_DIR/remote" refs/tags/v1.0.1
    git -C "$PROJECT_ROOT" tag -d v1.0.1 >/dev/null
    export GH_MODE=ok
    run publish
    [ "$status" -eq 2 ]
    [ "$(remote_git rev-parse refs/heads/main)" = "$SHA" ]
    ! grep -q -- '--method POST' "$GH_LOG"
}

@test "c133 v2: crash after the tag: the re-run completes without a second tag" {
    generate
    export GH_MODE=fail
    run publish
    [ "$status" -eq 1 ]
    tag_object="$(remote_git rev-parse refs/tags/v1.0.1)"
    [ "$(remote_git rev-parse refs/heads/main)" = "$SHA" ]
    export GH_MODE=ok
    run publish
    [ "$status" -eq 0 ]
    [ "$(remote_git rev-parse refs/tags/v1.0.1)" = "$tag_object" ]
    [ "$(remote_git rev-parse refs/heads/main)" = "$(ledger_new)" ]
}

@test "c133 v2: crash after the release is created: the re-run reuses it" {
    generate
    export GH_MODE=ok GH_FAIL_ONCE=release-readback
    run publish
    [ "$status" -eq 1 ]
    [ "$(remote_git rev-parse refs/heads/main)" = "$SHA" ]
    run publish
    [ "$status" -eq 0 ]
    [ "$(grep -c -- '--method POST repos/test/repo/releases ' "$GH_LOG")" = 1 ]
    [ "$(remote_git rev-parse refs/heads/main)" = "$(ledger_new)" ]
}

@test "c133 v2: crash after the ledger push: the re-run completes without a second push" {
    generate
    export GH_MODE=ok GH_FAIL_ONCE=notify
    run publish
    [ "$status" -eq 1 ]
    [ "$(remote_git rev-parse refs/heads/main)" = "$(ledger_new)" ]
    run publish
    [ "$status" -eq 0 ]
    [ "$(remote_git reflog show refs/heads/main | wc -l | tr -d ' ')" = 2 ]
    jq -e '.state == "DONE" and .phases.ledger.result.state == "published" and .phases.notify.result.verified' "$PROJECT_ROOT/.run/post-merge-state.json"
}

@test "bug-283 (KF-064): a release body quoting a backslash-u control escape survives GitHub's caret rewrite on read-back and publishes DONE" {
    # the merge carries a commit subject with a literal \u0000-\u001f (cycle-137's sanitiser commit did); the notes quote it
    git -C "$PROJECT_ROOT" commit --allow-empty -qm 'fix: strip the `\u0000-\u001f` range in the sanitiser'
    SHA="$(git -C "$PROJECT_ROOT" rev-parse HEAD)"
    git -C "$PROJECT_ROOT" push -q "$CASE_DIR/remote" "$SHA:refs/heads/main"
    generate
    jq -e '.release_body | contains("\\u0000-\\u001f")' "$CANDIDATE" >/dev/null || { echo "fixture: the candidate body does not quote the escape"; return 1; }
    export GH_MODE=ok GH_BODY_REWRITE=caret
    run publish
    [ "$status" -eq 0 ] || { echo "publish status=$status"; printf '%s\n' "$output" | tail -5; return 1; }
    jq -e '.state == "DONE" and .phases.release.status == "completed" and .phases.release.result.verified == true and .phases.release.result.id == 81' "$PROJECT_ROOT/.run/post-merge-state.json"
    [ "$(grep -c -- '--method POST repos/test/repo/releases ' "$GH_LOG")" = 1 ]
    [ "$(remote_git rev-parse refs/heads/main)" = "$(ledger_new)" ]
    # the stored body really was rewritten (the stub did its job) and the sealed candidate was never touched
    jq -e '.body | contains("\\^@-\\^_")' "${GH_LOG}.release" >/dev/null
    [ "$(sha256sum "$CANDIDATE" | cut -d' ' -f1)" = "$DIGEST" ]
}

@test "bug-283 (KF-064): under the same rewrite, a pre-existing release whose body differs in any other way still fails read-back" {
    git -C "$PROJECT_ROOT" commit --allow-empty -qm 'fix: strip the `\u0000-\u001f` range in the sanitiser'
    SHA="$(git -C "$PROJECT_ROOT" rev-parse HEAD)"
    git -C "$PROJECT_ROOT" push -q "$CASE_DIR/remote" "$SHA:refs/heads/main"
    generate
    export GH_MODE=ok GH_BODY_REWRITE=caret
    # a release already exists for the tag: the rewritten body PLUS one extra line (another identity)
    jq -nc --arg tag "$(jq -r .tag "$CANDIDATE")" --arg title "$(jq -r .release_title "$CANDIDATE")" \
        --arg body "$(jq -r .release_body "$CANDIDATE" | sed 's/\\u0000-\\u001f/\\^@-\\^_/g'; printf '\nappended by someone else')" \
        '{id:81, tag_name:$tag, name:$title, body:$body, draft:false, prerelease:false}' > "${GH_LOG}.release"
    run publish
    [ "$status" -eq 1 ]
    jq -e '.state == "FAILED" and .phases.release.status == "failed" and .phases.ledger.status == "pending"' "$PROJECT_ROOT/.run/post-merge-state.json"
    [ "$(grep -c -- '--method POST repos/test/repo/releases ' "$GH_LOG")" = 0 ]
    [ "$(remote_git rev-parse refs/heads/main)" = "$SHA" ]
}

@test "bug-283 r1 (DISS-001): under the caret rewrite, a pre-existing release whose body differs only by CRLF line endings still fails read-back" {
    git -C "$PROJECT_ROOT" commit --allow-empty -qm 'fix: strip the `\u0000-\u001f` range in the sanitiser'
    SHA="$(git -C "$PROJECT_ROOT" rev-parse HEAD)"
    git -C "$PROJECT_ROOT" push -q "$CASE_DIR/remote" "$SHA:refs/heads/main"
    generate
    export GH_MODE=ok GH_BODY_REWRITE=caret
    jq -c --arg tag "$(jq -r .tag "$CANDIDATE")" --arg title "$(jq -r .release_title "$CANDIDATE")" \
        '{id:81, tag_name:$tag, name:$title, body:(.release_body | gsub("\\\\u0000-\\\\u001f"; "\\^@-\\^_") | gsub("\n"; "\r\n")), draft:false, prerelease:false}' "$CANDIDATE" > "${GH_LOG}.release"
    jq -e '.body | contains("\r\n")' "${GH_LOG}.release" >/dev/null
    run publish
    [ "$status" -eq 1 ] || { echo "CRLF body accepted as identical (status=$status)"; return 1; }
    jq -e '.state == "FAILED" and .phases.release.status == "failed" and .phases.ledger.status == "pending"' "$PROJECT_ROOT/.run/post-merge-state.json"
    [ "$(remote_git rev-parse refs/heads/main)" = "$SHA" ]
}

@test "bug-283 r1 (DISS-001/C-002): under the caret rewrite, a pre-existing release whose body has extra trailing newlines still fails read-back" {
    git -C "$PROJECT_ROOT" commit --allow-empty -qm 'fix: strip the `\u0000-\u001f` range in the sanitiser'
    SHA="$(git -C "$PROJECT_ROOT" rev-parse HEAD)"
    git -C "$PROJECT_ROOT" push -q "$CASE_DIR/remote" "$SHA:refs/heads/main"
    generate
    export GH_MODE=ok GH_BODY_REWRITE=caret
    jq -c --arg tag "$(jq -r .tag "$CANDIDATE")" --arg title "$(jq -r .release_title "$CANDIDATE")" \
        '{id:81, tag_name:$tag, name:$title, body:((.release_body | gsub("\\\\u0000-\\\\u001f"; "\\^@-\\^_")) + "\n\n"), draft:false, prerelease:false}' "$CANDIDATE" > "${GH_LOG}.release"
    run publish
    [ "$status" -eq 1 ] || { echo "trailing-newline body accepted as identical (status=$status)"; return 1; }
    jq -e '.phases.release.status == "failed" and .phases.ledger.status == "pending"' "$PROJECT_ROOT/.run/post-merge-state.json"
    [ "$(remote_git rev-parse refs/heads/main)" = "$SHA" ]
}

@test "bug-283 r1 (DISS-C-003): release_body_normalize maps the REAL rc.9 candidate line onto GitHub's stored line, and a caret table" {
    sed '$d' "$SCRIPT" > "$PROJECT_ROOT/.claude/scripts/source-orchestrator.sh"
    local fx="$ROOT/tests/fixtures/post-merge/rc9-release-body"
    [ -s "$fx/candidate-line.txt" ]
    [ -s "$fx/github-line.txt" ]
    run cmp -s "$fx/candidate-line.txt" "$fx/github-line.txt"
    [ "$status" -ne 0 ]   # the pair really differs before normalisation (a bare `! cmp` would never fail the test)
    run bash -c 'source "$1"; release_body_normalize < "$2"' _ "$PROJECT_ROOT/.claude/scripts/source-orchestrator.sh" "$fx/candidate-line.txt"
    [ "$status" -eq 0 ]
    [ "$output" = "$(cat "$fx/github-line.txt")" ] || { echo "normalised candidate line != GitHub line"; echo "got:  $output"; echo "want: $(cat "$fx/github-line.txt")"; return 1; }
    run bash -c 'source "$1"; release_body_normalize < "$2"' _ "$PROJECT_ROOT/.claude/scripts/source-orchestrator.sh" "$fx/github-line.txt"
    [ "$output" = "$(cat "$fx/github-line.txt")" ]   # idempotent on the stored form
    # the caret table: NUL, TAB, FS, US, DEL; a non-control escape and a bare word are untouched
    run bash -c 'source "$1"; printf "%s" "a\\u0000 b\\u0009 c\\u001c d\\u001f e\\u007f f\\u0041 g\\u00ff \\u0000x" | release_body_normalize' _ "$PROJECT_ROOT/.claude/scripts/source-orchestrator.sh"
    [ "$status" -eq 0 ]
    [ "$output" = 'a\^@ b\^I c\^\ d\^_ e\^? f\u0041 g\u00ff \^@x' ] || { echo "caret table: $output"; return 1; }
}

@test "bug-283 r2 (DISS-001): release_body_identical compares a 200 000-byte body (no argv limit) and a 200 000-byte read-back JSON" {
    sed '$d' "$SCRIPT" > "$PROJECT_ROOT/.claude/scripts/source-orchestrator.sh"
    local big="$CASE_DIR/big.txt"; head -c 200000 /dev/zero | tr '\0' 'a' > "$big"; printf ' \\u0000 tail\n' >> "$big"
    jq -n --rawfile b "$big" '{id:81, tag_name:"v1.0.1", name:"v1.0.1", body:($b | gsub("\\\\u0000"; "\\^@")), draft:false, prerelease:false}' > "$CASE_DIR/big-rb.json"
    [ "$(wc -c < "$CASE_DIR/big-rb.json")" -gt 131072 ]   # above MAX_ARG_STRLEN: an argv-borne JSON could not be exec'd
    run bash -c 'source "$1"; release_body_identical "$(cat "$2")" "$(cat "$3")"' _ "$PROJECT_ROOT/.claude/scripts/source-orchestrator.sh" "$big" "$CASE_DIR/big-rb.json"
    [ "$status" -eq 0 ] || { echo "status=$status output=${output:0:200}"; return 1; }
    [ "$output" = equal ] || { echo "verdict: $output"; return 1; }
}

@test "bug-283 r2 (DISS-C-004): release_body_identical itself maps the REAL rc.9 pair to equal and refuses a one-caret shift inside the normalised region" {
    sed '$d' "$SCRIPT" > "$PROJECT_ROOT/.claude/scripts/source-orchestrator.sh"
    local fx="$ROOT/tests/fixtures/post-merge/rc9-release-body"
    run bash -c 'source "$1"; release_body_identical "$(cat "$2")" "$(jq -n --rawfile b "$3" "{body: (\$b | rtrimstr(\"\\n\"))}")"' _ "$PROJECT_ROOT/.claude/scripts/source-orchestrator.sh" "$fx/candidate-line.txt" "$fx/github-line.txt"
    [ "$status" -eq 0 ]
    [ "$output" = equal ] || { echo "real pair: $output"; return 1; }
    # the stored line with \^@ shifted to \^A (NUL -> SOH): not GitHub's rewrite of the sent \u0000 -> refuse
    run bash -c 'source "$1"; release_body_identical "$(cat "$2")" "$(sed "s/\\\\^@/\\\\^A/" "$3" | jq -Rs "{body: rtrimstr(\"\\n\")}")"' _ "$PROJECT_ROOT/.claude/scripts/source-orchestrator.sh" "$fx/candidate-line.txt" "$fx/github-line.txt"
    [ "$status" -eq 0 ]
    [[ "$output" == differ\ * ]] || { echo "one-caret shift accepted: $output"; return 1; }
}

@test "c133 v2: mutated notes under the approved digest refuse" {
    generate
    jq '.release_body = "tampered"' "$CANDIDATE" > "$CASE_DIR/c" && mv "$CASE_DIR/c" "$CANDIDATE"
    recanon "$CANDIDATE"
    export GH_MODE=ok
    run publish
    [ "$status" -eq 2 ]
    assert_nothing_published
}

@test "c133 v2: mutated notes re-approved without their digest refuse" {
    generate
    jq '.release_body = "tampered"' "$CANDIDATE" > "$CASE_DIR/c" && mv "$CASE_DIR/c" "$CANDIDATE"
    recanon "$CANDIDATE"
    reapprove
    export GH_MODE=ok
    run publish
    [ "$status" -eq 2 ]
    [[ "$output" == *"release_notes_sha256"* ]]
    assert_nothing_published
}

@test "c133 v2: a mutated intended ref update refuses even when re-approved" {
    generate
    jq --arg sha "$SHA" '.ref_updates[0].new = $sha' "$CANDIDATE" > "$CASE_DIR/c" && mv "$CASE_DIR/c" "$CANDIDATE"
    recanon "$CANDIDATE"
    reapprove
    export GH_MODE=ok
    run publish
    [ "$status" -eq 2 ]
    assert_nothing_published
}

@test "c133 v2: a mutated ledger patch refuses" {
    generate
    sed -i 's/archived/retired/' "$PROJECT_ROOT/.run/post-merge-ledger.patch"
    export GH_MODE=ok
    run publish
    [ "$status" -eq 2 ]
    assert_nothing_published
}

@test "c133 v2: a re-approved candidate that is not in canonical form refuses" {
    generate
    printf '\n' >> "$CANDIDATE"
    reapprove
    export GH_MODE=ok
    run publish
    [ "$status" -eq 2 ]
    assert_nothing_published
}

@test "c133 v2: a ledger patch touching another path refuses" {
    generate
    patch="$PROJECT_ROOT/.run/post-merge-ledger.patch"
    printf 'diff --git a/app.txt b/app.txt\n--- a/app.txt\n+++ b/app.txt\n@@ -1 +1 @@\n-fixed\n+tampered\n' >> "$patch"
    jq --arg d "$(sha256sum "$patch" | cut -d' ' -f1)" '.ledger_patch_sha256 = $d' "$CANDIDATE" > "$CASE_DIR/c" && mv "$CASE_DIR/c" "$CANDIDATE"
    recanon "$CANDIDATE"
    reapprove
    export GH_MODE=ok
    run publish
    [ "$status" -eq 2 ]
    [[ "$output" == *"grimoires/loa/ledger.json"* ]]
    assert_nothing_published
}

@test "c133 v2: a ledger patch that is not the active to archived transition refuses" {
    generate
    ledger="$PROJECT_ROOT/grimoires/loa/ledger.json"
    cp "$ledger" "$CASE_DIR/ledger.keep"
    jq '.cycles[0].status = "archived" | .active_cycle = null | .cycles[0].sprints = []' "$CASE_DIR/ledger.keep" > "$ledger"
    patch="$PROJECT_ROOT/.run/post-merge-ledger.patch"
    git -C "$PROJECT_ROOT" diff "$SHA" -- grimoires/loa/ledger.json > "$patch"
    cp "$CASE_DIR/ledger.keep" "$ledger"
    jq --arg d "$(sha256sum "$patch" | cut -d' ' -f1)" '.ledger_patch_sha256 = $d' "$CANDIDATE" > "$CASE_DIR/c" && mv "$CASE_DIR/c" "$CANDIDATE"
    recanon "$CANDIDATE"
    reapprove
    export GH_MODE=ok
    run publish
    [ "$status" -eq 2 ]
    [[ "$output" == *"active"*"archived"* ]]
    assert_nothing_published
}

v1_candidate() {
    bash "$SCRIPT" --generate --pr 7 --type other --sha "$SHA" --downstream --skip-gt --skip-rtfm
    CANDIDATE="$PROJECT_ROOT/.run/post-merge-candidate.json"
    jq '{schema_version:1, pr_number, pr_type, merge_sha, target_commit, target_tree,
        remote_origin, remote_push_url, tag, prerelease, release_body,
        notification_body, prepared_state}' "$CANDIDATE" > "$CASE_DIR/v1"
    mv "$CASE_DIR/v1" "$CANDIDATE"
    reapprove
}

@test "c133 v2: a schema_version 1 candidate refuses with a regeneration instruction" {
    v1_candidate
    export GH_MODE=ok
    run publish
    [ "$status" -eq 2 ]
    [[ "$output" == *"--generate"* && "$output" == *"--allow-v1"* ]]
    assert_nothing_published
}

@test "c133 v2: --allow-v1 publishes a schema_version 1 candidate and logs the reason" {
    v1_candidate
    export GH_MODE=ok
    run publish --allow-v1 "operator accepts the legacy candidate for the test"
    [ "$status" -eq 0 ]
    [[ "$output" == *"operator accepts the legacy candidate for the test"* ]]
    jq -e '.allow_v1.reason == "operator accepts the legacy candidate for the test" and .state == "DONE"' "$PROJECT_ROOT/.run/post-merge-state.json"
    [ "$(remote_git rev-parse 'v1.0.1^{commit}')" = "$SHA" ]
}

@test "c133 v2: --allow-v1 requires a reason" {
    v1_candidate
    run publish --allow-v1 ""
    [ "$status" -eq 2 ]
    assert_nothing_published
}

@test "c133 v2: the stdlib canonical form equals lib/jcs.sh (rfc8785) on a generated candidate" {
    python3 -c 'import rfc8785' 2>/dev/null || skip "rfc8785 not installed"
    generate
    sed '$d' "$SCRIPT" > "$PROJECT_ROOT/.claude/scripts/source-orchestrator.sh"
    jq '. + {probe: {"\u00e9": "x", "\ud83d\ude00": "astral", "\uff61": "bmp-high", "e": "tab\tquote\"\u0001", n: -3}}' "$CANDIDATE" > "$CASE_DIR/probe.json"
    bash -c 'source "$1"; jcs_stdlib_file "$2"' _ "$PROJECT_ROOT/.claude/scripts/source-orchestrator.sh" "$CASE_DIR/probe.json" > "$CASE_DIR/stdlib"
    python3 "$ROOT/.claude/scripts/lib/jcs-helper.py" < "$CASE_DIR/probe.json" > "$CASE_DIR/rfc8785"
    cmp "$CASE_DIR/stdlib" "$CASE_DIR/rfc8785"
    # A value outside the exact domain is refused, never approximated.
    printf '{"x": 1.5}' > "$CASE_DIR/float.json"
    run bash -c 'source "$1"; jcs_stdlib_file "$2"' _ "$PROJECT_ROOT/.claude/scripts/source-orchestrator.sh" "$CASE_DIR/float.json"
    [ "$status" -ne 0 ]
}

# =============================================================================
# cycle-134 C-9 (bd-4pv1j; sdd.md D-3.2, D-3.2a, D-3.2b): the exit-code
# contract. Exit 2 is a refusal before any write: the tag identity checks
# (local and remote, lightweight tag = refusal, unreachable remote = identity
# unverified) run in validate_candidate_v2, before PUBLISHING. A tag that
# appears between validation and the push is a step failing after a write:
# exit 1, state FAILED. Candidate numbers are integers (no fraction, no
# exponent, |n| <= 2^53-1, no -0), enforced on the lexical tokens at
# --generate and at --publish, whether or not rfc8785 is installed.
# =============================================================================

# 'Pre-write' (Task 1.7): the state file, the progress file, the ledger patch,
# the local branches and tags and every ref of the bare remote are unchanged.
# The private observation refs under refs/loa/post-merge/ are excluded: the
# pre-write validation itself records what it read from the remote there.
prewrite_fingerprint() {
    local f
    for f in post-merge-state.json post-merge-progress.json post-merge-ledger.patch; do
        if [[ -f "$PROJECT_ROOT/.run/$f" ]]; then
            printf '%s %s\n' "$f" "$(sha256sum < "$PROJECT_ROOT/.run/$f" | cut -d' ' -f1)"
        else
            printf '%s absent\n' "$f"
        fi
    done
    git -C "$PROJECT_ROOT" for-each-ref --format='local %(refname) %(objectname)' refs/heads refs/tags
    remote_git for-each-ref --format='remote %(refname) %(objectname)'
}
snapshot_prewrite() { prewrite_fingerprint > "$CASE_DIR/prewrite.before"; }
assert_prewrite_unchanged() {
    prewrite_fingerprint > "$CASE_DIR/prewrite.after"
    diff "$CASE_DIR/prewrite.before" "$CASE_DIR/prewrite.after"
    [ ! -f "$PROJECT_ROOT/.run/post-merge-progress.json" ]
    jq -e '.state == "PREPARED"' "$PROJECT_ROOT/.run/post-merge-state.json"
    if [[ -f "$GH_LOG" ]]; then
        ! grep -q -- '--method POST' "$GH_LOG"
    fi
}

# The orchestrator without its trailing `main "$@"`, for sourcing a helper.
source_copy() {
    SOURCED="$PROJECT_ROOT/.claude/scripts/source-orchestrator.sh"
    sed '$d' "$SCRIPT" > "$SOURCED"
}

@test "c134 C-9: a local tag of another identity refuses with exit 2 before any write" {
    generate
    git -C "$PROJECT_ROOT" tag -a v1.0.1 v1.0.0 -m "Release v1.0.1"
    snapshot_prewrite
    export GH_MODE=ok
    run publish
    [ "$status" -eq 2 ]
    [[ "$output" == *"Local tag v1.0.1"*"another identity"* ]]
    assert_prewrite_unchanged
}

@test "c134 C-9: a lightweight local tag on the merge refuses with exit 2 before any write" {
    generate
    git -C "$PROJECT_ROOT" tag v1.0.1 "$SHA"
    snapshot_prewrite
    export GH_MODE=ok
    run publish
    [ "$status" -eq 2 ]
    [[ "$output" == *"Local tag v1.0.1"*"lightweight"* ]]
    assert_prewrite_unchanged
}

@test "c134 C-9: a remote tag of another identity refuses with exit 2 before any write" {
    generate
    git -C "$PROJECT_ROOT" tag -a v1.0.1 "$SHA" -m "Something else"
    git -C "$PROJECT_ROOT" push -q "$CASE_DIR/remote" refs/tags/v1.0.1
    git -C "$PROJECT_ROOT" tag -d v1.0.1 >/dev/null
    snapshot_prewrite
    export GH_MODE=ok
    run publish
    [ "$status" -eq 2 ]
    [[ "$output" == *"Remote tag v1.0.1"*"another identity"* ]]
    assert_prewrite_unchanged
}

@test "c134 C-9: a lightweight remote tag on the merge refuses with exit 2 before any write" {
    generate
    remote_git update-ref refs/tags/v1.0.1 "$SHA"
    snapshot_prewrite
    export GH_MODE=ok
    run publish
    [ "$status" -eq 2 ]
    [[ "$output" == *"Remote tag v1.0.1"*"another identity"* ]]
    assert_prewrite_unchanged
}

@test "c134 C-9: an unreachable remote refuses with exit 2: identity unverified" {
    git -C "$PROJECT_ROOT" remote set-url --push origin "$CASE_DIR/no-such-remote"
    generate
    [ "$(jq -r '.remote_push_url' "$CANDIDATE")" = "$CASE_DIR/no-such-remote" ]
    snapshot_prewrite
    export GH_MODE=ok
    run publish
    [ "$status" -eq 2 ]
    [[ "$output" == *"remote unreachable, identity unverified"* ]]
    # One refusal line.
    [ "$(grep -c '^ERROR: ' <<<"$output")" = 1 ]
    assert_prewrite_unchanged
}

@test "c134 C-9: a tag appearing between validation and the push exits 1 with the state FAILED" {
    generate
    other="$(git -C "$PROJECT_ROOT" rev-parse v1.0.0)"
    # The first fetch of the private observed-main ref happens after the
    # validation (the preflight ancestry check); the remote tag of another
    # identity appears exactly then.
    cat > "$PROJECT_ROOT/.git/hooks/reference-transaction" <<HOOK
#!/usr/bin/env bash
[[ "\$1" == committed && ! -f "$CASE_DIR/raced" ]] || exit 0
while read -r _old _new ref; do
    if [[ "\$ref" == refs/loa/post-merge/observed-main ]]; then
        touch "$CASE_DIR/raced"
        obj=\$(printf 'object %s\ntype commit\ntag v1.0.1\ntagger Racer <racer@example.invalid> 0 +0000\n\nRelease v1.0.1\n' "$other" |
            git --git-dir="$CASE_DIR/remote" mktag)
        git --git-dir="$CASE_DIR/remote" update-ref refs/tags/v1.0.1 "\$obj"
    fi
done
exit 0
HOOK
    chmod +x "$PROJECT_ROOT/.git/hooks/reference-transaction"
    export GH_MODE=ok
    run publish
    [ "$status" -eq 1 ]
    [ -f "$CASE_DIR/raced" ]
    [[ "$output" == *"appeared between validation and the push"* ]]
    jq -e '.state == "FAILED" and .phases.tag.status == "failed"' "$PROJECT_ROOT/.run/post-merge-state.json"
    [ "$(remote_git rev-parse 'refs/tags/v1.0.1^{commit}')" = "$other" ]
    [ "$(remote_git rev-parse refs/heads/main)" = "$SHA" ]
    ! grep -q -- '--method POST' "$GH_LOG"
}

@test "c134 C-9: a re-run with an identical-identity tag skips the push and continues" {
    generate
    export GH_MODE=fail
    run publish
    [ "$status" -eq 1 ]
    tag_object="$(remote_git rev-parse refs/tags/v1.0.1)"
    cat > "$PROJECT_ROOT/.git/hooks/pre-push" <<HOOK
#!/usr/bin/env bash
while read -r _lref _lsha rref _rsha; do printf '%s\n' "\$rref" >> "$CASE_DIR/pushed"; done
exit 0
HOOK
    chmod +x "$PROJECT_ROOT/.git/hooks/pre-push"
    export GH_MODE=ok
    run publish
    [ "$status" -eq 0 ]
    [[ "$output" == *"Existing remote v1.0.1 matches the candidate; not pushed again"* ]]
    ! grep -q '^refs/tags/' "$CASE_DIR/pushed"
    [ "$(remote_git rev-parse refs/tags/v1.0.1)" = "$tag_object" ]
    jq -e '.state == "DONE" and .phases.tag.result.verified' "$PROJECT_ROOT/.run/post-merge-state.json"
}

# --- integer domain -----------------------------------------------------------

# Plant a JSON number token, as text, into the semver phase result (nested),
# through a wrapper committed as the merge (so the checkout stays clean).
plant_number() {
    local dir="$PROJECT_ROOT/.claude/scripts"
    cp -p "$dir/semver-bump.sh" "$dir/semver-bump.real.sh"
    cat > "$dir/semver-bump.sh" <<SH
#!/usr/bin/env bash
out=\$("\$(dirname "\$0")/semver-bump.real.sh" "\$@") || exit \$?
printf '%s' "\$out" | python3 -I -c 'import sys; t = sys.stdin.read(); i = t.index("{"); sys.stdout.write(t[:i + 1] + "\"planted\": {\"deep\": [0, {\"x\": " + sys.argv[1] + "}]}, " + t[i + 1:])' '$1'
SH
    git -C "$PROJECT_ROOT" add "$dir"
    git -C "$PROJECT_ROOT" commit -qm "fix: plant a number"
    SHA="$(git -C "$PROJECT_ROOT" rev-parse HEAD)"
    git -C "$PROJECT_ROOT" push -q "$CASE_DIR/remote" "$SHA:refs/heads/main"
}

# A python3 on which `import rfc8785` fails (lib/jcs.sh then reports the
# package absent and the stdlib canonicaliser is used).
hide_rfc8785() {
    mkdir -p "$CASE_DIR/no-rfc8785"
    printf 'raise ImportError("rfc8785 hidden by the test")\n' > "$CASE_DIR/no-rfc8785/rfc8785.py"
    export PYTHONPATH="$CASE_DIR/no-rfc8785"
}

# --generate with the planted token refuses: exit 2, the JSON path, nothing
# written (no candidate, no ledger patch, state not PREPARED), in both modes.
# $2 is the token as the run state carries it when jq re-serialises it
# (jq 1.7 writes 1e3 as 1E+3 — still an exponent, still refused).
assert_generate_refuses() {
    local token="$1" reported="${2:-$1}" mode
    plant_number "$token"
    for mode in rfc8785 stdlib; do
        if [[ "$mode" == rfc8785 ]]; then
            python3 -c 'import rfc8785' 2>/dev/null || continue
        else
            hide_rfc8785
            ! python3 -c 'import rfc8785' 2>/dev/null
        fi
        git -C "$PROJECT_ROOT" reset -q --hard "$SHA"
        rm -f "$PROJECT_ROOT/.run/post-merge-state.json"
        run bash "$SCRIPT" --generate --pr 7 --type cycle --sha "$SHA" --downstream --skip-gt --skip-rtfm
        echo "mode=$mode token=$token status=$status" >&2
        [ "$status" -eq 2 ]
        [[ "$output" == *"Non-integer number ${reported} at .prepared_state.phases.semver.result.planted.deep[1].x"* ]]
        [ ! -f "$PROJECT_ROOT/.run/post-merge-candidate.json" ]
        [ ! -f "$PROJECT_ROOT/.run/post-merge-ledger.patch" ]
        ! jq -e '.state == "PREPARED"' "$PROJECT_ROOT/.run/post-merge-state.json"
        [ -z "$(remote_git tag)" ]
        [ "$(remote_git rev-parse refs/heads/main)" = "$SHA" ]
    done
    unset PYTHONPATH
}

@test "c134 C-9: --generate refuses a fraction (1.0) with exit 2 and the JSON path, with and without rfc8785" {
    assert_generate_refuses 1.0
}

@test "c134 C-9: --generate refuses an exponent form (1e3) with exit 2, with and without rfc8785" {
    assert_generate_refuses 1e3 "$(jq -nc --argjson n 1e3 '$n')"
}

@test "c134 C-9: --generate refuses -0 with exit 2, with and without rfc8785" {
    assert_generate_refuses -0
}

@test "c134 C-9: --generate refuses 2^53 (9007199254740992) with exit 2, with and without rfc8785" {
    assert_generate_refuses 9007199254740992
}

@test "c134 C-9: --generate refuses -2^53 (-9007199254740992) with exit 2, with and without rfc8785" {
    assert_generate_refuses -9007199254740992
}

@test "c134 C-9: --generate accepts 2^53-1 (9007199254740991) on both canonicalisers, byte-identical" {
    plant_number 9007199254740991
    run bash "$SCRIPT" --generate --pr 7 --type cycle --sha "$SHA" --downstream --skip-gt --skip-rtfm
    [ "$status" -eq 0 ]
    CANDIDATE="$PROJECT_ROOT/.run/post-merge-candidate.json"
    jq -e '.prepared_state.phases.semver.result.planted.deep[1].x == 9007199254740991' "$CANDIDATE"
    grep -q '"x":9007199254740991' "$CANDIDATE"
    source_copy
    bash -c 'source "$1"; jcs_stdlib_file "$2"' _ "$SOURCED" "$CANDIDATE" | cmp - "$CANDIDATE"
}

# Plant a number token as text into the generated candidate and re-approve
# it (the file is not re-canonicalised: a parser would normalise the token).
plant_in_candidate() {
    python3 -I -c 'import sys
p = sys.argv[1]
t = open(p, encoding="utf-8").read()
k = "\"prepared_state\":{"
assert t.count(k) == 1
open(p, "w", encoding="utf-8").write(t.replace(k, k + "\"planted\":" + sys.argv[2] + ","))' "$CANDIDATE" "$1"
    reapprove
}

@test "c134 C-9: --publish refuses a candidate carrying 1.0, -0, 2^53 or 1E+3 with exit 2 and the path, before any write" {
    local token
    generate
    cp "$CANDIDATE" "$CASE_DIR/candidate.clean"
    for token in 1.0 -0 9007199254740992 1E+3; do
        cp "$CASE_DIR/candidate.clean" "$CANDIDATE"
        plant_in_candidate "$token"
        snapshot_prewrite
        export GH_MODE=ok
        run publish
        echo "token=$token status=$status" >&2
        [ "$status" -eq 2 ]
        [[ "$output" == *"Non-integer number ${token} at .prepared_state.planted"* ]]
        assert_prewrite_unchanged
    done
}

@test "c134 C-9: the real rc.8 candidate passes the publish-time number scan (10 integers)" {
    fixture="$ROOT/tests/fixtures/post-merge/candidate-rc8.json"
    source_copy
    run bash -c 'source "$1"; number_domain_check "$2" ""' _ "$SOURCED" "$fixture"
    [ "$status" -eq 0 ]
    [ "$(python3 -I -c 'import json, sys
n = []
json.load(open(sys.argv[1]), parse_int=lambda t: n.append(t), parse_float=lambda t: n.append("float " + t))
print(len(n), all(not x.startswith("float") for x in n))' "$fixture")" = "10 True" ]
}

@test "c134 C-9: the integer domain canonicalises identically on the stdlib and rfc8785 paths (rc.8 candidate)" {
    python3 -c 'import rfc8785' 2>/dev/null || skip "rfc8785 not installed"
    fixture="$ROOT/tests/fixtures/post-merge/candidate-rc8.json"
    source_copy
    bash -c 'source "$1"; jcs_stdlib_file "$2"' _ "$SOURCED" "$fixture" > "$CASE_DIR/stdlib"
    python3 "$ROOT/.claude/scripts/lib/jcs-helper.py" < "$fixture" > "$CASE_DIR/rfc8785"
    cmp "$CASE_DIR/stdlib" "$CASE_DIR/rfc8785"
    cmp "$CASE_DIR/stdlib" "$fixture"
    printf '{"a":9007199254740991,"b":-9007199254740991,"c":0,"d":-3}' > "$CASE_DIR/bounds.json"
    bash -c 'source "$1"; jcs_stdlib_file "$2"' _ "$SOURCED" "$CASE_DIR/bounds.json" > "$CASE_DIR/b.stdlib"
    python3 "$ROOT/.claude/scripts/lib/jcs-helper.py" < "$CASE_DIR/bounds.json" | cmp - "$CASE_DIR/b.stdlib"
}
