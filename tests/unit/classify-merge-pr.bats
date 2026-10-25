#!/usr/bin/env bats
# =============================================================================
# classify-merge-pr.bats — Tests for classify-merge-pr.sh (Issue #668)
# =============================================================================
# sprint-bug-124. Validates the merge-context wrapper that resolves a
# commit subject (PRIMARY) and optionally enriches with gh-pr-view labels
# (SECONDARY), then dispatches to the shared classify-pr-type.sh rules
# engine. The bug being fixed: when `gh pr view` returns empty title/labels
# in the GitHub Actions runner, the inline workflow classifier falls
# through to "other" — silently bypassing the full post-merge pipeline.

bats_require_minimum_version 1.5.0

setup() {
    export PROJECT_ROOT="$BATS_TEST_DIRNAME/../.."
    export WRAPPER="$PROJECT_ROOT/.claude/scripts/classify-merge-pr.sh"

    # Hermetic temp workdir for $GITHUB_OUTPUT and stub bins
    export TMPDIR_TEST="$(mktemp -d)"
    export STUB_BIN="${TMPDIR_TEST}/bin"
    mkdir -p "$STUB_BIN"
    export PATH="${STUB_BIN}:${PATH}"
    export GITHUB_OUTPUT="${TMPDIR_TEST}/github_output"
    : >"$GITHUB_OUTPUT"
}

teardown() {
    if [[ -n "${TMPDIR_TEST:-}" && -d "$TMPDIR_TEST" ]]; then
        rm -rf "$TMPDIR_TEST"
    fi
}

# Helper: install a `gh` stub that prints the given JSON for `pr view`
_stub_gh_json() {
    local json="$1"
    cat >"${STUB_BIN}/gh" <<STUB
#!/usr/bin/env bash
# stub gh — prints fixture JSON for 'pr view --json title,labels'
if [[ "\$1" == "pr" && "\$2" == "view" ]]; then
  printf '%s' '${json}'
  exit 0
fi
exit 0
STUB
    chmod +x "${STUB_BIN}/gh"
}

# Helper: install a `gh` stub that fails with stderr message (simulates the bug)
_stub_gh_fail() {
    local stderr_msg="${1:-error: pr not found}"
    cat >"${STUB_BIN}/gh" <<STUB
#!/usr/bin/env bash
# stub gh — fails for 'pr view'
if [[ "\$1" == "pr" && "\$2" == "view" ]]; then
  echo "${stderr_msg}" >&2
  exit 1
fi
exit 0
STUB
    chmod +x "${STUB_BIN}/gh"
}

# Helper: install a `gh` stub that returns empty JSON (simulates GH Actions runner mode)
_stub_gh_empty() {
    cat >"${STUB_BIN}/gh" <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == "pr" && "$2" == "view" ]]; then
  printf '%s' '{"title": "", "labels": []}'
  exit 0
fi
exit 0
STUB
    chmod +x "${STUB_BIN}/gh"
}

# =========================================================================
# CMP-T1..T6: PRIMARY classifier (merge subject) — the #668 defect class
# =========================================================================

@test "CMP-T1: feat(cycle-097) subject classifies as cycle when gh returns empty" {
    _stub_gh_empty
    run "$WRAPPER" --merge-msg "feat(cycle-097): quick wins (#666)" --pr-number 666
    [ "$status" -eq 0 ]
    [[ "$output" == *"pr_type=cycle"* ]]
}

@test "CMP-T2: feat(cycle-XYZ) subject + working gh with empty labels → cycle" {
    _stub_gh_json '{"title": "feat(cycle-097): quick wins", "labels": []}'
    run "$WRAPPER" --merge-msg "feat(cycle-097): quick wins (#666)" --pr-number 666
    [ "$status" -eq 0 ]
    [[ "$output" == *"pr_type=cycle"* ]]
}

@test "CMP-T3: fix(cycle-XYZ) subject → cycle" {
    _stub_gh_empty
    run "$WRAPPER" --merge-msg "fix(cycle-097): correct adapter routing (#665)" --pr-number 665
    [ "$status" -eq 0 ]
    [[ "$output" == *"pr_type=cycle"* ]]
}

@test "CMP-T4: feat(sprint-N) subject → cycle" {
    _stub_gh_empty
    run "$WRAPPER" --merge-msg "feat(sprint-3): task batch (#234)" --pr-number 234
    [ "$status" -eq 0 ]
    [[ "$output" == *"pr_type=cycle"* ]]
}

@test "CMP-T5: bare fix subject → bugfix" {
    _stub_gh_empty
    run "$WRAPPER" --merge-msg "fix: typo in README (#100)" --pr-number 100
    [ "$status" -eq 0 ]
    [[ "$output" == *"pr_type=bugfix"* ]]
}

@test "CMP-T6: chore subject → other" {
    _stub_gh_empty
    run "$WRAPPER" --merge-msg "chore: bump dep version (#101)" --pr-number 101
    [ "$status" -eq 0 ]
    [[ "$output" == *"pr_type=other"* ]]
}

# =========================================================================
# CMP-T7..T8: gh failure modes — must NOT silently degrade
# =========================================================================

@test "CMP-T7: gh fails loud, but cycle subject still produces cycle" {
    _stub_gh_fail "error: API rate limit exceeded"
    run "$WRAPPER" --merge-msg "feat(cycle-097): quick wins (#666)" --pr-number 666
    [ "$status" -eq 0 ]
    [[ "$output" == *"pr_type=cycle"* ]]
    # Bridgebuilder F003 (PR #670): require the wrapper-emitted prefix
    # specifically. The previous disjunction matched the stub's stderr
    # ('error: API rate limit exceeded') passing the test even if the
    # wrapper silently swallowed gh stderr. The strict prefix asserts the
    # wrapper actively emitted the WARN line.
    [[ "$output" == *"[classify-merge-pr] WARN: gh pr view failed"* ]]
}

@test "CMP-T8: gh fails for chore subject — still classifies as other (not silent crash)" {
    _stub_gh_fail "error: PR not found"
    run "$WRAPPER" --merge-msg "chore: bump dep (#101)" --pr-number 101
    [ "$status" -eq 0 ]
    [[ "$output" == *"pr_type=other"* ]]
}

# =========================================================================
# CMP-T9: SECONDARY enrichment — labels override subject when applicable
# =========================================================================

@test "CMP-T9: cycle label overrides chore subject → cycle" {
    _stub_gh_json '{"title": "chore: bump dep", "labels": [{"name": "cycle"}]}'
    run "$WRAPPER" --merge-msg "chore: bump dep (#101)" --pr-number 101
    [ "$status" -eq 0 ]
    [[ "$output" == *"pr_type=cycle"* ]]
}

# =========================================================================
# CMP-T10: $GITHUB_OUTPUT integration
# =========================================================================

@test "CMP-T10: writes pr_type to GITHUB_OUTPUT when set" {
    _stub_gh_empty
    run "$WRAPPER" --merge-msg "feat(cycle-097): quick wins (#666)" --pr-number 666
    [ "$status" -eq 0 ]
    grep -q '^pr_type=cycle$' "$GITHUB_OUTPUT"
    grep -q '^pr_number=666$' "$GITHUB_OUTPUT"
}

# =========================================================================
# CMP-T11: empty merge-msg with no PR number → other (graceful, not crash)
# =========================================================================

@test "CMP-T11: empty merge-msg with no pr-number → other" {
    _stub_gh_empty
    run "$WRAPPER" --merge-msg ""
    [ "$status" -eq 0 ]
    [[ "$output" == *"pr_type=other"* ]]
}

# =========================================================================
# CMP-T12: argument validation
# =========================================================================

@test "CMP-T12: missing required args → exit 2" {
    run "$WRAPPER"
    [ "$status" -eq 2 ]
}

@test "CMP-T13: --merge-sha resolves subject from git log when in repo" {
    # This test runs against the real repo (no stub), uses HEAD's actual subject.
    # Just validates the --merge-sha branch doesn't crash.
    _stub_gh_empty
    cd "$PROJECT_ROOT"
    run "$WRAPPER" --merge-sha "HEAD"
    [ "$status" -eq 0 ]
    [[ "$output" == *"pr_type="* ]]
}

# =========================================================================
# R-005 (bd-m1o6, agent-ergonomics pass 1): release merges are cycle-type.
# Live incident 2026-07-10: PR #1201 (release/v1.196.0-mechanical-floor)
# carried only fix/chore commits, classified non-cycle → simple-release
# path auto-tagged a PATCH (v1.195.1) on the named-release commit,
# requiring a manual delete+retag to v1.196.0.
# =========================================================================

@test "R-005: release/* branch-merge subject (the #1201 incident) → cycle" {
    _stub_gh_empty
    run "$WRAPPER" --merge-msg "Merge pull request #1201 from 0xHoneyJar/release/v1.196.0-mechanical-floor"
    [ "$status" -eq 0 ]
    [[ "$output" == *"pr_type=cycle"* ]]
}

@test "R-005: conventional release(...) subject → cycle" {
    _stub_gh_empty
    # KF-063 (cycle-134): a subject without a PR number is a push, not a
    # merge, and classifies `other`; the squash-merged form of this subject
    # carries GitHub's `(#NNN)` trailer, which is what the rule is about.
    run "$WRAPPER" --merge-msg "release(v2.0.0): big milestone (#1300)"
    [ "$status" -eq 0 ]
    [[ "$output" == *"pr_type=cycle"* ]]
}

@test "R-005: 'released-*' branch name does NOT false-positive" {
    _stub_gh_empty
    run "$WRAPPER" --merge-msg "Merge pull request #7 from acme/released-features-audit"
    [ "$status" -eq 0 ]
    [[ "$output" == *"pr_type=other"* ]]
}

@test "R-005: fix/* branch merge keeps pre-change classification (other)" {
    _stub_gh_empty
    run "$WRAPPER" --merge-msg "Merge pull request #900 from 0xHoneyJar/fix/some-bug"
    [ "$status" -eq 0 ]
    [[ "$output" == *"pr_type=other"* ]]
}

# =========================================================================
# KF-063 (bd-hyx0n, cycle-134 Task 1.6; sdd.md C-8, D-3.1, D-3.2b): a push
# to main that is not a PR merge. The PR number comes only from GitHub's
# own subject forms — the squash trailer `(#NNN)` at the end of the subject,
# or the merge-commit prefix `Merge pull request #NNN` — validated as a
# positive decimal; with no number the outcome is `other` (neither
# post-merge job runs). Run 40112013975 classified the publisher's ledger
# push (`chore(ledger): archive … after merge`) as cycle with an empty PR
# number and --generate aborted on `--pr is required`.
# =========================================================================

@test "KF063-T1: ledger fast-forward subject → other, empty pr_number, stderr note" {
    _stub_gh_empty
    run --separate-stderr "$WRAPPER" --merge-msg "chore(ledger): archive cycle-133-follow-through after merge"
    [ "$status" -eq 0 ]
    [[ "$output" == *"pr_type=other"* ]]
    grep -qx 'pr_number=' <<<"$output"
    [[ "$stderr" == *"[classify-merge-pr] no associated PR: a push, not a merge"* ]]
    grep -qx 'pr_type=other' "$GITHUB_OUTPUT"
    grep -qx 'pr_number=' "$GITHUB_OUTPUT"
}

@test "KF063-T2: cycle subject without a trailer → other (not cycle)" {
    _stub_gh_empty
    run --separate-stderr "$WRAPPER" --merge-msg "feat(cycle-134): post-ship fixes"
    [ "$status" -eq 0 ]
    [[ "$output" == *"pr_type=other"* ]]
    grep -qx 'pr_number=' <<<"$output"
    [[ "$stderr" == *"no associated PR: a push, not a merge"* ]]
}

@test "KF063-T3: only the trailing (#NNN) counts — 'closes #12 (#345)' → 345" {
    _stub_gh_empty
    run "$WRAPPER" --merge-msg "fix: guard the parser, closes #12 (#345)"
    [ "$status" -eq 0 ]
    [[ "$output" == *"pr_type=bugfix"* ]]
    grep -qx 'pr_number=345' <<<"$output"
}

@test "KF063-T4: an issue reference without the trailer yields no number" {
    _stub_gh_empty
    run "$WRAPPER" --merge-msg "feat(cycle-134): closes #12"
    [ "$status" -eq 0 ]
    [[ "$output" == *"pr_type=other"* ]]
    grep -qx 'pr_number=' <<<"$output"
}

@test "KF063-T5: (#0) is not a PR number → empty → other" {
    _stub_gh_empty
    run "$WRAPPER" --merge-msg "feat(cycle-134): something (#0)"
    [ "$status" -eq 0 ]
    [[ "$output" == *"pr_type=other"* ]]
    grep -qx 'pr_number=' <<<"$output"
}

@test "KF063-T6: (#12a) is not a PR number → empty → other" {
    _stub_gh_empty
    run "$WRAPPER" --merge-msg "feat(cycle-134): something (#12a)"
    [ "$status" -eq 0 ]
    [[ "$output" == *"pr_type=other"* ]]
    grep -qx 'pr_number=' <<<"$output"
}

@test "KF063-T7: a leading zero is not a positive decimal → (#012) empty → other" {
    _stub_gh_empty
    run "$WRAPPER" --merge-msg "feat(cycle-134): something (#012)"
    [ "$status" -eq 0 ]
    [[ "$output" == *"pr_type=other"* ]]
    grep -qx 'pr_number=' <<<"$output"
}

@test "KF063-T8: trailing whitespace after the trailer is tolerated" {
    _stub_gh_empty
    run "$WRAPPER" --merge-msg "feat(cycle-134): post-ship fixes (#1295)   "
    [ "$status" -eq 0 ]
    [[ "$output" == *"pr_type=cycle"* ]]
    grep -qx 'pr_number=1295' <<<"$output"
}

@test "KF063-T9: an explicit --pr-number is honoured with a cycle subject" {
    _stub_gh_empty
    run "$WRAPPER" --merge-msg "feat(cycle-134): post-ship fixes" --pr-number 7
    [ "$status" -eq 0 ]
    [[ "$output" == *"pr_type=cycle"* ]]
    grep -qx 'pr_number=7' <<<"$output"
}

@test "KF063-T10: gh failure on a subject with the trailer keeps the subject classification and the number" {
    _stub_gh_fail "error: HTTP 502"
    run --separate-stderr "$WRAPPER" --merge-msg "feat(cycle-134): post-ship fixes (#1295)"
    [ "$status" -eq 0 ]
    [[ "$output" == *"pr_type=cycle"* ]]
    grep -qx 'pr_number=1295' <<<"$output"
    [[ "$stderr" == *"[classify-merge-pr] WARN: gh pr view failed for PR #1295"* ]]
    [[ "$stderr" != *"no associated PR"* ]]
}

@test "KF063-T11: GitHub's merge-commit subject keeps its number (the form this repository merges with)" {
    _stub_gh_empty
    run "$WRAPPER" --merge-msg "Merge pull request #1294 from 0xHoneyJar/chore/kf-063-post-merge-ledger-push — KF-063"
    [ "$status" -eq 0 ]
    grep -qx 'pr_number=1294' <<<"$output"
    run "$WRAPPER" --merge-msg "Merge pull request #1274: cycle-126 — Full size"
    [ "$status" -eq 0 ]
    grep -qx 'pr_number=1274' <<<"$output"
}

@test "KF063-T12: a merge-commit subject with #0 or a non-decimal number yields no number" {
    _stub_gh_empty
    run "$WRAPPER" --merge-msg "Merge pull request #0 from acme/release/v1.0.0"
    [ "$status" -eq 0 ]
    [[ "$output" == *"pr_type=other"* ]]
    grep -qx 'pr_number=' <<<"$output"
    run "$WRAPPER" --merge-msg "Merge pull request #12a from acme/release/v1.0.0"
    [ "$status" -eq 0 ]
    [[ "$output" == *"pr_type=other"* ]]
    grep -qx 'pr_number=' <<<"$output"
}

@test "KF063-T13: --merge-sha on the ledger fast-forward commit → other" {
    _stub_gh_empty
    repo="${TMPDIR_TEST}/repo"
    git init -q "$repo"
    git -C "$repo" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty \
        -m "chore(ledger): archive cycle-133-follow-through after merge"
    cd "$repo"
    run --separate-stderr "$WRAPPER" --merge-sha HEAD
    [ "$status" -eq 0 ]
    [[ "$output" == *"pr_type=other"* ]]
    grep -qx 'pr_number=' <<<"$output"
    [[ "$stderr" == *"no associated PR: a push, not a merge"* ]]
}

@test "KF063-T14: a squash message with a body after the (#NNN) subject still yields the number (first line only; Bridgebuilder round 2 on PR #1296)" {
    _stub_gh_empty
    run --separate-stderr "$WRAPPER" --merge-msg $'feat(cycle-200): the thing (#1297)\n\n* commit one\n* commit two closes #12'
    [ "$status" -eq 0 ]
    [[ "$output" == *"pr_number=1297"* ]]
    [[ "$output" == *"pr_type=cycle"* ]]
}
