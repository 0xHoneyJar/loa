#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# Unit tests for golden-path.sh C8 (cycle-119): structured-first gate
# consumption. _gp_sprint_is_reviewed / _gp_sprint_is_audited must:
#   - stay byte-identical in behavior for legacy files (no LOA-VERDICT trailer)
#   - use verdict-derive.sh's derived verdict when a trailer IS present

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"

    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_TMPDIR="$BATS_TMPDIR/golden-path-c8-test-$$"
    mkdir -p "$TEST_TMPDIR/.claude/scripts" "$TEST_TMPDIR/.run"
    mkdir -p "$TEST_TMPDIR/grimoires/loa/a2a/sprint-1"

    for f in bootstrap.sh golden-path.sh path-lib.sh compat-lib.sh verdict-derive.sh; do
        cp "$PROJECT_ROOT/.claude/scripts/$f" "$TEST_TMPDIR/.claude/scripts/"
    done
    chmod +x "$TEST_TMPDIR/.claude/scripts/verdict-derive.sh"

    # Initialize git repo for bootstrap's PROJECT_ROOT detection
    cd "$TEST_TMPDIR"
    git init -q
    git add -A 2>/dev/null || true
    git commit -q -m "init" --allow-empty

    export PROJECT_ROOT="$TEST_TMPDIR"
    SPRINT_DIR="$TEST_TMPDIR/grimoires/loa/a2a/sprint-1"
}

teardown() {
    cd /
    if [[ -d "$TEST_TMPDIR" ]]; then
        rm -rf "$TEST_TMPDIR"
    fi
}

skip_if_no_jq() {
    command -v jq &>/dev/null || skip "jq not installed"
}

# =============================================================================
# Legacy behavior (no trailer) — must stay byte-identical
# =============================================================================

@test "C8 legacy: reviewed=true when engineer-feedback.md says 'All good' (no trailer)" {
    cat > "$SPRINT_DIR/engineer-feedback.md" <<'EOF'
All good

No issues found.
EOF
    source "$TEST_TMPDIR/.claude/scripts/golden-path.sh"
    run _gp_sprint_is_reviewed sprint-1
    [ "$status" -eq 0 ]
}

@test "C8 legacy: reviewed=false when engineer-feedback.md has a Changes Required heading (no trailer)" {
    cat > "$SPRINT_DIR/engineer-feedback.md" <<'EOF'
## Changes Required

- fix the thing
EOF
    source "$TEST_TMPDIR/.claude/scripts/golden-path.sh"
    run _gp_sprint_is_reviewed sprint-1
    [ "$status" -eq 1 ]
}

@test "C8 legacy: reviewed=false when no engineer-feedback.md exists" {
    source "$TEST_TMPDIR/.claude/scripts/golden-path.sh"
    run _gp_sprint_is_reviewed sprint-1
    [ "$status" -eq 1 ]
}

@test "C8 legacy: audited=true when auditor-sprint-feedback.md contains APPROVED (no trailer)" {
    cat > "$SPRINT_DIR/auditor-sprint-feedback.md" <<'EOF'
APPROVED - LET'S FUCKING GO
EOF
    source "$TEST_TMPDIR/.claude/scripts/golden-path.sh"
    run _gp_sprint_is_audited sprint-1
    [ "$status" -eq 0 ]
}

@test "C8 legacy: audited=false when auditor-sprint-feedback.md lacks APPROVED (no trailer)" {
    cat > "$SPRINT_DIR/auditor-sprint-feedback.md" <<'EOF'
CHANGES_REQUIRED: fix the security bug.
EOF
    source "$TEST_TMPDIR/.claude/scripts/golden-path.sh"
    run _gp_sprint_is_audited sprint-1
    [ "$status" -eq 1 ]
}

@test "C8 legacy: an audited sprint is implicitly reviewed (no trailer)" {
    cat > "$SPRINT_DIR/auditor-sprint-feedback.md" <<'EOF'
APPROVED - LET'S FUCKING GO
EOF
    source "$TEST_TMPDIR/.claude/scripts/golden-path.sh"
    run _gp_sprint_is_reviewed sprint-1
    [ "$status" -eq 0 ]
}

# =============================================================================
# Structured-first behavior (LOA-VERDICT trailer present)
# =============================================================================

@test "C8 structured: reviewed=true when trailer verdict is APPROVED" {
    skip_if_no_jq
    cat > "$SPRINT_DIR/engineer-feedback.md" <<'EOF'
All good
<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->
EOF
    source "$TEST_TMPDIR/.claude/scripts/golden-path.sh"
    run _gp_sprint_is_reviewed sprint-1
    [ "$status" -eq 0 ]
}

@test "C8 structured: reviewed=false when trailer verdict is CHANGES_REQUIRED (even if prose looks fine)" {
    skip_if_no_jq
    # Deliberately no findings headings and no 'All good' — the trailer alone
    # must drive the decision once present (structured-first).
    cat > "$SPRINT_DIR/engineer-feedback.md" <<'EOF'
Some prose that would pass the legacy heuristic.
<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":0,"low":0},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->
EOF
    source "$TEST_TMPDIR/.claude/scripts/golden-path.sh"
    run _gp_sprint_is_reviewed sprint-1
    [ "$status" -eq 1 ]
}

@test "C8 structured: audited=true when trailer verdict is APPROVED" {
    skip_if_no_jq
    cat > "$SPRINT_DIR/auditor-sprint-feedback.md" <<'EOF'
APPROVED - LET'S FUCKING GO
<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->
EOF
    source "$TEST_TMPDIR/.claude/scripts/golden-path.sh"
    run _gp_sprint_is_audited sprint-1
    [ "$status" -eq 0 ]
}

@test "C8 structured: audited=false when trailer verdict is CHANGES_REQUIRED" {
    skip_if_no_jq
    cat > "$SPRINT_DIR/auditor-sprint-feedback.md" <<'EOF'
Some prose without the ritual string.
<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":1,"high":0,"medium":0,"low":0},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->
EOF
    source "$TEST_TMPDIR/.claude/scripts/golden-path.sh"
    run _gp_sprint_is_audited sprint-1
    [ "$status" -eq 1 ]
}

# =============================================================================
# FR-5 (cycle-124): consistency-gated. A present trailer must ALSO pass
# verdict-derive.sh (exit 0 AND .consistent == true) before its verdict
# counts — an APPROVED label on an inconsistent trailer denies (fail closed).
# =============================================================================

@test "FR-5 review: reviewed=false when an APPROVED trailer carries counts.critical=1 (one-way rule)" {
    skip_if_no_jq
    cat > "$SPRINT_DIR/engineer-feedback.md" <<'EOF'
All good
<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":1,"high":0,"medium":0,"low":0},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->
EOF
    source "$TEST_TMPDIR/.claude/scripts/golden-path.sh"
    run _gp_sprint_is_reviewed sprint-1
    [ "$status" -eq 1 ]
}

@test "FR-5 audit: audited=false when an APPROVED trailer carries counts.high=2 (one-way rule)" {
    skip_if_no_jq
    cat > "$SPRINT_DIR/auditor-sprint-feedback.md" <<'EOF'
APPROVED - LET'S FUCKING GO
<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":2,"medium":0,"low":0},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->
EOF
    source "$TEST_TMPDIR/.claude/scripts/golden-path.sh"
    run _gp_sprint_is_audited sprint-1
    [ "$status" -eq 1 ]
}

@test "FR-5 review: reviewed=false when the APPROVED trailer is not the last line" {
    skip_if_no_jq
    cat > "$SPRINT_DIR/engineer-feedback.md" <<'EOF'
All good
<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->
Trailing prose after the trailer.
EOF
    source "$TEST_TMPDIR/.claude/scripts/golden-path.sh"
    run _gp_sprint_is_reviewed sprint-1
    [ "$status" -eq 1 ]
}

@test "FR-5 audit: an inconsistent audit trailer does not implicitly mark the sprint reviewed" {
    skip_if_no_jq
    # No engineer-feedback.md at all — the ONLY route to reviewed=true is the
    # _gp_sprint_is_audited short-circuit, which must not fire on an
    # inconsistent audit trailer.
    cat > "$SPRINT_DIR/auditor-sprint-feedback.md" <<'EOF'
APPROVED - LET'S FUCKING GO
<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":2,"medium":0,"low":0},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->
EOF
    source "$TEST_TMPDIR/.claude/scripts/golden-path.sh"
    run _gp_sprint_is_reviewed sprint-1
    [ "$status" -eq 1 ]
}

@test "FR-5 fail-closed: verdict-derive.sh exit 2 with EMPTY stdout ⇒ reviewed=false" {
    skip_if_no_jq
    cat > "$SPRINT_DIR/engineer-feedback.md" <<'EOF'
All good
<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->
EOF
    # Stub: the usage-error shape (verdict-derive.sh exits 2 BEFORE emit_json).
    printf '#!/usr/bin/env bash\nexit 2\n' > "$TEST_TMPDIR/.claude/scripts/verdict-derive.sh"
    source "$TEST_TMPDIR/.claude/scripts/golden-path.sh"
    run _gp_sprint_is_reviewed sprint-1
    [ "$status" -eq 1 ]
}

@test "FR-5 fail-closed: verdict-derive.sh exit 2 with an APPROVED-looking stdout still ⇒ reviewed=false" {
    skip_if_no_jq
    cat > "$SPRINT_DIR/engineer-feedback.md" <<'EOF'
All good
<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->
EOF
    # Any rc != 0 denies — the .verdict field alone must never carry the gate.
    cat > "$TEST_TMPDIR/.claude/scripts/verdict-derive.sh" <<'EOF'
#!/usr/bin/env bash
echo '{"verdict":"APPROVED","consistent":true,"trailer_found":true}'
exit 2
EOF
    source "$TEST_TMPDIR/.claude/scripts/golden-path.sh"
    run _gp_sprint_is_reviewed sprint-1
    [ "$status" -eq 1 ]
}

@test "FR-5 legacy preserved: a file with NO trailer marker never reaches verdict-derive.sh (prose heuristic decides)" {
    # A poisoned verdict-derive.sh proves the helper is never consulted for
    # legacy files: if it were, the first case would deny.
    cat > "$TEST_TMPDIR/.claude/scripts/verdict-derive.sh" <<'EOF'
#!/usr/bin/env bash
echo '{"verdict":"CHANGES_REQUIRED","consistent":false,"trailer_found":true}'
exit 1
EOF
    source "$TEST_TMPDIR/.claude/scripts/golden-path.sh"

    echo "Looks great, no issues found." > "$SPRINT_DIR/engineer-feedback.md"
    run _gp_sprint_is_reviewed sprint-1
    [ "$status" -eq 0 ]

    printf '## Changes Required\n\n- fix the thing\n' > "$SPRINT_DIR/engineer-feedback.md"
    run _gp_sprint_is_reviewed sprint-1
    [ "$status" -eq 1 ]
}

@test "FR-5 diagnostic: the violation text reaches stderr (and nothing reaches stdout) on an inconsistent trailer" {
    skip_if_no_jq
    cat > "$SPRINT_DIR/engineer-feedback.md" <<'EOF'
All good
<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":1,"high":0,"medium":0,"low":0},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->
EOF
    source "$TEST_TMPDIR/.claude/scripts/golden-path.sh"
    run --separate-stderr _gp_sprint_is_reviewed sprint-1
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"golden-path: inconsistent LOA-VERDICT trailer in "*"engineer-feedback.md"* ]]
    [[ "$stderr" == *"counts.critical=1"* ]]
    [ -z "$output" ]
}

# --- Audit cross-check: a reviewer-demoted high (`excluded`, FR-8) must be
# --- confirmed by the auditor (`excluded_confirmed`); absent reads as 0.

@test "FR-5 audit cross-check: review excluded=1 without audit excluded_confirmed ⇒ audited=false" {
    skip_if_no_jq
    cat > "$SPRINT_DIR/engineer-feedback.md" <<'EOF'
All good

## Observations

- **HIGH** (speculative, confidence: low) `src/x.py:1` — might race under load

<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"excluded":1,"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->
EOF
    cat > "$SPRINT_DIR/auditor-sprint-feedback.md" <<'EOF'
APPROVED - LET'S FUCKING GO
<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->
EOF
    source "$TEST_TMPDIR/.claude/scripts/golden-path.sh"
    run --separate-stderr _gp_sprint_is_audited sprint-1
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"excluded=1"* ]]
    [[ "$stderr" == *"excluded_confirmed=0"* ]]
}

@test "FR-5 audit cross-check: audit excluded_confirmed=1 does not confirm review excluded=2 ⇒ audited=false" {
    skip_if_no_jq
    cat > "$SPRINT_DIR/engineer-feedback.md" <<'EOF'
All good

## Observations

- **HIGH** (speculative, confidence: low) `src/x.py:1` — might race under load
- **HIGH** (speculative, confidence: low) `src/y.py:9` — might leak a handle

<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"excluded":2,"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->
EOF
    cat > "$SPRINT_DIR/auditor-sprint-feedback.md" <<'EOF'
APPROVED - LET'S FUCKING GO
<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"excluded_confirmed":1,"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->
EOF
    source "$TEST_TMPDIR/.claude/scripts/golden-path.sh"
    run _gp_sprint_is_audited sprint-1
    [ "$status" -eq 1 ]
}

@test "FR-5 audit cross-check: audit excluded_confirmed=1 matching review excluded=1 ⇒ audited=true" {
    skip_if_no_jq
    cat > "$SPRINT_DIR/engineer-feedback.md" <<'EOF'
All good

## Observations

- **HIGH** (speculative, confidence: low) `src/x.py:1` — might race under load

<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"excluded":1,"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->
EOF
    cat > "$SPRINT_DIR/auditor-sprint-feedback.md" <<'EOF'
APPROVED - LET'S FUCKING GO
<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"excluded_confirmed":1,"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->
EOF
    source "$TEST_TMPDIR/.claude/scripts/golden-path.sh"
    run _gp_sprint_is_audited sprint-1
    [ "$status" -eq 0 ]
}

@test "FR-5 audit path validates the review trailer: audit APPROVED but review APPROVED with counts.critical=1 ⇒ audited=false" {
    skip_if_no_jq
    cat > "$SPRINT_DIR/engineer-feedback.md" <<'EOF'
All good
<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":1,"high":0,"medium":0,"low":0},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->
EOF
    cat > "$SPRINT_DIR/auditor-sprint-feedback.md" <<'EOF'
APPROVED - LET'S FUCKING GO
<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->
EOF
    source "$TEST_TMPDIR/.claude/scripts/golden-path.sh"
    run --separate-stderr _gp_sprint_is_audited sprint-1
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"engineer-feedback.md"* ]]
    # and the implicit review pass is denied with it
    run _gp_sprint_is_reviewed sprint-1
    [ "$status" -eq 1 ]
}

@test "FR-5 audit cross-check: a non-integer review excluded (1.0) denies instead of reading as 0" {
    skip_if_no_jq
    cat > "$SPRINT_DIR/engineer-feedback.md" <<'EOF'
All good
<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"excluded":1.0,"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->
EOF
    cat > "$SPRINT_DIR/auditor-sprint-feedback.md" <<'EOF'
APPROVED - LET'S FUCKING GO
<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->
EOF
    source "$TEST_TMPDIR/.claude/scripts/golden-path.sh"
    run --separate-stderr _gp_sprint_is_audited sprint-1
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"non-integer excluded"* ]]
}

@test "FR-5 audit cross-check: a non-integer audit excluded_confirmed (\"1\") never confirms review excluded=1" {
    skip_if_no_jq
    cat > "$SPRINT_DIR/engineer-feedback.md" <<'EOF'
All good

## Observations

- **HIGH** (speculative, confidence: low) `src/x.py:1` — might race under load

<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"excluded":1,"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->
EOF
    cat > "$SPRINT_DIR/auditor-sprint-feedback.md" <<'EOF'
APPROVED - LET'S FUCKING GO
<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"excluded_confirmed":"1","sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->
EOF
    source "$TEST_TMPDIR/.claude/scripts/golden-path.sh"
    run --separate-stderr _gp_sprint_is_audited sprint-1
    [ "$status" -eq 1 ]
    # verdict-derive.sh (FR-9) now rejects the string before golden-path's own
    # integer check runs; either refusal is the fail-closed outcome.
    [[ "$stderr" == *"excluded_confirmed=invalid"* || "$stderr" == *"excluded_confirmed must be a non-negative integer"* ]]
}

@test "slice-C HIGH: a TAB-marker CHANGES_REQUIRED audit trailer under 'NOT APPROVED' prose is neither audited nor reviewed (no fall-through to the prose heuristic)" {
    skip_if_no_jq
    cat > "$SPRINT_DIR/engineer-feedback.md" <<'EOF'
All good
<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->
EOF
    printf 'Status: NOT APPROVED - 2 HIGH findings\n<!-- LOA-VERDICT\t{"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":0,"low":0},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->\n' > "$SPRINT_DIR/auditor-sprint-feedback.md"
    source "$TEST_TMPDIR/.claude/scripts/golden-path.sh"
    run --separate-stderr _gp_sprint_is_audited sprint-1
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"malformed"* ]]
    # and the sprint is not implicitly reviewed via "already audited"
    rm -f "$SPRINT_DIR/engineer-feedback.md"
    run _gp_sprint_is_reviewed sprint-1
    [ "$status" -eq 1 ]
}

@test "slice-C HIGH: NBSP and U+2010 marker variants on a CHANGES_REQUIRED review trailer ⇒ reviewed=false" {
    skip_if_no_jq
    local nbsp=$' ' hyph=$'‐'
    for marker in "<!--${nbsp}LOA-VERDICT " "<!-- LOA${hyph}VERDICT "; do
        printf '%s%s{"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":3,"medium":0,"low":0},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->\n' "Looks fine overall." $'\n'"$marker" > "$SPRINT_DIR/engineer-feedback.md"
        source "$TEST_TMPDIR/.claude/scripts/golden-path.sh"
        run _gp_sprint_is_reviewed sprint-1
        [ "$status" -eq 1 ] || { echo "marker variant accepted: $marker" >&2; return 1; }
    done
}

@test "slice-C MEDIUM: excluded=2^64 (wraps to 0 in bash) is invalid, not 'no exclusions'" {
    skip_if_no_jq
    cat > "$SPRINT_DIR/engineer-feedback.md" <<'EOF'
All good
<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"excluded":18446744073709551616,"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->
EOF
    cat > "$SPRINT_DIR/auditor-sprint-feedback.md" <<'EOF'
APPROVED - LET'S FUCKING GO
<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->
EOF
    source "$TEST_TMPDIR/.claude/scripts/golden-path.sh"
    run --separate-stderr _gp_sprint_is_audited sprint-1
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"non-integer excluded"* || "$stderr" == *"excluded must be a non-negative integer"* ]]
}

# =============================================================================
# Doc-lock (AC-5.2): run-mode/SKILL.md and sprint-completion.md describe the
# gate in verdict-derive terms.
# =============================================================================

@test "FR-5 doc-lock: run-mode Issue-Hash Tracking hashes the derived verdict; grep -A 100 survives only as the labelled fallback" {
    local repo_root skill block
    repo_root="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    skill="$repo_root/.claude/skills/run-mode/SKILL.md"
    block="$(awk '/^### Issue Hash Tracking/{p=1; next} /^### /{p=0} p' "$skill")"

    [[ "$block" == *"verdict-derive.sh"* ]]
    [[ "$block" == *"jq -Sc '{verdict,counts}'"* ]]
    [[ "$block" == *'echo "none"'* ]]
    [[ "$block" == *"fallback"* ]]

    # The bare prose recipe appears exactly once in the whole file, and that
    # one occurrence is inside the Issue-Hash block, on the labelled fallback line.
    [ "$(grep -c 'grep -A 100 "## Findings' "$skill")" -eq 1 ]
    [ "$(printf '%s\n' "$block" | grep -c 'grep -A 100 "## Findings')" -eq 1 ]
    printf '%s\n' "$block" | grep 'grep -A 100 "## Findings' | grep -qi 'fallback'
}

@test "FR-5 doc-lock: run-mode main-loop steps 5 and 8 phrase 'has findings' in verdict-derive terms" {
    local repo_root skill loop
    repo_root="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    skill="$repo_root/.claude/skills/run-mode/SKILL.md"
    loop="$(awk '/^## Main Loop — Single Sprint/{p=1; next} /^## /{p=0} p' "$skill")"

    [[ -n "$loop" ]]
    ! printf '%s\n' "$loop" | grep -q "has findings"
    printf '%s\n' "$loop" | grep -E '^ +5\. ' | grep -q 'verdict-derive.sh'
    printf '%s\n' "$loop" | grep -E '^ +8\. ' | grep -q 'verdict-derive.sh'
    printf '%s\n' "$loop" | grep -qi 'inconsistent trailer'
}

@test "FR-5 doc-lock: sprint-completion.md names the trailer path and the fail-closed rule" {
    local repo_root proto
    repo_root="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    proto="$repo_root/.claude/protocols/sprint-completion.md"

    grep -q 'LOA-VERDICT' "$proto"
    grep -q 'verdict-derive.sh' "$proto"
    grep -qi 'fail.closed' "$proto"
}

# =============================================================================
# Late Sprint 2 review (slice B): detection is case-insensitive; the canon is
# byte-exact and pinned.
# =============================================================================

@test "late-S2 MEDIUM: a lowercase loa-verdict marker is a malformed trailer for verdict-derive.sh (exit 1), never a legacy file" {
    skip_if_no_jq
    printf 'NOT APPROVED\n<!-- loa-verdict {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":1,"high":0,"medium":0,"low":0},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->\n' > "$TEST_TMPDIR/lc.md"
    run "$TEST_TMPDIR/.claude/scripts/verdict-derive.sh" --file "$TEST_TMPDIR/lc.md" --gate audit
    [ "$status" -eq 1 ]
    [[ "$output" == *"malformed"* ]]
}

@test "late-S2 MEDIUM: golden-path does not let a lowercase CHANGES_REQUIRED audit marker fall through to the prose heuristic" {
    skip_if_no_jq
    printf 'NOT APPROVED\n<!-- loa-verdict {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":1,"high":0,"medium":0,"low":0},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->\n' > "$SPRINT_DIR/auditor-sprint-feedback.md"
    source "$TEST_TMPDIR/.claude/scripts/golden-path.sh"
    run _gp_sprint_is_audited sprint-1
    [ "$status" -eq 1 ]
    run _gp_sprint_is_reviewed sprint-1
    [ "$status" -eq 1 ]
}

@test "late-S2 LOW (pinned tightening): whitespace after --> or two spaces before the JSON is a malformed marker" {
    skip_if_no_jq
    printf 'All good\n<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} --> \n' > "$TEST_TMPDIR/ws.md"
    run "$TEST_TMPDIR/.claude/scripts/verdict-derive.sh" --file "$TEST_TMPDIR/ws.md" --gate review
    [ "$status" -eq 1 ]
    printf 'All good\n<!-- LOA-VERDICT  {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->\n' > "$TEST_TMPDIR/ws2.md"
    run "$TEST_TMPDIR/.claude/scripts/verdict-derive.sh" --file "$TEST_TMPDIR/ws2.md" --gate review
    [ "$status" -eq 1 ]
}
