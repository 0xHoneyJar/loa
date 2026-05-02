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
    # gh failure must surface in stderr — do not silently swallow
    [[ "$output" == *"WARN"* ]] || [[ "$output" == *"error"* ]] || [[ "$output" == *"API rate"* ]]
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
